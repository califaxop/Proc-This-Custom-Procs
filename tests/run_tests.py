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
    # a rule's result in a fresh pass (results are kept for one pass: an update)
    L.execute('function Eval(r) G.NewPass(); return G.Evaluate(r) end')
    # pure gates for the result-model tests: Gt("a"), and their opposites (they know each other)
    L.execute('''function Gt(n) return { n = n } end
function Inv(g) if not g.inv then local ng = { n = "not " .. g.n }; g.inv, ng.inv = ng, g end return g.inv end
function Gset(...) return R.Gates({ ... }) end''')
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
@test("result: AND - a confirmed FALSE decides; else ERROR, else UNKNOWN; gate sets multiply; else TRUE")
def _():
    """
    local T, F, Gd, U, E = R.TRUE, R.FALSE, R.GATED, R.UNKNOWN, R.ERROR
    local a, b, c = Gt("a"), Gt("b"), Gt("c")
    assert(R.All({ { T }, { T } }) == T)
    assert(R.All({ { U, "u" }, { F, "no" } }) == F, "FALSE beats UNKNOWN")
    local st, why = R.All({ { T }, { U, "hidden" } }); assert(st == U and why == "hidden")
    assert(R.All({ { U, "u" }, { E, "e" } }) == E, "ERROR reported before UNKNOWN")
    local st2, _, set = R.All({ { Gd, nil, Gset(a) }, { T }, { Gd, nil, Gset(b, c) } })
    assert(st2 == Gd and #set == 1 and #set[1] == 3, "one term, three gates")
    assert(R.All({ { Gd, nil, Gset(a) }, { U, "u" } }) == U, "a gate and an unknown: can't glow")
    local st3 = R.All({ { Gd, nil, Gset(a) }, { Gd, nil, Gset(Inv(a)) } })
    assert(st3 == F, "a hidden value and its opposite can't both hold")
    local st4, _, s4 = R.All({ { Gd, nil, Gset(a) }, { Gd, nil, Gset(a, b) } })
    assert(st4 == Gd and #s4[1] == 2, "the same gate counts once")
    """

@test("result: OR - TRUE decides; GATED ones join (one term each); with an UNKNOWN it's partial")
def _():
    """
    local T, F, Gd, U, E = R.TRUE, R.FALSE, R.GATED, R.UNKNOWN, R.ERROR
    local a, b = Gt("a"), Gt("b")
    assert(R.Any({ { F, "a" }, { U, "u" }, { T } }) == T)
    local st, _, set = R.Any({ { Gd, nil, Gset(a) }, { Gd, nil, Gset(b) } })
    assert(st == Gd and #set == 2 and not set.partial, "two hidden checks ORed: two terms (1.16.0: UNKNOWN)")
    local st2, why2, s2 = R.Any({ { F, "a" }, { Gd, nil, Gset(a) }, { U, "u" } })
    assert(st2 == Gd and s2.partial and why2 == "u", "the unknown branch can't light it: partial")
    local st3, _, s3 = R.Any({ { Gd, nil, Gset(a) }, { Gd, nil, Gset(a, b) } })
    assert(st3 == Gd and #s3 == 1 and #s3[1] == 1, "a or (a and b) = a")
    assert(R.Any({ { F, "a" }, { U, "u" } }) == U, "UNKNOWN is not FALSE")
    assert(R.Any({ { F, "a" }, { E, "e" } }) == E)
    local st4, why = R.Any({ { F, "a" }, { F, "b" } }); assert(st4 == F and why == "none of: a; or b", why)
    """

@test("result: NOT - TRUE<->FALSE; UNKNOWN / ERROR stay; gate sets negate (De Morgan); partial -> UNKNOWN")
def _():
    """
    local a, b = Gt("a"), Gt("b")
    assert(R.Not(R.TRUE) == R.FALSE and R.Not(R.FALSE) == R.TRUE)
    assert(R.Not(R.UNKNOWN, "u") == R.UNKNOWN and R.Not(R.ERROR, "e") == R.ERROR)
    local st, _, s = R.Not(R.GATED, nil, Gset(a), Inv); assert(st == R.GATED and s[1][1] == Inv(a))
    local st2, _, s2 = R.Not(R.GATED, nil, Gset(a, b), Inv)
    assert(st2 == R.GATED and #s2 == 2, "not (a and b) = not a, or not b (1.16.0: UNKNOWN)")
    local _, _, or2 = R.Any({ { R.GATED, nil, Gset(a) }, { R.GATED, nil, Gset(b) } })
    local st3, _, s3 = R.Not(R.GATED, nil, or2, Inv)
    assert(st3 == R.GATED and #s3 == 1 and #s3[1] == 2, "not (a or b) = not a and not b")
    assert(R.Not(R.GATED, nil, Gset(a), function() return nil end) == R.UNKNOWN, "no opposite")
    local _, _, part = R.Any({ { R.GATED, nil, Gset(a) }, { R.UNKNOWN, "u" } })
    assert(R.Not(R.GATED, nil, part, Inv) == R.UNKNOWN, "the opposite of a partial answer would glow wrongly")
    """

