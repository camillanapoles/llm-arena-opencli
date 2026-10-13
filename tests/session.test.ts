import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionStore, defaultState } from "../src/session/store.ts";

function tempRoot(): string {
  return mkdtempSync(join(tmpdir(), "arena-session-"));
}

test("read() falls back to defaults when state file is missing", () => {
  const root = tempRoot();
  try {
    const store = new SessionStore(root);
    const state = store.read();
    assert.equal(state.sessionId, defaultState().sessionId);
    assert.equal(state.status, "active");
    assert.deepEqual(state.checkpoints, []);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("write/read round-trip preserves state", () => {
  const root = tempRoot();
  try {
    const store = new SessionStore(root);
    const state = defaultState();
    state.branch = "arena/continuity-20261013-120000";
    state.pr = 2;
    state.status = "continuity";
    state.nextActions = ["a", "b"];
    store.write(state);
    const readBack = store.read();
    assert.equal(readBack.branch, "arena/continuity-20261013-120000");
    assert.equal(readBack.pr, 2);
    assert.equal(readBack.status, "continuity");
    assert.deepEqual(readBack.nextActions, ["a", "b"]);
    // file is valid JSON with trailing newline
    const raw = readFileSync(store.statePath, "utf8");
    assert.ok(raw.endsWith("\n"));
    JSON.parse(raw);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("checkpoint appends entries with timestamps", () => {
  const root = tempRoot();
  try {
    const store = new SessionStore(root);
    store.checkpoint({ note: "primeiro", event: "manual", sha: "abc" });
    const state = store.checkpoint({ note: "segundo", event: "push" });
    assert.equal(state.checkpoints.length, 2);
    assert.equal(state.checkpoints[0]?.note, "primeiro");
    assert.equal(state.checkpoints[1]?.note, "segundo");
    assert.equal(state.checkpoints[1]?.event, "push");
    assert.ok(state.checkpoints[0]?.at);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("checkpoints are capped at 50 (oldest dropped)", () => {
  const root = tempRoot();
  try {
    const store = new SessionStore(root);
    for (let i = 0; i < 60; i += 1) {
      store.checkpoint({ note: `cp-${i}` });
    }
    const state = store.read();
    assert.equal(state.checkpoints.length, 50);
    assert.equal(state.checkpoints[0]?.note, "cp-10");
    assert.equal(state.checkpoints[49]?.note, "cp-59");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("corrupted state file degrades to defaults", () => {
  const root = tempRoot();
  try {
    const store = new SessionStore(root);
    mkdirSync(join(root, "session"), { recursive: true });
    writeFileSync(store.statePath, "{ not json !!!", "utf8");
    const state = store.read();
    assert.equal(state.sessionId, defaultState().sessionId);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("suggestBranchName is stable, unique and in the arena/* namespace", () => {
  const store = new SessionStore(tempRoot());
  const d1 = new Date("2026-10-13T12:34:56.000Z");
  const d2 = new Date("2026-10-13T12:34:57.000Z");
  const n1 = store.suggestBranchName(d1);
  const n2 = store.suggestBranchName(d2);
  assert.match(n1, /^arena\/continuity-\d{8}-\d{6}$/);
  assert.notEqual(n1, n2);
});

test("resumeBriefing surfaces session, checkpoints, next actions and resume paths", () => {
  const root = tempRoot();
  try {
    const store = new SessionStore(root);
    store.checkpoint({ note: "driver implementado", event: "session-bootstrap", sha: "70d10f4" });
    store.setNextActions(["mesclar PR #1", "configurar OPENCLI_TOKEN"]);
    store.setStatus("continuity");
    const briefing = store.resumeBriefing();
    assert.match(briefing, /Session resume briefing/);
    assert.match(briefing, /driver implementado/);
    assert.match(briefing, /mesclar PR #1/);
    assert.match(briefing, /status.*continuity/);
    assert.match(briefing, /session\/CONTEXT\.md/);
    assert.match(briefing, /\/session continue/);
    assert.match(briefing, /session-continue/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("setStatus updates persisted status", () => {
  const root = tempRoot();
  try {
    const store = new SessionStore(root);
    store.write(defaultState());
    store.setStatus("merged");
    assert.equal(store.read().status, "merged");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
