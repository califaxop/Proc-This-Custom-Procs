# SpellGlow-Custom-Procs
The modern proc glow on your action bar spells, only when the conditions you choose are met.

SpellGlow: Custom Procs puts Blizzard's own retail spell-alert glow on any spell in your action bars, every rank of it. You write simple rules: each rule names a spell and the conditions that must all be true, and the spell glows while they hold, like a proc you design yourself. It works on Blizzard's bars and FlareUI's, including macros that cast the spell, without tainting your buttons.

Features
- Rules: one spell each, every rank matched by name, typed in or dragged from your spellbook.
- Buffs and debuffs, as many as you need, all must hold. Each one sets:
  - who has it: on me or on target
  - buff or debuff
  - active or missing, with an optional minimum stack count
  - for your debuffs on a target: only mine, and a backup from your casts (how long it lasts, used up after N casts of chosen spells)
- Debuff types: match any Poison, Curse, Disease or Magic debuff (or buff), or any dispellable one, on you or your target, instead of a name. Example: Cure Poison glows while a poison is on you. Your own debuffs' types are read even in combat, with no Cooldown Manager needed.
- Other conditions: being attacked in melee, castable (known, enough mana), off cooldown (global cooldown ignored), I have control (not stunned), only in combat, the game flags it as a proc.
- Example: Lightning Bolt glows while Stormstrike is on your target, Maelstrom Weapon is on you, and Flame Shock is on your target.
- Combat-aware: follows buffs, debuffs and stack counts through Blizzard's Cooldown Manager; each condition shows whether it's tracked there.
- Glow style: just the glow, glow + a brief shine when it starts, or Blizzard's zoom-in burst; adjustable size and intensity.
- Live status per rule: glowing or not, and why; how many buttons have the spell; how each buff and debuff is being read.
- Settings window in the same style as XP Planner (FlareUI's when installed), with Rules, Look and Help tabs.
- Starter rule included: Lightning Shield glows when it is missing, you are being hit in melee, and you can cast it.

Settings and commands
- /spellglow or /sglow: the settings window (Rules, Look, Help).
- /sglow test: show every rule's glow for 3 seconds.
- /sglow auras: list your target's and your own buffs and debuffs with spell IDs (out of combat).
- Esc > Options > AddOns > Spell Glow.

Requirements
- WoW: Forever (client 16001). No other addons required.
- Blizzard's Cooldown Manager turned on, with every buff and debuff your rules use added to its Tracked Buffs or Tracked Bars. In combat the game hides auras from addons; the Cooldown Manager is how Spell Glow follows them.

Known limits
- Forever hides auras from addons in combat. Auras not tracked in the Cooldown Manager fall back to your casts (your own debuffs) or can't be checked (others' auras), and those rules don't glow.
- Comparing a hidden stack count relies on a client function not yet confirmed on Forever; the rule's status says whether it works.
- A dodged or parried application can't be detected unless the debuff is tracked in the Cooldown Manager.
- The Cooldown Manager only tracks your own spells' auras: auras other players put on you or your target can only be checked out of combat.

Changelogs
- 1.8.0: Debuff type conditions: glow while any Poison, Curse, Disease or Magic debuff (or buff) is on you or your target, or is missing. No names or Cooldown Manager needed; works in combat for your own debuffs.
- 1.7.0: Redesigned settings window (XP Planner's style, with tabs); unlimited buff and debuff conditions per rule, each on you or your target; existing rules are converted automatically.
- 1.6.1: Fixed an error when opening the settings window.
- 1.6.0: Choose how the glow starts (just the glow, glow + shine, or Blizzard's zoom-in burst) and its intensity.
- 1.5.1: Logo in the AddOns list.
- 1.5.0: Up to 3 buff conditions per rule (all must hold), minimum stacks read from the Cooldown Manager.
- 1.4.0: Debuffs on your target and on you followed in combat through the Cooldown Manager.
- 1.3.0: A target debuff can be used up after N casts of chosen spells.
- 1.2.1: /sglow auras lists auras with their spell IDs; combat aura errors fixed.
- 1.2.0: Buff on my target condition.
- 1.1.0: Debuff on my target and Debuff on me conditions.
- 1.0.0: First release: Blizzard's proc glow on action bar spells by rule.
