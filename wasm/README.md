# arena-runtime (WebAssembly core)

Pure-compute gate/cache primitives compiled from
[`assembly/index.ts`](./assembly/index.ts) to `dist/arena-runtime.wasm`, so the
same gate decisions that the backend's GateDriver makes can run in the browser
at [arena.ai/agent](https://arena.ai/agent) without a backend round-trip.

## Best practices baked in

| Practice | Where |
| --- | --- |
| Pure numeric functions, no I/O | `assembly/index.ts` |
| Zero wasm imports — self-contained module (no `env.abort` stub) | `build.mjs` (`stub` runtime, no `--exportRuntime`) |
| Host-owned scratch buffer + explicit lengths (no hidden allocation) | `scratchPtr` / `fnv1a` |
| Magic-byte validation before instantiate | `loader.mjs` → `assertWasmMagic` |
| `instantiateStreaming` with ArrayBuffer fallback | `loader.mjs` → `compileFrom` |
| Compile/instantiate separation (module cacheable) | `loader.mjs` |
| Re-create `memory.buffer` views after calls (grow detaches) | `hashString` |
| Frozen API surface, no `eval` | `loadArenaRuntime` |

## Build

```sh
npm run build:wasm          # -> wasm/dist/arena-runtime.wasm
```

## Use on the web

```html
<script type="module">
  import { loadArenaRuntime, maskFromTypes } from "./wasm/loader.mjs";

  const rt = await loadArenaRuntime("https://your-host/wasm/dist/arena-runtime.wasm");

  // Same semantics as src/gate/events.ts `matchesTrigger`:
  const eventMask = maskFromTypes(["push"]);
  const triggerMask = maskFromTypes(["push", "pull_request"]);
  const fires = rt.evaluateGate(eventMask, triggerMask,
    /* hasRefConstraint */ 0, 0, 0,
    /* hasActorConstraint */ 0, 0, 0);

  console.log("gate fires:", fires === 1);
  console.log("cache key hash:", rt.hashString("gate:ci-blocking:last"));
</script>
```

CI uploads `arena-runtime.wasm` as the `arena-runtime-wasm` artifact
(see `.github/workflows/opencli-driver.yml`).
