// Arena runtime core — pure compute compiled to WebAssembly.
//
// WASM best practices embodied here:
//  - Pure numeric functions only: no DOM, no syscalls, no hidden I/O.
//  - Explicit host-owned scratch buffer for byte input (no hidden allocation,
//    no string marshalling across the boundary).
//  - Fixed-width integer semantics; every decision is deterministic and
//    testable both in Node and in the browser.
//
// This module is AssemblyScript (a strict TS subset), not regular TypeScript.

const SCRATCH_SIZE: i32 = 4096;
const SCRATCH: usize = memory.data(SCRATCH_SIZE, 8);

/// Pointer to the host-writable scratch region in linear memory.
export function scratchPtr(): i32 {
  return SCRATCH as i32;
}

/// Size in bytes of the scratch region.
export function scratchSize(): i32 {
  return SCRATCH_SIZE;
}

/// FNV-1a 32-bit hash of `len` bytes at `ptr` (cache keys, id shortening).
export function fnv1a(ptr: i32, len: i32): u32 {
  let hash: u32 = 2166136261;
  for (let i: i32 = 0; i < len; i++) {
    hash = hash ^ load<u8>(ptr + i);
    hash = hash * 16777619;
  }
  return hash;
}

/// Bitmask gate match: 1 when any event bit overlaps the trigger bits.
export function gateMatch(eventMask: u32, triggerMask: u32): u32 {
  return (eventMask & triggerMask) != 0 ? 1 : 0;
}

/**
 * Full gate decision mirroring src/gate/events.ts `matchesTrigger`:
 * event bit overlap AND (no ref constraint OR ref hash equal) AND
 * (no actor constraint OR actor hash equal). Returns 1 = fire, 0 = skip.
 */
export function evaluateGate(
  eventMask: u32,
  triggerMask: u32,
  hasRefConstraint: i32,
  refHash: u32,
  eventRefHash: u32,
  hasActorConstraint: i32,
  actorHash: u32,
  eventActorHash: u32,
): i32 {
  if (gateMatch(eventMask, triggerMask) == 0) return 0;
  if (hasRefConstraint != 0 && refHash != eventRefHash) return 0;
  if (hasActorConstraint != 0 && actorHash != eventActorHash) return 0;
  return 1;
}

/**
 * Cache eviction score — higher means evict sooner.
 * TTL breaches dominate; then age weighted inversely by hits.
 */
export function cacheEvictScore(ageMs: i32, ttlMs: i32, hits: i32): i32 {
  const expiredBoost: i32 = (ttlMs > 0 && ageMs >= ttlMs) ? 1000000 : 0;
  return expiredBoost + (ageMs / (hits + 1));
}

/// Combine two 32-bit hashes into one decision tag (run id shortening).
export function combineHash(a: u32, b: u32): u32 {
  return (a * 16777619) ^ b;
}
