import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp, seedDefaults, type App } from "../src/app.ts";
import { normalizeEvent, parseWebhook, matchesTrigger } from "../src/gate/events.ts";
import { MockTransport } from "../src/drivers/transport.ts";
import type { GateDefinition } from "../src/core/types.ts";

function app(): { app: App; transport: MockTransport } {
  const transport = new MockTransport();
  const created = createApp({ dbPath: ":memory:", transport, log: () => {} });
  return { app: created, transport };
}

test("normalizeEvent maps github webhook shapes", () => {
  const event = normalizeEvent({
    type: "push",
    payload: {
      ref: "refs/heads/main",
      repository: { full_name: "jackwener/OpenCLI" },
      sender: { login: "octocat" },
    },
  });
  assert.equal(event.type, "push");
  assert.equal(event.repo, "jackwener/OpenCLI");
  assert.equal(event.ref, "refs/heads/main");
  assert.equal(event.actor, "octocat");
});

test("normalizeEvent falls back to manual for unknown types", () => {
  const event = normalizeEvent({ type: "totally-unknown", payload: {} });
  assert.equal(event.type, "manual");
});

test("parseWebhook maps repository_dispatch event_type", () => {
  const event = parseWebhook("repository_dispatch", { event_type: "opencli-command" });
  assert.equal(event.type, "repository_dispatch");
});

test("matchesTrigger respects events, refs and actor allow-list", () => {
  const trigger = {
    events: ["push" as const],
    refs: ["refs/heads/main"],
    actorAllow: ["octocat"],
  };
  const push = normalizeEvent({ type: "push", ref: "refs/heads/main", actor: "octocat" });
  const wrongRef = normalizeEvent({ type: "push", ref: "refs/heads/dev", actor: "octocat" });
  const wrongActor = normalizeEvent({ type: "push", ref: "refs/heads/main", actor: "mallory" });
  const wrongType = normalizeEvent({ type: "schedule", ref: "refs/heads/main", actor: "octocat" });

  assert.equal(matchesTrigger(trigger, push), true);
  assert.equal(matchesTrigger(trigger, wrongRef), false);
  assert.equal(matchesTrigger(trigger, wrongActor), false);
  assert.equal(matchesTrigger(trigger, wrongType), false);
});

test("seedDefaults is idempotent", () => {
  const { app: created } = app();
  const first = seedDefaults(created);
  const second = seedDefaults(created);
  assert.ok(first.functions.length > 0);
  assert.ok(first.gates.length > 0);
  assert.deepEqual(second, { functions: [], gates: [] });
  created.close();
});

test("receive runs matching gates and persists runs", async () => {
  const { app: created } = app();
  seedDefaults(created);
  const event = normalizeEvent({ type: "push", ref: "refs/heads/main", payload: {} });
  const result = await created.driver.receive(event);

  assert.equal(result.ok, true);
  assert.equal(result.outcomes.length, 1);
  const outcome = result.outcomes[0];
  assert.ok(outcome);
  assert.equal(outcome.gate.id, "gate-ci-blocking");
  assert.equal(outcome.run.status, "success");
  assert.equal(outcome.run.steps.length, 2);

  const stored = created.runs.get(outcome.run.id);
  assert.ok(stored);
  assert.equal(stored.status, "success");
  assert.equal(created.events.get(event.id)?.id, event.id);

  // Decision is cached for web-side fast path.
  const cached = created.cache.get("gate:gate-ci-blocking:last") as { status: string };
  assert.equal(cached.status, "success");
  created.close();
});

test("blocking gate failure fails receive; advisory does not", async () => {
  const { app: created } = app();
  created.functions.create({
    id: "fn-fail",
    name: "Always fails",
    kind: "sql.query",
    params: { sql: "DELETE FROM runs" }, // rejected: not SELECT
    cacheTtlMs: 0,
    enabled: true,
  });
  const blocking: GateDefinition = {
    id: "gate-block",
    name: "Blocking fail",
    policy: "blocking",
    trigger: { events: ["manual"] },
    functions: ["fn-fail"],
    enabled: true,
  };
  const advisory: GateDefinition = {
    id: "gate-adv",
    name: "Advisory fail",
    policy: "advisory",
    trigger: { events: ["manual"] },
    functions: ["fn-fail"],
    enabled: true,
  };
  created.gates.create(blocking);
  created.gates.create(advisory);

  const result = await created.driver.receive(normalizeEvent({ type: "manual", payload: {} }));
  assert.equal(result.ok, false);
  assert.equal(result.outcomes.length, 2);
  const byGate = Object.fromEntries(result.outcomes.map((o) => [o.gate.id, o]));
  assert.equal(byGate["gate-block"]?.run.status, "failure");
  assert.equal(byGate["gate-adv"]?.run.status, "failure");
  assert.equal(byGate["gate-adv"]?.blocking, false);
  created.close();
});

test("disabled function steps are skipped, missing ones fail", async () => {
  const { app: created } = app();
  created.functions.create({
    id: "fn-off",
    name: "Disabled",
    kind: "echo",
    params: {},
    cacheTtlMs: 0,
    enabled: false,
  });
  created.gates.create({
    id: "gate-skip",
    name: "Skip test",
    policy: "blocking",
    trigger: { events: ["manual"] },
    functions: ["fn-off", "fn-missing"],
    enabled: true,
  });
  const result = await created.driver.receive(normalizeEvent({ type: "manual", payload: {} }));
  const outcome = result.outcomes[0];
  assert.ok(outcome);
  assert.equal(outcome.run.steps[0]?.status, "skipped");
  assert.equal(outcome.run.steps[1]?.status, "failure");
  assert.match(String(outcome.run.steps[1]?.error), /not found/i);
  created.close();
});

test("opencli gate dispatches to the target repo through the transport", async () => {
  const { app: created, transport } = app();
  seedDefaults(created);
  const result = await created.driver.receive(
    normalizeEvent({ type: "workflow_dispatch", payload: {} }),
  );
  assert.equal(result.outcomes.length, 1);
  const dispatched = transport.requests.find((r) => r.url.includes("/dispatches"));
  assert.ok(dispatched, "expected a repository_dispatch request");
  const body = JSON.parse(dispatched.body ?? "{}") as { event_type: string };
  assert.equal(body.event_type, "opencli-command");
  created.close();
});

test("gate with no matching trigger is not executed", async () => {
  const { app: created } = app();
  seedDefaults(created);
  const result = await created.driver.receive(normalizeEvent({ type: "release", payload: {} }));
  assert.equal(result.outcomes.length, 0);
  assert.equal(result.ok, true);
  created.close();
});
