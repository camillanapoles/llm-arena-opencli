/**
 * HTTP backend for the arena driver.
 *
 * REST CRUD over functions/gates/runs/events + gate-event ingestion + cache
 * introspection + direct OpenCLI dispatch. Implemented on `node:http` so the
 * runtime has zero production dependencies (Actions-runner friendly).
 *
 * Handler contract: return a JSON value -> 200 with that body; call
 * `reply(ctx, status, payload)` for any other status (then return undefined).
 *
 * CORS: arena.ai/agent web pages call this API cross-origin, so the
 * allowlist is configurable (ARENA_CORS_ORIGIN, default "*").
 */

import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { App } from "./app.ts";
import { normalizeEvent, parseWebhook } from "./gate/events.ts";
import { verifyWebhookSignature } from "./gate/webhook.ts";
import type { GateEventType, GatePolicy, GateTrigger } from "./core/types.ts";

type Json = Record<string, unknown> | unknown[] | string | number | boolean | null;

interface RouteContext {
  req: IncomingMessage;
  res: ServerResponse;
  body: Json;
  /** corpo cru (bytes exatos) — necessário ao HMAC do webhook real */
  rawBody: string;
  params: Record<string, string>;
}

type Handler = (ctx: RouteContext, app: App) => Promise<Json | void> | Json | void;

interface Route {
  method: string;
  pattern: string;
  handler: Handler;
}

export function corsOrigin(): string {
  return process.env["ARENA_CORS_ORIGIN"] ?? "*";
}

function sendJson(res: ServerResponse, status: number, payload: Json, cors: string): void {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": cors,
    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers":
      "Content-Type, X-GitHub-Event, X-Hub-Signature-256, Authorization",
  });
  res.end(JSON.stringify(payload));
}

function reply(ctx: RouteContext, status: number, payload: Json): void {
  sendJson(ctx.res, status, payload, corsOrigin());
}

async function readBody(req: IncomingMessage): Promise<{ parsed: Json; raw: string }> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const raw = Buffer.concat(chunks).toString("utf8");
  if (chunks.length === 0 || raw.trim() === "") return { parsed: {}, raw };
  try {
    return { parsed: JSON.parse(raw) as Json, raw };
  } catch {
    return { parsed: { _raw: raw }, raw };
  }
}

function match(pattern: string, path: string): Record<string, string> | null {
  const patternParts = pattern.split("/").filter((p) => p !== "");
  const pathParts = path.split("/").filter((p) => p !== "");
  if (patternParts.length !== pathParts.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < patternParts.length; i += 1) {
    const pp = patternParts[i] as string;
    const vp = pathParts[i] as string;
    if (pp.startsWith(":")) {
      params[pp.slice(1)] = decodeURIComponent(vp);
    } else if (pp !== vp) {
      return null;
    }
  }
  return params;
}

