#!/usr/bin/env python3
"""Proc This! offline tests: python3 tests/run_tests.py  (needs: pip install lupa)

Loads the addon's files (in the toc's order) against a mock of the game client (tests/mock.lua)
and checks the evaluation results, aura estimates, rule dependencies and saved-variable
migration. Logic only: what the real client returns and hides is checked in game (see
DEVELOPMENT.md, "In-game checklist").
"""
import os, sys
from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FILES = [l.strip() for l in open(os.path.join(ROOT, 'ProcThis.toc')) if l.strip().endswith('.lua') and not l.startswith('#')]


def load(saved=None):
    L = LuaRuntime()
    L.execute(open(os.path.join(HERE, 'mock.lua')).read())
    if saved:
        L.execute(saved)
    ns = L.eval('{}')
    run = L.eval('function(src, n, ns) return assert(loadstring(src, "@" .. n))("ProcThis", ns) end')
    for f in FILES:
        run(open(os.path.join(ROOT, f)).read(), f, ns)
    L.globals().NS = ns
    L.execute('MOCK.Start(); R = NS.Result; G = NS.Glow; S = NS.State')
    return L


failures, count = [], 0


def test(name, saved=None):
    def wrap(fn):
        global count
        count += 1
        try:
            L = load(saved)
            L.execute(fn.__doc__)
            print('ok   ', name)
        except Exception as e:  # noqa
            failures.append(name); print('FAIL ', name, '\n     ', str(e).replace('\n', '\n      '))
        return fn
    return wrap

# ---------------------------------------------------------------------------------------------
# The result model (pure)
# ---------------------------------------------------------------------------------------------
@test("result: AND - a confirmed FALSE decides; else ERROR, else UNKNOWN; gates gathered; else TRUE")
def _():
    """
    local T, F, Gd, U, E = R.TRUE, R.FALSE, R.GATED, R.UNKNOWN, R.ERROR
    assert(R.All({ { T }, { T } }) == T)
    assert(R.All({ { U, "u" }, { F, "no" } }) == F, "FALSE beats UNKNOWN")
    local st, why = R.All({ { T }, { U, "hidden" } }); assert(st == U and why == "hidden")
    assert(R.All({ { U, "u" }, { E, "e" } }) == E, "ERROR reported before UNKNOWN")
    local st2, _, gs = R.All({ { Gd, nil, { "a" } }, { T }, { Gd, nil, { "b", "c" } } })
    assert(st2 == Gd and #gs == 3, "gates gathered")
    assert(R.All({ { Gd, nil, { "a" } }, { U, "u" } }) == U, "a gate and an unknown: can't glow")
    """

@test("result: OR - TRUE decides; one GATED stands for it; two GATED -> UNKNOWN; UNKNOWN beats FALSE")
def _():
    """
    local T, F, Gd, U, E = R.TRUE, R.FALSE, R.GATED, R.UNKNOWN, R.ERROR
    assert(R.Any({ { F, "a" }, { U, "u" }, { T } }) == T)
    local st, _, gs = R.Any({ { F, "a" }, { Gd, nil, { "g" } }, { U, "u" } })
    assert(st == Gd and gs[1] == "g", "one gate: the game decides (never a wrong glow)")
    assert(R.Any({ { Gd, nil, { "g" } }, { Gd, nil, { "h" } } }) == U, "two gates can't be ORed yet")
    assert(R.Any({ { F, "a" }, { U, "u" } }) == U, "UNKNOWN is not FALSE")
    assert(R.Any({ { F, "a" }, { E, "e" } }) == E)
    local st2, why = R.Any({ { F, "a" }, { F, "b" } }); assert(st2 == F and why == "none of: a; or b", why)
    """

@test("result: NOT - TRUE<->FALSE; UNKNOWN / ERROR stay; one invertible gate flips, else UNKNOWN")
def _():
    """
    local inv = function(g) return "not " .. g end
    assert(R.Not(R.TRUE) == R.FALSE and R.Not(R.FALSE) == R.TRUE)
    assert(R.Not(R.UNKNOWN, "u") == R.UNKNOWN and R.Not(R.ERROR, "e") == R.ERROR)
    local st, _, gs = R.Not(R.GATED, nil, { "g" }, inv); assert(st == R.GATED and gs[1] == "not g")
    assert(R.Not(R.GATED, nil, { "g", "h" }, inv) == R.UNKNOWN)
    assert(R.Not(R.GATED, nil, { "g" }, function() return nil end) == R.UNKNOWN)
    """

