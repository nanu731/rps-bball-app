import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Manual, Player, Possession, Values } from "./domain.ts";
import { count, validCount, BOX_FIELDS, POS_FIELDS } from "./domain.ts";
export type Access = {
  team_id: string;
  user_id: string;
  is_owner: boolean;
  can_propose_stats: boolean;
  capabilities: string[];
  access_revision: number;
};
export type Team = { id: string; name: string };
export type Game = {
  id: string;
  team_id: string;
  date: string;
  opponent: string;
  home_away: "home" | "away";
  game_type: "regularSeason" | "playoff";
  publication_generation: number;
};
export type Kind =
  | "box_scores"
  | "our_possessions"
  | "opponent_possessions"
  | "player_paint_touches";
export type Version = {
  id: string;
  team_id: string;
  game_id: string;
  dataset_id: string;
  dataset_type: Kind;
  author_user_id: string;
  revision: number;
  status:
    | "draft"
    | "completed"
    | "submitted"
    | "published"
    | "rejected"
    | "superseded";
  records: Record<string, unknown>[];
  covered_roster: { id: string; version: number }[];
  base_published_version_id: string | null;
};
export type EditRequest = {
  id: string;
  team_id: string;
  source_version_id: string;
  requester_user_id: string;
  revision: number;
  status: string;
  working_version_id: string | null;
  reason: string;
};
export const KIND_LABEL: Record<Kind, string> = {
  box_scores: "Player box scores",
  our_possessions: "Our possessions",
  opponent_possessions: "Opponent possessions",
  player_paint_touches: "Player paint touches",
};
export class ServerError extends Error {
  code: string;
  uncertain: boolean;
  constructor(code: string, write = false) {
    super(
      code === "42501" || code === "401" || code === "403"
        ? "Access denied or session expired. Protected content has been concealed."
        : code === "PT409" || code === "409"
          ? "The server changed. Reload and review the current revision before continuing."
          : code === "22023"
            ? "The server rejected these inputs. Review counts, coverage and required confirmations."
            : code === "42883" || code === "PGRST202"
              ? "This server capability is unavailable. No success or publication is claimed."
              : write
                ? "No confirmed result. Reload and reconcile the saved revision before any further write."
                : "Could not load from the server. Check the connection and Retry.",
    );
    this.code = code;
    this.uncertain =
      write && !["42501", "401", "403", "PT409", "409", "22023"].includes(code);
  }
}
export function publicConfiguration(url: string, key: string) {
  const u = new URL(url);
  if (
    !(
      (u.protocol === "https:" && u.hostname.endsWith(".supabase.co")) ||
      (u.protocol === "http:" &&
        ["127.0.0.1", "localhost"].includes(u.hostname))
    ) ||
    u.pathname !== "/" ||
    u.username ||
    u.password ||
    u.search ||
    u.hash
  )
    throw Error(
      "Use the Supabase project HTTPS URL, or an isolated loopback runtime.",
    );
  if (key.startsWith("sb_publishable_") && key.length > 25)
    return { url: u.origin, key };
  try {
    const part = key.split(".")[1];
    const payload = JSON.parse(
      atob(part.replace(/-/g, "+").replace(/_/g, "/")),
    );
    if (payload.role === "anon") return { url: u.origin, key };
  } catch {
    /* Reject secrets and unsupported keys. */
  }
  throw Error(
    "Use a browser publishable key or legacy anon key. Privileged keys are forbidden.",
  );
}
export function clientFor(url: string, key: string) {
  const c = publicConfiguration(url, key);
  return createClient(c.url, c.key, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: "pkce",
      storageKey: "teamstats-web-auth:" + c.url,
    },
    global: {
      fetch: async (input, init) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 20000);
        const signal = init?.signal
          ? AbortSignal.any([controller.signal, init.signal])
          : controller.signal;
        try {
          return await fetch(input, { ...init, signal, redirect: "error" });
        } finally {
          clearTimeout(timer);
        }
      },
    },
  });
}
export function safeValue(v: unknown): string {
  if (v === undefined || v === null) return "";
  if (typeof v !== "number" || !Number.isSafeInteger(v) || v < 0)
    throw Error(
      "A saved count cannot be represented safely in this browser. No values were rounded.",
    );
  return String(v);
}
export function decodeManual(versions: Version[], game: string): Manual {
  const m: Manual = { box: {}, paint: {}, ours: [], opponent: [] };
  for (const v of versions) {
    for (const r of v.records) {
      if (String(r.gameID).toLowerCase() !== game.toLowerCase())
        throw Error("Saved record has a different game identity.");
      if (v.dataset_type === "box_scores") {
        if (
          typeof r.playerID !== "string" ||
          !r.values ||
          typeof r.values !== "object"
        )
          throw Error("Invalid saved box score.");
        m.box[r.playerID.toLowerCase()] = Object.fromEntries(
          Object.entries(r.values).map(([k, v]) => [k, safeValue(v)]),
        );
      } else if (v.dataset_type === "player_paint_touches") {
        if (typeof r.playerID !== "string")
          throw Error("Invalid saved player identity.");
        m.paint[r.playerID.toLowerCase()] = safeValue(r.total);
      } else {
        if (
          typeof r.id !== "string" ||
          !Number.isSafeInteger(r.number) ||
          typeof r.values !== "object" ||
          r.values === null ||
          ![null, undefined, true, false].includes(r.turnover as never)
        )
          throw Error("Invalid saved possession.");
        const team = v.dataset_type === "our_possessions" ? "ours" : "opponent";
        m[team].push({
          id: r.id,
          number: Number(r.number),
          values: Object.fromEntries(
            Object.entries(r.values).map(([k, n]) => [k, safeValue(n)]),
          ),
          turnover: typeof r.turnover === "boolean" ? r.turnover : null,
        });
      }
    }
  }
  return m;
}
export function encodeRecords(
  m: Manual,
  kind: Kind,
  game: string,
  players: Player[],
) {
  const values = (v: Values) =>
    Object.fromEntries(
      Object.entries(v)
        .filter(([, n]) => n !== "")
        .map(([f, n]) => {
          if (!validCount(n)) throw Error("Fix invalid counts before saving.");
          return [f, count(n)];
        }),
    );
  if (kind === "box_scores")
    return players.map((p) => ({
      gameID: game,
      playerID: p.id,
      values: values(m.box[p.id] ?? {}),
    }));
  if (kind === "player_paint_touches")
    return players.map((p) => ({
      gameID: game,
      playerID: p.id,
      total: count(m.paint[p.id] ?? ""),
    }));
  const team = kind === "our_possessions" ? "ours" : "opponent";
  return m[team].map((r: Possession) => ({
    id: r.id,
    gameID: game,
    team,
    number: r.number,
    values: values(r.values),
    turnover: r.turnover,
  }));
}
export function validateVersion(
  v: Version,
  team: string,
  game: string,
): Version {
  if (
    !v ||
    v.team_id !== team ||
    v.game_id !== game ||
    !KIND_LABEL[v.dataset_type] ||
    !v.id ||
    !Number.isSafeInteger(v.revision) ||
    v.revision < 1 ||
    !Array.isArray(v.records) ||
    !Array.isArray(v.covered_roster) ||
    ![
      "draft",
      "completed",
      "submitted",
      "published",
      "rejected",
      "superseded",
    ].includes(v.status)
  )
    throw Error("The server returned an unsupported statistics snapshot.");
  decodeManual([v], game);
  return v;
}
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value && typeof value === "object")
    return (
      "{" +
      Object.entries(value)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => JSON.stringify(k) + ":" + canonical(v))
        .join(",") +
      "}"
    );
  return JSON.stringify(value);
}
export class CoreServer {
  client: SupabaseClient;
  namespace: string;
  epoch = 0;
  constructor(client: SupabaseClient, namespace = "unconfigured") {
    this.client = client;
    this.namespace = namespace;
  }
  async identity() {
    const { data, error } = await this.client.auth.getUser();
    if (error || !data.user || data.user.is_anonymous)
      throw new ServerError("401");
    return data.user;
  }
  async access(team: string) {
    await this.identity();
    const { data, error } = await this.client.rpc("team_access", {
      p_team_id: team,
    });
    if (error) throw new ServerError(error.code);
    if (
      !data ||
      data.team_id !== team ||
      !Array.isArray(data.capabilities) ||
      !Number.isSafeInteger(data.access_revision)
    )
      throw Error("Invalid authority response.");
    return data as Access;
  }
  async rows<T>(
    table: string,
    columns: string,
    filters: Record<string, string> = {},
    order = "id",
  ): Promise<T[]> {
    const all: T[] = [];
    for (let offset = 0; offset < 10000; offset += 200) {
      let q = this.client
        .from(table)
        .select(columns)
        .range(offset, offset + 199);
      for (const column of order.split(",")) q = q.order(column);
      for (const [k, v] of Object.entries(filters)) q = q.eq(k, v);
      const { data, error } = await q;
      if (error) throw new ServerError(error.code);
      if (!data) throw Error("Missing server response.");
      all.push(...(data as unknown as T[]));
      if (data.length < 200) return all;
    }
    throw Error(
      "This snapshot exceeds the browser page limit; no partial snapshot was displayed.",
    );
  }
  async command<T>(
    team: string,
    name: string,
    args: Record<string, unknown>,
  ): Promise<T> {
    const epoch = this.epoch;
    const authority = await this.access(team);
    if (epoch !== this.epoch) throw new ServerError("401");
    let result;
    try {
      result = await this.client.rpc(name, {
        ...args,
        ...(name === "web_session_command"
          ? { p_expected_access_revision: authority.access_revision }
          : {}),
        p_team_id: team,
      });
    } catch {
      throw new ServerError("network", true);
    }
    // A dispatched write may have committed even after this account/view detached.
    if (epoch !== this.epoch) throw new ServerError("account_changed", true);
    if (result.error) throw new ServerError(result.error.code, true);
    return result.data as T;
  }
}
export type PendingOperation = {
  name: string;
  args: Record<string, unknown>;
  actor: string;
};
function normalizedRecords(records: unknown) {
  if (!Array.isArray(records)) return records;
  return records.map((r) => {
    const v = { ...r };
    for (const key of ["id", "gameID", "playerID"])
      if (typeof v[key] === "string") v[key] = v[key].toLowerCase();
    return v;
  });
}
export function operationConfirmed(
  op: PendingOperation,
  versions: Version[],
  requests: EditRequest[],
): boolean {
  const a = op.args;
  const saved = (
    versionID: unknown,
    revision: unknown,
    records: unknown,
    coverage: unknown,
  ) => {
    const v = versions.find((v) => v.id === versionID);
    return (
      !!v &&
      v.status === "draft" &&
      v.revision === Number(revision) + 1 &&
      canonical(normalizedRecords(v.records)) ===
        canonical(normalizedRecords(records)) &&
      canonical(v.covered_roster) === canonical(coverage ?? [])
    );
  };
  if (op.name === "stats_save_draft")
    return saved(
      a.p_version_id,
      a.p_expected_revision,
      a.p_records,
      a.p_covered_roster,
    );
  if (op.name === "stats_save_drafts")
    return (
      Array.isArray(a.p_items) &&
      a.p_items.every((i) =>
        saved(i.version_id, i.expected_revision, i.records, i.covered_roster),
      )
    );
  const status: Record<string, string> = {
    stats_complete: "completed",
    stats_submit: "submitted",
    stats_publish: "published",
    stats_review: a.p_approve ? "published" : "rejected",
  };
  if (status[op.name])
    return versions.some(
      (v) =>
        v.id === a.p_version_id &&
        v.revision === Number(a.p_expected_revision) + 1 &&
        v.status === status[op.name],
    );
  if (op.name === "stats_open_draft")
    return versions.some(
      (v) =>
        v.game_id === a.p_game_id &&
        v.author_user_id === op.actor &&
        v.dataset_type === a.p_dataset_type &&
        v.status === "draft",
    );
  if (op.name === "stats_request_edit")
    return requests.some(
      (r) =>
        r.source_version_id === a.p_source_version_id &&
        r.requester_user_id === op.actor &&
        r.status === "pending",
    );
  if (op.name === "stats_review_edit")
    return requests.some(
      (r) =>
        r.id === a.p_request_id &&
        r.revision === Number(a.p_expected_revision) + 1 &&
        r.status === (a.p_approve ? "approved" : "rejected") &&
        (!a.p_approve ||
          versions.some(
            (v) => v.id === r.working_version_id && v.status === "draft",
          )),
    );
  return false;
}

