# Boom - Windower 4 (0.1.3-test4)

**Load it. Skillchain happens. Boom.** Boom automatically attempts one learned, job-usable, ready, affordable magic burst on the currently targeted enemy when it detects a skillchain. No activation or spell-tier setup required. This update **keeps the exact 0.9-second delay** that the user reported working in game.

## Installing or upgrading

1. **If updating from BoomMB**, on each character where it is loaded run `//lua unload BoomMB`. Remove the old `Windower4/addons/BoomMB/` folder. **Do not leave BoomMB running with Boom**, or both may attempt to burst.
2. Extract `Boom/` to `Windower4/addons/` so the main script is `Windower4/addons/Boom/Boom.lua`.
3. If using Trust on the same character, use `//trust mb off` to avoid two automatic casters. Unload any other automatic magic-burst addon (for example autoMB) on that character.
4. Run `//lua load Boom`. **Auto bursting begins immediately**; no additional command or configuration is required.
5. Keep the skillchain enemy targeted as `<t>` or `<bt>`; Boom never injects targeting packets or changes the selected enemy.

Boom prints a color-formatted `[Boom] Casting ...` message on attempted bursts. The FFXI combat log's actual `Magic Burst!` message confirms whether the server registered a successful burst.

## Which spells does it use?

- For six elemental properties, Boom chooses the highest learned, usable, ready, affordable corresponding elemental spell from VI down to tier I, following its existing elemental priority order.
- For **Light**, a **WHM main job** tries its light spells first: `Holy II`, `Holy`, `Banish III`, `Banish II`, `Banish`. If Holy II is unavailable and the WHM knows Holy, the addon will attempt **Holy** on a Light skillchain (and other Light-compatible chains such as Fusion, Transfixion, and Radiance). This priority is retained even with a nuking support job. When no light spell is usable, it may use a compatible elemental spell from the support job instead.
- For other main jobs, the original elemental order is unchanged; light spells remain available if no higher-priority eligible elemental spell is usable. On Dark properties, Drain-family spells remain eligible.

Boom does not perform SMN Blood Pacts, BST Ready moves, or PUP pet commands. It does not initiate skillchains; it reacts to detected skillchain effects. Normal GearSwap spell interception remains in place.

## Commands

- `//boom` or `//boom help` — help
- `//boom status` — version, activation, last attempted spell, last skip
- `//boom on` / `//boom off` — enable or disable automatic bursting (on immediately after load)
- `//boom debug on` / `//boom debug off` — show detection, duplicate-event and skip explanations
- `//boom trace on` / `//boom trace off` — verbose raw action message IDs for selected-target WS/magic/pet actions to investigate missing skillchain recognition (off by default)
- `//boom restart` — reload, enabling auto again
- `//boom unload` — unload

## Limits and diagnosing a missed burst

Boom attempts **one spell per detected skillchain**, not an unconditional guarantee of a successful burst. It only acts on a live, already-targeted monster within its conservative 20-yalm check, and does not override an action lock or another addon that has started a cast. On zoning, logout, and job change it cancels pending scheduled actions. A new load always starts in Auto.

If no cast occurs: run `//boom debug on` and `//boom status`. Debug (yellow details, standard [Boom] label) reports recognized chains, rejected/duplicate events, missing targets, and weapon-skill packets on the selected target that contain no recognized skillchain effect. If the game shows a burst window but debug has no corresponding chain, turn on `//boom trace on`, reproduce **one** missed level-2 window, and share the `category`, `action`, `additional`, `has_add` message values, target name, and the skillchain displayed by TargetSC. Turn trace back off afterward to keep the log quiet. Trace deliberately **does not** print every ordinary attack; it concentrates on relevant action categories and the currently selected target.

A skillchain effect can be present in the action's additional-effect message or, rarely, the primary action message. Both paths are now examined. The previous whole-second duplicate filter could silently drop a legitimate repeated effect for nearly two seconds; this release uses a 0.20-second suppression interval and reports suppression when debug is enabled. The effect table already includes the four level-2 skillchains and their alternate effect IDs. This does not establish that every FFXI skillchain window is now recognized; further packet evidence may be necessary.

Boom continues to attempt one spell per detected skillchain, with the same **0.9-second casting delay**. It doesn't move or retarget your character, and normal spell-eligibility checks still apply. The default chat output is quiet; debug and trace are explicit opt-ins. Chat output follows the shared FFXI addon convention: `[Boom]` label color 200; headings 167; syntax 207; ordinary descriptions/values 0; ON green 158; OFF red 167; ASCII hyphens only. By user preference, **Debug details use readable yellow color 207** instead of neutral white; Trace and ordinary details stay white.

## Changelog

- **0.1.3-test4 (2026-11-12)** - Make the text of `[Boom] Debug:` messages yellow (color 207) instead of white, including detection, non-chain observation, and skip explanations. Keep heading/label, other messages, trace, casting, and help colors unchanged. Review Cioara's real November 12 log and document observed cast refusals separately from successful detection; no change to cast logic, 0.9-second delay, spell selection, or targeting.

- **0.1.2-test3 (2026-11-12)** - Diagnose suspected missed level-2 magic-burst windows without changing the confirmed 0.9-second cast delay: reduce duplicate suppression from roughly 1-2 seconds to 0.20 seconds, accept recognized effect IDs in the primary action message as a fallback, report recognized/ignored/rejected events in Debug, and expose `//boom trace on|off` for selected-target action IDs. Bring all in-game output and help text into the shared `WORKFLOW.md` label/color conventions (including ASCII punctuation). Preserve all known spell choices, target safeguards, and Auto-on-load behavior.

- **0.1.1-test2 (2026-11-11)** — Rename addon directory, Lua entry point, display label and commands from BoomMB to **Boom**. Prefer Light-family magic for WHM-main on Light-compatible skillchains, including Holy/Holy II, even when /BLM has elemental magic. Keep the working 0.9-second timing, default-on activation, safety checks, and other jobs' priorities unchanged. Expand simulated regression tests for WHM spell choice and renamed commands.
- **0.1.0-test1 (2026-11-11)** — Original standalone BoomMB automatic single-burst test. Targets existing `<t>/<bt>`, validates learned spell/job/MP/recast, schedules 0.9 seconds after detected skillchain, and provides status/debug controls. Initially delivered without live verification; user subsequently confirmed it works well in game and its timing is good.
