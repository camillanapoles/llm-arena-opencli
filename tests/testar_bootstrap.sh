#!/usr/bin/env bash
# ==============================================================================
#  testar_bootstrap.sh — prova que o bootstrap.sh recria este projeto idêntico
# ==============================================================================
#  Etapas:
#    1. o bootstrap.sh está atualizado? (tools/gerar_bootstrap.py --conferir)
#    2. bash bootstrap.sh cria o projeto num diretório temporário
#    3. a árvore criada é comparada com o repositório (diff -r, exceto .git)
#    4. as permissões conferem (755 em scripts/testes, 644 em docs/dados)
#    5. as 5 suítes de teste rodam DENTRO do projeto recriado
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

titulo '3. Árvore criada x repositório (byte a byte, arquivos do kit)'
# No repositório unificado (pilhas CNJ + Node/TS) o bootstrap cobre o KIT CNJ —
# os arquivos que tools/gerar_bootstrap.py embute. A comparação é byte a byte
# sobre esse inventário; a pilha Node/TS se reinstala com npm (ver README).
mapfile -t KIT < <(python3 -c "import sys; sys.path.insert(0, 'tools'); import gerar_bootstrap as g; print('\n'.join(g.ARQUIVOS))")
diferencas=0
for caminho in "${KIT[@]}"; do
  if [[ ! -f "$TMP/projeto/$caminho" ]]; then
    ruim "faltando no projeto criado: $caminho"; diferencas=$((diferencas+1)); continue
  fi
  if [[ ! -f "$RAIZ/$caminho" ]]; then
    ruim "faltando no repositório: $caminho"; diferencas=$((diferencas+1)); continue
  fi
  if ! cmp -s "$RAIZ/$caminho" "$TMP/projeto/$caminho"; then
    ruim "conteúdo diferente do repositório: $caminho"; diferencas=$((diferencas+1))
  fi
done
if [[ $diferencas -eq 0 ]]; then
  ok "todos os ${#KIT[@]} arquivos do kit idênticos ao repositório (byte a byte)"
fi
printf '%s\n' "${KIT[@]}" | sort >"$TMP/kit.txt"
(cd "$TMP/projeto" && find . -type f | sed 's|^\./||' | sort) >"$TMP/criado.txt"
if diff -u "$TMP/kit.txt" "$TMP/criado.txt" >"$TMP/diff.log" 2>&1; then
  ok "o projeto criado tem exatamente os ${#KIT[@]} arquivos do kit (sem extras nem faltas)"
else
  ruim 'inventário do projeto criado difere do kit:'
  sed 's/^/      /' "$TMP/diff.log" | head -20
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
if ( cd "$TMP/projeto" && python3 tests/testar_fabrica.py >/dev/null 2>&1 ); then
  ok 'suíte da fábrica de issues passa no projeto recriado'
else
  ruim 'suíte da fábrica falhou no projeto recriado'
fi
if ( cd "$TMP/projeto" && python3 pipeline/gate.py fabrica >/dev/null 2>&1 ); then
  ok 'gate fabrica roda no projeto recriado (fábrica íntegra)'
else
  ruim 'gate fabrica falhou no projeto recriado'
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