const routes: Route[] = [
  {
    method: "GET",
    pattern: "/health",
    handler: (_ctx, app) => ({
      status: "ok",
      functions: app.functions.count(),
      gates: app.gates.count(),
      runs: app.runs.count(),
    }),
  },
  {
    method: "GET",
    pattern: "/api/kinds",
    handler: (_ctx, app) => ({ kinds: app.factory.describe() }),
  },

  // ------------------------------------------------------------- functions
  {
    method: "GET",
    pattern: "/api/functions",
    handler: (_ctx, app) => ({ items: app.functions.list() }),
  },
  {
    method: "POST",
    pattern: "/api/functions",
    handler: (ctx, app) => {
      const body = ctx.body as Record<string, unknown>;
      const id = String(body["id"] ?? `fn-${Date.now()}`);
      const kind = String(body["kind"] ?? "echo");
      if (!app.factory.has(kind)) {
        reply(ctx, 400, { error: `unknown function kind "${kind}"`, kinds: app.factory.kinds() });
        return;
      }
      if (app.functions.get(id) !== undefined) {
        reply(ctx, 409, { error: `function "${id}" already exists` });
        return;
      }
      const spec = {
        id,
        name: String(body["name"] ?? id),
        kind,
        params: (body["params"] as Record<string, unknown>) ?? {},
        cacheTtlMs: Number(body["cacheTtlMs"] ?? 0),
        enabled: body["enabled"] !== false,
      };
      app.functions.create(spec);
      reply(ctx, 201, spec);
    },
  },
  {
    method: "GET",
    pattern: "/api/functions/:id",
    handler: (ctx, app) => {
      const spec = app.functions.get(ctx.params["id"] as string);
      if (spec === undefined) {
        reply(ctx, 404, { error: "not found" });
        return;
      }
      return spec;
    },
  },
  {
    method: "PATCH",
    pattern: "/api/functions/:id",
    handler: (ctx, app) => {
      const updated = app.functions.update(ctx.params["id"] as string, ctx.body as Record<string, unknown>);
      if (updated === undefined) {
        reply(ctx, 404, { error: "not found" });
        return;
      }
      return updated;
    },
  },
  {
    method: "DELETE",
    pattern: "/api/functions/:id",
    handler: (ctx, app) => {
      const removed = app.functions.remove(ctx.params["id"] as string);
      reply(ctx, removed ? 200 : 404, removed ? { removed: true } : { error: "not found" });
    },
  },

  // ----------------------------------------------------------------- gates
  {
    method: "GET",
    pattern: "/api/gates",
    handler: (_ctx, app) => ({ items: app.gates.list() }),
  },
  {
    method: "POST",
    pattern: "/api/gates",
    handler: (ctx, app) => {
      const body = ctx.body as Record<string, unknown>;
      const id = String(body["id"] ?? `gate-${Date.now()}`);
      if (app.gates.get(id) !== undefined) {
        reply(ctx, 409, { error: `gate "${id}" already exists` });
        return;
      }
      const gate = {
        id,
        name: String(body["name"] ?? id),
        policy: (body["policy"] as GatePolicy | undefined) ?? ("blocking" as GatePolicy),
        trigger: (body["trigger"] as GateTrigger | undefined) ?? { events: [] as GateEventType[] },
        functions: (body["functions"] as string[] | undefined) ?? [],
        enabled: body["enabled"] !== false,
      };
      app.gates.create(gate);
      reply(ctx, 201, gate);
    },
  },
  {
    method: "GET",
    pattern: "/api/gates/:id",
    handler: (ctx, app) => {
      const gate = app.gates.get(ctx.params["id"] as string);
      if (gate === undefined) {
        reply(ctx, 404, { error: "not found" });
        return;
      }
      return gate;
    },
  },
  {
    method: "PATCH",
    pattern: "/api/gates/:id",
    handler: (ctx, app) => {
      const updated = app.gates.update(ctx.params["id"] as string, ctx.body as Record<string, unknown>);
      if (updated === undefined) {
        reply(ctx, 404, { error: "not found" });
        return;
      }
      return updated;
    },
  },
  {
    method: "DELETE",
    pattern: "/api/gates/:id",
    handler: (ctx, app) => {
      const removed = app.gates.remove(ctx.params["id"] as string);
      reply(ctx, removed ? 200 : 404, removed ? { removed: true } : { error: "not found" });
    },
  },

  // ------------------------------------------------------------------ runs
  {
    method: "GET",
    pattern: "/api/runs",
    handler: (ctx, app) => {
      const gateId = new URL(ctx.req.url ?? "/api/runs", "http://localhost").searchParams.get("gateId");
      return { items: gateId === null ? app.runs.list() : app.runs.listByGate(gateId) };
    },
  },
  {
    method: "GET",
    pattern: "/api/runs/:id",
    handler: (ctx, app) => {
      const run = app.runs.get(ctx.params["id"] as string);
      if (run === undefined) {
        reply(ctx, 404, { error: "not found" });
        return;
      }
      return run;
    },
  },

  // --------------------------------------------------------------- events
  {
    method: "POST",
    pattern: "/api/events",
    handler: async (ctx, app) => {
      // ---- webhook real: autenticidade por assinatura (X-Hub-Signature-256)
      const secret = app.webhookSecret;
      if (secret !== "") {
        const signature = String(ctx.req.headers["x-hub-signature-256"] ?? "");
        if (!verifyWebhookSignature(secret, ctx.rawBody, signature)) {
          reply(ctx, 401, {
            ok: false,
            error: "assinatura de webhook inválida (X-Hub-Signature-256)",
          });
          return;
        }
      }
      const header = String(ctx.req.headers["x-github-event"] ?? "");
      const body = (ctx.body ?? {}) as Record<string, unknown>;
      // ---- handshake `ping` (entrega de teste do GitHub ao registrar o webhook)
      if (header === "ping") {
        return {
          ok: true,
          pong: true,
          zen: String((body as { zen?: unknown })["zen"] ?? ""),
          hook_id: (body as { hook_id?: unknown })["hook_id"] ?? null,
        };
      }
      const event =
        header !== ""
          ? parseWebhook(header, body)
          : normalizeEvent({
              type: String(body["type"] ?? "manual"),
              repo: body["repo"] as string | undefined,
              ref: body["ref"] as string | undefined,
              actor: body["actor"] as string | undefined,
              payload: (body["payload"] as Record<string, unknown> | undefined) ?? body,
            });
      const result = await app.driver.receive(event);
      reply(ctx, result.ok ? 200 : 422, {
        ok: result.ok,
        event: result.event,
        outcomes: result.outcomes.map((outcome) => ({
          gateId: outcome.gate.id,
          status: outcome.run.status,
          blocking: outcome.blocking,
          runId: outcome.run.id,
          steps: outcome.run.steps,
        })),
      });
    },
  },
  {
    method: "GET",
    pattern: "/api/events",
    handler: (_ctx, app) => ({ items: app.events.list() }),
  },

  // ---------------------------------------------------------------- cache
  {
    method: "GET",
    pattern: "/api/cache/stats",
    handler: (_ctx, app) => ({ stats: app.cache.stats() }),
  },
  {
    method: "GET",
    pattern: "/api/cache/:key",
    handler: (ctx, app) => {
      const value = app.cache.get(ctx.params["key"] as string);
      if (value === undefined) {
        reply(ctx, 404, { error: "not found" });
        return;
      }
      return { key: ctx.params["key"], value };
    },
  },
  {
    method: "PUT",
    pattern: "/api/cache/:key",
    handler: (ctx, app) => {
      const body = ctx.body as Record<string, unknown>;
      const ttlRaw = Number(body["ttlMs"]);
      app.cache.set(
        ctx.params["key"] as string,
        body["value"] ?? null,
        Number.isFinite(ttlRaw) && ttlRaw > 0 ? ttlRaw : undefined,
      );
      reply(ctx, 200, { stored: true });
    },
  },
  {
    method: "DELETE",
    pattern: "/api/cache/:key",
    handler: (ctx, app) => {
      app.cache.delete(ctx.params["key"] as string);
      reply(ctx, 200, { removed: true });
    },
  },

  // ------------------------------------------------------ opencli dispatch
  {
    method: "POST",
    pattern: "/api/opencli/run",
    handler: async (ctx, app) => {
      const body = ctx.body as Record<string, unknown>;
      const result = await app.opencli.run({
        command: String(body["command"] ?? "ping"),
        url: body["url"] as string | undefined,
        args: (body["args"] as string[] | undefined) ?? [],
        clientPayload: (body["clientPayload"] as Record<string, unknown> | undefined) ?? {},
      });
      reply(ctx, result.ok ? 202 : 502, result as unknown as Json);
    },
  },
];

export function createHttpServer(app: App): Server {
  return createServer(async (req, res) => {
    const cors = corsOrigin();
    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "Access-Control-Allow-Origin": cors,
        "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
        "Access-Control-Allow-Headers":
          "Content-Type, X-GitHub-Event, X-Hub-Signature-256, Authorization",
      });
      res.end();
      return;
    }

    const pathname = new URL(req.url ?? "/", "http://localhost").pathname;

    try {
      const empty = { parsed: {} as Json, raw: "" };
      const { parsed: body, raw: rawBody } =
        req.method === "GET" || req.method === "HEAD" ? empty : await readBody(req);
      for (const route of routes) {
        if (route.method !== req.method) continue;
        const params = match(route.pattern, pathname);
        if (params === null) continue;
        const ctx: RouteContext = { req, res, body, rawBody, params };
        const result = await route.handler(ctx, app);
        if (!res.writableEnded) {
          sendJson(res, result === undefined ? 204 : 200, result ?? null, cors);
        }
        return;
      }
      sendJson(res, 404, { error: `no route for ${req.method} ${pathname}` }, cors);
    } catch (err) {
      sendJson(res, 500, { error: err instanceof Error ? err.message : String(err) }, cors);
    }
  });
}
