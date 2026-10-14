/**
 * guardiao-cli — Guardião de Projeto (continuidade automática do escopo global).
 *
 *   node src/cli/guardiao-cli.ts scan                 # retrato do escopo global (JSON)
 *   node src/cli/guardiao-cli.ts next                 # próxima decisão (JSON, sempre com motivo)
 *   node src/cli/guardiao-cli.ts run [--executar]     # UMA ação limitada por ciclo
 *
 * `run` sem `--executar` é dry-run (mostra o comando). Com `--executar`, roda
 * exatamente o comando da decisão (limitado a cycle/fábrica/fix seguro) e
 * devolve o envelope. Exit: 0 ok/vigiar · 1 decisão humana necessária · 2 erro.
 */

import { execFileSync } from "node:child_process";
import { decidir, scanGlobal, type Decisao } from "../guardian/guardian.ts";

function sair(code: number): never {
  process.exit(code);
}

const [cmd, ...rest] = process.argv.slice(2);
const executar = rest.includes("--executar");
const raiz = ".";

const escopo = scanGlobal(raiz);

switch (cmd) {
  case "scan": {
    console.log(JSON.stringify(escopo, null, 2));
    sair(0);
  }

  case "next":
  case "run": {
    const decisao: Decisao = decidir(escopo);
    if (cmd === "next" || !executar) {
      console.log(JSON.stringify({ modo: cmd === "next" ? "next" : "dry-run", decisao }, null, 2));
      sair(decisao.acao === "humano" ? 1 : 0);
    }
    // run --executar: UMA ação limitada
    console.log(JSON.stringify({ modo: "run", decisao }, null, 2));
    if (decisao.acao === "vigiar") {
      console.log("✔ guardião: nada a executar — " + decisao.motivo);
      sair(0);
    }
    if (decisao.acao === "humano") {
      console.error("✋ guardião: " + decisao.motivo);
      sair(1);
    }
    if (decisao.comando === undefined) {
      console.error("✘ decisão sem comando — débito interno do guardião");
      sair(2);
    }
    try {
      const saida = execFileSync("bash", ["-c", decisao.comando], {
        encoding: "utf8",
        timeout: 1_800_000,
      });
      console.log(saida.slice(-4000));
      console.log(`✔ guardião executou: ${decisao.comando}`);
      sair(0);
    } catch (e) {
      const err = e as { stdout?: string; stderr?: string; message: string };
      console.error(`✘ comando falhou: ${decisao.comando}`);
      console.error((err.stdout ?? "").slice(-2000));
      console.error((err.stderr ?? err.message).slice(-2000));
      console.error("→ fluxo de débito: registrar em .session/DEBT.md com prioridade e retorno para fix");
      sair(2);
    }
    break;
  }

  default:
    console.error("comandos: scan | next | run [--executar]");
    sair(2);
}