@test("result: limits - a term over MAX_GATES is left out (partial); nothing left -> UNKNOWN")
def _():
    """
    local gs = {}
    for i = 1, R.MAX_GATES + 1 do gs[i] = { R.GATED, nil, Gset(Gt("g" .. i)) } end
    local st, why = R.All(gs); assert(st == R.UNKNOWN and why:find("too many"), tostring(why))
    local st2, _, s2 = R.Any({ { R.GATED, nil, Gset(Gt("x")) }, { R.All(gs) } })
    assert(st2 == R.GATED and s2.partial, "kept what fits")
    """


# Every combination of truth values, against a formula built at random: the gate set lights the glow
# exactly when the formula holds (or, partial, never when it doesn't), and the exclusive layers
# (Disjoint) never light two at once.
@test("result: random nested AND / OR / NOT formulas against every truth assignment (exact, exclusive layers)")
def _():
    """
    math.randomseed(7)
    local vars = { Gt("p"), Gt("q"), Gt("r"), Gt("s") }
    local function holds(term, val)
      for _, g in ipairs(term) do
        local v = g.n:find("^not ") and not val[g.inv] or val[g]
        if not v then return false end
      end
      return true
    end
    -- a random formula: { op, ... } with leaves; returns evaluator and result
    local function build(depth)
      local k = math.random(depth > 2 and 1 or 4)
      if k == 1 then
        local g = vars[math.random(#vars)]
        local neg = math.random(3) == 1
        local leaf = neg and Inv(g) or g
        return function(val) return holds({ leaf }, val) end, { R.GATED, nil, Gset(leaf) }
      end
      local n = math.random(2, 3)
      local fs, rs = {}, {}
      for i = 1, n do fs[i], rs[i] = build(depth + 1) end
      if k == 2 then
        return function(val) for _, f in ipairs(fs) do if not f(val) then return false end end return true end, { R.All(rs) }
      elseif k == 3 then
        return function(val) for _, f in ipairs(fs) do if f(val) then return true end end return false end, { R.Any(rs) }
      end
      local f, x = fs[1], rs[1]
      return function(val) return not f(val) end, { R.Not(x[1], x[2], x[3], Inv) }
    end
    local checked = 0
    for _ = 1, 300 do
      local f, x = build(1)
      local st, set = x[1], x[3]
      if st == R.GATED then
        local layers = R.Disjoint(set, Inv, 99)
        for m = 0, 15 do
          local val = {}
          for i, g in ipairs(vars) do val[g] = math.floor(m / 2 ^ (i - 1)) % 2 == 1 end
          local lit = 0
          for _, t in ipairs(layers) do if holds(t, val) then lit = lit + 1 end end
          assert(lit <= 1, "two layers at once")
          local any = false
          for _, t in ipairs(set) do if holds(t, val) then any = true end end
          assert((lit == 1) == any, "the layers light exactly when the set does")
          if set.partial then assert(not any or f(val), "partial: never a wrong glow")
          else assert(any == f(val), "exact") end
          checked = checked + 1
        end
      elseif st == R.TRUE or st == R.FALSE then
        for m = 0, 15 do
          local val = {}
          for i, g in ipairs(vars) do val[g] = math.floor(m / 2 ^ (i - 1)) % 2 == 1 end
          assert(f(val) == (st == R.TRUE), "a decided answer is right for every value")
        end
      end
    end
    assert(checked > 1000, "enough GATED formulas: " .. checked)
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
    local st = Eval(r)
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

@test("aura: a buff with charges (Lightning Shield) can't be estimated as on once you're hit")
def _():
    """
    MOCK.buffs["Lightning Shield"] = { duration = 600, expirationTime = MOCK.now + 600, applications = 3 }
    S.HasBuff("Lightning Shield")                          -- learns: 600 s, has charges
    MOCK.Combat(true)
    MOCK.now = MOCK.now + 1
    local has, how = S.HasBuff("Lightning Shield", true); assert(has == true and how == "estimate")
    MOCK.Hit("HEAL"); assert(S.HasBuff("Lightning Shield", true) == true, "a heal uses no charge")
    MOCK.now = MOCK.now + 1; MOCK.Hit()
    has, how = S.HasBuff("Lightning Shield", true); assert(has == nil and how == "unknown", "seen on, then hit")
    MOCK.now = MOCK.now + 1; MOCK.Cast(945)
    has, how = S.HasBuff("Lightning Shield", true); assert(has == true and how == "estimate", "recast: full charges")
    MOCK.now = MOCK.now + 1; MOCK.Hit(MOCK.Secret("WOUND"))
    has = S.HasBuff("Lightning Shield", true); assert(has == nil, "a hidden hit counts too")
    MOCK.Rule({ spell = "Lightning Shield", auras = { { kind = "buff", name = "Lightning Shield", unit = "player", mode = "missing" } } })
    G.Update(); assert(MOCK.Glow("ActionButton1") == "", "can't tell -> no glow")
    """

@test("aura: a buff without charges stays estimated as on when you're hit")
def _():
    """
    MOCK.buffs["Water Walking"] = { duration = 600, expirationTime = MOCK.now + 600 }
    S.HasBuff("Water Walking")
    MOCK.Combat(true); MOCK.now = MOCK.now + 1; MOCK.Hit()
    local has, how = S.HasBuff("Water Walking"); assert(has == true and how == "estimate")
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
    assert(Eval(r) == R.TRUE, "refresh it on B")
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
    assert(Eval(r) == R.ERROR); G.Update(); assert(MOCK.Glow("ActionButton2") == "")
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
    assert(Eval(r) == R.FALSE)
    r.auras = { unknownRow, { name = "", unit = "player", kind = "instant", mode = "missing", group = 1 } }
    assert(Eval(r) == R.UNKNOWN)
    r.auras = { unknownRow, trueRow }; r.join = "or"
    assert(Eval(r) == R.TRUE, "one OR group holds")
    G.Update(); assert(MOCK.Glow("ActionButton2") == "glow")
    """

@test("evaluate: 'any one' group with two hidden health checks -> GATED, two layers (1.16.0: UNKNOWN)")
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
    local st, _, set = Eval(r); assert(st == R.GATED and #set == 2, "the game decides either")
    G.Update(); local g, n = MOCK.Glow("ActionButton2"); assert(g == "gated" and n == 2, g .. n)
    r.auras[2] = nil
    G.Update(); g, n = MOCK.Glow("ActionButton2"); assert(g == "gated" and n == 1, "one layer again")
    """

