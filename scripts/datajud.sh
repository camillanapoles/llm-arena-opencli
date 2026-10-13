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
