# Proc This!: development notes

Proc This! glows action-bar buttons when the conditions a player sets for a spell or item are
met. WoW: Forever, Interface 16001 (a Midnight 12.x client running Classic content). This file
holds the architecture, the conventions, the milestone plan and its progress. API facts and their
verification status: [API_COMPATIBILITY.md](API_COMPATIBILITY.md). User-facing changes:
[CHANGELOG.md](CHANGELOG.md).

## Milestones

| # | Milestone | Status |
|---|---|---|
| 1 | Condition engine reliability | **Done in 1.16.0, waiting for review and in-game validation** |
| 2 | Advanced condition evaluation (Boolean expressions, dependency caching, cycles) | Not started |
| 3 | Spell, item and aura tracking (compatibility layer, macros) | Not started |
| 4 | Button discovery and rendering (providers, lifecycle, profiling) | Not started |
| 5 | User experience (live status, priority, templates, import / export) | Not started |
| 6 | Diagnostics and release readiness | Not started |

## Conventions

- Evolve, don't rewrite. Saved variables, character rules, rule ids and migrations are kept.
- No API is used before it's checked against Forever's API docs (`Blizzard_APIDocumentationGenerated`)
  and, where it matters, in game. API_COMPATIBILITY.md says which.
- A hidden ("secret") value is never compared, tested or read: it's handed to a game-side check
  (`SetAlphaFromBoolean`, a step curve with `UnitHealthPercent` / `UnitPowerPercent`), or the
  condition is UNKNOWN.
- Unknown never counts as true or false (see "Result model"). A glow that shows at the wrong time
  is worse than one that doesn't show because the answer is genuinely unknown.
- No unused code or settings (luacheck clean apart from the slash-command globals).
- Offline tests for logic (`tests/run_tests.py`); game behaviour is checked in game (checklist
  below) and never claimed from the tests.

## Architecture (1.16.0)

Load order (ProcThis.toc): Core → Result → State → Glow → UI → Options.

| File | Module | Does |
|---|---|---|
| Core.lua | `ns` | Rule and condition defaults (`NEW_RULE`, `NEW_AURA`), saved variables (`ProcThisDB`: shared settings, `chars[Name-Realm].rules`), migrations of older rule formats, rule ids, per-character set-up and copying, spell / item names, glow colours and looks, EllesmereUI / FlareUI detection |
| Result.lua | `ns.Result` | The result model: TRUE / FALSE / GATED / UNKNOWN / ERROR, and how they combine (AND, OR, NOT). Pure Lua |
| State.lua | `ns.State` | Every condition reader: buffs (direct, Cooldown Manager, estimates), target debuffs (direct, Cooldown Manager, estimates from your casts per target), health / mana / combo points / rage / energy (readable, or step curves for hidden values), cast time, melee, castable, cooldown, control, combat, proc flag |
| Glow.lua | `ns.Glow` | Button discovery (Blizzard bars, EllesmereUI's `EABButton`s), what each button holds (spell, item, macro), the evaluator (rows → groups → rule), the update loop and events, the glow frames (Blizzard's alert template, gates, styles, EllesmereUI glows) |
| UI.lua | `ns.UI` | The shared settings-window kit (and EllesmereUI / FlareUI looks) |
| Options.lua | — | The settings window (rules list, editor, look, settings, help), live status per rule, start-up, slash commands |

### Data model

- A rule: `{ id, enabled, spell (name, ID or item link), auras = { rows }, groupModes = { "all" | "any" },
  join = "and" | "or", melee, usable, ready, control, combat, proc, look fields }`.
