# Changelog

## 2.1.0

- "Report a bug" now sits at the top right of the settings window, next to the ×, and opens a bug report window (like Questie's trace export): the form's link to copy at the top, then one line to paste into the form with your version, the game client, what Proc This! sees right now, each rule's status and your rules; never your name, realm or guild. Also `/pt report`. The Help page's button and the Share window's report are replaced by it. The settings window is now solid and comes to the front when opened or clicked: with several addons' settings open, they no longer show through each other.

## 2.0.0 (the development plan: Milestones 1-6)

The first release of the development plan. 1.16.0 to 1.20.0 below were test builds of its
milestones (not published); 2.0.0 is all of them, plus Milestone 6:

- New: `/pt report` puts everything a bug report needs into one text to copy: version and client,
  what the game lets Proc This! see right now, the buttons, each rule's status, the last errors
  caught, and your rules; its "Bug report page" button gives the link to the bug report form.
- New: `/pt debug` prints each rule's status changes as they happen.
- Errors while working out a rule are kept (for `/pt report`) besides showing as "error".

## 1.20.0 (Milestone 5: user experience; test build)

- Each rule in the list shows its live status as a dot (green glowing, yellow the game decides,
  orange can't tell, red error); hover it for why.
- Move rules Up and Down: when several rules glow one spell, the higher one comes first (its look).
- Duplicate a rule; start a rule from a template (buff missing, debuff missing on target, target
  below 20%, you below 40%, instant cast, proc).
- Share rules: export a rule (with the rules it uses) or all of them as text, and import rules
  someone sent you. Imported text is checked field by field and never run.
- Fixed: with no target, a "debuff missing on target" rule glowed.

## 1.19.0 (Milestone 4: button discovery and rendering; test build)

- Glows on action bars built on LibActionButton (Bartender4, ElvUI and others), besides Blizzard's
  and EllesmereUI's.
- Fixed: a button whose bar was turned off could keep its glow.
- Lighter updates: only rules whose spell is on a shown button are worked out, a glow's look is
  set when it starts instead of on every update, and out of combat the safety check runs once a
  second instead of four times (everything has its own event there).
- An item's glow follows the end of its cooldown at once.
- New: `/pt perf` shows how long glow updates take; `/pt buttons` starts with how many buttons each
  kind of bar has.

## 1.18.0 (Milestone 3: spell, item and aura tracking; test build)

- Fixed: a debuff cast at another unit (a mouseover or focus macro) counted as on your target.
- Fixed: switching targets while casting put the debuff on the new target.
- Fixed: a buff cast on someone else counted as on you.
- How long buffs and debuffs last is remembered per character across sessions, and taken from the
  spell's tooltip until it's been seen: a buff cast in combat right after logging in is no longer
  "can't tell".
- Macros with modifier conditions ([mod:shift]) switch their glow at once.
- New: `/pt spell <spell>` (cast time, duration, charges), `/pt buttons` (what each macro reads as),
  `/pt api` (which game functions this client has).
- Every game function is read through one compatibility layer, always protected.

## 1.17.0 (Milestone 2: advanced condition evaluation; test build)

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

## 1.16.0 (Milestone 1: condition engine reliability; test build)

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
