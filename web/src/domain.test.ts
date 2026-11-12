import test from "node:test";
import assert from "node:assert/strict";
import {
  entryError,
  count,
  scoring,
  rebound,
  clockSeconds,
  emptyLedger,
  newSession,
  recordChange,
  undoChange,
  currentEvents,
  saveLedger,
  readLedger,
  shotValueAt,
} from "./domain.ts";

test("court geometry selects twos inside/on the line and threes beyond the arc or corners", () => {
  const at = (x: number, y: number) => shotValueAt({ x: x / 500, y: y / 420 });
  assert.equal(at(250, 57), 2);
  assert.equal(at(250, 314), 2);
  assert.equal(at(250, 315), 2);
  assert.equal(at(250, 316), 3);
  for (const y of [12, 57, 99]) {
    assert.equal(at(33, y), 3);
    assert.equal(at(34, y), 2);
    assert.equal(at(35, y), 2);
    assert.equal(at(465, y), 2);
    assert.equal(at(466, y), 2);
    assert.equal(at(467, y), 3);
  }
  const diagonal = 216 / Math.sqrt(2);
  for (const side of [-1, 1]) {
    assert.equal(at(250 + side * diagonal, 99 + diagonal), 2);
    assert.equal(at(250 + side * (diagonal + 1), 100 + diagonal), 3);
  }
  assert.equal(at(250, 408), 3);
});

test("blank remains missing; zero is explicit; invalid and overflow are rejected", () => {
  assert.equal(count(""), null);
  assert.equal(count("0"), 0);
  for (const x of ["-1", "1.5", "1e3", " 2", "9007199254740992"])
    assert.throws(() => count(x));
});

test("partial scoring is a lower bound, never a fabricated match; misses are irrelevant", () => {
  assert.deepEqual(scoring({ points: "4", threesMade: "7" }), {
    kind: "discrepancy",
    detail: "Entered 4; made baskets imply at least 21.",
  });
  assert.equal(scoring({ points: "4", threesMade: "1" }).kind, "incomplete");
  assert.equal(
    scoring({
      points: "0",
      twosMade: "0",
      threesMade: "0",
      freeThrowsMade: "0",
    }).kind,
    "match",
  );
  assert.equal(
    scoring({
      points: "4",
      twosMade: "0",
      threesMade: "1",
      freeThrowsMade: "0",
    }).kind,
    "discrepancy",
  );
  assert.equal(scoring({ points: "", twosMade: "1" }).kind, "incomplete");
  assert.equal(scoring({ points: "4", twosMade: "-1" }).kind, "invalid");
  assert.equal(
    scoring({ points: "4", threesMade: "9007199254740991" }).kind,
    "invalid",
  );
  assert.equal(
    rebound({ offensiveRebounds: "", defensiveRebounds: "0" }),
    "Not entered",
  );
  assert.equal(
    rebound({ offensiveRebounds: "2", defensiveRebounds: "0" }),
    "2",
  );
});

test("clock recovers elapsed running time without rewriting historical event readings", () => {
  assert.equal(
    clockSeconds(
      {
        period: "P1",
        seconds: 120,
        startedAt: 1000,
        configured: true,
        length: 120,
      },
      5100,
    ),
    115.9,
  );
  assert.equal(
    clockSeconds(
      {
        period: "P1",
        seconds: 120,
        startedAt: 1000,
        configured: true,
        length: 120,
      },
      999999,
    ),
    0,
  );
});

test("capture corrections and Undo retain history and stable event identity", () => {
  const event = {
    id: crypto.randomUUID(),
    kind: "shot" as const,
    team: "ours" as const,
    playerID: "p",
    x: 0.2,
    y: 0.3,
    value: 3 as const,
    made: true,
    label: "",
    note: "",
    at: "2026-11-11T12:00:00Z",
    period: "P1",
    clock: 90,
  };
  let changes = recordChange([], event);
  changes = recordChange(changes, { ...event, made: false });
  assert.equal(currentEvents(changes)[0].made, false);
  changes = undoChange(changes);
  assert.equal(currentEvents(changes)[0].made, true);
  changes = undoChange(changes);
  assert.equal(currentEvents(changes).length, 0);
  assert.equal(changes.length, 4);
  assert.throws(() => undoChange(changes));
});

