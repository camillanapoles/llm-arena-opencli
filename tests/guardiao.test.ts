/**
 * Guardião de Projeto — garantias da decisão automática de continuidade.
 * Regras: 1 decisão/ciclo · prioridade de débito → RECON → bloqueio → cadeia →
 * fábrica → órfãos → vigiar · M6: todo caminho tem `motivo` explícito.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { decidir, parseDebitos, scanGlobal, type EscopoGlobal } from "../src/guardian/guardian.ts";
import { writeCheckpoint } from "../src/session/igc.ts";

const RAIZ = process.cwd();

function escopoBase(): EscopoGlobal {
  return {
    igc: { resumeOk: true, recon: [], profileOk: true, profileFaltas: [], orfaos: [], walEntradas: 3 },
    debitos: [],
    cadeia: [{ id: "ISSUE-3", title: "wasm", estado: "pending", acceptance: "npm run ci" }],
    cnj: [{ id: "ISSUE-013", titulo: "x", status: "pendente" }],
  };
}

test("decisão 1: débito urgente com retorno para fix vem ANTES de tudo", () => {
  const e = escopoBase();
  e.debitos.push({ id: "D5", titulo: "issue #3 403", prioridade: "urgente", acao: "corrigir" });
  const d = decidir(e);
  assert.equal(d.acao, "fix");
  assert.equal(d.alvo, "D5");
  assert.equal(d.prioridade, "urgente");
  assert.ok(d.motivo.length > 0 && d.comando !== undefined);
});

test("decisão 2: memória RECON (M4) exige humano antes de evoluir", () => {
  const e = escopoBase();
  e.igc.resumeOk = false;
  e.igc.recon = ["WAL perdeu entradas"];
  const d = decidir(e);
  assert.equal(d.acao, "humano");
  assert.match(d.motivo, /M4/);
});

test("decisão 3: item BLOQUEADO nunca é destravado pelo guardião", () => {
  const e = escopoBase();
  e.cnj.push({ id: "ISSUE-007", titulo: "julgado", status: "bloqueada" });
  const d = decidir(e);
  assert.equal(d.acao, "humano");
  assert.equal(d.alvo, "ISSUE-007");
});

test("decisão 4: cadeia TS pendente executa o cycle com acceptance", () => {
  const d = decidir(escopoBase());
  assert.equal(d.acao, "executar-cadeia");
  assert.equal(d.alvo, "ISSUE-3");
  assert.match(d.comando ?? "", /pipeline-cli\.ts cycle --id ISSUE-3/);
});

test("decisão 5: sem cadeia pendente, fábrica CNJ assume os pendentes", () => {
  const e = escopoBase();
  e.cadeia = [{ id: "ISSUE-3", title: "wasm", estado: "delivered", acceptance: "npm run ci" }];
  const d = decidir(e);
  assert.equal(d.acao, "fabrica");
  assert.equal(d.alvo, "ISSUE-013");
  assert.match(d.comando ?? "", /gate\.py issue/);
});

test("decisão 6: tudo completo → vigiar com motivo explícito (M6)", () => {
  const e = escopoBase();
  e.cadeia = [{ id: "ISSUE-3", title: "wasm", estado: "chain-complete", acceptance: "npm run ci" }];
  e.cnj = [{ id: "ISSUE-013", titulo: "x", status: "concluida" }];
  const d = decidir(e);
  assert.equal(d.acao, "vigiar");
  assert.ok(d.motivo.includes("sem pendências"));
  for (const cenario of [escopoBase(), e]) {
    assert.ok(decidir(cenario).motivo.length > 0, "M6: nenhum caminho sem motivo");
  }
});

test("decisão 7: órfãos de linhagem (G5) geram retorno antes do vigiar", () => {
  const e = escopoBase();
  e.cadeia = [{ id: "ISSUE-3", title: "wasm", estado: "chain-complete", acceptance: "npm run ci" }];
  e.cnj = [];
  e.igc.orfaos = ["ed79bd77"];
  const d = decidir(e);
  assert.equal(d.acao, "fix");
  assert.match(d.motivo, /G5/);
});

test("scanGlobal do repositório real: retrato íntegro (IGC + cadeia + CNJ + débitos)", () => {
  const e = scanGlobal(RAIZ);
  assert.ok(e.igc.walEntradas >= 10, "WAL vivo legível");
  assert.equal(e.igc.profileOk, true, "profile do repositório válido (G6)");
  assert.ok(e.cadeia.length >= 3, "cadeia TS indexada");
  assert.ok(e.cnj.some((i) => i.id === "ISSUE-001"), "backlog CNJ legível");
  assert.ok(e.debitos.length >= 3, "débitos D1+ vivos em DEBT.md");
});

test("parseDebitos: cabeçalhos Dn/Mn com prioridade e gatilho", () => {
  const itens = parseDebitos([
    "# Débitos",
    "## D6 (IGC Art. 7) — registry no default branch",
    "**Gatilho / retorno para fix (E5):** no merge",
    "**Prioridade:** baixa · **Quando:** merge",
    "## M1 — correção de âncora",
    "**Gatilho:** n/a",
    "**Prioridade:** baixa.",
  ].join("\n"));
  assert.equal(itens.length, 2);
  assert.equal(itens[0]!.id, "D6");
  assert.equal(itens[0]!.acao, "corrigir");
  assert.equal(itens[1]!.id, "M1");
});

test("guardiao-cli: dry-run devolve UMA decisão com motivo; scan devolve o retrato", () => {
  const run = spawnSync(process.execPath, [join(RAIZ, "src/cli/guardiao-cli.ts"), "run"], {
    cwd: RAIZ,
    encoding: "utf8",
  });
  const next = JSON.parse(run.stdout);
  assert.equal(next.modo, "dry-run");
  assert.ok(next.decisao.motivo.length > 0, "M6: motivo presente");
  assert.ok(["fix", "humano", "executar-cadeia", "fabrica", "vigiar"].includes(next.decisao.acao));
  assert.ok(run.status === 0 || (run.status === 1 && next.decisao.acao === "humano"),
    "exit 0, ou 1 apenas quando a decisão é humana");

  const scan = JSON.parse(execFileSync(process.execPath, [
    join(RAIZ, "src/cli/guardiao-cli.ts"), "scan",
  ], { cwd: RAIZ, encoding: "utf8" }));
  assert.ok(Array.isArray(scan.cadeia) && Array.isArray(scan.cnj) && Array.isArray(scan.debitos));
});

test("guardiao-cli: run --executar é limitado — vigiar/decisão sem comando não executa nada", () => {
  const dir = mkdtempSync(join(tmpdir(), "guard-t-"));
  mkdirSync(join(dir, ".session"), { recursive: true });
  mkdirSync(join(dir, "pipeline"), { recursive: true });
  // cenário mínimo: WAL + CHECKPOINT derivado coerente, sem débitos/cadeia/CNJ → vigiar
  writeFileSync(join(dir, ".session", "WAL.md"), "# WAL\n");
  writeCheckpoint(join(dir, ".session", "CHECKPOINT"), { id_conteudo: "abc1234", estado: "CONTINUE" });
  writeFileSync(join(dir, ".igc-profile.yml"), readFileSync(join(RAIZ, ".igc-profile.yml"), "utf8"));
  writeFileSync(join(dir, "pipeline", "blueprint.json"), JSON.stringify({ chain: [] }));
  writeFileSync(join(dir, "pipeline", "chain-state.json"), JSON.stringify({ estados: {} }));
  writeFileSync(join(dir, "pipeline", "backlog.json"), JSON.stringify({ issues: [] }));
  const saida = execFileSync(process.execPath, [
    join(RAIZ, "src/cli/guardiao-cli.ts"), "run", "--executar",
  ], { cwd: dir, encoding: "utf8" });
  assert.match(saida, /nada a executar/);
  rmSync(dir, { recursive: true, force: true });
});
