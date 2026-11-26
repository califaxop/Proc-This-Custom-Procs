# Changelog

## 1.16.0 (Milestone 1: condition engine reliability)

- Every condition now answers yes, no, "the game decides" (hidden values), "can't tell" or
  "error". "Can't tell" and "error" never light a glow, and never count as yes or as no.
- Fixed: a buff not tracked in the Cooldown Manager counted as **missing** in combat when it had
  never been seen, so a "buff missing" rule could glow while the buff was on.
- Fixed: casting a spell marked the buff of that name as on until combat ended, so "missing" rules
  stopped glowing after it ran out. It's now an estimate that ends with the buff's known duration
  (learned from reads out of combat).
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
