/**
 * Interop — ponte de integração entre as DUAS sessões paralelas do repo:
 *
 *   arena/d917b13b (PR #1, Node/TS)  ·  ActionEnvelope
 *   arena/ed79bd77 (PR #2, Python)   ·  contrato {id, gate, status:"0"|"1"|"2",
 *                                          codigo_saida, mensagem, continuidade,
 *                                          next_issue, direcao, proximo_passo,
 *                                          anexos, dados, timestamp, versao}
 *
 * Ambos os contratos são semanticamente equivalentes (id · mensagem · anexos ·
 * estado · próxima issue · código 0/1/2 · continuidade · direção). Este módulo:
 *   - converte envelopes nos dois sentidos (fromCnjEnvelope / toCnjEnvelope)
 *   - mescla os backlogs/cadeias das duas sessões num REGISTRO unificado
 *     (`pipeline/registry.json`), para que ambas sigam o mesmo fluxo gate-driven.
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import {
  makeEnvelope,
  type ActionEnvelope,
  type Addendum,
  type Direction,
  type ExitCode,
} from "./envelope.ts";
import type { Blueprint } from "./chain.ts";

// ------------------------------------------------------- contrato da sessão CNJ

export interface CnjAnexo {
  path: string;
  filename: string;
  descricao: string;
}

export interface CnjEnvelope {
  id: string;
  gate: string;
  status: string; // "0" | "1" | "2"
  codigo_saida: number;
  mensagem: string;
  continuidade: boolean;
  next_issue: string | null;
  direcao: string; // continuar|corrigir|depurar|proxima|encerrar|humano
  proximo_passo: string;
  anexos: CnjAnexo[];
  dados: Record<string, unknown>;
  timestamp: string;
  versao: string;
}

export interface CnjIssue {
  id: string;
  indice: number;
  titulo: string;
  entregavel: string;
  instrucao_teste: string;
  instrucao_desenvolvimento: string;
  status: string; // pendente|concluida|completada|bloqueada|cancelada
  depende_de: string[];
  origem: string;
  criada_em: string;
  concluida_em: string | null;
  evidencias: string[];
}

export interface CnjBacklog {
  nome: string;
  gerado_por: string;
  gerado_em: string;
  issues: CnjIssue[];
}

// -------------------------------------------------------------- vocabulários

/** direction (nosso) -> direcao (CNJ) */
export const DIRECTION_TO_CNJ: Record<Direction, string> = {
  continue: "proxima",
  fix: "corrigir",
  debt: "depurar",
  complete: "encerrar",
  hold: "humano",
};

/** direcao (CNJ) -> direction (nosso) */
export const DIRECTION_FROM_CNJ: Record<string, Direction> = {
  proxima: "continue",
  continuar: "continue",
  corrigir: "fix",
  depurar: "debt",
  encerrar: "complete",
  humano: "hold",
};

function statusFromCnjCode(code: string): string {
  if (code === "0") return "success";
  if (code === "1") return "continuity";
  return "human-required";
}

// ------------------------------------------------------------- conversões

/** Converte o envelope da sessão CNJ no nosso ActionEnvelope. */
export function fromCnjEnvelope(cnj: CnjEnvelope): ActionEnvelope {
  const addenda: Addendum[] = (cnj.anexos ?? []).map((anexo) => ({
    kind: anexo.filename !== "" ? ("filename" as const) : ("path" as const),
    ref: anexo.path !== "" ? anexo.path : anexo.filename,
    description: anexo.descricao,
  }));
  const exitCode = (Number(cnj.codigo_saida) === 0 ? 0 : Number(cnj.codigo_saida) === 1 ? 1 : 2) as ExitCode;
  return makeEnvelope({
    id: cnj.id,
    message: cnj.mensagem,
    addenda,
    status: statusFromCnjCode(cnj.status),
    nextIssue: cnj.next_issue,
    exitCode,
    direction: DIRECTION_FROM_CNJ[cnj.direcao] ?? "hold",
    at: cnj.timestamp,
    continuity: {
      required: Boolean(cnj.continuidade),
      reason: cnj.continuidade ? cnj.mensagem : "",
    },
  });
}

