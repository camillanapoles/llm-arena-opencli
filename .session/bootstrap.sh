#!/usr/bin/env bash
# .session/bootstrap.sh — bootstrap obrigatório do worktree da sessão (IGC W2)
# Sem bootstrap verde, a FSM não sai de BOOT.
set -euo pipefail
cd "$(dirname "$0")/.."

PASSO() { printf '✔ %s\n' "$1"; }
MORRER() { printf '✘ %s\n' "$1" >&2; exit 1; }

# 1) toolchain
command -v node >/dev/null 2>&1 || MORRER "node ausente (necessário >= 22)"
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' \
  || MORRER "node >= 22 exigido (node:sqlite)"
command -v python3 >/dev/null 2>&1 || MORRER "python3 ausente (suítes CNJ)"
command -v git >/dev/null 2>&1 || MORRER "git ausente"
PASSO "toolchain: node $(node -v), python3 $(python3 -V 2>&1 | cut -d' ' -f2), git $(git --version | cut -d' ' -f3)"

# 2) dependências + artefatos regeneráveis (A1: tudo fora do repo é reconstruível)
[ -d node_modules ] || npm install --no-audit --no-fund
PASSO "node_modules presente"
npm run build:wasm >/dev/null
PASSO "wasm/dist construído (arena-runtime.wasm)"

# 3) hooks próprios do worktree (W4: isolamento via extensions.worktreeConfig)
git config extensions.worktreeConfig true 2>/dev/null || true
git config --worktree core.hooksPath .session/hooks 2>/dev/null || true
chmod +x .session/hooks/* 2>/dev/null || true
PASSO "hooks do worktree apontando para .session/hooks"

# 4) memória da sessão presente (A5)
for f in WAL.md STATE.yml INTENT.md CONTEXT.md DEBT.md CHECKPOINT; do
  [ -f ".session/$f" ] || MORRER ".session/$f ausente"
done
PASSO "memória .session/ completa (WAL, STATE, INTENT, CONTEXT, DEBT, CHECKPOINT)"

echo "bootstrap OK — worktree pronto para a FSM sair de BOOT"
