import { BOX_FIELDS, POS_FIELDS, count } from "./domain.ts";
import type { Player, Capture } from "./domain.ts";
import { safeValue } from "./server.ts";
export type Results = {
  games: { id: string; opponent: string; date: string }[];
  versions: {
    id: string;
    game_id: string;
    dataset_type: string;
    records: {
      playerID?: string;
      total?: number | null;
      turnover?: boolean | null;
      number?: number;
      values?: Record<string, number | null>;
    }[];
  }[];
  charts: {
    id: string;
    game_id: string;
    title: string;
    snapshot_id: string;
    players: Player[];
    events: Capture[];
  }[];
};
export type Subtotal = {
  value: number | null;
  known: number;
  missing: number;
  missingGames: number;
};
export function summarizeResults(results: Results, playerID?: string) {
  const versions = new Map<string, Results["versions"][number]>();
  const gameIDs = new Set(results.games.map((g) => g.id));
  if (gameIDs.size !== results.games.length)
    throw Error(
      "Results contain duplicate games. Reload before using these totals.",
    );
  for (const version of results.versions) {
    const key = version.game_id + ":" + version.dataset_type;
    if (!gameIDs.has(version.game_id) || versions.has(key))
      throw Error(
        "Results contain duplicate or unrelated stat sheets. Reload before using these totals.",
      );
    versions.set(key, version);
  }
  const fields: Record<string, Subtotal> = {};
  const shooting = {
    twos: {
      makes: 0,
      attempts: 0,
      percentage: null as number | null,
      missing: 0,
    },
    threes: {
      makes: 0,
      attempts: 0,
      percentage: null as number | null,
      missing: 0,
    },
    freeThrows: {
      makes: 0,
      attempts: 0,
      percentage: null as number | null,
      missing: 0,
    },
  };
  const add = (a: number, b: number) => {
    const sum = a + b;
    if (!Number.isSafeInteger(sum))
      throw Error(
        "These totals are too large to display safely. Use an individual game view.",
      );
    return sum;
  };
  const numeric = (v: number | null | undefined) => count(safeValue(v));
  for (const field of [
    ...BOX_FIELDS.map(([key]) => key),
    "rebounds",
    "paintTouches",
  ]) {
    const total: Subtotal = {
      value: null,
      known: 0,
      missing: 0,
      missingGames: 0,
    };
    for (const game of results.games) {
      const sheet = versions.get(
        game.id +
          ":" +
          (field === "paintTouches" ? "player_paint_touches" : "box_scores"),
      );
      const rows =
        sheet?.records.filter(
          (r) =>
            !playerID || r.playerID?.toLowerCase() === playerID.toLowerCase(),
        ) ?? [];
      let missingGame = !rows.length;
      if (!rows.length) total.missing++;
      for (const row of rows) {
        let value: number | null;
        if (field === "paintTouches") value = numeric(row.total);
        else if (field === "rebounds") {
          const offense = numeric(row.values?.offensiveRebounds),
            defense = numeric(row.values?.defensiveRebounds);
          value =
            offense === null || defense === null ? null : add(offense, defense);
        } else value = numeric(row.values?.[field]);
        if (value === null) {
          total.missing++;
          missingGame = true;
        } else {
          total.value = add(total.value ?? 0, value);
          total.known++;
        }
      }
      if (missingGame) total.missingGames++;
    }
    fields[field] = total;
  }
  for (const [prefix, total] of Object.entries(shooting)) {
    for (const game of results.games) {
      const rows =
        versions
          .get(game.id + ":box_scores")
          ?.records.filter(
            (r) =>
              !playerID || r.playerID?.toLowerCase() === playerID.toLowerCase(),
          ) ?? [];
      if (!rows.length) total.missing++;
      for (const row of rows) {
        const makes = numeric(row.values?.[prefix + "Made"]),
          misses = numeric(row.values?.[prefix + "Missed"]);
        if (makes === null || misses === null) total.missing++;
        else {
          total.makes = add(total.makes, makes);
          total.attempts = add(total.attempts, add(makes, misses));
        }
      }
    }
    if (total.attempts > 0)
      total.percentage = (total.makes / total.attempts) * 100;
  }
  const possessions = Object.fromEntries(
    (["ours", "opponent"] as const).map((team) => {
      const result = {
        records: 0,
        missingGames: 0,
        realPossessions: {
          value: null,
          known: 0,
          missing: 0,
          missingGames: 0,
        } as Subtotal,
        fields: Object.fromEntries(
          POS_FIELDS.map(([field]) => [
            field,
            { value: null, known: 0, missing: 0, missingGames: 0 } as Subtotal,
          ]),
        ),
        turnovers: { yes: 0, no: 0, unanswered: 0 },
      };
      for (const game of results.games) {
        const sheet = versions.get(
          game.id +
            ":" +
            (team === "ours" ? "our_possessions" : "opponent_possessions"),
        );
        if (!sheet) result.missingGames++;
        const rows = sheet?.records ?? [];
        result.records = add(result.records, rows.length);
        for (const row of rows) {
          if (row.turnover === true) result.turnovers.yes++;
          else if (row.turnover === false) result.turnovers.no++;
          else if (row.turnover === null || row.turnover === undefined)
            result.turnovers.unanswered++;
          else
            throw Error(
              "A saved turnover answer could not be read. Reload the game.",
            );
        }
        const real = result.realPossessions;
        const rebounds = rows.map((r) => numeric(r.values?.offensiveRebounds));
        const unanswered = rows.filter(
          (r) => r.turnover === null || r.turnover === undefined,
        ).length;
        if (!rows.length || rebounds.some((n) => n === null) || unanswered) {
          real.missingGames++;
          real.missing += !rows.length
            ? 1
            : rebounds.filter((n) => n === null).length + unanswered;
        } else {
          const offensive = rebounds.reduce<number>(
            (sum, n) => add(sum, n!),
            0,
          );
          const turnovers = rows.filter((r) => r.turnover === true).length;
          real.value = add(
            real.value ?? 0,
            add(rows.length - turnovers, offensive),
          );
          real.known++;
        }
        for (const [field] of POS_FIELDS) {
          const total = result.fields[field];
          let incomplete = !rows.length;
          if (!rows.length) total.missing++;
          for (const row of rows) {
            const value = numeric(row.values?.[field]);
            if (value === null) {
              total.missing++;
              incomplete = true;
            } else {
              total.value = add(total.value ?? 0, value);
              total.known++;
            }
          }
          if (incomplete) total.missingGames++;
        }
      }
      return [team, result];
    }),
  ) as Record<
    "ours" | "opponent",
    {
      records: number;
      missingGames: number;
      realPossessions: Subtotal;
      fields: Record<string, Subtotal>;
      turnovers: { yes: number; no: number; unanswered: number };
    }
  >;
  return { fields, shooting, possessions };
}
export function selectedCharts(
  results: Results,
  selections: Record<string, string>,
) {
  const charts: Results["charts"] = [],
    ambiguous: string[] = [],
    missing: string[] = [];
  for (const game of results.games) {
    const choices = results.charts.filter((c) => c.game_id === game.id);
    const selected =
      choices.find((c) => c.id === selections[game.id]) ??
      (choices.length === 1 && !selections[game.id] ? choices[0] : null);
    if (selected) charts.push(selected);
    else if (choices.length > 1) ambiguous.push(game.id);
    else missing.push(game.id);
  }
  return { charts, ambiguous, missing };
}

