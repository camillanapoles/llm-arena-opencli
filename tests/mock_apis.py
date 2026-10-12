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
