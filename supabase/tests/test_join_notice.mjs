// Injected worker seam; actual signed Auth/database and TLS SMTP are separate.
import test from "node:test";
import assert from "node:assert/strict";
import { handle } from "../functions/teamstats-access-notice/index.ts";
test("notification is disabled before any Auth, database or SMTP call", async () => {
  const result = await handle(
    new Request("http://127.0.0.1/notice", { method: "POST", body: "{}" }),
    {},
    () => assert.fail("no network"),
    () => assert.fail("no email"),
  );
  assert.equal(result.status, 503);
  assert.deepEqual(await result.json(), { state: "disabled" });
});
const id = "11111111-1111-4111-8111-111111111111",
  session = "22222222-2222-4222-8222-222222222222";
const env = {
  TEAMSTATS_JOIN_MAIL_ENABLED: "reviewed_nonproduction",
  TEAMSTATS_JOIN_MAIL_BUDGET: "reviewed_zero_cost",
  TEAMSTATS_LOCAL_MAIL_TEST: "synthetic_loopback",
  SUPABASE_URL: "http://127.0.0.1:55901",
  TEAMSTATS_WEB_ORIGIN: "http://127.0.0.1:4173",
  SUPABASE_ANON_KEY: "TEST_ONLY_PUBLIC",
  SUPABASE_SERVICE_ROLE_KEY: "TEST_ONLY_SERVER",
  TEAMSTATS_SMTP_USER: "test-only-sender@example.invalid",
  TEAMSTATS_SMTP_PASSWORD: "TEST_ONLY_PASSWORD",
  TEAMSTATS_OWNER_EMAIL: "test-only-owner@example.invalid",
  TEAMSTATS_LOCAL_SMTP_PORT: "55943",
};
const token =
  "a." +
  btoa(JSON.stringify({ sub: id, session_id: session, exp: 4102444800 })) +
  ".c";
const request = () =>
  new Request("http://127.0.0.1/notice", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      Origin: env.TEAMSTATS_WEB_ORIGIN,
    },
    body: JSON.stringify({ request_id: id }),
  });
const claim = {
  state: "claimed",
  claim: session,
  team_id: id,
  first_name: "TEST ONLY",
  last_name: "Synthetic",
  verified_email: "test-only-applicant@example.invalid",
  requested_role: "manager",
};
test("fresh Auth precedes the fenced claim; destination is private and output is sanitized", async () => {
  const calls = [],
    logs = [];
  const original = console.info;
  console.info = (x) => logs.push(x);
  try {
    const result = await handle(
      request(),
      env,
      async (url, init) => {
        calls.push(url);
        assert.equal(init.redirect, "error");
        if (url.endsWith("/user")) {
          assert.equal(init.headers.Authorization, "Bearer " + token);
          assert.equal(init.headers.apikey, env.SUPABASE_ANON_KEY);
          return Response.json({ id, is_anonymous: false });
        }
        assert.equal(init.headers.apikey, env.SUPABASE_SERVICE_ROLE_KEY);
        if (url.endsWith("_claim")) return Response.json(claim);
        assert.equal(JSON.parse(init.body).p_outcome, "sent");
        return Response.json({ state: "sent" });
      },
      async (mail, settings, signal) => {
        assert.equal(mail.to, env.TEAMSTATS_OWNER_EMAIL);
        assert.equal(settings.password, env.TEAMSTATS_SMTP_PASSWORD);
        assert.equal(signal.aborted, false);
        assert.match(mail.text, /TEST ONLY Synthetic/);
        assert.match(mail.text, /requested: test-only-applicant/);
        assert.match(mail.text, /Requested role: manager/);
        assert.match(mail.text, /\?reviewTeam=.*#access-requests/);
        assert.match(mail.text, /email grants no access/);
        return "sent";
      },
    );
    assert.equal((await result.json()).state, "sent");
    assert.equal(calls.length, 3);
  } finally {
    console.info = original;
  }
  const output = logs.join("");
  assert.equal(output, "");
  for (const secret of [
    token,
    env.SUPABASE_SERVICE_ROLE_KEY,
    env.TEAMSTATS_SMTP_PASSWORD,
    env.TEAMSTATS_OWNER_EMAIL,
    claim.verified_email,
    claim.first_name,
    id,
  ])
    assert.equal(output.includes(secret), false);
});
test("confirmed denial and provider unavailability are distinct; neither claims or sends", async () => {
  for (const status of [401, 403, 503]) {
    let reads = 0;
    const result = await handle(
      request(),
      env,
      async () => {
        reads++;
        return new Response("PRIVATE_ERROR_BODY", { status });
      },
      () => assert.fail("no email"),
    );
    assert.equal(result.status, status === 503 ? 503 : status);
    assert.deepEqual(await result.json(), {
      state: status === 503 ? "unconfirmed" : "denied",
    });
    assert.equal(reads, 1);
  }
});
test("busy, uncertain and accepted jobs cannot be sent twice", async () => {
  for (const state of [
    "busy",
    "manual_review",
    "sent",
    "retry_wait",
    "disabled",
  ]) {
    const result = await handle(
      request(),
      env,
      async (url) => Response.json(url.endsWith("/user") ? { id } : { state }),
      () => assert.fail("no email"),
    );
    assert.equal((await result.json()).state, state);
  }
});
test("lost finish reply never resubmits SMTP and cancellation still records uncertainty", async () => {
  let sends = 0;
  const lost = await handle(
    request(),
    env,
    async (url) => {
      if (url.endsWith("/user")) return Response.json({ id });
      if (url.endsWith("_claim")) return Response.json(claim);
      throw Error("PRIVATE provider details");
    },
    async () => {
      sends++;
      return "sent";
    },
  );
  assert.equal((await lost.json()).state, "unconfirmed");
  assert.equal(sends, 1);
  const controller = new AbortController();
  const r = request();
  const cancelled = new Request(r, { signal: controller.signal });
  const result = await handle(
    cancelled,
    env,
    async (url, init) => {
      if (url.endsWith("/user")) return Response.json({ id });
      if (url.endsWith("_claim")) return Response.json(claim);
      assert.equal(init.signal.aborted, false);
      assert.equal(JSON.parse(init.body).p_outcome, "uncertain");
      return Response.json({ state: "manual_review" });
    },
    async () => {
      controller.abort();
      throw Error("cancelled after possible acceptance");
    },
  );
  assert.equal((await result.json()).state, "manual_review");
});
test("untrusted origins, extra body fields and oversized requests never claim jobs", async () => {
  const denied = await handle(
    new Request(request(), {
      headers: { Origin: "https://untrusted.example.invalid" },
    }),
    env,
    () => assert.fail("no network"),
  );
  assert.equal(denied.status, 403);
  for (const body of [
    JSON.stringify({ request_id: id, to: "attacker@example.invalid" }),
    "x".repeat(129),
  ]) {
    const result = await handle(new Request(request(), { body }), env, () =>
      assert.fail("no network"),
    );
    assert.notEqual(result.status, 200);
  }
});
test("a failing diagnostic sink cannot replace the saved delivery receipt", async () => {
  const original = console.info;
  console.info = () => {
    throw Error("synthetic sink failure");
  };
  let finishes = 0;
  try {
    const result = await handle(
      request(),
      env,
      async (url) => {
        if (url.endsWith("/user")) return Response.json({ id });
        if (url.endsWith("_claim")) return Response.json(claim);
        finishes++;
        return Response.json({ state: "sent" });
      },
      async () => "sent",
    );
    assert.equal((await result.json()).state, "sent");
    assert.equal(finishes, 1);
  } finally {
    console.info = original;
  }
});
