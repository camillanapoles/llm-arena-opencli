#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gate.py — gates do pipeline (gate-driven pipeline / blueprint tipo BPMN).

Cada ação deste pipeline devolve SEMPRE o mesmo objeto JSON no stdout:

    {
      "id":          "gate-continuidade-20261013T141500Z-8f3a1c",  # único
      "gate":        "continuidade",
      "status":      "0",              # string: 0=sucesso, 1=erro tipo 1, 2=erro tipo 2
      "codigo_saida": 0,               # mesmo valor, como inteiro (exit code do processo)
      "mensagem":    "...",            # string pronta OU resumo/log da execução
      "continuidade": true,            # true = o pipeline DEVE continuar (trabalho pendente)
      "next_issue":  "ISSUE-007",      # mesma issue se falhou; a próxima se passou
      "anexos":      [{"path": "...", "filename": "...", "descricao": "..."}],
      "dados":       { ... },          # detalhes estruturados de cada gate
      "timestamp":   "2026-10-13T14:15:00Z",
      "versao":      "1.0.0"
    }

Semântica dos códigos (contrato do projeto):

  "0" SUCESSO      — o gate é positivo: nada pendente. `continuidade` = false.
  "1" ERRO TIPO 1  — pendência CONHECIDA e tratável: issue aberta, CI vermelho ou
                     teste ausente/reprovado. `continuidade` = true → o pipeline
                     segue (é o "enquanto não positivo, significa continuidade").
  "2" ERRO TIPO 2  — não foi possível avaliar (gh ausente/sem credencial, fixture
                     inválida, issue sem instrução de teste). `continuidade` = false
                     → exige intervenção humana; não continue automaticamente.

O código de saída do processo é igual ao `status` (0, 1 ou 2), para uso direto em
`if`/`|| true` dentro do GitHub Actions.

Comandos:
    gate.py issues        [--sem-gh|--issues-json F]      # existem issues abertas?
    gate.py cicd          [--sem-gh|--runs-json F]        # há execução de CI com erro?
    gate.py testes        [--comando "make testes"]       # os testes existem e passam?
    gate.py continuidade                                  # agrega os três acima
    gate.py issue [--id ISSUE-007] [--marcar]             # executa a instrução da issue
    gate.py blueprint                                     # valida a planta (BPMN-like)
    gate.py situacao                                      # lê os últimos JSONs gravados

Opções comuns:
    --json-saida ARQUIVO   grava o objeto JSON também em arquivo
    --saida-dir DIR        diretório de anexos/JSON (padrão: pipeline/saida)
    --backlog ARQUIVO      fila de issues (padrão: pipeline/backlog.json)
    --repo OWNER/REPO      repositório para consultas via gh (padrão: o atual)
    -q/--quieto            não imprime o JSON no stdout (só grava)

Requisitos: Python 3.8+ (biblioteca padrão). `gh` é necessário para os gates
`issues` e `cicd` fora do modo fixture.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

VERSAO = "1.0.0"
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAIDA_PADRAO = os.path.join(RAIZ, "pipeline", "saida")
BACKLOG_PADRAO = os.path.join(RAIZ, "pipeline", "backlog.json")
BLUEPRINT_PADRAO = os.path.join(RAIZ, "pipeline", "blueprint.json")

STATUS_SUCESSO, STATUS_CONTINUIDADE, STATUS_INDETERMINADO = "0", "1", "2"

# comandos de teste usados pelo gate `testes` e pela checagem de presença
ARQUIVOS_DE_TESTE = [
    "tests/testar_conformidade.py",
    "tests/testar_main.py",
    "tests/rodar-testes.sh",
    "tests/testar_bootstrap.sh",
    "tests/testar_pipeline.py",
]
COMANDO_TESTES_PADRAO = "make testes"


class ErroGate(Exception):
    """Falha do tipo 2 (não foi possível avaliar) com mensagem pronta."""


