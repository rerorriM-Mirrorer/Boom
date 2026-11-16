# Packet notes — test 1 (2026-11-11)

**Incoming 0x028**: Windower's `windower.packets.parse_action(data)` is used to read `packet.targets[*].id` and `packet.targets[*].actions[*].add_effect_message`. Known effect IDs for Light, Darkness, level 1/2 chains and Radiance/Umbra are selected from established Windower addons (autoMB and AutoBurst). This is source-level reference evidence, **not an independent in-game capture**.

Action: detect skillchain effects applied to an NPC and queue a single burst on that mob if it is Cioara's current `<t>` or `<bt>`. No packet injection occurs.

**Open questions**: actual packet behavior on Cioara's targets, FFXI action-lock delay, animation/cast timing, and whether Windower's `parse_action` returns all intended additional-effect IDs under her test conditions. Collect Cioara's combat log and debug output if casts do not occur.

## Test 3 - November 12, 2026 (no new live capture)

- User observed apparent missed level-2 burst opportunities, sometimes with no Boom debug message. The original duplicate-event suppression used integer `os.time()` with `<= 1`, potentially ignoring the same target/effect for up to nearly two seconds and without a message. The interval is now 0.20 seconds via `os.clock()`. This is a code-level explanation of **some possible misses**, not confirmed live packet evidence for the reported events.
- Windower `parse_action` exposes action `message`, `has_add_effect`, and `add_effect_message` in 0x028 action targets. The additional-effect field remains primary. The fallback accepts a recognized skillchain ID from the main `message` when the additional-effect value does not match; this is a conservative parser fallback, not a claim of observed primary-only skillchain packets.
- Regular Debug logs valid skillchains, discarded duplicate packets and missing/invalid/other-target cases, plus final weapon-skill action packets for the selected mob without a recognized chain. Optional Trace logs numeric `category`, `message` and `add_effect_message` plus `has_add_effect` for selected-target action categories (3,4,6,11,13,14,20). These IDs are intended to be collected during a confirmed missed level-2 window, without injecting or modifying packets.
- Only these recognized IDs trigger casts: 288-301, 385-398, 767-770. Other special IDs, including 302 and 732, are not assumed to be ordinary burst-compatible skillchains. Full FFXI live behavior remains unverified for this revision.

## Test 4 - Cioara FFXI log review (2026-11-12)

**Data source:** user-uploaded `Cioara_2026.11.12.log` text export, *not* a raw packet capture. After Boom 0.1.2 was loaded and Debug enabled, Boom reported `Compression detected ... (effect 294)` twice and `Detonation detected ... (effect 300)` once; it printed `Casting Drain` twice and `Casting Aero` once. FFXI subsequently refused the spells due to action readiness. These lines establish that at least those event IDs reached Boom and produced scheduled dispatch attempts, but cannot prove their original packet layout or which addon caused the concurrent action lock.

**Further action observations:** Debug printed category 13, main action message 317, additional 0, no additional effect for ordinary pet actions and category 3, main message 185, additional 0, no additional effect for ordinary weapon skills. Those are valid non-chain outcomes, not evidence of a missed skillchain by themselves. No level-2 skillchain effect was recorded after Debug was enabled in this log. Continue collecting live packet IDs only if a visible MB opportunity goes unrecognized.

## Test 5 - skillchain coordinator (2026-11-16, no live capture)

- **Read, not sent:** incoming 0x028 via `windower.packets.parse_action`: `category`, `actor_id`, `param`, `targets[*].id`, `targets[*].actions[1].message`, `add_effect_message`. Category 3 (weapon skill finish, `param` = weapon skill id) and 13 (avatar ability finish, `param` treated as the job ability id). A step counts only when `message` is a Trust weapon-skill hit id (2, 110, 185, 187, 317, 529, 802). Actor ids are matched against party members and their pets (`get_party()` mob ids and `pet_index`).
- **Chain state** is tracked per mob like Trust's `SkillchainTracker`: an effect id in Boom's table makes the next step (upgraded through Trust's matrix, e.g. Light after Light), otherwise the action restarts at step 1.
- **No packet injection.** Actions are sent as chat input: `/ws "Name" <mob id>`, `/pet "Name" <mob id>`.
- **IPC (not packets):** `boomsc|poll|offer|plan|ack|go|abort|busy|result|set|...` lines between Boom clients on the same PC. Confidence on the category 13 `param` mapping is low until a live capture: Windower's `actions.lua` maps avatar finishes to `job_abilities`, which matches Trust's `skills.job_abilities` ids.
