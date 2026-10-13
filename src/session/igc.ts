/**
 * igc-continuity v2.1 — motor do protocolo (Art. 2/4/7/9/10).
 *
 * Texto puro onde o contrato exige (WAL/CHECKPOINT/registry = YAML/markdown),
 * mecanismos trocáveis por capability (Art. 11). Nada aqui depende de
 * fornecedor: o único "estado" são arquivos versionados.
 */

import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync, appendFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";

// ------------------------------------------------------------------ WAL (M1)

export interface WalEntry {
  timestamp: string;
  evento: string;
  classe: "FIX" | "CONTINUE" | "IMPLEMENT" | "DEBT" | "HANDOFF" | string;
  causa: string;
  acao: string;
  resultado: string;
  id_conteudo: string;
}

const ENTRY_RE = /^([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+)\s*$/;

export function parseWal(text: string): WalEntry[] {
  const entries: WalEntry[] = [];
  for (const line of text.split("\n")) {
    if (!/^\d{4}-\d{2}-\d{2}T/.test(line)) continue; // comentários/cabeçalho não são entradas
    const m = ENTRY_RE.exec(line);
    if (m === null) throw new Error(`entrada WAL fora do formato: ${line.slice(0, 60)}…`);
    entries.push({
      timestamp: m[1]!.trim(),
      evento: m[2]!.trim(),
      classe: m[3]!.trim(),
      causa: m[4]!.trim(),
      acao: m[5]!.trim(),
      resultado: m[6]!.trim(),
      id_conteudo: m[7]!.trim(),
    });
  }
  return entries;
}

/** Âncora E3: número ordinal da entrada (WAL#n, 1-based). */
export function walAnchor(entries: WalEntry[], index: number): string {
  return `WAL#${index + 1}`;
}

export function formatWalEntry(e: WalEntry): string {
  return `${e.timestamp} | ${e.evento} | ${e.classe} | ${e.causa} | ${e.acao} | ${e.resultado} | ${e.id_conteudo}`;
}

/** M1: append-only — o ÚNICO jeito de "corrigir" é acrescentar entrada. */
export function appendWal(walPath: string, entry: WalEntry): void {
  appendFileSync(walPath, `${formatWalEntry(entry)}\n`, "utf8");
}

export function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

// ------------------------------------------------------- emit_guard (E4/T1)

export interface EmitGuardResult {
  status: 0 | 3; // 0 = livre para emitir · 3 = duplicado (idempotência G2)
  reason: string;
}

/**
 * Recusa evento cuja chave (event_id, checkpoint_id) já conste no WAL.
 * Convenção: emissões trazem `event_id=<id>` na coluna `ação`.
 */
export function emitGuard(walText: string, eventId: string, checkpointId: string): EmitGuardResult {
  const entries = parseWal(walText);
  const chave = `event_id=${eventId}`;
  const dup = entries.some(
    (e) => e.acao.includes(chave) && e.id_conteudo === checkpointId,
  );
  return dup
    ? { status: 3, reason: `evento ${eventId} já emitido no checkpoint ${checkpointId} (idempotência G2)` }
    : { status: 0, reason: `chave (${eventId}, ${checkpointId}) livre` };
}

// ---------------------------------------------------------- CHECKPOINT (M4)

export interface Checkpoint {
  id_conteudo: string;
  wal: string; // sha256 do WAL no momento da gravação
  entradas: number; // nº de entradas WAL observadas (tamper-evidence)
  estado: string; // FSM (v2.1)
  atualizado_em: string;
}

export function walHash(walText: string): string {
  return createHash("sha256").update(walText, "utf8").digest("hex");
}

export function writeCheckpoint(path: string, cp: Omit<Checkpoint, "wal" | "entradas" | "atualizado_em"> & Partial<Checkpoint>): Checkpoint {
  const walText = existsSync(join(dirname(path), "WAL.md")) ? readFileSync(join(dirname(path), "WAL.md"), "utf8") : "";
  const full: Checkpoint = {
    id_conteudo: cp.id_conteudo,
    wal: cp.wal ?? walHash(walText),
    entradas: cp.entradas ?? parseWal(walText).length,
    estado: cp.estado ?? "CONTINUE",
    atualizado_em: cp.atualizado_em ?? nowIso(),
  };
  const corpo = [
    `id_conteudo=${full.id_conteudo}`,
    `wal=${full.wal}`,
    `entradas=${full.entradas}`,
    `estado=${full.estado}`,
    `atualizado_em=${full.atualizado_em}`,
    "convencao=id_conteudo = último commit de trabalho verificado (acceptance verde); o commit que grava o CHECKPOINT é a assinatura (diff = apenas .session/ + registry)",
  ].join("\n");
  writeFileSync(path, `${corpo}\n`, "utf8");
  return full;
}

export function readCheckpoint(path: string): Checkpoint {
  const out: Record<string, string> = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
  }
  if (out["id_conteudo"] === undefined) throw new Error("CHECKPOINT sem id_conteudo");
  return {
    id_conteudo: out["id_conteudo"]!,
    wal: out["wal"] ?? "",
    entradas: Number(out["entradas"] ?? "0"),
    estado: out["estado"] ?? "CONTINUE",
    atualizado_em: out["atualizado_em"] ?? "",
  };
}

