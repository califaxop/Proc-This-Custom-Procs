-- Spell Glow: shared namespace, settings and spell helpers.
local ADDON, ns = ...
ns.name = ADDON

ns.isSecret = issecretvalue or function() return false end
ns.canAccess = canaccessvalue or function(v) return not ns.isSecret(v) end
function ns.Readable(v) return v ~= nil and not ns.isSecret(v) end
function ns.Print(...) print("|cffffd200Spell Glow:|r", ...) end

-- A rule: glow `spell` (every rank, matched by name) while ALL of its checked conditions hold.
--   buff        "ignore" | "missing" | "present" -- a buff on you (buffName, or the spell itself)
--   melee       you're being attacked in melee (hit / dodged / parried / blocked recently)
--   usable      castable: known and enough mana
--   ready       off cooldown (the global cooldown doesn't count)
--   control     you have control (not stunned, feared, charmed...)
--   combat      only while you're in combat
--   proc        the game flags the spell as a proc
--   tdebuff     "ignore" | "missing" | "present" -- a debuff on your target (tdebuffName, or the spell)
--               tdebuffMine: only yours; tdebuffDur: how long yours lasts after you cast it (0 = auto)
--               tdebuffCharges / tdebuffUsedBy: in combat, it's used up after that many casts of
--               those spells (comma-separated; blank = the rule's spell). 0 = not used up by casts.
--   pdebuff     "ignore" | "missing" | "present" -- a debuff on you (pdebuffName)
--   tbuff       "ignore" | "missing" | "present" -- a buff on your target (tbuffName)
--   buffs       list of { mode = "present" | "missing", name = "" (blank = the spell), stacks = 0 }
--               all must hold; stacks = at least this many (0/1 = any)
ns.NEW_RULE = { enabled = true, spell = "", buffs = {},
  tdebuff = "ignore", tdebuffName = "", tdebuffMine = true, tdebuffDur = 0,
  tdebuffCharges = 0, tdebuffUsedBy = "",
  pdebuff = "ignore", pdebuffName = "",
  tbuff = "ignore", tbuffName = "",
  melee = false, usable = true, ready = true, control = true, combat = false, proc = false }

ns.DEFAULTS = {
  meleeWindow = 3,   -- seconds a melee hit on you counts as "being attacked in melee"
  glowScale = 1.4,   -- Blizzard's alert size around a button
  glowStyle = "shine", -- "glow" (just the glow), "shine" (brief flare at the start), "burst" (Blizzard's zoom-in start)
  glowAlpha = 1,       -- glow intensity
  rules = {
    -- the example asked for: Lightning Shield when it's not on you, you're being hit in melee,
    -- and you can cast it (not stunned, enough mana)
    { enabled = true, spell = "Lightning Shield", buffs = { { mode = "missing", name = "", stacks = 0 } },
      melee = true, usable = true, ready = true, control = true, combat = false, proc = false },
  },
}

local function Copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = Copy(x) end
  return t
end
ns.Copy = Copy

function ns.LoadDB()
  SpellGlowDB = SpellGlowDB or {}
  for k, v in pairs(ns.DEFAULTS) do
    if SpellGlowDB[k] == nil then SpellGlowDB[k] = Copy(v) end
  end
  -- rules saved by an older version get any new condition fields
  for _, r in ipairs(SpellGlowDB.rules) do
    -- one "Buff on me" (older versions) -> the list of buff conditions
    if r.buffs == nil then
      r.buffs = {}
      if r.buff and r.buff ~= "ignore" then
        r.buffs[1] = { mode = r.buff, name = r.buffName or "", stacks = 0 }
      end
    end
    r.buff, r.buffName = nil, nil
    for k, v in pairs(ns.NEW_RULE) do if r[k] == nil then r[k] = v end end
  end
  ns.db = SpellGlowDB
end

---------------------------------------------------------------------------
-- Spells: rules name a spell; every rank of it counts (matched by name, as the game names ranks alike)
---------------------------------------------------------------------------
function ns.SpellName(id)
  if not id or ns.isSecret(id) then return nil end
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id))
end

function ns.SpellIcon(spell)
  local ok, tex = pcall(function()
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
    return GetSpellTexture and GetSpellTexture(spell)
  end)
  return ok and tex or nil
end

-- A rule's spell as typed: a name, or a spell ID -> its name.
function ns.RuleSpellName(rule)
  local s = rule.spell
  if not s or s == "" then return nil end
  local id = tonumber(s)
  if id then return ns.SpellName(id) end
  return s
end

-- a name/ID field of a rule, falling back to the rule's spell when blank
local function NameOrSpell(rule, field)
  local b = rule[field]
  if b and b ~= "" then
    local id = tonumber(b)
    return id and ns.SpellName(id) or b
  end
  return ns.RuleSpellName(rule)
end
-- a buff condition's buff name (blank = the rule's spell)
function ns.BuffCondName(rule, cond)
  local b = cond.name
  if b and b ~= "" then
    local id = tonumber(b)
    return id and ns.SpellName(id) or b
  end
  return ns.RuleSpellName(rule)
end
function ns.RuleTargetDebuffName(rule) return NameOrSpell(rule, "tdebuffName") end
-- named-only fields (no "the spell itself" fallback)
local function Named(rule, field)
  local b = rule[field]
  if not b or b == "" then return nil end
  local id = tonumber(b)
  return id and ns.SpellName(id) or b
end
function ns.RuleMyDebuffName(rule) return Named(rule, "pdebuffName") end

-- spells that use up a target debuff (comma-separated names/IDs; blank = the rule's own spell)
function ns.RuleUsedBy(rule)
  local list = {}
  local text = rule.tdebuffUsedBy or ""
  for part in text:gmatch("[^,]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then
      local id = tonumber(part)
      list[#list + 1] = id and ns.SpellName(id) or part
    end
  end
  if #list == 0 then list[1] = ns.RuleSpellName(rule) end
  return list
end
function ns.RuleTargetBuffName(rule) return Named(rule, "tbuffName") end
