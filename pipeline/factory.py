#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""factory.py — fábrica de issues event-driven do pipeline gate-driven (BPMN).

A fábrica transforma EVENTOS (push, CI, execução de gate, chegada de demanda) em
ISSUES INDEXADAS conforme o padrão declarado no blueprint (pipeline/blueprint.json).
É orientada a objetos e persiste tudo em SQLite (`pipeline/fabrica.db`), mantendo o
`pipeline/backlog.json` como espelho versionável (export/import).

Classes (todas com responsabilidade única):

    ArmazenamentoSqlite  — conexão, esquema, migração                        (POO)
    Evento               — fato observado (tipo, payload, quando)
    Issue                — entidade do backlog (id, instrução de teste, de
                           desenvolvimento, status, dependências, evidencias)
    ModeloIssue          — modelo do padrão BPMN: campos obrigatórios, formato do
                           id e instrução de desenvolvimento padrão
    PadraoBPMN           — lê/valida o blueprint.json e sintetiza a próxima issue
    Backlog              — coleção de issues (ordenar, proxima_pendente, achar, …)
    Repositorio          — repositório/fachada: persistência + consultas (JSON ⇄ SQLite)
    Fabrica              — orquestra: entradas → eventos → issues → backlog → gate-driven

Uso pela CLI (mesmo contrato JSON dos gates):

    python3 pipeline/factory.py --evento "issue_aberta|refs=…|titulo=…"
    python3 pipeline/factory.py --sincronizar           # backlog.json ⇄ SQLite
    python3 pipeline/factory.py --proxima               # sintetiza a próxima indexada
    python3 pipeline/factory.py --listar                # tabela de issues e eventos
    python3 pipeline/factory.py --exportar F --importar F

Requisitos: Python 3.8+ (biblioteca padrão: sqlite3, json, argparse).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone

VERSAO = "1.0.0"
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANCO_PADRAO = os.path.join(RAIZ, "pipeline", "fabrica.db")
BACKLOG_PADRAO = os.path.join(RAIZ, "pipeline", "backlog.json")
BLUEPRINT_PADRAO = os.path.join(RAIZ, "pipeline", "blueprint.json")

# campos do padrão (blueprint.modelo_issue.campos + os operacionais da fábrica)
CAMPOS_ISSUE = ["id", "indice", "titulo", "entregavel", "instrucao_teste",
                "instrucao_desenvolvimento", "status", "depende_de", "origem",
                "criada_em", "concluida_em", "evidencias"]
STATUS_VALIDOS = {"pendente", "concluida", "completada", "bloqueada", "cancelada"}
STATUS_ENCERRADOS = {"concluida", "completada", "done"}

# classes públicas da fábrica (usadas na verificação do gate `fabrica`)
CLASSES = ["ArmazenamentoSqlite", "Evento", "Issue", "ModeloIssue", "PadraoBPMN",
           "Backlog", "Repositorio", "Fabrica"]

SCHEMA = """
CREATE TABLE IF NOT EXISTS schema_info (
    chave TEXT PRIMARY KEY,
    valor TEXT NOT NULL
) STRICT;
CREATE TABLE IF NOT EXISTS issues (
    id                       TEXT PRIMARY KEY,
    indice                   INTEGER NOT NULL,
    titulo                   TEXT NOT NULL,
    entregavel               TEXT NOT NULL DEFAULT '',
    instrucao_teste          TEXT,
    instrucao_desenvolvimento TEXT NOT NULL,
    status                   TEXT NOT NULL DEFAULT 'pendente',
    depende_de               TEXT NOT NULL DEFAULT '[]',
    origem                   TEXT NOT NULL DEFAULT '',
    criada_em                TEXT NOT NULL,
    concluida_em             TEXT,
    evidencias               TEXT NOT NULL DEFAULT '[]'
) STRICT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_issues_indice ON issues (indice);
CREATE TABLE IF NOT EXISTS eventos (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    tipo      TEXT NOT NULL,
    payload   TEXT NOT NULL DEFAULT '{}',
    quando    TEXT NOT NULL
) STRICT;
"""


class ErroFabrica(Exception):
    """Falha de regra (padrão violado, dependência ausente, banco inválido) → erro tipo 2."""


class ErroContinuidade(ErroFabrica):
    """Pendência CONHECIDA e tratável (ex.: issue em andamento) → erro tipo 1.

    Não é falha: é a ordem do fluxo — conclua a issue em curso (fix/debug) e a
    fábrica constrói a próxima indexada. `continuidade = true`.
    """


def agora() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _json_ou(valor, padrao):
    try:
        return json.loads(valor) if isinstance(valor, str) else valor
    except (json.JSONDecodeError, TypeError):
        return padrao


# --------------------------------------------------------------------------- #
# 1. armazenamento (POO)
# --------------------------------------------------------------------------- #


