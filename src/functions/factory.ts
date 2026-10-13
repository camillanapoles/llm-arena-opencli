/**
 * FunctionFactory — factory pattern for creating runtime functions.
 *
 * A `FunctionBlueprint` describes one *kind* of function (e.g.
 * "opencli.dispatch"). The factory holds the registry of blueprints and
 * materializes executable `RuntimeFunction` instances from persisted
 * `FunctionSpec` rows — so CRUD-created functions are created *through the
 * factory*, never with ad-hoc `eval` or string code.
 */

import type { FunctionSpec } from "../core/types.ts";
import type { ArenaCache } from "../cache/cache.ts";
import type { Database } from "../db/database.ts";
import type { GitHubActionsDriver } from "../drivers/github-actions.driver.ts";

export interface FunctionResult {
  ok: boolean;
  output: unknown;
  error: string | null;
}

export interface RuntimeContext {
  cache: ArenaCache;
  db: Database;
  log: (message: string) => void;
  actions: GitHubActionsDriver | null;
  event: Record<string, unknown>;
}

export interface RuntimeFunction {
  readonly spec: FunctionSpec;
  readonly kind: string;
  execute(input: Record<string, unknown>, ctx: RuntimeContext): Promise<FunctionResult>;
}

export interface FunctionBlueprint {
  kind: string;
  description: string;
  create(spec: FunctionSpec): RuntimeFunction;
}

export class UnknownKindError extends Error {
  constructor(kind: string, known: string[]) {
    super(`Unknown function kind "${kind}". Known kinds: ${known.join(", ")}`);
    this.name = "UnknownKindError";
  }
}

export class FunctionFactory {
  private readonly blueprints = new Map<string, FunctionBlueprint>();

  register(blueprint: FunctionBlueprint): void {
    this.blueprints.set(blueprint.kind, blueprint);
  }

  kinds(): string[] {
    return [...this.blueprints.keys()].sort();
  }

  describe(): { kind: string; description: string }[] {
    return this.kinds().map((kind) => {
      const bp = this.blueprints.get(kind);
      return { kind, description: bp?.description ?? "" };
    });
  }

  has(kind: string): boolean {
    return this.blueprints.has(kind);
  }

  /** Materialize a RuntimeFunction from a CRUD-managed spec. */
  create(spec: FunctionSpec): RuntimeFunction {
    const blueprint = this.blueprints.get(spec.kind);
    if (blueprint === undefined) {
      throw new UnknownKindError(spec.kind, this.kinds());
    }
    return blueprint.create(spec);
  }
}

/** Helper used by blueprints to build simple synchronous/async functions. */
export function defineFunction(
  spec: FunctionSpec,
  kind: string,
  run: (input: Record<string, unknown>, ctx: RuntimeContext) => Promise<unknown>,
): RuntimeFunction {
  return {
    spec,
    kind,
    async execute(input, ctx) {
      try {
        const output = await run(input, ctx);
        return { ok: true, output, error: null };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { ok: false, output: null, error: message };
      }
    },
  };
}
