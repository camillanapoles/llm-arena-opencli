#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Testes da fábrica de issues (pipeline/factory.py) e do gate `fabrica`.

Cobrem: classes (POO), esquema SQLite, o padrão do blueprint (BPMN), a construção
da PRÓXIMA issue indexada só depois do sucesso testado, os eventos event-driven,
o espelho backlog.json ⇄ SQLite e o contrato JSON do gate.

Uso:  python3 tests/testar_fabrica.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "pipeline"))

import factory  # noqa: E402
import gate  # noqa: E402

BLUEPRINT = os.path.join(RAIZ, "pipeline", "blueprint.json")
BACKLOG = os.path.join(RAIZ, "pipeline", "backlog.json")
FACTORY_CLI = os.path.join(RAIZ, "pipeline", "factory.py")
GATE_CLI = os.path.join(RAIZ, "pipeline", "gate.py")


def rodar(script, *argumentos):
    proc = subprocess.run([sys.executable, script, *argumentos],
                          capture_output=True, text=True, cwd=RAIZ)
    try:
        return proc.returncode, json.loads(proc.stdout), proc.stdout + proc.stderr
    except json.JSONDecodeError:
        return proc.returncode, None, proc.stdout + proc.stderr


class CasoBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.banco = os.path.join(self.dir, "fabrica.db")
        self.saida = os.path.join(self.dir, "saida")
        self.padrao = factory.PadraoBPMN(BLUEPRINT)
        self.repo = factory.Repositorio(self.banco)
        self.fabrica = factory.Fabrica(self.repo, self.padrao)

    def tearDown(self):
        try:
            self.repo.armazenamento.fechar()
        except Exception:
            pass
        self.tmp.cleanup()

    def uma_issue(self, indice=1, status="concluida", **extra):
        dados = {"id": f"ISSUE-{indice:03d}", "indice": indice, "titulo": f"t{indice}",
                 "entregavel": "ent", "instrucao_teste": "true",
                 "instrucao_desenvolvimento": "executar e testar", "status": status,
                 "origem": "teste"}
        dados.update(extra)
        return self.repo.salvar_issue(factory.Issue.de_dict(dados))


class TesteArmazenamento(CasoBase):
    def test_esquema_strict_criado(self):
        tabelas = self.repo.tabelas()
        for esperada in ("issues", "eventos", "schema_info"):
            self.assertIn(esperada, tabelas)
        colunas = self.repo.armazenamento.consultar("PRAGMA table_info(issues)")
        nomes = {c["name"] for c in colunas}
        for campo in factory.CAMPOS_ISSUE:
            self.assertIn(campo, nomes, f"coluna ausente no SQLite: {campo}")

    def test_versao_do_esquema_migrada(self):
        linhas = self.repo.armazenamento.consultar("SELECT valor FROM schema_info WHERE chave='versao'")
        self.assertEqual(linhas[0]["valor"], factory.VERSAO)

    def test_indice_unico(self):
        self.uma_issue(1)
        with self.assertRaises(Exception):
            self.uma_issue(1, id="ISSUE-099")


class TesteEntidades(CasoBase):
    def test_issue_valida_o_padrao(self):
        issue = self.padrao.modelo(indice=8, titulo="nova", instrucao_teste="true",
                                   anterior="ISSUE-007")
        issue.validar()
        self.assertEqual(issue.id, "ISSUE-008")
        self.assertEqual(issue.depende_de, ["ISSUE-007"])

    def test_id_fora_do_padrao_e_recusado(self):
        ruim = factory.Issue.de_dict({"id": "TAREFA-1", "indice": 1, "titulo": "x",
                                      "instrucao_desenvolvimento": "y"})
        with self.assertRaises(factory.ErroFabrica):
            ruim.validar()

    def test_instrucao_de_desenvolvimento_e_obrigatoria(self):
        sem_instrucao = factory.Issue.de_dict({"id": "ISSUE-042", "indice": 42,
                                               "titulo": "x",
                                               "instrucao_desenvolvimento": ""})
        with self.assertRaisesRegex(factory.ErroFabrica, "instrucao_desenvolvimento"):
            sem_instrucao.validar()

    def test_concluir_registra_evidencia_e_data(self):
        issue = self.padrao.modelo(indice=1, titulo="a")
        issue.concluir({"sucesso": "COMPLETADA"})
        self.assertTrue(issue.concluida())
        self.assertEqual(issue.status, "concluida")
        self.assertIsNotNone(issue.concluida_em)
        self.assertEqual(issue.evidencias[0]["sucesso"], "COMPLETADA")

    def test_completada_conta_como_concluida(self):
        issue = factory.Issue.de_dict({"id": "ISSUE-001", "indice": 1, "titulo": "a",
                                       "instrucao_desenvolvimento": "b",
                                       "status": "completada"})
        self.assertTrue(issue.concluida())


