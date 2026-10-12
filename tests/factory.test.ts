import { test } from "node:test";
import assert from "node:assert/strict";
import { Database } from "../src/db/database.ts";
import { migrate } from "../src/db/schema.ts";
import { ArenaCache } from "../src/cache/cache.ts";
import { builtinBlueprints, createDefaultFactory } from "../src/functions/builtins.ts";
import {
  FunctionFactory,
  UnknownKindError,
  defineFunction,
  type RuntimeContext,
} from "../src/functions/factory.ts";
import type { FunctionSpec } from "../src/core/types.ts";
import { GitHubActionsDriver } from "../src/drivers/github-actions.driver.ts";
import { MockTransport } from "../src/drivers/transport.ts";

function spec(overrides: Partial<FunctionSpec> = {}): FunctionSpec {
  return {
    id: "fn-x",
    name: "test fn",
    kind: "echo",
    params: {},
    cacheTtlMs: 0,
    enabled: true,
    ...overrides,
  };
}

function ctx(overrides: Partial<RuntimeContext> = {}): RuntimeContext {
  const db = new Database(":memory:");
  migrate(db);
  return {
    cache: new ArenaCache(),
    db,
    log: () => {},
    actions: null,
    event: {},
    ...overrides,
  };
}

test("factory registers builtins and lists kinds", () => {
  const factory = createDefaultFactory();
  const kinds = factory.kinds();
  for (const expected of ["echo", "cache.get", "cache.put", "sql.query", "github.event", "opencli.dispatch", "log"]) {
    assert.ok(kinds.includes(expected), `missing kind ${expected}`);
  }
  assert.ok(factory.has("echo"));
  assert.equal(factory.has("nope"), false);
});

test("factory create materializes a working function", async () => {
  const factory = createDefaultFactory();
  const fn = factory.create(spec());
  const result = await fn.execute({ hello: "world" }, ctx());
  assert.equal(result.ok, true);
  assert.deepEqual((result.output as { echoed: unknown }).echoed, { hello: "world" });
});

test("factory throws UnknownKindError for unregistered kinds", () => {
  const factory = createDefaultFactory();
  assert.throws(() => factory.create(spec({ kind: "does.not.exist" })), UnknownKindError);
});

test("custom blueprint via factory pattern (extension point)", async () => {
  const factory = new FunctionFactory();
  factory.register({
    kind: "double",
    description: "doubles a numeric input",
    create: (s) =>
      defineFunction(s, "double", async (input) => {
        return { value: Number(input["value"] ?? 0) * 2 };
      }),
  });
  const fn = factory.create(spec({ kind: "double" }));
  const result = await fn.execute({ value: 21 }, ctx());
  assert.equal(result.ok, true);
  assert.deepEqual(result.output, { value: 42 });
});

test("cache.put/cache.get blueprints round-trip through the cache", async () => {
  const factory = createDefaultFactory();
  const context = ctx();
  const put = factory.create(spec({ kind: "cache.put", params: { key: "k" } }));
  const get = factory.create(spec({ kind: "cache.get", params: { key: "k" } }));
  await put.execute({ key: "k", value: [1, 2, 3] }, context);
  const read = await get.execute({ key: "k" }, context);
  assert.equal(read.ok, true);
  assert.deepEqual((read.output as { value: unknown }).value, [1, 2, 3]);
});

test("sql.query only allows SELECT", async () => {
  const factory = createDefaultFactory();
  const context = ctx();
  const query = factory.create(spec({ kind: "sql.query" }));
  const ok = await query.execute({ sql: "SELECT 1 AS one" }, context);
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.output, [{ one: 1 }]);

  const denied = await query.execute({ sql: "DELETE FROM functions" }, context);
  assert.equal(denied.ok, false);
  assert.match(String(denied.error), /only SELECT/i);
});

test("github.event extracts nested paths", async () => {
  const factory = createDefaultFactory();
  const context = ctx({ event: { repository: { full_name: "jackwener/OpenCLI" } } });
  const fn = factory.create(spec({ kind: "github.event", params: { path: "repository.full_name" } }));
  const result = await fn.execute({}, context);
  assert.equal(result.output, "jackwener/OpenCLI");
});

test("opencli.dispatch fires repository_dispatch through the driver", async () => {
  const transport = new MockTransport();
  const actions = new GitHubActionsDriver({
    repo: "jackwener/OpenCLI",
    token: "test-token",
    transport,
  });
  const factory = createDefaultFactory();
  const context = ctx({ actions });
  const fn = factory.create(spec({ kind: "opencli.dispatch", params: { command: "ping" } }));
  const result = await fn.execute({ command: "open url", url: "https://arena.ai/agent" }, context);
  assert.equal(result.ok, true);
  assert.equal(transport.requests.length, 1);
  const request = transport.requests[0];
  assert.ok(request);
  assert.equal(request.method, "POST");
  assert.match(request.url, /\/repos\/jackwener\/OpenCLI\/dispatches$/);
  const body = JSON.parse(request.body ?? "{}") as { event_type: string; client_payload: { command: string } };
  assert.equal(body.event_type, "opencli-command");
  assert.equal(body.client_payload.command, "open url");
});

test("builtinBlueprints list matches createDefaultFactory kinds", () => {
  const factory = createDefaultFactory();
  assert.equal(builtinBlueprints().length, factory.kinds().length);
});
