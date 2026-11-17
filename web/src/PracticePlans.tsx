import { useEffect, useRef, useState } from "react";
import { CoreServer, ServerError, readFileResponse } from "./server.ts";
import { entryError, id } from "./domain.ts";
import type { PlanItem } from "./domain.ts";
import { Empty, Notice } from "./ui.tsx";
type SharedPlan = {
  id: string;
  revision: number;
  kind: "builder" | "pdf";
  pdf_version_id: string | null;
  builder: {
    title: string;
    date: string;
    protocol: string;
    spots: string[];
    plan: PlanItem[];
  } | null;
  shared_at: string;
  is_current: boolean;
  operation_id?: string | null;
};
type Upload = {
  operation: string;
  resource: string;
  bytes: number;
  title: string;
  base: string | null;
  version?: string;
};
type Share = { operation: string; revision: number; pdf: string | null };
type FileVersion = {
  id: string;
  revision: number;
  resource_id: string;
  status: string;
  sha256: string | null;
  byte_count: number | null;
};
export function PracticePlans({
  server,
  team,
  actor,
  practice,
  revision,
  editable,
  dirty,
  onDenied,
}: {
  server: CoreServer;
  team: string;
  actor: string;
  practice: string;
  revision: number;
  editable: boolean;
  dirty: boolean;
  onDenied: () => void;
}) {
  const key = `teamstats-plan:${encodeURIComponent(server.namespace)}:${team}:${actor}:${practice}`;
  const [fileDrafts, setFileDrafts] = useState<
      (FileVersion & { title: string })[]
    >([]),
    [plans, setPlans] = useState<SharedPlan[]>([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [loaded, setLoaded] = useState(false),
    [file, setFile] = useState<File | null>(null),
    [title, setTitle] = useState(""),
    [upload, setUpload] = useState<Upload | null>(null),
    [share, setShare] = useState<Share | null>(null),
    [ready, setReady] = useState<FileVersion | null>(null),
    [preview, setPreview] = useState("");
  const active = useRef(true),
    gate = useRef(false),
    transfer = useRef<AbortController | null>(null),
    previewRef = useRef("");
  const fail = (e: unknown) => {
    if (e instanceof ServerError && ["401", "403", "42501"].includes(e.code)) {
      setPlans([]);
      if (previewRef.current) URL.revokeObjectURL(previewRef.current);
      setPreview("");
      onDenied();
    }
    setError(entryError(e));
  };
  const remember = (name: "upload" | "share", value: Upload | Share | null) => {
    if (value) sessionStorage.setItem(key + ":" + name, JSON.stringify(value));
    else sessionStorage.removeItem(key + ":" + name);
    if (name === "upload") setUpload(value as Upload | null);
    else setShare(value as Share | null);
  };
  const load = async () => {
    const epoch = server.epoch;
    try {
      const list = await server.command<SharedPlan[]>(team, "web_plan_list", {
        p_practice_id: practice,
      });
      if (!active.current || epoch !== server.epoch) return;
      if (
        !Array.isArray(list) ||
        list.some(
          (p) =>
            !p.id ||
            !Number.isSafeInteger(p.revision) ||
            !["builder", "pdf"].includes(p.kind),
        )
      )
        throw Error("Shared plans could not be read. Retry before using them.");
      setPlans(list);
      setLoaded(true);
      if (editable) {
        const resources = await server.rows<{ id: string }>(
          "file_resources",
          "id",
          { team_id: team, practice_id: practice, kind: "practice_plan" },
        );
        const versions = resources.length
          ? await server.rows<FileVersion & { title: string }>(
              "file_resource_versions",
              "id,revision,resource_id,status,sha256,byte_count,title",
              {
                team_id: team,
                resource_id: resources[0].id,
                author_user_id: actor,
                status: "ready",
              },
            )
          : [];
        if (active.current && epoch === server.epoch) setFileDrafts(versions);
      }
      if (share && list.some((p) => p.operation_id === share.operation)) {
        remember("share", null);
        setError("");
      }
    } catch (e) {
      if (active.current && epoch === server.epoch) fail(e);
    }
  };
  useEffect(() => {
    active.current = true;
    try {
      const u = sessionStorage.getItem(key + ":upload"),
        s = sessionStorage.getItem(key + ":share");
      if (u) {
        const value = JSON.parse(u);
        if (
          !value.operation ||
          !value.resource ||
          !Number.isSafeInteger(value.bytes) ||
          value.bytes < 1 ||
          value.bytes > 5 * 1024 * 1024
        )
          throw Error(
            "Unreadable upload recovery details. Keep this tab and the original PDF, then ask the team owner for help.",
          );
        setUpload(value);
      }
      if (s) {
        const value = JSON.parse(s);
        if (!value.operation || !Number.isSafeInteger(value.revision))
          throw Error(
            "Unreadable plan-sharing recovery details. Keep this tab and ask for help.",
          );
        setShare(value);
      }
    } catch (e) {
      fail(e);
    }
    void load();
    return () => {
      active.current = false;
      transfer.current?.abort();
      if (previewRef.current) URL.revokeObjectURL(previewRef.current);
    };
  }, [key]);
  useEffect(() => {
    void load();
  }, [revision]);
  const gateway = () => {
    let configured = import.meta.env.VITE_FILES_GATEWAY ?? "";
    if (!configured && ["localhost", "127.0.0.1"].includes(location.hostname)) {
      try {
        configured =
          JSON.parse(
            localStorage.getItem("teamstats-web-public-config") ?? "{}",
          ).filesGateway ?? "";
      } catch {
        /* No alternate endpoint on invalid configuration. */
      }
    }
    const target = new URL(
      configured || server.namespace + "/functions/v1/teamstats-files",
    );
    if (
      target.username ||
      target.password ||
      target.search ||
      target.hash ||
      !(
        target.origin === new URL(server.namespace).origin ||
        (["localhost", "127.0.0.1"].includes(location.hostname) &&
          target.protocol === "http:" &&
          target.hostname === "127.0.0.1")
      )
    )
      throw Error(
        "Private PDF delivery is not configured for this team. The plan builder remains available.",
      );
    return target.href.replace(/\/$/, "");
  };
  const request = async (path: string, body?: File | null) => {
    const epoch = server.epoch;
    const user = await server.identity();
    if (user.id !== actor) throw new ServerError("401");
    const session = await server.client.auth.getSession();
    if (
      session.error ||
      session.data.session?.user.id !== actor ||
      epoch !== server.epoch
    )
      throw new ServerError("401");
    const controller = new AbortController();
    transfer.current = controller;
    const deadline = setTimeout(() => controller.abort(), 90000);
    try {
      const response = await fetch(gateway() + path, {
        method: body === undefined ? "GET" : "POST",
        headers: {
          Authorization: "Bearer " + session.data.session!.access_token,
          ...(body ? { "Content-Type": "application/pdf" } : {}),
        },
        body: body || undefined,
        signal: controller.signal,
        redirect: "error",
      });
      const bytes = await readFileResponse(
        response,
        body === undefined && response.ok ? 5 * 1024 * 1024 : 16384,
        controller.signal,
      );
      if (!active.current || epoch !== server.epoch)
        throw new ServerError("401");
      if (!response.ok) {
        if ([401, 403].includes(response.status))
          throw new ServerError(String(response.status));
        let code = "";
        try {
          code = JSON.parse(new TextDecoder().decode(bytes)).error ?? "";
        } catch {
          /* Never render a raw service body. */
        }
        if (code === "upload_not_stored_start_new_operation") {
          // The worker confirmed absence; retain its reservation/history, release only this browser marker.
          remember("upload", null);
          throw Error(
            "This upload is confirmed absent. Keep the original PDF and start a new upload.",
          );
        }
        throw Error(
          response.status === 429
            ? "Too many file requests. Wait before checking this upload again."
            : "The private file service could not finish. Keep the original PDF and check upload status before trying another upload.",
        );
      }
      return { response, bytes };
    } catch (e) {
      if (e instanceof TypeError)
        throw Error(
          "The private file service could not finish. Keep the original PDF and check upload status before trying another upload.",
        );
      throw e;
    } finally {
      clearTimeout(deadline);
      if (transfer.current === controller) transfer.current = null;
    }
  };
  const run = async (action: () => Promise<void>) => {
    if (gate.current) return;
    gate.current = true;
    setBusy(true);
    setError("");
    try {
      await action();
    } catch (e) {
      if (active.current) fail(e);
    } finally {
      gate.current = false;
      if (active.current) setBusy(false);
    }
  };
  const sharePlan = async (pdf: string | null, pending = share) =>
    run(async () => {
      const op = pending ?? { operation: id(), revision, pdf };
      remember("share", op);
      try {
        await server.command(team, "web_plan_share", {
          p_practice_id: practice,
          p_operation_id: op.operation,
          p_expected_revision: op.revision,
          p_pdf_version_id: op.pdf,
        });
      } catch (e) {
        if (e instanceof ServerError && !e.uncertain) remember("share", null);
        throw e;
      }
      if (!active.current) return;
      remember("share", null);
      await load();
    });
  const reserve = async (ticket: Upload) => {
    try {
      return await server.command<FileVersion>(team, "file_reserve", {
        p_resource_id: ticket.resource,
        p_kind: "practice_plan",
        p_target_id: practice,
        p_operation_id: ticket.operation,
        p_declared_bytes: ticket.bytes,
        p_title: ticket.title,
        p_base_published_version_id: ticket.base,
      });
    } catch (e) {
      if (e instanceof ServerError && !e.uncertain) remember("upload", null);
      throw e;
    }
  };
  const startUpload = () =>
    run(async () => {
      if (!file || !title.trim() || upload) return;
      if (
        file.size < 1 ||
        file.size > 5 * 1024 * 1024 ||
        (file.type && file.type !== "application/pdf")
      )
        throw Error(
          "Choose a PDF no larger than 5 MB. The server checks its contents before it can be shared.",
        );
      const resources = await server.rows<{
        id: string;
        published_version_id: string | null;
      }>("file_resources", "id,published_version_id", {
        team_id: team,
        practice_id: practice,
        kind: "practice_plan",
      });
      const ticket: Upload = {
        operation: id(),
        resource: resources[0]?.id ?? id(),
        base: resources[0]?.published_version_id ?? null,
        bytes: file.size,
        title: title.trim(),
      };
      remember("upload", ticket);
      let version: FileVersion;
      try {
        version = await reserve(ticket);
      } catch (e) {
        if (e instanceof ServerError && !e.uncertain) remember("upload", null);
        throw e;
      }
      ticket.version = version.id;
      remember("upload", ticket);
      const result = await request("/uploads/" + ticket.operation, file);
      const saved = JSON.parse(
        new TextDecoder().decode(result.bytes),
      ) as FileVersion;
      if (
        saved.id !== ticket.version ||
        saved.status !== "ready" ||
        saved.byte_count !== ticket.bytes ||
        !/^[a-f0-9]{64}$/.test(saved.sha256 ?? "")
      )
        throw Error(
          "PDF validation could not be confirmed. Check upload status.",
        );
      setReady(saved);
      remember("upload", null);
      setFile(null);
      setTitle("");
      await load();
    });
  const reconcile = () =>
    run(async () => {
      if (!upload) return;
      if (!upload.version) {
        const versions = await server.rows<FileVersion>(
          "file_resource_versions",
          "id,revision,resource_id,status,sha256,byte_count",
          { team_id: team, operation_id: upload.operation },
        );
        if (!versions.length)
          throw Error(
            "The upload reservation could not be found. Check again before starting a new upload.",
          );
        remember("upload", { ...upload, version: versions[0].id });
      }
      const result = await request(
        "/uploads/" + upload.operation + "/reconcile",
        null,
      );
      const saved = JSON.parse(
        new TextDecoder().decode(result.bytes),
      ) as FileVersion;
      if (
        saved.status !== "ready" ||
        saved.byte_count !== upload.bytes ||
        !/^[a-f0-9]{64}$/.test(saved.sha256 ?? "")
      )
        throw Error(
          "PDF validation is still unconfirmed. Keep the original PDF.",
        );
      setReady(saved);
      remember("upload", null);
      await load();
    });
  const openPDF = (plan: SharedPlan) =>
    run(async () => {
      const op = id();
      await server.command(team, "file_delivery", {
        p_version_id: plan.pdf_version_id,
        p_operation_id: op,
      });
      const result = await request(
        "/files/" + plan.pdf_version_id + "?operation=" + op,
      );
      const digest = Array.from(
        new Uint8Array(await crypto.subtle.digest("SHA-256", result.bytes)),
      )
        .map((n) => n.toString(16).padStart(2, "0"))
        .join("");
      if (
        result.response.headers.get("Content-Type")?.split(";")[0] !==
          "application/pdf" ||
        result.response.headers.get("X-TeamStats-SHA256") !== digest
      )
        throw Error(
          "The PDF did not match its saved receipt. It was not opened.",
        );
      if (previewRef.current) URL.revokeObjectURL(previewRef.current);
      previewRef.current = URL.createObjectURL(
        new Blob([result.bytes], { type: "application/pdf" }),
      );
      setPreview(previewRef.current);
    });
  const show = (plan: SharedPlan) => (
    <section>
      <h4>
        {plan.kind === "pdf"
          ? "PDF plan"
          : (plan.builder?.title ?? "Practice plan")}{" "}
        · Shared version {plan.revision}
      </h4>
      <p>
        {new Date(plan.shared_at).toLocaleString()} ·{" "}
        {plan.is_current ? "Current shared plan" : "Earlier shared plan"}
      </p>
      {plan.kind === "pdf" ? (
        <button
          type="button"
          disabled={busy}
          onClick={() => void openPDF(plan)}
        >
          Open PDF version {plan.revision}
        </button>
      ) : (
        <>
          <p>
            {plan.builder?.date} ·{" "}
            {plan.builder?.protocol || "Drill instructions not entered"}
          </p>
          <ol>
            {plan.builder?.plan.map((row) => (
              <li key={row.id}>
                <strong>{row.name || "Drill name not entered"}</strong>
                <p>
                  {row.minutes
                    ? row.minutes + " minutes"
                    : "Duration not entered"}
                </p>
                <p>{row.instructions || "Instructions not entered"}</p>
              </li>
            ))}
          </ol>
          <button type="button" onClick={() => window.print()}>
            Print shared plan / Save PDF
          </button>
        </>
      )}
    </section>
  );
  return (
    <section className="shared-practice-plan">
      <div className="section-heading">
        <h3>Shared practice plan</h3>
        <button type="button" disabled={busy} onClick={() => void load()}>
          Refresh shared plan
        </button>
      </div>
      <p>
        Plans can be shared before practice. Sharing a plan does not verify or
        publish collected statistics.
      </p>
      {error && <Notice error>{error}</Notice>}
      {busy && <p role="status">Working with the practice plan…</p>}
      {loaded && !plans.length && (
        <Empty title="No shared plan yet">
          A coach or manager can save the builder plan or upload a PDF, then
          explicitly share it with the team.
        </Empty>
      )}
      {plans
        .filter((p) => p.is_current)
        .map((p) => (
          <div key={p.id}>{show(p)}</div>
        ))}
      {preview && (
        <>
          <iframe
            className="plan-pdf"
            title="Shared practice plan PDF"
            src={preview}
          />
          <a href={preview} download="teamstats-practice-plan.pdf">
            Download the opened PDF
          </a>
          <p className="muted">
            A downloaded copy remains on this device. Later access changes
            cannot recall it.
          </p>
        </>
      )}
      {editable && (
        <details>
          <summary>Share a plan or upload a PDF</summary>
          <p>
            Use Plan below to edit the builder. Save your team draft first, then
            share its saved plan. PDF upload is separate from the builder and is
            not converted into editable drills.
          </p>
          <button
            type="button"
            disabled={busy || dirty || !!share}
            onClick={() => void sharePlan(null)}
          >
            Share saved builder plan
          </button>
          {dirty && <p>Save the team draft before sharing its plan.</p>}
          {share && (
            <Notice>
              Plan sharing is unconfirmed. Check the shared plan before another
              change.
              <button type="button" disabled={busy} onClick={() => void load()}>
                Check shared plan status
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => void sharePlan(share.pdf, share)}
              >
                Retry same plan share
              </button>
            </Notice>
          )}
          <label className="field">
            PDF plan title
            <input
              maxLength={120}
              value={title}
              disabled={busy || !!upload}
              onChange={(e) => setTitle(e.target.value)}
            />
          </label>
          <label className="field">
            Practice plan PDF · maximum 5 MB
            <input
              type="file"
              accept="application/pdf,.pdf"
              disabled={busy || !!upload}
              onChange={(e) => {
                setFile(e.target.files?.[0] ?? null);
                setReady(null);
              }}
            />
          </label>
          <button
            type="button"
            disabled={busy || !!upload || !file || !title.trim()}
            onClick={startUpload}
          >
            Upload PDF draft
          </button>
          {upload && (
            <Notice>
              Upload outcome is not confirmed. Keep the original PDF; the
              selected file itself is not backed up here.
              {!upload.version && (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void run(async () => {
                      const version = await reserve(upload);
                      remember("upload", { ...upload, version: version.id });
                      await load();
                    })
                  }
                >
                  Retry same upload reservation
                </button>
              )}
              <button type="button" disabled={busy} onClick={reconcile}>
                Check PDF upload status
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    const versions = await server.rows<FileVersion>(
                      "file_resource_versions",
                      "id,revision,resource_id,status,sha256,byte_count",
                      { team_id: team, operation_id: upload.operation },
                    );
                    if (
                      versions.length !== 1 ||
                      versions[0].status !== "failed"
                    )
                      throw Error(
                        "The previous upload is not confirmed failed. Check its status first.",
                      );
                    remember("upload", null);
                    setReady(null);
                  })
                }
              >
                Start another upload after confirmed failure
              </button>
            </Notice>
          )}
          {ready && fileDrafts.every((v) => v.id !== ready.id) && (
            <Notice>
              PDF uploaded and validated. It is not shared yet.
              <button
                type="button"
                disabled={busy || !!share}
                onClick={() => void sharePlan(ready.id)}
              >
                Share validated PDF
              </button>
            </Notice>
          )}
          {fileDrafts.map((v) => (
            <section key={v.id} aria-label="Validated PDF draft">
              <h4>{v.title || "Untitled PDF draft"}</h4>
              <p>Validated PDF draft · not shared</p>
              <button
                type="button"
                disabled={busy || !!share}
                onClick={() => void sharePlan(v.id)}
              >
                Share validated PDF
              </button>
            </section>
          ))}
        </details>
      )}
      {plans.length > 1 && (
        <details>
          <summary>Earlier shared plans</summary>
          {plans
            .filter((p) => !p.is_current)
            .map((p) => (
              <div key={p.id}>{show(p)}</div>
            ))}
        </details>
      )}
    </section>
  );
}
