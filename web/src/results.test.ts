import test from "node:test";
import assert from "node:assert/strict";
import {
  summarizeResults,
  selectedCharts,
  summarizeEvents,
  type Results,
} from "./results.ts";
const fixture = (): Results => ({
  games: [
    { id: "g1", opponent: "TEST ONLY A", date: "2037-01-01" },
    { id: "g2", opponent: "TEST ONLY B", date: "2037-01-02" },
  ],
  versions: [
    {
      id: "accepted-correction",
      game_id: "g1",
      dataset_type: "box_scores",
      records: [
        {
          playerID: "p1",
          values: {
            points: 0,
            assists: null,
            offensiveRebounds: 2,
            defensiveRebounds: 3,
            twosMade: 1,
            twosMissed: 1,
          },
        },
      ],
    },
    {
      id: "accepted-second-game",
      game_id: "g2",
      dataset_type: "box_scores",
      records: [
        {
          playerID: "p1",
          values: {
            points: 4,
            assists: 0,
            offensiveRebounds: 1,
            defensiveRebounds: null,
            twosMade: 1,
            twosMissed: 7,
          },
        },
      ],
    },
  ],
  charts: [],
});
test("accepted game totals keep explicit zero, missing inputs, derived pairs and weighted percentages separate", () => {
  const result = summarizeResults(fixture(), "p1");
  assert.deepEqual(result.fields.points, {
    value: 4,
    known: 2,
    missing: 0,
    missingGames: 0,
  });
  assert.deepEqual(result.fields.assists, {
    value: 0,
    known: 1,
    missing: 1,
    missingGames: 1,
  });
  assert.deepEqual(result.fields.rebounds, {
    value: 5,
    known: 1,
    missing: 1,
    missingGames: 1,
  });
  assert.equal(result.shooting.twos.makes, 2);
  assert.equal(result.shooting.twos.attempts, 10);
  assert.equal(result.shooting.twos.percentage, 20);
  assert.equal(result.fields.paintTouches.value, null);
  assert.equal(result.fields.paintTouches.missingGames, 2);
});
test("unpublished games and absent players remain missing, duplicate datasets and overflow are unavailable", () => {
  const f = fixture();
  f.games.push({
    id: "unpublished",
    opponent: "TEST ONLY C",
    date: "2037-01-03",
  });
  assert.equal(summarizeResults(f).fields.points.missingGames, 1);
  assert.equal(summarizeResults(f, "other-player").fields.points.value, null);
  f.versions.push(f.versions[0]);
  assert.throws(() => summarizeResults(f), /duplicate/i);
  const big = fixture();
  big.versions[0].records[0].values!.points = Number.MAX_SAFE_INTEGER;
  assert.throws(() => summarizeResults(big), /large/i);
});
test("multiple accepted charts for a game require an explicit choice; they are never summed or silently picked", () => {
  const f = fixture();
  f.charts = [
    {
      id: "a",
      game_id: "g1",
      title: "TEST ONLY A",
      snapshot_id: "s1",
      players: [],
      events: [],
    },
    {
      id: "b",
      game_id: "g1",
      title: "TEST ONLY B",
      snapshot_id: "s2",
      players: [],
      events: [],
    },
  ];
  assert.equal(selectedCharts(f, {}).charts.length, 0);
  assert.deepEqual(selectedCharts(f, {}).ambiguous, ["g1"]);
  assert.equal(selectedCharts(f, { g1: "b" }).charts[0].id, "b");
  assert.equal(selectedCharts(f, { g1: "denied-or-stale" }).charts.length, 0);
});

test("possession totals preserve historical unanswered turnovers and missing team sheets", () => {
  const f = fixture();
  f.versions.push({
    id: "possession-current",
    game_id: "g1",
    dataset_type: "our_possessions",
    records: [
      { values: { paintTouches: 0, offensiveRebounds: null }, turnover: null },
    ],
  });
  const p = summarizeResults(f).possessions.ours;
  assert.equal(p.records, 1);
  assert.equal(p.missingGames, 1);
  assert.equal(p.fields.paintTouches.value, 0);
  assert.equal(p.fields.offensiveRebounds.value, null);
  assert.deepEqual(p.turnovers, { yes: 0, no: 0, unanswered: 1 });
});

test("Real Possessions uses only sheets with known offensive rebounds and answered turnovers", () => {
  const f = fixture();
  f.versions.push({
    id: "pos",
    game_id: "g1",
    dataset_type: "our_possessions",
    records: [{ values: { offensiveRebounds: 0 }, turnover: null }],
  });
  assert.equal(
    summarizeResults(f).possessions.ours.realPossessions.value,
    null,
  );
  f.versions[2].records[0].turnover = false;
  assert.equal(summarizeResults(f).possessions.ours.realPossessions.value, 1);
  assert.equal(
    summarizeResults(f).possessions.ours.realPossessions.missingGames,
    1,
  );
  f.versions[2].records[0].turnover = true;
  assert.equal(summarizeResults(f).possessions.ours.realPossessions.value, 0);
});

test("custom event totals retain rule versions, paired ratios and individual clock readings", () => {
  const template = {
    id: "test",
    version: 1,
    kind: "makes" as const,
    name: "TEST ONLY chances",
    definition: "Synthetic rule",
  };
  const event = {
    kind: "event",
    template,
    values: { made: "1", attempts: "2" },
    clock: 17,
  } as unknown as import("./domain.ts").Capture;
  const groups = summarizeEvents([
    event,
    { ...event, values: { made: "2", attempts: "8" }, clock: 3 },
    { ...event, values: { made: "", attempts: "4" } },
    { ...event, template: { ...template, version: 2 } },
  ]);
  assert.equal(groups.length, 2);
  assert.deepEqual(groups[0].total, { made: 3, attempts: 10, missing: 1 });
  assert.deepEqual(
    groups[0].events.map((e) => e.clock),
    [17, 3, 17],
  );
  const timed = summarizeEvents([
    {
      ...event,
      template: { ...template, kind: "timed" },
      values: { count: "45" },
    },
  ]);
  assert.equal(timed[0].total, null);
});
