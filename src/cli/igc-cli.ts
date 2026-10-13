/**
 * igc-cli — operações do protocolo igc-continuity v2.1 (Art. 8: WAL no CI).
 *
 *   node src/cli/igc-cli.ts boot-check                     # Art. 10/11 (T6/T7)
 *   node src/cli/igc-cli.ts emit-guard --event X --checkpoint Y   # E4 (T1)
 *   node src/cli/igc-cli.ts wal-append --evento E --classe C --causa ... --acao ... --resultado ... --id-conteudo SHA
 *   node src/cli/igc-cli.ts checkpoint --id-conteudo SHA --estado CONTINUE [--run-id N]  # C1 (T5)
 *   node src/cli/igc-cli.ts resume-check                   # M4/D3 (T4)
 *   node src/cli/igc-cli.ts registry-sync --slug S --checkpoint-ref SHA [--ativa]
 *   node src/cli/igc-cli.ts scan-orphans [--hoje YYYY-MM-DD]      # G5 (T3)
 *   node src/cli/igc-cli.ts close-gate [--handoff] [--round-trip] # Art. 12
 *
 * Exit: 0 ok · 1 erro de verificação/RECON · 2 BOOT recusado/DEBT · 3 duplicidade (E4).
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import {
  appendWal,
  bootCheck,
  closeGate,
  emitGuard,
  nowIso,
  parseRegistry,
  readCheckpoint,
  registrySync,
  resumeCheck,
  scanOrphans,
  writeCheckpoint,
  type WalEntry,
} from "../session/igc.ts";

const SESSION = ".session";
const WAL = join(SESSION, "WAL.md");
const CHECKPOINT = join(SESSION, "CHECKPOINT");
const REGISTRY = ".igc-registry.yml";
const PROFILE = ".igc-profile.yml";

function flags(args: string[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  for (let i = 0; i < args.length; i++) {
    if (!args[i]!.startsWith("--")) continue;
    const key = args[i]!.slice(2);
    const prox = args[i + 1];
    if (prox !== undefined && !prox.startsWith("--")) {
      out[key] = prox;
      i++;
    } else {
      out[key] = true;
    }
  }
  return out;
}

function gitHead(): string {
  try {
    return execFileSync("git", ["rev-parse", "--short", "HEAD"], { encoding: "utf8" }).trim();
  } catch {
    return "sem-vcs";
  }
}

function emitir(classe: string, resultado: string): void {
  console.log(JSON.stringify({ classe, resultado }));
}

const [cmd, ...rest] = process.argv.slice(2);
const f = flags(rest);

switch (cmd) {
  case "boot-check": {
    const profileText = existsSync(PROFILE) ? readFileSync(PROFILE, "utf8") : undefined;
    const r = bootCheck({ profileText });
    if (!r.ok) {
      console.error(`✘ ${r.motivo}`);
      emitir("DEBT", r.motivo ?? "BOOT recusado");
      process.exit(2);
    }
    for (const fb of r.fallbacks) console.log(`⚠ CAPABILITY: ${fb}`);
    console.log("✔ boot-check: profile válido; capabilities:", Object.keys(r.capabilities).join(", "));
    process.exit(0);
  }

  case "emit-guard": {
    const eventId = String(f["event"] ?? "");
    const checkpoint = String(f["checkpoint"] ?? gitHead());
    const walText = existsSync(WAL) ? readFileSync(WAL, "utf8") : "";
    const r = emitGuard(walText, eventId, checkpoint);
    console.log(JSON.stringify(r));
    process.exit(r.status);
  }

  case "wal-append": {
    const entry: WalEntry = {
      timestamp: String(f["timestamp"] ?? nowIso()),
      evento: String(f["evento"] ?? "MANUAL"),
      classe: String(f["classe"] ?? "CONTINUE"),
      causa: String(f["causa"] ?? ""),
      acao: String(f["acao"] ?? ""),
      resultado: String(f["resultado"] ?? ""),
      id_conteudo: String(f["id-conteudo"] ?? gitHead()),
    };
    appendWal(WAL, entry);
    console.log(`✔ WAL += ${entry.evento} (${entry.classe})`);
    process.exit(0);
  }

  case "checkpoint": {
    // C4: linhagem sem .session/ → bootstrap do protocolo neste run
    if (!existsSync(SESSION)) {
      writeFileSync(WAL, "# WAL.md — append-only (IGC v2.1)\n", "utf8");
      appendWal(WAL, {
        timestamp: nowIso(), evento: "BOOT", classe: "CONTINUE",
        causa: "pipeline em linhagem sem .session/ (C4)", acao: "bootstrap do protocolo no run",
        resultado: "memória iniciada no CI", id_conteudo: String(f["id-conteudo"] ?? gitHead()),
      });
    }
    const id = String(f["id-conteudo"] ?? gitHead());
    const estado = String(f["estado"] ?? "CONTINUE");
    const runId = f["run-id"] !== undefined ? `run_id=${String(f["run-id"])}` : "";
    appendWal(WAL, {
      timestamp: nowIso(),
      evento: "igc(ci)",
      classe: String(f["classe"] ?? "CONTINUE"),
      causa: runId !== "" ? `pipeline concluído (${runId})` : String(f["causa"] ?? "checkpoint manual"),
      acao: "C1: append WAL + recompute CHECKPOINT",
      resultado: String(f["resultado"] ?? "checkpoint avançado"),
      id_conteudo: id,
    });
    const cp = writeCheckpoint(CHECKPOINT, { id_conteudo: id, estado });
    // D2: registry no mesmo commit do CHECKPOINT
    if (existsSync(REGISTRY) && f["slug"] !== undefined) {
      const reg = parseRegistry(readFileSync(REGISTRY, "utf8"));
      const atualizado = registrySync(reg, String(f["slug"]), {
        checkpoint_ref: id,
        checkpoint_em: nowIso(),
      });
      writeFileSync(REGISTRY, writeRegistryText(atualizado), "utf8");
    }
    console.log(`✔ checkpoint: id=${cp.id_conteudo} entradas=${cp.entradas} estado=${cp.estado}`);
    process.exit(0);
  }

  case "resume-check": {
    const walText = existsSync(WAL) ? readFileSync(WAL, "utf8") : "";
    const cp = readCheckpoint(CHECKPOINT);
    let registryRef: string | undefined;
    if (existsSync(REGISTRY)) {
      const reg = parseRegistry(readFileSync(REGISTRY, "utf8"));
      const minha = Object.values(reg.linhagens).find((l) => l.ativa);
      registryRef = minha?.checkpoint_ref;
    }
    const r = resumeCheck(walText, cp, registryRef);
    for (const d of r.detalhes) console.log(`• ${d}`);
    if (r.recon) {
      for (const d of r.debitos) console.error(`DEBT: ${d}`);
      console.error("✘ divergência — estado RECON obrigatório (M4)");
      process.exit(1);
    }
    console.log("✔ resume-check: memória íntegra");
    process.exit(0);
  }

  case "registry-sync": {
    const reg = existsSync(REGISTRY)
      ? parseRegistry(readFileSync(REGISTRY, "utf8"))
      : { linhagens: {} };
    const slug = String(f["slug"] ?? "d917b13b");
    const atualizado = registrySync(reg, slug, {
      ...(f["checkpoint-ref"] !== undefined ? { checkpoint_ref: String(f["checkpoint-ref"]) } : {}),
      ...(f["branch"] !== undefined ? { branch: String(f["branch"]) } : {}),
      ativa: f["inativa"] === true ? false : true,
      checkpoint_em: nowIso(),
    });
    writeFileSync(REGISTRY, writeRegistryText(atualizado), "utf8");
    console.log(`✔ registry: ${slug} → ${atualizado.linhagens[slug]?.checkpoint_ref}`);
    process.exit(0);
  }

  case "scan-orphans": {
    const reg = parseRegistry(readFileSync(REGISTRY, "utf8"));
    const hoje = f["hoje"] !== undefined ? new Date(`${String(f["hoje"])}T00:00:00Z`) : new Date();
    const r = scanOrphans(reg, hoje);
    if (r.orfaos.length > 0) {
      for (const slug of r.orfaos) console.error(`DEBT: linhagem órfã >30d sem checkpoint: ${slug} (G5)`);
      process.exit(1);
    }
    console.log(`✔ sem órfãos (ativas: ${r.ativas.join(", ")})`);
    process.exit(0);
  }

  case "close-gate": {
    const r = closeGate({
      walAppendOnly: f["wal-append-only"] === true,
      checkpointGravado: existsSync(CHECKPOINT),
      verificacaoVerde: f["verificacao-verde"] === true,
      emitContratado: f["emit-contratado"] === true,
      debitosComGatilho: f["debitos-com-gatilho"] === true,
      territorioPruned: f["territorio-pruned"] === true,
      desviosDeclarados: f["desvios-declarados"] === true,
      roundTrip: f["round-trip"] === true,
    });
    for (const [k, v] of Object.entries(r.checklist)) console.log(`(${v ? "x" : " "}) ${k}`);
    console.log(`nota: ${r.nota.toFixed(1)}/10 ${r.podeFechar ? "→ pode fechar" : "→ NÃO fecha; retorna a EXEC (Art. 12)"}`);
    process.exit(r.podeFechar ? 0 : 1);
  }

  default:
    console.error("comandos: boot-check | emit-guard | wal-append | checkpoint | resume-check | registry-sync | scan-orphans | close-gate");
    process.exit(1);
}

/** serialização YAML mínima do registry (formato estável do Art. 7 + extras) */
function writeRegistryText(reg: { linhagens: Record<string, Record<string, unknown>> }): string {
  const linhas = [
    "# .igc-registry.yml — IGC Art. 7 (D1): descoberta de linhagens",
    "# D2: todo EMIT atualiza o registry no mesmo commit do CHECKPOINT.",
    "",
    "linhagens:",
  ];
  for (const [slug, l] of Object.entries(reg.linhagens)) {
    linhas.push(`  ${slug}:`);
    for (const [k, v] of Object.entries(l)) {
      if (v === undefined) continue;
      const val = typeof v === "string" ? `"${v.replace(/"/g, "'")}"` : String(v);
      linhas.push(`    ${k}: ${val}`);
    }
  }
  return `${linhas.join("\n")}\n`;
}