class TesteBacklog(CasoBase):
    def test_ordenacao_e_proxima_pendente(self):
        backlog = factory.Backlog([
            {"id": "ISSUE-003", "indice": 3, "titulo": "c", "status": "pendente",
             "instrucao_desenvolvimento": "x"},
            {"id": "ISSUE-001", "indice": 1, "titulo": "a", "status": "concluida",
             "instrucao_desenvolvimento": "x"}])
        self.assertEqual([i.id for i in backlog.ordenadas()], ["ISSUE-001", "ISSUE-003"])
        self.assertEqual(backlog.proxima_pendente().id, "ISSUE-003")
        self.assertEqual(backlog.proximo_indice(), 4)

    def test_dependencia_inexistente_e_recusada(self):
        backlog = factory.Backlog()
        issue = self.padrao.modelo(indice=2, titulo="b", depende_de=["ISSUE-404"])
        with self.assertRaisesRegex(factory.ErroFabrica, "depende de issue inexistente"):
            backlog.adicionar(issue)

    def test_resumo_por_status(self):
        backlog = factory.Backlog([
            {"id": "ISSUE-001", "indice": 1, "titulo": "a", "status": "concluida",
             "instrucao_desenvolvimento": "x"},
            {"id": "ISSUE-002", "indice": 2, "titulo": "b", "status": "pendente",
             "instrucao_desenvolvimento": "x"}])
        self.assertEqual(backlog.resumo_por_status(), {"concluida": 1, "pendente": 1})


class TestePadraoBPMN(CasoBase):
    def test_planta_do_projeto_tem_modelo_e_fabrica(self):
        self.padrao.validar()
        self.assertIn("fabrica", self.padrao.gates)
        self.assertIn("instrucao_desenvolvimento", self.padrao.modelo_issue.campos)

    def test_instrucoes_de_desenvolvimento_declaradas(self):
        instrucoes = self.padrao.instrucoes()
        self.assertGreaterEqual(len(instrucoes), 3)
        self.assertTrue(any("gate" in i for i in instrucoes))

    def test_id_sintetizado_pelo_formato_do_blueprint(self):
        self.assertEqual(self.padrao.modelo_issue.id_de(12), "ISSUE-012")
        self.assertEqual(self.padrao.modelo_issue.id_de(1234), "ISSUE-1234")

    def test_blueprint_sem_modelo_falha(self):
        caminho = os.path.join(self.dir, "planta.json")
        with open(caminho, "w", encoding="utf-8") as fh:
            json.dump({"gates": [{"id": "issues"}]}, fh)
        with self.assertRaises(factory.ErroFabrica):
            factory.PadraoBPMN(caminho).validar()

    def test_blueprint_inexistente_e_erro_tipo_2(self):
        with self.assertRaises(factory.ErroFabrica):
            factory.PadraoBPMN(os.path.join(self.dir, "nao-existe.json"))


class TesteConstrucaoIndexada(CasoBase):
    def test_constroi_a_proxima_so_depois_do_sucesso(self):
        self.uma_issue(1, status="pendente")
        with self.assertRaises(factory.ErroContinuidade):
            self.fabrica.construir_proxima()
        self.repo.atualizar_issue(factory.Issue.de_dict(
            {**self.repo.proxima_pendente().para_dict(), "status": "concluida"}))
        nova = self.fabrica.construir_proxima()
        self.assertEqual(nova.id, "ISSUE-002")
        self.assertEqual(nova.depende_de, [])

    def test_indexada_depende_da_ultima_concluida(self):
        anterior = self.uma_issue(1)
        nova = self.fabrica.construir_proxima(anterior=anterior, titulo="próxima")
        self.assertEqual(nova.id, "ISSUE-002")
        self.assertEqual(nova.depende_de, ["ISSUE-001"])
        self.assertIn("executar", nova.instrucao_desenvolvimento)

    def test_bloqueada_nao_congela_a_fabrica(self):
        self.uma_issue(1)
        self.uma_issue(2, status="bloqueada")
        nova = self.fabrica.construir_proxima()
        self.assertEqual(nova.id, "ISSUE-003", "issue bloqueada (humano) não trava a fábrica")

    def test_instruir_pendentes_preenche_o_que_falta(self):
        # issue "legada" (sem instrução): só entra tolerada — o gate é que acusa
        self.repo.salvar_issue(factory.Issue.de_dict(
            {"id": "ISSUE-001", "indice": 1, "titulo": "a", "instrucao_desenvolvimento": ""}),
            exigir_instrucao=False)
        atualizadas = self.fabrica.instrutir_pendentes()
        self.assertEqual(atualizadas, ["ISSUE-001"])
        self.assertTrue(self.repo.proxima_pendente().instrucao_desenvolvimento)
        self.assertEqual(self.fabrica.instrutir_pendentes(), [], "não repete quem já tem")


