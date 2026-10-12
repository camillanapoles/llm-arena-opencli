/**
 * GitHubActionsDriver — uses the GitHub Actions runtime as the execution
 * environment ("driver") of a target repository (by default jackwener/OpenCLI).
 *
 * From inside a workflow, GITHUB_TOKEN + this driver make the runner itself an
 * automation actuator: it fires `repository_dispatch` / `workflow_dispatch`
 * events on the target repo, and can poll workflow runs for gate status.
 */

import { FetchTransport, type ActionsTransport } from "./transport.ts";

export interface GitHubActionsDriverOptions {
  /** Target repository, e.g. "jackwener/OpenCLI". */
  repo: string;
  /** Token with repo + actions scope. Defaults to $GITHUB_TOKEN. */
  token?: string | undefined;
  /** API base URL. Defaults to https://api.github.com. */
  apiBase?: string | undefined;
  transport?: ActionsTransport | undefined;
}

export interface DispatchResult {
  ok: boolean;
  status: number;
  detail: string;
}

export class GitHubActionsDriver {
  readonly repo: string;
  private readonly token: string;
  private readonly apiBase: string;
  private readonly transport: ActionsTransport;

  constructor(options: GitHubActionsDriverOptions) {
    this.repo = options.repo;
    this.token = options.token ?? process.env["GITHUB_TOKEN"] ?? "";
    this.apiBase = options.apiBase ?? process.env["GITHUB_API_BASE"] ?? "https://api.github.com";
    this.transport = options.transport ?? new FetchTransport();
  }

  /** Fire a `repository_dispatch` event (type defaults to "opencli-command"). */
  async dispatchRepositoryDispatch(
    eventType: string,
    clientPayload: Record<string, unknown>,
  ): Promise<DispatchResult> {
    return this.request("POST", `/repos/${this.repo}/dispatches`, {
      event_type: eventType,
      client_payload: clientPayload,
    });
  }

  /** Fire a `workflow_dispatch` on a workflow file of the target repo. */
  async dispatchWorkflow(
    workflowId: string,
    ref: string,
    inputs: Record<string, string> = {},
  ): Promise<DispatchResult> {
    return this.request(
      "POST",
      `/repos/${this.repo}/actions/workflows/${workflowId}/dispatches`,
      { ref, inputs },
    );
  }

  /** Fetch a workflow run — used by gate drivers to poll gate status. */
  async getWorkflowRun(runId: string | number): Promise<Record<string, unknown> | null> {
    const result = await this.request("GET", `/repos/${this.repo}/actions/runs/${runId}`);
    if (!result.ok) return null;
    try {
      return JSON.parse(result.detail) as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  private async request(
    method: string,
    path: string,
    payload?: unknown,
  ): Promise<DispatchResult> {
    const url = path.startsWith("http") ? path : `${this.apiBase}${path}`;
    const headers: Record<string, string> = {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "llm-arena-opencli-gate-driver",
    };
    if (this.token !== "") {
      headers["Authorization"] = `Bearer ${this.token}`;
    }
    let body: string | undefined;
    if (payload !== undefined) {
      headers["Content-Type"] = "application/json";
      body = JSON.stringify(payload);
    }
    const response = await this.transport.request({ method, url, headers, body });
    const ok = response.status >= 200 && response.status < 300;
    return { ok, status: response.status, detail: response.body };
  }
}
