# SpellGlow-Custom-Procs
The modern proc glow on your action bar spells, only when the conditions you choose are met.

SpellGlow: Custom Procs puts Blizzard's own retail spell-alert glow on any spell in your action bars, every rank of it. You write simple rules: each rule names a spell and the conditions that must all be true, and the spell glows while they hold, like a proc you design yourself. It works on Blizzard's bars and FlareUI's, including macros that cast the spell, without tainting your buttons.

Features
- Rules: one spell each, every rank matched by name, typed in or dragged from your spellbook.
- Conditions per rule, all required:
  - Buffs on me: up to 3 rows, each "on me" or "missing", with an optional minimum stack count.
  - Debuff on my target: on it or missing, only mine, with a duration and "used up after N casts of" spells.
  - Buff on my target and Debuff on me: on or missing.
  - Being attacked in melee (hit, dodged, parried or blocked in the last few seconds).
  - Castable (known, enough mana), off cooldown (global cooldown ignored), I have control (not stunned), only in combat, the game flags it as a proc.
- Glow style: just the glow, glow + a brief shine when it starts, or Blizzard's zoom-in burst; adjustable size and intensity.
- Combat-aware: reads Blizzard's Cooldown Manager for buffs, debuffs and stack counts it tracks, and your own casts as a backup.
- Live status per rule: glowing or not, and why; how many buttons have the spell; whether each aura is followed in combat.
- Starter rule included: Lightning Shield glows when it is missing, you are being hit in melee, and you can cast it.

Settings and commands
- /spellglow or /sglow: the rules window (add, edit, remove rules; melee window 1-10 s; glow size, intensity and start style; test).
- /sglow test: show every rule's glow for 3 seconds.
- /sglow auras: list your target's and your own buffs and debuffs with spell IDs (out of combat).
- Esc > Options > AddOns > Spell Glow.

Requirements
- WoW: Forever (client 16001). No other addons required.
- For in-combat buff, debuff and stack tracking: add those auras to Blizzard's Cooldown Manager (Tracked Buffs).

Known limits
- Forever hides auras from addons in combat. Auras not tracked in the Cooldown Manager fall back to your casts (your own debuffs) or can't be checked (others' auras), and those rules don't glow.
- Comparing a hidden stack count relies on a client function not yet confirmed on Forever; the rule's status says whether it works.
- A dodged or parried application can't be detected unless the debuff is tracked in the Cooldown Manager.

Changelogs
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
