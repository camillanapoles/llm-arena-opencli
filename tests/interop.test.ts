import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DIRECTION_FROM_CNJ,
  DIRECTION_TO_CNJ,
  fromCnjEnvelope,
  loadCnjBacklog,
  mergeRegistry,
  toCnjEnvelope,
  type CnjEnvelope,
} from "../src/pipeline/interop.ts";
import { loadBlueprint } from "../src/pipeline/chain.ts";
import { makeEnvelope } from "../src/pipeline/envelope.ts";

const cnjSample: CnjEnvelope = {
  id: "gate-continuidade-20261013T141500Z-8f3a1c",
  gate: "continuidade",
  status: "1",
  codigo_saida: 1,
  mensagem: "há 2 issues abertas — continuidade",
  continuidade: true,
  next_issue: "ISSUE-007",
  direcao: "proxima",
  proximo_passo: "python3 pipeline/gate.py issue --id ISSUE-007 --marcar",
  anexos: [
    { path: "pipeline/saida/issues-abertas.md", filename: "issues-abertas.md", descricao: "evidência" },
  ],
  dados: { issues_abertas: 2 },
  timestamp: "2026-10-13T14:15:00Z",
  versao: "1.0.0",
};

test("fromCnjEnvelope: contrato CNJ -> ActionEnvelope", () => {
  const env = fromCnjEnvelope(cnjSample);
  assert.equal(env.id, cnjSample.id);
  assert.equal(env.message, "há 2 issues abertas — continuidade");
  assert.equal(env.exitCode, 1);
  assert.equal(env.nextIssue, "ISSUE-007");
  assert.equal(env.status, "continuity");
  assert.equal(env.direction, "continue"); // proxima -> continue
  assert.equal(env.continuity.required, true);
  assert.equal(env.addenda[0]?.kind, "filename");
  assert.equal(env.addenda[0]?.ref, "pipeline/saida/issues-abertas.md");
  assert.equal(env.at, "2026-10-13T14:15:00Z");
});

test("fromCnjEnvelope: status 0 -> success; status 2 -> human-required/hold", () => {
  const ok = fromCnjEnvelope({ ...cnjSample, status: "0", codigo_saida: 0, direcao: "encerrar", continuidade: false, next_issue: null });
  assert.equal(ok.status, "success");
  assert.equal(ok.direction, "complete");
  assert.equal(ok.continuity.required, false);

  const humano = fromCnjEnvelope({ ...cnjSample, status: "2", codigo_saida: 2, direcao: "humano" });
  assert.equal(humano.status, "human-required");
  assert.equal(humano.direction, "hold");
  assert.equal(humano.exitCode, 2);
});

test("toCnjEnvelope: ActionEnvelope -> contrato CNJ (campos canônicos)", () => {
  const ours = makeEnvelope({
    id: "action-x",
    message: "entrega testada",
    addenda: [{ kind: "log", ref: "ci.log", description: "saída do acceptance" }],
    status: "delivered",
    nextIssue: "ISSUE-2",
    exitCode: 0,
    direction: "continue",
  });
  const cnj = toCnjEnvelope(ours, { gate: "issue", dados: { origem: "d917" } });
  assert.equal(cnj.id, "action-x");
  assert.equal(cnj.status, "0");
  assert.equal(cnj.codigo_saida, 0);
  assert.equal(cnj.mensagem, "entrega testada");
  assert.equal(cnj.next_issue, "ISSUE-2");
  assert.equal(cnj.direcao, "proxima");
  assert.equal(cnj.anexos[0]?.filename, "ci.log");
  assert.deepEqual(cnj.dados, { origem: "d917" });
  assert.equal(cnj.versao, "1.0.0");
});

test("round-trip de direções nos dois vocabulários é consistente", () => {
  for (const [ours, theirs] of Object.entries(DIRECTION_TO_CNJ)) {
    assert.equal(DIRECTION_FROM_CNJ[theirs], ours, `${ours} <-> ${theirs}`);
  }
});

test("round-trip envelope -> CNJ -> envelope preserva o essencial", () => {
  const ours = makeEnvelope({
    id: "rt-1",
    message: "msg",
    status: "error",
    nextIssue: "ISSUE-1",
    exitCode: 1,
    direction: "fix",
    continuity: { required: true, reason: "corrigir" },
  });
  const back = fromCnjEnvelope(toCnjEnvelope(ours));
  assert.equal(back.id, ours.id);
  assert.equal(back.message, ours.message);
  assert.equal(back.nextIssue, ours.nextIssue);
  assert.equal(back.exitCode, ours.exitCode);
  assert.equal(back.direction, ours.direction);
  assert.equal(back.continuity.required, true);
});

test("backlog CNJ real carrega e a ISSUE-007/008 (unificação) está mapeada", () => {
  const backlog = loadCnjBacklog("pipeline/backlog-cnj.json");
  assert.ok(backlog.issues.length >= 8);
  const i7 = backlog.issues.find((i) => i.id === "ISSUE-007");
  const i8 = backlog.issues.find((i) => i.id === "ISSUE-008");
  assert.ok(i7 && i8);
  assert.equal(i7.status, "bloqueada");
  assert.match(i8.titulo, /unificar com o fluxo da sess[ãa]o d917b13b/i);
});

