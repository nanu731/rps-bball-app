export const BOX_FIELDS = [
  ["points", "PTS", "Points"],
  ["offensiveRebounds", "OREB", "Offensive rebounds"],
  ["defensiveRebounds", "DREB", "Defensive rebounds"],
  ["assists", "AST", "Assists"],
  ["turnovers", "TO", "Turnovers"],
  ["steals", "STL", "Steals"],
  ["blocks", "BLK", "Blocks"],
  ["fouls", "PF", "Fouls"],
  ["chargesDrawn", "CHG", "Charges drawn"],
  ["twosMade", "2PM", "Twos made"],
  ["twosMissed", "2P−", "Twos missed"],
  ["threesMade", "3PM", "Threes made"],
  ["threesMissed", "3P−", "Threes missed"],
  ["freeThrowsMade", "FTM", "Free throws made"],
  ["freeThrowsMissed", "FT−", "Free throws missed"],
] as const;
export const POS_FIELDS = [
  ["paintTouches", "PT", "Paint touches"],
  ["offensiveRebounds", "OREB", "Offensive rebounds"],
  ...BOX_FIELDS.slice(9),
] as readonly (readonly string[])[];
export type Values = Record<string, string>;
export type Player = {
  id: string;
  name: string;
  number: string;
  version: number;
};
export type Template = {
  id: string;
  name: string;
  kind: "count" | "makes" | "timed" | "note";
  definition: string;
  version: number;
};
export type PlanItem = {
  id: string;
  name: string;
  minutes: string;
  instructions: string;
  template?: Template;
};
export type Pair = { made: string; attempts: string };
export type Clock = {
  period: string;
  seconds: number;
  startedAt: number | null;
  configured: boolean;
  length: number;
};
export type Observation = {
  id: string;
  playerID: string | null;
  template: Template;
  values: Values;
  note: string;
  at: string;
  supersedes?: string;
  withdrawn?: boolean;
  correctedAt?: string;
};
export type Capture = {
  id: string;
  kind: "shot" | "freeThrow" | "event";
  team: "ours" | "opponent";
  playerID: string | null;
  x: number | null;
  y: number | null;
  value: 1 | 2 | 3;
  made: boolean | null;
  label: string;
  note: string;
  at: string;
  period: string;
  clock: number;
  template?: Template;
  values?: Values;
};
export type Change = {
  id: string;
  before: Capture | null;
  after: Capture | null;
  eventID: string;
  at: string;
  undoOf?: string;
};
export type Possession = {
  id: string;
  number: number;
  values: Values;
  turnover: boolean | null;
};
export type Manual = {
  box: Record<string, Values>;
  paint: Values;
  ours: Possession[];
  opponent: Possession[];
};
export type Session = {
  id: string;
  kind: "practice" | "game";
  title: string;
  date: string;
  venue: "home" | "away";
  season: "regularSeason" | "playoff";
  players: Player[];
  spots: string[];
  protocol: string;
  plan: PlanItem[];
  shooting: Record<string, Record<string, Pair>>;
  ft: Record<string, Pair>;
  observations: Observation[];
  changes: Change[];
  clock: Clock;
  manual: Manual;
  savedAt: string;
};
export type Ledger = {
  schema: 1;
  revision: number;
  players: Player[];
  templates: Template[];
  sessions: Session[];
};
export const id = () => crypto.randomUUID();
export const emptyLedger = (): Ledger => ({
  schema: 1,
  revision: 0,
  players: [],
  templates: [],
  sessions: [],
});
export function count(raw: string): number | null {
  if (raw === "") return null;
  if (!/^\d+$/.test(raw) || !Number.isSafeInteger(Number(raw)))
    throw Error(
      "Enter a nonnegative whole number up to 9,007,199,254,740,991, or leave blank.",
    );
  return Number(raw);
}
export const validCount = (raw: string) => {
  try {
    count(raw);
    return true;
  } catch {
    return false;
  }
};
export const shown = (raw: string | number | null | undefined) =>
  raw === undefined || raw === null || raw === "" ? "Not entered" : String(raw);
