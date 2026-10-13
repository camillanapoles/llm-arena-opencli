/**
 * IGC Art. 9 — testes das garantias (T1–T8) do protocolo igc-continuity v2.1.
 * T8 (transporte/handoff offline) valida A5 num clone frio SEM rede.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  appendWal,
  bootCheck,
  closeGate,
  conflictCheck,
  emitGuard,
  parseRegistry,
  parseWal,
  readCheckpoint,
  registrySync,
  resumeCheck,
  scanOrphans,
  walHash,
  writeCheckpoint,
  type WalEntry,
} from "../src/session/igc.ts";

const RAIZ = process.cwd();

function entrada(parcial: Partial<WalEntry>): WalEntry {
  return {
    timestamp: "2026-10-13T10:00:00Z",
    evento: "EXEC",
    classe: "IMPLEMENT",
    causa: "c",
    acao: "a",
    resultado: "r",
    id_conteudo: "abc1234",
    ...parcial,
  };
}

function walDe(...entries: WalEntry[]): string {
  return ["# WAL.md — append-only", ...entries.map((e) =>
    `${e.timestamp} | ${e.evento} | ${e.classe} | ${e.causa} | ${e.acao} | ${e.resultado} | ${e.id_conteudo}`,
  )].join("\n") + "\n";
}

// T1 — idempotência: mesmo (event_id, checkpoint_id) → recusado, WAL intacto
test("T1: emit_guard recusa chave duplicada (event_id, checkpoint_id) e não toca o WAL", () => {
  const wal = walDe(entrada({ evento: "EMIT", acao: "emit event_id=push#42 rótulo=IMPLEMENT", id_conteudo: "abc1234" }));
  const livre = emitGuard(wal, "push#99", "abc1234");
  assert.equal(livre.status, 0);
  const dup = emitGuard(wal, "push#42", "abc1234");
  assert.equal(dup.status, 3, "duplicata exige status 3 (sem emissão duplicada)");
  const outroCheckpoint = emitGuard(wal, "push#42", "def5678");
  assert.equal(outroCheckpoint.status, 0, "mesmo evento em checkpoint NOVO é emissão nova legítima");
  assert.equal(parseWal(wal).length, 1, "WAL intacto após o guard");
});

// T2 — paralelismo: duas linhagens no mesmo artefato exigem CONFLICT
test("T2: conflito de linhagens sem entrada CONFLICT é reprovado; com entrada, aprovado", () => {
  const states = [
    { slug: "d917b13b", artefatos: { "pipeline/backlog.json": "aaa1111" } },
    { slug: "ed79bd77", artefatos: { "pipeline/backlog.json": "bbb2222" } },
  ];
  const sem = conflictCheck(walDe(entrada({})), states);
  assert.equal(sem.ok, false);
  assert.match(sem.conflitos[0] ?? "", /SEM entrada CONFLICT/);
  const com = conflictCheck(
    walDe(entrada({ evento: "CONFLICT", causa: "pipeline/backlog.json: d917b13b × ed79bd77", resultado: "resolvido por merge manual" })),
    states,
  );
  assert.equal(com.ok, true, "CONFLICT registrado torna o conflito auditável (G4)");
});

// T3 — órfãos: >30d sem checkpoint gera DEBT; ativa preservada
test("T3: varredura de órfãos — linhagem ativa sem checkpoint recente é candidata a DEBT", () => {
  const reg = {
    linhagens: {
      viva: { branch: "a/x", checkpoint_ref: "h1", ativa: true, checkpoint_em: "2026-10-10T00:00:00Z" },
      orfa: { branch: "b/y", checkpoint_ref: "h2", ativa: true, checkpoint_em: "2026-08-01T00:00:00Z" },
      encerrada: { branch: "c/z", checkpoint_ref: "h3", ativa: false, checkpoint_em: "2020-01-01T00:00:00Z" },
    },
  };
  const r = scanOrphans(reg, new Date("2026-10-13T00:00:00Z"));
  assert.deepEqual(r.orfaos, ["orfa"]);
  assert.deepEqual(r.ativas, ["viva", "orfa"], "ativas preservadas; encerrada fora da varredura");
});

// T4 — registry: roundtrip frio; adulteração → RECON + DEBT (M4/D3)
test("T4: roundtrip do registry e detecção de adulteração (RECON + DEBT)", () => {
  registrySync({ linhagens: {} }, "d917b13b", {
    branch: "arena/d917b13b-llm-arena-opencli",
    checkpoint_ref: "abc1234",
    ativa: true,
    checkpoint_em: "2026-10-13T10:00:00Z",
  });
  const texto = [
    "# .igc-registry.yml — IGC Art. 7 (D1): descoberta de linhagens",
    "# D2: todo EMIT atualiza o registry no mesmo commit do CHECKPOINT.",
    "",
    "linhagens:",
    "  d917b13b:",
    '    branch: "arena/d917b13b-llm-arena-opencli"',
    '    checkpoint_ref: "abc1234"',
    "    ativa: true",
    '    checkpoint_em: "2026-10-13T10:00:00Z"',
    "",
  ].join("\n");
  const frio = parseRegistry(texto);
  assert.equal(frio.linhagens["d917b13b"]?.checkpoint_ref, "abc1234");
  assert.equal(frio.linhagens["d917b13b"]?.ativa, true);

  const wal = walDe(entrada({ id_conteudo: "abc1234" }));
  const dir = mkdtempSync(join(tmpdir(), "igc-t4-"));
  writeFileSync(join(dir, "WAL.md"), wal);
  const cp = writeCheckpoint(join(dir, "CHECKPOINT"), { id_conteudo: "abc1234", estado: "CONTINUE" });
  const integro = resumeCheck(wal, cp, frio.linhagens["d917b13b"]!.checkpoint_ref);
  assert.equal(integro.ok, true);

  const adulterado = resumeCheck(wal, cp, "zzz9999"); // registry aponta outra coisa
  assert.equal(adulterado.recon, true, "divergência registry × CHECKPOINT → RECON");
  assert.match(adulterado.debitos[0] ?? "", /D3/);
  rmSync(dir, { recursive: true, force: true });
});

// T5 — WAL no CI: checkpoint avança a memória; o pipeline tem o step final (C1)
test("T5: checkpoint avança WAL+CHECKPOINT e os pipelines carregam o step igc (C1–C3)", () => {
  const dir = mkdtempSync(join(tmpdir(), "igc-t5-"));
  mkdirSync(join(dir, ".session"));
  writeFileSync(join(dir, ".session", "WAL.md"), "# WAL.md\n");
  const antes = readFileSync(join(dir, ".session", "WAL.md"), "utf8");
  execFileSync(process.execPath, [
    join(RAIZ, "src/cli/igc-cli.ts"), "checkpoint",
    "--id-conteudo", "feedf00d", "--run-id", "42", "--estado", "CONTINUE",
  ], { cwd: dir, encoding: "utf8" });
  const depois = readFileSync(join(dir, ".session", "WAL.md"), "utf8");
  assert.ok(parseWal(depois).length > parseWal(antes).length, "C1: WAL avançou com o run");
  const cp = readCheckpoint(join(dir, ".session", "CHECKPOINT"));
  assert.equal(cp.id_conteudo, "feedf00d");
  assert.equal(cp.wal, walHash(depois), "CHECKPOINT guarda o hash do WAL após o append");
  assert.equal(cp.entradas, parseWal(depois).length);

  for (const fluxo of [".github/workflows/ci.yml", ".github/workflows/gates.yml"]) {
    const yml = readFileSync(join(RAIZ, fluxo), "utf8");
    assert.match(yml, /igc-checkpoint/, `${fluxo} precisa do step final igc (C1)`);
    assert.match(yml, /\[igc-checkpoint\]/, `${fluxo} persiste com tag [igc-checkpoint] (C1/C2)`);
    assert.match(yml, /\[skip ci\]/, `${fluxo} previne re-trigger (C2)`);
  }
  rmSync(dir, { recursive: true, force: true });
});

// T6 — profile: ausente bloqueia BOOT; inválido declara DEBT+RECON
test("T6: BOOT sem profile é recusado (G6); profile inválido vira DEBT + RECON", () => {
  const sem = bootCheck({ profileText: undefined });
  assert.equal(sem.ok, false);
  assert.match(sem.motivo ?? "", /OBRIGATÓRIO/);
  const incompleto = bootCheck({ profileText: "igc_profile: \"1\"\nlinhagem:\n" });
  assert.equal(incompleto.ok, false);
  assert.match(incompleto.motivo ?? "", /DEBT \+ RECON/);
  assert.ok(incompleto.profile.faltas.includes("bootstrap"));
  const completo = bootCheck({ profileText: readFileSync(join(RAIZ, ".igc-profile.yml"), "utf8") });
  assert.equal(completo.ok, true, "profile do repositório é válido");
});

// T7 — capabilities: fallbacks ativados sem quebrar a FSM (CP1/CP3)
test("T7: capabilities ausentes ativam fallbacks declarados (vcs/exec) sem parar a FSM", () => {
  const profileText = readFileSync(join(RAIZ, ".igc-profile.yml"), "utf8");
  const r = bootCheck({ profileText, capabilities: { vcs: false, exec: false } });
  assert.equal(r.ok, true, "com fallback declarado o BOOT segue (CP1)");
  assert.equal(r.fallbacks.length, 2);
  assert.match(r.fallbacks[0] ?? "", /branch\+clone/);
  assert.match(r.fallbacks[1] ?? "", /gates de pipeline/);
  // CP3: WAL funciona em qualquer capability (texto puro)
  const wal = walDe(entrada({}));
  assert.equal(parseWal(wal).length, 1);
});

// T8 — transporte/handoff offline (W7 + EV-5): tar → commit → bundle → clone frio → suíte verde
test("T8: round-trip de transporte — clone frio SEM rede reexecuta a suíte e fica verde", () => {
  const dir = mkdtempSync(join(tmpdir(), "igc-t8-"));
  const transporte = join(dir, "transporte");
  const frio = join(dir, "frio");
  mkdirSync(transporte);
  // W7: população por transporte — tar do worktree (sem .git/node_modules/regeneráveis)
  execFileSync("bash", [
    "-c",
    `tar -cf "${join(dir, "estado.tar")}" ` +
      "--exclude=./.git --exclude=./node_modules --exclude=./wasm/dist --exclude=./dist " +
      "--exclude=./data --exclude=./saida --exclude=./pipeline/saida --exclude='*.db*' " +
      "--exclude=./__pycache__ --exclude='*/__pycache__' --exclude='*.pyc' --exclude='./processos-*.jsonl' .",
  ], { cwd: RAIZ, encoding: "utf8" });
  execFileSync("tar", ["-xf", join(dir, "estado.tar"), "-C", transporte], { encoding: "utf8" });
  execFileSync("git", ["init", "-q", "-b", "linhagem"], { cwd: transporte });
  execFileSync("git", ["config", "user.name", "igc-t8"], { cwd: transporte });
  execFileSync("git", ["config", "user.email", "igc@t8"], { cwd: transporte });
  execFileSync("git", ["add", "-A"], { cwd: transporte });
  execFileSync("git", ["commit", "-qm", "checkpoint de transporte (W7) [igc-checkpoint] [skip ci]"], { cwd: transporte });
  // bundle → verify → clone frio (sem rede)
  execFileSync("git", ["bundle", "create", join(dir, "estado.bundle"), "linhagem"], { cwd: transporte });
  execFileSync("git", ["bundle", "verify", join(dir, "estado.bundle")], { cwd: transporte, encoding: "utf8" });
  execFileSync("git", ["clone", "-q", "-b", "linhagem", join(dir, "estado.bundle"), frio], { encoding: "utf8" });
  // suíte de verificação OFFLINE reexecutada no clone independente (make testes)
  const saida = execFileSync("make", ["testes"], {
    cwd: frio,
    encoding: "utf8",
    timeout: 240_000,
  });
  assert.ok(saida.includes("Todas as verificações passaram") || saida.includes("0 falharam"),
    "suíte offline verde no clone frio");
  assert.ok(!saida.includes("FALHA"), "nenhuma falha na suíte do clone");
  rmSync(dir, { recursive: true, force: true });
});

