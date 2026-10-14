/**
 * Guardião de Projeto — continuidade automática do ESCOPO GLOBAL.
 *
 * Varre, num só retrato (EscopoGlobal):
 *   · memória IGC (WAL/CHECKPOINT/registry/profile — M4/D3, G5, G6)
 *   · débitos abertos (.session/DEBT.md — fluxo de débito com prioridade)
 *   · cadeia TS (pipeline/blueprint.json × pipeline/chain-state.json)
 *   · backlog CNJ (pipeline/backlog.json — fábrica)
 *
 * E decide UMA próxima ação por ciclo (Decisao), com `motivo` sempre explícito
 * (M6: nada é pulado/decidido em silêncio) e `comando` de retorno para fix.
 * Prioridade: débito urgente/alta → memória RECON → item bloqueado → próxima
 * issue da cadeia → fábrica CNJ → órfãos de linhagem → vigiar.
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  bootCheck,
  parseRegistry,
  readCheckpoint,
  resumeCheck,
  scanOrphans,
  parseWal,
} from "../session/igc.ts";

export interface ItemDebito {
  id: string;
  titulo: string;
  prioridade: string;
  acao: string; // "corrigir" | "humano" | ...
}

export interface ItemCadeia {
  id: string;
  title: string;
  estado: string; // "delivered" | "pending" | "chain-complete"
  acceptance: string;
}

export interface ItemCnj {
  id: string;
  titulo: string;
  status: string;
}

export interface EscopoGlobal {
  igc: {
    resumeOk: boolean;
    recon: string[];
    profileOk: boolean;
    profileFaltas: string[];
    orfaos: string[];
    walEntradas: number;
  };
  debitos: ItemDebito[];
  cadeia: ItemCadeia[];
  cnj: ItemCnj[];
}

export type AcaoGuardiao =
  | "fix"
  | "humano"
  | "executar-cadeia"
  | "fabrica"
  | "vigiar";

export interface Decisao {
  acao: AcaoGuardiao;
  alvo?: string;
  motivo: string;
  comando?: string;
  prioridade: "urgente" | "alta" | "media" | "baixa";
}

const RAIZ_PADRAO = ".";

function lerArquivo(raiz: string, rel: string): string | undefined {
  const p = join(raiz, rel);
  return existsSync(p) ? readFileSync(p, "utf8") : undefined;
}

/** Débitos vivos de .session/DEBT.md — cabeçalhos `## Dn …`/`## M1 …` com Prioridade/ação. */
export function parseDebitos(texto: string): ItemDebito[] {
  const itens: ItemDebito[] = [];
  const blocos = texto.split(/^## /m).slice(1);
  for (const bloco of blocos) {
    const cabecalho = bloco.split("\n")[0] ?? "";
    const id = /^([DM][\w.]*)\b/.exec(cabecalho.trim())?.[1];
    if (id === undefined) continue;
    const prioridade = /\*\*Prioridade:\*\*\s*([\wÀ-ú]+)/i.exec(bloco)?.[1] ?? "media";
    const acao = /\*\*Gatilho[^*]*\*\*:?/i.test(bloco) ? "corrigir" : "humano";
    itens.push({ id, titulo: cabecalho.trim(), prioridade: prioridade.toLowerCase(), acao });
  }
  return itens;
}

export function scanGlobal(raiz: string = RAIZ_PADRAO): EscopoGlobal {
  // — IGC (M4/D3/G5/G6)
  const walText = lerArquivo(raiz, ".session/WAL.md") ?? "";
  const cpPath = join(raiz, ".session/CHECKPOINT");
  const recon: string[] = [];
  let resumeOk = true;
  let walEntradas = 0;
  try {
    walEntradas = parseWal(walText).length;
    const cp = readCheckpoint(cpPath);
    const regText = lerArquivo(raiz, ".igc-registry.yml");
    const registryRef = regText !== undefined
      ? Object.values(parseRegistry(regText).linhagens).find((l) => l.ativa === true)?.checkpoint_ref
      : undefined;
    const r = resumeCheck(walText, cp, registryRef);
    resumeOk = r.ok && !r.recon;
    recon.push(...r.detalhes.filter(() => !resumeOk));
  } catch (e) {
    resumeOk = false;
    recon.push(`memória ilegível: ${(e as Error).message}`);
  }

  const profileText = lerArquivo(raiz, ".igc-profile.yml");
  const boot = bootCheck({ profileText });

  const orfaos: string[] = [];
  const regText = lerArquivo(raiz, ".igc-registry.yml");
  if (regText !== undefined) {
    orfaos.push(...scanOrphans(parseRegistry(regText), new Date()).orfaos);
  }

  // — débitos
  const debitos = parseDebitos(lerArquivo(raiz, ".session/DEBT.md") ?? "");

  // — cadeia TS
  const cadeia: ItemCadeia[] = [];
  const bpText = lerArquivo(raiz, "pipeline/blueprint.json");
  const stateText = lerArquivo(raiz, "pipeline/chain-state.json");
  if (bpText !== undefined) {
    const bp = JSON.parse(bpText) as {
      chain?: { id: string; title: string; acceptance: string; next: string | null }[];
    };
    const estados = stateText !== undefined
      ? (JSON.parse(stateText) as { estados?: Record<string, string> }).estados ?? {}
      : {};
    for (const step of bp.chain ?? []) {
      cadeia.push({
        id: step.id,
        title: step.title,
        acceptance: step.acceptance,
        estado: estados[step.id] ?? (step.next === null ? "pending" : "pending"),
      });
    }
  }

  // — backlog CNJ (fábrica)
  const cnj: ItemCnj[] = [];
  const backlogText = lerArquivo(raiz, "pipeline/backlog.json");
  if (backlogText !== undefined) {
    const bl = JSON.parse(backlogText) as { issues?: { id: string; titulo: string; status: string }[] };
    for (const item of bl.issues ?? []) {
      cnj.push({ id: item.id, titulo: item.titulo, status: item.status });
    }
  }

  return {
    igc: {
      resumeOk,
      recon,
      profileOk: boot.ok,
      profileFaltas: boot.profile.faltas,
      orfaos,
      walEntradas,
    },
    debitos,
    cadeia,
    cnj,
  };
}

const PRIORIDADE_ALTA = new Set(["urgente", "alta", "urgent", "high"]);

/** UMA decisão por ciclo — sempre com motivo (M6) e comando de retorno (fluxo de débito). */
export function decidir(escopo: EscopoGlobal): Decisao {
  // 1. débito com prioridade alta/urgente → retorno para fix primeiro
  const urgente = escopo.debitos.find(
    (d) => PRIORIDADE_ALTA.has(d.prioridade) && d.acao === "corrigir",
  );
  if (urgente !== undefined) {
    return {
      acao: "fix",
      alvo: urgente.id,
      motivo: `débito ${urgente.id} com prioridade ${urgente.prioridade} — retorno para fix antes de evoluir o escopo`,
      comando: `corrigir ${urgente.id} (${urgente.titulo})`,
      prioridade: urgente.prioridade === "urgente" || urgente.prioridade === "urgent" ? "urgente" : "alta",
    };
  }

  // 2. memória divergente (M4) → humano reconciliar
  if (!escopo.igc.resumeOk || escopo.igc.recon.length > 0) {
    return {
      acao: "humano",
      motivo: `M4/D3: memória IGC divergente (${escopo.igc.recon.join("; ") || "RECON"}) — reconciliar antes de evoluir`,
      comando: "node src/cli/igc-cli.ts resume-check",
      prioridade: "urgente",
    };
  }

  // 3. profile inválido (G6) → humano (BOOT recusado)
  if (!escopo.igc.profileOk) {
    return {
      acao: "humano",
      motivo: `G6: .igc-profile.yml inválido/incompleto (${escopo.igc.profileFaltas.join(", ")}) — BOOT recusado`,
      comando: "node src/cli/igc-cli.ts boot-check",
      prioridade: "alta",
    };
  }

  // 4. item bloqueado → decisão humana (nunca auto-merge de bloqueio)
  const bloqueado = escopo.cnj.find((i) => i.status === "bloqueada");
  if (bloqueado !== undefined) {
    return {
      acao: "humano",
      alvo: bloqueado.id,
      motivo: `${bloqueado.id} está BLOQUEADA (${bloqueado.titulo}) — ação humana para destravar; o guardião não destrava sozinho`,
      prioridade: "media",
    };
  }

  // 5. próxima issue da cadeia TS → execução automática (acceptance dentro do cycle)
  const pendente = escopo.cadeia.find((c) => c.estado === "pending");
  if (pendente !== undefined) {
    return {
      acao: "executar-cadeia",
      alvo: pendente.id,
      motivo: `cadeia TS com ${pendente.id} pendente (${pendente.title}) — executar acceptance '${pendente.acceptance}'`,
      comando: `node --disable-warning=ExperimentalWarning src/cli/pipeline-cli.ts cycle --id ${pendente.id}`,
      prioridade: "alta",
    };
  }

  // 6. backlog CNJ pendente → fábrica (gate 6)
  const cnjPendente = escopo.cnj.find((i) => i.status === "pendente");
  if (cnjPendente !== undefined) {
    return {
      acao: "fabrica",
      alvo: cnjPendente.id,
      motivo: `backlog CNJ com ${cnjPendente.id} pendente (${cnjPendente.titulo}) — delegar ao gate 6/fábrica`,
      comando: `python3 pipeline/gate.py issue --id ${cnjPendente.id} --marcar`,
      prioridade: "media",
    };
  }

  // 7. linhagens órfãs (G5) → abrir débito/retorno
  if (escopo.igc.orfaos.length > 0) {
    return {
      acao: "fix",
      alvo: escopo.igc.orfaos.join(","),
      motivo: `G5: linhagem(ns) órfã(s) >30d sem checkpoint (${escopo.igc.orfaos.join(", ")}) — registrar débito e retomar`,
      comando: "node src/cli/igc-cli.ts scan-orphans",
      prioridade: "media",
    };
  }

  // 8. escopo global sem pendências → vigiar (nunca silencioso)
  return {
    acao: "vigiar",
    motivo:
      "escopo global sem pendências: cadeia TS completa, CNJ sem pendentes, memória íntegra, sem órfãos — ciclo de monitoramento",
    prioridade: "baixa",
  };
}
