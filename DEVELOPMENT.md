# Proc This!: development notes

Proc This! glows action-bar buttons when the conditions a player sets for a spell or item are
met. WoW: Forever, Interface 16001 (a Midnight 12.x client running Classic content). This file
holds the architecture, the conventions, the milestone plan and its progress. API facts and their
verification status: [API_COMPATIBILITY.md](API_COMPATIBILITY.md). User-facing changes:
[CHANGELOG.md](CHANGELOG.md).

## Milestones

| # | Milestone | Status |
|---|---|---|
| 1 | Condition engine reliability | Done in 1.16.0, verified in game, reviewed |
| 2 | Advanced condition evaluation (Boolean expressions, dependency caching, cycles) | Done in 1.17.0, verified in game, reviewed |
| 3 | Spell, item and aura tracking (compatibility layer, macros) | Done in 1.18.0, verified in game, reviewed |
| 4 | Button discovery and rendering (providers, lifecycle, profiling) | Done in 1.19.0, verified in game, reviewed |
| 5 | User experience (live status, priority, templates, import / export) | Done in 1.20.0, verified in game |
| 6 | Diagnostics and release readiness | **Done in 2.0.0 (the release of 1-6), waiting for in-game validation** |

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

## Architecture (2.0.0)

Load order (ProcThis.toc): Core → Share → Compat → Result → State → Buttons → Glow → UI → Options.

