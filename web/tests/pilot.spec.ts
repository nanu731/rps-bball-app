import { test, expect } from "@playwright/test";
import { mkdirSync } from "node:fs";
const evidence =
  process.env.TEAMSTATS_EVIDENCE ?? "../.scratch/teamstats-web/rendered-round2";
mkdirSync(evidence, { recursive: true });
async function demo(page: import("@playwright/test").Page) {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Try sample demo", exact: true })
    .click();
  await expect(
    page.getByText("SAMPLE DEMO · TEST ONLY", { exact: true }),
  ).toBeVisible();
}

test("practice station collection, missing versus zero, save/reopen and plan PDF", async ({
  page,
}) => {
  await demo(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/desktop-workspace-light.png",
    fullPage: true,
  });
  await page
    .getByRole("button", { name: /TEST ONLY shooting practice/ })
    .click();
  await expect(
    page.getByRole("heading", { name: "Practice plan", exact: true }),
  ).toBeVisible();
  await page.pdf({
    path: evidence + "/synthetic-practice-plan.pdf",
    format: "A4",
    printBackground: true,
  });
  await page.getByRole("button", { name: "Shooting", exact: true }).click();
  await page.getByLabel("Spot 1 makes", { exact: true }).fill("0");
  await page.getByLabel("Spot 1 attempts", { exact: true }).fill("0");
  await page
    .getByRole("button", { name: "Save in this browser", exact: true })
    .click();
  await expect(
    page.getByText("Sample data saved in this browser only."),
  ).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/desktop-practice-shooting.png",
    fullPage: true,
  });
  await page.reload();
  await page
    .getByRole("button", { name: "Try sample demo", exact: true })
    .click();
  await page
    .getByRole("button", { name: /TEST ONLY shooting practice/ })
    .click();
  await page.getByRole("button", { name: "Shooting", exact: true }).click();
  await expect(page.getByLabel("Spot 1 makes", { exact: true })).toHaveValue(
    "0",
  );
  await expect(page.getByLabel("Spot 2 makes", { exact: true })).toHaveValue(
    "",
  );
});

test("court locations automatically select shot value, with manual override and explicit recording", async ({
  page,
}) => {
  await demo(page);
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  const court = page.getByRole("img", { name: /Schematic court/ });
  const two = page.getByRole("button", { name: "2 points", exact: true });
  const three = page.getByRole("button", { name: "3 points", exact: true });
  const observations = page.locator(".observation");
  const before = await observations.count();
  for (const width of [390, 1024]) {
    await page.setViewportSize({ width, height: 1000 });
    const bounds = (await court.boundingBox())!;
    for (const [x, y, value] of [
      [250, 250, 2],
      [250, 350, 3],
      [20, 50, 3],
      [50, 50, 2],
      [480, 50, 3],
    ]) {
      await court.click({
        position: { x: (bounds.width * x) / 500, y: (bounds.height * y) / 420 },
      });
      await expect(value === 2 ? two : three).toHaveAttribute(
        "aria-pressed",
        "true",
      );
      await expect(observations).toHaveCount(before);
    }
  }
  await two.click();
  await expect(two).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "Make", exact: true }).click();
  await expect(
    page.getByText("TEST ONLY Player A · 2PT make", { exact: true }),
  ).toBeVisible();
  await expect(observations).toHaveCount(before + 1);
  await page
    .getByText("Choose location with keyboard", { exact: true })
    .click();
  await page
    .getByRole("button", { name: "Select center location", exact: true })
    .click();
  await expect(two).toHaveAttribute("aria-pressed", "true");
  await page.getByLabel("Horizontal location (%)", { exact: true }).fill("0");
  await expect(three).toHaveAttribute("aria-pressed", "true");
  await expect(observations).toHaveCount(before + 1);
});

