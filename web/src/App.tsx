import { useEffect, useRef, useState } from "react";
import type { Ledger, Session, Template } from "./domain.ts";
import {
  entryError,
  demoLedger,
  emptyLedger,
  id,
  newSession,
  readLedger,
  validateLedger,
  saveLedger,
} from "./domain.ts";
import { ManualEntry, ManualSummary } from "./Manual.tsx";
import { CaptureEntry, ShotResults } from "./Capture.tsx";
import { Practice } from "./Practice.tsx";
import { Connected } from "./Connected.tsx";
import { Empty, Icon, Notice, Tabs, download, taskLabel } from "./ui.tsx";
const LOCAL = "teamstats.web.local.v1",
  DEMO = "teamstats.web.demo.v1";
export default function App() {
  const [demo, setDemo] = useState(false),
    [screen, setScreen] = useState("Workspace"),
    [filter, setFilter] = useState("All sessions"),
    [db, setDB] = useState<Ledger>(emptyLedger),
    [work, setWork] = useState<Ledger>(emptyLedger),
    [loaded, setLoaded] = useState(false),
    [loadError, setLoadError] = useState(""),
    [error, setError] = useState(""),
    [storageFailure, setStorageFailure] = useState(false),
    [busy, setBusy] = useState(false),
    [receipt, setReceipt] = useState(""),
    [selected, setSelected] = useState<string | null>(null),
    [tab, setTab] = useState("Plan"),
    [adding, setAdding] = useState<"practice" | "game" | null>(null),
    [theme, setTheme] = useState("system");
  const sharedGuard = useRef(() => true);
  const busyRef = useRef(false),
    file = useRef<HTMLInputElement>(null),
    dock = useRef<HTMLDivElement>(null),
    retryRef = useRef<{ candidate: Ledger; retain?: Ledger } | null>(null);
  const key = demo ? DEMO : LOCAL,
    dirty = JSON.stringify(db) !== JSON.stringify(work),
    session = work.sessions.find((s) => s.id === selected);
  const load = (mode = demo) => {
    try {
      const next = readLedger(localStorage, mode ? DEMO : LOCAL);
      setDB(next);
      setWork(next);
      setLoadError("");
      setLoaded(true);
      setStorageFailure(false);
      setError("");
    } catch (e) {
      setLoadError(entryError(e));
      setLoaded(false);
    }
  };
  useEffect(() => {
    load(false);
  }, []);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);
  useEffect(() => {
    const node = dock.current;
    if (!node) return;
    const resize = new ResizeObserver(() =>
      document.documentElement.style.setProperty(
        "--dock-height",
        node.offsetHeight + "px",
      ),
    );
    resize.observe(node);
    const focus = (event: FocusEvent) => {
      const field = event.target;
      if (
        !(field instanceof HTMLElement) ||
        !field.matches("input,select,textarea")
      )
        return;
      requestAnimationFrame(() => {
        const rect = field.getBoundingClientRect(),
          bar = node.getBoundingClientRect();
        if (rect.bottom > bar.top - 14 || rect.top < 12)
          field.scrollIntoView({ block: "center", behavior: "instant" });
      });
    };
    document.addEventListener("focusin", focus);
    return () => {
      resize.disconnect();
      document.removeEventListener("focusin", focus);
    };
  }, [loaded, screen]);

  useEffect(() => {
    const unload = (e: BeforeUnloadEvent) => {
      if (dirty) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", unload);
    return () => window.removeEventListener("beforeunload", unload);
  }, [dirty]);
  useEffect(() => {
    const storage = (e: StorageEvent) => {
      if (e.key === key) {
        setError(
          "Your drafts changed in another tab. Download unsaved entries, then reload the saved drafts.",
        );
        setStorageFailure(true);
      }
    };
    window.addEventListener("storage", storage);
    return () => window.removeEventListener("storage", storage);
  }, [key]);
  const change = (s: Session) => {
    setWork((w) => ({
      ...w,
      sessions: w.sessions.map((x) => (x.id === s.id ? s : x)),
    }));
    setReceipt("");
  };
  const save = async (candidate = work, retain?: Ledger): Promise<boolean> => {
    if (busyRef.current || !loaded) return false;
    try {
      validateLedger(candidate);
    } catch (e) {
      setError(entryError(e));
      return false;
    }
    busyRef.current = true;
    setBusy(true);
    setError("");
    setReceipt("");
    setWork(retain ?? candidate);
    retryRef.current = { candidate, retain };
    try {
      const next = await saveLedger(
        localStorage,
        key,
        candidate,
        db.revision,
        navigator.locks,
      );
      setDB(next);
      setWork(retain ? { ...retain, revision: next.revision } : next);
      retryRef.current = null;
      setStorageFailure(false);
      setReceipt(
        retain
          ? "Shots and clock saved in this browser. Other entries still need saving."
          : demo
            ? "Sample data saved in this browser only."
            : "Saved in this browser only. Not sent to your team.",
      );
      return true;
    } catch (e) {
      setError(entryError(e));
      setStorageFailure(true);
      return false;
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  const saveCapture = (s: Session) => {
    const retained = {
      ...work,
      sessions: work.sessions.map((v) =>
        v.id === s.id ? { ...v, clock: s.clock, changes: s.changes } : v,
      ),
    };
    const candidate = {
      ...db,
      sessions: db.sessions.map((v) =>
        v.id === s.id
          ? {
              ...v,
              clock: s.clock,
              changes: s.changes,
              savedAt: new Date().toISOString(),
            }
          : v,
      ),
    };
    return save(
      candidate,
      JSON.stringify(work) === JSON.stringify(db) ? undefined : retained,
    );
  };
  const switchMode = async () => {
    if (dirty) {
      setError(
        "Save or download your entries before switching between your drafts and the demo.",
      );
      return;
    }
    if (screen === "Shared team" && !sharedGuard.current()) return;
    const nextMode = !demo;
    if (nextMode && localStorage.getItem(DEMO) === null) {
      try {
        await saveLedger(localStorage, DEMO, demoLedger(), 0, navigator.locks);
      } catch (e) {
        setError(entryError(e));
        return;
      }
    }
    setDemo(nextMode);
    setSelected(null);
    setScreen("Workspace");
    setAdding(null);
    setReceipt("");
    load(nextMode);
  };
  const recovery = () =>
    download(
      "teamstats-browser-draft.json",
      JSON.stringify(
        {
          format: "teamstats-web-recovery-v1",
          mode: demo ? "demo" : "local",
          ledger: work,
        },
        null,
        2,
      ),
    );
  const importRecovery = async (f: File) => {
    try {
      if (f.size > 4_000_000) throw Error("Recovery file exceeds 4 MB.");
      let raw;
      try {
        raw = JSON.parse(await f.text());
      } catch {
        throw Error(
          "This backup could not be read. Choose a TeamStats backup file; your drafts have not changed.",
        );
      }
      if (
        raw.format !== "teamstats-web-recovery-v1" ||
        raw.mode !== (demo ? "demo" : "local")
      )
        throw Error(
          "Choose a backup for this workspace. Sample data and your own drafts stay separate.",
        );
      const restored = validateLedger(raw.ledger);
      const merged = {
        ...work,
        players: [...work.players],
        templates: [...work.templates],
        sessions: [...work.sessions],
      };
      for (const p of restored.players)
        if (!merged.players.some((x) => x.id === p.id)) merged.players.push(p);
      for (const t of restored.templates)
        if (!merged.templates.some((x) => x.id === t.id))
          merged.templates.push(t);
      for (const s of restored.sessions) {
        const old = merged.sessions.find((x) => x.id === s.id);
        if (old && JSON.stringify(old) !== JSON.stringify(s))
          throw Error(
            "This practice or game already has different entries. Keep both backups; nothing was overwritten.",
          );
        if (!old) merged.sessions.push(s);
      }
      await save(merged);
    } catch (e) {
      setError(entryError(e));
    }
  };
  const open = (s: Session) => {
    setSelected(s.id);
    setTab(s.kind === "practice" ? "Plan" : "Court");
    setAdding(null);
  };
  return (
    <div className="app">
      <a className="skip" href="#main">
        Skip to main content
      </a>
      <header className="brand-header">
        <a
          href="#"
          onClick={(e) => {
            e.preventDefault();
            if (screen === "Shared team" && !sharedGuard.current()) return;
            setSelected(null);
            setScreen("Workspace");
          }}
          className="wordmark"
        >
          TEAM<span>STATS</span>
          <small>Practice & game stats</small>
        </a>
        <div className="header-actions">
          <button
            type="button"
            onClick={() =>
              setTheme(
                theme === "dark"
                  ? "light"
                  : theme === "light"
                    ? "system"
                    : "dark",
              )
            }
            aria-label={`Appearance: ${theme}. Change appearance`}
          >
            <Icon name="sun" />
            {theme}
          </button>
          <button
            type="button"
            className={demo ? "demo-active" : ""}
            onClick={() => void switchMode()}
          >
            {demo ? "Exit sample demo" : "Try sample demo"}
          </button>
        </div>
      </header>
      <div className="workspace">
        <aside className="sidebar">
          <nav aria-label="Workspace navigation">
            {[
              ["Workspace", "calendar"],
              ["Shared team", "user"],
              ["Setup", "list"],
            ].map(([name, icon]) => (
              <button
                type="button"
                key={name}
                aria-current={screen === name ? "page" : undefined}
                onClick={() => {
                  if (
                    screen === "Shared team" &&
                    name !== screen &&
                    !sharedGuard.current()
                  )
                    return;
                  setScreen(name);
                  setSelected(null);
                  setAdding(null);
                }}
              >
                <Icon name={icon} />
                {taskLabel(name)}
              </button>
            ))}
          </nav>
          <div className="sidebar-note">
            <strong>
              {demo ? "Sample demo" : "My drafts · browser backups"}
            </strong>
            <p>
              {demo
                ? "TEST ONLY sample players and games. Not sent to a team."
                : "Backups below contain My drafts only, not team entries."}
            </p>
            <button type="button" onClick={recovery}>
              <Icon name="download" />
              Download backup
            </button>
            <button type="button" onClick={() => file.current?.click()}>
              Import backup
            </button>
            <input
              hidden
              type="file"
              accept="application/json,.json"
              ref={file}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) void importRecovery(f);
                e.target.value = "";
              }}
            />
          </div>
        </aside>
        <main id="main">
          <div className={`context-bar ${demo ? "demo" : ""}`}>
            <span>
              {demo
                ? "SAMPLE DEMO · TEST ONLY"
                : screen === "Shared team"
                  ? "TEAM WORKSPACE"
                  : "ONLY IN THIS BROWSER"}
            </span>
            <span>
              {screen === "Shared team" && !demo
                ? "Your team access applies here"
                : dirty
                  ? "Unsaved draft changes"
                  : "Not sent to your team"}
            </span>
          </div>
          {demo && (
            <p className="demo-note muted">
              TEST ONLY sample data. Demo entries stay separate from your drafts
              and team.
            </p>
          )}
          {loadError ? (
            <>
              <Notice error>{loadError}</Notice>
              <div className="actions">
                <button type="button" onClick={() => load()}>
                  Retry load
                </button>
                <button
                  type="button"
                  onClick={() =>
                    download(
                      "teamstats-original-ledger.json",
                      localStorage.getItem(key) ?? "",
                    )
                  }
                >
                  Download unreadable backup
                </button>
              </div>
            </>
          ) : (
            <>
              {error && (
                <Notice error>
                  {error}
                  <div className="actions">
                    {storageFailure && (
                      <button
                        type="button"
                        onClick={() =>
                          void save(
                            retryRef.current?.candidate ?? work,
                            retryRef.current?.retain,
                          )
                        }
                      >
                        Try saving again
                      </button>
                    )}
                    <button type="button" onClick={recovery}>
                      Download unsaved entries
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        if (
                          !dirty ||
                          window.confirm(
                            "Download a backup of your unsaved entries first. Replace them with the last saved drafts?",
                          )
                        )
                          load();
                      }}
                    >
                      Reload saved drafts
                    </button>
                  </div>
                </Notice>
              )}
              {receipt && (
                <p className="receipt" role="status">
                  <Icon name="check" />
                  {receipt}
                </p>
              )}
              {screen === "Shared team" ? (
                demo ? (
                  <Empty title="Leave the demo to use your team">
                    Exit the sample demo, then sign in from Team. Sample players
                    and stats stay here.
                  </Empty>
                ) : (
                  <Connected navigationGuard={sharedGuard} />
                )
              ) : screen === "Setup" ? (
                <>
                  <Setup db={work} change={setWork} />
                  <div className="actions">
                    <button type="button" onClick={recovery}>
                      Download backup
                    </button>
                    <button type="button" onClick={() => file.current?.click()}>
                      Import backup
                    </button>
                  </div>
                </>
              ) : session ? (
                <>
                  <button
                    type="button"
                    className="back"
                    onClick={() => setSelected(null)}
                  >
                    <Icon name="back" />
                    All practices & games
                  </button>
                  <div className="session-banner">
                    <div>
                      <h1>{session.title}</h1>
                      <p>
                        {session.date} ·{" "}
                        {session.kind === "practice"
                          ? "Practice"
                          : `${session.venue === "home" ? "Home" : "Away"} · ${session.season === "playoff" ? "Playoff" : "Regular season"}`}
                      </p>
                    </div>
                    <span>
                      Device-only draft
                      <br />
                      Not reviewed
                    </span>
                  </div>
                  {session.players.length === 0 && (
                    <Notice>
                      No players are included. Add players in Settings, then{" "}
                      <button
                        type="button"
                        disabled={!work.players.length}
                        onClick={() =>
                          change({
                            ...session,
                            players: structuredClone(work.players),
                          })
                        }
                      >
                        Include my players
                      </button>
                      .
                    </Notice>
                  )}
                  <Tabs
                    items={
                      session.kind === "practice"
                        ? [
                            "Plan",
                            "Shooting",
                            "FT conditioning",
                            "Collection",
                            "Results",
                          ]
                        : ["Court", "Manual entry", "Summary"]
                    }
                    value={tab}
                    onChange={setTab}
                    label="Session section"
                  />
                  {session.kind === "practice" ? (
                    <Practice
                      key={session.id}
                      session={session}
                      onChange={change}
                      templates={work.templates}
                      tab={tab}
                    />
                  ) : (
                    <>
                      <div hidden={tab !== "Court"}>
                        <CaptureEntry
                          key={session.id}
                          session={session}
                          save={saveCapture}
                          blocked={busy || storageFailure}
                          templates={work.templates}
                          pending={storageFailure}
                        />
                      </div>
                      <div hidden={tab !== "Manual entry"}>
                        <ManualEntry
                          key={session.id}
                          manual={session.manual}
                          players={session.players}
                          onChange={(manual) => change({ ...session, manual })}
                        />
                      </div>
                      {tab === "Summary" && (
                        <>
                          <ShotResults session={session} />
                          <ManualSummary
                            manual={session.manual}
                            players={session.players}
                          />
                        </>
                      )}
                    </>
                  )}
                </>
              ) : (
                <>
                  <div className="page-heading">
                    <div>
                      <h1>Practices & games</h1>
                      <p>Plan the work. Record what happened.</p>
                    </div>
                    <div className="actions">
                      <button
                        type="button"
                        className="secondary"
                        onClick={() => setAdding("practice")}
                      >
                        <Icon name="plus" />
                        Add practice
                      </button>
                      <button
                        type="button"
                        className="primary"
                        onClick={() => setAdding("game")}
                      >
                        <Icon name="plus" />
                        Add game
                      </button>
                    </div>
                  </div>
                  {adding && (
                    <CreateSession
                      kind={adding}
                      cancel={() => setAdding(null)}
                      create={async (title, date, venue, season) => {
                        try {
                          const s = {
                            ...newSession(adding, title, date, work.players),
                            venue,
                            season,
                          };
                          if (
                            await save({
                              ...work,
                              sessions: [s, ...work.sessions],
                            })
                          )
                            open(s);
                        } catch (e) {
                          setError(entryError(e));
                        }
                      }}
                    />
                  )}
                  <Tabs
                    items={["All sessions", "Practices", "Games"]}
                    value={filter}
                    onChange={setFilter}
                    label="Filter sessions"
                  />
                  {work.sessions.length === 0 ? (
                    <Empty title="Your next session starts here">
                      Add a practice to plan drills, or add a game to record
                      shots and after-game stats.
                    </Empty>
                  ) : (
                    <>
                      {(["practice", "game"] as const)
                        .filter(
                          (kind) =>
                            filter === "All sessions" ||
                            (filter === "Practices"
                              ? kind === "practice"
                              : kind === "game"),
                        )
                        .map((kind) => (
                          <section
                            key={kind}
                            aria-label={
                              kind === "practice" ? "Practices" : "Games"
                            }
                          >
                            <h2>
                              {kind === "practice" ? "Practices" : "Games"}
                            </h2>
                            {work.sessions.some((s) => s.kind === kind) ? (
                              <div className="session-list">
                                <div className="list-head">
                                  <span>Session</span>
                                  <span>Players</span>
                                  <span>Status</span>
                                </div>
                                {work.sessions
                                  .filter((s) => s.kind === kind)
                                  .map((s) => (
                                    <div className="session-row" key={s.id}>
                                      <span className="session-date">
                                        <strong>{s.date.slice(8)}</strong>
                                        <small>
                                          {new Date(
                                            s.date + "T12:00:00",
                                          ).toLocaleDateString(undefined, {
                                            month: "short",
                                          })}
                                        </small>
                                      </span>
                                      <button
                                        type="button"
                                        className="session-title session-open"
                                        onClick={() => open(s)}
                                      >
                                        <strong>{s.title}</strong>
                                        <small>
                                          {s.kind === "practice"
                                            ? "Practice plan & stats"
                                            : "Game shots & after-game stats"}
                                        </small>
                                        <span>
                                          {s.kind === "practice"
                                            ? "Open practice"
                                            : "Open game"}
                                        </span>
                                      </button>
                                      <span className="session-collection">
                                        {s.players.length} players included
                                      </span>
                                      <span className="badge">
                                        Device-only draft
                                      </span>
                                      <button
                                        type="button"
                                        onClick={() => {
                                          setSelected(s.id);
                                          setTab(
                                            s.kind === "practice"
                                              ? "Results"
                                              : "Summary",
                                          );
                                          setAdding(null);
                                        }}
                                      >
                                        View results
                                        <Icon name="arrow" />
                                      </button>
                                    </div>
                                  ))}
                              </div>
                            ) : (
                              <Empty
                                title={
                                  kind === "practice"
                                    ? "No practices yet"
                                    : "No games yet"
                                }
                              >
                                {kind === "practice"
                                  ? "Add a practice to plan drills and record results."
                                  : "Add a game to record shots and after-game stats."}
                              </Empty>
                            )}
                          </section>
                        ))}
                    </>
                  )}
                  <div className="workspace-footer">
                    <h2>Keep each stat sheet separate</h2>
                    <p>
                      Shot-chart entries do not fill in after-game totals.
                      Drafts saved here are not team results.
                    </p>
                  </div>
                </>
              )}
              {screen !== "Shared team" && loaded && (
                <div className="save-dock" ref={dock}>
                  <span>
                    {busy
                      ? "Saving in this browser…"
                      : dirty
                        ? "Unsaved changes — keep this tab open until saved."
                        : "Only in this browser · not sent to your team"}
                  </span>
                  <button
                    type="button"
                    className="primary"
                    disabled={busy || !dirty}
                    onClick={() => void save()}
                  >
                    {busy ? "Saving…" : "Save in this browser"}
                  </button>
                </div>
              )}
            </>
          )}
        </main>
      </div>
      <footer className="app-footer">TeamStats · Test version</footer>
    </div>
  );
}
function CreateSession({
  kind,
  cancel,
  create,
}: {
  kind: "practice" | "game";
  cancel: () => void;
  create: (
    title: string,
    date: string,
    venue: "home" | "away",
    season: "regularSeason" | "playoff",
  ) => Promise<void>;
}) {
  const [title, setTitle] = useState(""),
    [date, setDate] = useState(new Date().toLocaleDateString("en-CA")),
    [venue, setVenue] = useState<"home" | "away">("home"),
    [season, setSeason] = useState<"regularSeason" | "playoff">(
      "regularSeason",
    ),
    [pending, setPending] = useState(false);
  return (
    <form
      className="create-form"
      onSubmit={async (e) => {
        e.preventDefault();
        if (pending) return;
        setPending(true);
        await create(title, date, venue, season);
        setPending(false);
      }}
    >
      <h2>Add {kind}</h2>
      <div className="field-grid">
        <label className="field">
          {kind === "practice" ? "Practice name" : "Opponent"}
          <input
            autoFocus
            required
            value={title}
            maxLength={100}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <label className="field">
          Date
          <input
            required
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
          />
        </label>
        {kind === "game" && (
          <>
            <label className="field">
              Our team is
              <select
                value={venue}
                onChange={(e) => setVenue(e.target.value as "home" | "away")}
              >
                <option value="home">Home</option>
                <option value="away">Away</option>
              </select>
            </label>
            <label className="field">
              Game type
              <select
                value={season}
                onChange={(e) =>
                  setSeason(e.target.value as "regularSeason" | "playoff")
                }
              >
                <option value="regularSeason">Regular season</option>
                <option value="playoff">Playoff</option>
              </select>
            </label>
          </>
        )}
      </div>
      <div className="actions">
        <button type="submit" className="primary" disabled={pending}>
          {pending ? "Creating…" : `Create ${kind} draft`}
        </button>
        <button type="button" onClick={cancel}>
          Cancel
        </button>
      </div>
    </form>
  );
}
function Setup({ db, change }: { db: Ledger; change: (s: Ledger) => void }) {
  const [name, setName] = useState(""),
    [number, setNumber] = useState(""),
    [title, setTitle] = useState(""),
    [kind, setKind] = useState<Template["kind"]>("count"),
    [definition, setDefinition] = useState(""),
    [issue, setIssue] = useState("");
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Draft settings</h1>
          <p>
            Players and stat-tracking templates for your device-only drafts.
          </p>
        </div>
      </div>
      <Notice>
        These players and templates are only for drafts in this browser. Your
        team roster is separate. Earlier entries keep their original player
        details and tracking rules.
      </Notice>
      <section>
        <h2>My draft players</h2>
        <form
          className="inline-form"
          onSubmit={(e) => {
            e.preventDefault();
            if (!name.trim() || !number.trim()) {
              setIssue("Enter a player name and jersey number.");
              return;
            }
            change({
              ...db,
              players: [
                ...db.players,
                {
                  id: id(),
                  name: name.trim(),
                  number: number.trim(),
                  version: 1,
                },
              ],
            });
            setName("");
            setNumber("");
            setIssue("");
          }}
        >
          <label className="field">
            Player name
            <input
              required
              maxLength={100}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </label>
          <label className="field">
            Jersey number
            <input
              required
              maxLength={10}
              value={number}
              onChange={(e) => setNumber(e.target.value)}
            />
          </label>
          <button type="submit">Add player</button>
        </form>
        <div className="ledger-rows">
          {db.players.map((p) => (
            <div className="roster-row" key={p.id}>
              <strong>{p.name}</strong>
              <span>#{p.number}</span>
            </div>
          ))}
        </div>
        {!db.players.length && (
          <p className="muted">
            No players added yet. Add only names you have permission to use.
          </p>
        )}
      </section>
      <section>
        <h2>Stat-tracking templates</h2>
        <p>
          Use your coach’s drill names and what counts. Changing a template does
          not change earlier entries.
        </p>
        <form
          className="create-form"
          onSubmit={(e) => {
            e.preventDefault();
            if (!title.trim() || !definition.trim()) {
              setIssue("Enter the template name and counting rule.");
              return;
            }
            change({
              ...db,
              templates: [
                ...db.templates,
                {
                  id: id(),
                  name: title.trim(),
                  kind,
                  definition: definition.trim(),
                  version: 1,
                },
              ],
            });
            setTitle("");
            setDefinition("");
            setIssue("");
          }}
        >
          <div className="field-grid">
            <label className="field">
              Template name
              <input
                required
                maxLength={100}
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Coach’s name"
              />
            </label>
            <label className="field">
              What to record
              <select
                value={kind}
                onChange={(e) => setKind(e.target.value as Template["kind"])}
              >
                <option value="count">Simple count</option>
                <option value="makes">Makes / attempts</option>
                <option value="timed">Timed event (seconds)</option>
                <option value="note">Note</option>
              </select>
            </label>
          </div>
          <label className="field">
            What counts?
            <textarea
              required
              value={definition}
              maxLength={4000}
              onChange={(e) => setDefinition(e.target.value)}
              placeholder="Enter your coach’s instructions and what counts"
            />
          </label>
          <button type="submit">Add template</button>
        </form>
        {db.templates.map((t) => (
          <div className="template-row" key={t.id}>
            <div>
              <h3>{t.name}</h3>
              <p>{t.definition}</p>
              <small>
                {t.kind === "count"
                  ? "Count"
                  : t.kind === "makes"
                    ? "Makes / attempts"
                    : t.kind === "timed"
                      ? "Timed event"
                      : "Note"}
              </small>
            </div>
            <button
              type="button"
              onClick={() => {
                const rule = window.prompt(
                  "What counts in future practices and games? Earlier entries will keep their original rule.",
                  t.definition,
                );
                if (rule?.trim())
                  change({
                    ...db,
                    templates: db.templates.map((x) =>
                      x.id === t.id
                        ? {
                            ...x,
                            definition: rule.trim(),
                            version: x.version + 1,
                          }
                        : x,
                    ),
                  });
              }}
            >
              Change future rule
            </button>
          </div>
        ))}
      </section>
      {issue && <Notice error>{issue}</Notice>}
      <section>
        <h2>Back up your drafts</h2>
        <p>
          Browser data can be cleared. Download a backup and keep it somewhere
          private: it may contain player information. Nothing is sent
          automatically. This backs up browser drafts, not your team account.
        </p>
        <p className="muted">
          Use only team-approved player information and coach-provided rules.
        </p>
      </section>
    </>
  );
}