/** Converte o nosso ActionEnvelope no contrato da sessão CNJ. */
export function toCnjEnvelope(
  env: ActionEnvelope,
  options: { gate?: string; dados?: Record<string, unknown>; proximoPasso?: string } = {},
): CnjEnvelope {
  return {
    id: env.id,
    gate: options.gate ?? env.status,
    status: String(env.exitCode),
    codigo_saida: env.exitCode,
    mensagem: env.message,
    continuidade: env.continuity.required,
    next_issue: env.nextIssue,
    direcao: DIRECTION_TO_CNJ[env.direction] ?? "humano",
    proximo_passo: options.proximoPasso ?? "",
    anexos: env.addenda.map((a) => ({
      path: a.ref,
      filename: a.ref.split("/").pop() ?? a.ref,
      descricao: a.description,
    })),
    dados: options.dados ?? {},
    timestamp: env.at,
    versao: "1.0.0",
  };
}

// ------------------------------------------------- registro unificado (ambas)

export interface RegistryEntry {
  /** id canônico no registro: <sufixo-da-sessão>:<id-original> */
  id: string;
  source: string; // "arena/d917b13b" | "arena/ed79bd77"
  pr: number | null;
  originalId: string;
  index: number;
  title: string;
  deliverable: string;
  testInstruction: string;
  devInstruction: string;
  status: string;
  dependsOn: string[];
  next: string | null;
}

export interface Registry {
  version: number;
  generatedAt: string;
  sessions: { source: string; branch: string; pr: number | null; pending: number }[];
  entries: RegistryEntry[];
}

function suffixOf(source: string): string {
  return source.replace(/^arena\//, "").split("-")[0] ?? source;
}

/** Mescla a nossa cadeia (blueprint) com o backlog CNJ num registro único. */
export function mergeRegistry(
  ours: Blueprint,
  theirs: CnjBacklog,
  meta: {
    ourBranch: string;
    ourPr: number | null;
    theirBranch: string;
    theirPr: number | null;
    now?: () => Date;
  },
): Registry {
  const now = meta.now ?? (() => new Date());
  const entries: RegistryEntry[] = [];

  const ourSuffix = suffixOf(meta.ourBranch);
  ours.chain.forEach((step, i) => {
    entries.push({
      id: `${ourSuffix}:${step.id}`,
      source: meta.ourBranch,
      pr: meta.ourPr,
      originalId: step.id,
      index: i + 1,
      title: step.title,
      deliverable: "",
      testInstruction: step.acceptance,
      devInstruction: step.instruction,
      status: "pendente",
      dependsOn: [],
      next: step.next === null ? null : `${ourSuffix}:${step.next}`,
    });
  });

  const theirSuffix = suffixOf(meta.theirBranch);
  for (const issue of theirs.issues ?? []) {
    entries.push({
      id: `${theirSuffix}:${issue.id}`,
      source: meta.theirBranch,
      pr: meta.theirPr,
      originalId: issue.id,
      index: issue.indice,
      title: issue.titulo,
      deliverable: issue.entregavel,
      testInstruction: issue.instrucao_teste,
      devInstruction: issue.instrucao_desenvolvimento,
      status: issue.status,
      dependsOn: (issue.depende_de ?? []).map((dep) => `${theirSuffix}:${dep}`),
      next: null,
    });
  }

  const pending = (source: string): number =>
    entries.filter((e) => e.source === source && e.status === "pendente").length;

  return {
    version: 1,
    generatedAt: now().toISOString(),
    sessions: [
      { source: meta.ourBranch, branch: meta.ourBranch, pr: meta.ourPr, pending: pending(meta.ourBranch) },
      { source: meta.theirBranch, branch: meta.theirBranch, pr: meta.theirPr, pending: pending(meta.theirBranch) },
    ],
    entries,
  };
}

export function loadCnjBacklog(path: string): CnjBacklog {
  if (!existsSync(path)) {
    throw new Error(`backlog CNJ não encontrado: ${path}`);
  }
  return JSON.parse(readFileSync(path, "utf8")) as CnjBacklog;
}

export function writeRegistry(registry: Registry, path: string): void {
  writeFileSync(path, `${JSON.stringify(registry, null, 2)}\n`, "utf8");
}
