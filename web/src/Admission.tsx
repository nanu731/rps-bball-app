import { useEffect, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { applicantDetails, CoreServer, type SignupStatus } from "./server.ts";
import { entryError } from "./domain.ts";
import { Empty, Notice, Tabs } from "./ui.tsx";
import { CourtDiagram } from "./Capture.tsx";
export type ApplicantDraft = {
  first_name: string;
  last_name: string;
  requested_role: string;
};
export function ApplicantFields({
  value,
  onChange,
}: {
  value: ApplicantDraft;
  onChange: (value: ApplicantDraft) => void;
}) {
  return (
    <>
      <div className="field-grid">
        <label className="field">
          First name
          <input
            autoComplete="given-name"
            required
            maxLength={80}
            value={value.first_name}
            onChange={(e) => onChange({ ...value, first_name: e.target.value })}
          />
        </label>
        <label className="field">
          Last name
          <input
            autoComplete="family-name"
            required
            maxLength={80}
            value={value.last_name}
            onChange={(e) => onChange({ ...value, last_name: e.target.value })}
          />
        </label>
      </div>
      <label className="field">
        Requested role
        <select
          required
          value={value.requested_role}
          onChange={(e) =>
            onChange({ ...value, requested_role: e.target.value })
          }
        >
          <option value="">Choose a role</option>
          <option value="player">Player</option>
          <option value="coach">Coach</option>
          <option value="manager">Manager</option>
        </select>
      </label>
      <p className="muted">
        The owner confirms or changes this role before granting team access.
        Coaches and managers have the same plan and statistics tools.
      </p>
    </>
  );
}
const ownDetails = (user: User): ApplicantDraft => ({
  first_name:
    typeof user.user_metadata.first_name === "string"
      ? user.user_metadata.first_name
      : "",
  last_name:
    typeof user.user_metadata.last_name === "string"
      ? user.user_metadata.last_name
      : "",
  requested_role:
    typeof user.user_metadata.requested_role === "string"
      ? user.user_metadata.requested_role
      : "",
});
export function PendingAccess({
  server,
  user,
  initial,
  onApproved,
}: {
  server: CoreServer;
  user: User;
  initial: SignupStatus;
  onApproved: () => void;
}) {
  const [status, setStatus] = useState(initial),
    [details, setDetails] = useState(() => ownDetails(user)),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [preview, setPreview] = useState("Results preview");
  const active = useRef(true),
    gate = useRef(false);
  const check = async (submit = false) => {
    if (gate.current) return;
    gate.current = true;
    setBusy(true);
    setError("");
    try {
      let next = await server.admission();
      if (submit && !next.has_access && !next.request && next.configured) {
        next = await server.admission(
          applicantDetails(
            details.first_name,
            details.last_name,
            details.requested_role,
          ),
        );
        if (active.current) setStatus(next);
        if (next.request?.status === "pending") {
          try {
            await server.notifyAccess(next.request.id);
          } catch {
            if (active.current)
              setError(
                "Your access request is saved. Email notification could not be confirmed; the owner can still review it.",
              );
          }
          next = await server.admission();
        }
      }
      if (!active.current) return;
      setStatus(next);
      if (next.has_access) onApproved();
    } catch (e) {
      if (active.current) setError(entryError(e));
    } finally {
      gate.current = false;
      if (active.current) setBusy(false);
    }
  };
  const notify = async () => {
    if (gate.current || !status.request) return;
    gate.current = true;
    setBusy(true);
    setError("");
    try {
      await server.notifyAccess(status.request.id);
      const next = await server.admission();
      if (active.current) setStatus(next);
    } catch {
      if (active.current)
        setError(
          "Notification could not be confirmed. Your request remains saved. Check approval status before retrying; an uncertain email needs owner review.",
        );
    } finally {
      gate.current = false;
      if (active.current) setBusy(false);
    }
  };
  useEffect(() => {
    active.current = true;
    // This one replay-safe request is bound to a verified Auth UUID; the server creates it once.
    if (user.email_confirmed_at && initial.configured && !initial.request) {
      try {
        applicantDetails(
          details.first_name,
          details.last_name,
          details.requested_role,
        );
        void check(true);
      } catch {
        /* Older verified accounts provide the missing fields below. */
      }
    }
    return () => {
      active.current = false;
    };
  }, [user.id]);
  const request = status.request;
  return (
    <section className="pending-access">
      <div className="section-heading">
        <h2>
          {request?.status === "pending"
            ? "Awaiting owner approval"
            : request?.status === "declined"
              ? "Access request declined"
              : request
                ? "Team access needs the owner’s attention"
                : "Request team access"}
        </h2>
        <button type="button" disabled={busy} onClick={() => void check()}>
          Check approval status
        </button>
      </div>
      <p>
        {user.email_confirmed_at
          ? "Your email is verified."
          : "Verify an email address before requesting team access."}{" "}
        Team permission is a separate decision by the owner.
      </p>
      {error && <Notice error>{error}</Notice>}
      {busy && <p role="status">Checking your access request…</p>}
      {request ? (
        <Notice>
          <strong>
            {request.first_name} {request.last_name}
          </strong>{" "}
          · Requested {request.requested_role}.
          <p>
            {request.status === "pending"
              ? "Your request is saved. The owner must verify your identity and confirm your role."
              : request.status === "declined"
                ? "The owner declined this access request. No team access was granted. Contact the owner about the decision; submitting another role does not change it."
                : "Your current server-confirmed access does not open the team. Contact the owner; submitting a different role will not restore access."}
          </p>
          {request.status === "pending" &&
            !["sent", "sending", "manual_review"].includes(
              request.notification ?? "",
            ) && (
              <button
                type="button"
                disabled={busy}
                onClick={() => void notify()}
              >
                Retry owner notification
              </button>
            )}
          <p>
            {request.notification === "sent"
              ? "Notification accepted by the email server; inbox delivery is not confirmed here."
              : request.notification_error === "disabled" ||
                  request.notification_error === "configuration"
                ? "Email notification is unavailable. The owner can still review your saved request."
                : "Email notification has not been confirmed. Your saved request remains available for owner review."}
          </p>
        </Notice>
      ) : status.configured ? (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            void check(true);
          }}
        >
          <fieldset
            className="entry-fields"
            disabled={busy || !user.email_confirmed_at}
          >
            <ApplicantFields value={details} onChange={setDetails} />
            <button type="submit" className="primary">
              Send access request
            </button>
          </fieldset>
        </form>
      ) : (
        <Empty title="Owner approval setup is not ready">
          Your verified account is retained. Ask the owner to finish configuring
          access requests, then check again.
        </Empty>
      )}
      <section
        className="admission-preview"
        aria-label="Data-free TeamStats preview"
      >
        <h3>Preview — no team data</h3>
        <p>
          Explore the layout while you wait. These empty templates do not load
          team records.
        </p>
        <Tabs
          items={["Results preview", "Practice preview"]}
          value={preview}
          onChange={setPreview}
          label="Welcome preview"
        />
        {preview === "Results preview" ? (
          <>
            <h4>Player and team results</h4>
            <p>
              After approval, view published game and season box scores,
              independent paint-touch totals and shot charts for yourself and
              teammates.
            </p>
            <div className="preview-ledger">
              <strong>Statistic</strong>
              <strong>Published value</strong>
              {["Points", "Rebounds", "Paint touches"].map((name) => (
                <div key={name}>
                  <span>{name}</span>
                  <span>Available after approval</span>
                </div>
              ))}
            </div>
            <figure>
              <CourtDiagram events={[]} team="ours" />
              <figcaption>
                Empty shot-chart template. No attempts or player records are
                shown.
              </figcaption>
            </figure>
          </>
        ) : (
          <>
            <h4>Shared practice plan</h4>
            <p>
              Read shared builder plans and PDFs before practice. Published
              shooting and free-throw results stay separate from the plan.
            </p>
            <Empty title="Practice-plan template">
              The shared drill name, duration and coach instructions appear here
              after approval. This preview has no practice records.
            </Empty>
          </>
        )}
        <h4>Requested staff tools</h4>
        <p>
          {details.requested_role === "player" ||
          request?.requested_role === "player"
            ? "Players view published results and shared plans. Recording and review controls are reserved for authorized staff."
            : "If the owner confirms Coach or Manager, both roles can create/edit builder plans, upload PDFs, record/correct statistics and verify their own entries. Server-confirmed permissions and recorder assignments still apply."}
        </p>
      </section>
    </section>
  );
}

