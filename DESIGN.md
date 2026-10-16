---
name: TeamStats
description: Native after-game statistics and team workspace
colors:
  accent-light: "#7A1F3D"
  accent-dark: "#E39BAD"
  filled-accent-dark: "#B4496B"
  error-light: "#B42318"
  error-dark: "#FF6961"
typography:
  game-title:
    fontFamily: "SwiftUI system"
  task-heading:
    fontFamily: "SwiftUI system"
  body:
    fontFamily: "SwiftUI system"
  supporting:
    fontFamily: "SwiftUI system"
spacing:
  close: "8pt"
  standard: "16pt"
  spacious: "24pt"
components:
  game-identity:
    typography: "{typography.game-title}"
  task-row:
    typography: "{typography.task-heading}"
  save-draft-light:
    backgroundColor: "{colors.accent-light}"
  save-draft-dark:
    backgroundColor: "{colors.filled-accent-dark}"
---

# Design System: TeamStats

## Overview

**Creative North Star: "The Game Ledger"**

TeamStats uses a recognizable game identity and a readable scorekeeper ledger. Native system surfaces hold the observations; provisional maroon marks navigation and useful actions. Real opponent, date and venue facts establish context before entry or inspection.

The interface uses system typography, purposeful SF Symbols, wrapping text and native forms, lists, sheets and toolbars. Local drafts and server-confirmed shared records remain visibly distinct. Missing observations, validation errors and save receipts are stated in words rather than inferred from styling.

**Key Characteristics:**

- Game identity before game tasks.
- Native text styles and adaptive semantic surfaces.
- Aligned numeric observations, with missing values kept visible.
- One calm scoring notice, with text and an informational icon.
- Task guidance is available without preceding every input.

This is a source-derived native record, not a web theme or release acceptance.
The canonical palette and ongoing accessibility evidence remain in
DESIGN_SYSTEM.md. Actual owner identity assets remain TODO_TEAM_LOGO,
TODO_APP_ICON and TODO_TEAM_ROSTER. No new raster assets were introduced.

## Colors

Provisional maroon is used sparingly against platform-controlled surfaces.
Frontmatter records the app-defined sRGB colors. Platform adaptive colors and
materials are deliberately not replaced with fixed light/dark hex guesses.

### Primary

- **Maroon accent:** the light accent and its brighter dark counterpart belong
  to AccentColor; they identify links, navigation and selected controls.
- **Filled maroon:** light uses the light accent; dark filled controls use the
  separate darker fill token so white native button labels remain legible.

### Neutral

- **Primary text and surfaces:** SwiftUI primary text and UIKit semantic grouped
  backgrounds follow system appearance and accessibility settings.
- **Supporting text:** TeamStatsStyle.secondaryText is primary at 75% opacity;
  it supports metadata and explicit missing-value prompts.
- **Section headings:** repaired Scoring and Rebounds headings use explicit
  Color.primary so inherited section-header styling does not dim them.

### Status

- **Entry discrepancies:** a restrained informational symbol and secondary supporting text identify a saveable draft inconsistency. Invalid numbers and failed operations retain actionable adaptive error text.
- **Warning and success:** existing system orange/green roles include text or
  icons. Neither these colors nor maroon establishes authority by itself.

**The State Is Written Rule.** Maroon identifies navigation and actions; explicit words establish draft, pending, saved and server-confirmed states.

## Typography

**Display Font:** no separate custom display face.
**Body Font:** the native SwiftUI system family.
**Label/Mono Font:** system text with monospaced digits where counts align.

### Hierarchy

- **Game identity:** title2 bold for opponent; wrapping subheadline for date,
  home/away and game kind; semibold subheadline for provenance.
- **Task headings:** headline titles with subheadline detail; purposeful title3
  SF Symbols are decorative to assistive reading when the text names the task.
- **Entry context:** headline opponent and caption date in the box-score editor.
- **Observations:** native body text, number-pad fields and monospaced digits.
- **Supporting copy:** subheadline, footnote and caption are selected by context;
  status and validation copy wrap rather than using a smaller fixed font.

No fixed point-size or line-height ramp is claimed: SwiftUI text styles and
Dynamic Type select their actual metrics. Table widths and guide measure use
ScaledMetric relative to body text.

**The Native Type Rule.** Use SwiftUI text styles and Dynamic Type; numeric observations may use monospaced digits without replacing the system text family.

## Layout

Games and entry screens begin with actual game context, then state and task.
Lists and forms provide native row grouping. Team navigation uses native
sidebar/detail adaptation rather than a custom responsive breakpoint scheme.

The reused spacing rhythm is the frontmatter scale; compact stacks also use
4-point spacing. Team task rows use a 16-point icon/text gap, 24-point icon
column, 8-point vertical padding and a 44-point minimum interactive area.

Box-score entry separates Scoring from Rebounds and contributions. Its header
is independently scrollable with a shrinkable200-point maximum. Mode controls
stay outside it, and native layout respects the keyboard and bottom Save area. The ledger table scrolls on both axes; scaled editing columns start at200 points and player identity at156 points;
read-only numeric columns start at76 points and player identity at164 points.
Both identity columns are capped at40% of the available width; text wraps rather
than covering every statistic.
Direct numeric entry shares a row with44-point counter targets. These are measured native points, not CSS pixel breakpoints.

Possession columns retain our team on the left and opponent on the right.
Native two-axis scrolling measures the overflow rather than intercepting
control gestures. Empty opposite cells do not imply possession records.

The guide uses a centered body-scaled reading measure starting at 640 points.
Save uses a bottom safe-area inset; ViewThatFits changes box-score status and
Save from a horizontal row to a vertical arrangement when needed. No fixed
warning height clips its text. Larger-text layouts still require rendered
acceptance in every affected state.

