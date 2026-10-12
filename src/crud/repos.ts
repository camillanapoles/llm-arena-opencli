/**
 * Concrete CRUD repositories for the arena driver's domain entities.
 */

import type { Database } from "../db/database.ts";
import { fromJson, toJson } from "../db/database.ts";
import { CrudRepository } from "./repository.ts";
import type {
  GateDefinition,
  GateEvent,
  GateEventType,
  GatePolicy,
  GateTrigger,
  FunctionSpec,
  RunRecord,
  RunStatus,
  RunStep,
} from "../core/types.ts";

// ---------------------------------------------------------------- functions

export class FunctionsRepo extends CrudRepository<FunctionSpec> {
  constructor(db: Database) {
    super({
      db,
      table: "functions",
      columns: ["id", "name", "kind", "params", "cache_ttl_ms", "enabled"],
      hydrate: (row) => ({
        id: String(row["id"]),
        name: String(row["name"]),
        kind: String(row["kind"]),
        params: fromJson<Record<string, unknown>>(String(row["params"] ?? "{}"), {}),
        cacheTtlMs: Number(row["cache_ttl_ms"] ?? 0),
        enabled: Number(row["enabled"] ?? 1) === 1,
      }),
      serialize: (entity) => ({
        id: entity.id,
        name: entity.name,
        kind: entity.kind,
        params: toJson(entity.params),
        cache_ttl_ms: entity.cacheTtlMs,
        enabled: entity.enabled ? 1 : 0,
      }),
    });
  }

  listEnabled(): FunctionSpec[] {
    return this.list().filter((spec) => spec.enabled);
  }
}

// -------------------------------------------------------------------- gates

export class GatesRepo extends CrudRepository<GateDefinition> {
  constructor(db: Database) {
    super({
      db,
      table: "gates",
      columns: ["id", "name", "policy", "trigger", "functions", "enabled"],
      hydrate: (row) => ({
        id: String(row["id"]),
        name: String(row["name"]),
        policy: String(row["policy"] ?? "blocking") as GatePolicy,
        trigger: fromJson<GateTrigger>(String(row["trigger"] ?? "{}"), { events: [] }),
        functions: fromJson<string[]>(String(row["functions"] ?? "[]"), []),
        enabled: Number(row["enabled"] ?? 1) === 1,
      }),
      serialize: (entity) => ({
        id: entity.id,
        name: entity.name,
        policy: entity.policy,
        trigger: toJson(entity.trigger),
        functions: toJson(entity.functions),
        enabled: entity.enabled ? 1 : 0,
      }),
    });
  }
}

// --------------------------------------------------------------------- runs

export class RunsRepo extends CrudRepository<RunRecord> {
  constructor(db: Database) {
    super({
      db,
      table: "runs",
      columns: ["id", "gate_id", "event_id", "status", "steps", "started_at", "finished_at"],
      hydrate: (row) => ({
        id: String(row["id"]),
        gateId: String(row["gate_id"]),
        eventId: String(row["event_id"]),
        status: String(row["status"]) as RunStatus,
        steps: fromJson<RunStep[]>(String(row["steps"] ?? "[]"), []),
        startedAt: String(row["started_at"]),
        finishedAt: row["finished_at"] == null ? null : String(row["finished_at"]),
      }),
      serialize: (entity) => ({
        id: entity.id,
        gate_id: entity.gateId,
        event_id: entity.eventId,
        status: entity.status,
        steps: toJson(entity.steps),
        started_at: entity.startedAt,
        finished_at: entity.finishedAt ?? "",
      }),
    });
  }

  listByGate(gateId: string, limit = 50): RunRecord[] {
    return this.db
      .query<Record<string, unknown>>(
        "SELECT * FROM runs WHERE gate_id = ? ORDER BY started_at DESC LIMIT ?",
        gateId,
        limit,
      )
      .map((row) => ({
        id: String(row["id"]),
        gateId: String(row["gate_id"]),
        eventId: String(row["event_id"]),
        status: String(row["status"]) as RunStatus,
        steps: fromJson<RunStep[]>(String(row["steps"] ?? "[]"), []),
        startedAt: String(row["started_at"]),
        finishedAt: row["finished_at"] == null ? null : String(row["finished_at"]),
      }));
  }
}

// ------------------------------------------------------------------- events

export class EventsRepo extends CrudRepository<GateEvent> {
  constructor(db: Database) {
    super({
      db,
      table: "events",
      columns: ["id", "type", "repo", "ref", "actor", "payload", "received_at"],
      hydrate: (row) => ({
        id: String(row["id"]),
        type: String(row["type"]) as GateEventType,
        repo: String(row["repo"]),
        ref: row["ref"] == null ? undefined : String(row["ref"]),
        actor: row["actor"] == null ? undefined : String(row["actor"]),
        payload: fromJson<Record<string, unknown>>(String(row["payload"] ?? "{}"), {}),
        receivedAt: String(row["received_at"]),
      }),
      serialize: (entity) => ({
        id: entity.id,
        type: entity.type,
        repo: entity.repo,
        ref: entity.ref ?? "",
        actor: entity.actor ?? "",
        payload: toJson(entity.payload),
        received_at: entity.receivedAt,
      }),
    });
  }
}
