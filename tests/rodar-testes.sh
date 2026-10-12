#!/usr/bin/env bash
# =============================================================================
#  rodar-testes.sh — testa scripts/datajud.sh contra um mock local da API
# =============================================================================
#  Não é preciso internet nem chave real: tests/mock_datajud.py simula a API
#  Pública do DataJud (autenticação, erros 400/401/404/429, agregações e
#  paginação com search_after).
#
#  Uso: ./tests/rodar-testes.sh
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

CHAVE_TESTE="CHAVE-DE-TESTE"
LOG="$(mktemp)"; DIR_TMP="$(mktemp -d)"
PORTA="$(python3 - <<'PY'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
PY
)"

export DATAJUD_BASE_URL="http://127.0.0.1:${PORTA}"
export DATAJUD_API_KEY="$CHAVE_TESTE"
export DATAJUD_PAUSA=0

MOCK_LOG="$LOG" MOCK_API_KEY="$CHAVE_TESTE" python3 tests/mock_datajud.py --porta "$PORTA" >"$DIR_TMP/mock.log" 2>&1 &
PID_MOCK=$!
limpar() { kill "$PID_MOCK" 2>/dev/null || true; rm -rf "$DIR_TMP"; rm -f "$LOG"; }
trap limpar EXIT

# espera o mock subir (sem sleep cego)
python3 - "$PORTA" <<'PY'
import socket, sys, time
porta = int(sys.argv[1])
limite = time.time() + 10
while time.time() < limite:
    try:
        with socket.create_connection(("127.0.0.1", porta), 0.3):
            sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit("mock não subiu")
PY

PASSOU=0; FALHOU=0
ok()    { printf '  \033[1;32m✔\033[0m %s\n' "$1"; PASSOU=$((PASSOU+1)); }
ruim()  { printf '  \033[1;31m✘\033[0m %s\n' "$1"; FALHOU=$((FALHOU+1)); }
titulo(){ printf '\n\033[1;34m%s\033[0m\n' "$1"; }

