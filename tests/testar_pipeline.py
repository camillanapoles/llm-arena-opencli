#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Testes do pipeline de gates (pipeline/gate.py, blueprint, backlog e workflow).

Roda 100% offline: as consultas ao `gh` são substituídas por fixtures
(`--issues-json`/`--runs-json`) e as instruções de teste usam comandos triviais.

Uso:  python3 tests/testar_pipeline.py
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "pipeline"))

import contextlib  # noqa: E402
import io  # noqa: E402
import urllib.error  # noqa: E402
from unittest import mock  # noqa: E402

import verificar_cnj  # noqa: E402  (pipeline/verificar_cnj.py)

import gate  # noqa: E402  (módulo do pipeline)

GATE = os.path.join(RAIZ, "pipeline", "gate.py")
BACKLOG = os.path.join(RAIZ, "pipeline", "backlog.json")
BLUEPRINT = os.path.join(RAIZ, "pipeline", "blueprint.json")
WORKFLOW = os.path.join(RAIZ, ".github", "workflows", "gates.yml")

CHAVES_OBRIGATORIAS = {"id", "gate", "status", "mensagem", "next_issue", "anexos",
                       "continuidade", "codigo_saida", "dados", "timestamp", "versao",
                       "direcao", "proximo_passo"}
DIRECOES_VALIDAS = {"continuar", "corrigir", "depurar", "proxima", "encerrar", "humano"}


def rodar(*argumentos, saida_dir=None):
    """Executa o gate.py e devolve (código_de_saída, objeto_json, stdout_bruto)."""
    cmd = [sys.executable, GATE, *argumentos]
    if saida_dir:
        cmd += ["--saida-dir", saida_dir]
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=RAIZ)
    try:
        obj = json.loads(proc.stdout)
    except json.JSONDecodeError:
        obj = None
    return proc.returncode, obj, proc.stdout + proc.stderr


def blocos_run(texto: str) -> list:
    """Extrai os blocos `run: |` de um workflow (para validar o bash embutido)."""
    linhas, blocos, i = texto.splitlines(), [], 0
    while i < len(linhas):
        m = re.match(r"^(\s+)run: \|\s*$", linhas[i])
        if m:
            indent = len(m.group(1))
            corpo, j = [], i + 1
            while j < len(linhas) and (not linhas[j].strip()
                                       or len(linhas[j]) - len(linhas[j].lstrip()) > indent):
                corpo.append(linhas[j])
                j += 1
            base = min((len(l) - len(l.lstrip()) for l in corpo if l.strip()), default=0)
            blocos.append("\n".join(l[base:] for l in corpo))
            i = j
        else:
            i += 1
    return blocos


def fixture(pasta, nome, conteudo):
    caminho = os.path.join(pasta, nome)
    with open(caminho, "w", encoding="utf-8") as fh:
        json.dump(conteudo, fh, ensure_ascii=False)
    return caminho


class CasoBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.saida = os.path.join(self.dir, "saida")

    def tearDown(self):
        self.tmp.cleanup()


class TesteContrato(CasoBase):
    """O objeto JSON do contrato precisa ser igual em TODOS os gates."""

    def test_chaves_obrigatorias_e_tipos(self):
        for argumentos in (["blueprint"], ["issues", "--sem-gh"], ["situacao"]):
            codigo, obj, bruto = rodar(*argumentos, saida_dir=self.saida)
            with self.subTest(gate=argumentos[0]):
                self.assertIsNotNone(obj, f"saída não é JSON: {bruto[:200]}")
                self.assertTrue(CHAVES_OBRIGATORIAS <= set(obj), "faltam chaves do contrato")
                self.assertIsInstance(obj["id"], str)
                self.assertTrue(obj["id"].startswith("gate-"))
                self.assertIn(obj["status"], {"0", "1", "2"}, "status é string 0/1/2")
                self.assertIsInstance(obj["mensagem"], str)
                self.assertIsInstance(obj["continuidade"], bool)
                self.assertIsInstance(obj["anexos"], list)
                self.assertIsInstance(obj["dados"], dict)
                self.assertIn(obj["direcao"], DIRECOES_VALIDAS, "direção de continuidade")
                self.assertIsInstance(obj["proximo_passo"], str)
                self.assertTrue(obj["proximo_passo"].strip(), "sempre há um próximo passo")
                for anexo in obj["anexos"]:
                    self.assertEqual({"path", "filename", "descricao"}, set(anexo))

    def test_codigo_de_saida_igual_ao_status(self):
        casos = [(["blueprint"], "0"), (["issues", "--sem-gh"], "2")]
        for argumentos, esperado in casos:
            codigo, obj, _ = rodar(*argumentos, saida_dir=self.saida)
            with self.subTest(gate=argumentos[0]):
                self.assertEqual(obj["status"], esperado)
                self.assertEqual(codigo, int(esperado), "exit code deve espelhar o status")
                self.assertEqual(obj["codigo_saida"], codigo)

    def test_anexos_gravados_no_disco(self):
        codigo, obj, _ = rodar("blueprint", saida_dir=self.saida)
        for anexo in obj["anexos"]:
            self.assertTrue(os.path.exists(anexo["path"]), f"anexo ausente: {anexo}")
            self.assertEqual(anexo["filename"], os.path.basename(anexo["path"]))

    def test_json_saida_grava_arquivo(self):
        destino = os.path.join(self.dir, "resultado.json")
        codigo, obj, _ = rodar("blueprint", "--json-saida", destino, saida_dir=self.saida)
        self.assertTrue(os.path.exists(destino))
        with open(destino, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh)["status"], obj["status"])


