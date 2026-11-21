-- Spell Glow: shared namespace, settings and spell helpers.
local ADDON, ns = ...
ns.name = ADDON

ns.isSecret = issecretvalue or function() return false end
ns.canAccess = canaccessvalue or function(v) return not ns.isSecret(v) end
function ns.Readable(v) return v ~= nil and not ns.isSecret(v) end
function ns.Print(...) print("|cffffd200Proc This!:|r", ...) end

-- A rule: glow `spell` (every rank, matched by name) while ALL of its checked conditions hold.
--   auras       list of aura conditions, all must hold:
--               { name = "" (name or ID; blank = the rule's spell), unit = "player" | "target",
--                 kind = "buff" | "debuff" | "instant" (the named spell is instant cast right now;
--                 mode "present" = is, "missing" = isn't), mode = "present" | "missing",
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
ns.NEW_AURA = { name = "", unit = "player", kind = "buff", mode = "present", mine = true,
  dur = 0, charges = 0, usedBy = "",
  group = 1 }  -- which group it's in (see ns.NormalizeGroups)

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
      auras = { { name = "", unit = "player", kind = "buff", mode = "missing", mine = true, dur = 0, charges = 0, usedBy = "" } },
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

-- Conditions come in groups: rule.groupModes[g] = "all" (every row in the group must hold) or
-- "any" (one is enough); rule.join = "and" (every group must hold) or "or" (one group is enough).
-- Keeps groups numbered 1..n in order, rows sorted by group, and drops empty groups.
function ns.NormalizeGroups(r)
  r.auras = r.auras or {}
  r.groupModes = r.groupModes or {}
  r.join = (r.join == "or") and "or" or "and"
  local order, map = {}, {}
  for _, a in ipairs(r.auras) do
    local g = tonumber(a.group) or 1
    if not map[g] then order[#order + 1] = g; map[g] = true end
  end
  table.sort(order)
  local renum, modes = {}, {}
  for i, g in ipairs(order) do renum[g] = i; modes[i] = (r.groupModes[g] == "any") and "any" or "all" end
  for _, a in ipairs(r.auras) do a.group = renum[tonumber(a.group) or 1] end
  -- stable sort by group
  for i, a in ipairs(r.auras) do a._i = i end
  table.sort(r.auras, function(x, y) if x.group ~= y.group then return x.group < y.group end return x._i < y._i end)
  for _, a in ipairs(r.auras) do a._i = nil end
  r.groupModes = modes
end

function ns.LoadDB()
  -- first run after the rename: bring over the rules saved under the old SpellGlow folder
  -- (the small "SpellGlow" carry-over addon that ships alongside loads them for us)
  if ProcThisDB == nil and type(SpellGlowDB) == "table" then
    ProcThisDB = Copy(SpellGlowDB)
    ns.carriedOver = true
  end
  ProcThisDB = ProcThisDB or {}
  for k, v in pairs(ns.DEFAULTS) do
    if ProcThisDB[k] == nil then ProcThisDB[k] = Copy(v) end
  end
  -- rules saved by an older version: their separate buff / debuff fields become aura conditions
  for _, r in ipairs(ProcThisDB.rules) do
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
        add({ unit = "player", kind = "buff", mode = b.mode or "present", name = b.name or "", stacks = b.stacks })
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
    -- stack checks are gone (Forever hides stack counts). Maelstrom Weapon rows become
    -- Lightning Bolt instant checks: "5 stacks" -> is instant, "fewer than 5" -> isn't instant;
    -- other stack numbers can't be told apart any more, so the row just needs the buff
    for _, a in ipairs(r.auras) do
      if a.stacks ~= nil or a.cmp ~= nil then
        local n, cmp = math.floor(tonumber(a.stacks) or 0), a.cmp or "ge"
        local mw = a.name == "Maelstrom Weapon" or (ns.SpellName and a.name == ns.SpellName(408505))
        if mw and a.mode ~= "missing" and a.unit ~= "target" then
          local bolt = (ns.SpellName and ns.SpellName(403)) or "Lightning Bolt"
          if (cmp == "ge" and n >= 5) or (cmp == "eq" and n >= 5) or (cmp == "gt" and n >= 4) then
            a.kind, a.name, a.mode = "instant", bolt, "present"
          elseif (cmp == "lt" and n <= 5 and n > 1) or (cmp == "le" and n < 5 and n > 0) then
            a.kind, a.name, a.mode = "instant", bolt, "missing"
          end
        end
        a.stacks, a.cmp = nil, nil
      end
    end
    ProcThisDB.boltRaw = nil
    -- rows joined by OR (an earlier test build) -> groups: each OR run becomes an "any" group,
    -- the rest one "all" group
    local hadJoin = false
    for _, a in ipairs(r.auras) do if a.join ~= nil then hadJoin = true end end
    if hadJoin and r.groupModes == nil then
      local runs, cur = {}, nil
      for i, a in ipairs(r.auras) do
        if i == 1 or a.join ~= "or" then cur = { a }; runs[#runs + 1] = cur else cur[#cur + 1] = a end
      end
      r.groupModes = {}
      local g, single = 0, nil
      for _, run in ipairs(runs) do
        if #run > 1 then
          g = g + 1; r.groupModes[g] = "any"; single = nil
          for _, a in ipairs(run) do a.group = g end
        else
          if not single then g = g + 1; r.groupModes[g] = "all"; single = g end
          run[1].group = single
        end
      end
    end
    for _, a in ipairs(r.auras) do a.join = nil end
    ns.NormalizeGroups(r)
    for _, c in ipairs(r.auras) do
      for k, v in pairs(ns.NEW_AURA) do if c[k] == nil then c[k] = v end end
    end
  end
  ns.db = ProcThisDB
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
