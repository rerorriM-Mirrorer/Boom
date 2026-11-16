# Boom testing log

## Current Development Status - November 12, 2026 (America/Chicago)

- **Source / branch:** Baseline: user-tested `Boom_0.1.2_test3.zip`, local commit `e0ef0e9`; this color-only change is in local Git branch `test/debug-yellow-log-review`. There is no Boom GitHub repository/remote, so no GitHub push or published remote branch is claimed.
- **Live observations (user-uploaded `Cioara_2026.11.12.log`):** The 0.1.1 build before its reload includes successful Liquefaction/Fire, Distortion/Blizzard, and Detonation/Aero magic bursts. After the 0.1.2 `Auto ON - Loaded; watching skillchains` line and `Debug ON`, the log records two **Compression** effects (ID 294), both detected and queued by Boom, and one **Detonation** (ID 300), also detected and queued. The game subsequently says `Unable to cast spells at this time` / `Spell was refused. Waiting for readiness.` for each attempted Drain/Drain/Aero. No successful burst or additional level-2 effect is present in that post-debug sample. The log does not prove which addon/manual action caused the lock or that all other skillchains were detected. One earlier Light effect is followed immediately by mob defeat, before Boom's debug was enabled; no burst could be observed in that sequence.
- **Change in 0.1.3-test4:** Only Debug *body text* changes from white (0) to yellow (207). `[Boom]` label remains 200, `Debug:` heading remains 167, and Trace/normal/status/help/cast messages retain prior coloring. Keep the default Auto ON, unchanged spell choice, unchanged packet parsing/duplicate window, and exact 0.9-second schedule. No new cast readiness logic yet; reported action refusals warrant separate investigation.
- **Verification:** LuaTeX/texlua host executes 28 mocked production-module checks including new asserts for yellow detection/WS/skip details, unchanged white trace/status text, and exact 0.9-second delay. Host `loadfile` parse and `git diff --check` pass; packaged-copy mock rerun is completed before delivery. Not a live FFXI or Windower Lua 5.1 test.
- **Live checks pending:** Load replacement Boom folder, run `//boom debug on`, confirm debug bodies look yellow with the normal label/heading. Confirm a subsequent MB still lands with unchanged timing. For refused casts, capture any simultaneous Cioara spell/JA command and Trust action as the possible source of readiness blocking; do not infer an addon cause from chat text alone.
- **Rollback:** Unload Boom; restore the prior `Boom_0.1.2_test3.zip` folder; reload Boom. Back up user-owned `data/` before folder replacement.

---

## Batch: 0.1.3-test4 - November 12, 2026

**User request:** Change Boom Debug message text from white to yellow, and review the attached `Cioara_2026.11.12.log` for skillchain and cast evidence.

**Source and patch scope:** local `test/debug-yellow-log-review` from `e0ef0e9`. One production renderer and addon version changed; no other casting or detection code changed. Add a color-specific regression, document the log observations, keep cumulative history intact.

**Observed sample:** With 0.1.2 and Debug ON, Compression on Yagudo Chanter and Yagudo Sentinel each produced a debug event (effect 294), `Casting Drain`, and then the game's readiness refusal. Detonation on Yagudo Assassin produced effect 300, `Casting Aero`, then refusal. Selected-target WS/pet events without a skillchain produced `category 3 / 13; action 185 / 317; additional 0; has_add false` diagnostics, which are expected *non-skillchain* messages and do not prove a missed MB. Earlier logged real successful bursts confirm this is not a universally broken casting/timing path.

**Interpretation / limitations:** `Casting` means Boom dispatched a command, not that the game accepted it. The refusals indicate an unavailable action state, but without outgoing command attribution or timestamps the exact competing source is unknown. The post-debug sample contains no level-2 effect to classify as missed. No additional action-state arbitration has been applied in this color-only patch. Live acceptance remains required.

---

## Current Development Status - November 12, 2026 (America/Chicago)