class TesteGateIssues(CasoBase):
    def test_com_issue_aberta_e_continuidade(self):
        fx = fixture(self.dir, "issues.json", [
            {"number": 3, "title": "SESSION CONTINUITY CONTROL", "url": "https://x/3"}])
        codigo, obj, _ = rodar("issues", "--issues-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertEqual(obj["dados"]["abertas"], 1)
        self.assertIn("continua", obj["mensagem"])

    def test_sem_issue_aberta_e_sucesso(self):
        fx = fixture(self.dir, "issues.json", [])
        codigo, obj, _ = rodar("issues", "--issues-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("0", 0, False))
        self.assertIsNone(obj["next_issue"])

    def test_sem_fonte_e_erro_tipo_2(self):
        codigo, obj, _ = rodar("issues", "--sem-gh", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("2", 2, False))


class TesteGateCicd(CasoBase):
    def test_ci_com_erro_e_continuidade(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 1, "workflowName": "ci", "status": "completed",
             "conclusion": "failure", "headBranch": "main", "url": "https://x/1"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertEqual(obj["dados"]["com_erro"], 1)

    def test_ci_limpo_e_sucesso(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 1, "workflowName": "ci", "status": "completed",
             "conclusion": "success", "headBranch": "main", "url": "https://x/1"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))

    def test_execucao_em_andamento_nao_e_erro(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 2, "workflowName": "gates", "status": "in_progress",
             "conclusion": None, "headBranch": "x", "url": "https://x/2"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
        self.assertEqual(obj["status"], "0")
        self.assertEqual(obj["dados"]["em_andamento"], 1)

    def test_erro_antigo_superado_por_verde_nao_e_pendencia(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 10, "workflowName": "gates", "status": "completed",
             "conclusion": "failure", "headBranch": "b", "url": "https://x/10"},
            {"databaseId": 11, "workflowName": "gates", "status": "completed",
             "conclusion": "success", "headBranch": "b", "url": "https://x/11"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0), "veredito é o da execução mais recente")
        self.assertEqual(obj["dados"]["com_erro"], 0)
        self.assertEqual(obj["dados"]["historicos_com_erro"], 1)

    def test_verde_antigo_com_erro_recente_e_pendencia(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 20, "workflowName": "gates", "status": "completed",
             "conclusion": "success", "headBranch": "b", "url": "https://x/20"},
            {"databaseId": 21, "workflowName": "gates", "status": "completed",
             "conclusion": "failure", "headBranch": "b", "url": "https://x/21"}])
        codigo, obj, _ = rodar("cicd", "--runs-json", fx, "--saida-dir", self.saida)
        self.assertEqual((obj["status"], obj["direcao"]), ("1", "depurar"))
        self.assertEqual(obj["dados"]["execucoes_com_erro"][0]["databaseId"], 21)

    def test_conclusoes_problematicas_detectadas(self):
        for conclusao in ("failure", "timed_out", "startup_failure", "action_required", "cancelled"):
            fx = fixture(self.dir, f"runs-{conclusao}.json", [
                {"databaseId": 3, "workflowName": "ci", "status": "completed",
                 "conclusion": conclusao, "headBranch": "x", "url": "https://x/3"}])
            codigo, obj, _ = rodar("cicd", "--runs-json", fx, saida_dir=self.saida)
            with self.subTest(conclusao=conclusao):
                self.assertEqual(obj["status"], "1", f"{conclusao} deveria ser erro de CI")