test("game court provisional selection, explicit value, FT, correction Undo and running clock", async ({
  page,
}) => {
  await demo(page);
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await expect(
    page.getByRole("button", { name: "Make", exact: true }),
  ).toBeDisabled();
  await page
    .getByRole("img", { name: /Schematic court/ })
    .click({ position: { x: 120, y: 150 } });
  await page.getByRole("button", { name: "3 points", exact: true }).click();
  await page.getByRole("button", { name: "Make", exact: true }).click();
  await expect(
    page.getByText("TEST ONLY Player A · 3PT make", { exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "FT miss", exact: true }).click();
  await expect(
    page.getByText("TEST ONLY Player A · FT miss", { exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Undo last change", exact: true })
    .click();
  await expect(
    page.getByText("TEST ONLY Player A · FT miss", { exact: true }),
  ).toHaveCount(0);
  await page.getByText("Set game clock", { exact: true }).click();
  const period = page.getByRole("combobox", { name: "Period", exact: true });
  await expect(period.locator("option")).toHaveText([
    "Quarter 1",
    "Quarter 2",
    "Quarter 3",
    "Quarter 4",
    "Overtime",
  ]);
  await period.selectOption("Quarter 3");
  await page.getByLabel("Period length (minutes)", { exact: true }).fill("8");
  await page
    .getByRole("button", { name: "Set stopped period", exact: true })
    .click();
  await expect(
    page.getByText("Quarter 3 · manager reference", { exact: true }),
  ).toBeVisible();
  await page.getByText("Set game clock", { exact: true }).click();
  await period.selectOption("Overtime");
  await page
    .getByRole("button", { name: "Set stopped period", exact: true })
    .click();
  await expect(
    page.getByText("Overtime · manager reference", { exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Start clock", exact: true }).click();
  await expect(
    page.getByText("Running in this browser", { exact: false }),
  ).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/desktop-game-court-light.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Stop clock", exact: true }).click();
  await page.reload();
  await page
    .getByRole("button", { name: "Try sample demo", exact: true })
    .click();
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await expect(
    page.getByText("TEST ONLY Player A · 3PT make", { exact: true }),
  ).toBeVisible();
});

test("manual modes share draft, calm scoring does not block Save, independent paired counts", async ({
  page,
}) => {
  await demo(page);
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await page
    .getByRole("button", { name: "After-game stats", exact: true })
    .click();
  await page.getByLabel("Points", { exact: true }).fill("4");
  await page.getByLabel("Threes made", { exact: true }).fill("7");
  await expect(page.getByText("Check scoring", { exact: true })).toBeVisible();
  await expect(
    page.getByText(
      "TEST ONLY Player A: Entered 4; made baskets imply at least 21.",
    ),
  ).toBeVisible();
  await page.getByRole("button", { name: "Roster table", exact: true }).click();
  await expect(
    page.getByLabel("TEST ONLY Player A Points", { exact: true }),
  ).toHaveValue("4");
  await page
    .getByRole("button", { name: "Save in this browser", exact: true })
    .click();
  await expect(
    page.getByText("Sample data saved in this browser only."),
  ).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/desktop-manual-table.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Possessions", exact: true }).click();
  await page
    .getByRole("button", { name: "Add next our-team possession", exact: true })
    .click();
  await expect(
    page.getByText("1 records entered", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText("0 records entered", { exact: true }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Save in this browser", exact: true })
    .click();
});

test("responsive phone/tablet, dark, reduced motion and accessible scrolling render evidence", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await demo(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/phone-workspace-light.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/phone-game-court-light.png",
    fullPage: true,
  });
  await page
    .getByRole("button", { name: "After-game stats", exact: true })
    .click();
  await page.getByLabel("Points", { exact: true }).fill("4");
  await page.getByLabel("Threes made", { exact: true }).fill("7");
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/phone-manual-warning.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Roster table", exact: true }).click();
  await page
    .getByRole("button", { name: "Scroll Box-score roster right" })
    .click();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/phone-manual-far-right.png",
    fullPage: true,
  });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(
    390,
  );
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/tablet-manual-dark-reduced-motion.png",
    fullPage: true,
  });
  await page
    .getByRole("button", { name: "Save in this browser", exact: true })
    .click();
  await page.getByRole("button", { name: "Court", exact: true }).click();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/tablet-game-dark.png",
    fullPage: true,
  });
});

test("clock stop persists despite unrelated invalid manual input; capture selection survives tabs", async ({
  page,
}) => {
  await demo(page);
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await page
    .getByRole("group", { name: "Quick player selection" })
    .getByRole("button", { name: /#1/ })
    .click();
  await page.getByRole("button", { name: "3 points", exact: true }).click();
  await page.getByText("Set game clock", { exact: true }).click();
  await page.getByLabel("Period length (minutes)", { exact: true }).fill("8");
  await page
    .getByRole("button", { name: "Set stopped period", exact: true })
    .click();
  await page.getByRole("button", { name: "Start clock", exact: true }).click();
  await page
    .getByRole("button", { name: "After-game stats", exact: true })
    .click();
  await page.getByLabel("Points", { exact: true }).fill("-1");
  await page.getByRole("button", { name: "Court", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "3 points", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(
    page
      .getByRole("group", { name: "Quick player selection" })
      .getByRole("button", { name: /#1/ }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "Stop clock", exact: true }).click();
  await expect(
    page.getByText("Stopped · not the official scoreboard", { exact: false }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "After-game stats", exact: true })
    .click();
  await expect(page.getByLabel("Points", { exact: true })).toHaveValue("-1");
  const stored = await page.evaluate(() =>
    JSON.parse(localStorage.getItem("teamstats.web.demo.v1")!),
  );
  expect(
    stored.sessions.find((s: { kind: string }) => s.kind === "game").clock
      .startedAt,
  ).toBeNull();
  expect(
    stored.sessions.find((s: { kind: string }) => s.kind === "game").manual.box,
  ).toEqual({});
});

test("same browser tabs cannot both overwrite one base revision", async ({
  page,
  context,
}) => {
  await page.goto("/");
  const second = await context.newPage();
  await second.goto("/");
  for (const p of [page, second]) {
    await p.getByRole("button", { name: "Add game", exact: true }).click();
    await p
      .getByLabel("Opponent", { exact: true })
      .fill(p === page ? "TEST ONLY first tab" : "TEST ONLY second tab");
  }
  await Promise.all([
    page
      .getByRole("button", { name: "Create game draft", exact: true })
      .click(),
    second
      .getByRole("button", { name: "Create game draft", exact: true })
      .click(),
  ]);
  await expect
    .poll(async () => {
      const rejected = await Promise.all(
        [page, second].map((p) => p.getByRole("alert").count()),
      );
      return rejected.some((n) => n > 0);
    })
    .toBe(true);
  const saved = await page.evaluate(() =>
    JSON.parse(localStorage.getItem("teamstats.web.local.v1")!),
  );
  expect(saved.sessions).toHaveLength(1);
  expect(saved.revision).toBe(1);
});

test("task wording separates browser drafts, team sign-in and advanced owner settings", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "My drafts", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText("ONLY IN THIS BROWSER", { exact: true }),
  ).toBeVisible();
  await expect(page.locator("main")).not.toContainText(
    /ledger|revision|authoritative|RPC|JWT/,
  );
  await page.getByRole("button", { name: "Team", exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await expect(page.getByText("TEAM WORKSPACE", { exact: true })).toBeVisible();
  await expect(
    page.getByText("Backups below contain My drafts only, not team entries.", {
      exact: true,
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("textbox", { name: "Project URL", exact: true }),
  ).not.toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByText("Owner connection settings", { exact: true }).click();
  await expect(
    page.getByRole("textbox", { name: "Project URL", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: evidence + "/phone-owner-connection.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Settings", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Stat-tracking templates", exact: true }),
  ).toBeVisible();
  await expect(page.locator("main")).not.toContainText(
    /stable local identity|authoritative|TODO_/,
  );
  await page.screenshot({
    path: evidence + "/phone-draft-settings.png",
    fullPage: true,
  });
});

test("unreadable browser drafts show a recovery action without echoing private contents or an empty state", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const broken = '{"private fixture contents"';
  await page.addInitScript(
    (raw) => localStorage.setItem("teamstats.web.local.v1", raw),
    broken,
  );
  await page.goto("/");
  await expect(page.getByRole("alert")).toContainText(
    "Your saved drafts could not be opened. Nothing was overwritten.",
  );
  await expect(page.getByRole("alert")).not.toContainText("private fixture");
  await expect(
    page.getByRole("button", {
      name: "Download unreadable backup",
      exact: true,
    }),
  ).toBeVisible();
  await expect(
    page.getByText("Your next session starts here", { exact: true }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "Retry load", exact: true }).click();
  expect(
    await page.evaluate(() => localStorage.getItem("teamstats.web.local.v1")),
  ).toBe(broken);
  await page.screenshot({
    path: evidence + "/phone-unreadable-draft-recovery.png",
    fullPage: true,
  });
});
