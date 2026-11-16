# Boom - Windower 4 (0.2.2-test7)

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

Bursting itself never uses Blood Pacts, BST Ready moves, or PUP pet commands; it reacts to detected skillchain effects. Normal GearSwap spell interception remains in place. Making skillchains is the separate, optional coordinator below.

## Skillchain coordinator (test5, not yet live-tested)

Load Boom on **every** character in the party. When a character is ready (1000+ TP while engaged, or Blood Pact: Rage ready with an avatar out), its Boom polls the other Boom clients, collects what each of them can use right now, plans the best chain, asks each member to confirm, then runs it: step 1 fires, and each later step fires when the previous step's action is seen plus that ability's chain delay (3 seconds unless Trust's data says otherwise) and a small margin. If anyone refuses, misses, acts out of turn, the chain breaks, the target dies or a step times out, the plan stops on every client and they may plan again from the open window. Refused steps are re-sent (see below).

- **Requires Trust installed** (it reads Trust's `cylibs/res/skills.lua` and `cylibs/util/skillchain_util.lua`, so chain data and rules match Trust). Default folder is `addons/Trust/` next to Boom; change with `//boom sc trust <folder>`.
- **Turn Trust's own skillchains off on every character** with `//trust sc off` so two systems don't fire.
- Works for any number of party/alliance members running Boom on the same PC (Windower IPC). Boom clients not in your party are ignored.
- Each member is used once per chain; with `mixed` on (default) a member may give one weapon skill and one blood pact.
- If no chain is possible, nothing is fired until a member reaches the solo TP (3000 by default), which then uses its best weapon skill alone.
- A step the game refuses ("Unable to use weapon skill") is re-sent every second until the action starts or the window gets too short.

**With Failsafe loaded:** both can re-send a refused command. Failsafe tries once when the character looks ready and prints "... was refused. Waiting for readiness."; Boom sees that line and waits one more second before trying itself. Keep Failsafe's `notify` on so Boom can see it.

Settings changed on one character are sent to every Boom client and saved in `data/sc_settings.xml`.

- `//boom sc` or `//boom sc status` - settings, Trust data folder, last plan and result
- `//boom sc on|off` - enable or disable coordinated skillchains (on by default)
- `//boom sc steps 2-6` - longest chain to plan (default 3)
- `//boom sc hold on|off` - save TP for a 3-step chain when the party could make one; ignored when it can't
- `//boom sc holdtp <n>` - stop holding once a ready weapon-skill member reaches this TP (default 3000)
- `//boom sc target <list>|clear` - prefer chain properties or elements, e.g. `Light,Fusion` or `Fire`; falls back to the best available chain
- `//boom sc opener <list>|clear` - prefer openers, e.g. `Savage Blade` or `Cioara:Flaming Crush`; falls back to any usable opener
- `//boom sc tp <n>` - minimum TP for weapon skills (default 1000)
- `//boom sc solo <n>|off` - when no chain is possible, a member at this TP weapon skills alone (default 3000)
- Shortcuts: `//boom target ...`, `//boom opener ...`, `//boom hold ...`, `//boom steps ...`, `//boom solo ...` work without `sc`
- `//boom sc bp on|off`, `//boom sc mixed on|off`, `//boom sc announce local|party|off`
- `//boom sc set color_member|color_ability|color_chain <n>` - plan line colors (defaults: names 207 light blue, abilities 0 white, result 158 green, as seen on the user's screen)
- `//boom sc set <key> <value>` - timing: `poll_window` 0.5, `ack_window` 0.7, `step_margin` 0.4, `step_timeout` 6, `retry_delay` 1.5 (seconds)

Plan choice, in order: a requested target, a requested opener, the highest chain level, then more steps (each step is another magic-burst window). A chain that is already a requested target is not continued into one that isn't. `//boom debug on` adds `SC:` lines explaining polls, plans, refusals and aborts.

## Commands

- `//boom` or `//boom help` — help
- `//boom status` — version, activation, last attempted spell, last skip
- `//boom on` / `//boom off` — enable or disable automatic bursting (on immediately after load)
- `//boom debug on` / `//boom debug off` — show detection, duplicate-event and skip explanations
- `//boom trace on` / `//boom trace off` — verbose raw action message IDs for selected-target WS/magic/pet actions to investigate missing skillchain recognition (off by default)
- `//boom retry on|off` - re-send a burst the game refused ("Unable to cast spells at this time"), up to 4 inputs inside the burst window (on)
- `//boom multi on|off` - after a burst lands, cast another one on the same skillchain if the window allows (on)
- `//boom bursts 1-4` - bursts per skillchain step (2); `//boom window <sec>` - how long after a skillchain to keep trying (7)
- `//boom restart` — reload, enabling auto again
- `//boom unload` — unload

## Limits and diagnosing a missed burst

Boom attempts **one spell per detected skillchain**, not an unconditional guarantee of a successful burst. It only acts on a live, already-targeted monster within its conservative 20-yalm check, and does not override an action lock or another addon that has started a cast. On zoning, logout, and job change it cancels pending scheduled actions. A new load always starts in Auto.

If no cast occurs: run `//boom debug on` and `//boom status`. Debug (yellow details, standard [Boom] label) reports recognized chains, rejected/duplicate events, missing targets, and weapon-skill packets on the selected target that contain no recognized skillchain effect. If the game shows a burst window but debug has no corresponding chain, turn on `//boom trace on`, reproduce **one** missed level-2 window, and share the `category`, `action`, `additional`, `has_add` message values, target name, and the skillchain displayed by TargetSC. Turn trace back off afterward to keep the log quiet. Trace deliberately **does not** print every ordinary attack; it concentrates on relevant action categories and the currently selected target.

A skillchain effect can be present in the action's additional-effect message or, rarely, the primary action message. Both paths are now examined. The previous whole-second duplicate filter could silently drop a legitimate repeated effect for nearly two seconds; this release uses a 0.20-second suppression interval and reports suppression when debug is enabled. The effect table already includes the four level-2 skillchains and their alternate effect IDs. This does not establish that every FFXI skillchain window is now recognized; further packet evidence may be necessary.

Boom continues to attempt one spell per detected skillchain, with the same **0.9-second casting delay**. It doesn't move or retarget your character, and normal spell-eligibility checks still apply. The default chat output is quiet; debug and trace are explicit opt-ins. Chat output follows the shared FFXI addon convention: `[Boom]` label color 200; headings 167; syntax 207; ordinary descriptions/values 0; ON green 158; OFF red 167; ASCII hyphens only. By user preference, **Debug details use readable yellow color 207** instead of neutral white; Trace and ordinary details stay white.

## Changelog

- **0.2.2-test7 (2026-11-16)** - The `Skillchain:` plan line shows characters, abilities and the result in three colors. Works alongside Failsafe (Broguypal fork): when Failsafe announces it will re-send a refused command, Boom waits a second before its own retry, so both don't send it.

- **0.2.1-test6 (2026-11-16)** - Fixes from the first live session logs. Shield Bash (and other category-3 job abilities) no longer read as a weapon skill with the same number (Expiacion), which had broken plans and invented open chains. A blood pact is no longer cancelled by its own recast while the avatar is still readying it. Refused steps are re-sent every second until they start or the window closes; the leader's "continuing" decision is shared with everyone. New: solo release at 3000 TP; bursts are retried when refused and a second burst follows when the window allows (`retry`, `multi`, `bursts`, `window`); `//boom target ...` style shortcuts. First burst delay is still exactly 0.9 seconds.

- **0.2.0-test5 (2026-11-16)** - Add the party skillchain coordinator (`sc/`, `//boom sc`): IPC poll, offers, plan, confirmation and packet-timed execution of weapon skills and Blood Pact: Rage across any number of Boom clients; uses Trust's skillchain data and combination rules. Options: steps, hold for 3-step, targets, openers, min TP, blood pacts, mixed, announce. Burst behavior, 0.9-second delay and spell choice unchanged; if the coordinator cannot load, bursting runs as before.

- **0.1.3-test4 (2026-11-12)** - Make the text of `[Boom] Debug:` messages yellow (color 207) instead of white, including detection, non-chain observation, and skip explanations. Keep heading/label, other messages, trace, casting, and help colors unchanged. Review Cioara's real November 12 log and document observed cast refusals separately from successful detection; no change to cast logic, 0.9-second delay, spell selection, or targeting.

- **0.1.2-test3 (2026-11-12)** - Diagnose suspected missed level-2 magic-burst windows without changing the confirmed 0.9-second cast delay: reduce duplicate suppression from roughly 1-2 seconds to 0.20 seconds, accept recognized effect IDs in the primary action message as a fallback, report recognized/ignored/rejected events in Debug, and expose `//boom trace on|off` for selected-target action IDs. Bring all in-game output and help text into the shared `WORKFLOW.md` label/color conventions (including ASCII punctuation). Preserve all known spell choices, target safeguards, and Auto-on-load behavior.

- **0.1.1-test2 (2026-11-11)** — Rename addon directory, Lua entry point, display label and commands from BoomMB to **Boom**. Prefer Light-family magic for WHM-main on Light-compatible skillchains, including Holy/Holy II, even when /BLM has elemental magic. Keep the working 0.9-second timing, default-on activation, safety checks, and other jobs' priorities unchanged. Expand simulated regression tests for WHM spell choice and renamed commands.
- **0.1.0-test1 (2026-11-11)** — Original standalone BoomMB automatic single-burst test. Targets existing `<t>/<bt>`, validates learned spell/job/MP/recast, schedules 0.9 seconds after detected skillchain, and provides status/debug controls. Initially delivered without live verification; user subsequently confirmed it works well in game and its timing is good.