SAIDA_TXT=""; SAIDA_ST=0
executar() { set +e; SAIDA_TXT="$("$@" 2>&1)"; SAIDA_ST=$?; set -e; }
contem()   { case "$SAIDA_TXT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

teste() { # teste "<nome>" <esperado: sucesso|falha> <condição como string avaliada por grep>
  local nome="$1" espera="$2" padrao="$3"
  if [[ "$espera" == "sucesso" && "$SAIDA_ST" != "0" ]]; then
    ruim "$nome (esperava sucesso, saiu com código $SAIDA_ST)"; printf '%s\n' "$SAIDA_TXT" | sed 's/^/      /'; return
  fi
  if [[ "$espera" == "falha" && "$SAIDA_ST" == "0" ]]; then
    ruim "$nome (esperava erro, mas saiu com 0)"; printf '%s\n' "$SAIDA_TXT" | sed 's/^/      /'; return
  fi
  if printf '%s' "$SAIDA_TXT" | grep -qE -- "$padrao"; then ok "$nome"
  else ruim "$nome (saída não contém: $padrao)"; printf '%s\n' "$SAIDA_TXT" | sed 's/^/      /' | head -20; fi
}

printf 'Testes do datajud.sh (mock em 127.0.0.1:%s)\n' "$PORTA"

titulo '1. Estrutura e ajuda'
executar bash -n scripts/datajud.sh
if [[ "$SAIDA_ST" == "0" && -z "$SAIDA_TXT" ]]; then ok 'scripts/datajud.sh não tem erro de sintaxe'
else ruim "scripts/datajud.sh tem erro de sintaxe: $SAIDA_TXT"; fi
executar bash scripts/datajud.sh ajuda
teste 'ajuda mostra os comandos' sucesso 'relatorio'
executar bash scripts/datajud.sh
teste 'sem argumentos mostra a ajuda' sucesso 'USO'

titulo '2. Contagem de processos'
executar bash scripts/datajud.sh contar --tribunal tjpe
teste 'contar sem filtro devolve total em modo gte' sucesso 'Total: 10000 \(relação: gte'
executar bash scripts/datajud.sh contar --classe 1116 --grau G1
teste 'contar com filtros devolve relação eq' sucesso 'Total: 4321 \(relação: eq'
executar bash scripts/datajud.sh contar --classe 1116 --json
teste 'contar --json devolve JSON estruturado' sucesso '"total": 4321'

titulo '3. Agregações (com e sem fallback de campo)'
executar bash scripts/datajud.sh agregar grau
teste 'agregar grau cai para grau.keyword' sucesso 'grau\.keyword'
teste 'agregar grau traz os buckets' sucesso 'G1\s+9000'
executar bash scripts/datajud.sh agregar classe-nome
teste 'agregar classe-nome faz fallback para classe.codigo' sucesso 'classe\.codigo'
teste 'agregar classe-nome avisa o fallback' sucesso 'não é agregável'
executar bash scripts/datajud.sh agregar assunto-nome
teste 'agregar assunto-nome faz fallback para assuntos.codigo' sucesso 'assuntos\.codigo'
executar bash scripts/datajud.sh agregar orgao-nome --classe 1116
teste 'agregar orgao-nome funciona direto no .keyword' sucesso 'VARA DE EXECUÇÃO FISCAL'
executar bash scripts/datajud.sh agregar ano
teste 'agregar ano usa date_histogram' sucesso '2024\s+5000'
executar bash scripts/datajud.sh agregar campo-que-nao-existe
teste 'campo de agregação inválido falha com mensagem útil' falha 'desconhecido'

titulo '4. Busca por número de processo'
executar bash scripts/datajud.sh processo 0001234-56.2024.8.17.2001 --tribunal tjpe
teste 'processo encontrado mostra a classe' sucesso 'Execução Fiscal'
teste 'processo encontrado mostra o órgão julgador' sucesso '1ª VARA DE EXECUÇÃO FISCAL'
teste 'processo encontrado mostra o último movimento' sucesso 'Expedição de documento'
executar bash scripts/datajud.sh processo 0001234-56.2024.8.17.2001 --movimentos
teste '--movimentos lista a tabela de movimentos' sucesso 'Distribuição'
executar bash scripts/datajud.sh processo 99999999920248172999
teste 'processo inexistente falha com orientação' falha 'não encontrado'

titulo '5. Paginação com search_after'
executar bash scripts/datajud.sh paginar --limite 3 --pagina 2 --saida "$DIR_TMP/pagina.jsonl"
teste 'paginar conclui com sucesso' sucesso 'gravado:'
if [[ -f "$DIR_TMP/pagina.jsonl" && "$(wc -l < "$DIR_TMP/pagina.jsonl" | tr -d ' ')" == "3" ]]; then
  ok 'paginar grava exatamente o limite pedido (3 registros)'
else
  ruim "paginar gravou $(wc -l < "$DIR_TMP/pagina.jsonl" 2>/dev/null || echo 0) registros (esperado 3)"
fi
if grep -q 'search_after=True' "$LOG"; then ok 'paginar usou search_after na requisição seguinte'
else ruim 'paginar não usou search_after'; fi

titulo '6. Relatório do TJPE'
executar bash scripts/datajud.sh relatorio --tribunal tjpe --saida "$DIR_TMP/rel" --top 5
teste 'relatorio conclui e informa o arquivo gerado' sucesso 'relatorio-TJPE-[0-9]{8}-[0-9]{4}\.md'
MD="$(ls "$DIR_TMP"/rel/relatorio-TJPE-*.md 2>/dev/null | head -1 || true)"
if [[ -n "$MD" ]] && grep -q 'Total de processos' "$MD" && grep -q 'Por órgão julgador' "$MD" && grep -q 'Termo de Uso' "$MD"; then
  ok 'relatório markdown tem total, seções e notas do Termo de Uso'
else
  ruim 'relatório markdown incompleto'
fi
if ls "$DIR_TMP"/rel/agg-*.csv >/dev/null 2>&1 && ls "$DIR_TMP"/rel/agg-*.tsv >/dev/null 2>&1; then
  ok 'relatório gera CSV e TSV por agregação'
else
  ruim 'relatório não gerou CSV/TSV'
fi

titulo '7. Chave pública'
CHAVE_FALSA_WIKI="dGVzdGUtY2hhdmUtcHVibGljYS1mYWxzYS1wYXJhLXRlc3RlLW9mZmxpbmUtZG8tZGF0YWp1ZC0xMjM0NTY3OA=="
executar env DATAJUD_WIKI_URL="http://127.0.0.1:${PORTA}/wiki/acesso" bash scripts/datajud.sh chave
teste 'chave extrai a chave pública publicada (página HTML)' sucesso "$CHAVE_FALSA_WIKI"

titulo '8. Tratamento de erros'
executar env DATAJUD_API_KEY=chave-errada bash scripts/datajud.sh contar
teste 'chave inválida gera erro 401 explicado' falha 'HTTP 401'
teste 'chave inválida orienta atualizar a chave' falha 'datajud.sh chave'
executar bash scripts/datajud.sh contar --tribunal 429
teste 'HTTP 429 explica o limite de 120 req/min' falha '120'
executar bash scripts/datajud.sh contar --tribunal tjxx
teste 'alias inexistente gera 404 com link da lista' falha 'Alias de tribunal inexistente'
executar env DATAJUD_BASE_URL="http://127.0.0.1:1" bash scripts/datajud.sh contar
teste 'falha de rede produz mensagem clara' falha 'falha de rede'
executar bash scripts/datajud.sh --debug contar
teste '--debug mostra o curl equivalente' sucesso 'curl -sS'

printf '\n\033[1;34mResultado\033[0m: %s passaram, %s falharam\n' "$PASSOU" "$FALHOU"
[[ "$FALHOU" == "0" ]] || exit 1
