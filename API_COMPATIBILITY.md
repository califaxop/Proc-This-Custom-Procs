# Proc This!: API compatibility (WoW: Forever, Interface 16001)

Verification status:
- **Verified in game**: observed on Forever by the author (screenshots, `/pt` diagnostics).
- **In use**: used by released versions that work in game, but the specific behaviour noted
  hasn't been observed on its own.
- **Docs**: Forever's API docs (`Blizzard_APIDocumentationGenerated`) or Blizzard's UI code; not
  yet observed in game.
- **Inferred**: assumed from behaviour, not tested.
- **Unsupported**: not available to addons, or not used.

Every function below is called through the compatibility layer (`Compat.lua`, 1.18.0): the first
form the client has is used, always protected; `/pt api` lists which form this client has.

"Secret" = the value can be hidden from addons: an addon can pass it to some calls, not compare,
test or read it. `issecretvalue(v)` says whether it is.

## Auras

| API | Signature | Secret when | Proc This! uses it for | Status |
|---|---|---|---|---|
| `C_Secrets.ShouldAurasBeSecret()` | → bool | never | in combat: don't query auras | In use |
| `C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)` | → AuraData or nil | unit aura restricted; in combat Forever errors ("Auras cannot be accessed when secret") | out of combat: buffs and debuffs, their `duration`, `expirationTime`, `applications` and `charges` (for estimates) | In use (the combat error is quoted from an in-game report); `expirationTime`, `applications`, `charges` for estimates: Docs |
| `C_UnitAuras.GetAuraDataByIndex(unit, i, filter)` | → AuraData or nil | as above | fallback buff read; `/pt auras` | In use |
| `canaccessvalue(v)` | → bool | — | an aura record with hidden fields | Docs |
| `C_CooldownViewer.GetCooldownViewerCooldownInfo(id)`, the viewers `BuffIconCooldownViewer` / `BuffBarCooldownViewer` and their icons' `cooldownID`, `isActive`, `auraInstanceID` | — | `auraInstanceID` can be hidden | your tracked buffs and debuffs in combat | In use (verified in game with Stormstrike, Lightning Shield) |

## Spells and items

