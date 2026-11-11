import test from "node:test";
import assert from "node:assert/strict";
import {
  publicConfiguration,
  safeValue,
  decodeManual,
  encodeRecords,
  ServerError,
  CoreServer,
} from "./server.ts";

test("browser configuration rejects secret keys and arbitrary destinations", () => {
  const legacy = (role: string) => "a." + btoa(JSON.stringify({ role })) + ".b";
  assert.equal(
    publicConfiguration("https://example.supabase.co", legacy("anon")).url,
    "https://example.supabase.co",
  );
  assert.throws(() =>
    publicConfiguration("https://example.supabase.co", legacy("service_role")),
  );
  assert.throws(() =>
    publicConfiguration("https://attacker.example", legacy("anon")),
  );
  assert.throws(() =>
    publicConfiguration("https://example.supabase.co/path", legacy("anon")),
  );
});
test("shared count decoding never rounds Int64 values or converts missing to zero", () => {
  assert.equal(safeValue(null), "");
  assert.equal(safeValue(0), "0");
  assert.throws(() => safeValue(9007199254740992));
  assert.throws(() => safeValue("4"));
  const m = {
    box: {},
    paint: {},
    ours: [
      {
        id: "r",
        number: 1,
        values: { paintTouches: "", offensiveRebounds: "0" },
        turnover: null,
      },
    ],
    opponent: [],
  };
  const records = encodeRecords(m, "our_possessions", "g", []);
  const v = {
    id: "v",
    team_id: "t",
    game_id: "g",
    dataset_id: "d",
    dataset_type: "our_possessions" as const,
    author_user_id: "a",
    revision: 1,
    status: "draft" as const,
    records,
    covered_roster: [],
    base_published_version_id: null,
  };
  const decoded = decodeManual([v], "g");
  assert.equal(decoded.ours[0].values.paintTouches, undefined);
  assert.equal(decoded.ours[0].values.offensiveRebounds, "0");
  assert.equal(decoded.ours[0].turnover, null);
  assert.equal(decoded.opponent.length, 0);
});
test("a lost write is uncertain and never advertised as a successful save", () => {
  assert.equal(new ServerError("network", true).uncertain, true);
  assert.equal(new ServerError("42501", true).uncertain, false);
});

test("native uppercase UUIDs decode without losing player values or missingness", () => {
  const g = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    p = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  const v = {
    id: "v",
    team_id: "t",
    game_id: g,
    dataset_id: "d",
    dataset_type: "box_scores" as const,
    author_user_id: "a",
    revision: 1,
    status: "draft" as const,
    records: [
      {
        gameID: g.toUpperCase(),
        playerID: p.toUpperCase(),
        values: { points: 4, defensiveRebounds: 0 },
      },
    ],
    covered_roster: [],
    base_published_version_id: null,
  };
  const m = decodeManual([v], g);
  assert.equal(m.box[p].points, "4");
  assert.equal(m.box[p].defensiveRebounds, "0");
  assert.equal(m.box[p].offensiveRebounds, undefined);
  assert.deepEqual(
    (
      encodeRecords(m, "box_scores", g, [
        { id: p, name: "TEST ONLY", number: "0", version: 1 },
      ])[0] as { values: unknown }
    ).values,
    { points: 4, defensiveRebounds: 0 },
  );
});

// A navigation/account epoch change cannot prove whether a dispatched write committed.
test("account generation change after dispatch retains an uncertain outcome", async () => {
  let server: CoreServer;
  const client = {
    auth: {
      getUser: async () => ({
        data: { user: { id: "synthetic-actor", is_anonymous: false } },
        error: null,
      }),
    },
    rpc: async (name: string) => {
      if (name === "team_access")
        return {
          data: {
            team_id: "synthetic-team",
            capabilities: [],
            access_revision: 1,
          },
          error: null,
        };
      server.epoch++;
      return { data: { saved: true }, error: null };
    },
  };
  server = new CoreServer(client as unknown as CoreServer["client"]);
  await assert.rejects(
    server.command("synthetic-team", "test_only_mutation", {}),
    (e: unknown) => e instanceof ServerError && e.uncertain,
  );
});
