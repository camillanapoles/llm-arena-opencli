import { test } from "node:test";
import assert from "node:assert/strict";
import { Database } from "../src/db/database.ts";
import { loadBlueprint, type Blueprint } from "../src/pipeline/chain.ts";
import { decideDirection } from "../src/pipeline/envelope.ts";
import {
  BashRunner,
  IssueFactory,
  IssueRepository,
  PipelineEngine,
  PipelineIssue,
  isCompleteSuccess,
  type CommandResult,
  type CommandRunner,
} from "../src/pipeline/domain.ts";

const demoBlueprint: Blueprint = {
  version: 1,
  chain: [
    {
      id: "ISSUE-1",
      title: "Primeira",
      instruction: "construir A",
      acceptance: "ok-cmd",
      next: "ISSUE-2",
    },
    {
      id: "ISSUE-2",
      title: "Segunda",
      instruction: "construir B",
      acceptance: "fail-cmd",
      next: null,
    },
  ],
};

/** Runner fake determinístico: mapeia comando -> resultado fixo. */
function fakeRunner(results: Record<string, CommandResult>): CommandRunner {
  return {
    run(command: string): CommandResult {
      return results[command] ?? { exitCode: 0, log: "" };
    },
  };
}

function makeEngine(runner: CommandRunner): { engine: PipelineEngine; repo: IssueRepository } {
  const db = new Database(":memory:");
  const repo = new IssueRepository(db);
  const factory = new IssueFactory(demoBlueprint);
  return { engine: new PipelineEngine({ repo, factory, runner }), repo };
}

// ------------------------------------------------------- entidade + estados

test("PipelineIssue: máquina de estados start/deliver/fail", () => {
  const issue = new PipelineIssue({
    id: "ISSUE-1",
    title: "t",
    instruction: "i",
    acceptance: "npm run ci",
    state: "pending",
    attempts: 0,
    next: "ISSUE-2",
    lastError: null,
  });
  issue.start();
  assert.equal(issue.state, "in_progress");
  assert.equal(issue.attempts, 1);
  issue.deliver();
  assert.equal(issue.state, "delivered");
  issue.start();
  issue.fail("boom", "fix");
  assert.equal(issue.state, "failed");
  assert.equal(issue.lastError, "boom");
  issue.start();
  issue.fail("débito", "debt");
  assert.equal(issue.state, "debt");
});

test("IssueRepository: persistência SQLite OO (round-trip + pendentes)", () => {
  const repo = new IssueRepository(new Database(":memory:"));
  const factory = new IssueFactory(demoBlueprint);
  for (const issue of factory.materializeAll()) repo.save(issue);

  assert.equal(repo.list().length, 2);
  assert.equal(repo.listPending().length, 2);

  const issue = repo.get("ISSUE-1");
  assert.ok(issue);
  issue.start();
  issue.deliver();
  repo.save(issue);

  assert.equal(repo.get("ISSUE-1")?.state, "delivered");
  assert.equal(repo.listPending().length, 1); // só ISSUE-2
});

// ----------------------------------------------------------------- factory

test("IssueFactory: criação a partir do blueprint (pattern factory)", () => {
  const factory = new IssueFactory(demoBlueprint);
  const issue = factory.createById("ISSUE-2");
  assert.equal(issue.state, "pending");
  assert.equal(issue.acceptance, "fail-cmd");
  assert.equal(factory.materializeAll().length, 2);
  assert.throws(() => factory.createById("ISSUE-404"), /não existe/);
});

test("IssueFactory event-driven: evento demanda issue fora do blueprint", () => {
  const factory = new IssueFactory(demoBlueprint);
  const created = factory.createFromEvent({ type: "issue.requested", issueId: "ISSUE-9" });
  assert.equal(created.id, "ISSUE-9");
  assert.match(created.instruction, /factory event-driven/);
  const known = factory.createFromEvent({ type: "issue.completed", issueId: "ISSUE-1" });
  assert.equal(known.id, "ISSUE-1");
  assert.throws(() => factory.createFromEvent({ type: "issue.completed" }), /sem issueId/);
});

test("IssueFactory rejeita blueprint inválido", () => {
  assert.throws(
    () =>
      new IssueFactory({
        version: 1,
        chain: [{ id: "X", title: "x", instruction: "y", acceptance: "", next: null }],
      }),
    /blueprint inválido/,
  );
});

// ----------------------------------------------------------- determinismo

test("decideDirection: continue | complete | fix | debt", () => {
  assert.equal(decideDirection(0, true), "continue");
  assert.equal(decideDirection(0, false), "complete");
  assert.equal(decideDirection(1, true), "fix");
  assert.equal(decideDirection(1, false), "fix");
  assert.equal(decideDirection(2, true), "debt");
  assert.equal(decideDirection(2, false), "debt");
});

test("isCompleteSuccess: exit 0 + nenhum # fail n>0", () => {
  assert.equal(isCompleteSuccess(0, "# tests 10\n# pass 10\n# fail 0"), true);
  assert.equal(isCompleteSuccess(0, "# tests 10\n# fail 2"), false); // sucesso mascarado
  assert.equal(isCompleteSuccess(1, "# fail 0"), false);
  // nomes de testes TAP contendo "# fail 3" NÃO podem falsear a validação
  assert.equal(
    isCompleteSuccess(0, "# Subtest: runCycle (\\# fail 3 com exit 0)\nok 22 - x\n# fail 0"),
    true,
  );
  assert.equal(
    isCompleteSuccess(0, "# Subtest: x (\\# fail 3)\n# fail 1"),
    false,
  );
});

