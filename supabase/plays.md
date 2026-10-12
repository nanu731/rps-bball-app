# Reviewed team plays

Apply migration `202610110004_play_versions.sql` after migrations 001–003. It does
not read, convert or upload existing local JSON/temporary players. Play markers
are user-authored numbered diagram roles with stable UUIDs, optional labels,
normalized half-court coordinates and ordered movement steps.

`plays` holds the stable play identity and accepted pointer. `play_versions` holds
private editable drafts and frozen submitted/rejected/published revisions. Members
see accepted history; authors see their own drafts/proposals; `plays.review`
reviewers see submitted/rejected proposals. Protected direct writes are denied.

Authenticated commands recheck verified live sessions, active membership and
current capability grants while serialized on the team:

- `play_open_draft(team, play, source?)`: requires `plays.author`; stable opening
  retries return the same author draft. A correction clones the current published
  revision or an author's rejected proposal into a fresh draft, preserving marker
  identities. Previously accepted data stays intact.
- `play_save_draft(team, version, expected_revision, title, diagram)`: requires
  the current author's draft and author capability. Partial empty diagrams can be
  saved; invalid geometry/identity/durations are rejected. No implicit correction.
- `play_transition(team, version, expected_revision, action, reason?)`: `submit`
  freezes an author's draft for review; `publish` requires the author's separate
  `plays.publish` bypass; `approve`/`reject` require `plays.review` and an independent
  reviewer (owner exception). Submit/publication needs a nonblank name, at least
  one marker and one movement step. Rejected proposals stay immutable and may be
  cloned into a new draft.

Every save/transition checks both expected revision and current accepted base.
Conflicts return SQLSTATE `40001`; denied access `42501`; invalid inputs `22023`
(or UUID parse `22P02`). The native model never automatically repeats a POST and
requires reload after uncertain mutations. Audit events are append-only. A 1 MiB
request bound and 0.1–30 second step durations protect playback/resource handling;
these are engineering limits, not invented basketball collection limits.

Native `PlaybookView(account:teamID:)` uses real Supabase Swift commands and native
scrolling/forms. Dragging follows the finger; marker selection and coordinate
sliders provide an alternative to dragging. Playback computes positions from the
saved sequence, supports play/pause/replay/step/scrub, and uses discrete positions
with Reduce Motion. It never invents trajectories beyond linear authored segments.

Verification: a Foundation geometry tracer failed before validation, then passed
finite/range rejection, authored midpoint and reduced-motion placement. All 54
actual local PostgreSQL pgTAP command/RLS/lifecycle checks passed using rollback
synthetic fixtures. Native SDK transport fixture tests and live iPhone/iPad editor,
playback, keyboard/Save, larger text and VoiceOver checks require integration.
Hosted provider configuration and physical devices remain unverified.
