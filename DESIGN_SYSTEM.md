# TeamStats native design system

Rutgers Prep maroon is owner-confirmed. These provisional sRGB values are our
accessible implementation palette, not an official school hex specification.
Logo: `TODO_TEAM_LOGO`; final icon: `TODO_APP_ICON`; actual roster: `TODO_TEAM_ROSTER`.

| Semantic role | Light | Dark | Use |
|---|---|---|---|
| Primary accent | #7A1F3D | #E39BAD | AccentColor asset; links, navigation, selected controls |
| Filled accent | #7A1F3D | #B4496B | TeamStatsStyle.filledAccent; prominent buttons/switches with white labels |
| Surfaces/text | System semantic colors | System semantic colors | Native lists/forms, primary/secondary text; avoid maroon backgrounds everywhere |
| Error/warning/success | System red/orange/green plus text/icon | Same semantic roles | Brand color never establishes a validation or permission state |

Calculated WCAG sRGB contrast: light accent against white10.04:1; dark text accent
against #1C1C1E7.74:1; white against dark filled accent5.11:1. Dark filled accent
against #1C1C1E3.33:1. These sample pairs are arithmetic evidence, not rendered
acceptance for every system material/disabled state. Appearance inspection remains
required. The brighter dark text accent must not fill white-label buttons.

Use system text styles/Dynamic Type, monospaced digits for aligned counts and
labels naming the player/team/field. Modified screens use8/16/24-point spacing,
minimum44-point controls and flexible wrapping. Keep table scrolling and keyboard
Save safe; no fixed-height warning block that hides inputs. Native forms, lists,
sheets, alerts, toolbars and purposeful SF Symbols carry hierarchy. iPad uses
sidebar/detail where useful and bounded readable text; narrow windows adapt.

Pending shows progress and freezes affected inputs; a server reply alone confirms
permission/completion/review/publication. Duplicate taps must not duplicate writes.
Failures retain recoverable input with plain errors/Retry; confirmed denial hides
protected content. Dirty navigation offers Keep editing/explicit discard. Loading,
empty, pending admission and errors have distinct next actions.

Motion remains native/restrained, respecting Reduce Motion. No decorative glass
cards, gradients, emoji headings, web components, invented branding or chart
conclusions. Existing legacy spacing and all representative screens remain in the
final visual audit; the palette change alone is not visual acceptance.

Routine team tasks must be available outside administrative tools. Account holds
sign-in/configuration; owner/delegate controls stay protected. Local drafts remain
visibly separate from official shared games. Clip downloads are optional; already
delivered copies cannot reliably be recalled, while future remote access checks
current authority. Full films open Hudl independently, never upload here.

Baseline: [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
[layout](https://developer.apple.com/design/human-interface-guidelines/layout), and
[split views](https://developer.apple.com/design/human-interface-guidelines/split-views).
Installed apple-design, ui-ux-pro-max SwiftUI and design-system guidance are adapted
to native platform controls; conflicting web recommendations are excluded.

Representative local visual acceptance at source4da97b6: both26.4 device families
rendered readable maroon/system light/dark screens; five preferred-text increments
and settled landscape captures inspected. iPhone native scrolling reached large-text
form footer; iPad keyboard-visible new-game Save passed. These limited local views
do not accept every entry/Team/player/PDF screen or VoiceOver/Reduce Motion. Unreliable
app-control automation requires the recorded manual checks; no visual redesign was
inferred from an input-tool failure. Screenshots remain private.