# ---------------------------------------------------------------------------------------------
# Buffs on you (the M1 defect: never-seen buffs were "absent")
# ---------------------------------------------------------------------------------------------
@test("aura: never seen in combat, not tracked -> UNKNOWN, and a 'missing' rule doesn't glow")
def _():
    """
    wipe(NS.db.rules)
    local r = MOCK.Rule({ spell = "Lightning Bolt", auras = { { name = "Clearcasting", unit = "player", kind = "buff", mode = "missing" } } })
    MOCK.Combat(true)
    local has, how = S.HasBuff("Clearcasting")
    assert(has == nil and how == "unknown", tostring(has) .. " " .. tostring(how))
    local st = G.Evaluate(r)
    assert(st == R.UNKNOWN, "was TRUE before 1.16.0 (never seen = absent): " .. tostring(st))
    G.Update(); assert(MOCK.Glow("ActionButton2") == "", "no glow")
    """

@test("aura: seen on you with an end time -> present (estimate) until then, then absent (estimate)")
def _():
    """
    MOCK.buffs["Lightning Shield"] = { duration = 600, expirationTime = MOCK.now + 30 }
    assert(S.HasBuff("Lightning Shield") == true)        -- read directly, remembered
    MOCK.Combat(true)
    local has, how = S.HasBuff("Lightning Shield"); assert(has == true and how == "estimate")
    MOCK.now = MOCK.now + 31
    has, how = S.HasBuff("Lightning Shield"); assert(has == false and how == "estimate")
    """

@test("aura: seen absent -> absent (estimate) only for the rule's own spell; any other buff UNKNOWN")
def _():
    """
    assert(S.HasBuff("Lightning Shield") == false)
    assert(S.HasBuff("Clearcasting") == false)
    MOCK.Combat(true)
    local has, how = S.HasBuff("Lightning Shield", true); assert(has == false and how == "estimate")
    has, how = S.HasBuff("Clearcasting", false); assert(has == nil and how == "unknown", "a proc can put it on you")
    """

@test("aura: your cast -> present (estimate) for its known duration; unknown duration -> UNKNOWN")
def _():
    """
    MOCK.buffs["Lightning Shield"] = { duration = 600, expirationTime = MOCK.now + 600 }
    S.HasBuff("Lightning Shield")                          -- learns it lasts 600 s
    MOCK.buffs["Lightning Shield"] = nil; S.HasBuff("Lightning Shield")
    MOCK.Combat(true)
    MOCK.now = MOCK.now + 5; MOCK.Cast(945)
    local has, how = S.HasBuff("Lightning Shield", true); assert(has == true and how == "estimate")
    MOCK.now = MOCK.now + 601
    has = S.HasBuff("Lightning Shield", true); assert(has == false, "ran out")
    MOCK.Cast(403)                                         -- Lightning Bolt: never seen as a buff
    assert(S.HasBuff("Lightning Bolt") == nil, "a cast alone doesn't prove a buff")
    """

@test("aura: the Cooldown Manager answers exactly in combat")
def _():
    """
    MOCK.Combat(true); MOCK.cdmOn = true; MOCK.cdm[945] = true
    local has, how = S.HasBuff("Lightning Shield"); assert(has == true and how == "cdm")
    MOCK.cdm[945] = false
    has = S.HasBuff("Lightning Shield"); assert(has == false)
    """

# ---------------------------------------------------------------------------------------------
# Your debuffs on your target: from your casts, per target
# ---------------------------------------------------------------------------------------------
@test("debuff: per target (GUID): cast on A, switch to B (absent), back to A (still on)")
def _():
    """
    MOCK.Combat(true)
    local r = MOCK.Rule({ spell = "Flame Shock", auras = { { name = "", unit = "target", kind = "debuff", mode = "missing", mine = true, dur = 12 } } })
    MOCK.Cast(8050)
    local has, how = S.TargetDebuff("Flame Shock", true, 12); assert(has == true and how == "estimate")
    MOCK.target = "Creature-2"; MOCK.Fire("PLAYER_TARGET_CHANGED")
    has = S.TargetDebuff("Flame Shock", true, 12); assert(has == false, "nothing cast on B")
    assert(G.Evaluate(r) == R.TRUE, "refresh it on B")
    MOCK.target = "Creature-1"; MOCK.Fire("PLAYER_TARGET_CHANGED")
    has = S.TargetDebuff("Flame Shock", true, 12); assert(has == true, "A still has it (was absent before 1.16.0)")
    MOCK.now = MOCK.now + 13
    assert(S.TargetDebuff("Flame Shock", true, 12) == false, "ran out")
    """

