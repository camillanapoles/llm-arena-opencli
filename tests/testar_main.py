#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Testes do main.py (consulta de processo → relatório em Markdown).

Roda 100% offline: sobe o mock de tests/mock_apis.py numa porta livre e aponta o
main.py para ele pelas variáveis de ambiente, como se fosse o CNJ.

Uso:  python3 tests/testar_main.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tests"))

import main  # noqa: E402  (import após ajustar o sys.path)
import mock_apis  # noqa: E402

CHAVE_TESTE = "CHAVE-DE-TESTE"
NUMERO = mock_apis.NUMERO_TESTE                # 00012344320248172001 (DV válido)
NUMERO_FMT = "0001234-43.2024.8.17.2001"
SERVIDOR, PORTA = mock_apis.criar_servidor(0, CHAVE_TESTE)

AMBIENTE = dict(
    os.environ,
    DATAJUD_BASE_URL=f"http://127.0.0.1:{PORTA}",
    DJEN_BASE_URL=f"http://127.0.0.1:{PORTA}/api/v1",
    DATAJUD_API_KEY=CHAVE_TESTE,
    PYTHONIOENCODING="utf-8",
)


def rodar(*argumentos: str, ambiente=None):
    """Roda o main.py como subprocesso e devolve (código, stdout, stderr)."""
    proc = subprocess.run([sys.executable, os.path.join(RAIZ, "main.py"), *argumentos],
                          capture_output=True, text=True, env=ambiente or AMBIENTE, cwd=RAIZ)
    return proc.returncode, proc.stdout, proc.stderr


class TesteNumeroCNJ(unittest.TestCase):
    """Resolução CNJ 65/2008 — estrutura e dígito verificador (módulo 97 base 10)."""

    NUMEROS_OFICIAIS = [
        "00008323520184013202",   # exemplo da wiki do DataJud (TRF1)
        "07223914020178070001",   # exemplo da wiki do DataJud (TJDFT)
        "00073039720138070015",   # exemplo da wiki do DataJud (TJDFT)
        "00017115620175130002",   # exemplo público da ABJ (0001711-56.2017.5.13.0002)
    ]

    def test_dv_de_numeros_reais_confere(self):
        for numero in self.NUMEROS_OFICIAIS:
            self.assertTrue(main.dv_valido(numero), f"DV deveria conferir em {numero}")

    def test_calculo_dv_bate_com_o_numero(self):
        for numero in self.NUMEROS_OFICIAIS:
            self.assertEqual(main.calcular_dv(numero), numero[7:9],
                             f"DV calculado difere do informado em {numero}")

    def test_dv_detecta_erro_de_digitacao(self):
        self.assertFalse(main.dv_valido("00008323520184013203"))

    def test_formatacao_e_limpeza(self):
        self.assertEqual(main.somente_digitos("0001234-43.2024.8.17.2001"), NUMERO)
        self.assertEqual(main.formatar_numero(NUMERO), NUMERO_FMT)

    def test_decodificacao_de_tribunais(self):
        casos = {
            NUMERO: ("TJPE", "tjpe"),                         # 8.17
            "00008323520184013202": ("TRF1", "trf1"),          # 4.01
            "00017115620175130002": ("TRT13", "trt13"),        # 5.13
            "07223914020178070001": ("TJDFT", "tjdft"),        # 8.07 (alias especial)
            "00000000020246170000": ("TRE-PE", "tre-pe"),      # 6.17 (Eleitoral de PE)
        }
        for numero, (sigla, alias) in casos.items():
            d = main.decodificar(numero)
            self.assertEqual(d["tribunal_sigla"], sigla, f"sigla de {numero}")
            self.assertEqual(d["datajud_alias"], alias, f"alias de {numero}")


