/**
 * GateDriver — the gate/trigger engine.
 *
 * `receive(event)` finds every gate whose trigger matches the event, executes
 * each gate's function pipeline (functions created through the FunctionFactory
 * from CRUD specs), records runs in SQLite and caches the last decision.
 *
 * Policy semantics:
 *  - `blocking` gates make `receive` fail when their run fails (red gate).
 *  - `advisory` gates record their outcome but never fail the driver.
 */

import { randomUUID } from "node:crypto";
import type {
  GateDefinition,
  GateEvent,
  RunRecord,
  RunStep,
  RunStatus,
} from "../core/types.ts";
import type { ArenaCache } from "../cache/cache.ts";
import type { Database } from "../db/database.ts";
import type { EventsRepo, FunctionsRepo, GatesRepo, RunsRepo } from "../crud/repos.ts";
import type { FunctionFactory, RuntimeContext } from "../functions/factory.ts";
import type { GitHubActionsDriver } from "../drivers/github-actions.driver.ts";
import { matchesTrigger } from "./events.ts";

export interface GateDriverDeps {
  db: Database;
  cache: ArenaCache;
  gates: GatesRepo;
  functions: FunctionsRepo;
  runs: RunsRepo;
  events: EventsRepo;
  factory: FunctionFactory;
  actions?: GitHubActionsDriver | undefined;
  log?: (message: string) => void;
}

export interface GateRunOutcome {
  gate: GateDefinition;
  run: RunRecord;
  blocking: boolean;
}

export interface DriverResult {
  event: GateEvent;
  outcomes: GateRunOutcome[];
  ok: boolean;
}

export class GateDriver {
  private readonly deps: GateDriverDeps;

  constructor(deps: GateDriverDeps) {
    this.deps = deps;
  }

  /** Ingest one gate event and execute all matching gates. */
  async receive(event: GateEvent): Promise<DriverResult> {
    this.deps.events.create(event);
    const gates = this.deps.gates.list().filter((gate) => gate.enabled && matchesTrigger(gate.trigger, event));
    const outcomes: GateRunOutcome[] = [];
    for (const gate of gates) {
      outcomes.push(await this.runGate(gate, event));
    }
    const ok = outcomes.every((outcome) => !outcome.blocking || outcome.run.status === "success");
    return { event, outcomes, ok };
  }

  /** Execute a single gate for a single event. */
  async runGate(gate: GateDefinition, event: GateEvent): Promise<GateRunOutcome> {
    const run: RunRecord = {
      id: randomUUID(),
      gateId: gate.id,
      eventId: event.id,
      status: "running",
      steps: [],
      startedAt: new Date().toISOString(),
      finishedAt: null,
    };
    this.deps.runs.create(run);

    const ctx: RuntimeContext = {
      cache: this.deps.cache,
      db: this.deps.db,
      log: (message: string) => {
        (this.deps.log ?? console.log)(`[gate:${gate.id}] ${message}`);
      },
      actions: this.deps.actions ?? null,
      event: event.payload,
    };

    let failed = false;
    for (const functionId of gate.functions) {
      const step = await this.runStep(functionId, ctx);
      run.steps.push(step);
      if (step.status === "failure") failed = true;
    }

    run.status = (failed ? "failure" : "success") satisfies RunStatus;
    run.finishedAt = new Date().toISOString();
    this.deps.runs.update(run.id, { status: run.status, steps: run.steps, finishedAt: run.finishedAt });

    this.deps.cache.set(`gate:${gate.id}:last`, {
      runId: run.id,
      status: run.status,
      eventId: event.id,
      at: run.finishedAt,
    }, 300_000);

    return { gate, run, blocking: gate.policy === "blocking" };
  }

  private async runStep(functionId: string, ctx: RuntimeContext): Promise<RunStep> {
    const started = Date.now();
    const spec = this.deps.functions.get(functionId);
    if (spec === undefined) {
      return {
        functionId,
        kind: "missing",
        status: "failure",
        output: null,
        error: `FunctionSpec "${functionId}" not found`,
        durationMs: Date.now() - started,
      };
    }
    if (!spec.enabled) {
      return {
        functionId,
        kind: spec.kind,
        status: "skipped",
        output: null,
        error: null,
        durationMs: Date.now() - started,
      };
    }
    try {
      const fn = this.deps.factory.create(spec);
      const result = await fn.execute({}, ctx);
      return {
        functionId,
        kind: spec.kind,
        status: result.ok ? "success" : "failure",
        output: result.output,
        error: result.error,
        durationMs: Date.now() - started,
      };
    } catch (err) {
      return {
        functionId,
        kind: spec.kind,
        status: "failure",
        output: null,
        error: err instanceof Error ? err.message : String(err),
        durationMs: Date.now() - started,
      };
    }
  }
}
