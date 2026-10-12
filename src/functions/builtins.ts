/**
 * Built-in function blueprints.
 *
 * These are the building blocks gates compose. New kinds are added by
 * registering another blueprint on the factory — open/closed for extension.
 */

import type { FunctionSpec } from "../core/types.ts";
import {
  defineFunction,
  FunctionFactory,
  type FunctionBlueprint,
  type RuntimeContext,
} from "./factory.ts";
import { toJson } from "../db/database.ts";

function param(spec: FunctionSpec, key: string, fallback = ""): string {
  const value = spec.params[key];
  return value == null ? fallback : String(value);
}

export const echoBlueprint: FunctionBlueprint = {
  kind: "echo",
  description: "Returns its input unchanged (smoke/debug function).",
  create: (spec) =>
    defineFunction(spec, "echo", async (input) => ({ echoed: input, spec: spec.id })),
};

export const cacheGetBlueprint: FunctionBlueprint = {
  kind: "cache.get",
  description: "Reads a value from the arena cache. Input: { key }.",
  create: (spec) =>
    defineFunction(spec, "cache.get", async (input, ctx: RuntimeContext) => {
      const key = String(input["key"] ?? param(spec, "key"));
      if (key === "") throw new Error("cache.get: missing key");
      return { key, value: ctx.cache.get(key), hit: ctx.cache.get(key) !== undefined };
    }),
};

export const cachePutBlueprint: FunctionBlueprint = {
  kind: "cache.put",
  description: "Writes a value into the arena cache. Input: { key, value, ttlMs? }.",
  create: (spec) =>
    defineFunction(spec, "cache.put", async (input, ctx: RuntimeContext) => {
      const key = String(input["key"] ?? param(spec, "key"));
      if (key === "") throw new Error("cache.put: missing key");
      const ttlRaw = input["ttlMs"] ?? spec.cacheTtlMs;
      const ttlMs = Number(ttlRaw ?? 0);
      ctx.cache.set(key, input["value"] ?? null, Number.isFinite(ttlMs) ? ttlMs : undefined);
      return { key, stored: true };
    }),
};

export const sqlQueryBlueprint: FunctionBlueprint = {
  kind: "sql.query",
  description: "Runs a read-only SQL SELECT. Params: { sql, params? }.",
  create: (spec) =>
    defineFunction(spec, "sql.query", async (input, ctx: RuntimeContext) => {
      const sql = String(input["sql"] ?? param(spec, "sql"));
      if (!/^\s*select/i.test(sql)) {
        throw new Error("sql.query: only SELECT statements are allowed");
      }
      const rawParams = (input["params"] as unknown[] | undefined) ?? [];
      const values = rawParams.map((v) => (v == null ? null : (typeof v === "object" ? toJson(v) : (v as string | number))));
      return ctx.db.query(sql, ...values);
    }),
};

export const githubEventBlueprint: FunctionBlueprint = {
  kind: "github.event",
  description: "Extracts a field from the triggering gate event payload. Params: { path }.",
  create: (spec) =>
    defineFunction(spec, "github.event", async (input, ctx: RuntimeContext) => {
      const path = String(input["path"] ?? param(spec, "path"));
      let current: unknown = ctx.event;
      for (const segment of path.split(".").filter((s) => s !== "")) {
        if (current == null || typeof current !== "object") return undefined;
        current = (current as Record<string, unknown>)[segment];
      }
      return current;
    }),
};

export const opencliDispatchBlueprint: FunctionBlueprint = {
  kind: "opencli.dispatch",
  description:
    "Dispatches an OpenCLI command to the target repo's GitHub Actions runtime " +
    "(repository_dispatch of type 'opencli-command').",
  create: (spec) =>
    defineFunction(spec, "opencli.dispatch", async (input, ctx: RuntimeContext) => {
      if (ctx.actions === null) {
        throw new Error("opencli.dispatch: no GitHubActionsDriver configured");
      }
      const command = String(input["command"] ?? param(spec, "command"));
      if (command === "") throw new Error("opencli.dispatch: missing command");
      const payload = {
        command,
        url: String(input["url"] ?? param(spec, "url")),
        args: (input["args"] as unknown[] | undefined) ?? [],
        client_payload: input["clientPayload"] ?? {},
      };
      await ctx.actions.dispatchRepositoryDispatch("opencli-command", payload);
      return { dispatched: true, command };
    }),
};

export const logBlueprint: FunctionBlueprint = {
  kind: "log",
  description: "Appends a message to the run log. Input: { message }.",
  create: (spec) =>
    defineFunction(spec, "log", async (input, ctx: RuntimeContext) => {
      const message = String(input["message"] ?? param(spec, "message", "(empty)"));
      ctx.log(message);
      return { logged: message };
    }),
};

/** All built-in blueprints, ready to register on a factory. */
export function builtinBlueprints(): FunctionBlueprint[] {
  return [
    echoBlueprint,
    cacheGetBlueprint,
    cachePutBlueprint,
    sqlQueryBlueprint,
    githubEventBlueprint,
    opencliDispatchBlueprint,
    logBlueprint,
  ];
}

/** A factory pre-loaded with every built-in blueprint. */
export function createDefaultFactory(): FunctionFactory {
  const factory = new FunctionFactory();
  for (const bp of builtinBlueprints()) factory.register(bp);
  return factory;
}
