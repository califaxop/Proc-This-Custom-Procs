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

-- Stacks from the Cooldown Manager icon tracking `name`: a number, the game's hidden number,
-- or nil if it can't be told; plus where it came from.
local function StacksFromCooldownManager(name)
  local active, item = FromCooldownManager(name)
  if active == nil then return nil, "untracked" end
  if not active then return 0, "cdm" end
  local data
  if item and item.GetAuraDataCached then
    local ok, d = pcall(item.GetAuraDataCached, item)
    if ok then data = d end
  end
  if data == nil or not canAccess(data) then return nil, "no data" end
  local ok, apps = pcall(function() return data.applications end)
  if not ok then return nil, "no data" end
  if isSecret(apps) then return apps, "hidden" end
  if type(apps) == "number" then return math.max(1, apps), "cdm" end
  return 1, "cdm" -- active with no stack count: one
end

-- How many stacks of buff `name` you have (see AuraStacks).
function S.BuffStacks(name)
  if not S.AurasLocked() and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if ok and a == nil then return 0, "aura" end
    if ok and canAccess(a) and Readable(a.applications) then return math.max(1, a.applications), "aura" end
  end
  return StacksFromCooldownManager(name)
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

-- How many stacks: a number, the game's hidden number, or nil; plus where it came from.
function S.AuraStacks(a, name)
  if a.unit ~= "target" and a.kind ~= "debuff" then return S.BuffStacks(name) end
  local unit = (a.unit == "target") and "target" or "player"
  if not S.AurasLocked() and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    local ok, au = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, AuraFilter(a))
    if ok and au == nil then return 0, "aura" end
    if ok and canAccess(au) and Readable(au.applications) then return math.max(1, au.applications), "aura" end
  end
  return StacksFromCooldownManager(name)
end

---------------------------------------------------------------------------
-- Maelstrom Weapon stacks, worked out from Lightning Bolt's cast time: each stack cuts it by 20%
-- (instant at 5). Forever hides the stack count itself in combat, but the cast time stays readable.
-- The 0-stack cast time is learned whenever Maelstrom Weapon isn't on you.
---------------------------------------------------------------------------
local MW_IDS = { 408505, 53817, 51530, 65986 }
function S.IsMaelstrom(name)
  if name == "Maelstrom Weapon" then return true end
  for _, id in ipairs(MW_IDS) do if name and ns.SpellName(id) == name then return true end end
  return false
end

local function BoltCastTime()
  if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
  local bolt = ns.SpellName(403) or "Lightning Bolt"
  local ok, info = pcall(C_Spell.GetSpellInfo, bolt)
  if not ok or type(info) ~= "table" then return nil end
  local okT, ct = pcall(function() return info.castTime end)
  if not okT or type(ct) ~= "number" or isSecret(ct) then return nil end
  return ct
end

S.BoltCastTime = BoltCastTime

-- Your spell haste as a fraction (0.3 = 30%), or nil if the game won't say. Cast times are
-- base / (1 + haste), so taking it out makes the reading immune to haste buffs.
local function Haste()
  if not UnitSpellHaste then return nil end
  local ok, h = pcall(UnitSpellHaste, "player")
  if not ok or type(h) ~= "number" or isSecret(h) then return nil end
  return h / 100
end
S.Haste = Haste

-- Lightning Bolt's cast time with no Maelstrom stacks and no haste (ms): learned whenever Maelstrom
-- Weapon isn't on you, with the haste you had then taken out.
local boltRaw
local function RawBase()
  return boltRaw or (SpellGlowDB and SpellGlowDB.boltRaw) or 2500
end

-- called on every update
function S.LearnBoltBase()
  local ct = BoltCastTime()
  if not ct or ct <= 0 then return end
  local mw = ns.SpellName(408505) or "Maelstrom Weapon"
  if not S.HasBuff(mw) then
    boltRaw = ct * (1 + (Haste() or 0))
    if SpellGlowDB then SpellGlowDB.boltRaw = boltRaw end
  end
end

-- Maelstrom Weapon stacks (0-5) from Lightning Bolt's cast time, haste taken into account.
function S.MaelstromStacks()
  local ct = BoltCastTime()
  if not ct then return nil, "cast time hidden" end
  local mw = ns.SpellName(408505) or "Maelstrom Weapon"
  if not S.HasBuff(mw) then return 0, "no Maelstrom Weapon" end
  if ct <= 0 then return 5, "instant" end
  local h = Haste()
  local expected = RawBase() / (1 + (h or 0)) -- what it would cast at with 0 stacks right now
  local n = math.floor((1 - ct / expected) / 0.2 + 0.5)
  local note = format("%d ms of %d", ct, math.floor(expected + 0.5))
  if h and h > 0 then note = note .. format(", %d%% haste", math.floor(h * 100 + 0.5)) end
  if not h then note = note .. ", haste unknown" end
  return math.max(1, math.min(5, n)), note
end
S.BoltBase = function() return math.floor(RawBase() / (1 + (Haste() or 0)) + 0.5) end

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