# --------------------------------------------------------------------------- #
# contrato JSON
# --------------------------------------------------------------------------- #


def agora() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def novo_id(gate: str) -> str:
    carimbo = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"gate-{gate}-{carimbo}-{uuid.uuid4().hex[:6]}"


def objeto(*, gate: str, status: str, mensagem: str, anexos=None, dados=None,
           next_issue=None, continuidade=None, duracao: float = 0.0) -> dict:
    """Monta o objeto JSON do contrato. Unico ponto de criação — garante o formato."""
    if continuidade is None:
        continuidade = status == STATUS_CONTINUIDADE
    return {
        "id": novo_id(gate),
        "gate": gate,
        "status": str(status),
        "codigo_saida": int(status),
        "mensagem": str(mensagem),
        "continuidade": bool(continuidade),
        "next_issue": next_issue,
        "anexos": [
            {"path": a.get("path"), "filename": os.path.basename(a.get("path") or ""),
             "descricao": a.get("descricao", "")}
            for a in (anexos or [])
        ],
        "dados": dados or {},
        "timestamp": agora(),
        "duracao_s": round(duracao, 3),
        "versao": VERSAO,
    }


def gravar(objeto_json: dict, saida_dir: str) -> dict:
    """Grava o objeto em pipeline/saida/<id>.json e devolve o registro do anexo."""
    os.makedirs(saida_dir, exist_ok=True)
    caminho = os.path.join(saida_dir, f"{objeto_json['id']}.json")
    with open(caminho, "w", encoding="utf-8") as fh:
        json.dump(objeto_json, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return {"path": caminho, "filename": os.path.basename(caminho),
            "descricao": f"objeto JSON do gate {objeto_json['gate']}"}


def gravar_anexo(nome: str, conteudo: str, saida_dir: str, descricao: str) -> dict:
    os.makedirs(saida_dir, exist_ok=True)
    caminho = os.path.join(saida_dir, nome)
    with open(caminho, "w", encoding="utf-8") as fh:
        fh.write(conteudo)
    return {"path": caminho, "filename": os.path.basename(caminho), "descricao": descricao}


def executar(comando: str, tempo_limite: int = 1800) -> tuple:
    """Roda um comando de shell e devolve (código, saída_completa)."""
    processo = subprocess.run(["/bin/bash", "-lc", comando], capture_output=True,
                              text=True, timeout=tempo_limite, cwd=RAIZ)
    saida = (processo.stdout or "") + (processo.stderr or "")
    return processo.returncode, saida


# --------------------------------------------------------------------------- #
# backlog (fila indexada de issues)
# --------------------------------------------------------------------------- #


def ler_backlog(caminho: str = BACKLOG_PADRAO) -> dict:
    if not os.path.exists(caminho):
        raise ErroGate(f"backlog não encontrado: {caminho}")
    try:
        with open(caminho, encoding="utf-8") as fh:
            dados = json.load(fh)
    except json.JSONDecodeError as e:
        raise ErroGate(f"backlog inválido (JSON): {e}")
    if not isinstance(dados.get("issues"), list) or not dados["issues"]:
        raise ErroGate("backlog sem a lista 'issues' ou vazia")
    return dados


def ordenar(issues: list) -> list:
    def chave(item):
        m = re.search(r"(\d+)$", str(item.get("id", "")))
        return int(m.group(1)) if m else 0
    return sorted(issues, key=chave)


def proxima_pendente(backlog: dict, excluir=None) -> dict | None:
    """Primeira issue não concluída, ignorando ids em `excluir` (as já validadas na execução)."""
    ignorar = set(excluir or ())
    for item in ordenar(backlog["issues"]):
        if item.get("id") in ignorar:
            continue
        if str(item.get("status", "")).lower() not in ("concluida", "concluída", "done"):
            return item
    return None


def achar_issue(backlog: dict, identificador: str) -> dict | None:
    for item in backlog["issues"]:
        if item.get("id") == identificador:
            return item
    return None


def marcar_concluida(backlog: dict, identificador: str, evidencias: dict) -> None:
    item = achar_issue(backlog, identificador)
    if item is None:
        raise ErroGate(f"issue {identificador} não está no backlog")
    item["status"] = "concluida"
    item["concluida_em"] = agora()
    item.setdefault("evidencias", [])
    item["evidencias"].append(evidencias)


# --------------------------------------------------------------------------- #
# gates de verificação
# --------------------------------------------------------------------------- #


def _rodar_gh(argumentos: list) -> list:
    if shutil.which("gh") is None:
        raise ErroGate("o comando 'gh' não está instalado — não é possível avaliar "
                       "issues/CI (use --issues-json/--runs-json ou --sem-gh)")
    proc = subprocess.run(["gh", *argumentos], capture_output=True, text=True, cwd=RAIZ)
    if proc.returncode != 0:
        raise ErroGate(f"gh {' '.join(argumentos[:3])} falhou: "
                       f"{(proc.stderr or proc.stdout).strip()[:300]}")
    try:
        return json.loads(proc.stdout or "[]")
    except json.JSONDecodeError as e:
        raise ErroGate(f"resposta do gh não é JSON: {e}")


def gate_issues(args, saida_dir: str) -> dict:
    inicio = time.time()
    if args.issues_json:
        with open(args.issues_json, encoding="utf-8") as fh:
            abertas = json.load(fh)
        fonte = f"fixture {args.issues_json}"
    elif args.sem_gh:
        raise ErroGate("modo --sem-gh exige --issues-json (sem fonte para avaliar issues)")
    else:
        consulta = ["issue", "list", "--state", "open", "--limit", "100",
                    "--json", "number,title,url,labels,createdAt"]
        if args.repo:
            consulta += ["--repo", args.repo]
        abertas = _rodar_gh(consulta)
        fonte = "gh issue list"

    linhas = [f"| #{i.get('number')} | {i.get('title','')} | {i.get('url','')} |" for i in abertas]
    anexo = gravar_anexo("issues-abertas.md",
                         "# Issues abertas\n\n| # | título | url |\n| --- | --- | --- |\n"
                         + ("\n".join(linhas) or "| — | nenhuma | — |") + "\n",
                         saida_dir, "lista de issues abertas consultadas pelo gate")

    if abertas:
        return objeto(
            gate="issues", status=STATUS_CONTINUIDADE, continuidade=True,
            mensagem=f"{len(abertas)} issue(s) aberta(s) — pendência conhecida: o pipeline "
                     f"continua (fonte: {fonte})",
            anexos=[anexo], dados={"fonte": fonte, "abertas": len(abertas), "issues": abertas},
            duracao=time.time() - inicio)
    return objeto(
        gate="issues", status=STATUS_SUCESSO,
        mensagem=f"nenhuma issue aberta (fonte: {fonte})",
        anexos=[anexo], dados={"fonte": fonte, "abertas": 0, "issues": []},
        duracao=time.time() - inicio)


def gate_cicd(args, saida_dir: str) -> dict:
    inicio = time.time()
    if args.runs_json:
        with open(args.runs_json, encoding="utf-8") as fh:
            execucoes = json.load(fh)
        fonte = f"fixture {args.runs_json}"
    elif args.sem_gh:
        raise ErroGate("modo --sem-gh exige --runs-json (sem fonte para avaliar o CI)")
    else:
        consulta = ["run", "list", "--limit", "30",
                    "--json", "databaseId,workflowName,status,conclusion,headBranch,url"]
        if args.repo:
            consulta += ["--repo", args.repo]
        execucoes = _rodar_gh(consulta)
        fonte = "gh run list"

    problematicas = [e for e in execucoes
                     if str(e.get("conclusion") or "").lower() in
                     ("failure", "timed_out", "startup_failure", "action_required", "cancelled")
                     and str(e.get("status") or "completed") == "completed"]
    pendentes = [e for e in execucoes if str(e.get("status") or "") in ("in_progress", "queued")]

    linhas = [f"| {e.get('workflowName') or e.get('name')} | {e.get('status')} | "
              f"{e.get('conclusion')} | {e.get('headBranch')} | {e.get('url','')} |"
              for e in execucoes]
    anexo = gravar_anexo("execucoes-ci.md",
                         "# Execuções de CI/CD\n\n| workflow | status | conclusão | branch | url |\n"
                         "| --- | --- | --- | --- | --- |\n"
                         + ("\n".join(linhas) or "| — | — | — | — | — |") + "\n",
                         saida_dir, "execuções de CI recentes consultadas pelo gate")

    dados = {"fonte": fonte, "total": len(execucoes), "com_erro": len(problematicas),
             "em_andamento": len(pendentes),
             "workflows": sorted({str(e.get("workflowName") or e.get("name") or "?")
                                  for e in execucoes})}
    if problematicas:
        nomes = ", ".join(sorted({str(e.get("workflowName") or "?") for e in problematicas}))
        return objeto(
            gate="cicd", status=STATUS_CONTINUIDADE, continuidade=True,
            mensagem=f"{len(problematicas)} execução(ões) de CI com erro ({nomes}) — "
                     "pendência conhecida: o pipeline continua",
            anexos=[anexo], dados={**dados, "execucoes_com_erro": problematicas},
            duracao=time.time() - inicio)
    return objeto(
        gate="cicd", status=STATUS_SUCESSO,
        mensagem=(f"CI sem erros ({len(execucoes)} execução(ões) analisada(s)"
                  + (f", {len(pendentes)} em andamento" if pendentes else "") + f"; fonte: {fonte})"),
        anexos=[anexo], dados=dados, duracao=time.time() - inicio)


def gate_testes(args, saida_dir: str) -> dict:
    inicio = time.time()
    faltando = [a for a in ARQUIVOS_DE_TESTE if not os.path.exists(os.path.join(RAIZ, a))]
    comando = args.comando or COMANDO_TESTES_PADRAO

    if faltando:
        anexo = gravar_anexo("testes-ausentes.md",
                             "# Testes ausentes\n\n" + "\n".join(f"- `{a}`" for a in faltando) + "\n",
                             saida_dir, "arquivos de teste ausentes")
        return objeto(
            gate="testes", status=STATUS_CONTINUIDADE, continuidade=True,
            mensagem=f"sem testes: {len(faltando)} arquivo(s) ausente(s) "
                     f"({', '.join(faltando)}) — pendência conhecida",
            anexos=[anexo], dados={"faltando": faltando, "comando": None},
            duracao=time.time() - inicio)

    codigo, saida = executar(comando)
    anexo = gravar_anexo(f"log-testes-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.txt",
                         f"$ {comando}\n(código de saída: {codigo})\n\n{saida}",
                         saida_dir, "log completo da execução dos testes")
    dados = {"comando": comando, "codigo_saida": codigo,
             "arquivos_testados": ARQUIVOS_DE_TESTE,
             "resumo": [l for l in saida.splitlines() if l.strip().startswith(
                 ("Ran ", "OK", "FAILED", "Resultado"))][-4:]}

    if codigo == 0:
        return objeto(
            gate="testes", status=STATUS_SUCESSO,
            mensagem=f"testes presentes e aprovados (`{comando}`, código 0)",
            anexos=[anexo], dados=dados, duracao=time.time() - inicio)
    return objeto(
        gate="testes", status=STATUS_CONTINUIDADE, continuidade=True,
        mensagem=f"testes reprovados (`{comando}`, código {codigo}) — pendência conhecida: "
                 "o pipeline continua até ficar verde",
        anexos=[anexo], dados=dados, duracao=time.time() - inicio)


def gate_continuidade(args, saida_dir: str) -> dict:
    """Agrega issues + CI + testes na decisão de continuidade.

    Regra do projeto: o gate só é POSITIVO quando não há issue aberta, não há CI
    com erro e existem testes passando. Enquanto não for positivo ⇒ continuidade.
    """
    inicio = time.time()
    parciais, anexos = {}, []

    for nome, funcao, override in (("issues", gate_issues, getattr(args, "status_issues", None)),
                                   ("cicd", gate_cicd, getattr(args, "status_cicd", None)),
                                   ("testes", gate_testes, getattr(args, "status_testes", None))):
        if override is not None:
            # valor vindo de outro job do workflow (encadeamento por `needs`)
            parciais[nome] = objeto(
                gate=nome, status=str(override), continuidade=str(override) == STATUS_CONTINUIDADE,
                mensagem=f"status {override} informado por outro job do pipeline "
                         f"(--status-{nome.lstrip('-')})",
                dados={"origem": "job anterior"})
        else:
            try:
                parciais[nome] = funcao(args, saida_dir)
            except ErroGate as e:
                parciais[nome] = objeto(gate=nome, status=STATUS_INDETERMINADO,
                                        continuidade=False, mensagem=str(e))
        anexos.extend(parciais[nome]["anexos"])

    # contexto: próxima issue do backlog (alimenta o campo next_issue)
    try:
        backlog = ler_backlog(args.backlog)
        proxima = proxima_pendente(backlog)
        contexto_backlog = {"proxima_pendente": (proxima or {}).get("id"),
                            "titulo": (proxima or {}).get("titulo"),
                            "instrucao_teste": (proxima or {}).get("instrucao_teste")}
    except ErroGate as e:
        proxima, contexto_backlog = None, {"erro": str(e)}

    indeterminados = [n for n, p in parciais.items() if p["status"] == STATUS_INDETERMINADO]
    pendentes = [n for n, p in parciais.items() if p["status"] == STATUS_CONTINUIDADE]

    if indeterminados:
        status = STATUS_INDETERMINADO
        continuidade = False
        mensagem = (f"não foi possível avaliar: {', '.join(indeterminados)} — "
                    "exige intervenção (erro tipo 2): "
                    + " | ".join(parciais[n]["mensagem"] for n in indeterminados))
    elif pendentes:
        status = STATUS_CONTINUIDADE
        continuidade = True
        mensagem = ("gate NÃO positivo — continuidade obrigatória. Pendências: "
                    + "; ".join(f"{n} ({parciais[n]['dados'].get('abertas', parciais[n]['dados'].get('com_erro', '?'))})"
                                for n in pendentes))
    else:
        status = STATUS_SUCESSO
        continuidade = False
        mensagem = "gate positivo: nenhuma issue aberta, CI sem erros e testes aprovados"

    dados = {
        "checks": {n: {"status": p["status"], "mensagem": p["mensagem"]} for n, p in parciais.items()},
        "gate_positivo": status == STATUS_SUCESSO,
        "regra": "positivo ⇔ (0 issues abertas) ∧ (CI sem erro) ∧ (testes presentes e verdes)",
        "backlog": contexto_backlog,
    }

    resultado = objeto(
        gate="continuidade", status=status, continuidade=continuidade, mensagem=mensagem,
        next_issue=(proxima or {}).get("id") if continuidade else None,
        anexos=anexos, dados=dados, duracao=time.time() - inicio)

    # anexo consolidado em markdown (resumo humano do veredito)
    resumo_md = [
        "# Veredito do gate de continuidade", "",
        f"- **status:** `{resultado['status']}` "
        f"({'sucesso' if status == '0' else 'continuidade' if status == '1' else 'indeterminado'})",
        f"- **continuidade:** `{str(continuidade).lower()}`",
        f"- **next_issue:** `{resultado['next_issue'] or '—'}`",
        f"- **timestamp:** {resultado['timestamp']}", "",
        "| check | status | mensagem |", "| --- | --- | --- |",
    ]
    for nome, parcial in parciais.items():
        resumo_md.append(f"| {nome} | {parcial['status']} | {parcial['mensagem']} |")
    resultado["anexos"].append(gravar_anexo(
        "veredito-continuidade.md", "\n".join(resumo_md) + "\n", saida_dir,
        "veredito do gate em Markdown (resumo para humanos)"))
    return resultado


# --------------------------------------------------------------------------- #
# gate de execução de issue (instrução → teste → próxima issue)
# --------------------------------------------------------------------------- #


def gate_issue(args, saida_dir: str) -> dict:
    """Executa a instrução de teste da issue e devolve a PRÓXIMA indexada.

    − sucesso testado (código 0): status 0, marca concluída (com --marcar) e o
      `next_issue` passa a ser a próxima pendente, junto com a instrução dela;
    − falha no teste: status 1 (continuidade), `next_issue` = a MESMA issue;
    − issue sem instrução executável: status 2 (precisa de gente).
    """
    inicio = time.time()
    backlog = ler_backlog(args.backlog)
    identificador = args.id or (proxima_pendente(backlog) or {}).get("id")
    if not identificador:
        raise ErroGate("não há issue pendente no backlog e nenhuma foi informada em --id")

    issue = achar_issue(backlog, identificador)
    if issue is None:
        raise ErroGate(f"issue {identificador} não existe no backlog ({args.backlog})")

    instrucao = (issue.get("instrucao_teste") or "").strip()
    if not instrucao:
        return objeto(
            gate="issue", status=STATUS_INDETERMINADO, continuidade=False,
            next_issue=identificador,
            mensagem=f"{identificador} (“{issue.get('titulo')}”) não tem instrucao_teste "
                     "executável — requer decisão humana (erro tipo 2)",
            dados={"issue": issue, "backlog": args.backlog}, duracao=time.time() - inicio)

    codigo, saida = executar(instrucao)
    anexo_log = gravar_anexo(f"{identificador}-log.txt",
                             f"$ {instrucao}\n(código de saída: {codigo})\n\n{saida}",
                             saida_dir, f"log da instrução de teste da {identificador}")
    anexos = [anexo_log]

    if codigo == 0:
        if args.marcar:
            marcar_concluida(backlog, identificador,
                             {"teste": instrucao, "codigo_saida": 0, "quando": agora()})
            with open(args.backlog, "w", encoding="utf-8") as fh:
                json.dump(backlog, fh, ensure_ascii=False, indent=2)
                fh.write("\n")
        # a issue recém-validada não entra como "próxima" (mesmo sem --marcar)
        proxima = proxima_pendente(backlog, excluir=[identificador])
        if proxima:
            guia = [
                f"# Próxima issue: {proxima.get('id')} — {proxima.get('titulo')}", "",
                f"- **entregável:** {proxima.get('entregavel', '—')}",
                f"- **instrução de teste:** `{proxima.get('instrucao_teste') or '—'}`", "",
                "## Como executar", "```bash",
                f"python3 pipeline/gate.py issue --id {proxima.get('id')} --marcar",
                "```", "",
                f"_(depende de: {', '.join(proxima.get('depende_de', []) )or '—'})_",
            ]
            anexos.append(gravar_anexo(f"{identificador}-proxima-issue.md", "\n".join(guia) + "\n",
                                       saida_dir,
                                       f"instrução da issue seguinte ({proxima.get('id')})"))
            mensagem = (f"{identificador} testada com sucesso (código 0) — "
                        f"segue a issue {proxima.get('id')}: {proxima.get('titulo')}"
                        + ("" if args.marcar else
                           " (não marcada: use --marcar para persistir a conclusão no backlog)"))
            next_issue = proxima.get("id")
        else:
            mensagem = (f"{identificador} testada com sucesso (código 0) — backlog sem pendências"
                        + ("" if args.marcar else
                           " (não marcada: use --marcar para persistir a conclusão no backlog)"))
            next_issue = None
        return objeto(
            gate="issue", status=STATUS_SUCESSO, continuidade=bool(proxima),
            mensagem=mensagem, next_issue=next_issue, anexos=anexos,
            dados={"issue": identificador, "teste": instrucao, "codigo_saida": 0,
                   "marcada_concluida": bool(args.marcar), "backlog": args.backlog,
                   "resumo": saida[-1500:]},
            duracao=time.time() - inicio)

    return objeto(
        gate="issue", status=STATUS_CONTINUIDADE, continuidade=True,
        next_issue=identificador,
        mensagem=f"{identificador} ainda não passa (`{instrucao}`, código {codigo}) — "
                 "continuidade: repita/mesma issue até ficar verde",
        anexos=anexos,
        dados={"issue": identificador, "teste": instrucao, "codigo_saida": codigo,
               "backlog": args.backlog, "resumo": saida[-1500:]},
        duracao=time.time() - inicio)


# --------------------------------------------------------------------------- #
# blueprint e situação
# --------------------------------------------------------------------------- #


def gate_blueprint(args, saida_dir: str) -> dict:
    inicio = time.time()
    with open(args.blueprint, encoding="utf-8") as fh:
        planta = json.load(fh)

    falhas = []
    gates_planta = {g["id"] for g in planta.get("gates", [])}
    implementacao = {"issues", "cicd", "testes", "continuidade", "issue"}
    if not gates_planta:
        falhas.append("blueprint sem 'gates'")
    if gates_planta - implementacao:
        falhas.append(f"gates no blueprint sem implementação: {sorted(gates_planta - implementacao)}")
    ligados = set()
    for t in planta.get("transicoes", []):
        for campo in ("de", "para", "quando_status"):
            if campo not in t:
                falhas.append(f"transição sem '{campo}': {t}")
        ligados.add(t.get("de"))
    if gates_planta - ligados - {"fim"}:
        falhas.append(f"gates sem transição de saída: {sorted(gates_planta - ligados - {'fim'})}")

    if falhas:
        anexo = gravar_anexo("blueprint-erros.md", "# Falhas na planta\n\n"
                             + "\n".join(f"- {f}" for f in falhas) + "\n", saida_dir,
                             "falhas de consistência da planta")
        return objeto(gate="blueprint", status=STATUS_INDETERMINADO, continuidade=False,
                      mensagem="blueprint inconsistente: " + "; ".join(falhas),
                      anexos=[anexo], dados={"falhas": falhas}, duracao=time.time() - inicio)

    return objeto(gate="blueprint", status=STATUS_SUCESSO,
                  mensagem=f"planta consistente: {len(gates_planta)} gates, "
                           f"{len(planta.get('transicoes', []))} transições",
                  dados={"gates": sorted(gates_planta),
                         "transicoes": len(planta.get("transicoes", [])),
                         "arquivo": args.blueprint}, duracao=time.time() - inicio)


def gate_situacao(args, saida_dir: str) -> dict:
    """Lê os últimos JSONs gravados e resume a situação do pipeline."""
    inicio = time.time()
    if not os.path.isdir(saida_dir):
        return objeto(gate="situacao", status=STATUS_INDETERMINADO, continuidade=False,
                      mensagem=f"sem histórico: {saida_dir} não existe", duracao=time.time() - inicio)
    ultimos = {}
    for nome in sorted(os.listdir(saida_dir)):
        if not nome.endswith(".json"):
            continue
        with open(os.path.join(saida_dir, nome), encoding="utf-8") as fh:
            try:
                obj = json.load(fh)
            except json.JSONDecodeError:
                continue
        ultimos[obj.get("gate", "?")] = obj

    linhas = ["| gate | status | continuidade | next_issue | quando |",
              "| --- | --- | --- | --- | --- |"]
    for nome, obj in ultimos.items():
        linhas.append(f"| {nome} | {obj.get('status')} | {obj.get('continuidade')} | "
                      f"{obj.get('next_issue') or '—'} | {obj.get('timestamp')} |")
    anexo = gravar_anexo("situacao.md", "# Situação dos gates\n\n" + "\n".join(linhas) + "\n",
                         saida_dir, "tabela com o último resultado de cada gate")
    return objeto(gate="situacao", status=STATUS_SUCESSO,
                  mensagem=f"{len(ultimos)} gate(s) com histórico em {saida_dir}",
                  anexos=[anexo], dados={"ultimos": {k: {"status": v["status"],
                                                         "continuidade": v["continuidade"]}
                                                     for k, v in ultimos.items()}},
                  duracao=time.time() - inicio)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def montar_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gate.py",
        description="Gates do pipeline (JSON sempre no stdout; código de saída = status).",
        epilog="Status: 0=sucesso, 1=erro tipo 1/continuidade, 2=erro tipo 2/indeterminado.")
    p.add_argument("gate", choices=["issues", "cicd", "testes", "continuidade", "issue",
                                    "blueprint", "situacao"])
    p.add_argument("--json-saida", help="arquivo extra para o objeto JSON")
    p.add_argument("--saida-dir", default=os.environ.get("GATE_SAIDA_DIR") or SAIDA_PADRAO)
    p.add_argument("--backlog", default=BACKLOG_PADRAO)
    p.add_argument("--blueprint", default=BLUEPRINT_PADRAO)
    p.add_argument("--repo", default=os.environ.get("GATE_REPO"))
    p.add_argument("--id", help="(gate issue) identificador da issue, ex.: ISSUE-007")
    p.add_argument("--marcar", action="store_true",
                   help="(gate issue) marca a issue como concluída no backlog quando passa")
    p.add_argument("--comando", help=f"(gate testes) comando a executar (padrão: {COMANDO_TESTES_PADRAO})")
    p.add_argument("--issues-json", help="(gates issues/continuidade) fixture de issues abertas")
    p.add_argument("--runs-json", help="(gates cicd/continuidade) fixture de execuções de CI")
    p.add_argument("--sem-gh", action="store_true", help="não chamar gh (usa apenas fixtures)")
    for _nome in ("issues", "cicd", "testes"):
        p.add_argument(f"--status-{_nome}", choices=["0", "1", "2"],
                       help=f"(continuidade) usa este status para '{_nome}' em vez de avaliar "
                            "— encadeamento de jobs do workflow")
    p.add_argument("-q", "--quieto", action="store_true", help="não imprime o JSON no stdout")
    p.add_argument("-V", "--versao", action="version", version=f"gate.py {VERSAO}")
    return p