- A row (`auras[i]`): `kind` = buff / debuff (on `unit` player / target, `mode` present / missing,
  `mine`, and for your target debuffs the backup `dur`, `charges`, `usedBy`), instant, health,
  mana, combo, rage, energy (`op`, `pct`), or rule (`rule` = another rule's id, `mode`).
- Rows are in numbered groups: a group needs all its rows ("all") or one ("any"); the rule needs
  every group ("and") or one ("or").

### Evaluation path

`Glow.Update` (events, merged to at most every 0.05 s, plus a 0.25 s safety tick):
1. For each rule with a spell: `Glow.Evaluate(rule)` → result. Per spell: a TRUE result glows
   plainly and wins; otherwise the first GATED rule's gates are used; FALSE / UNKNOWN / ERROR
   never glow.
2. For each visible action button: the spell or item it holds (`ButtonSpell`: cached per slot,
   macros read every time) → glow, gated glow, or hide.

`Glow.Evaluate(rule)` (guarded against loops and errors):
1. Simple checks: in combat, control, being hit in melee. A confirmed FALSE ends it.
2. Each group: its rows through `Glow.CheckAura` → `Result.All` ("all") or `Result.Any` ("any");
   the groups through `Result.All` ("and") or `Result.Any` ("or").
3. Proc flag, off cooldown, castable / usable.
4. Everything through `Result.All`; more than 4 gates → UNKNOWN.

### Result model (1.16.0)

| Result | Means | Glows |
|---|---|---|
| TRUE | confirmed: it holds | yes |
| FALSE | confirmed: it doesn't | no |
| GATED | a hidden value decides: the gates on the glow open only when it holds | when the game says so |
| UNKNOWN | not enough information (hidden, untracked, never seen, an unsupported combination) | no |
| ERROR | reading it failed | no |

Combining (Result.lua):
- AND: a FALSE decides it; else ERROR; else UNKNOWN; else all the gates together (exact: gates
  multiply); else TRUE.
- OR: a TRUE decides it; one GATED stands for the OR (the game opens it only when that branch
  holds: never a wrong glow); two or more GATED can't be combined (gates only multiply) →
  UNKNOWN; else UNKNOWN, else ERROR, else FALSE.
- NOT ("missing", "rule inactive"): TRUE ↔ FALSE; UNKNOWN and ERROR stay; GATED flips only when it
  hangs on one invertible gate, else UNKNOWN.

Each aura answer also says how it was known: read directly, seen (details hidden), the Cooldown
Manager, an **estimate**, or unknown. Estimates count as answers (TRUE / FALSE) but are labelled
in the explanations: they can be wrong (see below).

### Aura sources (1.16.0)

| Aura | Out of combat | In combat |
|---|---|---|
| Your buffs | read directly | the Cooldown Manager if tracked; else an estimate, else UNKNOWN |
| Your debuffs on your target | read directly | the Cooldown Manager if tracked; else an estimate from your casts on that target |
| Anyone's buffs on your target, debuffs on you | read directly | the Cooldown Manager if tracked; else UNKNOWN |

Buff estimates (no Cooldown Manager), from what was last read and your casts since:
- you cast it after the last read, and its duration is known (from a read): on for that long,
  then off. Can be wrong: the cast may not have applied it.
- last read on, with an end time: on until then, then off. Can be wrong: dispelled, cancelled.
- a buff read with charges or stacks (e.g. Lightning Shield): once anything hits you after the
  cast or read (`UNIT_COMBAT` on you, except heals and energize; a hidden kind counts), UNKNOWN:
  the hit may have used the last charge. (Found in game, 1.16.0 test: the estimate said "on" after
  the shield was used up.)
- last read on, no end time: on. Can be wrong: removed.
- last read off, and it's the rule's own spell (only your cast puts it on you): off until you
  cast it. Can be wrong: someone else casts it on you.
- anything else: UNKNOWN.

Target debuff estimates (no Cooldown Manager), from your casts, kept per target (its GUID; when
the game hides GUIDs, only for the current target):
- on for the row's duration (or the one read out of combat, or 12 s assumed) after your cast, until
  its charges are used by the spells named; off when no cast of yours is recorded on that target.
  Can be wrong: a cast that missed or was resisted, a cast that went to another unit (mouseover,
  focus), a duration that changed.
- forgotten when combat ends (the game answers directly again).

## Milestone 1 audit (1.15.1 source)

Severity: High = wrong glow in normal play; Medium = wrong in some situations; Low = cleanup.

### Confirmed defects (fixed in 1.16.0)

| # | Sev. | Defect | Where |
|---|---|---|---|
| 1 | High | A buff never seen (not tracked in the Cooldown Manager, in combat) read as **absent** (`known[name] or false`): a "buff missing" row glowed when the buff may have been on (a proc, a pre-combat buff seen only as "unknown"). Now UNKNOWN unless an estimate applies | State.lua `HasBuff` |
| 2 | High | A cast of a spell marked the same-named buff as **on, forever** (`known[n] = true`, never cleared in combat): "missing" rows never glowed again until combat ended, "present" rows glowed after the buff ended. Now an estimate bounded by the buff's known duration | State.lua `OnCast` |
| 3 | High | A hidden spell cooldown read as **ready** (`not Readable(isActive) → true`): a rule could glow a spell on cooldown. Forever's docs mark `GetSpellCooldown` as secret when cooldowns are restricted. Now a gate on the hidden flag | State.lua `Ready` |
| 4 | Medium | Your debuff casts were forgotten on every target switch: switching back to a target you'd dotted read as **absent** ("missing" glowed). Now kept per target GUID | State.lua `TargetDebuff`, `OnTargetChanged` |
| 5 | Medium | Unknown or failed reads became TRUE: no cooldown info, an unreadable item cooldown, a hidden "control" flag, a missing usable API. Now UNKNOWN / ERROR / a gate | State.lua `Ready`, `HasControl`, `Usable` |
| 6 | Medium | "Rule X is inactive" on a rule that couldn't be told (hidden, untracked) read as TRUE (`not on → true`). Now UNKNOWN | Glow.lua `CheckAura` |
| 7 | Low | A failed buff read by index (`pcall` error) read as absent. Now unknown | State.lua `AuraByName` |
| 8 | Low | Unknown and error results all showed as "Not glowing: …", indistinguishable from a confirmed no. The status now says "can't tell" / "error", and each aura's source (estimate details included) | Options.lua `UpdateStatus` |

### Potential risks (not changed in M1)

| # | Risk | Milestone |
|---|---|---|
| R1 | Two or more hidden checks joined by OR (or in an "any" group) can't glow: UNKNOWN (before: "can't be decided", no glow). | M2 (Boolean expressions) |
| R2 | At most 4 gates per glow (`MAX_GATES`); more → UNKNOWN. | M2 |
| R3 | A rule used by several "Rule X" rows is evaluated once per row, every update; no caching. | M2 |
| R4 | Several rules for one spell: only the first GATED rule's gates are used, so a later GATED rule that holds doesn't glow (never a wrong glow). | M2 |
| R5 | Estimates can be wrong (see "Aura sources"): a cast that missed, a buff ended early. They're labelled, not hidden. | M3 |
| R6 | Macros: the spell or item is read every update (`GetActionInfo` subtype, `GetMacroSpell`, `GetMacroItem`); conditional macros follow what the game reports for the current conditions. Not verified for every macro form. | M3 |
| R7 | Buttons: a fixed list of Blizzard bars plus EllesmereUI's `EABButton1..180` (rebuilt every 5 s while EllesmereUI is on). No provider interface yet. | M4 |
| R8 | Every rule is evaluated on every update (events merged to 0.05 s, plus a 0.25 s tick for the melee window and Cooldown Manager changes, which have no events). Not profiled yet. | M4 |
| R9 | A target debuff row on "missing" with no target reads "absent" (true): the rule can glow with no target if its spell is castable. Unchanged behaviour. | M5 (review) |
| R10 | During the global cooldown, a hidden cooldown flag (finding 3) reads "on cooldown": the gated glow may dip for the GCD. Safer than glowing while on cooldown. | Check in game |

## Testing

### Offline

```
pip install lupa
python3 tests/run_tests.py
```

19 tests (1.16.0): the result model (AND / OR / NOT), buff estimates and unknowns, debuff
estimates per target and charges, cooldown / usable / control results, rule evaluation with mixed
results, groups with hidden checks, dependencies (active, inactive, loops, unknown), several rules
for one spell, the gate limit, and saved-variable migration with duplicate ids. The mock's hidden
values are tables; the real client is stricter, so the tests prove logic, not client behaviour.

### In-game checklist (Milestone 1 → 2)

1. Install 1.16.0, `/reload`. Your rules are all there, with their looks. No Lua errors.
2. Out of combat: each rule glows as before.
3. A buff rule on "missing" (e.g. Lightning Shield missing) **with the buff not in the Cooldown
   Manager**: in combat, open `/pt` on that rule. The status line for the buff now says "estimate:
   …" or "can't tell in combat …". Cast it: "from your cast N s ago". Glows only when the estimate
   says it's missing.
4. The same with the buff **in** the Cooldown Manager (Tracked Buffs): "from the Cooldown Manager",
   and it follows the buff exactly.
5. A target debuff rule on "missing" (e.g. Flame Shock): dot target A, switch to B (glows), back to
   A (doesn't glow while your Flame Shock should still be on A).
6. A rule with "Off cooldown": in combat, a spell on cooldown never glows. If the status ever says
   "decided by the game", note it (the cooldown was hidden), and whether the glow dips during the
   global cooldown.
7. Any status showing "can't tell" or "error": screenshot it with the rule's settings.

Results (1.16.0 test build, Shaman, solo):
- 2, 4: pass. Lightning Shield tracked: "on you / not on you (from the Cooldown Manager)", glow
  exact.
- 3: pass after a fix. Not tracked: "not on you (estimate: not on you when last seen …)" glows;
  cast: "on you (estimate: from your cast 4 s ago (lasts 600 s))", no glow. But 16 s later the
  shield's charges were used up and the estimate still said "on". Fixed: charged buffs become
  "can't tell" once you're hit.
- 1, 5, 6, 7: pending.

## Known limitations

- Buffs and debuffs not tracked in the Cooldown Manager can't be followed exactly in combat; the
  settings window says so per row, and estimates are labelled.
