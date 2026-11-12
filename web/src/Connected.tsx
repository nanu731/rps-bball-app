import { WebSessions } from "./WebSessions.tsx";
import { useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import type { Manual, Player } from "./domain.ts";
import { id, entryError } from "./domain.ts";
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
  statusLabel,
} from "./ui.tsx";
import type { NavigationGuard } from "./ui.tsx";
const CONFIG = "teamstats-web-public-config";
const kinds = Object.keys(KIND_LABEL) as Kind[];
const capabilityLabel = (cap: string) =>
  ({
    "stats.review": "Review after-game stats",
    "stats.publish": "Publish own after-game stats",
    "datasets.reopen": "Allow stat corrections",
    "roster.manage": "Manage roster",
    "members.manage": "Manage members",
    "sessions.manage": "Plan sessions and assign recorders",
    "sessions.record": "Record assigned sessions",
    "sessions.clock": "Control assigned game clock",
    "sessions.review": "Review session entries",
    "sessions.publish": "Publish own session entries",
    "sessions.reopen": "Allow session corrections",
  })[cap] ?? "Unknown access";
export function Connected({
  navigationGuard,
}: {
  navigationGuard: NavigationGuard;
}) {
  const [url, setUrl] = useState(""),
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
      const saved = ["127.0.0.1", "localhost"].includes(location.hostname)
        ? localStorage.getItem(CONFIG)
        : null;
      const config = saved ? JSON.parse(saved) : null;
      const u = import.meta.env.VITE_SUPABASE_URL ?? config?.url ?? "",
        k = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? config?.key ?? "";
      setUrl(u);
      if (u && k) setClient(clientFor(u, k));
    } catch {
      setError(
        "The team connection could not be opened. Ask the team owner to check connection settings.",
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
      const local = await client.auth.getSession();
      if (local.error) throw new ServerError("session");
      if (!local.data.session) {
        actorRef.current = null;
        setUser(null);
        setTeams([]);
        setTeam("");
        server.epoch++;
        return;
      }
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
      setTeam((current) =>
        rows.some((t) => t.id === current)
          ? current
          : rows.length === 1
            ? rows[0].id
            : "",
      );
      setMessage("Signed in. Choose your team to continue.");
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
        setError(entryError(e));
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
  const auth = async (action: "send" | "verify" | "out" | "google") => {
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
            "Team entries are hidden, but sign-out could not be confirmed. Check your sign-in before continuing.",
          );
        setMessage("Signed out. Your device-only drafts are still here.");
      } else if (action === "google") {
        const { error } = await client.auth.signInWithOAuth({
          provider: "google",
          options: { redirectTo: location.origin },
        });
        if (error)
          throw Error(
            "Google sign-in could not start. Try again or ask the team owner.",
          );
      } else if (action === "send") {
        const { error } = await client.auth.signInWithOtp({
          email: email.trim(),
          options: {
            shouldCreateUser: true,
            emailRedirectTo: location.origin,
          },
        });
        if (error)
          throw Error(
            "The sign-in email could not be requested. Check your address or ask the team owner for help.",
          );
        setSent(true);
        setMessage(
          "Sign-in email requested. Check your inbox for the link or code.",
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
      setError(entryError(e));
    } finally {
      setPending(false);
    }
  };
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>{user ? "Team" : "Sign in to TeamStats"}</h1>
          {!team && (
            <p>
              Sign in to work with your team. Drafts saved only in this browser
              stay here.
            </p>
          )}
        </div>
        {client && !team && (
          <button
            type="button"
            disabled={pending}
            onClick={() => void verify(true)}
          >
            {pending ? "Checking…" : "Check sign-in"}
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
        <summary>Account and team{user ? " · verified" : ""}</summary>
        {team && client && (
          <button
            type="button"
            disabled={pending}
            onClick={() => void verify(true)}
          >
            Check sign-in
          </button>
        )}
        {message && (
          <p className="receipt" role="status">
            {message}
          </p>
        )}
        {!client ? (
          <Empty title="Team sign-in is not ready">
            Ask the team owner to finish connecting this test version. My drafts
            remains separate and available in this browser.
          </Empty>
        ) : !user ? (
          <section className="auth-form">
            <h2>Sign in or request team access</h2>
            {import.meta.env.VITE_GOOGLE_SIGN_IN_ENABLED === "true" && (
              <button
                type="button"
                disabled={pending}
                onClick={() => void auth("google")}
              >
                Continue with Google
              </button>
            )}
            {import.meta.env.VITE_EMAIL_SIGN_IN_ENABLED === "true" ? (
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
                      ? "Signing in…"
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
            ) : (
              <p>Email sign-in is not available on this test connection.</p>
            )}
            <p className="muted">
              Phone sign-in is unavailable. If your sign-in email does not
              arrive, ask the team owner to check email setup.
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
                Ask the team owner for your team code, then request to join.
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
              <summary>Join a team</summary>
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
                      data === "active"
                        ? "You have joined this team. Check your sign-in again to load it."
                        : "Request sent. A team administrator must approve it.",
                    );
                  } catch (e) {
                    setError(entryError(e));
                  } finally {
                    setPending(false);
                  }
                }}
              >
                <label className="field">
                  Team code from the owner
                  <input
                    required
                    value={join}
                    onChange={(e) => setJoin(e.target.value)}
                    pattern="[0-9a-fA-F-]{36}"
                  />
                </label>
                <button type="submit" disabled={pending}>
                  Request to join
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
        <summary>About this pilot</summary>
        <p>
          Team features depend on the connection set up by your owner. Drafts
          saved in this browser stay separate. Google Sheets, video delivery and
          scheduled exports are not active in this pilot.
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
    [section, setSection] = useState("After-game stats"),
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
    setError(
      "You no longer have access to this team. Check your sign-in or ask the team owner.",
    );
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
      setError(entryError(e));
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
      setError(entryError(e));
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
      setAdminReceipt("Team access updated.");
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
      setError(entryError(e));
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
          ? `This access is assigned${current.expires_at ? " with an expiry" : ""}.`
          : "This access is not assigned.";
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
          "This access change could not be checked. Keep your recovery information and ask for help.",
        );
      const after = await server.access(team.id);
      if (before.access_revision !== after.access_revision)
        throw Error("Team access changed while checking. Check again.");
      setAccess(after);
      setAdminReceipt(
        description +
          " The earlier change is still unconfirmed. Check this access before allowing another change.",
      );
      setAdminChecked(true);
    } catch (e) {
      if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code))
        conceal();
      setError(entryError(e));
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
          <summary>Team access</summary>

          <div className="actions">
            <button type="button" disabled={busy} onClick={() => void load()}>
              Check team access
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
                      setError(entryError(e));
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
      {busy && <p role="status">Loading your team…</p>}
      {access && (
        <p className="muted">
          {access.is_owner
            ? "Team owner · access verified"
            : access.can_propose_stats
              ? "Team member · can enter draft stats"
              : "Team member · can view published results"}{" "}
        </p>
      )}
      {manage && access && (
        <section className="create-form">
          <h3>Manage team</h3>
          <p>
            {members.length} members · {roster.length} active players. Access
            changes apply to this team.
          </p>
          {adminReceipt && (
            <p className="receipt" role="status">
              {adminReceipt}
            </p>
          )}
          <details>
            <summary>Member access · account codes</summary>
            <p>
              Use a member’s verified account code. Check it privately with that
              person before changing access.
            </p>
            {members
              .filter((m) => m.user_id !== actor)
              .map((m) => (
                <div className="observation" key={m.user_id}>
                  <div>
                    <strong>Account {m.user_id}</strong>
                    <small>{statusLabel(m.status)}</small>
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
                      .filter(
                        (m) => m.user_id !== actor && m.status === "active",
                      )
                      .map((m) => (
                        <option key={m.user_id} value={m.user_id}>
                          {m.user_id}
                        </option>
                      ))}
                  </select>
                </label>
                <label className="field">
                  Access to give or remove
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
                      <option key={cap} value={cap}>
                        {capabilityLabel(cap)}
                      </option>
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
                          `Allow “${capabilityLabel(adminCap)}” for this member?`,
                        )
                      )
                        void adminCommand("team_set_capability", {
                          p_user_id: adminTarget,
                          p_capability: adminCap,
                          p_enabled: true,
                        });
                    }}
                  >
                    Allow selected access
                  </button>
                  <button
                    type="button"
                    disabled={busy || adminLocked || !adminTarget}
                    onClick={() => {
                      if (
                        window.confirm(
                          `Remove “${capabilityLabel(adminCap)}” from this member?`,
                        )
                      )
                        void adminCommand("team_set_capability", {
                          p_user_id: adminTarget,
                          p_capability: adminCap,
                          p_enabled: false,
                        });
                    }}
                  >
                    Remove selected access
                  </button>
                </div>
                <p className="muted">
                  Recording access allows assignment to a practice or game. It
                  does not change who owns the team.
                </p>
              </>
            )}
          </details>
          {adminLocked && (
            <Notice error>
              This access change could not be confirmed. Check the current
              access before making another change.
              <div className="actions">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void reconcileAdmin()}
                >
                  Check current access
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
                          "Recovery could not finish. Check current access again before making another change.",
                        );
                      }
                    }}
                  >
                    I checked access; allow another change
                  </button>
                )}
              </div>
            </Notice>
          )}
        </section>
      )}
      {access && (
        <Tabs
          items={["After-game stats", "Practices & shots"]}
          value={section}
          onChange={(next) => {
            if (navigationGuard.current()) setSection(next);
          }}
          label="Shared team section"
        />
      )}
      {section === "Practices & shots" && access ? (
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
                <h3>Add team game</h3>
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
                  Create team game
                </button>
                {uncertain && (
                  <p>
                    We could not confirm whether the game was created. Reload
                    the game list before trying again.
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
              "A player’s saved roster details are unavailable. Names have not been replaced.",
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
            "Newer entries were saved elsewhere. Compare them with your unsaved entries before continuing.",
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
      setError(entryError(e));
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
        name === "stats_save_drafts" || name === "stats_save_draft"
          ? "Saved for your team. Not published yet."
          : name === "stats_complete"
            ? "Entry complete. Send it for review when ready."
            : name === "stats_submit"
              ? "Waiting for review."
              : name === "stats_publish" ||
                  (name === "stats_review" && args.p_approve === true)
                ? "Published to team."
                : name === "stats_review"
                  ? "Not approved. Saved entries are kept in history."
                  : name === "stats_request_edit"
                    ? "Correction request sent."
                    : name === "stats_review_edit"
                      ? "Correction approved. The requester can now edit."
                      : "Your change was saved.",
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
      setError(entryError(e));
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
          "A player’s saved roster details are unavailable. Names have not been replaced.",
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
      setError(entryError(e));
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
        "This browser could not back up your unsaved entries. Keep this tab open and download them before leaving.",
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
        setMessage("The expected change was saved. It was not sent again.");
      } else
        setMessage(
          "We still cannot confirm this change. Your unsaved entries are kept here. Check Review & history before continuing.",
        );
    } catch (e) {
      if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code))
        onDenied();
      setError(entryError(e));
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
      setError(entryError(e));
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
      setError(entryError(e));
    }
  };
  return (
    <>
      <div className="session-banner">
        <div>
          <h2>{game.opponent}</h2>
          <p>
            {game.date} · {game.home_away === "home" ? "Home" : "Away"} · Team
            game
          </p>
        </div>
        <span>
          Separate stat sheets
          <br />
          Only published stats appear in team results
        </span>
      </div>
      <Tabs
        items={["Accepted summary", "Draft entry", "Review & history"]}
        value={view}
        onChange={setView}
        label="Shared game section"
      />
      {busy && <p role="status">Loading team stats…</p>}
      {error && (
        <Notice error>
          {error}
          <button type="button" disabled={busy} onClick={() => void load()}>
            Reload saved stats
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
          We could not confirm whether this saved. Keep this tab open. Check
          before saving again.
          <button
            type="button"
            disabled={busy}
            onClick={() => void reconcile()}
          >
            Check save status
          </button>
          {reconciled && (
            <button
              type="button"
              onClick={() => {
                try {
                  sessionStorage.removeItem(pendingKey);
                } catch {
                  setError(
                    "Recovery could not finish. Keep your backup and check save status again before editing.",
                  );
                  return;
                }
                setUncertain(false);
                pendingOp.current = null;
                setEditing(null);
                setDirty(false);
                setView("Review & history");
                setMessage(
                  "Latest saved stats loaded. Nothing was sent again. Open your draft to recover unsaved entries.",
                );
              }}
            >
              Continue from latest saved stats
            </button>
          )}
        </Notice>
      )}
      {view === "Accepted summary" && loaded && (
        <>
          {accepted.length === 0 ? (
            <Empty title="No published stats yet">
              Drafts and stats waiting for review are not team results yet.
            </Empty>
          ) : (
            <>
              <p>
                {accepted.length} published stat sheets. Sheets not yet
                published are not included.
              </p>
              <ManualSummary
                manual={acceptedManual}
                players={acceptedPlayers}
                provenance="Published to team · missing sheets not included"
              />
            </>
          )}
        </>
      )}
      {view === "Draft entry" && (
        <>
          <label className="field">
            Stat sheet
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
                Open your draft to enter stats. Finished entries are locked;
                request a correction from Review & history.
              </p>
              <button
                type="button"
                disabled={busy || uncertain || !access.can_propose_stats}
                onClick={() => void openWorking()}
              >
                Open my draft
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
                    Continue saved draft
                  </button>
                ))}
            </>
          ) : (
            <>
              <p className="badge">
                {statusLabel(editing.status)}
                {dirty ? " · unsaved changes" : ""}
              </p>
              {editing.status === "draft" ? (
                <>
                  <fieldset
                    disabled={busy || uncertain}
                    className="entry-fields"
                  >
                    <ManualEntry
                      shared
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
                      Save team draft
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
                      Download unsaved entries
                    </button>
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        try {
                          const raw = sessionStorage.getItem(recoveryKey);
                          if (!raw)
                            throw Error(
                              "No unsaved entries were found for this account and game.",
                            );
                          const b = JSON.parse(raw);
                          if (
                            b.actor !== actor ||
                            b.team !== game.team_id ||
                            b.game !== game.id ||
                            b.version?.id !== editing.id
                          )
                            throw Error(
                              "These unsaved entries belong to a different draft. Nothing was imported.",
                            );
                          encodeRecords(b.manual, kind, game.id, players);
                          buffer(b.manual);
                          setMessage(
                            "Unsaved entries restored. Save them to your team when ready.",
                          );
                        } catch (e) {
                          setError(entryError(e));
                        }
                      }}
                    >
                      Restore my unsaved entries
                    </button>
                  </div>
                  <details>
                    <summary>Finish this stat sheet</summary>
                    <p>
                      Save first. Finishing locks this sheet until a correction
                      is approved. You can then send it for review. Check
                      scoring differences before finishing; drafts can still be
                      saved.
                    </p>
                    {kind === "box_scores" ||
                    kind === "player_paint_touches" ? (
                      <label className="checkbox">
                        <input
                          type="checkbox"
                          checked={confirmRoster}
                          onChange={(e) => setConfirmRoster(e.target.checked)}
                        />
                        I checked the game and the players included.
                      </label>
                    ) : (
                      <label className="checkbox">
                        <input
                          type="checkbox"
                          checked={confirmZeros}
                          onChange={(e) => setConfirmZeros(e.target.checked)}
                        />
                        Blank counts in rows I added will be saved as 0. Every
                        turnover still needs Yes or No.
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
                  These entries are locked. Use Review & history to send them
                  for review or request a correction.
                </Notice>
              )}
            </>
          )}
        </>
      )}
      {view === "Review & history" && (
        <>
          {versions.length === 0 && (
            <p>No saved stat sheets are available to you.</p>
          )}
          <div className="version-list">
            {versions.map((v) => (
              <section key={v.id}>
                <div className="section-heading">
                  <h3>{KIND_LABEL[v.dataset_type]}</h3>
                  <span className="badge">{statusLabel(v.status)}</span>
                </div>
                <p>
                  {v.records.length} records ·{" "}
                  {v.base_published_version_id
                    ? "Correction · earlier results kept"
                    : "First submission"}
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
                      Send for review
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
                                "Approve these saved stats and publish them to the team? Earlier published results will be kept.",
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
                          Approve & publish
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
                          Do not approve
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
                              "Your access lets you publish without another reviewer. Publish these saved stats to the team?",
                            )
                          )
                            void mutate("stats_publish", {
                              p_version_id: v.id,
                              p_expected_revision: v.revision,
                            });
                        }}
                      >
                        Publish my saved stats
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
                          "Why do these entries need a correction?",
                        );
                        if (reason?.trim())
                          void mutate("stats_request_edit", {
                            p_source_version_id: v.id,
                            p_expected_revision: v.revision,
                            p_reason: reason.trim(),
                          });
                      }}
                    >
                      Request a correction
                    </button>
                  )}
                </div>
                <details>
                  <summary>View saved stats and changes</summary>
                  {v.base_published_version_id ? (
                    (() => {
                      const base = versions.find(
                        (b) => b.id === v.base_published_version_id,
                      );
                      if (!base)
                        return (
                          <p>
                            The earlier published stats are not available to
                            you, so changes cannot be compared.
                          </p>
                        );
                      const changes = recordChanges(base, v);
                      return (
                        <section>
                          <h4>Changes from published stats</h4>
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
                    <p>
                      First submission — no earlier published stats to compare.
                    </p>
                  )}
                  <ManualSummary
                    manual={decodeManual([v], game.id)}
                    players={labelsFor(v)}
                    provenance={statusLabel(v.status)}
                  />
                  <details>
                    <summary>Technical details</summary>
                    <pre>{JSON.stringify(v.records, null, 2)}</pre>
                  </details>
                </details>
              </section>
            ))}
          </div>
          {requests.map((r) => (
            <section className="request-row" key={r.id}>
              <h3>Correction request · {statusLabel(r.status)}</h3>
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
                          "Allow a new correction draft? Published history will be kept.",
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
                    Allow correction
                  </button>
                )}
            </section>
          ))}
          <p className="muted">
            Google Sheets delivery is not active. Published stats are available
            to your team in TeamStats.
          </p>
        </>
      )}
    </>
  );
}
