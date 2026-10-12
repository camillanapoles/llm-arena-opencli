/**
 * WASM build script (best-practice pipeline for the arena runtime core):
 *
 *  1. Compile the AssemblyScript module with size+speed optimizations and the
 *     `stub` runtime (pure compute — no allocator needed at the boundary).
 *     No `--exportRuntime`: the module stays fully self-contained (zero wasm
 *     imports), which is exactly what a browser wants to instantiate.
 *  2. Emit `wasm/dist/arena-runtime.wasm` (the artifact uploaded by CI and
 *     consumed by the web loader used at arena.ai/agent).
 *  3. Verify the artifact magic header so a corrupt build fails fast in CI.
 */

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const outDir = join(here, "dist");
const outFile = join(outDir, "arena-runtime.wasm");

const ascCandidates = [
  join(root, "node_modules", ".bin", "asc"),
  join(root, "node_modules", "assemblyscript", "bin", "asc"),
];
const ascBin = ascCandidates.find((candidate) => existsSync(candidate));

if (ascBin === undefined) {
  console.error("assemblyscript not found — run `npm install` first.");
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });

const result = spawnSync(
  ascBin,
  [
    join(here, "assembly", "index.ts"),
    "--outFile", outFile,
    "--optimize",
    "--runtime", "stub",
    "--noAssert",
  ],
  { stdio: "inherit", cwd: root },
);

if (result.status !== 0) {
  process.exit(result.status ?? 1);
}

const bytes = readFileSync(outFile);
const magic = [0x00, 0x61, 0x73, 0x6d];
const valid = magic.every((byte, i) => bytes[i] === byte);
if (!valid) {
  console.error(`build:wasm: ${outFile} is not a valid wasm module`);
  process.exit(1);
}

console.log(`build:wasm: ${outFile} (${bytes.length} bytes)`);
