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
