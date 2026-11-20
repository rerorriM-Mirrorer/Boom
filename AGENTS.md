# Agent entry point

Before making changes, read this repository's current `WORKFLOW.md` and `TESTING.md`, and compare with the shared canonical NPCMirror `WORKFLOW.md`. This is a first-test addon: preserve minimal load-and-burst behavior and distinguish mocked checks from actual FFXI verification. Keep changes on test branches until the user confirms live success.

## REPO

Project-specific guidance moved from the former project-specific `WORKFLOW.md` (2026-11-20). The addon focus: **load the addon and it tries to hit magic bursts automatically.** Testing ZIP contents follow the canonical README-only rule in `WORKFLOW.md`.

- Prefer the smallest responsible code change; do not introduce menus, unrelated automation, or settings that complicate the initial use case.
- `main` represents known-good behavior only after live testing. Experimental changes live on test branches. Keep changes traceable with small coherent commits.
- Start each development session by checking the current `AGENTS.md`, `WORKFLOW.md`, and `TESTING.md`. Preserve old testing observations rather than overwriting them.
- Follow Windower 4 conventions, use learned game/resource data, and avoid unverified packet injection. Keep user-modified settings under `data/` if settings are introduced.
- Build on actual action-packet skillchain events. Treat burst-dispatch, spell-casting, and server-confirmed magic-burst messages as distinct outcomes.
- Check static Lua parse, mocked smoke tests, regression behavior, and finally in-game behavior. Report these separately.
- Prefer quiet, meaningful messages. Provide documented `help`, `status`, `restart`, and `unload` commands. Keep auto activation on load as the primary action.
- For **all in-game messages** (including debug, trace, help, startup, status and lifecycle output), follow the latest canonical `WORKFLOW.md` exactly: require Windower `chat`; use `string.color()` fragments and `windower.add_to_chat(0, ...)`. Color `[Boom]` 200, headings 167, command `//boom` and `->` 200, syntax 207, descriptions/values 0. Show ON in green 158 and OFF in red 167. Generate plain ASCII hyphens instead of en/em dashes, which render incorrectly in FFXI. Output should remain concise when debug/trace are off. By explicit November 12 user preference, Debug message bodies use yellow color 207 rather than the default white 0. This exception applies only to Debug output; Trace, ordinary values, and command descriptions retain their standard colors.
- Keep `README.md` and `TESTING.md` current.
- For packet-related changes, record observed packet IDs, fields and confidence in `docs/PACKETS.md`. No injection is used in this build.