type ApplicantReview = NonNullable<SignupStatus["request"]> & {
  user_id: string;
  verified_email: string;
  current_verified_email: string | null;
  notification_attempts: number;
  created_at: string;
};
export function OwnerApplications({
  server,
  team,
  revision,
  locked,
  onReview,
  onRetry,
  onDenied,
  onKnown,
}: {
  server: CoreServer;
  team: string;
  revision: number;
  locked: boolean;
  onReview: (args: Record<string, unknown>) => Promise<void>;
  onRetry: (args: Record<string, unknown>) => Promise<boolean>;
  onDenied: () => void;
  onKnown: (users: string[]) => void;
}) {
  const [rows, setRows] = useState<ApplicantReview[]>([]),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [roles, setRoles] = useState<Record<string, string>>({}),
    [confirmed, setConfirmed] = useState<Record<string, boolean>>({}),
    [acknowledged, setAcknowledged] = useState<Record<string, boolean>>({}),
    [noticeMessage, setNoticeMessage] = useState("");
  const active = useRef(true),
    generation = useRef(0),
    section = useRef<HTMLElement>(null);
  useEffect(() => {
    if (location.hash === "#access-requests") {
      section.current?.focus({ preventScroll: true });
      section.current?.scrollIntoView({ behavior: "instant", block: "start" });
    }
  }, []);
  const load = async () => {
    const n = ++generation.current,
      epoch = server.epoch;
    setBusy(true);
    setError("");
    try {
      const data = await server.command<ApplicantReview[]>(
        team,
        "web_list_join_requests",
        {},
      );
      if (!active.current || n !== generation.current || epoch !== server.epoch)
        return;
      if (
        !Array.isArray(data) ||
        data.some(
          (r) => !r.id || !r.user_id || !Number.isSafeInteger(r.revision),
        )
      )
        throw Error(
          "Applicant requests could not be read. Retry before approving anyone.",
        );
      setRows(data);
      onKnown(data.filter((r) => r.status === "pending").map((r) => r.user_id));
    } catch (e) {
      if (active.current && n === generation.current) {
        setError(entryError(e));
        if (
          e instanceof Error &&
          "code" in e &&
          ["401", "403", "42501"].includes(String(e.code))
        ) {
          setRows([]);
          onDenied();
        }
      }
    } finally {
      if (active.current && n === generation.current) setBusy(false);
    }
  };
  useEffect(() => {
    active.current = true;
    void load();
    return () => {
      active.current = false;
      generation.current++;
    };
  }, [team, revision]);
  const review = async (row: ApplicantReview, approve: boolean) => {
    if (busy || locked) return;
    setBusy(true);
    setError("");
    try {
      await onReview({
        p_request_id: row.id,
        p_expected_revision: row.revision,
        p_confirm_identity: !!confirmed[row.id],
        p_role: roles[row.id] ?? row.requested_role,
        p_approve: approve,
      });
      if (active.current) await load();
    } catch (e) {
      if (active.current) setError(entryError(e));
    } finally {
      if (active.current) setBusy(false);
    }
  };
  const notify = async (row: ApplicantReview, retry = false) => {
    if (busy || locked) return;
    setBusy(true);
    setError("");
    setNoticeMessage("");
    try {
      if (
        retry &&
        !(await onRetry({
          p_request_id: row.id,
          p_expected_revision: row.revision,
          p_acknowledge_possible_duplicate: !!acknowledged[row.id],
        }))
      )
        return;
      const state = await server.notifyAccess(row.id);
      if (active.current)
        setNoticeMessage(
          state === "sent"
            ? "Notification accepted by the mail server; inbox delivery is unverified."
            : state === "retry_wait"
              ? "The saved retry deadline has not arrived. Check later."
              : "Notification status: " +
                state +
                ". The saved request can still be reviewed.",
        );
    } catch (e) {
      if (active.current)
        setError(
          "Email notification could not be confirmed. Refresh signup requests before retrying. The request remains available for review.",
        );
    } finally {
      if (active.current) {
        await load();
        setBusy(false);
      }
    }
  };
  return (
    <section
      ref={section}
      tabIndex={-1}
      id="access-requests"
      aria-label="Owner access requests"
    >
      <div className="section-heading">
        <h3>Verified signup requests</h3>
        <button type="button" disabled={busy} onClick={() => void load()}>
          Refresh signup requests
        </button>
      </div>
      <p>
        Names and requested roles are supplied by applicants. Verify each person
        privately using their verified account contact, then confirm or change
        the role. Email links never approve access.
      </p>
      {error && <Notice error>{error}</Notice>}
      {noticeMessage && <p role="status">{noticeMessage}</p>}
      {busy && <p role="status">Loading signup requests…</p>}
      {!busy && !error && !rows.length && (
        <Empty title="No signup requests">
          Verified requests appear here even when email notification is
          unavailable.
        </Empty>
      )}
      {rows.map((row) => (
        <article className="create-form" key={row.id}>
          <h4>
            {row.first_name} {row.last_name}
          </h4>
          <p>
            Requested {row.requested_role} · {row.status}. Email verified when
            requested: {row.verified_email}.
          </p>
          {row.current_verified_email !== row.verified_email && (
            <p>
              Current verified contact:{" "}
              {row.current_verified_email ?? "No verified email available"}.
              Check the identity change before approval.
            </p>
          )}
          <p>
            {row.notification === "sent"
              ? "Notification accepted by the mail server; inbox receipt unverified."
              : row.notification_error
                ? `Notification unavailable (${row.notification_error}). The request is still saved.`
                : "Email notification pending or unconfirmed. Review does not depend on email."}
          </p>
          {row.status === "pending" ? (
            <fieldset className="entry-fields" disabled={busy || locked}>
              {row.notification !== "sent" && (
                <div>
                  {row.notification_error === "uncertain" && (
                    <label className="check">
                      <input
                        type="checkbox"
                        checked={!!acknowledged[row.id]}
                        onChange={(e) =>
                          setAcknowledged({
                            ...acknowledged,
                            [row.id]: e.target.checked,
                          })
                        }
                      />
                      A prior email may have arrived. I accept that retrying
                      could send a duplicate notification.
                    </label>
                  )}
                  <button
                    type="button"
                    disabled={
                      row.notification_error === "uncertain" &&
                      !acknowledged[row.id]
                    }
                    onClick={() =>
                      void notify(row, row.notification === "manual_review")
                    }
                  >
                    {row.notification === "manual_review"
                      ? "Allow notification retry"
                      : "Check/send owner notification"}
                  </button>
                </div>
              )}
              <label className="field">
                Role for {row.first_name} {row.last_name}
                <select
                  value={roles[row.id] ?? row.requested_role}
                  onChange={(e) => {
                    setRoles({ ...roles, [row.id]: e.target.value });
                    setConfirmed({ ...confirmed, [row.id]: false });
                  }}
                >
                  <option value="player">Player — view only</option>
                  <option value="coach">Coach</option>
                  <option value="manager">Manager</option>
                </select>
              </label>
              <p>
                Coaches and managers receive the same plan/statistics
                permissions. Player access is read-only. Owner authority is
                unchanged.
              </p>
              <label className="check">
                <input
                  type="checkbox"
                  checked={!!confirmed[row.id]}
                  onChange={(e) =>
                    setConfirmed({ ...confirmed, [row.id]: e.target.checked })
                  }
                />
                I verified this applicant’s identity and the selected role.
              </label>
              <div className="actions">
                <button
                  type="button"
                  className="primary"
                  disabled={!confirmed[row.id] || !row.current_verified_email}
                  onClick={() => void review(row, true)}
                >
                  Approve selected role
                </button>
                <button type="button" onClick={() => void review(row, false)}>
                  Decline request
                </button>
              </div>
            </fieldset>
          ) : (
            <p>
              {row.confirmed_role
                ? `Confirmed role: ${row.confirmed_role}. Current permissions remain server-controlled.`
                : "Request declined. No team permission was granted."}
            </p>
          )}
        </article>
      ))}
    </section>
  );
}
