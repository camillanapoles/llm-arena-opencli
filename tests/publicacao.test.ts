/**
 * ISSUE-3 — smoke do canal de publicação do arena-runtime.wasm (arena.ai/agent).
 * Valida manifest × bytes × SRI sem rede (dry-run), e a documentação de consumo.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const RAIZ = process.cwd();

test("publicar-wasm --dry-run: manifest com sha256/SRI coerentes com os bytes", () => {
  const dir = mkdtempSync(join(tmpdir(), "pub-wasm-"));
  execFileSync("bash", [
    join(RAIZ, "scripts/publicar-wasm.sh"),
    "--versao", "0.0.0-teste",
    "--dry-run",
    "--saida-dir", dir,
    "--ref", "deadbeef",
  ], { cwd: RAIZ, encoding: "utf8" });

  const manifest = JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  assert.equal(manifest.nome, "arena-runtime");
  assert.equal(manifest.tag, "wasm-v0.0.0-teste");

  for (const nome of ["arena-runtime.wasm", "loader.mjs"]) {
    const bytes = readFileSync(join(dir, nome));
    const sha = createHash("sha256").update(bytes).digest("hex");
    assert.equal(manifest.arquivos[nome].sha256, sha, `sha256 de ${nome} confere com os bytes`);
    assert.match(manifest.arquivos[nome].sri, /^sha384-[A-Za-z0-9+/=]+$/, "SRI sha384 em base64");
    assert.equal(manifest.arquivos[nome].bytes, bytes.length);
  }
  assert.match(manifest.consumo.url_release, /releases\/download\/wasm-v0\.0\.0-teste\/arena-runtime\.wasm/);
  assert.match(manifest.consumo.url_git, /release\/wasm-v0\.0\.0-teste\/arena-runtime\.wasm/);
  assert.ok(existsSync(join(dir, "loader.mjs")), "loader publicado junto ao wasm");
  rmSync(dir, { recursive: true, force: true });
});

test("loader publicado mantém as best practices do consumo web (arena.ai/agent)", async () => {
  const { loadArenaRuntime, assertWasmMagic } = await import(join(RAIZ, "wasm/loader.mjs"));
  const wasm = readFileSync(join(RAIZ, "wasm/dist/arena-runtime.wasm"));
  assertWasmMagic(wasm);
  const rt = await loadArenaRuntime(new Uint8Array(wasm));
  assert.equal(Object.isFrozen(rt), true, "API congelada (sem monkey-patching)");
  assert.equal(rt.maskFromTypes(["push"]), 1);
  assert.equal(rt.maskFromTypes(["pull_request"]), 2);
  assert.equal(rt.hashString("a"), 0xe40c292c, "FNV-1a32('a') pelo scratch buffer");

  const loaderSrc = readFileSync(join(RAIZ, "wasm/loader.mjs"), "utf8");
  assert.match(loaderSrc, /instantiateStreaming/, "instantiateStreaming presente");
  assert.match(loaderSrc, /assertWasmMagic|WASM_MAGIC/, "magic validado antes de instanciar");

  const doc = readFileSync(join(RAIZ, "docs/PUBLICACAO-WASM.md"), "utf8");
  assert.match(doc, /arena\.ai\/agent/);
  assert.match(doc, /loadArenaRuntime/);
  assert.match(doc, /integrity|sri/i, "consumo com SRI documentado");
});
