-- The compatibility layer (1.18.0): every game function Proc This! reads conditions and buttons
-- with, in one place. Each has the forms it may take on a client (the newer C_ namespaces first,
-- then the older globals); the first one this client has is used, and always called safely.
-- API_COMPATIBILITY.md lists each with what's known about it on Forever; /pt api shows which form
-- this client has.
--
--   API.Call(name, ...) -> true, results...   it answered (results may be hidden: check them)
--                       -> false, message     it failed
--                       -> nil                this client doesn't have it
--   API.Has(name)       -> the function, or nil
local _, ns = ...
local API = {}
ns.API = API

-- { name, its forms... }, in the order /pt api lists them
local FORMS = {
  -- auras
  { "AurasSecret", "C_Secrets.ShouldAurasBeSecret" },
  { "AuraBySpellName", "C_UnitAuras.GetAuraDataBySpellName" },
  { "AuraByIndex", "C_UnitAuras.GetAuraDataByIndex" },
  { "CooldownViewerInfo", "C_CooldownViewer.GetCooldownViewerCooldownInfo" },
  -- spells and items
  { "SpellInfo", "C_Spell.GetSpellInfo" },
  { "SpellDescription", "C_Spell.GetSpellDescription", "GetSpellDescription" },
  { "SpellCooldown", "C_Spell.GetSpellCooldown" },
  { "SpellUsable", "C_Spell.IsSpellUsable", "IsUsableSpell" },
  { "ItemUsable", "C_Item.IsUsableItem", "IsUsableItem" },
  { "ItemCooldown", "C_Container.GetItemCooldown", "GetItemCooldown" },
  -- units
  { "UnitGUID", "UnitGUID" },
  { "UnitName", "UnitName" },
  { "Dead", "UnitIsDeadOrGhost" },
  { "FullControl", "HasFullControl" },
  { "InCombat", "UnitAffectingCombat" },
  { "Health", "UnitHealth" },
  { "HealthMax", "UnitHealthMax" },
  { "HealthPercent", "UnitHealthPercent" },
  { "Power", "UnitPower" },
  { "PowerMax", "UnitPowerMax" },
  { "PowerPercent", "UnitPowerPercent" },
  { "ComboPoints", "GetComboPoints" },
  { "PowerSecrecy", "C_Secrets.GetPowerTypeSecrecy" },
  { "PowerSecret", "C_Secrets.ShouldUnitPowerBeSecret" },
  -- the action bars
  { "ActionInfo", "GetActionInfo" },
  { "MacroSpell", "GetMacroSpell" },
  { "MacroItem", "GetMacroItem" },
}

-- name -> { { "C_Spell", "IsSpellUsable" }, ... } and its forms' names, once
local split, names = {}, {}
for _, e in ipairs(FORMS) do
  split[e[1]], names[e[1]] = {}, {}
  for i = 2, #e do
    local parts = {}
    for p in e[i]:gmatch("[^.]+") do parts[#parts + 1] = p end
    table.insert(split[e[1]], parts); table.insert(names[e[1]], e[i])
  end
end

-- the first form this client has, and its name (looked up each time: cheap, and nothing is kept
-- that another addon or a later load could change)
local function Find(name)
  for i, parts in ipairs(split[name] or {}) do
    local t = _G
    for _, p in ipairs(parts) do
      if type(t) ~= "table" then t = nil; break end
      t = t[p]
    end
    if type(t) == "function" then return t, names[name][i] end
  end
end

function API.Has(name) return (Find(name)) end

function API.Call(name, ...)
  local fn = Find(name)
  if not fn then return nil end
  return pcall(fn, ...)
end

-- /pt api: each function, and the form this client has
function API.Report()
  local lines = {}
  for _, e in ipairs(FORMS) do
    local _, form = Find(e[1])
    lines[#lines + 1] = format("%s: %s", e[1], form or "|cffff6060not on this client|r")
  end
  return lines
end