| API | Signature | Secret when | Use | Status |
|---|---|---|---|---|
| `C_Spell.GetSpellCooldown(spell)` | → SpellCooldownInfo { isActive, isOnGCD, ... } (nil: no such spell) | cooldowns restricted (`C_Secrets.ShouldCooldownsBeSecret`) | "Off cooldown": readable → TRUE / FALSE; hidden `isActive` → a gate (open when false) | Readable case: Verified in game (Flame Shock on the shared shock cooldown: "on cooldown"); hidden case: Docs only (never hidden solo) |
| `C_Spell.IsSpellUsable(spell)` | → isUsable, insufficientPower | can be hidden | "Castable": hidden → a gate | In use (the hidden case: Inferred) |
| `C_Item.IsUsableItem(item)` | → usable, noMana | — | items' "usable" | Docs |
| `C_Container.GetItemCooldown(itemID)` | → start, duration, enable | — | items' "off cooldown" (hidden → UNKNOWN) | Docs |
| `C_Spell.GetSpellInfo(spell)` | → SpellInfo { castTime, spellID, ... } | — | "Instant" rows (cast time 0); a spell's ID for its tooltip | Verified in game (`/pt cast`: readable in combat) |
| `C_Spell.GetSpellDescription(spellID)` (older: `GetSpellDescription`) | → text | — | a buff's or debuff's duration before it's ever read ("for 12 sec", "Lasts 10 min": the longest; English wording) | Verified in game (`/pt spell`: Lightning Shield 600 s, Flame Shock 12 s) |
| `C_Spell.GetSpellName(id)`, `C_Item.GetItemNameByID`, `C_Item.GetItemInfoInstant` | — | — | names | In use |
| `UNIT_SPELLCAST_SUCCEEDED` (unit, castGUID, spellID) | event | spellID can be hidden (then ignored) | your casts, for estimates | In use |
| `UNIT_SPELLCAST_SENT` (unit, target name, castGUID, spellID) | event | the name or castGUID may be hidden (then the cast counts as before) | where a cast went: your target, another unit, you | Verified in game (a mouseover Flame Shock wasn't counted on the target) |
| `MODIFIER_STATE_CHANGED` | event | — | macros with `[mod]` conditions: update at once | Verified in game (`[mod:shift]` macro) |
| `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / HIDE` (spellID) | events | — | "Proc" | In use |

## Units

| API | Signature | Secret when | Use | Status |
|---|---|---|---|---|
| `UnitName(unit)` | → name, realm | can be hidden | compared with a cast's target name | Docs |
| `UnitGUID(unit)` | → GUID or nil | unit identity restricted (PvP tokens) | keys your debuff casts per target; hidden → only the current target | Docs |
| `HasFullControl()` | → bool | not marked | "Control": hidden → a gate | Docs |
| `UnitAffectingCombat(unit)` | → bool | not marked | "In combat": hidden → a gate | Docs |
| `UnitHealth`, `UnitHealthMax`, `UnitHealthPercent(unit, usePredicted, curve)` | — | health hidden in combat | health rows: readable, else a step curve as a gate | In use |
| `UnitPower`, `UnitPowerMax`, `UnitPowerPercent(unit, type, unmodified, curve)` | — | your mana is always hidden on Forever; others at times | mana / combo / rage / energy rows | Verified in game (`/pt power`) |
| `GetComboPoints("player", "target")` | → number | can be hidden | combo points | In use |
| `UNIT_COMBAT` (unit, action, descriptor, amount, school) | event | fields can be hidden (then counted as melee, and as a hit) | "Being hit in melee"; hits that may use up a charged buff | In use |

## Glow

| API | Use | Status |
|---|---|---|
| `ActionButtonSpellAlertTemplate` | the glow art (Blizzard's own) on its own frame | In use |
| `Frame:SetAlphaFromBoolean(value, ifTrue, ifFalse)` | gates from hidden booleans | In use |
| `C_CurveUtil.CreateCurve()`, `Enum.LuaCurveType.Step` | step curves for hidden health / power | In use (`/pt power` reports whether it works) |
| `LibStub("LibActionButton-1.0", true).buttonRegistry` (button → true); a button's `_state_type`, `_state_action` | LibActionButton bars (Bartender4, ElvUI...): their buttons and action slots | Docs (the library's source); not seen on Forever yet |
| `debugprofilestop()` | `/pt perf`: how long updates take, in ms | Verified in game (`/pt perf`) |
| `GetBuildInfo()`, `C_AddOns.GetAddOnMetadata(addon, "Version")` (older: `GetAddOnMetadata`) | `/pt report`: the client and Proc This!'s version | Docs |
| `ADDON_LOADED`, `PLAYER_ENTERING_WORLD` | look for buttons again (a bar addon came in) | In use |
| `BAG_UPDATE_COOLDOWN` | an item's cooldown started or ended | Docs |
| `GetActionInfo(slot)` | → kind, id, subType: what a button holds (macro subtype "spell" / "item") | In use |
| `GetMacroSpell(index)`, `GetMacroItem(index)` | older macro resolution | Docs |
| `EllesmereUI.Glows` (`StartGlow`, `StartShapeGlow`, `StopAllGlows`, `STYLES`), `EllesmereUI.SHAPE_MASKS` | EllesmereUI's glow styles and shaped buttons | In use (EllesmereUI 9.9.x) |

## Testing an API in game

- `/pt auras`: your and your target's auras with IDs (out of combat only).
- `/pt power`: what's readable of your mana, combo points, rage and energy, and whether the
  game-side check works.
- `/pt spell <spell>` (or `/pt cast`): its cast time now, how long it lasts and where that's from,
  whether it has charges.
- `/pt buttons`: what each macro button (and each button with a rule's spell) reads as now.
- `/pt api`: which form of each function this client has (all 27 present on Forever, newest forms).
- `/pt debug`: each rule's status changes, as they happen.
- `/pt report`: all of the above that matters for a bug report, as one text.
- The settings window's live status (per rule): each row's answer and its source.
