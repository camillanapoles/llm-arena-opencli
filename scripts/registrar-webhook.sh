#!/usr/bin/env bash
# scripts/registrar-webhook.sh — registra (ou atualiza) o webhook real do
# GitHub apontando para o POST /api/events do backend.
#
# Uso:
#   GITHUB_WEBHOOK_SECRET="<seu secret>" \
#     bash scripts/registrar-webhook.sh https://<host-do-backend>/api/events [owner/repo]
#
# Requer: gh autenticado (SEU login) com administração do repositório-alvo.
# O secret vem da SUA variável de ambiente — nunca é digitado aqui nem guardado.
set -euo pipefail

URL="${1:?uso: registrar-webhook.sh <payload-url> [owner/repo]}"
REPO="${2:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

if [ -z "${GITHUB_WEBHOOK_SECRET:-}" ]; then
  echo "✘ GITHUB_WEBHOOK_SECRET não definido — gere com: openssl rand -hex 32" >&2
  exit 1
fi
command -v gh >/dev/null 2>&1 || { echo "✘ gh (GitHub CLI) ausente" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "✘ python3 ausente" >&2; exit 1; }

corpo() { # $1 = método create|update — imprime o JSON do hook
  python3 - "$URL" "$GITHUB_WEBHOOK_SECRET" "$1" <<'PY'
import json, sys
url, secret, modo = sys.argv[1], sys.argv[2], sys.argv[3]
eventos = ["push", "pull_request", "repository_dispatch", "issues",
           "issue_comment", "workflow_run", "workflow_dispatch"]
hook = {
    "name": "web",
    "active": True,
    "events": eventos,
    "config": {"url": url, "content_type": "json", "secret": secret, "insecure_ssl": "0"},
}
if modo == "update":
    del hook["name"], hook["events"]   # PATCH não altera nome/eventos aqui
print(json.dumps(hook))
PY
}

HOOK=$(gh api "repos/$REPO/hooks" --jq '.[] | select(.config.url == "'"$URL"'") | .id' 2>/dev/null || true)

if [ -n "$HOOK" ]; then
  corpo update | gh api -X PATCH "repos/$REPO/hooks/$HOOK" --input - >/dev/null
  echo "✔ webhook #$HOOK atualizado em $REPO → $URL"
else
  corpo create | gh api -X POST "repos/$REPO/hooks" --input - >/dev/null
  echo "✔ webhook criado em $REPO → $URL"
fi

echo "→ confira o handshake 'ping' em Settings → Webhooks → Recent Deliveries"
