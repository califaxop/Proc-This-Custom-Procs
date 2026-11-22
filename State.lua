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

-- Out of combat: read your buffs directly. true / false, or nil if unreadable.
local function AuraByName(name)
  if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if ok then
      if aura == nil then return false end
      if canAccess(aura) then return true end
      return nil
    end
  end
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 60 do
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or not aura then return false end
      if not canAccess(aura) or not Readable(aura.name) then return nil end
      if aura.name == name then return true end
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

-- last known state per buff name (from out of combat, or from casting it)
local known = {}

-- Is buff `name` on you? Returns true/false, plus how it knows: "aura", "cdm" or "guess".
function S.HasBuff(name)
  if not S.AurasLocked() then
    local v = AuraByName(name)
    if v ~= nil then known[name] = v; return v, "aura" end
  end
  local v = FromCooldownManager(name)
  if v ~= nil then known[name] = v; return v, "cdm" end
  -- not tracked in the Cooldown Manager: the last thing we knew (it can't see it run out in combat)
  return known[name] or false, "guess"
end

-- For the settings window: can this buff/debuff be followed in combat?
function S.Tracked(name) return FromCooldownManager(name) ~= nil end
function S.BuffTracked(name)
  return FromCooldownManager(name) ~= nil
end

---------------------------------------------------------------------------
-- Debuffs and buffs on your target, debuffs on you
-- Out of combat the game answers exactly. In combat Forever refuses aura queries from addons
-- ("Auras cannot be accessed when secret"), so none are made then. Your own debuffs on your
-- target are followed from your casts instead (your casts stay readable); anything else is
-- "can't tell" in combat, and a rule that needs it doesn't glow.
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

local castAt, learnedDur = {}, {}   -- debuff name -> when you last cast it / how long it lasts
local DEFAULT_DUR = 12

-- Is debuff `name` on your target? Returns true/false (nil = can't tell) and how it was decided.
function S.TargetDebuff(name, mineOnly, dur)
  local filter = mineOnly and "HARMFUL|PLAYER" or "HARMFUL"
  local present, how, aura = Query("target", name, filter)
  if aura and Readable(aura.duration) and aura.duration > 0 then learnedDur[name] = aura.duration end
  if present ~= nil then return present, how end
  -- combat: Blizzard's Cooldown Manager follows debuffs you track there (Stormstrike...), exactly
  local cdm = FromCooldownManager(name)
  if cdm ~= nil then return cdm, "cdm" end
  -- otherwise: your own debuff is on it while your last cast of it lasts
  if mineOnly then
    local lasts = (dur and dur > 0) and dur or learnedDur[name] or DEFAULT_DUR
    local c = castAt[name]
    if c and GetTime() - c.t <= lasts and (not c.left or c.left > 0) then return true, "your cast" end
    return false, "your cast"
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

-- your casts: a debuff of yours lands on your current target (cleared when you switch targets)
function S.NoteDebuffCast(name, charges)
  castAt[name] = { t = GetTime(), left = (charges and charges > 0) and charges or nil }
end
-- a spell that uses the debuff up was cast: one charge gone
function S.UseDebuffCharge(name)
  local c = castAt[name]
  if c and c.left then c.left = c.left - 1 end
end
function S.OnTargetChanged() wipe(castAt) end

---------------------------------------------------------------------------
-- One aura condition of a rule (see ns.NEW_AURA): on you or your target, a buff or a debuff.
---------------------------------------------------------------------------
local function AuraFilter(a)
  local f = (a.kind == "debuff") and "HARMFUL" or "HELPFUL"
  if a.unit == "target" and a.mine then f = f .. "|PLAYER" end
  return f
end

-- Is it there? true/false, or nil when the game won't say (combat, not in the Cooldown Manager);
-- plus how it was decided: "aura", "exact", "hidden", "cdm", "your cast", "guess", "unknown".
function S.AuraPresent(a, name)
  if a.unit == "target" then
    if a.kind == "debuff" then return S.TargetDebuff(name, a.mine, a.dur) end
    return S.TargetBuff(name)
  end
  if a.kind == "debuff" then return S.MyDebuff(name) end
  return S.HasBuff(name)
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
function S.HealthCurve(below, pct) return S.StepCurve(below and "below" or "atleast", pct) end

-- does a readable percent meet the mode?
function S.Meets(mode, v, pct)
  if mode == "below" then return v < pct elseif mode == "above" then return v > pct
  elseif mode == "atleast" then return v >= pct else return v <= pct end
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
-- Castable (known, enough mana). Returns true/false, or the game's hidden value untouched.
function S.Usable(name)
  if not (C_Spell and C_Spell.IsSpellUsable) then
    if IsUsableSpell then return (IsUsableSpell(name)) and true or false end
    return true
  end
  local ok, usable = pcall(C_Spell.IsSpellUsable, name)
  if not ok then return false end
  if isSecret(usable) then return usable end
  return usable and true or false
end

-- Off cooldown. The global cooldown doesn't count (both flags stay readable).
function S.Ready(name)
  if not (C_Spell and C_Spell.GetSpellCooldown) then return true end
  local ok, info = pcall(C_Spell.GetSpellCooldown, name)
  if not (ok and type(info) == "table") then return true end
  local active, gcd = info.isActive, info.isOnGCD
  if not Readable(active) then return true end
  if not active then return true end
  return Readable(gcd) and gcd or false
end

-- You have control of your character (not stunned, feared, charmed...).
function S.HasControl()
  if not HasFullControl then return true end
  local v = HasFullControl()
  if isSecret(v) then return true end
  return v and true or false
end

function S.InCombat() return UnitAffectingCombat("player") and true or false end

-- The game's proc flag for a spell (its glow on Blizzard's bars), followed by name.
local flagged = {}
function S.OnOverlay(show, spellID)
  if spellID == nil then if not show then wipe(flagged) end return end
  if not Readable(spellID) then return end
  local n = ns.SpellName(spellID)
  if n then flagged[n] = show or nil end
end
function S.Flagged(name) return flagged[name] and true or false end

-- You cast it: the buff is on you now (until we learn otherwise), and if it's a debuff of yours
-- that some rule watches on your target, it's on your target now.
function S.OnCast(spellID)
  local n = Readable(spellID) and ns.SpellName(spellID)
  if not n then return end
  known[n] = true
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
