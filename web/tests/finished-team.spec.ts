import { test, expect, type Page } from "@playwright/test";
import { readFileSync, existsSync, mkdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { dirname, join } from "node:path";
const path = process.env.TEAMSTATS_FINISHED_FIXTURE ?? "";
const fixture =
  path && existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : null;
const load = (name: string) =>
  JSON.parse(readFileSync(join(dirname(path), name), "utf8"));
test.use({ actionTimeout: 10000 });
test.skip(!fixture, "Requires private signed local synthetic team fixture.");
async function signed(
  page: Page,
  role: string,
  filesGateway = "http://127.0.0.1:55878",
) {
  if (
    !fixture?.syntheticOnly ||
    new URL(fixture.apiRoot).hostname !== "127.0.0.1"
  )
    throw Error("Synthetic loopback fixture required");
  await page.addInitScript(
    ({ f, role, filesGateway }) => {
      localStorage.setItem(
        "teamstats-web-public-config",
        JSON.stringify({
          url: f.apiRoot,
          key: f.publishableKey,
          filesGateway,
        }),
      );
      localStorage.setItem(
        "teamstats-web-auth:" + f.apiRoot,
        JSON.stringify(f.actors[role].session),
      );
    },
    { f: fixture, role, filesGateway },
  );
  await page.goto("/");
  await page.getByRole("button", { name: "Team", exact: true }).click();
  const summary = page
    .locator("summary")
    .filter({ hasText: "Account and team" });
  await expect(summary).toContainText("verified");
  if (
    !(await page
      .getByRole("combobox", { name: "Team", exact: true })
      .isVisible())
  )
    await summary.click();
  await page
    .getByRole("combobox", { name: "Team", exact: true })
    .selectOption(fixture.team);
  await expect(
    page.getByRole("button", { name: "Published results", exact: true }),
  ).toBeVisible();
}
async function plans() {
  const reply = await fetch(fixture.apiRoot + "/rest/v1/rpc/web_plan_list", {
    method: "POST",
    headers: {
      apikey: fixture.publishableKey,
      Authorization: "Bearer " + fixture.actors.player.session.access_token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_team_id: fixture.team,
      p_practice_id: load("plan-journey.local.json").practice,
    }),
  });
  if (!reply.ok) throw Error("Synthetic plan fixture read failed");
  return (await reply.json()) as { revision: number }[];
}
async function screenshot(page: Page, name: string) {
  const root = process.env.TEAMSTATS_EVIDENCE;
  if (root) {
    mkdirSync(root, { recursive: true });
    await page.screenshot({ path: join(root, name + ".png"), fullPage: true });
  }
}
test("player opens independently shared PDF and retained history without editing controls", async ({
  page,
}) => {
  const plan = load("plan-journey.local.json");
  const current = (await plans())[0].revision;
  await signed(page, "player");
  await page
    .getByRole("button", { name: "Practices & shots", exact: true })
    .click();
  await page.getByRole("button").filter({ hasText: plan.title }).click();
  const section = page.locator(".shared-practice-plan");
  await expect(
    section.getByRole("heading", { name: "Shared practice plan", exact: true }),
  ).toBeVisible();
  await expect(
    section.getByText("Current shared plan", { exact: false }),
  ).toBeVisible();
  await expect(
    section.getByText("Share a plan or upload a PDF", { exact: true }),
  ).toHaveCount(0);
  await section
    .getByRole("button", { name: "Open PDF version " + current, exact: true })
    .click();
  await expect(
    section.locator("iframe[title='Shared practice plan PDF']"),
  ).toHaveAttribute("src", /^blob:/);
  await section
    .locator("summary")
    .filter({ hasText: "Earlier shared plans" })
    .click();
  await section
    .getByRole("button", { name: "Open PDF version 2", exact: true })
    .click();
  await expect(
    section.getByText("TEST ONLY synthetic instructions", { exact: true }),
  ).toBeVisible();
  await screenshot(page, "player-retained-plan");
});
test("manager PDF upload lost reply reconciles after reload, shares once and preserves prior plans", async ({
  page,
}) => {
  const plan = load("plan-journey.local.json");
  const current = (await plans())[0].revision;
  await signed(page, "manager");
  await page
    .getByRole("button", { name: "Practices & shots", exact: true })
    .click();
  await page.getByRole("button").filter({ hasText: plan.title }).click();
  let section = page.locator(".shared-practice-plan");
  await section
    .locator("summary")
    .filter({ hasText: "Share a plan or upload a PDF" })
    .click();
  const uploadTitle = "TEST ONLY recovered PDF " + randomUUID().slice(0, 8);
  await section.getByLabel("PDF plan title", { exact: true }).fill(uploadTitle);
  await section
    .getByLabel("Practice plan PDF · maximum 5 MB", { exact: true })
    .setInputFiles(join(dirname(path), "../pdf-spike/fixtures/valid.pdf"));
  let intercepted = false;
  await page.route("http://127.0.0.1:55878/uploads/*", async (route) => {
    if (!intercepted && !route.request().url().endsWith("/reconcile")) {
      intercepted = true;
      await route.fetch();
      await route.abort("failed");
    } else await route.continue();
  });
  await section
    .getByRole("button", { name: "Upload PDF draft", exact: true })
    .click();
  await expect(section.getByText(/could not finish/)).toBeVisible();
  await page.reload();
  await signed(page, "manager");
  await page
    .getByRole("button", { name: "Practices & shots", exact: true })
    .click();
  await page.getByRole("button").filter({ hasText: plan.title }).click();
  section = page.locator(".shared-practice-plan");
  await section
    .locator("summary")
    .filter({ hasText: "Share a plan or upload a PDF" })
    .click();
  await section
    .getByRole("button", { name: "Check PDF upload status", exact: true })
    .click();
  const recovered = section
    .getByRole("region", { name: "Validated PDF draft", exact: true })
    .filter({
      has: page.getByRole("heading", { name: uploadTitle, exact: true }),
    });
  await expect(
    recovered.getByRole("button", { name: "Share validated PDF", exact: true }),
  ).toBeVisible();
  await recovered
    .getByRole("button", { name: "Share validated PDF", exact: true })
    .click();
  await expect(
    section.getByRole("button", {
      name: "Open PDF version " + (current + 1),
      exact: true,
    }),
  ).toBeVisible();
  await section
    .locator("summary")
    .filter({ hasText: "Earlier shared plans" })
    .click();
  await expect(
    section.getByRole("button", {
      name: "Open PDF version " + current,
      exact: true,
    }),
  ).toBeVisible();
  await screenshot(page, "manager-pdf-recovery");
});
for (const width of [390, 1024, 1440])
  test(`published season results preserve missingness and weighted ratios at ${width}px`, async ({
    page,
  }) => {
    const season = load("results-journey.local.json");
    await page.setViewportSize({ width, height: 950 });
    await page.emulateMedia({
      colorScheme: width === 1024 ? "dark" : "light",
      reducedMotion: "reduce",
    });
    await signed(page, "player");
    await page.getByRole("button", { name: "Season", exact: true }).click();
    await page
      .getByRole("combobox", { name: "Results season", exact: true })
      .selectOption(season.season);
    await expect(page.getByText("30.0%", { exact: true })).toBeVisible();
    const row = page.getByRole("row").filter({
      has: page.getByRole("rowheader", { name: "Assists", exact: true }),
    });
    await expect(row).toContainText("Entered-data subtotal");
    await expect(row).toContainText("1 of 2 games");
    await page
      .getByRole("combobox", { name: "Results player", exact: true })
      .selectOption(season.player);
    await expect(page.getByText("30.0%", { exact: true })).toBeVisible();
    if (width === 390)
      await page.addStyleTag({ content: "html {font-size:24px !important}" });
    await page
      .getByRole("heading", { name: "Shot charts", exact: true })
      .scrollIntoViewIfNeeded();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth),
    ).toBe(width);
    if (width === 390) {
      const ledger = page.getByRole("region", {
        name: "Published game and season totals",
        exact: true,
      });
      await page
        .getByRole("button", {
          name: "Scroll Published game and season totals right",
          exact: true,
        })
        .click();
      await expect
        .poll(() => ledger.evaluate((el) => el.scrollLeft))
        .toBeGreaterThan(0);
      expect(
        await ledger.evaluate((el) => getComputedStyle(el).scrollbarWidth),
      ).toBe("none");
    }
    await screenshot(page, "season-results-" + width);
  });