export interface ResumeCheck {
  ok: boolean;
  recon: boolean; // divergência → RECON obrigatório (M4/D3)
  debitos: string[];
  detalhes: string[];
}

/**
 * M4 + D3: integridade do CHECKPOINT contra o WAL e o registry.
 *  - entradas REMOVIDAS do WAL (count menor) → RECON;
 *  - hash divergente com o mesmo nº de entradas → WAL adulterado → RECON;
 *  - registry.checkpoint_ref ≠ CHECKPOINT.id_conteudo → RECON + DEBT;
 *  - WAL que só cresceu (append) é o estado NORMAL.
 */
export function resumeCheck(walText: string, cp: Checkpoint, registryRef?: string): ResumeCheck {
  const detalhes: string[] = [];
  const debitos: string[] = [];
  const entries = parseWal(walText);
  let recon = false;
  if (entries.length < cp.entradas) {
    recon = true;
    detalhes.push(`WAL perdeu entradas (${entries.length} < ${cp.entradas}) — M1 violado`);
  } else if (entries.length === cp.entradas && walHash(walText) !== cp.wal) {
    recon = true;
    detalhes.push("wal_hash do CHECKPOINT não confere — WAL adulterado");
  } else {
    detalhes.push(`WAL consistente (+${entries.length - cp.entradas} entradas desde o checkpoint — append esperado)`);
  }
  if (registryRef !== undefined && registryRef !== "" && registryRef !== cp.id_conteudo) {
    recon = true;
    debitos.push(`registry.checkpoint_ref (${registryRef}) ≠ CHECKPOINT (${cp.id_conteudo}) — D3`);
    detalhes.push("divergência registry × CHECKPOINT → RECON + DEBT");
  }
  return { ok: !recon, recon, debitos, detalhes };
}

// ------------------------------------------------------------- registry (Art. 7)

export interface RegistryLineage {
  branch: string;
  checkpoint_ref: string;
  ativa: boolean;
  checkpoint_em?: string;
  descricao?: string;
  [k: string]: unknown;
}

export interface Registry {
  linhagens: Record<string, RegistryLineage>;
}