@test("debuff: charges used up by other spells; GUID hidden -> UNKNOWN after a switch; combat end forgets")
def _():
    """
    MOCK.Combat(true)
    local r = MOCK.Rule({ spell = "Earth Shock", auras = { { name = "Stormstrike", unit = "target", kind = "debuff", mode = "present", mine = true, dur = 12, charges = 2, usedBy = "Lightning Bolt, Earth Shock" } } })
    MOCK.Cast(17364)
    assert(S.TargetDebuff("Stormstrike", true, 12) == true)
    MOCK.Cast(403); MOCK.Cast(8042)
    local has, how, d = S.TargetDebuff("Stormstrike", true, 12); assert(has == false and d:find("charges"), tostring(d))
    MOCK.guidHidden = true; MOCK.Cast(17364)
    assert(S.TargetDebuff("Stormstrike", true, 12) == true, "same target, GUID hidden: still followed")
    MOCK.Fire("PLAYER_TARGET_CHANGED")
    assert(S.TargetDebuff("Stormstrike", true, 12) == nil, "can't tell targets apart: unknown")
    MOCK.guidHidden = false; MOCK.Cast(17364); MOCK.Combat(false); MOCK.Combat(true)
    assert(S.TargetDebuff("Stormstrike", true, 12) == false, "forgotten after combat (no cast on it since)")
    """

# ---------------------------------------------------------------------------------------------
# Rule-level checks and evaluation
# ---------------------------------------------------------------------------------------------
@test("ready: a hidden cooldown flag -> GATED (open when off cooldown); readable on cooldown -> FALSE")
def _():
    """
    MOCK.cooldown = { isActive = MOCK.Secret(true), isOnGCD = MOCK.Secret(false) }
    local st, _, g = S.Ready("Lightning Bolt"); assert(st == R.GATED and g.kind == "bool" and g.invert, tostring(st))
    MOCK.cooldown = { isActive = true, isOnGCD = false }; assert(S.Ready("Lightning Bolt") == R.FALSE)
    MOCK.cooldown = { isActive = true, isOnGCD = true }; assert(S.Ready("Lightning Bolt") == R.TRUE, "just the GCD")
    MOCK.noCooldownInfo = true; assert(S.Ready("Lightning Bolt") == R.UNKNOWN, "was TRUE before 1.16.0")
    """

@test("usable / control: hidden -> GATED; an error -> ERROR and no glow")
def _():
    """
    wipe(NS.db.rules)
    MOCK.usable = MOCK.Secret(true); assert(S.Usable("Lightning Bolt") == R.GATED)
    MOCK.control = MOCK.Secret(true); assert(S.HasControl() == R.GATED, "was TRUE before 1.16.0")
    MOCK.usable, MOCK.control = true, true
    MOCK.usableError = true; assert(S.Usable("Lightning Bolt") == R.ERROR)
    local r = MOCK.Rule({ spell = "Lightning Bolt" })
    assert(G.Evaluate(r) == R.ERROR); G.Update(); assert(MOCK.Glow("ActionButton2") == "")
    """

