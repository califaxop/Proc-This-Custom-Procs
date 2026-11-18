# SpellGlow: Custom Procs

**Make any spell light up like a proc, exactly when it matters.**

Pick a spell, set your conditions, and SpellGlow puts Blizzard's own proc glow on it the moment they're met. No more watching buff bars mid-fight.

## Highlights
- **Any spell, any rank:** on Blizzard and FlareUI bars, macros included.
- **Buffs & debuffs:** on you or your target, active or missing, as many as you like.
- **Groups with AND / OR:** e.g. *(Buff X or Buff Y) and (Debuff Z and Debuff W)*.
- **Maelstrom Weapon stacks:** `>=`, `>`, `=`, `<=`, `<` (read from Lightning Bolt's cast time, haste included).
- **Extra checks:** being hit in melee, castable, off cooldown, not stunned, in combat, proc flagged.
- **Your look:** just the glow, glow + shine, or Blizzard's burst; adjustable size and intensity.
- **Live status:** each rule tells you why it is or isn't glowing.

## Quick start
1. Type `/sglow` and click **+ Add rule**.
2. Name the spell, then add your buffs and debuffs.
3. Add those auras to Blizzard's **Cooldown Manager** (Tracked Buffs/Bars) so SpellGlow can see them in combat.

## Commands
| Command | Does |
|---|---|
| `/sglow` | Open settings |
| `/sglow test` | Show every glow for 3 seconds |
| `/sglow auras` | List auras and spell IDs (out of combat) |
| `/sglow mw` | Show the Maelstrom Weapon stack reading |

## Good to know
- In combat the game hides auras from addons: **track them in the Cooldown Manager**, or the rule can't see them.
- The Cooldown Manager only tracks **your own** spells' auras.
- Stack counts are hidden in combat, so only **Maelstrom Weapon** has a stack check.

## Recent changes
- **1.7.2:** Condition groups (All / Any, joined by AND / OR); Maelstrom Weapon stacks; other stack checks removed.
- **1.7.1:** Glows on spells cast from macros.
- **1.7.0:** New tabbed settings window; unlimited buff and debuff conditions.