export function sumKnown(raw: (string | undefined)[]) {
  let total = 0n,
    missing = 0;
  for (const s of raw) {
    const v = count(s ?? "");
    if (v === null) missing++;
    else total += BigInt(v);
  }
  if (total > BigInt(Number.MAX_SAFE_INTEGER))
    throw Error("Entered subtotal exceeds the supported range.");
  return { total: Number(total), missing };
}
export function scoring(v: Values): {
  kind: "incomplete" | "match" | "discrepancy" | "invalid";
  detail: string;
} {
  try {
    const points = count(v.points ?? ""),
      makes = [
        count(v.twosMade ?? ""),
        count(v.threesMade ?? ""),
        count(v.freeThrowsMade ?? ""),
      ];
    if (points === null)
      return {
        kind: "incomplete",
        detail: "Check incomplete — points not entered.",
      };
    const subtotal = makes.reduce<bigint>(
      (s, n, i) => s + BigInt(n ?? 0) * BigInt([2, 3, 1][i]),
      0n,
    );
    if (subtotal > BigInt(Number.MAX_SAFE_INTEGER))
      return {
        kind: "invalid",
        detail:
          "Scoring check unavailable — total exceeds the supported range.",
      };
    const complete = makes.every((n) => n !== null),
      implied = Number(subtotal);
    if (complete && implied === points)
      return {
        kind: "match",
        detail: `Entered points and made baskets agree: ${points}.`,
      };
    if (complete || implied > points)
      return {
        kind: "discrepancy",
        detail: `Entered ${points}; made baskets imply ${complete ? "" : "at least "}${implied}.`,
      };
    return {
      kind: "incomplete",
      detail:
        "Check incomplete — missing made-basket counts; no proven disagreement.",
    };
  } catch {
    return {
      kind: "invalid",
      detail: "Scoring check unavailable — fix invalid counts.",
    };
  }
}
export function rebound(v: Values): string {
  try {
    const a = count(v.offensiveRebounds ?? ""),
      b = count(v.defensiveRebounds ?? "");
    if (a === null || b === null) return "Not entered";
    const n = BigInt(a) + BigInt(b);
    return n > BigInt(Number.MAX_SAFE_INTEGER)
      ? "Unavailable (overflow)"
      : String(n);
  } catch {
    return "Unavailable (invalid counts)";
  }
}
export function percentage(made: string, attempts: string): string {
  const m = count(made),
    a = count(attempts);
  if (m === null || a === null || a === 0) return "Unavailable";
  if (m > a) throw Error("Makes cannot exceed attempts.");
  return `${((m / a) * 100).toFixed(1)}%`;
}
export function validatePair(p: Pair) {
  const m = count(p.made),
    a = count(p.attempts);
  if (m !== null && a !== null && m > a)
    throw Error("Makes cannot exceed attempts.");
  return p;
}
export function clockSeconds(c: Clock, now = Date.now()) {
  return Math.max(
    0,
    c.seconds -
      (c.startedAt === null ? 0 : Math.max(0, (now - c.startedAt) / 1000)),
  );
}
export const formatClock = (n: number) =>
  `${Math.floor(Math.ceil(n) / 60)}:${String(Math.ceil(n) % 60).padStart(2, "0")}`;