test("mergeRegistry: registra unificado das duas sessões com namespace de origem", () => {
  const ours = loadBlueprint("pipeline/blueprint.json");
  const theirs = loadCnjBacklog("pipeline/backlog-cnj.json");
  const registry = mergeRegistry(ours, theirs, {
    ourBranch: "arena/d917b13b-llm-arena-opencli",
    ourPr: 1,
    theirBranch: "arena/ed79bd77-llm-arena-opencli",
    theirPr: 2,
    now: () => new Date("2026-10-13T20:00:00Z"),
  });

  assert.equal(registry.sessions.length, 2);
  assert.equal(registry.entries.length, ours.chain.length + theirs.issues.length);

  const ours0 = registry.entries.find((e) => e.id === "d917b13b:ISSUE-1");
  assert.ok(ours0);
  assert.equal(ours0.source, "arena/d917b13b-llm-arena-opencli");
  assert.equal(ours0.pr, 1);
  assert.equal(ours0.testInstruction, "npm run ci");

  const theirs7 = registry.entries.find((e) => e.id === "ed79bd77:ISSUE-007");
  assert.ok(theirs7);
  assert.equal(theirs7.source, "arena/ed79bd77-llm-arena-opencli");
  assert.equal(theirs7.status, "bloqueada");
  assert.match(theirs7.devInstruction, /unificar|unificar|decisão/i);

  // pendências por sessão refletem o status real
  const d917 = registry.sessions.find((s) => s.source.includes("d917b13b"));
  const ed79 = registry.sessions.find((s) => s.source.includes("ed79bd77"));
  assert.equal(d917?.pending, ours.chain.length); // nossas 3 cadeias pendentes
  assert.ok((ed79?.pending ?? 0) >= 1); // ISSUE-008 pendente na outra sessão
});

test("dependências entre issues da sessão CNJ são namespaced no registro", () => {
  const ours = loadBlueprint("pipeline/blueprint.json");
  const theirs = loadCnjBacklog("pipeline/backlog-cnj.json");
  const registry = mergeRegistry(ours, theirs, {
    ourBranch: "arena/d917b13b-llm-arena-opencli",
    ourPr: 1,
    theirBranch: "arena/ed79bd77-llm-arena-opencli",
    theirPr: 2,
  });
  const i8 = registry.entries.find((e) => e.originalId === "ISSUE-008");
  assert.ok(i8);
  // ISSUE-008 depende de ISSUE-006 na sessão ed79
  assert.ok(i8.dependsOn.every((d) => d.startsWith("ed79bd77:")));
});

// ------------------------------------------------- débitos de erro (debts ↔ debitos)

test("toCnjEnvelope: debts -> debitos (prioridade/acao/tipo/comando_fix)", () => {
  const ours = makeEnvelope({
    status: "error",
    message: "acceptance reprovado",
    nextIssue: "ISSUE-2",
    exitCode: 1,
    direction: "fix",
    debts: [
      {
        gate: "ISSUE-2",
        kind: "known",
        reason: "acceptance reprovado (exit 1)",
        priority: "high",
        action: "fix",
        fixCommand: "npm run ci",
      },
    ],
  });
  const cnj = toCnjEnvelope(ours, { gate: "issue" });
  assert.deepEqual(cnj.debitos, [
    {
      gate: "ISSUE-2",
      tipo: "1",
      motivo: "acceptance reprovado (exit 1)",
      prioridade: "alta",
      acao: "corrigir",
      comando_fix: "npm run ci",
    },
  ]);
});

test("fromCnjEnvelope: debitos -> debts (tipo 2 = unknown/human urgente)", () => {
  const env = fromCnjEnvelope({
    ...cnjSample,
    status: "2",
    codigo_saida: 2,
    direcao: "humano",
    debitos: [
      { gate: "testes", tipo: "2", motivo: "gh ausente", prioridade: "urgente", acao: "humano", comando_fix: "gh auth login" },
    ],
  });
  assert.deepEqual(env.debts, [
    {
      gate: "testes",
      kind: "unknown",
      reason: "gh ausente",
      priority: "urgent",
      action: "human",
      fixCommand: "gh auth login",
    },
  ]);
});

test("roundtrip débito: ActionEnvelope -> CNJ -> ActionEnvelope preserva semântica", () => {
  const ours = makeEnvelope({
    status: "continuity",
    message: "2 pendências",
    nextIssue: "ISSUE-3",
    exitCode: 1,
    direction: "fix",
    debts: [
      { gate: "testes", kind: "known", reason: "make testes código 2", priority: "high", action: "fix", fixCommand: "make testes" },
      { gate: "issues", kind: "known", reason: "2 abertas", priority: "medium", action: "fix" },
    ],
  });
  const back = fromCnjEnvelope(toCnjEnvelope(ours));
  assert.deepEqual(back.debts, ours.debts);
});

test("sem erro não há débito (debitos: []) nos dois dialetos", () => {
  const ours = makeEnvelope({
    status: "success",
    message: "ok",
    nextIssue: "ISSUE-3",
    exitCode: 0,
  });
  assert.deepEqual(ours.debts, []);
  const cnj = toCnjEnvelope(ours);
  assert.deepEqual(cnj.debitos, []);
});
