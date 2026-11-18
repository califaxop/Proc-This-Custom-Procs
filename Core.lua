-- Spell Glow: shared namespace, settings and spell helpers.
local ADDON, ns = ...
ns.name = ADDON

ns.isSecret = issecretvalue or function() return false end
ns.canAccess = canaccessvalue or function(v) return not ns.isSecret(v) end
function ns.Readable(v) return v ~= nil and not ns.isSecret(v) end
function ns.Print(...) print("|cffffd200Spell Glow:|r", ...) end

-- A rule: glow `spell` (every rank, matched by name) while ALL of its checked conditions hold.
--   auras       list of aura conditions, all must hold:
--               { name = "" (name or ID; blank = the rule's spell), unit = "player" | "target",
--                 kind = "buff" | "debuff", mode = "present" | "missing",
--                 stacks + cmp ("ge" at least, "gt" more than, "le" at most, "lt" less than): Maelstrom
--                 Weapon only, worked out from Lightning Bolt's cast time (Forever hides stack counts)
--                 mine = true (target auras: only yours), and for your debuffs on a target, the backup
--                 used in combat when it isn't in the Cooldown Manager: dur (s it lasts, 0 = auto),
--                 charges / usedBy (used up after that many casts of those spells; 0 = not used up) }
--   melee       you're being attacked in melee (hit / dodged / parried / blocked recently)
--   usable      castable: known and enough mana
--   ready       off cooldown (the global cooldown doesn't count)
--   control     you have control (not stunned, feared, charmed...)
--   combat      only while you're in combat
--   proc        the game flags the spell as a proc
ns.NEW_RULE = { enabled = true, spell = "", auras = {},
  melee = false, usable = true, ready = true, control = true, combat = false, proc = false }
ns.NEW_AURA = { name = "", unit = "player", kind = "buff", mode = "present", stacks = 0, mine = true,
  dur = 0, charges = 0, usedBy = "", cmp = "ge" }

ns.DEFAULTS = {
  meleeWindow = 3,   -- seconds a melee hit on you counts as "being attacked in melee"
  glowScale = 1.4,   -- Blizzard's alert size around a button
  glowStyle = "shine", -- "glow" (just the glow), "shine" (brief flare at the start), "burst" (Blizzard's zoom-in start)
  glowAlpha = 1,       -- glow intensity
  flareStyle = true,   -- settings window in FlareUI's style when FlareUI is installed
  rules = {
    -- the example asked for: Lightning Shield when it's not on you, you're being hit in melee,
    -- and you can cast it (not stunned, enough mana)
    { enabled = true, spell = "Lightning Shield",
      auras = { { name = "", unit = "player", kind = "buff", mode = "missing", stacks = 0, mine = true, dur = 0, charges = 0, usedBy = "" } },
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
  -- rules saved by an older version: their separate buff / debuff fields become aura conditions
  for _, r in ipairs(SpellGlowDB.rules) do
    if r.auras == nil then
      local au = {}
      local function add(t)
        local c = Copy(ns.NEW_AURA)
        for k, v in pairs(t) do c[k] = v end
        au[#au + 1] = c
      end
      if r.buffs == nil and r.buff and r.buff ~= "ignore" then -- oldest: one "Buff on me"
        r.buffs = { { mode = r.buff, name = r.buffName or "", stacks = 0 } }
      end
      for _, b in ipairs(r.buffs or {}) do
        add({ unit = "player", kind = "buff", mode = b.mode or "present", name = b.name or "", stacks = b.stacks or 0 })
      end
      if r.tdebuff and r.tdebuff ~= "ignore" then
        add({ unit = "target", kind = "debuff", mode = r.tdebuff, name = r.tdebuffName or "",
          mine = r.tdebuffMine ~= false, dur = r.tdebuffDur or 0, charges = r.tdebuffCharges or 0, usedBy = r.tdebuffUsedBy or "" })
      end
      if r.tbuff and r.tbuff ~= "ignore" and (r.tbuffName or "") ~= "" then
        add({ unit = "target", kind = "buff", mode = r.tbuff, name = r.tbuffName, mine = false })
      end
      if r.pdebuff and r.pdebuff ~= "ignore" and (r.pdebuffName or "") ~= "" then
        add({ unit = "player", kind = "debuff", mode = r.pdebuff, name = r.pdebuffName })
      end
      r.auras = au
    end
    for _, k in ipairs({ "buff", "buffName", "buffs", "tdebuff", "tdebuffName", "tdebuffMine", "tdebuffDur",
      "tdebuffCharges", "tdebuffUsedBy", "pdebuff", "pdebuffName", "tbuff", "tbuffName" }) do r[k] = nil end
    for k, v in pairs(ns.NEW_RULE) do if r[k] == nil then r[k] = Copy(v) end end
    for _, c in ipairs(r.auras) do
      for k, v in pairs(ns.NEW_AURA) do if c[k] == nil then c[k] = v end end
    end
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

-- an aura condition's aura name (name or ID; blank = the rule's spell)
function ns.AuraName(rule, a)
  local b = a.name
  if b and b ~= "" then
    local id = tonumber(b)
    return id and ns.SpellName(id) or b
  end
  return ns.RuleSpellName(rule)
end

-- spells that use up a debuff of yours on the target (comma-separated names/IDs; blank = the rule's spell)
function ns.AuraUsedBy(rule, a)
  local list = {}
  for part in (a.usedBy or ""):gmatch("[^,]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    if part ~= "" then
      local id = tonumber(part)
      list[#list + 1] = id and ns.SpellName(id) or part
    end
  end
  if #list == 0 then list[1] = ns.RuleSpellName(rule) end
  return list
end
