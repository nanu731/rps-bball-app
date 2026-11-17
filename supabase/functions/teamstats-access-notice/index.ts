// No browser credentials, message content or raw provider errors enter diagnostics.
export type Mail = {
  from: string;
  to: string;
  messageId: string;
  subject: string;
  text: string;
};
export type MailSettings = {
  host: string;
  port: number;
  user: string;
  password: string;
  local: boolean;
  ca?: string;
};
export type Delivery =
  "sent" | "transient" | "configuration" | "permanent" | "uncertain";
type Sender = (
  mail: Mail,
  settings: MailSettings,
  signal: AbortSignal,
) => Promise<Delivery>;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const address = /^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$/;
const states = new Set([
  "sent",
  "retry",
  "retry_wait",
  "busy",
  "manual_review",
  "disabled",
  "cancelled",
  "stale",
]);
async function bounded(
  stream: ReadableStream<Uint8Array> | null,
  maximum: number,
  signal: AbortSignal,
): Promise<string> {
  if (!stream) return "";
  const reader = stream.getReader();
  let size = 0,
    text = "";
  const decoder = new TextDecoder();
  const cancel = () => {
    void reader.cancel().catch(() => {});
  };
  signal.addEventListener("abort", cancel, { once: true });
  try {
    while (true) {
      signal.throwIfAborted();
      const n = await reader.read();
      signal.throwIfAborted();
      if (n.done) break;
      size += n.value.byteLength;
      if (size > maximum) throw Error("bounded");
      text += decoder.decode(n.value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    signal.removeEventListener("abort", cancel);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
export async function handle(
  request: Request,
  env: Record<string, string | undefined>,
  transport: typeof fetch = fetch,
  send?: Sender,
): Promise<Response> {
  const reply = (state: string, status = 200) => {
    return Response.json(
      { state },
      {
        status,
        headers: {
          "Cache-Control": "no-store",
          ...(origin && origin === env.TEAMSTATS_WEB_ORIGIN
            ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" }
            : {}),
        },
      },
    );
  };
  const origin = request.headers.get("Origin");
  try {
    if (origin && origin !== env.TEAMSTATS_WEB_ORIGIN)
      return reply("denied", 403);
    if (request.method === "OPTIONS" && origin === env.TEAMSTATS_WEB_ORIGIN)
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": origin!,
          "Access-Control-Allow-Methods": "POST",
          "Access-Control-Allow-Headers": "authorization,apikey,content-type",
          "Access-Control-Max-Age": "300",
          Vary: "Origin",
        },
      });
    if (
      env.TEAMSTATS_JOIN_MAIL_ENABLED !== "reviewed_nonproduction" ||
      env.TEAMSTATS_JOIN_MAIL_BUDGET !== "reviewed_zero_cost"
    )
      return reply("disabled", 503);
    if (request.method !== "POST" || new URL(request.url).search)
      return reply("invalid", 400);
    const local = env.TEAMSTATS_LOCAL_MAIL_TEST === "synthetic_loopback",
      base = new URL(env.SUPABASE_URL ?? ""),
      web = new URL(env.TEAMSTATS_WEB_ORIGIN ?? "");
    if (
      base.origin !== env.SUPABASE_URL ||
      web.origin !== env.TEAMSTATS_WEB_ORIGIN ||
      !(
        (base.protocol === "https:" &&
          /^[a-z0-9]+\.supabase\.co$/.test(base.hostname)) ||
        (local && base.hostname === "127.0.0.1" && base.protocol === "http:")
      ) ||
      !(
        web.origin === "https://teamstats-nonproduction.pages.dev" ||
        (local && web.protocol === "http:" && web.hostname === "127.0.0.1")
      ) ||
      !env.SUPABASE_ANON_KEY ||
      !env.SUPABASE_SERVICE_ROLE_KEY ||
      !env.TEAMSTATS_SMTP_PASSWORD ||
      !address.test(env.TEAMSTATS_SMTP_USER ?? "") ||
      !address.test(env.TEAMSTATS_OWNER_EMAIL ?? "")
    )
      return reply("configuration", 503);
    const settings: MailSettings = {
      host: local ? "127.0.0.1" : "smtp.gmail.com",
      port: local ? Number(env.TEAMSTATS_LOCAL_SMTP_PORT) : 465,
      user: env.TEAMSTATS_SMTP_USER!,
      password: env.TEAMSTATS_SMTP_PASSWORD!,
      local,
      ca: local ? env.TEAMSTATS_LOCAL_SMTP_CA : undefined,
    };
    if (
      !Number.isInteger(settings.port) ||
      (settings.port < 1024 && local) ||
      settings.port > 65535
    )
      return reply("configuration", 503);
    const authorization = request.headers.get("Authorization") ?? "";
    if (!authorization.startsWith("Bearer ") || authorization.length > 16384)
      return reply("denied", 401);
    const signal = AbortSignal.any([
      request.signal,
      AbortSignal.timeout(20000),
    ]);
    const body = JSON.parse(await bounded(request.body, 128, signal));
    if (!body || Object.keys(body).length !== 1 || !uuid.test(body.request_id))
      return reply("invalid", 400);
    const auth = await transport(base.origin + "/auth/v1/user", {
      headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: authorization },
      signal,
      redirect: "error",
    });
    if (!auth.ok) {
      await auth.body?.cancel();
      return [401, 403].includes(auth.status)
        ? reply("denied", auth.status)
        : reply("unconfirmed", 503);
    }
    const user = JSON.parse(await bounded(auth.body, 16384, signal));
    const part = authorization.slice(7).split(".")[1] ?? "",
      claims = JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    if (
      !uuid.test(user.id) ||
      user.id !== claims.sub ||
      user.is_anonymous ||
      !uuid.test(claims.session_id) ||
      !Number.isSafeInteger(claims.exp) ||
      claims.exp <= Date.now() / 1000
    )
      return reply("denied", 401);
    const rpc = async (
      name: string,
      args: Record<string, unknown>,
      deadline: AbortSignal,
    ) => {
      const response = await transport(base.origin + "/rest/v1/rpc/" + name, {
        method: "POST",
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY!,
          Authorization: "Bearer " + env.SUPABASE_SERVICE_ROLE_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(args),
        signal: deadline,
        redirect: "error",
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw Error("unavailable");
      }
      return JSON.parse(await bounded(response.body, 4096, deadline));
    };
    const claim = await rpc(
      "web_join_notice_claim",
      {
        p_request_id: body.request_id,
        p_actor: user.id,
        p_session: claims.session_id,
        p_exp: claims.exp,
      },
      signal,
    );
    if (claim.state !== "claimed")
      return states.has(claim.state)
        ? reply(claim.state)
        : reply("unconfirmed", 503);
    let delivery: Delivery = "configuration",
      dispatched = false;
    try {
      if (
        !uuid.test(claim.claim) ||
        !uuid.test(claim.team_id) ||
        !["player", "coach", "manager"].includes(claim.requested_role) ||
        !address.test(claim.verified_email) ||
        [claim.first_name, claim.last_name].some(
          (n) =>
            typeof n !== "string" ||
            n.length < 1 ||
            n.length > 160 ||
            /[\p{Cc}]/u.test(n),
        )
      )
        throw Error("configuration");
      const mail: Mail = {
        from: settings.user,
        to: env.TEAMSTATS_OWNER_EMAIL!,
        subject: "TeamStats access request",
        messageId: `<teamstats-request-${body.request_id}@${web.hostname}>`,
        text: `A verified account requested TeamStats access.\n\nName: ${claim.first_name} ${claim.last_name}\nEmail verified when requested: ${claim.verified_email}\nRequested role: ${claim.requested_role}\n\nSign in to review: ${web.origin}/?reviewTeam=${claim.team_id}#access-requests\n\nThis email grants no access. Verify the applicant and confirm or change their role in TeamStats.`,
      };
      const sender = send ?? (await import("./smtp.ts")).deliver;
      dispatched = true;
      delivery = await sender(mail, settings, signal);
      if (
        ![
          "sent",
          "transient",
          "configuration",
          "permanent",
          "uncertain",
        ].includes(delivery)
      )
        delivery = "uncertain";
    } catch {
      delivery = dispatched ? "uncertain" : "configuration";
    }
    // A disconnected browser does not release a claimed email for automatic resend.
    const finished = await rpc(
      "web_join_notice_finish",
      {
        p_request_id: body.request_id,
        p_claim: claim.claim,
        p_outcome: delivery,
      },
      AbortSignal.timeout(5000),
    );
    return states.has(finished.state)
      ? reply(finished.state)
      : reply("unconfirmed", 503);
  } catch {
    return reply("unconfirmed", 503);
  }
}
if (typeof Deno !== "undefined")
  Deno.serve((request) => handle(request, Deno.env.toObject()));
