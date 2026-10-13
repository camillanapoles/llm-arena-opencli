import { test } from "node:test";
import assert from "node:assert/strict";
import {
  makeEnvelope,
  successEnvelope,
  errorEnvelope,
  EXIT_CODES,
} from "../src/pipeline/envelope.ts";
import { evaluateContinuityGate, gateEnvelope } from "../src/pipeline/gates.ts";
import {
  loadBlueprint,
  validateBlueprint,
  getStep,
  nextStepAfter,
  runChainStep,
  type Blueprint,
} from "../src/pipeline/chain.ts";

// ---------------------------------------------------------------- envelope

test("envelope tem o contrato obrigatório: id, message, addenda, status, nextIssue, exitCode", () => {
  const env = makeEnvelope({
    status: "success",
    nextIssue: "ISSUE-2",
    exitCode: 0,
  });
  assert.equal(typeof env.id, "string");
  assert.ok(env.id.length > 0);
  assert.equal(typeof env.message, "string");
  assert.ok(Array.isArray(env.addenda));
  assert.equal(typeof env.status, "string");
  assert.equal(env.nextIssue, "ISSUE-2");
  assert.equal(env.exitCode, 0);
});

test("successEnvelope: exit 0, próxima issue indexada, continuidade da cadeia", () => {
  const env = successEnvelope({ nextIssue: "ISSUE-3", message: "ok" });
  assert.equal(env.exitCode, EXIT_CODES.SUCCESS);
  assert.equal(env.nextIssue, "ISSUE-3");
  assert.equal(env.status, "success");
  assert.equal(env.continuity.required, true);
});

test("errorEnvelope tipo 1: MESMA issue + info de continuidade", () => {
  const env = errorEnvelope({
    sameIssue: "ISSUE-2",
    errorType: 1,
    continuityReason: "falha nos testes — correção necessária para continuidade",
    message: "log de erro",
    addenda: [{ kind: "log", ref: "tail do teste", description: "log" }],
  });
  assert.equal(env.exitCode, 1);
  assert.equal(env.status, "error");
  assert.equal(env.nextIssue, "ISSUE-2"); // mesma issue
  assert.equal(env.continuity.required, true);
  assert.match(env.continuity.reason, /continuidade/);
  assert.equal(env.addenda.length, 1);
});

test("errorEnvelope tipo 2: MESMA issue + continuidade de pré-condição", () => {
  const env = errorEnvelope({
    sameIssue: "ISSUE-1",
    errorType: 2,
    continuityReason: "pré-condição violada",
  });
  assert.equal(env.exitCode, 2);
  assert.equal(env.status, "continuity");
  assert.equal(env.nextIssue, "ISSUE-1");
});

// ------------------------------------------------------------------- gates

test("gate positivo: sem issues abertas, CI verde, testes presentes e aprovados", () => {
  const decision = evaluateContinuityGate({
    openIssues: 0,
    ciFailures: 0,
    testsTotal: 66,
    testsPassed: 66,
  });
  assert.equal(decision.positive, true);
  assert.deepEqual(decision.reasons, []);
  const env = gateEnvelope(decision, {
    openIssues: 0,
    ciFailures: 0,
    testsTotal: 66,
    testsPassed: 66,
  });
  assert.equal(env.status, "production-ready");
  assert.equal(env.exitCode, 0);
});

test("gate não positivo: issues abertas -> CONTINUIDADE (exit 2)", () => {
  const snapshot = { openIssues: 3, ciFailures: 0, testsTotal: 66, testsPassed: 66 };
  const decision = evaluateContinuityGate(snapshot);
  assert.equal(decision.positive, false);
  assert.match(decision.reasons.join(" "), /3 issue\(s\) aberta\(s\)/);
  const env = gateEnvelope(decision, snapshot);
  assert.equal(env.status, "continuity");
  assert.equal(env.exitCode, 2);
  assert.equal(env.continuity.required, true);
});

test("gate não positivo: CI com erros e SEM TESTES -> múltiplos motivos", () => {
  const decision = evaluateContinuityGate({
    openIssues: 0,
    ciFailures: 2,
    testsTotal: 0,
    testsPassed: 0,
  });
  assert.equal(decision.positive, false);
  assert.equal(decision.reasons.length, 2);
  assert.match(decision.reasons.join(" "), /CI\/CD com 2/);
  assert.match(decision.reasons.join(" "), /sem testes/);
});

test("gate não positivo: testes presentes porém não aprovados", () => {
  const decision = evaluateContinuityGate({
    openIssues: 0,
    ciFailures: 0,
    testsTotal: 10,
    testsPassed: 8,
  });
  assert.equal(decision.positive, false);
  assert.match(decision.reasons.join(" "), /8\/10/);
});

// ------------------------------------------------------------------- chain

const demoBlueprint: Blueprint = {
  version: 1,
  chain: [
    {
      id: "ISSUE-1",
      title: "Primeira",
      instruction: "construir A",
      acceptance: "npm run ci",
      next: "ISSUE-2",
    },
    {
      id: "ISSUE-2",
      title: "Segunda",
      instruction: "construir B",
      acceptance: "npm run ci",
      next: null,
    },
  ],
};

