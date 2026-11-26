-- Reads each condition a rule can use. Forever hides some values from addons in combat; where
-- a value is hidden, this either uses a source that stays live (Blizzard's Cooldown Manager for
-- your buffs) or hands the hidden value to the glow untouched (it can show/hide from it).
local _, ns = ...
local S = {}
ns.State = S
local isSecret, Readable, canAccess = ns.isSecret, ns.Readable, ns.canAccess

---------------------------------------------------------------------------
-- Buffs on you
---------------------------------------------------------------------------
-- In combat the game hides your buffs from addons (C_Secrets says when).
function S.AurasLocked()
  if C_Secrets and C_Secrets.ShouldAurasBeSecret then
    local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
    if ok and Readable(secret) then return secret end
    return true
  end
  return false
end

-- Out of combat: read your buffs directly. true / false, or nil if unreadable; plus the aura (when
-- readable: for how long it lasts and when it ends).
local function AuraByName(name)
  if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if ok then
      if aura == nil then return false end
      if canAccess(aura) then return true, aura end
      return nil
    end
  end
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 60 do
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok then return nil end -- (failed: can't tell, not "absent")
      if not aura then return false end
      if not canAccess(aura) or not Readable(aura.name) then return nil end
      if aura.name == name then return true, aura end
    end
    return false
  end
  return nil
end

-- In combat: Blizzard's Cooldown Manager keeps the buffs you track there up to date. Its icons
-- are read, never changed. Returns true/false if the buff is tracked there, nil if not.
local CDM_VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local cdmNames = {} -- cooldownID -> { name = true }
local function CooldownNames(cid)
  local cached = cdmNames[cid]
  if cached then return cached end
  local names = {}
  local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
  if ok and type(info) == "table" then
    local function add(id) local n = Readable(id) and ns.SpellName(id); if n then names[n] = true end end
    add(info.spellID); add(info.overrideSpellID); add(info.overrideTooltipSpellID)
    if Readable(info.linkedSpellIDs) and type(info.linkedSpellIDs) == "table" then
      for _, id in ipairs(info.linkedSpellIDs) do add(id) end
    end
  end
  cdmNames[cid] = names
  return names
end

local function IconActive(f)
  local v = f.isActive
  if Readable(v) and type(v) == "boolean" then return v end
  local inst = f.auraInstanceID
  if not canAccess(inst) then return true end -- a (hidden) aura instance means it's there
  return inst ~= nil
end

local function FromCooldownManager(name)
  if not (C_CooldownViewer and GetCVarBool and GetCVarBool("cooldownViewerEnabled")) then return nil end
  local found, active, item = false, false, nil
  for _, viewerName in ipairs(CDM_VIEWERS) do
    local viewer = _G[viewerName]
    if viewer and viewer:IsShown() then
      local function visit(f)
        local cid = f.cooldownID
        if Readable(cid) and type(cid) == "number" and CooldownNames(cid)[name] then
          found = true
          if IconActive(f) then active = true; item = f end
        end
      end
      local pool = viewer.itemFramePool
      if pool and pool.EnumerateActive then for f in pool:EnumerateActive() do visit(f) end
      else for _, f in ipairs({ viewer:GetChildren() }) do visit(f) end end
    end
  end
  if found then return active, item end
  return nil
end

-- What Proc This! knows of your buffs between direct reads (1.16.0). In combat the game hides your
-- buffs; a buff not tracked in the Cooldown Manager is then estimated, and only where that's sound:
--   seen[name] = { present, at, expires (GetTime; 0 = no end time) }: the last direct read
--   castAt[name] = when you last cast a spell of that name (the cast doesn't prove the buff landed)
--   buffDur[name] = how long it lasts, from direct reads
--   charged[name] = it has charges or stacks when read (e.g. Lightning Shield): being hit can use it
--     up before its time runs out, so once you're hit after the cast or read, it's unknown
-- Estimates (how = "estimate"):
--   - you cast it after the last read, and its duration is known: on until that runs out, then off
--   - read on with an end time: on until then, then off (it can end sooner: a dispel)
--   - read on with no end time: on
--   - read off, and it's the rule's own spell (only your cast puts it on you): off until you cast it
-- Anything else is unknown (how = "unknown"): never treated as on or as off.
local seen, castAt, buffDur, charged = {}, {}, {}, {}
local lastHit = 0 -- anything that landed on you, or tried to (UNIT_COMBAT), for charged buffs

-- a count on the aura (stacks or charges); a hidden one counts as a count
local function Counted(v) return v ~= nil and (not Readable(v) or (type(v) == "number" and v > 0)) end

local function Remember(name, present, aura)
  local expires = 0
  if aura and Readable(aura.expirationTime) and type(aura.expirationTime) == "number" then expires = aura.expirationTime end
  if aura and Readable(aura.duration) and type(aura.duration) == "number" and aura.duration > 0 then buffDur[name] = aura.duration end
  if aura and (Counted(aura.applications) or Counted(aura.charges)) then charged[name] = true end
  seen[name] = { present = present, at = GetTime(), expires = present and expires or nil }
end

-- a charged buff, and you've been hit since `t`: it may be used up
local USED_UP = "it has charges, and you've been hit since"
local function MaybeUsedUp(name, t) return charged[name] and lastHit > t end

-- Is buff `name` on you? Returns true/false or nil (can't tell), how it knows ("aura", "cdm",
-- "estimate", "unknown"), and a detail for the settings window. selfOnly: it's the rule's own spell.
function S.HasBuff(name, selfOnly)
  if not S.AurasLocked() then
    local v, aura = AuraByName(name)
    if v ~= nil then Remember(name, v, aura); return v, "aura" end
  end
  local v = FromCooldownManager(name)
  if v ~= nil then return v, "cdm" end
  local now, last, c = GetTime(), seen[name], castAt[name]
  if c and (not last or c >= last.at) then
    local d = buffDur[name]
    if not d then return nil, "unknown", "cast, but how long it lasts isn't known yet" end
    if now - c <= d then
      if MaybeUsedUp(name, c) then return nil, "unknown", USED_UP end
      return true, "estimate", format("from your cast %d s ago (lasts %d s)", now - c, d)
    end
    return false, "estimate", format("your cast %d s ago has run out (lasts %d s)", now - c, d)
  end
  if last then
    if last.present then
      if (last.expires == 0 or now < last.expires) and MaybeUsedUp(name, last.at) then return nil, "unknown", USED_UP end
      if (last.expires or 0) == 0 then return true, "estimate", "seen on you, with no end time" end
      if now < last.expires then return true, "estimate", format("seen on you, ends in %d s", last.expires - now) end
      return false, "estimate", "seen on you, and its time has run out"
    end
    if selfOnly then return false, "estimate", "not on you when last seen, and you haven't cast it since" end
  end
  return nil, "unknown", "not seen since combat began"
end

-- For the settings window: can this buff/debuff be followed in combat?
function S.Tracked(name) return FromCooldownManager(name) ~= nil end

---------------------------------------------------------------------------
-- Debuffs and buffs on your target, debuffs on you
-- Out of combat the game answers exactly. In combat Forever refuses aura queries from addons
-- ("Auras cannot be accessed when secret"), so none are made then. Your own debuffs on your
-- target are followed from your casts instead (your casts stay readable): an estimate (a cast can
-- miss or be resisted); anything else is "can't tell" in combat, and a rule that needs it doesn't glow.
---------------------------------------------------------------------------
-- present = true/false, or nil if the game won't say; how = "exact" or "hidden"
local function Query(unit, name, filter)
  if S.AurasLocked() then return nil end -- in combat: the game refuses (don't even ask)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
  if not UnitExists(unit) then return false, "exact" end
  local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
  if not ok then return nil end
  if isSecret(aura) then return true, "hidden" end   -- hidden details, but it's there
  if aura == nil then return false, "exact" end
  return true, "exact", aura
end

-- your debuff casts, per target (its GUID, when the game shows it; else "current", forgotten when
-- you change targets): dots[key][debuff] = { t = when, left = charges left }
local dots, learnedDur = {}, {}
local DEFAULT_DUR = 12
local function TargetKey()
  if not UnitExists("target") then return nil end
  local ok, guid = pcall(UnitGUID, "target")
  if ok and Readable(guid) and type(guid) == "string" then return guid end
  return "current"
end

-- Is debuff `name` on your target? Returns true/false (nil = can't tell), how it was decided, and
-- a detail.
function S.TargetDebuff(name, mineOnly, dur)
  local filter = mineOnly and "HARMFUL|PLAYER" or "HARMFUL"
  local present, how, aura = Query("target", name, filter)
  if aura and Readable(aura.duration) and aura.duration > 0 then learnedDur[name] = aura.duration end
  if present ~= nil then return present, how end
  -- combat: Blizzard's Cooldown Manager follows debuffs you track there (Stormstrike...), exactly
  local cdm = FromCooldownManager(name)
  if cdm ~= nil then return cdm, "cdm" end
  -- otherwise: your own debuff, estimated from your casts on this target
  if mineOnly then
    local key = TargetKey()
    if not key then return false, "exact" end -- (no target: nothing on it)
    local lasts = (dur and dur > 0) and dur or learnedDur[name]
    local assumed = not lasts
    lasts = lasts or DEFAULT_DUR
    local c = dots[key] and dots[key][name]
    if not c then
      if key == "current" then return nil, "unknown", "your casts can't be told apart per target here" end
      return false, "estimate", "you haven't cast it on this target"
    end
    local ago = GetTime() - c.t
    if c.left and c.left <= 0 then return false, "estimate", "its charges are used up" end
    if ago <= lasts then
      return true, "estimate", format("from your cast %d s ago (lasts %d s%s)", ago, lasts, assumed and ", assumed" or "")
    end
    return false, "estimate", format("your cast %d s ago has run out (lasts %d s%s)", ago, lasts, assumed and ", assumed" or "")
  end
  return nil, "unknown"
end

-- Is buff `name` on your target? (anyone's buff: no cast backup)
function S.TargetBuff(name)
  local present, how = Query("target", name, "HELPFUL")
  if present ~= nil then return present, how end
  local cdm = FromCooldownManager(name)
  if cdm ~= nil then return cdm, "cdm" end
  return nil, "unknown"
end

-- Is debuff `name` on you?
function S.MyDebuff(name)
  local present, how = Query("player", name, "HARMFUL")
  if present ~= nil then return present, how end
  local cdm = FromCooldownManager(name)
  if cdm ~= nil then return cdm, "cdm" end
  return nil, "unknown"
end

-- your casts: a debuff of yours lands on your current target (an estimate: the cast can miss)
function S.NoteDebuffCast(name, charges)
  local key = TargetKey()
  if not key then return end
  dots[key] = dots[key] or {}
  dots[key][name] = { t = GetTime(), left = (charges and charges > 0) and charges or nil }
end
-- a spell that uses the debuff up was cast: one charge gone (on your current target)
function S.UseDebuffCharge(name)
  local key = TargetKey()
  local c = key and dots[key] and dots[key][name]
  if c and c.left then c.left = c.left - 1 end
end
-- (records per GUID stay; the "current" ones belong to the old target)
function S.OnTargetChanged() dots.current = nil; S.comboStale = true end
-- out of combat the game answers directly again: old estimates can go
function S.OnCombatEnd() wipe(dots) end

---------------------------------------------------------------------------
-- One aura condition of a rule (see ns.NEW_AURA): on you or your target, a buff or a debuff.
---------------------------------------------------------------------------
-- Is it there? true/false, or nil when it can't be told; how it was decided ("aura", "exact",
-- "hidden", "cdm", "estimate", "unknown"), and a detail. selfOnly: the buff is the rule's own spell.
function S.AuraPresent(a, name, selfOnly)
  if a.unit == "target" then
    if a.kind == "debuff" then return S.TargetDebuff(name, a.mine, a.dur) end
    return S.TargetBuff(name)
  end
  if a.kind == "debuff" then return S.MyDebuff(name) end
  return S.HasBuff(name, selfOnly)
end

---------------------------------------------------------------------------
-- A spell's current cast time (ms), as the game shows it on the tooltip: readable in combat,
-- and 0 while something makes it instant (Maelstrom Weapon at 5, Nature's Swiftness, Presence
-- of Mind, Shadow Trance...). nil when the game won't say.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Health: "below / at or above N%" on you or your target.
-- Out of combat health reads as numbers. In combat the game hides it; then the game itself
-- applies a step curve to the hidden health (UnitHealthPercent with a curve) and the result
-- becomes a gate's alpha: 1 when the condition holds, 0 when not. Proc This! never sees it.
---------------------------------------------------------------------------
local curves = {}
-- mode: "below" (< N), "above" (> N), and their exact opposites "atleast" (>= N), "atmost" (<= N)
local CURVE = { below = { 1, 0, 0 }, atleast = { 0, 1, 0 }, above = { 0, 1, 0.00001 }, atmost = { 1, 0, 0.00001 } }
S.OPPOSITE = { below = "atleast", atleast = "below", above = "atmost", atmost = "above" }
function S.StepCurve(mode, pct)
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
  local spec = CURVE[mode]
  if not spec then return nil end
  local key = mode .. pct
  if curves[key] ~= nil then return curves[key] or nil end
  local ok, curve = pcall(function()
    local c = C_CurveUtil.CreateCurve()
    local lo, hi, at = spec[1], spec[2], pct / 100 + spec[3] -- lo: under the line, hi: from it up
    if Enum.LuaCurveType and Enum.LuaCurveType.Step and c.SetType then
      c:SetType(Enum.LuaCurveType.Step)
      c:AddPoint(0, lo); c:AddPoint(at, hi)
    else -- a steep ramp, for clients without step curves
      c:AddPoint(0, lo); c:AddPoint(math.max(0, at - 0.001), lo); c:AddPoint(at, hi)
    end
    return c
  end)
  curves[key] = ok and curve or false
  return ok and curve or nil
end
-- (kept for callers of the earlier name)

-- does a readable percent meet the mode?
function S.Meets(mode, v, pct)
  if mode == "below" then return v < pct elseif mode == "above" then return v > pct
  elseif mode == "atleast" then return v >= pct else return v <= pct end
end

-- Number rows compare with an operator: >, >=, <, <=, =
S.OPS = { gt = ">", ge = ">=", lt = "<", le = "<=", eq = "=" }
S.OP_ORDER = { "gt", "ge", "lt", "le", "eq" }
local OP_MODE = { lt = "below", le = "atmost", gt = "above", ge = "atleast" }
-- a row's operator (rows from before operators: their Below / Above / At least / At most)
local OLD_OP = { below = "lt", above = "gt", atleast = "ge", atmost = "le" }
function S.Op(a)
  if not a then return "lt" end
  if S.OPS[a.op] then return a.op end
  if a.kind == "combo" then return OLD_OP[a.cpMode] or "ge" end
  return OLD_OP[a.hpMode] or "lt"
end
function S.OpMeets(op, v, n)
  if op == "eq" then return math.floor(v + 0.5) == n end
  return S.Meets(OP_MODE[op] or "below", v, n)
end
-- For a hidden value, the steps the game checks it against: { { mode, pct }, ... }, all must hold.
-- scale: % per unit. "=" is the band that rounds to n.
function S.OpSteps(op, n, scale)
  if op == "eq" then
    local steps = {}
    if n - 0.5 > 0 then steps[#steps + 1] = { "atleast", (n - 0.5) * scale } end
    steps[#steps + 1] = { "below", (n + 0.5) * scale }
    return steps
  end
  return { { OP_MODE[op] or "below", n * scale } }
end

-- a unit's mana in percent; nil, "hidden" when the game hides it (your own mana always is, on
-- Forever); nil, "none" for no such unit; nil, "nomana" for a unit without mana
function S.ManaPct(unit)
  if not UnitExists(unit) then return nil, "none" end
  local mana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
  local okM, m = pcall(UnitPowerMax, unit, mana)
  if okM and Readable(m) and type(m) == "number" and m <= 0 then return nil, "nomana" end
  local okP, p = pcall(UnitPower, unit, mana)
  if okP and okM and Readable(p) and Readable(m) and type(p) == "number" and type(m) == "number" and m > 0 then
    return p / m * 100
  end
  return nil, "hidden"
end

---------------------------------------------------------------------------
-- Your combo points, rage and energy. Forever may hide them from addons like your mana; then, as
-- for health and mana, the game itself checks them against the row's line (UnitPowerPercent with
-- a step curve) and Proc This! never sees the number.
-- Combo points sit on your target in Forever: after you change targets, the game's power count can
-- still be the old target's until points are gained or move over (COMBO_TARGET_CHANGED), so until
-- then a hidden count isn't trusted.
---------------------------------------------------------------------------
local PT = Enum and Enum.PowerType or {}
S.POWER = {
  combo = { type = PT.ComboPoints or 4, max = 5, label = "combo points" },
  rage = { type = PT.Rage or 1, max = 100, label = "rage" },
  energy = { type = PT.Energy or 3, max = 100, label = "energy" },
}
S.comboStale = false
-- (a power update or the points moving over: the count is your target's again)
function S.OnPower(token)
  if token == nil or token == "COMBO_POINTS" then S.comboStale = false end
end
function S.OnComboTarget() S.comboStale = false end

-- the most you can have (readable, else the usual)
function S.PowerMax(kind)
  local p = S.POWER[kind]
  if not p then return nil end
  local ok, m = pcall(UnitPowerMax, "player", p.type)
  if ok and Readable(m) and type(m) == "number" and m > 0 then return m end
  return p.max
end

-- what you have now; nil, "hidden" when the game hides it; nil, "stale" for combo points right after
-- a target change (hidden ones only)
function S.PowerAmount(kind)
  local p = S.POWER[kind]
  if not p then return nil, "unknown" end
  if kind == "combo" then
    if not UnitExists("target") then return 0 end
    if GetComboPoints then
      local ok, c = pcall(GetComboPoints, "player", "target")
      if ok and Readable(c) and type(c) == "number" then return c end
    end
    if S.comboStale then return nil, "stale" end
  end
  local ok, v = pcall(UnitPower, "player", p.type)
  if ok and Readable(v) and type(v) == "number" then return v end
  return nil, "hidden"
end

-- /pt power: what the game lets Proc This! see of each, right now
function S.PowerReport()
  local lines = {}
  local function sec(t)
    local out = {}
    if C_Secrets and C_Secrets.GetPowerTypeSecrecy then
      local ok, lvl = pcall(C_Secrets.GetPowerTypeSecrecy, t)
      local names = { [0] = "never hidden", [1] = "always hidden", [2] = "hidden at times" }
      out[#out + 1] = ok and (names[lvl] or tostring(lvl)) or "?"
    end
    if C_Secrets and C_Secrets.ShouldUnitPowerBeSecret then
      local ok, v = pcall(C_Secrets.ShouldUnitPowerBeSecret, "player", t)
      out[#out + 1] = ok and (v and "hidden now" or "readable now") or "?"
    end
    return table.concat(out, ", ")
  end
  local mana = PT.Mana or 0
  for _, k in ipairs({ "combo", "rage", "energy", "mana" }) do
    local t = (k == "mana") and mana or S.POWER[k].type
    local label = (k == "mana") and "mana" or S.POWER[k].label
    local okV, v = pcall(UnitPower, "player", t)
    local val = (okV and Readable(v)) and tostring(v) or (okV and "hidden" or "error")
    local okM, m = pcall(UnitPowerMax, "player", t)
    local max = (okM and Readable(m)) and tostring(m) or (okM and "hidden" or "error")
    -- the game-side check: does a step curve come back, and does a frame take it?
    local check = "no curve support"
    local curve = S.StepCurve("atleast", 50)
    if curve and UnitPowerPercent then
      local okP, r = pcall(UnitPowerPercent, "player", t, false, curve)
      if not okP then check = "the game refused: " .. tostring(r)
      elseif r == nil then check = "no answer"
      else
        S.probe = S.probe or CreateFrame("Frame")
        local okA = pcall(S.probe.SetAlpha, S.probe, r)
        check = (okA and "works" or "answer can't drive a glow") .. ((isSecret and isSecret(r)) and " (hidden answer)" or "")
      end
    end
    local secrecy = sec(t)
    lines[#lines + 1] = format("%s: now %s / max %s; %sgame-side check: %s", label, val, max, secrecy ~= "" and (secrecy .. "; ") or "", check)
  end
  if GetComboPoints then
    local ok, c = pcall(GetComboPoints, "player", "target")
    lines[#lines + 1] = "combo points on your target: " .. (not UnitExists("target") and "no target" or
      (ok and (Readable(c) and tostring(c) or "hidden") or "error"))
      .. (S.comboStale and " (just changed target: not trusted until points change)" or "")
  end
  lines[#lines + 1] = "in combat: " .. ((InCombatLockdown and InCombatLockdown()) and "yes" or "no")
  return lines
end

-- a unit's health in percent, or nil when the game hides it (or there's no such unit)
function S.HealthPct(unit)
  if not UnitExists(unit) then return nil, "none" end
  local okH, h = pcall(UnitHealth, unit)
  local okM, m = pcall(UnitHealthMax, unit)
  if okH and okM and Readable(h) and Readable(m) and type(h) == "number" and type(m) == "number" and m > 0 then
    return h / m * 100
  end
  return nil, "hidden"
end

function S.IsDead(unit)
  if not UnitIsDeadOrGhost then return false end
  local ok, d = pcall(UnitIsDeadOrGhost, unit)
  return ok and Readable(d) and d and true or false
end

function S.CastTime(name)
  if not (name and C_Spell and C_Spell.GetSpellInfo) then return nil end
  local ok, info = pcall(C_Spell.GetSpellInfo, name)
  if not ok or type(info) ~= "table" then return nil end
  local okT, ct = pcall(function() return info.castTime end)
  if not okT or type(ct) ~= "number" or isSecret(ct) then return nil end
  return ct
end

---------------------------------------------------------------------------
-- Being attacked in melee: any hit, dodge, parry, block or miss on you recently.
-- (If the game hides what kind of event it was, it still counts.)
---------------------------------------------------------------------------
local lastMelee = 0
local MELEE_ACTIONS = { WOUND = true, DODGE = true, PARRY = true, BLOCK = true, MISS = true }
function S.OnUnitCombat(action, descriptor, amount, school)
  if not (Readable(action) and (action == "HEAL" or action == "ENERGIZE")) then lastHit = GetTime() end
  if Readable(action) then
    if not MELEE_ACTIONS[action] then return end   -- e.g. a heal
    if action == "WOUND" and Readable(school) and school ~= 1 then return end -- spell damage, not melee
  end
  lastMelee = GetTime()
end
function S.BeingMeleed()
  return GetTime() - lastMelee <= (ns.db.meleeWindow or 3)
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
-- Each answers with a result (see Result.lua): status, why, and for GATED the one gate (a hidden
-- boolean the glow is switched by, never read here).
local R = ns.Result

-- Castable (known, enough mana); for an item, usable (you have it and can use it now).
function S.Usable(name, item)
  local fn
  if item then fn = (C_Item and C_Item.IsUsableItem) or IsUsableItem
  else fn = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell end
  if not fn then return R.UNKNOWN, "this client can't tell if it's usable" end
  local ok, usable = pcall(fn, item or name)
  if not ok then return R.ERROR, "the game couldn't check if it's usable" end
  if isSecret(usable) then return R.GATED, nil, { kind = "bool", v = usable } end
  if usable then return R.TRUE end
  return R.FALSE, item and "not usable (none in your bags, or can't use it now)" or "not castable (mana / not known)"
end

-- Off cooldown. The global cooldown doesn't count. For an item, its own cooldown (a cooldown of
-- 1.5 s or less is the global one). When the game hides a spell's cooldown, the glow is switched
-- by the hidden "on cooldown" flag (open when it's off); the global cooldown then counts too.
function S.Ready(name, item)
  if item then
    local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not fn then return R.UNKNOWN, "this client can't read item cooldowns" end
    local ok, start, duration = pcall(fn, item)
    if not ok then return R.ERROR, "the game couldn't read its cooldown" end
    if not (Readable(start) and Readable(duration)) then return R.UNKNOWN, "its cooldown is hidden" end
    if start and start > 0 and duration and duration > 1.5 then return R.FALSE, "on cooldown" end
    return R.TRUE
  end
  if not (C_Spell and C_Spell.GetSpellCooldown) then return R.UNKNOWN, "this client can't read cooldowns" end
  local ok, info = pcall(C_Spell.GetSpellCooldown, name)
  if not ok then return R.ERROR, "the game couldn't read its cooldown" end
  if type(info) ~= "table" then return R.UNKNOWN, "the game doesn't know this spell's cooldown" end
  local active, gcd = info.isActive, info.isOnGCD
  if isSecret(active) then return R.GATED, nil, { kind = "bool", v = active, invert = true } end
  if active == nil then return R.UNKNOWN, "its cooldown isn't readable" end
  if not active then return R.TRUE end
  if Readable(gcd) and gcd then return R.TRUE end -- (just the global cooldown)
  return R.FALSE, "on cooldown"
end

-- You have control of your character (not stunned, feared, charmed...).
function S.HasControl()
  if not HasFullControl then return R.UNKNOWN, "this client can't tell" end
  local ok, v = pcall(HasFullControl)
  if not ok then return R.ERROR, "the game couldn't tell" end
  if isSecret(v) then return R.GATED, nil, { kind = "bool", v = v } end
  if v then return R.TRUE end
  return R.FALSE, "no control (stunned...)"
end

function S.InCombat()
  local ok, v = pcall(UnitAffectingCombat, "player")
  if not ok then return R.ERROR, "the game couldn't tell" end
  if isSecret(v) then return R.GATED, nil, { kind = "bool", v = v } end
  if v then return R.TRUE end
  return R.FALSE, "not in combat"
end

-- The game's proc flag for a spell (its glow on Blizzard's bars), followed by name.
local flagged = {}
function S.OnOverlay(show, spellID)
  if spellID == nil then if not show then wipe(flagged) end return end
  if not Readable(spellID) then return end
  local n = ns.SpellName(spellID)
  if n then flagged[n] = show or nil end
end
function S.Flagged(name) return flagged[name] and true or false end

-- You cast a spell: noted for estimates (a buff of that name may be on you now, a debuff of yours
-- that some rule watches may be on your target now). A cast doesn't prove the aura landed.
function S.OnCast(spellID)
  local n = Readable(spellID) and ns.SpellName(spellID)
  if not n then return end
  castAt[n] = GetTime()
  if not ns.db then return end
  for _, r in ipairs(ns.db.rules) do
    for _, a in ipairs(r.auras or {}) do
      if a.unit == "target" and a.kind == "debuff" then
        local dn = ns.AuraName(r, a)
        local charges = tonumber(a.charges) or 0
        -- a spell that uses it up (e.g. Lightning Bolt using up Stormstrike's bonus)
        if charges > 0 and dn ~= n then
          for _, used in ipairs(ns.AuraUsedBy(r, a)) do
            if used == n then S.UseDebuffCharge(dn) end
          end
        end
        -- you applied it
        if dn == n and UnitExists("target") then S.NoteDebuffCast(n, charges) end
      end
    end
  end
end