test("actual local Edge relay supports browser preflight and verified PDF viewing", async ({
  page,
}) => {
  const plan = load("plan-journey.local.json");
  const current = (await plans())[0].revision;
  await signed(
    page,
    "player",
    "http://127.0.0.1:55880/functions/v1/teamstats-files",
  );
  await page
    .getByRole("button", { name: "Practices & shots", exact: true })
    .click();
  await page.getByRole("button").filter({ hasText: plan.title }).click();
  await page
    .getByRole("button", { name: "Open PDF version " + current, exact: true })
    .click();
  await expect(
    page.locator("iframe[title='Shared practice plan PDF']"),
  ).toHaveAttribute("src", /^blob:/);
});
test("definite plan and upload refusals release pending controls without blind writes", async ({
  page,
}) => {
  const plan = load("plan-journey.local.json");
  await signed(page, "manager");
  await page
    .getByRole("button", { name: "Practices & shots", exact: true })
    .click();
  await page.getByRole("button").filter({ hasText: plan.title }).click();
  const section = page.locator(".shared-practice-plan");
  await section
    .locator("summary")
    .filter({ hasText: "Share a plan or upload a PDF" })
    .click();
  await page.route("**/rpc/web_plan_share", (r) =>
    r.fulfill({
      status: 409,
      contentType: "application/json",
      body: JSON.stringify({ code: "PT409" }),
    }),
  );
  await section
    .getByRole("button", { name: "Share saved builder plan", exact: true })
    .click();
  await expect(section.getByText(/changed elsewhere/)).toBeVisible();
  await expect(
    section.getByRole("button", {
      name: "Share saved builder plan",
      exact: true,
    }),
  ).toBeEnabled();
  await expect(
    section.getByRole("button", { name: "Retry same plan share", exact: true }),
  ).toHaveCount(0);
  await page.route("**/rpc/file_reserve", (r) =>
    r.fulfill({
      status: 409,
      contentType: "application/json",
      body: JSON.stringify({ code: "PT409" }),
    }),
  );
  await section
    .getByLabel("PDF plan title", { exact: true })
    .fill("TEST ONLY rejected reservation");
  await section
    .getByLabel("Practice plan PDF · maximum 5 MB", { exact: true })
    .setInputFiles(join(dirname(path), "../pdf-spike/fixtures/valid.pdf"));
  await section
    .getByRole("button", { name: "Upload PDF draft", exact: true })
    .click();
  await expect(
    section.getByLabel("PDF plan title", { exact: true }),
  ).toBeEnabled();
  await expect(
    section.getByRole("button", { name: "Upload PDF draft", exact: true }),
  ).toBeEnabled();
  await expect(
    section.getByRole("button", {
      name: "Check PDF upload status",
      exact: true,
    }),
  ).toHaveCount(0);
});
test("responsive sign-in has one rendered root and reachable primary action", async ({
  page,
}) => {
  await page.addInitScript(
    (f) =>
      localStorage.setItem(
        "teamstats-web-public-config",
        JSON.stringify({ url: f.apiRoot, key: f.publishableKey }),
      ),
    fixture,
  );
  await page.goto("/");
  await page.getByRole("button", { name: "Team", exact: true }).click();
  for (const width of [390, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({
      colorScheme: width === 1024 ? "dark" : "light",
      reducedMotion: "reduce",
    });
    await expect(page.locator(".sign-in-page")).toHaveCount(1);
    await expect(page.locator(".brand-header")).toHaveCount(1);
    const action = page
      .getByRole("button", { name: "Sign in", exact: true })
      .last();
    await action.scrollIntoViewIfNeeded();
    await expect(action).toBeVisible();
    await page.evaluate(() => window.scrollTo(0, 0));
    if (width === 390)
      expect(
        (await action.boundingBox())!.y + (await action.boundingBox())!.height,
      ).toBeLessThanOrEqual(844);
    expect(
      await page
        .locator(".skip")
        .evaluate((el) => el.getBoundingClientRect().bottom),
    ).toBeLessThanOrEqual(0);
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth),
    ).toBe(width);
    await screenshot(page, "final-signin-" + width);
    if (process.env.TEAMSTATS_EVIDENCE)
      await page.screenshot({
        path: join(
          process.env.TEAMSTATS_EVIDENCE,
          `signin-viewport-${width}.png`,
        ),
        fullPage: false,
      });
  }
});

