# Changelog

## 1.17.0 (Milestone 2: advanced condition evaluation)

- Conditions the game hides now work when joined by OR ("any one" groups, rules joined by OR):
  the glow shows when any of them holds. Before, two or more of them gave "can't tell" and no glow.
- Several rules for one spell now all count when the game decides them: it glows when any of
  them holds (before, only the first one), in that rule's look, never two glows on top of each
  other.
- More hidden conditions fit in one rule (6 together, up to 4 alternatives).
- Fixed: "Rule X is inactive" could glow when X was active through a branch that couldn't be told.
- A rule used by other rules is worked out once per update.
- Several rules for one spell show their place in the rules list ("Lightning Bolt (#3)"), as
  Rule rows name them.
- A loop between rules names them (A > B > A), and the rule picker no longer offers a rule that
  would make one.

## 1.16.0 (Milestone 1: condition engine reliability)

- Every condition now answers yes, no, "the game decides" (hidden values), "can't tell" or
  "error". "Can't tell" and "error" never light a glow, and never count as yes or as no.
- Fixed: a buff not tracked in the Cooldown Manager counted as **missing** in combat when it had
  never been seen, so a "buff missing" rule could glow while the buff was on.
- Fixed: casting a spell marked the buff of that name as on until combat ended, so "missing" rules
  stopped glowing after it ran out. It's now an estimate that ends with the buff's known duration
  (learned from reads out of combat).
- A buff with charges (e.g. Lightning Shield) isn't estimated as on once you've been hit since the
  cast: the hit may have used it up. It says "can't tell" (no glow); track it in the Cooldown
  Manager for an exact answer.
- Fixed: a spell cooldown the game hides counted as ready, so a rule could glow a spell on
  cooldown. The hidden cooldown now switches the glow itself.
- Fixed: your debuffs on a target were forgotten when you switched targets: switching back to a
  target you'd dotted counted as "not on it". They're now kept per target.
- Fixed: unreadable cooldowns, control or usability no longer count as yes.
- "Rule X is inactive" on a rule that can't be told is now "can't tell" (it counted as inactive).
- The live status says "can't tell" or "error" apart from a plain no, and for each buff or debuff
  where its answer came from: read directly, the Cooldown Manager, or an estimate (with how old).
- Developer docs (DEVELOPMENT.md, API_COMPATIBILITY.md) and offline tests (`tests/`).

Earlier versions: see "Recent changes" in README.md.
