import { test } from "node:test";
import assert from "node:assert/strict";
import { Database, fromJson, toJson } from "../src/db/database.ts";
import { migrate } from "../src/db/schema.ts";
import { EventsRepo, FunctionsRepo, GatesRepo, RunsRepo } from "../src/crud/repos.ts";
import type { FunctionSpec, GateDefinition, RunRecord } from "../src/core/types.ts";

function freshDb(): Database {
  const db = new Database(":memory:");
  migrate(db);
  return db;
}

test("migrate creates tables", () => {
  const db = freshDb();
  const tables = db.query<{ name: string }>(
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
  );
  const names = tables.map((t) => t.name);
  for (const expected of ["cache", "events", "functions", "gates", "runs"]) {
    assert.ok(names.includes(expected), `missing table ${expected}`);
  }
  db.close();
});

test("FunctionsRepo CRUD round-trip", () => {
  const db = freshDb();
  const repo = new FunctionsRepo(db);
  const spec: FunctionSpec = {
    id: "fn-1",
    name: "Echo one",
    kind: "echo",
    params: { alpha: 1, nested: { ok: true } },
    cacheTtlMs: 1234,
    enabled: true,
  };

  repo.create(spec);
  const fetched = repo.get("fn-1");
  assert.ok(fetched);
  assert.equal(fetched.name, "Echo one");
  assert.deepEqual(fetched.params, { alpha: 1, nested: { ok: true } });
  assert.equal(fetched.cacheTtlMs, 1234);
  assert.equal(fetched.enabled, true);
  assert.equal(repo.count(), 1);

  const updated = repo.update("fn-1", { name: "Echo renamed", enabled: false });
  assert.ok(updated);
  assert.equal(updated.name, "Echo renamed");
  assert.equal(updated.enabled, false);
  assert.equal(repo.get("fn-1")?.enabled, false);

  assert.equal(repo.list().length, 1);
  assert.equal(repo.remove("fn-1"), true);
  assert.equal(repo.remove("fn-1"), false);
  assert.equal(repo.get("fn-1"), undefined);
  db.close();
});

test("GatesRepo stores trigger and function ids", () => {
  const db = freshDb();
  const repo = new GatesRepo(db);
  const gate: GateDefinition = {
    id: "gate-1",
    name: "Blocking",
    policy: "blocking",
    trigger: { events: ["push"], refs: ["refs/heads/main"] },
    functions: ["fn-a", "fn-b"],
    enabled: true,
  };
  repo.create(gate);
  const fetched = repo.get("gate-1");
  assert.ok(fetched);
  assert.deepEqual(fetched.trigger, { events: ["push"], refs: ["refs/heads/main"] });
  assert.deepEqual(fetched.functions, ["fn-a", "fn-b"]);
  db.close();
});

test("RunsRepo listByGate orders newest first", () => {
  const db = freshDb();
  const repo = new RunsRepo(db);
  const base: RunRecord = {
    id: "run-1",
    gateId: "gate-1",
    eventId: "evt-1",
    status: "success",
    steps: [],
    startedAt: "2026-01-01T00:00:00.000Z",
    finishedAt: "2026-01-01T00:00:01.000Z",
  };
  repo.create(base);
  repo.create({
    ...base,
    id: "run-2",
    startedAt: "2026-01-02T00:00:00.000Z",
  });
  const items = repo.listByGate("gate-1");
  assert.equal(items.length, 2);
  assert.equal(items[0]?.id, "run-2");
  db.close();
});

test("EventsRepo round-trip", () => {
  const db = freshDb();
  const repo = new EventsRepo(db);
  repo.create({
    id: "evt-1",
    type: "push",
    repo: "camillanapoles/llm-arena-opencli",
    ref: "refs/heads/main",
    actor: "octocat",
    payload: { ref: "refs/heads/main" },
    receivedAt: "2026-01-01T00:00:00.000Z",
  });
  const fetched = repo.get("evt-1");
  assert.ok(fetched);
  assert.equal(fetched.type, "push");
  assert.equal(fetched.actor, "octocat");
  assert.deepEqual(fetched.payload, { ref: "refs/heads/main" });
  db.close();
});

test("toJson/fromJson helpers", () => {
  assert.equal(toJson({ a: 1 }), '{"a":1}');
  assert.deepEqual(fromJson<{ a: number }>('{"a":1}', { a: 0 }), { a: 1 });
  assert.deepEqual(fromJson<unknown[]>(null, []), []);
  assert.deepEqual(fromJson<unknown[]>("not-json", ["x"]), ["x"]);
});