class ArmazenamentoSqlite:
    """Conexão com o SQLite, criação/migração do esquema e transações."""

    def __init__(self, caminho: str = BANCO_PADRAO):
        self.caminho = caminho
        self.conn = sqlite3.connect(caminho)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA journal_mode = WAL")
        self.conn.execute("PRAGMA foreign_keys = ON")
        self.migrar()

    def migrar(self) -> None:
        self.conn.executescript(SCHEMA)
        self.conn.execute(
            "INSERT INTO schema_info (chave, valor) VALUES ('versao', ?) "
            "ON CONFLICT(chave) DO UPDATE SET valor = excluded.valor", (VERSAO,))
        self.conn.commit()

    def tabelas(self) -> list:
        return [r["name"] for r in self.conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name")]

    def inserir(self, tabela: str, dados: dict) -> None:
        colunas = ", ".join(dados)
        valores = ", ".join("?" for _ in dados)
        self.conn.execute(f"INSERT INTO {tabela} ({colunas}) VALUES ({valores})",
                          tuple(dados.values()))
        self.conn.commit()

    def atualizar(self, tabela: str, chave: str, identificador: str, dados: dict) -> int:
        atribuicoes = ", ".join(f"{c} = ?" for c in dados)
        cursor = self.conn.execute(
            f"UPDATE {tabela} SET {atribuicoes} WHERE {chave} = ?",
            (*dados.values(), identificador))
        self.conn.commit()
        return cursor.rowcount

    def consultar(self, sql: str, parametros=()) -> list:
        return [dict(r) for r in self.conn.execute(sql, parametros)]

    def fechar(self) -> None:
        self.conn.close()


# --------------------------------------------------------------------------- #
# 2. entidades (POO)
# --------------------------------------------------------------------------- #


@dataclass
class Evento:
    """Fato observado que a fábrica transforma em issue."""
    tipo: str
    payload: dict = field(default_factory=dict)
    quando: str = field(default_factory=agora)


@dataclass
class Issue:
    """Issue do backlog (entidade única — igual no SQLite e no backlog.json)."""
    id: str
    indice: int
    titulo: str
    entregavel: str
    instrucao_teste: str
    instrucao_desenvolvimento: str
    status: str = "pendente"
    depende_de: list = field(default_factory=list)
    origem: str = ""
    criada_em: str = field(default_factory=agora)
    concluida_em: str = None
    evidencias: list = field(default_factory=list)

    # -- conversão ---------------------------------------------------------- #
    def para_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def de_dict(cls, dados: dict) -> "Issue":
        campos = {c: dados.get(c) for c in CAMPOS_ISSUE if c in dados}
        campos.setdefault("id", dados.get("id", ""))
        campos["indice"] = int(campos.get("indice") or cls.indice_do_id(campos["id"]))
        campos["depende_de"] = list(campos.get("depende_de") or [])
        campos["evidencias"] = list(campos.get("evidencias") or [])
        campos.setdefault("status", "pendente")
        campos.setdefault("entregavel", "")
        campos.setdefault("origem", "")
        campos.setdefault("criada_em", agora())
        campos.setdefault("instrucao_teste", None)
        campos.setdefault("instrucao_desenvolvimento", "")
        return cls(**campos)

    @staticmethod
    def indice_do_id(identificador: str) -> int:
        m = re.search(r"(\d+)$", str(identificador or ""))
        return int(m.group(1)) if m else 0

    # -- comportamento ------------------------------------------------------ #
    def concluida(self) -> bool:
        return str(self.status).lower() in STATUS_ENCERRADOS

    def pendente(self) -> bool:
        return not self.concluida()

    def validar(self, exigir_instrucao: bool = True) -> None:
        if not re.fullmatch(r"ISSUE-\d{3,}", str(self.id)):
            raise ErroFabrica(f"id fora do padrão ISSUE-NNN: {self.id!r}")
        if self.indice <= 0:
            raise ErroFabrica(f"{self.id}: índice inválido ({self.indice})")
        if not str(self.titulo).strip():
            raise ErroFabrica(f"{self.id}: título obrigatório")
        if exigir_instrucao and not str(self.instrucao_desenvolvimento).strip():
            raise ErroFabrica(
                f"{self.id}: instrucao_desenvolvimento obrigatória (padrão do blueprint) — "
                "é a direção de continuidade que a fábrica entrega para a execução")
        if str(self.status).lower() not in STATUS_VALIDOS:
            raise ErroFabrica(f"{self.id}: status inválido ({self.status})")

    def concluir(self, evidencias: dict) -> None:
        self.status = "concluida"
        self.concluida_em = agora()
        self.evidencias = list(self.evidencias) + [evidencias]

    def __str__(self) -> str:
        return f"{self.id} [{self.status}] {self.titulo}"


class Backlog:
    """Coleção de issues — ordenação, busca e próxima pendente."""

    def __init__(self, issues=None):
        self.issues = [i if isinstance(i, Issue) else Issue.de_dict(i)
                       for i in (issues or [])]

    def __len__(self) -> int:
        return len(self.issues)

    def __iter__(self):
        return iter(self.ordenadas())

    def ordenadas(self) -> list:
        return sorted(self.issues, key=lambda i: i.indice)

    def achar(self, identificador: str) -> Issue | None:
        for item in self.issues:
            if item.id == identificador:
                return item
        return None

    def proxima_pendente(self, excluir=None) -> Issue | None:
        ignorar = set(excluir or ())
        for item in self.ordenadas():
            if item.id in ignorar or item.concluida():
                continue
            return item
        return None

    def proximo_indice(self) -> int:
        return max((i.indice for i in self.issues), default=0) + 1

    def ids_sem_instrucao_desenvolvimento(self) -> list:
        return [i.id for i in self.ordenadas()
                if not str(i.instrucao_desenvolvimento).strip()]

    def resumo_por_status(self) -> dict:
        contagem = {}
        for item in self.ordenadas():
            contagem[item.status] = contagem.get(item.status, 0) + 1
        return contagem

    def adicionar(self, issue: Issue) -> Issue:
        issue.validar()
        if self.achar(issue.id):
            raise ErroFabrica(f"issue duplicada: {issue.id}")
        ausentes = [d for d in issue.depende_de if not self.achar(d)]
        if ausentes:
            raise ErroFabrica(f"{issue.id} depende de issue inexistente: {ausentes}")
        self.issues.append(issue)
        return issue

    def para_dict(self) -> dict:
        return {"issues": [i.para_dict() for i in self.ordenadas()]}


# --------------------------------------------------------------------------- #
# 3. padrão (BPMN) e fábrica de issues
# --------------------------------------------------------------------------- #


class ModeloIssue:
    """Modelo declarado no blueprint: campos obrigatórios, formato do id e instrução padrão."""

    def __init__(self, dados: dict):
        self.bruto = dict(dados or {})
        self.campos = list(self.bruto.get("campos") or CAMPOS_ISSUE)
        self.formato = self.bruto.get("formato_id", "ISSUE-NNN")
        self.dependencia_padrao = list(self.bruto.get("dependencia_padrao") or ["anterior"])
        self.instrucao_padrao = self.bruto.get(
            "instrucao_desenvolvimento_padrao",
            "executar/entregar; `make testes`; `python3 pipeline/gate.py issue --marcar`")

    def validar(self, exigir_instrucao: bool = True) -> None:
        if "id" not in self.campos or "instrucao_desenvolvimento" not in self.campos:
            raise ErroFabrica("blueprint.modelo_issue.campos precisa conter 'id' e "
                              "'instrucao_desenvolvimento' (padrão da fábrica)")
        if "{indice:03d}" not in self.formato:
            raise ErroFabrica("blueprint.modelo_issue.formato_id deve usar {indice:03d}")

    def id_de(self, indice: int) -> str:
        return self.formato.format(indice=indice)

    def modelo(self, indice: int, titulo: str, entregavel: str, instrucao_teste,
               instrucao_desenvolvimento: str, depende_de=None, origem: str = "",
               anterior: str = None) -> Issue:
        """Sintetiza uma issue conforme o padrão (o coração da fábrica)."""
        dependencias = list(depende_de) if depende_de is not None else \
            [anterior] if (anterior and "anterior" in self.dependencia_padrao) else []
        return Issue(
            id=self.id_de(indice), indice=indice, titulo=titulo, entregavel=entregavel,
            instrucao_teste=(instrucao_teste or None),
            instrucao_desenvolvimento=(str(instrucao_desenvolvimento).strip()
                                       or self.instrucao_padrao),
            depende_de=[d for d in dependencias if d], origem=origem)


class PadraoBPMN:
    """Lê o blueprint.json e expõe o modelo de issue + a fábrica de instruções."""

    def __init__(self, caminho: str = BLUEPRINT_PADRAO):
        self.caminho = caminho
        try:
            with open(caminho, encoding="utf-8") as fh:
                self.planta = json.load(fh)
        except FileNotFoundError:
            raise ErroFabrica(f"blueprint não encontrado: {caminho}")
        except json.JSONDecodeError as e:
            raise ErroFabrica(f"blueprint inválido (JSON): {e}")
        self.modelo_issue = ModeloIssue(self.planta.get("modelo_issue") or {})
        self.gates = [g.get("id") for g in self.planta.get("gates", [])]
        self.gatilhos = self.planta.get("gatilhos_github_actions") or {}

    def validar(self, exigir_instrucao: bool = True) -> None:
        if not self.gates:
            raise ErroFabrica("blueprint sem 'gates' — planta incompleta")
        if not self.planta.get("modelo_issue"):
            raise ErroFabrica("blueprint sem 'modelo_issue' — a fábrica não tem padrão para seguir")
        self.modelo_issue.validar()

    # fábrica de instruções: o que a próxima issue pede, em ordem de execução
    def instrucoes(self) -> list:
        return list(self.planta.get("modelo_issue", {}).get("instrucoes_de_desenvolvimento", []))

    def direcao(self) -> dict:
        return dict(self.planta.get("instrucao_proxima_issue") or {})

    def modelo(self, indice: int, titulo: str, entregavel: str = "", instrucao_teste=None,
               instrucao_desenvolvimento: str = "", depende_de=None, origem="",
               anterior: str = None) -> Issue:
        """Sintetiza a próxima issue indexada conforme o padrão do blueprint."""
        if not self.esta_valido():
            self.validar()
        padrao = self.modelo_issue
        texto = instrucao_desenvolvimento or " / ".join(self.instrucoes())
        return padrao.modelo(
            indice=indice, titulo=titulo or f"pendência {indice} (gerada pela fábrica)",
            entregavel=entregavel, instrucao_teste=instrucao_teste,
            instrucao_desenvolvimento=texto, depende_de=depende_de, origem=origem,
            anterior=anterior)

    def esta_valido(self) -> bool:
        """True quando a planta traz gates e o modelo de issue do padrão."""
        return bool(self.modelo_issue.campos) and bool(self.gates)


# --------------------------------------------------------------------------- #
# 4. repositório (persistência: JSON ⇄ SQLite)
# --------------------------------------------------------------------------- #

COLUNAS_SQLITE = ["id", "indice", "titulo", "entregavel", "instrucao_teste",
                  "instrucao_desenvolvimento", "status", "depende_de", "origem",
                  "criada_em", "concluida_em", "evidencias"]


class Repositorio:
    """Fachada de persistência: SQLite como fonte de verdade, backlog.json como espelho."""

    def __init__(self, banco: str = BANCO_PADRAO):
        self.armazenamento = ArmazenamentoSqlite(banco)
        self.banco = banco

    # -- issues ------------------------------------------------------------- #
    def salvar_issue(self, issue: Issue, exigir_instrucao: bool = True) -> Issue:
        issue.validar(exigir_instrucao=exigir_instrucao)
        if self.armazenamento.consultar("SELECT id FROM issues WHERE id = ?", (issue.id,)):
            raise ErroFabrica(f"issue já existe no banco: {issue.id}")
        dados = issue.para_dict()
        dados["depende_de"] = json.dumps(dados["depende_de"], ensure_ascii=False)
        dados["evidencias"] = json.dumps(dados["evidencias"], ensure_ascii=False)
        self.armazenamento.inserir("issues", {c: dados[c] for c in COLUNAS_SQLITE})
        return issue

    def atualizar_issue(self, issue: Issue) -> int:
        dados = issue.para_dict()
        dados["depende_de"] = json.dumps(dados["depende_de"], ensure_ascii=False)
        dados["evidencias"] = json.dumps(dados["evidencias"], ensure_ascii=False)
        return self.armazenamento.atualizar(
            "issues", "id", issue.id, {c: dados[c] for c in COLUNAS_SQLITE if c != "id"})

    def listar_issues(self, status=None) -> list:
        sql = "SELECT * FROM issues"
        parametros = ()
        if status:
            sql += " WHERE status = ?"
            parametros = (status,)
        sql += " ORDER BY indice"
        return [self._issue_de_linha(l) for l in self.armazenamento.consultar(sql, parametros)]

    def proxima_pendente(self) -> Issue | None:
        linhas = self.armazenamento.consultar(
            "SELECT * FROM issues WHERE lower(status) NOT IN ('concluida','completada','done') "
            "ORDER BY indice")
        return self._issue_de_linha(linhas[0]) if linhas else None

    def proximo_indice(self) -> int:
        linhas = self.armazenamento.consultar("SELECT COALESCE(MAX(indice), 0) AS m FROM issues")
        return int(linhas[0]["m"]) + 1

    def backlog(self) -> Backlog:
        return Backlog(self.listar_issues())

    def _issue_de_linha(self, linha: dict) -> Issue:
        dados = dict(linha)
        dados["depende_de"] = _json_ou(dados.get("depende_de"), [])
        dados["evidencias"] = _json_ou(dados.get("evidencias"), [])
        return Issue.de_dict(dados)

    # -- eventos ------------------------------------------------------------ #
    def registrar_evento(self, evento: Evento) -> int:
        self.armazenamento.inserir("eventos", {
            "tipo": evento.tipo,
            "payload": json.dumps(evento.payload, ensure_ascii=False),
            "quando": evento.quando})
        return len(self.listar_eventos())

    def listar_eventos(self, tipo=None) -> list:
        sql = "SELECT * FROM eventos"
        parametros = ()
        if tipo:
            sql += " WHERE tipo = ?"
            parametros = (tipo,)
        sql += " ORDER BY id"
        return [{"tipo": e["tipo"], "payload": _json_ou(e["payload"], {}),
                 "quando": e["quando"]}
                for e in self.armazenamento.consultar(sql, parametros)]

    # -- espelho backlog.json ----------------------------------------------- #
    def sincronizar_backlog(self, caminho: str = BACKLOG_PADRAO) -> int:
        """Importa um backlog.json para o SQLite (idempotente) e devolve quantas entraram."""
        try:
            with open(caminho, encoding="utf-8") as fh:
                dados = json.load(fh)
        except FileNotFoundError:
            raise ErroFabrica(f"backlog não encontrado: {caminho}")
        except json.JSONDecodeError as e:
            raise ErroFabrica(f"backlog inválido (JSON): {e}")
        existentes = {i.id for i in self.listar_issues()}
        entraram = 0
        for bruto in dados.get("issues", []):
            issue = Issue.de_dict(bruto)
            if issue.id in existentes:
                self.atualizar_issue(issue)
            else:
                # importação é tolerante: issue sem instrução entra e o gate `fabrica`
                # aponta a pendência (status 1) em vez de recusar o backlog inteiro
                self.salvar_issue(issue, exigir_instrucao=False)
                entraram += 1
        return entraram

    def exportar_backlog(self, caminho: str = BACKLOG_PADRAO, metadados=None) -> str:
        base = {"nome": "backlog do projeto — consulta processual DataJud/DJEN",
                "gerado_por": f"pipeline/factory.py {VERSAO} (SQLite ⇄ backlog.json)",
                "gerado_em": agora(),
                "issues": [i.para_dict() for i in self.listar_issues()]}
        base.update(metadados or {})
        os.makedirs(os.path.dirname(os.path.abspath(caminho)), exist_ok=True)
        with open(caminho, "w", encoding="utf-8") as fh:
            json.dump(base, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        return caminho

    def tabelas(self) -> list:
        return self.armazenamento.tabelas()


# --------------------------------------------------------------------------- #
# 5. fábrica (orquestração event-driven)
# --------------------------------------------------------------------------- #


class Fabrica:
    """Transforma eventos em issues indexadas, conforme o padrão do blueprint (BPMN)."""

    HANDLERS = {
        "demanda": "titulo",
        "issue_aberta": "refs",
        "ci_falhou": "run",
        "teste_falhou": "comando",
        "gate_falhou": "gate",
        "checkpoint": "fase",
    }

    def __init__(self, repositorio: Repositorio, padrao: PadraoBPMN):
        self.repositorio = repositorio
        self.padrao = padrao

    # -- leitura ------------------------------------------------------------ #
    def backlog(self) -> Backlog:
        return self.repositorio.backlog()

    def proxima_pendente(self) -> Issue | None:
        return self.backlog().proxima_pendente()

    def em_desenvolvimento(self) -> Issue | None:
        """Issue realmente EM ANDAMENTO (status 'pendente').

        Uma issue 'bloqueada' está estacionada aguardando decisão humana e NÃO
        congela a fábrica — senão uma decisão pendente pararia o desenvolvimento.
        """
        for issue in self.backlog().ordenadas():
            if str(issue.status).lower() == "pendente":
                return issue
        return None

    # -- fábrica de issues -------------------------------------------------- #
    def construir_proxima(self, anterior: Issue = None, titulo=None, entregavel="",
                           instrucao_teste=None, instrucao_desenvolvimento="",
                           origem="fábrica (próxima indexada)") -> Issue:
        """Constrói a PRÓXIMA issue indexada conforme o padrão BPMN."""
        backlog = self.backlog()
        indice = backlog.proximo_indice()
        em_curso = self.em_desenvolvimento()
        if em_curso is not None:
            raise ErroContinuidade(
                f"a {em_curso.id} ainda está pendente (não foi COMPLETADA com sucesso "
                "testado) — a fábrica constrói a próxima indexada só depois do sucesso "
                "dela; issues 'bloqueadas' (decisão humana) não travam a construção")
        anterior = anterior or None
        issue = self.padrao.modelo(
            indice=indice, titulo=titulo, entregavel=entregavel,
            instrucao_teste=instrucao_teste,
            instrucao_desenvolvimento=instrucao_desenvolvimento or self.direcao(),
            origem=origem, anterior=(anterior.id if anterior else None))
        if not issue.depende_de and anterior is not None:
            issue.depende_de = [anterior.id]
        backlog.adicionar(issue)
        self.repositorio.salvar_issue(issue)
        return issue

    # -- event-driven ------------------------------------------------------- #
    def processar_evento(self, evento: Evento, construir=True) -> dict:
        """Converte um evento em issue (se o padrão pedir) e registra o evento.

        Se a issue anterior já estiver COMPLETADA, o evento gera a PRÓXIMA indexada;
        se ainda houver pendência, ele apenas registra a direção de continuidade.
        """
        if evento.tipo not in self.HANDLERS:
            raise ErroFabrica(f"evento sem handler no padrão: {evento.tipo!r} "
                              f"(conhecidos: {', '.join(sorted(self.HANDLERS))})")
        self.repositorio.registrar_evento(evento)
        pendente = self.proxima_pendente()

        acao_gate = self._gate_do_evento(evento)
        if pendente is not None and pendente.pendente():
            return {"acao": "continuar", "direcao": acao_gate,
                    "issue": pendente.id, "pendente": pendente.para_dict(),
                    "instrucao_desenvolvimento": pendente.instrucao_desenvolvimento,
                    "instrucao_teste": pendente.instrucao_teste,
                    "motivo": "há pendência aberta: a fábrica mantém a MESMA issue "
                              "até o sucesso testado"}
        if not construir:
            return {"acao": "registrado", "issue": None, "direcao": "continuar",
                    "motivo": "evento registrado; construção da próxima desativada"}

        nova = self.construir_proxima(titulo=evento.payload.get("titulo"))
        return {"acao": "construida", "direcao": "proxima", "issue": nova.id,
                "nova": nova.para_dict(), "evento": evento.tipo,
                "instrucao_desenvolvimento": nova.instrucao_desenvolvimento,
                "instrucao_teste": nova.instrucao_teste}

    def instrutir_pendentes(self, instrucao: str = "") -> list:
        """Cria/atualiza a instrução de desenvolvimento de TODA issue que não tem uma.

        É o que garante o pedido "instrução a cada issue pendente necessária para
        concluir o desenvolvimento": cada issue passa a dizer, em ordem, o que
        fazer para ser concluída — e a fábrica entrega essa instrução junto da issue.
        """
        padrao = instrucao.strip() or self.direcao()
        atualizadas = []
        for issue in self.repositorio.listar_issues():
            if str(issue.instrucao_desenvolvimento or "").strip():
                continue
            issue.instrucao_desenvolvimento = padrao
            self.repositorio.atualizar_issue(issue)
            self.repositorio.registrar_evento(Evento(
                "instrucao_criada", {"issue": issue.id, "instrucao": padrao}))
            atualizadas.append(issue.id)
        return atualizadas

    def marcar_concluida(self, identificador: str, evidencias: dict) -> Issue:
        issue = self.backlog().achar(identificador)
        if issue is None:
            raise ErroFabrica(f"issue não encontrada: {identificador}")
        issue.concluir(evidencias)
        self.repositorio.atualizar_issue(issue)
        self.repositorio.registrar_evento(Evento(
            "issue_completada", {"issue": identificador, **evidencias}))
        return issue

    # -- direção de continuidade ------------------------------------------- #
    def direcao(self) -> str:
        """Instrução de desenvolvimento que a fábrica entrega junto de cada issue."""
        instrucoes = self.padrao.instrucoes()
        if instrucoes:
            return " / ".join(instrucoes)
        return ("executar a instrução de teste; corrigir até passar; "
                "`python3 pipeline/gate.py issue --marcar`")

    def instrucao_proxima(self, proxima: Issue = None) -> dict:
        """Bloco padronizado de direção de continuidade (+ nudge de compactação)."""
        proxima = proxima or self.proxima_pendente()
        bloco = dict(self.padrao.direcao())
        bloco["next_issue"] = (proxima.id if proxima else None)
        bloco["instrucao_desenvolvimento"] = (proxima.instrucao_desenvolvimento
                                              if proxima else self.direcao())
        bloco["instrucao_teste"] = proxima.instrucao_teste if proxima else None
        bloco["comando"] = (f"python3 pipeline/gate.py issue --id {proxima.id} --marcar"
                            if proxima else "python3 pipeline/gate.py situacao")
        return bloco

    def _gate_do_evento(self, evento: Evento) -> str:
        if evento.tipo == "ci_falhou":
            return "depurar"
        if evento.tipo in ("teste_falhou", "gate_falhou"):
            return "corrigir"
        return "continuar"

    # -- objeto JSON do contrato (mesmo formato dos gates) ------------------ #
    def objeto(self, resultado: dict, status: str, mensagem: str, anexos=None,
               next_issue=None, continuidade=None, dados=None, duracao=0.0) -> dict:
        if continuidade is None:
            continuidade = status == "1"
        return {
            "id": f"gate-fabrica-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
                  f"-{os.urandom(2).hex()}",
            "gate": "fabrica",
            "status": str(status),
            "codigo_saida": int(status),
            "mensagem": str(mensagem),
            "continuidade": bool(continuidade),
            "next_issue": next_issue,
            "direcao": resultado.get("direcao", "humano" if str(status) == "2" else "continuar"),
            "proximo_passo": (f"python3 pipeline/gate.py issue --id {next_issue} --marcar"
                              if next_issue else "python3 pipeline/gate.py situacao"),
            "anexos": [a for a in (anexos or [])],
            "dados": dados or {},
            "timestamp": agora(),
            "duracao_s": round(duracao, 3),
            "versao": VERSAO,
        }


# --------------------------------------------------------------------------- #
# 6. CLI (mesmo contrato dos gates: JSON no stdout, exit code = status)
# --------------------------------------------------------------------------- #


def _anexo(nome: str, conteudo: str, saida_dir: str, descricao: str) -> dict:
    os.makedirs(saida_dir, exist_ok=True)
    caminho = os.path.join(saida_dir, nome)
    with open(caminho, "w", encoding="utf-8") as fh:
        fh.write(conteudo)
    return {"path": caminho, "filename": os.path.basename(caminho), "descricao": descricao}


def _evento_de_texto(texto: str) -> Evento:
    """Interpreta --evento "tipo|chave=valor|chave=valor"."""
    partes = [p.strip() for p in str(texto).split("|")]
    tipo = partes[0]
    payload = {}
    for parte in partes[1:]:
        if "=" in parte:
            chave, valor = parte.split("=", 1)
            payload[chave.strip()] = valor.strip()
    return Evento(tipo=tipo, payload=payload)


def montar_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="factory.py",
        description="Fábrica de issues event-driven do pipeline (SQLite + POO + BPMN).",
        epilog='Exemplo: python3 pipeline/factory.py --evento "issue_aberta|refs=#3|titulo=Continuidade"')
    p.add_argument("--evento", action="append", default=[],
                   help='evento no formato "tipo|chave=valor|…" (repetível)')
    p.add_argument("--sincronizar", action="store_true",
                   help="importa backlog.json para o SQLite (idempotente)")
    p.add_argument("--exportar", help="regera o backlog.json a partir do SQLite")
    p.add_argument("--importar", help="importa um backlog.json para o SQLite")
    p.add_argument("--proxima", action="store_true",
                   help="constrói a próxima issue indexada (exige a anterior COMPLETADA)")
    p.add_argument("--concluir", help="marca uma issue como COMPLETADA (sucesso testado)")
    p.add_argument("--instruir", action="store_true",
                   help="cria a instrução de desenvolvimento de toda issue que não tem uma")
    p.add_argument("--listar", action="store_true", help="lista issues e eventos")
    p.add_argument("--titulo", default=None, help="(--proxima) título da issue a construir")
    p.add_argument("--banco", default=os.environ.get("FABRICA_BANCO") or BANCO_PADRAO)
    p.add_argument("--backlog", default=BACKLOG_PADRAO)
    p.add_argument("--blueprint", default=BLUEPRINT_PADRAO)
    p.add_argument("--saida-dir", default=os.environ.get("GATE_SAIDA_DIR")
                   or os.path.join(RAIZ, "pipeline", "saida"))
    p.add_argument("--json-saida", help="grava o objeto JSON também neste arquivo")
    p.add_argument("-q", "--quieto", action="store_true", help="não imprime o JSON")
    p.add_argument("-V", "--versao", action="version", version=f"factory.py {VERSAO}")
    return p


def main(argv=None) -> int:
    args = montar_parser().parse_args(argv)
    inicio = time.time()
    anexos, resultados = [], []
    contruida = None
    try:
        padrao = PadraoBPMN(args.blueprint)
        padrao.validar()
        repositorio = Repositorio(args.banco)
        fabrica = Fabrica(repositorio, padrao)

        if args.importar:
            entraram = repositorio.sincronizar_backlog(args.importar)
            resultados.append(f"importadas {entraram} issue(s) de {args.importar}")
        if args.sincronizar:
            entraram = repositorio.sincronizar_backlog(args.backlog)
            resultados.append(f"sincronizado: {entraram} issue(s) nova(s) de {args.backlog}")

        for texto in args.evento:
            evento = _evento_de_texto(texto)
            saida = fabrica.processar_evento(evento)
            resultados.append(f"evento {evento.tipo} → {saida['acao']}"
                              + (f" ({saida['issue']})" if saida.get("issue") else ""))
            if saida["acao"] == "construida":
                contruida = saida["nova"]

        if args.instruir:
            atualizadas = fabrica.instrutir_pendentes()
            resultados.append(f"instrução de desenvolvimento criada para "
                              f"{len(atualizadas)} issue(s): {', '.join(atualizadas) or '—'}")
            if args.exportar:
                pass  # a exportação acontece logo abaixo, já com as instruções

        if args.concluir:
            issue = fabrica.marcar_concluida(args.concluir,
                                             {"sucesso": "COMPLETADA", "quando": agora()})
            resultados.append(f"{issue.id} COMPLETADA")

        if args.proxima:
            concluidas = [i for i in fabrica.backlog().ordenadas() if i.concluida()]
            anterior = concluidas[-1] if concluidas else None
            contruida = fabrica.construir_proxima(anterior=anterior, titulo=args.titulo)
            resultados.append(f"construída {contruida.id}: {contruida.titulo} "
                              f"(depende de {', '.join(contruida.depende_de) or '—'})")

        if args.exportar:
            caminho = repositorio.exportar_backlog(args.exportar)
            resultados.append(f"backlog exportado: {caminho}")

        if args.listar:
            backlog = fabrica.backlog()
            linhas = [f"| {i.id} | {i.indice} | {i.status} | {i.titulo} | "
                      f"{', '.join(i.depende_de) or '—'} |" for i in backlog.ordenadas()]
            md = ("# Fábrica de issues\n\n"
                  f"- issues: {len(backlog)} — {json.dumps(backlog.resumo_por_status(), ensure_ascii=False)}\n"
                  f"- tabelas: {', '.join(repositorio.tabelas())}\n"
                  f"- eventos: {len(repositorio.listar_eventos())}\n\n"
                  "| id | índice | status | título | depende de |\n| --- | --- | --- | --- | --- |\n"
                  + ("\n".join(linhas) or "| — | — | — | — | — |") + "\n")
            anexos.append(_anexo("fabrica-estado.md", md, args.saida_dir,
                                 "estado da fábrica (issues + eventos + esquema)"))
            resultados.append(f"listadas {len(backlog)} issue(s), "
                              f"{len(repositorio.listar_eventos())} evento(s)")

        if not resultados:
            resultados.append("nada a fazer: use --evento/--sincronizar/--listar/"
                              "--proxima/--instruir/--exportar (veja --help)")

        backlog = fabrica.backlog()
        proxima = backlog.proxima_pendente()
        resultado = {"direcao": "continuar"}
        objeto = fabrica.objeto(
            resultado, status="0",
            mensagem="fábrica executada: " + "; ".join(resultados),
            anexos=anexos, next_issue=(proxima.id if proxima else None),
            continuidade=bool(proxima),
            dados={"resultados": resultados, "banco": args.banco,
                   "tabelas": repositorio.tabelas(),
                   "issues": len(backlog), "status": backlog.resumo_por_status(),
                   "eventos": len(repositorio.listar_eventos()),
                   "nova_issue": contruida.para_dict() if contruida else None,
                   "direcao": fabrica.instrucao_proxima(proxima),
                   "blueprint": args.blueprint},
            duracao=time.time() - inicio)
    except ErroContinuidade as e:
        pendente = None
        try:
            em_curso = fabrica.em_desenvolvimento()
            pendente = em_curso.id if em_curso else None
        except Exception:
            pass
        objeto = {"id": f"gate-fabrica-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}",
                  "gate": "fabrica", "status": "1", "codigo_saida": 1,
                  "mensagem": f"continuidade: {e}", "continuidade": True,
                  "next_issue": pendente, "direcao": "corrigir",
                  "proximo_passo": (f"python3 pipeline/gate.py issue --id {pendente} --marcar"
                                    if pendente else "python3 pipeline/gate.py fabrica"),
                  "anexos": [], "dados": {"motivo": str(e)}, "timestamp": agora(),
                  "duracao_s": round(time.time() - inicio, 3), "versao": VERSAO}
    except (sqlite3.Error, OSError) as e:
        objeto = {"id": f"gate-fabrica-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}",
                  "gate": "fabrica", "status": "2", "codigo_saida": 2,
                  "mensagem": f"erro tipo 2: banco/arquivo inacessível "
                              f"({e.__class__.__name__}: {str(e)[:200]})",
                  "continuidade": False, "next_issue": None, "direcao": "humano",
                  "proximo_passo": "conferir o caminho do banco (--banco) e permissões",
                  "anexos": [], "dados": {}, "timestamp": agora(),
                  "duracao_s": round(time.time() - inicio, 3), "versao": VERSAO}
    except ErroFabrica as e:
        objeto = {"id": f"gate-fabrica-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}",
                  "gate": "fabrica", "status": "2", "codigo_saida": 2,
                  "mensagem": f"erro tipo 2: {e}", "continuidade": False,
                  "next_issue": None, "direcao": "humano",
                  "proximo_passo": "revisar a fábrica/blueprint (decisão humana)",
                  "anexos": [], "dados": {}, "timestamp": agora(),
                  "duracao_s": round(time.time() - inicio, 3), "versao": VERSAO}

    try:
        os.makedirs(args.saida_dir, exist_ok=True)
        registro = os.path.join(args.saida_dir, f"{objeto['id']}.json")
        with open(registro, "w", encoding="utf-8") as fh:
            json.dump(objeto, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        objeto["anexos"].append({"path": registro, "filename": os.path.basename(registro),
                                 "descricao": "objeto JSON do gate fabrica"})
    except OSError:
        pass
    if args.json_saida:
        os.makedirs(os.path.dirname(os.path.abspath(args.json_saida)), exist_ok=True)
        with open(args.json_saida, "w", encoding="utf-8") as fh:
            json.dump(objeto, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
    if not args.quieto:
        print(json.dumps(objeto, ensure_ascii=False, indent=2))
    return int(objeto["status"])


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass
    sys.exit(main())