test("confirmed absent pre-storage upload releases controls and starts a fresh operation without deleting history", async ({
  page,
}) => {
  const plan = load("plan-journey.local.json");
  await signed(page, "manager");
  await page
    .getByRole("button", { name: "Practices & shots", exact: true })
    .click();
  await page.getByRole("button").filter({ hasText: plan.title }).click();
  const section = page.locator(".shared-practice-plan");
  await section
    .locator("summary")
    .filter({ hasText: "Share a plan or upload a PDF" })
    .click();
  await section
    .getByLabel("PDF plan title", { exact: true })
    .fill("TEST ONLY interrupted before Storage " + randomUUID().slice(0, 8));
  await section
    .getByLabel("Practice plan PDF · maximum 5 MB", { exact: true })
    .setInputFiles(join(dirname(path), "../pdf-spike/fixtures/valid.pdf"));
  let interrupted = true;
  const operations: string[] = [];
  page.on("request", (request) => {
    if (request.url().endsWith("/rpc/file_reserve"))
      operations.push(request.postDataJSON().p_operation_id);
  });
  await page.route("http://127.0.0.1:55878/uploads/*", async (route) => {
    if (interrupted && !route.request().url().endsWith("/reconcile")) {
      interrupted = false;
      await route.abort("failed");
    } else await route.continue();
  });
  await section
    .getByRole("button", { name: "Upload PDF draft", exact: true })
    .click();
  await expect(
    section.getByRole("button", {
      name: "Check PDF upload status",
      exact: true,
    }),
  ).toBeVisible();
  await section
    .getByRole("button", { name: "Check PDF upload status", exact: true })
    .click();
  await expect(section.getByText(/confirmed absent/)).toBeVisible();
  await expect(
    section.getByRole("button", { name: "Upload PDF draft", exact: true }),
  ).toBeEnabled();
  await section
    .getByRole("button", { name: "Upload PDF draft", exact: true })
    .click();
  await expect(
    section
      .getByRole("region", { name: "Validated PDF draft", exact: true })
      .filter({ hasText: /TEST ONLY interrupted before Storage/ })
      .getByRole("button", { name: "Share validated PDF", exact: true }),
  ).toBeVisible();
  expect(operations.length).toBe(2);
  expect(operations[0]).not.toBe(operations[1]);
  const query =
    fixture.apiRoot +
    "/rest/v1/file_resource_versions?select=operation_id,status&operation_id=in.(" +
    operations.join(",") +
    ")";
  const response = await fetch(query, {
    headers: {
      apikey: fixture.publishableKey,
      Authorization: "Bearer " + fixture.actors.manager.session.access_token,
    },
  });
  expect(response.ok).toBe(true);
  const rows = await response.json();
  expect(rows.length).toBe(2);
  expect(
    rows.find((r: { operation_id: string }) => r.operation_id === operations[0])
      .status,
  ).toBe("uploading");
  expect(
    rows.find((r: { operation_id: string }) => r.operation_id === operations[1])
      .status,
  ).toBe("ready");
});