@test("evaluate: an UNKNOWN row with a FALSE row -> FALSE; with TRUE rows -> UNKNOWN; OR with a TRUE group -> TRUE")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Combat(true)
    local unknownRow = { name = "Clearcasting", unit = "player", kind = "buff", mode = "present", group = 1 }
    local falseRow = { name = "", unit = "player", kind = "instant", mode = "present", group = 1 }  -- 1.5 s cast: FALSE
    local trueRow = { name = "", unit = "player", kind = "instant", mode = "missing", group = 2 }
    local r = MOCK.Rule({ spell = "Lightning Bolt", auras = { unknownRow, falseRow } })
    assert(G.Evaluate(r) == R.FALSE)
    r.auras = { unknownRow, { name = "", unit = "player", kind = "instant", mode = "missing", group = 1 } }
    assert(G.Evaluate(r) == R.UNKNOWN)
    r.auras = { unknownRow, trueRow }; r.join = "or"
    assert(G.Evaluate(r) == R.TRUE, "one OR group holds")
    G.Update(); assert(MOCK.Glow("ActionButton2") == "glow")
    """

@test("evaluate: 'any one' group with two hidden health checks -> UNKNOWN (no glow), as before")
def _():
    """
    wipe(NS.db.rules)
    UnitHealth = function() return MOCK.Secret(50) end; UnitHealthMax = function() return MOCK.Secret(100) end
    UnitHealthPercent = function() return MOCK.Secret(1) end
    C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
    Enum = { LuaCurveType = { Step = 1 } }
    local r = MOCK.Rule({ spell = "Lightning Bolt", groupModes = { "any" }, auras = {
      { kind = "health", unit = "player", op = "lt", pct = 40, group = 1 },
      { kind = "health", unit = "target", op = "lt", pct = 20, group = 1 } } })
    assert(G.Evaluate(r) == R.UNKNOWN)
    r.auras[2] = nil
    assert(G.Evaluate(r) == R.GATED, "one hidden check: the game decides")
    G.Update(); assert(MOCK.Glow("ActionButton2") == "gated")
    """

@test("dependencies: active / inactive, a loop -> ERROR, an UNKNOWN rule propagates")
def _():
    """
    wipe(NS.db.rules)
    local a = MOCK.Rule({ spell = "Lightning Shield" })
    local b = MOCK.Rule({ spell = "Lightning Bolt", auras = { { kind = "rule", rule = a.id, mode = "present" } } })
    assert(G.Evaluate(b) == R.TRUE)
    b.auras[1].mode = "missing"; assert(G.Evaluate(b) == R.FALSE)
    MOCK.usable = MOCK.Secret(true)
    local st, _, gs = G.Evaluate(b); assert(st == R.GATED and gs[1].invert, "inactive = the hidden 'usable' flipped")
    MOCK.usable = true
    a.auras = { { name = "Clearcasting", unit = "player", kind = "buff", mode = "present" } }
    MOCK.Combat(true)
    b.auras[1].mode = "present"
    assert(G.Evaluate(b) == R.UNKNOWN, "depends on a rule that can't be told")
    b.auras[1].mode = "missing"
    assert(G.Evaluate(b) == R.UNKNOWN, "and its opposite can't be told either (was TRUE before 1.16.0)")
    a.auras = { { kind = "rule", rule = b.id, mode = "present" } }
    assert(G.Evaluate(b) == R.ERROR, "a loop")
    """

@test("several rules for one spell: TRUE wins over GATED; UNKNOWN / FALSE never glow")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Combat(true)
    MOCK.Rule({ spell = "Lightning Bolt", auras = { { name = "Clearcasting", unit = "player", kind = "buff", mode = "present" } } })
    G.Update(); assert(MOCK.Glow("ActionButton2") == "", "unknown only")
    MOCK.usable = MOCK.Secret(true)
    MOCK.Rule({ spell = "Lightning Bolt" })
    G.Update(); assert(MOCK.Glow("ActionButton2") == "gated")
    MOCK.usable = true
    G.Update(); assert(MOCK.Glow("ActionButton2") == "glow")
    """

@test("too many hidden checks -> UNKNOWN with a reason (no glow)")
def _():
    """
    wipe(NS.db.rules)
    MOCK.usable, MOCK.control, MOCK.inCombat = MOCK.Secret(true), MOCK.Secret(true), MOCK.Secret(true)
    MOCK.cooldown = { isActive = MOCK.Secret(false) }
    UnitHealth = function() return MOCK.Secret(50) end; UnitHealthMax = function() return MOCK.Secret(100) end
    UnitHealthPercent = function() return MOCK.Secret(1) end
    C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
    Enum = { LuaCurveType = { Step = 1 } }
    local r = MOCK.Rule({ spell = "Lightning Bolt", combat = true, auras = { { kind = "health", unit = "player", op = "lt", pct = 40 } } })
    local st, why = G.Evaluate(r); assert(st == R.UNKNOWN and why:find("too many"), tostring(why))
    """

# ---------------------------------------------------------------------------------------------
# Saved variables
# ---------------------------------------------------------------------------------------------
SAVED_OLD = '''
ProcThisDB = { nextRuleId = 5, chars = { ["Tester-Realm"] = { rules = {
  { id = 3, enabled = true, spell = "Lightning Shield", buff = "missing" },
  { id = 3, enabled = true, spell = "Earth Shock", tdebuff = "present", tdebuffName = "Stormstrike", tdebuffCharges = 2 },
} } } }
'''

@test("saved variables: old rule formats migrate; duplicate ids are fixed; other ids kept", saved=SAVED_OLD)
def _():
    """
    local rules = NS.db.rules
    assert(#rules == 2)
    assert(rules[1].id == 3, "the first keeps its id")
    assert(rules[2].id ~= 3 and rules[2].id > 5, "a duplicate gets a new one: " .. tostring(rules[2].id))
    local a1 = rules[1].auras[1]
    assert(a1.kind == "buff" and a1.mode == "missing" and a1.unit == "player")
    local a2 = rules[2].auras[1]
    assert(a2.kind == "debuff" and a2.unit == "target" and a2.name == "Stormstrike" and a2.charges == 2)
    assert(rules[1].buff == nil and rules[2].tdebuff == nil, "old fields dropped")
    """

@test("saved variables: a fresh character starts with the example rule (Lightning Shield)")
def _():
    """
    assert(#NS.db.rules == 1 and NS.db.rules[1].spell == "Lightning Shield", tostring(#NS.db.rules))
    assert(NS.db.rules[1].id ~= nil)
    """

print(f"\n{count - len(failures)}/{count} passed")
sys.exit(1 if failures else 0)