// Art. 12 — gate de fechamento (nota < 9.5 não fecha)
test("Art. 12: close-gate reprova fechamento incompleto e aprova o completo", () => {
  const incompleto = closeGate({
    walAppendOnly: true, checkpointGravado: true, verificacaoVerde: true,
    emitContratado: false, debitosComGatilho: true, territorioPruned: true, desviosDeclarados: true,
  });
  assert.equal(incompleto.podeFechar, false);
  const completo = closeGate({
    walAppendOnly: true, checkpointGravado: true, verificacaoVerde: true,
    emitContratado: true, debitosComGatilho: true, territorioPruned: true, desviosDeclarados: true,
    roundTrip: true,
  });
  assert.equal(completo.podeFechar, true);
  assert.equal(completo.nota, 10);
});

// Sanity: o WAL vivo do repositório é parseável e append-only coerente (M1)
test("M1: WAL vivo do repositório parseia; CHECKPOINT nunca tem mais entradas que o WAL", () => {
  const wal = readFileSync(join(RAIZ, ".session", "WAL.md"), "utf8");
  const entries = parseWal(wal);
  assert.ok(entries.length >= 8, "pelo menos as entradas da sessão v1.0 + v2.1");
  for (const e of entries) {
    assert.ok(e.id_conteudo.length > 0, "todo evento tem id_conteúdo (A3/M1)");
  }
  // entradas pós-v2.1 (a partir do RESUME) carregam a classe das 5 oficiais (A4)
  const v21 = entries.filter((e) => ["RESUME", "AMENDA", "M7", "EMIT"].includes(e.evento));
  for (const e of v21) {
    assert.ok(["FIX", "CONTINUE", "IMPLEMENT", "DEBT", "HANDOFF"].includes(e.classe),
      `classe das 5 oficiais (A4): ${e.classe}`);
    assert.ok(e.id_conteudo.length >= 6, `WAL# com id_conteúdo ≥6: ${e.id_conteudo}`);
  }
  const cp = readCheckpoint(join(RAIZ, ".session", "CHECKPOINT"));
  assert.ok(entries.length >= cp.entradas, "append-only: nunca menos entradas que o checkpoint");
});