test("unconfirmed season creation retains its identity across navigation until authoritative readback", async ({
  page,
}) => {
  await signed(page, "owner");
  await page.locator("summary").filter({ hasText: "Season setup" }).click();
  const name = "TEST ONLY season recovery " + randomUUID().slice(0, 8);
  await page.getByLabel("Season name", { exact: true }).fill(name);
  let seasonID = "";
  let writes = 0;
  await page.route("**/rpc/team_save_season", async (route) => {
    writes++;
    seasonID = route.request().postDataJSON().p_season_id;
    if (writes === 1) {
      await route.fetch();
      await route.abort("failed");
    } else await route.continue();
  });
  await page
    .getByRole("button", { name: "Create season", exact: true })
    .click();
  await expect(
    page.getByText(/This setup change is unconfirmed/),
  ).toBeVisible();
  await page.route("**/web_seasons?*", (route) =>
    route.fulfill({
      status: 500,
      contentType: "application/json",
      body: JSON.stringify({ code: "SYNTHETIC_OFFLINE" }),
    }),
  );
  await page
    .getByRole("button", { name: "Practices & shots", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Published results", exact: true })
    .click();
  await page.locator("summary").filter({ hasText: "Season setup" }).click();
  await page.getByLabel("Season name", { exact: true }).fill(name);
  await expect(
    page.getByRole("button", { name: "Create season", exact: true }),
  ).toBeDisabled();
  await page
    .getByRole("button", { name: "Retry same setup request", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Retry same setup request", exact: true }),
  ).toBeEnabled();
  await expect(
    page.getByRole("button", { name: "Create season", exact: true }),
  ).toBeDisabled();
  await page.unroute("**/web_seasons?*");
  await page
    .getByRole("button", { name: "Check season setup", exact: true })
    .click();
  await expect(page.getByLabel("Season name", { exact: true })).toHaveValue("");
  expect(writes).toBe(2);
  const query =
    fixture.apiRoot +
    "/rest/v1/web_seasons?select=id&team_id=eq." +
    fixture.team +
    "&name=eq." +
    encodeURIComponent(name);
  const read = await fetch(query, {
    headers: {
      apikey: fixture.publishableKey,
      Authorization: "Bearer " + fixture.actors.owner.session.access_token,
    },
  });
  expect(read.ok).toBe(true);
  expect(await read.json()).toEqual([{ id: seasonID }]);
});