class TesteRelatorio(unittest.TestCase):
    """Relatório em Markdown gerado a partir do mock."""

    @classmethod
    def setUpClass(cls):
        cls.codigo, cls.saida, cls.erro = rodar(NUMERO_FMT)

    def test_roda_com_sucesso(self):
        self.assertEqual(self.codigo, 0, self.erro)

    def test_cabecalho_e_numero_formatado(self):
        self.assertIn(f"# Processo {NUMERO_FMT}", self.saida)

    def test_secoes_principais(self):
        for secao in ("## 1. Resumo executivo", "## 2. Identificação e validação do número",
                      "## 3. Capa do processo", "## 4. Movimentações processuais",
                      "## 5. Panorama estatístico", "## 7. Anexos e documentos",
                      "## 8. Links oficiais de consulta", "## 10. Notas, limitações e conformidade"):
            self.assertIn(secao, self.saida)

    def test_validacao_do_numero_aparece(self):
        self.assertIn("válido ✔", self.saida)
        self.assertIn("módulo 97 base 10", self.saida)

    def test_capa_traz_classe_assunto_e_orgao(self):
        self.assertIn("1116 — Execução Fiscal", self.saida)
        self.assertIn("6017 — Dívida Ativa (Execução Fiscal)", self.saida)
        self.assertIn("1ª VARA DE EXECUÇÃO FISCAL DA COMARCA DE RECIFE", self.saida)
        self.assertIn("2611606 — PE", self.saida)      # município IBGE + UF

    def test_dois_graus_sao_renderizados(self):
        self.assertIn("3.1 Documento 1 — grau G1", self.saida)
        self.assertIn("3.2 Documento 2 — grau G2", self.saida)
        self.assertIn("2ª CÂMARA DE DIREITO PÚBLICO", self.saida)

    def test_movimentos_e_complementos(self):
        self.assertIn("Distribuição", self.saida)
        self.assertIn("tipo_de_distribuicao_redistribuicao", self.saida)
        self.assertIn("sorteio", self.saida)
        self.assertIn("05/03/2024 12:00", self.saida)   # data formatada em pt-BR

    def test_estatisticas(self):
        self.assertIn("5.1 Movimentações por ano", self.saida)
        self.assertIn("5.2 Movimentos mais frequentes", self.saida)
        self.assertIn("5.4 Tempo e inércia", self.saida)
        self.assertIn("█", self.saida)                   # barra do gráfico

    def test_secao_de_anexos_explica_a_limitacao(self):
        self.assertIn("apenas metadados", self.saida.replace("*", ""))
        self.assertIn("Autos completos, petições, decisões e anexos", self.saida)

    def test_links_oficiais_do_tjpe(self):
        for link in ("pje.cloud.tjpe.jus.br/1g/ConsultaPublica/listView.seam",
                     "pje.cloud.tjpe.jus.br/2g/ConsultaPublica/listView.seam",
                     "srv01.tjpe.jus.br/consultaprocessualunificada",
                     "comunica.pje.jus.br/consulta?numeroProcesso=" + NUMERO):
            self.assertIn(link, self.saida)

    def test_notas_legais(self):
        self.assertIn("120 requisições por minuto", self.saida)
        self.assertIn("não comercial", self.saida)
        self.assertIn("LGPD", self.saida)