@test("evaluate: OR of hidden flags - the layers open exactly when the OR holds, one at a time")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Combat(true)
    -- (castable and in control) or in combat, each hidden: A = usable, B = control, C = combat
    MOCK.usable, MOCK.control, MOCK.inCombat = MOCK.Secret("A"), MOCK.Secret("B"), MOCK.Secret("C")
    local a = MOCK.Rule({ spell = "Purge", usable = true, control = true })
    local r = MOCK.Rule({ spell = "Lightning Bolt", usable = false, control = false, join = "or", auras = {
      { kind = "rule", rule = a.id, mode = "present", group = 1 },
      { kind = "rule", rule = MOCK.Rule({ spell = "Earth Shock", usable = false, control = false, combat = true }).id, mode = "present", group = 2 } } })
    local st, _, set = Eval(r); assert(st == R.GATED and #set == 2)
    G.Update()
    for m = 0, 7 do
      local A, B, C = m % 2 == 1, math.floor(m / 2) % 2 == 1, math.floor(m / 4) % 2 == 1
      local open = MOCK.OpenLayers("ActionButton2", { A = A, B = B, C = C })
      assert(open == (((A and B) or C) and 1 or 0), "A B C = " .. tostring(A) .. tostring(B) .. tostring(C) .. ": " .. open)
    end
    """

@test("several rules for one spell: both GATED -> both count (1.16.0: only the first); TRUE wins")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Combat(true)
    MOCK.Rule({ spell = "Lightning Bolt", auras = { { name = "Clearcasting", unit = "player", kind = "buff", mode = "present" } } })
    G.Update(); assert(MOCK.Glow("ActionButton2") == "", "unknown only")
    MOCK.usable, MOCK.control = MOCK.Secret("U"), MOCK.Secret("K")
    local r1 = MOCK.Rule({ spell = "Lightning Bolt", control = false })     -- castable (hidden)
    local r2 = MOCK.Rule({ spell = "Lightning Bolt", usable = false })      -- in control (hidden)
    G.Update()
    assert(MOCK.OpenLayers("ActionButton2", { U = true, K = false }) == 1, "the first rule")
    assert(MOCK.OpenLayers("ActionButton2", { U = false, K = true }) == 1, "the second rule (1.16.0: no glow)")
    assert(MOCK.OpenLayers("ActionButton2", { U = true, K = true }) == 1, "both: one layer only")
    assert(MOCK.OpenLayers("ActionButton2", { U = false, K = false }) == 0)
    MOCK.usable = true
    G.Update(); local g, n = MOCK.Glow("ActionButton2"); assert(g == "glow" and n == 1, "a plain yes wins")
    """

@test("dependencies: active / inactive; hidden -> the opposite gate; UNKNOWN propagates both ways")
def _():
    """
    wipe(NS.db.rules)
    local a = MOCK.Rule({ spell = "Lightning Shield" })
    local b = MOCK.Rule({ spell = "Lightning Bolt", auras = { { kind = "rule", rule = a.id, mode = "present" } } })
    assert(Eval(b) == R.TRUE)
    b.auras[1].mode = "missing"; assert(Eval(b) == R.FALSE)
    MOCK.usable = MOCK.Secret("U")
    local st, _, set = Eval(b)
    assert(st == R.GATED and #set == 1 and set[1][1].invert, "inactive = the hidden 'usable' flipped")
    MOCK.usable = true
    a.auras = { { name = "Clearcasting", unit = "player", kind = "buff", mode = "present" } }
    MOCK.Combat(true)
    b.auras[1].mode = "present"
    assert(Eval(b) == R.UNKNOWN, "depends on a rule that can't be told")
    b.auras[1].mode = "missing"
    assert(Eval(b) == R.UNKNOWN, "and its opposite can't be told either")
    """

@test("dependencies: a rule used by several others is worked out once per pass")
def _():
    """
    wipe(NS.db.rules)
    local base = MOCK.Rule({ spell = "Lightning Shield" })
    for _, sp in ipairs({ "Lightning Bolt", "Earth Shock", "Flame Shock" }) do
      MOCK.Rule({ spell = sp, auras = { { kind = "rule", rule = base.id, mode = "present" } } })
    end
    local calls, real = 0, C_Spell.IsSpellUsable
    C_Spell.IsSpellUsable = function(n) if n == "Lightning Shield" then calls = calls + 1 end return real(n) end
    G.Update()
    assert(calls == 1, "Lightning Shield's rule read " .. calls .. " times")
    C_Spell.IsSpellUsable = real
    """

@test("dependencies: a loop names its rules; the rule picker leaves out rules that would make one")
def _():
    """
    wipe(NS.db.rules)
    local a = MOCK.Rule({ spell = "Lightning Shield" })
    local b = MOCK.Rule({ spell = "Lightning Bolt", auras = { { kind = "rule", rule = a.id, mode = "present" } } })
    local c = MOCK.Rule({ spell = "Earth Shock", auras = { { kind = "rule", rule = b.id, mode = "present" } } })
    assert(NS.DependsOn(c, a) and not NS.DependsOn(a, c), "c needs a (through b)")
    a.auras = { { kind = "rule", rule = c.id, mode = "present" } }
    local st, why = Eval(a)
    assert(st == R.ERROR and why:find("Lightning Shield > Earth Shock > Lightning Bolt > Lightning Shield", 1, true), why)
    G.Update(); assert(MOCK.Glow("ActionButton1") == "", "no glow")
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
    local r = MOCK.Rule({ spell = "Lightning Bolt", combat = true, auras = {
      { kind = "health", unit = "player", op = "lt", pct = 40 }, { kind = "health", unit = "target", op = "lt", pct = 40 },
      { kind = "health", unit = "player", op = "gt", pct = 10 } } })
    local st, why = Eval(r); assert(st == R.UNKNOWN and why:find("too many"), tostring(why))
    G.Update(); assert(MOCK.Glow("ActionButton2") == "")
    """

# ---------------------------------------------------------------------------------------------
# Milestone 3: the compatibility layer, durations, where casts went, macros
# ---------------------------------------------------------------------------------------------
@test("compat: a missing function -> nil (UNKNOWN), an older form is used when the newer one is missing")
def _():
    """
    local API = NS.API
    assert(API.Call("ItemUsable", 1) == nil, "no C_Item.IsUsableItem / IsUsableItem in the mock")
    assert(S.Usable("Hearthstone", 6948) == R.UNKNOWN)
    local newer = C_Spell.IsSpellUsable
    C_Spell.IsSpellUsable = nil; IsUsableSpell = function() return false end
    assert(S.Usable("Lightning Bolt") == R.FALSE, "the older global answers")
    C_Spell.IsSpellUsable = newer
    local ok, msg = API.Call("SpellUsable", "x"); assert(ok == true)
    MOCK.usableError = true; ok = API.Call("SpellUsable", "x"); assert(ok == false, "an error is false, not nil")
    local report = table.concat(API.Report(), " | ")
    assert(report:find("SpellUsable: C_Spell.IsSpellUsable", 1, true) and report:find("ItemUsable: .*not on this client"), report)
    """

SAVED_DUR = '''
ProcThisDB = { chars = { ["Tester-Realm"] = { rules = {}, durations = { ["Lightning Shield"] = 600 }, charged = {} } } }
'''

@test("durations: kept from an earlier session - a cast in combat right after login is an estimate", saved=SAVED_DUR)
def _():
    """
    MOCK.Combat(true); MOCK.now = MOCK.now + 1; MOCK.Cast(945)
    local has, how, d = S.HasBuff("Lightning Shield", true)
    assert(has == true and how == "estimate" and d:find("lasts 600 s)", 1, true), tostring(d))
    """

@test("durations: a read is kept in the character's saved variables")
def _():
    """
    MOCK.buffs["Lightning Shield"] = { duration = 600, expirationTime = MOCK.now + 600, applications = 3 }
    S.HasBuff("Lightning Shield")
    assert(NS.char.durations["Lightning Shield"] == 600 and NS.char.charged["Lightning Shield"] == true)
    """

@test("durations: never seen -> from the spell's tooltip (labelled); a learned one comes first")
def _():
    """
    C_Spell.GetSpellDescription = function(id)
      if id == 945 then return "Surrounds the caster with balls of lightning. Each ball deals 13 Nature damage. Lasts 10 min." end
      if id == 8050 then return "Instantly sears the target with fire, causing 25 Fire damage immediately and 28 Fire damage over 12 sec." end
      return ""
    end
    MOCK.Combat(true); MOCK.Cast(945)
    local has, how, d = S.HasBuff("Lightning Shield", true)
    assert(has == true and how == "estimate" and d:find("lasts 600 s, from its tooltip", 1, true), tostring(d))
    MOCK.Rule({ spell = "Earth Shock", auras = { { name = "Flame Shock", unit = "target", kind = "debuff", mode = "missing", mine = true } } })
    MOCK.Cast(8050)
    local _, _, d2 = S.TargetDebuff("Flame Shock", true, 0)
    assert(d2:find("lasts 12 s, from its tooltip", 1, true), d2)
    NS.char.durations["Flame Shock"] = 15
    _, _, d2 = S.TargetDebuff("Flame Shock", true, 0); assert(d2:find("lasts 15 s)", 1, true), d2)
    assert(S.TooltipDuration("Purge") == nil, "no text: nothing")
    """

@test("where casts went: a mouseover / focus cast isn't put on your target; a switch mid-cast keeps the first target")
def _():
    """
    MOCK.Combat(true)
    MOCK.Rule({ spell = "Earth Shock", auras = { { name = "Flame Shock", unit = "target", kind = "debuff", mode = "missing", mine = true, dur = 12 } } })
    MOCK.Sent(8050, "Other Mob", "g1"); MOCK.Done(8050, "g1")
    local has, _, d = S.TargetDebuff("Flame Shock", true, 12)
    assert(has == false and d:find("haven't cast"), "went to another unit (1.17.0: counted on your target)")
    MOCK.Sent(8050, "Mob", "g2")
    MOCK.target, MOCK.targetName = "Creature-2", "Other"; MOCK.Fire("PLAYER_TARGET_CHANGED")
    MOCK.Done(8050, "g2")
    assert(S.TargetDebuff("Flame Shock", true, 12) == false, "not on the target you switched to")
    MOCK.target, MOCK.targetName = "Creature-1", "Mob"; MOCK.Fire("PLAYER_TARGET_CHANGED")
    assert(S.TargetDebuff("Flame Shock", true, 12) == true, "on the one it was cast at")
    MOCK.Sent(8050, "Mob-OtherRealm", "g3"); MOCK.Done(8050, "g3")
    assert(S.TargetDebuff("Flame Shock", true, 12) == true, "a realm after the name is the same unit")
    """

@test("where casts went: a buff cast on someone else isn't counted as on you")
def _():
    """
    NS.char.durations = { ["Lightning Shield"] = 600 }
    MOCK.Combat(true)
    MOCK.Sent(945, "Friend", "g1"); MOCK.Done(945, "g1")
    assert(S.HasBuff("Lightning Shield", true) == nil, "not counted as on you (1.17.0: on you)")
    MOCK.Sent(945, "", "g2"); MOCK.Done(945, "g2")
    assert(S.HasBuff("Lightning Shield", true) == true, "a self cast")
    """

@test("macros: a modifier change updates at once; /pt buttons shows what a macro reads as")
def _():
    """
    assert(MOCK.events.MODIFIER_STATE_CHANGED, "registered")
    MOCK.slots[3] = { "macro", 403, "spell" }; MOCK.Fire("ACTIONBAR_SLOT_CHANGED", 3)
    local report = table.concat(G.ButtonReport(), " | ")
    assert(report:find("ActionButton3 (slot 3): macro -> Lightning Bolt", 1, true), report)
    assert(report:find("ActionButton1 (slot 1): spell Lightning Shield |cff60ff60(has a rule)", 1, true), report)
    MOCK.slots[3] = { "macro", 999, "" }; MOCK.Fire("ACTIONBAR_SLOT_CHANGED", 3)
    report = table.concat(G.ButtonReport(), " | ")
    assert(report:find("nothing Proc This! can read", 1, true), report)
    """

# ---------------------------------------------------------------------------------------------
# Milestone 4: button providers, rendering, performance
# ---------------------------------------------------------------------------------------------
@test("buttons: a LibActionButton bar glows; a button that drops out of the list loses its glow")
def _():
    """
    -- a LibActionButton-1.0 bar (Bartender4, ElvUI): its button for action slot 2 (Lightning Bolt)
    LABBTN = MOCK.obj("BT4Button2"); LABBTN._state_type = "action"; LABBTN._state_action = 2
    LAB = { buttonRegistry = { [LABBTN] = true } }
    LibStub = { GetLibrary = function(_, name) if name == "LibActionButton-1.0" then return LAB end end }
    NS.Buttons.Rescan()
    wipe(NS.db.rules)
    MOCK.Rule({ spell = "Lightning Bolt" })
    G.Update()
    assert(MOCK.Glow("BT4Button2") == "glow", "LibActionButton's button glows")
    assert(MOCK.Glow("ActionButton2") == "glow", "and Blizzard's")
    local report = G.ButtonReport()[1]
    assert(report:find("Blizzard 5", 1, true) and report:find("LibActionButton 1", 1, true) and report:find("EllesmereUI not loaded", 1, true), report)
    LAB.buttonRegistry[LABBTN] = nil
    MOCK.now = MOCK.now + 6; G.Update()
    assert(MOCK.Glow("BT4Button2") == "", "dropped: glow off")
    """

@test("performance: rules whose spell isn't on a shown button aren't worked out")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Rule({ spell = "Purge" })                            -- not on any bar
    MOCK.Rule({ spell = "Lightning Bolt" })
    local calls, real = {}, C_Spell.IsSpellUsable
    C_Spell.IsSpellUsable = function(n) calls[n] = (calls[n] or 0) + 1 return real(n) end
    G.PerfReport()
    G.Update()
    assert(not calls["Purge"] and calls["Lightning Bolt"] == 1, "Purge read " .. tostring(calls["Purge"]))
    ActionButton2._shown = false; G.Update()                  -- its button hidden (a bar page, a hidden bar)
    assert(calls["Lightning Bolt"] == 1, "not read while its button is hidden")
    ActionButton2._shown = true
    local lines = G.PerfReport()
    assert(lines[1]:find("^2 updates") and lines[2]:find("0.5 rules worked out, 1.5 skipped", 1, true), lines[1] .. " / " .. lines[2])
    C_Spell.IsSpellUsable = real
    """

@test("performance: the safety tick runs 4 a second in combat, once a second out of combat")
def _():
    """
    local n, real = 0, G.Update
    G.Update = function() n = n + 1; real() end
    real()                                                     -- (an update just happened)
    for _ = 1, 4 do MOCK.now = MOCK.now + 0.25; G.Tick() end
    assert(n == 1, "out of combat: once in a second, " .. n)
    MOCK.Combat(true); n = 0
    for _ = 1, 4 do MOCK.now = MOCK.now + 0.25; G.Tick() end
    assert(n == 4, "in combat: every tick, " .. n)
    assert(MOCK.events.BAG_UPDATE_COOLDOWN, "item cooldowns have their event")
    G.Update = real
    """

@test("rendering: a glowing button's look is set once, not on every update; a restyle sets it again")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Rule({ spell = "Lightning Bolt", color = "custom", colorCustom = { 0, 1, 1 } })
    G.Update(); local after1 = MOCK.tints or 0
    assert(after1 > 0, "tinted when it starts")
    G.Update(); G.Update()
    assert((MOCK.tints or 0) == after1, "not again while it glows")
    G.Restyle()
    assert((MOCK.tints or 0) > after1, "a restyle sets the look again")
    """

# ---------------------------------------------------------------------------------------------
# Milestone 5: sharing, templates, priority, no target
# ---------------------------------------------------------------------------------------------
@test("share: export -> import gives the same rules (item links, colours, groups); Rule rows follow the copies")
def _():
    """
    wipe(NS.db.rules)
    local a = MOCK.Rule({ spell = "|cffffffff|Hitem:6948::::::::60:::::|h[Hearthstone]|h|r", color = "custom",
      colorCustom = { 0.25, 0.5, 1 }, scale = 1.2, alpha = 0.8, join = "or", groupModes = { "all", "any" },
      auras = { { name = "Clearcasting", unit = "player", kind = "buff", mode = "missing", group = 1 },
                { kind = "health", unit = "target", op = "le", pct = 35, group = 2 } } })
    local b = MOCK.Rule({ spell = "Earth Shock", auras = { { kind = "rule", rule = a.id, mode = "present" } } })
    local text = NS.Share.Export(NS.db.rules)
    assert(text:sub(1, 4) == "PT1:" and not text:find("|", 1, true), "no raw | in the text")
    local rules = assert(NS.Share.Import(text))
    assert(#rules == 2 and rules[1].spell == a.spell and rules[1].colorCustom[3] == 1 and rules[1].scale == 1.2)
    assert(rules[1].groupModes[2] == "any" and rules[1].join == "or" and rules[1].auras[2].op == "le" and rules[1].auras[2].pct == 35)
    local n = NS.AddRuleCopies(rules)
    assert(n == 2 and #NS.db.rules == 4)
    local ca, cb = NS.db.rules[3], NS.db.rules[4]
    assert(ca.id ~= a.id and cb.auras[1].rule == ca.id, "the copy's Rule row points at the copy")
    local one = assert(NS.Share.Import(NS.Share.Export(NS.db.rules, b)))
    assert(#one == 2, "a rule exports with the rules it uses: " .. #one)
    """

@test("share: import never runs the text; bad text is refused; unknown fields and bad values are dropped")
def _():
    """
    local r, err = NS.Share.Import("hello"); assert(not r and err:find("isn't Proc This!"), err)
    r, err = NS.Share.Import("PT1:{os.exit()}"); assert(not r and err:find("damaged"), err)
    r, err = NS.Share.Import('PT1:{{spell="x";'); assert(not r, "unfinished")
    r, err = NS.Share.Import("PT1:" .. string.rep("{", 20) .. string.rep("}", 20)); assert(not r and err:find("deep"), err)
    r = assert(NS.Share.Import('PT1:{{spell="Purge";alpha=5;evil="x";enabled="yes";auras={{kind="nope";unit="target";pct=50;};};};}'))
    assert(r[1].spell == "Purge" and r[1].alpha == 1 and r[1].evil == nil and r[1].enabled == true, "defaults for bad values")
    assert(r[1].auras[1].kind == "buff" and r[1].auras[1].unit == "target" and r[1].auras[1].pct == 50)
    assert(select(2, NS.Share.Import("PT1:{}")):find("no rules"))
    """

@test("templates, duplicate and priority: the higher rule's look comes first")
def _():
    """
    wipe(NS.db.rules)
    local t = NS.NewRule("debuffMissing")
    assert(t.combat and t.auras[1].kind == "debuff" and t.auras[1].unit == "target" and t.auras[1].mine and t.auras[1].dur == 0)
    assert(#NS.NewRule().auras == 0 and NS.NewRule().id ~= NS.NewRule().id)
    MOCK.Combat(true)
    MOCK.usable, MOCK.control = MOCK.Secret("U"), MOCK.Secret("K")
    local r1 = MOCK.Rule({ spell = "Lightning Bolt", control = false, color = "red" })
    local i = NS.DuplicateRule(1)
    local r2 = NS.db.rules[i]
    assert(i == 2 and r2.id ~= r1.id and r2.color == "red")
    r2.usable, r2.control, r2.color = false, true, "blue"
    G.Update()
    assert(ActionButton2.SG_Layers[1].styled == r1, "the higher rule is the first layer")
    assert(NS.MoveRule(2, -1) == 1 and NS.db.rules[1] == r2)
    G.Restyle()
    assert(ActionButton2.SG_Layers[1].styled == r2, "moved up: now first")
    assert(NS.MoveRule(1, -1) == 1, "already at the top")
    """

@test("no target: a target buff / debuff row doesn't hold, 'missing' included (before: glowed)")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Rule({ spell = "Flame Shock", auras = { { name = "Flame Shock", unit = "target", kind = "debuff", mode = "missing", mine = true } } })
    MOCK.target = nil
    G.Update(); assert(MOCK.Glow("ActionButton3") == "", "nothing targeted: no glow")
    local st, why = Eval(NS.db.rules[1]); assert(st == R.FALSE and why == "no target", tostring(why))
    MOCK.target = "Creature-1"
    G.Update(); assert(MOCK.Glow("ActionButton3") == "glow", "a target without it: glows")
    """

# ---------------------------------------------------------------------------------------------
# Milestone 6: diagnostics
# ---------------------------------------------------------------------------------------------
@test("diagnostics: an error while working a rule out is caught, shown as ERROR and kept for /pt report")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Rule({ spell = "Lightning Bolt" })
    local real = S.Usable
    S.Usable = function() error("boom") end
    G.Update(); G.Update()
    assert(MOCK.Glow("ActionButton2") == "", "no glow")
    local e = G.errors[#G.errors]
    assert(e and e.where == "Lightning Bolt" and e.msg:find("boom") and e.n == 2, "kept once, counted twice")
    S.Usable = real
    """

@test("diagnostics: /pt debug prints each rule's status change; /pt report gathers everything in one text")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Rule({ spell = "Lightning Bolt" })
    MOCK.Rule({ spell = "Purge" })
    G.Update()
    SlashCmdList.PROCTHIS("debug")
    MOCK.usable = false; G.Update()
    local said = table.concat(PRINTS, " / ")
    assert(said:find("Lightning Bolt: glowing > not glowing (not castable", 1, true), said)
    SlashCmdList.PROCTHIS("debug"); MOCK.usable = true
    local text
    NS.OpenShare = function(t) text = t end
    SlashCmdList.PROCTHIS("report")
    assert(text, "report made: " .. table.concat(PRINTS, " / "))
    assert(text:find("rule 1 Lightning Bolt: true", 1, true) and text:find("rule 2 Purge", 1, true)
      and text:find("not on a shown button", 1, true), text)
    assert(text:find("errors caught: none", 1, true) and text:find("rules: PT1:", 1, true), text)
    assert(text:find("game functions: missing", 1, true), "the mock lacks some")
    """

@test("diagnostics: /pt report opens the real Share window with the report in its box (2.0.0 test build: error)")
def _():
    """
    wipe(NS.db.rules)
    MOCK.Rule({ spell = "Lightning Bolt" })
    SlashCmdList.PROCTHIS("report")
    local win = _G.ProcThisShare
    assert(win and win._shown, "the window is shown")
    assert(win.box._text:find("rule 1 Lightning Bolt", 1, true), tostring(win.box._text))
    assert(win.bug._shown, "with a report: the bug report page button")
    win:Hide(); NS.OpenShare(); assert(win._shown and win.box._text == "" and not win.bug._shown, "opened again: empty, no bug button")
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
