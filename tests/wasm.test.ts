import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadArenaRuntime, maskFromTypes, assertWasmMagic } from "../wasm/loader.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const wasmPath = join(here, "..", "wasm", "dist", "arena-runtime.wasm");

test("wasm artifact exists (run `npm run build:wasm` first)", () => {
  assert.ok(existsSync(wasmPath), `missing ${wasmPath}`);
});

test("loader rejects non-wasm bytes", () => {
  assert.throws(() => assertWasmMagic(new Uint8Array([1, 2, 3, 4])), /bad magic/);
});

test("maskFromTypes is stable and ordered as GATE_EVENT_TYPES", () => {
  assert.equal(maskFromTypes(["push"]), 1);
  assert.equal(maskFromTypes(["pull_request"]), 2);
  assert.equal(maskFromTypes(["push", "manual"]), (1 | 1 << 8) >>> 0);
  assert.equal(maskFromTypes(["not-an-event"]), 0);
});

test("runtime: fnv1a hashes UTF-8 bytes via the scratch buffer", async () => {
  const bytes = await readFile(wasmPath);
  const rt = await loadArenaRuntime(bytes);
  // FNV-1a 32-bit of "a" is a well-known vector.
  assert.equal(rt.hashString("a"), 0xe40c292c);
  assert.equal(rt.hashString(""), 2166136261);
  assert.equal(rt.hashString("hello"), rt.hashString("hello"));
  assert.notEqual(rt.hashString("hello"), rt.hashString("hellp"));
});

test("runtime: gateMatch and evaluateGate mirror the TS trigger logic", async () => {
  const bytes = await readFile(wasmPath);
  const rt = await loadArenaRuntime(bytes);
  const push = maskFromTypes(["push"]);
  const pushPr = maskFromTypes(["push", "pull_request"]);
  const schedule = maskFromTypes(["schedule"]);

  assert.equal(rt.gateMatch(push, pushPr), 1);
  assert.equal(rt.gateMatch(schedule, pushPr), 0);

  // No ref/actor constraints -> fires on event overlap only.
  assert.equal(rt.evaluateGate(push, pushPr, 0, 0, 0, 0, 0, 0), 1);
  assert.equal(rt.evaluateGate(schedule, pushPr, 0, 0, 0, 0, 0, 0), 0);

  // Ref constraint enforced via hashes.
  const refMain = rt.hashString("refs/heads/main");
  const refDev = rt.hashString("refs/heads/dev");
  assert.equal(rt.evaluateGate(push, pushPr, 1, refMain, refMain, 0, 0, 0), 1);
  assert.equal(rt.evaluateGate(push, pushPr, 1, refMain, refDev, 0, 0, 0), 0);

  // Actor constraint enforced via hashes.
  const actor = rt.hashString("octocat");
  assert.equal(rt.evaluateGate(push, pushPr, 0, 0, 0, 1, actor, actor), 1);
  assert.equal(rt.evaluateGate(push, pushPr, 0, 0, 0, 1, actor, rt.hashString("mallory")), 0);
});

test("runtime: cacheEvictScore ranks expired entries first", async () => {
  const bytes = await readFile(wasmPath);
  const rt = await loadArenaRuntime(bytes);
  const fresh = rt.cacheEvictScore(10, 1000, 5);
  const stale = rt.cacheEvictScore(900, 1000, 5);
  const expired = rt.cacheEvictScore(1500, 1000, 5);
  assert.ok(stale > fresh);
  assert.ok(expired > stale);
});

test("runtime: combineHash is deterministic", async () => {
  const bytes = await readFile(wasmPath);
  const rt = await loadArenaRuntime(bytes);
  const a = rt.hashString("gate");
  const b = rt.hashString("event");
  assert.equal(rt.combineHash(a, b), rt.combineHash(a, b));
  assert.notEqual(rt.combineHash(a, b), rt.combineHash(b, a));
});
