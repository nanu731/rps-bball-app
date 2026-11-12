import { useEffect, useState } from "react";
import type { Capture, Session, Template, Values } from "./domain.ts";
import {
  id,
  clockSeconds,
  formatClock,
  currentEvents,
  recordChange,
  undoChange,
  count,
  validatePair,
  SHOT_COURT,
  shotValueAt,
} from "./domain.ts";
import { Count, Icon, Notice, Scroller } from "./ui.tsx";
const PERIODS = [
  "Quarter 1",
  "Quarter 2",
  "Quarter 3",
  "Quarter 4",
  "Overtime",
];
export function CaptureEntry({
  session: s,
  save,
  blocked,
  templates,
  pending = false,
  clockBlocked = blocked,
  shared = false,
}: {
  session: Session;
  save: (s: Session) => Promise<boolean>;
  blocked: boolean;
  templates: Template[];
  pending?: boolean;
  clockBlocked?: boolean;
  shared?: boolean;
}) {
  const [team, setTeam] = useState<"ours" | "opponent">("ours"),
    [player, setPlayer] = useState(s.players[0]?.id ?? ""),
    [value, setValue] = useState<2 | 3>(2),
    [point, setPoint] = useState<{ x: number; y: number } | null>(null),
    [label, setLabel] = useState(""),
    [note, setNote] = useState(""),
    [correct, setCorrect] = useState<string | null>(null),
    [now, setNow] = useState(Date.now()),
    [minutes, setMinutes] = useState(""),
    [period, setPeriod] = useState(
      PERIODS.includes(s.clock.period)
        ? s.clock.period
        : s.clock.configured
          ? ""
          : "Quarter 1",
    ),
    [remaining, setRemaining] = useState(""),
    [issue, setIssue] = useState(""),
    [clockOpen, setClockOpen] = useState(false),
    [eventValues, setEventValues] = useState<Values>({});
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(timer);
  }, []);
  const seconds = clockSeconds(s.clock, now),
    events = currentEvents(s.changes);
  const correction = events.find((e) => e.id === correct);
  const eventTemplate =
      correction?.template ?? templates.find((t) => t.id === label),
    correctedKind = correction?.kind;
  const selected = s.players.find((p) => p.id === player);
  const choosePoint = (p: { x: number; y: number }) => {
    setPoint(p);
    setValue(shotValueAt(p));
  };
  const push = async (kind: Capture["kind"], made: boolean | null) => {
    try {
      if (team === "ours" && !selected)
        throw Error("Select one of this session’s players first.");
      if (kind === "shot" && !point)
        throw Error(
          "Choose a location first. A tap alone does not record an attempt.",
        );
      if (
        kind === "event" &&
        (!eventTemplate || !eventTemplate.definition.trim())
      )
        throw Error("Choose a configured event template first.");
      if (kind === "event" && eventTemplate?.kind === "makes")
        validatePair({
          made: eventValues.made ?? "",
          attempts: eventValues.attempts ?? "",
        });
      if (
        kind === "event" &&
        ["count", "timed"].includes(eventTemplate?.kind ?? "")
      )
        count(eventValues.count ?? "");
      const prior = events.find((e) => e.id === correct);
      if (prior && prior.kind !== kind)
        throw Error(
          "Finish or cancel this correction before choosing a different event type.",
        );
      const e: Capture = {
        id: prior?.id ?? id(),
        team,
        playerID: team === "ours" ? selected!.id : null,
        kind,
        value: kind === "freeThrow" ? 1 : value,
        made,
        x: kind === "shot" ? point!.x : null,
        y: kind === "shot" ? point!.y : null,
        label: kind === "event" ? eventTemplate!.name : "",
        note: kind === "event" ? note || eventTemplate!.definition : note,
        ...(kind === "event"
          ? {
              template: structuredClone(eventTemplate!),
              values: { ...eventValues },
            }
          : {}),
        at: prior?.at ?? new Date().toISOString(),
        period: prior?.period ?? s.clock.period,
        clock: prior?.clock ?? Math.ceil(clockSeconds(s.clock)),
      };
      if (await save({ ...s, changes: recordChange(s.changes, e) })) {
        setPoint(null);
        setCorrect(null);
        setIssue("");
      }
    } catch (e) {
      setIssue((e as Error).message);
    }
  };
  const clock = async (action: "start" | "stop" | "set") => {
    try {
      let c = {
        ...s.clock,
        seconds: clockSeconds(s.clock),
        startedAt: null as number | null,
      };
      if (action === "set") {
        const n = count(minutes);
        if (
          n === null ||
          n === 0 ||
          n > Math.floor(Number.MAX_SAFE_INTEGER / 60)
        )
          throw Error(
            "Enter a positive whole-number period length in minutes.",
          );
        if (!PERIODS.includes(period))
          throw Error("Choose a quarter or overtime.");
        c = {
          period: period.trim(),
          length: n * 60,
          seconds: n * 60,
          startedAt: null,
          configured: true,
        };
      }
      if (action === "start") {
        if (!c.configured || c.seconds === 0)
          throw Error(
            "Set a period length and remaining time before starting.",
          );
        c.startedAt = Date.now();
      }
      if (await save({ ...s, clock: c })) {
        setIssue("");
        setClockOpen(false);
      }
    } catch (e) {
      setIssue((e as Error).message);
    }
  };
  const chooseCorrection = (e: Capture) => {
    setCorrect(e.id);
    setTeam(e.team);
    setPlayer(e.playerID ?? "");
    setValue(e.value === 3 ? 3 : 2);
    setPoint(e.x === null ? null : { x: e.x, y: e.y! });
    setLabel(e.template?.id ?? "");
    setEventValues(e.values ?? {});
    setNote(e.note);
    setIssue("");
  };
  let known = 0;
  for (const e of events) if (e.kind !== "event" && e.made) known += e.value;
  return (
    <>
      <div className="clock-strip">
        <div>
          <span className="muted">{s.clock.period} · manager reference</span>
          <strong
            className="clock"
            aria-label={`Game clock ${formatClock(seconds)}`}
          >
            {formatClock(seconds)}
          </strong>
          <small>
            {pending
              ? "Pending write — clock state not saved"
              : s.clock.startedAt !== null && seconds > 0
                ? shared
                  ? "Server-anchored shared reference"
                  : "Running on this browser"
                : "Stopped"}{" "}
            · not the official scoreboard
          </small>
        </div>
        <div className="actions">
          <button
            type="button"
            disabled={clockBlocked}
            className="primary"
            onClick={() =>
              void clock(s.clock.startedAt === null ? "start" : "stop")
            }
          >
            {s.clock.startedAt === null ? "Start clock" : "Stop clock"}
          </button>
          <details
            open={clockOpen}
            onToggle={(e) => setClockOpen(e.currentTarget.open)}
          >
            <summary>Set / correct clock</summary>
            <div className="clock-settings">
              <label className="field">
                Period
                <select
                  value={period}
                  onChange={(e) => setPeriod(e.target.value)}
                >
                  {period === "" && (
                    <option value="" disabled>
                      Choose a period
                    </option>
                  )}
                  {PERIODS.map((p) => (
                    <option key={p} value={p}>
                      {p}
                    </option>
                  ))}
                </select>
              </label>
              <Count
                label="Period length (minutes)"
                value={minutes}
                onChange={setMinutes}
              />
              <button
                type="button"
                disabled={clockBlocked}
                onClick={() => void clock("set")}
              >
                Set stopped period
              </button>
              <label className="field">
                Remaining seconds
                <input
                  inputMode="numeric"
                  value={remaining}
                  onChange={(e) => setRemaining(e.target.value)}
                />
              </label>
              <button
                type="button"
                disabled={clockBlocked}
                onClick={() => {
                  try {
                    const n = count(remaining);
                    if (n === null) throw Error("Enter remaining seconds.");
                    void save({
                      ...s,
                      clock: {
                        ...s.clock,
                        seconds: n,
                        startedAt: null,
                        configured: true,
                      },
                    });
                  } catch (e) {
                    setIssue((e as Error).message);
                  }
                }}
              >
                Correct stopped clock
              </button>
            </div>
          </details>
        </div>
      </div>
      <details className="clock-guidance">
        <summary>Clock authority & recovery</summary>
        <p>
          {shared
            ? "Current server assignment controls this reference. Reconnect and reload authority after connection loss; historical event readings are retained."
            : "Clock continues from saved start time after backgrounding/refresh. One browser controls this local reference; historical event readings are retained."}
        </p>
      </details>
      {issue && <Notice error>{issue}</Notice>}
      <div className="section-heading">
        <h2>{correct ? "Correct recorded event" : "Record a field goal"}</h2>
        <span className="badge">
          {shared ? "Shared draft · unreviewed" : "Browser draft only"}
        </span>
      </div>
      <fieldset className="entry-fields" disabled={blocked}>
        <div className="capture-layout">
          <div>
            <div className="player-header">
              <div className="segmented">
                <button
                  type="button"
                  aria-pressed={team === "ours"}
                  onClick={() => {
                    setTeam("ours");
                    setPoint(null);
                  }}
                >
                  Our team
                </button>
                <button
                  type="button"
                  aria-pressed={team === "opponent"}
                  onClick={() => {
                    setTeam("opponent");
                    setPoint(null);
                  }}
                >
                  Opponent
                </button>
              </div>
              {team === "ours" ? (
                <>
                  <div
                    className="player-quick"
                    role="group"
                    aria-label="Quick player selection"
                  >
                    {s.players.map((p) => (
                      <button
                        type="button"
                        key={p.id}
                        aria-pressed={player === p.id}
                        onClick={() => {
                          setPlayer(p.id);
                          setPoint(null);
                        }}
                      >
                        <strong>#{p.number}</strong>
                        <small>{p.name}</small>
                      </button>
                    ))}
                  </div>
                  <label className="field">
                    Player
                    <select
                      value={player}
                      onChange={(e) => {
                        setPlayer(e.target.value);
                        setPoint(null);
                      }}
                    >
                      <option value="">Choose a player</option>
                      {s.players.map((p) => (
                        <option key={p.id} value={p.id}>
                          #{p.number} {p.name}
                        </option>
                      ))}
                    </select>
                  </label>
                </>
              ) : (
                <p className="team-only">Opponent · team-only recording</p>
              )}
            </div>
            <CourtDiagram
              events={events}
              team={team}
              point={point}
              onPick={(p) => {
                if (!blocked) choosePoint(p);
              }}
            />
            <div className="court-commit">
              <div className="segmented">
                <button
                  type="button"
                  aria-pressed={value === 2}
                  onClick={() => setValue(2)}
                >
                  2 points
                </button>
                <button
                  type="button"
                  aria-pressed={value === 3}
                  onClick={() => setValue(3)}
                >
                  3 points
                </button>
              </div>
              <div className="make-miss">
                <button
                  type="button"
                  className="primary"
                  disabled={
                    blocked ||
                    !point ||
                    (team === "ours" && !selected) ||
                    (correctedKind !== undefined && correctedKind !== "shot")
                  }
                  onClick={() => void push("shot", true)}
                >
                  Make
                </button>
                <button
                  type="button"
                  className="secondary"
                  disabled={
                    blocked ||
                    !point ||
                    (team === "ours" && !selected) ||
                    (correctedKind !== undefined && correctedKind !== "shot")
                  }
                  onClick={() => void push("shot", false)}
                >
                  Miss
                </button>
              </div>
              <p className="muted">
                Location selects 2 or 3 points. Adjust if needed, then Make/Miss
                records one observed attempt.
              </p>
            </div>
            <div className="court-caption">
              <span>Schematic half court · on the line counts as 2 points</span>
              <span>{point ? "Location selected" : "Select a location"}</span>
            </div>
            <details>
              <summary>Keyboard / precise location</summary>
              <div className="field-grid">
                {(["x", "y"] as const).map((axis) => (
                  <label className="field" key={axis}>
                    {axis === "x" ? "Horizontal" : "Vertical"} location (%)
                    <input
                      type="range"
                      min="0"
                      max="100"
                      value={(point?.[axis] ?? 0.5) * 100}
                      onChange={(e) =>
                        choosePoint({
                          ...(point ?? { x: 0.5, y: 0.5 }),
                          [axis]: Number(e.target.value) / 100,
                        })
                      }
                    />
                  </label>
                ))}
              </div>
              <button
                type="button"
                onClick={() => choosePoint({ x: 0.5, y: 0.5 })}
              >
                Select center location
              </button>
            </details>
          </div>
          <div className="capture-controls">
            <h3>
              {team === "ours"
                ? (selected?.name ?? "Choose a player")
                : "Opponent"}
            </h3>
            <h3>Free throws</h3>
            <p className="muted">
              Separate from court locations. Record one observed attempt.
            </p>
            <div className="actions">
              <button
                type="button"
                disabled={
                  blocked ||
                  (team === "ours" && !selected) ||
                  (correctedKind !== undefined && correctedKind !== "freeThrow")
                }
                onClick={() => void push("freeThrow", true)}
              >
                FT make
              </button>
              <button
                type="button"
                disabled={
                  blocked ||
                  (team === "ours" && !selected) ||
                  (correctedKind !== undefined && correctedKind !== "freeThrow")
                }
                onClick={() => void push("freeThrow", false)}
              >
                FT miss
              </button>
            </div>
            <h3>Selected observations</h3>
            <label className="field">
              Event definition
              <select
                value={label}
                disabled={blocked || correctedKind === "event"}
                onChange={(e) => {
                  setLabel(e.target.value);
                  setEventValues({});
                  setNote("");
                }}
              >
                <option value="">Choose an event</option>
                {(correctedKind === "event" && eventTemplate
                  ? [eventTemplate]
                  : templates
                ).map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name} · v{t.version}
                  </option>
                ))}
              </select>
            </label>
            {eventTemplate && (
              <>
                <p className="muted">
                  {eventTemplate.definition} · definition v
                  {eventTemplate.version}
                </p>
                {eventTemplate.kind === "count" ||
                eventTemplate.kind === "timed" ? (
                  <Count
                    label={
                      eventTemplate.kind === "timed"
                        ? "Event time (seconds)"
                        : "Observed count"
                    }
                    value={eventValues.count ?? ""}
                    onChange={(v) =>
                      setEventValues({ ...eventValues, count: v })
                    }
                  />
                ) : eventTemplate.kind === "makes" ? (
                  <>
                    <Count
                      label="Event makes"
                      value={eventValues.made ?? ""}
                      onChange={(v) =>
                        setEventValues({ ...eventValues, made: v })
                      }
                    />
                    <Count
                      label="Event attempts"
                      value={eventValues.attempts ?? ""}
                      onChange={(v) =>
                        setEventValues({ ...eventValues, attempts: v })
                      }
                    />
                  </>
                ) : null}
              </>
            )}
            <label className="field">
              Counting rule / context
              <input
                maxLength={500}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Use your coach’s definition"
              />
            </label>
            <button
              type="button"
              disabled={
                blocked ||
                !eventTemplate ||
                (correctedKind !== undefined && correctedKind !== "event") ||
                (eventTemplate.kind === "note" && !note.trim())
              }
              onClick={() => void push("event", null)}
            >
              Record event
            </button>
            {correct && (
              <button
                type="button"
                onClick={() => {
                  setCorrect(null);
                  setPoint(null);
                }}
              >
                Cancel correction
              </button>
            )}
          </div>
        </div>
      </fieldset>
      <div className="section-heading">
        <h2>Recorded observations</h2>
        <button
          type="button"
          disabled={blocked || !s.changes.length}
          onClick={() => {
            try {
              void save({ ...s, changes: undoChange(s.changes) });
            } catch (e) {
              setIssue((e as Error).message);
            }
          }}
        >
          <Icon name="undo" />
          Undo last change
        </button>
      </div>
      <p className="muted">
        {events.length} observations · {known} recorded points across both
        teams, not a final score. {s.changes.length} retained changes.
        Corrections retain original event time and clock reading.
      </p>
      <div className="ledger-rows">
        {[...events].reverse().map((e) => (
          <div className="observation" key={e.id}>
            <div>
              <strong>
                {e.team === "ours"
                  ? (s.players.find((p) => p.id === e.playerID)?.name ??
                    "Player unavailable")
                  : "Opponent"}{" "}
                ·{" "}
                {e.kind === "event"
                  ? e.label
                  : `${e.value === 1 ? "FT" : e.value + "PT"} ${e.made ? "make" : "miss"}`}
              </strong>
              <small>
                {e.period} · {formatClock(e.clock)} ·{" "}
                {e.values
                  ? Object.entries(e.values)
                      .map(([k, v]) => `${k}: ${v || "Not entered"}`)
                      .join(", ")
                  : ""}{" "}
                · {e.note || "No note"}{" "}
                {e.template ? `· definition v${e.template.version}` : ""}
              </small>
            </div>
            <button
              type="button"
              disabled={blocked}
              onClick={() => chooseCorrection(e)}
            >
              Correct
            </button>
          </div>
        ))}
      </div>
      <p className="muted">
        Player, team and time stay attached to each recorded observation. No
        complete-coverage, official-score or shared-publication claim.
      </p>
    </>
  );
}

