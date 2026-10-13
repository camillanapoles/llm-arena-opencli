/**
 * SessionStore — durable session context for continuity across sessions.
 *
 * The Arena chat session ends when the PR is merged; the CI/CD flow must not.
 * This store keeps the *session* (goals, state, checkpoints, next actions) in
 * files that live in git (`session/state.json` + `session/CONTEXT.md`) and are
 * additionally snapshotted as workflow artifacts — so any future session,
 * human, or GitHub Actions run can resume with full context.
 */

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

export interface Checkpoint {
  at: string;
  event: string;
  note: string;
  sha?: string | undefined;
}

export const SESSION_STATUSES = ["active", "paused", "merged", "continuity"] as const;
export type SessionStatus = (typeof SESSION_STATUSES)[number];

export interface SessionState {
  sessionId: string;
  branch: string;
  pr: number | null;
  status: SessionStatus;
  updatedAt: string;
  checkpoints: Checkpoint[];
  nextActions: string[];
}

export function defaultState(): SessionState {
  return {
    sessionId: "arena/d917b13b-llm-arena-opencli",
    branch: "arena/d917b13b-llm-arena-opencli",
    pr: 1,
    status: "active",
    updatedAt: new Date().toISOString(),
    checkpoints: [],
    nextActions: [],
  };
}

export interface CheckpointInput {
  note: string;
  event?: string | undefined;
  sha?: string | undefined;
  now?: (() => Date) | undefined;
}

const MAX_CHECKPOINTS = 50;

export class SessionStore {
  readonly root: string;

  constructor(root: string = process.cwd()) {
    this.root = root;
  }

  get statePath(): string {
    return join(this.root, "session", "state.json");
  }

  get contextPath(): string {
    return join(this.root, "session", "CONTEXT.md");
  }

  read(): SessionState {
    if (!existsSync(this.statePath)) return defaultState();
    try {
      const raw = JSON.parse(readFileSync(this.statePath, "utf8")) as Partial<SessionState>;
      const base = defaultState();
      return {
        sessionId: String(raw.sessionId ?? base.sessionId),
        branch: String(raw.branch ?? base.branch),
        pr: raw.pr == null ? null : Number(raw.pr),
        status: (SESSION_STATUSES as readonly string[]).includes(String(raw.status))
          ? (raw.status as SessionStatus)
          : base.status,
        updatedAt: String(raw.updatedAt ?? base.updatedAt),
        checkpoints: Array.isArray(raw.checkpoints) ? (raw.checkpoints as Checkpoint[]) : [],
        nextActions: Array.isArray(raw.nextActions) ? raw.nextActions.map(String) : [],
      };
    } catch {
      return defaultState();
    }
  }

  write(state: SessionState): void {
    mkdirSync(dirname(this.statePath), { recursive: true });
    // Atomic write: tmp file + rename, so a crashed workflow never leaves a
    // half-written state file as the resume source of truth.
    const tmp = `${this.statePath}.tmp`;
    writeFileSync(tmp, `${JSON.stringify(state, null, 2)}\n`, "utf8");
    renameSync(tmp, this.statePath);
  }

  checkpoint(input: CheckpointInput): SessionState {
    const state = this.read();
    const now = input.now ?? (() => new Date());
    state.checkpoints.push({
      at: now().toISOString(),
      event: input.event ?? "manual",
      note: input.note,
      sha: input.sha,
    });
    if (state.checkpoints.length > MAX_CHECKPOINTS) {
      state.checkpoints = state.checkpoints.slice(-MAX_CHECKPOINTS);
    }
    state.updatedAt = now().toISOString();
    this.write(state);
    return state;
  }

  setNextActions(actions: string[]): SessionState {
    const state = this.read();
    state.nextActions = actions;
    state.updatedAt = new Date().toISOString();
    this.write(state);
    return state;
  }

  setStatus(status: SessionStatus): SessionState {
    const state = this.read();
    state.status = status;
    state.updatedAt = new Date().toISOString();
    this.write(state);
    return state;
  }

  /** Suggested name for the next continuity branch (same repo). */
  suggestBranchName(now: Date = new Date()): string {
    const ts = now.toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-");
    return `arena/continuity-${ts}`;
  }

  /** Markdown briefing a new session/agent/human reads to resume seamlessly. */
  resumeBriefing(): string {
    const state = this.read();
    const recent = state.checkpoints.slice(-5);
    const lines: string[] = [];
    lines.push("## Session resume briefing");
    lines.push("");
    lines.push(`- **session**: \`${state.sessionId}\``);
    lines.push(`- **branch**: \`${state.branch}\` · **PR**: ${state.pr ?? "n/a"} · **status**: ${state.status}`);
    lines.push(`- **updatedAt**: ${state.updatedAt}`);
    lines.push("");
    lines.push("### Últimos checkpoints");
    if (recent.length === 0) {
      lines.push("- (nenhum)");
    } else {
      for (const cp of recent) {
        lines.push(`- \`${cp.at}\` [${cp.event}] ${cp.note}${cp.sha ? ` (${cp.sha})` : ""}`);
      }
    }
    lines.push("");
    lines.push("### Próximas ações");
    if (state.nextActions.length === 0) {
      lines.push("- (nenhuma declarada)");
    } else {
      for (const action of state.nextActions) {
        lines.push(`- ${action}`);
      }
    }
    lines.push("");
    lines.push("### Retomada");
    lines.push("- Contexto completo: `session/CONTEXT.md` (metas, arquitetura, convenções).");
    lines.push("- CLI: `npm run session -- resume` · `npm run session -- checkpoint --note \"...\"`");
    lines.push("- Segunda via (sem sessão): comentário `/session continue` na issue de continuidade,");
    lines.push("  `gh workflow run continuity.yml -f action=resume-report`, ou");
    lines.push("  `gh api repos/<owner>/<repo>/dispatches -f event_type=session-continue`.");
    return lines.join("\n");
  }
}