- **Source / branch:** The exact delivered `Boom_0.1.1_test2.zip` is the baseline; working tree `test/sc-diagnostics-format` is a local Git branch derived from the archived package. No separate Boom GitHub repository has been identified. Do not imply this is a remote published release.
- **User-confirmed live observations:** Boom's initial casting behavior and 0.9-second timing worked well; the user now suspects that some level-2 skillchain MB windows pass without an attempt or debug explanation. The precise cause has not been captured in FFXI. The renamed WHM/Holy behavior has not been separately confirmed in-game.
- **Changes in 0.1.2-test3:** A 0.20-second duplicate suppression window replaces the whole-second `os.time() <= 1` check (which could ignore a legitimate repeat), and the parser checks a recognized `action.message` as a fallback to `action.add_effect_message`. Debug explains recognized, discarded and skipped events and gives a one-line WS/pet-action note when no recognized chain exists on the selected target. Optional trace shows selected-target packet category and message fields. All user-visible Boom messages now use the canonical `chat` + `string.color()` formatting with labeled, heading, command, syntax, state and neutral-value colors; generated punctuation uses ASCII. No change to 0.9-second burst dispatch delay, spell ranking, target behavior or Auto-on-load.
- **Current verification:** LuaTeX/texlua host loads the production file and runs 27 mocked tests successfully, including a 0.9-second scheduled-delay assertion and Windower-style chat-color mocks; `git diff --check` passes. This is **not** actual Windower 4 Lua 5.1 or an FFXI packet capture. Final local branch commit and package hash are reported with the delivery.
- **Next live checks:** Trigger actual level-2 Gravitation, Fragmentation, Distortion and Fusion chains on Cioara's selected target while `//boom debug on`. If a window appears without detection, enable `//boom trace on`, reproduce once and record the incoming action's category, main and additional message IDs, and target. Confirm actual magic-burst success remains timely, including repeated same-effect chains, WHM Holy if used, and the FFXI chat colors. Turn trace off afterward.
- **Rollback:** Unload Boom and restore the previous `Boom_0.1.1_test2.zip` contents. Preserve any user-owned files in `data/`.

---

## Batch: 0.1.2-test3 - November 12, 2026

**Purpose:** Investigate apparently missed level-2 skillchain MB windows and fully apply the shared per-addon chat conventions to normal, debug, trace, help, status, and lifecycle messages. Preserve the live-confirmed 0.9-second casting delay and known-good selection behavior.

**Host tests:** 27 mocked production-module checks cover the original spell choice and WHM behavior, four normal and four alternate level-2 effect IDs, primary-message fallback, same-effect retransmit versus genuine later effect, filtered WS/trace output, target and cast safety, chat color fragments and syntax, and lifecycle commands. These mocks cannot establish live FFXI packet timing.

**Preliminary source finding:** Existing Boom already had all level-2 chain IDs (290-293 and alternate 387-390), so those IDs were not simply missing. The prior duplicate filter silently dropped matching mob+effect packets whose `os.time()` timestamps differed by 0 or 1 second. Also, several detection-stage early returns were silent. The primary-message fallback and Trace are hypotheses/investigative coverage, not evidence of a specific live packet field.

**Live acceptance still required:** A real missed level-2 skillchain should be reproduced; distinguish a server-recognized skillchain from a predictive TargetSC window, and distinguish a queued cast from the game's actual `Magic Burst!` result. If no actionable ID is present in 0x028, collect raw action IDs; do not infer a burst window from a normal WS finish. Verify label/color rendering on Cioara's display and no regressions to successful timing.

**Install and rollback:** Unload Boom (`//lua unload Boom`), back up the current folder, merge the delivered `Boom/` into `Windower4/addons/Boom/`, then `//lua load Boom`. This is a complete testing folder including `README.md`, `WORKFLOW.md`, `TESTING.md`, `AGENTS.md`, `docs/PACKETS.md`, and mock tests. Debug/trace start OFF; Auto remains ON immediately. To roll back, restore the previous test2 `Boom/` folder. Do not load two competing auto-burst addons on one client.

---


## Current batch: 0.1.1-test2 — November 11, 2026

**Goal:** Rename the working BoomMB addon completely to **Boom**, and confirm that a WHM with Holy will use it on Light skillchains. Preserve the reported excellent magic-burst timing and no-setup Auto-on-load behavior.

**Source and branch:** This test continues from the exact previously delivered `BoomMB_0.1.0_test1.zip`. No GitHub repository for BoomMB/Boom was identified; the baseline is an archived test package rather than a fetched remote branch. Local changes are traceable in the development workspace on `test/whm-holy-rename`; there is **no GitHub push**. The package includes this cumulative record and the local source documentation.

**User-confirmed live behavior (previous batch):** On 2026-11-11, user reported that BoomMB is "Working great" and that the "Timing is great." Treat this as confirmation of the previous addon working in FFXI, **not a test of this renamed WHM build**. Actual Holy/WHM behavior still needs live confirmation.

**Code changes:** The addon, script, command, message prefix, and lifecycle actions are now `Boom`. A WHM main job prefers Light candidates on any chain permitting Light: Holy II, Holy, Banish III, Banish II, Banish; if none are usable, the existing elemental fallbacks remain. Other jobs retain their existing ordering. The established `coroutine.schedule` delay remains exactly **0.9 seconds**.

**Host checks:** `texlua` parses `Boom/Boom.lua` and `Boom/tests/mock_test.lua`. The actual addon passes **17 production-module mock tests** for original elemental behavior, WHM Holy and Holy II, WHM/BLM prioritization, fallback when Holy is unavailable, Fusion/Transfixion, renamed lifecycle commands, target safety, MP/recast/level gates, zone cancellation, and malformed packets. These use simulated FFXI packets and resources. **Lua 5.1 and live game verification of this version were not available.**

