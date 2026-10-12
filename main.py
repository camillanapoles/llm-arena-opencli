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