def main(argv=None) -> int:
    args = montar_parser().parse_args(argv)
    funcoes = {"issues": gate_issues, "cicd": gate_cicd, "testes": gate_testes,
               "continuidade": gate_continuidade, "issue": gate_issue,
               "blueprint": gate_blueprint, "situacao": gate_situacao}
    try:
        resultado = funcoes[args.gate](args, args.saida_dir)
    except ErroGate as e:
        resultado = objeto(gate=args.gate, status=STATUS_INDETERMINADO, continuidade=False,
                           mensagem=f"erro tipo 2: {e}")
    except subprocess.TimeoutExpired:
        resultado = objeto(gate=args.gate, status=STATUS_INDETERMINADO, continuidade=False,
                           mensagem="erro tipo 2: tempo limite excedido na execução")
    except FileNotFoundError as e:
        resultado = objeto(gate=args.gate, status=STATUS_INDETERMINADO, continuidade=False,
                           mensagem=f"erro tipo 2: arquivo não encontrado ({e})")

    if args.saida_dir:
        resultado["anexos"].append(gravar(resultado, args.saida_dir))
    if args.json_saida:
        os.makedirs(os.path.dirname(os.path.abspath(args.json_saida)), exist_ok=True)
        with open(args.json_saida, "w", encoding="utf-8") as fh:
            json.dump(resultado, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    if not args.quieto:
        print(json.dumps(resultado, ensure_ascii=False, indent=2))
    return int(resultado["status"])


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass
    sys.exit(main())
