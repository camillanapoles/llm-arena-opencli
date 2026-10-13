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

import gate  # noqa: E402  (módulo do pipeline)

GATE = os.path.join(RAIZ, "pipeline", "gate.py")
BACKLOG = os.path.join(RAIZ, "pipeline", "backlog.json")
BLUEPRINT = os.path.join(RAIZ, "pipeline", "blueprint.json")
WORKFLOW = os.path.join(RAIZ, ".github", "workflows", "gates.yml")

CHAVES_OBRIGATORIAS = {"id", "gate", "status", "mensagem", "next_issue", "anexos",
                       "continuidade", "codigo_saida", "dados", "timestamp", "versao"}


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
                         ["cicd", "continuidade", "issue", "issues", "testes"])

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
        self.assertEqual(proxima["id"], "ISSUE-006")
        bagunçado = [{"id": "ISSUE-010", "status": "pendente"},
                     {"id": "ISSUE-002", "status": "concluida"},
                     {"id": "ISSUE-007", "status": "pendente"}]
        self.assertEqual([i["id"] for i in gate.ordenar(bagunçado)],
                         ["ISSUE-002", "ISSUE-007", "ISSUE-010"], "ordenação por índice")
        self.assertEqual(gate.proxima_pendente({"issues": bagunçado})["id"], "ISSUE-007")
        self.assertEqual(gate.proxima_pendente({"issues": bagunçado}, excluir=["ISSUE-007"])["id"],
                         "ISSUE-010", "issue validada não deve voltar como próxima")
        self.assertNotEqual(gate.novo_id("x"), gate.novo_id("x"), "id deve ser único")


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
