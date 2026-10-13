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
