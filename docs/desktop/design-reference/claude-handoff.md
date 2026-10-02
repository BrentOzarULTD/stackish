> Archived third-party design proposal supplied by the user. The [implemented desktop behavior](../README.md) incorporates the user’s later before/after comparison request and records the first-version choices.

# Handoff: Stackish desktop UI (v1)

## Overview
Stackish is a SQL Server workload simulator for database training classes. It calls existing stored procedures to generate Stack Overflow–style activity (reads, searches, posts, votes, edits, occasional expensive queries). The operator is a busy instructor. The whole normal workflow is: **open → connect → choose concurrency → Start → glance while teaching → Stop.** Everything lives on **one main window**; there is no navigation.

Target: **C# / .NET + Avalonia**, one shared UI for Windows and macOS (Linux later).

## About the design files
The files in `design_reference/` are **HTML design references** showing the intended look and behavior. They are not production code. Rebuild them in Avalonia (XAML + view models) using idiomatic patterns: a `Styles`/`ResourceDictionary` for tokens, `ControlTheme`s for buttons and inputs, and an MVVM state machine. Don't embed the HTML.

- `screenshots/*.png`: the source of truth for visuals (1× scale, includes a caption strip above each window).
- `design_reference/Stackish Window.dc.html`: the window as a clickable prototype. Open it in a browser next to `support.js`. Its logic class contains the exact sample numbers, chart generator, and per-state values.
- `design_reference/Stackish Design.dc.html`: the presentation board with all screens and the spec.