/** Parser mínimo do subconjunto YAML que gravamos (indentação 2, sem âncoras). */
export function parseRegistry(text: string): Registry {
  const linhagens: Record<string, RegistryLineage> = {};
  let atual: string | null = null;
  let emLinhagens = false;
  for (const raw of text.split("\n")) {
    const line = raw.replace(/#.*$/, "").trimEnd();
    if (line.trim() === "") continue;
    if (/^linhagens:/.test(line)) {
      emLinhagens = true;
      continue;
    }
    if (!emLinhagens) continue;
    const slug = /^ {2}([\w.\-\/]+):\s*$/.exec(line);
    if (slug !== null) {
      atual = slug[1]!;
      linhagens[atual] = { branch: "", checkpoint_ref: "", ativa: false };
      continue;
    }
    const kv = /^ {4}([\w_]+):\s*(.+?)\s*$/.exec(line);
    if (kv !== null && atual !== null) {
      const key = kv[1]!;
      let val: string | boolean = kv[2]!.replace(/^["']|["']$/g, "");
      if (val === "true") val = true;
      if (val === "false") val = false;
      linhagens[atual]![key] = val;
    }
  }
  return { linhagens };
}

export function formatRegistry(reg: Registry): string {
  const linhas = [
    "# .igc-registry.yml — IGC Art. 7 (D1): descoberta de linhagens",
    "# D2: todo EMIT atualiza o registry no mesmo commit do CHECKPOINT.",
    "",
    "linhagens:",
  ];
  for (const [slug, l] of Object.entries(reg.linhagens)) {
    linhas.push(`  ${slug}:`);
    linhas.push(`    branch: ${l.branch}`);
    linhas.push(`    checkpoint_ref: ${l.checkpoint_ref}`);
    linhas.push(`    ativa: ${String(l.ativa)}`);
    if (l.checkpoint_em !== undefined) linhas.push(`    checkpoint_em: ${l.checkpoint_em}`);
    if (l.descricao !== undefined) linhas.push(`    descricao: "${String(l.descricao).replace(/"/g, "'")}"`);
    for (const [k, v] of Object.entries(l)) {
      if (["branch", "checkpoint_ref", "ativa", "checkpoint_em", "descricao"].includes(k)) continue;
      linhas.push(`    ${k}: ${typeof v === "string" ? `"${v}"` : String(v)}`);
    }
  }
  return `${linhas.join("\n")}\n`;
}

/** D2: sincroniza o checkpoint da linhagem no registry (mesmo commit do CHECKPOINT). */
export function registrySync(reg: Registry, slug: string, patch: Partial<RegistryLineage>): Registry {
  const atual = reg.linhagens[slug] ?? { branch: "", checkpoint_ref: "", ativa: true };
  return { linhagens: { ...reg.linhagens, [slug]: { ...atual, ...patch } } };
}

// ------------------------------------------------- capabilities/boot (Art. 11)

export interface BootCheck {
  ok: boolean; // false = BOOT recusado (G6/CP2)
  profile: { present: boolean; valido: boolean; faltas: string[] };
  capabilities: Record<string, boolean>; // fs_write, vcs, exec, append_wal
  fallbacks: string[];
  motivo?: string;
}

const PROFILE_KEYS = [
  "igc_profile", "linhagem", "eventos", "bootstrap", "verificacao",
  "integridade", "envelope", "ci", "runtime",
];

export function bootCheck(opts: {
  profileText?: string | undefined;
  capabilities?: Partial<Record<string, boolean>>;
}): BootCheck {
  const faltas: string[] = [];
  const present = opts.profileText !== undefined;
  if (present) {
    for (const k of PROFILE_KEYS) {
      if (!new RegExp(`^${k}:`, "m").test(opts.profileText!)) faltas.push(k);
    }
  }
  const capabilities = {
    fs_write: true, // exigida mínima universal (além de append_wal)
    append_wal: true,
    vcs: opts.capabilities?.vcs ?? true,
    exec: opts.capabilities?.exec ?? true,
  };
  const fallbacks: string[] = [];
  if (!capabilities.vcs) fallbacks.push("vcs ausente → isolamento por branch+clone (W1) + id_conteudo alternativo no profile (M1)");
  if (!capabilities.exec) fallbacks.push("exec ausente → hooks viram gates de pipeline (W4)");
  if (!present) {
    return {
      ok: false,
      profile: { present: false, valido: false, faltas: PROFILE_KEYS },
      capabilities,
      fallbacks,
      motivo: "BOOT recusado (G6): .igc-profile.yml ausente — profile é OBRIGATÓRIO (Art. 10); registrar DEBT",
    };
  }
  if (faltas.length > 0) {
    return {
      ok: false,
      profile: { present: true, valido: false, faltas },
      capabilities,
      fallbacks,
      motivo: `profile inválido — chaves faltando: ${faltas.join(", ")} (DEBT + RECON, T6)`,
    };
  }
  return { ok: true, profile: { present: true, valido: true, faltas: [] }, capabilities, fallbacks };
}

// -------------------------------------------------------- órfãos (G5/T3)

export interface OrphanScan {
  orfaos: string[]; // slugs >30d sem checkpoint
  ativas: string[];
}

export function scanOrphans(reg: Registry, hoje: Date): OrphanScan {
  const orfaos: string[] = [];
  const ativas: string[] = [];
  for (const [slug, l] of Object.entries(reg.linhagens)) {
    if (!l.ativa) continue;
    ativas.push(slug);
    const quando = l.checkpoint_em !== undefined ? new Date(l.checkpoint_em) : null;
    const dias = quando !== null && !Number.isNaN(quando.getTime())
      ? (hoje.getTime() - quando.getTime()) / 86_400_000
      : Infinity;
    if (dias > 30) orfaos.push(slug);
  }
  return { orfaos, ativas };
}

// ---------------------------------------------- paralelismo/conflito (G4/T2)

export interface LineageState {
  slug: string;
  artefatos: Record<string, string>; // path → id_conteudo
}

/** T2: duas linhagens mexendo no MESMO artefato com ids diferentes exigem entrada CONFLICT. */
export function conflictCheck(walText: string, states: LineageState[]): { ok: boolean; conflitos: string[] } {
  const donos = new Map<string, { slug: string; id: string }[]>();
  for (const s of states) {
    for (const [path, id] of Object.entries(s.artefatos)) {
      const lista = donos.get(path) ?? [];
      lista.push({ slug: s.slug, id });
      donos.set(path, lista);
    }
  }
  const conflitos: string[] = [];
  for (const [path, lista] of donos) {
    const ids = new Set(lista.map((x) => x.id));
    if (ids.size > 1) {
      const slugs = lista.map((x) => x.slug).join(" × ");
      const registrado = parseWal(walText).some(
        (e) => e.evento === "CONFLICT" && e.causa.includes(path),
      );
      if (!registrado) conflitos.push(`${path}: ${slugs} com id_conteudo divergente e SEM entrada CONFLICT no WAL`);
    }
  }
  return { ok: conflitos.length === 0, conflitos };
}

// ---------------------------------------------- gate de fechamento (Art. 12)

export interface CloseGate {
  nota: number; // 0–10; < 9.5 → não fecha
  podeFechar: boolean;
  checklist: Record<string, boolean>;
}

export function closeGate(checks: {
  walAppendOnly: boolean;
  checkpointGravado: boolean;
  verificacaoVerde: boolean;
  emitContratado: boolean;
  debitosComGatilho: boolean;
  territorioPruned: boolean;
  desviosDeclarados: boolean;
  roundTrip?: boolean | undefined; // obrigatório se HANDOFF (T8)
}): CloseGate {
  const checklist: Record<string, boolean> = {
    "WAL append-only sem edições": checks.walAppendOnly,
    "CHECKPOINT gravado": checks.checkpointGravado,
    "verificação verde no território": checks.verificacaoVerde,
    "EMIT contratado (E5)": checks.emitContratado,
    "débitos registrados com gatilho": checks.debitosComGatilho,
    "território pruned": checks.territorioPruned,
    "desvios de convenção declarados": checks.desviosDeclarados,
    "round-trip verde (T8 — só HANDOFF)": checks.roundTrip ?? true,
  };
  const ok = Object.values(checklist).filter(Boolean).length;
  const nota = (ok / Object.keys(checklist).length) * 10;
  return { nota, podeFechar: nota >= 9.5, checklist };
}