/** Compare only saved fields from two visible versions of the same dataset. */
export function recordChanges(base: Version, proposal: Version) {
  if (
    base.team_id !== proposal.team_id ||
    base.game_id !== proposal.game_id ||
    base.dataset_type !== proposal.dataset_type
  )
    throw Error("Comparison requires the same game and dataset.");
  const player =
    proposal.dataset_type === "box_scores" ||
    proposal.dataset_type === "player_paint_touches";
  const records = (version: Version) => {
    const map = new Map<string, Record<string, unknown>>();
    for (const row of version.records) {
      const key = String(row[player ? "playerID" : "id"] ?? "").toLowerCase();
      if (!key || map.has(key))
        throw Error("Comparison has missing or duplicate record identities.");
      map.set(key, row);
    }
    return map;
  };
  const before = records(base),
    after = records(proposal);
  const fields =
    proposal.dataset_type === "box_scores"
      ? BOX_FIELDS.map(([key, , label]) => [key, label])
      : proposal.dataset_type === "player_paint_touches"
        ? [["total", "Paint touches"]]
        : [
            ...POS_FIELDS.map(([key, , label]) => [key, label]),
            ["turnover", "Turnover"],
            ["number", "Possession number"],
          ];
  const changes: {
    record: string;
    field: string;
    previous: string;
    proposed: string;
  }[] = [];
  const display = (v: unknown, field: string) =>
    v === null || v === undefined
      ? field === "turnover"
        ? "Not answered"
        : "Not entered"
      : typeof v === "boolean"
        ? v
          ? "Yes"
          : "No"
        : safeValue(v);
  for (const key of new Set([...before.keys(), ...after.keys()])) {
    const old = before.get(key),
      next = after.get(key);
    if (!old || !next)
      changes.push({
        record: key,
        field: "Record",
        previous: old ? "Present" : "Not present",
        proposed: next ? "Present" : "Not present",
      });
    for (const [field, label] of fields) {
      const value = (row: Record<string, unknown> | undefined) =>
        field === "total" || field === "turnover" || field === "number"
          ? row?.[field]
          : (row?.values as Record<string, unknown> | undefined)?.[field];
      const a = value(old),
        b = value(next);
      if ((a ?? null) !== (b ?? null))
        changes.push({
          record: key,
          field: label,
          previous: display(a, field),
          proposed: display(b, field),
        });
    }
  }
  return changes;
}