export function newSession(
  kind: Session["kind"],
  title: string,
  date: string,
  players: Player[],
): Session {
  if (!title.trim() || title.trim().length > 100)
    throw Error("Enter a name or opponent (up to 100 characters).");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(date)))
    throw Error("Choose a valid date.");
  return {
    id: id(),
    kind,
    title: title.trim(),
    date,
    venue: "home",
    season: "regularSeason",
    players: structuredClone(players),
    spots: Array.from({ length: 9 }, (_, i) => `Spot ${i + 1}`),
    protocol: "",
    plan: [],
    shooting: {},
    ft: {},
    observations: [],
    changes: [],
    clock: {
      period: "Period 1",
      seconds: 0,
      startedAt: null,
      configured: false,
      length: 0,
    },
    manual: { box: {}, paint: {}, ours: [], opponent: [] },
    savedAt: new Date().toISOString(),
  };
}
export function currentEvents(changes: Change[]): Capture[] {
  const events = new Map<string, Capture>();
  const seen = new Set<string>();
  for (const c of changes) {
    if (seen.has(c.id)) throw Error("Duplicate change identity.");
    seen.add(c.id);
    if (
      JSON.stringify(events.get(c.eventID) ?? null) !== JSON.stringify(c.before)
    )
      throw Error("Correction history does not match its before-image.");
    if (c.after) {
      if (c.after.id !== c.eventID) throw Error("Changed event identity.");
      events.set(c.eventID, c.after);
    } else events.delete(c.eventID);
  }
  return [...events.values()];
}
export function recordChange(changes: Change[], event: Capture): Change[] {
  const before = currentEvents(changes).find((e) => e.id === event.id) ?? null;
  const next = [
    ...changes,
    {
      id: id(),
      eventID: event.id,
      before,
      after: event,
      at: new Date().toISOString(),
    },
  ];
  currentEvents(next);
  return next;
}
export function undoChange(changes: Change[]): Change[] {
  const undone = new Set(changes.flatMap((c) => (c.undoOf ? [c.undoOf] : [])));
  const last = [...changes]
    .reverse()
    .find((c) => !c.undoOf && !undone.has(c.id));
  if (!last) throw Error("No remaining change to undo.");
  const events = currentEvents(changes);
  const before = events.find((e) => e.id === last.eventID) ?? null;
  if (JSON.stringify(before) !== JSON.stringify(last.after))
    throw Error("A later correction needs review before Undo.");
  const next = [
    ...changes,
    {
      id: id(),
      eventID: last.eventID,
      before,
      after: last.before,
      at: new Date().toISOString(),
      undoOf: last.id,
    },
  ];
  currentEvents(next);
  return next;
}
export function currentObservations(
  observations: Observation[],
): Observation[] {
  const superseded = new Set(
    observations.flatMap((o) => (o.supersedes ? [o.supersedes] : [])),
  );
  return observations.filter((o) => !superseded.has(o.id) && !o.withdrawn);
}
export function validateLedger(db: Ledger): Ledger {
  if (
    !db ||
    db.schema !== 1 ||
    !Number.isSafeInteger(db.revision) ||
    db.revision < 0 ||
    !Array.isArray(db.players) ||
    !Array.isArray(db.templates) ||
    !Array.isArray(db.sessions)
  )
    throw Error(
      "Unsupported or damaged local ledger. Original bytes were kept.",
    );
  const ids = new Set<string>();
  const identity = (x: string) => {
    if (typeof x !== "string" || !x || ids.has(x))
      throw Error("Duplicate or missing identity.");
    ids.add(x);
  };
  for (const p of db.players) {
    identity(p.id);
    if (!p.name?.trim() || typeof p.number !== "string")
      throw Error("Invalid local player.");
  }
  for (const t of db.templates) {
    identity(t.id);
    if (
      !t.name?.trim() ||
      !["count", "makes", "timed", "note"].includes(t.kind)
    )
      throw Error("Invalid template.");
  }
  for (const s of db.sessions) {
    identity(s.id);
    if (
      !s.title?.trim() ||
      !["practice", "game"].includes(s.kind) ||
      !Array.isArray(s.players) ||
      s.spots?.length !== 9 ||
      !Array.isArray(s.plan) ||
      !Array.isArray(s.observations)
    )
      throw Error("Invalid session.");
    const players = new Set(s.players.map((p) => p.id));
    if (players.size !== s.players.length)
      throw Error("Duplicate session player.");
    if (
      !s.clock ||
      !Number.isFinite(s.clock.seconds) ||
      s.clock.seconds < 0 ||
      s.clock.seconds > Number.MAX_SAFE_INTEGER ||
      !Number.isSafeInteger(s.clock.length) ||
      s.clock.length < 0 ||
      (s.clock.startedAt !== null && !Number.isFinite(s.clock.startedAt))
    )
      throw Error("Invalid clock.");
    for (const row of Object.values(s.shooting))
      for (const p of Object.values(row)) validatePair(p);
    for (const p of Object.values(s.ft)) validatePair(p);
    for (const v of Object.values(s.manual.box))
      for (const n of Object.values(v)) count(n);
    for (const n of Object.values(s.manual.paint)) count(n);
    for (const team of ["ours", "opponent"] as const)
      s.manual[team].forEach((r, i) => {
        if (
          !r.id ||
          r.number !== i + 1 ||
          ![null, true, false].includes(r.turnover)
        )
          throw Error("Invalid independent possession numbering.");
        for (const n of Object.values(r.values)) count(n);
      });
    for (const item of s.plan) {
      if (
        typeof item.name !== "string" ||
        typeof item.instructions !== "string" ||
        item.name.length > 100 ||
        item.instructions.length > 4000
      )
        throw Error("Invalid practice plan.");
      count(item.minutes);
    }
    const iso = (value: string) =>
      typeof value === "string" &&
      /^\d{4}-\d{2}-\d{2}T/.test(value) &&
      Number.isFinite(Date.parse(value));
    const observationIDs = new Set<string>();
    for (const o of s.observations) {
      if (
        observationIDs.has(o.id) ||
        (o.supersedes && !observationIDs.has(o.supersedes))
      )
        throw Error("Invalid observation correction lineage.");
      observationIDs.add(o.id);
      if (
        !o.id ||
        !iso(o.at) ||
        (o.playerID !== null && !players.has(o.playerID)) ||
        !o.template?.name?.trim() ||
        !o.template.definition?.trim() ||
        !Number.isSafeInteger(o.template.version) ||
        o.template.version < 1 ||
        !["count", "makes", "timed", "note"].includes(o.template.kind) ||
        typeof o.note !== "string" ||
        o.note.length > 4000
      )
        throw Error("Invalid observation definition, identity or time.");
      if (o.template.kind === "makes")
        validatePair({
          made: o.values.made ?? "",
          attempts: o.values.attempts ?? "",
        });
      else if (o.template.kind === "count" || o.template.kind === "timed")
        count(o.values.count ?? "");
      else if (!o.note.trim() && !o.withdrawn)
        throw Error("Enter the observation note.");
    }
    for (const team of ["ours", "opponent"] as const) {
      const seen = new Set<string>();
      for (const r of s.manual[team]) {
        if (seen.has(r.id)) throw Error("Duplicate possession identity.");
        seen.add(r.id);
      }
    }
    currentEvents(s.changes);
    for (const change of s.changes) {
      if (!iso(change.at)) throw Error("Invalid correction time.");
      if (
        change.before &&
        change.after &&
        (change.before.at !== change.after.at ||
          change.before.clock !== change.after.clock ||
          change.before.period !== change.after.period)
      )
        throw Error(
          "Correction cannot rewrite the original event clock or time.",
        );
      for (const e of [change.before, change.after]) {
        if (!e) continue;
        if (
          !["shot", "freeThrow", "event"].includes(e.kind) ||
          !["ours", "opponent"].includes(e.team) ||
          (e.team === "ours" && (!e.playerID || !players.has(e.playerID))) ||
          (e.team === "opponent" && e.playerID !== null) ||
          !iso(e.at) ||
          !Number.isSafeInteger(e.clock) ||
          e.clock < 0 ||
          !e.period?.trim() ||
          typeof e.note !== "string" ||
          e.note.length > 4000 ||
          (e.kind === "shot" &&
            (![2, 3].includes(e.value) ||
              e.x === null ||
              e.y === null ||
              !Number.isFinite(e.x) ||
              !Number.isFinite(e.y) ||
              e.x < 0 ||
              e.x > 1 ||
              e.y < 0 ||
              e.y > 1)) ||
          (e.kind !== "shot" && (e.x !== null || e.y !== null)) ||
          (e.kind === "freeThrow" && e.value !== 1) ||
          (e.kind !== "event" && typeof e.made !== "boolean") ||
          (e.kind === "event" &&
            (e.made !== null || !e.label.trim() || !e.note.trim()))
        )
          throw Error("Invalid captured event or retained history.");
        if (e.kind === "event" && e.template) {
          if (
            !e.template.definition.trim() ||
            !e.template.name.trim() ||
            !Number.isSafeInteger(e.template.version)
          )
            throw Error("Invalid event definition.");
          if (e.template.kind === "makes")
            validatePair({
              made: e.values?.made ?? "",
              attempts: e.values?.attempts ?? "",
            });
          else if (e.template.kind === "count" || e.template.kind === "timed")
            count(e.values?.count ?? "");
        }
      }
    }
  }
  return db;
}
export interface Store {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}
export function readLedger(store: Store, key: string): Ledger {
  const raw = store.getItem(key);
  if (raw === null) return emptyLedger();
  try {
    return validateLedger(JSON.parse(raw));
  } catch {
    throw Error(
      "Could not load this browser’s ledger. Its stored bytes were preserved. Retry or download the original for recovery.",
    );
  }
}
function writeLedger(
  store: Store,
  key: string,
  db: Ledger,
  expected: number,
): Ledger {
  const current = readLedger(store, key);
  if (current.revision !== expected)
    throw Error(
      "Another tab saved newer work. Keep this draft, download a recovery copy, then reload the latest ledger.",
    );
  const next = validateLedger({ ...db, revision: expected + 1 });
  const bytes = JSON.stringify(next);
  if (bytes.length > 4_000_000)
    throw Error(
      "This browser draft is too large. Download a recovery copy before continuing.",
    );
  store.setItem(key, bytes);
  if (store.getItem(key) !== bytes)
    throw Error(
      "Could not confirm browser storage. Keep this draft and Retry.",
    );
  return next;
}
export function demoLedger(): Ledger {
  const db = emptyLedger();
  db.players = [
    { id: id(), name: "TEST ONLY Player A", number: "0", version: 1 },
    { id: id(), name: "TEST ONLY Player B", number: "1", version: 1 },
  ];
  const practice = newSession(
    "practice",
    "TEST ONLY shooting practice",
    "2026-11-11",
    db.players,
  );
  practice.plan = [
    {
      id: id(),
      name: "Nine-spot shooting",
      minutes: "12",
      instructions:
        "Configure spot labels and the coach’s protocol before real collection.",
    },
    {
      id: id(),
      name: "Free-throw conditioning",
      minutes: "",
      instructions: "Enter observed makes and attempts. Protocol not supplied.",
    },
  ];
  db.sessions = [
    practice,
    newSession("game", "TEST ONLY opponent", "2026-11-11", db.players),
  ];
  return db;
}

export async function saveLedger(
  store: Store,
  key: string,
  db: Ledger,
  expected: number,
  locks?: { request: (key: string, fn: () => Ledger) => Promise<Ledger> },
): Promise<Ledger> {
  if (!locks)
    throw Error(
      "This browser lacks safe cross-tab locking. Keep this draft and download a recovery copy; use a browser supporting Web Locks to save.",
    );
  return locks.request(key, () => writeLedger(store, key, db, expected));
}
