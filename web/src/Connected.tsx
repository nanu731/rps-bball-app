import { WebSessions } from "./WebSessions.tsx";
import { useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import type { Manual, Player } from "./domain.ts";
import { id } from "./domain.ts";
import {
  clientFor,
  CoreServer,
  ServerError,
  KIND_LABEL,
  validateVersion,
  decodeManual,
  encodeRecords,
  operationConfirmed,
  recordChanges,
} from "./server.ts";
import type {
  Access,
  EditRequest,
  Game,
  Kind,
  Team,
  Version,
  PendingOperation,
} from "./server.ts";
import { ManualEntry, ManualSummary } from "./Manual.tsx";
import {
  Empty,
  Notice,
  Tabs,
  download,
  useUnsavedGuard,
  Scroller,
} from "./ui.tsx";
import type { NavigationGuard } from "./ui.tsx";
const CONFIG = "teamstats-web-public-config";
const kinds = Object.keys(KIND_LABEL) as Kind[];
export function Connected({
  navigationGuard,
}: {
  navigationGuard: NavigationGuard;
}) {
  const [url, setUrl] = useState(""),
    [key, setKey] = useState(""),
    [client, setClient] = useState<SupabaseClient | null>(null),
    [error, setError] = useState(""),
    [user, setUser] = useState<User | null>(null),
    [email, setEmail] = useState(""),
    [otp, setOTP] = useState(""),
    [pending, setPending] = useState(false),
    [sent, setSent] = useState(false),
    [teams, setTeams] = useState<Team[]>([]),
    [team, setTeam] = useState(""),
    [join, setJoin] = useState(""),
    [message, setMessage] = useState("");
  const server = useMemo(
      () => (client ? new CoreServer(client, url) : null),
      [client],
    ),
    generation = useRef(0),
    actorRef = useRef<string | null>(null);
  useEffect(() => {
    try {
      const saved = localStorage.getItem(CONFIG);
      const config = saved ? JSON.parse(saved) : null;
      const u = config?.url ?? import.meta.env.VITE_SUPABASE_URL ?? "",
        k = config?.key ?? import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "";
      setUrl(u);
      setKey(k);
      if (u && k) setClient(clientFor(u, k));
    } catch {
      setError(
        "Could not load public connection configuration. Re-enter it; no account authority was assumed.",
      );
    }
  }, []);
  const verify = async (keep = false) => {
    if (!client || !server) return;
    const g = ++generation.current;
    if (!keep) {
      server.epoch++;
      setUser(null);
      setTeams([]);
      setTeam("");
    }
    setError("");
    setPending(true);
    try {
      const u = await server.identity();
      const rows = await server.rows<Team>("teams", "id,name");
      if (g !== generation.current) return;
      if (actorRef.current !== null && actorRef.current !== u.id) {
        server.epoch++;
        setTeam("");
      }
      actorRef.current = u.id;
      setUser(u);
      setTeams(rows);
      setMessage(
        "Account verified by Supabase. Team permissions are checked by the server.",
      );
    } catch (e) {
      if (g === generation.current) {
        if (
          e instanceof ServerError &&
          ["401", "403", "42501"].includes(e.code)
        ) {
          actorRef.current = null;
          setUser(null);
          setTeams([]);
          setTeam("");
          server.epoch++;
        }
        setError((e as Error).message);
      }
    } finally {
      if (g === generation.current) setPending(false);
    }
  };
  useEffect(() => {
    if (!client) return;
    let disposed = false;
    const { data } = client.auth.onAuthStateChange((_event, session) => {
      if (disposed) return;
      const same =
        actorRef.current !== null && actorRef.current === session?.user.id;
      if (!same) {
        generation.current++;
        server!.epoch++;
        setUser(null);
        setTeams([]);
        setTeam("");
        actorRef.current = null;
      }
      setTimeout(() => {
        if (!disposed) void verify(same);
      }, 0);
    });
    void verify();
    return () => {
      disposed = true;
      generation.current++;
      server!.epoch++;
      data.subscription.unsubscribe();
    };
  }, [client]);
  const auth = async (action: "send" | "verify" | "out") => {
    if (!client || pending) return;
    setPending(true);
    setError("");
    setMessage("");
    try {
      if (action === "out") {
        if (!navigationGuard.current()) return;
        generation.current++;
        server!.epoch++;
        setUser(null);
        setTeams([]);
        setTeam("");
        const { error } = await client.auth.signOut({ scope: "local" });
        if (error)
          throw Error(
            "This browser has been concealed, but server sign-out was not confirmed. Check session again before continuing.",
          );
        setMessage(
          "Signed out of this browser. Original local drafts were not uploaded or removed.",
        );
      } else if (action === "send") {
        const { error } = await client.auth.signInWithOtp({
          email: email.trim(),
          options: {
            shouldCreateUser: false,
            emailRedirectTo: location.origin,
          },
        });
        if (error)
          throw Error(
            "Could not request email sign-in. Check the address/provider configuration; no account was created.",
          );
        setSent(true);
        setMessage(
          "Email requested. Use the link or code supplied by your configured provider. Delivery is not guaranteed by this screen.",
        );
      } else {
        const { error } = await client.auth.verifyOtp({
          email: email.trim(),
          token: otp,
          type: "email",
        });
        if (error)
          throw Error(
            "The code could not be verified. Check the code or request a new email.",
          );
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setPending(false);
    }
  };
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>Shared team workspace</h1>
          {!team && (
            <p>
              Supabase is authoritative. Browser drafts never upload
              automatically.
            </p>
          )}
        </div>
        {client && !team && (
          <button
            type="button"
            disabled={pending}
            onClick={() => void verify(true)}
          >
            {pending ? "Checking…" : "Check session again"}
          </button>
        )}
      </div>
      {error && (
        <Notice error>
          {error}
          <button
            type="button"
            disabled={pending}
            onClick={() => void verify(true)}
          >
            Retry connection
          </button>
        </Notice>
      )}
      <details className="account-details" open={!team}>
        <summary>Team and account{user ? " · verified" : ""}</summary>
        {team && client && (
          <button
            type="button"
            disabled={pending}
            onClick={() => void verify(true)}
          >
            Check session again
          </button>
        )}
        {message && (
          <p className="receipt" role="status">
            {message}
          </p>
        )}
        {!client ? (
          <form
            className="create-form"
            onSubmit={(e) => {
              e.preventDefault();
              try {
                const c = clientFor(url, key);
                localStorage.setItem(CONFIG, JSON.stringify({ url, key }));
                setClient(c);
                setError("");
              } catch (e) {
                setError((e as Error).message);
              }
            }}
          >
            <h2>Connect nonproduction</h2>
            <p>
              Only a browser publishable/anon key belongs here. Never enter a
              service-role key. No project or owner authority is created.
            </p>
            <label className="field">
              Project URL
              <input
                type="url"
                required
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                placeholder="https://your-project.supabase.co"
              />
            </label>
            <label className="field">
              Publishable key
              <input
                required
                value={key}
                onChange={(e) => setKey(e.target.value)}
                autoComplete="off"
              />
            </label>
            <button type="submit" className="primary">
              Use this connection
            </button>
          </form>
        ) : !user ? (
          <section className="auth-form">
            <h2>Sign in to an existing account</h2>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void auth(sent ? "verify" : "send");
              }}
            >
              <label className="field">
                Email
                <input
                  type="email"
                  autoComplete="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </label>
              {sent && (
                <label className="field">
                  Email code
                  <input
                    value={otp}
                    onChange={(e) => setOTP(e.target.value)}
                    autoComplete="one-time-code"
                    inputMode="numeric"
                    required
                  />
                </label>
              )}
              <div className="actions">
                <button type="submit" className="primary" disabled={pending}>
                  {pending
                    ? "Contacting Supabase…"
                    : sent
                      ? "Verify code"
                      : "Request sign-in email"}
                </button>
                {sent && (
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => void auth("send")}
                  >
                    Request new email
                  </button>
                )}
              </div>
            </form>
            <p className="muted">
              SMS remains disabled under the $0 boundary. Email
              delivery/templates and redirect allowlists are provider
              configuration gates. No signup or paid sender is activated here.
            </p>
          </section>
        ) : (
          <>
            <div className="account-strip">
              <strong>Account verified</strong>
              <span>{user.email ?? "Verified account"}</span>
              <button
                type="button"
                disabled={pending}
                onClick={() => void auth("out")}
              >
                Sign out of this browser
              </button>
            </div>
            {teams.length === 0 ? (
              <Empty title="No accessible teams">
                A verified account is not team membership. Request admission
                with a team ID supplied privately by the owner.
              </Empty>
            ) : (
              <label className="field">
                Team
                <select
                  value={team}
                  onChange={(e) => {
                    if (navigationGuard.current()) setTeam(e.target.value);
                  }}
                >
                  <option value="">Choose a team</option>
                  {teams.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.name}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <details>
              <summary>Request team admission</summary>
              <form
                className="inline-form"
                onSubmit={async (e) => {
                  e.preventDefault();
                  if (pending) return;
                  setPending(true);
                  try {
                    const { data, error } = await client.rpc(
                      "team_request_membership",
                      { p_team_id: join.trim() },
                    );
                    if (error) throw new ServerError(error.code);
                    setMessage(
                      `Server-confirmed admission status: ${data}. Only an authorized administrator can activate membership.`,
                    );
                  } catch (e) {
                    setError((e as Error).message);
                  } finally {
                    setPending(false);
                  }
                }}
              >
                <label className="field">
                  Owner-provided team ID
                  <input
                    required
                    value={join}
                    onChange={(e) => setJoin(e.target.value)}
                    pattern="[0-9a-fA-F-]{36}"
                  />
                </label>
                <button type="submit" disabled={pending}>
                  Request admission
                </button>
              </form>
            </details>
          </>
        )}
      </details>
      {user && team && server && (
        <SharedTeam
          key={user.id + ":" + team}
          server={server}
          team={teams.find((t) => t.id === team)!}
          actor={user.id}
          navigationGuard={navigationGuard}
        />
      )}
      <details className="capability-boundary">
        <summary>What is connected in this web pilot?</summary>
        <p>
          Existing shared manual statistics use current Auth, team authority,
          RLS and version/review commands. Practice plans, running clocks and
          court/event capture have a separate prepared server contract. Shared
          use is available only on a compatible authorized server; hosted
          activation remains unverified. Video permissions do not authorize
          practice collection. No Sheets/media delivery or scheduling is
          activated.
        </p>
      </details>
    </>
  );
}
function SharedTeam({
  navigationGuard,
  server,
  team,
  actor,
}: {
  server: CoreServer;
  team: Team;
  actor: string;
  navigationGuard: NavigationGuard;
}) {
  const adminKey = `teamstats-web-admin-pending:${encodeURIComponent(server.namespace)}:${team.id}:${actor}`;
  type AdminAttempt = { name: string; args: Record<string, unknown> };
  const [adminAttempt, setAdminAttempt] = useState<AdminAttempt | null>(() => {
    try {
      return JSON.parse(sessionStorage.getItem(adminKey) ?? "null");
    } catch {
      return { name: "unreadable", args: {} };
    }
  });
  const [adminChecked, setAdminChecked] = useState(false);
  const [access, setAccess] = useState<Access | null>(null),
    [games, setGames] = useState<Game[]>([]),
    [roster, setRoster] = useState<Player[]>([]),
    [revisions, setRevisions] = useState<Player[]>([]),
    [game, setGame] = useState<Game | null>(null),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [manage, setManage] = useState(false),
    [members, setMembers] = useState<{ status: string; user_id: string }[]>([]),
    [opponent, setOpponent] = useState(""),
    [date, setDate] = useState(new Date().toLocaleDateString("en-CA")),
    [venue, setVenue] = useState("home"),
    [type, setType] = useState("regularSeason"),
    [newID, setNewID] = useState(id),
    [uncertain, setUncertain] = useState(false),
    [section, setSection] = useState("Manual games"),
    [adminTarget, setAdminTarget] = useState(""),
    [adminCap, setAdminCap] = useState("sessions.record"),
    [adminLocked, setAdminLocked] = useState(!!adminAttempt),
    [adminReceipt, setAdminReceipt] = useState("");
  const generation = useRef(0),
    busyRef = useRef(false);
  const conceal = () => {
    generation.current++;
    server.epoch++;
    setAccess(null);
    setGames([]);
    setRoster([]);
    setRevisions([]);
    setGame(null);
    setManage(false);
    setMembers([]);
    setError("Current team access was denied. Cached team data is concealed.");
  };
  const load = async () => {
    const g = ++generation.current;
    setBusy(true);
    setError("");
    try {
      const a = await server.access(team.id);
      const [list, players, history] = await Promise.all([
        server.rows<Game>(
          "games",
          "id,team_id,date,opponent,home_away,game_type,publication_generation",
          { team_id: team.id },
        ),
        server.rows<{
          id: string;
          display_name: string;
          jersey_number: string;
          version: number;
          archived_at: string | null;
        }>(
          "roster_entries",
          "id,display_name,jersey_number,version,archived_at",
          { team_id: team.id },
        ),
        server.rows<{
          roster_id: string;
          display_name: string;
          jersey_number: string;
          version: number;
        }>(
          "roster_entry_revisions",
          "roster_id,display_name,jersey_number,version",
          { team_id: team.id },
          "roster_id,version",
        ),
      ]);
      if (g !== generation.current) return;
      setAccess(a);
      setGames(list);
      setRoster(
        players
          .filter((p) => !p.archived_at)
          .map((p) => ({
            id: p.id,
            name: p.display_name,
            number: p.jersey_number,
            version: p.version,
          })),
      );
      setRevisions(
        history.map((p) => ({
          id: p.roster_id,
          name: p.display_name,
          number: p.jersey_number,
          version: p.version,
        })),
      );
      if (uncertain) {
        const saved = list.find((x) => x.id === newID);
        if (saved) {
          setGame(saved);
          setUncertain(false);
          setNewID(id());
          setOpponent("");
        }
      }
    } catch (e) {
      if (g !== generation.current) return;
      if (
        e instanceof ServerError &&
        ["42501", "401", "403"].includes(e.code)
      ) {
        setAccess(null);
        setGames([]);
        setRoster([]);
        setRevisions([]);
        setGame(null);
      }
      setError((e as Error).message);
    } finally {
      if (g === generation.current) setBusy(false);
    }
  };
  useEffect(() => {
    void load();
    const focus = () => {
      void load();
    };
    window.addEventListener("focus", focus);
    return () => {
      generation.current++;
      window.removeEventListener("focus", focus);
    };
  }, [team.id]);
  const create = async () => {
    if (busyRef.current || uncertain) return;
    busyRef.current = true;
    setBusy(true);
    setError("");
    try {
      if (!opponent.trim()) throw Error("Enter an opponent.");
      const row = await server.command<Game>(team.id, "stats_create_game", {
        p_game_id: newID,
        p_date: date,
        p_opponent: opponent.trim(),
        p_home_away: venue,
        p_game_type: type,
      });
      if (row.team_id !== team.id || row.id !== newID)
        throw new ServerError("invalid", true);
      setGame(row);
      setNewID(id());
      setOpponent("");
      await load();
    } catch (e) {
      if (e instanceof ServerError && e.uncertain) setUncertain(true);
      if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code))
        conceal();
      setError((e as Error).message);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  const adminCommand = async (name: string, args: Record<string, unknown>) => {
    if (busyRef.current || adminLocked || !access) return;
    busyRef.current = true;
    setBusy(true);
    setAdminReceipt("");
    const attempt = { name, args };
    try {
      sessionStorage.setItem(adminKey, JSON.stringify(attempt));
      setAdminAttempt(attempt);
      setAdminChecked(false);
      await server.command(team.id, name, {
        ...args,
        p_expected_access_revision: access.access_revision,
      });
      sessionStorage.removeItem(adminKey);
      setAdminAttempt(null);
      setAdminReceipt(
        "Server confirmed the administration change. Effective access is rechecked on every operation.",
      );
      await load();
      setMembers(
        await server.rows(
          "team_memberships",
          "status,user_id",
          {
            team_id: team.id,
          },
          "user_id",
        ),
      );
    } catch (e) {
      if (e instanceof ServerError && e.uncertain) setAdminLocked(true);
      else {
        sessionStorage.removeItem(adminKey);
        setAdminAttempt(null);
      }
      if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code))
        conceal();
      setError((e as Error).message);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  const reconcileAdmin = async () => {
    if (!adminAttempt || busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setAdminChecked(false);
    try {
      const before = await server.access(team.id);
      let description: string;
      if (adminAttempt.name === "team_set_capability") {
        const grants = await server.rows<{
          revoked_at: string | null;
          expires_at: string | null;
        }>("capability_grants", "id,revoked_at,expires_at", {
          team_id: team.id,
          user_id: String(adminAttempt.args.p_user_id),
          capability: String(adminAttempt.args.p_capability),
        });
        const current = grants.find((g) => g.revoked_at === null);
        description = current
          ? `Current stored grant is present${current.expires_at ? " with an expiry; server authority remains decisive" : ""}.`
          : "Current stored grant is absent.";
      } else if (adminAttempt.name === "team_set_membership") {
        const found = await server.rows<{ status: string }>(
          "team_memberships",
          "status,user_id",
          { team_id: team.id, user_id: String(adminAttempt.args.p_user_id) },
          "user_id",
        );
        description = `Current membership: ${found[0]?.status ?? "not visible"}.`;
      } else
        throw Error(
          "Unrecognized retained administration command; preserve recovery data for support.",
        );
      const after = await server.access(team.id);
      if (before.access_revision !== after.access_revision)
        throw Error("Authority changed during readback. Check again.");
      setAccess(after);
      setAdminReceipt(
        description +
          " The prior reply remains unconfirmed; no write was repeated. Review this state before allowing a new command.",
      );
      setAdminChecked(true);
    } catch (e) {
      if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code))
        conceal();
      setError((e as Error).message);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  return (
    <section className="shared-team">
      <div className="section-heading">
        <h2>{team.name}</h2>
        <details className="team-authority">
          <summary>Team authority & administration</summary>
          <p>Access revision {access?.access_revision ?? "not loaded"}</p>
          <div className="actions">
            <button type="button" disabled={busy} onClick={() => void load()}>
              Reload current authority
            </button>
            {access &&
              (access.is_owner ||
                access.capabilities.includes("members.manage") ||
                access.capabilities.includes("roster.manage")) && (
                <button
                  type="button"
                  onClick={async () => {
                    setManage(!manage);
                    try {
                      setAccess(await server.access(team.id));
                      setMembers(
                        await server.rows(
                          "team_memberships",
                          "status,user_id",
                          {
                            team_id: team.id,
                          },
                          "user_id",
                        ),
                      );
                    } catch (e) {
                      if (
                        e instanceof ServerError &&
                        ["401", "403", "42501"].includes(e.code)
                      )
                        conceal();
                      setError((e as Error).message);
                      setMembers([]);
                    }
                  }}
                >
                  Manage team
                </button>
              )}
          </div>
        </details>
      </div>
      {error && <Notice error>{error}</Notice>}
      {busy && <p role="status">Loading current team state…</p>}
      {access && (
        <p className="muted">
          {access.is_owner
            ? "Owner access confirmed by server"
            : access.can_propose_stats
              ? "Active member · draft proposals allowed"
              : "Active viewer"}{" "}
        </p>
      )}
      {manage && access && (
        <section className="create-form">
          <h3>Protected team administration</h3>
          <p>
            {members.length} visible membership records; {roster.length} active
            roster entries. Only server-confirmed authority permits a change. No
            owner identity is inferred from an email.
          </p>
          {adminReceipt && (
            <p className="receipt" role="status">
              {adminReceipt}
            </p>
          )}
          {members
            .filter((m) => m.user_id !== actor)
            .map((m) => (
              <div className="observation" key={m.user_id}>
                <div>
                  <strong>Account {m.user_id}</strong>
                  <small>Server membership: {m.status}</small>
                </div>
                {m.status === "pending" &&
                  (access.is_owner ||
                    access.capabilities.includes("members.manage")) && (
                    <button
                      type="button"
                      disabled={busy || adminLocked}
                      onClick={() =>
                        void adminCommand("team_set_membership", {
                          p_user_id: m.user_id,
                          p_status: "active",
                        })
                      }
                    >
                      Admit member
                    </button>
                  )}
              </div>
            ))}
          {access.is_owner && (
            <>
              <label className="field">
                Existing active member
                <select
                  value={adminTarget}
                  onChange={(e) => setAdminTarget(e.target.value)}
                >
                  <option value="">Choose an account</option>
                  {members
                    .filter((m) => m.user_id !== actor && m.status === "active")
                    .map((m) => (
                      <option key={m.user_id} value={m.user_id}>
                        {m.user_id}
                      </option>
                    ))}
                </select>
              </label>
              <label className="field">
                Capability
                <select
                  value={adminCap}
                  onChange={(e) => setAdminCap(e.target.value)}
                >
                  {[
                    "stats.review",
                    "stats.publish",
                    "datasets.reopen",
                    "roster.manage",
                    "members.manage",
                    "sessions.manage",
                    "sessions.record",
                    "sessions.clock",
                    "sessions.review",
                    "sessions.publish",
                    "sessions.reopen",
                  ].map((cap) => (
                    <option key={cap}>{cap}</option>
                  ))}
                </select>
              </label>
              <div className="actions">
                <button
                  type="button"
                  disabled={busy || adminLocked || !adminTarget}
                  onClick={() => {
                    if (
                      window.confirm(
                        `Grant ${adminCap} to this selected existing account?`,
                      )
                    )
                      void adminCommand("team_set_capability", {
                        p_user_id: adminTarget,
                        p_capability: adminCap,
                        p_enabled: true,
                      });
                  }}
                >
                  Grant selected capability
                </button>
                <button
                  type="button"
                  disabled={busy || adminLocked || !adminTarget}
                  onClick={() => {
                    if (
                      window.confirm(
                        `Revoke ${adminCap} from this selected existing account?`,
                      )
                    )
                      void adminCommand("team_set_capability", {
                        p_user_id: adminTarget,
                        p_capability: adminCap,
                        p_enabled: false,
                      });
                  }}
                >
                  Revoke selected capability
                </button>
              </div>
              <p className="muted">
                sessions.* permissions are separate from practice-video grants.
                Unactivated servers reject unsupported names. This panel does
                not create accounts or delegate owner authority.
              </p>
            </>
          )}
          {adminLocked && (
            <Notice error>
              Administration result uncertain. No command will be replayed.
              <div className="actions">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void reconcileAdmin()}
                >
                  Read current attempted target state
                </button>
                {adminChecked && (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      try {
                        sessionStorage.removeItem(adminKey);
                        setAdminAttempt(null);
                        setAdminLocked(false);
                        setAdminChecked(false);
                        setError("");
                      } catch {
                        setError(
                          "Could not clear the recovery marker. New administration remains blocked.",
                        );
                      }
                    }}
                  >
                    I reviewed the current state; allow a new command
                  </button>
                )}
              </div>
            </Notice>
          )}
        </section>
      )}
      {access && (
        <Tabs
          items={["Manual games", "Practices & capture"]}
          value={section}
          onChange={(next) => {
            if (navigationGuard.current()) setSection(next);
          }}
          label="Shared team section"
        />
      )}
      {section === "Practices & capture" && access ? (
        <WebSessions
          server={server}
          team={team.id}
          actor={actor}
          access={access}
          roster={roster}
          games={games}
          onDenied={conceal}
          navigationGuard={navigationGuard}
        />
      ) : game && access ? (
        <>
          <button
            type="button"
            className="back"
            onClick={() => {
              if (navigationGuard.current()) setGame(null);
            }}
          >
            Back to shared games
          </button>
          <SharedGame
            key={`${actor}:${game.id}`}
            server={server}
            game={game}
            actor={actor}
            access={access}
            roster={roster}
            rosterHistory={revisions}
            onDenied={conceal}
            navigationGuard={navigationGuard}
          />
        </>
      ) : (
        access && (
          <>
            <div className="ledger-rows">
              {games.map((g) => (
                <button
                  type="button"
                  className="session-row"
                  key={g.id}
                  onClick={() => setGame(g)}
                >
                  <span className="session-title">
                    <strong>{g.opponent}</strong>
                    <small>
                      {g.date} · {g.home_away === "home" ? "Home" : "Away"}
                    </small>
                  </span>
                  <span className="badge">Server game</span>
                </button>
              ))}
            </div>
            {games.length === 0 && (
              <p>No saved games visible to this account.</p>
            )}
            {access.can_propose_stats && (
              <form
                className="create-form"
                onSubmit={(e) => {
                  e.preventDefault();
                  void create();
                }}
              >
                <h3>Add shared game</h3>
                <div className="field-grid">
                  <label className="field">
                    Opponent
                    <input
                      required
                      maxLength={100}
                      value={opponent}
                      onChange={(e) => setOpponent(e.target.value)}
                    />
                  </label>
                  <label className="field">
                    Date
                    <input
                      type="date"
                      required
                      value={date}
                      onChange={(e) => setDate(e.target.value)}
                    />
                  </label>
                  <label className="field">
                    Our team
                    <select
                      value={venue}
                      onChange={(e) => setVenue(e.target.value)}
                    >
                      <option value="home">Home</option>
                      <option value="away">Away</option>
                    </select>
                  </label>
                  <label className="field">
                    Game type
                    <select
                      value={type}
                      onChange={(e) => setType(e.target.value)}
                    >
                      <option value="regularSeason">Regular season</option>
                      <option value="playoff">Playoff</option>
                    </select>
                  </label>
                </div>
                <button
                  type="submit"
                  className="primary"
                  disabled={busy || uncertain}
                >
                  Create server game
                </button>
                {uncertain && (
                  <p>
                    Creation result is uncertain. Reload to reconcile this
                    stable game ID; do not create another copy.
                  </p>
                )}
              </form>
            )}
          </>
        )
      )}
    </section>
  );
}
function SharedGame({
  navigationGuard,
  server,
  game,
  actor,
  access,
  roster,
  rosterHistory,
  onDenied,
}: {
  server: CoreServer;
  game: Game;
  actor: string;
  access: Access;
  roster: Player[];
  rosterHistory: Player[];
  onDenied: () => void;
  navigationGuard: NavigationGuard;
}) {
  const pendingKey = `teamstats-manual-pending:${encodeURIComponent(server.namespace)}:${actor}:${game.team_id}:${game.id}`;
  const [retainedOperation] = useState<PendingOperation | null>(() => {
    try {
      const raw = sessionStorage.getItem(pendingKey);
      if (!raw) return null;
      const op = JSON.parse(raw);
      if (op.actor !== actor || typeof op.name !== "string" || !op.args)
        throw Error();
      return op;
    } catch {
      return { actor, name: "unreadable", args: {} };
    }
  });
  const [versions, setVersions] = useState<Version[]>([]),
    [pointers, setPointers] = useState<
      { dataset_type: Kind; published_version_id: string | null }[]
    >([]),
    [requests, setRequests] = useState<EditRequest[]>([]),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState(""),
    [view, setView] = useState("Accepted summary"),
    [kind, setKind] = useState<Kind>("box_scores"),
    [editing, setEditing] = useState<Version | null>(null),
    [manual, setManual] = useState<Manual>({
      box: {},
      paint: {},
      ours: [],
      opponent: [],
    }),
    [dirty, setDirty] = useState(false),
    [uncertain, setUncertain] = useState(!!retainedOperation),
    [confirmRoster, setConfirmRoster] = useState(false),
    [confirmZeros, setConfirmZeros] = useState(false),
    [paired, setPaired] = useState<Version[]>([]),
    [loaded, setLoaded] = useState(false),
    [reconciled, setReconciled] = useState(false);
  useUnsavedGuard(navigationGuard, dirty);
  const busyRef = useRef(false),
    generation = useRef(0),
    recoveryKey = `teamstats-shared-buffer:${actor}:${game.team_id}:${game.id}`,
    pendingOp = useRef<PendingOperation | null>(retainedOperation);
  const load = async (reportExternalChange = true) => {
    const g = ++generation.current;
    setBusy(true);
    setError("");
    try {
      await server.access(game.team_id);
      const [v, p, r] = await Promise.all([
        server.rows<Version>("stat_versions", "*", {
          team_id: game.team_id,
          game_id: game.id,
        }),
        server.rows<{
          dataset_type: Kind;
          published_version_id: string | null;
        }>("stat_datasets", "dataset_type,published_version_id", {
          team_id: game.team_id,
          game_id: game.id,
        }),
        server.rows<EditRequest>(
          "stat_edit_requests",
          "*,source:stat_versions!stat_edit_requests_source_version_id_fkey!inner(game_id)",
          { team_id: game.team_id, "source.game_id": game.id },
        ),
      ]);
      v.forEach((x) => {
        validateVersion(x, game.team_id, game.id);
        for (const c of x.covered_roster) {
          if (
            !rosterHistory.some(
              (p) =>
                p.id.toLowerCase() === c.id.toLowerCase() &&
                p.version === c.version,
            )
          )
            throw Error(
              "A covered roster revision is unavailable; saved labels were not replaced.",
            );
        }
      });
      if (g !== generation.current) return;
      setVersions(v);
      setPointers(p);
      setRequests(r);
      setLoaded(true);
      if (editing && reportExternalChange) {
        const latest = v.find((x) => x.id === editing.id);
        if (latest && latest.revision > editing.revision)
          setMessage(
            "A newer server revision exists. Compare it with retained entries before continuing.",
          );
      }
    } catch (e) {
      if (g !== generation.current) return;
      if (
        e instanceof ServerError &&
        ["42501", "401", "403"].includes(e.code)
      ) {
        setVersions([]);
        setPointers([]);
        setRequests([]);
        setView("Accepted summary");
        setEditing(null);
        onDenied();
      }
      setError((e as Error).message);
    } finally {
      if (g === generation.current) setBusy(false);
    }
  };
  useEffect(() => {
    void load();
    return () => {
      generation.current++;
    };
  }, [game.id]);
  useEffect(() => {
    const handler = (e: BeforeUnloadEvent) => {
      if (dirty) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [dirty]);
  const mutate = async <T,>(
    name: string,
    args: Record<string, unknown>,
    onSuccess?: (value: T) => void,
  ) => {
    if (busyRef.current || uncertain) return;
    busyRef.current = true;
    setBusy(true);
    setError("");
    setMessage("");
    pendingOp.current = { name, args: structuredClone(args), actor };
    setReconciled(false);
    try {
      sessionStorage.setItem(pendingKey, JSON.stringify(pendingOp.current));
      const value = await server.command<T>(game.team_id, name, args);
      onSuccess?.(value);
      sessionStorage.removeItem(pendingKey);
      pendingOp.current = null;
      setMessage(
        "Server confirmed this operation. Saving, completion, submission and publication are separate states.",
      );
      await load(false);
    } catch (e) {
      if (!(e instanceof ServerError) || e.uncertain) setUncertain(true);
      else {
        sessionStorage.removeItem(pendingKey);
        pendingOp.current = null;
      }
      if (
        e instanceof ServerError &&
        ["401", "403", "42501"].includes(e.code)
      ) {
        setVersions([]);
        setEditing(null);
        setPointers([]);
        setRequests([]);
        onDenied();
      }
      setError((e as Error).message);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  const labelsFor = (v: Version): Player[] =>
    v.covered_roster.map((c) => {
      const p = rosterHistory.find(
        (p) =>
          p.id.toLowerCase() === c.id.toLowerCase() && p.version === c.version,
      );
      if (!p)
        throw Error(
          "A covered roster revision is unavailable; no name was substituted.",
        );
      return p;
    });
  const begin = (v: Version, companions: Version[] = paired) => {
    try {
      validateVersion(v, game.team_id, game.id);
      decodeManual([v], game.id);
      labelsFor(v);
      const both =
        v.dataset_type === "our_possessions" ||
        v.dataset_type === "opponent_possessions"
          ? [v, ...companions.filter((x) => x.id !== v.id)]
          : [];
      setPaired(both);
      setEditing(v);
      setKind(v.dataset_type);
      setManual(decodeManual(both.length ? both : [v], game.id));
      setDirty(false);
      setConfirmRoster(false);
      setConfirmZeros(false);
      setView("Draft entry");
    } catch (e) {
      setError((e as Error).message);
    }
  };
  const players =
    editing && (kind === "box_scores" || kind === "player_paint_touches")
      ? editing.covered_roster.length
        ? labelsFor(editing)
        : roster
      : roster;
  const buffer = (m: Manual) => {
    setManual(m);
    setDirty(true);
    try {
      sessionStorage.setItem(
        recoveryKey,
        JSON.stringify({
          actor,
          game: game.id,
          team: game.team_id,
          version: editing,
          manual: m,
        }),
      );
    } catch {
      setError(
        "Browser recovery storage failed. Keep this tab open and download the unsaved draft before leaving.",
      );
    }
  };
  const accepted = versions.filter(
    (v) =>
      pointers.some((p) => p.published_version_id === v.id) &&
      v.status === "published",
  );
  let acceptedManual: Manual = { box: {}, paint: {}, ours: [], opponent: [] },
    acceptedPlayers: Player[] = [];
  try {
    acceptedManual = decodeManual(accepted, game.id);
    acceptedPlayers = accepted
      .flatMap(labelsFor)
      .filter((p, i, a) => a.findIndex((x) => x.id === p.id) === i);
  } catch {
    /* The visible error below prevents fabricated labels. */
  }
  const reconcile = async () => {
    try {
      await server.access(game.team_id);
      const v = await server.rows<Version>("stat_versions", "*", {
        team_id: game.team_id,
        game_id: game.id,
      });
      const r = await server.rows<EditRequest>(
        "stat_edit_requests",
        "*,source:stat_versions!stat_edit_requests_source_version_id_fkey!inner(game_id)",
        { team_id: game.team_id, "source.game_id": game.id },
      );
      v.forEach((x) => validateVersion(x, game.team_id, game.id));
      setVersions(v);
      setRequests(r);
      setReconciled(true);
      if (pendingOp.current && operationConfirmed(pendingOp.current, v, r)) {
        const args = pendingOp.current.args;
        const target =
          editing?.id ??
          args.p_version_id ??
          (Array.isArray(args.p_items)
            ? args.p_items[0]?.version_id
            : undefined);
        const current =
          v.find((x) => x.id === target) ??
          (pendingOp.current.name === "stats_open_draft"
            ? v.find(
                (x) =>
                  x.author_user_id === actor &&
                  x.dataset_type === args.p_dataset_type &&
                  x.status === "draft",
              )
            : undefined);
        if (current)
          begin(
            current,
            v.filter(
              (x) =>
                x.author_user_id === actor &&
                ["our_possessions", "opponent_possessions"].includes(
                  x.dataset_type,
                ) &&
                ["draft", "completed", "submitted"].includes(x.status),
            ),
          );
        sessionStorage.removeItem(pendingKey);
        setUncertain(false);
        pendingOp.current = null;
        setMessage(
          "Reconciled with the exact expected saved revision/status. No write was replayed.",
        );
      } else
        setMessage(
          "Fresh server state does not establish the expected outcome. Retained entries are unchanged; inspect history before explicitly resuming with revision checks.",
        );
    } catch (e) {
      if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code))
        onDenied();
      setError((e as Error).message);
    }
  };
  const openWorking = async (target: Kind = kind) => {
    if (busyRef.current || uncertain) return;
    busyRef.current = true;
    setBusy(true);
    setError("");
    try {
      const chosen: Kind[] =
        target === "our_possessions" || target === "opponent_possessions"
          ? ["our_possessions", "opponent_possessions"]
          : [target];
      const found: Version[] = [];
      for (const k of chosen) {
        const existing = versions.find(
          (v) =>
            v.author_user_id === actor &&
            v.dataset_type === k &&
            ["draft", "completed", "submitted"].includes(v.status),
        );
        if (existing) {
          found.push(existing);
          continue;
        }
        const args = { p_game_id: game.id, p_dataset_type: k };
        pendingOp.current = { name: "stats_open_draft", args, actor };
        sessionStorage.setItem(pendingKey, JSON.stringify(pendingOp.current));
        const v = await server.command<Version>(
          game.team_id,
          "stats_open_draft",
          args,
        );
        found.push(validateVersion(v, game.team_id, game.id));
        sessionStorage.removeItem(pendingKey);
        pendingOp.current = null;
      }
      begin(
        found.find((v) => v.dataset_type === target)!,
        found,
      );
      await load();
    } catch (e) {
      if (!(e instanceof ServerError) || e.uncertain) setUncertain(true);
      else {
        sessionStorage.removeItem(pendingKey);
        pendingOp.current = null;
      }
      if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code))
        onDenied();
      setError((e as Error).message);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  };
  const saveWorking = () => {
    if (!editing) return;
    try {
      if (kind === "our_possessions" || kind === "opponent_possessions") {
        const editable = paired.filter((v) => v.status === "draft");
        const items = editable.map((v) => ({
          version_id: v.id,
          expected_revision: v.revision,
          records: encodeRecords(manual, v.dataset_type, game.id, players),
          covered_roster: [],
        }));
        void mutate<Version[]>(
          "stats_save_drafts",
          { p_items: items },
          (saved) => {
            saved.forEach((v) => validateVersion(v, game.team_id, game.id));
            const all = [
              ...saved,
              ...paired.filter((v) => v.status !== "draft"),
            ];
            begin(
              all.find((v) => v.id === editing.id)!,
              all,
            );
          },
        );
      } else {
        const records = encodeRecords(manual, kind, game.id, players);
        void mutate<Version>(
          "stats_save_draft",
          {
            p_version_id: editing.id,
            p_expected_revision: editing.revision,
            p_records: records,
            p_covered_roster: players.map((p) => ({
              id: p.id,
              version: p.version,
            })),
          },
          begin,
        );
      }
    } catch (e) {
      setError((e as Error).message);
    }
  };
  return (
    <>
      <div className="session-banner">
        <div>
          <h2>{game.opponent}</h2>
          <p>
            {game.date} · {game.home_away} · server-confirmed game
          </p>
        </div>
        <span>
          Independent datasets
          <br />
          Accepted versions only in summary
        </span>
      </div>
      <Tabs
        items={["Accepted summary", "Draft entry", "Review & history"]}
        value={view}
        onChange={setView}
        label="Shared game section"
      />
      {busy && <p role="status">Contacting statistics server…</p>}
      {error && (
        <Notice error>
          {error}
          <button type="button" disabled={busy} onClick={() => void load()}>
            Reload / Retry reads
          </button>
        </Notice>
      )}
      {message && (
        <p role="status" className="receipt">
          {message}
        </p>
      )}
      {uncertain && (
        <Notice error>
          Write result uncertain. Further writes are blocked; retained entries
          remain available.
          <button
            type="button"
            disabled={busy}
            onClick={() => void reconcile()}
          >
            Reload and reconcile
          </button>
          {reconciled && (
            <button
              type="button"
              onClick={() => {
                try {
                  sessionStorage.removeItem(pendingKey);
                } catch {
                  setError(
                    "Recovery marker could not be cleared; further writes remain blocked.",
                  );
                  return;
                }
                setUncertain(false);
                pendingOp.current = null;
                setEditing(null);
                setDirty(false);
                setView("Review & history");
                setMessage(
                  "Current server state loaded. No old command was replayed. Open a permitted current draft before recovering browser entries.",
                );
              }}
            >
              Continue from reviewed server state without replay
            </button>
          )}
        </Notice>
      )}
      {view === "Accepted summary" && loaded && (
        <>
          {accepted.length === 0 ? (
            <Empty title="No accepted statistics visible">
              Drafts and submitted proposals do not appear as reviewed results.
              A load failure is shown above, not treated as proof of empty data.
            </Empty>
          ) : (
            <>
              <p>
                {accepted.length} independently accepted datasets. Missing
                accepted datasets remain missing.
              </p>
              <ManualSummary
                manual={acceptedManual}
                players={acceptedPlayers}
                provenance="Server-accepted versions · missing datasets remain unavailable"
              />
            </>
          )}
        </>
      )}
      {view === "Draft entry" && (
        <>
          <label className="field">
            Dataset
            <select
              value={kind}
              disabled={dirty || busy}
              onChange={(e) => {
                const k = e.target.value as Kind;
                setKind(k);
                const v = paired.find((v) => v.dataset_type === k);
                setEditing(v ?? null);
              }}
            >
              {kinds.map((k) => (
                <option key={k} value={k}>
                  {KIND_LABEL[k]}
                </option>
              ))}
            </select>
          </label>
          {!editing ? (
            <>
              <p>
                Open your existing permitted draft. Completed/published versions
                require an authorized edit request; no new permission is
                inferred.
              </p>
              <button
                type="button"
                disabled={busy || uncertain || !access.can_propose_stats}
                onClick={() => void openWorking()}
              >
                Open my permitted draft
              </button>
              {versions
                .filter(
                  (v) =>
                    v.author_user_id === actor &&
                    v.dataset_type === kind &&
                    v.status === "draft",
                )
                .map((v) => (
                  <button
                    type="button"
                    key={v.id}
                    onClick={() => {
                      void openWorking(v.dataset_type);
                    }}
                  >
                    Continue saved draft · revision {v.revision}
                  </button>
                ))}
            </>
          ) : (
            <>
              <p className="badge">
                {editing.status} · server revision {editing.revision}
                {dirty ? " · unsaved browser entries" : ""}
              </p>
              {editing.status === "draft" ? (
                <>
                  <fieldset
                    disabled={busy || uncertain}
                    className="entry-fields"
                  >
                    <ManualEntry
                      only={
                        kind === "box_scores"
                          ? "Box scores"
                          : kind === "player_paint_touches"
                            ? "Paint touches"
                            : "Possessions"
                      }
                      manual={manual}
                      players={players}
                      onChange={buffer}
                      disabledTeams={paired
                        .filter((v) => v.status !== "draft")
                        .map((v) =>
                          v.dataset_type === "our_possessions"
                            ? "ours"
                            : "opponent",
                        )}
                    />
                  </fieldset>
                  <div className="shared-save">
                    <button
                      type="button"
                      className="primary"
                      disabled={!dirty || busy || uncertain}
                      onClick={saveWorking}
                    >
                      Save server draft
                    </button>
                    <button
                      type="button"
                      onClick={() =>
                        download(
                          "teamstats-shared-unsaved-draft.json",
                          JSON.stringify(
                            {
                              actor,
                              game: game.id,
                              team: game.team_id,
                              version: editing,
                              manual,
                            },
                            null,
                            2,
                          ),
                        )
                      }
                    >
                      Download unsaved recovery copy
                    </button>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        try {
                          const raw = sessionStorage.getItem(recoveryKey);
                          if (!raw)
                            throw Error(
                              "No retained browser buffer for this account and game.",
                            );
                          const b = JSON.parse(raw);
                          if (
                            b.actor !== actor ||
                            b.team !== game.team_id ||
                            b.game !== game.id ||
                            b.version?.id !== editing.id
                          )
                            throw Error(
                              "Retained buffer belongs to a different version; no values were imported.",
                            );
                          encodeRecords(b.manual, kind, game.id, players);
                          buffer(b.manual);
                          setMessage(
                            "Retained browser entries loaded. Not saved or server-confirmed.",
                          );
                        } catch (e) {
                          setError((e as Error).message);
                        }
                      }}
                    >
                      Recover this account’s retained entries
                    </button>
                  </div>
                  <details>
                    <summary>Complete this independent dataset</summary>
                    <p>
                      Save first. Completion freezes entry; it is not submission
                      or publication. Scoring contradictions block completion,
                      not draft saving.
                    </p>
                    {kind === "box_scores" ||
                    kind === "player_paint_touches" ? (
                      <label className="checkbox">
                        <input
                          type="checkbox"
                          checked={confirmRoster}
                          onChange={(e) => setConfirmRoster(e.target.checked)}
                        />
                        I confirm this game and the covered real roster.
                      </label>
                    ) : (
                      <label className="checkbox">
                        <input
                          type="checkbox"
                          checked={confirmZeros}
                          onChange={(e) => setConfirmZeros(e.target.checked)}
                        />
                        Convert only existing numeric blanks to explicit zero on
                        completion. Every turnover must be answered.
                      </label>
                    )}
                    <button
                      type="button"
                      disabled={
                        dirty ||
                        busy ||
                        uncertain ||
                        !(kind === "box_scores" ||
                        kind === "player_paint_touches"
                          ? confirmRoster
                          : confirmZeros)
                      }
                      onClick={() =>
                        void mutate<Version>(
                          "stats_complete",
                          {
                            p_version_id: editing.id,
                            p_expected_revision: editing.revision,
                            p_confirm_roster: confirmRoster,
                            p_confirm_numeric_zeros: confirmZeros,
                            p_suppress_numeric_warning: false,
                          },
                          (v) => begin(v),
                        )
                      }
                    >
                      Complete {KIND_LABEL[kind].toLowerCase()}
                    </button>
                  </details>
                </>
              ) : (
                <Notice>
                  This version is frozen. Use Review & history to submit it or
                  request an authorized correction. No values were silently
                  reopened.
                </Notice>
              )}
            </>
          )}
        </>
      )}
      {view === "Review & history" && (
        <>
          {versions.length === 0 && <p>No versions visible to this account.</p>}
          <div className="version-list">
            {versions.map((v) => (
              <section key={v.id}>
                <div className="section-heading">
                  <h3>{KIND_LABEL[v.dataset_type]}</h3>
                  <span className="badge">
                    {v.status} · revision {v.revision}
                  </span>
                </div>
                <p>
                  {v.records.length} records ·{" "}
                  {v.base_published_version_id
                    ? "Correction lineage retained"
                    : "Original proposal"}
                </p>
                <div className="actions">
                  {v.author_user_id === actor && v.status === "draft" && (
                    <button
                      type="button"
                      onClick={() => void openWorking(v.dataset_type)}
                    >
                      Edit this draft
                    </button>
                  )}
                  {v.author_user_id === actor && v.status === "completed" && (
                    <button
                      type="button"
                      disabled={busy || uncertain}
                      onClick={() =>
                        void mutate("stats_submit", {
                          p_version_id: v.id,
                          p_expected_revision: v.revision,
                        })
                      }
                    >
                      Submit for review
                    </button>
                  )}
                  {v.status === "submitted" &&
                    (access.is_owner ||
                      access.capabilities.includes("stats.review")) &&
                    (access.is_owner || v.author_user_id !== actor) && (
                      <>
                        <button
                          type="button"
                          disabled={busy || uncertain}
                          onClick={() => {
                            if (
                              window.confirm(
                                "Accept and publish this exact submitted version? This creates a queued export job; it does not deliver to Google.",
                              )
                            )
                              void mutate("stats_review", {
                                p_version_id: v.id,
                                p_expected_revision: v.revision,
                                p_approve: true,
                                p_reason: "",
                              });
                          }}
                        >
                          Accept & publish
                        </button>
                        <button
                          type="button"
                          disabled={busy || uncertain}
                          onClick={() =>
                            void mutate("stats_review", {
                              p_version_id: v.id,
                              p_expected_revision: v.revision,
                              p_approve: false,
                              p_reason: "Rejected through reviewed web action",
                            })
                          }
                        >
                          Reject proposal
                        </button>
                      </>
                    )}
                  {v.author_user_id === actor &&
                    ["completed", "submitted"].includes(v.status) &&
                    (access.is_owner ||
                      access.capabilities.includes("stats.publish")) && (
                      <button
                        type="button"
                        disabled={busy || uncertain}
                        onClick={() => {
                          if (
                            window.confirm(
                              "Publish your exact saved version using server-confirmed bypass authority?",
                            )
                          )
                            void mutate("stats_publish", {
                              p_version_id: v.id,
                              p_expected_revision: v.revision,
                            });
                        }}
                      >
                        Publish with current authority
                      </button>
                    )}
                  {["published", "completed", "submitted", "rejected"].includes(
                    v.status,
                  ) && (
                    <button
                      type="button"
                      disabled={busy || uncertain}
                      onClick={() => {
                        const reason = window.prompt(
                          "Reason for requesting permission to edit this retained version:",
                        );
                        if (reason?.trim())
                          void mutate("stats_request_edit", {
                            p_source_version_id: v.id,
                            p_expected_revision: v.revision,
                            p_reason: reason.trim(),
                          });
                      }}
                    >
                      Request permission to edit
                    </button>
                  )}
                </div>
                <details>
                  <summary>Review saved values and correction context</summary>
                  {v.base_published_version_id ? (
                    (() => {
                      const base = versions.find(
                        (b) => b.id === v.base_published_version_id,
                      );
                      if (!base)
                        return (
                          <p>
                            Accepted base unavailable to this account. No
                            comparison is inferred.
                          </p>
                        );
                      const changes = recordChanges(base, v);
                      return (
                        <section>
                          <h4>Changes from accepted base</h4>
                          {changes.length === 0 ? (
                            <p>No saved field changes.</p>
                          ) : (
                            <Scroller label="Correction changes">
                              <table>
                                <thead>
                                  <tr>
                                    <th>Player / record</th>
                                    <th>Field</th>
                                    <th>Previous</th>
                                    <th>Proposed</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  {changes.map((c, i) => (
                                    <tr key={i}>
                                      <th scope="row">
                                        {rosterHistory.find(
                                          (p) =>
                                            p.id.toLowerCase() === c.record,
                                        )?.name ??
                                          "Possession " +
                                            String(
                                              [
                                                ...v.records,
                                                ...base.records,
                                              ].find(
                                                (r) =>
                                                  String(r.id).toLowerCase() ===
                                                  c.record,
                                              )?.number ?? "unavailable",
                                            )}
                                      </th>
                                      <td>{c.field}</td>
                                      <td>{c.previous}</td>
                                      <td>{c.proposed}</td>
                                    </tr>
                                  ))}
                                </tbody>
                              </table>
                            </Scroller>
                          )}
                        </section>
                      );
                    })()
                  ) : (
                    <p>Original proposal — no accepted base to compare.</p>
                  )}
                  <ManualSummary
                    manual={decodeManual([v], game.id)}
                    players={labelsFor(v)}
                    provenance={`${v.status} · server revision ${v.revision}`}
                  />
                  <details>
                    <summary>Technical record identifiers / raw JSON</summary>
                    <pre>{JSON.stringify(v.records, null, 2)}</pre>
                  </details>
                </details>
              </section>
            ))}
          </div>
          {requests.map((r) => (
            <section className="request-row" key={r.id}>
              <h3>Edit request · {r.status}</h3>
              <p>{r.reason}</p>
              {r.status === "pending" &&
                (access.is_owner ||
                  access.capabilities.includes("datasets.reopen")) &&
                (access.is_owner || r.requester_user_id !== actor) && (
                  <button
                    type="button"
                    disabled={busy || uncertain}
                    onClick={() => {
                      if (
                        window.confirm(
                          "Approve one new working revision while preserving published history?",
                        )
                      )
                        void mutate("stats_review_edit", {
                          p_request_id: r.id,
                          p_expected_revision: r.revision,
                          p_approve: true,
                          p_reason: "",
                        });
                    }}
                  >
                    Approve reopening
                  </button>
                )}
            </section>
          ))}
          <p className="muted">
            Publication can queue output work. Queued is not delivered. Google
            delivery and scheduling remain disabled.
          </p>
        </>
      )}
    </>
  );
}
