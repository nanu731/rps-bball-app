# TeamStats product context

Confirmed requirements live in PRD.md; PROJECT_CONTEXT.md records implementation evidence.
This short native-design context does not replace either document.

TeamStats helps a high school basketball team collect statistics after games,
review shared datasets, and find approved plays, practice clips, scouting PDFs
and authorized Hudl shortcuts. Owner amendment2026-10-17 also authorizes a planned
in-app iPad-first shot recorder for both teams, including side-panel free throws.
It is not implemented yet. This is the only exception to earlier no-live-tracking
rules; existing box-score/possession/paint-touch entry stays after-game. Read
PRD.md's shot-recorder amendment and ADR0007 before work on capture or charts.

iPhone and iPad use native SwiftUI, system typography, Dynamic Type and restrained
motion. Local incomplete drafts and temporary identities remain device-local;
Supabase confirms shared authority, review and publication. Missing inputs are
not zeros. Google Sheets is one-way output, never the source of authority.

Use DESIGN_SYSTEM.md's provisional maroon palette and native semantic surfaces.
No decorative glass, gradients, generic card grids or invented team assets.
Official color, logo, roster, privacy/legal content and distribution remain owner TODOs.
The budget is strictly $0; unavailable hosted delivery stays disabled.
