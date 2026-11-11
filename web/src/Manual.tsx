import { useState } from "react";
import type { Manual, Player, Values, Possession } from "./domain.ts";
import {
  BOX_FIELDS,
  POS_FIELDS,
  id,
  rebound,
  scoring,
  shown,
  sumKnown,
} from "./domain.ts";
import { Count, Empty, Notice, Scroller, Tabs } from "./ui.tsx";
export function ManualEntry({
  manual,
  players,
  onChange,
  only,
  disabledTeams = [],
}: {
  manual: Manual;
  players: Player[];
  onChange: (m: Manual) => void;
  only?: string;
  disabledTeams?: ("ours" | "opponent")[];
}) {
  const [tab, setTab] = useState("Box scores"),
    [mode, setMode] = useState("Single player"),
    [selected, setSelected] = useState(players[0]?.id ?? "");
  const active = only ?? tab,
    p = players.find((p) => p.id === selected) ?? players[0];
  const scope = mode === "Single player" ? (p ? [p] : []) : players;
  const discrepancies = scope.flatMap((p) => {
    const s = scoring(manual.box[p.id] ?? {});
    return s.kind === "discrepancy" ? [{ p, detail: s.detail }] : [];
  });
  const box = (player: Player, field: string, value: string) =>
    onChange({
      ...manual,
      box: {
        ...manual.box,
        [player.id]: { ...manual.box[player.id], [field]: value },
      },
    });
  const poss = (team: "ours" | "opponent", row: Possession) =>
    onChange({
      ...manual,
      [team]: manual[team].map((r) => (r.id === row.id ? row : r)),
    });
  return (
    <div className="manual">
      {!only && (
        <Tabs
          items={["Box scores", "Possessions", "Paint touches"]}
          value={tab}
          onChange={setTab}
          label="Manual dataset"
        />
      )}
      <p className="muted">
        After-game datasets are collected independently. Court records do not
        fill these fields.
      </p>
      {active === "Box scores" && (
        <>
          {discrepancies.length > 0 && (
            <Notice>
              <strong>Check scoring</strong>
              <ul>
                {discrepancies.map(({ p, detail }) => (
                  <li key={p.id}>
                    {p.name}: {detail}
                  </li>
                ))}
              </ul>
              <span>
                Drafts can still be saved. No values are changed automatically.
              </span>
            </Notice>
          )}
          <Tabs
            items={["Single player", "Roster table"]}
            value={mode}
            onChange={setMode}
            label="Box-score entry mode"
          />
          {!p ? (
            <Empty title="No players included">
              Add your local roster, then explicitly include it in this session.
              Shared entry requires an authorized server roster.
            </Empty>
          ) : mode === "Single player" ? (
            <>
              <label className="field">
                Player
                <select
                  value={p.id}
                  onChange={(e) => setSelected(e.target.value)}
                >
                  {players.map((p) => (
                    <option value={p.id} key={p.id}>
                      #{p.number} {p.name}
                    </option>
                  ))}
                </select>
              </label>
              <h3>
                {p.name} <span className="muted">#{p.number}</span>
              </h3>
              <div className="field-grid">
                {BOX_FIELDS.map(([f, , label]) => (
                  <Count
                    key={f}
                    label={label}
                    value={manual.box[p.id]?.[f] ?? ""}
                    onChange={(v) => box(p, f, v)}
                  />
                ))}
              </div>
              <p>
                Total rebounds:{" "}
                <strong>{rebound(manual.box[p.id] ?? {})}</strong>
              </p>
              {scoring(manual.box[p.id] ?? {}).kind !== "discrepancy" && (
                <p className="muted">
                  {scoring(manual.box[p.id] ?? {}).detail}
                </p>
              )}
            </>
          ) : (
            <Scroller label="Box-score roster">
              <table className="entry-table">
                <thead>
                  <tr>
                    <th scope="col">Player</th>
                    {BOX_FIELDS.map(([f, abbr, label]) => (
                      <th key={f} scope="col" title={label}>
                        {abbr}
                      </th>
                    ))}
                    <th>REB</th>
                    <th>Scoring check</th>
                  </tr>
                </thead>
                <tbody>
                  {players.map((p) => (
                    <tr key={p.id}>
                      <th scope="row">
                        {p.name}
                        <small>#{p.number}</small>
                      </th>
                      {BOX_FIELDS.map(([f, , label]) => (
                        <td key={f}>
                          <Count
                            compact
                            label={`${p.name} ${label}`}
                            value={manual.box[p.id]?.[f] ?? ""}
                            onChange={(v) => box(p, f, v)}
                          />
                        </td>
                      ))}
                      <td>{rebound(manual.box[p.id] ?? {})}</td>
                      <td>
                        {scoring(manual.box[p.id] ?? {}).kind === "discrepancy"
                          ? "See Check scoring above"
                          : scoring(manual.box[p.id] ?? {}).detail}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </Scroller>
          )}
        </>
      )}
      {active === "Possessions" && (
        <>
          <Notice>
            Each side has its own nth possession. Rows do not imply
            chronological alignment. A possession ends when the opponent legally
            possesses the ball; offensive rebounds and free throws stay within
            it. Period-ending actions count; no-action holds do not.
          </Notice>
          <Scroller label="Independent possession sheets">
            <div className="paired">
              {(["ours", "opponent"] as const).map((team) => (
                <section key={team}>
                  <fieldset
                    disabled={disabledTeams.includes(team)}
                    className="entry-fields"
                  >
                    <h3>
                      {team === "ours" ? "Our team" : "Opponent"}{" "}
                      <span className="badge">
                        {manual[team].length} records entered
                      </span>
                    </h3>
                    {manual[team].map((row) => (
                      <fieldset className="possession" key={row.id}>
                        <legend>Possession {row.number}</legend>
                        <div className="field-grid">
                          {POS_FIELDS.map(([f, , label]) => (
                            <Count
                              key={f}
                              label={label}
                              value={row.values[f] ?? ""}
                              onChange={(v) =>
                                poss(team, {
                                  ...row,
                                  values: { ...row.values, [f]: v },
                                })
                              }
                            />
                          ))}
                        </div>
                        <label className="field">
                          Turnover
                          <select
                            value={
                              row.turnover === null
                                ? ""
                                : row.turnover
                                  ? "yes"
                                  : "no"
                            }
                            onChange={(e) =>
                              poss(team, {
                                ...row,
                                turnover:
                                  e.target.value === ""
                                    ? null
                                    : e.target.value === "yes",
                              })
                            }
                          >
                            <option value="">Not answered</option>
                            <option value="no">No</option>
                            <option value="yes">Yes</option>
                          </select>
                        </label>
                      </fieldset>
                    ))}
                    <button
                      type="button"
                      className="secondary"
                      onClick={() =>
                        onChange({
                          ...manual,
                          [team]: [
                            ...manual[team],
                            {
                              id: id(),
                              number: manual[team].length + 1,
                              values: {},
                              turnover: false,
                            },
                          ],
                        })
                      }
                    >
                      Add next {team === "ours" ? "our-team" : "opponent"}{" "}
                      possession
                    </button>
                    {manual[team].length === 0 && (
                      <p className="muted">
                        No records entered. The opposite sheet does not add
                        records here.
                      </p>
                    )}
                  </fieldset>
                </section>
              ))}
            </div>
          </Scroller>
        </>
      )}
      {active === "Paint touches" && (
        <>
          <h3>Player game-total paint touches</h3>
          <p>
            A player intentionally establishes two feet in the paint with the
            ball. Independent totals; not inferred from possession records.
          </p>
          {players.length === 0 ? (
            <Empty title="No players included">
              Include your roster before entry.
            </Empty>
          ) : (
            <div className="ledger-rows">
              {players.map((p) => (
                <div className="paint-row" key={p.id}>
                  <div>
                    <strong>{p.name}</strong>
                    <small>#{p.number}</small>
                  </div>
                  <Count
                    label={`${p.name} paint touches`}
                    value={manual.paint[p.id] ?? ""}
                    onChange={(v) =>
                      onChange({
                        ...manual,
                        paint: { ...manual.paint, [p.id]: v },
                      })
                    }
                  />
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
export function ManualSummary({
  manual,
  players,
  provenance = "Local draft · incomplete and unreviewed",
}: {
  manual: Manual;
  players: Player[];
  provenance?: string;
}) {
  const [filter, setFilter] = useState("all");
  const visible =
    filter === "all" ? players : players.filter((p) => p.id === filter);
  let subtotal = "Unavailable",
    missing = players.length;
  try {
    const s = sumKnown(players.map((p) => manual.box[p.id]?.points));
    subtotal = String(s.total);
    missing = s.missing;
  } catch {
    /* Invalid values are displayed below, never coerced. */
  }
  return (
    <>
      <div className="section-heading">
        <h2>Independent manual totals</h2>
        <span className="badge">{provenance}</span>
      </div>
      <p>
        <strong>{subtotal} points</strong> — entered-data subtotal; {missing} of{" "}
        {players.length} players missing points. This is not a final score.
      </p>
      <label className="field player-select">
        View player
        <select value={filter} onChange={(e) => setFilter(e.target.value)}>
          <option value="all">All covered players</option>
          {players.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name} · #{p.number}
            </option>
          ))}
        </select>
      </label>
      <Scroller label="Saved player statistics">
        <table>
          <thead>
            <tr>
              <th>Player</th>
              {BOX_FIELDS.map(([f, abbr]) => (
                <th key={f}>{abbr}</th>
              ))}
              <th>REB</th>
              <th>Paint touches</th>
              <th>Points check</th>
            </tr>
          </thead>
          <tbody>
            {visible.map((p) => (
              <tr key={p.id}>
                <th scope="row">
                  {p.name}
                  <small>#{p.number}</small>
                </th>
                {BOX_FIELDS.map(([f]) => (
                  <td key={f}>{shown(manual.box[p.id]?.[f])}</td>
                ))}
                <td>{rebound(manual.box[p.id] ?? {})}</td>
                <td>{shown(manual.paint[p.id])}</td>
                <td>{scoring(manual.box[p.id] ?? {}).detail}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Scroller>
      {(["ours", "opponent"] as const).map((team) => (
        <section key={team}>
          <h3>
            {team === "ours" ? "Our team" : "Opponent"} — {manual[team].length}{" "}
            possession records entered
          </h3>
          <p className="muted">
            Records entered, not final game possessions. No cross-sheet
            reconciliation is claimed.
          </p>
          <Scroller label={`${team} possession records`}>
            <table>
              <thead>
                <tr>
                  <th>Record</th>
                  {POS_FIELDS.map(([f, , label]) => (
                    <th key={f}>{label}</th>
                  ))}
                  <th>Turnover</th>
                </tr>
              </thead>
              <tbody>
                {manual[team].map((r) => (
                  <tr key={r.id}>
                    <th scope="row">{r.number}</th>
                    {POS_FIELDS.map(([f]) => (
                      <td key={f}>{shown(r.values[f])}</td>
                    ))}
                    <td>
                      {r.turnover === null
                        ? "Not answered"
                        : r.turnover
                          ? "Yes"
                          : "No"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Scroller>
        </section>
      ))}
    </>
  );
}
export function valuesToNumbers(v: Values) {
  return Object.fromEntries(
    Object.entries(v)
      .filter(([, v]) => v !== "")
      .map(([k, v]) => [k, Number(v)]),
  );
}