test("browser durability, stale revision denial, failure preservation and missing values", async () => {
  const locks = {
    request: async (_key: string, fn: () => unknown) => fn(),
  } as never;
  const map = new Map<string, string>();
  const store = {
    getItem: (k: string) => map.get(k) ?? null,
    setItem: (k: string, v: string) => {
      map.set(k, v);
    },
  };
  let db = emptyLedger();
  const s = newSession("game", "TEST ONLY", "2026-11-11", []);
  s.manual.ours = [
    {
      id: crypto.randomUUID(),
      number: 1,
      values: { paintTouches: "", offensiveRebounds: "0" },
      turnover: null,
    },
  ];
  db.sessions = [s];
  db = await saveLedger(store, "synthetic", db, 0, locks);
  assert.equal(
    readLedger(store, "synthetic").sessions[0].manual.ours[0].values
      .paintTouches,
    "",
  );
  assert.equal(
    readLedger(store, "synthetic").sessions[0].manual.ours[0].values
      .offensiveRebounds,
    "0",
  );
  assert.equal(
    readLedger(store, "synthetic").sessions[0].manual.opponent.length,
    0,
  );
  await assert.rejects(
    () => saveLedger(store, "synthetic", db, 0, locks),
    /Another tab/,
  );
  const prior = map.get("synthetic");
  await assert.rejects(() =>
    saveLedger(
      {
        ...store,
        setItem: () => {
          throw Error("Quota exceeded");
        },
      },
      "synthetic",
      db,
      1,
      locks,
    ),
  );
  assert.equal(map.get("synthetic"), prior);
  map.set("broken", "{");
  assert.throws(() => readLedger(store, "broken"), /Nothing was overwritten/);
  assert.equal(map.get("broken"), "{");
});

test("repeated subsecond pauses consume elapsed time rather than losing fractions", () => {
  let c = {
    period: "P1",
    seconds: 60,
    startedAt: null as number | null,
    configured: true,
    length: 60,
  };
  for (let i = 0; i < 10; i++) {
    c.startedAt = i * 10000;
    c = { ...c, seconds: clockSeconds(c, i * 10000 + 900), startedAt: null };
  }
  assert.ok(Math.abs(c.seconds - 51) < 0.00001);
});
test("same-base concurrent saves serialize and reject the loser without false success", async () => {
  const map = new Map<string, string>();
  const store = {
    getItem: (k: string) => map.get(k) ?? null,
    setItem: (k: string, v: string) => {
      map.set(k, v);
    },
  };
  let tail = Promise.resolve();
  const locks = {
    request: async (_key: string, fn: () => unknown) => {
      const prev = tail;
      let release = () => {};
      tail = new Promise<void>((r) => {
        release = r;
      });
      await prev;
      try {
        return fn();
      } finally {
        release();
      }
    },
  } as never;
  const a = emptyLedger(),
    b = emptyLedger();
  a.sessions = [newSession("game", "A", "2026-11-11", [])];
  b.sessions = [newSession("game", "B", "2026-11-11", [])];
  const results = await Promise.allSettled([
    saveLedger(store, "r", a, 0, locks),
    saveLedger(store, "r", b, 0, locks),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(readLedger(store, "r").sessions[0].title, "A");
  assert.equal(b.sessions[0].title, "B");
  await assert.rejects(
    () => saveLedger(store, "r", a, 1),
    /cannot save drafts safely/,
  );
});
test("saved template observations and retained capture history reject malformed inputs", async () => {
  const map = new Map<string, string>();
  const store = {
    getItem: (k: string) => map.get(k) ?? null,
    setItem: (k: string, v: string) => {
      map.set(k, v);
    },
  };
  const locks = {
    request: async (_key: string, fn: () => unknown) => fn(),
  } as never;
  const db = emptyLedger();
  const s = newSession("practice", "TEST ONLY", "2026-11-11", []);
  db.sessions = [s];
  s.observations = [
    {
      id: "o",
      playerID: null,
      template: {
        id: "t",
        name: "TEST ONLY",
        kind: "makes",
        definition: "TEST ONLY observed attempts",
        version: 1,
      },
      values: { made: "2", attempts: "1" },
      note: "",
      at: "bad",
    },
  ];
  await assert.rejects(() => saveLedger(store, "r", db, 0, locks));
  assert.equal(map.size, 0);
  s.observations[0].at = "2026-11-11T12:00:00.000Z";
  s.observations[0].values = { made: "0", attempts: "0" };
  await saveLedger(store, "r", db, 0, locks);
  const event = {
    id: "e",
    kind: "freeThrow" as const,
    team: "opponent" as const,
    playerID: null,
    x: 0.5,
    y: 0.5,
    value: 1 as const,
    made: true,
    label: "",
    note: "",
    at: "bad",
    period: "P1",
    clock: -10,
  };
  db.sessions[0].changes = recordChange([], event);
  await assert.rejects(() => saveLedger(store, "r", db, 1, locks));
  assert.equal(readLedger(store, "r").sessions[0].changes.length, 0);
});

test("unreadable and blocked browser storage errors give recovery steps without echoing contents", () => {
  assert.match(
    entryError(new SyntaxError("private fixture content")),
    /original backup/,
  );
  assert.doesNotMatch(
    entryError(new SyntaxError("private fixture content")),
    /private fixture/,
  );
  assert.match(
    entryError(new DOMException("private storage key", "QuotaExceededError")),
    /download a backup/,
  );
  assert.doesNotMatch(
    entryError(new DOMException("private request detail", "AbortError")),
    /store|private request/,
  );
  assert.doesNotMatch(
    entryError(new DOMException("private file", "NotReadableError")),
    /store|private file/,
  );
  assert.equal(
    entryError(new Error("Makes cannot exceed attempts.")),
    "Makes cannot exceed attempts.",
  );
});
