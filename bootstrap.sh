#!/usr/bin/env bash
# ==============================================================================
#  bootstrap.sh — recria este projeto INTEIRO, do zero, e prova que funciona.
# ==============================================================================
#  Gerado por tools/gerar_bootstrap.py — NÃO edite à mão; regenere com
#      python3 tools/gerar_bootstrap.py
#
#  O que este script faz, em ordem:
#    1. confere os pré-requisitos (bash 4+, python3 3.8+; curl/jq são opcionais)
#    2. cria TODOS os diretórios e escreve TODOS os arquivos (conteúdo embutido)
#    3. aplica TODAS as permissões (755 em scripts/testes, 644 em docs/dados)
#    4. confere a integridade por SHA-256 de cada arquivo escrito
#    5. valida a sintaxe (python -m py_compile, bash -n)
#    6. roda as 4 suítes de teste offline (conformidade, main.py, datajud.sh, pipeline)
#    7. imprime um relatório final com o código de saída de cada etapa
#
#  Uso:
#      bash bootstrap.sh                       # cria em ./projeto-datajud
#      bash bootstrap.sh --destino /opt/xyz    # cria em outro diretório
#      bash bootstrap.sh --forcar              # sobrescreve destino existente
#      bash bootstrap.sh --so-criar            # cria e confere, sem rodar testes
#      bash bootstrap.sh --verificar           # só verifica um projeto já criado
#      bash bootstrap.sh --sem-testes          # pula as suítes
#      bash bootstrap.sh --ajuda
#
#  Conteúdo embutido: 29 arquivos, 6711 linhas, 309 KiB.
#  Documentação: BOOTSTRAP.md · Wiki do CNJ: https://datajud-wiki.cnj.jus.br/api-publica/acesso
# ==============================================================================
set -euo pipefail

VERSAO_BOOTSTRAP="1.0.0"
DESTINO="./projeto-datajud"
FORCAR=0
SO_CRIAR=0
SEM_TESTES=0
SO_VERIFICAR=0

TITULO() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
PASSO()  { printf '   \033[1;32m✔\033[0m %s\n' "$*"; }
ALERTA() { printf '   \033[1;33m!\033[0m %s\n' "$*"; }
FALHA()  { printf '   \033[1;31m✘\033[0m %s\n' "$*" >&2; }
MORRER() { FALHA "$*"; exit 1; }
modo_de() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

uso() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while (($#)); do
  case "$1" in
    --destino)     DESTINO="${2:?faltou o valor}"; shift ;;
    --forcar)      FORCAR=1 ;;
    --so-criar)    SO_CRIAR=1 ;;
    --sem-testes)  SEM_TESTES=1 ;;
    --verificar)   SO_VERIFICAR=1 ;;
    -h|--help|ajuda) uso ;;
    *) MORRER "opção desconhecida: $1 (use --ajuda)" ;;
  esac
  shift
done

# Extrai do próprio script o conteúdo de um arquivo embutido
MARCADOR_FIM="__ARQ_""EOF__"   # montado em runtime para não coincidir com o conteúdo embutido
# Extrai o blob de um arquivo embutido usando comparação exata de linha (awk),
# para não depender de escape de regex nos caminhos (docs/… tem “/”).
conteudo_arquivo() {
  awk -v alvo="__ARQ__ $1" -v fim="$MARCADOR_FIM" '
    $0 == alvo { dentro = 1; next }
    dentro && $0 == fim { exit }
    dentro { print }
  ' "$0"
}

# ------------------------------------------------------------------ 1. apoio ---
TITULO "1/7 · Pré-requisitos"
[[ "${BASH_VERSINFO[0]:-0}" -ge 4 ]] || MORRER "bash 4+ é necessário (atual: ${BASH_VERSION:-?})"
PASSO "bash ${BASH_VERSION%%(*}"
command -v python3 >/dev/null 2>&1 || MORRER "python3 não encontrado no PATH"
VERSAO_PY=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' \
  || MORRER "python3 3.8+ é necessário (atual: $VERSAO_PY)"
PASSO "python3 $VERSAO_PY"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  PASSO "curl e jq presentes (necessários só para scripts/datajud.sh)"
else
  ALERTA "curl e/ou jq ausentes — o main.py funciona; scripts/datajud.sh não"
fi
if [[ "$SO_VERIFICAR" == "1" && "$DESTINO" == "./projeto-datajud" ]]; then
  DESTINO="."
fi

# ------------------------------------------------------------------ 2. estrutura ---
if [[ "$SO_VERIFICAR" == "0" ]]; then
  TITULO "2/7 · Estrutura de diretórios"
  if [[ -e "$DESTINO" && "$FORCAR" == "0" && -n "$(ls -A "$DESTINO" 2>/dev/null || true)" ]]; then
    MORRER "$DESTINO já existe e não está vazio (use --forcar para sobrescrever)"
  fi
  mkdir -p "$DESTINO"
  chmod 755 "$DESTINO"
  for d in .github/workflows docs docs/exemplo-saida pipeline scripts tests tools; do
    mkdir -p "$DESTINO/$d"
    chmod 755 "$d" 2>/dev/null || true
    chmod 755 "$DESTINO/$d"
  done
  PASSO "diretórios criados (raiz + subdiretórios), todos com modo 755"

  # ---------------------------------------------------------------- 3. arquivos ---
  TITULO "3/7 · Arquivos do projeto"
  while read -r modo caminho; do
    [[ -z "${caminho:-}" ]] && continue
    conteudo_arquivo "$caminho" > "$DESTINO/$caminho"
    chmod "$modo" "$DESTINO/$caminho"
  done <<'LISTA'
644 .github/workflows/gates.yml
644 .gitignore
644 BOOTSTRAP.md
644 ENTREGA.md
644 Makefile
644 README.md
644 docs/01-api-datajud.md
644 docs/02-receitas-curl-tjpe.md
644 docs/03-pipeline-gates.md
644 docs/exemplo-saida/agg-grau.tsv
644 docs/exemplo-saida/agg-orgao-nome.csv
644 docs/exemplo-saida/relatorio-processo-exemplo.md
644 docs/exemplo-saida/relatorio-tjpe-exemplo.md
755 main.py
644 pipeline/.gitignore
644 pipeline/backlog.json
644 pipeline/blueprint.json
755 pipeline/gate.py
755 pipeline/verificar_cnj.py
755 scripts/datajud.sh
755 tests/mock_apis.py
755 tests/mock_datajud.py
755 tests/rodar-testes.sh
755 tests/testar_bootstrap.sh
755 tests/testar_conformidade.py
755 tests/testar_main.py
755 tests/testar_pipeline.py
755 tools/gerar_bootstrap.py
LISTA
  if [[ -f "$0" && -r "$0" ]]; then
    install -m 755 "$0" "$DESTINO/bootstrap.sh"
    PASSO "bootstrap.sh copiado junto (para reinstalar/verificar depois)"
  else
    ALERTA "executado via stdin/pipe: bootstrap.sh não foi copiado (copie manualmente)"
  fi
  PASSO "arquivos escritos com as permissões corretas"
else
  TITULO "2/7 · Estrutura de diretórios"
  [[ -d "$DESTINO" ]] || MORRER "diretório não encontrado: $DESTINO"
  PASSO "verificando o projeto em $DESTINO"
  TITULO "3/7 · Arquivos do projeto"
  PASSO "escrita pulada (modo --verificar)"
fi

# ------------------------------------------------- 4. integridade (SHA-256) ---
TITULO "4/7 · Integridade dos arquivos (SHA-256)"
falhas_hash=0
while read -r esperado caminho; do
  [[ -z "${caminho:-}" ]] && continue
  caminho="${caminho#./}"
  alvo="$DESTINO/$caminho"
  if [[ ! -f "$alvo" ]]; then
    FALHA "faltando: $caminho"; falhas_hash=$((falhas_hash+1)); continue
  fi
  obtido=$( { sha256sum "$alvo" 2>/dev/null || shasum -a 256 "$alvo"; } | cut -d' ' -f1 )
  if [[ "$obtido" != "$esperado" ]]; then
    FALHA "hash diferente: $caminho"; falhas_hash=$((falhas_hash+1))
  fi
done <<'MANIFESTO'
8b4f26ed565c04416496608d1897e49a317a53c014d2ea49c10844264b8259d6  ./.github/workflows/gates.yml
f96c1e19a2859767ea2b94ce848b8e0b0fa03444e4704db468dcf2b226ad60e6  ./.gitignore
4b306003100e8ba1982697fa5f41e0a7e8853747ea9aaedd310194db4cc11087  ./BOOTSTRAP.md
f35dd831e6152076b24d8f86b899fb24d0903efdc6899f700e9865e9df9cbe81  ./ENTREGA.md
68ed5b0153318d3c8c66bff72248cd93bc9b3af8af82d74435d1b835c770413a  ./Makefile
3b1ab982ed3dd509f5f3410be2d4095a7346f559ea7d2a93409751881cd89e7b  ./README.md
16d76f838f1d9b2e8eafd538b0f2f62bbe34cab647a17181e440610a0c0234d3  ./docs/01-api-datajud.md
5e8befc6e2434cb27c1404693dc775f7de8056893bcc94712e61644e40ddbc3f  ./docs/02-receitas-curl-tjpe.md
b171fc3f4334c76d47064ace4115c415cd768ff776d1793d1e44981835160958  ./docs/03-pipeline-gates.md
7c75c6c9e28b98ba45eb7ffdb7ad5165b2d002338c9e32dbbe61d02986e1fd06  ./docs/exemplo-saida/agg-grau.tsv
8d95b990767a0c8a967f45ccce11471fccb2d6f875f494213f223f7a788a05d0  ./docs/exemplo-saida/agg-orgao-nome.csv
e36c89bd1faf65d6ea5f2044b705d473a6e48276585ddd3263782bf3657110c8  ./docs/exemplo-saida/relatorio-processo-exemplo.md
0988a9fe28376cca40c84bbbe73172203e1f4740695026e2f9408f1fd88bea0a  ./docs/exemplo-saida/relatorio-tjpe-exemplo.md
c58f533ad991e50add1ec5ea7c2f79910fb05796f36beb5f288311c39d6ceadf  ./main.py
4392304e7b6b15961c43e67e4d1acbd351ca41eaf235fc347d972f2c06d6b687  ./pipeline/.gitignore
eca7fe60e2c3997e1a235de31ed49df8556b94d6e94220f81d1d64a1f543032a  ./pipeline/backlog.json
e7846f8cfdb64b14fbfd4dfdfca19bb5fd0891b38e7805def94757f7dc33c3d5  ./pipeline/blueprint.json
4e5e1ede5261d28b2003e7958f68c989b2241308b6d56c5504f33681abb9a005  ./pipeline/gate.py
74fedbc6f554883485cac903bcf696cc7b77098233e315d812080f708d57a20e  ./pipeline/verificar_cnj.py
dd78d8b6469b06e5ab67d11137eaac3891ac16b2856064bce8be6a801e67dea0  ./scripts/datajud.sh
b3dbad0dbe125d5d02874e534e8f693d8068c9180fc508db33cc4c57626c6f46  ./tests/mock_apis.py
54b84ce8348712a3e8d689f96d284d0f019e11bb2bcf888abeab2c147fe63baa  ./tests/mock_datajud.py
3d917cdf5b4b7732d17ccf0f542987e8daded8b62f03c0e5c055a4988f329daa  ./tests/rodar-testes.sh
273c83433da70daaf0e5f7e4585b180b79b2de6b6ac8866b18aa0ceea6bccd6d  ./tests/testar_bootstrap.sh
a8baa3b18dbd5133b51bc4ee3691c67eabc87b8066ff58a4b01386a1c97016a3  ./tests/testar_conformidade.py
6ac8cccd6052e64e491e23e0319b841526797be31ee541fb74945693cb55c156  ./tests/testar_main.py
e87a75c9fa395cd43f4f3fe6baafc7c6a75cce0f7b6d6e6615472078b814f9b7  ./tests/testar_pipeline.py
fb2b5c775f6459108607466ec51d5a2a593af17c39ca5ce8e6d8bea8bab3b90c  ./tools/gerar_bootstrap.py
MANIFESTO
if [[ "$falhas_hash" == "0" ]]; then
  PASSO "todos os hashes conferem com o manifesto embutido"
else
  MORRER "$falhas_hash arquivo(s) divergentes — o destino não corresponde a este bootstrap"
fi

# ------------------------------------------------------ 5. permissões esperadas ---
TITULO "5/7 · Permissões"
falhas_modo=0
while read -r modo caminho; do
  [[ -z "${caminho:-}" ]] && continue
  real=$(modo_de "$DESTINO/$caminho" 2>/dev/null || echo "?")
  if [[ "$real" != "$modo" ]]; then
    FALHA "$caminho: modo $real (esperado $modo)"; falhas_modo=$((falhas_modo+1))
  fi
done <<'PERMISSOES'
644 .github/workflows/gates.yml
644 .gitignore
644 BOOTSTRAP.md
644 ENTREGA.md
644 Makefile
644 README.md
755 bootstrap.sh
644 docs/01-api-datajud.md
644 docs/02-receitas-curl-tjpe.md
644 docs/03-pipeline-gates.md
644 docs/exemplo-saida/agg-grau.tsv
644 docs/exemplo-saida/agg-orgao-nome.csv
644 docs/exemplo-saida/relatorio-processo-exemplo.md
644 docs/exemplo-saida/relatorio-tjpe-exemplo.md
755 main.py
644 pipeline/.gitignore
644 pipeline/backlog.json
644 pipeline/blueprint.json
755 pipeline/gate.py
755 pipeline/verificar_cnj.py
755 scripts/datajud.sh
755 tests/mock_apis.py
755 tests/mock_datajud.py
755 tests/rodar-testes.sh
755 tests/testar_bootstrap.sh
755 tests/testar_conformidade.py
755 tests/testar_main.py
755 tests/testar_pipeline.py
755 tools/gerar_bootstrap.py
PERMISSOES
if [[ "$falhas_modo" == "0" ]]; then
  PASSO "755 em scripts/testes, 644 em docs/dados — todos corretos"
else
  ALERTA "$falhas_modo arquivo(s) com permissão divergente (corrija com chmod)"
fi

# --------------------------------------------------------- 6. validação estática ---
TITULO "6/7 · Validação de sintaxe"
ST_PY=0; ST_SH=0
for arq in main.py pipeline/gate.py pipeline/verificar_cnj.py tests/mock_apis.py tests/mock_datajud.py tests/testar_conformidade.py tests/testar_main.py tests/testar_pipeline.py tools/gerar_bootstrap.py; do
  python3 -m py_compile "$DESTINO/$arq" 2>/dev/null || { FALHA "python inválido: $arq"; ST_PY=1; }
done
rm -rf "$DESTINO"/__pycache__ "$DESTINO"/tests/__pycache__ "$DESTINO"/tools/__pycache__ \
       "$DESTINO"/pipeline/__pycache__ 2>/dev/null || true
[[ "$ST_PY" == "0" ]] && PASSO "Python: 9 arquivos compilam sem erro (py_compile)"
for arq in bootstrap.sh scripts/datajud.sh tests/rodar-testes.sh tests/testar_bootstrap.sh; do
  bash -n "$DESTINO/$arq" 2>/dev/null || { FALHA "bash inválido: $arq"; ST_SH=1; }
done
[[ "$ST_SH" == "0" ]] && PASSO "Bash: 4 scripts sem erro de sintaxe (bash -n)"

# ------------------------------------------------------------------ 7. testes ---
ST_CONF="pulado"; ST_MAIN="pulado"; ST_SH_T="pulado"; ST_PIPE="pulado"
if [[ "$SEM_TESTES" == "1" || "$SO_CRIAR" == "1" ]]; then
  TITULO "7/7 · Testes"
  ALERTA "suítes de teste não executadas (--so-criar/--sem-testes)"
else
  TITULO "7/7 · Testes (offline, contra mocks locais)"
  ( cd "$DESTINO" && python3 tests/testar_conformidade.py ) >/tmp/bootstrap_conf.log 2>&1 \
    && ST_CONF="ok" || ST_CONF="FALHOU"
  grep -E '^(Ran |OK|FAILED)' /tmp/bootstrap_conf.log | tail -2 | sed 's/^/     /' || true
  [[ "$ST_CONF" == "ok" ]] && PASSO "conformidade com a documentação do CNJ" || FALHA "conformidade"

  ( cd "$DESTINO" && python3 tests/testar_main.py ) >/tmp/bootstrap_main.log 2>&1 \
    && ST_MAIN="ok" || ST_MAIN="FALHOU"
  grep -E '^(Ran |OK|FAILED)' /tmp/bootstrap_main.log | tail -2 | sed 's/^/     /' || true
  [[ "$ST_MAIN" == "ok" ]] && PASSO "main.py (consulta de processo e relatório)" || FALHA "testes do main.py"

  ( cd "$DESTINO" && bash tests/rodar-testes.sh ) >/tmp/bootstrap_sh.log 2>&1 \
    && ST_SH_T="ok" || ST_SH_T="FALHOU"
  tail -1 /tmp/bootstrap_sh.log | sed 's/^/     /' || true
  [[ "$ST_SH_T" == "ok" ]] && PASSO "scripts/datajud.sh (curl + jq)" || FALHA "testes do datajud.sh"

  ( cd "$DESTINO" && python3 tests/testar_pipeline.py ) >/tmp/bootstrap_pipe.log 2>&1 \
    && ST_PIPE="ok" || ST_PIPE="FALHOU"
  grep -E '^(Ran |OK|FAILED)' /tmp/bootstrap_pipe.log | tail -2 | sed 's/^/     /' || true
  [[ "$ST_PIPE" == "ok" ]] && PASSO "pipeline de gates (contrato JSON, 0/1/2)" || FALHA "testes do pipeline"
fi

# ------------------------------------------------------------------ resumo ---
TITULO "Resultado do bootstrap"
printf '  destino..... : %s\n' "$(cd "$DESTINO" && pwd)"
printf '  arquivos.... : %s\n' "28 no manifesto SHA-256 (+ bootstrap.sh)"
printf '  permissões.. : 755 em scripts/testes, 644 em docs/dados\n'
printf '  python...... : %s\n' "$([[ "$ST_PY" == "0" ]] && echo 'compila' || echo 'FALHOU')"
printf '  bash........ : %s\n' "$([[ "$ST_SH" == "0" ]] && echo 'sem erro de sintaxe' || echo 'FALHOU')"
printf '  teste conf.. : %s\n' "$ST_CONF"
printf '  teste main.. : %s\n' "$ST_MAIN"
printf '  teste shell. : %s\n' "$ST_SH_T"
printf '  teste pipe.. : %s\n' "$ST_PIPE"
printf '\n  Próximos passos:\n'
printf '    cd %s\n' "$DESTINO"
printf '    python3 main.py 0001234-56.2024.8.17.2001   # consulta real (precisa de internet)\n'
printf '    make gates                                  # veredito de continuidade do pipeline\n'
printf '    make testes                                 # roda as 5 suítes de novo\n\n'

if [[ "$ST_PY" != "0" || "$ST_SH" != "0" || "$ST_CONF" == "FALHOU" \
      || "$ST_MAIN" == "FALHOU" || "$ST_SH_T" == "FALHOU" || "$ST_PIPE" == "FALHOU" ]]; then
  FALHA "bootstrap concluiu com falhas (veja acima)"
  exit 1
fi
printf '\033[1;32mBootstrap concluído com sucesso.\033[0m\n'
exit 0

# ==============================================================================
#  CONTEÚDO EMBUTIDO — cada bloco abaixo é um arquivo do projeto.
#  Formato:  __ARQ__ <caminho>  ... conteúdo ...  <marcador de fim>
# ==============================================================================

# Heredoc não executado: mantém o payload fora da análise do bash.
: <<'__PAYLOAD_FIM__'
__ARQ__ .github/workflows/gates.yml
# ==============================================================================
#  gates.yml — pipeline orientado a gates (blueprint tipo BPMN) no GitHub Actions
# ==============================================================================
#  Planta: pipeline/blueprint.json  ·  Executor: pipeline/gate.py
#
#  Fluxo (cada gate devolve o JSON do contrato e o exit code = status):
#
#    [push|PR|issues|schedule|dispatch]
#                 │
#          ┌──────┴───────┬──────────────┐
#          ▼              ▼              ▼
#     gate-issues     gate-cicd     gate-testes
#     (0/1/2)         (0/1/2)       (0/1/2)
#          └──────┬───────┴──────────────┘
#                 ▼
#        gate-continuidade   ← positivo ⇔ 0 issues ∧ CI limpo ∧ testes verdes
#           │        │
#       (1) │        │ (0)        (2) → job FALHA (exige humano)
#           ▼        ▼
#      executa-    pipeline pode
#       issue      encerrar
#     (0/1/2) ── 0 ⇒ próxima issue · 1 ⇒ mesma issue · 2 ⇒ humano
#
#  Todo gate publica: JSON no stdout, anexo em pipeline/saida/,
#  resumo no job summary e artifact para download.
# ==============================================================================
name: gates

on:
  push:
    branches: ["**"]
  pull_request:
  issues:
    types: [opened, closed, reopened, labeled]
  schedule:
    - cron: "0 12 * * 1-5"        # dias úteis, 12:00 UTC (09:00 em Brasília)
  workflow_dispatch:
    inputs:
      issue:
        description: "ID da issue do backlog a executar (vazio = próxima pendente)"
        required: false
        default: ""
      marcar:
        description: "Marcar a issue como concluída no backlog quando o teste passar"
        type: boolean
        required: false
        default: false

permissions:
  contents: read
  issues: read
  actions: read

env:
  GATE_SAIDA_DIR: pipeline/saida
  GH_TOKEN: ${{ github.token }}

concurrency:
  group: gates-${{ github.ref }}
  cancel-in-progress: false

jobs:
  # ---------------------------------------------------------------- gate 1: issues
  gate-issues:
    name: "gate 1 · issues abertas"
    runs-on: ubuntu-latest
    outputs:
      status: ${{ steps.gate.outputs.status }}
      continuidade: ${{ steps.gate.outputs.continuidade }}
    steps:
      - uses: actions/checkout@v5
      - name: Executar gate de issues
        id: gate
        run: |
          set +e
          python3 pipeline/gate.py issues --repo "$GITHUB_REPOSITORY" \
            --json-saida /tmp/gate-issues.json > /tmp/gate-issues.out 2>&1
          codigo=$?
          set -e
          cat /tmp/gate-issues.out
          status=$(python3 -c "import json;print(json.load(open('/tmp/gate-issues.json'))['status'])")
          cont=$(python3 -c "import json;print(str(json.load(open('/tmp/gate-issues.json'))['continuidade']).lower())")
          echo "status=$status" >> "$GITHUB_OUTPUT"
          echo "continuidade=$cont" >> "$GITHUB_OUTPUT"
          {
            echo "### gate 1 · issues abertas — status \`$status\`"
            echo
            python3 -c "import json;print(json.load(open('/tmp/gate-issues.json'))['mensagem'])"
          } >> "$GITHUB_STEP_SUMMARY"
          echo "exit do gate: $codigo (0=sucesso, 1=continuidade, 2=indeterminado)"
      - uses: actions/upload-artifact@v5
        if: always()
        with:
          name: gate-issues
          path: |
            pipeline/saida/issue*.md
            pipeline/saida/gate-issues-*.json
          if-no-files-found: warn

  # ------------------------------------------------------------------ gate 2: cicd
  gate-cicd:
    name: "gate 2 · CI/CD sem erros"
    runs-on: ubuntu-latest
    outputs:
      status: ${{ steps.gate.outputs.status }}
      continuidade: ${{ steps.gate.outputs.continuidade }}
    steps:
      - uses: actions/checkout@v5
      - name: Executar gate de CI/CD
        id: gate
        run: |
          set +e
          python3 pipeline/gate.py cicd --repo "$GITHUB_REPOSITORY" \
            --json-saida /tmp/gate-cicd.json > /tmp/gate-cicd.out 2>&1
          codigo=$?
          set -e
          cat /tmp/gate-cicd.out
          status=$(python3 -c "import json;print(json.load(open('/tmp/gate-cicd.json'))['status'])")
          cont=$(python3 -c "import json;print(str(json.load(open('/tmp/gate-cicd.json'))['continuidade']).lower())")
          echo "status=$status" >> "$GITHUB_OUTPUT"
          echo "continuidade=$cont" >> "$GITHUB_OUTPUT"
          {
            echo "### gate 2 · CI/CD — status \`$status\`"
            echo
            python3 -c "import json;print(json.load(open('/tmp/gate-cicd.json'))['mensagem'])"
          } >> "$GITHUB_STEP_SUMMARY"
      - uses: actions/upload-artifact@v5
        if: always()
        with:
          name: gate-cicd
          path: |
            pipeline/saida/execucoes-ci.md
            pipeline/saida/gate-cicd-*.json
          if-no-files-found: warn

  # ---------------------------------------------------------------- gate 3: testes
  gate-testes:
    name: "gate 3 · testes presentes e verdes"
    runs-on: ubuntu-latest
    outputs:
      status: ${{ steps.gate.outputs.status }}
      continuidade: ${{ steps.gate.outputs.continuidade }}
    steps:
      - uses: actions/checkout@v5
      - name: Executar gate de testes
        id: gate
        run: |
          set +e
          python3 pipeline/gate.py testes --json-saida /tmp/gate-testes.json \
            > /tmp/gate-testes.out 2>&1
          codigo=$?
          set -e
          cat /tmp/gate-testes.out
          status=$(python3 -c "import json;print(json.load(open('/tmp/gate-testes.json'))['status'])")
          cont=$(python3 -c "import json;print(str(json.load(open('/tmp/gate-testes.json'))['continuidade']).lower())")
          echo "status=$status" >> "$GITHUB_OUTPUT"
          echo "continuidade=$cont" >> "$GITHUB_OUTPUT"
          {
            echo "### gate 3 · testes — status \`$status\`"
            echo
            python3 -c "import json;print(json.load(open('/tmp/gate-testes.json'))['mensagem'])"
          } >> "$GITHUB_STEP_SUMMARY"
      - uses: actions/upload-artifact@v5
        if: always()
        with:
          name: gate-testes
          path: |
            pipeline/saida/log-testes-*.txt
            pipeline/saida/gate-testes-*.json
          if-no-files-found: warn

  # --------------------------------------------------------- gate 4: continuidade
  gate-continuidade:
    name: "gate 4 · veredito de continuidade"
    runs-on: ubuntu-latest
    needs: [gate-issues, gate-cicd, gate-testes]
    if: always()
    outputs:
      status: ${{ steps.gate.outputs.status }}
      continuidade: ${{ steps.gate.outputs.continuidade }}
      next_issue: ${{ steps.gate.outputs.next_issue }}
    steps:
      - uses: actions/checkout@v5
      - name: Agregar os três gates
        id: gate
        run: |
          set +e
          python3 pipeline/gate.py continuidade \
            --status-issues "${{ needs.gate-issues.outputs.status }}" \
            --status-cicd "${{ needs.gate-cicd.outputs.status }}" \
            --status-testes "${{ needs.gate-testes.outputs.status }}" \
            --json-saida /tmp/gate-continuidade.json > /tmp/gate-continuidade.out 2>&1
          codigo=$?
          set -e
          cat /tmp/gate-continuidade.out
          status=$(python3 -c "import json;print(json.load(open('/tmp/gate-continuidade.json'))['status'])")
          cont=$(python3 -c "import json;print(str(json.load(open('/tmp/gate-continuidade.json'))['continuidade']).lower())")
          prox=$(python3 -c "import json;print(json.load(open('/tmp/gate-continuidade.json'))['next_issue'] or '')")
          echo "status=$status" >> "$GITHUB_OUTPUT"
          echo "continuidade=$cont" >> "$GITHUB_OUTPUT"
          echo "next_issue=$prox" >> "$GITHUB_OUTPUT"
          {
            echo "### gate 4 · veredito — status \`$status\` (continuidade=\`$cont\`)"
            echo
            python3 -c "import json;print(json.load(open('/tmp/gate-continuidade.json'))['mensagem'])"
            echo
            echo "Próxima issue do backlog: \`${prox:-—}\`"
          } >> "$GITHUB_STEP_SUMMARY"
          if [ "$status" = "2" ]; then
            echo "::error::gate indeterminado (erro tipo 2) — exige intervenção humana"
            exit 1
          fi
          if [ "$status" = "1" ]; then
            echo "::notice::continuidade: há pendências — siga para a issue ${prox:-pendente}"
          else
            echo "::notice::gate positivo: nenhuma pendência, o pipeline pode encerrar"
          fi
      - uses: actions/upload-artifact@v5
        if: always()
        with:
          name: gate-continuidade
          path: |
            pipeline/saida/veredito-continuidade.md
            pipeline/saida/gate-continuidade-*.json
          if-no-files-found: warn

  # ------------------------------------------------- executa a issue (continuidade)
  executa-issue:
    name: "gate 5 · executa a issue (instrução → teste → próxima)"
    runs-on: ubuntu-latest
    needs: [gate-continuidade]
    if: needs.gate-continuidade.outputs.continuidade == 'true'
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v5
      - name: Rodar a instrução da issue do backlog
        id: issue
        run: |
          set +e
          argumentos=""
          [ -n "${{ inputs.issue }}" ] && argumentos="--id ${{ inputs.issue }}"
          [ "${{ inputs.marcar }}" = "true" ] && argumentos="$argumentos --marcar"
          python3 pipeline/gate.py issue $argumentos \
            --json-saida /tmp/gate-issue.json > /tmp/gate-issue.out 2>&1
          codigo=$?
          set -e
          cat /tmp/gate-issue.out
          status=$(python3 -c "import json;print(json.load(open('/tmp/gate-issue.json'))['status'])")
          prox=$(python3 -c "import json;print(json.load(open('/tmp/gate-issue.json'))['next_issue'] or '')")
          echo "status=$status" >> "$GITHUB_OUTPUT"
          echo "next_issue=$prox" >> "$GITHUB_OUTPUT"
          {
            echo "### gate 5 · issue — status \`$status\`"
            echo
            python3 -c "import json;print(json.load(open('/tmp/gate-issue.json'))['mensagem'])"
            echo
            echo "Próxima: \`${prox:-—}\` (instrução anexada em \`pipeline/saida/*-proxima-issue.md\`)"
          } >> "$GITHUB_STEP_SUMMARY"
          if [ "$status" = "2" ]; then exit 1; fi
          if [ "$status" = "1" ]; then
            echo "::warning::a issue ainda não passa — continuidade na MESMA issue (veja o log em anexo)"
          fi
      - name: Versionar o backlog atualizado (somente com marcar=true, fora de PR)
        if: inputs.marcar && github.event_name != 'pull_request'
        run: |
          if git diff --quiet -- pipeline/backlog.json; then
            echo "backlog sem alterações"
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add pipeline/backlog.json
          git commit -m "pipeline: issue ${{ steps.issue.outputs.next_issue || inputs.issue }} concluída (gate issue --marcar) [skip ci]"
          git push
      - uses: actions/upload-artifact@v5
        if: always()
        with:
          name: gate-issue
          path: |
            pipeline/saida/*-log.txt
            pipeline/saida/*-proxima-issue.md
            pipeline/saida/gate-issue-*.json
          if-no-files-found: warn
__ARQ_EOF__
__ARQ__ .gitignore
# artefatos gerados pelas consultas
saida/
*.jsonl
processos-*.jsonl
.datajud-key
__pycache__/
*.pyc
__ARQ_EOF__
__ARQ__ BOOTSTRAP.md
# BOOTSTRAP.md — criação, configuração, validação e testes do projeto

Este é o **documento único** do projeto: ele descreve como o `bootstrap.sh` recria
**tudo do zero** (todos os diretórios, todos os arquivos, todas as permissões), como
ele **valida e testa** o resultado, e qual é exatamente a **saída esperada** de cada
etapa. O `bootstrap.sh` é autossuficiente: traz o conteúdo dos 28 arquivos embutido —
não precisa de internet, Git nem de nenhum arquivo externo.

```bash
bash bootstrap.sh                      # cria ./projeto-datajud, valida e roda os 90 testes
bash bootstrap.sh --destino /opt/jus   # escolhe outro diretório
bash bootstrap.sh --verificar          # só confere um projeto já criado (hashes + permissões)
```

---

## 1. Uso em 30 segundos

| Situação | Comando |
| --- | --- |
| Recriar o projeto inteiro (local) | `bash bootstrap.sh` |
| Recriar em outro lugar | `bash bootstrap.sh --destino ~/projetos/datajud` |
| Sobrescrever um destino existente | `bash bootstrap.sh --destino ./x --forcar` |
| Criar sem rodar os testes | `bash bootstrap.sh --so-criar` |
| Conferir um projeto já criado | `bash bootstrap.sh --destino ./projeto-datajud --verificar` |
| Atualizar o bootstrap após editar um arquivo | `python3 tools/gerar_bootstrap.py` (ou `make bootstrap`) |
| Provar que o bootstrap recria o repo idêntico | `./tests/testar_bootstrap.sh` |

O `bootstrap.sh` não depende de rede. Só as consultas reais ao CNJ (comandos
`python3 main.py …` e `scripts/datajud.sh …`) precisam de internet.

---

## 2. Estrutura completa criada (diretórios, arquivos e permissões)

```
projeto-datajud/                        755   (diretório raiz)
├── .gitignore                          644
├── BOOTSTRAP.md                        644   este documento
├── Makefile                            644   atalhos (make consultar | relatorio | testes)
├── README.md                           644   porta de entrada
├── bootstrap.sh                        755   instalador/verificador (copia a si mesmo)
├── main.py                             755   consulta 1 processo → relatório Markdown
├── docs/                               755
│   ├── 01-api-datajud.md               644   referência da API pública do DataJud
│   ├── 02-receitas-curl-tjpe.md        644   receitas curl prontas (TJPE)
│   └── exemplo-saida/                  755
│       ├── relatorio-processo-exemplo.md   644   exemplo do relatório de processo
│       ├── relatorio-tjpe-exemplo.md       644   exemplo do relatório agregado
│       ├── agg-grau.tsv                    644   dados de exemplo (TSV)
│       └── agg-orgao-nome.csv              644   dados de exemplo (CSV)
├── scripts/                            755
│   └── datajud.sh                      755   CLI curl+jq: contar, agregar, relatório, paginar
├── tests/                              755
│   ├── mock_apis.py                    755   dublê local (DataJud + DJEN + wiki)
│   ├── mock_datajud.py                 755   dublê local (só DataJud, para o datajud.sh)
│   ├── rodar-testes.sh                 755   32 testes do scripts/datajud.sh
│   ├── testar_main.py                  755   29 testes do main.py
│   ├── testar_conformidade.py          755   29 testes de conformidade com a doc do CNJ
│   └── testar_bootstrap.sh             755   verificação do próprio bootstrap
└── tools/                              755
    └── gerar_bootstrap.py              755   regenera/conferê o bootstrap.sh
```

**Regra de permissões:** `755` para tudo que se executa (scripts, testes, `main.py`,
`bootstrap.sh`) e para diretórios; `644` para documentos e dados.

---

## 3. Pré-requisitos

| Dependência | Versão | Obrigatória? | Para quê |
| --- | --- | --- | --- |
| `bash` | 4.0+ | sim (para o bootstrap) | instalação, testes do `datajud.sh` |
| `python3` | 3.8+ | sim | `main.py`, mocks e suítes de teste |
| `curl` + `jq` | quaisquer | opcionais | apenas `scripts/datajud.sh` |
| internet | — | opcional | apenas consultas reais ao CNJ |

O bootstrap **para com erro claro** se faltar `bash`/`python3`. Se faltar `curl`/`jq`,
ele apenas avisa — porque o `main.py` não usa nenhum dos dois. Nada de `pip install`:
o projeto inteiro roda com a biblioteca padrão do Python.

---

## 4. As 7 etapas do bootstrap (e como cada uma falha)

| # | Etapa | O que faz | Falha se… |
| --- | --- | --- | --- |
| 1 | Pré-requisitos | valida bash 4+, python 3.8+, detecta curl/jq | versão mínima não atingida (sai com 1) |
| 2 | Diretórios | cria a raiz + `docs/`, `docs/exemplo-saida/`, `scripts/`, `tests/`, `tools/`; `chmod 755` | destino existe e não está vazio sem `--forcar` |
| 3 | Arquivos | escreve os 28 arquivos a partir do conteúdo embutido; aplica `755`/`644` | execução via pipe (avisa que o `bootstrap.sh` não pôde ser copiado) |
| 4 | Integridade | recalcula `sha256sum` de cada arquivo e compara com o manifesto | qualquer byte diferente → não segue (sai com 1) |
| 5 | Permissões | confere o modo de cada arquivo com `stat` | modo divergente → avisa (corrija com `chmod`) |
| 6 | Sintaxe | `python3 -m py_compile` em 9 arquivos ; `bash -n` em 4 scripts | qualquer erro de sintaxe |
| 7 | Testes | roda as 4 suítes offline e captura os códigos de saída | alguma suíte ≠ 0 |

O manifesto SHA-256 (na etapa 4) prova que o destino é **byte a byte** igual ao que o
bootstrap promete. É o que separa "criei arquivos" de "criei *este* projeto".

---

## 5. Validação conforme a documentação oficial do CNJ

Cada item abaixo é verificado automaticamente por `tests/testar_conformidade.py`
(29 testes). Fonte: wiki oficial do DataJud e Termo de Uso v1.2.

| Item da documentação | Onde está documentado | Como o projeto cumpre | Teste que verifica |
| --- | --- | --- | --- |
| URL base e rota `POST /api_publica_<alias>/_search` | [Acesso](https://datajud-wiki.cnj.jus.br/api-publica/acesso) / [Endpoints](https://datajud-wiki.cnj.jus.br/api-publica/endpoints) | `DATAJUD_BASE` + `api_publica_{alias}/_search` | `TesteAcesso.test_url_base_oficial`, `test_rota_search_com_alias` |
| Cabeçalho `Authorization: APIKey <chave>` | Acesso | enviado em todas as requisições | `test_cabecalho_authorization_apikey` |
| Cabeçalho `Content-Type: application/json` | Exemplos 1–3 | enviado em todo POST com corpo | `test_cabecalho_content_type_json` |
| Chave pública da wiki (pode mudar) | Acesso | embutida como default + comando `--chave-publica` relê a wiki | `test_chave_publica_vigente_embutida`, `test_comando_para_reler_a_chave_na_wiki` |
| Alias por tribunal | Endpoints | `J.TR` → alias (inclui `tjdft`, `tre-dft`, `tst`, `tse`) | `TesteEndpoints.*` |
| Campos do glossário | [Glossário](https://datajud-wiki.cnj.jus.br/api-publica/glossario) | 15 campos lidos e documentados | `TesteGlossario.*` |
| Busca por número | [Exemplo 1](https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo1) | `match` em `numeroProcesso` | `test_busca_por_numero_usa_match` |
| Filtros por classe/órgão | [Exemplo 2](https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo2) | `bool.must` com `classe.codigo`, `orgaoJulgador.codigo` | `test_filtros_por_classe_e_orgao` |
| Paginação `search_after` + `sort @timestamp asc` | [Exemplo 3](https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo3) | `paginar` usa o vetor `sort` da página anterior | `test_paginacao_com_search_after_e_sort_timestamp` |
| `size` entre 1 e 10.000 | Exemplo 3 | validado na CLI (`--pagina`) | `test_tamanho_de_pagina_dentro_do_limite` |
| Total truncado em 10.000 (`relation: gte`) | Considerações finais | avisa e sugere fatiar/agregar | `test_contagem_trata_teto_de_10000` |
| Agregações `terms` e `date_histogram` | Considerações finais | usa `calendar_interval` ano/mês | `test_agregacoes_terms_e_historico_de_datas` |
| `Fielddata is disabled` → usar `.keyword` | Exemplo 2 / boas práticas | fallback automático de campo | `test_fallback_para_campo_keyword` |
| **120 requisições/minuto** (Termo, 3.13) | [Termo de Uso](https://formularios.cnj.jus.br/wp-content/uploads/2023/11/Termos-de-uso-api-publica-V1.2.pdf) | pausas entre requisições e avisos | `TesteTermoDeUso.*` |
| Uso não comercial + ciência ao CNJ (3.3/3.8/3.9) | Termo | notas fixas no rodapé do relatório | `test_uso_nao_comercial_e_ciencia_ao_cnj_no_relatorio` |
| LGPD: não coletar dados pessoais (4.2/4.6) | Termo | nenhum campo de parte/CPF no código | `test_sem_dados_pessoais_coletados` |
| CNJ não garante precisão/atualidade (3.6) | Termo | aviso explícito na seção 10 do relatório | `test_avisos_de_limitacao_presentes_no_relatorio` |
| Numeração única e DV (Resolução CNJ 65/2008) | Res. 65, Anexo VIII | DV módulo 97 base 10, conferido contra números oficiais | `TesteNumeroCNJ.test_dv_de_numeros_reais_confere` |

**O que a API pública NÃO entrega** (e o relatório diz isso em vez de fingir): peças,
anexos, nomes/CPF das partes e valores. Autos e documentos ficam na consulta pública do
tribunal (PJe/e-SAJ) — o relatório inclui os links. Alternativa autenticada para
advogados: **MNI** do PJe, com certificado digital.

---

## 6. Códigos de teste: o que cada suíte cobre e o resultado esperado

Rode tudo de uma vez com `make testes`: são **5 suítes** e **151 verificações**, todas offline,
contra mocks locais (nenhuma requisição real ao CNJ).

| Suíte | Arquivo | Testes | Cobre | Saída esperada |
| --- | --- | --- | --- | --- |
| Conformidade | `tests/testar_conformidade.py` | **29** | itens da doc oficial (seção 5), ausência de dependências externas, shebang/permissões, sintaxe do shell | `Ran 29 tests` / `OK` / código **0** |
| Consulta de processo | `tests/testar_main.py` | **29** | DV e estrutura do NUP (4 números oficiais), decodificação de tribunais, as 10 seções do relatório, DJEN, `--json`, `-o`, erros 400/401/404/429 | `Ran 29 tests` / `OK` / código **0** |
| Consultas agregadas | `tests/rodar-testes.sh` | **32** | `contar`, `agregar` (com fallback de campo), `processo`, `paginar` (`search_after`), `relatorio`, tratamento de 401/404/429/rede, `--debug` | `32 passaram, 0 falharam` / código **0** |
| Pipeline de gates | `tests/testar_pipeline.py` | **36** | contrato JSON (`id`/`mensagem`/`anexos`/`status`/`next_issue`), semântica 0/1/2, `next_issue` (mesma issue × próxima), `--marcar`, blueprint, backlog e o workflow do Actions | `Ran 36 tests` / `OK (skipped=1)` / código **0** |
| Recriação | `tests/testar_bootstrap.sh` | **25** (7 grupos) | bootstrap atualizado, criação, `diff -r` contra o repo, permissões, suítes dentro do projeto novo, `--verificar`, proteção contra sobrescrita | `0 falharam` / código **0** |

Exemplo de saída final do `bootstrap.sh`:

```
== Resultado do bootstrap ==
  destino..... : /caminho/projeto-datajud
  arquivos.... : 28 no manifesto SHA-256 (+ bootstrap.sh)
  permissões.. : 755 em scripts/testes, 644 em docs/dados
  python...... : compila
  bash........ : sem erro de sintaxe
  teste conf.. : ok
  teste main.. : ok
  teste shell. : ok
  teste pipe.. : ok

  Próximos passos:
    cd /caminho/projeto-datajud
    python3 main.py 0001234-56.2024.8.17.2001   # consulta real (precisa de internet)
    make gates                                  # veredito de continuidade do pipeline
    make testes                                 # roda as 5 suítes de novo

Bootstrap concluído com sucesso.
```

## 7. Códigos de saída (exit codes)

| Artefato | Código | Significado |
| --- | --- | --- |
| `bootstrap.sh` | `0` | tudo criado, hashes conferidos e 90 testes passando |
| | `1` | pré-requisito ausente, hash divergente, sintaxe inválida ou suíte reprovada |
| `main.py` | `0` | relatório gerado |
| | `1` | uso incorreto (sem número do processo) |
| | `2` | falha de consulta (número inválido, 401/404/429, processo não encontrado) |
| | `130` | interrompido pelo usuário (Ctrl+C) |
| `scripts/datajud.sh` | `0` | comando concluído |
| | `1` | erro tratado (chave recusada, alias inexistente, limite de requisições, rede) |
| `tests/*` | `0` | todas as asserções passaram |
| | `1` | pelo menos uma falhou (a saída lista cada ✘) |

---

## 8. Verificação independente (como conferir sem confiar)

1. **Está atualizado?** `python3 tools/gerar_bootstrap.py --conferir` — falha se alguém
   editou um arquivo e esqueceu de regenerar o bootstrap.
2. **Recria idêntico?** `./tests/testar_bootstrap.sh` — cria num diretório temporário e
   roda `diff -r` contra o repositório; qualquer byte diferente é reportado.
3. **Integridade dos arquivos:** o próprio bootstrap recalcula `sha256sum` de cada
   arquivo e compara com o manifesto embutido (`--verificar` faz isso sozinho).
4. **Testes no projeto novo:** a suíte roda *dentro* da árvore recriada — não basta o
   código existir, ele precisa funcionar no destino.
5. **Sem efeitos colaterais:** nada é criado fora do `--destino`; os mocks usam portas
   efêmeras em `127.0.0.1` e nenhum teste acessa a internet.

---

## 9. Solução de problemas

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `destino já existe e não está vazio` | proteção contra sobrescrita | use `--forcar` ou outro `--destino` |
| `hash diferente: …` | destino alterado após a criação | apague o destino e rode de novo |
| `HTTP 401` nas consultas reais | o CNJ trocou a chave pública | `python3 main.py --chave-publica` e exporte `DATAJUD_API_KEY` |
| `HTTP 429` | passou de 120 req/min | aguarde; o projeto já pausa entre requisições |
| `curl e/ou jq ausentes` | só o `datajud.sh` depende deles | instale (`apt install curl jq`) ou use só o `main.py` |
| `nenhum documento …` no `main.py` | processo sigiloso ou tribunal errado | confirme o DV/tribunal; use `--todos` para varrer TJPE, TRF5, TRT6, TRE-PE, STJ, TST, TSE e STM |
| `bootstrap.sh está DESATUALIZADO` | arquivos editados após a geração | `python3 tools/gerar_bootstrap.py` |

---

## 10. Regras de uso dos dados (Termo de Uso v1.2 + LGPD)

- **120 requisições por minuto** no máximo (item 3.13); o CNJ pode limitar sem aviso (3.14).
- Uso **legal e não comercial** (3.3, 3.8).
- O CNJ **não garante** precisão, integridade ou atualidade (3.6).
- Ao divulgar relatórios, **dê ciência ao CNJ** (3.9).
- Não coletar, armazenar ou cruzar dados pessoais (4.2, 4.6 — LGPD).
- A API expõe **metadados de processos públicos**; partes, valores e peças não são dela.

---

## 11. Manutenção

| Quando | Faça |
| --- | --- |
| Mudou qualquer arquivo do projeto | `python3 tools/gerar_bootstrap.py` (regenera) e `./tests/testar_bootstrap.sh` |
| O CNJ trocou a chave pública | nada a mudar no código: use `--chave-publica`/`DATAJUD_API_KEY`; opcionalmente atualize o default no `main.py` e no `scripts/datajud.sh` |
| Adicionou um arquivo novo | inclua-o em `ARQUIVOS` no `tools/gerar_bootstrap.py` (com a permissão) e regenere |
| Quer só validar | `bash bootstrap.sh --destino . --verificar` |
__ARQ_EOF__
__ARQ__ ENTREGA.md
# ENTREGA — branch `arena/ed79bd77-llm-arena-opencli`

Relatório de entrega do branch: **o que foi solicitado → incrementado à solicitação (timeline)
→ realizado → testado → validado → pronto para produção**.

- **Repositório:** https://github.com/camillanapoles/llm-arena-opencli
- **Branch:** `arena/ed79bd77-llm-arena-opencli` (base: `main` em `3d9b774`)
- **Pull request:** https://github.com/camillanapoles/llm-arena-opencli/pull/2 — OPEN / MERGEABLE
- **Data da entrega:** 13/10/2026
- **Situação:** pronto para uso — `bash bootstrap.sh` recria o projeto inteiro do zero;
  `make gates` diz se há pendências; `python3 main.py <processo>` consulta a Justiça de verdade.

---

## 1. Resumo executivo

| # | Solicitado | Entregue | Evidência |
| --- | --- | --- | --- |
| 1 | Consultar processos e contar por órgão/grau no TJPE usando a **API pública do CNJ** por `curl` | `scripts/datajud.sh` (7 subcomandos, mesma semântica da wiki do CNJ) + `docs/01`, `docs/02` + exemplos de saída | 32 verificações |
| 2 | Script **completo** em Python, na raiz, com **relatório em Markdown**, cobrindo "o processo, os anexos, tudo que puder" — e todo o público (DataJud + DJEN) | `main.py` (1 arquivo, sem dependências externas): DataJud + DJEN + montagem de número/validação de DV + relatório Markdown com anexos | 29 testes |
| 3 | **Validar conforme a documentação** e um **bootstrap que auto-cria o projeto** (todos os arquivos, todas as permissões) **e valida os testes, verificando resultado e códigos de teste** | `tests/testar_conformidade.py` (conferência contra a wiki/CNJ) + `bootstrap.sh` autossuficiente (7 etapas, manifesto SHA-256, `py_compile`, `bash -n`, suítes) + `BOOTSTRAP.md` | 29 + 25 verificações |
| 4 | **Gatilho** que só é positivo sem issues abertas, sem CI com erro e com testes verdes; **enquanto não positivo ⇒ continuidade**; cada issue testada e entregue com a instrução da seguinte; **toda action devolve JSON** (`id`, `mensagem`, `anexos`, `status`, `next_issue`) | `pipeline/gate.py` + `pipeline/blueprint.json` (BPMN) + `pipeline/backlog.json` + `.github/workflows/gates.yml` + `docs/03` + esta `ENTREGA.md` | 36 testes |

**Total: 151 verificações automatizadas**, todas offline, em 5 suítes (`make testes`).

---

## 2. Timeline completa

### 2.1 Solicitado (o pedido original, em quatro blocos)

| Data | Pedido |
| --- | --- |
| 11/10 | "consultar processos do TJPE pela API pública do CNJ, por curl; contar por órgão julgador e grau" |
| 12/10 | "script **completo** em `main.py`, saída em **Markdown**, 'o processo, os anexos, tudo que puder' — todo o público (DataJud + DJEN)" |
| 12/10 | "**validar conforme doc**" + "**bootstrap** que auto-**cria** o projeto completo (diretórios, arquivos, permissões), monta/configura tudo e **valida os testes, conferindo resultado e códigos de teste" |
| 13/10 | "**RELATE O QUE ESTÁ ENTREGANDO NESTE BRANCH… DOCUMENTE**: solicitado, incrementado (TIMELINE), realizado, testado, validado ⇒ **PRODUÇÃO** (pronto para uso pelo usuário)" |

### 2.2 Incrementado à solicitação (o que foi acrescentado ao pedido, e por quê)

| Incremento | Origem | Por quê |
| --- | --- | --- |
| **DJEN (Res. CNJ 455/2022)** somado ao DataJud no mesmo relatório | pedido 2 ("todo o público") | DataJud dá metadados do processo; as *publicações* (intimações) só estão no Diário de Justiça Eletrônico Nacional. Sem DJEN o relatório ficaria pela metade |
| Construção/validação do **número único CNJ** (`NNNNNNN-DD.AAAA.J.TR.OOOO`, Res. 65/2008) | necessidade prática | Sem isso, qualquer dígito trocado gera consulta vazia indistinguível de "processo sem publicação" |
| **Glossário dos 15 campos** do DataJud em português + mapeamento `tjdft`→`tjdf`, `tre-*` | pedido 1 | Os códigos de tribunal da API não são óbvios; erro de sigla é o erro nº 1 de quem usa a API |
| **Resiliência**: paginação por `search_after`, teto de 10.000 hits, agregações com fallback `.keyword`, respeito ao limite de 120 req/min | pedido 1 | Sem isso o kit quebra exatamente nos tribunais grandes |
| **LGPD explícita**: nenhuma consulta por nome de parte ou CPF, nenhum campo de parte no relatório | Termo de Uso do CNJ | A API é pública mas restrita a metadados processuais; o teste proíbe esses campos |
| **Bootstrap autossuficiente** com manifesto **SHA-256**, `py_compile`, `bash -n` e execução das suítes no destino | pedido 3 ("verificando resultado e **códigos de teste**") | Entrega não é "gerar arquivos": é provar que o que foi gerado funciona, e com código de saída verificável |
| **Pipeline de gates** (blueprint tipo BPMN) + fila de issues **indexada** | pedido 4 | Transforma a entrega num fluxo que se auto-verifica a cada push/PR/issue, em vez de um relatório morto |
| **Erro tipo 1 × erro tipo 2** no `status` | pedido 4 | Separar "pendência tratável, continue" de "não dá para avaliar, chame humano" é o que permite o gatilho decidir sem adivinhação |
| `pipeline/verificar_cnj.py` como **instrução executável** da ISSUE-006 | pedido 4 | "Toda issue tem instrução de teste": até a validação ao vivo precisa ser um comando reprodutível com código de saída |

### 2.3 Realizado (linha do tempo de execução)

| Quando | Marco |
| --- | --- |
| 11/10 20:42 | `3d9b774` — commit inicial do repositório |
| 12/10 21:33 | `3bd0cc4` — **kit de consulta à API Pública do DataJud** (curl + CLI + docs) |
| 12/10 22:10 | `17b35aa` — **`main.py`**: consulta de processo com relatório completo em Markdown |
| 12/10 22:11 | `aa5a5f4` — `__pycache__`/`.pyc` fora do versionamento |
| 12/10 22:30 | `436253a` — **`bootstrap.sh` auto-criador + `BOOTSTRAP.md` + validação de conformidade** |
| 12/10 22:4x | **PR #2** aberto (base `main` ← branch), +9.347/−1 em 20 arquivos |
| 13/10 | **Pedido 4**: `pipeline/gate.py`, `blueprint.json`, `backlog.json`, `.github/workflows/gates.yml`, `docs/03`, `tests/testar_pipeline.py`, `pipeline/verificar_cnj.py`, esta `ENTREGA.md`, Makefile com alvos de gate, bootstrap regenerado |

### 2.4 Testado (5 suítes, 151 verificações, tudo offline)

| Suíte | Verificações | O que cobre |
| --- | --- | --- |
| `tests/testar_conformidade.py` | 29 | conformidade com a doc oficial do CNJ: URL/rota/headers, aliases de tribunal, 15 campos do glossário, `search_after`, teto de 10.000, agregações com `.keyword`, 120 req/min, LGPD |
| `tests/testar_main.py` | 29 | `main.py`: DV do número CNJ (`% 97 == 1`), montagem do número de 20 dígitos, DataJud + DJEN com mocks, relatório Markdown, anexos, exit codes |
| `tests/rodar-testes.sh` | 32 | `scripts/datajud.sh`: chave pública, consulta, contagem, agregação, relatório, paginação, erros |
| `tests/testar_pipeline.py` | 36 | contrato JSON em todos os gates, semântica 0/1/2, `next_issue`, `--marcar`, blueprint, backlog e o próprio workflow |
| `tests/testar_bootstrap.sh` | 25 | bootstrap atualizado, criação byte a byte vs. repositório, permissões, 4 suítes rodando **dentro** do projeto recriado, gates rodando no projeto recriado, `--verificar`, proteção contra sobrescrita |

### 2.5 Validado (como cada promessa foi conferida)

| Validação | Comando | Resultado |
| --- | --- | --- |
| Conformidade com a documentação do CNJ | `python3 tests/testar_conformidade.py` | 29/29 OK |
| Bootstrap recria o projeto **idêntico** | `bash tests/testar_bootstrap.sh` | 25/25 OK, `diff -r` sem diferenças, hashes conferem |
| Planta BPMN × implementação | `python3 pipeline/gate.py blueprint` | `status "0"` — *5 gates, 15 transições* |
| Gatilho de continuidade | `python3 pipeline/gate.py continuidade` | `status "1"` (há issue aberta) — **continuidade**, como manda a regra |
| CI/CD | `python3 pipeline/gate.py cicd` | `status "0"` — 5 execuções, nenhuma com erro |
| Testes | `python3 pipeline/gate.py testes` | `status "0"` — 151 verificações aprovadas |
| Sem fonte de dados (`gh` ausente) | `python3 pipeline/gate.py issues --sem-gh` | `status "2"` (erro tipo 2) — não inventa sucesso |
| Projeto reconstruído funciona | `bash bootstrap.sh --destino /tmp/x` | 7/7 etapas ✔, exit 0 |

### 2.6 Produção (pronto para uso)

```bash
git clone https://github.com/camillanapoles/llm-arena-opencli && cd llm-arena-opencli

make testes        # 5 suítes, 151 verificações, offline
make gates         # veredito: 0 = nada pendente · 1 = continuidade · 2 = exige humano
make consultar NUMERO=0001234-43.2024.8.17.2001   # relatório Markdown do processo (rede real)
bash bootstrap.sh --destino ./projeto-datajud      # recria o projeto inteiro do zero
```

---

## 3. O que este branch entrega, arquivo por arquivo

```
main.py                     consulta de processo + relatório Markdown (DataJud + DJEN)
scripts/datajud.sh          kit curl (chave|processo|contar|agregar|relatorio|paginar)
docs/01-api-datajud.md      manual da API (endpoints, campos, limites, LGPD)
docs/02-receitas-curl-tjpe.md  receitas prontas de curl para o TJPE
docs/03-pipeline-gates.md   manual do pipeline de gates (contrato JSON, 0/1/2, BPMN)
docs/exemplo-saida/         exemplos de relatórios e agregações já gerados

pipeline/gate.py            executor dos gates (7 subcomandos) — o "gatilho"
pipeline/blueprint.json     planta BPMN do fluxo (validada pelo próprio pipeline)
pipeline/backlog.json       fila indexada de issues (instrução de teste por issue)
pipeline/verificar_cnj.py   instrução executável da ISSUE-006 (validação ao vivo do CNJ)
.github/workflows/gates.yml gatilho no GitHub Actions (5 jobs encadeados)

bootstrap.sh                recria o projeto inteiro e prova que funciona
tools/gerar_bootstrap.py    gerador/verificador do bootstrap (--conferir)
BOOTSTRAP.md                manual do bootstrap
ENTREGA.md                  este relatório

tests/                      5 suítes, 151 verificações (offline, com mocks)
```

---

## 4. O gatilho e o contrato JSON (pedido 4, em uma página)

### 4.1 Regra do gatilho

> O gate **só é positivo** quando, ao mesmo tempo: **(a)** não existe issue aberta,
> **(b)** nenhuma execução de CI/CD terminou com erro e **(c)** os testes existem e passam.
> **Enquanto não for positivo ⇒ `continuidade = true`** e o fluxo segue para a próxima
> pendência do backlog. Se um check não puder nem ser avaliado, o status é `2` e o
> pipeline **para** (exige humano) — nunca "chuta" sucesso.

```bash
python3 pipeline/gate.py continuidade \
  --status-issues 0 --status-cicd 0 --status-testes 0   # ⇒ status "0", continuidade false
```

### 4.2 Toda action devolve o mesmo objeto

```json
{
  "id": "gate-issue-20261013T141702Z-4c9ab1",
  "gate": "issue",
  "status": "0",
  "codigo_saida": 0,
  "mensagem": "ISSUE-005 testada com sucesso (código 0) — segue a issue ISSUE-006: ...",
  "continuidade": true,
  "next_issue": "ISSUE-006",
  "anexos": [
    {"path": "pipeline/saida/ISSUE-005-proxima-issue.md",
     "filename": "ISSUE-005-proxima-issue.md",
     "descricao": "instrução da issue seguinte do backlog"}
  ],
  "dados": {"criterio": ">= 1 issue aberta", "abertas": 1},
  "timestamp": "2026-10-13T14:17:02Z",
  "duracao_s": 0.31,
  "versao": "1.0.0"
}
```

| `status` | Significado | `continuidade` | `next_issue` |
| --- | --- | --- | --- |
| `"0"` | sucesso: nada pendente | `false` | próxima indexada (ou `null` se acabou) |
| `"1"` | **erro tipo 1**: pendência conhecida e tratável | **`true`** | **a mesma issue** (falhou) |
| `"2"` | **erro tipo 2**: não foi possível avaliar (exige humano) | `false` | `null` ou a issue bloqueada |

O **exit code do processo é igual ao `status`**, então qualquer orquestrador (Actions,
cron, Makefile) encadeia os gates sem parsear nada — e ainda assim recebe o JSON completo
com `mensagem` (log/resumo) e `anexos` (`path` + `filename`).

### 4.3 Como o fluxo fecha o ciclo

1. Os gates 1–3 medem issues, CI/CD e testes **em paralelo**.
2. O gate 4 agrega os três (recebendo os status por `--status-*`, sem reexecutar nada).
3. Se `continuidade = true`, o gate 5 **executa a instrução da próxima issue do backlog**:
   - passou ⇒ `next_issue` = **próxima indexada**, e o anexo `*-proxima-issue.md` traz a
     instrução pronta (com o comando) para o ciclo seguinte;
   - falhou ⇒ `next_issue` = **a mesma issue**, com o log anexado;
   - com `--marcar`, a conclusão é persistida no `backlog.json` (o workflow commita com `[skip ci]`).
4. Volta ao passo 1. O ciclo se repete enquanto houver pendência — é isso que significa
   *gate-driven pipeline*.

---

## 5. Estado atual do pipeline (medido, não presumido)

```text
gate 1 · issues        → status "1"  (1 issue aberta: #3 SESSION CONTINUITY CONTROL)
gate 2 · CI/CD         → status "0"  (5 execuções analisadas, 0 com erro)
gate 3 · testes        → status "0"  (5 suítes aprovadas, 151 verificações)
gate 4 · continuidade  → status "1"  ⇒ continua; próxima do backlog: ISSUE-006
gate 5 · issue         → executa a ISSUE-006 quando o ambiente tiver internet
```

Backlog do projeto (`pipeline/backlog.json`):

| Issue | Título | Status |
| --- | --- | --- |
| ISSUE-001 | Kit de consulta por `curl` (DataJud/TJPE) | concluída |
| ISSUE-002 | `main.py` + relatório Markdown (DataJud + DJEN) | concluída |
| ISSUE-003 | Bootstrap auto-criador do projeto | concluída |
| ISSUE-004 | Validação de conformidade com a documentação do CNJ | concluída |
| ISSUE-005 | Pipeline de gates (contrato JSON, 0/1/2) | concluída |
| ISSUE-006 | Validação **ao vivo** contra o CNJ (`pipeline/verificar_cnj.py`) | **pendente** |
| ISSUE-007 | Decidir unificação com o fluxo da issue #3 (outra sessão) | bloqueada (decisão humana) |

---

## 6. Limitações conhecidas e próximos passos

| Limitação | Detalhe | Próximo passo |
| --- | --- | --- |
| Validação **ao vivo** do CNJ (ISSUE-006) | o ambiente de desenvolvimento não tem rota até `api-publica.datajud.cnj.jus.br` (TLS encerrado pelo proxy) — `pipeline/verificar_cnj.py` devolve honestamente `status "1"`/continuidade | rodar `python3 pipeline/verificar_cnj.py` numa máquina com internet; `status "0"` ⇒ `gate.py issue --id ISSUE-006 --marcar` |
| ISSUE-007 (unificação com a issue #3, de outra sessão) | o outro fluxo não está em `main` (`.github/workflows` → 404 no ref `main`) e vive na issue #3; não foi tocado | gate devolve `2` de propósito: requer decisão do usuário |
| YAML do workflow | não há PyYAML no ambiente de desenvolvimento; a checagem local é estrutural (indentação, tabulação, gatilhos, jobs) | a validação definitiva é a execução real do workflow no GitHub Actions — visível em **Actions → gates** |
| Permissão de escrita do bot | o job `executa-issue` só commita o backlog quando disparado com `marcar=true` (e o repositório precisa permitir "Read and write permissions" para o `GITHUB_TOKEN`) | conferir em **Settings → Actions → General → Workflow permissions** |
| Consulta pública do TJPE (Projudi/PJe) | as URLs do TJPE não respondem fora da rede da Justiça (`srv01…`, `pje.cloud…`) | usar o kit em rede compatível; o DataJud/DJEN cobrem o que é público nacional |

---

## 7. Checklist final de entrega

- [x] **Solicitado** — os 4 pedidos implementados no branch (kit curl, `main.py` Markdown, conformidade + bootstrap, pipeline de gates documentado)
- [x] **Incrementado** — DJEN, número CNJ, glossário, resiliência, LGPD, manifesto SHA-256, erro tipo 1 × 2, verificador ao vivo (seção 2.2)
- [x] **Realizado** — 5 marcos de commit + 9 arquivos novos, tudo versionado no branch (seção 2.3)
- [x] **Testado** — 5 suítes, **151 verificações**, todas offline e reprodutíveis (seção 2.4)
- [x] **Validado** — conformidade com a doc do CNJ, bootstrap byte a byte, planta BPMN, semântica 0/1/2, projeto recriado do zero (seção 2.5)
- [x] **Produção** — `make testes`, `make gates`, `make consultar`, `bash bootstrap.sh` prontos para uso (seção 2.6)
- [x] **Documentado** — `README.md` (visão geral), `BOOTSTRAP.md` (instalação), `docs/01-03` (API, receitas, pipeline) e esta `ENTREGA.md`
- [ ] **Pendente do usuário** — rodar a validação ao vivo do CNJ (ISSUE-006) num ambiente com internet e decidir a ISSUE-007
__ARQ_EOF__
__ARQ__ Makefile
# Atalhos para o kit DataJud (API Pública do CNJ)
TRIBUNAL ?= tjpe
SAIDA    ?= saida
LIMITE   ?= 1000
# processo de exemplo (DV válido) usado por `make consultar`
NUMERO   ?= 0001234-43.2024.8.17.2001

.PHONY: ajuda chave chave-publica consultar contar processo relatorio paginar testes limpar \
        bootstrap regenerar-bootstrap verificar \
        gates gate-issues gate-cicd gate-testes gate-issue gate-situacao blueprint testes-pipeline

ajuda: ## mostra o manual do script
	@bash scripts/datajud.sh ajuda

chave: ## imprime a chave pública vigente publicada na wiki do CNJ
	@bash scripts/datajud.sh chave

chave-publica: ## idem, usando o main.py (Python)
	@python3 main.py --chave-publica

consultar: ## relatório de UM processo: make consultar NUMERO=0001234-43.2024.8.17.2001
	@python3 main.py "$(NUMERO)" --todos

contar: ## conta os processos do tribunal informado (TRIBUNAL=tjpe)
	@bash scripts/datajud.sh contar --tribunal $(TRIBUNAL)

processo: ## consulta um processo: make processo NUMERO=0001234-56.2024.8.17.2001
	@bash scripts/datajud.sh processo "$(NUMERO)" --tribunal $(TRIBUNAL)

relatorio: ## gera o relatório em markdown/csv (SAIDA=saida)
	@bash scripts/datajud.sh relatorio --tribunal $(TRIBUNAL) --saida $(SAIDA)

paginar: ## baixa processos em JSONL (LIMITE=1000)
	@bash scripts/datajud.sh paginar --tribunal $(TRIBUNAL) --limite $(LIMITE) --saida processos-$(TRIBUNAL).jsonl

testes: ## roda as suítes offline (conformidade + main.py + datajud.sh + pipeline + bootstrap)
	@python3 tests/testar_conformidade.py
	@python3 tests/testar_main.py
	@bash tests/rodar-testes.sh
	@python3 tests/testar_pipeline.py
	@bash tests/testar_bootstrap.sh

testes-pipeline: ## roda só a suíte do pipeline de gates (offline)
	@python3 tests/testar_pipeline.py

gates: ## veredito de continuidade (0=sem pendências, 1=continuidade, 2=humano)
	@python3 pipeline/gate.py continuidade ; true

gate-issues: ## gate 1 — existem issues abertas?
	@python3 pipeline/gate.py issues ; true

gate-cicd: ## gate 2 — há execução de CI/CD com erro?
	@python3 pipeline/gate.py cicd ; true

gate-testes: ## gate 3 — testes presentes e verdes?
	@python3 pipeline/gate.py testes ; true

gate-issue: ## executa a próxima issue do backlog (ISSUE=ISSUE-00N, MARCAR=--marcar)
	@python3 pipeline/gate.py issue $$( [ -n "$(ISSUE)" ] && echo "--id $(ISSUE)" ) $(MARCAR) ; true

gate-situacao: ## histórico do pipeline (últimos resultados gravados)
	@python3 pipeline/gate.py situacao ; true

blueprint: ## valida a planta BPMN do pipeline (pipeline/blueprint.json)
	@python3 pipeline/gate.py blueprint ; true

bootstrap: ## cria o projeto completo do zero (DIR=./projeto-datajud)
	@bash bootstrap.sh --destino "$${DIR:-./projeto-datajud}"

regenerar-bootstrap: ## regera o bootstrap.sh a partir dos arquivos atuais
	@python3 tools/gerar_bootstrap.py

verificar: ## confere hashes e permissões do projeto atual (DIR=.)
	@bash bootstrap.sh --destino "$${DIR:-.}" --verificar

limpar: ## remove artefatos gerados
	rm -rf $(SAIDA) processos-*.jsonl
__ARQ_EOF__
__ARQ__ README.md
# llm-arena-opencli — consulta processual nas APIs públicas do CNJ

Consulta um processo judicial e gera um **relatório em Markdown** com tudo o que as APIs
públicas do CNJ entregam: capa, partes(*) e movimentações (DataJud) + publicações, intimações
e inteiro teor (DJEN).

```bash
python3 main.py 0001234-56.2024.8.17.2001            # relatório em Markdown no terminal
python3 main.py 0001234-56.2024.8.17.2001 -o rel.md  # grava em arquivo
python3 main.py 0001234-56.2024.8.17.2001 --json     # JSON cru das duas APIs
```

    (*) a API do DataJud não expõe nome/CPF das partes — veja "Anexos e documentos" abaixo.

| Arquivo | Para que serve |
| --- | --- |
| **`main.py`** | consulta **um processo** (DataJud + DJEN) e gera relatório completo em Markdown |
| `scripts/datajud.sh` | CLI `curl`+`jq`: contagens, agregações e relatórios **agregados** (por classe, vara, ano…) |
| `docs/01-api-datajud.md` | referência da API do DataJud (acesso, campos, DSL, erros, regras) |
| `docs/02-receitas-curl-tjpe.md` | receitas `curl` prontas para o TJPE |
| `docs/03-pipeline-gates.md` | manual do **pipeline de gates** (contrato JSON, 0/1/2, planta BPMN) |
| **`pipeline/gate.py`** + `pipeline/blueprint.json` + `pipeline/backlog.json` | **gatilho** de continuidade: mede issues/CI/testes, diz o que fazer agora e devolve JSON |
| `docs/exemplo-saida/` | exemplo do relatório de processo e do relatório agregado |
| `tests/` | mock local das APIs + 5 suítes de teste offline (**151 verificações**) |
| **`bootstrap.sh`** + `BOOTSTRAP.md` | recriam/configuram o projeto inteiro (arquivos, permissões, hashes) e validam tudo |
| `.github/workflows/gates.yml` | roda os gates no GitHub Actions (push, PR, issue, agenda, manual) |
| **`ENTREGA.md`** | relatório de entrega do branch: solicitado → incrementado → realizado → testado → validado → produção |

Requisitos: **Python 3.8+** (só biblioteca padrão) para o `main.py`; `bash`, `curl` e `jq` para o `scripts/datajud.sh`.

---

## 1. Consultar um processo (`main.py`)

```bash
python3 main.py 0001234-56.2024.8.17.2001               # TJPE (deduzido do número CNJ)
python3 main.py 0001234-56.2024.8.17.2001 -o processo.md
python3 main.py 0000832-35.2018.4.01.3202               # TRF1
python3 main.py 0001234-56.2024.8.17.2001 --todos       # varre TJPE, TRF5, TRT6, TRE-PE, STJ, TST, TSE, STM
python3 main.py 0001234-56.2024.8.17.2001 --sem-djen    # só DataJud
python3 main.py --chave-publica                         # imprime a chave pública vigente da wiki
```

O script lê o **número único (Resolução CNJ 65/2008)**: valida o dígito verificador (módulo 97
base 10), descobre o tribunal pelo campo `J.TR` e escolhe o índice correto do DataJud — inclusive
os casos especiais (`8.07` → `tjdft`, `6.07` → `tre-dft`, `5.00` → `tst`).

### O que entra no relatório

1. **Resumo executivo** — tribunal, grau(s), classe, órgão julgador, ajuizamento, nº de movimentações, última movimentação, publicações no DJEN.
2. **Identificação e validação do número** — DV conferido, campos `NNNNNNN/DD/AAAA/J/TR/OOOO` decodificados.
3. **Capa do processo** — classe e assuntos (TPU), órgão julgador + município (IBGE), sigilo, formato, sistema, datas de atualização. Um bloco por grau encontrado (G1 e G2).
4. **Movimentações processuais** — tabela completa (data/hora, código TPU, nome, complementos tabelados, órgão).
5. **Panorama estatístico** — movimentações por ano (com gráfico de barras), movimentos mais frequentes, órgãos, maior intervalo sem movimentação, janela temporal e dias de inércia.
6. **Publicações e intimações (DJEN)** — disponibilização, tipo, órgão, texto e link do inteiro teor.
7. **Anexos e documentos** — o que é público, onde buscar os autos e o que a API não entrega.
8. **Links oficiais de consulta** — TJPE/PJe 1º e 2º grau, portal, DJe, DJEN.
9. **Índices consultados** — rastreabilidade (documentos por índice, erros).
10. **Notas, limitações e conformidade** — Termo de Uso e LGPD.

Exemplo completo: [`docs/exemplo-saida/relatorio-processo-exemplo.md`](docs/exemplo-saida/relatorio-processo-exemplo.md).

### Opções

| Opção | Efeito |
| --- | --- |
| `-o, --saida ARQUIVO` | grava o relatório no arquivo (.md ou .json) |
| `--json` | devolve o JSON cru (DataJud + DJEN) em vez do Markdown |
| `--todos` | procura também em TRF5, TRT6, TRE-PE, STJ, TST, TSE e STM |
| `--buscar-em tjpe,trf5` | escolhe manualmente os índices do DataJud |
| `--sem-djen` | não consulta as publicações |
| `--chave-publica` | imprime a chave pública vigente da wiki do CNJ |
| `-k, --chave-api CHAVE` | usa outra chave do DataJud |
| `--debug` | mostra as requisições HTTP (com a chave mascarada) |
| `-q, --quieto` | silencia o progresso (stderr) |

Variáveis: `DATAJUD_API_KEY`, `DATAJUD_BASE_URL`, `DJEN_BASE_URL`, `DATAJUD_TIMEOUT`.

### Anexos e documentos: o que dá e o que não dá

Ser honesto aqui evita frustração: **a API Pública do DataJud não devolve peças nem anexos** —
ela expõe metadados (número, classe, assuntos, órgão, datas, movimentações). O relatório deixa
isso explícito e aponta os caminhos públicos:

| O que | Onde |
| --- | --- |
| Movimentações e metadados | DataJud (já no relatório) |
| Publicações/intimações e **inteiro teor em PDF** | DJEN/Comunica (link no relatório) |
| **Autos, petições, decisões e anexos** | Consulta pública do tribunal: [PJe 1º grau TJPE](https://pje.cloud.tjpe.jus.br/1g/ConsultaPublica/listView.seam), [PJe 2º grau](https://pje.cloud.tjpe.jus.br/2g/ConsultaPublica/listView.seam), [consulta unificada](http://srv01.tjpe.jus.br/consultaprocessualunificada/) |
| Partes (nome, CPF/CNPJ), valores | autos no portal do tribunal — a API pública não expõe |
| Integração autenticada (advogado) | MNI do PJe, com certificado digital |

Processo em **segredo de justiça** não aparece em nenhuma consulta pública: o acesso é restrito
às partes e advogados habilitados.

---

## 2. Consultas agregadas (`scripts/datajud.sh`)


---

## Início rápido

```bash
# 1) contar os processos públicos do TJPE
./scripts/datajud.sh contar --tribunal tjpe

# 2) consultar um processo (numeração única CNJ, sem máscara)
./scripts/datajud.sh processo 0001234-56.2024.8.17.2001 --tribunal tjpe

# 3) gerar o relatório completo (Markdown + TSV/CSV) em ./saida
./scripts/datajud.sh relatorio --tribunal tjpe --saida saida

# 4) ver o curl equivalente a qualquer comando (para copiar/colar ou auditar)
./scripts/datajud.sh --debug contar --tribunal tjpe --classe 1116
```

O curl "cru", sem script, é só isto:

```bash
CHAVE="cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw=="

curl -sS -X POST "https://api-publica.datajud.cnj.jus.br/api_publica_tjpe/_search" \
  -H "Authorization: APIKey $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{ "query": { "match_all": {} }, "size": 0, "track_total_hits": true }' \
  | jq '.hits.total'
```

> A chave é **pública**, publicada na [wiki do CNJ](https://datajud-wiki.cnj.jus.br/api-publica/acesso),
> e pode ser trocada a qualquer momento. Atualize com
> `export DATAJUD_API_KEY="$(bash scripts/datajud.sh chave)"`.

---

## Comandos do script

| Comando | O que faz |
| --- | --- |
| `chave` | lê a chave pública vigente na wiki do CNJ |
| `processo <numero>` | busca 1 processo pela numeração única CNJ (aceita máscara; normaliza para dígitos) |
| `contar` | conta processos do filtro (trata o teto de 10.000 / `relation: gte`) |
| `agregar <campo>` | agrupa e conta por classe, órgão julgador, assunto, grau, ano, mês… |
| `relatorio` | 1 requisição de total + 7 agregações → `.md` + `.tsv`/`.csv` |
| `paginar` | varre resultados com `search_after`, gravando JSONL |
| `ajuda` | manual completo |

Filtros disponíveis: `--tribunal`, `--classe`, `--assunto`, `--orgao`, `--municipio`, `--grau`, `--de`,
`--ate`, `--sigilo`. Opções: `--top`, `--json`, `--saida`, `--limite`, `--pagina`, `--pausa`, `--debug`.

```bash
# execuções fiscais (classe 1116) por vara, apenas de 2024
./scripts/datajud.sh agregar orgao-nome --classe 1116 --de 2024-01-01 --ate 2024-12-31 --top 20

# série anual de ajuizamentos de 1º grau
./scripts/datajud.sh agregar ano --grau G1

# 2.000 processos em JSONL, 100 por página
./scripts/datajud.sh paginar --limite 2000 --pagina 100 --saida processos-tjpe.jsonl
```

## Relatório

```bash
./scripts/datajud.sh relatorio --tribunal tjpe --saida saida
# → saida/relatorio-TJPE-AAAAMMDD-HHMM.md  (total, 7 agregações, notas legais)
# → saida/agg-*.tsv e saida/agg-*.csv      (dados para Excel/pandas)
```

Veja o formato em [`docs/exemplo-saida/relatorio-tjpe-exemplo.md`](docs/exemplo-saida/relatorio-tjpe-exemplo.md).

O relatório registra endpoint, hora UTC, filtros usados e nº de requisições — e traz as notas do Termo de
Uso (dados não garantidos pelo CNJ, uso não comercial, ciência ao CNJ ao divulgar, LGPD).

## Pipeline de gates (o gatilho)

```bash
make gates          # veredito: 0 = nada pendente · 1 = continuidade · 2 = exige humano
make gate-issues    # existem issues abertas?
make gate-cicd      # alguma execução de CI/CD terminou com erro?
make gate-testes    # os testes existem e passam?
make gate-issue     # executa a próxima issue do backlog (ISSUE=ISSUE-006 MARCAR=--marcar)
```

Cada gate devolve **o mesmo objeto JSON** (`id`, `mensagem`, `anexos`, `status`, `next_issue`…)
e o **exit code é igual ao `status`**: `"0"` sucesso, `"1"` erro tipo 1 (pendência tratável ⇒
**continuidade**), `"2"` erro tipo 2 (não foi possível avaliar ⇒ exige humano). O **gatilho só é
positivo** quando não há issue aberta **e** o CI não tem erro **e** os testes passam; enquanto não
for positivo, `continuidade = true` e o fluxo segue para a próxima issue indexada — cada issue
entregue vem com a **instrução de teste** da seguinte. Detalhes, diagrama BPMN e contrato completo:
[`docs/03-pipeline-gates.md`](docs/03-pipeline-gates.md). Entrega documentada: [`ENTREGA.md`](ENTREGA.md).

## Testes (sem internet)

```bash
make testes                          # todas as 5 suítes (151 verificações)
python3 tests/testar_conformidade.py # 29 — conformidade com a doc oficial do CNJ
python3 tests/testar_main.py         # 29 — NUP/DV, relatório, DJEN, erros
./tests/rodar-testes.sh              # 32 — datajud.sh (curl + jq)
python3 tests/testar_pipeline.py     # 36 — contrato JSON dos gates, 0/1/2, blueprint, workflow
./tests/testar_bootstrap.sh          # 25 — recria o projeto e compara byte a byte
```

As suítes sobem mocks locais das APIs (`tests/mock_apis.py` e `tests/mock_datajud.py`) que imitam
autenticação, erros 400/401/404/429, agregações e paginação. **Nenhuma requisição real ao CNJ é feita.**

### Reconstruir o projeto do zero

```bash
bash bootstrap.sh                  # cria ./projeto-datajud, confere hashes e roda as 4 suítes
bash bootstrap.sh --verificar      # só valida uma cópia existente
python3 tools/gerar_bootstrap.py   # regera o bootstrap após editar algum arquivo
```

Detalhes de estrutura, permissões, etapas e saída esperada: [`BOOTSTRAP.md`](BOOTSTRAP.md).

## Requisitos

`bash` ≥ 4.3, `curl` e `jq`. Em Debian/Ubuntu: `sudo apt install curl jq`.

## Regras de uso (resumo do Termo de Uso v1.2)

- **120 requisições por minuto** no máximo (item 3.13); o CNJ pode limitar sem aviso (3.14).
- Uso **legal e não comercial** (3.3, 3.8).
- O CNJ **não garante** precisão, integridade ou atualidade (3.6).
- Ao divulgar relatórios, **dê ciência ao CNJ** (3.9).
- Não coletar, armazenar ou cruzar dados pessoais (4.2, LGPD).

Os dados são metadados de processos **públicos** (sem partes, sem peças). A atualização depende do envio
de cada tribunal ao DataJud — pode haver atraso de dias.
__ARQ_EOF__
__ARQ__ docs/01-api-datajud.md
# API Pública do DataJud (CNJ) — guia de referência

Estudo da documentação oficial ([wiki do DataJud](https://datajud-wiki.cnj.jus.br/api-publica/acesso)) com
tudo o que é necessário para consultar os metadados processuais via `curl`.

---

## 1. O que é

A **API Pública do DataJud** dá acesso aos **metadados** dos processos **públicos** de todos os tribunais
brasileiros, a partir da Base Nacional de Dados do Poder Judiciário (CNJ), conforme a Portaria nº 160/2020.

O que vem no retorno (capa do processo + movimentações):

- número único (CNJ), tribunal, grau/instância, data de ajuizamento, nível de sigilo;
- classe processual e assuntos (Tabelas Processuais Unificadas — TPU);
- órgão julgador (vara/câmara/turma), código do município (IBGE);
- sistema processual (PJe, eproc…), formato (físico/eletrônico);
- lista de **movimentos** com código, nome, data/hora e complementos tabelados.

O que **não** vem: nome das partes, CPF/CNPJ, conteúdo das peças. A wiki cita expressamente o resguardo de
processos sigilosos e de dados das partes.

- `dataHoraUltimaAtualizacao`: milissegundos do `millisInsercao` na origem (quando o tribunal enviou o dado).
- `@timestamp`: quando o documento foi atualizado no índice do DataJud.

> A atualização depende de cada tribunal enviar os dados ao CNJ — costuma haver atraso de alguns dias.

---

## 2. Acesso e autenticação

| Item | Valor |
| --- | --- |
| URL base | `https://api-publica.datajud.cnj.jus.br/` |
| Rota | `POST /<alias_do_tribunal>/_search` |
| Cabeçalho | `Authorization: APIKey <chave pública>` |
| Cabeçalho | `Content-Type: application/json` |
| Corpo | Query DSL do Elasticsearch (JSON) |

A chave é **pública**, publicada na página [Acesso](https://datajud-wiki.cnj.jus.br/api-publica/acesso) e
**pode ser trocada pelo CNJ a qualquer momento**. O script deste repositório embute a chave vigente no
momento da escrita e permite atualizá-la com:

```bash
export DATAJUD_API_KEY="$(bash scripts/datajud.sh chave)"
```

Chave vigente na data desta documentação:

```
cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw==
```

Nos exemplos da wiki o esquema aparece como `ApiKey` e na página de acesso como `APIKey` — o cabeçalho HTTP
não diferencia maiúsculas/minúsculas no nome, e ambos os formatos de valor funcionam.

### Alias do tribunal (o que muda por tribunal)

O único trecho que muda entre tribunais é o alias na URL:

| Tribunal | Endpoint |
| --- | --- |
| **TJPE — Tribunal de Justiça de Pernambuco** | `https://api-publica.datajud.cnj.jus.br/api_publica_tjpe/_search` |
| TRF5 (Justiça Federal da 5ª Região) | `.../api_publica_trf5/_search` |
| TRT6 (Trabalho, 6ª Região) | `.../api_publica_trt6/_search` |
| TRE-PE (Eleitoral) | `.../api_publica_tre-pe/_search` |
| STJ / TST / TSE / STM | `.../api_publica_stj/_search` etc. |

A lista completa (superiores, federais, estaduais, trabalho, eleitoral e militar) está em
<https://datajud-wiki.cnj.jus.br/api-publica/endpoints>.

> ⚠️ Um processo de PE pode estar em outro índice: recursos ao TRF5 ficam em `api_publica_trf5`,
> execuções trabalhistas em `api_publica_trt6`, matéria eleitoral em `api_publica_tre-pe`.

---

## 3. Campos disponíveis (glossário)

| Campo | Tipo | Descrição |
| --- | --- | --- |
| `id` | text/keyword | Chave `Tribunal_Classe_Grau_OrgaoJulgador_NumeroProcesso` |
| `tribunal` | text/keyword | Sigla do tribunal (ex.: `TJPE`) |
| `numeroProcesso` | text/keyword | Numeração única CNJ **sem formatação** (20 dígitos) |
| `dataAjuizamento` | datetime | Data de ajuizamento da capa |
| `grau` | text/keyword | Instância: `G1`, `G2`, `JE`, … |
| `nivelSigilo` | long | Nível de sigilo |
| `formato.codigo` / `formato.nome` | long / text | Físico ou Eletrônico |
| `sistema.codigo` / `sistema.nome` | long / text | Sistema processual de origem |
| `classe.codigo` / `classe.nome` | long / text | Classe processual (TPU) |
| `assuntos[].codigo` / `.nome` | long / text | Assuntos (TPU) |
| `orgaoJulgador.codigo` / `.nome` | long / text | Vara/câmara atual |
| `orgaoJulgador.codigoMunicipioIBGE` | long | Município do órgão julgador |
| `movimentos[].codigo` / `.nome` / `.dataHora` | long / text / datetime | Movimentações |
| `movimentos[].complementosTabelados[]` | array | Complementos da movimentação |
| `dataHoraUltimaAtualizacao` | datetime | Marca da origem (controle interno) |
| `@timestamp` | datetime | Marca de atualização no índice (controle interno) |

Campos de texto normalmente possuem subcampo `.keyword` (agregável); campos `long` (códigos) são
agregáveis diretamente.

---

## 4. Consultas essenciais

### 4.1 Buscar por número do processo

```json
{ "query": { "match": { "numeroProcesso": "00008323520184013202" } } }
```

### 4.2 Combinar filtros (classe + órgão julgador)

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "classe.codigo": 1116 } },
        { "match": { "orgaoJulgador.codigo": 13597 } }
      ]
    }
  }
}
```

### 4.3 Filtrar por período de ajuizamento

```json
{
  "query": {
    "bool": {
      "must": [
        { "range": { "dataAjuizamento": { "gte": "2024-01-01T00:00:00.000Z",
                                           "lte": "2024-12-31T23:59:59.999Z" } } }
      ]
    }
  }
}
```

### 4.4 Contar sem trazer documentos

```json
{ "query": { "match_all": {} }, "size": 0, "track_total_hits": true }
```

Resposta: `hits.total.value` e `hits.total.relation`. Quando `relation` for `"gte"`, o valor é **10.000**
e o total real é maior — a API trunca a contagem nesse teto.

### 4.5 Agregações (o "relatório" propriamente dito)

```json
{
  "size": 0,
  "query": { "match_all": {} },
  "aggs": { "por_classe": { "terms": { "field": "classe.codigo", "size": 10 } } }
}
```

- `terms` em campo de código (`classe.codigo`, `orgaoJulgador.codigo`, `grau.keyword`, …).
- Se a API responder `Fielddata is disabled on text fields`, use o subcampo `.keyword`
  (ex.: `orgaoJulgador.nome.keyword`) ou o campo de código correspondente.
- Para séries temporais: `date_histogram` em `dataAjuizamento` com `calendar_interval: year` (ou `month`)
  e `format: yyyy` (ou `yyyy-MM`).

### 4.6 Paginar com `search_after` (recomendado pelo CNJ)

`size` aceita de 1 a 10.000 documentos por página. Para volumes maiores, ordene por `@timestamp` e use o
vetor `sort` do último documento como `search_after` da página seguinte:

```json
{
  "size": 100,
  "query": { "match_all": {} },
  "sort": [ { "@timestamp": { "order": "asc" } } ],
  "search_after": [ 1681366085550 ]
}
```

---

## 5. Códigos de resposta

| HTTP | Significado | O que fazer |
| --- | --- | --- |
| 200 | OK | — |
| 400 | Query inválida (campo inexistente, agregação sem `fielddata`) | ajustar o corpo (usar `.keyword` / código) |
| 401/403 | Chave ausente, inválida ou trocada | reler a wiki e atualizar `DATAJUD_API_KEY` |
| 404 | Alias de tribunal inexistente | conferir a lista de endpoints |
| 429 | Excesso de requisições | reduzir o ritmo (limite: 120 req/min) |
| 5xx | Instabilidade do CNJ | tentar mais tarde, com backoff |

---

## 6. Regras de uso (Termo de Uso v1.2)

Fonte: [Termos-de-uso-api-publica-V1.2.pdf](https://formularios.cnj.jus.br/wp-content/uploads/2023/11/Termos-de-uso-api-publica-V1.2.pdf)
(versão de 27/11/2023 — a leitura da API implica aceitação tácita).

- **3.13 — no máximo 120 requisições por minuto** (salvo autorização expressa do CNJ).
- **3.14 —** o CNJ pode limitar requisições por usuário/chave sem aviso prévio.
- **3.3 / 3.8 —** uso exclusivamente legal e **não comercial**; proibido modificar, distribuir, vender ou
  explorar comercialmente a API ou informação derivada.
- **3.6 —** o CNJ **não garante** precisão, integridade ou atualidade dos dados.
- **3.9 —** quem divulgar estudo/relatório ao público deve **dar ciência ao CNJ**.
- **4.2 / 4.6 —** não coletar, armazenar, processar nem cruzar dados pessoais oriundos da API (LGPD).
- **3.19 —** comunicar ao CNJ falhas de segurança ou informação incorreta.

Na prática: identifique-se (`User-Agent`), coloque pausa entre páginas, prefira agregações a varrer a base,
não repita a consulta do que já foi obtido (`@timestamp` permite buscar só o que mudou).

---

## 7. Boas práticas

1. **Cache/checkpoint por `@timestamp`** — só reler o que mudou desde a última coleta.
2. **Reusar códigos** — descubra o código da vara/classe uma vez e guarde.
3. **Agregar em vez de paginar** — para relatórios, `aggs` custa 1 requisição e devolve o consolidado.
4. **Paciência** — 120 req/min é o teto global; com 1 req a cada 0,5 s você fica em 120/min. Deixe folga.
5. **Tratar `gte`** — total acima de 10.000 aparece truncado; refine o recorte ou use `aggs`.
6. **Não usar dados pessoais** — o índice é de metadados, mas a LGPD vale para qualquer cruzamento.
__ARQ_EOF__
__ARQ__ docs/02-receitas-curl-tjpe.md
# Verificando o TJPE com curl — receitas prontas

Todas as receitas abaixo consultam o **Tribunal de Justiça de Pernambuco**:

```
https://api-publica.datajud.cnj.jus.br/api_publica_tjpe/_search
```

Para outro tribunal, basta trocar `api_publica_tjpe` pelo alias correspondente
(`api_publica_trf5`, `api_publica_trt6`, `api_publica_tre-pe`…). Lista completa em
<https://datajud-wiki.cnj.jus.br/api-publica/endpoints>.

---

## 0. Prepare o terminal

```bash
# chave pública publicada pela wiki do CNJ (pode ser trocada pelo CNJ a qualquer momento)
export CHAVE="cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw=="

# endpoint do TJPE
export TJPE="https://api-publica.datajud.cnj.jus.br/api_publica_tjpe/_search"

# (opcional) reler a chave direto da wiki
# export CHAVE="$(bash scripts/datajud.sh chave)"
```

> No **PowerShell**, troque `curl` por `curl.exe`, use aspas duplas e escape o JSON, ou use
> `Invoke-RestMethod`. As receitas aqui são para `bash`/`zsh` (Linux, macOS, WSL, Git Bash).

---

## 1. Contar os processos do TJPE

```bash
curl -sS -X POST "$TJPE" \
  -H "Authorization: APIKey $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{ "query": { "match_all": {} }, "size": 0, "track_total_hits": true }' \
  | jq '{total: .hits.total.value, relacao: .hits.total.relation}'
```

Saída esperada (formato):

```json
{ "total": 10000, "relacao": "gte" }
```

`"gte"` significa **10.000 ou mais**: a API trunca a contagem nesse teto. Para saber números maiores é
preciso fatiar a consulta (por ano, por grau, por vara) e somar — ou usar agregações.

## 2. Contar com filtros (exemplo: execuções fiscais de 2024)

```bash
curl -sS -X POST "$TJPE" \
  -H "Authorization: APIKey $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{
        "query": { "bool": { "must": [
            { "match": { "classe.codigo": 1116 } },
            { "range": { "dataAjuizamento": { "gte": "2024-01-01T00:00:00.000Z",
                                              "lte": "2024-12-31T23:59:59.999Z" } } }
        ] } },
        "size": 0,
        "track_total_hits": true
      }' \
  | jq '.hits.total | {total: .value, relacao: .relation}'
```

Quando o recorte é pequeno, vem `"relation": "eq"` — aí o número é exato.

## 3. Consultar um processo específico (numeração única CNJ)

Use **somente os 20 dígitos**, sem pontos, traços ou espaços:

```bash
NUMERO=00012345620248172001     # = 0001234-56.2024.8.17.2001

curl -sS -X POST "$TJPE" \
  -H "Authorization: APIKey $CHAVE" \
  -H "Content-Type: application/json" \
  -d "{ \"query\": { \"match\": { \"numeroProcesso\": \"$NUMERO\" } }, \"size\": 1 }" \
  | jq '.hits.hits[0]._source | {processo: .numeroProcesso, grau, classe: .classe.nome,
        orgao: .orgaoJulgador.nome, assuntos: [.assuntos[].nome],
        ajuizamento: .dataAjuizamento, ultimoMovimento: .movimentos[-1].nome}'
```

Se vier `"value": 0`, o processo não está naquele índice — confira se ele é de 2º grau (`grau: G2` no
próprio TJPE), federal (`api_publica_trf5`), trabalhista (`api_publica_trt6`) ou eleitoral (`api_publica_tre-pe`).

## 4. Relatório por classe processual (agregação)

```bash
curl -sS -X POST "$TJPE" \
  -H "Authorization: APIKey $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{
        "size": 0,
        "query": { "match_all": {} },
        "aggs": { "por_classe": { "terms": { "field": "classe.codigo", "size": 15 } } }
      }' \
  | jq -r '.aggregations.por_classe.buckets[] | "\(.key)\t\(.doc_count)"'
```

A saída é TSV (código + quantidade, separados por tabulação), pronta para `column -t`, planilha ou `xargs`.
Troque `classe.codigo` por outros campos para mudar o recorte:

| O que você quer | Campo da agregação |
| --- | --- |
| Classe processual (código TPU) | `classe.codigo` |
| Órgão julgador (vara/câmara) | `orgaoJulgador.codigo` |
| Nome da vara | `orgaoJulgador.nome.keyword` |
| Grau / instância | `grau.keyword` |
| Assunto (TPU) | `assuntos.codigo` |
| Sistema processual | `sistema.codigo` ou `sistema.nome.keyword` |
| Físico ou eletrônico | `formato.codigo` |
| Movimento mais comum | `movimentos.codigo` |

> Se a API responder **`Fielddata is disabled on text fields`**, o campo é texto sem `.keyword`:
> acrescente `.keyword` (ex.: `classe.nome.keyword`) ou use o campo de código. O
> `scripts/datajud.sh` faz esse fallback automaticamente.

## 5. Série por ano de ajuizamento (`date_histogram`)

```bash
curl -sS -X POST "$TJPE" \
  -H "Authorization: APIKey $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{
        "size": 0,
        "query": { "match_all": {} },
        "aggs": { "por_ano": { "date_histogram": { "field": "dataAjuizamento",
                                                    "calendar_interval": "year",
                                                    "format": "yyyy",
                                                    "min_doc_count": 1 } } }
      }' \
  | jq -r '.aggregations.por_ano.buckets[] | "\(.key_as_string)\t\(.doc_count)"'
```

Troque `year`/`yyyy` por `month`/`yyyy-MM` para a série mensal.

## 6. Relatório completo em uma linha (markdown)

```bash
{
  echo "# DataJud TJPE — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  curl -sS -X POST "$TJPE" -H "Authorization: APIKey $CHAVE" -H "Content-Type: application/json" \
    -d '{"size":0,"query":{"match_all":{}},"track_total_hits":true}' \
    | jq -r '"Total: \(.hits.total.value) (relação \(.hits.total.relation))"'
  for CAMPO in classe.codigo grau.keyword orgaoJulgador.nome.keyword; do
    echo; echo "## $CAMPO"; echo
    curl -sS -X POST "$TJPE" -H "Authorization: APIKey $CHAVE" -H "Content-Type: application/json" \
      -d "{\"size\":0,\"query\":{\"match_all\":{}},\"aggs\":{\"a\":{\"terms\":{\"field\":\"$CAMPO\",\"size\":10}}}}" \
      | jq -r '.aggregations.a.buckets[] | "| \(.key) | \(.doc_count) |"'
    sleep 1   # cortesia: o limite do CNJ é 120 requisições por minuto
  done
} > relatorio-tjpe.md
```

Isso gera 4 requisições e um `relatorio-tjpe.md` com total e três tabelas. Para o relatório completo
(7 agregações, TSV/CSV, notas legais e avisos de fallback), use o script do repositório:

```bash
./scripts/datajud.sh relatorio --tribunal tjpe --saida saida
```

## 7. Baixar processos (paginação com `search_after`)

```bash
SAIDA=processos-tjpe.jsonl; : > "$SAIDA"
AFTER="null"
for i in $(seq 1 10); do            # 10 páginas × 100 = 1.000 registros
  CORPO=$(cat <<JSON
{ "size": 100,
  "query": { "bool": { "must": [ { "match": { "grau": "G1" } } ] } },
  "sort": [ { "@timestamp": { "order": "asc" } } ]
  $( [ "$AFTER" = "null" ] || echo ", \"search_after\": $AFTER" ) }
JSON
)
  RESP=$(curl -sS -X POST "$TJPE" -H "Authorization: APIKey $CHAVE" \
            -H "Content-Type: application/json" -d "$CORPO")
  echo "$RESP" | jq -c '.hits.hits[] | ._source' >> "$SAIDA"
  N=$(echo "$RESP" | jq '.hits.hits | length')
  [ "$N" -eq 0 ] && break
  AFTER=$(echo "$RESP" | jq -c '.hits.hits[-1].sort')
  echo "página $i: $N registros (acumulado: $(wc -l < "$SAIDA"))"
  sleep 0.5
done
```

O mesmo com o script: `./scripts/datajud.sh paginar --limite 1000 --pagina 100 --saida processos-tjpe.jsonl`

## 8. Descobrir o código de uma vara/classe

1. Agregue os valores existentes (receita 4) e veja quais códigos aparecem com mais volume.
2. Confirme o significado do código nas **Tabelas Processuais Unificadas (TPU)** do CNJ — usadas pelo
   DataJud para classes e assuntos. Ex.: `1116` = Execução Fiscal, `436` = Procedimento do Juizado
   Especial Cível.
3. Ache o nome da vara com o campo de código dele (`orgaoJulgador.nome` no JSON de um processo).

---

## 9. Erros mais comuns

| Sintoma | Causa provável | Correção |
| --- | --- | --- |
| `401 Unauthorized` | chave ausente, errada ou trocada pelo CNJ | reler a chave na wiki (`./scripts/datajud.sh chave`) |
| `404 no such index` | alias do tribunal errado | conferir a lista de endpoints |
| `400 Fielddata is disabled` | agregação em campo texto | usar `.keyword` ou o campo de código |
| `400 No field found` | nome de campo inexistente naquele índice | conferir o glossário |
| `429 Too Many Requests` | passou de 120 req/min | dar pausa entre chamadas |
| total `gte 10000` | teto de contagem da API | fatiar por ano/vara/grau |
| JSON vazio (`hits` sem `_source`) | consulta pegou processos sigilosos/fora do índice | revisar filtros |

## 10. Ver o curl que o script dispararia

```bash
./scripts/datajud.sh --debug contar --tribunal tjpe --classe 1116
```

Imprime o `curl` equivalente completo — útil para copiar para um `.sh`, Para Postman, ou para auditar
exatamente o que foi enviado ao CNJ.

---

### Lembrete legal (Termo de Uso v1.2)

- Limite: **120 requisições por minuto** (item 3.13).
- Uso **legal e não comercial** (itens 3.3 e 3.8).
- O CNJ **não garante** precisão/atualidade (item 3.6).
- Divulgando relatório ao público: **dê ciência ao CNJ** (item 3.9).
- **Não** coletar/cruzar dados pessoais (item 4.2 — LGPD).
__ARQ_EOF__
__ARQ__ docs/03-pipeline-gates.md
# Pipeline orientado a gates (gate-driven pipeline / blueprint BPMN)

Este projeto tem um **pipeline de portões (gates)** executável localmente **e** no
GitHub Actions. Cada ação devolve **sempre o mesmo objeto JSON**, e o **código de saída
é igual ao `status`** — o que permite encadear gates com `if`/`needs` sem parsing extra.

- Executor: [`pipeline/gate.py`](../pipeline/gate.py)
- Planta (BPMN-like): [`pipeline/blueprint.json`](../pipeline/blueprint.json)
- Fila indexada de issues: [`pipeline/backlog.json`](../pipeline/backlog.json)
- Gatilho no GitHub Actions: [`.github/workflows/gates.yml`](../.github/workflows/gates.yml)
- Testes: [`tests/testar_pipeline.py`](../tests/testar_pipeline.py) (36 testes, offline)

---

## 1. Contrato JSON (igual em todas as ações)

```json
{
  "id": "gate-continuidade-20261013T141603Z-751a07",
  "gate": "continuidade",
  "status": "1",
  "codigo_saida": 1,
  "mensagem": "gate NÃO positivo — continuidade obrigatória. Pendências: issues (1)",
  "continuidade": true,
  "next_issue": "ISSUE-006",
  "anexos": [
    {"path": "pipeline/saida/issues-abertas.md", "filename": "issues-abertas.md",
     "descricao": "lista de issues abertas consultadas pelo gate"},
    {"path": "pipeline/saida/veredito-continuidade.md", "filename": "veredito-continuidade.md",
     "descricao": "veredito do gate em Markdown (resumo para humanos)"}
  ],
  "dados": {"checks": {"issues": {"status": "1"}, "...": {}}, "gate_positivo": false},
  "timestamp": "2026-10-13T14:16:03Z",
  "duracao_s": 0.412,
  "versao": "1.0.0"
}
```

| Campo | Tipo | Regra |
| --- | --- | --- |
| `id` | string | único por execução (`gate-<nome>-<timestamp>-<hash>`) |
| `gate` | string | qual gate gerou (`issues`, `cicd`, `testes`, `continuidade`, `issue`, `blueprint`, `situacao`) |
| `status` | **string** | `"0"`, `"1"` ou `"2"` (ver tabela abaixo) |
| `codigo_saida` | int | espelho do `status`; é o **exit code** do processo |
| `mensagem` | **string** | mensagem pronta **ou** resumo/log da execução |
| `continuidade` | bool | `true` ⇒ o pipeline **deve continuar** (trabalho pendente) |
| `next_issue` | string \| null | a **mesma** issue se falhou; a **próxima** indexada se passou; `null` se acabou ou não se aplica |
| `anexos` | array | `{path, filename, descricao}` — artefatos gerados (logs, listas, veredito, guia da próxima issue) |
| `dados` | objeto | detalhes estruturados de cada gate |

### Códigos

| status | nome | significado | continuidade | exemplo |
| --- | --- | --- | --- | --- |
| `"0"` | **SUCESSO** | gate positivo: nada pendente | `false` | sem issues abertas, CI limpo, testes verdes |
| `"1"` | **ERRO TIPO 1** | pendência **conhecida e tratável** | **`true`** | existe issue aberta; CI vermelho; teste ausente/reprovado; instrução da issue falhou |
| `"2"` | **ERRO TIPO 2** | **não foi possível avaliar** | `false` | `gh` ausente/sem credencial; blueprint inconsistente; issue sem instrução; chave do CNJ recusada |

> **Regra de ouro do projeto:** o gate só é **positivo** quando não há issue aberta **E**
> o CI não tem execução com erro **E** existem testes presentes e aprovados.
> **Enquanto não for positivo ⇒ `continuidade = true`** e `next_issue` aponta a próxima
> pendência do backlog — é isso que mantém o fluxo andando sem sessão humana.

---

## 2. Fluxo (blueprint tipo BPMN)

```mermaid
flowchart TD
    E["Eventos: push · pull_request · issues · schedule (dias úteis 09:00) · workflow_dispatch"] --> G1
    G1{"gate 1<br/>issues abertas?"} -->|0 sem issues| G2
    G1 -->|1 há issue aberta| G2
    G1 -->|2 indeterminado| GC
    G2{"gate 2<br/>CI/CD com erro?"} -->|0 limpo| G3
    G2 -->|1 com erro| G3
    G2 -->|2 indeterminado| GC
    G3{"gate 3<br/>testes presentes e verdes?"} -->|0 verdes| GC
    G3 -->|1 ausentes/reprovados| GC
    G3 -->|2 erro de execução| GC
    GC{"gate 4<br/>continuidade ⇒<br/>0 issues ∧ CI limpo ∧ testes verdes"}
    GC -->|2 erro tipo 2| F["FIM: falha o job<br/>(exige humano)"]
    GC -->|0 positivo| OK["FIM: pipeline pode encerrar<br/>(continuidade=false)"]
    GC -->|1 continuidade| G5{"gate 5<br/>executa a issue do backlog"}
    G5 -->|0 passou| NX["next_issue = PRÓXIMA indexada<br/>+ guia da próxima anexada"]
    G5 -->|1 falhou| MS["next_issue = MESMA issue<br/>+ log do erro anexado"]
    G5 -->|2 sem instrução| F
    NX --> GC
    MS --> G5
```

A mesma planta está em `pipeline/blueprint.json` (consumida pelo comando
`gate.py blueprint`, que **falha com status 2** se a planta e a implementação divergirem —
gate sem código, transição sem destino, etc.).

---

## 3. Comandos

```bash
# verificação isolada (cada um devolve JSON e sai com 0/1/2)
python3 pipeline/gate.py issues        # existem issues abertas?      (gh issue list)
python3 pipeline/gate.py cicd          # há execução de CI com erro?  (gh run list)
python3 pipeline/gate.py testes        # testes presentes e verdes?   (make testes)
python3 pipeline/gate.py blueprint     # a planta é consistente?

# veredito agregado (o "gate" propriamente dito)
python3 pipeline/gate.py continuidade

# executa a instrução da issue: sucesso ⇒ próxima indexada; falha ⇒ mesma
python3 pipeline/gate.py issue                  # próxima pendente do backlog
python3 pipeline/gate.py issue --id ISSUE-006   # uma issue específica
python3 pipeline/gate.py issue --marcar         # e persiste a conclusão no backlog

# leitura do histórico
python3 pipeline/gate.py situacao

# modo offline/fixture (usado pelos testes e por quem não tem gh)
python3 pipeline/gate.py issues --issues-json fixture.json
python3 pipeline/gate.py cicd   --runs-json fixture.json
python3 pipeline/gate.py issues --sem-gh        # ⇒ status 2 (erro tipo 2, sem fonte)
```

### Encadeando jobs (como o workflow faz)

```bash
python3 pipeline/gate.py continuidade \
  --status-issues "$S_ISSUES" --status-cicd "$S_CICD" --status-testes "$S_TESTES"
```

Assim o agregador **não reexecuta** a suíte: ele recebe o resultado de cada job
(`needs.<job>.outputs.status`), que é o padrão de `needs` do GitHub Actions.

---

## 4. Fila de issues (`pipeline/backlog.json`)

Cada item tem `id` sequencial, `titulo`, `entregavel`, **`instrucao_teste` executável** e
`status` (`concluida` | `pendente` | `bloqueada`). O gate `issue`:

1. localiza a issue (informada ou a **primeira pendente**);
2. roda a `instrucao_teste` e **anexa o log**;
3. **código 0** ⇒ `status "0"`, `next_issue` = próxima indexada e anexa
   `<ID>-proxima-issue.md` com a instrução da seguinte (com o comando pronto);
   com `--marcar`, grava `status: concluida`, `concluida_em` e `evidencias`;
4. **código ≠ 0** ⇒ `status "1"`, `next_issue` = **mesma issue**, log anexado
   (continua tentando até ficar verde);
5. **sem `instrucao_teste`** ⇒ `status "2"` (exige decisão humana — usado de propósito na
   ISSUE-007, que depende de escolha do usuário).

Situação atual do backlog: ISSUE-001…005 concluídas, **ISSUE-006 pendente** (validação ao
vivo contra o CNJ — requer internet) e ISSUE-007 bloqueada (decisão humana).

---

## 5. O workflow (`.github/workflows/gates.yml`)

| Job | Gate | Saída |
| --- | --- | --- |
| `gate-issues` | issues abertas | outputs `status`, `continuidade` + artifact |
| `gate-cicd` | CI/CD com erro | outputs `status`, `continuidade` + artifact |
| `gate-testes` | suíte completa | outputs + `log-testes-*.txt` |
| `gate-continuidade` | veredito agregado | `status`, `continuidade`, `next_issue`; **falha o job se status 2** |
| `executa-issue` | roda a próxima issue | executa a `instrucao_teste`, publica log/guia; com `marcar=true`, commita o backlog |

Todo job publica o JSON no log, o veredito no **job summary** (`$GITHUB_STEP_SUMMARY`) e os
artefatos via `actions/upload-artifact` — os "anexos" do contrato ficam baixáveis.

Gatilhos: `push`, `pull_request`, `issues` (aberta/fechada/reaberta), `schedule` (dias úteis
12:00 UTC) e `workflow_dispatch` (com os inputs `issue` e `marcar`).

```bash
# disparar manualmente (depois que o arquivo estiver na branch padrão)
gh workflow run gates.yml -f issue=ISSUE-006 -f marcar=false
gh run list --workflow=gates.yml
```

---

## 6. Como os testes cobrem o pipeline

`tests/testar_pipeline.py` (36 testes, offline) verifica:

- **contrato**: as 11 chaves obrigatórias em todos os gates, `status` string, `anexos` com
  `{path, filename, descricao}`, `codigo_saida == status == exit code`, arquivos anexados
  existindo no disco, `--json-saida`;
- **issues**: com pendência ⇒ `1`/continuidade; vazio ⇒ `0`; sem fonte ⇒ `2`;
- **cicd**: `failure`, `timed_out`, `startup_failure`, `action_required`, `cancelled` ⇒ `1`;
  sucesso e `in_progress` ⇒ `0`;
- **testes**: comando OK ⇒ `0`; comando falho ⇒ `1` com o log anexado;
- **continuidade**: pendência em qualquer check ⇒ `1` + `next_issue`; tudo limpo ⇒ `0`
  (`next_issue: null`); `2` propaga; anexo do veredito em Markdown;
- **issue**: sucesso avança para a próxima (e anexa a guia), falha mantém a mesma,
  sem instrução ⇒ `2`, `--marcar` atualiza o backlog, `--marcar` ausente não altera;
- **blueprint/backlog**: planta do projeto consistente, planta quebrada ⇒ `2`, backlog
  íntegro (ids sequenciais, instruções apontando para arquivos existentes);
- **workflow**: gatilhos exigidos, os 5 jobs, chamadas ao executor, publicação de JSON/
  summary/artifacts, `status 2` derrubando o job, e checagem estrutural do YAML
  (sem tabulação, indentação par) — a validação definitiva do YAML é a execução real no
  Actions.

```bash
python3 tests/testar_pipeline.py         # 36 testes
make gates                               # veredito de continuidade de verdade
```
__ARQ_EOF__
__ARQ__ docs/exemplo-saida/agg-grau.tsv
# campo: grau.keyword
G1	9000
G2	3000
__ARQ_EOF__
__ARQ__ docs/exemplo-saida/agg-orgao-nome.csv
"valor","documentos"
"1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE",1200
"2ª VARA CÍVEL DA COMARCA DO RECIFE",900
__ARQ_EOF__
__ARQ__ docs/exemplo-saida/relatorio-processo-exemplo.md
> **Aviso:** exemplo de saída gerado com o mock local (`tests/mock_apis.py`) — o processo,
> o órgão julgador e as publicações são **fictícios**, para demonstrar o formato do
> relatório. Rode `python3 main.py <numero>` na sua máquina para consultar um processo real.

# Processo 0001234-43.2024.8.17.2001

> **Relatório gerado em** 12/10/2026 às 22:09 UTC  
> **Fontes:** API Pública do DataJud (CNJ) e DJEN/Comunica  
> **Índices consultados:** api_publica_tjpe, api_publica_trf5, api_publica_trt6, api_publica_tre-pe, api_publica_stj, api_publica_tst, api_publica_tse, api_publica_stm  
> **Comando:** `/usr/bin/python3 main.py 00012344320248172001 --todos`

## 1. Resumo executivo

- **Tribunal:** TJPE — Tribunal de Justiça de Pernambuco (segmento 8: Justiça dos Estados e do Distrito Federal)
- **Grau(s) encontrado(s) no índice:** G1, G2
- **Classe:** 1116 — Execução Fiscal
- **Órgão julgador:** 1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE (código 12345, município IBGE 2611606 — PE)
- **Ajuizamento:** 05/03/2024 — há **951 dias**
- **Movimentações:** 6 registro(s); última: “Expedição de documento” em 01/02/2025 08:00 (há 618 dias)
- **Publicações no DJEN:** 2 encontrada(s)

## 2. Identificação e validação do número

| Campo | Valor |
| --- | --- |
| Número único (CNJ) | 0001234-43.2024.8.17.2001 |
| Somente dígitos | 00012344320248172001 |
| Dígito verificador | 43 — válido ✔ (módulo 97 base 10) |
| Ano de ajuizamento (campo AAAA) | 2024 |
| Segmento (campo J) | 8 — Justiça dos Estados e do Distrito Federal |
| Tribunal (campo TR) | 17 — TJPE (Tribunal de Justiça de Pernambuco) |
| Origem (campo OOOO) | 2001 |
| Índice DataJud consultado | api_publica_tjpe |

## 3. Capa do processo (metadados do DataJud)

### 3.1 Documento 1 — grau G1

| Campo | Valor |
| --- | --- |
| ID DataJud | TJPE_1116_G1_12345_00012344320248172001 |
| Tribunal / grau | TJPE / G1 |
| Classe processual (TPU) | 1116 — Execução Fiscal |
| Assuntos (TPU) | 6017 — Dívida Ativa (Execução Fiscal); 10586 — ICMS |
| Órgão julgador | 12345 — 1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE |
| Município do órgão (IBGE) | 2611606 — PE |
| Data de ajuizamento | 05/03/2024 |
| Nível de sigilo | 0 |
| Formato | 1 — Eletrônico |
| Sistema | 1 — PJe |
| Última atualização na origem | 11/02/2025 13:20 |
| Atualizado no índice (@timestamp) | 12/02/2025 02:00 |
| Total de movimentos | 6 |

### 3.2 Documento 2 — grau G2

| Campo | Valor |
| --- | --- |
| ID DataJud | TJPE_1980_G2_98765_00012344320248172001 |
| Tribunal / grau | TJPE / G2 |
| Classe processual (TPU) | 1980 — Apelação Cível |
| Assuntos (TPU) | 6017 — Dívida Ativa (Execução Fiscal) |
| Órgão julgador | 98765 — 2ª CÂMARA DE DIREITO PÚBLICO |
| Município do órgão (IBGE) | 2611606 — PE |
| Data de ajuizamento | 05/03/2024 |
| Nível de sigilo | 0 |
| Formato | 1 — Eletrônico |
| Sistema | 1 — PJe |
| Última atualização na origem | 21/03/2025 09:00 |
| Atualizado no índice (@timestamp) | 22/03/2025 02:00 |
| Total de movimentos | 2 |

## 4. Movimentações processuais

| # | Data/hora (UTC) | Código | Movimento | Complementos | Órgão |
| --- | --- | --- | --- | --- | --- |
| 1 | 05/03/2024 12:00 | 26 | Distribuição | sorteio [tipo_de_distribuicao_redistribuicao]=2 | — |
| 2 | 10/03/2024 09:00 | 51 | Conclusão | — | — |
| 3 | 02/04/2024 15:30 | 246 | Expedição de documento | — | 1ª VARA DE EXECUÇÃO FISCAL DE RECIFE |
| 4 | 20/06/2024 10:00 | 85 | Citação | — | — |
| 5 | 15/01/2025 11:00 | 22 | Juntada | — | — |
| 6 | 01/02/2025 08:00 | 246 | Expedição de documento | — | — |

_Tabela com todas as 6 movimentações retornadas pela API, em ordem cronológica._

## 5. Panorama estatístico

### 5.1 Movimentações por ano

| Ano | Movimentações | Volume |
| --- | --- | --- |
| 2024 | 4 | ████████████████████████████ |
| 2025 | 2 | ██████████████ |

### 5.2 Movimentos mais frequentes

| Movimento | Ocorrências |
| --- | --- |
| Expedição de documento | 2 |
| Citação | 1 |
| Conclusão | 1 |
| Distribuição | 1 |
| Juntada | 1 |

### 5.3 Órgãos que movimentaram o processo

| Órgão julgador | Movimentações |
| --- | --- |
| 1ª VARA DE EXECUÇÃO FISCAL DE RECIFE | 1 |

### 5.4 Tempo e inércia

- **Maior intervalo sem movimentação:** 209 dias — entre “Citação” (20/06/2024) e “Juntada” (15/01/2025).

- **Janela de movimentações:** 05/03/2024 a 01/02/2025 (332 dias).

- **Sem movimentação há:** 618 dias (considerando a data de hoje).  
  _Pode indicar processo parado, arquivado ou ainda não atualizado no DataJud._

## 6. Publicações e intimações (DJEN)

| Disponibilização | Tipo | Órgão | Texto | Inteiro teor |
| --- | --- | --- | --- | --- |
| 03/04/2024 | Intimação | 1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE | Fica a parte executada intimada a efetuar o pagamento do débito no prazo de 5 (cinco) dias, nos termos do art. 9º da Lei 6.830/80. | [abrir](https://comunica.pje.jus.br/documento/9001.pdf) |
| 21/06/2024 | Despacho | 1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE | Intime-se a parte exequente para informar o andamento do feito. | [abrir](https://comunica.pje.jus.br/documento/9002.pdf) |

_Publicação = primeiro dia útil seguinte à disponibilização (art. 224, §2º, CPC). Confirme sempre no portal do DJEN._

## 7. Anexos e documentos

A API Pública do DataJud disponibiliza **apenas metadados** — não expõe as peças nem os anexos do processo. Use os links oficiais abaixo para abrir os documentos na consulta pública do tribunal.

**O que é possível obter publicamente:**


| O que | Onde | Observação |
| --- | --- | --- |
| Movimentações e metadados da capa | API Pública do DataJud | já incluídos neste relatório |
| Publicações, intimações e **inteiro teor em PDF** das comunicações | API/portal do DJEN | seção 6 deste relatório |
| **Autos completos, petições, decisões e anexos** | Consulta pública do tribunal (PJe/e-SAJ) | exige o processo **não ser sigiloso**; alguns tribunais usam captcha |
| Dados de partes (nome, CPF/CNPJ), valores | Portal do tribunal (autos), mediante consulta | a API pública do DataJud **não** expõe partes nem valores |
| Dados estruturados para advogado/API autenticada | **MNI** do PJe (certificado digital A1/A3) | integração oficial, exige credencial |

Se o processo estiver em **segredo de justiça**, nenhuma consulta pública devolverá resultado — o acesso é restrito às partes e aos advogados habilitados.

## 8. Links oficiais de consulta

- [Consulta processual unificada TJPE (1º e 2º grau)](http://srv01.tjpe.jus.br/consultaprocessualunificada/)
- [PJe 1º Grau — consulta pública (autos e anexos)](https://pje.cloud.tjpe.jus.br/1g/ConsultaPublica/listView.seam)
- [PJe 2º Grau — consulta pública (autos e anexos)](https://pje.cloud.tjpe.jus.br/2g/ConsultaPublica/listView.seam)
- [Portal de consultas do TJPE](https://portal.tjpe.jus.br/servicos/consulta-processual)
- [Diário de Justiça Eletrônico do TJPE](http://www.tjpe.jus.br/dje)
- [DJEN — publicações, intimações e inteiro teor](https://comunica.pje.jus.br/consulta?numeroProcesso=00012344320248172001)
- [API Pública do DataJud (fonte destes metadados)](https://datajud-wiki.cnj.jus.br/api-publica/acesso)

## 9. Índices consultados

| Índice do DataJud | Documentos encontrados | Observação |
| --- | --- | --- |
| api_publica_tjpe | 2 | ok |
| api_publica_trf5 | 0 | ok |
| api_publica_trt6 | 0 | ok |
| api_publica_tre-pe | 0 | ok |
| api_publica_stj | 0 | ok |
| api_publica_tst | 0 | ok |
| api_publica_tse | 0 | ok |
| api_publica_stm | 0 | ok |

## 10. Notas, limitações e conformidade

- Dados de **metadados** de processos **públicos**, obtidos da Base Nacional de Dados do Poder Judiciário (DataJud), conforme a Portaria CNJ nº 160/2020.
- O CNJ **não garante** precisão, integridade ou atualidade dos dados (Termo de Uso, item 3.6); a atualização depende do envio do tribunal ao DataJud e pode levar dias.
- Uso **legal e não comercial** (itens 3.3 e 3.8). Limite de **120 requisições por minuto** (item 3.13).
- Ao divulgar este relatório, **dê ciência ao CNJ** (item 3.9).
- **LGPD:** não coletar, armazenar ou cruzar dados pessoais oriundos da API (itens 4.2 e 4.6).
- Este relatório é um **resumo automatizado** e **não substitui** a consulta oficial aos autos.


---

<sub>Gerado por `main.py` v1.0.0 em 12/10/2026 22:09:57 UTC · fontes: DataJud/CNJ e DJEN/CNJ.</sub>

__ARQ_EOF__
__ARQ__ docs/exemplo-saida/relatorio-tjpe-exemplo.md
> **Aviso:** esta é uma saída de demonstração gerada com o mock local (`tests/mock_datajud.py`).
> Os números **não** são dados reais do TJPE — servem apenas para mostrar o formato do relatório,
> das tabelas e das notas legais. Rode o script na sua máquina para obter os dados reais.

# Relatório DataJud — TJPE

- **Fonte:** API Pública do DataJud (CNJ) — https://datajud-wiki.cnj.jus.br/api-publica/
- **Endpoint consultado:** `http://127.0.0.1:8901/api_publica_tjpe/_search`
- **Gerado em (UTC):** 2026-10-12T21:30:03Z
- **Filtros aplicados:** nenhum (todos os processos públicos do índice)
- **Requisições realizadas:** 12 (limite do CNJ: 120/min)

## Total de processos

>= **10000** processos — a API limita a contagem a 10.000 quando o total é maior; refine os filtros ou leia as agregações abaixo como recorte parcial.

## Por classe processual

_campo agregado: `classe.codigo`_

| valor | documentos |
| --- | ---: |
| 1116 | 8200 |
| 436 | 1500 |

## Por assunto

_campo agregado: `assuntos.codigo`_

| valor | documentos |
| --- | ---: |
| 6017 | 6100 |

## Por órgão julgador

_campo agregado: `orgaoJulgador.nome.keyword`_

| valor | documentos |
| --- | ---: |
| 1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE | 1200 |
| 2ª VARA CÍVEL DA COMARCA DO RECIFE | 900 |

## Por grau

_campo agregado: `grau.keyword`_

| valor | documentos |
| --- | ---: |
| G1 | 9000 |
| G2 | 3000 |

## Por ano de ajuizamento

_campo agregado: `dataAjuizamento (date_histogram year)`_

| valor | documentos |
| --- | ---: |
| 2024 | 5000 |

## Por formato (físico/eletrônico)

_campo agregado: `formato.codigo`_

| valor | documentos |
| --- | ---: |
| 1 | 12000 |

## Por sistema processual

_campo agregado: `sistema.nome.keyword`_

| valor | documentos |
| --- | ---: |
| PJe | 11000 |

## Notas e limitações

- A API Pública do DataJud expõe **apenas metadados** de processos públicos (sem dados das partes).
- O CNJ **não garante** precisão, integridade ou atualidade dos dados (Termo de Uso, item 3.6); a atualização depende do envio do tribunal ao DataJud.
- Uso exclusivamente **legal e não comercial** (itens 3.3 e 3.8); não coletar/cruzar dados pessoais (item 4.2, LGPD).
- Ao divulgar este relatório publicamente, **dê ciência ao CNJ** (item 3.9 do Termo de Uso).
- Limite de consumo: **120 requisições por minuto** (item 3.13).
- Arquivos auxiliares desta execução: `agg-*.tsv` e `agg-*.csv` no mesmo diretório.
__ARQ_EOF__
__ARQ__ main.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
main.py — consulta um processo judicial e gera um relatório completo em Markdown.

Fontes públicas usadas (nenhuma exige cadastro):

  1. API Pública do DataJud (CNJ) — metadados do processo: capa, partes(*) e
     movimentações.   https://datajud-wiki.cnj.jus.br/api-publica/acesso
  2. API do DJEN / Comunica (CNJ) — publicações e intimações do processo, com
     link para o inteiro teor em PDF.   https://comunica.pje.jus.br

(*) A API do DataJud traz apenas METADADOS: número, classe, assuntos, órgão
    julgador, datas e movimentações. NÃO traz nome das partes, CPF, valores e
    NÃO traz as peças/anexos. Para documentos (petições, decisões, anexos) o
    caminho é a consulta pública do tribunal (PJe/e-SAJ) — o relatório inclui
    os links diretos. Veja a seção "Anexos e documentos" do relatório gerado.

Uso:
    python3 main.py 0001234-56.2024.8.17.2001
    python3 main.py 00012345620248172001 -o relatorio.md
    python3 main.py 0001234-56.2024.8.17.2001 --todos          # varre TJPE/TRF5/TRT6/TRE-PE/STJ...
    python3 main.py 0001234-56.2024.8.17.2001 --sem-djen       # só DataJud
    python3 main.py 0001234-56.2024.8.17.2001 --json           # JSON cru
    python3 main.py --ajuda

Variáveis de ambiente:
    DATAJUD_API_KEY    chave pública (o default é a chave vigente da wiki)
    DATAJUD_BASE_URL   default https://api-publica.datajud.cnj.jus.br
    DJEN_BASE_URL      default https://comunicaapi.pje.jus.br/api/v1
    DATAJUD_TIMEOUT    timeout em segundos (default 45)
    DATAJUD_WIKI_URL   página da wiki lida por --chave-publica

Requisitos: Python 3.8+ (apenas biblioteca padrão).

Termo de Uso da API Pública (resumo): uso legal e NÃO comercial; no máximo 120
requisições por minuto (item 3.13); o CNJ não garante precisão/atualidade (3.6);
dar ciência ao CNJ ao divulgar relatórios (3.9); não cruzar dados pessoais (4.2).
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# --------------------------------------------------------------------------- #
# Configuração
# --------------------------------------------------------------------------- #

VERSAO = "1.0.0"

CHAVE_PUBLICA_PADRAO = "cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw=="
DATAJUD_BASE = os.environ.get("DATAJUD_BASE_URL", "https://api-publica.datajud.cnj.jus.br")
DJEN_BASE = os.environ.get("DJEN_BASE_URL", "https://comunicaapi.pje.jus.br/api/v1")
WIKI_URL = os.environ.get("DATAJUD_WIKI_URL", "https://datajud-wiki.cnj.jus.br/api-publica/acesso")
CHAVE = os.environ.get("DATAJUD_API_KEY", CHAVE_PUBLICA_PADRAO)
TIMEOUT = int(os.environ.get("DATAJUD_TIMEOUT", "45"))
USER_AGENT = f"consulta-processual/{VERSAO} (+relatorio em markdown; contato: usuario local)"

TEXTO_ANEXO_AVISO = (
    "A API Pública do DataJud disponibiliza **apenas metadados** — não expõe as "
    "peças nem os anexos do processo. Use os links oficiais abaixo para abrir os "
    "documentos na consulta pública do tribunal."
)

# --------------------------------------------------------------------------- #
# Utilidades de terminal
# --------------------------------------------------------------------------- #

QUIETO = False


def info(msg: str) -> None:
    if not QUIETO:
        print(f"[info] {msg}", file=sys.stderr)


def aviso(msg: str) -> None:
    print(f"[aviso] {msg}", file=sys.stderr)


def erro(msg: str) -> None:
    print(f"[erro] {msg}", file=sys.stderr)


class FalhaConsulta(Exception):
    """Erro esperado, com mensagem amigável."""


# --------------------------------------------------------------------------- #
# Número único (NUP) — Resolução CNJ nº 65/2008
# --------------------------------------------------------------------------- #
# Estrutura: NNNNNNN-DD.AAAA.J.TR.OOOO  (20 dígitos)
#   N = sequencial (7) | DD = dígito verificador (2) | AAAA = ano (4)
#   J = segmento da justiça (1) | TR = tribunal no segmento (2) | OOOO = origem (4)
# DV pelo algoritmo Módulo 97 Base 10 (ISO 7064):
#   DD = 98 - ( (NNNNNNN AAAA J TR OOOO * 100) mod 97 )
# Validação: int(NNNNNNN AAAA J TR OOOO DD) mod 97 == 1

SEGMENTOS = {
    "1": ("STF", "Supremo Tribunal Federal"),
    "2": ("CNJ", "Conselho Nacional de Justiça"),
    "3": ("STJ", "Superior Tribunal de Justiça"),
    "4": ("JF", "Justiça Federal"),
    "5": ("JT", "Justiça do Trabalho"),
    "6": ("JE", "Justiça Eleitoral"),
    "7": ("JMU", "Justiça Militar da União"),
    "8": ("JE-estadual", "Justiça dos Estados e do Distrito Federal"),
    "9": ("JME", "Justiça Militar Estadual"),
}

# Justiça Estadual e Justiça Eleitoral: TR = ordem alfabética das unidades
# federativas (Resolução 65/2008, Anexos I a VII) — o mesmo par UF/código vale
# para as duas justiças. Fonte: 8.17 = TJPE, 8.26 = TJSP, 6.17 = TRE-PE.
_UFS_ALFABETICAS = [
    ("AC", "Acre"), ("AL", "Alagoas"), ("AP", "Amapá"), ("AM", "Amazonas"),
    ("BA", "Bahia"), ("CE", "Ceará"), ("DF", "Distrito Federal e Territórios"),
    ("ES", "Espírito Santo"), ("GO", "Goiás"), ("MA", "Maranhão"),
    ("MT", "Mato Grosso"), ("MS", "Mato Grosso do Sul"), ("MG", "Minas Gerais"),
    ("PA", "Pará"), ("PB", "Paraíba"), ("PR", "Paraná"), ("PE", "Pernambuco"),
    ("PI", "Piauí"), ("RJ", "Rio de Janeiro"), ("RN", "Rio Grande do Norte"),
    ("RS", "Rio Grande do Sul"), ("RO", "Rondônia"), ("RR", "Roraima"),
    ("SC", "Santa Catarina"), ("SE", "Sergipe"), ("SP", "São Paulo"),
    ("TO", "Tocantins"),
]

# Código IBGE de UF (2 primeiros dígitos do código do município) -> UF
UF_IBGE = {
    "11": "RO", "12": "AC", "13": "AM", "14": "RR", "15": "PA", "16": "AP",
    "17": "TO", "21": "MA", "22": "PI", "23": "CE", "24": "RN", "25": "PB",
    "26": "PE", "27": "AL", "28": "SE", "29": "BA", "31": "MG", "32": "ES",
    "33": "RJ", "35": "SP", "41": "PR", "42": "SC", "43": "RS", "50": "MS",
    "51": "MT", "52": "GO", "53": "DF",
}


def somente_digitos(texto: str) -> str:
    return re.sub(r"\D", "", texto or "")


def calcular_dv(numero20_ou_18: str) -> str:
    """Calcula o DD (2 dígitos) de um número CNJ sem os dígitos verificadores."""
    base18 = somente_digitos(numero20_ou_18)
    if len(base18) == 20:  # remove o DV, caso venha completo
        base18 = base18[:7] + base18[9:]
    if len(base18) != 18:
        raise FalhaConsulta("número inválido: esperados 20 dígitos no padrão CNJ.")
    return f"{98 - ((int(base18) * 100) % 97):02d}"


def dv_valido(numero20: str) -> bool:
    """Confere o DV (Anexo VIII da Res. 65/2008): com o DD deslocado para o final
    do número, o resto da divisão por 97 deve ser 1.

        int(NNNNNNN + AAAA + J + TR + OOOO + DD) % 97 == 1
    """
    if len(numero20) != 20 or not numero20.isdigit():
        return False
    reordenado = numero20[:7] + numero20[9:] + numero20[7:9]
    return int(reordenado) % 97 == 1


def formatar_numero(numero20: str) -> str:
    return (f"{numero20[0:7]}-{numero20[7:9]}.{numero20[9:13]}."
            f"{numero20[13:14]}.{numero20[14:16]}.{numero20[16:20]}")


def decodificar(numero20: str) -> dict:
    """Traduz o NUP em segmento, tribunal, sigla e alias do DataJud."""
    seg = numero20[13]
    tr = numero20[14:16]
    ano = numero20[9:13]
    origem = numero20[16:20]
    seg_sigla, seg_nome = SEGMENTOS.get(seg, ("?", "Segmento desconhecido"))

    d = {
        "numero": numero20,
        "ano": ano,
        "origem": origem,
        "segmento": seg,
        "segmento_sigla": seg_sigla,
        "segmento_nome": seg_nome,
        "tr": tr,
        "tribunal_sigla": None,
        "tribunal_nome": None,
        "datajud_alias": None,
        "grau_hint": "G2" if origem == "0000" else "G1",
    }

    indice = int(tr) - 1
    if seg in ("8", "6") and 0 <= indice < len(_UFS_ALFABETICAS):
        # Estadual e Eleitoral: TR = ordem alfabética das UFs (8.17 = TJPE, 6.17 = TRE-PE)
        uf, nome_uf = _UFS_ALFABETICAS[indice]
        if seg == "8":
            # o DF foge do padrão TJ+UF: sigla TJDFT e índice api_publica_tjdft
            sigla = "TJDFT" if uf == "DF" else f"TJ{uf}"
            alias = "tjdft" if uf == "DF" else f"tj{uf.lower()}"
            nome = ("Tribunal de Justiça do Distrito Federal e Territórios" if uf == "DF"
                    else f"Tribunal de Justiça de {nome_uf}")
            d.update(tribunal_sigla=sigla, tribunal_nome=nome, datajud_alias=alias)
        else:
            # idem para a Justiça Eleitoral do DF: sigla TRE-DF e índice api_publica_tre-dft
            sigla = "TRE-DF" if uf == "DF" else f"TRE-{uf}"
            alias = "tre-dft" if uf == "DF" else f"tre-{uf.lower()}"
            d.update(tribunal_sigla=sigla,
                     tribunal_nome=f"Tribunal Regional Eleitoral {'do Distrito Federal' if uf == 'DF' else 'de ' + nome_uf}",
                     datajud_alias=alias)
    elif seg == "5" and tr == "00":  # Tribunal Superior do Trabalho
        d.update(tribunal_sigla="TST", tribunal_nome="Tribunal Superior do Trabalho",
                 datajud_alias="tst")
    elif seg == "6" and tr == "00":  # Tribunal Superior Eleitoral
        d.update(tribunal_sigla="TSE", tribunal_nome="Tribunal Superior Eleitoral",
                 datajud_alias="tse")
    elif seg == "8" and tr == "00":  # processos do próprio tribunal (2º grau originário)
        d.update(tribunal_sigla="TJ (tribunal)", tribunal_nome="Processo originário do tribunal",
                 datajud_alias=None)
    elif seg == "4":  # Justiça Federal: TRF1..TRF6
        d.update(tribunal_sigla=f"TRF{int(tr)}",
                 tribunal_nome=f"Tribunal Regional Federal da {int(tr)}ª Região",
                 datajud_alias=f"trf{int(tr)}")
    elif seg == "5":  # TRT1..TRT24
        d.update(tribunal_sigla=f"TRT{int(tr)}",
                 tribunal_nome=f"Tribunal Regional do Trabalho da {int(tr)}ª Região",
                 datajud_alias=f"trt{int(tr)}")
    elif seg == "3":
        d.update(tribunal_sigla="STJ", tribunal_nome="Superior Tribunal de Justiça", datajud_alias="stj")
    elif seg == "1":
        d.update(tribunal_sigla="STF", tribunal_nome="Supremo Tribunal Federal", datajud_alias=None)
    elif seg == "7":
        d.update(tribunal_sigla="STM", tribunal_nome="Superior Tribunal Militar", datajud_alias="stm")
    elif seg == "2":
        d.update(tribunal_sigla="CNJ", tribunal_nome="Conselho Nacional de Justiça", datajud_alias=None)
    return d


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #


def requisitar(url: str, *, params: dict | None = None, corpo: dict | None = None,
               headers: dict | None = None, tentativas: int = 3, debug: bool = False):
    """Faz GET/POST e devolve (status, objeto_json_ou_texto). Trata 429/5xx com backoff."""
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    dados = None
    cabecalhos = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if corpo is not None:
        dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
        cabecalhos["Content-Type"] = "application/json"
    cabecalhos.update(headers or {})

    if debug:
        print(f"[debug] {'POST' if dados else 'GET'} {url}", file=sys.stderr)
        for k, v in cabecalhos.items():
            valor = v if k.lower() != "authorization" else (v[:16] + "…")
            print(f"[debug]   {k}: {valor}", file=sys.stderr)
        if dados:
            print(f"[debug]   corpo: {dados.decode('utf-8')}", file=sys.stderr)

    ultimo_erro = None
    for tentativa in range(1, tentativas + 1):
        req = urllib.request.Request(url, data=dados, headers=cabecalhos,
                                     method="POST" if dados else "GET")
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resposta:
                bruto = resposta.read()
                if resposta.headers.get("Content-Encoding") == "gzip":
                    bruto = gzip.decompress(bruto)
                texto = bruto.decode("utf-8", errors="replace")
                try:
                    return resposta.status, json.loads(texto)
                except json.JSONDecodeError:
                    return resposta.status, texto
        except urllib.error.HTTPError as e:
            bruto = e.read()
            if e.headers.get("Content-Encoding") == "gzip":
                bruto = gzip.decompress(bruto)
            texto = bruto.decode("utf-8", errors="replace")
            try:
                corpo_erro = json.loads(texto)
            except json.JSONDecodeError:
                corpo_erro = texto
            if e.code in (429, 500, 502, 503, 504) and tentativa < tentativas:
                espera = 2 ** tentativa
                aviso(f"HTTP {e.code} — aguardando {espera}s e tentando de novo "
                      f"({tentativa}/{tentativas - 1})")
                time.sleep(espera)
                ultimo_erro = (e.code, corpo_erro)
                continue
            return e.code, corpo_erro
        except urllib.error.URLError as e:
            ultimo_erro = (0, str(e.reason))
            if tentativa < tentativas:
                time.sleep(1.5 * tentativa)
                continue
            return 0, str(e.reason)
    return ultimo_erro or (0, "falha desconhecida")


def motivo(corpo) -> str:
    """Extrai uma mensagem legível de um erro no estilo Elasticsearch/DJEN."""
    if isinstance(corpo, str):
        return corpo[:300]
    if isinstance(corpo, dict):
        e = corpo.get("error", corpo)
        if isinstance(e, dict):
            for chave in ("root_cause", "caused_by"):
                if isinstance(e.get(chave), list) and e[chave]:
                    cand = e[chave][0]
                    if isinstance(cand, dict) and cand.get("reason"):
                        return str(cand["reason"])[:300]
            for chave in ("reason", "type", "message", "detail"):
                if e.get(chave):
                    return str(e[chave])[:300]
        for chave in ("message", "detail", "title", "erro"):
            if corpo.get(chave):
                return str(corpo[chave])[:300]
    return ""


# --------------------------------------------------------------------------- #
# Consulta 1 — DataJud
# --------------------------------------------------------------------------- #


def consultar_datajud(numero20: str, alias: str, *, debug: bool = False):
    url = f"{DATAJUD_BASE.rstrip('/')}/api_publica_{alias}/_search"
    corpo = {
        "query": {"match": {"numeroProcesso": numero20}},
        "size": 20,
        "sort": [{"grau": {"order": "asc"}}],
    }
    status, resposta = requisitar(url, corpo=corpo, debug=debug,
                                  headers={"Authorization": f"APIKey {CHAVE}"})
    if status in (401, 403):
        raise FalhaConsulta(
            f"HTTP {status} em {url}: chave pública recusada. "
            "Atualize com:  export DATAJUD_API_KEY=\"$(python3 main.py --chave)\""
        )
    if status == 404:
        raise FalhaConsulta(f"HTTP 404 em {url}: alias '{alias}' não existe "
                            "(veja a lista de endpoints na wiki do DataJud).")
    if status == 429:
        raise FalhaConsulta("HTTP 429: limite de requisições do CNJ atingido (120/minuto). "
                            "Aguarde um pouco e rode de novo.")
    if status != 200:
        raise FalhaConsulta(f"HTTP {status} em {url}: {motivo(resposta) or 'resposta inesperada'}")
    if isinstance(resposta, str):
        raise FalhaConsulta(f"resposta não-JSON de {url}: {resposta[:200]}")
    return (resposta.get("hits", {}) or {}).get("hits", []) or []


def buscar_chave_publica() -> str:
    """Lê a chave vigente na página de acesso da wiki do CNJ."""
    status, html = requisitar(WIKI_URL)
    if status != 200 or not isinstance(html, str):
        raise FalhaConsulta(f"não consegui ler a wiki do CNJ (HTTP {status}).")
    texto = re.sub(r"<[^>]+>", " ", html)
    achados = re.findall(r"[A-Za-z0-9+/=]{40,}", texto)
    if not achados:
        raise FalhaConsulta("não encontrei a chave na página — veja "
                            "https://datajud-wiki.cnj.jus.br/api-publica/acesso")
    return achados[0]


# --------------------------------------------------------------------------- #
# Consulta 2 — DJEN / Comunica (publicações e intimações)
# --------------------------------------------------------------------------- #


def _valor(item: dict, *nomes, padrao=""):
    """Lê o primeiro campo presente, aceitando camelCase ou snake_case."""
    for nome in nomes:
        if nome in item and item[nome] not in (None, "", []):
            return item[nome]
    for chave, valor in item.items():
        baixa = chave.lower().replace("_", "")
        for nome in nomes:
            if valor not in (None, "", []) and baixa == nome.lower().replace("_", ""):
                return valor
    return padrao


def consultar_djen(numero20: str, sigla_tribunal: str | None, *, debug: bool = False):
    """GET /comunicacao — público, sem autenticação. Devolve a lista de itens."""
    url = f"{DJEN_BASE.rstrip('/')}/comunicacao"
    params = {"numeroProcesso": numero20, "pagina": 1, "itensPorPagina": 50}
    if sigla_tribunal:
        params["siglaTribunal"] = sigla_tribunal
    status, resposta = requisitar(url, params=params, debug=debug)
    if status == 400 and sigla_tribunal:
        # alguns deploys do DJEN recusam siglaTribunal junto com numeroProcesso
        params.pop("siglaTribunal", None)
        status, resposta = requisitar(url, params=params, debug=debug)
    if status != 200 or not isinstance(resposta, dict):
        raise FalhaConsulta(f"DJEN HTTP {status}: {motivo(resposta) or 'sem detalhe'}")
    for chave in ("items", "itens", "content", "data", "results"):
        if isinstance(resposta.get(chave), list):
            return resposta[chave]
    return []


# --------------------------------------------------------------------------- #
# Formatação
# --------------------------------------------------------------------------- #


def escapar(texto: str) -> str:
    return (str(texto).replace("|", "\\|").replace("\r", " ")
            .replace("\n", "<br>").strip())


def cortar(texto: str, limite: int = 400) -> str:
    texto = re.sub(r"\s+", " ", str(texto)).strip()
    return texto if len(texto) <= limite else texto[:limite].rstrip() + " […]"


def tabela(cabecalho: list, linhas: list) -> list:
    if not linhas:
        return ["_Nenhum registro._", ""]
    saida = ["| " + " | ".join(cabecalho) + " |",
             "|" + "|".join([" --- "] * len(cabecalho)) + "|"]
    for linha in linhas:
        saida.append("| " + " | ".join(escapar(c) for c in linha) + " |")
    saida.append("")
    return saida


def como_data(valor):
    """Converte datas ISO do DataJud ('2024-03-05T12:00:00.000Z') em datetime."""
    if not valor:
        return None
    texto = str(valor).strip().replace("Z", "+00:00")
    for formato in (None, "%Y-%m-%d", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%d %H:%M:%S"):
        try:
            if formato is None:
                return datetime.fromisoformat(texto)
            return datetime.strptime(texto, formato).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def data_br(valor, com_hora: bool = False) -> str:
    d = como_data(valor)
    if not d:
        return str(valor or "—")
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc).strftime("%d/%m/%Y %H:%M" if com_hora else "%d/%m/%Y")


def dias_desde(valor) -> int | None:
    d = como_data(valor)
    if not d:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - d).days


def barra(quantidade: int, maximo: int, largura: int = 28) -> str:
    if maximo <= 0:
        return ""
    return "█" * max(1, round(quantidade / maximo * largura))


def link_tribunal(info_trib: dict, numero_formatado: str) -> list:
    """Links oficiais de consulta pública (documentos/anexos ficam lá)."""
    seg = info_trib.get("segmento")
    sigla = info_trib.get("tribunal_sigla") or ""
    links = []

    if seg == "8" and sigla == "TJPE":
        links += [
            ("Consulta processual unificada TJPE (1º e 2º grau)",
             "http://srv01.tjpe.jus.br/consultaprocessualunificada/"),
            ("PJe 1º Grau — consulta pública (autos e anexos)",
             "https://pje.cloud.tjpe.jus.br/1g/ConsultaPublica/listView.seam"),
            ("PJe 2º Grau — consulta pública (autos e anexos)",
             "https://pje.cloud.tjpe.jus.br/2g/ConsultaPublica/listView.seam"),
            ("Portal de consultas do TJPE", "https://portal.tjpe.jus.br/servicos/consulta-processual"),
            ("Diário de Justiça Eletrônico do TJPE", "http://www.tjpe.jus.br/dje"),
        ]
    elif seg == "8":
        uf = sigla.replace("TJ", "").lower()
        links += [
            (f"Portal do {sigla}", f"https://www.tj{uf}.jus.br/"),
            ("PJe — consulta pública (selecione o tribunal)", "https://www.pje.jus.br/"),
        ]
    elif seg == "4":
        n = sigla.replace("TRF", "")
        links += [
            (f"Portal do {sigla}", f"https://www.trf{n}.jus.br/"),
            ("PJe — consulta pública", "https://www.pje.jus.br/"),
        ]
    elif seg == "5":
        links += [("PJe / PJe-legado — consulta pública (TRTs)", "https://www.pje.jus.br/")]
    elif seg == "6":
        links += [("Consulta processual — TREs", "https://www.tse.jus.br/servicos-judiciais/processos")]
    else:
        links += [(f"Consulta processual — {sigla}", "https://www.cnj.jus.br/")]

    links += [
        ("DJEN — publicações, intimações e inteiro teor",
         f"https://comunica.pje.jus.br/consulta?numeroProcesso={somente_digitos(numero_formatado)}"),
        ("API Pública do DataJud (fonte destes metadados)",
         "https://datajud-wiki.cnj.jus.br/api-publica/acesso"),
    ]
    return links


# --------------------------------------------------------------------------- #
# Relatório
# --------------------------------------------------------------------------- #


def relatorio_markdown(numero20: str, info: dict, documentos: list, djen: list | None,
                       consultas: list, djen_erro: str | None, comando: str) -> str:
    numero_fmt = formatar_numero(numero20)
    seg = info["segmento"]
    linhas: list = []
    agora = datetime.now(timezone.utc)

    def h(titulo: str, nivel: int = 2) -> None:
        linhas.append("#" * nivel + f" {titulo}")
        linhas.append("")

    def paragrafo(texto: str) -> None:
        linhas.append(texto)
        linhas.append("")

    # ---------------- cabeçalho ----------------
    h(f"Processo {numero_fmt}", 1)
    paragrafo(
        f"> **Relatório gerado em** {agora.strftime('%d/%m/%Y às %H:%M')} UTC  \n"
        f"> **Fontes:** API Pública do DataJud (CNJ) e DJEN/Comunica  \n"
        f"> **Índices consultados:** {', '.join('api_publica_' + c['alias'] for c in consultas)}  \n"
        f"> **Comando:** `{comando}`"
    )

    # ---------------- dados principais do documento mais completo ----------------
    principal = documentos[0] if documentos else {}
    src = principal.get("_source", {}) if principal else {}
    classe = src.get("classe", {}) or {}
    orgao = src.get("orgaoJulgador", {}) or {}
    graus = sorted({(d.get("_source", {}) or {}).get("grau", "?") for d in documentos})

    # ---------------- resumo executivo ----------------
    h("1. Resumo executivo")
    mov_principal = (src.get("movimentos") or [])
    ultimo_mov = mov_principal[-1] if mov_principal else {}
    dias_ajuizamento = dias_desde(src.get("dataAjuizamento"))
    dias_ultimo = dias_desde(ultimo_mov.get("dataHora"))
    municipio = orgao.get("codigoMunicipioIBGE")
    uf_municipio = UF_IBGE.get(str(municipio)[:2], "") if municipio else ""

    bullets = [
        f"**Tribunal:** {info['tribunal_sigla']} — {info['tribunal_nome']} "
        f"(segmento {seg}: {info['segmento_nome']})",
        f"**Grau(s) encontrado(s) no índice:** {', '.join(graus) if graus else '—'}",
        f"**Classe:** {classe.get('codigo', '—')} — {classe.get('nome', '—')}",
        f"**Órgão julgador:** {orgao.get('nome', '—')} "
        f"(código {orgao.get('codigo', '—')}"
        + (f", município IBGE {municipio}{' — ' + uf_municipio if uf_municipio else ''})" if municipio else ")"),
        f"**Ajuizamento:** {data_br(src.get('dataAjuizamento'))}"
        + (f" — há **{dias_ajuizamento:,} dias**".replace(",", ".") if dias_ajuizamento is not None else ""),
        f"**Movimentações:** {len(mov_principal)} registro(s); "
        f"última: “{ultimo_mov.get('nome', '—')}” em {data_br(ultimo_mov.get('dataHora'), True)}"
        + (f" (há {dias_ultimo} dias)" if dias_ultimo is not None else ""),
        f"**Publicações no DJEN:** "
        + (f"{len(djen)} encontrada(s)" if djen is not None else f"não consultado ({djen_erro or 'desativado'})"),
    ]
    for b in bullets:
        linhas.append(f"- {b}")
    linhas.append("")

    if not mov_principal:
        paragrafo("⚠️ **Nenhuma movimentação retornada** pela API para este processo "
                  "(comum em processos sigilosos ou recém-distribuídos).")
    if (src.get("nivelSigilo") or 0) and int(src["nivelSigilo"]) > 0:
        paragrafo(f"⚠️ **Nível de sigilo {src['nivelSigilo']}** — a API pública só devolve "
                  "metadados; detalhes adicionais podem estar restritos.")
    if ultimo_mov and re.search(r"arquiv|baixa definitiva", str(ultimo_mov.get("nome", "")), re.I):
        paragrafo(f"ℹ️ O último movimento (“{ultimo_mov.get('nome')}”) sugere **processo arquivado** "
                  "(heurística pelo nome do movimento — confirme na consulta oficial).")

    # ---------------- identificação ----------------
    h("2. Identificação e validação do número")
    dv_informado = numero20[7:9]
    dv_calculado = calcular_dv(numero20)
    linhas += tabela(
        ["Campo", "Valor"],
        [
            ["Número único (CNJ)", formatar_numero(numero20)],
            ["Somente dígitos", numero20],
            ["Dígito verificador", f"{dv_informado} — " + ("válido ✔ (módulo 97 base 10)" if dv_valido(numero20)
                                                          else f"⚠ NÃO confere (esperado {dv_calculado})")],
            ["Ano de ajuizamento (campo AAAA)", info["ano"]],
            ["Segmento (campo J)", f"{seg} — {info['segmento_nome']}"],
            ["Tribunal (campo TR)", f"{info['tr']} — {info['tribunal_sigla']} ({info['tribunal_nome']})"],
            ["Origem (campo OOOO)", info["origem"] + (" — processo originário de 2º grau"
                                                      if info["origem"] == "0000" else "")],
            ["Índice DataJud consultado", f"api_publica_{info['datajud_alias']}"
             if info["datajud_alias"] else "—"],
        ],
    )

    # ---------------- capa ----------------
    h("3. Capa do processo (metadados do DataJud)")
    if documentos:
        for i, doc in enumerate(documentos, 1):
            d = doc.get("_source", {}) or {}
            classe_d = d.get("classe", {}) or {}
            orgao_d = d.get("orgaoJulgador", {}) or {}
            if len(documentos) > 1:
                h(f"3.{i} Documento {i} — grau {d.get('grau', '—')}", 3)
            municipio_d = orgao_d.get("codigoMunicipioIBGE")
            uf_d = UF_IBGE.get(str(municipio_d)[:2], "") if municipio_d else ""
            assuntos = "; ".join(f"{a.get('codigo')} — {a.get('nome')}" for a in (d.get("assuntos") or [])) or "—"
            linhas += tabela(
                ["Campo", "Valor"],
                [
                    ["ID DataJud", d.get("id", doc.get("_id", "—"))],
                    ["Tribunal / grau", f"{d.get('tribunal', '—')} / {d.get('grau', '—')}"],
                    ["Classe processual (TPU)", f"{classe_d.get('codigo', '—')} — {classe_d.get('nome', '—')}"],
                    ["Assuntos (TPU)", assuntos],
                    ["Órgão julgador", f"{orgao_d.get('codigo', '—')} — {orgao_d.get('nome', '—')}"],
                    ["Município do órgão (IBGE)",
                     f"{municipio_d}{' — ' + uf_d if uf_d else ''}" if municipio_d else "—"],
                    ["Data de ajuizamento", data_br(d.get("dataAjuizamento"))],
                    ["Nível de sigilo", d.get("nivelSigilo", "—")],
                    ["Formato", f"{(d.get('formato') or {}).get('codigo', '—')} — "
                                f"{(d.get('formato') or {}).get('nome', '—')}"],
                    ["Sistema", f"{(d.get('sistema') or {}).get('codigo', '—')} — "
                                f"{(d.get('sistema') or {}).get('nome', '—')}"],
                    ["Última atualização na origem", data_br(d.get("dataHoraUltimaAtualizacao"), True)],
                    ["Atualizado no índice (@timestamp)", data_br(d.get("@timestamp"), True)],
                    ["Total de movimentos", len(d.get("movimentos") or [])],
                ],
            )
    else:
        paragrafo("_Nenhum documento retornado pelos índices consultados._")

    # ---------------- movimentos ----------------
    h("4. Movimentações processuais")
    if mov_principal:
        movs = sorted(mov_principal, key=lambda m: str(m.get("dataHora") or ""))
        linhas_dados = []
        for i, m in enumerate(movs, 1):
            complementos = "; ".join(
                f"{c.get('nome', '?')} [{c.get('descricao', '?')}]={c.get('valor', '?')}"
                for c in (m.get("complementosTabelados") or [])
            )
            oj = m.get("orgaoJulgador") or {}
            linhas_dados.append([
                i,
                data_br(m.get("dataHora"), True),
                m.get("codigo", "—"),
                cortar(m.get("nome", "—"), 200),
                cortar(complementos, 200) or "—",
                oj.get("nomeOrgao") or oj.get("nome") or "—",
            ])
        linhas += tabela(["#", "Data/hora (UTC)", "Código", "Movimento", "Complementos", "Órgão"], linhas_dados)
        paragrafo(f"_Tabela com todas as {len(movs)} movimentações retornadas pela API, em ordem cronológica._")
    else:
        paragrafo("_Sem movimentações para exibir._")

    # ---------------- estatísticas ----------------
    h("5. Panorama estatístico")
    if mov_principal:
        por_ano: dict = {}
        por_nome: dict = {}
        por_orgao: dict = {}
        for m in mov_principal:
            d = como_data(m.get("dataHora"))
            if d:
                por_ano[d.year] = por_ano.get(d.year, 0) + 1
            nome = str(m.get("nome") or "—")
            por_nome[nome] = por_nome.get(nome, 0) + 1
            oj = m.get("orgaoJulgador") or {}
            chave = oj.get("nomeOrgao") or oj.get("nome")
            if chave:
                por_orgao[chave] = por_orgao.get(chave, 0) + 1

        if por_ano:
            h("5.1 Movimentações por ano", 3)
            maximo = max(por_ano.values())
            linhas += tabela(
                ["Ano", "Movimentações", "Volume"],
                [[ano, por_ano[ano], barra(por_ano[ano], maximo)] for ano in sorted(por_ano)],
            )

        h("5.2 Movimentos mais frequentes", 3)
        top = sorted(por_nome.items(), key=lambda kv: (-kv[1], kv[0]))[:10]
        linhas += tabela(["Movimento", "Ocorrências"],
                         [[cortar(nome, 120), qtd] for nome, qtd in top])

        if por_orgao:
            h("5.3 Órgãos que movimentaram o processo", 3)
            linhas += tabela(["Órgão julgador", "Movimentações"],
                             [[cortar(nome, 120), qtd] for nome, qtd
                              in sorted(por_orgao.items(), key=lambda kv: -kv[1])[:10]])

        h("5.4 Tempo e inércia", 3)
        movs_ord = sorted([m for m in mov_principal if como_data(m.get("dataHora"))],
                          key=lambda m: str(m.get("dataHora")))
        if len(movs_ord) >= 2:
            maior_gap, par_gap = 0, None
            for anterior, seguinte in zip(movs_ord, movs_ord[1:]):
                delta = (como_data(seguinte["dataHora"]) - como_data(anterior["dataHora"])).days
                if delta > maior_gap:
                    maior_gap, par_gap = delta, (anterior, seguinte)
            paragrafo(f"- **Maior intervalo sem movimentação:** {maior_gap} dias — entre "
                      f"“{par_gap[0].get('nome')}” ({data_br(par_gap[0].get('dataHora'))}) e "
                      f"“{par_gap[1].get('nome')}” ({data_br(par_gap[1].get('dataHora'))}).")
            primeiro = como_data(movs_ord[0]["dataHora"])
            ultimo = como_data(movs_ord[-1]["dataHora"])
            paragrafo(f"- **Janela de movimentações:** {data_br(movs_ord[0]['dataHora'])} a "
                      f"{data_br(movs_ord[-1]['dataHora'])} ({(ultimo - primeiro).days} dias).")
        if dias_ultimo is not None:
            paragrafo(f"- **Sem movimentação há:** {dias_ultimo} dias "
                      f"(considerando a data de hoje)."
                      + ("  \n  _Pode indicar processo parado, arquivado ou ainda não atualizado "
                         "no DataJud._" if dias_ultimo > 180 else ""))
    else:
        paragrafo("_Sem dados suficientes para estatísticas._")

    # ---------------- DJEN ----------------
    h("6. Publicações e intimações (DJEN)")
    if djen is None:
        paragrafo(f"_Não consultado ({djen_erro or 'desativado'})._")
    elif not djen:
        paragrafo("_Nenhuma publicação encontrada no DJEN para este número._")
    else:
        itens_linhas = []
        for item in djen:
            data_disp = _valor(item, "dataDisponibilizacao", "datadisponibilizacao", "data_disponibilizacao")
            tipo = _valor(item, "tipoComunicacao", "tipocomunicacao", "tipo_comunicacao")
            orgao_d = _valor(item, "nomeOrgao", "nomeorgao", "nome_orgao", "orgao")
            texto = cortar(_valor(item, "texto", "conteudo", "resumo"), 300)
            link = _valor(item, "link", "url", "linkInteiroTeor")
            hash_com = _valor(item, "hash", "hashComunicacao")
            if not link and hash_com:
                link = f"{DJEN_BASE.rstrip('/')}/comunicacao/{hash_com}/certidao"
            itens_linhas.append([
                data_br(data_disp),
                tipo,
                cortar(orgao_d, 80),
                texto,
                f"[abrir]({link})" if link else "—",
            ])
        linhas += tabela(["Disponibilização", "Tipo", "Órgão", "Texto", "Inteiro teor"], itens_linhas)
        paragrafo("_Publicação = primeiro dia útil seguinte à disponibilização (art. 224, §2º, CPC). "
                  "Confirme sempre no portal do DJEN._")

    # ---------------- anexos ----------------
    h("7. Anexos e documentos")
    paragrafo(TEXTO_ANEXO_AVISO)
    paragrafo("**O que é possível obter publicamente:**\n")
    linhas.append("| O que | Onde | Observação |")
    linhas.append("| --- | --- | --- |")
    linhas.append("| Movimentações e metadados da capa | API Pública do DataJud | já incluídos neste relatório |")
    linhas.append("| Publicações, intimações e **inteiro teor em PDF** das comunicações | API/portal do DJEN | seção 6 deste relatório |")
    linhas.append("| **Autos completos, petições, decisões e anexos** | Consulta pública do tribunal (PJe/e-SAJ) | exige o processo **não ser sigiloso**; alguns tribunais usam captcha |")
    linhas.append("| Dados de partes (nome, CPF/CNPJ), valores | Portal do tribunal (autos), mediante consulta | a API pública do DataJud **não** expõe partes nem valores |")
    linhas.append("| Dados estruturados para advogado/API autenticada | **MNI** do PJe (certificado digital A1/A3) | integração oficial, exige credencial |")
    linhas.append("")
    paragrafo("Se o processo estiver em **segredo de justiça**, nenhuma consulta pública devolverá "
              "resultado — o acesso é restrito às partes e aos advogados habilitados.")

    # ---------------- links ----------------
    h("8. Links oficiais de consulta")
    for rotulo, url in link_tribunal(info, numero_fmt):
        linhas.append(f"- [{rotulo}]({url})")
    linhas.append("")

    # ---------------- rastreabilidade das consultas ----------------
    h("9. Índices consultados")
    linhas += tabela(
        ["Índice do DataJud", "Documentos encontrados", "Observação"],
        [["api_publica_" + c["alias"], c["documentos"],
          "erro: " + cortar(c["erro"], 160) if c["erro"] else "ok"] for c in consultas],
    )
    if all(c["documentos"] == 0 for c in consultas if not c["erro"]):
        paragrafo("_Nenhum índice devolveu documentos para este número — confira se o "
                  "processo é público e se o tribunal está correto._")

    # ---------------- notas ----------------
    h("10. Notas, limitações e conformidade")
    paragrafo(
        "- Dados de **metadados** de processos **públicos**, obtidos da Base Nacional de Dados do "
        "Poder Judiciário (DataJud), conforme a Portaria CNJ nº 160/2020.\n"
        "- O CNJ **não garante** precisão, integridade ou atualidade dos dados (Termo de Uso, item 3.6); "
        "a atualização depende do envio do tribunal ao DataJud e pode levar dias.\n"
        "- Uso **legal e não comercial** (itens 3.3 e 3.8). Limite de **120 requisições por minuto** "
        "(item 3.13).\n"
        "- Ao divulgar este relatório, **dê ciência ao CNJ** (item 3.9).\n"
        "- **LGPD:** não coletar, armazenar ou cruzar dados pessoais oriundos da API (itens 4.2 e 4.6).\n"
        "- Este relatório é um **resumo automatizado** e **não substitui** a consulta oficial aos autos."
    )
    linhas.append("")
    linhas.append("---")
    linhas.append("")
    linhas.append(f"<sub>Gerado por `main.py` v{VERSAO} em "
                  f"{agora.strftime('%d/%m/%Y %H:%M:%S')} UTC · fontes: DataJud/CNJ e DJEN/CNJ.</sub>")
    linhas.append("")
    return "\n".join(linhas)


# --------------------------------------------------------------------------- #
# Programa principal
# --------------------------------------------------------------------------- #


def executar(args) -> int:
    global QUIETO, CHAVE, TIMEOUT
    QUIETO = args.quieto
    if args.chave:
        CHAVE = args.chave
    if args.timeout:
        TIMEOUT = args.timeout

    # 1) número ------------------------------------------------------------
    numero20 = somente_digitos(args.numero)
    if len(numero20) != 20:
        erro(f"o número informado tem {len(numero20)} dígito(s); o padrão CNJ exige 20 "
             "(ex.: 0001234-56.2024.8.17.2001). Serão considerados apenas os dígitos.")
        raise FalhaConsulta("número inválido")
    if not dv_valido(numero20):
        aviso(f"o dígito verificador {numero20[7:9]} não confere (esperado {calcular_dv(numero20)} "
              "pelo módulo 97 base 10) — seguindo a consulta mesmo assim.")

    info_num = decodificar(numero20)
    info(f"processo {formatar_numero(numero20)} → tribunal {info_num['tribunal_sigla'] or '?'} "
         f"(segmento {info_num['segmento']})")

    # 2) quais índices consultar -------------------------------------------
    aliases: list = []
    if args.buscar_em:
        aliases = [a.strip().lower().replace("api_publica_", "")
                   for a in args.buscar_em.split(",") if a.strip()]
    elif args.todos:
        aliases = ["tjpe", "trf5", "trt6", "tre-pe", "stj", "tst", "tse", "stm"]
        if info_num["datajud_alias"]:
            aliases.insert(0, info_num["datajud_alias"])
    elif info_num["datajud_alias"]:
        aliases = [info_num["datajud_alias"]]
    else:
        raise FalhaConsulta(
            f"não sei qual índice do DataJud corresponde a {info_num['tribunal_sigla'] or numero20[13:16]}. "
            "Informe com --buscar-em (ex.: --buscar-em stj)."
        )

    # 3) consultas ---------------------------------------------------------
    documentos: list = []
    consultas: list = []
    for i, alias in enumerate(dict.fromkeys(aliases)):
        if i:
            time.sleep(0.4)  # cortesia: limite de 120 req/min
        try:
            achados = consultar_datajud(numero20, alias, debug=args.debug)
        except FalhaConsulta as e:
            aviso(f"api_publica_{alias}: {e}")
            consultas.append({"alias": alias, "documentos": 0, "erro": str(e)})
            continue
        info(f"  api_publica_{alias}: "
             + (f"{len(achados)} documento(s)" if achados else "nenhum documento"))
        documentos.extend(achados)
        consultas.append({"alias": alias, "documentos": len(achados), "erro": None})

    if not documentos:
        raise FalhaConsulta(
            f"nenhum documento para o processo {formatar_numero(numero20)} nos índices "
            f"consultados ({', '.join(aliases)}). Confira o número/tribunal, ou rode com "
            "--todos para varrer TJPE, TRF5, TRT6, TRE-PE, STJ, TST, TSE e STM."
        )

    # ordena por grau (G1 antes de G2/JE) para o documento principal ser o 1º grau
    ordem = {"G1": 0, "G2": 1, "JE": 2}
    documentos.sort(key=lambda d: ordem.get((d.get("_source", {}) or {}).get("grau", "?"), 9))

    # 4) DJEN --------------------------------------------------------------
    djen, djen_erro = None, None
    if not args.sem_djen:
        try:
            djen = consultar_djen(numero20, info_num["tribunal_sigla"], debug=args.debug)
            info(f"  DJEN: {len(djen)} publicação(ões)")
        except FalhaConsulta as e:
            djen, djen_erro = None, str(e)
            aviso(f"DJEN: {e} (o relatório segue sem as publicações)")

    # 5) saída -------------------------------------------------------------
    if args.json:
        pacote = {
            "numero": formatar_numero(numero20),
            "tribunal": info_num,
            "consultas": consultas,
            "documentos": documentos,
            "djen": djen,
            "djen_erro": djen_erro,
        }
        texto = json.dumps(pacote, ensure_ascii=False, indent=2)
    else:
        comando = " ".join([sys.executable, os.path.basename(sys.argv[0]), *sys.argv[1:]])
        texto = relatorio_markdown(numero20, info_num, documentos, djen, consultas,
                                   djen_erro, comando)

    if args.saida:
        with open(args.saida, "w", encoding="utf-8") as fh:
            fh.write(texto if texto.endswith("\n") else texto + "\n")
        info(f"relatório gravado em {args.saida}")
        if not QUIETO:
            print(args.saida)
    else:
        print(texto)
    return 0


def montar_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="main.py",
        description="Consulta um processo judicial nas APIs públicas do CNJ "
                    "(DataJud + DJEN) e gera um relatório completo em Markdown.",
        epilog="Exemplos:\n"
               "  python3 main.py 0001234-56.2024.8.17.2001\n"
               "  python3 main.py 0001234-56.2024.8.17.2001 -o processo.md\n"
               "  python3 main.py 0001234-56.2024.8.17.2001 --todos --json\n"
               "  python3 main.py --chave-publica\n",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("numero", nargs="?", help="número do processo (com ou sem máscara)")
    p.add_argument("-o", "--saida", help="grava o relatório neste arquivo (.md ou .json)")
    p.add_argument("--json", action="store_true", help="devolve o JSON cru em vez do Markdown")
    p.add_argument("--todos", action="store_true",
                   help="procura também em TRF5, TRT6, TRE-PE, STJ, TST, TSE e STM")
    p.add_argument("--buscar-em", metavar="ALIASES",
                   help="lista de índices DataJud separada por vírgula (ex.: tjpe,trf5)")
    p.add_argument("--sem-djen", action="store_true", help="não consulta as publicações do DJEN")
    p.add_argument("--chave-publica", action="store_true",
                   help="apenas imprime a chave pública vigente publicada na wiki do CNJ")
    p.add_argument("-k", "--chave-api", dest="chave", metavar="CHAVE",
                   help="usa esta chave do DataJud em vez da padrão")
    p.add_argument("--timeout", type=int, help=f"timeout em segundos (default {TIMEOUT})")
    p.add_argument("--debug", action="store_true", help="mostra as requisições HTTP enviadas")
    p.add_argument("-q", "--quieto", action="store_true", help="silencia mensagens de progresso")
    p.add_argument("-V", "--versao", action="version", version=f"main.py {VERSAO}")
    return p


def main(argv=None) -> int:
    parser = montar_parser()
    args = parser.parse_args(argv)
    if args.chave_publica:
        try:
            print(buscar_chave_publica())
            return 0
        except FalhaConsulta as e:
            erro(str(e))
            return 2
    if not args.numero:
        parser.print_help()
        return 1
    try:
        return executar(args)
    except FalhaConsulta as e:
        erro(str(e))
        return 2
    except KeyboardInterrupt:
        erro("interrompido pelo usuário")
        return 130


if __name__ == "__main__":
    try:  # evita UnicodeEncodeError em consoles Windows (cp1252)
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass
    sys.exit(main())
__ARQ_EOF__
__ARQ__ pipeline/.gitignore
# artefatos do pipeline (JSONs e anexos por execução)
saida/
__ARQ_EOF__
__ARQ__ pipeline/backlog.json
{
  "nome": "backlog do projeto — consulta processual DataJud/DJEN",
  "descricao": "Fila indexada de issues. Cada item traz a instrução de teste executável do entregável; o gate `issue` roda essa instrução e, quando ela passa, marca o item como concluída e entrega a instrução da ISSUE SEGUINTE.",
  "como_usar": [
    "python3 pipeline/gate.py issue                 # roda a próxima pendente (sem marcar)",
    "python3 pipeline/gate.py issue --marcar        # roda e marca concluída se passar",
    "python3 pipeline/gate.py issue --id ISSUE-007  # roda uma issue específica"
  ],
  "status_possiveis": [
    "concluida",
    "pendente",
    "bloqueada"
  ],
  "issues": [
    {
      "id": "ISSUE-001",
      "titulo": "Kit curl para a API Pública do DataJud (TJPE)",
      "entregavel": "scripts/datajud.sh + docs/01-api-datajud.md + docs/02-receitas-curl-tjpe.md",
      "instrucao_teste": "bash tests/rodar-testes.sh",
      "status": "concluida",
      "concluida_em": "2026-10-13T00:00:00Z",
      "depende_de": [],
      "evidencias": [
        "32 verificações offline passando"
      ]
    },
    {
      "id": "ISSUE-002",
      "titulo": "main.py — consulta um processo e gera relatório Markdown",
      "entregavel": "main.py + tests/testar_main.py + tests/mock_apis.py",
      "instrucao_teste": "python3 tests/testar_main.py",
      "status": "concluida",
      "concluida_em": "2026-10-13T00:00:00Z",
      "depende_de": [
        "ISSUE-001"
      ],
      "evidencias": [
        "29 testes: NUP/DV, seções do relatório, DJEN, erros 400/401/404/429"
      ]
    },
    {
      "id": "ISSUE-003",
      "titulo": "Bootstrap auto-criador (estrutura, arquivos, permissões, hashes)",
      "entregavel": "bootstrap.sh + BOOTSTRAP.md + tools/gerar_bootstrap.py",
      "instrucao_teste": "bash tests/testar_bootstrap.sh",
      "status": "concluida",
      "concluida_em": "2026-10-13T00:00:00Z",
      "depende_de": [
        "ISSUE-002"
      ],
      "evidencias": [
        "22 verificações: recriação byte a byte (diff -r), permissões, SHA-256, --verificar"
      ]
    },
    {
      "id": "ISSUE-004",
      "titulo": "Validação de conformidade com a documentação oficial do CNJ",
      "entregavel": "tests/testar_conformidade.py + tabela de conformidade no BOOTSTRAP.md",
      "instrucao_teste": "python3 tests/testar_conformidade.py",
      "status": "concluida",
      "concluida_em": "2026-10-13T00:00:00Z",
      "depende_de": [
        "ISSUE-001"
      ],
      "evidencias": [
        "29 testes contra a wiki do DataJud e o Termo de Uso v1.2"
      ]
    },
    {
      "id": "ISSUE-005",
      "titulo": "Pipeline orientado a gates (JSON) + workflow do GitHub Actions",
      "entregavel": "pipeline/gate.py + pipeline/blueprint.json + pipeline/backlog.json + .github/workflows/gates.yml",
      "instrucao_teste": "python3 tests/testar_pipeline.py",
      "status": "concluida",
      "concluida_em": "2026-10-13T00:00:00Z",
      "depende_de": [
        "ISSUE-003"
      ],
      "evidencias": [
        "contrato JSON, status 0/1/2, continuidade, next_issue, anexos, blueprint e workflow validados"
      ]
    },
    {
      "id": "ISSUE-006",
      "titulo": "Validar as consultas AO VIVO contra as APIs do CNJ (DataJud + DJEN)",
      "entregavel": "relatório real de um processo do TJPE (a execução exige internet para api-publica.datajud.cnj.jus.br)",
      "instrucao_teste": "python3 pipeline/verificar_cnj.py --timeout 20",
      "status": "pendente",
      "depende_de": [
        "ISSUE-002"
      ],
      "observacao": "Instrução executável: consulta real e mínima ao DataJud (size=0). Devolve 0 se o CNJ responder 200, 1 se a rede não alcançar a API (continuidade — é o caso do ambiente de desenvolvimento atual) e 2 se a chave for recusada."
    },
    {
      "id": "ISSUE-007",
      "titulo": "Integrar o gate ao painel de continuidade da sessão (issue #3) e decidir sobre o fluxo da outra sessão",
      "entregavel": "decisão do usuário: unificar os dois fluxos (npm/continuity da sessão d917b13b × python/pipeline desta sessão)",
      "instrucao_teste": null,
      "status": "bloqueada",
      "depende_de": [
        "ISSUE-005"
      ],
      "observacao": "Sem instrução de teste executável de propósito: o gate devolve status 2 (erro tipo 2) e exige decisão humana."
    }
  ]
}
__ARQ_EOF__
__ARQ__ pipeline/blueprint.json
{
  "nome": "pipeline-datajud-gates",
  "versao": "1.0.0",
  "descricao": "Planta do pipeline orientado a gates (gate-driven pipeline), no formato de blueprint tipo BPMN. Cada gate devolve o objeto JSON do contrato {id, status, mensagem, next_issue, anexos, dados} com status 0 (sucesso), 1 (erro tipo 1 = continuidade) ou 2 (erro tipo 2 = indeterminado).",
  "contrato": {
    "campos_obrigatorios": ["id", "gate", "status", "mensagem", "next_issue", "anexos", "dados", "timestamp", "versao"],
    "status": {
      "0": "sucesso — gate positivo, nada pendente; continuidade=false",
      "1": "erro tipo 1 — pendência conhecida e tratável (issue aberta, CI vermelho, teste ausente/reprovado); continuidade=true",
      "2": "erro tipo 2 — não avaliável (gh ausente, fixture inválida, issue sem instrução); continuidade=false, exige humano"
    },
    "anexos": "lista de {path, filename, descricao} — artefatos gerados por cada gate"
  },
  "regra_de_continuidade": "positivo ⇔ (0 issues abertas) ∧ (CI sem execuções com erro) ∧ (testes presentes e aprovados). Enquanto NÃO for positivo ⇒ continuidade = true e next_issue aponta a próxima pendência do backlog.",
  "inicio": "issues",
  "gates": [
    {
      "id": "issues",
      "tipo": "gateway-exclusivo",
      "descricao": "Verifica a NÃO existência de issues abertas (gh issue list ou fixture).",
      "entrada": ["evento do GitHub (push/PR/issues/dispatch)", "fixture opcional --issues-json"],
      "saidas": {
        "0": "nenhuma issue aberta",
        "1": "existe issue aberta → continuidade",
        "2": "não foi possível consultar (gh ausente/sem credencial)"
      },
      "implementacao": "pipeline/gate.py issues",
      "evidencias": "pipeline/saida/issues-abertas.md"
    },
    {
      "id": "cicd",
      "tipo": "gateway-exclusivo",
      "descricao": "Verifica se há execução de CI/CD concluída com erro (failure, timed_out, startup_failure, action_required, cancelled).",
      "entrada": ["gh run list (30 mais recentes)", "fixture opcional --runs-json"],
      "saidas": {
        "0": "nenhuma execução com erro",
        "1": "há execução com erro → continuidade",
        "2": "não foi possível consultar"
      },
      "implementacao": "pipeline/gate.py cicd",
      "evidencias": "pipeline/saida/execucoes-ci.md"
    },
    {
      "id": "testes",
      "tipo": "tarefa",
      "descricao": "Confere a existência dos arquivos de teste e executa a suíte completa.",
      "entrada": ["tests/*.py", "tests/*.sh", "--comando"],
      "saidas": {
        "0": "testes presentes e aprovados",
        "1": "testes ausentes ou reprovados → continuidade",
        "2": "erro de execução (timeout, comando inexistente)"
      },
      "implementacao": "pipeline/gate.py testes",
      "evidencias": "pipeline/saida/log-testes-<ts>.txt"
    },
    {
      "id": "continuidade",
      "tipo": "gateway-inclusivo",
      "descricao": "Agrega issues + cicd + testes no veredito. Só é positivo (0) quando os três são positivos; qualquer pendência conhecida ⇒ 1 (continuidade) com next_issue do backlog; qualquer indeterminação ⇒ 2.",
      "entrada": ["issues", "cicd", "testes", "pipeline/backlog.json"],
      "saidas": {
        "0": "pipeline pode finalizar (continuidade=false, next_issue=null)",
        "1": "pipeline DEVE continuar (continuidade=true, next_issue=<primeira pendente>)",
        "2": "exige intervenção humana (continuidade=false)"
      },
      "implementacao": "pipeline/gate.py continuidade",
      "evidencias": "pipeline/saida/veredito-continuidade.md"
    },
    {
      "id": "issue",
      "tipo": "tarefa",
      "descricao": "Executa a instrução de teste da issue (ou da próxima pendente). Sucesso testado ⇒ marca concluída e entrega a instrução da ISSUE SEGUINTE indexada; falha ⇒ devolve a MESMA issue com o log do erro.",
      "entrada": ["pipeline/backlog.json", "--id opcional", "--marcar"],
      "saidas": {
        "0": "instrução passou — next_issue = próxima pendente (ou null se acabou)",
        "1": "instrução falhou — next_issue = a mesma issue (continuidade)",
        "2": "issue sem instrucao_teste executável — requer decisão humana"
      },
      "implementacao": "pipeline/gate.py issue",
      "evidencias": ["pipeline/saida/<ID>-log.txt", "pipeline/saida/<ID>-proxima-issue.md"]
    }
  ],
  "transicoes": [
    {"de": "issues", "para": "cicd", "quando_status": "0", "condicao": "sem issue aberta"},
    {"de": "issues", "para": "cicd", "quando_status": "1", "condicao": "com issue aberta — ainda assim avalia o resto (o veredito sai no agregador)"},
    {"de": "issues", "para": "continuidade", "quando_status": "2", "condicao": "indeterminado — o agregador decide status 2"},
    {"de": "cicd", "para": "testes", "quando_status": "0", "condicao": "CI limpo"},
    {"de": "cicd", "para": "testes", "quando_status": "1", "condicao": "CI com erro — segue avaliando os testes"},
    {"de": "cicd", "para": "continuidade", "quando_status": "2", "condicao": "indeterminado"},
    {"de": "testes", "para": "continuidade", "quando_status": "0", "condicao": "testes verdes"},
    {"de": "testes", "para": "continuidade", "quando_status": "1", "condicao": "testes vermelhos/ausentes"},
    {"de": "testes", "para": "continuidade", "quando_status": "2", "condicao": "indeterminado"},
    {"de": "continuidade", "para": "issue", "quando_status": "1", "condicao": "continuidade=true → executar a próxima issue do backlog"},
    {"de": "continuidade", "para": "fim", "quando_status": "0", "condicao": "gate positivo — nada pendente, pipeline pode encerrar"},
    {"de": "continuidade", "para": "fim", "quando_status": "2", "condicao": "erro tipo 2 — para e exige humano"},
    {"de": "issue", "para": "issue", "quando_status": "1", "condicao": "falhou — repete a MESMA issue"},
    {"de": "issue", "para": "continuidade", "quando_status": "0", "condicao": "passou — reavalia o gate agregado com a próxima issue"},
    {"de": "issue", "para": "fim", "quando_status": "2", "condicao": "issue sem instrução executável — exige humano"}
  ],
  "gatilhos_github_actions": {
    "arquivo": ".github/workflows/gates.yml",
    "on": ["push", "pull_request", "issues (opened/closed/reopened)", "schedule (dias úteis 09:00)", "workflow_dispatch"],
    "jobs": {
      "gate-issues": "executa `gate.py issues`, publica o JSON e o anexo",
      "gate-cicd": "executa `gate.py cicd`, publica o JSON e o anexo",
      "gate-testes": "executa `gate.py testes` (suíte completa)",
      "gate-continuidade": "agrega os três (needs) e decide: 0 finaliza, 1 continua, 2 falha o job",
      "executa-issue": "roda a próxima issue do backlog quando continuidade=true (workflow_dispatch)"
    },
    "saidas": ["artifacts com pipeline/saida/*", "GITHUB_STEP_SUMMARY com o veredito", "exit code = status do gate"]
  }
}
__ARQ_EOF__
__ARQ__ pipeline/gate.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gate.py — gates do pipeline (gate-driven pipeline / blueprint tipo BPMN).

Cada ação deste pipeline devolve SEMPRE o mesmo objeto JSON no stdout:

    {
      "id":          "gate-continuidade-20261013T141500Z-8f3a1c",  # único
      "gate":        "continuidade",
      "status":      "0",              # string: 0=sucesso, 1=erro tipo 1, 2=erro tipo 2
      "codigo_saida": 0,               # mesmo valor, como inteiro (exit code do processo)
      "mensagem":    "...",            # string pronta OU resumo/log da execução
      "continuidade": true,            # true = o pipeline DEVE continuar (trabalho pendente)
      "next_issue":  "ISSUE-007",      # mesma issue se falhou; a próxima se passou
      "anexos":      [{"path": "...", "filename": "...", "descricao": "..."}],
      "dados":       { ... },          # detalhes estruturados de cada gate
      "timestamp":   "2026-10-13T14:15:00Z",
      "versao":      "1.0.0"
    }

Semântica dos códigos (contrato do projeto):

  "0" SUCESSO      — o gate é positivo: nada pendente. `continuidade` = false.
  "1" ERRO TIPO 1  — pendência CONHECIDA e tratável: issue aberta, CI vermelho ou
                     teste ausente/reprovado. `continuidade` = true → o pipeline
                     segue (é o "enquanto não positivo, significa continuidade").
  "2" ERRO TIPO 2  — não foi possível avaliar (gh ausente/sem credencial, fixture
                     inválida, issue sem instrução de teste). `continuidade` = false
                     → exige intervenção humana; não continue automaticamente.

O código de saída do processo é igual ao `status` (0, 1 ou 2), para uso direto em
`if`/`|| true` dentro do GitHub Actions.

Comandos:
    gate.py issues        [--sem-gh|--issues-json F]      # existem issues abertas?
    gate.py cicd          [--sem-gh|--runs-json F]        # há execução de CI com erro?
    gate.py testes        [--comando "make testes"]       # os testes existem e passam?
    gate.py continuidade                                  # agrega os três acima
    gate.py issue [--id ISSUE-007] [--marcar]             # executa a instrução da issue
    gate.py blueprint                                     # valida a planta (BPMN-like)
    gate.py situacao                                      # lê os últimos JSONs gravados

Opções comuns:
    --json-saida ARQUIVO   grava o objeto JSON também em arquivo
    --saida-dir DIR        diretório de anexos/JSON (padrão: pipeline/saida)
    --backlog ARQUIVO      fila de issues (padrão: pipeline/backlog.json)
    --repo OWNER/REPO      repositório para consultas via gh (padrão: o atual)
    -q/--quieto            não imprime o JSON no stdout (só grava)

Requisitos: Python 3.8+ (biblioteca padrão). `gh` é necessário para os gates
`issues` e `cicd` fora do modo fixture.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

VERSAO = "1.0.0"
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAIDA_PADRAO = os.path.join(RAIZ, "pipeline", "saida")
BACKLOG_PADRAO = os.path.join(RAIZ, "pipeline", "backlog.json")
BLUEPRINT_PADRAO = os.path.join(RAIZ, "pipeline", "blueprint.json")

STATUS_SUCESSO, STATUS_CONTINUIDADE, STATUS_INDETERMINADO = "0", "1", "2"

# comandos de teste usados pelo gate `testes` e pela checagem de presença
ARQUIVOS_DE_TESTE = [
    "tests/testar_conformidade.py",
    "tests/testar_main.py",
    "tests/rodar-testes.sh",
    "tests/testar_bootstrap.sh",
    "tests/testar_pipeline.py",
]
COMANDO_TESTES_PADRAO = "make testes"


class ErroGate(Exception):
    """Falha do tipo 2 (não foi possível avaliar) com mensagem pronta."""


# --------------------------------------------------------------------------- #
# contrato JSON
# --------------------------------------------------------------------------- #


def agora() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def novo_id(gate: str) -> str:
    carimbo = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"gate-{gate}-{carimbo}-{uuid.uuid4().hex[:6]}"


def objeto(*, gate: str, status: str, mensagem: str, anexos=None, dados=None,
           next_issue=None, continuidade=None, duracao: float = 0.0) -> dict:
    """Monta o objeto JSON do contrato. Unico ponto de criação — garante o formato."""
    if continuidade is None:
        continuidade = status == STATUS_CONTINUIDADE
    return {
        "id": novo_id(gate),
        "gate": gate,
        "status": str(status),
        "codigo_saida": int(status),
        "mensagem": str(mensagem),
        "continuidade": bool(continuidade),
        "next_issue": next_issue,
        "anexos": [
            {"path": a.get("path"), "filename": os.path.basename(a.get("path") or ""),
             "descricao": a.get("descricao", "")}
            for a in (anexos or [])
        ],
        "dados": dados or {},
        "timestamp": agora(),
        "duracao_s": round(duracao, 3),
        "versao": VERSAO,
    }


def gravar(objeto_json: dict, saida_dir: str) -> dict:
    """Grava o objeto em pipeline/saida/<id>.json e devolve o registro do anexo."""
    os.makedirs(saida_dir, exist_ok=True)
    caminho = os.path.join(saida_dir, f"{objeto_json['id']}.json")
    with open(caminho, "w", encoding="utf-8") as fh:
        json.dump(objeto_json, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return {"path": caminho, "filename": os.path.basename(caminho),
            "descricao": f"objeto JSON do gate {objeto_json['gate']}"}


def gravar_anexo(nome: str, conteudo: str, saida_dir: str, descricao: str) -> dict:
    os.makedirs(saida_dir, exist_ok=True)
    caminho = os.path.join(saida_dir, nome)
    with open(caminho, "w", encoding="utf-8") as fh:
        fh.write(conteudo)
    return {"path": caminho, "filename": os.path.basename(caminho), "descricao": descricao}


def executar(comando: str, tempo_limite: int = 1800) -> tuple:
    """Roda um comando de shell e devolve (código, saída_completa)."""
    processo = subprocess.run(["/bin/bash", "-lc", comando], capture_output=True,
                              text=True, timeout=tempo_limite, cwd=RAIZ)
    saida = (processo.stdout or "") + (processo.stderr or "")
    return processo.returncode, saida


# --------------------------------------------------------------------------- #
# backlog (fila indexada de issues)
# --------------------------------------------------------------------------- #


def ler_backlog(caminho: str = BACKLOG_PADRAO) -> dict:
    if not os.path.exists(caminho):
        raise ErroGate(f"backlog não encontrado: {caminho}")
    try:
        with open(caminho, encoding="utf-8") as fh:
            dados = json.load(fh)
    except json.JSONDecodeError as e:
        raise ErroGate(f"backlog inválido (JSON): {e}")
    if not isinstance(dados.get("issues"), list) or not dados["issues"]:
        raise ErroGate("backlog sem a lista 'issues' ou vazia")
    return dados


def ordenar(issues: list) -> list:
    def chave(item):
        m = re.search(r"(\d+)$", str(item.get("id", "")))
        return int(m.group(1)) if m else 0
    return sorted(issues, key=chave)


def proxima_pendente(backlog: dict, excluir=None) -> dict | None:
    """Primeira issue não concluída, ignorando ids em `excluir` (as já validadas na execução)."""
    ignorar = set(excluir or ())
    for item in ordenar(backlog["issues"]):
        if item.get("id") in ignorar:
            continue
        if str(item.get("status", "")).lower() not in ("concluida", "concluída", "done"):
            return item
    return None


def achar_issue(backlog: dict, identificador: str) -> dict | None:
    for item in backlog["issues"]:
        if item.get("id") == identificador:
            return item
    return None


def marcar_concluida(backlog: dict, identificador: str, evidencias: dict) -> None:
    item = achar_issue(backlog, identificador)
    if item is None:
        raise ErroGate(f"issue {identificador} não está no backlog")
    item["status"] = "concluida"
    item["concluida_em"] = agora()
    item.setdefault("evidencias", [])
    item["evidencias"].append(evidencias)


# --------------------------------------------------------------------------- #
# gates de verificação
# --------------------------------------------------------------------------- #


def _rodar_gh(argumentos: list) -> list:
    if shutil.which("gh") is None:
        raise ErroGate("o comando 'gh' não está instalado — não é possível avaliar "
                       "issues/CI (use --issues-json/--runs-json ou --sem-gh)")
    proc = subprocess.run(["gh", *argumentos], capture_output=True, text=True, cwd=RAIZ)
    if proc.returncode != 0:
        raise ErroGate(f"gh {' '.join(argumentos[:3])} falhou: "
                       f"{(proc.stderr or proc.stdout).strip()[:300]}")
    try:
        return json.loads(proc.stdout or "[]")
    except json.JSONDecodeError as e:
        raise ErroGate(f"resposta do gh não é JSON: {e}")


def gate_issues(args, saida_dir: str) -> dict:
    inicio = time.time()
    if args.issues_json:
        with open(args.issues_json, encoding="utf-8") as fh:
            abertas = json.load(fh)
        fonte = f"fixture {args.issues_json}"
    elif args.sem_gh:
        raise ErroGate("modo --sem-gh exige --issues-json (sem fonte para avaliar issues)")
    else:
        consulta = ["issue", "list", "--state", "open", "--limit", "100",
                    "--json", "number,title,url,labels,createdAt"]
        if args.repo:
            consulta += ["--repo", args.repo]
        abertas = _rodar_gh(consulta)
        fonte = "gh issue list"

    linhas = [f"| #{i.get('number')} | {i.get('title','')} | {i.get('url','')} |" for i in abertas]
    anexo = gravar_anexo("issues-abertas.md",
                         "# Issues abertas\n\n| # | título | url |\n| --- | --- | --- |\n"
                         + ("\n".join(linhas) or "| — | nenhuma | — |") + "\n",
                         saida_dir, "lista de issues abertas consultadas pelo gate")

    if abertas:
        return objeto(
            gate="issues", status=STATUS_CONTINUIDADE, continuidade=True,
            mensagem=f"{len(abertas)} issue(s) aberta(s) — pendência conhecida: o pipeline "
                     f"continua (fonte: {fonte})",
            anexos=[anexo], dados={"fonte": fonte, "abertas": len(abertas), "issues": abertas},
            duracao=time.time() - inicio)
    return objeto(
        gate="issues", status=STATUS_SUCESSO,
        mensagem=f"nenhuma issue aberta (fonte: {fonte})",
        anexos=[anexo], dados={"fonte": fonte, "abertas": 0, "issues": []},
        duracao=time.time() - inicio)


def gate_cicd(args, saida_dir: str) -> dict:
    inicio = time.time()
    if args.runs_json:
        with open(args.runs_json, encoding="utf-8") as fh:
            execucoes = json.load(fh)
        fonte = f"fixture {args.runs_json}"
    elif args.sem_gh:
        raise ErroGate("modo --sem-gh exige --runs-json (sem fonte para avaliar o CI)")
    else:
        consulta = ["run", "list", "--limit", "30",
                    "--json", "databaseId,workflowName,status,conclusion,headBranch,url"]
        if args.repo:
            consulta += ["--repo", args.repo]
        execucoes = _rodar_gh(consulta)
        fonte = "gh run list"

    problematicas = [e for e in execucoes
                     if str(e.get("conclusion") or "").lower() in
                     ("failure", "timed_out", "startup_failure", "action_required", "cancelled")
                     and str(e.get("status") or "completed") == "completed"]
    pendentes = [e for e in execucoes if str(e.get("status") or "") in ("in_progress", "queued")]

    linhas = [f"| {e.get('workflowName') or e.get('name')} | {e.get('status')} | "
              f"{e.get('conclusion')} | {e.get('headBranch')} | {e.get('url','')} |"
              for e in execucoes]
    anexo = gravar_anexo("execucoes-ci.md",
                         "# Execuções de CI/CD\n\n| workflow | status | conclusão | branch | url |\n"
                         "| --- | --- | --- | --- | --- |\n"
                         + ("\n".join(linhas) or "| — | — | — | — | — |") + "\n",
                         saida_dir, "execuções de CI recentes consultadas pelo gate")

    dados = {"fonte": fonte, "total": len(execucoes), "com_erro": len(problematicas),
             "em_andamento": len(pendentes),
             "workflows": sorted({str(e.get("workflowName") or e.get("name") or "?")
                                  for e in execucoes})}
    if problematicas:
        nomes = ", ".join(sorted({str(e.get("workflowName") or "?") for e in problematicas}))
        return objeto(
            gate="cicd", status=STATUS_CONTINUIDADE, continuidade=True,
            mensagem=f"{len(problematicas)} execução(ões) de CI com erro ({nomes}) — "
                     "pendência conhecida: o pipeline continua",
            anexos=[anexo], dados={**dados, "execucoes_com_erro": problematicas},
            duracao=time.time() - inicio)
    return objeto(
        gate="cicd", status=STATUS_SUCESSO,
        mensagem=(f"CI sem erros ({len(execucoes)} execução(ões) analisada(s)"
                  + (f", {len(pendentes)} em andamento" if pendentes else "") + f"; fonte: {fonte})"),
        anexos=[anexo], dados=dados, duracao=time.time() - inicio)


def gate_testes(args, saida_dir: str) -> dict:
    inicio = time.time()
    faltando = [a for a in ARQUIVOS_DE_TESTE if not os.path.exists(os.path.join(RAIZ, a))]
    comando = args.comando or COMANDO_TESTES_PADRAO

    if faltando:
        anexo = gravar_anexo("testes-ausentes.md",
                             "# Testes ausentes\n\n" + "\n".join(f"- `{a}`" for a in faltando) + "\n",
                             saida_dir, "arquivos de teste ausentes")
        return objeto(
            gate="testes", status=STATUS_CONTINUIDADE, continuidade=True,
            mensagem=f"sem testes: {len(faltando)} arquivo(s) ausente(s) "
                     f"({', '.join(faltando)}) — pendência conhecida",
            anexos=[anexo], dados={"faltando": faltando, "comando": None},
            duracao=time.time() - inicio)

    codigo, saida = executar(comando)
    anexo = gravar_anexo(f"log-testes-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.txt",
                         f"$ {comando}\n(código de saída: {codigo})\n\n{saida}",
                         saida_dir, "log completo da execução dos testes")
    dados = {"comando": comando, "codigo_saida": codigo,
             "arquivos_testados": ARQUIVOS_DE_TESTE,
             "resumo": [l for l in saida.splitlines() if l.strip().startswith(
                 ("Ran ", "OK", "FAILED", "Resultado"))][-4:]}

    if codigo == 0:
        return objeto(
            gate="testes", status=STATUS_SUCESSO,
            mensagem=f"testes presentes e aprovados (`{comando}`, código 0)",
            anexos=[anexo], dados=dados, duracao=time.time() - inicio)
    return objeto(
        gate="testes", status=STATUS_CONTINUIDADE, continuidade=True,
        mensagem=f"testes reprovados (`{comando}`, código {codigo}) — pendência conhecida: "
                 "o pipeline continua até ficar verde",
        anexos=[anexo], dados=dados, duracao=time.time() - inicio)


def gate_continuidade(args, saida_dir: str) -> dict:
    """Agrega issues + CI + testes na decisão de continuidade.

    Regra do projeto: o gate só é POSITIVO quando não há issue aberta, não há CI
    com erro e existem testes passando. Enquanto não for positivo ⇒ continuidade.
    """
    inicio = time.time()
    parciais, anexos = {}, []

    for nome, funcao, override in (("issues", gate_issues, getattr(args, "status_issues", None)),
                                   ("cicd", gate_cicd, getattr(args, "status_cicd", None)),
                                   ("testes", gate_testes, getattr(args, "status_testes", None))):
        if override is not None:
            # valor vindo de outro job do workflow (encadeamento por `needs`)
            parciais[nome] = objeto(
                gate=nome, status=str(override), continuidade=str(override) == STATUS_CONTINUIDADE,
                mensagem=f"status {override} informado por outro job do pipeline "
                         f"(--status-{nome.lstrip('-')})",
                dados={"origem": "job anterior"})
        else:
            try:
                parciais[nome] = funcao(args, saida_dir)
            except ErroGate as e:
                parciais[nome] = objeto(gate=nome, status=STATUS_INDETERMINADO,
                                        continuidade=False, mensagem=str(e))
        anexos.extend(parciais[nome]["anexos"])

    # contexto: próxima issue do backlog (alimenta o campo next_issue)
    try:
        backlog = ler_backlog(args.backlog)
        proxima = proxima_pendente(backlog)
        contexto_backlog = {"proxima_pendente": (proxima or {}).get("id"),
                            "titulo": (proxima or {}).get("titulo"),
                            "instrucao_teste": (proxima or {}).get("instrucao_teste")}
    except ErroGate as e:
        proxima, contexto_backlog = None, {"erro": str(e)}

    indeterminados = [n for n, p in parciais.items() if p["status"] == STATUS_INDETERMINADO]
    pendentes = [n for n, p in parciais.items() if p["status"] == STATUS_CONTINUIDADE]

    if indeterminados:
        status = STATUS_INDETERMINADO
        continuidade = False
        mensagem = (f"não foi possível avaliar: {', '.join(indeterminados)} — "
                    "exige intervenção (erro tipo 2): "
                    + " | ".join(parciais[n]["mensagem"] for n in indeterminados))
    elif pendentes:
        status = STATUS_CONTINUIDADE
        continuidade = True
        mensagem = ("gate NÃO positivo — continuidade obrigatória. Pendências: "
                    + "; ".join(f"{n} ({parciais[n]['dados'].get('abertas', parciais[n]['dados'].get('com_erro', '?'))})"
                                for n in pendentes))
    else:
        status = STATUS_SUCESSO
        continuidade = False
        mensagem = "gate positivo: nenhuma issue aberta, CI sem erros e testes aprovados"

    dados = {
        "checks": {n: {"status": p["status"], "mensagem": p["mensagem"]} for n, p in parciais.items()},
        "gate_positivo": status == STATUS_SUCESSO,
        "regra": "positivo ⇔ (0 issues abertas) ∧ (CI sem erro) ∧ (testes presentes e verdes)",
        "backlog": contexto_backlog,
    }

    resultado = objeto(
        gate="continuidade", status=status, continuidade=continuidade, mensagem=mensagem,
        next_issue=(proxima or {}).get("id") if continuidade else None,
        anexos=anexos, dados=dados, duracao=time.time() - inicio)

    # anexo consolidado em markdown (resumo humano do veredito)
    resumo_md = [
        "# Veredito do gate de continuidade", "",
        f"- **status:** `{resultado['status']}` "
        f"({'sucesso' if status == '0' else 'continuidade' if status == '1' else 'indeterminado'})",
        f"- **continuidade:** `{str(continuidade).lower()}`",
        f"- **next_issue:** `{resultado['next_issue'] or '—'}`",
        f"- **timestamp:** {resultado['timestamp']}", "",
        "| check | status | mensagem |", "| --- | --- | --- |",
    ]
    for nome, parcial in parciais.items():
        resumo_md.append(f"| {nome} | {parcial['status']} | {parcial['mensagem']} |")
    resultado["anexos"].append(gravar_anexo(
        "veredito-continuidade.md", "\n".join(resumo_md) + "\n", saida_dir,
        "veredito do gate em Markdown (resumo para humanos)"))
    return resultado


# --------------------------------------------------------------------------- #
# gate de execução de issue (instrução → teste → próxima issue)
# --------------------------------------------------------------------------- #


def gate_issue(args, saida_dir: str) -> dict:
    """Executa a instrução de teste da issue e devolve a PRÓXIMA indexada.

    − sucesso testado (código 0): status 0, marca concluída (com --marcar) e o
      `next_issue` passa a ser a próxima pendente, junto com a instrução dela;
    − falha no teste: status 1 (continuidade), `next_issue` = a MESMA issue;
    − issue sem instrução executável: status 2 (precisa de gente).
    """
    inicio = time.time()
    backlog = ler_backlog(args.backlog)
    identificador = args.id or (proxima_pendente(backlog) or {}).get("id")
    if not identificador:
        raise ErroGate("não há issue pendente no backlog e nenhuma foi informada em --id")

    issue = achar_issue(backlog, identificador)
    if issue is None:
        raise ErroGate(f"issue {identificador} não existe no backlog ({args.backlog})")

    instrucao = (issue.get("instrucao_teste") or "").strip()
    if not instrucao:
        return objeto(
            gate="issue", status=STATUS_INDETERMINADO, continuidade=False,
            next_issue=identificador,
            mensagem=f"{identificador} (“{issue.get('titulo')}”) não tem instrucao_teste "
                     "executável — requer decisão humana (erro tipo 2)",
            dados={"issue": issue, "backlog": args.backlog}, duracao=time.time() - inicio)

    codigo, saida = executar(instrucao)
    anexo_log = gravar_anexo(f"{identificador}-log.txt",
                             f"$ {instrucao}\n(código de saída: {codigo})\n\n{saida}",
                             saida_dir, f"log da instrução de teste da {identificador}")
    anexos = [anexo_log]

    if codigo == 0:
        if args.marcar:
            marcar_concluida(backlog, identificador,
                             {"teste": instrucao, "codigo_saida": 0, "quando": agora()})
            with open(args.backlog, "w", encoding="utf-8") as fh:
                json.dump(backlog, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
        # a issue recém-validada não entra como "próxima" (mesmo sem --marcar)
        proxima = proxima_pendente(backlog, excluir=[identificador])
        if proxima:
            guia = [
                f"# Próxima issue: {proxima.get('id')} — {proxima.get('titulo')}", "",
                f"- **entregável:** {proxima.get('entregavel', '—')}",
                f"- **instrução de teste:** `{proxima.get('instrucao_teste') or '—'}`", "",
                "## Como executar", "```bash",
                f"python3 pipeline/gate.py issue --id {proxima.get('id')} --marcar",
                "```", "",
                f"_(depende de: {', '.join(proxima.get('depende_de', []) )or '—'})_",
            ]
            anexos.append(gravar_anexo(f"{identificador}-proxima-issue.md", "\n".join(guia) + "\n",
                                       saida_dir,
                                       f"instrução da issue seguinte ({proxima.get('id')})"))
            mensagem = (f"{identificador} testada com sucesso (código 0) — "
                        f"segue a issue {proxima.get('id')}: {proxima.get('titulo')}"
                        + ("" if args.marcar else
                           " (não marcada: use --marcar para persistir a conclusão no backlog)"))
            next_issue = proxima.get("id")
        else:
            mensagem = (f"{identificador} testada com sucesso (código 0) — backlog sem pendências"
                        + ("" if args.marcar else
                           " (não marcada: use --marcar para persistir a conclusão no backlog)"))
            next_issue = None
        return objeto(
            gate="issue", status=STATUS_SUCESSO, continuidade=bool(proxima),
            mensagem=mensagem, next_issue=next_issue, anexos=anexos,
            dados={"issue": identificador, "teste": instrucao, "codigo_saida": 0,
                   "marcada_concluida": bool(args.marcar), "backlog": args.backlog,
                   "resumo": saida[-1500:]},
            duracao=time.time() - inicio)

    return objeto(
        gate="issue", status=STATUS_CONTINUIDADE, continuidade=True,
        next_issue=identificador,
        mensagem=f"{identificador} ainda não passa (`{instrucao}`, código {codigo}) — "
                 "continuidade: repita/mesma issue até ficar verde",
        anexos=anexos,
        dados={"issue": identificador, "teste": instrucao, "codigo_saida": codigo,
               "backlog": args.backlog, "resumo": saida[-1500:]},
        duracao=time.time() - inicio)


# --------------------------------------------------------------------------- #
# blueprint e situação
# --------------------------------------------------------------------------- #


def gate_blueprint(args, saida_dir: str) -> dict:
    inicio = time.time()
    with open(args.blueprint, encoding="utf-8") as fh:
        planta = json.load(fh)

    falhas = []
    gates_planta = {g["id"] for g in planta.get("gates", [])}
    implementacao = {"issues", "cicd", "testes", "continuidade", "issue"}
    if not gates_planta:
        falhas.append("blueprint sem 'gates'")
    if gates_planta - implementacao:
        falhas.append(f"gates no blueprint sem implementação: {sorted(gates_planta - implementacao)}")
    ligados = set()
    for t in planta.get("transicoes", []):
        for campo in ("de", "para", "quando_status"):
            if campo not in t:
                falhas.append(f"transição sem '{campo}': {t}")
        ligados.add(t.get("de"))
    if gates_planta - ligados - {"fim"}:
        falhas.append(f"gates sem transição de saída: {sorted(gates_planta - ligados - {'fim'})}")

    if falhas:
        anexo = gravar_anexo("blueprint-erros.md", "# Falhas na planta\n\n"
                             + "\n".join(f"- {f}" for f in falhas) + "\n", saida_dir,
                             "falhas de consistência da planta")
        return objeto(gate="blueprint", status=STATUS_INDETERMINADO, continuidade=False,
                      mensagem="blueprint inconsistente: " + "; ".join(falhas),
                      anexos=[anexo], dados={"falhas": falhas}, duracao=time.time() - inicio)

    return objeto(gate="blueprint", status=STATUS_SUCESSO,
                  mensagem=f"planta consistente: {len(gates_planta)} gates, "
                           f"{len(planta.get('transicoes', []))} transições",
                  dados={"gates": sorted(gates_planta),
                         "transicoes": len(planta.get("transicoes", [])),
                         "arquivo": args.blueprint}, duracao=time.time() - inicio)


def gate_situacao(args, saida_dir: str) -> dict:
    """Lê os últimos JSONs gravados e resume a situação do pipeline."""
    inicio = time.time()
    if not os.path.isdir(saida_dir):
        return objeto(gate="situacao", status=STATUS_INDETERMINADO, continuidade=False,
                      mensagem=f"sem histórico: {saida_dir} não existe", duracao=time.time() - inicio)
    ultimos = {}
    for nome in sorted(os.listdir(saida_dir)):
        if not nome.endswith(".json"):
            continue
        with open(os.path.join(saida_dir, nome), encoding="utf-8") as fh:
            try:
                obj = json.load(fh)
            except json.JSONDecodeError:
                continue
        ultimos[obj.get("gate", "?")] = obj

    linhas = ["| gate | status | continuidade | next_issue | quando |",
              "| --- | --- | --- | --- | --- |"]
    for nome, obj in ultimos.items():
        linhas.append(f"| {nome} | {obj.get('status')} | {obj.get('continuidade')} | "
                      f"{obj.get('next_issue') or '—'} | {obj.get('timestamp')} |")
    anexo = gravar_anexo("situacao.md", "# Situação dos gates\n\n" + "\n".join(linhas) + "\n",
                         saida_dir, "tabela com o último resultado de cada gate")
    return objeto(gate="situacao", status=STATUS_SUCESSO,
                  mensagem=f"{len(ultimos)} gate(s) com histórico em {saida_dir}",
                  anexos=[anexo], dados={"ultimos": {k: {"status": v["status"],
                                                         "continuidade": v["continuidade"]}
                                                     for k, v in ultimos.items()}},
                  duracao=time.time() - inicio)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def montar_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gate.py",
        description="Gates do pipeline (JSON sempre no stdout; código de saída = status).",
        epilog="Status: 0=sucesso, 1=erro tipo 1/continuidade, 2=erro tipo 2/indeterminado.")
    p.add_argument("gate", choices=["issues", "cicd", "testes", "continuidade", "issue",
                                    "blueprint", "situacao"])
    p.add_argument("--json-saida", help="arquivo extra para o objeto JSON")
    p.add_argument("--saida-dir", default=os.environ.get("GATE_SAIDA_DIR") or SAIDA_PADRAO)
    p.add_argument("--backlog", default=BACKLOG_PADRAO)
    p.add_argument("--blueprint", default=BLUEPRINT_PADRAO)
    p.add_argument("--repo", default=os.environ.get("GATE_REPO"))
    p.add_argument("--id", help="(gate issue) identificador da issue, ex.: ISSUE-007")
    p.add_argument("--marcar", action="store_true",
                   help="(gate issue) marca a issue como concluída no backlog quando passa")
    p.add_argument("--comando", help=f"(gate testes) comando a executar (padrão: {COMANDO_TESTES_PADRAO})")
    p.add_argument("--issues-json", help="(gates issues/continuidade) fixture de issues abertas")
    p.add_argument("--runs-json", help="(gates cicd/continuidade) fixture de execuções de CI")
    p.add_argument("--sem-gh", action="store_true", help="não chamar gh (usa apenas fixtures)")
    for _nome in ("issues", "cicd", "testes"):
        p.add_argument(f"--status-{_nome}", choices=["0", "1", "2"],
                       help=f"(continuidade) usa este status para '{_nome}' em vez de avaliar "
                            "— encadeamento de jobs do workflow")
    p.add_argument("-q", "--quieto", action="store_true", help="não imprime o JSON no stdout")
    p.add_argument("-V", "--versao", action="version", version=f"gate.py {VERSAO}")
    return p


def main(argv=None) -> int:
    args = montar_parser().parse_args(argv)
    funcoes = {"issues": gate_issues, "cicd": gate_cicd, "testes": gate_testes,
               "continuidade": gate_continuidade, "issue": gate_issue,
               "blueprint": gate_blueprint, "situacao": gate_situacao}
    try:
        resultado = funcoes[args.gate](args, args.saida_dir)
    except ErroGate as e:
        resultado = objeto(gate=args.gate, status=STATUS_INDETERMINADO, continuidade=False,
                           mensagem=f"erro tipo 2: {e}")
    except subprocess.TimeoutExpired:
        resultado = objeto(gate=args.gate, status=STATUS_INDETERMINADO, continuidade=False,
                           mensagem="erro tipo 2: tempo limite excedido na execução")
    except FileNotFoundError as e:
        resultado = objeto(gate=args.gate, status=STATUS_INDETERMINADO, continuidade=False,
                           mensagem=f"erro tipo 2: arquivo não encontrado ({e})")

    if args.saida_dir:
        resultado["anexos"].append(gravar(resultado, args.saida_dir))
    if args.json_saida:
        os.makedirs(os.path.dirname(os.path.abspath(args.json_saida)), exist_ok=True)
        with open(args.json_saida, "w", encoding="utf-8") as fh:
            json.dump(resultado, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    if not args.quieto:
        print(json.dumps(resultado, ensure_ascii=False, indent=2))
    return int(resultado["status"])


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass
    sys.exit(main())
__ARQ_EOF__
__ARQ__ pipeline/verificar_cnj.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verificar_cnj.py — instrução executável da ISSUE-006 (validação ao vivo do CNJ).

Faz uma consulta real e mínima à API Pública do DataJud e responde com o MESMO
objeto JSON do contrato do pipeline (id, mensagem, anexos, status, next_issue).

Códigos (contrato do projeto):
    0 — a API respondeu 200 com JSON válido: acesso ao CNJ confirmado
    1 — não foi possível alcançar a API (rede restrita/timeout): continuidade,
        precisa rodar num ambiente com internet
    2 — a API respondeu, mas de forma inesperada (ex.: 401 — chave trocada;
        precisa de decisão humana)

Uso:
    python3 pipeline/verificar_cnj.py [--tribunal tjpe] [--timeout 20] [--json-saida F]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

CHAVE_PADRAO = "cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw=="
BASE = os.environ.get("DATAJUD_BASE_URL", "https://api-publica.datajud.cnj.jus.br")


def objeto(status: str, mensagem: str, dados: dict, id_gate: str = "verificar-cnj") -> dict:
    return {
        "id": f"{id_gate}-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}",
        "gate": id_gate,
        "status": str(status),
        "codigo_saida": int(status),
        "mensagem": mensagem,
        "continuidade": str(status) == "1",
        "next_issue": "ISSUE-006" if str(status) != "0" else None,
        "anexos": [],
        "dados": dados,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "versao": "1.0.0",
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Validação ao vivo da API Pública do DataJud")
    p.add_argument("--tribunal", default="tjpe")
    p.add_argument("--timeout", type=int, default=20)
    p.add_argument("--chave", default=os.environ.get("DATAJUD_API_KEY", CHAVE_PADRAO))
    p.add_argument("--json-saida")
    args = p.parse_args(argv)

    url = f"{BASE.rstrip('/')}/api_publica_{args.tribunal}/_search"
    corpo = json.dumps({"query": {"match_all": {}}, "size": 0, "track_total_hits": True}).encode()
    requisicao = urllib.request.Request(
        url, data=corpo, method="POST",
        headers={"Authorization": f"APIKey {args.chave}", "Content-Type": "application/json",
                 "Accept": "application/json", "User-Agent": "pipeline-gates/1.0"})

    inicio = time.time()
    try:
        with urllib.request.urlopen(requisicao, timeout=args.timeout) as resposta:
            bruto = resposta.read()
            dados = json.loads(bruto.decode("utf-8", errors="replace"))
            total = (((dados.get("hits") or {}).get("total") or {}).get("value"))
            resultado = objeto("0", f"API do CNJ acessível: HTTP {resposta.status}, "
                                    f"índice api_publica_{args.tribunal}, "
                                    f"hits.total={total} — acesso confirmado",
                               {"url": url, "http": resposta.status, "took_ms": dados.get("took"),
                                "total": total, "duracao_s": round(time.time() - inicio, 2)})
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            resultado = objeto("2", f"HTTP {e.code}: chave pública recusada pelo CNJ — "
                                    "atualize a chave (python3 main.py --chave-publica) "
                                    "(erro tipo 2: exige decisão humana)",
                               {"url": url, "http": e.code})
        else:
            resultado = objeto("1", f"HTTP {e.code} do CNJ — situação inesperada; "
                                    "continuidade: tente novamente",
                               {"url": url, "http": e.code})
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        resultado = objeto("1", f"não foi possível alcançar {BASE} ({e.__class__.__name__}: "
                                f"{str(e)[:160]}) — continuidade: rode num ambiente com internet",
                           {"url": url, "erro": str(e)[:300],
                            "duracao_s": round(time.time() - inicio, 2)})

    if args.json_saida:
        with open(args.json_saida, "w", encoding="utf-8") as fh:
            json.dump(resultado, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    print(json.dumps(resultado, ensure_ascii=False, indent=2))
    return int(resultado["status"])


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass
    sys.exit(main())
__ARQ_EOF__
__ARQ__ scripts/datajud.sh
#!/usr/bin/env bash
# =============================================================================
#  datajud.sh — consultas à API Pública do DataJud (CNJ) com curl + jq
# =============================================================================
#  Documentação oficial (fonte da verdade):
#    • Acesso / chave  : https://datajud-wiki.cnj.jus.br/api-publica/acesso
#    • Endpoints       : https://datajud-wiki.cnj.jus.br/api-publica/endpoints
#    • Glossário       : https://datajud-wiki.cnj.jus.br/api-publica/glossario
#    • Exemplos 1-3    : https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo1
#    • Termo de uso    : https://formularios.cnj.jus.br/wp-content/uploads/2023/11/Termos-de-uso-api-publica-V1.2.pdf
#
#  Requisitos: bash >= 4.3, curl, jq
#  Exemplos:  ./scripts/datajud.sh ajuda
#
#  Termo de Uso (resumo): uso legal e NÃO comercial; máx. 120 req/min (item 3.13);
#  CNJ não garante precisão/atualidade (3.6); não coletar/cruzar dados pessoais
#  (4.2 - LGPD); dar ciência ao CNJ de relatórios divulgados ao público (3.9).
# =============================================================================
set -euo pipefail

# ------------------------------ configuração ---------------------------------
# A chave pública vigente é publicada pela wiki e pode ser trocada pelo CNJ a
# qualquer momento. Este valor é apenas o default; sobrescreva com
# DATAJUD_API_KEY ou rode: ./scripts/datajud.sh chave
CHAVE_PUBLICA_PADRAO="cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw=="

WIKI_ACESSO="${DATAJUD_WIKI_URL:-https://datajud-wiki.cnj.jus.br/api-publica/acesso}"
BASE_URL="${DATAJUD_BASE_URL:-https://api-publica.datajud.cnj.jus.br}"
API_KEY="${DATAJUD_API_KEY:-$CHAVE_PUBLICA_PADRAO}"
TRIBUNAL="${DATAJUD_TRIBUNAL:-tjpe}"
TIMEOUT="${DATAJUD_TIMEOUT:-60}"
PAUSA_PADRAO="${DATAJUD_PAUSA:-0.3}"
DEBUG="${DATAJUD_DEBUG:-0}"
TOPO_PADRAO="${DATAJUD_TOPO:-15}"

COR_ERRO='\033[1;31m'; COR_AVISO='\033[1;33m'; COR_INFO='\033[1;34m'; COR_OK='\033[1;32m'; COR_FIM='\033[0m'
if [[ ! -t 2 ]]; then COR_ERRO=''; COR_AVISO=''; COR_INFO=''; COR_OK=''; COR_FIM=''; fi

info()  { printf "${COR_INFO}[info]${COR_FIM} %s\n"  "$*" >&2; }
aviso() { printf "${COR_AVISO}[aviso]${COR_FIM} %s\n" "$*" >&2; }
erro()  { printf "${COR_ERRO}[erro]${COR_FIM} %s\n"   "$*" >&2; }
morrer() { erro "$*"; exit 1; }
exigir() { command -v "$1" >/dev/null 2>&1 || morrer "programa '$1' não encontrado no PATH"; }

# Contadores globais usados no cabeçalho do relatório
REQ_TOTAL=0
HTTP_STATUS=""
RESPOSTA=""

# -------------------------------- utilidades ---------------------------------
data_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

alinhar_iso() { # 2024-01-31 -> 2024-01-31T00:00:00.000Z  (o DataJud usa ISO-8601 UTC)
  local d="$1"
  case "$d" in
    ????-??-??) printf '%sT00:00:00.000Z' "$d" ;;
    ????-??-????:??) printf '%s:00.000Z' "$d" ;;
    *) printf '%s' "$d" ;;
  esac
}

normalizar_alias() { # tjpe | api_publica_tjpe | TJPE -> api_publica_tjpe
  local a; a="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  a="${a#api_publica_}"
  [[ -n "$a" ]] || morrer "alias de tribunal vazio"
  printf 'api_publica_%s' "$a"
}

url_search() { printf '%s/%s/_search' "$BASE_URL" "$(normalizar_alias "$TRIBUNAL")"; }

# ------------------------------ HTTP (curl) ----------------------------------
requisicao() { # $1 = corpo JSON. Define HTTP_STATUS e RESPOSTA. Só morre em falha de rede.
  local corpo="$1" alvo; alvo="$(url_search)"
  local tmp; tmp="$(mktemp)"
  local http
  if [[ "$DEBUG" == "1" ]]; then
    printf "${COR_INFO}[debug]${COR_FIM} curl -sS --max-time %s -X POST '%s' \\\\\n" "$TIMEOUT" "$alvo" >&2
    printf "            -H 'Authorization: APIKey %s' \\\\\n" "$API_KEY" >&2
    printf "            -H 'Content-Type: application/json' \\\\\n" >&2
    printf "            --data-binary '%s'\n" "$corpo" >&2
  fi
  if ! http="$(curl -sS --max-time "$TIMEOUT" -o "$tmp" -w '%{http_code}' -X POST "$alvo" \
        -H "Authorization: APIKey $API_KEY" \
        -H 'Content-Type: application/json' \
        --data-binary "$corpo")"; then
    rm -f "$tmp"
    morrer "falha de rede ao chamar $alvo — verifique internet/proxy/firewall."
  fi
  RESPOSTA="$(cat "$tmp")"; rm -f "$tmp"
  HTTP_STATUS="$http"; REQ_TOTAL=$((REQ_TOTAL + 1))
}

motivo_erro() { # extrai a mensagem do erro no estilo Elasticsearch
  printf '%s' "$1" | jq -r '
    (.error.root_cause[0].reason? // .error.reason? // .error.type? // .message? // empty)
    | tostring' 2>/dev/null || true
}

tratar_erro_http() { # $1 = status, $2 = corpo
  local http="$1" corpo="$2" motivo tipo
  motivo="$(motivo_erro "$corpo")"
  tipo="$(printf '%s' "$corpo" | jq -r '.error.type? // empty' 2>/dev/null || true)"
  erro "HTTP $http do DataJud${tipo:+ ($tipo)}${motivo:+ — $motivo}"
  case "$http" in
    401|403) erro "→ Chave pública ausente, inválida ou trocada pelo CNJ."
             erro "  Atualize com: export DATAJUD_API_KEY=\$(bash scripts/datajud.sh chave)"
             erro "  Cabeçalho correto: Authorization: APIKey <chave>" ;;
    404)     erro "→ Alias de tribunal inexistente ($TRIBUNAL). Lista: https://datajud-wiki.cnj.jus.br/api-publica/endpoints" ;;
    429)     erro "→ Limite de requisições atingido (Termo de Uso, item 3.13: 120 req/min). Aguarde e reduza o ritmo." ;;
    400)     erro "→ Query DSL rejeitada pelo Elasticsearch (campo inexistente, agregação sem fielddata, sintaxe)." ;;
    5*)      erro "→ Instabilidade do lado do CNJ. Tente novamente mais tarde." ;;
  esac
  return 1
}

checar_sucesso() { [[ "$HTTP_STATUS" == 2* ]] || tratar_erro_http "$HTTP_STATUS" "$RESPOSTA"; }

# ------------------------- construção da consulta ----------------------------
# Cláusulas acumuladas nos filtros de linha de comando
CLAUSULAS=()

add_clausula() { CLAUSULAS+=("$1"); }

adicionar_filtros() { # função única que traduz flags em cláusulas bool/must
  [[ -n "$F_CLASSE"    ]] && add_clausula "$(jq -nc --argjson v "$F_CLASSE"    '{match:{"classe.codigo":$v}}')"
  [[ -n "$F_ASSUNTO"   ]] && add_clausula "$(jq -nc --argjson v "$F_ASSUNTO"   '{match:{"assuntos.codigo":$v}}')"
  [[ -n "$F_ORGAO"     ]] && add_clausula "$(jq -nc --argjson v "$F_ORGAO"     '{match:{"orgaoJulgador.codigo":$v}}')"
  [[ -n "$F_MUNICIPIO" ]] && add_clausula "$(jq -nc --argjson v "$F_MUNICIPIO" '{match:{"orgaoJulgador.codigoMunicipioIBGE":$v}}')"
  [[ -n "$F_GRAU"      ]] && add_clausula "$(jq -nc --arg v "$F_GRAU"          '{match:{grau:$v}}')"
  [[ -n "$F_SIGILO"    ]] && add_clausula "$(jq -nc --argjson v "$F_SIGILO"    '{match:{nivelSigilo:$v}}')"
  if [[ -n "$F_DE" || -n "$F_ATE" ]]; then
    local gte lte int
    gte="$([[ -n "$F_DE"  ]] && alinhar_iso "$F_DE"  || true)"
    lte="$([[ -n "$F_ATE" ]] && alinhar_iso "$F_ATE" || true)"
    int="$(jq -nc --arg g "$gte" --arg l "$lte" '{gte:$g,lte:$l} | with_entries(select(.value!=""))')"
    add_clausula "$(jq -nc --argjson r "$int" '{range:{dataAjuizamento:$r}}')"
  fi
}

montar_query() { # devolve o objeto "query" pronto
  if [[ "${#CLAUSULAS[@]}" -eq 0 ]]; then
    printf '{"match_all":{}}'
  else
    local arr; arr="$(printf '%s\n' "${CLAUSULAS[@]}" | jq -sc .)"
    jq -nc --argjson a "$arr" '{bool:{must:$a}}'
  fi
}

descricao_filtros() {
  local partes=()
  [[ -n "$F_CLASSE"    ]] && partes+=("classe.codigo=$F_CLASSE")
  [[ -n "$F_ASSUNTO"   ]] && partes+=("assuntos.codigo=$F_ASSUNTO")
  [[ -n "$F_ORGAO"     ]] && partes+=("orgaoJulgador.codigo=$F_ORGAO")
  [[ -n "$F_MUNICIPIO" ]] && partes+=("orgaoJulgador.codigoMunicipioIBGE=$F_MUNICIPIO")
  [[ -n "$F_GRAU"      ]] && partes+=("grau=$F_GRAU")
  [[ -n "$F_SIGILO"    ]] && partes+=("nivelSigilo=$F_SIGILO")
  [[ -n "$F_DE"        ]] && partes+=("dataAjuizamento>=${F_DE}")
  [[ -n "$F_ATE"       ]] && partes+=("dataAjuizamento<=${F_ATE}")
  if [[ "${#partes[@]}" -eq 0 ]]; then printf 'nenhum (todos os processos públicos do índice)'; else
    printf '%s' "${partes[*]}"; fi
}

# ------------------------------ agregações -----------------------------------
# Mapeia o apelido amigável -> campo no mapeamento do Elasticsearch
campo_es() {
  case "$1" in
    classe|codigo-classe)   printf 'classe.codigo' ;;
    classe-nome)            printf 'classe.nome.keyword' ;;
    assunto|codigo-assunto) printf 'assuntos.codigo' ;;
    assunto-nome)           printf 'assuntos.nome.keyword' ;;
    orgao|orgao-julgador)   printf 'orgaoJulgador.codigo' ;;
    orgao-nome)             printf 'orgaoJulgador.nome.keyword' ;;
    municipio)              printf 'orgaoJulgador.codigoMunicipioIBGE' ;;
    grau)                   printf 'grau.keyword' ;;
    sistema)                printf 'sistema.codigo' ;;
    sistema-nome)           printf 'sistema.nome.keyword' ;;
    formato)                printf 'formato.codigo' ;;
    movimento|codigo-movimento) printf 'movimentos.codigo' ;;
    movimento-nome)         printf 'movimentos.nome.keyword' ;;
    ano)                    printf 'dataAjuizamento~year' ;;   # date_histogram
    mes)                    printf 'dataAjuizamento~month' ;;  # date_histogram
    *) return 1 ;;
  esac
}

campo_alternativo() { # .keyword <-> campo texto puro
  case "$1" in
    *.keyword) printf '%s' "${1%.keyword}" ;;
    *)         printf '%s.keyword' "$1" ;;
  esac
}

campo_reserva_codigo() { # último recurso quando nada em texto é agregável
  case "$1" in
    classe.nome*)        printf 'classe.codigo' ;;
    assuntos.nome*)      printf 'assuntos.codigo' ;;
    orgaoJulgador.nome*) printf 'orgaoJulgador.codigo' ;;
    sistema.nome*)       printf 'sistema.codigo' ;;
    movimentos.nome*)    printf 'movimentos.codigo' ;;
    *) printf '' ;;
  esac
}

lista_campos_agregaveis() {
  printf '%s\n' 'classe, classe-nome, assunto, assunto-nome, orgao, orgao-nome, municipio,' \
                'grau, sistema, sistema-nome, formato, movimento, movimento-nome, ano, mes'
}

# Executa uma agregação de termos. Define AGG_BUCKETS (JSON) e CAMPO_USADO.
executar_agg_termos() { # $1 = campo ES, $2 = tamanho
  local corpo
  corpo="$(jq -nc --argjson q "$(montar_query)" --arg c "$1" --argjson t "$2" \
    '{size:0, query:$q, aggs:{por_campo:{terms:{field:$c, size:$t}}}}')"
  requisicao "$corpo"
  AGG_BUCKETS="$(printf '%s' "$RESPOSTA" | jq -c '.aggregations.por_campo.buckets // []')"
}

# Executa uma agregação de data (date_histogram). Define AGG_BUCKETS.
executar_agg_data() { # $1 = campo data, $2 = intervalo, $3 = formato
  local corpo
  corpo="$(jq -nc --argjson q "$(montar_query)" --arg c "$1" --arg i "$2" --arg f "$3" \
    '{size:0, query:$q,
      aggs:{por_campo:{date_histogram:{field:$c, calendar_interval:$i, format:$f, min_doc_count:1}}}}')"
  requisicao "$corpo"
  AGG_BUCKETS="$(printf '%s' "$RESPOSTA" | jq -c '.aggregations.por_campo.buckets // []')"
}

# Roda a agregação com degradação automática (texto -> texto.keyword -> codigo)
executar_agg_com_fallback() { # $1 = apelido do campo, $2 = topo
  local apelido="$1" topo="$2" primario alt reserva candidatos c
  primario="$(campo_es "$apelido")" || morrer "campo de agregação desconhecido: '$apelido'. Aceitos: $(lista_campos_agregaveis)"

  if [[ "$primario" == *"~"* ]]; then   # agregação de data
    local campo="${primario%~*}" intervalo="${primario#*~}" formato
    [[ "$intervalo" == "year" ]] && formato="yyyy" || formato="yyyy-MM"
    executar_agg_data "$campo" "$intervalo" "$formato" || true
    if [[ "$HTTP_STATUS" != 2* ]]; then
      tratar_erro_http "$HTTP_STATUS" "$RESPOSTA" || true
      morrer "não foi possível agregar por $apelido."
    fi
    CAMPO_USADO="$campo (date_histogram $intervalo)"
    return 0
  fi

  alt="$(campo_alternativo "$primario")"
  reserva="$(campo_reserva_codigo "$primario")"
  candidatos=("$primario" "$alt")
  [[ -n "$reserva" && "$reserva" != "$primario" && "$reserva" != "$alt" ]] && candidatos+=("$reserva")

  for c in "${candidatos[@]}"; do
    executar_agg_termos "$c" "$topo"
    if [[ "$HTTP_STATUS" == 2* ]]; then
      CAMPO_USADO="$c"
      [[ "$c" != "$primario" ]] && aviso "campo '$primario' não é agregável neste índice; usando '$c'."
      return 0
    fi
    if ! printf '%s' "$(motivo_erro "$RESPOSTA")" | grep -qiE 'fielddata|aggrega|no field found|not supported'; then
      tratar_erro_http "$HTTP_STATUS" "$RESPOSTA" || true
      return 1
    fi
    aviso "agregação em '$c' recusada pela API; tentando alternativa..."
  done
  erro "nenhum campo agregável para '$apelido' (tentado: ${candidatos[*]})."
  return 1
}

buckets_para_tsv() { printf 'valor\tdocumentos\n'; printf '%s' "$AGG_BUCKETS" |
  jq -r '.[] | [(.key_as_string // .key | tostring), (.doc_count | tostring)] | @tsv'; }

buckets_para_csv() { printf '%s' "$AGG_BUCKETS" |
  jq -r '(["valor","documentos"] | @csv), (.[] | [(.key_as_string // .key | tostring), .doc_count] | @csv)'; }

buckets_para_md() {
  printf '| valor | documentos |\n| --- | ---: |\n'
  printf '%s' "$AGG_BUCKETS" | jq -r '.[] | "| \(.key_as_string // .key | tostring | gsub("\\|"; "\\\\|")) | \(.doc_count) |"'
}

# -------------------------------- comandos -----------------------------------
cmd_chave() {
  exigir curl
  info "consultando a chave pública vigente em $WIKI_ACESSO"
  local html chave
  html="$(curl -sS --max-time "$TIMEOUT" "$WIKI_ACESSO")" || morrer "não foi possível ler a wiki do CNJ."
  local texto; texto="$(printf '%s' "$html" | sed 's/<[^>]*>//g')"
  # estratégia 1: token que aparece logo após a palavra APIKey
  chave="$(printf '%s' "$texto" | grep -oE 'APIKey[[:space:]]*:?[[:space:]]*[A-Za-z0-9+/=]{40,}' \
            | head -1 | grep -oE '[A-Za-z0-9+/=]{40,}$' || true)"
  # estratégia 2 (fallback): primeiro token base64 longo da página
  if [[ -z "$chave" ]]; then
    chave="$(printf '%s' "$texto" | grep -oE '[A-Za-z0-9+/=]{40,}' | head -1 || true)"
  fi
  [[ -n "$chave" ]] || morrer "não encontrei a chave na página (o layout da wiki pode ter mudado). Veja $WIKI_ACESSO"
  printf '%s\n' "$chave"
  info "use: export DATAJUD_API_KEY='$chave'"
}

cmd_processo() {
  local numero="$1"
  [[ -n "$numero" ]] || morrer "informe o número do processo (somente dígitos, 20 caracteres, sem máscara)."
  numero="${numero//[!0-9]/}"   # remove . - e espaços
  info "buscando numeroProcesso=$numero em $TRIBUNAL"
  local corpo; corpo="$(jq -nc --arg n "$numero" '{query:{match:{numeroProcesso:$n}}, size:1}')"
  requisicao "$corpo"; checar_sucesso || exit 1
  if [[ "$(printf '%s' "$RESPOSTA" | jq -r '.hits.total.value')" == "0" ]]; then
    erro "processo não encontrado no índice $TRIBUNAL."
    erro "Confira o tribunal de origem: G1/G2 de PE = tjpe; federais = trf5; trabalhistas = trt6; eleitorais = tre-pe."
    return 1
  fi
  if [[ "$SAIDA_JSON" == "1" ]]; then printf '%s\n' "$RESPOSTA" | jq .; return 0; fi
  local doc; doc="$(printf '%s' "$RESPOSTA" | jq '.hits.hits[0]._source')"
  printf 'Processo......: %s\n' "$(printf '%s' "$doc" | jq -r '.numeroProcesso')"
  printf 'Tribunal/grau.: %s / %s\n' "$(printf '%s' "$doc" | jq -r '.tribunal')" "$(printf '%s' "$doc" | jq -r '.grau')"
  printf 'Classe........: %s - %s\n' "$(printf '%s' "$doc" | jq -r '.classe.codigo')" "$(printf '%s' "$doc" | jq -r '.classe.nome')"
  printf 'Órgão julgador: %s - %s\n' "$(printf '%s' "$doc" | jq -r '.orgaoJulgador.codigo')" "$(printf '%s' "$doc" | jq -r '.orgaoJulgador.nome')"
  printf 'Assuntos......: %s\n' "$(printf '%s' "$doc" | jq -r '[.assuntos[]? | "\(.codigo) - \(.nome)"] | join("; ")')"
  printf 'Ajuizamento...: %s\n' "$(printf '%s' "$doc" | jq -r '.dataAjuizamento')"
  printf 'Sigilo........: %s\n' "$(printf '%s' "$doc" | jq -r '.nivelSigilo')"
  printf 'Formato/sist..: %s / %s\n' "$(printf '%s' "$doc" | jq -r '.formato.nome')" "$(printf '%s' "$doc" | jq -r '.sistema.nome')"
  printf 'Movimentos....: %s registros (último: %s em %s)\n' \
    "$(printf '%s' "$doc" | jq -r '.movimentos | length')" \
    "$(printf '%s' "$doc" | jq -r '.movimentos[-1].nome // "-"')" \
    "$(printf '%s' "$doc" | jq -r '.movimentos[-1].dataHora // "-"')"
  if [[ "$MOSTRAR_MOVIMENTOS" == "1" ]]; then
    printf '\ncodigo\tdataHora\tnome\n'
    printf '%s' "$doc" | jq -r '.movimentos[] | [.codigo, .dataHora, .nome] | @tsv'
  fi
}

cmd_contar() {
  local corpo; corpo="$(jq -nc --argjson q "$(montar_query)" '{query:$q, size:0, track_total_hits:true}')"
  info "contando processos (filtros: $(descricao_filtros))"
  requisicao "$corpo"; checar_sucesso || exit 1
  if [[ "$SAIDA_JSON" == "1" ]]; then printf '%s\n' "$RESPOSTA" | jq '{total:.hits.total.value, relacao:.hits.total.relation}'; return 0; fi
  local total relacao
  total="$(printf '%s' "$RESPOSTA" | jq -r '.hits.total.value')"
  relacao="$(printf '%s' "$RESPOSTA" | jq -r '.hits.total.relation')"
  printf 'Total: %s (relação: %s)\n' "$total" "$relacao"
  [[ "$relacao" == "gte" ]] && aviso "a API limita a contagem a 10.000: o total real é MAIOR. Estreite os filtros ou use agregações."
  return 0
}

cmd_agregar() {
  local apelido="$1"; [[ -n "$apelido" ]] || morrer "informe o campo. Aceitos: $(lista_campos_agregaveis)"
  info "agregando por '$apelido' (filtros: $(descricao_filtros))"
  executar_agg_com_fallback "$apelido" "$TOPO" || exit 1
  if [[ "$SAIDA_JSON" == "1" ]]; then
    printf '%s' "$AGG_BUCKETS" | jq -c --arg campo "$CAMPO_USADO" '{campo:$campo, buckets:.}'
    return 0
  fi
  printf '# campo agregado: %s\n' "$CAMPO_USADO"
  [[ "$(printf '%s' "$AGG_BUCKETS" | jq 'length')" == "0" ]] && aviso "nenhum resultado para os filtros informados."
  buckets_para_tsv
}

cmd_paginar() { # paginação eficiente com search_after (Exemplo 3 da wiki)
  local limite="$1" pagina="$2" pausa="$3" destino="$4"
  [[ "$pagina" -ge 1 && "$pagina" -le 10000 ]] || morrer "--pagina deve ficar entre 1 e 10000."
  local saida
  if [[ -n "$destino" ]]; then saida="$destino"; else saida="/dev/stdout"; fi
  local fichatmp; fichatmp="$(mktemp)"
  local search_after="" coletados=0 n lote ult sortv corpo
  info "paginando (filtros: $(descricao_filtros); limite: $limite; pagina: $pagina)"
  while [[ "$coletados" -lt "$limite" ]]; do
    corpo="$(jq -nc --argjson q "$(montar_query)" --argjson s "$pagina" --argjson sa "${search_after:-null}" \
      '{size:$s, query:$q, sort:[{"@timestamp":{"order":"asc"}}], _source:true}
       + (if $sa == null then {} else {search_after:$sa} end)')"
    requisicao "$corpo"; checar_sucesso || exit 1
    n="$(printf '%s' "$RESPOSTA" | jq -r '.hits.hits | length')"
    [[ "$n" == "0" ]] && break
    printf '%s' "$RESPOSTA" | jq -c '.hits.hits[] | ._source + {_id: ._id}' >> "$fichatmp"
    ult="$(printf '%s' "$RESPOSTA" | jq -c '.hits.hits[-1].sort')"
    search_after="$ult"
    coletados=$((coletados + n))
    info "  página recebida: $n registros (total acumulado: $coletados)"
    [[ "$n" -lt "$pagina" ]] && break
    sleep "$pausa"
  done
  head -n "$limite" "$fichatmp" > "$saida"; rm -f "$fichatmp"
  if [[ -n "$destino" ]]; then info "gravado: $destino ($(wc -l < "$destino" | tr -d ' ') registros)"; fi
  info "requisições realizadas: $REQ_TOTAL (limite do CNJ: 120/min — item 3.13 do Termo de Uso)"
}

cmd_relatorio() {
  local dir="$1" topo="$2"
  exigir jq
  mkdir -p "$dir"
  local inicio; inicio="$(data_iso)"
  local filtros; filtros="$(descricao_filtros)"
  local alias_curto; alias_curto="$(normalizar_alias "$TRIBUNAL" | sed 's/api_publica_//' | tr '[:lower:]' '[:upper:]')"
  local arquivo_md="$dir/relatorio-${alias_curto}-$(date -u +%Y%m%d-%H%M).md"

  info "gerando relatório de $alias_curto em $dir (filtros: $filtros)"

  # 1) total de processos
  local corpo_total total relacao
  corpo_total="$(jq -nc --argjson q "$(montar_query)" '{query:$q, size:0, track_total_hits:true}')"
  requisicao "$corpo_total"; checar_sucesso || exit 1
  total="$(printf '%s' "$RESPOSTA" | jq -r '.hits.total.value')"
  relacao="$(printf '%s' "$RESPOSTA" | jq -r '.hits.total.relation')"

  # 2) agregações (com degradação automática de campo)
  local campos=(classe-nome assunto-nome orgao-nome grau ano formato sistema-nome)
  local titulos=("Por classe processual" "Por assunto" "Por órgão julgador" "Por grau"
                 "Por ano de ajuizamento" "Por formato (físico/eletrônico)" "Por sistema processual")
  local nomes_ok=() campos_ok=() buckets_ok=() falhas=()
  local i c nome_arq
  for i in "${!campos[@]}"; do
    c="${campos[$i]}"
    if executar_agg_com_fallback "$c" "$topo"; then
      nome_arq="$(printf '%s' "$c" | tr ' ' '_')"
      printf '# campo: %s\n' "$CAMPO_USADO" > "$dir/agg-$nome_arq.tsv"
      buckets_para_tsv | tail -n +2 >> "$dir/agg-$nome_arq.tsv"
      buckets_para_csv > "$dir/agg-$nome_arq.csv"
      nomes_ok+=("$c"); campos_ok+=("$CAMPO_USADO"); buckets_ok+=("$AGG_BUCKETS")
    else
      nomes_ok+=("$c"); campos_ok+=(""); buckets_ok+=("[]")
      falhas+=("$c")
    fi
    sleep "$PAUSA_PADRAO"
  done

  # 3) relatório em markdown
  {
    printf '# Relatório DataJud — %s\n\n' "$alias_curto"
    printf -- '- **Fonte:** API Pública do DataJud (CNJ) — https://datajud-wiki.cnj.jus.br/api-publica/\n'
    printf -- '- **Endpoint consultado:** `%s`\n' "$(url_search)"
    printf -- '- **Gerado em (UTC):** %s\n' "$inicio"
    printf -- '- **Filtros aplicados:** %s\n' "$filtros"
    printf -- '- **Requisições realizadas:** %s (limite do CNJ: 120/min)\n\n' "$REQ_TOTAL"
    printf '## Total de processos\n\n'
    if [[ "$relacao" == "gte" ]]; then
      printf '>= **%s** processos — a API limita a contagem a 10.000 quando o total é maior; refine os filtros ou leia as agregações abaixo como recorte parcial.\n\n' "$total"
    else
      printf '**%s** processos (relação `%s`).\n\n' "$total" "$relacao"
    fi
    local idx b cp
    for idx in "${!nomes_ok[@]}"; do
      b="${buckets_ok[$idx]}"; cp="${campos_ok[$idx]}"
      printf '## %s\n\n' "${titulos[$idx]}"
      if [[ "$b" == "[]" || -z "$cp" ]]; then
        printf '_Não foi possível obter esta agregação para este índice._\n\n'
      else
        printf '_campo agregado: `%s`_\n\n' "$cp"
        printf '%s' "$b" | buckets_de_json_para_md
        printf '\n'
      fi
    done
    printf '## Notas e limitações\n\n'
    printf -- '- A API Pública do DataJud expõe **apenas metadados** de processos públicos (sem dados das partes).\n'
    printf -- '- O CNJ **não garante** precisão, integridade ou atualidade dos dados (Termo de Uso, item 3.6); a atualização depende do envio do tribunal ao DataJud.\n'
    printf -- '- Uso exclusivamente **legal e não comercial** (itens 3.3 e 3.8); não coletar/cruzar dados pessoais (item 4.2, LGPD).\n'
    printf -- '- Ao divulgar este relatório publicamente, **dê ciência ao CNJ** (item 3.9 do Termo de Uso).\n'
    printf -- '- Limite de consumo: **120 requisições por minuto** (item 3.13).\n'
    [[ "${#falhas[@]}" -gt 0 ]] && printf -- '- Agregações indisponíveis nesta execução: %s.\n' "${falhas[*]}"
    printf -- '- Arquivos auxiliares desta execução: `agg-*.tsv` e `agg-*.csv` no mesmo diretório.\n'
  } > "$arquivo_md"

  printf '%s\n' "$arquivo_md"
  info "arquivos auxiliares (TSV/CSV) em: $dir"
  info "requisições realizadas: $REQ_TOTAL (limite do CNJ: 120/min — item 3.13 do Termo de Uso)"
}

buckets_de_json_para_md() {
  local json; json="$(cat)"
  printf '| valor | documentos |\n| --- | ---: |\n'
  printf '%s' "$json" | jq -r '.[] | "| \(.key_as_string // .key | tostring | gsub("\\|"; "\\\\|")) | \(.doc_count) |"'
}

# --------------------------------- ajuda -------------------------------------
mostrar_ajuda() {
  cat <<'AJUDA'
datajud.sh — consultas à API Pública do DataJud (CNJ) com curl + jq

USO
  ./scripts/datajud.sh <comando> [opções]

COMANDOS
  chave                       Mostra a chave pública vigente publicada na wiki do CNJ
  processo <numero>           Busca um processo pela numeração única (20 dígitos, sem máscara)
  contar                      Conta processos que atendem aos filtros
  agregar <campo>             Agrupa e conta por campo (ver CAMPOS abaixo)
  relatorio [--saida DIR]     Gera relatório .md (+ TSV/CSV) com total e principais agregações
  paginar [--limite N]        Percorre resultados com search_after, gravando JSONL
  ajuda                       Esta mensagem

FILTROS (valem para contar, agregar, relatorio e paginar)
  --tribunal tjpe             Alias do tribunal (padrão: tjpe). Também aceita api_publica_tjpe
  --classe 1116               Código da classe processual (TPU)
  --assunto 6017              Código do assunto (TPU)
  --orgao 12345               Código do órgão julgador (vara/câmara)
  --municipio 2611606         Código IBGE do município do órgão julgador
  --grau G1                   Grau/instância (G1, G2, JE, ...)
  --de 2024-01-01             dataAjuizamento >= (aceita AAAA-MM-DD ou ISO completo)
  --ate 2024-12-31            dataAjuizamento <=
  --sigilo 0                  nivelSigilo (0 = público)

OPÇÕES
  --top 15                    Quantos itens por agregação (padrão 15; máx. efetivo 10000)
  --json                      Saída JSON crua da API
  --movimentos                (comando processo) lista todos os movimentos
  --limite 1000               (paginar) máximo de registros a coletar
  --pagina 100                (paginar) registros por requisição (1..10000)
  --pausa 0.3                 (paginar) segundos entre requisições
  --saida DIR|ARQUIVO         Diretório do relatório / arquivo JSONL
  --debug                     Mostra o curl equivalente (útil para copiar/colar)

CAMPOS PARA 'agregar'
  classe, classe-nome, assunto, assunto-nome, orgao, orgao-nome, municipio,
  grau, sistema, sistema-nome, formato, movimento, movimento-nome, ano, mes

VARIÁVEIS DE AMBIENTE
  DATAJUD_API_KEY   Sobrescreve a chave pública (obrigatório se o CNJ trocar a chave)
  DATAJUD_BASE_URL  Padrão https://api-publica.datajud.cnj.jus.br
  DATAJUD_TRIBUNAL  Alias padrão (tjpe)
  DATAJUD_TIMEOUT   Timeout do curl em segundos (padrão 60)
  DATAJUD_TOPO      Itens por agregação (padrão 15)
  DATAJUD_DEBUG=1   Equivalente a --debug
  DATAJUD_WIKI_URL  Página da wiki usada pelo comando 'chave' (padrão: página oficial)

RECEITAS RÁPIDAS
  # total de processos do TJPE
  ./scripts/datajud.sh contar --tribunal tjpe

  # consultar um processo específico do TJPE
  ./scripts/datajud.sh processo 0001234-56.2024.8.17.2001 --tribunal tjpe

  # relatório completo (markdown + csv) em ./saida
  ./scripts/datajud.sh relatorio --tribunal tjpe --saida saida

  # executivas fiscais de 2024, por órgão julgador
  ./scripts/datajud.sh agregar orgao-nome --classe 1116 --de 2024-01-01 --ate 2024-12-31

DOCUMENTAÇÃO OFICIAL
  https://datajud-wiki.cnj.jus.br/api-publica/acesso
  https://datajud-wiki.cnj.jus.br/api-publica/endpoints
  https://datajud-wiki.cnj.jus.br/api-publica/glossario
  https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo3
AJUDA
}

# ----------------------------- interpretação ---------------------------------
COMANDO=""
ARG_COMANDO=""
F_CLASSE=""; F_ASSUNTO=""; F_ORGAO=""; F_MUNICIPIO=""; F_GRAU=""; F_SIGILO=""; F_DE=""; F_ATE=""
SAIDA_JSON=0; MOSTRAR_MOVIMENTOS=0; SAIDA=""; LIMITE=1000; PAGINA=100; PAUSA="$PAUSA_PADRAO"; TOPO="$TOPO_PADRAO"

# aceita --opcao=valor
_novos=(); for _a in "$@"; do
  case "$_a" in (--*=*) _novos+=("${_a%%=*}" "${_a#*=}") ;; (*) _novos+=("$_a") ;; esac
done
set -- "${_novos[@]:-}"

while (($#)); do
  case "$1" in
    chave|contar|agregar|relatorio|paginar|processo|ajuda|-h|--help|help)
      if [[ -z "$COMANDO" ]]; then COMANDO="$1"; else ARG_COMANDO="$1"; fi ;;
    --tribunal)   TRIBUNAL="${2:?valor faltando}"; shift ;;
    --classe)     F_CLASSE="${2:?}"; shift ;;
    --assunto)    F_ASSUNTO="${2:?}"; shift ;;
    --orgao)      F_ORGAO="${2:?}"; shift ;;
    --municipio)  F_MUNICIPIO="${2:?}"; shift ;;
    --grau)       F_GRAU="${2:?}"; shift ;;
    --sigilo)     F_SIGILO="${2:?}"; shift ;;
    --de)         F_DE="${2:?}"; shift ;;
    --ate)        F_ATE="${2:?}"; shift ;;
    --top|--tamanho) TOPO="${2:?}"; shift ;;
    --limite)     LIMITE="${2:?}"; shift ;;
    --pagina)     PAGINA="${2:?}"; shift ;;
    --pausa)      PAUSA="${2:?}"; shift ;;
    --saida)      SAIDA="${2:?}"; shift ;;
    --json)       SAIDA_JSON=1 ;;
    --movimentos) MOSTRAR_MOVIMENTOS=1 ;;
    --debug)      DEBUG=1 ;;
    "")           ;;
    *)            if [[ -z "$ARG_COMANDO" && "$COMANDO" != "" ]]; then ARG_COMANDO="$1"
                  else morrer "opção desconhecida: '$1' (veja: datajud.sh ajuda)"; fi ;;
  esac
  shift
done

[[ -n "$COMANDO" ]] || { mostrar_ajuda; exit 0; }   # sem argumentos = ajuda
adicionar_filtros

case "$COMANDO" in
  ajuda|-h|--help|help) mostrar_ajuda; exit 0 ;;
  chave)      cmd_chave ;;
  processo)   cmd_processo "$ARG_COMANDO" ;;
  contar)     cmd_contar ;;
  agregar)    cmd_agregar "$ARG_COMANDO" ;;
  relatorio)  cmd_relatorio "${SAIDA:-saida}" "$TOPO" ;;
  paginar)    cmd_paginar "$LIMITE" "$PAGINA" "$PAUSA" "$SAIDA" ;;
esac
__ARQ_EOF__
__ARQ__ tests/mock_apis.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Mock local das APIs públicas usadas pelo main.py — DataJud (CNJ) e DJEN (CNJ).

Serve de dublê para os testes automatizados: nada aqui vai à internet.

Rotas:
  POST /api_publica_<alias>/_search      → consulta processual (estilo Elasticsearch)
  GET  /api/v1/comunicacao               → publicações do DJEN
  GET  /wiki/acesso                      → página com a chave pública (para testes de 'chave')

Comportamentos simulados de propósito (para testar o tratamento de erro do main.py):
  • 401 quando o cabeçalho Authorization não for "APIKey <chave>"
  • 404 para alias de tribunal inexistente
  • 429 no alias api_publica_429
  • 400 "Fielddata is disabled" em agregação por campo texto sem .keyword
  • lista de índices que respondem vazio (para --todos)

Os processos e publicações são fictícios (mas o número de teste tem DV válido).
"""
from __future__ import annotations

import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CHAVE = os.environ.get("MOCK_API_KEY", "CHAVE-DE-TESTE")
CHAVE_WIKI = os.environ.get(
    "MOCK_CHAVE_WIKI",
    "dGVzdGUtY2hhdmUtcHVibGljYS1mYWxzYS1wYXJhLXRlc3RlLW9mZmxpbmUtZG8tZGF0YWp1ZC0xMjM0NTY3OA==",
)

# Número de teste: 0001234-43.2024.8.17.2001 (TJPE, DV válido: módulo 97 = 1)
NUMERO_TESTE = "00012344320248172001"

DOC_G1 = {
    "_index": "api_publica_tjpe",
    "_id": "TJPE_1116_G1_12345_00012344320248172001",
    "_score": 1.0,
    "_source": {
        "id": "TJPE_1116_G1_12345_00012344320248172001",
        "tribunal": "TJPE",
        "numeroProcesso": NUMERO_TESTE,
        "dataAjuizamento": "2024-03-05T00:00:00.000Z",
        "grau": "G1",
        "nivelSigilo": 0,
        "formato": {"codigo": 1, "nome": "Eletrônico"},
        "sistema": {"codigo": 1, "nome": "PJe"},
        "classe": {"codigo": 1116, "nome": "Execução Fiscal"},
        "assuntos": [
            {"codigo": 6017, "nome": "Dívida Ativa (Execução Fiscal)"},
            {"codigo": 10586, "nome": "ICMS"},
        ],
        "orgaoJulgador": {
            "codigo": 12345,
            "nome": "1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE",
            "codigoMunicipioIBGE": 2611606,
        },
        "movimentos": [
            {
                "codigo": 26,
                "nome": "Distribuição",
                "dataHora": "2024-03-05T12:00:00.000Z",
                "complementosTabelados": [
                    {"codigo": 2, "valor": 2, "nome": "sorteio",
                     "descricao": "tipo_de_distribuicao_redistribuicao"}
                ],
            },
            {"codigo": 51, "nome": "Conclusão", "dataHora": "2024-03-10T09:00:00.000Z"},
            {
                "codigo": 246,
                "nome": "Expedição de documento",
                "dataHora": "2024-04-02T15:30:00.000Z",
                "orgaoJulgador": {"codigoOrgao": 12345, "nomeOrgao": "1ª VARA DE EXECUÇÃO FISCAL DE RECIFE"},
            },
            {"codigo": 85, "nome": "Citação", "dataHora": "2024-06-20T10:00:00.000Z"},
            {"codigo": 22, "nome": "Juntada", "dataHora": "2025-01-15T11:00:00.000Z"},
            {"codigo": 246, "nome": "Expedição de documento", "dataHora": "2025-02-01T08:00:00.000Z"},
        ],
        "dataHoraUltimaAtualizacao": "2025-02-11T13:20:00.000Z",
        "@timestamp": "2025-02-12T02:00:00.000Z",
    },
}

DOC_G2 = {
    "_index": "api_publica_tjpe",
    "_id": "TJPE_1980_G2_98765_00012344320248172001",
    "_score": 1.0,
    "_source": {
        "id": "TJPE_1980_G2_98765_00012344320248172001",
        "tribunal": "TJPE",
        "numeroProcesso": NUMERO_TESTE,
        "dataAjuizamento": "2024-03-05T00:00:00.000Z",
        "grau": "G2",
        "nivelSigilo": 0,
        "formato": {"codigo": 1, "nome": "Eletrônico"},
        "sistema": {"codigo": 1, "nome": "PJe"},
        "classe": {"codigo": 1980, "nome": "Apelação Cível"},  # fictício, só para o teste
        "assuntos": [{"codigo": 6017, "nome": "Dívida Ativa (Execução Fiscal)"}],
        "orgaoJulgador": {
            "codigo": 98765,
            "nome": "2ª CÂMARA DE DIREITO PÚBLICO",
            "codigoMunicipioIBGE": 2611606,
        },
        "movimentos": [
            {"codigo": 26, "nome": "Distribuição", "dataHora": "2025-03-01T10:00:00.000Z"},
            {"codigo": 51, "nome": "Conclusão", "dataHora": "2025-03-20T10:00:00.000Z"},
        ],
        "dataHoraUltimaAtualizacao": "2025-03-21T09:00:00.000Z",
        "@timestamp": "2025-03-22T02:00:00.000Z",
    },
}

DJEN_ITENS = [
    {
        "id": 9001,
        "dataDisponibilizacao": "2024-04-03",
        "tipoComunicacao": "Intimação",
        "nomeOrgao": "1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE",
        "texto": "Fica a parte executada intimada a efetuar o pagamento do débito "
                 "no prazo de 5 (cinco) dias, nos termos do art. 9º da Lei 6.830/80.",
        "link": "https://comunica.pje.jus.br/documento/9001.pdf",
        "hash": "abc123",
        "numeroProcesso": NUMERO_TESTE,
        "siglaTribunal": "TJPE",
        "nomeClasse": "Execução Fiscal",
        "meio": "D",
    },
    {
        "id": 9002,
        "dataDisponibilizacao": "2024-06-21",
        "tipoComunicacao": "Despacho",
        "nomeOrgao": "1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE",
        "texto": "Intime-se a parte exequente para informar o andamento do feito.",
        "link": "https://comunica.pje.jus.br/documento/9002.pdf",
        "hash": "def456",
        "numeroProcesso": NUMERO_TESTE,
        "siglaTribunal": "TJPE",
        "nomeClasse": "Execução Fiscal",
        "meio": "D",
    },
]

ALIASES_VAZIOS = {"trf5", "trt6", "tre-pe", "stj", "tst", "tse", "stm", "tjdft", "tjsp", "trf1", "trt13"}
ALIASES_CONHECIDOS = {"tjpe"} | ALIASES_VAZIOS | {"429"}

LOG: list = []


def _erro(tipo: str, motivo: str, status: int) -> dict:
    return {"error": {"type": tipo, "reason": motivo, "root_cause": [{"type": tipo, "reason": motivo}]},
            "status": status}


class Handler(BaseHTTPRequestHandler):
    server_version = "MockAPIs/1.0"

    # ------------------------------------------------------------------ #
    def _responder(self, status: int, corpo) -> None:
        dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8") if not isinstance(corpo, bytes) else corpo
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def log_message(self, formato: str, *args) -> None:  # silencia o log padrão
        return

    # ------------------------------------------------------------------ #
    def do_GET(self) -> None:  # noqa: N802
        alvo = self.path.split("?")[0]
        LOG.append(f"GET {self.path}")
        if alvo == "/wiki/acesso":
            html = ("<html><body><h1>API Key</h1><p>Authorization: APIKey "
                    f"<strong>{CHAVE_WIKI}</strong></p></body></html>").encode("utf-8")
            self._responder(200, html)
            return
        if alvo == "/api/v1/comunicacao":
            if self.headers.get("Authorization") not in (None, ""):
                pass  # o DJEN real não exige autenticação; ignoramos o cabeçalho
            self._responder(200, {"status": "success", "message": "", "count": len(DJEN_ITENS),
                                  "items": DJEN_ITENS})
            return
        self._responder(404, _erro("not_found", f"rota {alvo} não existe neste mock", 404))

    def do_POST(self) -> None:  # noqa: N802
        tamanho = int(self.headers.get("Content-Length", 0))
        bruto = self.rfile.read(tamanho).decode("utf-8") if tamanho else "{}"
        try:
            corpo = json.loads(bruto)
        except json.JSONDecodeError:
            self._responder(400, _erro("parse_exception", "corpo não é JSON válido", 400))
            return

        partes = self.path.split("/")
        alias = partes[1].replace("api_publica_", "") if len(partes) > 1 else ""
        LOG.append(f"POST {self.path}")

        autorizacao = self.headers.get("Authorization", "")
        if autorizacao != f"APIKey {CHAVE}":
            self._responder(401, _erro("security_exception",
                                       "Chave de API ausente, inválida ou expirada", 401))
            return
        if not self.path.endswith("/_search") or alias not in ALIASES_CONHECIDOS:
            self._responder(404, _erro("index_not_found_exception", f"no such index [{alias}]", 404))
            return
        if alias == "429":
            self._responder(429, _erro("limit_exceeded_exception",
                                       "Too many requests: 120 requests per minute exceeded", 429))
            return

        texto_query = json.dumps(corpo.get("query", {}), ensure_ascii=False)
        PROCESSO = NUMERO_TESTE
        if PROCESSO in texto_query and alias == "tjpe" and corpo.get("size") != 0:
            self._responder(200, {"took": 4, "timed_out": False,
                                  "hits": {"total": {"value": 2, "relation": "eq"},
                                           "hits": [DOC_G1, DOC_G2]}})
            return
        if PROCESSO in texto_query and alias in ALIASES_VAZIOS and corpo.get("size") != 0:
            self._responder(200, {"took": 2, "timed_out": False,
                                  "hits": {"total": {"value": 0, "relation": "eq"}, "hits": []}})
            return
        # agregações usadas pelo scripts/datajud.sh
        if corpo.get("aggs"):
            self._responder(200, {"took": 2, "timed_out": False,
                                  "hits": {"total": {"value": 2, "relation": "eq"}, "hits": []},
                                  "aggregations": {"por_campo": {"buckets": [
                                      {"key": 1116, "doc_count": 2}]}}})
            return
        self._responder(200, {"took": 3, "timed_out": False,
                              "hits": {"total": {"value": 0, "relation": "eq"}, "hits": []}})


def criar_servidor(porta: int = 0, chave: str | None = None):
    """Sobe o mock numa thread e devolve (servidor, porta). Use servidor.shutdown()."""
    global CHAVE
    if chave:
        CHAVE = chave
    servidor = ThreadingHTTPServer(("127.0.0.1", porta), Handler)
    thread = threading.Thread(target=servidor.serve_forever, daemon=True)
    thread.start()
    return servidor, servidor.server_address[1]


def main() -> None:
    import argparse
    p = argparse.ArgumentParser(description="Mock das APIs DataJud + DJEN")
    p.add_argument("--porta", type=int, default=8899)
    p.add_argument("--chave", default=CHAVE)
    args = p.parse_args()
    servidor, porta = criar_servidor(args.porta, args.chave)
    print(f"mock ouvindo em http://127.0.0.1:{porta} (chave={CHAVE})", flush=True)
    try:
        while True:
            import time as _t
            _t.sleep(3600)
    except KeyboardInterrupt:
        servidor.shutdown()


if __name__ == "__main__":
    main()
__ARQ_EOF__
__ARQ__ tests/mock_datajud.py
#!/usr/bin/env python3
"""Mock local da API Pública do DataJud, para testar `scripts/datajud.sh` sem rede.

Simula o comportamento real do Elasticsearch por trás da API do CNJ:
  • 401 se o cabeçalho Authorization não for "APIKey <chave>"
  • 404 para alias de tribunal inexistente
  • 429 no alias `api_publica_429` (para testar a mensagem de limite de uso)
  • 400 "Fielddata is disabled" em agregação por campo texto sem .keyword
  • 400 "No field found" em agregação por campo inexistente
  • busca por numeroProcesso, contagem com track_total_hits, agregações de
    termos/date_histogram e paginação com search_after

Uso:
    python3 tests/mock_datajud.py [--porta 8899]
Variáveis: MOCK_API_KEY, MOCK_LOG (arquivo de log das requisições)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CHAVE = os.environ.get("MOCK_API_KEY", "CHAVE-DE-TESTE")
CHAVE_WIKI = os.environ.get(
    "MOCK_CHAVE_WIKI",
    "dGVzdGUtY2hhdmUtcHVibGljYS1mYWxzYS1wYXJhLXRlc3RlLW9mZmxpbmUtZG8tZGF0YWp1ZC0xMjM0NTY3OA==",
)
LOG = os.environ.get("MOCK_LOG", "")

NUMERO_FIXTURE = "00012345620248172001"

DOC_FIXTURE = {
    "_index": "api_publica_tjpe",
    "_id": "TJPE_1116_G1_12345_00012345620248172001",
    "_score": 1.0,
    "_source": {
        "id": "TJPE_1116_G1_12345_00012345620248172001",
        "tribunal": "TJPE",
        "numeroProcesso": NUMERO_FIXTURE,
        "dataAjuizamento": "2024-03-05T00:00:00.000Z",
        "grau": "G1",
        "nivelSigilo": 0,
        "formato": {"codigo": 1, "nome": "Eletrônico"},
        "sistema": {"codigo": 1, "nome": "PJe"},
        "classe": {"codigo": 1116, "nome": "Execução Fiscal"},
        "assuntos": [{"codigo": 6017, "nome": "Dívida Ativa (Execução Fiscal)"}],
        "orgaoJulgador": {
            "codigo": 12345,
            "nome": "1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE",
            "codigoMunicipioIBGE": 2611606,
        },
        "movimentos": [
            {
                "codigo": 26,
                "nome": "Distribuição",
                "dataHora": "2024-03-05T12:00:00.000Z",
                "complementosTabelados": [
                    {
                        "codigo": 2,
                        "valor": 2,
                        "nome": "sorteio",
                        "descricao": "tipo_de_distribuicao_redistribuicao",
                    }
                ],
            },
            {"codigo": 51, "nome": "Conclusão", "dataHora": "2024-04-01T09:30:00.000Z"},
            {"codigo": 246, "nome": "Expedição de documento", "dataHora": "2024-06-10T15:45:00.000Z"},
        ],
        "dataHoraUltimaAtualizacao": "2025-02-11T13:20:00.000Z",
        "@timestamp": "2025-02-12T02:00:00.000Z",
    },
}

# Documentos usados na paginação (search_after)
DOCS_PAGINA = []
for i in range(5):
    ts = 1_700_000_000_000 + i * 1000
    DOCS_PAGINA.append(
        {
            "_index": "api_publica_tjpe",
            "_id": f"TJPE_1116_G1_12345_00012345620248172{i:03d}",
            "_score": None,
            "_source": {
                "id": f"TJPE_1116_G1_12345_00012345620248172{i:03d}",
                "tribunal": "TJPE",
                "numeroProcesso": f"00012345620248172{i:03d}",
                "grau": "G1",
                "classe": {"codigo": 1116, "nome": "Execução Fiscal"},
                "orgaoJulgador": {"codigo": 12345, "nome": "1ª VARA DE EXECUÇÃO FISCAL DE RECIFE"},
                "@timestamp": f"2023-11-14T22:13:2{i}.000Z",
            },
            "sort": [ts],
        }
    )

BUCKETS = {
    "classe.codigo": [
        {"key": 1116, "doc_count": 8200},
        {"key": 436, "doc_count": 1500},
    ],
    "assuntos.codigo": [{"key": 6017, "doc_count": 6100}],
    "orgaoJulgador.codigo": [{"key": 12345, "doc_count": 1200}],
    "orgaoJulgador.nome.keyword": [
        {"key": "1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE", "doc_count": 1200},
        {"key": "2ª VARA CÍVEL DA COMARCA DO RECIFE", "doc_count": 900},
    ],
    "grau.keyword": [
        {"key": "G1", "doc_count": 9000},
        {"key": "G2", "doc_count": 3000},
    ],
    "sistema.codigo": [{"key": 1, "doc_count": 11000}],
    "sistema.nome.keyword": [{"key": "PJe", "doc_count": 11000}],
    "formato.codigo": [{"key": 1, "doc_count": 12000}],
    "movimentos.codigo": [{"key": 26, "doc_count": 11000}],
}


def erro(tipo: str, motivo: str) -> dict:
    return {"error": {"type": tipo, "reason": motivo, "root_cause": [{"type": tipo, "reason": motivo}]}, "status": 400}


def resposta_aggs(aggs: dict):
    """Devolve (status, corpo) para uma requisição com agregações."""
    nome = next(iter(aggs))            # o mock devolve o nome pedido pelo cliente
    agg = aggs[nome]
    if "date_histogram" in agg:
        formato = agg["date_histogram"].get("format", "yyyy")
        if formato == "yyyy":
            buckets = [{"key_as_string": "2024", "key": 1704067200000, "doc_count": 5000}]
        else:
            buckets = [
                {"key_as_string": "2024-01", "key": 1704067200000, "doc_count": 400},
                {"key_as_string": "2024-02", "key": 1706745600000, "doc_count": 460},
            ]
        return 200, {"took": 3, "timed_out": False,
                     "hits": {"total": {"value": 4321, "relation": "eq"}, "hits": []},
                     "aggregations": {nome: {"buckets": buckets}}}

    campo = agg["terms"]["field"]
    texto_sem_keyword = {"grau", "classe.nome", "assuntos.nome", "orgaoJulgador.nome", "sistema.nome"}
    if campo in texto_sem_keyword:
        return 400, erro(
            "illegal_argument_exception",
            f"Text fields are not optimised for operations that require per-document field data like "
            f"aggregations, sorting, and scripting. Fielddata is disabled on text fields by default. "
            f"Set fielddata=true on [{campo}] in order to load field data in memory.",
        )
    if campo == "classe.nome.keyword":
        return 400, erro("illegal_argument_exception", f"Fielddata is disabled on text fields by default: [{campo}]")
    if campo == "assuntos.nome.keyword":
        return 400, erro("search_phase_execution_exception", f"No field found for [{campo}] in mapping with types []")
    if campo in ("orgaoJulgador.nome", "orgaoJulgador.nome.keyword") and campo not in BUCKETS:
        return 400, erro("illegal_argument_exception", f"Fielddata is disabled on text fields by default: [{campo}]")
    if campo not in BUCKETS:
        return 400, erro("search_phase_execution_exception", f"No field found for [{campo}] in mapping with types []")
    return 200, {"took": 2, "timed_out": False,
                 "hits": {"total": {"value": 4321, "relation": "eq"}, "hits": []},
                 "aggregations": {nome: {"buckets": BUCKETS[campo]}}}


def resposta_busca(corpo: dict):
    query = corpo.get("query", {})
    # busca por número de processo
    texto = json.dumps(query)
    if "numeroProcesso" in texto:
        valor = query.get("match", {}).get("numeroProcesso") or query.get("bool", {}).get("must", [{}])[0].get("match", {}).get("numeroProcesso")
        hits = [DOC_FIXTURE] if valor == NUMERO_FIXTURE else []
        return 200, {"took": 5, "timed_out": False,
                     "hits": {"total": {"value": len(hits), "relation": "eq"}, "hits": hits}}
    # agregações
    if corpo.get("aggs"):
        return resposta_aggs(corpo["aggs"])
    # contagem
    if corpo.get("size") == 0:
        sem_filtro = not query or query.get("match_all") is not None
        total = {"value": 10000, "relation": "gte"} if sem_filtro else {"value": 4321, "relation": "eq"}
        return 200, {"took": 1, "timed_out": False, "hits": {"total": total, "hits": []}}
    # paginação com search_after
    size = int(corpo.get("size", 10))
    buscados = corpo.get("search_after")
    inicio = 0
    if buscados:
        for idx, d in enumerate(DOCS_PAGINA):
            if d["sort"] == buscados:
                inicio = idx + 1
                break
    pagina = DOCS_PAGINA[inicio:inicio + size]
    return 200, {"took": 2, "timed_out": False,
                 "hits": {"total": {"value": len(DOCS_PAGINA), "relation": "eq"}, "hits": pagina}}


class Handler(BaseHTTPRequestHandler):
    server_version = "MockDataJud/1.0"

    def _log(self, msg: str) -> None:
        if LOG:
            with open(LOG, "a", encoding="utf-8") as fh:
                fh.write(msg + "\n")

    def _responder(self, status: int, corpo: dict) -> None:
        dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_POST(self) -> None:  # noqa: N802
        tamanho = int(self.headers.get("Content-Length", 0))
        bruto = self.rfile.read(tamanho).decode("utf-8") if tamanho else "{}"
        try:
            corpo = json.loads(bruto)
        except json.JSONDecodeError:
            self._responder(400, erro("parse_exception", "corpo da requisição não é JSON válido"))
            return

        autorizacao = self.headers.get("Authorization", "")
        partes = self.path.split("/")
        alias = partes[1] if len(partes) > 1 else ""
        caminho_ok = self.path.endswith("/_search")

        self._log(f"POST {self.path} auth={autorizacao} size={corpo.get('size')} "
                  f"search_after={'search_after' in corpo} aggs={'aggs' in corpo}")

        if autorizacao != f"APIKey {CHAVE}":
            self._responder(401, erro("security_exception", "Chave de API ausente, inválida ou expirada"))
            return
        if not caminho_ok or alias not in ("api_publica_tjpe", "api_publica_429"):
            self._responder(404, erro("index_not_found_exception", f"no such index [{alias}]"))
            return
        if alias == "api_publica_429":
            self._responder(429, erro("limit_exceeded_exception", "Too many requests: 120 requests per minute exceeded"))
            return

        status, resposta = resposta_busca(corpo)
        self._responder(status, resposta)

    def do_GET(self) -> None:  # noqa: N802
        """Simula a página de acesso da wiki (usada por `datajud.sh chave`)."""
        if self.path.startswith("/wiki"):
            html = (
                "<html><body><h1>API Key</h1>"
                "<p>Para incorporar a API Key: Authorization: APIKey "
                f"<strong>{CHAVE_WIKI}</strong></p></body></html>"
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
            self._log(f"GET {self.path}")
            return
        self._log(f"GET {self.path} (404)")
        self.send_error(404, "not found")

    def log_message(self, formato: str, *args) -> None:  # silencia o log padrão
        return


def main() -> int:
    p = argparse.ArgumentParser(description="Mock da API Pública do DataJud")
    p.add_argument("--porta", type=int, default=8899)
    args = p.parse_args()
    servidor = ThreadingHTTPServer(("127.0.0.1", args.porta), Handler)
    print(f"mock DataJud ouvindo em http://127.0.0.1:{args.porta} (chave={CHAVE})", flush=True)
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
__ARQ_EOF__
__ARQ__ tests/rodar-testes.sh
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
__ARQ_EOF__
__ARQ__ tests/testar_bootstrap.sh
#!/usr/bin/env bash
# ==============================================================================
#  testar_bootstrap.sh — prova que o bootstrap.sh recria este projeto idêntico
# ==============================================================================
#  Etapas:
#    1. o bootstrap.sh está atualizado? (tools/gerar_bootstrap.py --conferir)
#    2. bash bootstrap.sh cria o projeto num diretório temporário
#    3. a árvore criada é comparada com o repositório (diff -r, exceto .git)
#    4. as permissões conferem (755 em scripts/testes, 644 em docs/dados)
#    5. as 4 suítes de teste rodam DENTRO do projeto recriado
#    6. `bootstrap.sh --verificar` reconhece o projeto como íntegro
#
#  Uso: ./tests/testar_bootstrap.sh
# ==============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

TMP="$(mktemp -d)"
limpar() { rm -rf "$TMP"; }
trap limpar EXIT

PASSOU=0; FALHOU=0
ok()   { printf '  \033[1;32m✔\033[0m %s\n' "$1"; PASSOU=$((PASSOU+1)); }
ruim() { printf '  \033[1;31m✘\033[0m %s\n' "$1"; FALHOU=$((FALHOU+1)); }
titulo(){ printf '\n\033[1;34m%s\033[0m\n' "$1"; }

printf 'Testes do bootstrap.sh (destino temporário: %s)\n' "$TMP/projeto"

titulo '1. O bootstrap está atualizado?'
if python3 tools/gerar_bootstrap.py --conferir >/dev/null 2>&1; then
  ok 'bootstrap.sh confere com tools/gerar_bootstrap.py'
else
  ruim 'bootstrap.sh desatualizado — rode: python3 tools/gerar_bootstrap.py'
fi
if bash -n bootstrap.sh 2>/dev/null; then ok 'bootstrap.sh sem erro de sintaxe'; else ruim 'sintaxe do bootstrap.sh'; fi
if [[ -x bootstrap.sh ]]; then ok 'bootstrap.sh tem permissão de execução'; else ruim 'bootstrap.sh não é executável'; fi

titulo '2. Criação do projeto a partir do zero'
if bash bootstrap.sh --destino "$TMP/projeto" --sem-testes >"$TMP/criacao.log" 2>&1; then
  ok 'bootstrap concluiu a criação (código 0)'
else
  ruim 'bootstrap falhou na criação'
  sed 's/^/      /' "$TMP/criacao.log" | tail -20
fi
for etapa in '1/7' '2/7' '3/7' '4/7' '5/7' '6/7'; do
  if grep -q "$etapa" "$TMP/criacao.log"; then ok "etapa $etapa executada"; else ruim "etapa $etapa ausente"; fi
done

titulo '3. Árvore criada x repositório (byte a byte)'
if diff -r -q \
      --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
      --exclude='saida' --exclude='*.jsonl' \
      "$RAIZ" "$TMP/projeto" >"$TMP/diff.log" 2>&1; then
  ok 'todos os arquivos idênticos ao repositório'
else
  ruim 'há diferenças entre o projeto criado e o repositório:'
  sed 's/^/      /' "$TMP/diff.log" | head -20
fi
# diretórios gerados em tempo de execução (saida/, __pycache__) não entram na contagem
qtd_repo=$(find "$RAIZ" -type f -not -path '*/.git/*' -not -path '*__pycache__*' \
             -not -path '*/saida/*' | wc -l | tr -d ' ')
qtd_novo=$(find "$TMP/projeto" -type f -not -path '*/.git/*' -not -path '*__pycache__*' \
             -not -path '*/saida/*' | wc -l | tr -d ' ')
if [[ "$qtd_repo" == "$qtd_novo" ]]; then
  ok "mesma quantidade de arquivos ($qtd_novo)"
else
  ruim "quantidade diferente: repositório=$qtd_repo, criado=$qtd_novo"
fi
python3 tools/gerar_bootstrap.py --conferir >/dev/null 2>&1 && ok 'bootstrap presente no projeto criado'

titulo '4. Permissões'
modo_de() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
permissao_ok=1
for arq in main.py scripts/datajud.sh bootstrap.sh tests/rodar-testes.sh tests/testar_bootstrap.sh; do
  [[ "$(modo_de "$TMP/projeto/$arq")" == "755" ]] || { ruim "$arq deveria ser 755 (é $(modo_de "$TMP/projeto/$arq"))"; permissao_ok=0; }
done
for arq in README.md BOOTSTRAP.md docs/01-api-datajud.md docs/exemplo-saida/relatorio-processo-exemplo.md; do
  [[ "$(modo_de "$TMP/projeto/$arq")" == "644" ]] || { ruim "$arq deveria ser 644 (é $(modo_de "$TMP/projeto/$arq"))"; permissao_ok=0; }
done
[[ "$permissao_ok" == "1" ]] && ok 'permissões 755 (executáveis) e 644 (docs/dados) corretas'
[[ "$(modo_de "$TMP/projeto/docs")" == "755" ]] && ok 'diretórios em 755' || ruim 'diretório com modo errado'

titulo '5. Testes rodando DENTRO do projeto recriado'
if ( cd "$TMP/projeto" && python3 tests/testar_conformidade.py >/dev/null 2>&1 ); then
  ok 'suíte de conformidade passa no projeto recriado'
else
  ruim 'suíte de conformidade falhou no projeto recriado'
fi
if ( cd "$TMP/projeto" && python3 tests/testar_main.py >/dev/null 2>&1 ); then
  ok 'suíte do main.py passa no projeto recriado'
else
  ruim 'suíte do main.py falhou no projeto recriado'
fi
if ( cd "$TMP/projeto" && bash tests/rodar-testes.sh >/dev/null 2>&1 ); then
  ok 'suíte do datajud.sh passa no projeto recriado'
else
  ruim 'suíte do datajud.sh falhou no projeto recriado'
fi
if ( cd "$TMP/projeto" && python3 tests/testar_pipeline.py >/dev/null 2>&1 ); then
  ok 'suíte do pipeline de gates passa no projeto recriado'
else
  ruim 'suíte do pipeline falhou no projeto recriado'
fi
if ( cd "$TMP/projeto" && python3 pipeline/gate.py blueprint >/dev/null 2>&1 ); then
  ok 'gate blueprint roda no projeto recriado (planta consistente)'
else
  ruim 'gate blueprint falhou no projeto recriado'
fi
if ( cd "$TMP/projeto" && python3 pipeline/gate.py continuidade --status-issues 0 \
       --status-cicd 0 --status-testes 0 --saida-dir "$TMP/projeto/pipeline/saida" >/dev/null 2>&1 ); then
  ok 'gate continuidade devolve 0 quando os três checks estão limpos'
else
  ruim 'gate continuidade não reconheceu o estado limpo'
fi

titulo '6. Verificação de integridade (--verificar)'
if bash "$TMP/projeto/bootstrap.sh" --destino "$TMP/projeto" --verificar >"$TMP/verif.log" 2>&1; then
  ok '--verificar reconhece o projeto como íntegro'
else
  ruim '--verificar apontou problema:'
  sed 's/^/      /' "$TMP/verif.log" | tail -15
fi
grep -q 'todos os hashes conferem' "$TMP/verif.log" && ok 'manifesto SHA-256 conferiu' \
  || ruim 'o manifesto SHA-256 não foi validado'

titulo '7. Proteção contra sobrescrita'
mkdir -p "$TMP/ocupado"; echo "arquivo" > "$TMP/ocupado/existente.txt"
if bash bootstrap.sh --destino "$TMP/ocupado" --sem-testes >/dev/null 2>&1; then
  ruim 'deveria recusar destino não vazio sem --forcar'
else
  ok 'recusa destino não vazio sem --forcar'
fi
if bash bootstrap.sh --destino "$TMP/ocupado" --sem-testes --forcar >/dev/null 2>&1; then
  ok '--forcar sobrescreve como esperado'
else
  ruim '--forcar não funcionou'
fi

printf '\n\033[1;34mResultado\033[0m: %s passaram, %s falharam\n' "$PASSOU" "$FALHOU"
[[ "$FALHOU" == "0" ]] || exit 1
__ARQ_EOF__
__ARQ__ tests/testar_conformidade.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Conformidade do código com a documentação oficial do CNJ.

Cada teste aqui corresponde a um item publicado em
  • https://datajud-wiki.cnj.jus.br/api-publica/acesso      (chave e cabeçalho)
  • https://datajud-wiki.cnj.jus.br/api-publica/endpoints  (rotas e aliases)
  • https://datajud-wiki.cnj.jus.br/api-publica/glossario  (campos)
  • https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo3 (search_after)
  • Termos de uso v1.2 (itens 3.6, 3.8, 3.9, 3.13, 4.2)

Não acessa a internet: inspeciona os fontes e usa os mocks locais.

Uso:  python3 tests/testar_conformidade.py
"""
from __future__ import annotations

import ast
import os
import re
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tests"))

MAIN = open(os.path.join(RAIZ, "main.py"), encoding="utf-8").read()
SH = open(os.path.join(RAIZ, "scripts", "datajud.sh"), encoding="utf-8").read()
DOC_API = open(os.path.join(RAIZ, "docs", "01-api-datajud.md"), encoding="utf-8").read()

import main  # noqa: E402


class TesteAcesso(unittest.TestCase):
    """Página 'Acesso': URL base, rota e cabeçalhos."""

    def test_url_base_oficial(self):
        self.assertEqual(main.DATAJUD_BASE, "https://api-publica.datajud.cnj.jus.br")
        self.assertIn("https://api-publica.datajud.cnj.jus.br", SH)

    def test_rota_search_com_alias(self):
        self.assertIn('/api_publica_{alias}/_search', MAIN)
        self.assertRegex(SH, r"api_publica_%s/_search|/api_publica_")

    def test_cabecalho_authorization_apikey(self):
        # formato exigido: "Authorization: APIKey <chave>"
        self.assertIn('f"APIKey {CHAVE}"', MAIN)
        self.assertRegex(SH, r'Authorization: APIKey \$API_KEY')

    def test_cabecalho_content_type_json(self):
        self.assertIn('cabecalhos["Content-Type"] = "application/json"', MAIN)
        self.assertIn("Content-Type: application/json", SH)

    def test_metodo_post(self):
        self.assertIn('method="POST" if dados else "GET"', MAIN)  # POST quando há corpo
        self.assertIn("curl -sS", SH)

    def test_chave_publica_vigente_embutida(self):
        # a chave da wiki é um base64 longo; guardamos a vigente como default
        self.assertGreaterEqual(len(main.CHAVE_PUBLICA_PADRAO), 40)
        self.assertTrue(re.fullmatch(r"[A-Za-z0-9+/=]{40,}", main.CHAVE_PUBLICA_PADRAO))
        self.assertTrue(main.CHAVE_PUBLICA_PADRAO.endswith("=="))
        self.assertIn(main.CHAVE_PUBLICA_PADRAO, SH)

    def test_comando_para_reler_a_chave_na_wiki(self):
        # a wiki avisa que a chave pode mudar: precisa existir um caminho para relê-la
        self.assertIn("datajud-wiki.cnj.jus.br/api-publica/acesso", main.WIKI_URL)
        self.assertIn("--chave-publica", MAIN)
        self.assertIn("cmd_chave", SH)


class TesteEndpoints(unittest.TestCase):
    """Página 'Endpoints': aliases por tribunal."""

    CASOS = {
        "00008323520184013202": ("TRF1", "trf1"),        # exemplo oficial (wiki)
        "07223914020178070001": ("TJDFT", "tjdft"),      # exemplo oficial (wiki)
        "00012344320248172001": ("TJPE", "tjpe"),        # 8.17
        "00017115620175130002": ("TRT13", "trt13"),      # 5.13
        "00000000020246170000": ("TRE-PE", "tre-pe"),    # 6.17 (Eleitoral de PE)
    }

    def test_alias_por_tribunal(self):
        for numero, (sigla, alias) in self.CASOS.items():
            d = main.decodificar(numero)
            self.assertEqual((d["tribunal_sigla"], d["datajud_alias"]), (sigla, alias), numero)

    def test_aliases_presentes_na_documentacao(self):
        """Todo alias suportado pelo código precisa estar citado na documentação."""
        corpus = "\n".join([
            DOC_API,
            open(os.path.join(RAIZ, "docs", "02-receitas-curl-tjpe.md"), encoding="utf-8").read(),
            open(os.path.join(RAIZ, "README.md"), encoding="utf-8").read(),
            MAIN,
        ])
        for alias in ("tjpe", "trf5", "trt6", "tre-pe", "tjdft", "stj", "tst", "tse", "stm"):
            self.assertIn(alias, corpus, f"alias '{alias}' não aparece em nenhum doc do projeto")

    def test_alias_tjdft_e_dft_sao_os_especiais_da_doc(self):
        # 8.07 -> api_publica_tjdft e 6.07 -> api_publica_tre-dft (fogem do padrão TJ+UF)
        self.assertIn("tjdft", MAIN)
        self.assertIn("tre-dft", MAIN)


class TesteGlossario(unittest.TestCase):
    """Página 'Glossário de Dados': campos consumidos e documentados."""

    CAMPOS = ["numeroProcesso", "tribunal", "dataAjuizamento", "grau", "nivelSigilo",
              "formato", "sistema", "classe", "assuntos", "orgaoJulgador", "movimentos",
              "complementosTabelados", "dataHoraUltimaAtualizacao", "@timestamp",
              "codigoMunicipioIBGE"]

    def test_main_le_todos_os_campos_do_glossario(self):
        for campo in self.CAMPOS:
            self.assertIn(campo, MAIN, f"campo {campo} não é lido pelo main.py")

    def test_documentacao_lista_o_glossario(self):
        for campo in self.CAMPOS:
            self.assertIn(campo, DOC_API, f"campo {campo} ausente de docs/01-api-datajud.md")

    def test_id_no_padrao_tribunal_classe_grau_orgao_numero(self):
        # id = Tribunal_Classe_Grau_OrgaoJulgador_NumeroProcesso (glossário)
        componente = re.search(r"Chave `?Tribunal_Classe_Grau_OrgaoJulgador_NumeroProcesso", DOC_API)
        self.assertIsNotNone(componente, "o glossário do projeto deve citar a composição do id")


class TesteConsultas(unittest.TestCase):
    """Exemplos 1 a 3 e boas práticas de consulta."""

    def test_busca_por_numero_usa_match(self):
        self.assertIn('{"match": {"numeroProcesso": numero20}}', MAIN)

    def test_filtros_por_classe_e_orgao(self):
        self.assertRegex(SH, r'classe\.codigo')
        self.assertRegex(SH, r'orgaoJulgador\.codigo')

    def test_paginacao_com_search_after_e_sort_timestamp(self):
        # Exemplo 3: ordenar por @timestamp e usar o vetor sort como search_after
        self.assertIn('sort:[{"@timestamp":{"order":"asc"}}]', SH)
        self.assertIn("search_after", SH)

    def test_tamanho_de_pagina_dentro_do_limite(self):
        # a API aceita de 1 a 10.000 documentos por página
        self.assertIn('[ "$pagina" -ge 1 && "$pagina" -le 10000 ]', SH)

    def test_contagem_trata_teto_de_10000(self):
        self.assertIn("track_total_hits", SH)
        self.assertIn('"gte"', SH)

    def test_agregacoes_terms_e_historico_de_datas(self):
        self.assertIn("terms", SH)
        self.assertIn("date_histogram", SH)
        self.assertIn("calendar_interval", SH)

    def test_fallback_para_campo_keyword(self):
        # a doc avisa: campo texto não é agregável; usar .keyword
        self.assertIn(".keyword", SH)
        self.assertIn("fielddata", SH.lower())


class TesteTermoDeUso(unittest.TestCase):
    """Termo de Uso v1.2 — itens que o código precisa respeitar."""

    def test_limite_de_120_requisicoes_por_minuto_citado(self):
        self.assertIn("120", MAIN)
        self.assertIn("3.13", MAIN + SH)

    def test_pausa_entre_requisicoes_para_nao_estourar_o_limite(self):
        self.assertRegex(SH, r"DATAJUD_PAUSA|pausa|sleep")
        self.assertIn("time.sleep(", MAIN)

    def test_uso_nao_comercial_e_ciencia_ao_cnj_no_relatorio(self):
        relatorio = os.path.join(RAIZ, "docs", "exemplo-saida", "relatorio-processo-exemplo.md")
        texto = ""
        if os.path.exists(relatorio):
            with open(relatorio, encoding="utf-8") as fh:
                texto = fh.read()
        self.assertIn("não comercial", MAIN)
        self.assertIn("dê ciência ao CNJ", MAIN)
        if texto:
            self.assertIn("não comercial", texto)

    def test_lgpd_mencionada(self):
        self.assertIn("LGPD", MAIN)
        self.assertIn("LGPD", DOC_API)

    def test_sem_dados_pessoais_coletados(self):
        # o projeto não deve ter campos de partes/CPF/CNPJ em nenhuma estrutura de dados
        proibidos = ["cpf", "nomeParte", "documentoParte", "cnpj"]
        for termo in proibidos:
            ocorrencias = re.findall(rf'["\']{termo}', MAIN + SH, re.I)
            self.assertEqual(ocorrencias, [], f"campo pessoal '{termo}' parece ser coletado")

    def test_avisos_de_limitacao_presentes_no_relatorio(self):
        # item 3.6: o CNJ não garante precisão/atualidade — precisa estar dito no relatório
        self.assertIn("não garante", MAIN)


class TesteIntegridadeDosFontes(unittest.TestCase):
    """Sanidade estrutural: o projeto precisa compilar e não ter dependências externas."""

    def test_main_sem_dependencias_externas(self):
        arvore = ast.parse(MAIN)
        modulos = set()
        for no in ast.walk(arvore):
            if isinstance(no, ast.Import):
                modulos |= {a.name.split(".")[0] for a in no.names}
            elif isinstance(no, ast.ImportFrom) and no.module:
                modulos.add(no.module.split(".")[0])
        externos = modulos - set(sys.stdlib_module_names)
        self.assertEqual(externos, set(), f"main.py importa módulos não-stdlib: {externos}")

    def test_shebang_e_permissao_de_execucao(self):
        for relativo in ("main.py", "scripts/datajud.sh", "tests/rodar-testes.sh",
                         "tests/mock_apis.py", "tests/mock_datajud.py", "tests/testar_main.py",
                         "tests/testar_conformidade.py"):
            caminho = os.path.join(RAIZ, relativo)
            self.assertTrue(open(caminho, encoding="utf-8").readline().startswith("#!"),
                            f"{relativo} sem shebang")
            self.assertTrue(os.access(caminho, os.X_OK), f"{relativo} sem permissão de execução")

    def test_bash_script_sem_erro_de_sintaxe(self):
        import subprocess
        r = subprocess.run(["bash", "-n", os.path.join(RAIZ, "scripts", "datajud.sh")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
__ARQ_EOF__
__ARQ__ tests/testar_main.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Testes do main.py (consulta de processo → relatório em Markdown).

Roda 100% offline: sobe o mock de tests/mock_apis.py numa porta livre e aponta o
main.py para ele pelas variáveis de ambiente, como se fosse o CNJ.

Uso:  python3 tests/testar_main.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tests"))

import main  # noqa: E402  (import após ajustar o sys.path)
import mock_apis  # noqa: E402

CHAVE_TESTE = "CHAVE-DE-TESTE"
NUMERO = mock_apis.NUMERO_TESTE                # 00012344320248172001 (DV válido)
NUMERO_FMT = "0001234-43.2024.8.17.2001"
SERVIDOR, PORTA = mock_apis.criar_servidor(0, CHAVE_TESTE)

AMBIENTE = dict(
    os.environ,
    DATAJUD_BASE_URL=f"http://127.0.0.1:{PORTA}",
    DJEN_BASE_URL=f"http://127.0.0.1:{PORTA}/api/v1",
    DATAJUD_API_KEY=CHAVE_TESTE,
    PYTHONIOENCODING="utf-8",
)


def rodar(*argumentos: str, ambiente=None):
    """Roda o main.py como subprocesso e devolve (código, stdout, stderr)."""
    proc = subprocess.run([sys.executable, os.path.join(RAIZ, "main.py"), *argumentos],
                          capture_output=True, text=True, env=ambiente or AMBIENTE, cwd=RAIZ)
    return proc.returncode, proc.stdout, proc.stderr


class TesteNumeroCNJ(unittest.TestCase):
    """Resolução CNJ 65/2008 — estrutura e dígito verificador (módulo 97 base 10)."""

    NUMEROS_OFICIAIS = [
        "00008323520184013202",   # exemplo da wiki do DataJud (TRF1)
        "07223914020178070001",   # exemplo da wiki do DataJud (TJDFT)
        "00073039720138070015",   # exemplo da wiki do DataJud (TJDFT)
        "00017115620175130002",   # exemplo público da ABJ (0001711-56.2017.5.13.0002)
    ]

    def test_dv_de_numeros_reais_confere(self):
        for numero in self.NUMEROS_OFICIAIS:
            self.assertTrue(main.dv_valido(numero), f"DV deveria conferir em {numero}")

    def test_calculo_dv_bate_com_o_numero(self):
        for numero in self.NUMEROS_OFICIAIS:
            self.assertEqual(main.calcular_dv(numero), numero[7:9],
                             f"DV calculado difere do informado em {numero}")

    def test_dv_detecta_erro_de_digitacao(self):
        self.assertFalse(main.dv_valido("00008323520184013203"))

    def test_formatacao_e_limpeza(self):
        self.assertEqual(main.somente_digitos("0001234-43.2024.8.17.2001"), NUMERO)
        self.assertEqual(main.formatar_numero(NUMERO), NUMERO_FMT)

    def test_decodificacao_de_tribunais(self):
        casos = {
            NUMERO: ("TJPE", "tjpe"),                         # 8.17
            "00008323520184013202": ("TRF1", "trf1"),          # 4.01
            "00017115620175130002": ("TRT13", "trt13"),        # 5.13
            "07223914020178070001": ("TJDFT", "tjdft"),        # 8.07 (alias especial)
            "00000000020246170000": ("TRE-PE", "tre-pe"),      # 6.17 (Eleitoral de PE)
        }
        for numero, (sigla, alias) in casos.items():
            d = main.decodificar(numero)
            self.assertEqual(d["tribunal_sigla"], sigla, f"sigla de {numero}")
            self.assertEqual(d["datajud_alias"], alias, f"alias de {numero}")


class TesteRelatorio(unittest.TestCase):
    """Relatório em Markdown gerado a partir do mock."""

    @classmethod
    def setUpClass(cls):
        cls.codigo, cls.saida, cls.erro = rodar(NUMERO_FMT)

    def test_roda_com_sucesso(self):
        self.assertEqual(self.codigo, 0, self.erro)

    def test_cabecalho_e_numero_formatado(self):
        self.assertIn(f"# Processo {NUMERO_FMT}", self.saida)

    def test_secoes_principais(self):
        for secao in ("## 1. Resumo executivo", "## 2. Identificação e validação do número",
                      "## 3. Capa do processo", "## 4. Movimentações processuais",
                      "## 5. Panorama estatístico", "## 7. Anexos e documentos",
                      "## 8. Links oficiais de consulta", "## 10. Notas, limitações e conformidade"):
            self.assertIn(secao, self.saida)

    def test_validacao_do_numero_aparece(self):
        self.assertIn("válido ✔", self.saida)
        self.assertIn("módulo 97 base 10", self.saida)

    def test_capa_traz_classe_assunto_e_orgao(self):
        self.assertIn("1116 — Execução Fiscal", self.saida)
        self.assertIn("6017 — Dívida Ativa (Execução Fiscal)", self.saida)
        self.assertIn("1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE", self.saida)
        self.assertIn("2611606 — PE", self.saida)      # município IBGE + UF

    def test_dois_graus_sao_renderizados(self):
        self.assertIn("3.1 Documento 1 — grau G1", self.saida)
        self.assertIn("3.2 Documento 2 — grau G2", self.saida)
        self.assertIn("2ª CÂMARA DE DIREITO PÚBLICO", self.saida)

    def test_movimentos_e_complementos(self):
        self.assertIn("Distribuição", self.saida)
        self.assertIn("tipo_de_distribuicao_redistribuicao", self.saida)
        self.assertIn("sorteio", self.saida)
        self.assertIn("05/03/2024 12:00", self.saida)   # data formatada em pt-BR

    def test_estatisticas(self):
        self.assertIn("5.1 Movimentações por ano", self.saida)
        self.assertIn("5.2 Movimentos mais frequentes", self.saida)
        self.assertIn("5.4 Tempo e inércia", self.saida)
        self.assertIn("█", self.saida)                   # barra do gráfico

    def test_secao_de_anexos_explica_a_limitacao(self):
        self.assertIn("apenas metadados", self.saida.replace("*", ""))
        self.assertIn("Autos completos, petições, decisões e anexos", self.saida)

    def test_links_oficiais_do_tjpe(self):
        for link in ("pje.cloud.tjpe.jus.br/1g/ConsultaPublica/listView.seam",
                     "pje.cloud.tjpe.jus.br/2g/ConsultaPublica/listView.seam",
                     "srv01.tjpe.jus.br/consultaprocessualunificada",
                     "comunica.pje.jus.br/consulta?numeroProcesso=" + NUMERO):
            self.assertIn(link, self.saida)

    def test_notas_legais(self):
        self.assertIn("120 requisições por minuto", self.saida)
        self.assertIn("não comercial", self.saida)
        self.assertIn("LGPD", self.saida)


class TesteDJEN(unittest.TestCase):
    """Publicações e intimações (DJEN/Comunica)."""

    def test_publicacoes_aparecem_no_relatorio(self):
        codigo, saida, erro = rodar(NUMERO_FMT)
        self.assertEqual(codigo, 0, erro)
        self.assertIn("## 6. Publicações e intimações (DJEN)", saida)
        self.assertIn("Intimação", saida)
        self.assertIn("https://comunica.pje.jus.br/documento/9001.pdf", saida)
        self.assertIn("art. 9º da Lei 6.830/80", saida)

    def test_sem_djen_nao_consulta_nem_exibe_itens(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--sem-djen")
        self.assertEqual(codigo, 0, erro)
        self.assertIn("_Não consultado", saida)
        self.assertNotIn("Lei 6.830/80", saida)

    def test_falha_do_djen_nao_derruba_o_relatorio(self):
        ambiente = dict(AMBIENTE, DJEN_BASE_URL="http://127.0.0.1:1/api/v1")
        codigo, saida, erro = rodar(NUMERO_FMT, ambiente=ambiente)
        self.assertEqual(codigo, 0, "o relatório deve sair mesmo sem DJEN")
        self.assertIn("## 1. Resumo executivo", saida)
        self.assertIn("não consultado", saida.lower() + erro.lower())


class TesteSaidasEArtigos(unittest.TestCase):
    """--json, -o e verificações de robustez."""

    def test_json_traz_documentos_e_djen(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--json")
        self.assertEqual(codigo, 0, erro)
        pacote = json.loads(saida)
        self.assertEqual(pacote["numero"], NUMERO_FMT)
        self.assertEqual(pacote["tribunal"]["datajud_alias"], "tjpe")
        self.assertEqual(len(pacote["documentos"]), 2)
        self.assertEqual(len(pacote["djen"]), 2)

    def test_gravacao_em_arquivo(self):
        with tempfile.TemporaryDirectory() as pasta:
            destino = os.path.join(pasta, "processo.md")
            codigo, saida, erro = rodar(NUMERO_FMT, "-o", destino)
            self.assertEqual(codigo, 0, erro)
            with open(destino, encoding="utf-8") as fh:
                conteudo = fh.read()
            self.assertIn("# Processo", conteudo)
            self.assertIn("## 4. Movimentações processuais", conteudo)

    def test_numero_invalido_falha_com_orientacao(self):
        codigo, saida, erro = rodar("12345")
        self.assertEqual(codigo, 2)
        self.assertIn("20", erro)

    def test_processo_inexistente_orienta_uso_do_todos(self):
        # número com DV válido, mas que não existe no mock (0009999-xx)
        outro = "0009999" + main.calcular_dv("000999920248172001") + "20248172001"
        codigo, saida, erro = rodar(main.formatar_numero(outro))
        self.assertEqual(codigo, 2)
        self.assertIn("--todos", erro)

    def test_chave_errada_explica_o_problema(self):
        ambiente = dict(AMBIENTE, DATAJUD_API_KEY="chave-errada")
        codigo, saida, erro = rodar(NUMERO_FMT, ambiente=ambiente)
        self.assertEqual(codigo, 2)
        self.assertIn("chave", erro.lower())

    def test_alias_de_tribunal_inexistente(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--buscar-em", "tribunal-que-nao-existe")
        self.assertEqual(codigo, 2)
        self.assertIn("404", erro + saida)

    def test_flag_todos_varre_outros_indices(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--todos")
        self.assertEqual(codigo, 0, erro)
        self.assertIn("api_publica_trf5", erro)   # o log lista todos os índices varridos
        self.assertIn("nenhum documento", erro)
        self.assertIn("# Processo", saida)

    def test_dv_invalido_avisa_mas_continua(self):
        numero_errado = NUMERO[:7] + ("99" if NUMERO[7:9] != "99" else "88") + NUMERO[9:]
        codigo, saida, erro = rodar(main.formatar_numero(numero_errado))
        self.assertIn("não confere", erro)

    def test_chave_publica_lida_da_wiki(self):
        ambiente = dict(AMBIENTE, DATAJUD_WIKI_URL=f"http://127.0.0.1:{PORTA}/wiki/acesso")
        codigo, saida, erro = rodar("--chave-publica", ambiente=ambiente)
        self.assertEqual(codigo, 0, erro)
        self.assertEqual(saida.strip(), mock_apis.CHAVE_WIKI)

    def test_help_e_versao(self):
        codigo, saida, _ = rodar("--help")
        self.assertEqual(codigo, 0)
        self.assertIn("DataJud", saida)
        codigo, saida, _ = rodar("--versao")
        self.assertEqual(codigo, 0)
        self.assertIn(main.VERSAO, saida)


if __name__ == "__main__":
    print(f"mock das APIs em 127.0.0.1:{PORTA} | processo de teste {NUMERO_FMT}\n")
    try:
        unittest.main(verbosity=2)
    finally:
        SERVIDOR.shutdown()
__ARQ_EOF__
__ARQ__ tests/testar_pipeline.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Testes do pipeline de gates (pipeline/gate.py, blueprint, backlog e workflow).

Roda 100% offline: as consultas ao `gh` são substituídas por fixtures
(`--issues-json`/`--runs-json`) e as instruções de teste usam comandos triviais.

Uso:  python3 tests/testar_pipeline.py
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "pipeline"))

import gate  # noqa: E402  (módulo do pipeline)

GATE = os.path.join(RAIZ, "pipeline", "gate.py")
BACKLOG = os.path.join(RAIZ, "pipeline", "backlog.json")
BLUEPRINT = os.path.join(RAIZ, "pipeline", "blueprint.json")
WORKFLOW = os.path.join(RAIZ, ".github", "workflows", "gates.yml")

CHAVES_OBRIGATORIAS = {"id", "gate", "status", "mensagem", "next_issue", "anexos",
                       "continuidade", "codigo_saida", "dados", "timestamp", "versao"}


def rodar(*argumentos, saida_dir=None):
    """Executa o gate.py e devolve (código_de_saída, objeto_json, stdout_bruto)."""
    cmd = [sys.executable, GATE, *argumentos]
    if saida_dir:
        cmd += ["--saida-dir", saida_dir]
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=RAIZ)
    try:
        obj = json.loads(proc.stdout)
    except json.JSONDecodeError:
        obj = None
    return proc.returncode, obj, proc.stdout + proc.stderr


def fixture(pasta, nome, conteudo):
    caminho = os.path.join(pasta, nome)
    with open(caminho, "w", encoding="utf-8") as fh:
        json.dump(conteudo, fh, ensure_ascii=False)
    return caminho


class CasoBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.saida = os.path.join(self.dir, "saida")

    def tearDown(self):
        self.tmp.cleanup()


class TesteContrato(CasoBase):
    """O objeto JSON do contrato precisa ser igual em TODOS os gates."""

    def test_chaves_obrigatorias_e_tipos(self):
        for argumentos in (["blueprint"], ["issues", "--sem-gh"], ["situacao"]):
            codigo, obj, bruto = rodar(*argumentos, saida_dir=self.saida)
            with self.subTest(gate=argumentos[0]):
                self.assertIsNotNone(obj, f"saída não é JSON: {bruto[:200]}")
                self.assertTrue(CHAVES_OBRIGATORIAS <= set(obj), "faltam chaves do contrato")
                self.assertIsInstance(obj["id"], str)
                self.assertTrue(obj["id"].startswith("gate-"))
                self.assertIn(obj["status"], {"0", "1", "2"}, "status é string 0/1/2")
                self.assertIsInstance(obj["mensagem"], str)
                self.assertIsInstance(obj["continuidade"], bool)
                self.assertIsInstance(obj["anexos"], list)
                self.assertIsInstance(obj["dados"], dict)
                for anexo in obj["anexos"]:
                    self.assertEqual({"path", "filename", "descricao"}, set(anexo))

    def test_codigo_de_saida_igual_ao_status(self):
        casos = [(["blueprint"], "0"), (["issues", "--sem-gh"], "2")]
        for argumentos, esperado in casos:
            codigo, obj, _ = rodar(*argumentos, saida_dir=self.saida)
            with self.subTest(gate=argumentos[0]):
                self.assertEqual(obj["status"], esperado)
                self.assertEqual(codigo, int(esperado), "exit code deve espelhar o status")
                self.assertEqual(obj["codigo_saida"], codigo)

    def test_anexos_gravados_no_disco(self):
        codigo, obj, _ = rodar("blueprint", saida_dir=self.saida)
        for anexo in obj["anexos"]:
            self.assertTrue(os.path.exists(anexo["path"]), f"anexo ausente: {anexo}")
            self.assertEqual(anexo["filename"], os.path.basename(anexo["path"]))

    def test_json_saida_grava_arquivo(self):
        destino = os.path.join(self.dir, "resultado.json")
        codigo, obj, _ = rodar("blueprint", "--json-saida", destino, saida_dir=self.saida)
        self.assertTrue(os.path.exists(destino))
        with open(destino, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh)["status"], obj["status"])


class TesteGateIssues(CasoBase):
    def test_com_issue_aberta_e_continuidade(self):
        fx = fixture(self.dir, "issues.json", [
            {"number": 3, "title": "SESSION CONTINUITY CONTROL", "url": "https://x/3"}])
        codigo, obj, _ = rodar("issues", "--issues-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertEqual(obj["dados"]["abertas"], 1)
        self.assertIn("continua", obj["mensagem"])

    def test_sem_issue_aberta_e_sucesso(self):
        fx = fixture(self.dir, "issues.json", [])
        codigo, obj, _ = rodar("issues", "--issues-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("0", 0, False))
        self.assertIsNone(obj["next_issue"])

    def test_sem_fonte_e_erro_tipo_2(self):
        codigo, obj, _ = rodar("issues", "--sem-gh", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("2", 2, False))


class TesteGateCicd(CasoBase):
    def test_ci_com_erro_e_continuidade(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 1, "workflowName": "ci", "status": "completed",
             "conclusion": "failure", "headBranch": "main", "url": "https://x/1"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertEqual(obj["dados"]["com_erro"], 1)

    def test_ci_limpo_e_sucesso(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 1, "workflowName": "ci", "status": "completed",
             "conclusion": "success", "headBranch": "main", "url": "https://x/1"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))

    def test_execucao_em_andamento_nao_e_erro(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 2, "workflowName": "gates", "status": "in_progress",
             "conclusion": None, "headBranch": "x", "url": "https://x/2"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
        self.assertEqual(obj["status"], "0")
        self.assertEqual(obj["dados"]["em_andamento"], 1)

    def test_conclusoes_problematicas_detectadas(self):
        for conclusao in ("failure", "timed_out", "startup_failure", "action_required", "cancelled"):
            fx = fixture(self.dir, f"runs-{conclusao}.json", [
                {"databaseId": 3, "workflowName": "ci", "status": "completed",
                 "conclusion": conclusao, "headBranch": "x", "url": "https://x/3"}])
            codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
            with self.subTest(conclusao=conclusao):
                self.assertEqual(obj["status"], "1", f"{conclusao} deveria ser erro de CI")


class TesteGateTestes(CasoBase):
    def test_comando_que_passa(self):
        codigo, obj, _ = rodar("testes", "--comando", "true", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertIn("aprovados", obj["mensagem"])

    def test_comando_que_falha_e_continuidade(self):
        codigo, obj, _ = rodar("testes", "--comando", "exit 3", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertEqual(obj["dados"]["codigo_saida"], 3)
        log = [a for a in obj["anexos"] if a["filename"].startswith("log-testes")]
        self.assertTrue(log, "o gate precisa anexar o log dos testes")
        self.assertIn("código de saída: 3", open(log[0]["path"], encoding="utf-8").read())


class TesteGateContinuidade(CasoBase):
    def test_pendencia_em_qualquer_check_vira_continuidade(self):
        codigo, obj, _ = rodar("continuidade", "--status-issues", "1", "--status-cicd", "0",
                               "--status-testes", "0", "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertIsNotNone(obj["next_issue"], "com pendência deve apontar a próxima issue")
        self.assertIn("NÃO positivo", obj["mensagem"])
        self.assertFalse(obj["dados"]["gate_positivo"])

    def test_tudo_limpo_vira_sucesso(self):
        codigo, obj, _ = rodar("continuidade", "--status-issues", "0", "--status-cicd", "0",
                               "--status-testes", "0", "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("0", 0, False))
        self.assertIsNone(obj["next_issue"])
        self.assertTrue(obj["dados"]["gate_positivo"])

    def test_indeterminado_propaga_erro_tipo_2(self):
        codigo, obj, _ = rodar("continuidade", "--status-issues", "2", "--status-cicd", "0",
                               "--status-testes", "0", "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("2", 2, False))
        self.assertIn("intervenção", obj["mensagem"])

    def test_regra_documentada_no_objeto(self):
        _, obj, _ = rodar("continuidade", "--status-issues", "0", "--status-cicd", "0",
                          "--status-testes", "0", "--saida-dir", self.saida)
        self.assertIn("positivo", obj["dados"]["regra"])

    def test_anexo_do_veredito_em_markdown(self):
        _, obj, _ = rodar("continuidade", "--status-issues", "1", "--status-cicd", "0",
                          "--status-testes", "0", "--saida-dir", self.saida)
        veredito = [a for a in obj["anexos"] if a["filename"] == "veredito-continuidade.md"]
        self.assertTrue(veredito, "falta o anexo do veredito")
        texto = open(veredito[0]["path"], encoding="utf-8").read()
        self.assertIn("continuidade", texto)
        self.assertIn("| issues |", texto)


class TesteGateIssue(CasoBase):
    def _backlog(self, itens):
        return fixture(self.dir, "backlog.json", {"nome": "teste", "issues": itens})

    def test_sucesso_entrega_a_proxima_indexada(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "primeira", "instrucao_teste": "true", "status": "pendente"},
            {"id": "ISSUE-002", "titulo": "segunda", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, "--id", "ISSUE-001",
                               "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["next_issue"]), ("0", 0, "ISSUE-002"))
        self.assertTrue(obj["continuidade"], "há próxima pendente ⇒ continuidade")
        guias = [a for a in obj["anexos"] if a["filename"].endswith("proxima-issue.md")]
        self.assertTrue(guias, "deve anexar a instrução da issue seguinte")
        self.assertIn("ISSUE-002", open(guias[0]["path"], encoding="utf-8").read())

    def test_falha_mantem_a_mesma_issue(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "quebrada", "instrucao_teste": "exit 7", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, "--id", "ISSUE-001",
                               "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["next_issue"]), ("1", 1, "ISSUE-001"))
        self.assertTrue(obj["continuidade"])
        log = open([a for a in obj["anexos"] if a["filename"].endswith("-log.txt")][0]["path"],
                   encoding="utf-8").read()
        self.assertIn("código de saída: 7", log)

    def test_issue_sem_instrucao_e_erro_tipo_2(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "sem instrução", "instrucao_teste": None,
             "status": "bloqueada"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("2", 2, False))
        self.assertIn("instrucao_teste", obj["mensagem"])

    def test_ultima_pendente_encerra_o_pipeline(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "única", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual((obj["status"], obj["next_issue"], obj["continuidade"]), ("0", None, False))

    def test_marcar_concluida_atualiza_o_backlog(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "a", "instrucao_teste": "true", "status": "pendente"},
            {"id": "ISSUE-002", "titulo": "b", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, "--id", "ISSUE-001",
                               "--marcar", saida_dir=self.saida)
        with open(caminho, encoding="utf-8") as fh:
            dados = json.load(fh)
        primeira = dados["issues"][0]
        self.assertEqual(primeira["status"], "concluida")
        self.assertIn("concluida_em", primeira)
        self.assertTrue(primeira["evidencias"])
        self.assertTrue(obj["dados"]["marcada_concluida"])

    def test_sem_marcar_nao_altera_o_backlog(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "a", "instrucao_teste": "true", "status": "pendente"}])
        antes = open(caminho, encoding="utf-8").read()
        rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual(antes, open(caminho, encoding="utf-8").read())

    def test_escolhe_a_proxima_pendente_sem_id(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "feita", "instrucao_teste": "true", "status": "concluida"},
            {"id": "ISSUE-002", "titulo": "próxima", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual(obj["dados"]["issue"], "ISSUE-002")


class TesteBlueprintEBacklog(CasoBase):
    def test_blueprint_do_projeto_e_consistente(self):
        codigo, obj, _ = rodar("blueprint", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertEqual(obj["dados"]["gates"],
                         ["cicd", "continuidade", "issue", "issues", "testes"])

    def test_blueprint_inconsistente_e_erro_tipo_2(self):
        caminho = fixture(self.dir, "planta.json", {
            "gates": [{"id": "issues"}, {"id": "gate-fantasma"}],
            "transicoes": [{"de": "issues", "para": "fim", "quando_status": "0"}]})
        codigo, obj, _ = rodar("blueprint", "--blueprint", caminho, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("2", 2))
        self.assertIn("sem implementação", obj["mensagem"])

    def test_backlog_do_projeto_e_integro(self):
        with open(BACKLOG, encoding="utf-8") as fh:
            backlog = json.load(fh)
        ids, numeros = [], []
        for item in backlog["issues"]:
            ids.append(item["id"])
            numeros.append(int(re.search(r"(\d+)$", item["id"]).group(1)))
            self.assertIn(item["status"], {"concluida", "pendente", "bloqueada"}, item["id"])
            self.assertTrue(item["titulo"].strip(), item["id"])
            self.assertTrue(item["entregavel"].strip(), item["id"])
            instrucao = item.get("instrucao_teste")
            if instrucao:
                for arquivo in re.findall(r"[\w/\.\-]+\.(?:py|sh)", instrucao):
                    self.assertTrue(os.path.exists(os.path.join(RAIZ, arquivo)),
                                    f"{item['id']}: instrução aponta para {arquivo} inexistente")
        self.assertEqual(len(ids), len(set(ids)), "ids duplicados no backlog")
        self.assertEqual(numeros, list(range(1, len(numeros) + 1)),
                         "ids devem ser sequenciais (ISSUE-001, ISSUE-002, …)")

    def test_funcoes_do_modulo(self):
        backlog = gate.ler_backlog(BACKLOG)
        proxima = gate.proxima_pendente(backlog)
        self.assertIsNotNone(proxima, "o backlog precisa manter a próxima pendência")
        self.assertEqual(proxima["id"], "ISSUE-006")
        bagunçado = [{"id": "ISSUE-010", "status": "pendente"},
                     {"id": "ISSUE-002", "status": "concluida"},
                     {"id": "ISSUE-007", "status": "pendente"}]
        self.assertEqual([i["id"] for i in gate.ordenar(bagunçado)],
                         ["ISSUE-002", "ISSUE-007", "ISSUE-010"], "ordenação por índice")
        self.assertEqual(gate.proxima_pendente({"issues": bagunçado})["id"], "ISSUE-007")
        self.assertEqual(gate.proxima_pendente({"issues": bagunçado}, excluir=["ISSUE-007"])["id"],
                         "ISSUE-010", "issue validada não deve voltar como próxima")
        self.assertNotEqual(gate.novo_id("x"), gate.novo_id("x"), "id deve ser único")


class TesteSituacao(CasoBase):
    def test_situacao_resume_o_historico(self):
        rodar("blueprint", saida_dir=self.saida)
        rodar("issues", "--issues-json", fixture(self.dir, "i.json", []), saida_dir=self.saida)
        codigo, obj, _ = rodar("situacao", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertIn("blueprint", obj["dados"]["ultimos"])
        self.assertIn("issues", obj["dados"]["ultimos"])


class TesteWorkflow(unittest.TestCase):
    def setUp(self):
        with open(WORKFLOW, encoding="utf-8") as fh:
            self.texto = fh.read()

    def test_gatilhos_exigidos(self):
        for gatilho in ("push:", "pull_request:", "issues:", "schedule:", "workflow_dispatch:"):
            self.assertIn(gatilho, self.texto, f"falta o gatilho {gatilho}")

    def test_cinco_gates_encadeados(self):
        for job in ("gate-issues", "gate-cicd", "gate-testes", "gate-continuidade", "executa-issue"):
            self.assertRegex(self.texto, rf"(?m)^\s{{2}}{job}:", f"falta o job {job}")
        self.assertRegex(self.texto, r"needs: \[gate-issues, gate-cicd, gate-testes\]")

    def test_jobs_chamam_o_executor(self):
        chamadas = re.findall(r"python3 pipeline/gate\.py (\w+)", self.texto)
        for gate_nome in ("issues", "cicd", "testes", "continuidade", "issue"):
            self.assertIn(gate_nome, chamadas, f"o job do gate {gate_nome} não chama gate.py")

    def test_publica_json_resumo_e_artefatos(self):
        self.assertIn("GITHUB_STEP_SUMMARY", self.texto)
        self.assertIn("actions/upload-artifact", self.texto)
        self.assertIn("--json-saida", self.texto)
        self.assertIn("GATE_SAIDA_DIR", self.texto)

    def test_status_2_derruba_o_job(self):
        self.assertIn('if [ "$status" = "2" ]; then', self.texto)
        self.assertIn("exit 1", self.texto)

    def test_yaml_estrutural(self):
        """Checagem estrutural mínima (sem PyYAML, que não está instalado aqui)."""
        self.assertNotIn("\t", self.texto, "YAML não aceita tabulação para indentação")
        with open(WORKFLOW, encoding="utf-8") as fh:
            linhas = fh.read().splitlines()
        self.assertTrue(linhas[0].startswith("#") or linhas[0].startswith("name:"),
                        "o arquivo precisa começar com comentário ou name:")
        for linha in linhas:
            if re.match(r"^\s*[\w\-\.\$\{\}'\"/]+\s*:", linha) and not linha.lstrip().startswith("#"):
                indent = len(linha) - len(linha.lstrip(" "))
                self.assertEqual(indent % 2, 0, f"indentação ímpar em: {linha!r}")
        try:
            import yaml  # type: ignore
        except ImportError:
            self.skipTest("PyYAML indisponível — a validação definitiva é a execução no Actions")
        dados = yaml.safe_load(self.texto)
        self.assertIn("jobs", dados)


if __name__ == "__main__":
    unittest.main(verbosity=2)
__ARQ_EOF__
__ARQ__ tools/gerar_bootstrap.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gera o bootstrap.sh — o instalador que recria este projeto inteiro, do zero.

O bootstrap.sh resultante é autossuficiente: contém o conteúdo de TODOS os
arquivos do projeto embutido em heredocs, cria os diretórios, aplica as
permissões, confere os hashes SHA-256, valida a sintaxe e roda as três suítes
de teste — imprimindo no fim um relatório com os códigos de saída.

Uso:
    python3 tools/gerar_bootstrap.py            # regenera ./bootstrap.sh
    python3 tools/gerar_bootstrap.py --conferir # falha se o bootstrap estiver desatualizado

O script NÃO embute a si mesmo (o bootstrap copia o próprio arquivo para o
destino quando executado a partir do disco).
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAIDA = os.path.join(RAIZ, "bootstrap.sh")
MARCADOR = "__ARQ_EOF__"

# Arquivos do projeto (caminho relativo -> bool executável)
ARQUIVOS = {
    ".gitignore": False,
    ".github/workflows/gates.yml": False,
    "Makefile": False,
    "README.md": False,
    "BOOTSTRAP.md": False,
    "ENTREGA.md": False,
    "main.py": True,
    "bootstrap.sh": True,          # copiado de $0 em tempo de execução
    "docs/01-api-datajud.md": False,
    "docs/02-receitas-curl-tjpe.md": False,
    "docs/03-pipeline-gates.md": False,
    "docs/exemplo-saida/agg-grau.tsv": False,
    "docs/exemplo-saida/agg-orgao-nome.csv": False,
    "docs/exemplo-saida/relatorio-processo-exemplo.md": False,
    "docs/exemplo-saida/relatorio-tjpe-exemplo.md": False,
    "pipeline/.gitignore": False,
    "pipeline/backlog.json": False,
    "pipeline/blueprint.json": False,
    "pipeline/gate.py": True,
    "pipeline/verificar_cnj.py": True,
    "scripts/datajud.sh": True,
    "tests/mock_apis.py": True,
    "tests/mock_datajud.py": True,
    "tests/rodar-testes.sh": True,
    "tests/testar_bootstrap.sh": True,
    "tests/testar_conformidade.py": True,
    "tests/testar_main.py": True,
    "tests/testar_pipeline.py": True,
    "tools/gerar_bootstrap.py": True,
}

# bootstrap.sh não entra no manifesto de hashes (ele contém o próprio manifesto)
FORA_DO_MANIFESTO = {"bootstrap.sh"}


def ler(relativo: str) -> str:
    with open(os.path.join(RAIZ, relativo), encoding="utf-8") as fh:
        return fh.read()


def sha256_de(conteudo: str) -> str:
    return hashlib.sha256(conteudo.encode("utf-8")).hexdigest()


# --------------------------------------------------------------------------- #
# Template do bootstrap.sh — string normal (sem f-string) com placeholders.
# Chaves do bash ficam literais; os @@PLACEHOLDERS@@ são substituídos em gerar().
# --------------------------------------------------------------------------- #
CORPO_SCRIPT = r"""#!/usr/bin/env bash
# ==============================================================================
#  bootstrap.sh — recria este projeto INTEIRO, do zero, e prova que funciona.
# ==============================================================================
#  Gerado por tools/gerar_bootstrap.py — NÃO edite à mão; regenere com
#      python3 tools/gerar_bootstrap.py
#
#  O que este script faz, em ordem:
#    1. confere os pré-requisitos (bash 4+, python3 3.8+; curl/jq são opcionais)
#    2. cria TODOS os diretórios e escreve TODOS os arquivos (conteúdo embutido)
#    3. aplica TODAS as permissões (755 em scripts/testes, 644 em docs/dados)
#    4. confere a integridade por SHA-256 de cada arquivo escrito
#    5. valida a sintaxe (python -m py_compile, bash -n)
#    6. roda as 4 suítes de teste offline (conformidade, main.py, datajud.sh, pipeline)
#    7. imprime um relatório final com o código de saída de cada etapa
#
#  Uso:
#      bash bootstrap.sh                       # cria em ./projeto-datajud
#      bash bootstrap.sh --destino /opt/xyz    # cria em outro diretório
#      bash bootstrap.sh --forcar              # sobrescreve destino existente
#      bash bootstrap.sh --so-criar            # cria e confere, sem rodar testes
#      bash bootstrap.sh --verificar           # só verifica um projeto já criado
#      bash bootstrap.sh --sem-testes          # pula as suítes
#      bash bootstrap.sh --ajuda
#
#  Conteúdo embutido: @@STATS@@.
#  Documentação: BOOTSTRAP.md · Wiki do CNJ: https://datajud-wiki.cnj.jus.br/api-publica/acesso
# ==============================================================================
set -euo pipefail

VERSAO_BOOTSTRAP="1.0.0"
DESTINO="./projeto-datajud"
FORCAR=0
SO_CRIAR=0
SEM_TESTES=0
SO_VERIFICAR=0

TITULO() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
PASSO()  { printf '   \033[1;32m✔\033[0m %s\n' "$*"; }
ALERTA() { printf '   \033[1;33m!\033[0m %s\n' "$*"; }
FALHA()  { printf '   \033[1;31m✘\033[0m %s\n' "$*" >&2; }
MORRER() { FALHA "$*"; exit 1; }
modo_de() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

uso() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while (($#)); do
  case "$1" in
    --destino)     DESTINO="${2:?faltou o valor}"; shift ;;
    --forcar)      FORCAR=1 ;;
    --so-criar)    SO_CRIAR=1 ;;
    --sem-testes)  SEM_TESTES=1 ;;
    --verificar)   SO_VERIFICAR=1 ;;
    -h|--help|ajuda) uso ;;
    *) MORRER "opção desconhecida: $1 (use --ajuda)" ;;
  esac
  shift
done

# Extrai do próprio script o conteúdo de um arquivo embutido
MARCADOR_FIM="__ARQ_""EOF__"   # montado em runtime para não coincidir com o conteúdo embutido
# Extrai o blob de um arquivo embutido usando comparação exata de linha (awk),
# para não depender de escape de regex nos caminhos (docs/… tem “/”).
conteudo_arquivo() {
  awk -v alvo="__ARQ__ $1" -v fim="$MARCADOR_FIM" '
    $0 == alvo { dentro = 1; next }
    dentro && $0 == fim { exit }
    dentro { print }
  ' "$0"
}

# ------------------------------------------------------------------ 1. apoio ---
TITULO "1/7 · Pré-requisitos"
[[ "${BASH_VERSINFO[0]:-0}" -ge 4 ]] || MORRER "bash 4+ é necessário (atual: ${BASH_VERSION:-?})"
PASSO "bash ${BASH_VERSION%%(*}"
command -v python3 >/dev/null 2>&1 || MORRER "python3 não encontrado no PATH"
VERSAO_PY=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' \
  || MORRER "python3 3.8+ é necessário (atual: $VERSAO_PY)"
PASSO "python3 $VERSAO_PY"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  PASSO "curl e jq presentes (necessários só para scripts/datajud.sh)"
else
  ALERTA "curl e/ou jq ausentes — o main.py funciona; scripts/datajud.sh não"
fi
if [[ "$SO_VERIFICAR" == "1" && "$DESTINO" == "./projeto-datajud" ]]; then
  DESTINO="."
fi

# ------------------------------------------------------------------ 2. estrutura ---
if [[ "$SO_VERIFICAR" == "0" ]]; then
  TITULO "2/7 · Estrutura de diretórios"
  if [[ -e "$DESTINO" && "$FORCAR" == "0" && -n "$(ls -A "$DESTINO" 2>/dev/null || true)" ]]; then
    MORRER "$DESTINO já existe e não está vazio (use --forcar para sobrescrever)"
  fi
  mkdir -p "$DESTINO"
  chmod 755 "$DESTINO"
  for d in @@DIRS@@; do
    mkdir -p "$DESTINO/$d"
    chmod 755 "$d" 2>/dev/null || true
    chmod 755 "$DESTINO/$d"
  done
  PASSO "diretórios criados (raiz + subdiretórios), todos com modo 755"

  # ---------------------------------------------------------------- 3. arquivos ---
  TITULO "3/7 · Arquivos do projeto"
  while read -r modo caminho; do
    [[ -z "${caminho:-}" ]] && continue
    conteudo_arquivo "$caminho" > "$DESTINO/$caminho"
    chmod "$modo" "$DESTINO/$caminho"
  done <<'LISTA'
@@LISTA_ARQUIVOS@@
LISTA
  if [[ -f "$0" && -r "$0" ]]; then
    install -m 755 "$0" "$DESTINO/bootstrap.sh"
    PASSO "bootstrap.sh copiado junto (para reinstalar/verificar depois)"
  else
    ALERTA "executado via stdin/pipe: bootstrap.sh não foi copiado (copie manualmente)"
  fi
  PASSO "arquivos escritos com as permissões corretas"
else
  TITULO "2/7 · Estrutura de diretórios"
  [[ -d "$DESTINO" ]] || MORRER "diretório não encontrado: $DESTINO"
  PASSO "verificando o projeto em $DESTINO"
  TITULO "3/7 · Arquivos do projeto"
  PASSO "escrita pulada (modo --verificar)"
fi

# ------------------------------------------------- 4. integridade (SHA-256) ---
TITULO "4/7 · Integridade dos arquivos (SHA-256)"
falhas_hash=0
while read -r esperado caminho; do
  [[ -z "${caminho:-}" ]] && continue
  caminho="${caminho#./}"
  alvo="$DESTINO/$caminho"
  if [[ ! -f "$alvo" ]]; then
    FALHA "faltando: $caminho"; falhas_hash=$((falhas_hash+1)); continue
  fi
  obtido=$( { sha256sum "$alvo" 2>/dev/null || shasum -a 256 "$alvo"; } | cut -d' ' -f1 )
  if [[ "$obtido" != "$esperado" ]]; then
    FALHA "hash diferente: $caminho"; falhas_hash=$((falhas_hash+1))
  fi
done <<'MANIFESTO'
@@MANIFESTO@@
MANIFESTO
if [[ "$falhas_hash" == "0" ]]; then
  PASSO "todos os hashes conferem com o manifesto embutido"
else
  MORRER "$falhas_hash arquivo(s) divergentes — o destino não corresponde a este bootstrap"
fi

# ------------------------------------------------------ 5. permissões esperadas ---
TITULO "5/7 · Permissões"
falhas_modo=0
while read -r modo caminho; do
  [[ -z "${caminho:-}" ]] && continue
  real=$(modo_de "$DESTINO/$caminho" 2>/dev/null || echo "?")
  if [[ "$real" != "$modo" ]]; then
    FALHA "$caminho: modo $real (esperado $modo)"; falhas_modo=$((falhas_modo+1))
  fi
done <<'PERMISSOES'
@@LISTA_PERMISSOES@@
PERMISSOES
if [[ "$falhas_modo" == "0" ]]; then
  PASSO "755 em scripts/testes, 644 em docs/dados — todos corretos"
else
  ALERTA "$falhas_modo arquivo(s) com permissão divergente (corrija com chmod)"
fi

# --------------------------------------------------------- 6. validação estática ---
TITULO "6/7 · Validação de sintaxe"
ST_PY=0; ST_SH=0
for arq in @@LISTA_PY@@; do
  python3 -m py_compile "$DESTINO/$arq" 2>/dev/null || { FALHA "python inválido: $arq"; ST_PY=1; }
done
rm -rf "$DESTINO"/__pycache__ "$DESTINO"/tests/__pycache__ "$DESTINO"/tools/__pycache__ \
       "$DESTINO"/pipeline/__pycache__ 2>/dev/null || true
[[ "$ST_PY" == "0" ]] && PASSO "Python: @@N_PY@@ arquivos compilam sem erro (py_compile)"
for arq in @@LISTA_SH@@; do
  bash -n "$DESTINO/$arq" 2>/dev/null || { FALHA "bash inválido: $arq"; ST_SH=1; }
done
[[ "$ST_SH" == "0" ]] && PASSO "Bash: @@N_SH@@ scripts sem erro de sintaxe (bash -n)"

# ------------------------------------------------------------------ 7. testes ---
ST_CONF="pulado"; ST_MAIN="pulado"; ST_SH_T="pulado"; ST_PIPE="pulado"
if [[ "$SEM_TESTES" == "1" || "$SO_CRIAR" == "1" ]]; then
  TITULO "7/7 · Testes"
  ALERTA "suítes de teste não executadas (--so-criar/--sem-testes)"
else
  TITULO "7/7 · Testes (offline, contra mocks locais)"
  ( cd "$DESTINO" && python3 tests/testar_conformidade.py ) >/tmp/bootstrap_conf.log 2>&1 \
    && ST_CONF="ok" || ST_CONF="FALHOU"
  grep -E '^(Ran |OK|FAILED)' /tmp/bootstrap_conf.log | tail -2 | sed 's/^/     /' || true
  [[ "$ST_CONF" == "ok" ]] && PASSO "conformidade com a documentação do CNJ" || FALHA "conformidade"

  ( cd "$DESTINO" && python3 tests/testar_main.py ) >/tmp/bootstrap_main.log 2>&1 \
    && ST_MAIN="ok" || ST_MAIN="FALHOU"
  grep -E '^(Ran |OK|FAILED)' /tmp/bootstrap_main.log | tail -2 | sed 's/^/     /' || true
  [[ "$ST_MAIN" == "ok" ]] && PASSO "main.py (consulta de processo e relatório)" || FALHA "testes do main.py"

  ( cd "$DESTINO" && bash tests/rodar-testes.sh ) >/tmp/bootstrap_sh.log 2>&1 \
    && ST_SH_T="ok" || ST_SH_T="FALHOU"
  tail -1 /tmp/bootstrap_sh.log | sed 's/^/     /' || true
  [[ "$ST_SH_T" == "ok" ]] && PASSO "scripts/datajud.sh (curl + jq)" || FALHA "testes do datajud.sh"

  ( cd "$DESTINO" && python3 tests/testar_pipeline.py ) >/tmp/bootstrap_pipe.log 2>&1 \
    && ST_PIPE="ok" || ST_PIPE="FALHOU"
  grep -E '^(Ran |OK|FAILED)' /tmp/bootstrap_pipe.log | tail -2 | sed 's/^/     /' || true
  [[ "$ST_PIPE" == "ok" ]] && PASSO "pipeline de gates (contrato JSON, 0/1/2)" || FALHA "testes do pipeline"
fi

# ------------------------------------------------------------------ resumo ---
TITULO "Resultado do bootstrap"
printf '  destino..... : %s\n' "$(cd "$DESTINO" && pwd)"
printf '  arquivos.... : %s\n' "@@TOTAL_ARQUIVOS@@"
printf '  permissões.. : 755 em scripts/testes, 644 em docs/dados\n'
printf '  python...... : %s\n' "$([[ "$ST_PY" == "0" ]] && echo 'compila' || echo 'FALHOU')"
printf '  bash........ : %s\n' "$([[ "$ST_SH" == "0" ]] && echo 'sem erro de sintaxe' || echo 'FALHOU')"
printf '  teste conf.. : %s\n' "$ST_CONF"
printf '  teste main.. : %s\n' "$ST_MAIN"
printf '  teste shell. : %s\n' "$ST_SH_T"
printf '  teste pipe.. : %s\n' "$ST_PIPE"
printf '\n  Próximos passos:\n'
printf '    cd %s\n' "$DESTINO"
printf '    python3 main.py 0001234-56.2024.8.17.2001   # consulta real (precisa de internet)\n'
printf '    make gates                                  # veredito de continuidade do pipeline\n'
printf '    make testes                                 # roda as 5 suítes de novo\n\n'

if [[ "$ST_PY" != "0" || "$ST_SH" != "0" || "$ST_CONF" == "FALHOU" \
      || "$ST_MAIN" == "FALHOU" || "$ST_SH_T" == "FALHOU" || "$ST_PIPE" == "FALHOU" ]]; then
  FALHA "bootstrap concluiu com falhas (veja acima)"
  exit 1
fi
printf '\033[1;32mBootstrap concluído com sucesso.\033[0m\n'
exit 0

# ==============================================================================
#  CONTEÚDO EMBUTIDO — cada bloco abaixo é um arquivo do projeto.
#  Formato:  __ARQ__ <caminho>  ... conteúdo ...  <marcador de fim>
# ==============================================================================
"""


def gerar() -> str:
    # bootstrap.sh é a própria saída (copiada de $0 em tempo de execução)
    faltando = [a for a in ARQUIVOS
                if a not in FORA_DO_MANIFESTO and not os.path.exists(os.path.join(RAIZ, a))]
    if faltando:
        raise SystemExit("arquivos ausentes: " + ", ".join(faltando))

    # embutido byte a byte: só é aceito arquivo que já termina com newline
    conteudos = {}
    for a in sorted(ARQUIVOS):
        if a in FORA_DO_MANIFESTO:
            continue
        texto = ler(a)
        if not texto.endswith("\n"):
            raise SystemExit(f"{a} não termina com newline — adicione um para o bootstrap embutir igual")
        conteudos[a] = texto
    for caminho, texto in conteudos.items():
        # só é problema se o marcador aparecer sozinho numa linha (é assim que o
        # bootstrap delimita os blocos); citações dentro de strings são inofensivas
        for reservado in (MARCADOR, DELIMITADOR_PAYLOAD):
            if any(linha.strip() == reservado for linha in texto.splitlines()):
                raise SystemExit(f"{caminho} tem uma linha só com {reservado}; troque o marcador.")

    manifesto = "\n".join(
        f"{sha256_de(conteudos[a])}  ./{a}"
        for a in sorted(conteudos) if a not in FORA_DO_MANIFESTO
    )
    total_bytes = sum(len(c.encode("utf-8")) for c in conteudos.values())
    total_linhas = sum(c.count("\n") for c in conteudos.values())
    dirs = sorted({os.path.dirname(a) for a in ARQUIVOS if os.path.dirname(a)})

    lista_arquivos = "\n".join(
        f'{"755" if ARQUIVOS[a] else "644"} {a}'
        for a in sorted(ARQUIVOS) if a != "bootstrap.sh"
    )
    lista_permissoes = "\n".join(
        f'{"755" if ARQUIVOS[a] else "644"} {a}' for a in sorted(ARQUIVOS)
    )
    stats = (f"{len(ARQUIVOS)} arquivos, {total_linhas} linhas, "
             f"{total_bytes // 1024} KiB")

    # arquivos validados na etapa 6 (sintaxe) — listas dinâmicas
    lista_py = [a for a in sorted(ARQUIVOS) if a.endswith(".py") and a not in FORA_DO_MANIFESTO]
    lista_sh = sorted({a for a in ARQUIVOS if a.endswith(".sh")} | {"bootstrap.sh"})

    corpo = "".join([
        CORPO_SCRIPT
        .replace("@@DIRS@@", " ".join(dirs))
        .replace("@@LISTA_ARQUIVOS@@", lista_arquivos)
        .replace("@@MANIFESTO@@", manifesto)
        .replace("@@LISTA_PERMISSOES@@", lista_permissoes)
        .replace("@@STATS@@", stats)
        .replace("@@LISTA_PY@@", " ".join(lista_py))
        .replace("@@N_PY@@", str(len(lista_py)))
        .replace("@@LISTA_SH@@", " ".join(lista_sh))
        .replace("@@N_SH@@", str(len(lista_sh)))
        .replace("@@TOTAL_ARQUIVOS@@", f"{len(conteudos)} no manifesto SHA-256 (+ bootstrap.sh)"),
        *_blocos_embutidos(conteudos),
    ])
    return corpo


DELIMITADOR_PAYLOAD = "__PAYLOAD_FIM__"


def _blocos_embutidos(conteudos: dict) -> list:
    blocos = ["\n# Heredoc não executado: mantém o payload fora da análise do bash.\n",
              f": <<'{DELIMITADOR_PAYLOAD}'\n"]
    for caminho in sorted(conteudos):
        if caminho == "bootstrap.sh":
            continue
        blocos.append(f"__ARQ__ {caminho}\n")
        blocos.append(conteudos[caminho])
        blocos.append(f"{MARCADOR}\n")
    blocos.append(f"{DELIMITADOR_PAYLOAD}\n")
    return blocos


def main() -> int:
    ap = argparse.ArgumentParser(description="Gera/valida o bootstrap.sh")
    ap.add_argument("--conferir", action="store_true",
                    help="não regrava: falha se o bootstrap.sh estiver desatualizado")
    args = ap.parse_args()

    novo = gerar()
    if args.conferir:
        atual = ler("bootstrap.sh") if os.path.exists(SAIDA) else ""
        if atual != novo:
            print("bootstrap.sh está DESATUALIZADO — rode: python3 tools/gerar_bootstrap.py",
                  file=sys.stderr)
            return 1
        print("bootstrap.sh está atualizado.")
        return 0

    with open(SAIDA, "w", encoding="utf-8") as fh:
        fh.write(novo)
    os.chmod(SAIDA, 0o755)
    print(f"bootstrap.sh gerado: {len(novo.splitlines())} linhas, "
          f"{len(novo.encode('utf-8')) // 1024} KiB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
__ARQ_EOF__
__PAYLOAD_FIM__
