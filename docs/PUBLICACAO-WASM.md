# Publicação do `arena-runtime.wasm` para `arena.ai/agent` (ISSUE-3)

**Status:** canal de publicação automatizado e **release `wasm-v0.1.0` publicado** · o deploy final no host `arena.ai/agent` é uma ação do usuário (DNS/CDN sob seu controle) — ver AUDITORIA.

## O que é publicado

| Artefato | Conteúdo |
|---|---|
| `arena-runtime.wasm` | core WASM do driver Arena — 335 bytes, **zero imports**, sem `--exportRuntime` |
| `wasm/loader.mjs` | loader web: `instantiateStreaming` + fallback ArrayBuffer, magic `\0asm`, scratch buffer com comprimento explícito, views recriadas a cada chamada, **API congelada** (`Object.freeze`) |
| `manifest.json` | versão, `sha256` e **SRI `sha384-…`** de cada arquivo + URLs de consumo |

## Canais de publicação (ambos automáticos)

1. **Canal git (fonte da verdade — sempre disponível):** o payload versionado em
   `release/wasm-v<versao>/` (wasm + loader + manifest). Consumível por URL raw:
   `https://raw.githubusercontent.com/camillanapoles/llm-arena-opencli/<ref>/release/wasm-v0.1.0/arena-runtime.wasm`.
2. **Release GitHub (best-effort):** tag `wasm-v<versao>` + assets quando
   `uploads.github.com` estiver acessível (neste runtime o upload é bloqueado —
   **DEBT D9**; a release vira marcador e o payload segue no canal git).

## Como publicar (uma linha)

```bash
bash scripts/publicar-wasm.sh --versao 0.1.0          # cria a release wasm-v0.1.0 (gh)
bash scripts/publicar-wasm.sh --versao 0.2.0 --dry-run # só gera manifest.json (sem gh)
```

O CI também publica: job `publicar-wasm` em `ci.yml` dispara em **tag `wasm-v*`** ou `workflow_dispatch` (a release é idempotente por tag; `gh release upload --clobber`).

## Como o front de `arena.ai/agent` consome

```html
<script type="module">
  import { loadArenaRuntime } from "https://arena.ai/agent/loader.mjs";

  const wasmUrl = "https://arena.ai/agent/arena-runtime.wasm";
  const runtime = await loadArenaRuntime(wasmUrl); // instantiateStreaming + fallback
  // API congelada: maskFromTypes, fnv1a32, decide… (ver wasm/loader.mjs)
  console.log(runtime.maskFromTypes(["push"]));
</script>
```

Com **SRI** (recomendado, o manifest traz os valores):

```html
<script type="module"
  src="https://arena.ai/agent/loader.mjs"
  integrity="sha384-…(ver manifest.json)…" crossorigin="anonymous"></script>
```

### Smoke de aceitação (roda no CI e local)

```bash
npm run ci            # typecheck + build:wasm + suítes (inclui smoke do loader)
node --test tests/publicacao.test.ts   # manifest × bytes × SRI coerentes
```

O smoke valida: magic `\0asm`, `instantiateStreaming` com fallback, scratch buffer, API congelada, FNV-1a32 conhecido (`"a"` → `0xe40c292c`), `maskFromTypes(["push"])`=1.

## Deploy em `arena.ai/agent` (ação do usuário — 3 passos)

1. Baixe os 3 arquivos da release: `gh release download wasm-v0.1.0 -D agent/` (ou pelos URLs `releases/download/wasm-v0.1.0/…`).
2. Suba-os no host/prefixo `arena.ai/agent/` com MIME `application/wasm` para o `.wasm` (essencial para `instantiateStreaming`).
3. Confira o smoke no browser (console): `loadArenaRuntime("https://arena.ai/agent/arena-runtime.wasm")` resolve e `maskFromTypes(["push"])` devolve `1`.

## AUDITORIA — O QUE FALTA

- **Deploy real em `arena.ai/agent`** (host do usuário; DEBT D8 com gatilho: após o upload, rodar o smoke do passo 3 e registrar o resultado no WAL).
- Publicação espelhada em CDN externo (opcional) — o manifest.json já permite verificação byte a byte de qualquer espelho.