class TesteEventos(CasoBase):
    def test_evento_com_pendencia_mantem_a_mesma_issue(self):
        self.uma_issue(1, status="pendente")
        saida = self.fabrica.processar_evento(factory.Evento("ci_falhou", {"run": "1"}))
        self.assertEqual(saida["acao"], "continuar")
        self.assertEqual(saida["issue"], "ISSUE-001")
        self.assertEqual(saida["direcao"], "depurar")
        self.assertEqual(len(self.repo.listar_issues()), 1, "não criou issue nova")

    def test_evento_apos_sucesso_constroi_a_proxima(self):
        self.uma_issue(1)
        saida = self.fabrica.processar_evento(factory.Evento("demanda", {"titulo": "nova frente"}))
        self.assertEqual(saida["acao"], "construida")
        self.assertEqual(saida["issue"], "ISSUE-002")
        self.assertEqual(saida["direcao"], "proxima")
        self.assertEqual(saida["nova"]["titulo"], "nova frente")

    def test_eventos_registrados_com_payload(self):
        self.uma_issue(1)
        self.fabrica.processar_evento(factory.Evento("gate_falhou", {"gate": "testes"}))
        eventos = self.repo.listar_eventos()
        self.assertEqual(eventos[0]["tipo"], "gate_falhou")
        self.assertEqual(eventos[0]["payload"]["gate"], "testes")

    def test_evento_sem_handler_e_recusado(self):
        with self.assertRaises(factory.ErroFabrica):
            self.fabrica.processar_evento(factory.Evento("meteoro", {}))

    def test_handlers_do_padrao(self):
        self.assertIn("demanda", factory.Fabrica.HANDLERS)
        self.assertIn("ci_falhou", factory.Fabrica.HANDLERS)


class TesteEspelhoBacklog(CasoBase):
    def test_round_trip_json_sqlite(self):
        caminho = os.path.join(self.dir, "backlog.json")
        self.uma_issue(1)
        self.uma_issue(2, status="pendente")
        self.repo.exportar_backlog(caminho)
        outro = factory.Repositorio(os.path.join(self.dir, "outro.db"))
        entraram = outro.sincronizar_backlog(caminho)
        self.assertEqual(entraram, 2)
        self.assertEqual([i.id for i in outro.listar_issues()], ["ISSUE-001", "ISSUE-002"])
        self.assertEqual(outro.listar_issues()[1].status, "pendente")
        self.assertEqual(outro.sincronizar_backlog(caminho), 0, "import é idempotente")

    def test_backlog_do_projeto_espelha_o_sqlite(self):
        self.repo.sincronizar_backlog(BACKLOG)
        self.assertEqual(len(self.repo.listar_issues()), 7)
        with open(BACKLOG, encoding="utf-8") as fh:
            dados = json.load(fh)
        self.assertEqual(len(dados["issues"]), 7)
        self.assertTrue(all(i.get("instrucao_desenvolvimento") for i in dados["issues"]),
                        "toda issue precisa da instrução de desenvolvimento (padrão)")
        self.assertTrue(all(i.get("instrucao_teste") or i["status"] == "bloqueada"
                            for i in dados["issues"]))

    def test_backlog_do_projeto_aponta_para_arquivos_reais(self):
        import re
        with open(BACKLOG, encoding="utf-8") as fh:
            dados = json.load(fh)
        for item in dados["issues"]:
            for arquivo in re.findall(r"[\w/\.\-]+\.(?:py|sh|json|md)", item["instrucao_desenvolvimento"]):
                self.assertTrue(os.path.exists(os.path.join(RAIZ, arquivo)),
                                f"{item['id']}: instrução cita {arquivo}, que não existe")


