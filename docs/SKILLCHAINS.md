# Skillchain coordinator design (0.2.0-test5)

Test bed for overhauling Trust's automatic skillchains. Labels: **Verified** = read in Trust `8f65874`; **Inferred** = reasoned, not tested in game.

## Why not Trust as-is (Verified)

Each client's `Skillchainer:check_skillchain` decides only for itself, once a second; `get_starter_ability` takes the first opener of the first buildable Light/Darkness chain and gives up if that one ability is unusable (no fallback); several clients can queue weapon skills in the same window.

## Layers

| File | Windower calls | Role |
|---|---|---|
| `sc/trust_data.lua` | `io.open`, `require` | Loads Trust's `skills.lua` and `skillchain_util.lua` from the Trust folder; exposes plain strings (properties, combine, level, elements, delay). |
| `sc/planner.lua` | none | Pure search: ordered chains from every member's offer and the open window; options; returns execute / hold / none. |
| `sc/protocol.lua` | none | IPC line format and poll ordering. |
| `sc/coordinator.lua` | injected `windower` | Readiness, offers, poll/plan/ack/go, per-mob chain tracker, packet-timed execution, aborts, settings sync. |
| `sc/boom_sc.lua` | yes | Events, `data/sc_settings.xml`, `//boom sc` commands. |

## Protocol

`poll(pid, leader, mob)` -> every party Boom replies `offer(pid, name, tp, abilities)` -> leader plans after `poll_window` -> `plan(pid, mob, chain, steps)` -> each step's member re-checks and replies `ack(ok|reason)` -> leader sends `go` when all ack within `ack_window`. Concurrent polls: earliest second, then name, then counter wins; the others yield. A client busy in a plan answers `busy`. `abort` stops a plan everywhere; `result` tells others a poll ended without a plan; `set` copies a setting.

Everyone follows the plan from action packets; only the step's member acts. Step k+1 fires at (step k packet) + step k delay + `step_margin`. A fresh plan's opener needs no chain effect; every later step must show one or the plan stops.

## Moving into Trust later

1. Trust fix independent of Boom: in `get_starter_ability`/`get_next_ability`, try each buildable opener until one passes its conditions.
2. Replace `trust_data` with direct use of Trust's tables; keep `planner.lua` unchanged.
3. Coordinated mode in Trust: `check_skillchain` stands down while a plan is active; the planned step goes through `perform_ability` (action queue); offers come from `ability:get_conditions()`.
