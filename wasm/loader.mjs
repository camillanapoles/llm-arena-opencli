/**
 * Web loader for the arena runtime WASM core — the piece meant to run inside
 * a browser page (e.g. embedded at arena.ai/agent).
 *
 * WASM best practices enforced here:
 *  - Validate the `\0asm` magic before instantiating.
 *  - Prefer `WebAssembly.instantiateStreaming` (compile while downloading),
 *    fall back to `compile` + `instantiate` for non-streaming sources.
 *  - Compile/instantiate are separated so the compiled module can be cached.
 *  - All byte crossing uses the exported scratch region with explicit
 *    lengths — no implicit string marshalling, no `eval`, no `Function`.
 *  - Views over `memory.buffer` are re-created after every call (memory.grow
 *    detaches old buffers).
 *  - The returned API is frozen — no accidental monkey-patching of the gate
 *    decision surface used by the web gate UI.
 */

const WASM_MAGIC = [0x00, 0x61, 0x73, 0x6d];

export function assertWasmMagic(bytes) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const ok = WASM_MAGIC.every((byte, i) => view[i] === byte);
  if (!ok) {
    throw new Error("arena-runtime: not a WebAssembly module (bad magic)");
  }
}

async function compileFrom(source) {
  if (typeof source === "string" || source instanceof URL) {
    const response = await fetch(source);
    if (!response.ok) {
      throw new Error(`arena-runtime: fetch failed with ${response.status}`);
    }
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        const { module, instance } = await WebAssembly.instantiateStreaming(response.clone(), {});
        return { module, instance };
      } catch {
        // MIME type not application/wasm — fall through to ArrayBuffer path.
      }
    }
    const bytes = await response.arrayBuffer();
    assertWasmMagic(bytes);
    const module = await WebAssembly.compile(bytes);
    return { module, instance: await WebAssembly.instantiate(module, {}) };
  }

  // Raw bytes (Node fs, ArrayBuffer, Uint8Array).
  const bytes = source instanceof Uint8Array ? source : new Uint8Array(source);
  assertWasmMagic(bytes);
  const module = await WebAssembly.compile(bytes);
  return { module, instance: await WebAssembly.instantiate(module, {}) };
}

const EVENT_TYPES = [
  "push",
  "pull_request",
  "workflow_dispatch",
  "workflow_run",
  "repository_dispatch",
  "issue_comment",
  "schedule",
  "release",
  "manual",
];

/** Stable bitmask for gate event types (shared with src/core/types.ts order). */
export function maskFromTypes(types) {
  let mask = 0;
  for (const type of types) {
    const index = EVENT_TYPES.indexOf(type);
    if (index >= 0) mask |= 1 << index;
  }
  return mask >>> 0;
}

export function hashString(runtime, text) {
  const bytes = new TextEncoder().encode(text);
  const scratch = runtime.scratchPtr();
  const capacity = runtime.scratchSize();
  if (bytes.length > capacity) {
    throw new Error(`arena-runtime: input too large for scratch buffer (${bytes.length} > ${capacity})`);
  }
  new Uint8Array(runtime.memory.buffer, scratch, capacity).set(bytes);
  return runtime.fnv1a(scratch, bytes.length);
}

/**
 * Load and wrap the arena runtime.
 * Accepts a URL/fetchable path or raw wasm bytes.
 */
export async function loadArenaRuntime(source) {
  const { module, instance } = await compileFrom(source);
  const exports = instance.exports;

  for (const name of ["fnv1a", "gateMatch", "evaluateGate", "cacheEvictScore", "combineHash", "scratchPtr", "scratchSize"]) {
    if (typeof exports[name] !== "function") {
      throw new Error(`arena-runtime: missing export "${name}"`);
    }
  }

  const runtime = {
    module,
    instance,
    memory: exports.memory,
    scratchPtr: exports.scratchPtr,
    scratchSize: exports.scratchSize,
    // u32 returns cross the wasm boundary as signed i32 — normalize to
    // unsigned so JS sees the same values the tests/vectors expect.
    fnv1a: (ptr, len) => exports.fnv1a(ptr, len) >>> 0,
    gateMatch: (eventMask, triggerMask) => exports.gateMatch(eventMask, triggerMask) >>> 0,
    evaluateGate: exports.evaluateGate,
    cacheEvictScore: exports.cacheEvictScore,
    combineHash: (a, b) => exports.combineHash(a, b) >>> 0,
    maskFromTypes,
    hashString: (text) => hashString(runtime, text),
  };

  return Object.freeze(runtime);
}
