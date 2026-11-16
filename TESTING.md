# Boom testing log

## Current Development Status - November 16, 2026, test7 (America/Chicago)

- **Source / branch:** `test/sc-coordinator`, after test6.
- **User report:** test6 "working so far" and well liked. Requested distinct colors in the skillchain plan line, and a check of how Boom works with Failsafe.
- **Failsafe review (user's zip, `rerorriM-Mirrorer/Broguypal-Addons` fork, Failsafe 1.1.1-dev, `mode ready`):** it records every outgoing `/ma`, `/ws`, `/pet` (as JA) line, including Boom's `input` commands. On "Unable to ..." text or matching 0x029 messages it waits for readiness (not casting, recast 0, TP 1000+, 0.35s minimum) and re-sends once, within 4 seconds. Its re-send starts a cast or weapon skill, which Boom sees and stops retrying. Overlap: if Boom's 1-second check runs before Failsafe's re-send shows up, both send; the extra input is refused and harmless (a weapon skill uses all TP and blood pacts start a recast, so it can't fire twice).
- **Change in 0.2.2-test7:** Boom and the coordinator watch for Failsafe's "was refused. Waiting for readiness." / "was unsuccessful. Retrying." lines; within 1.5 seconds of one, Boom delays its next re-send by one check (1s) once. Requires Failsafe `notify` on (its default). Plan line: `Skillchain:` 167, character 158, ability 207, ` > ` and ` = ` 0, result 200; changeable with `//boom sc set color_member|color_ability|color_chain <n>`.
- **Offline verification:** Lua 5.1: 37 burst checks, 23 planner, 21 simulation, 8 wiring; LuaJIT burst checks. Not FFXI.
- **Live observation (user, test7):** 158 shows green, 207 light blue, 200 purple in the user's chat (Boom's docs call 207 yellow; the user's screen decides). User prefers light blue names, green abilities, white result: set live with `//boom sc set color_member 207`, `color_ability 158`, `color_chain 0`; defaults changed to match for fresh installs (existing `data/sc_settings.xml` keeps saved values).
- **Live checks pending:** with Failsafe loaded, a refused burst shows Failsafe's line and then at most one more Boom "Retrying".

---

## Current Development Status - November 16, 2026, test6 (America/Chicago)

- **Source / branch:** `rerorriM-Mirrorer/Boom`, branch `test/sc-coordinator` (test6 commit follows test5). `main` still holds the 0.1.3-test4 baseline.
- **Live observations (user logs `Cioara/Myrr/Clairvaux_2026.11.16.log`, test5):** User reports the coordinator "working amazingly". From Cioara's log after the test5 load line: 135 plans announced, 52 game skillchain lines, 160 stop messages: 46 "No skillchain from <step>", 39 step-1 and 11 step-2 timeouts, 22 target gone, 22 "Cioara cannot use Poison Nails (Blood Pact: Rage recast)", 18 "Unexpected Clairvaux Expiacion", 1 low TP, 1 miss. Bursts: Cioara 36 "Magic Burst!" from 46 Boom casts with 21 "Unable to cast spells at this time"; Clairvaux 14 from 46. Myrr's log contains no addon lines (log filter), but Myrr took part (other logs show Myrr's steps and aborts) and its log has 66 "Unable to use weapon skill" lines. Trust's own skillchain chatter stops before Boom test5 loaded, so Trust SC was off.
- **Causes found (code, matched to log order):** (1) Clairvaux's Shield Bash arrives as category 3 with job ability id 46, the same number as weapon skill Expiacion; test5 read it as Expiacion: out-of-turn aborts and a fake open chain that made later plans "continuations" (the one-step plans and "No skillchain from ..." stops). Trust excludes these by message type. (2) The 2-second retry check ran while Carbuncle was still readying Poison Nails; the recast had started, so the client aborted a pact that then landed. (3) Step timeouts follow "Unable to use weapon skill" / "job ability" (casting, singing) and twice "out of range" for a blood pact.
- **Changes in 0.2.1-test6:** ignore category-3 messages 110/317 (job abilities); track readying packets (category 7, and category 6 for blood pacts) and stop retrying once the step began; a blocker that shows the action was used (recast or spent TP) never aborts a retry; refused steps re-sent every `retry_interval` (1s) until begun or the window is under 0.5s; the leader's "continuing" flag travels in `go`; solo release at `solo_tp` 3000 (user decision); `//boom target ...` shortcuts. Bursts: retry when no casting packet arrives within 1s (max 4 inputs, 7s window), retry after an interrupted cast, second burst 0.6s after the first finishes (max 2 per step). First burst delay unchanged at 0.9s.
- **Offline verification (not FFXI):** Lua 5.1: 36 burst checks (28 original + 8 new), 23 planner, 19 simulation (5 new; the Shield Bash, slow blood pact and busy-member tests were confirmed to fail on the test5 coordinator), 8 wiring. LuaJIT runs the burst checks. All files parse.
- **Inferred, confirm live:** category 6/7 readying packets come from the actor (or pet) with `param` 28787 on interruption; casting begin (8) / finish (4) come for our own spells; a 7-second burst window; whether the user's failsafe addon also re-sends refused commands (not yet seen; if it does, both may re-send the same spell).
- **Live checks pending:** (1) no more "Unexpected Clairvaux Expiacion" during Shield Bash; (2) Cioara's blood pact steps complete without "cannot use ... recast"; (3) count "Unable to use weapon skill" followed by a successful step (look for `SC: Step n ... (retry k)` with debug on); (4) a 3000 TP lone release; (5) bursts: "Retrying" after "Unable to cast spells at this time" and whether it lands as Magic Burst; "Bursting again" second bursts; (6) any double casts with the failsafe addon loaded.
- **Rollback:** unload Boom and restore the test5 folder; or `//boom retry off`, `//boom multi off`, `//boom sc solo off` to return individual behaviors to test5.

---

## Current Development Status - November 16, 2026 (America/Chicago)

- **Source / branch:** GitHub `rerorriM-Mirrorer/Boom` (new, was empty). `main` = baseline commit of the user's installed `0.1.3-test4` zip (no code change). This work is on **`test/sc-coordinator`**; keep it off `main` until live success.
- **Change in 0.2.0-test5:** New skillchain coordinator in `sc/` (`trust_data.lua`, `planner.lua`, `protocol.lua`, `coordinator.lua`, `boom_sc.lua`) and `//boom sc` commands. Boom.lua only gains a guarded `require`, the `sc` command route, one help line, one status line and the startup text. Burst detection, 0.9-second delay, spell choice and targeting are unchanged.
- **Trust foundation (read from Trust `8f65874`, `test/autorun-and-settings-fix`):** chain properties come from Trust's own `cylibs/res/skills.lua` and combinations/levels from `cylibs/util/skillchain_util.lua`, loaded from the installed Trust folder at runtime (not copied). Combination order follows `SkillchainBuilder:get_skillchain_by_properties`; closed at level 4 (`SkillchainStep:is_closed`); window = delay (3 or skills.lua value) then expires at start + delay + 8 - step (`skillchain_tracker.lua`); WS hit message ids from `action_message_util`; WS/BP preconditions and WS reach formula from `weapon_skill.lua`, `blood_pact_rage.lua`, `battle_util.lua`.
- **Offline verification (not FFXI):** Lua 5.1 (and LuaJIT for the burst tests). `tests/mock_test.lua` 28 burst checks unchanged and passing. `tests/sc_planner_test.lua` 21 checks on Trust's real data. `tests/sc_coordinator_test.lua` 14 checks: three to six simulated clients on a fake IPC bus and a fake game producing action packets. `tests/sc_wiring_test.lua` 8 checks loading the real Boom.lua. All files parse with `luac5.1 -p`. Run from the Boom folder: `BOOM_TRUST=<Trust folder> lua5.1 tests/sc_planner_test.lua` (same for the other sc_ tests). Offline tests stub Windower's `sets`/`lists` (Windower's own copies need its patched parser).
- **Bug found by simulation and fixed before delivery:** a Lua `a and b or c` slip made the summoner refuse its own blood pact step (checked TP). Also added: continuing an on-target chain into an off-target one is refused; a refused step is re-sent once after 2 seconds.
- **Inferred, confirm live:** Windower `require` finds Trust's files after Boom adds the Trust folder to `package.path`; avatar Blood Pact packets are category 13 with `param` = the job ability id (skills.lua `job_abilities` keys); `get_abilities().job_abilities` lists only the summoned avatar's pacts; `/ws "Name" <mob id>` and `/pet "Name" <mob id>` work as input (Trust sends the same form); 21-yalm summoner-to-mob blood pact range; 2 seconds is enough to see one's own action before retrying; IPC reaches only clients on the same PC.
- **Live checks pending:** see the batch below.
- **Rollback:** `//lua unload Boom`, restore the `0.1.3-test4` folder (or `//boom sc off`, which is sent to every client and saved, to keep only bursting). Back up `data/` first.

---

## Batch: 0.2.0-test5 - November 16, 2026

**User request:** Party skillchain coordinator built into Boom, working with any number of multiboxed characters, as a test for overhauling Trust's automatic skillchains; reuse Trust's logic where possible. User will test with Trust skillchains Off on all characters.

**Install:** On every character `//lua unload Boom`. Back up `addons/Boom/data/` if present. Copy the delivered `Boom/` folder over `addons/Boom/` (it adds `sc/`). On every character `//trust sc off` (Trust AutoSkillchainMode Off) - Trust must stay installed. `//lua load Boom` on every character. Startup should end with `| Skillchains ON`. If it says Trust data not found: `//boom sc trust C:/path/to/Windower/addons/Trust/` on that character.

**Live tests requested (record results here):**

1. `//boom sc status` on each character: `Trust data:` shows the Trust folder; settings identical on all.
2. Two melee at 1000+ TP engaged on one mob: both get a `Skillchain:` line with the same plan; only the planned order fires; the closer makes the named chain; Boom bursts on it. Note real seconds between steps.
3. Cioara with an avatar out, Blood Pact: Rage ready, one melee at 1000 TP: confirm the blood pact fires on the plan's mob (not another target) and its packet advances the plan (if Cioara's step is never recognized, `//boom debug on` and report the `SC:` lines - category 13 mapping is inferred).
4. Three members: confirm a 3-step chain, and that nobody uses a weapon skill inside another's step delay.
5. `//boom sc hold on` with one member under 1000 TP: others wait; when the third reaches 1000 the 3-step runs. Then confirm hold is skipped when the party has no 3-step chain.
6. `//boom sc target Darkness` (or a property your party can and cannot make): on-target chain chosen when possible, otherwise `fallback` in `//boom sc status` Last result.
7. `//boom sc opener <a WS>`: that opener is used.
8. Manually weapon skill out of turn mid-plan: every client prints `Skillchain stopped: Unexpected ...` and recovers.
9. Kill the mob or zone mid-plan: no late weapon skills.
10. Watch for "Unable to use weapon skill" refusals and whether the 2-second retry lands inside the window.

**Not done:** Trust's own opener-fallback fix (separate change to Trust); aeonic properties (Trust includes them only with the matching weapon; the coordinator ignores aeonic for now); burst-element preference for Boom's mages.

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