| File | Module | Does |
|---|---|---|
| Core.lua | `ns` | Rule and condition defaults (`NEW_RULE`, `NEW_AURA`), saved variables (`ProcThisDB`: shared settings, `chars[Name-Realm].rules`), migrations of older rule formats, rule ids, per-character set-up and copying, spell / item names, glow colours and looks, EllesmereUI / FlareUI detection |
| Share.lua | `ns.Share` | Rules as text (1.20.0): `Export(rules, rule?)` ("PT1:" and a plain serialization; one rule comes with the rules it uses), `Import(text)` (its own parser, never `loadstring`; only known fields, each checked for type and allowed values; size, depth and count limits) |
| Compat.lua | `ns.API` | The compatibility layer (1.18.0): every game function used to read conditions and buttons, by name, with the forms it may take (newer `C_` namespaces, older globals); `API.Call` (safe: answered / failed / not on this client), `API.Has`, `/pt api` |
| Result.lua | `ns.Result` | The result model: TRUE / FALSE / GATED / UNKNOWN / ERROR, and how they combine (AND, OR, NOT). Pure Lua |
| State.lua | `ns.State` | Every condition reader: buffs (direct, Cooldown Manager, estimates), target debuffs (direct, Cooldown Manager, estimates from your casts per target), health / mana / combo points / rage / energy (readable, or step curves for hidden values), cast time, melee, castable, cooldown, control, combat, proc flag |
| Buttons.lua | `ns.Buttons` | Button providers (1.19.0): Blizzard's bars, EllesmereUI's `EABButton`s (and their shapes), LibActionButton-1.0 bars (Bartender4, ElvUI...); the list (built again on a UI loading, entering the world, a restyle, or every 5 s while a provider whose buttons come and go is present), buttons that dropped out, each button's action slot |
| Glow.lua | `ns.Glow` | What each button holds (spell, item, macro), the evaluator (rows → groups → rule), the update loop and events, the glow frames (Blizzard's alert template, gates, styles, EllesmereUI glows) |
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
1. A new pass (`Glow.NewPass`): every rule's result, and the cooldown / castable / control /
   combat reads, are worked out once in it (the same reads are the same gates everywhere).
2. For each rule with a spell: `Glow.Evaluate(rule)` → result. Per spell: a TRUE result glows
   plainly and wins (the first one's look); otherwise the terms of every GATED rule, in rule order,
   made exclusive (`Result.Disjoint`), one glow layer each (at most 4); FALSE / UNKNOWN / ERROR
   never glow.
3. For each visible action button: the spell or item it holds (`ButtonSpell`: cached per slot,
   macros read every time) → its layers, or hide.

`Glow.Evaluate(rule)` (once per pass; a loop is an ERROR naming its rules; errors are caught):
1. Simple checks: in combat, control, being hit in melee. A confirmed FALSE ends it.
2. Each group: its rows through `Glow.CheckAura` → `Result.All` ("all") or `Result.Any` ("any");
   the groups through `Result.All` ("and") or `Result.Any` ("or").
3. Proc flag, off cooldown, castable / usable.
4. Everything through `Result.All`.

### Result model (1.16.0; gate sets 1.17.0)

| Result | Means | Glows |
|---|---|---|
| TRUE | confirmed: it holds | yes |
| FALSE | confirmed: it doesn't | no |
| GATED | a hidden value decides: the gates on the glow open only when it holds | when the game says so |
| UNKNOWN | not enough information (hidden, untracked, never seen, an unsupported combination) | no |
| ERROR | reading it failed | no |

Combining (Result.lua):
A GATED result carries a **gate set**: an OR of ANDs (terms, each a list of gates that must all
hold). Gates on one frame chain multiply (AND); an OR is drawn as several glow layers on the
button, one per term, made exclusive so that at most one shows (term k AND NOT each term before
it). A gate knows its opposite (`gate.inv`): a term holding both is dropped, and the same read is
one gate within a pass, so `(A and B) or C` never draws two layers for one case.

- AND: a FALSE decides it; else ERROR; else UNKNOWN; else the gate sets multiplied out; else TRUE.
- OR: a TRUE decides it; the GATED ones' terms together (`a or (a and b)` = `a`); with an UNKNOWN
  or ERROR beside them the set is **partial** (that branch can't light it); without any GATED:
  UNKNOWN, else ERROR, else FALSE.
- NOT ("missing", "rule inactive"): TRUE ↔ FALSE; UNKNOWN and ERROR stay; GATED by De Morgan
  (needs every gate's opposite: health / power curves and hidden flags have one). A partial set
  can't be negated: UNKNOWN (its opposite would glow wrongly).
- Limits: at most 6 gates in a term (`MAX_GATES`, the gate frames per layer), 8 terms while
  combining (`MAX_TERMS`), 4 layers per button. What doesn't fit is left out and the set is
  partial: it may miss a glow, never show a wrong one. Nothing left → UNKNOWN "too many hidden
  conditions at once". A set that can never hold (only contradictions) → FALSE.
- `tests/run_tests.py` checks this against every combination of four hidden values for 300 random
  nested AND / OR / NOT formulas: exact sets light exactly when the formula holds, partial ones
  never when it doesn't, and two layers never light at once.

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
| R1 | Two or more hidden checks joined by OR (or in an "any" group) can't glow: UNKNOWN (before: "can't be decided", no glow). | Fixed in 1.17.0 (gate sets, layers) |
| R2 | At most 4 gates per glow (`MAX_GATES`); more → UNKNOWN. | 1.17.0: 6 per layer, 4 layers; what doesn't fit is left out (partial) |
| R3 | A rule used by several "Rule X" rows is evaluated once per row, every update; no caching. | Fixed in 1.17.0 (once per pass) |
| R4 | Several rules for one spell: only the first GATED rule's gates are used, so a later GATED rule that holds doesn't glow (never a wrong glow). | Fixed in 1.17.0 (each GATED rule's terms are a layer) |
| R5 | Estimates can be wrong (see "Aura sources"): a cast that missed, a buff ended early. They're labelled, not hidden. | 1.18.0: casts at other units and target switches mid-cast fixed (defects 12-14); a miss or resist still can't be seen (no event says which spell missed) |
| R6 | Macros: the spell or item is read every update (`GetActionInfo` subtype, `GetMacroSpell`, `GetMacroItem`); conditional macros follow what the game reports for the current conditions. Not verified for every macro form. | 1.18.0: modifier changes update at once; `/pt buttons` shows what each macro reads as, to check forms in game |
| R7 | Buttons: a fixed list of Blizzard bars plus EllesmereUI's `EABButton1..180` (rebuilt every 5 s while EllesmereUI is on). No provider interface yet. | 1.19.0: providers (Blizzard, EllesmereUI, LibActionButton); other bar addons need a provider |
| R8 | Every rule is evaluated on every update (events merged to 0.05 s, plus a 0.25 s tick for the melee window and Cooldown Manager changes, which have no events). Not profiled yet. | 1.19.0: only rules whose spell is on a shown button; looks set once; `/pt perf` measures it |
| R9 | A target debuff row on "missing" with no target reads "absent" (true): the rule can glow with no target if its spell is castable. Unchanged behaviour. | 1.20.0: no target → FALSE "no target", either mode (defect 26) |
| R10 | During the global cooldown, a hidden cooldown flag (finding 3) reads "on cooldown": the gated glow may dip for the GCD. Safer than glowing while on cooldown. | Check in game |

## Milestone 2 (1.17.0)

Found while working on it (1.16.0 source):

| # | Sev. | Defect | Fix |
|---|---|---|---|
| 9 | Medium | OR with an unknown branch: `Any(GATED a, UNKNOWN u)` answered GATED a (right: a holding is enough), but a "Rule X is inactive" row then took its opposite, `not a`, and could glow while `u` made X active. | Such a set is partial; its opposite is UNKNOWN |
| 10 | Low | A loop between rules said only "rules depend on each other in a loop". | The error names the rules (`A > B > A`); the rule picker no longer offers a rule that needs this one (`ns.DependsOn`) |
| 11 | Low | `Result.LABEL` was never used. | Removed |

Changes:
- `Result.lua`: gate sets (OR of ANDs), `Gates`, `All` / `Any` / `Not` on sets, partial sets, `Disjoint`.
- `Glow.lua`: glow layers per button (`btn.SG_Layers`; each layer the 1.16.0 glow: gate frames, pulse,
  start animations, EllesmereUI glows); passes (`NewPass`, rule results and reads once per pass);
  loops named; every GATED rule for a spell counts.
- `Core.lua`: `ns.DependsOn` (the rule picker leaves out rules that would make a loop).
- `Options.lua`: a partial GATED result says so ("partly: … it may not glow every time it should").

No new game APIs: layers are more of the same frames and `SetAlphaFromBoolean` / curve gates.

## Milestone 3 (1.18.0)

Audit of the 1.17.0 tracking code:

| # | Sev. | Defect | Fix |
|---|---|---|---|
| 12 | Medium | A debuff cast at another unit (a mouseover or focus macro) was recorded on your target: "missing" didn't glow on your target, and a spell that uses up charges took one from your target's. | `UNIT_SPELLCAST_SENT` says where the cast went: a named unit that isn't your target isn't recorded |
| 13 | Medium | A cast with a cast time, and a target switch during it: recorded on the target you switched to. | The target is taken when the cast starts (`SENT`), matched to `SUCCEEDED` by castGUID |
| 14 | Medium | A buff cast on someone else (a mouseover heal-over-time, a party buff) counted as on you. | A cast sent to a named unit that isn't you isn't counted as a buff on you |
| 15 | Low | Durations were learned only for the session: after a `/reload` or login, the first cast of a buff in combat was "can't tell", and a target debuff without its own "lasts" was assumed 12 s. | Kept per character (`chars[...].durations`, `charged`); never read: the spell's tooltip ("for 12 sec", "Lasts 10 min"), labelled |
| 16 | Low | `GetActionInfo` was called unprotected: an error in it stopped every glow update. | Through the compatibility layer |
| 17 | Low | A macro with `[mod]` conditions changed spell on a modifier key, but the glow followed only at the next 0.25 s tick. | `MODIFIER_STATE_CHANGED` updates at once |
| 18 | Low | State.lua: a comment for a removed function, and the cast-time comment far from its function. | Removed / moved |

Changes:
- `Compat.lua` (new): the compatibility layer; State and Glow read through it (`API.Call`).
- `State.lua`: durations and charges kept per character (`Mem()`), `TooltipDuration`, `Duration`
  (learned, else tooltip), `OnSent` / `OnCast(spellID, castGUID)` with where each cast went.
- `Glow.lua`: `UNIT_SPELLCAST_SENT`, `MODIFIER_STATE_CHANGED`; `ButtonReport` (`/pt buttons`).
- `Options.lua`: `/pt spell` (cast time, duration and where it's from, charges; `/pt cast` still
  works), `/pt buttons`, `/pt api`.

Where a cast went (`State.OnSent`), from `UNIT_SPELLCAST_SENT`'s target name:
- empty, or hidden: as before (your target now; on you);
- your target's name (a realm after a "-" is ignored): your target when the cast started; if the
  game hides its GUID and you've changed target since, it isn't recorded;
- another name: not your target (no debuff recorded, no charge used there); and if it isn't your
  name either, not a buff on you.
Two units with the same name can't be told apart (a mouseover cast on a second "Southern Sand
Crawler" counts as on your target).

## Milestone 4 (1.19.0)

Audit of the 1.18.0 button and rendering code:

| # | Sev. | Defect | Fix |
|---|---|---|---|
| 19 | Medium | Only Blizzard's and EllesmereUI's buttons were known, as a fixed list in Glow.lua: no glows on bars built on LibActionButton-1.0 (Bartender4, ElvUI). | Button providers (Buttons.lua), LibActionButton through its `buttonRegistry` |
| 20 | Low | A button that dropped out of the list (a bar turned off) kept its glow. | Dropped buttons are handed back with the list, and their glows taken off |
| 21 | Low | Every rule was worked out on every update, also rules whose spell was on no shown button. | Only rules for spells on shown buttons (rules they use are worked out through them) |
| 22 | Low | Every glowing button was set up again on every update: colour (three textures on three frames), pulse, the EllesmereUI shape key (a new string each time). | Set up when a layer starts, and again only after a restyle, a new button list or a size change; the gates still follow every update |
| 23 | Low | No measure of what updates cost. | `/pt perf` (`debugprofilestop`) |
| 24 | Low | The 0.25 s safety tick ran out of combat too (measured: 3.9 updates a second idle, 0.28 ms each), although out of combat every condition is read directly and has its event; an item's cooldown ending had none (`BAG_UPDATE_COOLDOWN` wasn't listened to). | Out of combat the tick updates once a second at most; `BAG_UPDATE_COOLDOWN` |

Changes:
- `Buttons.lua` (new): providers `{ name, Present, Collect(add), dynamic, Shape }`, `List()` (the
  buttons, and the ones that dropped out), `Action(b)` (also LibActionButton's `_state_action`),
  `Shape(b)`, `Rescan()`, `Report()`.
- `Glow.lua`: uses `ns.Buttons`; layers keep their look (`styled`, `styleGen`); `Update` skips rules
  not on shown buttons and counts its cost; `ADDON_LOADED` / `PLAYER_ENTERING_WORLD` rescan the
  buttons; `/pt buttons` starts with each provider's count.
- `Options.lua`: `/pt perf`.

## Milestone 5 (1.20.0)

Review of the settings window and R9:

| # | Sev. | Finding | Change |
|---|---|---|---|
| 25 | Low | A rule's status showed only for the selected rule: to see why others did or didn't glow, each had to be opened. | Each rule in the list has a live dot (green glowing, yellow the game decides, orange can't tell, red error, none: doesn't hold or off), its status line on hover |
| 26 | Medium | R9: with no target, a target buff / debuff row on "missing" held, so a "Flame Shock missing" rule glowed with nothing targeted. | No target: a target row doesn't hold in either mode ("no target"), like health rows already |
| 27 | Low | Rule order decides which rule's look a spell glows in and which comes first, but rules couldn't be moved. | Up / Down |
| 28 | Low | No way to copy a rule within a character, to start from a pattern, or to share rules with another player. | Duplicate; templates; Share rules (export / import as text) |
| 29 | Low | Options.lua: a local `R()` that only called `Rule()` (and hid `ns.Result`). | Removed |
| 30 | Low | "Not on any of Blizzard's action bars" (since 1.19.0 other bars count too). | "Not on any shown action bar" |

Templates (Core.lua `ns.TEMPLATES`, the spell left blank to fill in): your buff is missing; your
debuff missing on target (in combat); target below 20% health; you below 40% health; instant cast
right now; the game flags it as a proc.

Import safety: the text is read by Share.lua's own parser (tables, strings, numbers, booleans:
nothing else is understood, and nothing is run); at most 60,000 characters, 6 levels deep, 6,000
values, 200 rules, 60 conditions a rule; only a rule's and a condition's known fields are kept,
each checked (type, range, allowed words); the rest come from the defaults. Imported rules are
added (new ids; Rule rows follow the imported copies; a Rule row to a rule not in the text is left
to be picked again), nothing is replaced.

## Milestone 6 (2.0.0)

Diagnostics:
- `/pt report`: one text for a bug report (in the Share window, to copy): Proc This!'s version,
  the client (`GetBuildInfo`), class, in combat, auras hidden, the Cooldown Manager on or off,
  buttons per provider, missing game functions, each rule's status and why (and "not on a shown
  button"), the last errors caught, and the rules as Share text.
- `/pt debug`: each rule's status change as it happens (rules on shown buttons), with why.
- Errors caught while working a rule out (`Glow.Evaluate`'s protected call) are kept: the last 10,
  the same one again counted (`Glow.errors`), for `/pt report`. They still show as "error".
- The other diagnostics, from earlier milestones: the status line per rule and the list's dots,
  `/pt spell`, `/pt buttons`, `/pt perf`, `/pt power`, `/pt api`, `/pt auras`.

Release readiness:
- `tests/check_release.py`: the version is the same in the toc, the CHANGELOG and README's Recent
  changes (the CurseForge notes are that README line); every toc file exists and every Lua file is
  in the toc; the release workflow leaves the developer files and tests out of the zip; the offline
  tests pass.
- 1.16.0-1.20.0 were milestone test builds, never published: 2.0.0 ships them together.

### Release (2.0.0)

1. `python3 tests/check_release.py` passes.
2. The in-game checklist below passes on the release zip.
3. Merge the release branch into main (fast-forward), push: the workflow uploads to CurseForge
   and tags v2.0.0.

### In-game checklist (2.0.0, the whole plan)

1. Install the 2.0.0 zip over 1.20.0, `/reload`: rules, looks and glows as before; no Lua errors.
2. `/pt report`: the text appears in the Share window, with your rules' statuses and "errors
   caught: none"; Ctrl+C copies it.
3. `/pt debug`, fight a mob: lines like "Lightning Shield: not glowing > glowing" as things
   change; `/pt debug` again stops them.
4. A quick pass over the earlier milestones' key checks: a "missing" buff rule in combat (estimate
   or Cooldown Manager), Flame Shock per target, two rules for one spell (colours), a `[mod:shift]`
   macro, `/pt perf` in a fight, the list's dots.

Results (2.0.0 release candidate):
- 3: pass. `/pt debug` in a fight: "Flame Shock: not glowing > glowing", "Lesser Healing Wave: not
  glowing > the game decides", "Lightning Shield: glowing > not glowing (Lightning Shield is on
  you)", "Earth Shock: glowing > not glowing (Stormstrike is not on your target)", "Flame Shock:
  glowing > not glowing (on cooldown)", "Lesser Healing Wave: the game decides > not glowing (not in
  combat)".
- 2: failed: "Options.lua:847: bad argument #1 to 'SetText'". The Share window's fill function was
  stored as `share.Show`, which hid the frame's own `Show` method: opening the window called it with
  the window as the text. Renamed (`share.Fill`); a test now opens the real window (the earlier one
  replaced `OpenShare`, so it couldn't catch this). Checked again: pass (the report shows in the box;
  client 1.60.1 (71139), interface 16001, all game functions present, errors caught: none).
- From that check: the report said to paste it into a bug report but didn't say where. The Share
  window now has a "Bug report page" button with a report (the same link as Help's button,
  `ns.OpenIssues`).

## Testing

### Offline

```
pip install lupa
python3 tests/run_tests.py
python3 tests/check_release.py   (before a release: versions, toc, workflow, tests)
```

44 tests (2.0.0): diagnostics (errors kept and counted, `/pt debug` lines, `/pt report`
contents); sharing (round trip, Rule rows, one rule with what it uses; bad, damaged and
hostile text refused, unknown fields and bad values dropped), templates, duplicate and priority, no
target; button providers (LibActionButton, dropped buttons), rules skipped when not on
a shown button, looks set once; the compatibility layer (missing functions, older forms, errors), durations
(kept across sessions, from tooltips), where casts went (mouseover / focus, target switch
mid-cast, buffs on others), macros (`/pt buttons`, modifier updates); the result model (AND / OR / NOT on gate sets, partial sets, limits, and the
random-formula check against every truth assignment), buff estimates and unknowns (charged buffs),
debuff estimates per target and charges, cooldown / usable / control results, rule evaluation
with mixed results, OR of hidden checks drawn as exclusive layers (checked for every combination
of the hidden values), several rules for one spell, dependencies (active, inactive, once per pass,
loops named, unknown), the gate limit, and saved-variable migration with duplicate ids. The mock's hidden
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
- 3: pass after a fix (verified: "seen on you, ends in 581 s" before the first hit, "can't tell -
  it has charges, and you've been hit since" after, no glow). Not tracked: "not on you (estimate: not on you when last seen …)" glows;
  cast: "on you (estimate: from your cast 4 s ago (lasts 600 s))", no glow. But 16 s later the
  shield's charges were used up and the estimate still said "on". Fixed: charged buffs become
  "can't tell" once you're hit. Limitation: once it's used up, the rule can't glow until combat
  ends (no read) unless the buff is tracked in the Cooldown Manager.
- 1: pass (rules and looks kept, no Lua errors seen during testing).
- 5: pass. Flame Shock not tracked: target A dotted, no glow; target B "not on your target
  (estimate: you haven't cast it on this target)", glows while A still has the dot; back to A, no
  glow.
- 6: pass. Flame Shock on the shared shock cooldown in combat: "Not glowing: on cooldown" (read
  directly; "decided by the game" never appeared: cooldowns weren't hidden solo).
- 7: the only "can't tell" seen was the charged-buff case above, which is correct.

Milestone 1 verified in game and reviewed.

### In-game checklist (Milestone 2 → 3)

1. Install 1.17.0, `/reload`. Rules, looks and glows as in 1.16.0; no Lua errors. Glow + shine,
   pulse and the EllesmereUI styles look the same.
2. Two rules for one spell, each with a different condition the game hides in combat (e.g. Lightning
   Bolt with "Castable", and a second Lightning Bolt rule with a Health [Self] [<] 50 % row, each in its
   own colour): in combat it glows when either holds (1.16.0: only the first rule), in the first
   rule's colour when both hold, and never two glows on top of each other.
3. A rule with an "any one" group of two health rows (e.g. [Health] [Self] [<] 50, [Health]
   [Target] [<] 20): in combat the status says "Glowing when the game says so", and it glows when
   either holds (1.16.0: "can't tell", no glow).
4. Three rules that use one rule (Rule rows): `/pt` status works for each; no slowdown.
5. A loop can no longer be made from the picker: rule A uses B, then on B's Rule
   row A isn't offered.
6. Any "can't tell", "partly" or "error" status: screenshot it with the rule's settings.

Results (1.17.0 test build, Shaman, solo):
- 3: pass. "Any one" group of [Health] [Self] [<] 50 and [Health] [Target] [<] 50: "Glowing when the
  game says so", both rows "hidden: the game decides"; glows with the target at 26% and 7%.
- 2: pass. Two Lightning Bolt rules, both decided by the game: cyan [Health] [Self] [<] 50, then
  magenta [Health] [Target] [<] 50. Target 23%, you above 50%: magenta (1.16.0: no glow). You below
  50%, target 67%: cyan. One glow at a time. Also a plain yes (cyan, castable only) wins over the
  magenta rule: cyan.
- 1, 4, 5: pass. Found: Rule rows name same-spell rules by place ("Lightning Bolt (#3)") but the
  rules list didn't show it; the list and the editor title now use the same label.


### In-game checklist (Milestone 3 → 4)

1. Install 1.18.0, `/reload`. Glows as in 1.17.0; no Lua errors.
2. `/pt api`: every line names a function (none "not on this client"); send the list.
3. `/pt spell Lightning Shield`, `/pt spell Flame Shock`: a duration "from its tooltip" (or "seen"
   once read). Then `/reload` and cast Lightning Shield in combat before it was read out of combat:
   "on you (estimate: from your cast …)" (1.17.0: "can't tell").
4. Flame Shock rule (not tracked in the Cooldown Manager): with a target, cast Flame Shock at a
   different mob through a `/cast [@mouseover] Flame Shock` macro: your target still reads "you
   haven't cast it on this target" (1.17.0: "from your cast").
5. A macro with `[mod:shift] Earth Shock; Lightning Bolt` on a bar, with rules for both: holding
   Shift switches the glow at once. `/pt buttons` shows the macro as "macro -> Lightning Bolt"
   (and Earth Shock with Shift held).
6. Any "can't tell" or "error": screenshot it with the rule's settings.

Results (1.18.0 test build, Shaman):
- 2: pass. `/pt api`: all 27 functions present, each in its newest form (`C_Spell.*`, `C_Item.IsUsableItem`,
  `C_Container.GetItemCooldown`, `C_Secrets.*`, `C_Spell.GetSpellDescription`).
- 3: pass. `/pt spell`: "Lightning Shield: instant; lasts 600 s (from its tooltip)", "Flame Shock:
  instant; lasts 12 s (from its tooltip)": the tooltip wording parses on Forever.
- 4: pass. After a `/reload`, Lightning Shield not tracked, cast in combat: "Not glowing: Lightning
  Shield is on you (estimate: from your cast 4 s ago (lasts 600 s, from its tooltip))" (1.17.0:
  "can't tell").
- 5 (Flame Shock tracked in the Cooldown Manager): pass. Cast at a second mob through a mouseover
  macro: your target "not on your target (from the Cooldown Manager)".
- 5 (not tracked): pass. Target Succubus Minion, Flame Shock mouseover-cast on a Bloodsail Warlock:
  "Flame Shock: not on your target (estimate: you haven't cast it on this target)" (1.17.0: "from
  your cast"); not glowing because the shocks were on cooldown.
- 1: pass (no Lua errors on 1.18.0).
- 6 (`[mod:shift] Earth Shock; Lightning Bolt` macro): pass, the glow follows the modifier.

Milestone 3 verified in game; awaiting review before Milestone 4.

### In-game checklist (Milestone 4 → 5)

1. Install 1.19.0, `/reload`. Glows as in 1.18.0 (Blizzard bars and EllesmereUI's, shapes
   included); no Lua errors.
2. `/pt buttons`: the first line counts each provider's buttons (Blizzard, EllesmereUI,
   LibActionButton "not loaded" unless Bartender4 / ElvUI is installed).
3. `/pt perf` once, play a fight with your rules (a minute or two), then `/pt perf` again: send the
   two lines (updates a second, ms each, rules worked out / skipped, buttons).
4. Change a rule's colour, size and "while it's on" in combat and out: the glow follows at once.
5. Turn an EllesmereUI bar off and on (if you use one): no glow left behind on the hidden bar.

Results (1.19.0 test build, Shaman):
- 2: pass. `/pt buttons`: "Blizzard 96, EllesmereUI not loaded, LibActionButton 0" (the library is
  loaded by another addon, with no bars). Macros read: Call of the Elements, Flame Shock (with its
  rule), Blood Fury; two macros (slots 25, 32) read as nothing: their contents to be checked.
- 3: measured (5 rules, 96 Blizzard buttons, Windows client): idle 3.9 updates a second, 0.277 ms
  each (0.857 ms at most): about 1 ms a second; a fight 13.9 a second, 0.586 ms each (2.637 ms at
  most): about 8 ms a second, under 1% of the frame time at 60 fps. All 5 rules on shown buttons
  (none skipped). Led to defect 24 (the idle tick). After the fix: idle 1.0 a second, 0.288 ms
  each (0.538 ms at most); a fight 11.9 a second, 0.580 ms each (1.079 ms at most).
- 2 (the two macros reading as nothing): they're on the right-hand bar, which the game reports as
  shown (`IsVisible`) but isn't on screen (faded or moved off). Not checked further: they hold no
  rule's spell.
- 4: pass. Colour, size and "while it's on" changed while glowing in combat: the glow follows at
  once.
- 1: glows as in 1.18.0 throughout the tests; no Lua errors reported.
- 5: not applicable (EllesmereUI not loaded on this character); covered by the offline test of a
  dropped button.

Milestone 4 verified in game; awaiting review before Milestone 5.

### In-game checklist (Milestone 5 → 6)

1. Install 1.20.0, `/reload`. No Lua errors; glows as in 1.19.0.
2. `/pt`: each rule in the list has a dot; hover it: its status line. In combat the dots follow.
3. Duplicate a rule, give the copy another colour, and move it Up above the original: when both
   hold, the spell glows in the copy's colour.
4. Pick "Your debuff missing on target", +, type Flame Shock: a rule with [Debuff] [Target] [Flame
   Shock] [Inactive]. With no target, it doesn't glow ("no target"); with a target without it, it
   does.
5. Share rules...: Export this rule (Flame Shock), Ctrl+C; paste it into the box again and Import:
   a copy appears. Paste "hello" and Import: refused with a reason.
6. Any "can't tell" or "error": screenshot it with the rule's settings.

Results (1.20.0 test build, Shaman): 1-6 all pass (reported by the author: status dots and their
tooltips, Duplicate and Up / Down priority, the debuff template with and without a target, export,
import of the copy, "hello" refused).

Milestone 5 verified in game.

## Known limitations

- Buffs and debuffs not tracked in the Cooldown Manager can't be followed exactly in combat; the
  settings window says so per row, and estimates are labelled.