// ------------------------------------------------------- ciclos + eventos

test("runCycle SUCESSO COMPLETO -> delivered + próxima issue + direção continue", () => {
  const { engine, repo } = makeEngine(
    fakeRunner({ "ok-cmd": { exitCode: 0, log: "# fail 0" } }),
  );
  const env = engine.runCycle("ISSUE-1", "action-test-1");
  assert.equal(env.exitCode, 0);
  assert.equal(env.nextIssue, "ISSUE-2");
  assert.equal(env.direction, "continue");
  assert.equal(env.status, "delivered");
  assert.equal(repo.get("ISSUE-1")?.state, "delivered");
  assert.equal(env.id, "action-test-1");
});

test("runCycle fim de cadeia -> direction complete", () => {
  const { engine } = makeEngine(
    fakeRunner({ "fail-cmd": { exitCode: 0, log: "" } }),
  );
  const env = engine.runCycle("ISSUE-2");
  assert.equal(env.exitCode, 0);
  assert.equal(env.nextIssue, null);
  assert.equal(env.direction, "complete");
  assert.equal(env.status, "chain-complete");
});

test("runCycle ERRO -> MESMA issue + direção fix + continuidade", () => {
  const { engine, repo } = makeEngine(
    fakeRunner({ "ok-cmd": { exitCode: 1, log: "acceptance quebrou" } }),
  );
  const env = engine.runCycle("ISSUE-1");
  assert.equal(env.exitCode, 1);
  assert.equal(env.nextIssue, "ISSUE-1");
  assert.equal(env.direction, "fix");
  assert.equal(env.continuity.required, true);
  assert.equal(repo.get("ISSUE-1")?.state, "failed");
});

test("runCycle com sucesso mascarado (# fail 3 com exit 0) -> tratado como erro", () => {
  const { engine } = makeEngine(
    fakeRunner({ "ok-cmd": { exitCode: 0, log: "# tests 9\n# fail 3" } }),
  );
  const env = engine.runCycle("ISSUE-1");
  assert.equal(env.exitCode, 1);
  assert.equal(env.direction, "fix");
});

test("runCycle issue desconhecida -> exit 2 + direction hold", () => {
  const { engine } = makeEngine(fakeRunner({}));
  const env = engine.runCycle("ISSUE-404");
  assert.equal(env.exitCode, 2);
  assert.equal(env.direction, "hold");
  assert.equal(env.continuity.required, true);
});

test("ciclos determinísticos: duas execuções idênticas -> mesmas decisões", () => {
  const runner = fakeRunner({ "ok-cmd": { exitCode: 0, log: "# fail 0" } });
  const a = makeEngine(runner).engine.runCycle("ISSUE-1", "id-a");
  const b = makeEngine(runner).engine.runCycle("ISSUE-1", "id-b");
  assert.equal(a.exitCode, b.exitCode);
  assert.equal(a.nextIssue, b.nextIssue);
  assert.equal(a.direction, b.direction);
  assert.equal(a.status, b.status);
});

test("onEvent issue.completed -> constrói próxima (continue); issue.failed -> fix; result 2 -> debt", () => {
  const { engine, repo } = makeEngine(fakeRunner({}));

  const completed = engine.onEvent({ type: "issue.completed", issueId: "ISSUE-1", result: 0 });
  assert.equal(completed.exitCode, 0);
  assert.equal(completed.nextIssue, "ISSUE-2");
  assert.equal(completed.direction, "continue");

  const failed = engine.onEvent({ type: "issue.failed", issueId: "ISSUE-1", result: 1 });
  assert.equal(failed.exitCode, 1);
  assert.equal(failed.nextIssue, "ISSUE-1");
  assert.equal(failed.direction, "fix");

  const debt = engine.onEvent({ type: "issue.failed", issueId: "ISSUE-2", result: 2 });
  assert.equal(debt.exitCode, 2);
  assert.equal(debt.direction, "debt");
  assert.equal(repo.get("ISSUE-2")?.state, "debt");

  const gate = engine.onEvent({ type: "gate.checked" });
  assert.equal(gate.status, "gate-event");
  assert.equal(gate.direction, "continue");
});

test("onEvent cria issue por evento (event-driven) quando não persistida", () => {
  const { engine, repo } = makeEngine(fakeRunner({}));
  const env = engine.onEvent({ type: "issue.requested", issueId: "ISSUE-9" });
  assert.equal(env.status, "created");
  assert.equal(env.nextIssue, "ISSUE-9"); // a MESMA issue criada é o próximo movimento
  assert.equal(env.direction, "continue");
  assert.equal(env.continuity.required, true);
  assert.equal(repo.get("ISSUE-9")?.state, "pending"); // ainda não testada
});

test("BashRunner existe e é determinístico (mesmo comando, mesmo exit)", () => {
  const runner = new BashRunner();
  const a = runner.run("echo hi");
  const b = runner.run("echo hi");
  assert.equal(a.exitCode, 0);
  assert.equal(b.exitCode, 0);
  assert.equal(a.log.trim(), "hi");
  assert.equal(b.log.trim(), "hi");
});

test("blueprint real materializa issues com instruções pendentes", () => {
  const factory = new IssueFactory(loadBlueprint("pipeline/blueprint.json"));
  const all = factory.materializeAll();
  assert.ok(all.length >= 3);
  for (const issue of all) {
    assert.ok(issue.instruction.length > 10, `${issue.id} sem instrução`);
    assert.ok(issue.acceptance.length > 0, `${issue.id} sem acceptance`);
  }
});
