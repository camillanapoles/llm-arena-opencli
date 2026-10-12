#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Conformidade do código com a documentação oficial do CNJ.

Cada teste aqui corresponde a um item publicado em
  • https://datajud-wiki.cnj.jus.br/api-publica/acesso      (chave e cabeçalho)
  • https://datajud-wiki.cnj.jus.br/api-publica/endpoints  (rotas e aliases)
  • https://datajud-wiki.cnj.jus.br/api-publica/glossario  (campos)
  • https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo3 (search_after)
  • Termos de uso v1.2 (itens 3.6, 3.8, 3.9, 3.13, 4.2)

Não acessa a internet: inspeciona os fontes e usa os mocks locais.

Uso:  python3 tests/testar_conformidade.py
"""
from __future__ import annotations

import ast
import os
import re
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, RAIZ)
sys.path.insert(0, os.path.join(RAIZ, "tests"))

MAIN = open(os.path.join(RAIZ, "main.py"), encoding="utf-8").read()
SH = open(os.path.join(RAIZ, "scripts", "datajud.sh"), encoding="utf-8").read()
DOC_API = open(os.path.join(RAIZ, "docs", "01-api-datajud.md"), encoding="utf-8").read()

import main  # noqa: E402


class TesteAcesso(unittest.TestCase):
    """Página 'Acesso': URL base, rota e cabeçalhos."""

    def test_url_base_oficial(self):
        self.assertEqual(main.DATAJUD_BASE, "https://api-publica.datajud.cnj.jus.br")
        self.assertIn("https://api-publica.datajud.cnj.jus.br", SH)

    def test_rota_search_com_alias(self):
        self.assertIn('/api_publica_{alias}/_search', MAIN)
        self.assertRegex(SH, r"api_publica_%s/_search|/api_publica_")

    def test_cabecalho_authorization_apikey(self):
        # formato exigido: "Authorization: APIKey <chave>"
        self.assertIn('f"APIKey {CHAVE}"', MAIN)
        self.assertRegex(SH, r'Authorization: APIKey \$API_KEY')

    def test_cabecalho_content_type_json(self):
        self.assertIn('cabecalhos["Content-Type"] = "application/json"', MAIN)
        self.assertIn("Content-Type: application/json", SH)

    def test_metodo_post(self):
        self.assertIn('method="POST" if dados else "GET"', MAIN)  # POST quando há corpo
        self.assertIn("curl -sS", SH)

    def test_chave_publica_vigente_embutida(self):
        # a chave da wiki é um base64 longo; guardamos a vigente como default
        self.assertGreaterEqual(len(main.CHAVE_PUBLICA_PADRAO), 40)
        self.assertTrue(re.fullmatch(r"[A-Za-z0-9+/=]{40,}", main.CHAVE_PUBLICA_PADRAO))
        self.assertTrue(main.CHAVE_PUBLICA_PADRAO.endswith("=="))
        self.assertIn(main.CHAVE_PUBLICA_PADRAO, SH)

    def test_comando_para_reler_a_chave_na_wiki(self):
        # a wiki avisa que a chave pode mudar: precisa existir um caminho para relê-la
        self.assertIn("datajud-wiki.cnj.jus.br/api-publica/acesso", main.WIKI_URL)
        self.assertIn("--chave-publica", MAIN)
        self.assertIn("cmd_chave", SH)


class TesteEndpoints(unittest.TestCase):
    """Página 'Endpoints': aliases por tribunal."""

    CASOS = {
        "00008323520184013202": ("TRF1", "trf1"),        # exemplo oficial (wiki)
        "07223914020178070001": ("TJDFT", "tjdft"),      # exemplo oficial (wiki)
        "00012344320248172001": ("TJPE", "tjpe"),        # 8.17
        "00017115620175130002": ("TRT13", "trt13"),      # 5.13
        "00000000020246170000": ("TRE-PE", "tre-pe"),    # 6.17 (Eleitoral de PE)
    }

    def test_alias_por_tribunal(self):
        for numero, (sigla, alias) in self.CASOS.items():
            d = main.decodificar(numero)
            self.assertEqual((d["tribunal_sigla"], d["datajud_alias"]), (sigla, alias), numero)

    def test_aliases_presentes_na_documentacao(self):
        """Todo alias suportado pelo código precisa estar citado na documentação."""
        corpus = "\n".join([
            DOC_API,
            open(os.path.join(RAIZ, "docs", "02-receitas-curl-tjpe.md"), encoding="utf-8").read(),
            open(os.path.join(RAIZ, "README.md"), encoding="utf-8").read(),
            MAIN,
        ])
        for alias in ("tjpe", "trf5", "trt6", "tre-pe", "tjdft", "stj", "tst", "tse", "stm"):
            self.assertIn(alias, corpus, f"alias '{alias}' não aparece em nenhum doc do projeto")

    def test_alias_tjdft_e_dft_sao_os_especiais_da_doc(self):
        # 8.07 -> api_publica_tjdft e 6.07 -> api_publica_tre-dft (fogem do padrão TJ+UF)
        self.assertIn("tjdft", MAIN)
        self.assertIn("tre-dft", MAIN)


class TesteGlossario(unittest.TestCase):
    """Página 'Glossário de Dados': campos consumidos e documentados."""

    CAMPOS = ["numeroProcesso", "tribunal", "dataAjuizamento", "grau", "nivelSigilo",
              "formato", "sistema", "classe", "assuntos", "orgaoJulgador", "movimentos",
              "complementosTabelados", "dataHoraUltimaAtualizacao", "@timestamp",
              "codigoMunicipioIBGE"]

    def test_main_le_todos_os_campos_do_glossario(self):
        for campo in self.CAMPOS:
            self.assertIn(campo, MAIN, f"campo {campo} não é lido pelo main.py")

    def test_documentacao_lista_o_glossario(self):
        for campo in self.CAMPOS:
            self.assertIn(campo, DOC_API, f"campo {campo} ausente de docs/01-api-datajud.md")

    def test_id_no_padrao_tribunal_classe_grau_orgao_numero(self):
        # id = Tribunal_Classe_Grau_OrgaoJulgador_NumeroProcesso (glossário)
        componente = re.search(r"Chave `?Tribunal_Classe_Grau_OrgaoJulgador_NumeroProcesso", DOC_API)
        self.assertIsNotNone(componente, "o glossário do projeto deve citar a composição do id")


class TesteConsultas(unittest.TestCase):
    """Exemplos 1 a 3 e boas práticas de consulta."""

    def test_busca_por_numero_usa_match(self):
        self.assertIn('{"match": {"numeroProcesso": numero20}}', MAIN)

    def test_filtros_por_classe_e_orgao(self):
        self.assertRegex(SH, r'classe\.codigo')
        self.assertRegex(SH, r'orgaoJulgador\.codigo')

    def test_paginacao_com_search_after_e_sort_timestamp(self):
        # Exemplo 3: ordenar por @timestamp e usar o vetor sort como search_after
        self.assertIn('sort:[{"@timestamp":{"order":"asc"}}]', SH)
        self.assertIn("search_after", SH)

    def test_tamanho_de_pagina_dentro_do_limite(self):
        # a API aceita de 1 a 10.000 documentos por página
        self.assertIn('[ "$pagina" -ge 1 && "$pagina" -le 10000 ]', SH)

    def test_contagem_trata_teto_de_10000(self):
        self.assertIn("track_total_hits", SH)
        self.assertIn('"gte"', SH)

    def test_agregacoes_terms_e_historico_de_datas(self):
        self.assertIn("terms", SH)
        self.assertIn("date_histogram", SH)
        self.assertIn("calendar_interval", SH)

    def test_fallback_para_campo_keyword(self):
        # a doc avisa: campo texto não é agregável; usar .keyword
        self.assertIn(".keyword", SH)
        self.assertIn("fielddata", SH.lower())


class TesteTermoDeUso(unittest.TestCase):
    """Termo de Uso v1.2 — itens que o código precisa respeitar."""

    def test_limite_de_120_requisicoes_por_minuto_citado(self):
        self.assertIn("120", MAIN)
        self.assertIn("3.13", MAIN + SH)

    def test_pausa_entre_requisicoes_para_nao_estourar_o_limite(self):
        self.assertRegex(SH, r"DATAJUD_PAUSA|pausa|sleep")
        self.assertIn("time.sleep(", MAIN)

    def test_uso_nao_comercial_e_ciencia_ao_cnj_no_relatorio(self):
        relatorio = os.path.join(RAIZ, "docs", "exemplo-saida", "relatorio-processo-exemplo.md")
        texto = ""
        if os.path.exists(relatorio):
            with open(relatorio, encoding="utf-8") as fh:
                texto = fh.read()
        self.assertIn("não comercial", MAIN)
        self.assertIn("dê ciência ao CNJ", MAIN)
        if texto:
            self.assertIn("não comercial", texto)

    def test_lgpd_mencionada(self):
        self.assertIn("LGPD", MAIN)
        self.assertIn("LGPD", DOC_API)

    def test_sem_dados_pessoais_coletados(self):
        # o projeto não deve ter campos de partes/CPF/CNPJ em nenhuma estrutura de dados
        proibidos = ["cpf", "nomeParte", "documentoParte", "cnpj"]
        for termo in proibidos:
            ocorrencias = re.findall(rf'["\']{termo}', MAIN + SH, re.I)
            self.assertEqual(ocorrencias, [], f"campo pessoal '{termo}' parece ser coletado")

    def test_avisos_de_limitacao_presentes_no_relatorio(self):
        # item 3.6: o CNJ não garante precisão/atualidade — precisa estar dito no relatório
        self.assertIn("não garante", MAIN)


class TesteIntegridadeDosFontes(unittest.TestCase):
    """Sanidade estrutural: o projeto precisa compilar e não ter dependências externas."""

    def test_main_sem_dependencias_externas(self):
        arvore = ast.parse(MAIN)
        modulos = set()
        for no in ast.walk(arvore):
            if isinstance(no, ast.Import):
                modulos |= {a.name.split(".")[0] for a in no.names}
            elif isinstance(no, ast.ImportFrom) and no.module:
                modulos.add(no.module.split(".")[0])
        externos = modulos - set(sys.stdlib_module_names)
        self.assertEqual(externos, set(), f"main.py importa módulos não-stdlib: {externos}")

    def test_shebang_e_permissao_de_execucao(self):
        for relativo in ("main.py", "scripts/datajud.sh", "tests/rodar-testes.sh",
                         "tests/mock_apis.py", "tests/mock_datajud.py", "tests/testar_main.py",
                         "tests/testar_conformidade.py"):
            caminho = os.path.join(RAIZ, relativo)
            self.assertTrue(open(caminho, encoding="utf-8").readline().startswith("#!"),
                            f"{relativo} sem shebang")
            self.assertTrue(os.access(caminho, os.X_OK), f"{relativo} sem permissão de execução")

    def test_bash_script_sem_erro_de_sintaxe(self):
        import subprocess
        r = subprocess.run(["bash", "-n", os.path.join(RAIZ, "scripts", "datajud.sh")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
