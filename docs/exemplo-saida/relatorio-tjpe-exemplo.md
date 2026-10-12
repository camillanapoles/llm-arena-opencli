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
