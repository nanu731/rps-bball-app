import { test, expect } from "@playwright/test";
import { demoLedger, id, recordChange } from "../src/domain.ts";
import type { Capture, Template } from "../src/domain.ts";
test("event correction retains its original rule; switching template kinds clears incompatible values", async ({
  page,
}) => {
  const db = demoLedger();
  const game = db.sessions.find((s) => s.kind === "game")!;
  const original: Template = {
    id: id(),
    name: "TEST ONLY count",
    kind: "count",
    definition: "TEST ONLY original observed rule",
    version: 1,
  };
  const makes: Template = {
    id: id(),
    name: "TEST ONLY makes",
    kind: "makes",
    definition: "TEST ONLY makes and attempts",
    version: 1,
  };
  const note: Template = {
    id: id(),
    name: "TEST ONLY note",
    kind: "note",
    definition: "TEST ONLY observation note",
    version: 1,
  };
  db.templates = [
    { ...original, definition: "TEST ONLY changed future rule", version: 2 },
    makes,
    note,
  ];
  const event: Capture = {
    id: id(),
    team: "ours",
    playerID: game.players[0].id,
    kind: "event",
    value: 2,
    made: null,
    x: null,
    y: null,
    label: original.name,
    note: "TEST ONLY original context",
    at: "2037-01-01T12:00:00Z",
    period: "TEST ONLY P1",
    clock: 60,
    template: original,
    values: { count: "1" },
  };
  game.changes = recordChange([], event);
  await page.addInitScript(
    (db) => localStorage.setItem("teamstats.web.demo.v1", JSON.stringify(db)),
    db,
  );
  await page.goto("/");
  await page.getByRole("button", { name: "My drafts", exact: true }).click();
  await page
    .getByRole("button", { name: "Try sample demo", exact: true })
    .click();
  await page.getByRole("button", { name: /TEST ONLY opponent/ }).click();
  await page.getByRole("button", { name: "Correct", exact: true }).click();
  await expect(
    page.getByText("TEST ONLY original observed rule · definition v1", {
      exact: true,
    }),
  ).toBeVisible();
  await expect(
    page.getByRole("combobox", { name: "What to track", exact: true }),
  ).toBeDisabled();
  await page.getByLabel("Observed count", { exact: true }).fill("2");
  await page.getByRole("button", { name: "Record event", exact: true }).click();
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          JSON.parse(
            localStorage.getItem("teamstats.web.demo.v1")!,
          ).sessions.find((s: { kind: string }) => s.kind === "game").changes
            .length,
      ),
    )
    .toBe(2);
  const corrected = await page.evaluate(
    () =>
      JSON.parse(localStorage.getItem("teamstats.web.demo.v1")!).sessions.find(
        (s: { kind: string }) => s.kind === "game",
      ).changes,
  );
  expect(corrected[1].after.template).toEqual(original);
  expect(corrected[1].after.values).toEqual({ count: "2" });
  expect(corrected[1].after.at).toBe(event.at);
  await page
    .getByRole("combobox", { name: "What to track", exact: true })
    .selectOption(makes.id);
  await page.getByLabel("Event makes", { exact: true }).fill("1");
  await page.getByLabel("Event attempts", { exact: true }).fill("2");
  await page.getByRole("button", { name: "Record event", exact: true }).click();
  await page
    .getByRole("combobox", { name: "What to track", exact: true })
    .selectOption(note.id);
  await page
    .getByLabel("What counts? / note", { exact: true })
    .fill("TEST ONLY note");
  await page.getByRole("button", { name: "Record event", exact: true }).click();
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          JSON.parse(
            localStorage.getItem("teamstats.web.demo.v1")!,
          ).sessions.find((s: { kind: string }) => s.kind === "game").changes
            .length,
      ),
    )
    .toBe(4);
  const changes = await page.evaluate(
    () =>
      JSON.parse(localStorage.getItem("teamstats.web.demo.v1")!).sessions.find(
        (s: { kind: string }) => s.kind === "game",
      ).changes,
  );
  expect(changes[2].after.values).toEqual({ made: "1", attempts: "2" });
  expect(changes[3].after.values).toEqual({});
});
