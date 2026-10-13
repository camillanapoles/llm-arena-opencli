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
    ".github/workflows/validacao-cnj.yml": False,
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
    "pipeline/factory.py": True,
    "pipeline/gate.py": True,
    "pipeline/verificar_cnj.py": True,
    "scripts/datajud.sh": True,
    "tests/mock_apis.py": True,
    "tests/mock_datajud.py": True,
    "tests/rodar-testes.sh": True,
    "tests/testar_bootstrap.sh": True,
    "tests/testar_conformidade.py": True,
    "tests/testar_main.py": True,
    "tests/testar_fabrica.py": True,
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
#    6. roda as 5 suítes de teste offline (conformidade, main.py, datajud.sh, pipeline, fábrica)
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
ST_CONF="pulado"; ST_MAIN="pulado"; ST_SH_T="pulado"; ST_PIPE="pulado"; ST_FAB="pulado"
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

  ( cd "$DESTINO" && python3 tests/testar_fabrica.py ) >/tmp/bootstrap_fab.log 2>&1 \
    && ST_FAB="ok" || ST_FAB="FALHOU"
  grep -E '^(Ran |OK|FAILED)' /tmp/bootstrap_fab.log | tail -2 | sed 's/^/     /' || true
  [[ "$ST_FAB" == "ok" ]] && PASSO "fábrica de issues (SQLite + eventos + padrão)" || FALHA "testes da fábrica"
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
printf '  teste fabr.. : %s\n' "$ST_FAB"
printf '\n  Próximos passos:\n'
printf '    cd %s\n' "$DESTINO"
printf '    python3 main.py 0001234-56.2024.8.17.2001   # consulta real (precisa de internet)\n'
printf '    make gates                                  # veredito de continuidade do pipeline\n'
printf '    make fabrica                                # estado da fábrica de issues (SQLite)\n'
printf '    make testes                                 # roda as 6 suítes de novo\n\n'

if [[ "$ST_PY" != "0" || "$ST_SH" != "0" || "$ST_CONF" == "FALHOU" \
      || "$ST_MAIN" == "FALHOU" || "$ST_SH_T" == "FALHOU" || "$ST_PIPE" == "FALHOU" \
      || "$ST_FAB" == "FALHOU" ]]; then
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
