/** Type declarations for the arena-runtime web loader (plain JS module). */

export interface ArenaRuntime {
  module: WebAssembly.Module;
  instance: WebAssembly.Instance;
  memory: WebAssembly.Memory;
  scratchPtr(): number;
  scratchSize(): number;
  fnv1a(ptr: number, len: number): number;
  gateMatch(eventMask: number, triggerMask: number): number;
  evaluateGate(
    eventMask: number,
    triggerMask: number,
    hasRefConstraint: number,
    refHash: number,
    eventRefHash: number,
    hasActorConstraint: number,
    actorHash: number,
    eventActorHash: number,
  ): number;
  cacheEvictScore(ageMs: number, ttlMs: number, hits: number): number;
  combineHash(a: number, b: number): number;
  maskFromTypes(types: string[]): number;
  hashString(text: string): number;
}

export function assertWasmMagic(bytes: ArrayBuffer | Uint8Array): void;
export function maskFromTypes(types: string[]): number;
export function hashString(runtime: ArenaRuntime, text: string): number;
export function loadArenaRuntime(source: string | URL | ArrayBuffer | Uint8Array): Promise<ArenaRuntime>;