test("validateBlueprint: indexação, next válido, acceptance obrigatório", () => {
  assert.equal(validateBlueprint(demoBlueprint).ok, true);

  const broken: Blueprint = {
    version: 1,
    chain: [
      { id: "ISSUE-9", title: "x", instruction: "y", acceptance: "", next: "ISSUE-404" },
    ],
  };
  const validation = validateBlueprint(broken);
  assert.equal(validation.ok, false);
  assert.ok(validation.problems.length >= 3);
});

test("blueprint real do repositório é íntegro e carregável", () => {
  const bp = loadBlueprint("pipeline/blueprint.json");
  assert.equal(validateBlueprint(bp).ok, true);
  assert.ok(bp.chain.length >= 3);
  assert.equal(bp.chain[0]?.id, "ISSUE-1");
});

test("runChainStep SUCESSO -> próxima issue indexada (ou cadeia completa)", () => {
  const step1 = getStep(demoBlueprint, "ISSUE-1");
  assert.ok(step1);
  const env1 = runChainStep(step1, { exitCode: 0, message: "entrega ok" });
  assert.equal(env1.exitCode, 0);
  assert.equal(env1.nextIssue, "ISSUE-2"); // avança
  assert.equal(env1.status, "delivered");

  const step2 = getStep(demoBlueprint, "ISSUE-2");
  assert.ok(step2);
  const env2 = runChainStep(step2, { exitCode: 0 });
  assert.equal(env2.nextIssue, null); // fim da cadeia
  assert.equal(env2.status, "chain-complete");
});

test("runChainStep ERRO -> MESMA issue + informações de continuidade", () => {
  const step = getStep(demoBlueprint, "ISSUE-2");
  assert.ok(step);
  const env = runChainStep(step, {
    exitCode: 1,
    message: "teste falhou",
    addenda: [{ kind: "log", ref: "tap.log", description: "saída dos testes" }],
  });
  assert.equal(env.exitCode, 1);
  assert.equal(env.nextIssue, "ISSUE-2"); // mesma
  assert.equal(env.continuity.required, true);
  assert.ok(env.addenda.length >= 2); // blueprint.json + log
});

test("nextStepAfter navega a cadeia indexada", () => {
  assert.equal(nextStepAfter(demoBlueprint, "ISSUE-1")?.id, "ISSUE-2");
  assert.equal(nextStepAfter(demoBlueprint, "ISSUE-2"), null);
  assert.equal(nextStepAfter(demoBlueprint, "ISSUE-404"), null);
});

// --------------------------------------- fluxo de débito de erro (prioridade + fix)

test("errorEnvelope tipo 1 abre débito known/high/fix com comando de fix", () => {
  const env = errorEnvelope({
    sameIssue: "ISSUE-2",
    errorType: 1,
    message: "acceptance reprovado",
    gate: "ISSUE-2",
    fixCommand: "npm run ci",
    continuityReason: "correção necessária",
  });
  assert.equal(env.direction, "fix"); // retorno para fix
  assert.deepEqual(env.debts, [
    {
      gate: "ISSUE-2",
      kind: "known",
      reason: "acceptance reprovado",
      priority: "high",
      action: "fix",
      fixCommand: "npm run ci",
    },
  ]);
});

test("errorEnvelope tipo 2 abre débito unknown/urgent/human", () => {
  const env = errorEnvelope({ sameIssue: "ISSUE-2", errorType: 2, message: "sem CI", continuityReason: "contorno" });
  assert.equal(env.debts[0]?.kind, "unknown");
  assert.equal(env.debts[0]?.priority, "urgent");
  assert.equal(env.debts[0]?.action, "human");
});

test("makeEnvelope: exitCode != 0 sem debts explícitos abre débito padrão; exit 0 fica vazio", () => {
  const erro = makeEnvelope({ status: "error", message: "x", nextIssue: "ISSUE-1", exitCode: 1, direction: "fix" });
  assert.equal(erro.debts.length, 1);
  assert.equal(erro.debts[0]?.action, "fix");
  const ok = makeEnvelope({ status: "success", message: "", nextIssue: null, exitCode: 0, direction: "complete" });
  assert.deepEqual(ok.debts, []);
});

test("runChainStep falha registra débito na MESMA issue com acceptance como comando de fix", () => {
  const step = { id: "ISSUE-2", title: "t", instruction: "i", acceptance: "npm run ci", next: "ISSUE-3" };
  const env = runChainStep(step, { exitCode: 1, message: "reprovado" });
  assert.equal(env.nextIssue, "ISSUE-2");
  assert.equal(env.direction, "fix");
  assert.equal(env.debts[0]?.gate, "ISSUE-2");
  assert.equal(env.debts[0]?.fixCommand, "npm run ci");
  assert.equal(env.debts[0]?.priority, "high");
});