**Install/rollback:** Unload BoomMB and remove its old addon folder, then extract `Boom/` into the Windower 4 addons directory. Run `//lua load Boom`; no activation command is needed. Do not run old BoomMB and Boom simultaneously. If a regression appears, unload Boom and restore the old 0.1.0-test1 BoomMB folder and `//lua load BoomMB`. Preserve existing addon data; this package contains no custom character settings. `WORKFLOW.md` and this record are included alongside the runtime file inside `Boom/`.

**Live tests pending:**

1. Load Boom on Cioara after removing the old instance, confirm `//boom status`, `//boom restart`, and that the first normal skillchain still lands bursts with the same timing as test1.
2. On a WHM main with Holy learned, adequate MP, ready recast, and a matching target, trigger **Light**. Verify the addon prints `Casting Holy` (or `Casting Holy II` when learned/ready) and the game confirms `Magic Burst!`.
3. Try WHM/BLM with Thunder learned and Holy learned: verify Holy is preferred on Light, while an ordinary elemental-only skillchain still chooses the appropriate elemental spell.
4. Try Fusion and Transfixion on WHM; observe correct Light candidate, including spell recast/fallback behavior.
5. Verify no double casts from old BoomMB or Trust's magic-burst mode, and try a normal zone transition.

**User request history:**
- 2026-11-11: User wants a minimal automatic magic-burst addon, loaded once, that simply hits MBs without setup.
- 2026-11-11: First BoomMB test reported working great, with great timing. User asks whether a WHM with Holy will burst during Light skillchains and requests rename to "Boom".

---

## Previous batch (archived verbatim from delivered BoomMB test1)

# BoomMB testing log

## Current batch: 0.1.0-test1 — November 11, 2026

**Goal**: `//lua load BoomMB` immediately starts automatic magic bursts for Cioara. One appropriate spell attempt per detected skillchain, without changing target or configuring tiers.

**Source context**: Standalone implementation informed by `ekrividus/autoMB` `main` (v1.3.4, December 2023 last push), `DanielHazzard/WindowerAddons` AutoBurst, and the ongoing Trust/TargetSC work. This is **not** a modified or committed branch of the upstream autoMB repository. Canonical development practices from `rerorriM-Mirrorer/ffxi-NPCmirror` have been adopted in `WORKFLOW.md`.

**Baseline evidence**: In a Cioara combat log from November 10, 2026, Fire damage previously registered a real `Magic Burst!` after Liquefaction. This proves that some manual/in-game elemental burst casting has succeeded on Cioara, not that this addon succeeds.

**Static verification**: File parses with installed `texlua` (Lua 5.3/5.4-family syntax check; not the exact Windower 4 Lua 5.1 runtime). This addon avoids Lua 5.2+ language constructs.

**Mock verification**: `tests/mock_test.lua` runs with `texlua` and exercises the actual addon under mocked Windower APIs. 11 tests pass: on-load auto Fire II; spell recast fallback; job-level restriction; MP fallback; target mismatch; `<bt>` fallback; Off; zone cancellation and re-arming; enemy death; silence; and empty packet handling. Mocked packets and spell resources are not equivalent to live server packets.

**Live FFXI verification**: **Not performed.** Cast acceptance and real Magic Burst timing remain pending.

**Current live test requested**:
1. Unload autoMB and set Trust MB Off on Cioara to avoid simultaneous automatic casts. Load BoomMB. Verify one chat startup message and no need to enable anything manually.
2. With Cioara targeting a surviving monster, trigger Liquefaction and watch BoomMB's `Casting Fire...` message, the spell animation, and the server's actual `Magic Burst!` result separately.
3. Try a Light or Distortion skillchain; verify a correct learned elemental spell instead of a high-tier unlearned one.
4. Try a skillchain on a different target; verify BoomMB does not switch Cioara's target or cast on the wrong enemy.
5. Test `//bmb debug on` if no attempt is seen. Collect job/subjob, spell tier currently learned, SC name, FFXI combat lines, and BoomMB messages.
6. Test zoning, loading with Trust, disabling and re-enabling, with no delayed casts after exiting a zone.

**Pending**: Live cast timing and action-lock observations; optional successful-MB feedback and carefully timed second burst after first reliable success. No pet Blood Pact casting in this batch.

**Delivery register**:
- 2026-11-11: Local test package containing `BoomMB.lua`, `README.md`, `WORKFLOW.md`, `TESTING.md`, `docs/PACKETS.md`, and `tests/mock_test.lua`. Source has not been pushed to GitHub. The local commit ID, if any, is recorded in the delivery response.

**User request history**:
- 2026-11-11: User tried autoMB and Trust's `auto` MB mode on Cioara but neither reliably hit MBs; requested simply loading an addon and having it hit magic bursts automatically, without setup rituals.
