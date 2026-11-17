import { useEffect, useRef, useState } from "react";
import type { Player, Capture } from "./domain.ts";
import { BOX_FIELDS, POS_FIELDS, entryError, id } from "./domain.ts";
import { CoreServer, ServerError } from "./server.ts";
import type { Access, Game } from "./server.ts";
import {
  summarizeResults,
  selectedCharts,
  summarizeEvents,
} from "./results.ts";
import type { Results as ResultData, Subtotal } from "./results.ts";
import { CourtDiagram } from "./Capture.tsx";
import { Empty, Notice, Scroller, Tabs } from "./ui.tsx";
type Season = { id: string; name: string };
type Assignment = { game_id: string; season_id: string };
type SetupAttempt = { name: string; args: Record<string, unknown> };
export function Results({
  server,
  team,
  access,
  roster,
  games,
  onDenied,
}: {
  server: CoreServer;
  team: string;
  access: Access;
  roster: Player[];
  games: Game[];
  onDenied: () => void;
}) {
  const [ownPlayer, setOwnPlayer] = useState(""),
    [seasons, setSeasons] = useState<Season[]>([]),
    [assignments, setAssignments] = useState<Assignment[]>([]),
    [scope, setScope] = useState("Game"),
    [seasonID, setSeasonID] = useState(""),
    [gameID, setGameID] = useState(""),
    [player, setPlayer] = useState(""),
    [side, setSide] = useState<"ours" | "opponent">("ours"),
    [choices, setChoices] = useState<Record<string, string>>({}),
    [data, setData] = useState<ResultData | null>(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [seasonName, setSeasonName] = useState(""),
    [newID, setNewID] = useState<string>(id),
    [assignGame, setAssignGame] = useState(""),
    [assignSeason, setAssignSeason] = useState(""),
    [uncertain, setUncertain] = useState(false);
  const generation = useRef(0),
    active = useRef(true),
    setupAttempt = useRef<SetupAttempt | null>(null);
  const setupKey = `teamstats-season-setup:${encodeURIComponent(server.namespace)}:${team}:${access.user_id}`;
  const rememberSetup = (value: SetupAttempt | null) => {
    if (value) sessionStorage.setItem(setupKey, JSON.stringify(value));
    else sessionStorage.removeItem(setupKey);
    setupAttempt.current = value;
    setUncertain(value !== null);
  };
  const fail = (e: unknown) => {
    if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code)) {
      setData(null);
      onDenied();
    }
    setError(entryError(e));
  };
  const loadSetup = async () => {
    const epoch = server.epoch;
    try {
      await server.access(team);
      const [s, a, links] = await Promise.all([
        server.rows<Season>("web_seasons", "id,name", { team_id: team }),
        server.rows<Assignment>(
          "web_season_games",
          "game_id,season_id",
          {
            team_id: team,
          },
          "game_id",
        ),
        server.rows<{ player_id: string }>(
          "team_player_accounts",
          "player_id",
          { team_id: team, user_id: access.user_id },
          "user_id",
        ),
      ]);
      if (!active.current || epoch !== server.epoch) return false;
      setSeasons(s);
      setAssignments(a);
      setOwnPlayer(links[0]?.player_id ?? "");
      const attempt = setupAttempt.current;
      if (attempt) {
        const confirmed =
          attempt.name === "team_save_season"
            ? s.some((row) => row.id === attempt.args.p_season_id)
            : a.some(
                (row) =>
                  row.game_id === attempt.args.p_game_id &&
                  row.season_id === attempt.args.p_season_id,
              );
        if (confirmed) {
          rememberSetup(null);
          setNewID(id());
          setSeasonName("");
          setError("");
        }
      }
      return true;
    } catch (e) {
      if (active.current && epoch === server.epoch) fail(e);
      return false;
    }
  };
  const load = async () => {
    const n = ++generation.current;
    setData(null);
    setError("");
    const selected = scope === "Game" ? gameID : seasonID;
    if (!selected) {
      setBusy(false);
      return;
    }
    setBusy(true);
    try {
      const result = await server.command<ResultData>(team, "web_results", {
        p_game_id: scope === "Game" ? gameID : null,
        p_season_id: scope === "Season" ? seasonID : null,
      });
      if (n !== generation.current || !active.current) return;
      if (
        !Array.isArray(result?.games) ||
        !Array.isArray(result.versions) ||
        !Array.isArray(result.charts) ||
        result.games.some((g) => !games.some((known) => known.id === g.id)) ||
        (scope === "Game" && result.games.some((g) => g.id !== gameID))
      )
        throw Error(
          "These results could not be matched to your team. Reload before using them.",
        );
      summarizeResults(result);
      setData(result);
    } catch (e) {
      if (n === generation.current && active.current) fail(e);
    } finally {
      if (n === generation.current && active.current) setBusy(false);
    }
  };
  useEffect(() => {
    active.current = true;
    try {
      const raw = sessionStorage.getItem(setupKey);
      if (raw) {
        const value = JSON.parse(raw) as SetupAttempt;
        if (
          !["team_save_season", "team_assign_season_game"].includes(
            value.name,
          ) ||
          !value.args ||
          typeof value.args.p_season_id !== "string" ||
          !Number.isSafeInteger(value.args.p_expected_access_revision)
        )
          throw Error(
            "Unreadable season recovery details. Keep this tab and ask for help before another change.",
          );
        setupAttempt.current = value;
        setUncertain(true);
        if (value.name === "team_save_season") {
          setNewID(String(value.args.p_season_id));
          setSeasonName(String(value.args.p_name ?? ""));
        }
      }
    } catch (e) {
      setUncertain(true);
      fail(e);
    }
    void loadSetup();
    return () => {
      active.current = false;
      generation.current++;
    };
  }, [team]);
  useEffect(() => {
    void load();
    const focus = () => void load();
    window.addEventListener("focus", focus);
    return () => {
      generation.current++;
      window.removeEventListener("focus", focus);
    };
  }, [team, scope, gameID, seasonID]);
  const command = async (
    name: string,
    args: Record<string, unknown>,
    frozen?: SetupAttempt,
  ) => {
    if (busy || (uncertain && !frozen)) return;
    setBusy(true);
    setError("");
    try {
      let attempt = frozen;
      if (!attempt) {
        const current = await server.access(team);
        attempt = {
          name,
          args: {
            ...args,
            p_expected_access_revision: current.access_revision,
          },
        };
        rememberSetup(attempt);
      }
      await server.command(team, attempt.name, attempt.args);
      if (!active.current) return;
      rememberSetup(null);
      if (name === "team_save_season") {
        setSeasonName("");
        setNewID(id());
      }
      await loadSetup();
      await load();
    } catch (e) {
      if (active.current) {
        try {
          if (e instanceof ServerError && !e.uncertain && !frozen)
            rememberSetup(null);
          if (
            frozen &&
            e instanceof ServerError &&
            ["PT409", "409"].includes(e.code)
          ) {
            const readback = await loadSetup();
            if (readback && setupAttempt.current) {
              const current = await server.access(team);
              if (
                current.access_revision !==
                frozen.args.p_expected_access_revision
              )
                rememberSetup(null);
            }
          }
        } catch (recoveryError) {
          fail(recoveryError);
          return;
        }
        fail(e);
      }
    } finally {
      if (active.current) setBusy(false);
    }
  };
  let totals: ReturnType<typeof summarizeResults> | null = null,
    calculationError = "";
  try {
    if (data) totals = summarizeResults(data, player || undefined);
  } catch (e) {
    calculationError = entryError(e);
  }
  const charts = data ? selectedCharts(data, choices) : null;
  const events =
    charts?.charts.flatMap((chart) =>
      chart.events
        .filter(
          (e) =>
            e.team === side &&
            (side === "opponent" || !player || e.playerID === player),
        )
        .map((event) => ({ ...event, id: chart.game_id + ":" + event.id })),
    ) ?? [];
  let eventGroups: ReturnType<typeof summarizeEvents> = [];
  try {
    eventGroups = summarizeEvents(events);
  } catch (e) {
    calculationError = entryError(e);
  }
  const attempts = events.filter((e) => e.kind !== "event");
  const display = (s: Subtotal) =>
    s.value === null ? "Not entered" : String(s.value);
  const missing = (s: Subtotal) =>
    `${s.missingGames} of ${data?.games.length ?? 0} games missing this stat; ${s.missing} unentered inputs`;
  const row = (key: string, label: string) =>
    totals && (
      <tr key={key}>
        <th scope="row">{label}</th>
        <td>{display(totals.fields[key])}</td>
        <td>
          {totals.fields[key].missing
            ? "Entered-data subtotal"
            : "Published total"}
          <small>{missing(totals.fields[key])}</small>
        </td>
      </tr>
    );
  return (
    <section className="published-results">
      <div className="section-heading">
        <h2>Published results</h2>
        <button
          type="button"
          disabled={busy}
          onClick={() => {
            void loadSetup();
            void load();
          }}
        >
          Refresh results
        </button>
      </div>
      <p>
        Choose a game or a season. Only currently published stat sheets and shot
        charts are included; practice results stay separate.
      </p>
      <Tabs
        items={["Game", "Season"]}
        value={scope}
        onChange={setScope}
        label="Results scope"
      />
      <div className="field-grid">
        {scope === "Game" ? (
          <label className="field">
            Results game
            <select value={gameID} onChange={(e) => setGameID(e.target.value)}>
              <option value="">Choose a game</option>
              {games.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.opponent} · {g.date}
                </option>
              ))}
            </select>
          </label>
        ) : (
          <label className="field">
            Results season
            <select
              value={seasonID}
              onChange={(e) => setSeasonID(e.target.value)}
            >
              <option value="">Choose a season</option>
              {seasons.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          </label>
        )}
        <label className="field">
          Results player
          <select value={player} onChange={(e) => setPlayer(e.target.value)}>
            <option value="">Our team — all players</option>
            {ownPlayer && roster.some((p) => p.id === ownPlayer) && (
              <option value={ownPlayer}>
                My stats — {roster.find((p) => p.id === ownPlayer)?.name}
              </option>
            )}
            {roster
              .filter((p) => p.id !== ownPlayer)
              .map((p) => (
                <option key={p.id} value={p.id}>
                  #{p.number} {p.name}
                </option>
              ))}
          </select>
        </label>
      </div>
      {error && (
        <Notice error>
          {error}
          <button
            type="button"
            disabled={busy}
            onClick={() => {
              void loadSetup();
              void load();
            }}
          >
            Retry results
          </button>
        </Notice>
      )}
      {busy && <p role="status">Loading published results…</p>}
      {calculationError && <Notice error>{calculationError}</Notice>}
      {data && !data.games.length ? (
        <Empty title="No games assigned to this season">
          The owner can assign games in Season setup. No dates or games are
          included automatically.
        </Empty>
      ) : (
        totals &&
        data && (
          <>
            <p>
              {data.games.length} games included. Blank values are not treated
              as zero. Rebounds require both offensive and defensive counts in
              each contributing player record.
            </p>
            {!data.versions.length && (
              <Notice>
                No published after-game stat sheets yet. Saved drafts and
                entries waiting for verification are not totals.
              </Notice>
            )}
            <Scroller label="Published game and season totals">
              <table>
                <thead>
                  <tr>
                    <th>Statistic</th>
                    <th>Entered total</th>
                    <th>Coverage</th>
                  </tr>
                </thead>
                <tbody>
                  {BOX_FIELDS.map(([key, , label]) => row(key, label))}
                  {row("rebounds", "Total rebounds")}
                  {row("paintTouches", "Player paint touches")}
                </tbody>
              </table>
            </Scroller>
            <h3>Shooting from box scores</h3>
            <p>
              Each percentage uses only records with both makes and misses
              entered. It is not an average of player or game percentages.
            </p>
            <Scroller label="Published shooting percentages">
              <table>
                <thead>
                  <tr>
                    <th>Shot</th>
                    <th>Makes / attempts</th>
                    <th>Percentage</th>
                    <th>Coverage</th>
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(totals.shooting).map(([type, s]) => (
                    <tr key={type}>
                      <th>
                        {type === "twos"
                          ? "Twos"
                          : type === "threes"
                            ? "Threes"
                            : "Free throws"}
                      </th>
                      <td>
                        {s.makes} / {s.attempts}
                      </td>
                      <td>
                        {s.percentage === null
                          ? "Unavailable"
                          : s.percentage.toFixed(1) + "%"}
                      </td>
                      <td>
                        {s.missing
                          ? `Entered-data percentage · ${s.missing} incomplete or missing records`
                          : "Published records"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </Scroller>
            <h3>Possession sheets</h3>
            <p>
              Each team’s entered records are independent. These counts do not
              establish complete game coverage or chronological alignment
              between teams.
            </p>
            {(["ours", "opponent"] as const).map((team) => {
              const p = totals.possessions[team];
              return (
                <section key={team}>
                  <h4>
                    {team === "ours" ? "Our team" : "Opponent"} · {p.records}{" "}
                    published possession records
                  </h4>
                  <p>
                    {p.missingGames} games have no published sheet. Turnovers:{" "}
                    {p.turnovers.yes} Yes · {p.turnovers.no} No ·{" "}
                    {p.turnovers.unanswered} Not answered.
                  </p>
                  <p>
                    Real Possessions:{" "}
                    <strong>{display(p.realPossessions)}</strong> ·{" "}
                    {p.realPossessions.missing
                      ? "Entered-data subtotal"
                      : "Published entered-data calculation"}
                    . {missing(p.realPossessions)}. Formula: possession records
                    − Yes turnovers + offensive rebounds; only games with all
                    required inputs contribute.
                  </p>
                  <Scroller
                    label={`${team === "ours" ? "Our team" : "Opponent"} possession totals`}
                  >
                    <table>
                      <thead>
                        <tr>
                          <th>Statistic</th>
                          <th>Entered-data subtotal</th>
                          <th>Missing inputs</th>
                        </tr>
                      </thead>
                      <tbody>
                        {Object.entries(p.fields).map(([key, s]) => (
                          <tr key={key}>
                            <th>
                              {POS_FIELDS.find(
                                ([field]) => field === key,
                              )?.[2] ?? "Statistic"}
                            </th>
                            <td>{display(s)}</td>
                            <td>{missing(s)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </Scroller>
                </section>
              );
            })}
            <h3>Shot charts</h3>
            <p>
              Recorded attempts only. Chart points are separate from box-score
              points and are never added together.
            </p>
            {charts &&
              (charts.missing.length > 0 || charts.ambiguous.length > 0) && (
                <Notice>
                  {charts.missing.length} games have no included published
                  chart. {charts.ambiguous.length} games need an explicit chart
                  choice and are excluded until selected.
                </Notice>
              )}
            {data.games
              .filter(
                (g) => data.charts.filter((c) => c.game_id === g.id).length > 1,
              )
              .map((g) => (
                <label className="field" key={g.id}>
                  Shot chart for {g.opponent}
                  <select
                    value={choices[g.id] ?? ""}
                    onChange={(e) =>
                      setChoices({ ...choices, [g.id]: e.target.value })
                    }
                  >
                    <option value="">Choose one published chart</option>
                    {data.charts
                      .filter((c) => c.game_id === g.id)
                      .map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.title}
                        </option>
                      ))}
                  </select>
                </label>
              ))}
            <div className="segmented">
              <button
                type="button"
                aria-pressed={side === "ours"}
                onClick={() => setSide("ours")}
              >
                Our team
              </button>
              <button
                type="button"
                aria-pressed={side === "opponent"}
                onClick={() => setSide("opponent")}
              >
                Opponent
              </button>
            </div>
            <CourtDiagram events={events as Capture[]} team={side} />
            <h4>Other recorded game stats</h4>
            <p>
              Only selected published charts are included. Rules and versions
              stay separate; event times and game-clock readings are not summed.
            </p>
            {!eventGroups.length && (
              <p>No other events recorded in these selected charts.</p>
            )}
            {eventGroups.map((group) => (
              <details key={group.template.id + ":" + group.template.version}>
                <summary>
                  {group.template.name} · rule {group.template.version} ·{" "}
                  {group.events.length} observations
                </summary>
                <p>{group.template.definition}</p>
                {group.total && (
                  <p>
                    {group.template.kind === "count"
                      ? `${group.total.made} entered count`
                      : `${group.total.made} makes / ${group.total.attempts} paired attempts${group.total.attempts ? ` · ${((100 * group.total.made) / group.total.attempts).toFixed(1)}%` : " · Percentage unavailable"}`}{" "}
                    · {group.total.missing} incomplete observations.
                    Entered-data subtotal; coverage may be incomplete.
                  </p>
                )}
                <ol>
                  {group.events.map((event) => (
                    <li key={event.id}>
                      {event.playerID
                        ? (roster.find((p) => p.id === event.playerID)?.name ??
                          "Player not in current roster")
                        : "Team"}{" "}
                      · {event.period}, clock {event.clock} seconds.
                      {Object.entries(event.values ?? {}).map(
                        ([key, value]) => (
                          <span key={key}>
                            {" "}
                            {key === "count" && group.template.kind === "timed"
                              ? "Event time (seconds)"
                              : key === "made"
                                ? "Makes"
                                : key === "attempts"
                                  ? "Attempts"
                                  : "Count"}
                            : {value === "" ? "Not entered" : value}.
                          </span>
                        ),
                      )}
                      {event.note && <p>{event.note}</p>}
                    </li>
                  ))}
                </ol>
              </details>
            ))}
            <p>
              Court:{" "}
              {attempts.filter((e) => e.kind === "shot" && e.made).length} makes
              / {attempts.filter((e) => e.kind === "shot").length} recorded
              field goals. Free throws:{" "}
              {attempts.filter((e) => e.kind === "freeThrow" && e.made).length}{" "}
              makes / {attempts.filter((e) => e.kind === "freeThrow").length}{" "}
              recorded attempts. {charts?.charts.length} selected game charts.
              Coverage may be incomplete.
            </p>
          </>
        )
      )}
      {access.is_owner && (
        <details>
          <summary>Season setup</summary>
          <p>
            Name each season and choose its games explicitly. Regular
            season/playoff is a game type, not a season boundary.
          </p>
          {uncertain && (
            <Notice error>
              This setup change is unconfirmed. Reload and inspect the current
              season/game assignments before another change.
              <button
                type="button"
                disabled={busy}
                onClick={() => void loadSetup()}
              >
                Check season setup
              </button>
              {setupAttempt.current && (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void command(
                      setupAttempt.current!.name,
                      setupAttempt.current!.args,
                      setupAttempt.current!,
                    )
                  }
                >
                  Retry same setup request
                </button>
              )}
            </Notice>
          )}
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void command("team_save_season", {
                p_season_id: newID,
                p_name: seasonName.trim(),
              });
            }}
          >
            <label className="field">
              Season name
              <input
                required
                maxLength={100}
                value={seasonName}
                onChange={(e) => setSeasonName(e.target.value)}
              />
            </label>
            <button
              type="submit"
              disabled={busy || uncertain || !seasonName.trim()}
            >
              Create season
            </button>
          </form>
          <div className="field-grid">
            <label className="field">
              Game to assign
              <select
                value={assignGame}
                onChange={(e) => setAssignGame(e.target.value)}
              >
                <option value="">Choose a game</option>
                {games.map((g) => (
                  <option key={g.id} value={g.id}>
                    {g.opponent} · {g.date}
                  </option>
                ))}
              </select>
            </label>
            <label className="field">
              Assign to season
              <select
                value={assignSeason}
                onChange={(e) => setAssignSeason(e.target.value)}
              >
                <option value="">Choose a season</option>
                {seasons.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <button
            type="button"
            disabled={busy || uncertain || !assignGame || !assignSeason}
            onClick={() => {
              const previous =
                assignments.find((a) => a.game_id === assignGame)?.season_id ??
                null;
              if (
                window.confirm(
                  "Assign this game to the selected season? If already assigned, it will move; game records remain unchanged.",
                )
              )
                void command("team_assign_season_game", {
                  p_game_id: assignGame,
                  p_season_id: assignSeason,
                  p_expected_season_id: previous,
                });
            }}
          >
            Assign game to season
          </button>
          <ul>
            {assignments.map((a) => (
              <li key={a.game_id}>
                {games.find((g) => g.id === a.game_id)?.opponent ??
                  "Game unavailable"}{" "}
                ·{" "}
                {seasons.find((s) => s.id === a.season_id)?.name ??
                  "Season unavailable"}
              </li>
            ))}
          </ul>
        </details>
      )}
    </section>
  );
}