// Rule versions stay separate; a clock reading is context, never an additive count.
export function summarizeEvents(events: Capture[]) {
  const groups = new Map<
    string,
    {
      template: NonNullable<Capture["template"]>;
      events: Capture[];
      total: { made: number; attempts: number; missing: number } | null;
    }
  >();
  for (const event of events.filter((e) => e.kind === "event" && e.template)) {
    const template = event.template!,
      key = template.id + ":" + template.version;
    let group = groups.get(key);
    if (!group) {
      group = {
        template,
        events: [],
        total: ["count", "makes"].includes(template.kind)
          ? { made: 0, attempts: 0, missing: 0 }
          : null,
      };
      groups.set(key, group);
    }
    if (JSON.stringify(group.template) !== JSON.stringify(template))
      throw Error(
        "Recorded event rules disagree. Inspect the individual chart before using totals.",
      );
    group.events.push(event);
    if (group.total) {
      const made = count(
          event.values?.[template.kind === "count" ? "count" : "made"] ?? "",
        ),
        attempts =
          template.kind === "count" ? 0 : count(event.values?.attempts ?? "");
      if (made === null || attempts === null) group.total.missing++;
      else {
        if (template.kind === "makes" && made > attempts)
          throw Error(
            "Recorded event makes exceed attempts. Inspect the individual chart.",
          );
        group.total.made += made;
        group.total.attempts += attempts;
        if (
          !Number.isSafeInteger(group.total.made) ||
          !Number.isSafeInteger(group.total.attempts)
        )
          throw Error("Recorded event totals are too large to display safely.");
      }
    }
  }
  return [...groups.values()];
}
