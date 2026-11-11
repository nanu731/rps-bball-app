import { test, expect } from "@playwright/test";
import { mkdirSync } from "node:fs";
const evidence =
  process.env.TEAMSTATS_EVIDENCE ?? "../.scratch/teamstats-web/rendered-round2";
mkdirSync(evidence, { recursive: true });
async function demo(page: import("@playwright/test").Page) {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Try synthetic demo", exact: true })
    .click();
  await expect(
    page.getByText("SYNTHETIC DEMO · TEST ONLY", { exact: true }),
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
    .getByRole("button", { name: "Save browser draft", exact: true })
    .click();
  await expect(
    page.getByText("Saved in this browser’s separate synthetic demo ledger."),
  ).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/desktop-practice-shooting.png",
    fullPage: true,
  });
  await page.reload();
  await page
    .getByRole("button", { name: "Try synthetic demo", exact: true })
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
  await page.getByText("Set / correct clock", { exact: true }).click();
  await page.getByLabel("Period length (minutes)", { exact: true }).fill("8");
  await page
    .getByRole("button", { name: "Set stopped period", exact: true })
    .click();
  await page.getByRole("button", { name: "Start clock", exact: true }).click();
  await expect(
    page.getByText("Running on this browser", { exact: false }),
  ).toBeVisible();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: evidence + "/desktop-game-court-light.png",
    fullPage: true,
  });
  await page.getByRole("button", { name: "Stop clock", exact: true }).click();
  await page.reload();
  await page
    .getByRole("button", { name: "Try synthetic demo", exact: true })
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
  await page.getByRole("button", { name: "Manual entry", exact: true }).click();
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
    .getByRole("button", { name: "Save browser draft", exact: true })
    .click();
  await expect(
    page.getByText("Saved in this browser’s separate synthetic demo ledger."),
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
    .getByRole("button", { name: "Save browser draft", exact: true })
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
  await page.getByRole("button", { name: "Manual entry", exact: true }).click();
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
    .getByRole("button", { name: "Save browser draft", exact: true })
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
  await page.getByText("Set / correct clock", { exact: true }).click();
  await page.getByLabel("Period length (minutes)", { exact: true }).fill("8");
  await page
    .getByRole("button", { name: "Set stopped period", exact: true })
    .click();
  await page.getByRole("button", { name: "Start clock", exact: true }).click();
  await page.getByRole("button", { name: "Manual entry", exact: true }).click();
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
  await page.getByRole("button", { name: "Manual entry", exact: true }).click();
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
