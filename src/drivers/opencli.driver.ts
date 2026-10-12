/**
 * OpenCLI driver — turns high-level "drive this website" intents into
 * OpenCLI command manifests that the target repository's GitHub Actions
 * workflows execute in the runner runtime.
 *
 * The manifest mirrors OpenCLI's `cli-manifest.json` shape: a command name,
 * an optional target URL and positional args. The heavy lifting (browser
 * automation, logged-in session, AX tree) happens inside the OpenCLI checkout
 * that the workflow sets up; this driver only decides *what* runs and *when*
 * (the gate event) and records the outcome.
 */

import type { GitHubActionsDriver } from "./github-actions.driver.ts";

export interface OpenCLICommand {
  command: string;
  url?: string;
  args?: string[];
  clientPayload?: Record<string, unknown>;
}

export interface OpenCLIDispatchResult {
  ok: boolean;
  status: number;
  detail: string;
  manifest: Record<string, unknown>;
}

export class OpenCLIDriver {
  private readonly actions: GitHubActionsDriver;
  readonly eventType = "opencli-command";

  constructor(actions: GitHubActionsDriver) {
    this.actions = actions;
  }

  buildManifest(command: OpenCLICommand): Record<string, unknown> {
    return {
      version: 1,
      command: command.command,
      url: command.url ?? "",
      args: command.args ?? [],
      targetRepo: this.actions.repo,
      createdAt: new Date().toISOString(),
    };
  }

  /** Dispatch one OpenCLI command through the Actions runtime of the target repo. */
  async run(command: OpenCLICommand): Promise<OpenCLIDispatchResult> {
    const manifest = this.buildManifest(command);
    const result = await this.actions.dispatchRepositoryDispatch(this.eventType, {
      ...manifest,
      ...(command.clientPayload ?? {}),
    });
    return { ok: result.ok, status: result.status, detail: result.detail, manifest };
  }
}
