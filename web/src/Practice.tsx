import { useState } from "react";
import type { Pair, Session, Template, Values } from "./domain.ts";
import {
  count,
  id,
  currentObservations,
  percentage,
  shown,
  validatePair,
} from "./domain.ts";
import { Count, Empty, Notice, Scroller } from "./ui.tsx";
export function Practice({
  session: s,
  onChange,
  templates,
  tab,
  provenance = "Local draft — incomplete and unreviewed.",
}: {
  session: Session;
  onChange: (s: Session) => void;
  templates: Template[];
  tab: string;
  provenance?: string;
}) {
  const [resultPlayer, setResultPlayer] = useState("all");
  const resultPlayers = s.players.filter(
    (p) => resultPlayer === "all" || p.id === resultPlayer,
  );
  const resultObservations = currentObservations(s.observations).filter(
    (o) =>
      resultPlayer === "all" ||
      o.playerID === resultPlayer ||
      o.playerID === null,
  );
  const [player, setPlayer] = useState(s.players[0]?.id ?? ""),
    [chosen, setChosen] = useState(""),
    [values, setValues] = useState<Values>({}),
    [note, setNote] = useState(""),
    [issue, setIssue] = useState(""),
    [editing, setEditing] = useState<string | null>(null);
  const visibleObservations = currentObservations(s.observations);
  const selected = s.players.find((p) => p.id === player) ?? s.players[0];
  const pair = (spot: string): Pair =>
    selected
      ? (s.shooting[selected.id]?.[spot] ?? { made: "", attempts: "" })
      : { made: "", attempts: "" };
  const changePair = (spot: string, next: Pair) => {
    if (selected)
      onChange({
        ...s,
        shooting: {
          ...s.shooting,
          [selected.id]: { ...s.shooting[selected.id], [spot]: next },
        },
      });
  };
  const percent = (p: Pair) => {
    try {
      return percentage(p.made, p.attempts);
    } catch {
      return "Invalid — makes exceed attempts";
    }
  };
  const addObservation = () => {
    try {
      const t =
        (editing
          ? s.observations.find((o) => o.id === editing)?.template
          : undefined) ?? templates.find((t) => t.id === chosen);
      if (!t) throw Error("Choose a collection template.");
      if (!t.definition.trim())
        throw Error("Define this template’s counting rule in Setup first.");
      if (t.kind === "makes")
        validatePair({
          made: values.made ?? "",
          attempts: values.attempts ?? "",
        });
      if (t.kind === "count" || t.kind === "timed") count(values.count ?? "");
      if (t.kind === "note" && !note.trim()) throw Error("Enter a note.");
      const original = s.observations.find((o) => o.id === editing);
      const observation = {
        id: id(),
        playerID: original?.playerID ?? selected?.id ?? null,
        template: structuredClone(original?.template ?? t),
        values: { ...values },
        note,
        at: original?.at ?? new Date().toISOString(),
        ...(original
          ? { supersedes: original.id, correctedAt: new Date().toISOString() }
          : {}),
      };
      onChange({ ...s, observations: [...s.observations, observation] });
      setEditing(null);
      setValues({});
      setNote("");
      setIssue("");
    } catch (e) {
      setIssue((e as Error).message);
    }
  };
  const t =
    (editing
      ? s.observations.find((o) => o.id === editing)?.template
      : undefined) ?? templates.find((t) => t.id === chosen);
  return (
    <>
      {tab === "Plan" && (
        <>
          <div className="section-heading">
            <h2>Practice plan</h2>
            <button type="button" onClick={() => window.print()}>
              Print / Save PDF
            </button>
          </div>
          <p className="muted">
            Print this plan before practice. Your browser’s print dialog
            provides Save as PDF; no file is uploaded.
          </p>
          <div className="print-plan">
            <div className="print-heading">
              <h2>{s.title}</h2>
              <p>
                {s.date} · Practice plan · {s.id}
              </p>
            </div>
            {s.plan.length === 0 && (
              <Empty title="Build the practice plan">
                Add a drill, order the work, and write the coach’s instructions.
              </Empty>
            )}
            {s.plan.map((row, i) => (
              <section className="plan-row" key={row.id}>
                <div className="plan-number">{i + 1}</div>
                <div>
                  <label className="field">
                    Drill name
                    <input
                      value={row.name}
                      maxLength={100}
                      onChange={(e) =>
                        onChange({
                          ...s,
                          plan: s.plan.map((r) =>
                            r.id === row.id
                              ? { ...r, name: e.target.value }
                              : r,
                          ),
                        })
                      }
                    />
                  </label>
                  <div className="plan-meta">
                    <label className="field">
                      Minutes
                      <input
                        value={row.minutes}
                        inputMode="numeric"
                        onChange={(e) =>
                          onChange({
                            ...s,
                            plan: s.plan.map((r) =>
                              r.id === row.id
                                ? { ...r, minutes: e.target.value }
                                : r,
                            ),
                          })
                        }
                      />
                    </label>
                    {row.template && (
                      <span className="badge">
                        {row.template.name} · definition v{row.template.version}
                      </span>
                    )}
                    <button
                      type="button"
                      disabled={i === 0}
                      onClick={() => {
                        const plan = [...s.plan];
                        [plan[i - 1], plan[i]] = [plan[i], plan[i - 1]];
                        onChange({ ...s, plan });
                      }}
                    >
                      Move earlier
                    </button>
                    <button
                      type="button"
                      disabled={i === s.plan.length - 1}
                      onClick={() => {
                        const plan = [...s.plan];
                        [plan[i + 1], plan[i]] = [plan[i], plan[i + 1]];
                        onChange({ ...s, plan });
                      }}
                    >
                      Move later
                    </button>
                  </div>
                  <label className="field">
                    Coach’s instructions
                    <textarea
                      rows={3}
                      value={row.instructions}
                      maxLength={4000}
                      placeholder="Instructions not supplied"
                      onChange={(e) =>
                        onChange({
                          ...s,
                          plan: s.plan.map((r) =>
                            r.id === row.id
                              ? { ...r, instructions: e.target.value }
                              : r,
                          ),
                        })
                      }
                    />
                  </label>
                </div>
              </section>
            ))}
          </div>
          <div className="actions">
            <button
              type="button"
              className="secondary"
              onClick={() =>
                onChange({
                  ...s,
                  plan: [
                    ...s.plan,
                    { id: id(), name: "", minutes: "", instructions: "" },
                  ],
                })
              }
            >
              Add drill
            </button>
            <label className="field">
              Add from a reusable template
              <select
                value=""
                onChange={(e) => {
                  const t = templates.find((t) => t.id === e.target.value);
                  if (t)
                    onChange({
                      ...s,
                      plan: [
                        ...s.plan,
                        {
                          id: id(),
                          name: t.name,
                          minutes: "",
                          instructions: t.definition,
                          template: structuredClone(t),
                        },
                      ],
                    });
                }}
              >
                <option value="">Choose a template</option>
                {templates.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name} · v{t.version}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <h3>Session protocol</h3>
          <label className="field">
            Sets, rotations, baskets and collector responsibility
            <textarea
              value={s.protocol}
              maxLength={4000}
              placeholder="TODO_DRILL_PROTOCOL — enter the coach’s instructions"
              onChange={(e) => onChange({ ...s, protocol: e.target.value })}
            />
          </label>
          <details>
            <summary>Configure this session’s nine spot labels</summary>
            <p>
              Labels are placeholders until defined by your coach. This grid is
              an ordered list, not official court geometry.
            </p>
            <div className="spot-settings">
              {s.spots.map((spot, i) => (
                <label className="field" key={i}>
                  Spot {i + 1}
                  <input
                    value={spot}
                    maxLength={80}
                    onChange={(e) =>
                      onChange({
                        ...s,
                        spots: s.spots.map((v, j) =>
                          i === j ? e.target.value : v,
                        ),
                      })
                    }
                  />
                </label>
              ))}
            </div>
          </details>
        </>
      )}
      {(tab === "Shooting" ||
        tab === "FT conditioning" ||
        tab === "Collection") && (
        <>
          {!selected ? (
            <Empty title="Include your players first">
              Add names in Setup, then include that local roster in this
              practice.
            </Empty>
          ) : (
            <>
              <label className="field player-select">
                Player
                <select
                  value={selected.id}
                  onChange={(e) => setPlayer(e.target.value)}
                >
                  {s.players.map((p) => (
                    <option key={p.id} value={p.id}>
                      #{p.number} {p.name}
                    </option>
                  ))}
                </select>
              </label>
              {tab === "Shooting" && (
                <>
                  <div className="section-heading">
                    <h2>Nine-spot shooting</h2>
                    <span className="badge">Player-attributed</span>
                  </div>
                  <p>
                    Enter observed makes and attempts at each coach-defined
                    spot. Blank is unentered; 0 is an observation.
                  </p>
                  {!s.protocol && (
                    <Notice>
                      Protocol not supplied. Configure the spot labels and
                      session protocol in Plan before real collection.
                    </Notice>
                  )}
                  <div className="nine-spots">
                    {s.spots.map((name, i) => (
                      <section key={i}>
                        <div className="station-title">
                          <span>{String(i + 1).padStart(2, "0")}</span>
                          <h3>{name || "Spot name not entered"}</h3>
                        </div>
                        <Count
                          label={`${name} makes`}
                          value={pair(String(i)).made}
                          onChange={(v) =>
                            changePair(String(i), {
                              ...pair(String(i)),
                              made: v,
                            })
                          }
                        />
                        <Count
                          label={`${name} attempts`}
                          value={pair(String(i)).attempts}
                          onChange={(v) =>
                            changePair(String(i), {
                              ...pair(String(i)),
                              attempts: v,
                            })
                          }
                        />
                        <p className="muted">{percent(pair(String(i)))}</p>
                      </section>
                    ))}
                  </div>
                </>
              )}
              {tab === "FT conditioning" && (
                <>
                  <h2>Free-throw conditioning</h2>
                  <p>
                    Observed makes and attempts for {selected.name}.
                    Conditioning rules remain the coach’s session protocol.
                  </p>
                  <div className="field-grid">
                    <Count
                      label="Free-throw makes"
                      value={s.ft[selected.id]?.made ?? ""}
                      onChange={(v) =>
                        onChange({
                          ...s,
                          ft: {
                            ...s.ft,
                            [selected.id]: {
                              ...(s.ft[selected.id] ?? {
                                made: "",
                                attempts: "",
                              }),
                              made: v,
                            },
                          },
                        })
                      }
                    />
                    <Count
                      label="Free-throw attempts"
                      value={s.ft[selected.id]?.attempts ?? ""}
                      onChange={(v) =>
                        onChange({
                          ...s,
                          ft: {
                            ...s.ft,
                            [selected.id]: {
                              ...(s.ft[selected.id] ?? {
                                made: "",
                                attempts: "",
                              }),
                              attempts: v,
                            },
                          },
                        })
                      }
                    />
                  </div>
                  <p>
                    {percent(s.ft[selected.id] ?? { made: "", attempts: "" })}
                  </p>
                </>
              )}
              {tab === "Collection" && (
                <>
                  <h2>Collect a coach-selected observation</h2>
                  <label className="field">
                    Template
                    <select
                      value={chosen}
                      onChange={(e) => {
                        setChosen(e.target.value);
                        setValues({});
                        setNote("");
                      }}
                    >
                      <option value="">Choose a template</option>
                      {templates.map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  {t && (
                    <>
                      <Notice>
                        {t.definition ||
                          "Counting rule not supplied. Define it in Setup."}{" "}
                        · definition v{t.version}
                      </Notice>
                      {t.kind === "count" || t.kind === "timed" ? (
                        <Count
                          label={
                            t.kind === "timed"
                              ? "Event time (seconds)"
                              : "Count"
                          }
                          value={values.count ?? ""}
                          onChange={(v) => setValues({ ...values, count: v })}
                        />
                      ) : t.kind === "makes" ? (
                        <div className="field-grid">
                          <Count
                            label="Makes"
                            value={values.made ?? ""}
                            onChange={(v) => setValues({ ...values, made: v })}
                          />
                          <Count
                            label="Attempts"
                            value={values.attempts ?? ""}
                            onChange={(v) =>
                              setValues({ ...values, attempts: v })
                            }
                          />
                        </div>
                      ) : null}
                      <label className="field">
                        Observation note
                        <textarea
                          value={note}
                          maxLength={4000}
                          onChange={(e) => setNote(e.target.value)}
                        />
                      </label>
                      <button
                        type="button"
                        className="primary"
                        onClick={addObservation}
                      >
                        {editing
                          ? "Save observation correction"
                          : "Add observation to draft"}
                      </button>
                    </>
                  )}
                  {issue && <Notice error>{issue}</Notice>}
                  <div className="actions">
                    <button
                      type="button"
                      disabled={!s.observations.length}
                      onClick={() => {
                        const last = s.observations.at(-1);
                        if (!last) return;
                        const before = s.observations.find(
                          (o) => o.id === last.supersedes,
                        );
                        onChange({
                          ...s,
                          observations: [
                            ...s.observations,
                            {
                              ...(before ?? last),
                              id: id(),
                              supersedes: last.id,
                              withdrawn: before ? !!before.withdrawn : true,
                              correctedAt: new Date().toISOString(),
                            },
                          ],
                        });
                      }}
                    >
                      Undo last observation change
                    </button>
                    <span className="muted">
                      {s.observations.length} retained history records
                    </span>
                  </div>
                  <div className="ledger-rows">
                    {visibleObservations.map((o) => (
                      <div className="observation" key={o.id}>
                        <div>
                          <strong>
                            {o.template.name} · v{o.template.version}
                          </strong>
                          <small>
                            {s.players.find((p) => p.id === o.playerID)?.name ??
                              "Team"}{" "}
                            ·{" "}
                            {Object.entries(o.values)
                              .map(([k, v]) => `${k}: ${shown(v)}`)
                              .join(" / ")}{" "}
                            · {o.note}
                          </small>
                          <small>Rule used: {o.template.definition}</small>
                        </div>
                        <button
                          type="button"
                          onClick={() => {
                            setChosen(o.template.id);
                            setValues(o.values);
                            setNote(o.note);
                            setPlayer(o.playerID ?? "");
                            setEditing(o.id);
                          }}
                        >
                          Correct observation
                        </button>
                        <button
                          type="button"
                          onClick={() =>
                            onChange({
                              ...s,
                              observations: [
                                ...s.observations,
                                {
                                  ...o,
                                  id: id(),
                                  supersedes: o.id,
                                  withdrawn: true,
                                  correctedAt: new Date().toISOString(),
                                },
                              ],
                            })
                          }
                        >
                          Withdraw with history
                        </button>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </>
          )}
        </>
      )}
      {tab === "Results" && (
        <>
          <div className="section-heading">
            <h2>Practice observations</h2>
            <label className="field">
              Results player
              <select
                value={resultPlayer}
                onChange={(e) => setResultPlayer(e.target.value)}
              >
                <option value="all">All included players</option>
                {s.players.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} · #{p.number}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <Notice>
            {provenance} Percentages use observed makes / attempts. No ranking
            or causal conclusions are inferred.
          </Notice>
          <Scroller label="Practice shooting results">
            <table>
              <thead>
                <tr>
                  <th>Player</th>
                  {s.spots.map((spot, i) => (
                    <th key={i}>
                      {spot || `Spot ${i + 1}`}
                      <small>Made / attempted</small>
                    </th>
                  ))}
                  <th>FT made / attempted</th>
                </tr>
              </thead>
              <tbody>
                {resultPlayers.map((p) => (
                  <tr key={p.id}>
                    <th scope="row">
                      {p.name}
                      <small>#{p.number}</small>
                    </th>
                    {s.spots.map((_, i) => {
                      const a = s.shooting[p.id]?.[String(i)];
                      return (
                        <td key={i}>
                          {shown(a?.made)} / {shown(a?.attempts)}
                          <small>
                            {percent(a ?? { made: "", attempts: "" })}
                          </small>
                        </td>
                      );
                    })}
                    <td>
                      {shown(s.ft[p.id]?.made)} / {shown(s.ft[p.id]?.attempts)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Scroller>
          <h3>Recorded template observations</h3>
          {resultObservations.length === 0 ? (
            <p className="muted">No observations entered.</p>
          ) : (
            resultObservations.map((o) => (
              <p key={o.id}>
                {o.template.name} (definition v{o.template.version}) ·{" "}
                {s.players.find((p) => p.id === o.playerID)?.name ?? "Team"} ·{" "}
                {Object.entries(o.values)
                  .map(([k, v]) => `${k}: ${shown(v)}`)
                  .join(", ")}{" "}
                · {o.note || "No note"} · Rule used: {o.template.definition}
              </p>
            ))
          )}
        </>
      )}
    </>
  );
}