export function CourtDiagram({
  events,
  team,
  point = null,
  onPick,
}: {
  events: Capture[];
  team: "ours" | "opponent";
  point?: { x: number; y: number } | null;
  onPick?: (point: { x: number; y: number }) => void;
}) {
  return (
    <svg
      className="court"
      role="img"
      aria-label={
        onPick
          ? "Schematic court. Tap a location to select two or three points automatically, adjust if needed, then Make or Miss. Keyboard location controls follow."
          : "Recorded-shot location chart. Marks show observed attempts only; made shots are circles and misses are crosses."
      }
      viewBox={`0 0 ${SHOT_COURT.width} ${SHOT_COURT.height}`}
      onClick={
        onPick
          ? (e) => {
              const r = e.currentTarget.getBoundingClientRect();
              onPick({
                x: Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)),
                y: Math.max(0, Math.min(1, (e.clientY - r.top) / r.height)),
              });
            }
          : undefined
      }
    >
      <rect x="12" y="12" width="476" height="396" rx="2" />
      <path d="M12 408h476M175 12v155h150V12M175 167a75 75 0 0 0 150 0M222 42h56" />
      <path
        d={`M${SHOT_COURT.centerX - SHOT_COURT.radius} 12V${SHOT_COURT.arcY}a${SHOT_COURT.radius} ${SHOT_COURT.radius} 0 0 0 ${2 * SHOT_COURT.radius} 0V12`}
      />
      <circle cx="250" cy="57" r="12" />
      <path d="M190 408a60 60 0 0 1 120 0" />
      {events
        .filter((e) => e.kind === "shot" && e.team === team)
        .map((e) => (
          <g
            key={e.id}
            transform={`translate(${e.x! * 500} ${e.y! * 420})`}
            className={e.made ? "made-marker" : "miss-marker"}
          >
            {e.made ? <circle r="6" /> : <path d="M-5-5 5 5M5-5-5 5" />}
          </g>
        ))}
      {point && (
        <g
          className="provisional"
          transform={`translate(${point.x * 500} ${point.y * 420})`}
        >
          <circle r="11" />
          <path d="M-15 0h30M0-15v30" />
        </g>
      )}
    </svg>
  );
}

