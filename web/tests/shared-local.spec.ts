import { test, expect, type Page } from "@playwright/test";
import { readFileSync, existsSync, mkdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { newSession } from "../src/domain.ts";
const path =
  process.env.TEAMSTATS_LOCAL_FIXTURE ??
  "../.scratch/teamstats-web/actual-fixture.local.json";
const fixture = existsSync(path)
  ? JSON.parse(readFileSync(path, "utf8"))
  : null;
test.use({ actionTimeout: 10000 });
test.skip(
  !fixture,
  "Requires private synthetic isolated Auth/PostgREST fixture.",
);

const evidence = process.env.TEAMSTATS_EVIDENCE;
async function shot(page: Page, name: string) {
  if (evidence) {
    mkdirSync(evidence, { recursive: true });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      path: evidence + "/" + name + ".png",
      fullPage: true,
    });
  }
}
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
  await expect(page.locator(".web-sessions")).toBeVisible();
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
  await page
    .getByText("Team authority & administration", { exact: true })
    .click();
  await page.getByRole("button", { name: "Manage team", exact: true }).click();
  await shot(page, "desktop-shared-owner-administration");
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

async function recovery(page: Page) {
  const summary = page.getByText("Recovery & server snapshot", { exact: true });
  if (await summary.evaluate((e) => !e.parentElement?.hasAttribute("open")))
    await summary.click();
}
async function openShared(page: Page, title: string) {
  await page
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await expect(
    page.getByRole("heading", { name: title, exact: true }),
  ).toBeVisible();
}
async function createShared(
  page: Page,
  kind: "practice" | "game",
  title: string,
) {
  await page
    .getByRole("combobox", { name: "Session kind", exact: true })
    .selectOption(kind);
  await page
    .getByRole("textbox", { name: "Session name", exact: true })
    .fill(title);
  if (kind === "game")
    await page
      .getByRole("combobox", { name: "Existing server game", exact: true })
      .selectOption(fixture.game);
  const response = page.waitForResponse(
    (r) =>
      r.url().endsWith("/rpc/web_session_command") &&
      r.request().postDataJSON()?.p_action === "create",
  );
  await page
    .getByRole("button", { name: "Create server session", exact: true })
    .click();
  const r = await response;
  expect(r.ok()).toBe(true);
  const result = await r.json();
  await expect(page.getByText(/Server confirmed create/)).toBeVisible();
  return result.session.id as string;
}
async function assign(page: Page) {
  const settings = page.getByText(
    "Recorder assignment and collection definitions",
    { exact: true },
  );
  if (await settings.evaluate((e) => !e.parentElement?.hasAttribute("open")))
    await settings.click();
  await page
    .getByRole("textbox", { name: "Recording account UUID", exact: true })
    .fill(fixture.actors.recorder.id);
  await page
    .getByRole("textbox", { name: "Clock account UUID", exact: true })
    .fill(fixture.actors.clock.id);
  await page
    .getByRole("button", { name: "Confirm recorder handoff", exact: true })
    .click();
  await expect(page.getByText(/Server confirmed assign/)).toBeVisible();
}
test("actual signed practice plan, recording, review, accepted viewer and correction lineage", async ({
  page,
  browser,
}) => {
  await signed(page);
  const title = "TEST ONLY practice journey " + randomUUID().slice(0, 8);
  const session = await createShared(page, "practice", title);
  await page
    .getByRole("textbox", {
      name: "Sets, rotations, baskets and collector responsibility",
      exact: true,
    })
    .fill(
      "TEST ONLY protocol: observed station totals; synthetic fixture only.",
    );
  await page.getByRole("button", { name: "Add drill", exact: true }).click();
  await page
    .getByLabel("Drill name", { exact: true })
    .fill("TEST ONLY station work");
  await page.getByLabel("Minutes", { exact: true }).fill("12");
  await page
    .getByLabel("Coach’s instructions", { exact: true })
    .fill("TEST ONLY synthetic observations, no coach protocol implied.");
  await page
    .getByRole("button", { name: "Save shared session draft", exact: true })
    .click();
  await expect(page.getByText(/Server confirmed save/)).toBeVisible();
  await shot(page, "desktop-shared-practice-plan");
  await assign(page);
  const recorder = await browser.newPage();
  await signed(recorder, "recorder");
  await openShared(recorder, title);
  await recorder.getByRole("button", { name: "Shooting", exact: true }).click();
  await recorder.getByLabel("Spot 1 makes", { exact: true }).fill("0");
  await recorder.getByLabel("Spot 1 attempts", { exact: true }).fill("0");
  await recorder
    .getByRole("button", { name: "FT conditioning", exact: true })
    .click();
  await recorder.getByLabel("Free-throw makes", { exact: true }).fill("1");
  await recorder.getByLabel("Free-throw attempts", { exact: true }).fill("2");
  await recorder
    .getByRole("button", { name: "Save shared session draft", exact: true })
    .click();
  await expect(recorder.getByText(/Server confirmed save/)).toBeVisible();
  const saved = await rpc("recorder", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  const player = saved.document.session.players[0].id;
  expect(saved.document.session.shooting[player]["0"]).toEqual({
    made: "0",
    attempts: "0",
  });
  expect(saved.document.session.shooting[player]["1"]).toBeUndefined();
  expect(saved.document.session.ft[player]).toEqual({
    made: "1",
    attempts: "2",
  });
  await recorder.setViewportSize({ width: 390, height: 844 });
  await shot(recorder, "phone-shared-practice-entry");
  await recovery(recorder);
  await recorder
    .getByRole("button", { name: "Load server snapshot", exact: true })
    .click();
  await recorder.getByRole("button", { name: "Shooting", exact: true }).click();
  await expect(
    recorder.getByLabel("Spot 1 makes", { exact: true }),
  ).toHaveValue("0");
  await recorder
    .getByRole("button", { name: "Submit session for review", exact: true })
    .click();
  await expect(recorder.getByText(/Server confirmed submit/)).toBeVisible();
  const reviewer = await browser.newPage();
  await signed(reviewer, "reviewer");
  await openShared(reviewer, title);
  reviewer.on("dialog", (d) => d.accept());
  await reviewer
    .getByRole("button", { name: "Accept session & publish", exact: true })
    .click();
  await expect(reviewer.getByText(/Server confirmed review/)).toBeVisible();
  const viewer = await browser.newPage();
  await signed(viewer, "viewer");
  await openShared(viewer, title);
  await expect(
    viewer.getByText("Server-accepted snapshot.", { exact: false }),
  ).toBeVisible();
  await expect(
    viewer.getByRole("button", {
      name: "Save shared session draft",
      exact: true,
    }),
  ).toHaveCount(0);
  await viewer.waitForResponse(
    (r) => r.url().endsWith("/rpc/web_session_state"),
    { timeout: 8000 },
  );
  await expect(
    viewer.getByRole("heading", { name: "Practice observations", exact: true }),
  ).toBeVisible();
  const accepted = await rpc("viewer", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  expect(accepted.document_scope).toBe("accepted");
  await expect(viewer.locator(".clock-strip")).toHaveCount(0);
  await viewer
    .getByRole("combobox", { name: "Results player", exact: true })
    .selectOption(fixture.roster[1]);
  await expect(
    viewer
      .getByRole("region", { name: "Practice shooting results", exact: true })
      .locator("tbody tr"),
  ).toHaveCount(1);
  await expect(
    viewer
      .getByRole("region", { name: "Practice shooting results", exact: true })
      .locator("tbody tr"),
  ).toContainText("TEST ONLY Web Player B");
  await viewer
    .getByRole("combobox", { name: "Results player", exact: true })
    .selectOption("all");
  await viewer.setViewportSize({ width: 1024, height: 768 });
  await viewer.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
  await shot(viewer, "tablet-shared-practice-accepted-dark");
  await recovery(recorder);
  await recorder
    .getByRole("button", { name: "Load server snapshot", exact: true })
    .click();
  await recorder
    .getByRole("button", { name: "Request session correction", exact: true })
    .click();
  await expect(
    recorder.getByText(/Server confirmed request edit/),
  ).toBeVisible();
  await recovery(reviewer);
  await reviewer
    .getByRole("button", { name: "Load server snapshot", exact: true })
    .click();
  await reviewer
    .getByRole("button", { name: "Approve session correction", exact: true })
    .click();
  await expect(reviewer.getByText(/Server confirmed reopen/)).toBeVisible();
  const correction = await rpc("recorder", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  expect(correction.session.base_accepted_snapshot_id).toBe(
    accepted.session.accepted_snapshot_id,
  );
  expect(correction.session.accepted_snapshot_id).toBe(
    accepted.session.accepted_snapshot_id,
  );
  await Promise.all([recorder.close(), reviewer.close(), viewer.close()]);
});

test("separate assigned clock operator and recorder save an actual shared shot while clock runs", async ({
  page,
  browser,
}) => {
  await signed(page);
  const title = "TEST ONLY game capture " + randomUUID().slice(0, 8);
  const session = await createShared(page, "game", title);
  await assign(page);
  const clock = await browser.newPage();
  await signed(clock, "clock");
  await openShared(clock, title);
  await clock.getByText("Set shared clock", { exact: true }).click();
  await clock.getByLabel("Shared clock seconds", { exact: true }).fill("480");
  await clock
    .getByRole("button", { name: "Set stopped shared clock", exact: true })
    .click();
  await expect(clock.getByText(/Server confirmed clock set/)).toBeVisible();
  await clock
    .getByRole("button", { name: "Start shared clock", exact: true })
    .click();
  await expect(clock.getByText(/Server confirmed clock start/)).toBeVisible();
  const recorder = await browser.newPage();
  await signed(recorder, "recorder");
  await openShared(recorder, title);
  await expect(
    recorder.getByRole("button", { name: "Stop clock", exact: true }),
  ).toBeDisabled();
  await recorder
    .getByRole("img", { name: /Schematic court/ })
    .click({ position: { x: 150, y: 170 } });
  await recorder.getByRole("button", { name: "3 points", exact: true }).click();
  await recorder.getByRole("button", { name: "Make", exact: true }).click();
  await expect(recorder.getByText(/Server confirmed save/)).toBeVisible();
  const saved = await rpc("recorder", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  expect(saved.document.session.changes).toHaveLength(1);
  expect(saved.document.session.changes[0].after.value).toBe(3);
  expect(saved.session.clock_started_at).not.toBeNull();
  await recorder.getByRole("button", { name: "FT miss", exact: true }).click();
  await expect(
    recorder.getByText(/Player A · FT miss/, { exact: false }),
  ).toBeVisible();
  await recorder
    .getByRole("button", { name: "Undo last change", exact: true })
    .click();
  await expect(recorder.getByText(/Server confirmed save/)).toBeVisible();
  const after = await rpc("recorder", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  expect(after.document.session.changes.length).toBe(3);
  expect(after.document.session.changes[2].undoOf).toBe(
    after.document.session.changes[1].id,
  );
  await clock
    .getByRole("button", { name: "Stop shared clock", exact: true })
    .click();
  await expect(clock.getByText(/Server confirmed clock stop/)).toBeVisible();
  await recorder.setViewportSize({ width: 390, height: 844 });
  await shot(recorder, "phone-shared-game-capture");
  await recorder
    .getByRole("button", { name: "Submit session for review", exact: true })
    .click();
  await expect(recorder.getByText(/Server confirmed submit/)).toBeVisible();
  const reviewer = await browser.newPage();
  await signed(reviewer, "reviewer");
  await openShared(reviewer, title);
  reviewer.on("dialog", (d) => d.accept());
  await reviewer
    .getByRole("button", { name: "Accept session & publish", exact: true })
    .click();
  await expect(reviewer.getByText(/Server confirmed review/)).toBeVisible();
  const viewer = await browser.newPage();
  await signed(viewer, "viewer");
  await openShared(viewer, title);
  await expect(
    viewer.getByRole("heading", { name: "Recorded-shot results", exact: true }),
  ).toBeVisible();
  await expect(
    viewer.getByText("Server-accepted snapshot · coverage unconfirmed", {
      exact: true,
    }),
  ).toBeVisible();
  await viewer.setViewportSize({ width: 1024, height: 768 });
  expect(
    await viewer.evaluate(() => document.documentElement.scrollWidth),
  ).toBe(1024);
  await viewer
    .getByRole("button", {
      name: "Scroll Recorded-shot totals right",
      exact: true,
    })
    .click();
  await expect(
    viewer.getByRole("columnheader", { name: "Observed %", exact: true }),
  ).toBeInViewport();
  await expect(viewer.locator(".clock-strip .clock")).toHaveText(/^\d+:\d{2}$/);
  await shot(viewer, "tablet-shared-game-accepted");
  const accepted = await rpc("viewer", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  expect(accepted.document_scope).toBe("accepted");
  expect(accepted.document.session.changes).toHaveLength(3);
  await Promise.all([
    clock.close(),
    recorder.close(),
    reviewer.close(),
    viewer.close(),
  ]);
});

async function sessionCommand(
  role: string,
  action: string,
  session: string,
  document: unknown = null,
  argument: Record<string, unknown> = {},
) {
  const state = await rpc(role, "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  const access = await rpc(role, "team_access", { p_team_id: fixture.team });
  return rpc(role, "web_session_command", {
    p_team_id: fixture.team,
    p_operation_id: randomUUID(),
    p_action: action,
    p_session_id: session,
    p_expected_revision: state.session.revision,
    p_expected_access_revision: access.access_revision,
    p_document: document,
    p_argument: argument,
  });
}
test("dirty working buffer is never relabeled accepted when server visibility falls back", async ({
  page,
  browser,
}) => {
  await signed(page);
  const title = "TEST ONLY visibility fallback " + randomUUID().slice(0, 8);
  const session = await createShared(page, "practice", title);
  await assign(page);
  const original = await rpc("recorder", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  const player = original.document.session.players[0].id;
  original.document.session.ft[player] = { made: "0", attempts: "0" };
  await sessionCommand("recorder", "save", session, original.document, {
    assignment_revision: original.session.assignment_revision,
  });
  await sessionCommand("recorder", "submit", session);
  await sessionCommand("reviewer", "review", session, null, { approve: true });
  await sessionCommand("recorder", "request_edit", session);
  await sessionCommand("reviewer", "reopen", session);
  const recorder = await browser.newPage();
  await signed(recorder, "recorder");
  await openShared(recorder, title);
  await recorder
    .getByRole("button", { name: "FT conditioning", exact: true })
    .click();
  await recorder.getByLabel("Free-throw makes", { exact: true }).fill("9");
  await sessionCommand("recorder", "submit", session);
  await sessionCommand("reviewer", "review", session, null, { approve: false });
  await sessionCommand("owner", "request_edit", session);
  await sessionCommand("reviewer", "reopen", session);
  await expect(recorder.getByText(/Accepted snapshot · revision/)).toBeVisible({
    timeout: 8000,
  });
  await expect(
    recorder.getByRole("cell", { name: "0 / 0", exact: true }),
  ).toBeVisible();
  await expect(
    recorder.getByRole("button", {
      name: "Save shared session draft",
      exact: true,
    }),
  ).toHaveCount(0);
  const retained = await recorder.evaluate(
    ({ url, team, actor }) =>
      JSON.parse(
        sessionStorage.getItem(
          `teamstats-web-session-buffer:${encodeURIComponent(url)}:${team}:${actor}`,
        ) ?? "null",
      )?.session.ft,
    {
      url: fixture.apiRoot,
      team: fixture.team,
      actor: fixture.actors.recorder.id,
    },
  );
  expect(retained[player].made).toBe("9");
  await recorder.close();
});

test("committed save with a lost reply reconciles after remount without duplicate mutation", async ({
  page,
}) => {
  page.on("dialog", (d) => d.accept());
  await signed(page);
  const title = "TEST ONLY lost reply " + randomUUID().slice(0, 8);
  const session = await createShared(page, "practice", title);
  await page
    .getByRole("textbox", {
      name: "Sets, rotations, baskets and collector responsibility",
      exact: true,
    })
    .fill("TEST ONLY retained protocol");
  let writes = 0;
  await page.route(
    "**/rpc/web_session_command",
    async (route) => {
      expect(route.request().postDataJSON().p_action).toBe("save");
      const response = await route.fetch();
      expect(response.ok()).toBe(true);
      writes++;
      await route.abort("failed");
    },
    { times: 1 },
  );
  await page
    .getByRole("button", { name: "Save shared session draft", exact: true })
    .click();
  await expect.poll(() => writes).toBe(1);
  await expect(page.getByText(/No confirmed result/)).toBeVisible();
  await page.getByRole("button", { name: "Workspace", exact: true }).click();
  await page.getByRole("button", { name: "Shared team", exact: true }).click();
  await page
    .getByRole("combobox", { name: "Team", exact: true })
    .selectOption(fixture.team);
  await page
    .getByRole("button", { name: "Practices & capture", exact: true })
    .click();
  await page
    .getByRole("button", {
      name: "Look up this command’s receipt",
      exact: true,
    })
    .click();
  await expect(
    page.getByText(/Server confirmed save · revision 2/),
  ).toBeVisible();
  const saved = await rpc("owner", "web_session_state", {
    p_team_id: fixture.team,
    p_session_id: session,
  });
  expect(saved.session.revision).toBe(2);
  expect(saved.document.session.protocol).toBe("TEST ONLY retained protocol");
  expect(writes).toBe(1);
  expect(
    await page.evaluate(() =>
      Object.keys(sessionStorage).filter((k) => k.endsWith(":pending")),
    ),
  ).toEqual([]);
});

test("actual shared manual box, paired possessions and paint keep independent completion and accepted results", async ({
  page,
  browser,
}) => {
  test.setTimeout(90000);
  await signed(page, "recorder");
  await page.getByRole("button", { name: "Manual games", exact: true }).click();
  const title = "TEST ONLY manual browser " + randomUUID().slice(0, 8);
  await page
    .getByRole("textbox", { name: "Opponent", exact: true })
    .fill(title);
  const created = page.waitForResponse((r) =>
    r.url().endsWith("/rpc/stats_create_game"),
  );
  await page
    .getByRole("button", { name: "Create server game", exact: true })
    .click();
  const game = await (await created).json();
  expect(game.opponent).toBe(title);
  await page.getByRole("button", { name: "Draft entry", exact: true }).click();
  await page
    .getByRole("button", { name: "Open my permitted draft", exact: true })
    .click();
  await page.getByLabel("Points", { exact: true }).fill("4");
  await page.getByLabel("Threes made", { exact: true }).fill("7");
  await expect(page.getByText("Check scoring", { exact: true })).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await shot(page, "phone-shared-manual-warning");
  await page
    .getByRole("button", { name: "Save server draft", exact: true })
    .click();
  await expect(page.getByText(/Server confirmed this operation/)).toBeVisible();
  await page.getByRole("button", { name: "Roster table", exact: true }).click();
  const players = ["TEST ONLY Web Player A", "TEST ONLY Web Player B"];
  for (const name of players)
    for (const label of [
      "Points",
      "Offensive rebounds",
      "Defensive rebounds",
      "Assists",
      "Turnovers",
      "Steals",
      "Blocks",
      "Fouls",
      "Charges drawn",
      "Twos made",
      "Twos missed",
      "Threes made",
      "Threes missed",
      "Free throws made",
      "Free throws missed",
    ])
      await page.getByLabel(name + " " + label, { exact: true }).fill("0");
  await expect(page.getByText("Check scoring", { exact: true })).toHaveCount(0);
  await page
    .getByRole("button", { name: "Save server draft", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Save server draft", exact: true }),
  ).toBeDisabled();
  await page
    .getByText("Complete this independent dataset", { exact: true })
    .click();
  await page
    .getByRole("checkbox", {
      name: "I confirm this game and the covered real roster.",
      exact: true,
    })
    .check();
  await page
    .getByRole("button", { name: "Complete player box scores", exact: true })
    .click();
  await expect(page.getByText(/This version is frozen/)).toBeVisible();
  await page
    .getByRole("combobox", { name: "Dataset", exact: true })
    .selectOption("our_possessions");
  await page
    .getByRole("button", { name: "Open my permitted draft", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Add next our-team possession", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Add next opponent possession", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Add next opponent possession", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Save server draft", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Save server draft", exact: true }),
  ).toBeDisabled();
  await expect(
    page.getByText("1 records entered", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText("2 records entered", { exact: true }),
  ).toBeVisible();
  for (const kind of ["our_possessions", "opponent_possessions"]) {
    await page
      .getByRole("combobox", { name: "Dataset", exact: true })
      .selectOption(kind);
    const disclosure = page.getByText("Complete this independent dataset", {
      exact: true,
    });
    if (
      await disclosure.evaluate((e) => !e.parentElement?.hasAttribute("open"))
    )
      await disclosure.click();
    await page
      .getByRole("checkbox", { name: /Convert only existing numeric blanks/ })
      .check();
    await page
      .getByRole("button", {
        name:
          kind === "our_possessions"
            ? "Complete our possessions"
            : "Complete opponent possessions",
        exact: true,
      })
      .click();
    await expect(page.getByText(/This version is frozen/)).toBeVisible();
  }
  await page
    .getByRole("combobox", { name: "Dataset", exact: true })
    .selectOption("player_paint_touches");
  await page
    .getByRole("button", { name: "Open my permitted draft", exact: true })
    .click();
  for (const name of players)
    await page.getByLabel(name + " paint touches", { exact: true }).fill("0");
  await page
    .getByRole("button", { name: "Save server draft", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Save server draft", exact: true }),
  ).toBeDisabled();
  await page
    .getByText("Complete this independent dataset", { exact: true })
    .click();
  await page
    .getByRole("checkbox", {
      name: "I confirm this game and the covered real roster.",
      exact: true,
    })
    .check();
  await page
    .getByRole("button", { name: "Complete player paint touches", exact: true })
    .click();
  await expect(page.getByText(/This version is frozen/)).toBeVisible();
  await page
    .getByRole("button", { name: "Review & history", exact: true })
    .click();
  for (const label of [
    "Player box scores",
    "Our possessions",
    "Opponent possessions",
    "Player paint touches",
  ]) {
    const row = page
      .locator(".version-list > section")
      .filter({ has: page.getByRole("heading", { name: label, exact: true }) });
    await row
      .getByRole("button", { name: "Submit for review", exact: true })
      .click();
    await expect(row.getByText(/submitted · revision/)).toBeVisible();
  }
  const reviewer = await browser.newPage();
  await signed(reviewer, "reviewer");
  await reviewer
    .getByRole("button", { name: "Manual games", exact: true })
    .click();
  await reviewer
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await reviewer
    .getByRole("button", { name: "Review & history", exact: true })
    .click();
  reviewer.on("dialog", (d) => d.accept());
  for (const label of [
    "Player box scores",
    "Our possessions",
    "Opponent possessions",
    "Player paint touches",
  ]) {
    const row = reviewer.locator(".version-list > section").filter({
      has: reviewer.getByRole("heading", { name: label, exact: true }),
    });
    await row
      .getByRole("button", { name: "Accept & publish", exact: true })
      .click();
    await expect(row.getByText(/published · revision/)).toBeVisible();
  }
  const viewer = await browser.newPage();
  await signed(viewer, "viewer");
  await viewer
    .getByRole("button", { name: "Manual games", exact: true })
    .click();
  await viewer
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await expect(
    viewer.getByText(/4 independently accepted datasets/),
  ).toBeVisible();
  await shot(viewer, "desktop-shared-manual-accepted");
  await expect(
    viewer.getByText(
      "Server-accepted versions · missing datasets remain unavailable",
      { exact: false },
    ),
  ).toBeVisible();
  await expect(
    viewer.getByRole("button", {
      name: "Open my permitted draft",
      exact: true,
    }),
  ).toHaveCount(0);
  await Promise.all([reviewer.close(), viewer.close()]);
});

test("manual lost save stays blocked across remount and reconciles the saved revision once", async ({
  page,
}) => {
  await signed(page, "recorder");
  await page.getByRole("button", { name: "Manual games", exact: true }).click();
  const title = "TEST ONLY manual lost reply " + randomUUID().slice(0, 8);
  await page
    .getByRole("textbox", { name: "Opponent", exact: true })
    .fill(title);
  await page
    .getByRole("button", { name: "Create server game", exact: true })
    .click();
  await page.getByRole("button", { name: "Draft entry", exact: true }).click();
  await page
    .getByRole("button", { name: "Open my permitted draft", exact: true })
    .click();
  await page.getByLabel("Points", { exact: true }).fill("4");
  await page.getByLabel("Threes made", { exact: true }).fill("7");
  let writes = 0;
  await page.route(
    "**/rpc/stats_save_draft",
    async (route) => {
      const r = await route.fetch();
      expect(r.ok()).toBe(true);
      writes++;
      await route.abort("failed");
    },
    { times: 1 },
  );
  await page
    .getByRole("button", { name: "Save server draft", exact: true })
    .click();
  await expect(page.getByText(/Write result uncertain/)).toBeVisible();
  page.on("dialog", (d) => d.accept());
  await page.getByRole("button", { name: "Workspace", exact: true }).click();
  await page.getByRole("button", { name: "Shared team", exact: true }).click();
  await page
    .getByRole("combobox", { name: "Team", exact: true })
    .selectOption(fixture.team);
  await page
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await expect(page.getByText(/Write result uncertain/)).toBeVisible();
  await page
    .getByRole("button", { name: "Reload and reconcile", exact: true })
    .click();
  await expect(
    page.getByText(/Reconciled with the exact expected saved revision\/status/),
  ).toBeVisible();
  await expect(page.getByLabel("Points", { exact: true })).toHaveValue("4");
  await expect(page.getByLabel("Threes made", { exact: true })).toHaveValue(
    "7",
  );
  expect(writes).toBe(1);
  expect(
    await page.evaluate(() =>
      Object.keys(sessionStorage).filter((k) =>
        k.startsWith("teamstats-manual-pending:"),
      ),
    ),
  ).toEqual([]);
});

test("dirty shared navigation keeps editing when recovery storage is unavailable", async ({
  page,
}) => {
  await signed(page);
  const title = "TEST ONLY navigation " + randomUUID().slice(0, 8);
  await createShared(page, "practice", title);
  await page.evaluate(() => {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = function (k, v) {
      if (
        k.startsWith("teamstats-web-session-buffer:") &&
        !k.endsWith(":pending")
      )
        throw new DOMException("TEST ONLY storage unavailable");
      return original.call(this, k, v);
    };
  });
  await page
    .getByRole("textbox", {
      name: "Sets, rotations, baskets and collector responsibility",
      exact: true,
    })
    .fill("TEST ONLY only-in-memory input");
  await expect(page.getByText(/Browser recovery storage failed/)).toBeVisible();
  await expect(
    page.getByText("Unsaved browser entries", { exact: true }),
  ).toBeVisible();
  let prompts = 0;
  page.on("dialog", async (d) => {
    prompts++;
    await d.dismiss();
  });
  await page.getByRole("button", { name: "Workspace", exact: true }).click();
  expect(prompts).toBe(1);
  await expect(
    page.getByRole("textbox", {
      name: "Sets, rotations, baskets and collector responsibility",
      exact: true,
    }),
  ).toHaveValue("TEST ONLY only-in-memory input");
  await page.getByRole("button", { name: "Manual games", exact: true }).click();
  await expect(
    page.getByRole("textbox", {
      name: "Sets, rotations, baskets and collector responsibility",
      exact: true,
    }),
  ).toHaveValue("TEST ONLY only-in-memory input");
  expect(prompts).toBe(2);
});

test("actual SDK account switch and browser sign-out conceal the previous account workspace", async ({
  page,
}) => {
  test.skip(
    !fixture?.actors.switchviewer,
    "Requires a separate actual session for the existing synthetic viewer.",
  );
  await signed(page);
  const title = "TEST ONLY account boundary " + randomUUID().slice(0, 8);
  await createShared(page, "practice", title);
  const switched = await page.evaluate(
    async ({ url, key, session }) => {
      const { clientFor } = await import("/src/server.ts");
      const client = clientFor(url, key);
      const { error } = await client.auth.setSession({
        access_token: session.access_token,
        refresh_token: session.refresh_token,
      });
      return !error;
    },
    {
      url: fixture.apiRoot,
      key: fixture.publishableKey,
      session: fixture.actors.switchviewer.session,
    },
  );
  expect(switched).toBe(true);
  await expect(
    page.getByRole("combobox", { name: "Team", exact: true }),
  ).toHaveValue("");
  await expect(
    page.getByRole("heading", { name: title, exact: true }),
  ).toHaveCount(0);
  await page
    .getByRole("combobox", { name: "Team", exact: true })
    .selectOption(fixture.team);
  await expect(
    page.getByRole("button", {
      name: "Manage team",
      exact: true,
      includeHidden: true,
    }),
  ).toHaveCount(0);
  await page
    .getByRole("button", { name: "Practices & capture", exact: true })
    .click();
  await openShared(page, title);
  await expect(
    page.getByRole("heading", {
      name: "No permitted snapshot available",
      exact: true,
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", {
      name: "Save shared session draft",
      exact: true,
    }),
  ).toHaveCount(0);
  await page.locator(".account-details > summary").click();
  await page
    .getByRole("button", { name: "Sign out of this browser", exact: true })
    .click();
  await expect(
    page.getByRole("heading", {
      name: "Sign in to an existing account",
      exact: true,
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: title, exact: true }),
  ).toHaveCount(0);
});

for (const kind of ["practice", "game"] as const)
  test(
    "actual signed " +
      kind +
      " collection accepts all four frozen template kinds and type switching",
    async ({ page, browser }) => {
      await signed(page);
      const title =
        "TEST ONLY " + kind + " templates " + randomUUID().slice(0, 8);
      const session = await createShared(page, kind, title);
      const settings = page.getByText(
        "Recorder assignment and collection definitions",
        { exact: true },
      );
      await settings.click();
      for (const type of ["count", "makes", "timed", "note"]) {
        await page
          .getByRole("textbox", { name: "Name", exact: true })
          .fill("TEST ONLY " + type);
        await page
          .getByRole("combobox", { name: "Type", exact: true })
          .selectOption(type);
        await page
          .getByRole("textbox", { name: "Counting rule", exact: true })
          .fill(
            "TEST ONLY " + type + " observation rule, not a coaching protocol",
          );
        await page
          .getByRole("button", {
            name: "Add definition to this session draft",
            exact: true,
          })
          .click();
      }
      await page
        .getByRole("button", { name: "Save shared session draft", exact: true })
        .click();
      await expect(page.getByText(/Server confirmed save/)).toBeVisible();
      await assign(page);
      const recorder = await browser.newPage();
      await signed(recorder, "recorder");
      await openShared(recorder, title);
      if (kind === "practice")
        await recorder
          .getByRole("button", { name: "Collection", exact: true })
          .click();
      const chooser = recorder.getByRole("combobox", {
        name: kind === "practice" ? "Template" : "Event definition",
        exact: true,
      });
      const select = async (type: string) =>
        chooser.selectOption({
          label: "TEST ONLY " + type + (kind === "game" ? " · v1" : ""),
        });
      const add = async () => {
        await recorder
          .getByRole("button", {
            name:
              kind === "practice" ? "Add observation to draft" : "Record event",
            exact: true,
          })
          .click();
        if (kind === "game")
          await expect(
            recorder.getByText(/Server confirmed save/),
          ).toBeVisible();
      };
      await select("count");
      await recorder
        .getByLabel(kind === "practice" ? "Count" : "Observed count", {
          exact: true,
        })
        .fill("5");
      await select("makes");
      await recorder
        .getByLabel(kind === "practice" ? "Makes" : "Event makes", {
          exact: true,
        })
        .fill("1");
      await recorder
        .getByLabel(kind === "practice" ? "Attempts" : "Event attempts", {
          exact: true,
        })
        .fill("2");
      await add();
      await select("note");
      await recorder
        .getByRole(kind === "practice" ? "textbox" : "textbox", {
          name:
            kind === "practice"
              ? "Observation note"
              : "Counting rule / context",
          exact: true,
        })
        .fill("TEST ONLY note");
      await add();
      await select("timed");
      await recorder
        .getByLabel("Event time (seconds)", { exact: true })
        .fill("90");
      await add();
      await select("count");
      await recorder
        .getByLabel(kind === "practice" ? "Count" : "Observed count", {
          exact: true,
        })
        .fill("0");
      await add();
      if (kind === "practice") {
        await recorder
          .getByRole("button", {
            name: "Save shared session draft",
            exact: true,
          })
          .click();
        await expect(recorder.getByText(/Server confirmed save/)).toBeVisible();
      }
      const saved = await rpc("recorder", "web_session_state", {
        p_team_id: fixture.team,
        p_session_id: session,
      });
      const observations =
        kind === "practice"
          ? saved.document.session.observations
          : saved.document.session.changes.map(
              (c: { after: unknown }) => c.after,
            );
      expect(
        observations.map(
          (o: { template: { kind: string } }) => o.template.kind,
        ),
      ).toEqual(["makes", "note", "timed", "count"]);
      expect(observations.map((o: { values: unknown }) => o.values)).toEqual([
        { made: "1", attempts: "2" },
        {},
        { count: "90" },
        { count: "0" },
      ]);
      await shot(recorder, kind + "-shared-typed-collection");
      await recorder.close();
    },
  );

test("authorized manual correction review shows saved base versus proposal without losing zero or missing", async ({
  page,
  browser,
}) => {
  const gameID = randomUUID(),
    title = "TEST ONLY correction compare " + randomUUID().slice(0, 8);
  await rpc("recorder", "stats_create_game", {
    p_team_id: fixture.team,
    p_game_id: gameID,
    p_date: "2037-01-01",
    p_opponent: title,
    p_home_away: "home",
    p_game_type: "regularSeason",
  });
  let v = await rpc("recorder", "stats_open_draft", {
    p_team_id: fixture.team,
    p_game_id: gameID,
    p_dataset_type: "box_scores",
  });
  const values = Object.fromEntries(
    [
      "points",
      "offensiveRebounds",
      "defensiveRebounds",
      "assists",
      "turnovers",
      "steals",
      "blocks",
      "fouls",
      "chargesDrawn",
      "twosMade",
      "twosMissed",
      "threesMade",
      "threesMissed",
      "freeThrowsMade",
      "freeThrowsMissed",
    ].map((k) => [k, 0]),
  );
  v = await rpc("recorder", "stats_save_draft", {
    p_team_id: fixture.team,
    p_version_id: v.id,
    p_expected_revision: v.revision,
    p_records: fixture.roster.map((id: string) => ({
      gameID: gameID,
      playerID: id,
      values,
    })),
    p_covered_roster: fixture.roster.map((id: string) => ({ id, version: 1 })),
  });
  v = await rpc("recorder", "stats_complete", {
    p_team_id: fixture.team,
    p_version_id: v.id,
    p_expected_revision: v.revision,
    p_confirm_roster: true,
  });
  v = await rpc("recorder", "stats_submit", {
    p_team_id: fixture.team,
    p_version_id: v.id,
    p_expected_revision: v.revision,
  });
  await rpc("reviewer", "stats_review", {
    p_team_id: fixture.team,
    p_version_id: v.id,
    p_expected_revision: v.revision,
    p_approve: true,
    p_reason: "",
  });
  await signed(page, "recorder");
  await page.getByRole("button", { name: "Manual games", exact: true }).click();
  await page
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await page
    .getByRole("button", { name: "Review & history", exact: true })
    .click();
  page.on("dialog", (d) =>
    d.type() === "prompt"
      ? d.accept("TEST ONLY correction comparison")
      : d.accept(),
  );
  await page
    .getByRole("button", { name: "Request permission to edit", exact: true })
    .click();
  await expect(
    page.getByText("Edit request · pending", { exact: true }),
  ).toBeVisible();
  const reviewer = await browser.newPage();
  await signed(reviewer, "reviewer");
  await reviewer
    .getByRole("button", { name: "Manual games", exact: true })
    .click();
  await reviewer
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await reviewer
    .getByRole("button", { name: "Review & history", exact: true })
    .click();
  reviewer.on("dialog", (d) => d.accept());
  await reviewer
    .getByRole("button", { name: "Approve reopening", exact: true })
    .click();
  await expect(
    reviewer.getByText("Edit request · approved", { exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Back to shared games", exact: true })
    .click();
  await page
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await page
    .getByRole("button", { name: "Review & history", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Edit this draft", exact: true })
    .click();
  await page.getByLabel("Points", { exact: true }).fill("");
  await page.getByLabel("Assists", { exact: true }).fill("1");
  const savedResponse = page.waitForResponse((r) =>
    r.url().endsWith("/rpc/stats_save_draft"),
  );
  await page
    .getByRole("button", { name: "Save server draft", exact: true })
    .click();
  const response = await savedResponse;
  expect(response.ok()).toBe(true);
  const savedProposal = await response.json();
  await expect(page.getByText(/Server confirmed this operation/)).toBeVisible();
  await expect(reviewer.locator(".version-list > section")).toHaveCount(1);
  await page
    .getByText("Complete this independent dataset", { exact: true })
    .click();
  await page
    .getByRole("checkbox", {
      name: "I confirm this game and the covered real roster.",
      exact: true,
    })
    .check();
  await page
    .getByRole("button", { name: "Complete player box scores", exact: true })
    .click();
  await expect(page.getByText(/This version is frozen/)).toBeVisible();
  await page
    .getByRole("button", { name: "Review & history", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Submit for review", exact: true })
    .click();
  await expect(
    page.getByText("submitted · revision " + (savedProposal.revision + 2), {
      exact: true,
    }),
  ).toBeVisible();
  await reviewer
    .getByRole("button", { name: "Back to shared games", exact: true })
    .click();
  await reviewer
    .getByRole("button", { name: new RegExp("^" + title + " ") })
    .click();
  await reviewer
    .getByRole("button", { name: "Review & history", exact: true })
    .click();
  await expect(reviewer.locator(".version-list > section")).toHaveCount(2);
  const proposal = reviewer.locator(".version-list > section").filter({
    has: reviewer.getByRole("button", {
      name: "Accept & publish",
      exact: true,
    }),
  });
  await proposal
    .getByText("Review saved values and correction context", { exact: true })
    .click();
  const changes = proposal.getByRole("region", {
    name: "Correction changes",
    exact: true,
  });
  await expect(
    changes.getByRole("row").filter({
      has: reviewer.getByRole("cell", { name: "Points", exact: true }),
    }),
  ).toContainText("0Not entered");
  await expect(
    changes.getByRole("row").filter({
      has: reviewer.getByRole("cell", { name: "Assists", exact: true }),
    }),
  ).toContainText("01");
  await shot(reviewer, "desktop-authorized-correction-comparison");
  await reviewer.close();
});
