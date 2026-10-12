/**
 * Gate event model: normalizes GitHub webhook/Actions payloads (and manual
 * triggers) into `GateEvent`, and matches them against gate triggers.
 */

import { randomUUID } from "node:crypto";
import type { GateEvent, GateEventType, GateTrigger } from "../core/types.ts";
import { GATE_EVENT_TYPES } from "../core/types.ts";

export function isGateEventType(value: string): value is GateEventType {
  return (GATE_EVENT_TYPES as readonly string[]).includes(value);
}

export interface NormalizeOptions {
  type: string;
  repo?: string | undefined;
  ref?: string | undefined;
  actor?: string | undefined;
  payload?: Record<string, unknown> | undefined;
  now?: () => Date;
}

export function normalizeEvent(options: NormalizeOptions): GateEvent {
  const type = isGateEventType(options.type) ? options.type : "manual";
  const payload = options.payload ?? {};
  const now = options.now ?? (() => new Date());

  let repo = options.repo ?? "";
  if (repo === "") {
    const repository = payload["repository"];
    if (repository !== null && typeof repository === "object") {
      repo = String((repository as Record<string, unknown>)["full_name"] ?? "");
    }
  }
  if (repo === "") repo = process.env["GITHUB_REPOSITORY"] ?? "";
  if (repo === "") repo = "local/local";

  let ref = options.ref ?? "";
  if (ref === "" && typeof payload["ref"] === "string") ref = payload["ref"];

  let actor = options.actor ?? "";
  if (actor === "") {
    const sender = payload["sender"];
    if (sender !== null && typeof sender === "object") {
      actor = String((sender as Record<string, unknown>)["login"] ?? "");
    }
  }
  if (actor === "") actor = process.env["GITHUB_ACTOR"] ?? "";
  if (actor === "") actor = "local";

  return {
    id: randomUUID(),
    type,
    repo,
    ref: ref === "" ? undefined : ref,
    actor: actor === "" ? undefined : actor,
    payload,
    receivedAt: now().toISOString(),
  };
}

/**
 * Parse the raw body of a GitHub webhook using the X-GitHub-Event header.
 * Used by the backend's POST /api/events endpoint. The header value is the
 * gate event type (`push`, `pull_request`, `repository_dispatch`, ...); finer
 * distinctions such as `event_type` stay inside the payload for gate
 * functions to read.
 */
export function parseWebhook(
  githubEventHeader: string,
  body: Record<string, unknown>,
): GateEvent {
  return normalizeEvent({
    type: githubEventHeader,
    payload: body,
  });
}

function matchesRef(trigger: GateTrigger, ref: string | undefined): boolean {
  const prefixes = trigger.refs ?? [];
  if (prefixes.length === 0) return true;
  if (ref === undefined) return false;
  return prefixes.some((prefix) => ref.startsWith(prefix));
}

function matchesActor(trigger: GateTrigger, actor: string | undefined): boolean {
  const allow = trigger.actorAllow ?? [];
  if (allow.length === 0) return true;
  if (actor === undefined) return false;
  return allow.includes(actor);
}

/** Does this gate trigger fire for this event? */
export function matchesTrigger(trigger: GateTrigger, event: GateEvent): boolean {
  return (
    trigger.events.includes(event.type) &&
    matchesRef(trigger, event.ref) &&
    matchesActor(trigger, event.actor)
  );
}
