import { useEffect, useRef, useState } from "react";
import type { Player, Session, Template, Ledger } from "./domain.ts";
import {
  id,
  newSession,
  validateLedger,
  emptyLedger,
  clockSeconds,
} from "./domain.ts";
import { CoreServer, ServerError } from "./server.ts";
import type { Access, Game } from "./server.ts";
import { Practice } from "./Practice.tsx";
import { CaptureEntry, ShotResults } from "./Capture.tsx";
import { Empty, Notice, Tabs, download, useUnsavedGuard } from "./ui.tsx";

import type { NavigationGuard } from "./ui.tsx";
type WebRow = {
  id: string;
  team_id: string;
  kind: "practice" | "game";
  game_id: string | null;
  title: string;
  session_date: string;
  revision: number;
  status: "draft" | "submitted" | "published" | "rejected";
  recorder_user_id: string;
  clock_user_id: string;
  assignment_revision: number;
  clock_revision: number;
  clock_period: string;
  clock_seconds: number;
  clock_started_at: string | null;
  current_snapshot_id: string;
  accepted_snapshot_id: string | null;
  edit_requested_by: string | null;
  contributors: string[];
};
type Document = { schema: 1; session: Omit<Session, "manual" | "clock"> };
type Reply = {
  session: WebRow;
  document: Document | null;
  server_time: string;
  document_scope?: "working" | "accepted" | "unavailable";
  document_snapshot_id?: string;
  document_revision?: number;
  operation_id?: string;
  visibility?: string;
  receivedAt?: number;
};
type Command = {
  id: string;
  action: string;
  session: string;
  revision: number;
  document: Document | null;
  argument: Record<string, unknown>;
};
export function sessionDocument(session: Session): Document {
  const { manual, clock, ...snapshot } = session;
  void manual;
  void clock;
  return { schema: 1, session: snapshot };
}
function clockFor(r: Reply): Session["clock"] {
  const row = r.session;
  const started = row.clock_started_at
    ? (r.receivedAt ?? Date.now()) -
      (Date.parse(r.server_time) - Date.parse(row.clock_started_at))
    : null;
  return {
    period: row.clock_period,
    seconds: Number(row.clock_seconds),
    startedAt: started,
    configured: row.clock_revision > 0,
    // Shared remaining time is fractional; the local-only period-length field is unused.
    length: 0,
  };
}
function sessionFor(r: Reply): Session | null {
  if (!r.document) return null;
  const s = {
    ...r.document.session,
    clock: clockFor(r),
    manual: { box: {}, paint: {}, ours: [], opponent: [] },
  };
  const db: Ledger = { ...emptyLedger(), sessions: [s] };
  validateLedger(db);
  return s;
}
export function WebSessions({
  navigationGuard,
  server,
  team,
  actor,
  access,
  roster,
  games,
  onDenied,
}: {
  server: CoreServer;
  team: string;
  actor: string;
  access: Access;
  roster: Player[];
  games: Game[];
  onDenied: () => void;
  navigationGuard: NavigationGuard;
}) {
  const [clockNow, setClockNow] = useState(Date.now);
  const bufferKey = `teamstats-web-session-buffer:${encodeURIComponent(server.namespace)}:${team}:${actor}`;
  const [rows, setRows] = useState<WebRow[]>([]),
    [reply, setReply] = useState<Reply | null>(null),
    [base, setBase] = useState<WebRow | null>(null),
    [draft, setDraft] = useState<Session | null>(null),
    [dirty, setDirty] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [receipt, setReceipt] = useState(""),
    [tab, setTab] = useState("Plan"),
    [selected, setSelected] = useState<string | null>(null),
    [title, setTitle] = useState(""),
    [date, setDate] = useState(new Date().toLocaleDateString("en-CA")),
    [kind, setKind] = useState<"practice" | "game">("practice"),
    [game, setGame] = useState(""),
    [pending, setPending] = useState<Command | null>(() => {
      try {
        const raw = sessionStorage.getItem(bufferKey + ":pending");
        if (!raw) return null;
        const saved = JSON.parse(raw);
        if (
          saved.actor !== actor ||
          saved.team !== team ||
          !saved.operation?.id ||
          !saved.operation?.session ||
          !Number.isSafeInteger(saved.operation.revision)
        )
          throw Error("Invalid pending marker");
        return saved.operation;
      } catch {
        return {
          id: "unreadable",
          action: "recovery_required",
          session: "",
          revision: 0,
          document: null,
          argument: {},
        };
      }
    }),
    [templateName, setTemplateName] = useState(""),
    [templateKind, setTemplateKind] = useState<Template["kind"]>("count"),
    [definition, setDefinition] = useState(""),
    [recorder, setRecorder] = useState(""),
    [clockUser, setClockUser] = useState(""),
    [available, setAvailable] = useState(false),
    [receiptMissing, setReceiptMissing] = useState(false),
    [clockPeriod, setClockPeriod] = useState("Period 1"),
    [clockRemaining, setClockRemaining] = useState("");
  useUnsavedGuard(navigationGuard, dirty);
  const gate = useRef(false),
    generation = useRef(0),
    dirtyRef = useRef(false),
    rowRef = useRef<WebRow | null>(null);
  useEffect(() => {
    if (!reply?.session.clock_started_at) return;
    const timer = setInterval(() => setClockNow(Date.now()), 500);
    return () => clearInterval(timer);
  }, [reply?.session.clock_started_at]);
  const can = (cap: string) =>
    access.is_owner || access.capabilities.includes(cap);
  const fail = (e: unknown) => {
    const err = e as Error;
    if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code)) {
      setReply(null);
      setBase(null);
      setDraft(null);
      setRows([]);
      generation.current++;
      onDenied();
    }
    setError(err.message);
  };
  const loadList = async () => {
    try {
      await server.access(team);
      const r = await server.rows<WebRow>(
        "web_sessions",
        "*",
        { team_id: team },
        "session_date,id",
      );
      setRows(r);
      setAvailable(true);
    } catch (e) {
      setAvailable(false);
      if (
        e instanceof ServerError &&
        ["42P01", "PGRST205", "42883", "PGRST202"].includes(e.code)
      )
        setError(
          "Shared practice/capture contracts are not activated on this server. Browser-local collection remains available; no shared save or permission is assumed.",
        );
      else fail(e);
    }
  };
  const state = async (sessionID: string, replace = true) => {
    const gen = ++generation.current;
    if (replace) {
      gate.current = true;
      setBusy(true);
    }
    try {
      await server.access(team);
      const { data, error } = await server.client.rpc("web_session_state", {
        p_team_id: team,
        p_session_id: sessionID,
      });
      if (error) throw new ServerError(error.code);
      const r = data as Reply;
      if (gen !== generation.current) return;
      validateReply(r);
      setReply(r);
      rowRef.current = r.session;
      if (replace) {
        const s = sessionFor(r);
        setDraft(s);
        setBase(r.session);
        setDirty(false);
        dirtyRef.current = false;
        setTab(s?.kind === "game" ? "Court" : "Plan");
      } else if (r.document_scope === "unavailable") {
        setDraft(null);
        setBase(null);
        setDirty(false);
        dirtyRef.current = false;
      } else if (
        r.document_scope === "accepted" ||
        r.session.status !== "draft" ||
        !dirtyRef.current
      ) {
        if (dirtyRef.current)
          setError(
            "Working entries remain in this account’s recovery buffer. Only the server-permitted snapshot is displayed.",
          );
        setDraft(sessionFor(r));
        setBase(r.session);
        setDirty(false);
        dirtyRef.current = false;
      }
    } catch (e) {
      if (gen === generation.current) fail(e);
    } finally {
      if (replace && gen === generation.current) {
        gate.current = false;
        setBusy(false);
      }
    }
  };
  const validateReply = (r: Reply) => {
    if (
      !r ||
      r.session.team_id !== team ||
      !Number.isSafeInteger(r.session.revision) ||
      !Number.isSafeInteger(r.session.clock_revision) ||
      !Number.isSafeInteger(r.session.assignment_revision) ||
      !Number.isFinite(Number(r.session.clock_seconds)) ||
      Number(r.session.clock_seconds) < 0 ||
      !Number.isFinite(Date.parse(r.server_time))
    )
      throw Error(
        "Invalid server session/clock response. No snapshot was displayed.",
      );
    r.receivedAt ??= Date.now();
    if (r.document && r.document.session.id !== r.session.id)
      throw Error("Wrong session document identity.");
    if (r.document) sessionFor(r);
  };
  useEffect(() => {
    void loadList();
    if (pending?.session) {
      setSelected(pending.session);
      if (pending.action !== "create") void state(pending.session);
    }
    if (pending?.action === "recovery_required")
      setError(
        "Retained command marker is unreadable. New writes are blocked; keep the original browser recovery data.",
      );
    return () => {
      generation.current++;
    };
  }, [team]);
  useEffect(() => {
    if (!selected || pending?.action === "create") return;
    const timer = setInterval(() => {
      if (document.visibilityState === "visible" && !gate.current)
        void state(selected, false);
    }, 5000);
    return () => clearInterval(timer);
  }, [selected, pending?.id]);
  useEffect(() => {
    const handler = (e: BeforeUnloadEvent) => {
      if (dirtyRef.current) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, []);
  const change = (s: Session) => {
    setDraft(s);
    setDirty(true);
    dirtyRef.current = true;
    setReceipt("");
    try {
      sessionStorage.setItem(
        bufferKey,
        JSON.stringify({ actor, team, base, session: s }),
      );
    } catch {
      setError(
        "Browser recovery storage failed. Keep this tab open and download the retained entries.",
      );
    }
  };
  const apply = (r: Reply, action: string) => {
    validateReply(r);
    setReply(r);
    rowRef.current = r.session;
    if (!action.startsWith("clock_") && action !== "assign") setBase(r.session);
    if (action.startsWith("clock_") || action === "assign") {
      setDraft((old) => (old ? { ...old, clock: clockFor(r) } : old));
    } else {
      setDraft(sessionFor(r));
      setDirty(false);
      dirtyRef.current = false;
    }
    setSelected(r.session.id);
    if (action === "create")
      setTab(r.session.kind === "game" ? "Court" : "Plan");
    setPending(null);
    setReceiptMissing(false);
    try {
      sessionStorage.setItem(
        bufferKey + ":last-confirmed",
        JSON.stringify({
          operation: r.operation_id,
          session: r.session.id,
          revision: r.session.revision,
        }),
      );
      sessionStorage.removeItem(bufferKey + ":pending");
    } catch {
      setError(
        "Server confirmed the operation, but the browser recovery marker could not be cleared. A remount may require receipt lookup.",
      );
    }
    setReceipt(
      `Server confirmed ${action.replaceAll("_", " ")} · revision ${r.session.revision} · clock revision ${r.session.clock_revision}.`,
    );
  };
  const clearPending = () => {
    sessionStorage.removeItem(bufferKey + ":pending");
    setPending(null);
    setReceiptMissing(false);
  };
  const command = async (
    action: string,
    document: Document | null = null,
    argument: Record<string, unknown> = {},
    sessionID = base?.id,
    revision = base?.revision,
  ): Promise<boolean> => {
    if (gate.current || pending || !sessionID || revision === undefined)
      return false;
    gate.current = true;
    setBusy(true);
    setError("");
    setReceipt("");
    const op: Command = {
      id: id(),
      action,
      session: sessionID,
      revision,
      document,
      argument,
    };
    setPending(op);
    try {
      sessionStorage.setItem(
        bufferKey + ":pending",
        JSON.stringify({ actor, team, operation: op }),
      );
      const r = await server.command<Reply>(team, "web_session_command", {
        p_operation_id: op.id,
        p_action: action,
        p_session_id: sessionID,
        p_expected_revision: revision,
        p_document: document,
        p_argument: argument,
      });
      if (r.operation_id !== op.id || r.session.id !== sessionID)
        throw Error("Unmatched command response; reconcile before retrying.");
      apply(r, action);
      await loadList();
      return true;
    } catch (e) {
      if (e instanceof ServerError && !e.uncertain) {
        clearPending();
      }
      fail(e);
      return false;
    } finally {
      gate.current = false;
      setBusy(false);
    }
  };
  const recover = async () => {
    if (!pending || gate.current) return;
    gate.current = true;
    setBusy(true);
    try {
      const r = await server.command<Reply | null>(
        team,
        "web_session_receipt",
        { p_operation_id: pending.id },
      );
      if (!r) {
        setReceiptMissing(true);
        setReceipt(
          "No receipt is visible yet. No write was repeated. Keep this exact command for another lookup or explicit same-command retry.",
        );
        return;
      }
      if (r.visibility === "metadata_only") {
        clearPending();
        setDraft(null);
        setBase(null);
        setReceipt(
          "The prior operation has a receipt, but its document is no longer visible to this account. No content was restored.",
        );
        return;
      }
      if (r.operation_id !== pending.id || r.session.id !== pending.session)
        throw Error("Unmatched recovery receipt.");
      apply(r, pending.action);
      await loadList();
    } catch (e) {
      fail(e);
    } finally {
      gate.current = false;
      setBusy(false);
    }
  };
  const save = async (s: Session) => {
    try {
      const db = { ...emptyLedger(), sessions: [s] };
      validateLedger(db);
      return await command("save", sessionDocument(s), {
        assignment_revision: rowRef.current?.assignment_revision,
      });
    } catch (e) {
      fail(e);
      return false;
    }
  };
  const captureSave = async (s: Session) => {
    if (!reply || !draft) return false;
    if (JSON.stringify(s.changes) !== JSON.stringify(draft.changes)) {
      change(s);
      return save(s);
    }
    const priorClock = clockFor(reply);
    if (JSON.stringify(s.clock) !== JSON.stringify(priorClock)) {
      const current = rowRef.current!;
      const action =
        s.clock.startedAt !== null && priorClock.startedAt === null
          ? "clock_start"
          : s.clock.startedAt === null && priorClock.startedAt !== null
            ? "clock_stop"
            : "clock_set";
      return command(
        action,
        null,
        {
          assignment_revision: current.assignment_revision,
          ...(action === "clock_set"
            ? { period: s.clock.period, seconds: Math.ceil(s.clock.seconds) }
            : {}),
        },
        current.id,
        current.clock_revision,
      );
    }
    return false;
  };
  const retryFrozen = async () => {
    if (
      !pending ||
      !receiptMissing ||
      gate.current ||
      pending.action === "recovery_required"
    )
      return;
    gate.current = true;
    setBusy(true);
    try {
      sessionStorage.setItem(
        bufferKey + ":pending",
        JSON.stringify({ actor, team, operation: pending }),
      );
      const r = await server.command<Reply>(team, "web_session_command", {
        p_operation_id: pending.id,
        p_action: pending.action,
        p_session_id: pending.session,
        p_expected_revision: pending.revision,
        p_document: pending.document,
        p_argument: pending.argument,
      });
      if (r.operation_id !== pending.id)
        throw Error("Unmatched retry receipt.");
      if (r.operation_id !== pending.id || r.session.id !== pending.session)
        throw Error("Unmatched recovery receipt.");
      apply(r, pending.action);
      await loadList();
    } catch (e) {
      fail(e);
    } finally {
      gate.current = false;
      setBusy(false);
    }
  };
  const current = reply?.session,
    isWorking =
      reply?.document_scope !== "accepted" &&
      reply?.document_scope !== "unavailable",
    canRecord =
      !!current &&
      current.status === "draft" &&
      current.recorder_user_id === actor &&
      can("sessions.record") &&
      isWorking;
  const templates =
    draft?.plan.flatMap((p) => (p.template ? [p.template] : [])) ?? [];
  const withClock =
    draft && reply ? { ...draft, clock: clockFor(reply) } : draft;
  return (
    <section className="web-sessions">
      <div className="section-heading">
        <h2>Shared practices & capture</h2>
        <button type="button" disabled={busy} onClick={() => void loadList()}>
          Check availability / Retry
        </button>
      </div>
      <p>
        New session permissions are separate from video grants. Only server
        replies confirm a save, assignment or publication.
      </p>
      {error && <Notice error>{error}</Notice>}
      {receipt && (
        <p role="status" className="receipt">
          {receipt}
        </p>
      )}
      {pending && (
        <Notice>
          Operation pending or uncertain. Do not record another copy.
          <div className="actions">
            <button
              type="button"
              disabled={busy || pending.action === "recovery_required"}
              onClick={() => void recover()}
            >
              Look up this command’s receipt
            </button>
            {receiptMissing && (
              <button
                type="button"
                disabled={busy}
                onClick={() => void retryFrozen()}
              >
                Retry the identical retained command
              </button>
            )}
            <button
              type="button"
              onClick={() =>
                download(
                  "teamstats-pending-web-command.json",
                  JSON.stringify(
                    { actor, team, operation: pending, draft },
                    null,
                    2,
                  ),
                )
              }
            >
              Download pending recovery copy
            </button>
          </div>
        </Notice>
      )}
      {!selected ? (
        <>
          <div className="ledger-rows">
            {rows.map((row) => (
              <button
                type="button"
                key={row.id}
                className="session-row"
                onClick={() => {
                  setSelected(row.id);
                  void state(row.id);
                }}
              >
                <span className="session-title">
                  <strong>{row.title}</strong>
                  <small>
                    {row.session_date} · {row.kind}
                  </small>
                </span>
                <span className="badge">{row.status}</span>
              </button>
            ))}
          </div>
          {available && rows.length === 0 && (
            <Empty title="No shared sessions yet">
              An authorized plan manager can create a practice or linked game
              capture.
            </Empty>
          )}
          {available && can("sessions.manage") && (
            <form
              className="create-form"
              onSubmit={(e) => {
                e.preventDefault();
                try {
                  if (kind === "game" && !game)
                    throw Error("Choose an existing shared game.");
                  const s = newSession(kind, title, date, roster);
                  void command(
                    "create",
                    sessionDocument(s),
                    kind === "game" ? { game_id: game } : {},
                    s.id,
                    0,
                  );
                } catch (e) {
                  fail(e);
                }
              }}
            >
              <h3>Create shared session</h3>
              <div className="field-grid">
                <label className="field">
                  Session kind
                  <select
                    value={kind}
                    onChange={(e) =>
                      setKind(e.target.value as "practice" | "game")
                    }
                  >
                    <option value="practice">Practice</option>
                    <option value="game">Game capture</option>
                  </select>
                </label>
                <label className="field">
                  Session name
                  <input
                    required
                    maxLength={100}
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                  />
                </label>
                <label className="field">
                  Session date
                  <input
                    required
                    type="date"
                    value={date}
                    onChange={(e) => setDate(e.target.value)}
                  />
                </label>
                {kind === "game" && (
                  <label className="field">
                    Existing server game
                    <select
                      required
                      value={game}
                      onChange={(e) => setGame(e.target.value)}
                    >
                      <option value="">Choose a game</option>
                      {games.map((g) => (
                        <option key={g.id} value={g.id}>
                          {g.opponent} · {g.date}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
              </div>
              <button
                type="submit"
                className="primary"
                disabled={busy || !!pending}
              >
                Create server session
              </button>
            </form>
          )}
        </>
      ) : (
        <>
          <button
            type="button"
            className="back"
            onClick={() => {
              if (dirty) {
                setError(
                  "Save or download this retained draft before leaving.",
                );
                return;
              }
              setSelected(null);
              setReply(null);
              setDraft(null);
              setBase(null);
            }}
          >
            Back to shared sessions
          </button>
          {reply && (
            <>
              <div className="session-banner">
                <div>
                  <h2>{current!.title}</h2>
                  <p>
                    {current!.session_date} · {current!.kind}
                  </p>
                </div>
                <span>
                  {reply.document_scope === "accepted"
                    ? "Accepted snapshot"
                    : current!.status}{" "}
                  · revision {reply.document_revision ?? current!.revision}
                  <br />
                  Clock revision {current!.clock_revision} · assignment{" "}
                  {current!.assignment_revision}
                </span>
              </div>
              <div className="actions">
                <button
                  type="button"
                  disabled={busy || !!pending}
                  onClick={() => {
                    if (
                      dirty &&
                      !window.confirm(
                        "Keep a recovery copy of unsaved entries before loading the server snapshot? Cancel keeps editing.",
                      )
                    )
                      return;
                    void state(selected);
                  }}
                >
                  Load server snapshot
                </button>
                <button
                  type="button"
                  onClick={() =>
                    download(
                      "teamstats-shared-session-recovery.json",
                      JSON.stringify(
                        { actor, team, base, draft, pending },
                        null,
                        2,
                      ),
                    )
                  }
                >
                  Download retained entries
                </button>
                <button
                  type="button"
                  disabled={busy || !isWorking || current!.status !== "draft"}
                  onClick={() => {
                    try {
                      const raw = sessionStorage.getItem(bufferKey);
                      if (!raw)
                        throw Error("No retained buffer for this account.");
                      const saved = JSON.parse(raw);
                      if (
                        saved.actor !== actor ||
                        saved.team !== team ||
                        saved.session.id !== selected
                      )
                        throw Error(
                          "Retained entries belong to a different session/account.",
                        );
                      const candidate = {
                        ...emptyLedger(),
                        sessions: [saved.session],
                      };
                      validateLedger(candidate);
                      change({ ...saved.session, clock: clockFor(reply) });
                      setReceipt(
                        "Retained entries recovered in this browser; not server-saved.",
                      );
                    } catch (e) {
                      fail(e);
                    }
                  }}
                >
                  Recover this account’s buffer
                </button>
              </div>
              {(!withClock || !canRecord) && reply && (
                <div className="clock-strip">
                  <div>
                    <strong className="clock">
                      {clockSeconds(
                        clockFor(reply),
                        Math.max(clockNow, reply.receivedAt ?? clockNow),
                      ).toFixed(1)}
                      seconds
                    </strong>
                    <small>
                      {current!.clock_period} · server-anchored manager
                      reference
                    </small>
                  </div>
                  {current!.clock_user_id === actor &&
                    can("sessions.clock") && (
                      <div>
                        <div className="actions">
                          <button
                            type="button"
                            disabled={busy || !!pending}
                            onClick={() =>
                              void command(
                                current!.clock_started_at
                                  ? "clock_stop"
                                  : "clock_start",
                                null,
                                {
                                  assignment_revision:
                                    current!.assignment_revision,
                                },
                                current!.id,
                                current!.clock_revision,
                              )
                            }
                          >
                            {current!.clock_started_at
                              ? "Stop shared clock"
                              : "Start shared clock"}
                          </button>
                        </div>
                        <details>
                          <summary>Set shared clock</summary>
                          <label className="field">
                            Clock period
                            <input
                              value={clockPeriod}
                              onChange={(e) => setClockPeriod(e.target.value)}
                            />
                          </label>
                          <label className="field">
                            Shared clock seconds
                            <input
                              inputMode="numeric"
                              value={clockRemaining}
                              onChange={(e) =>
                                setClockRemaining(e.target.value)
                              }
                            />
                          </label>
                          <button
                            type="button"
                            disabled={
                              busy ||
                              !!pending ||
                              !/^\d+$/.test(clockRemaining) ||
                              !Number.isSafeInteger(Number(clockRemaining))
                            }
                            onClick={() =>
                              void command(
                                "clock_set",
                                null,
                                {
                                  assignment_revision:
                                    current!.assignment_revision,
                                  period: clockPeriod,
                                  seconds: Number(clockRemaining),
                                },
                                current!.id,
                                current!.clock_revision,
                              )
                            }
                          >
                            Set stopped shared clock
                          </button>
                        </details>
                      </div>
                    )}
                </div>
              )}
              {withClock ? (
                <>
                  {current!.status === "draft" && isWorking ? (
                    <>
                      <Tabs
                        items={
                          withClock.kind === "practice"
                            ? [
                                "Plan",
                                "Shooting",
                                "FT conditioning",
                                "Collection",
                                "Results",
                              ]
                            : ["Court", "Results"]
                        }
                        value={tab}
                        onChange={setTab}
                        label="Shared session section"
                      />
                      {withClock.kind === "practice" ? (
                        <fieldset
                          className="entry-fields"
                          disabled={
                            busy ||
                            !!pending ||
                            (!canRecord && !can("sessions.manage"))
                          }
                        >
                          <Practice
                            session={withClock}
                            onChange={change}
                            templates={templates}
                            tab={tab}
                            provenance="Shared proposal — incomplete and unreviewed."
                          />
                        </fieldset>
                      ) : tab === "Court" ? (
                        <CaptureEntry
                          shared
                          session={withClock}
                          save={captureSave}
                          templates={templates}
                          blocked={busy || !!pending || !canRecord}
                          clockBlocked={
                            busy ||
                            !!pending ||
                            current!.clock_user_id !== actor ||
                            !can("sessions.clock")
                          }
                        />
                      ) : (
                        <ShotResults
                          session={withClock}
                          provenance="Shared proposal · not accepted"
                        />
                      )}
                      <div className="shared-save">
                        <span>
                          {dirty
                            ? "Unsaved browser entries"
                            : "Server snapshot loaded"}
                        </span>
                        <button
                          type="button"
                          className="primary"
                          disabled={
                            !dirty ||
                            busy ||
                            !!pending ||
                            (!canRecord && !can("sessions.manage"))
                          }
                          onClick={() => void save(draft!)}
                        >
                          Save shared session draft
                        </button>
                        <button
                          type="button"
                          disabled={dirty || busy || !!pending || !canRecord}
                          onClick={() => void command("submit")}
                        >
                          Submit session for review
                        </button>
                      </div>
                    </>
                  ) : withClock.kind === "practice" ? (
                    <Practice
                      session={withClock}
                      onChange={() => {}}
                      templates={templates}
                      tab="Results"
                      provenance={
                        reply.document_scope === "accepted" ||
                        current!.status === "published"
                          ? "Server-accepted snapshot."
                          : "Shared proposal — not accepted."
                      }
                    />
                  ) : (
                    <ShotResults
                      session={withClock}
                      provenance={
                        reply.document_scope === "accepted" ||
                        current!.status === "published"
                          ? "Server-accepted snapshot"
                          : "Shared proposal · not accepted"
                      }
                    />
                  )}
                </>
              ) : (
                <Empty title="No permitted snapshot available">
                  This account can see session metadata and clock authority, but
                  no working or accepted collection document.
                </Empty>
              )}
              {current!.status === "submitted" &&
                can("sessions.review") &&
                (access.is_owner || !current!.contributors.includes(actor)) && (
                  <div className="actions">
                    <button
                      type="button"
                      disabled={busy || !!pending}
                      onClick={() => {
                        if (
                          window.confirm(
                            "Accept this exact submitted snapshot and retain prior accepted history?",
                          )
                        )
                          void command("review", null, { approve: true });
                      }}
                    >
                      Accept session & publish
                    </button>
                    <button
                      type="button"
                      disabled={busy || !!pending}
                      onClick={() =>
                        void command("review", null, { approve: false })
                      }
                    >
                      Reject session proposal
                    </button>
                  </div>
                )}
              {["published", "submitted", "rejected"].includes(
                current!.status,
              ) &&
                can("sessions.record") &&
                !current!.edit_requested_by && (
                  <button
                    type="button"
                    disabled={busy || !!pending}
                    onClick={() => void command("request_edit")}
                  >
                    Request session correction
                  </button>
                )}
              {current!.edit_requested_by &&
                can("sessions.reopen") &&
                (access.is_owner || current!.edit_requested_by !== actor) && (
                  <button
                    type="button"
                    disabled={busy || !!pending}
                    onClick={() => void command("reopen")}
                  >
                    Approve session correction
                  </button>
                )}
              {can("sessions.manage") && (
                <details>
                  <summary>
                    Recorder assignment and collection definitions
                  </summary>
                  <p>
                    Assignments use existing verified team accounts with the
                    corresponding capabilities. Handoff stops the clock and
                    fences previous writers.
                  </p>
                  <label className="field">
                    Recording account UUID
                    <input
                      value={recorder}
                      onChange={(e) => setRecorder(e.target.value)}
                    />
                  </label>
                  <label className="field">
                    Clock account UUID
                    <input
                      value={clockUser}
                      onChange={(e) => setClockUser(e.target.value)}
                    />
                  </label>
                  <button
                    type="button"
                    disabled={busy || !!pending || !recorder || !clockUser}
                    onClick={() =>
                      void command("assign", null, {
                        recorder_user_id: recorder,
                        clock_user_id: clockUser,
                        assignment_revision: current!.assignment_revision,
                      })
                    }
                  >
                    Confirm recorder handoff
                  </button>
                  {draft && current!.status === "draft" && (
                    <fieldset
                      disabled={busy || !!pending}
                      className="entry-fields"
                    >
                      <form
                        onSubmit={(e) => {
                          e.preventDefault();
                          if (!templateName.trim() || !definition.trim())
                            return;
                          const t: Template = {
                            id: id(),
                            name: templateName.trim(),
                            kind: templateKind,
                            definition: definition.trim(),
                            version: 1,
                          };
                          change({
                            ...draft,
                            plan: [
                              ...draft.plan,
                              {
                                id: id(),
                                name: t.name,
                                minutes: "",
                                instructions: t.definition,
                                template: t,
                              },
                            ],
                          });
                          setTemplateName("");
                          setDefinition("");
                        }}
                      >
                        <h3>Session collection definition</h3>
                        <p>
                          Configure before collection starts; used definitions
                          are frozen with the session.
                        </p>
                        <label className="field">
                          Name
                          <input
                            required
                            value={templateName}
                            onChange={(e) => setTemplateName(e.target.value)}
                            maxLength={100}
                          />
                        </label>
                        <label className="field">
                          Type
                          <select
                            value={templateKind}
                            onChange={(e) =>
                              setTemplateKind(
                                e.target.value as Template["kind"],
                              )
                            }
                          >
                            <option value="count">Count</option>
                            <option value="makes">Makes / attempts</option>
                            <option value="timed">Timed event (seconds)</option>
                            <option value="note">Note</option>
                          </select>
                        </label>
                        <label className="field">
                          Counting rule
                          <textarea
                            required
                            value={definition}
                            onChange={(e) => setDefinition(e.target.value)}
                            maxLength={4000}
                          />
                        </label>
                        <button type="submit">
                          Add definition to this session draft
                        </button>
                      </form>
                    </fieldset>
                  )}
                </details>
              )}
            </>
          )}
        </>
      )}
    </section>
  );
}