## Fidelity
**High fidelity.** The colors, type, spacing, sizes, and copy are final proposals. Recreate them pixel-close. Use native window chrome (the title bars in the mocks just stand in for the OS chrome; don't draw custom chrome).

All metrics in the screenshots are **illustrative sample data**, not measured Stackish performance.

## Screens (`screenshots/`)
| File | State |
|---|---|
| 01-initial-setup.png | Not connected, form expanded, focus on Test connection |
| 02-connection-failed.png | Login failed (SQL 18456), focus on Password |
| 03-connected-ready.png | Connected, form collapsed into header, focus on Start |
| 04-running-windows.png | Running, Windows chrome |
| 05-running-macos.png | Running, macOS chrome (same layout) |
| 06-running-errors-drawer.png | Running with Errors & outcomes drawer open |
| 07-stopping.png | Stopping, active calls finishing |
| 08-stopped-summary.png | Stopped, final totals preserved |
| 09-compact-1000x700.png | Running at 1000 × 700 |

Primary design size: **1280 × 800**. Minimum window: **960 × 640**.

## Layout (all states)
```
┌ OS title bar (native) ───────────────────────────────────────────┐
├ App header 56px, white, 1px bottom border #E4E0DA ───────────────┤
│ [logo 26px] Stackish | ✓ server / database  as user   [Edit/lock]│
│ (Setup only) connection form row + options row + error banner    │
├ Body: padding 20, column gap 20 ─────────────────────────────────┤
│ Rail clamp(280,28%,344)px │ Monitor (fills)                      │
│  Workload card            │  Status card (pill · subline · clock)│
│  Write notice             │  Tiles 3 × 2, gap 14                 │
│  (flex spacer)            │  Chart card (flex:1, min 150)        │
│  Start/Stop 52px          │                                      │
│  shortcut hint            │  [Drawer overlays monitor, right]    │
└──────────────────────────────────────────────────────────────────┘
```
Window background is `#F7F5F2`. Cards are white with a 1px `#E4E0DA` border, an 8px radius, and no shadow.

### App header (56px, padding 0 20, gap 16)
- Logo: 26×26 square, radius 6, `#C8202F`, holding three white bars (16/12/8 × 3px, radius 1, gap 3), centered. Wordmark "Stackish" 19/700, letter-spacing −0.01em.
- A 1×28 divider in `#E4E0DA`.
- **Not connected:** 16px hollow ring (2px `#8A8D95`) + "Not connected" 14/500 `#5C5F68`. **Failed:** filled `#B3261E` circle with a white ✕ + "Connection failed" in `#B3261E`.
- **Connected:** 18px `#1F7A4D` circle with a white ✓, then **server** (600), " / " (`#6E717A`), **database** (600), then "as {user}" (`#5C5F68`). Single line, ellipsizes. Put the SQL Server version in the tooltip.
- Right side: "Edit connection" secondary button (32h) when idle or stopped. While running or stopping, show a lock icon + "Connection locked while running" (13px `#5C5F68`) instead.

### Connection form (Setup / Failed only; padding 4 20 16; gap 10)
- Grid columns `1.5fr 1.1fr 1fr 1fr auto`, gap 12, bottom-aligned. Labels 13/600, gap 5 to the input.
- Fields: **Server** (`sql-class-01.example.lab,1433`), **Database** (`StackOverflow2013`), **Username** (`stackish_student`), **Password** (always masked, no reveal toggle), then the **Test connection** button (ink fill, 36h, 14/600, padding 0 16).
- Options row (13px `#5C5F68`, gap 18): "Server accepts `name`, `name\instance`, or `name,port`" (examples in Plex Mono 12 ink); checkbox **Trust server certificate** (checked by default); checkbox **Remember password**.
- Error banner (Failed): bg `#FBE9E7`, text `#7A1A14`, radius 6, padding 10 12. It has an 18px `#B3261E` ✕ circle, **bold headline sentence**, a plain explanation, the SQL error number in `#9A3A33`, and a right-aligned "Copy details" underlined link. Example: "**Couldn't log in as stackish_student.** SQL Server reached, but it rejected the username or password. Check both and test again. SQL error 18456".
- Map common errors to plain language: 18456 login failed, 4060 database missing or no access, network/26/53 server unreachable, and certificate trust failures (suggest the checkbox).

### Rail
**Workload card** (padding 18 18 16, gap 14):
- "Concurrent operations" 15/600, plus "1–200" 12px `#5C5F68` right-aligned.
- Stepper: [−] 44×44 · numeric input (flex, 44h, 22/600, centered) · [+] 44×44. Joined borders `#CFC9C1`, outer radius 6.
- Helper 13px `#5C5F68`: "How many database calls can run at once." While running, append " Changes apply right away."
- In Setup the stepper is shown at 55% opacity (dimmed but still editable).
- 1px divider `#EEEAE4`.
- "Workload mix" 15/600 + "Automatic" tag (12/600, bg `#F2F0EC`, pill).
- Split bar 10h, radius 3, 2px gap: 55% `#2F6DB5` reads | 45% `#C66A12` writes. Legend below: "**55%** reads" / "**45%** writes" with 10px swatches.
- Three dash bullets (13px `#3B3D44`): "Broad activity across existing posts", "Repeated hits on a few hot posts", "Occasional expensive searches".
- Footnote 12px `#6E717A`: "Percentages are share of calls, not CPU or time."
- No mix editor.

**Write notice** (always visible): bg `#FBF0DC`, radius 8, padding 12 14, text 13px `#4A3200`. It has a 20px `#9A5B00` circle with a white "!", then "**Writes to {database}.** Adds questions, answers, votes, and edits. Use a training copy." It is not a dialog and is never dismissible.

**Primary action** (bottom of rail, full width, 52h, radius 8, 17/600, glyph + 10px gap):
- Setup: disabled, bg `#E4E0DA`, text `#6E717A`, "▶ Start workload". Hint below: "Connect to a database first".
- Ready: `#C8202F`, white, "▶ Start workload". Hover/pressed `#A91A27`. Hint: "F5 to start" (Win) / "⌘ R to start" (mac).
- Running: ink `#1E1F23`, white, "■ Stop" (12px white square, radius 2). Hover `#3B3D44`. Hint: "Shift+F5 to stop" / "⌘ . to stop".
- Stopping: disabled, bg `#F2F0EC`, 1px `#CFC9C1`, text `#5C5F68`, two amber 4×12 bars + "Stopping…". Hint: "Finishing active calls…".
- Stopped/Failed: red "▶ Start new run".
- Hint text is 12px `#6E717A`, centered, 6px below the button. **Start and Stop occupy the same slot**, so the instructor's eye never moves.

### Monitor
**Status card** (padding 16 20, gap 12):
- Status pill: padding 6 14 6 10, radius 999, gap 12. It holds a 14px shape plus the state word at 22/700.

| State | Pill bg | Word color | Shape |
|---|---|---|---|
| Not connected | `#F2F0EC` | `#3B3D44` | hollow circle, 2px `#8A8D95` |
| Ready | `#F2F0EC` | `#1E1F23` | hollow circle, 3px `#1E1F23` |
| Running | `#E7F3EC` | `#145C38` | filled circle `#1F7A4D` |
| Stopping | `#FBF0DC` | `#6B3F00` | hollow rounded square (r3), 3px `#9A5B00` |
| Stopped | `#F2F0EC` | `#1E1F23` | filled square (r3) `#3B3D44` |
| Failed | `#FBE9E7` | `#B3261E` | filled square `#B3261E` |

- Subline: 14px `#3B3D44`, flex. Text per state:
  - Not connected: "Enter connection details above, then test the connection."
  - Ready: "{n} concurrent operations · runs until you stop it"
  - Running: "Started 10:32:04 AM · {n} concurrent operations"
  - Stopping: "No new calls are starting. Waiting for {k} active calls to finish."
  - Stopped: "Started … · Stopped … by you. Totals below are final."
  - Failed: plain-language reason, e.g. "Lost connection to sql-class-01… at 10:41 AM."
- Clock (right): label 12/600 uppercase, tracking 0.06em, `#5C5F68` ("Elapsed", or "Total time" when stopped). Value in IBM Plex Mono 34/600 `HH:MM:SS`; `#B9B4AC` when idle.
- While stopping, add a progress row: 6px track `#F2E6CF`, fill `#9A5B00`, then "**3 of 8** active calls finished · cancels the rest after 30 s" (13px `#4A3200`).

**Metric tiles** (3 columns, gap 14; padding 14 16; gap 4):
- Label 13/600 `#3B3D44` with an optional 16px glyph badge. Value 32/600, tracking −0.01em, tabular numerals. Sub 12.5px `#5C5F68`, one line, ellipsized.
- Tiles:
  1. **Calls completed**: sub "{reads} reads · {writes} writes"
  2. **Calls / sec**: last 10 s; sub "last 10 s · avg N". When stopped: "Calls / sec (avg)" with "average · peak N".
  3. **Active calls**: sub "of {n} allowed" / "finishing, none starting" / "all calls finished"
  4. ✓ (`#1F7A4D`) **Successful writes**: sub "writes that changed data"
  5. – (`#6E717A`) **Expected outcomes**: Conflict + NoChange + NotFound; sub "Conflict 3.1k · NoChange 4.2k · NotFound 836" (use the k abbreviation ≥ 1000)
  6. ✕ (`#B3261E`) **Errors**: value in `#B3261E`; sub "SQL or connection failures"
- Idle: every value shows "—" in `#B9B4AC`, with no sub.
- **Rule:** writes = successful writes + expected outcomes + write errors. Never count a completed call as a successful write unless it changed data.

**Chart card** (flex 1, min 150, padding 14 20 12):
- Header: "Calls per second" 15/600 · range 13px `#5C5F68` ("last 5 minutes"; "whole run" when stopped) · legend (Reads / Writes swatches) · **Errors & outcomes** secondary button (30h) with a count badge (20h pill, `#B3261E`, white 12/600). Show the button once any run exists.
- Plot: **stacked area**, with reads at the bottom (`#2F6DB5`, fill 22% opacity, 2px line) and writes on top (`#C66A12`, same treatment). 5-second buckets; 60 buckets for 5 minutes. When stopped, use 60 buckets spread across the whole run.
- Y axis: fixed 0–600 (11.5px `#6E717A` labels: 600/400/200/0). Rescale only if the data exceeds it, to the next multiple of 200. Dashed `#EEEAE4` gridlines; solid `#CFC9C1` left and bottom axes.
- X labels: −5:00 … now, or 0:00 … total when stopped.
- Idle: empty plot with a centered 14px `#6E717A` message: "Connect to a database to get started." / "Press Start workload to begin."
- Suggested library: LiveCharts2 or ScottPlot.Avalonia, styled to match. A custom `Control` drawing two polylines is also fine.

**Errors & outcomes drawer** (overlay on the body's right edge):
- Width `min(440, 46%)`, white, left border `#E4E0DA`, shadow `-12 0 32 rgba(30,31,35,.12)`. No scrim, and the rail (Stop) stays usable.
- Header: "Errors & outcomes" 17/700 + a 32px ✕ close button. Tabs (14px, active tab gets a 3px ink underline): **Errors** [count, red pill] | **Expected outcomes** [count, neutral pill].
- Errors tab:
  - Explainer (13px `#5C5F68`): "SQL or connection failures. The workload keeps running; a single failed call doesn't stop it."
  - Grouped cards (border `#E4E0DA`, r8, padding 12 14): ✕ + **kind** + count (20/600); detail line, e.g. "SQL error 1205 · mostly during *Vote on post*, *Accept answer*"; "Last seen 14 s ago" 12px `#6E717A`.
  - "MOST RECENT" label, then rows: time (Plex Mono 12) | **operation** + one-line message. The list is scrollable.
  - Footer: "Copy error details" secondary button.
- Outcomes tab: same structure, grouped by Conflict / NoChange / NotFound with per-operation counts. It is explicitly labeled as expected behavior, not failure.
- Use friendly operation names only (Vote on post, Accept answer, Search posts, Edit question…). **Never show** SQL text, procedure names, parameters, or JSON.

## State machine
`NotConnected → (Test ok) Ready → (Start) Running → (Stop) Stopping → (all calls done or 30 s) Stopped`
- Test fail → `ConnectionFailed` (stays in the form; focus moves to the first likely-wrong field).
- Running → `Failed` automatically if every call fails for 10 s straight, or on a fatal auth/connection loss. Totals are kept and the drawer opens to the cause.
- Stopped/Failed → (Start new run) Running. Totals reset when the new run starts, not before.
- Ready/Stopped/Failed → (Edit connection) NotConnected, with the form pre-filled.

### Enabled controls
| Control | Setup | Ready | Running | Stopping | Stopped | Failed |
|---|---|---|---|---|---|---|
| Connection fields | Edit | via Edit | Locked | Locked | via Edit | via Edit |
| Test connection | Yes | — | — | — | — | — |
| Concurrency | Dimmed (editable) | Yes | Yes, live | No | Yes | Yes |
| Start | Disabled | Yes | — | — | Start new run | Start new run |
| Stop | — | — | Yes | Disabled | — | — |
| Errors & outcomes | — | — | Yes | Yes | Yes | Yes |

### View-model state (suggested)
`ConnectionState`, `RunState`, `Concurrency (int 1–200)`, `StartedAt`, `StoppedAt`, `Elapsed`, `CallsCompleted`, `Reads`, `Writes`, `CallsPerSec10s`, `AvgCallsPerSec`, `PeakCallsPerSec`, `ActiveCalls`, `SuccessfulWrites`, `Outcomes{Conflict,NoChange,NotFound}`, `Errors (grouped + recent ring buffer of ~200)`, `ChartBuckets[60]{reads,writes}`, `IsDrawerOpen`, `ConnectionError?`.

## Interactions
- **Shortcuts:** Windows F5 start / Shift+F5 stop; macOS ⌘R start / ⌘. stop. Esc closes the drawer. Enter in any connection field runs Test.
- **Concurrency:** type a value, or use −/+. Arrow keys change it by ±1, Shift+arrow by ±10. Values are clamped to 1–200. While running, changes take effect within 1 s.
- **Test connection:** the button shows a spinner and "Testing…"; fields stay editable. On success, the form collapses and focus moves to Start.
- **Stop:** new work stops immediately. Active calls get 30 s, then are cancelled; the progress label counts down the last 10 s. There is no second confirm.
- **Refresh:** tiles update once per second with no count-up animation (avoids jitter on screen-share). The chart appends one bucket every 5 s.
- **No toasts or modals during a run.** The drawer badge is the only alert.
- **Closing while running:** the one allowed confirm, "Stop the workload and quit?", which then performs a normal Stop.
- **Persistence:** server, database, username, concurrency, and Trust-cert are saved between launches. The password is saved only if "Remember password" is checked, using Windows Credential Manager or the macOS Keychain.
- **Focus:** every focusable control gets a 2px gap ring in the surface color plus a 2px ink `#1E1F23` ring (`0 0 0 2px <surface>, 0 0 0 4px #1E1F23`). Implement it as a `:focus-visible` style on all ControlThemes.
- **Responsive:** the rail is `clamp(280, 28% of width, 344)`. Tiles stay 3×2 at every width. Only the chart flexes vertically.

## Design tokens
**Color**
| Token | Hex | Use |
|---|---|---|
| Paper | #F7F5F2 | window bg |
| Surface | #FFFFFF | cards, header, inputs |
| Chrome | #EDEAE6 | (mock title bar only) |
| Line | #E4E0DA | card borders, dividers |
| Line subtle | #EEEAE4 | inner dividers, gridlines |
| Line strong | #CFC9C1 | input/button borders, axes |
| Ink | #1E1F23 | text, Stop, focus ring |
| Ink 2 | #3B3D44 | secondary text, ink hover |
| Ink 3 | #5C5F68 | helper text |
| Ink 4 | #6E717A | hints, axis labels |
| Muted | #8A8D95 / #B9B4AC | idle rings / idle values |
| Neutral fill | #F2F0EC | idle pill, hover, tags |
| Brand red | #C8202F | Start, logo only |
| Brand red hover | #A91A27 | Start hover/pressed, links hover |
| Running | #1F7A4D on #E7F3EC (text #145C38) | |
| Stopping / caution | #9A5B00 on #FBF0DC (text #6B3F00 / #4A3200) | |
| Error | #B3261E on #FBE9E7 (text #7A1A14) | |
| Reads | #2F6DB5 | chart, mix |
| Writes | #C66A12 | chart, mix |

Brand red approximates brentozar.com's accent. Confirm it against the site's real theme value.

**Type:** IBM Plex Sans (400/500/600/700) and IBM Plex Mono (500/600). Both are OFL; bundle them as `avares://` font resources. Use tabular numerals (`FontFeatures="+tnum"`) on all numbers.
| Style | Size/Weight |
|---|---|
| Wordmark | 19/700 |
| State word | 22/700 |
| Clock | Mono 34/600 |
| Tile value | 32/600 |
| Concurrency input | 22/600 |
| Primary button | 17/600 |
| Card title | 15/600 |
| Body / input | 14/400 |
| Label | 13/600 |
| Helper | 12–13/400 (min 11.5 for axes) |

**Spacing:** 4px grid. Common steps: 4, 5, 6, 8, 10, 12, 14, 16, 18, 20.
**Sizes:** header 56 · primary button 52 · stepper 44 · inputs and Test 36 · secondary buttons 30–32 · glyph badges 16–20.
**Radius:** controls 6 · cards and primary button 8 · pills 999 · checkbox 4.
**Shadow:** cards none; drawer `-12px 0 32px rgba(30,31,35,.12)`.

## Copy voice
Plain-spoken and first-person-friendly, like brentozar.com: short sentences and no jargon. Say what happened and what to do next ("Couldn't log in as stackish_student… Check both and test again."). Never use "users" for workers; say "concurrent operations" / "calls".

## Assets
- Logo: built from CSS shapes (red rounded square + three stacked white bars). Recreate it as an Avalonia `Path`/`Rectangle` group, or export it to SVG/ICO/ICNS for app icons.
- Glyphs: ✓ ✕ ! ▶ ■ and the lock are simple shapes. Use a consistent icon set (e.g. Fluent System Icons, MIT) at 16–20px.
- Fonts: IBM Plex Sans and Mono (Google Fonts / github.com/IBM/plex).

## Files
- `screenshots/` — 9 PNGs (listed above)
- `design_reference/Stackish Window.dc.html` — clickable window prototype (needs `support.js` in the same folder)
- `design_reference/Stackish Design.dc.html` — presentation board + spec
- `design_reference/support.js` — runtime for the two HTML files