## Elevation & Depth

Native grouped surfaces, separators, sheet presentation and navigation establish
depth. The Save inset uses native regularMaterial, not a decorative glass-card
system. No reusable custom shadow scale was found or added.

**The Quiet Surface Rule.** Use native semantic surfaces and separators for grouping; decorative shadows and glass cards do not establish hierarchy.

## Shapes

Native rounded-border text fields and platform button/list/sheet shapes carry
the form language; no app-wide custom radius scale is defined. The existing
invalid-number outline uses a 5-point rounded rectangle, an error-specific
cue rather than a general container style. Courts and play markers are domain
content, not decorative motifs for unrelated screens.

## Components

### Game identity and task rows

GameIdentity wraps the factual opponent, metadata and local/shared provenance.
TeamTaskLabel combines a purposeful SF Symbol, headline and short detail with
one accessible task label and hint. Game-centered actions do not require an
administrative tool unless their permission itself is administrative.

### Numeric inputs and counters

Fields retain direct typing, explicit missing prompts and player/team/field
accessibility labels. Possession and player paint-touch counters use native
bordered plus/minus buttons with 44-point minimum targets. Disabled states
prevent unavailable adjustments; blank plus becomes 1 and decrementing 1 gives
explicit 0. The keyboard can be dismissed without saving or changing a value.

### Scoring discrepancy

One calm “Check scoring” notice above entry-mode controls identifies affected
players. Individual mode scopes it to the selected player; table mode includes
all affected players, with inline disclosure for multiple-player details. A small
info symbol, native headline and secondary supporting text avoid an urgent red
alert block. No modal, acknowledgment, focus move or explicit live announcement.
Exact mismatches and partial lower bounds remain distinct; discrepancies are
saveable, while invalid inputs and failed saves keep separate actionable feedback.
This2026-10-15 owner decision supersedes the older red-warning requirement.

### Save and recovery

Prominent Save draft uses the filled accent. Unsaved changes, Local draft and
Draft saved on this device are distinct receipts. Pending, unavailable and
failure states retain their appropriate recovery actions; a prior receipt does
not establish that new changes saved. Native Keep editing and explicit discard
choices protect unsaved navigation where offered.

### Guidance and navigation

Entry guidance uses DisclosureGroup. Using TeamStats is revisitable from local
Games and Account; its native List has bounded reading measure. Photo review is
a toolbar action in individual box-score entry and a per-player table action.
Libraries use task-specific labels for plays, clips, scouting PDFs and Hudl,
while protected server authority remains the condition for shared actions.

### Motion

Motion remains native and restrained. Authored movement playback has explicit
Play/Pause, a position slider and step controls; the Reduce Motion path uses
discrete steps. No reusable custom easing/duration scale governs app navigation.
Native AVKit playback controls retain their platform behavior.

## Do's and Don'ts

### Do:

- **Do** retain readable game identity and local/shared provenance before the task.
- **Do** use system text styles, flexible wrapping and at least 44-point interactive areas in modified controls.
- **Do** retain blank observations as visibly unentered and show validation with readable text.
- **Do** keep Save in a keyboard-aware native safe-area control and provide a keyboard dismissal action.
- **Do** keep policy and entry guidance accessible through native disclosure and revisitable help.
- **Do** inspect actual light/dark and accessibility-size layouts; source tokens alone are not acceptance.

### Don't:

- **Don’t** present provisional maroon values as an official school specification.
- **Don’t** use color alone to communicate a discrepancy, permission or successful save.
- **Don’t** invent logos, roster identities, statistics or approved policies.
- **Don’t** introduce decorative gradient heroes, glass cards, emoji headings, generic card grids or custom scrolling physics.
- **Don’t** silently replace missing observations with zeros or treat a local save as publication.
- **Don’t** inherit unresolved contrast or reachability findings as design rules.

**Not canonized:** whole-app rendered acceptance remains partial. Normal
synthetic phone/tablet entry and guide views were inspected; some maximum-text
Save and cold JSON readback evidence exists. The final maximum-text UI test
built successfully but was interrupted before its reopening assertion; the
current footer recapture and complete UI reopening are not accepted. Actual
landscape geometry, the unexplained native date-contrast audit,
photo Apply/Cancel, repeatable AVKit controls, VoiceOver, actual iOS 26.0 and
physical-device coverage remain separate gaps. A specific primary-color section
heading was repaired; that does not certify every element. Private comparisons
mix appearance and screenshot framing and are not pixel-identical regression
proof. None of these gaps is a design rule to inherit.

Source evidence: TeamStats/TeamStats/DesignSystem.swift, AccentColor.colorset,
ContentView.swift, BoxScore.swift, Possession.swift, PlayerPaintTouches.swift,
TeamStatsGuide.swift, TeamWorkspaceView.swift and PlaybookView.swift. Capture
locations, synthetic fixtures and provider configuration remain private.

## Approved native sports-ledger section —2026-10-15

The approved prototype's local game/header/read-only box-score/editor flow now
governs this bounded section. Use the maroon identity strip, dark matchup with
explicit light text, honest entered-data subtotal/coverage, local-draft status and
underlined section navigation. Saved read-only player rows expand supported stats
and independently collected paint totals; Edit opens the selected player's separate
unsaved draft. No score, roster, completion or publication is fabricated.

Compact read-only columns differ from comfortable counter/text entry. Native
horizontal indicators are hidden; vertical scrolling and indicators remain native.
Local tables keep player identity visible using observed native scroll geometry,
not custom gestures or synchronized scrollers. Fields keep player/stat labels,
Dynamic Type and bottom safe-area Save. Existing shared-box entry reuses the calm
notice/counters while preserving its server-confirmed workflow; unrelated screens
and the legacy full local summary retain their current presentation.
