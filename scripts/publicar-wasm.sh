#!/usr/bin/env bash
# =============================================================================
# publicar-wasm.sh — publicação do arena-runtime.wasm para consumo web
# (ISSUE-3: arena.ai/agent via wasm/loader.mjs)
#
#   bash scripts/publicar-wasm.sh --versao 0.1.0            # release real (gh)
#   bash scripts/publicar-wasm.sh --versao 0.0.0 --dry-run  # só manifest + URLs
#
# Gera wasm/dist/manifest.json com sha256 + SRI (sha384) de cada arquivo e, sem
# --dry-run, cria a release `wasm-v<versao>` com os assets (canal consumível).
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSAO=""
DRY_RUN=0
SAIDA_DIR="$RAIZ/wasm/dist"
REF="$(git -C "$RAIZ" rev-parse HEAD 2>/dev/null || echo main)"

while [ $# -gt 0 ]; do
  case "$1" in
    --versao) VERSAO="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --saida-dir) SAIDA_DIR="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    *) echo "uso: publicar-wasm.sh --versao X [--dry-run] [--saida-dir DIR] [--ref REF]" >&2; exit 1 ;;
  esac
done

if [ -z "$VERSAO" ]; then echo "✘ --versao é obrigatório" >&2; exit 1; fi

# build determinístico do core
(cd "$RAIZ" && node wasm/build.mjs >/dev/null)
mkdir -p "$SAIDA_DIR"
cp "$RAIZ/wasm/loader.mjs" "$SAIDA_DIR/loader.mjs"
ORIGEM_WASM="$RAIZ/wasm/dist/arena-runtime.wasm"
if [ "$(realpath "$ORIGEM_WASM")" != "$(realpath -m "$SAIDA_DIR/arena-runtime.wasm")" ]; then
  cp "$ORIGEM_WASM" "$SAIDA_DIR/arena-runtime.wasm"
fi

sha256() { sha256sum "$1" | cut -d' ' -f1; }
sri() { printf 'sha384-%s' "$(openssl dgst -sha384 -binary "$1" | openssl base64 -A)"; }

WASM="$SAIDA_DIR/arena-runtime.wasm"
LOADER="$SAIDA_DIR/loader.mjs"
TAG="wasm-v$VERSAO"
URL_RELEASE="https://github.com/camillanapoles/llm-arena-opencli/releases/download/$TAG/arena-runtime.wasm"
URL_RAW="https://raw.githubusercontent.com/camillanapoles/llm-arena-opencli/$REF/wasm/dist/arena-runtime.wasm"
# canal git (sempre disponível): payload versionado no repositório, consumível por URL raw
DIR_GIT="$RAIZ/release/$TAG"
URL_GIT="https://raw.githubusercontent.com/camillanapoles/llm-arena-opencli/$REF/release/$TAG/arena-runtime.wasm"

cat > "$SAIDA_DIR/manifest.json" <<MANIFEST
{
  "nome": "arena-runtime",
  "versao": "$VERSAO",
  "tag": "$TAG",
  "gerado_em": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ref": "$REF",
  "arquivos": {
    "arena-runtime.wasm": {
      "sha256": "$(sha256 "$WASM")",
      "sri": "$(sri "$WASM")",
      "bytes": $(wc -c < "$WASM")
    },
    "loader.mjs": {
      "sha256": "$(sha256 "$LOADER")",
      "sri": "$(sri "$LOADER")",
      "bytes": $(wc -c < "$LOADER")
    }
  },
  "consumo": {
    "url_release": "$URL_RELEASE",
    "url_git": "$URL_GIT",
    "url_raw": "$URL_RAW",
    "loader": "release/$TAG/loader.mjs (git) · releases/download/$TAG/loader.mjs (release)",
    "smoke": "carregue loader.mjs e chame loadArenaRuntime(bytes) — ver docs/PUBLICACAO-WASM.md"
  }
}
MANIFEST

if [ "$DRY_RUN" = "1" ]; then
  echo "✔ dry-run: gh não acionado; canal git NÃO gravado (URL prevista: $URL_GIT)"
  exit 0
fi

# canal git: publica o payload versionado (funciona sem uploads.github.com)
mkdir -p "$DIR_GIT"
cp "$WASM" "$LOADER" "$SAIDA_DIR/manifest.json" "$DIR_GIT/"
echo "✔ canal git: $DIR_GIT (URL consumível: $URL_GIT)"
echo "  wasm   sha256=$(sha256 "$WASM")"
echo "  loader sha256=$(sha256 "$LOADER")"

# canal release (best-effort): tag/manifest na release + assets quando a rede permitir
if ! command -v gh >/dev/null 2>&1; then
  echo "::notice::gh ausente — canal git publicado; release é opcional"
  exit 0
fi
if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --title "arena-runtime.wasm v$VERSAO" \
    --notes "Core WASM do driver Arena (zero imports) + loader web (instantiateStreaming, scratch buffer, API congelada). Payload: release/$TAG/ no repositório (canal git) — consuma via URL raw. SRI no manifest.json." \
    || { echo "::notice::release-tag não criada (API indisponível) — canal git já publicado"; exit 0; }
fi
if gh release upload "$TAG" "$WASM" "$LOADER" "$SAIDA_DIR/manifest.json" --clobber 2>/dev/null; then
  echo "✔ release assets anexados: $URL_RELEASE"
else
  echo "::notice::upload de assets da release indisponível neste runtime (uploads.github.com bloqueado — DEBT D9); payload consumível pelo canal git: $URL_GIT"
fi
exit 0
