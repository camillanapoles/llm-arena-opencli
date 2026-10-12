/**
 * Shared domain types for the OpenCLI Arena Driver.
 *
 * The driver models GitHub Actions "gate events" (workflow triggers) as the
 * input of a gate-driven CI/CD pipeline. A Gate matches events, runs a list of
 * runtime functions created through the FunctionFactory, and records Runs in
 * SQLite.
 */

export const GATE_EVENT_TYPES = [
  "push",
  "pull_request",
  "workflow_dispatch",
  "workflow_run",
  "repository_dispatch",
  "issue_comment",
  "schedule",
  "release",
  "manual",
] as const;

export type GateEventType = (typeof GATE_EVENT_TYPES)[number];

export interface GateEvent {
  id: string;
  type: GateEventType;
  repo: string;
  ref?: string | undefined;
  actor?: string | undefined;
  payload: Record<string, unknown>;
  receivedAt: string;
}

export const RUN_STATUSES = ["pending", "running", "success", "failure", "skipped"] as const;
export type RunStatus = (typeof RUN_STATUSES)[number];

export const GATE_POLICIES = ["blocking", "advisory"] as const;
export type GatePolicy = (typeof GATE_POLICIES)[number];

export interface GateTrigger {
  /** Event types that fire this gate. Empty = never matches. */
  events: GateEventType[];
  /** Optional ref prefixes (e.g. "refs/heads/main"). Empty = any ref. */
  refs?: string[];
  /** Optional actor allow-list. Empty = any actor. */
  actorAllow?: string[];
}

export interface GateDefinition {
  id: string;
  name: string;
  policy: GatePolicy;
  trigger: GateTrigger;
  /** Ordered ids of FunctionSpec rows executed by this gate. */
  functions: string[];
  enabled: boolean;
}

export interface FunctionSpec {
  id: string;
  name: string;
  /** Blueprint kind resolved by the FunctionFactory (e.g. "opencli.dispatch"). */
  kind: string;
  params: Record<string, unknown>;
  cacheTtlMs: number;
  enabled: boolean;
}

export interface RunStep {
  functionId: string;
  kind: string;
  status: RunStatus;
  output: unknown;
  error: string | null;
  durationMs: number;
}

export interface RunRecord {
  id: string;
  gateId: string;
  eventId: string;
  status: RunStatus;
  steps: RunStep[];
  startedAt: string;
  finishedAt: string | null;
}