class TesteGateTestes(CasoBase):
    def test_comando_que_passa(self):
        codigo, obj, _ = rodar("testes", "--comando", "true", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertIn("aprovados", obj["mensagem"])

    def test_comando_que_falha_e_continuidade(self):
        codigo, obj, _ = rodar("testes", "--comando", "exit 3", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertEqual(obj["dados"]["codigo_saida"], 3)
        log = [a for a in obj["anexos"] if a["filename"].startswith("log-testes")]
        self.assertTrue(log, "o gate precisa anexar o log dos testes")
        self.assertIn("código de saída: 3", open(log[0]["path"], encoding="utf-8").read())


class TesteGateContinuidade(CasoBase):
    def test_pendencia_em_qualquer_check_vira_continuidade(self):
        codigo, obj, _ = rodar("continuidade", "--status-issues", "1", "--status-cicd", "0",
                               "--status-testes", "0", "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("1", 1, True))
        self.assertIsNotNone(obj["next_issue"], "com pendência deve apontar a próxima issue")
        self.assertIn("NÃO positivo", obj["mensagem"])
        self.assertFalse(obj["dados"]["gate_positivo"])

    def test_tudo_limpo_vira_sucesso(self):
        codigo, obj, _ = rodar("continuidade", "--status-issues", "0", "--status-cicd", "0",
                               "--status-testes", "0", "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("0", 0, False))
        self.assertIsNone(obj["next_issue"])
        self.assertTrue(obj["dados"]["gate_positivo"])

    def test_indeterminado_propaga_erro_tipo_2(self):
        codigo, obj, _ = rodar("continuidade", "--status-issues", "2", "--status-cicd", "0",
                               "--status-testes", "0", "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("2", 2, False))
        self.assertIn("intervenção", obj["mensagem"])

    def test_regra_documentada_no_objeto(self):
        _, obj, _ = rodar("continuidade", "--status-issues", "0", "--status-cicd", "0",
                          "--status-testes", "0", "--saida-dir", self.saida)
        self.assertIn("positivo", obj["dados"]["regra"])

    def test_anexo_do_veredito_em_markdown(self):
        _, obj, _ = rodar("continuidade", "--status-issues", "1", "--status-cicd", "0",
                          "--status-testes", "0", "--saida-dir", self.saida)
        veredito = [a for a in obj["anexos"] if a["filename"] == "veredito-continuidade.md"]
        self.assertTrue(veredito, "falta o anexo do veredito")
        texto = open(veredito[0]["path"], encoding="utf-8").read()
        self.assertIn("continuidade", texto)
        self.assertIn("| issues |", texto)


class TesteGateIssue(CasoBase):
    def _backlog(self, itens):
        return fixture(self.dir, "backlog.json", {"nome": "teste", "issues": itens})

    def test_sucesso_entrega_a_proxima_indexada(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "primeira", "instrucao_teste": "true", "status": "pendente"},
            {"id": "ISSUE-002", "titulo": "segunda", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, "--id", "ISSUE-001",
                               "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["next_issue"]), ("0", 0, "ISSUE-002"))
        self.assertTrue(obj["continuidade"], "há próxima pendente ⇒ continuidade")
        guias = [a for a in obj["anexos"] if a["filename"].endswith("proxima-issue.md")]
        self.assertTrue(guias, "deve anexar a instrução da issue seguinte")
        self.assertIn("ISSUE-002", open(guias[0]["path"], encoding="utf-8").read())

    def test_falha_mantem_a_mesma_issue(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "quebrada", "instrucao_teste": "exit 7", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, "--id", "ISSUE-001",
                               "--saida-dir", self.saida)
        self.assertEqual((obj["status"], codigo, obj["next_issue"]), ("1", 1, "ISSUE-001"))
        self.assertTrue(obj["continuidade"])
        log = open([a for a in obj["anexos"] if a["filename"].endswith("-log.txt")][0]["path"],
                   encoding="utf-8").read()
        self.assertIn("código de saída: 7", log)

    def test_issue_sem_instrucao_e_erro_tipo_2(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "sem instrução", "instrucao_teste": None,
             "status": "bloqueada"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo, obj["continuidade"]), ("2", 2, False))
        self.assertIn("instrucao_teste", obj["mensagem"])

    def test_ultima_pendente_encerra_o_pipeline(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "única", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual((obj["status"], obj["next_issue"], obj["continuidade"]), ("0", None, False))

    def test_marcar_concluida_atualiza_o_backlog(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "a", "instrucao_teste": "true", "status": "pendente"},
            {"id": "ISSUE-002", "titulo": "b", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, "--id", "ISSUE-001",
                               "--marcar", saida_dir=self.saida)
        with open(caminho, encoding="utf-8") as fh:
            dados = json.load(fh)
        primeira = dados["issues"][0]
        self.assertEqual(primeira["status"], "concluida")
        self.assertIn("concluida_em", primeira)
        self.assertTrue(primeira["evidencias"])
        self.assertTrue(obj["dados"]["marcada_concluida"])

    def test_sem_marcar_nao_altera_o_backlog(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "a", "instrucao_teste": "true", "status": "pendente"}])
        antes = open(caminho, encoding="utf-8").read()
        rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual(antes, open(caminho, encoding="utf-8").read())

    def test_bloqueada_nao_congela_o_gate_issue(self):
        # 007 bloqueada (decisão humana) + 008 pendente: o gate executa a EXECUTÁVEL
        itens = [{"id": "ISSUE-007", "indice": 7, "status": "bloqueada", "titulo": "decisão"},
                 {"id": "ISSUE-008", "indice": 8, "status": "pendente", "titulo": "executável",
                  "instrucao_teste": "true"}]
        backlog = {"issues": itens}
        codigo, obj, bruto = rodar("issue", "--backlog", self._backlog(itens),
                                   "--saida-dir", self.saida)
        self.assertEqual(obj["status"], "0", bruto[:200])
        self.assertEqual(obj["dados"]["issue"], "ISSUE-008",
                         "a bloqueada não é a próxima ação do gate")
        self.assertEqual(gate.proxima_executavel(backlog)["id"], "ISSUE-008")
        # sem nenhuma pendente, a bloqueada volta a ser a resposta (falta gente)
        self.assertEqual(gate.proxima_executavel({"issues": itens[:1]})["id"], "ISSUE-007")
        self.assertIsNone(gate.proxima_executavel({"issues": []}))

    def test_escolhe_a_proxima_pendente_sem_id(self):
        caminho = self._backlog([
            {"id": "ISSUE-001", "titulo": "feita", "instrucao_teste": "true", "status": "concluida"},
            {"id": "ISSUE-002", "titulo": "próxima", "instrucao_teste": "true", "status": "pendente"}])
        codigo, obj, _ = rodar("issue", "--backlog", caminho, saida_dir=self.saida)
        self.assertEqual(obj["dados"]["issue"], "ISSUE-002")


class TesteBlueprintEBacklog(CasoBase):
    def test_blueprint_do_projeto_e_consistente(self):
        codigo, obj, _ = rodar("blueprint", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertEqual(obj["dados"]["gates"],
                         ["cicd", "continuidade", "fabrica", "issue", "issues", "testes"])

    def test_blueprint_inconsistente_e_erro_tipo_2(self):
        caminho = fixture(self.dir, "planta.json", {
            "gates": [{"id": "issues"}, {"id": "gate-fantasma"}],
            "transicoes": [{"de": "issues", "para": "fim", "quando_status": "0"}]})
        codigo, obj, _ = rodar("blueprint", "--blueprint", caminho, saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("2", 2))
        self.assertIn("sem implementação", obj["mensagem"])

    def test_backlog_do_projeto_e_integro(self):
        with open(BACKLOG, encoding="utf-8") as fh:
            backlog = json.load(fh)
        ids, numeros = [], []
        for item in backlog["issues"]:
            ids.append(item["id"])
            numeros.append(int(re.search(r"(\d+)$", item["id"]).group(1)))
            self.assertIn(item["status"], {"concluida", "pendente", "bloqueada"}, item["id"])
            self.assertTrue(item["titulo"].strip(), item["id"])
            self.assertTrue(item["entregavel"].strip(), item["id"])
            instrucao = item.get("instrucao_teste")
            if instrucao:
                for arquivo in re.findall(r"[\w/\.\-]+\.(?:py|sh)", instrucao):
                    self.assertTrue(os.path.exists(os.path.join(RAIZ, arquivo)),
                                    f"{item['id']}: instrução aponta para {arquivo} inexistente")
        self.assertEqual(len(ids), len(set(ids)), "ids duplicados no backlog")
        self.assertEqual(numeros, list(range(1, len(numeros) + 1)),
                         "ids devem ser sequenciais (ISSUE-001, ISSUE-002, …)")

    def test_funcoes_do_modulo(self):
        backlog = gate.ler_backlog(BACKLOG)
        proxima = gate.proxima_pendente(backlog)
        self.assertIsNotNone(proxima, "o backlog precisa manter a próxima pendência")
        abertas = [i for i in gate.ordenar(backlog["issues"])
                   if str(i.get("status", "")).lower()
                   not in ("concluida", "completada", "done")]
        self.assertEqual(proxima["id"], abertas[0]["id"],
                         "a próxima pendência é a primeira issue aberta na ordem indexada")
        bagunçado = [{"id": "ISSUE-010", "status": "pendente"},
                     {"id": "ISSUE-002", "status": "concluida"},
                     {"id": "ISSUE-007", "status": "pendente"}]
        self.assertEqual([i["id"] for i in gate.ordenar(bagunçado)],
                         ["ISSUE-002", "ISSUE-007", "ISSUE-010"], "ordenação por índice")
        self.assertEqual(gate.proxima_pendente({"issues": bagunçado})["id"], "ISSUE-007")
        self.assertEqual(gate.proxima_pendente({"issues": bagunçado}, excluir=["ISSUE-007"])["id"],
                         "ISSUE-010", "issue validada não deve voltar como próxima")
        self.assertNotEqual(gate.novo_id("x"), gate.novo_id("x"), "id deve ser único")


class TesteDirecaoDeContinuidade(CasoBase):
    def test_sucesso_encaminha_para_a_proxima(self):
        caminho = fixture(self.dir, "backlog.json", {"issues": [
            {"id": "ISSUE-001", "titulo": "a", "instrucao_teste": "true", "status": "pendente"},
            {"id": "ISSUE-002", "titulo": "b", "instrucao_teste": "true", "status": "pendente"}]})
        _, obj, _ = rodar("issue", "--backlog", caminho, "--id", "ISSUE-001",
                          "--saida-dir", self.saida)
        self.assertEqual(obj["direcao"], "proxima")
        self.assertIn("ISSUE-002", obj["proximo_passo"])

    def test_falha_encaminha_para_corrigir_a_mesma(self):
        caminho = fixture(self.dir, "backlog.json", {"issues": [
            {"id": "ISSUE-001", "titulo": "a", "instrucao_teste": "exit 9",
             "status": "pendente"}]})
        _, obj, _ = rodar("issue", "--backlog", caminho, "--saida-dir", self.saida)
        self.assertEqual(obj["direcao"], "corrigir")
        self.assertIn("--id ISSUE-001", obj["proximo_passo"])

    def test_ci_com_erro_encaminha_para_depurar(self):
        fx = fixture(self.dir, "runs.json", [
            {"databaseId": 1, "workflowName": "gates", "status": "completed",
             "conclusion": "failure", "headBranch": "x", "url": "https://x"}])
        _, obj, _ = rodar("cicd", "--runs-json", fx, "--saida-dir", self.saida)
        self.assertEqual(obj["direcao"], "depurar")
        self.assertIn("gh run", obj["proximo_passo"])

    def test_indeterminado_encaminha_para_humano(self):
        _, obj, _ = rodar("issues", "--sem-gh", "--saida-dir", self.saida)
        self.assertEqual(obj["direcao"], "humano")

    def test_gate_positivo_encerra(self):
        _, obj, _ = rodar("continuidade", "--status-issues", "0", "--status-cicd", "0",
                          "--status-testes", "0", "--saida-dir", self.saida)
        self.assertEqual(obj["direcao"], "encerrar")

    def test_funcao_direcao_de(self):
        self.assertEqual(gate.direcao_de("testes", "1"), "corrigir")
        self.assertEqual(gate.direcao_de("issue", "0", next_issue="ISSUE-002"), "proxima")
        self.assertEqual(gate.direcao_de("issue", "0", next_issue=None), "encerrar")
        self.assertEqual(gate.direcao_de("fabrica", "2"), "humano")


class TesteGateFabricaNoFluxo(CasoBase):
    def test_gate_fabrica_consta_dos_arquivos_de_teste_do_gate_testes(self):
        self.assertIn("tests/testar_fabrica.py", gate.ARQUIVOS_DE_TESTE)

    def test_gate_fabrica_responde_no_contrato(self):
        codigo, obj, bruto = rodar("fabrica", "--saida-dir", self.saida)
        self.assertIsNotNone(obj, bruto[:300])
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertEqual(obj["gate"], "fabrica")

    def test_workflow_tem_o_job_da_fabrica(self):
        with open(WORKFLOW, encoding="utf-8") as fh:
            texto = fh.read()
        self.assertRegex(texto, r"(?m)^\s{2}gate-fabrica:")


class RespostaFalsa:
    """Resposta HTTP mínima (mesma interface usada por urllib)."""

    def __init__(self, status=200, corpo=b"{}"):
        self.status = status
        self._corpo = corpo

    def read(self):
        return self._corpo

    def __enter__(self):
        return self

    def __exit__(self, *argumentos):
        return False


class TesteVerificarCNJ(unittest.TestCase):
    """A instrução executável da ISSUE-006: 200/taxa/chave/rede → 0/1/2 (offline)."""

    def _rodar(self, efeito):
        if isinstance(efeito, Exception):
            alvo = mock.patch.object(verificar_cnj.urllib.request, "urlopen",
                                     side_effect=efeito)
        else:
            alvo = mock.patch.object(verificar_cnj.urllib.request, "urlopen",
                                     return_value=efeito)
        with alvo:
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                codigo = verificar_cnj.main(["--timeout", "1"])
        return codigo, json.loads(buffer.getvalue())

    def test_200_e_sucesso_com_direcao_proxima(self):
        resposta = RespostaFalsa(200, json.dumps(
            {"took": 7, "hits": {"total": {"value": 1234567}}}).encode())
        codigo, obj = self._rodar(resposta)
        self.assertEqual((codigo, obj["status"]), (0, "0"))
        self.assertEqual(obj["dados"]["total"], 1234567)
        self.assertEqual(obj["direcao"], "proxima")
        self.assertIn("--marcar", obj["proximo_passo"])
        self.assertIsNone(obj["next_issue"])
        self.assertFalse(obj["continuidade"])

    def test_429_e_continuidade_com_retry_after(self):
        erro = urllib.error.HTTPError("https://x", 429, "Too Many Requests", None, None)
        with mock.patch.object(verificar_cnj.urllib.request, "urlopen", side_effect=erro):
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                codigo = verificar_cnj.main(["--timeout", "1"])
        obj = json.loads(buffer.getvalue())
        self.assertEqual((codigo, obj["status"]), (1, "1"))
        self.assertIn("429", obj["mensagem"])
        self.assertIn("120 req/min", obj["mensagem"])
        self.assertEqual(obj["direcao"], "continuar")
        self.assertEqual(obj["next_issue"], "ISSUE-006")
        self.assertTrue(obj["continuidade"])

    def test_401_e_erro_tipo_2_humano(self):
        erro = urllib.error.HTTPError("https://x", 401, "Unauthorized", None, None)
        codigo, obj = self._rodar(erro)
        self.assertEqual((codigo, obj["status"]), (2, "2"))
        self.assertEqual(obj["direcao"], "humano")
        self.assertIn("chave", obj["mensagem"])
        self.assertFalse(obj["continuidade"])

    def test_rede_indisponivel_e_continuidade(self):
        codigo, obj = self._rodar(urllib.error.URLError("sem rota"))
        self.assertEqual((codigo, obj["status"]), (1, "1"))
        self.assertEqual(obj["direcao"], "continuar")

    def test_contrato_completo(self):
        codigo, obj = self._rodar(urllib.error.URLError("sem rota"))
        for chave in ("id", "gate", "status", "codigo_saida", "mensagem", "continuidade",
                      "next_issue", "direcao", "proximo_passo", "anexos", "dados",
                      "timestamp", "versao"):
            self.assertIn(chave, obj, f"falta {chave} no contrato")
        self.assertIsInstance(obj["status"], str)
        self.assertIsInstance(obj["mensagem"], str)
        self.assertIsInstance(obj["anexos"], list)


class TesteWorkflowValidacaoCNJ(unittest.TestCase):
    """O workflow event-driven da validação AO VIVO (ISSUE-006) no runner do GitHub."""

    def setUp(self):
        caminho = os.path.join(RAIZ, ".github", "workflows", "validacao-cnj.yml")
        with open(caminho, encoding="utf-8") as fh:
            self.texto = fh.read()

    def test_disparado_por_evento(self):
        for gatilho in ("push:", "pull_request:", "schedule:", "workflow_dispatch:"):
            self.assertIn(gatilho, self.texto, f"falta o gatilho {gatilho}")
        self.assertRegex(self.texto, r"cron: \"0 11 \* \* 1-5\"")

    def test_roda_a_instrucao_da_issue_006_com_retentativas(self):
        self.assertIn("pipeline/verificar_cnj.py", self.texto)
        self.assertIn("TENTATIVAS", self.texto)
        self.assertIn("for tentativa in", self.texto)
        self.assertIn('sleep "$espera"', self.texto)

    def test_mapeia_status_0_1_2_para_acao(self):
        self.assertIn('if [ "$status" = "2" ]', self.texto)
        self.assertIn("::error::", self.texto)
        self.assertIn('if [ "$status" = "1" ]', self.texto)
        self.assertIn("::warning::", self.texto)
        self.assertIn("::notice::", self.texto)

    def test_sucesso_conclui_a_pendencia_e_constroi_a_proxima(self):
        self.assertIn('--concluir "$issue"', self.texto)
        self.assertIn("--proxima", self.texto)
        self.assertIn("--exportar pipeline/backlog.json", self.texto)
        self.assertIn("[skip ci]", self.texto, "o commit do bot não re-dispara o workflow")
        self.assertNotIn("--concluir ISSUE-006", self.texto,
                         "a issue concluída não pode ser fixa: quem decide é a pendência do backlog")

    def test_conclusao_e_dirigida_pela_pendencia_real(self):
        self.assertIn("--pendencia-ao-vivo", self.texto)
        self.assertIn("prova_ao_vivo", self.texto)
        self.assertIn("steps.pendencia.outputs.prova_ao_vivo == 'true'", self.texto)
        self.assertIn(").lower())", self.texto,
                      "o output precisa ser 'true'/'false' — o Python imprime True/False "
                      "e o if: do GitHub compara com a string minúscula")

    def test_conclusao_que_nao_acontece_nao_deixa_o_job_vermelho(self):
        self.assertIn("steps.concluir.outputs.status == '0'", self.texto,
                      "o commit do backlog só acontece com a conclusão concluída")
        self.assertIn("a próxima indexada só nasce depois do sucesso testado", self.texto)
        bloco = self.texto[self.texto.index("Fábrica · concluir a pendência provada"):]
        bloco = bloco[:bloco.index("Continuidade ·")]
        self.assertIn("set +e", bloco, "status 1 = continuidade, não erro")

    def test_pendencia_nao_provada_nao_cria_issue(self):
        self.assertIn("steps.pendencia.outputs.prova_ao_vivo != 'true'", self.texto)
        self.assertIn('--evento "checkpoint|', self.texto,
                      "registra o evento de continuidade sem construir issue nova")

    def test_nao_commita_em_pull_request(self):
        self.assertIn("github.event_name != 'pull_request'", self.texto)

    def test_job_de_conclusao_depende_da_validacao(self):
        self.assertRegex(self.texto, r"(?m)^\s{2}concluir-pendencia:")
        self.assertIn("needs: [validacao-cnj]", self.texto)

    def test_evidencia_aponta_para_a_execucao(self):
        self.assertIn("github.run_id", self.texto)
        self.assertIn("--evidencia", self.texto)

    def test_guarda_de_json_invalido(self):
        self.assertIn("[ ! -s /tmp/validacao-cnj.json ]", self.texto)

    def test_backoff_respeita_retry_after_do_cnj(self):
        self.assertIn("retry_after", self.texto)
        self.assertIn("sleep \"$espera\"", self.texto)
        self.assertIn("espera=150", self.texto, "teto de espera por tentativa")

    def test_diagnostico_usa_o_mesmo_caminho_do_validador(self):
        self.assertIn("urllib", self.texto)
        self.assertIn("CHAVE_PADRAO", self.texto)

    def test_yaml_valido_quando_houver_pyyaml(self):
        try:
            import yaml  # type: ignore
        except ImportError:
            self.skipTest("PyYAML indisponível — a validação definitiva é o GitHub Actions")
        dados = yaml.safe_load(self.texto)
        self.assertIn("jobs", dados)
        self.assertEqual(set(dados["jobs"]), {"validacao-cnj", "concluir-pendencia"})

    def test_blocos_run_sao_bash_valido(self):
        blocos = blocos_run(self.texto)
        self.assertGreaterEqual(len(blocos), 4)
        for numero, corpo in enumerate(blocos, 1):
            seguro = re.sub(r"\$\{\{[^}]*\}\}", "VALOR", corpo)
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
                fh.write(seguro)
                caminho = fh.name
            try:
                proc = subprocess.run(["bash", "-n", caminho], capture_output=True, text=True)
            finally:
                os.unlink(caminho)
            self.assertEqual(proc.returncode, 0,
                             f"bloco run #{numero} inválido: {proc.stderr[:200]}")

    def test_yaml_estrutural(self):
        self.assertNotIn("\t", self.texto)
        for linha in self.texto.splitlines():
            if re.match(r'^\s*[A-Za-z0-9_.\-\$\{\}/" ]+\s*:', linha) and not linha.lstrip().startswith("#"):
                indent = len(linha) - len(linha.lstrip(" "))
                self.assertEqual(indent % 2, 0, f"indentação ímpar: {linha!r}")


class TesteSituacao(CasoBase):
    def test_situacao_resume_o_historico(self):
        rodar("blueprint", saida_dir=self.saida)
        rodar("issues", "--issues-json", fixture(self.dir, "i.json", []), saida_dir=self.saida)
        codigo, obj, _ = rodar("situacao", saida_dir=self.saida)
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertIn("blueprint", obj["dados"]["ultimos"])
        self.assertIn("issues", obj["dados"]["ultimos"])


class TesteWorkflow(unittest.TestCase):
    def setUp(self):
        with open(WORKFLOW, encoding="utf-8") as fh:
            self.texto = fh.read()

    def test_gatilhos_exigidos(self):
        for gatilho in ("push:", "pull_request:", "issues:", "schedule:", "workflow_dispatch:"):
            self.assertIn(gatilho, self.texto, f"falta o gatilho {gatilho}")

    def test_cinco_gates_encadeados(self):
        for job in ("gate-issues", "gate-cicd", "gate-testes", "gate-continuidade", "executa-issue"):
            self.assertRegex(self.texto, rf"(?m)^\s{{2}}{job}:", f"falta o job {job}")
        self.assertRegex(self.texto, r"needs: \[gate-issues, gate-cicd, gate-testes\]")

    def test_jobs_chamam_o_executor(self):
        chamadas = re.findall(r"python3 pipeline/gate\.py (\w+)", self.texto)
        for gate_nome in ("issues", "cicd", "testes", "continuidade", "issue"):
            self.assertIn(gate_nome, chamadas, f"o job do gate {gate_nome} não chama gate.py")

    def test_publica_json_resumo_e_artefatos(self):
        self.assertIn("GITHUB_STEP_SUMMARY", self.texto)
        self.assertIn("actions/upload-artifact", self.texto)
        self.assertIn("--json-saida", self.texto)
        self.assertIn("GATE_SAIDA_DIR", self.texto)

    def test_status_2_derruba_o_job(self):
        self.assertIn('if [ "$status" = "2" ]; then', self.texto)
        self.assertIn("exit 1", self.texto)

    def test_blocos_run_sao_bash_valido(self):
        """Valida de verdade o shell embutido no YAML (sem depender de PyYAML)."""
        blocos = blocos_run(self.texto)
        self.assertGreaterEqual(len(blocos), 6, "esperado um bloco run: por job")
        for numero, corpo in enumerate(blocos, 1):
            seguro = re.sub(r"\$\{\{[^}]*\}\}", "VALOR", corpo)  # expressões do Actions
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
                fh.write(seguro)
                caminho = fh.name
            try:
                proc = subprocess.run(["bash", "-n", caminho], capture_output=True, text=True)
            finally:
                os.unlink(caminho)
            self.assertEqual(proc.returncode, 0,
                             f"bloco run #{numero} não é bash válido: {proc.stderr[:200]}")

    def test_fabrica_no_fluxo(self):
        self.assertIn("pipeline/gate.py fabrica", self.texto)
        self.assertIn("pipeline/factory.py", self.texto)
        self.assertIn("--status-fabrica", self.texto)
        self.assertIn("--proxima", self.texto, "o caminho feliz constrói a próxima indexada")

    def test_yaml_estrutural(self):
        """Checagem estrutural mínima (sem PyYAML, que não está instalado aqui)."""
        self.assertNotIn("\t", self.texto, "YAML não aceita tabulação para indentação")
        with open(WORKFLOW, encoding="utf-8") as fh:
            linhas = fh.read().splitlines()
        self.assertTrue(linhas[0].startswith("#") or linhas[0].startswith("name:"),
                        "o arquivo precisa começar com comentário ou name:")
        for linha in linhas:
            if re.match(r"^\s*[\w\-\.\$\{\}'\"/]+\s*:", linha) and not linha.lstrip().startswith("#"):
                indent = len(linha) - len(linha.lstrip(" "))
                self.assertEqual(indent % 2, 0, f"indentação ímpar em: {linha!r}")
        try:
            import yaml  # type: ignore
        except ImportError:
            self.skipTest("PyYAML indisponível — a validação definitiva é a execução no Actions")
        dados = yaml.safe_load(self.texto)
        self.assertIn("jobs", dados)


if __name__ == "__main__":
    unittest.main(verbosity=2)