export function ShotResults({
  session: s,
  provenance = "Browser draft",
}: {
  session: Session;
  provenance?: string;
}) {
  const [team, setTeam] = useState<"ours" | "opponent">("ours"),
    [player, setPlayer] = useState("all");
  const events = currentEvents(s.changes).filter(
    (e) =>
      e.team === team &&
      (team === "opponent" || player === "all" || e.playerID === player),
  );
  const shots = events.filter((e) => e.kind === "shot"),
    ft = events.filter((e) => e.kind === "freeThrow"),
    points = events.reduce(
      (n, e) => n + (e.kind !== "event" && e.made ? e.value : 0),
      0,
    );
  const result = (value: 1 | 2 | 3) => {
    const attempts = events.filter(
      (e) => e.kind !== "event" && e.value === value,
    );
    const makes = attempts.filter((e) => e.made).length;
    return (
      <tr key={value}>
        <th scope="row">
          {value === 1 ? "Free throws" : `${value}-point field goals`}
        </th>
        <td>{makes}</td>
        <td>{attempts.length}</td>
        <td>
          {attempts.length
            ? ((makes / attempts.length) * 100).toFixed(1) + "%"
            : "Unavailable"}
        </td>
      </tr>
    );
  };
  return (
    <section>
      <div className="section-heading">
        <h2>Recorded-shot results</h2>
        <span className="badge">{provenance} · coverage unconfirmed</span>
      </div>
      <div className="actions">
        <div className="segmented">
          <button
            type="button"
            aria-pressed={team === "ours"}
            onClick={() => setTeam("ours")}
          >
            Our team
          </button>
          <button
            type="button"
            aria-pressed={team === "opponent"}
            onClick={() => setTeam("opponent")}
          >
            Opponent
          </button>
        </div>
        {team === "ours" && (
          <label className="field">
            Shot-chart player
            <select value={player} onChange={(e) => setPlayer(e.target.value)}>
              <option value="all">All included players</option>
              {s.players.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} · #{p.number}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>
      <div className="capture-layout">
        <div>
          <CourtDiagram events={events} team={team} />
          <p className="muted">
            Schematic locations. Circle = make; cross = miss. Free throws have
            no location. {shots.length} field-goal attempts and {ft.length}{" "}
            free-throw attempts recorded.
          </p>
        </div>
        <div>
          <h3>{points} recorded points</h3>
          <p className="muted">
            Entered-data subtotal, not the official score or proof every attempt
            was captured. Never added to manual totals.
          </p>
          <Scroller label="Recorded-shot totals">
            <table>
              <thead>
                <tr>
                  <th>Type</th>
                  <th>Made</th>
                  <th>Attempted</th>
                  <th>Observed %</th>
                </tr>
              </thead>
              <tbody>{[result(2), result(3), result(1)]}</tbody>
            </table>
          </Scroller>
        </div>
      </div>
      <h3>Selected event observations</h3>
      {events.filter((e) => e.kind === "event").length === 0 ? (
        <p className="muted">No selected events recorded.</p>
      ) : (
        events
          .filter((e) => e.kind === "event")
          .map((e) => (
            <div className="observation" key={e.id}>
              <div>
                <strong>
                  {e.label} ·{" "}
                  {s.players.find((p) => p.id === e.playerID)?.name ??
                    "Opponent"}
                </strong>
                <small>
                  {Object.entries(e.values ?? {})
                    .map(([k, v]) => `${k}: ${v || "Not entered"}`)
                    .join(", ")}{" "}
                  · {e.note} · {e.period} {formatClock(e.clock)}
                </small>
                <small>
                  {e.template?.definition} · definition v
                  {e.template?.version ?? "unavailable"}
                </small>
              </div>
            </div>
          ))
      )}
    </section>
  );
}
