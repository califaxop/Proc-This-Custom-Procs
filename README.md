# Proc This!: Custom Procs

**Make any spell light up like a proc, exactly when it matters.**

Pick a spell, set your conditions, and Proc This! puts Blizzard's own proc glow on it the moment they're met. No more watching buff bars mid-fight.

## Highlights
- **Any spell, any rank:** on Blizzard and FlareUI bars, macros included.
- **Buffs & debuffs:** on you or your target, active or missing, as many as you like.
- **Groups with AND / OR:** e.g. *(Buff X or Buff Y) and (Debuff Z and Debuff W)*.
- **Instant cast:** glow while a spell is instant (or isn't): Maelstrom Weapon at 5, Nature's Swiftness, Presence of Mind, Shadow Trance and more.
- **Health & mana:** glow while you or your target are below or above a % of health or mana, e.g. Healing Wave when your target drops under 40%, Evocation when your mana is under 20%. Works in combat too: the game checks it for you.
- **Rules that depend on rules:** glow while another of your rules is active, or isn't, e.g. Earth Shock while your Flame Shock rule is inactive.
- **Extra checks:** being hit in melee, castable, off cooldown, not stunned, in combat, proc flagged.
- **Your look:** just the glow, glow + shine, or Blizzard's burst; adjustable size and intensity.
- **Live status:** each rule tells you why it is or isn't glowing.

## Quick start
1. Type `/pt` and click **+ Add rule**.
2. Name the spell, then add your buffs and debuffs.
3. Add those auras to Blizzard's **Cooldown Manager** (Tracked Buffs/Bars) so Proc This! can see them in combat.

## Commands
| Command | Does |
|---|---|
| `/pt` (or `/proc`, `/procthis`) | Open settings |
| `/pt test` | Show every glow for 3 seconds |
| `/pt auras` | List auras and spell IDs (out of combat) |
| `/pt cast <spell>` | Show a spell's cast time right now |

## Good to know
- In combat the game hides auras from addons: **track them in the Cooldown Manager**, or the rule can't see them.
- The Cooldown Manager only tracks **your own** spells' auras.
- Stack counts are hidden in combat, so there are no stack checks: use **Instant** rows instead (e.g. Lightning Bolt is instant = 5 Maelstrom Weapon).

## Updates
New versions come out every **Wednesday at 12:00 UTC** (8 PM Philippine time, 8 AM US Eastern). Urgent fixes ship sooner.

## Feedback
Found a bug or have an idea? [Open an issue](https://github.com/califaxop/Proc-This-Custom-Procs/issues/new/choose): there's a short form for each. The settings window has a "Feedback" button with this link too.

## Recent changes
- **1.12.0:** Health and mana conditions (you or your target below or above a %; in combat too), "Rule X is active / inactive" conditions, and shorter commands: `/pt` or `/proc`.
- **1.11.4:** Native look: the settings use the game's own tooltip border in bronze (without FlareUI style).
- **1.11.3:** Lighter in combat: glow checks run at most 20 times a second (still instant to the eye), and nothing runs when you have no rules.
- **1.11.2:** The "Report a bug / suggest" link box is solid now and stays put over the settings window until you close it.
- **1.11.1:** The old SpellGlow carry-over folder is gone (the CurseForge app removes it for you). If you never logged in with 1.11.0, your rules start fresh.
- **1.11.0:** The addon folder is now **ProcThis**. Your rules come over automatically on first login (a small "SpellGlow" carry-over addon shipped alongside for that).
- **1.10.1:** Login message shows `/procthis`; feedback button links to the new repo.
- **1.10.0:** SpellGlow is now **Proc This!**: same addon, same rules and settings. New command `/procthis` (the old `/sglow` still works).
- **1.9.0:** New Instant condition (a spell is instant cast right now) replaces Maelstrom Weapon stack checks; existing stack rules convert.
- **1.7.3:** New "Report a bug / suggest" button in the settings, linking to a short feedback form.
- **1.7.2:** Condition groups (All / Any, joined by AND / OR); Maelstrom Weapon stacks; other stack checks removed.
- **1.7.1:** Glows on spells cast from macros.
- **1.7.0:** New tabbed settings window; unlimited buff and debuff conditions.
