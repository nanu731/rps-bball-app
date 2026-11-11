import { test, expect, type Page } from "@playwright/test";
import { readFileSync, existsSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { newSession } from "../src/domain.ts";
const path =
  process.env.TEAMSTATS_LOCAL_FIXTURE ??
  "../.scratch/teamstats-web/actual-fixture.local.json";
const fixture = existsSync(path)
  ? JSON.parse(readFileSync(path, "utf8"))
  : null;
test.skip(
  !fixture,
  "Requires private synthetic isolated Auth/PostgREST fixture.",
);
function safeFixture() {
  if (
    !fixture?.syntheticOnly ||
    new URL(fixture.apiRoot).hostname !== "127.0.0.1"
  )
    throw Error("Isolated synthetic fixture required");
}
async function signed(page: Page, role = "owner", pending?: unknown) {
  safeFixture();
  const account = fixture.actors[role];
  if (account.session.expires_at < Date.now() / 1000 + 60)
    throw Error("Local synthetic session needs private refresh");
  await page.addInitScript(
    ({ f, account, pending }) => {
      localStorage.setItem(
        "teamstats-web-public-config",
        JSON.stringify({ url: f.apiRoot, key: f.publishableKey }),
      );
      localStorage.setItem(
        "teamstats-web-auth:" + f.apiRoot,
        JSON.stringify(account.session),
      );
      if (pending)
        sessionStorage.setItem(
          `teamstats-web-session-buffer:${encodeURIComponent(f.apiRoot)}:${f.team}:${account.id}:pending`,
          JSON.stringify({
            actor: account.id,
            team: f.team,
            operation: pending,
          }),
        );
    },
    { f: fixture, account, pending },
  );
  await page.goto("/");
  await page.getByRole("button", { name: "Shared team", exact: true }).click();
  await expect(
    page.getByText("Account verified", { exact: true }),
  ).toBeVisible();
  await page
    .getByRole("combobox", { name: "Team", exact: true })
    .selectOption(fixture.team);
  await page
    .getByRole("button", { name: "Practices & capture", exact: true })
    .click();
  await expect(
    page.getByRole("heading", { name: "Shared practices & capture" }),
  ).toBeVisible();
}
async function rpc(role: string, name: string, args: Record<string, unknown>) {
  safeFixture();
  const r = await fetch(fixture.apiRoot + "/rest/v1/rpc/" + name, {
    method: "POST",
    headers: {
      apikey: fixture.publishableKey,
      Authorization: "Bearer " + fixture.actors[role].session.access_token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!r.ok)
    throw Error("Isolated signed RPC failed: " + r.status + " " + name);
  return r.json();
}
test("uncommitted create survives remount and retries the identical retained command once", async ({
  page,
}) => {
  const s = newSession(
    "practice",
    "TEST ONLY interrupted create " + randomUUID().slice(0, 8),
    "2037-01-01",
    [],
  );
  const { manual, clock, ...snapshot } = s;
  void manual;
  void clock;
  const pending = {
    id: randomUUID(),
    action: "create",
    session: s.id,
    revision: 0,
    document: { schema: 1, session: snapshot },
    argument: {},
  };
  await signed(page, "owner", pending);
  await page
    .getByRole("button", {
      name: "Look up this command’s receipt",
      exact: true,
    })
    .click();
  await expect(
    page.getByRole("button", { name: "Retry the identical retained command" }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Retry the identical retained command" })
    .click();
  await expect(
    page.getByText(/Server confirmed create · revision 1/),
  ).toBeVisible();
  const state = await rpc("owner", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: s.id,
  });
  expect(state.session.revision).toBe(1);
  expect(state.document.session.title).toBe(s.title);
  expect(
    await page.evaluate(() =>
      Object.keys(sessionStorage).filter((k) => k.endsWith(":pending")),
    ),
  ).toEqual([]);
});

test("lost administration reply reconciles the actual target before enabling another command", async ({
  page,
}) => {
  await signed(page);
  await page.getByRole("button", { name: "Manage team", exact: true }).click();
  await page
    .getByRole("combobox", { name: "Existing active member", exact: true })
    .selectOption(fixture.actors.viewer.id);
  await page
    .getByRole("combobox", { name: "Capability", exact: true })
    .selectOption("sessions.clock");
  page.on("dialog", (d) => d.accept());
  let applied = 0;
  await page.route(
    "**/rpc/team_set_capability",
    async (route) => {
      const response = await route.fetch();
      expect(response.ok()).toBe(true);
      applied++;
      await route.abort("failed");
    },
    { times: 1 },
  );
  await page
    .getByRole("button", { name: "Grant selected capability", exact: true })
    .click();
  await expect(
    page.getByText("Administration result uncertain.", { exact: false }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", {
      name: "Grant selected capability",
      exact: true,
    }),
  ).toBeDisabled();
  await page
    .getByRole("button", {
      name: "Read current attempted target state",
      exact: true,
    })
    .click();
  await expect(page.getByText(/Current stored grant is present/)).toBeVisible();
  expect(applied).toBe(1);
  await page
    .getByRole("button", {
      name: "I reviewed the current state; allow a new command",
      exact: true,
    })
    .click();
  await expect(
    page.getByRole("button", {
      name: "Revoke selected capability",
      exact: true,
    }),
  ).toBeEnabled();
  await page
    .getByRole("button", { name: "Revoke selected capability", exact: true })
    .click();
  await expect(
    page.getByText(/Server confirmed the administration change/),
  ).toBeVisible();
  expect(
    await page.evaluate(() =>
      Object.keys(sessionStorage).filter((k) =>
        k.startsWith("teamstats-web-admin-pending:"),
      ),
    ),
  ).toEqual([]);
});