class TesteGateFabrica(CasoBase):
    def test_gate_fabrica_do_projeto_e_sucesso(self):
        codigo, obj, bruto = rodar(GATE_CLI, "fabrica", "--saida-dir", self.saida)
        self.assertIsNotNone(obj, bruto[:300])
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertEqual(obj["gate"], "fabrica")
        self.assertIn("fabrica", obj["dados"]["classes"][0].lower()
                      + "".join(obj["dados"]["classes"]).lower())
        self.assertTrue(obj["dados"]["round_trip"])

    def test_contrato_do_gate_fabrica(self):
        _, obj, _ = rodar(GATE_CLI, "fabrica", "--saida-dir", self.saida)
        for chave in ("id", "mensagem", "anexos", "status", "next_issue", "direcao",
                      "proximo_passo", "continuidade", "versao"):
            self.assertIn(chave, obj)
        self.assertIsInstance(obj["status"], str)
        self.assertIsInstance(obj["mensagem"], str)
        for anexo in obj["anexos"]:
            self.assertEqual({"path", "filename", "descricao"}, set(anexo))
            self.assertTrue(os.path.exists(anexo["path"]))

    def test_gate_fabrica_em_projeto_sem_instrucao_e_continuidade(self):
        # reaproveita o gate num "projeto" temporário sem instruções
        with open(os.path.join(self.dir, "backlog.json"), "w", encoding="utf-8") as fh:
            json.dump({"issues": [{"id": "ISSUE-001", "indice": 1, "titulo": "sem instrução",
                                   "status": "pendente"}]}, fh)
        codigo, obj, bruto = rodar(GATE_CLI, "fabrica",
                                   "--backlog", os.path.join(self.dir, "backlog.json"),
                                   "--saida-dir", self.saida)
        self.assertEqual((obj["status"], obj["continuidade"]), ("1", True))
        self.assertEqual(obj["next_issue"], None)
        self.assertIn("instrução de desenvolvimento", obj["mensagem"])


class TesteCLIFabrica(CasoBase):
    def test_sincronizar_listar_e_contrato(self):
        codigo, obj, bruto = rodar(FACTORY_CLI, "--banco", self.banco, "--sincronizar",
                                   "--listar", "--saida-dir", self.saida)
        self.assertIsNotNone(obj, bruto[:300])
        self.assertEqual((obj["status"], codigo), ("0", 0))
        self.assertEqual(obj["dados"]["issues"], 7)
        self.assertEqual(obj["next_issue"], "ISSUE-006")
        self.assertIn("direcao", obj["dados"])

    def test_evento_pela_cli(self):
        rodar(FACTORY_CLI, "--banco", self.banco, "--sincronizar", "-q",
              "--saida-dir", self.saida)
        codigo, obj, bruto = rodar(FACTORY_CLI, "--banco", self.banco,
                                   "--evento", "ci_falhou|run=42|workflow=gates",
                                   "--saida-dir", self.saida)
        self.assertEqual(obj["status"], "0")
        self.assertEqual(obj["dados"]["eventos"], 1)
        self.assertIn("continuar", obj["dados"]["resultados"][0])

    def test_concluir_e_construir_a_proxima(self):
        rodar(FACTORY_CLI, "--banco", self.banco, "--sincronizar", "-q",
              "--saida-dir", self.saida)
        codigo, obj, bruto = rodar(FACTORY_CLI, "--banco", self.banco,
                                   "--concluir", "ISSUE-006", "--proxima",
                                   "--titulo", "frente nova", "--saida-dir", self.saida)
        self.assertEqual(obj["status"], "0", bruto[:200])
        nova = obj["dados"]["nova_issue"]
        self.assertEqual(nova["id"], "ISSUE-008")
        self.assertEqual(nova["depende_de"], ["ISSUE-006"])
        self.assertEqual(nova["origem"], "fábrica (próxima indexada)")

    def test_construir_com_pendencia_devolve_status_1(self):
        rodar(FACTORY_CLI, "--banco", self.banco, "--sincronizar", "-q",
              "--saida-dir", self.saida)
        codigo, obj, bruto = rodar(FACTORY_CLI, "--banco", self.banco, "--proxima",
                                   "--saida-dir", self.saida)
        self.assertEqual(obj["status"], "1")
        self.assertEqual(codigo, 1)
        self.assertTrue(obj["continuidade"])
        self.assertEqual(obj["direcao"], "corrigir")
        self.assertEqual(obj["next_issue"], "ISSUE-006")

    def test_banco_invalido_e_erro_tipo_2(self):
        with open(os.path.join(self.dir, "quebrado.db"), "w", encoding="utf-8") as fh:
            fh.write("isto não é um sqlite")
        codigo, obj, bruto = rodar(FACTORY_CLI, "--banco",
                                   os.path.join(self.dir, "quebrado.db"), "--listar",
                                   "--saida-dir", self.saida)
        self.assertEqual(obj["status"], "2")
        self.assertEqual(codigo, 2)
        self.assertFalse(obj["continuidade"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
