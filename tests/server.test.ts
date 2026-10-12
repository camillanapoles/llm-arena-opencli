import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createApp, seedDefaults, type App } from "../src/app.ts";
import { createHttpServer } from "../src/server.ts";
import { MockTransport } from "../src/drivers/transport.ts";

let app: App;
let server: Server;
let base: string;

before(async () => {
  const transport = new MockTransport();
  app = createApp({ dbPath: ":memory:", transport, log: () => {} });
  seedDefaults(app);
  server = createHttpServer(app);
  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve());
  });
  const address = server.address() as AddressInfo;
  base = `http://127.0.0.1:${address.port}`;
});

after(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
  app.close();
});

async function json(method: string, path: string, body?: unknown, headers?: Record<string, string>) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { "Content-Type": "application/json", ...(headers ?? {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return {
    status: response.status,
    body: text === "" ? null : (JSON.parse(text) as Record<string, unknown>),
  };
}

test("GET /health", async () => {
  const result = await json("GET", "/health");
  assert.equal(result.status, 200);
  assert.equal(result.body?.["status"], "ok");
  assert.ok(Number(result.body?.["functions"]) >= 3);
});

test("GET /api/kinds lists factory blueprints", async () => {
  const result = await json("GET", "/api/kinds");
  const kinds = result.body?.["kinds"] as { kind: string }[];
  assert.ok(kinds.some((k) => k.kind === "opencli.dispatch"));
});

test("functions CRUD over HTTP", async () => {
  const created = await json("POST", "/api/functions", {
    id: "fn-http-echo",
    name: "HTTP echo",
    kind: "echo",
    params: { tag: "http" },
  });
  assert.equal(created.status, 201);

  const duplicate = await json("POST", "/api/functions", { id: "fn-http-echo", kind: "echo" });
  assert.equal(duplicate.status, 409);

  const badKind = await json("POST", "/api/functions", { id: "fn-bad", kind: "nope.nope" });
  assert.equal(badKind.status, 400);

  const fetched = await json("GET", "/api/functions/fn-http-echo");
  assert.equal(fetched.status, 200);
  assert.equal(fetched.body?.["name"], "HTTP echo");

  const patched = await json("PATCH", "/api/functions/fn-http-echo", { name: "HTTP echo v2" });
  assert.equal(patched.status, 200);
  assert.equal(patched.body?.["name"], "HTTP echo v2");

  const removed = await json("DELETE", "/api/functions/fn-http-echo");
  assert.equal(removed.status, 200);
  const gone = await json("GET", "/api/functions/fn-http-echo");
  assert.equal(gone.status, 404);
});

test("gates CRUD over HTTP", async () => {
  const created = await json("POST", "/api/gates", {
    id: "gate-http",
    name: "HTTP gate",
    policy: "advisory",
    trigger: { events: ["issue_comment"] },
    functions: ["fn-log-start"],
  });
  assert.equal(created.status, 201);
  const fetched = await json("GET", "/api/gates/gate-http");
  assert.equal(fetched.status, 200);
  const removed = await json("DELETE", "/api/gates/gate-http");
  assert.equal(removed.status, 200);
});

test("POST /api/events runs matching gates (JSON interface)", async () => {
  const result = await json("POST", "/api/events", {
    type: "push",
    ref: "refs/heads/main",
    payload: {},
  });
  assert.equal(result.status, 200);
  assert.equal(result.body?.["ok"], true);
  const outcomes = result.body?.["outcomes"] as { gateId: string; status: string }[];
  assert.equal(outcomes.length, 1);
  assert.equal(outcomes[0]?.gateId, "gate-ci-blocking");
  assert.equal(outcomes[0]?.status, "success");
});

test("POST /api/events accepts X-GitHub-Event webhooks", async () => {
  const result = await json(
    "POST",
    "/api/events",
    {
      ref: "refs/heads/main",
      repository: { full_name: "camillanapoles/llm-arena-opencli" },
      sender: { login: "octocat" },
    },
    { "X-GitHub-Event": "push" },
  );
  assert.equal(result.status, 200);
  const event = result.body?.["event"] as { type: string; repo: string };
  assert.equal(event.type, "push");
  assert.equal(event.repo, "camillanapoles/llm-arena-opencli");
});

test("runs and cache endpoints", async () => {
  const runs = await json("GET", "/api/runs?gateId=gate-ci-blocking");
  assert.equal(runs.status, 200);
  const items = runs.body?.["items"] as unknown[];
  assert.ok(items.length > 0);

  const put = await json("PUT", "/api/cache/web-key", { value: { v: 1 }, ttlMs: 60_000 });
  assert.equal(put.status, 200);
  const read = await json("GET", "/api/cache/web-key");
  assert.equal(read.status, 200);
  assert.deepEqual(read.body?.["value"], { v: 1 });
  const drop = await json("DELETE", "/api/cache/web-key");
  assert.equal(drop.status, 200);
  const missing = await json("GET", "/api/cache/web-key");
  assert.equal(missing.status, 404);

  const stats = await json("GET", "/api/cache/stats");
  assert.equal(stats.status, 200);
});

test("POST /api/opencli/run returns 202 and a manifest", async () => {
  const result = await json("POST", "/api/opencli/run", {
    command: "open",
    url: "https://arena.ai/agent",
  });
  assert.equal(result.status, 202);
  assert.equal(result.body?.["ok"], true);
  const manifest = result.body?.["manifest"] as { command: string };
  assert.equal(manifest.command, "open");
});

test("unknown routes 404, CORS headers present", async () => {
  const result = await fetch(`${base}/nope`);
  assert.equal(result.status, 404);
  assert.equal(result.headers.get("access-control-allow-origin"), "*");
});
