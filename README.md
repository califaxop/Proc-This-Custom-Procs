# Proc This!: Custom Procs

**Make any spell light up like a proc, exactly when it matters.**

Pick a spell, set your conditions, and Proc This! puts Blizzard's own proc glow on it the moment they're met. No more watching buff bars mid-fight.

## Highlights
- **Any spell, any rank, or an item:** on Blizzard, FlareUI and EllesmereUI bars, macros included. Trinkets, potions and other usable items glow too.
- **Fits your UI:** EllesmereUI or FlareUI found by themselves, and the settings window takes on their look. With EllesmereUI, the glow follows its shaped buttons and you can pick its glow styles (autocast shine, pixel lines, GCD ants...).
- **Buffs & debuffs:** on you or your target, active or missing, as many as you like.
- **Groups with AND / OR:** e.g. *(Buff X or Buff Y) and (Debuff Z and Debuff W)*.
- **Instant cast:** glow while a spell is instant (or isn't): Maelstrom Weapon at 5, Nature's Swiftness, Presence of Mind, Shadow Trance and more.
- **Health, mana, combo points, rage & energy:** compare with >, >=, <, <= or =, e.g. Healing Wave when your target's health is < 40%, Evocation when your mana is < 20%, Eviscerate at >= 5 combo points, Sinister Strike at >= 45 energy. Works in combat too: when the game hides the number, it checks it for you.
- **Rules per character:** each character has its own rules; copy another character's in Settings.
- **Rules that depend on rules:** glow while another of your rules is active, or isn't, e.g. Earth Shock while your Flame Shock rule is inactive.
- **Each rule its own look:** colour (Blizzard's gold, red, green, blue... or any colour you pick), how it starts, steady or pulsing, size and intensity. A "Use for all rules" button copies one rule's look to every rule.
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
- **1.15.1:** Fixed: the settings window's text is readable with EllesmereUI installed and its style turned off (EllesmereUI's quest tracker shrinks the game's tracker fonts to 1 px, and the window used them). No EllesmereUI / FlareUI mode settings any more: Proc This! uses EllesmereUI (glows on its bars, its glow styles, its window style) or FlareUI's window style on its own whenever one is installed.
- **1.15.0:** Rules are now kept per character: each character has its own list. On each character's first login it keeps your old rules for the spells and items it has, and Settings > Rules on other characters copies another character's rules into it. New Combo Points, Rage and Energy conditions, and every number condition (Health, Mana, Combo Points, Rage, Energy) now compares with >, >=, <, <= or =: [Combo Points] [>=] [5], [Energy] [>=] [45], [Health] [Target] [<] [40] %. When the game hides the number from addons, the game itself decides whether the glow shows. `/pt power` shows what the game lets Proc This! read on your character.
- **1.14.0:** Items glow too: put a trinket, potion or any usable item in a rule (type its name or ID, or drag it from your bags) and it glows on your bars, as itself or in a /use macro; "Off cooldown" and "Castable" read the item's own cooldown and whether you can use it. Every condition now reads the same way, left to right: [Kind] [Who] [What] [State], e.g. [Debuff] [Target] [Stormstrike] [Active], [Rule] [Lightning Bolt] [Inactive], [Instant Cast] [Lightning Bolt] [Active], [Health] [Self] [Below] [40] %. Missing is now called Inactive; On me / On target are Self / Target. The "Right now" section is now "Current Rule Status".
- **1.13.0:** EllesmereUI and FlareUI modes, turned on by themselves when that UI is installed (Settings, Other UIs). EllesmereUI mode: glows on all its bars, its shape glow on shaped buttons (circle, hexagon, diamond...) in your rule's colour, its glow styles in each rule's Look (pixel lines, Action Button, autocast shine, GCD ants, Modern and Classic WoW), and the settings window in EllesmereUI's style through its own skinning API (your theme, accent colour and font). FlareUI mode: the settings window in FlareUI's style.
- **1.12.0:** Health and mana conditions (you or your target below or above a %; in combat too), "Rule X is active / inactive" conditions, a look of its own for every rule (colour, start, pulse, size, intensity), and shorter commands: `/pt` or `/proc`.
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
