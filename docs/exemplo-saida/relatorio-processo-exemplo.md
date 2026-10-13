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

