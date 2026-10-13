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