class TesteDJEN(unittest.TestCase):
    """Publicações e intimações (DJEN/Comunica)."""

    def test_publicacoes_aparecem_no_relatorio(self):
        codigo, saida, erro = rodar(NUMERO_FMT)
        self.assertEqual(codigo, 0, erro)
        self.assertIn("## 6. Publicações e intimações (DJEN)", saida)
        self.assertIn("Intimação", saida)
        self.assertIn("https://comunica.pje.jus.br/documento/9001.pdf", saida)
        self.assertIn("art. 9º da Lei 6.830/80", saida)

    def test_sem_djen_nao_consulta_nem_exibe_itens(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--sem-djen")
        self.assertEqual(codigo, 0, erro)
        self.assertIn("_Não consultado", saida)
        self.assertNotIn("Lei 6.830/80", saida)

    def test_falha_do_djen_nao_derruba_o_relatorio(self):
        ambiente = dict(AMBIENTE, DJEN_BASE_URL="http://127.0.0.1:1/api/v1")
        codigo, saida, erro = rodar(NUMERO_FMT, ambiente=ambiente)
        self.assertEqual(codigo, 0, "o relatório deve sair mesmo sem DJEN")
        self.assertIn("## 1. Resumo executivo", saida)
        self.assertIn("não consultado", saida.lower() + erro.lower())


class TesteSaidasEArtigos(unittest.TestCase):
    """--json, -o e verificações de robustez."""

    def test_json_traz_documentos_e_djen(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--json")
        self.assertEqual(codigo, 0, erro)
        pacote = json.loads(saida)
        self.assertEqual(pacote["numero"], NUMERO_FMT)
        self.assertEqual(pacote["tribunal"]["datajud_alias"], "tjpe")
        self.assertEqual(len(pacote["documentos"]), 2)
        self.assertEqual(len(pacote["djen"]), 2)

    def test_gravacao_em_arquivo(self):
        with tempfile.TemporaryDirectory() as pasta:
            destino = os.path.join(pasta, "processo.md")
            codigo, saida, erro = rodar(NUMERO_FMT, "-o", destino)
            self.assertEqual(codigo, 0, erro)
            with open(destino, encoding="utf-8") as fh:
                conteudo = fh.read()
            self.assertIn("# Processo", conteudo)
            self.assertIn("## 4. Movimentações processuais", conteudo)

    def test_numero_invalido_falha_com_orientacao(self):
        codigo, saida, erro = rodar("12345")
        self.assertEqual(codigo, 2)
        self.assertIn("20", erro)

    def test_processo_inexistente_orienta_uso_do_todos(self):
        # número com DV válido, mas que não existe no mock (0009999-xx)
        outro = "0009999" + main.calcular_dv("000999920248172001") + "20248172001"
        codigo, saida, erro = rodar(main.formatar_numero(outro))
        self.assertEqual(codigo, 2)
        self.assertIn("--todos", erro)

    def test_chave_errada_explica_o_problema(self):
        ambiente = dict(AMBIENTE, DATAJUD_API_KEY="chave-errada")
        codigo, saida, erro = rodar(NUMERO_FMT, ambiente=ambiente)
        self.assertEqual(codigo, 2)
        self.assertIn("chave", erro.lower())

    def test_alias_de_tribunal_inexistente(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--buscar-em", "tribunal-que-nao-existe")
        self.assertEqual(codigo, 2)
        self.assertIn("404", erro + saida)

    def test_flag_todos_varre_outros_indices(self):
        codigo, saida, erro = rodar(NUMERO_FMT, "--todos")
        self.assertEqual(codigo, 0, erro)
        self.assertIn("api_publica_trf5", erro)   # o log lista todos os índices varridos
        self.assertIn("nenhum documento", erro)
        self.assertIn("# Processo", saida)

    def test_dv_invalido_avisa_mas_continua(self):
        numero_errado = NUMERO[:7] + ("99" if NUMERO[7:9] != "99" else "88") + NUMERO[9:]
        codigo, saida, erro = rodar(main.formatar_numero(numero_errado))
        self.assertIn("não confere", erro)

    def test_chave_publica_lida_da_wiki(self):
        ambiente = dict(AMBIENTE, DATAJUD_WIKI_URL=f"http://127.0.0.1:{PORTA}/wiki/acesso")
        codigo, saida, erro = rodar("--chave-publica", ambiente=ambiente)
        self.assertEqual(codigo, 0, erro)
        self.assertEqual(saida.strip(), mock_apis.CHAVE_WIKI)

    def test_help_e_versao(self):
        codigo, saida, _ = rodar("--help")
        self.assertEqual(codigo, 0)
        self.assertIn("DataJud", saida)
        codigo, saida, _ = rodar("--versao")
        self.assertEqual(codigo, 0)
        self.assertIn(main.VERSAO, saida)


if __name__ == "__main__":
    print(f"mock das APIs em 127.0.0.1:{PORTA} | processo de teste {NUMERO_FMT}\n")
    try:
        unittest.main(verbosity=2)
    finally:
        SERVIDOR.shutdown()
