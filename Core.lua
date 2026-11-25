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
--   (an aura row can also be kind = "health" / "mana": unit, op, pct; "combo" / "rage" / "energy":
--    op, pct (an amount); op is "gt" (>), "ge" (>=), "lt" (<), "le" (<=) or "eq" (=);
--    or kind = "rule": rule = another rule's id, mode "present" = it's active, "missing" = it isn't)
ns.NEW_RULE = { enabled = true, spell = "", auras = {},
  melee = false, usable = true, ready = true, control = true, combat = false, proc = false,
  -- its look
  color = "gold", colorCustom = { 1, 1, 1 }, startStyle = "shine", motion = "steady", scale = 1.4, alpha = 1,
  glowType = "blizzard" } -- (EllesmereUI mode: one of its glow styles, see ns.EUI_GLOWS)
ns.NEW_AURA = { name = "", unit = "player", kind = "buff", mode = "present", mine = true,
  dur = 0, charges = 0, usedBy = "",
  group = 1 }  -- which group it's in (see ns.NormalizeGroups)

ns.DEFAULTS = {
  meleeWindow = 3,   -- seconds a melee hit on you counts as "being attacked in melee"
  -- (glowScale / glowStyle / glowAlpha: the old Look tab's one look for all rules; LoadDB copies
  -- them into each rule once, and nothing else reads them)
  flareStyle = true,   -- FlareUI mode: settings window in FlareUI's style (when FlareUI is installed)
  euiMode = true,      -- EllesmereUI mode: glows on its bars, shaped glows, its glow styles (when it's installed)
  chars = {},          -- each character's rules: chars["Name-Realm"] = { rules = {...}, class = "SHAMAN" }
}
-- A new character's first rules, on a fresh install (kept only if it knows the spell): the example
-- asked for, Lightning Shield when it's not on you, you're being hit in melee, and you can cast it
ns.EXAMPLE_RULES = {
  { enabled = true, spell = "Lightning Shield",
    auras = { { name = "", unit = "player", kind = "buff", mode = "missing", mine = true, dur = 0, charges = 0, usedBy = "" } },
    melee = true, usable = true, ready = true, control = true, combat = false, proc = false },
}

-- Glow colours. "gold" is Blizzard's own art, untouched; the rest tint a grey copy of it.
ns.GLOW_COLORS = {
  { "gold", "Blizzard gold" },
  { "red", "Red", { 1, 0.22, 0.2 } }, { "orange", "Orange", { 1, 0.55, 0.1 } }, { "yellow", "Yellow", { 1, 0.95, 0.25 } },
  { "green", "Green", { 0.3, 1, 0.3 } }, { "cyan", "Cyan", { 0.25, 0.9, 1 } }, { "blue", "Blue", { 0.3, 0.55, 1 } },
  { "purple", "Purple", { 0.75, 0.35, 1 } }, { "pink", "Pink", { 1, 0.4, 0.8 } }, { "white", "White", { 1, 1, 1 } },
  { "custom", "Custom" },
}
-- Other UIs, found by themselves: each one's "mode" is on while it's installed (and the player hasn't
-- turned it off in Settings).
function ns.HasEllesmere() return type(EllesmereUI) == "table" and type(EllesmereUI.Glows) == "table" end
function ns.EllesmereMode() return ns.HasEllesmere() and not (ns.db and ns.db.euiMode == false) end
function ns.HasFlare() return ns.UI and ns.UI.FlareBorder and ns.UI.FlareBorder() ~= nil end
-- EllesmereUI's glow styles (EllesmereUI.Glows.STYLES, matched by name): { key, label, its name }
ns.EUI_GLOWS = {
  { "blizzard", "Proc This! glow" },
  { "pixel", "Pixel lines", "Pixel Glow" }, { "button", "Action Button", "Action Button Glow" },
  { "autocast", "Autocast shine", "Auto-Cast Shine" }, { "gcd", "GCD ants", "GCD" },
  { "modern", "Modern WoW", "Modern WoW Glow" }, { "classic", "Classic WoW", "Classic WoW Glow" },
}
-- a rule's EllesmereUI glow style: its index in EllesmereUI.Glows.STYLES, or nil (Proc This!'s own glow)
function ns.EUIStyleIndex(rule)
  if not ns.EllesmereMode() then return nil end
  local key = rule and rule.glowType
  local want
  for _, g in ipairs(ns.EUI_GLOWS) do if g[1] == key then want = g[3] end end
  if not want or type(EllesmereUI.Glows.STYLES) ~= "table" then return nil end
  for i, s in ipairs(EllesmereUI.Glows.STYLES) do if s.name == want then return i end end
end

-- a colour key -> r, g, b, or nil for Blizzard gold
function ns.GlowRGB(key, custom)
  if key == "custom" and type(custom) == "table" then return custom[1], custom[2], custom[3] end
  for _, c in ipairs(ns.GLOW_COLORS) do if c[1] == key and c[3] then return c[3][1], c[3][2], c[3][3] end end
  return nil
end
-- A rule's look: style ("glow" | "shine" | "burst"), motion ("steady" | "pulse"), scale, alpha
function ns.RuleLook(rule)
  local d = ns.NEW_RULE
  return (rule and rule.startStyle) or d.startStyle, (rule and rule.motion) or d.motion,
    tonumber(rule and rule.scale) or d.scale, tonumber(rule and rule.alpha) or d.alpha
end

-- a rule's glow colour: r, g, b, or nil for Blizzard gold
function ns.RuleGlowRGB(rule)
  if not rule then return nil end
  return ns.GlowRGB(rule.color, rule.colorCustom)
end

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

-- Every rule has an id that never changes (moving or deleting other rules doesn't break a
-- "Rule X is active" condition pointing at it).
function ns.NewRuleId()
  ProcThisDB.nextRuleId = (ProcThisDB.nextRuleId or 0) + 1
  return ProcThisDB.nextRuleId
end
function ns.EnsureRuleIds()
  local seen = {}
  for _, r in ipairs(ns.db and ns.db.rules or {}) do
    if r.id == nil or seen[r.id] then r.id = ns.NewRuleId() end
    seen[r.id] = true
    if r.id > (ProcThisDB.nextRuleId or 0) then ProcThisDB.nextRuleId = r.id end
  end
end
function ns.RuleById(id)
  for i, r in ipairs(ns.db and ns.db.rules or {}) do if r.id == id then return r, i end end
end
-- a rule as people see it: its spell, plus its place in the list when several rules glow one spell
function ns.RuleLabel(r)
  local name = ns.RuleSpellName(r) or "(no spell)"
  local n, idx = 0, nil
  for i, x in ipairs(ns.db.rules) do
    if (ns.RuleSpellName(x) or "") == (ns.RuleSpellName(r) or "") then n = n + 1 end
    if x == r then idx = i end
  end
  return n > 1 and format("%s (#%d)", name, idx or 0) or name
end

-- rules saved by an older version: brought up to date
local function MigrateRules(list)
  for _, r in ipairs(list or {}) do
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
    -- the look used to be one for all rules (the old Look tab), with "Default" per rule: each rule
    -- now has its own, so parts left on Default take what that tab had
    local old = { color = ProcThisDB.glowColor, startStyle = ProcThisDB.glowStyle, motion = ProcThisDB.glowMotion,
      scale = ProcThisDB.glowScale, alpha = ProcThisDB.glowAlpha }
    for k, v in pairs(old) do
      if (r[k] == nil or r[k] == "default") and v ~= nil then r[k] = v end
    end
    if r.color == "custom" and r.colorCustom == nil and type(ProcThisDB.glowCustom) == "table" then r.colorCustom = Copy(ProcThisDB.glowCustom) end
    for k, v in pairs(ns.NEW_RULE) do if r[k] == nil or r[k] == "default" then r[k] = Copy(v) end end
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
      -- number rows: "Below" / "Above" / "At least" / "At most" become <, >, >=, <=
      if c.op == nil and (c.hpMode ~= nil or c.cpMode ~= nil) then
        if c.kind == "combo" then c.op = (c.cpMode == "atmost") and "le" or "ge"
        else c.op = (c.hpMode == "above") and "gt" or "lt" end
      end
      c.hpMode, c.cpMode = nil, nil
    end
  end
end

---------------------------------------------------------------------------
-- Rules belong to each character (ProcThisDB.chars["Name-Realm"].rules); settings are shared.
-- ns.db reads and writes ProcThisDB, except ns.db.rules: this character's list.
---------------------------------------------------------------------------
function ns.CharKey()
  local name = UnitName and UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or ""
  return format("%s-%s", tostring(name), tostring(realm))
end

function ns.LoadDB()
  ProcThisDB = ProcThisDB or {}
  for k, v in pairs(ns.DEFAULTS) do
    if ProcThisDB[k] == nil then ProcThisDB[k] = Copy(v) end
  end
  -- before 1.15.0 every character shared one list: kept, for each character's first login
  if ProcThisDB.rules ~= nil then
    if ProcThisDB.sharedRules == nil then ProcThisDB.sharedRules = ProcThisDB.rules end
    ProcThisDB.rules = nil
  end
  MigrateRules(ProcThisDB.sharedRules)
  for _, c in pairs(ProcThisDB.chars) do
    if type(c) == "table" then c.rules = c.rules or {}; MigrateRules(c.rules) end
  end
  local key = ns.CharKey()
  local me = ProcThisDB.chars[key]
  if type(me) ~= "table" then me = { rules = {}, fresh = true }; ProcThisDB.chars[key] = me end
  me.class = UnitClass and select(2, UnitClass("player")) or me.class
  me.name = UnitName and UnitName("player") or me.name
  ns.char = me
  ns.db = setmetatable({}, {
    __index = function(_, k) if k == "rules" then return ns.char.rules end return ProcThisDB[k] end,
    __newindex = function(_, k, v) if k == "rules" then ns.char.rules = v else ProcThisDB[k] = v end end,
  })
  ns.EnsureRuleIds()
end

-- Is this spell in your spellbook?
function ns.SpellKnown(name)
  if not name or name == "" then return false end
  if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
    local ok, slot = pcall(C_SpellBook.FindSpellBookSlotForSpell, name)
    if ok and slot then return true end
  end
  local id
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    id = ok and type(info) == "table" and info.spellID or nil
  end
  if not id or ns.isSecret(id) then return false end
  if IsPlayerSpell then local ok, k = pcall(IsPlayerSpell, id); if ok and k == true then return true end end
  if IsSpellKnown then local ok, k = pcall(IsSpellKnown, id); if ok and k == true then return true end end
  return false
end

-- Would this character use this rule? Its spell is in your spellbook, or its item is in your bags
-- or on you.
function ns.RuleFits(r)
  local item = ns.RuleItem(r)
  if item then
    local n = 0
    if C_Item and C_Item.GetItemCount then local ok, c = pcall(C_Item.GetItemCount, item, true); n = ok and tonumber(c) or 0
    elseif GetItemCount then n = GetItemCount(item, true) or 0 end
    if n > 0 then return true end
    return IsEquippedItem and IsEquippedItem(item) and true or false
  end
  return ns.SpellKnown(ns.RuleSpellName(r))
end

-- Copies of rules (from another character, or the old shared list) added to this character's,
-- each with a new id; "Rule X" rows point at the copies. keep(r): which to take (nil: all).
-- Returns how many were added.
function ns.AddRuleCopies(src, keep)
  if ns.char and keep == nil then ns.char.fresh = nil end -- (you chose this character's rules yourself)
  local map, added = {}, {}
  for _, r in ipairs(src or {}) do
    if not keep or keep(r) then
      local c = Copy(r); c.id = ns.NewRuleId()
      if r.id then map[r.id] = c.id end
      added[#added + 1] = c
    end
  end
  for _, c in ipairs(added) do
    for _, a in ipairs(c.auras or {}) do
      if a.kind == "rule" then a.rule = map[a.rule] end -- (a rule that wasn't copied: pick another)
    end
    table.insert(ns.db.rules, c)
  end
  return #added
end

-- A character's first login: the rules it would use, from the old shared list (or the example).
-- The spellbook can still be loading at login: when nothing fits, it waits for it (final = last try).
function ns.SetUpCharacter(final)
  local me = ns.char
  if not (me and me.fresh) then return end
  local src = ProcThisDB.sharedRules or ns.EXAMPLE_RULES
  local fits = 0
  for _, r in ipairs(src) do if ns.RuleFits(r) then fits = fits + 1 end end
  if fits == 0 and not final then return end
  ns.AddRuleCopies(src, ns.RuleFits)
  me.fresh = nil
  if ProcThisDB.sharedRules and #ProcThisDB.sharedRules > 0 then
    if fits > 0 then
      ns.Print(format("rules are now kept per character. This one starts with the %d of your rules for its spells and items; " ..
        "copy others from Settings > Rules on other characters.", fits))
    else
      ns.Print("rules are now kept per character. None of your rules are for this character's spells, so it starts with none; " ..
        "copy any from Settings > Rules on other characters.")
    end
  end
end

-- Other characters with rules, for "Copy rules from": { { key, label, count } }, sorted
function ns.OtherCharacters()
  local out = {}
  for key, c in pairs(ProcThisDB.chars or {}) do
    if type(c) == "table" and c ~= ns.char and #(c.rules or {}) > 0 then
      out[#out + 1] = { key, format("%s (%d)", key, #c.rules), #c.rules }
    end
  end
  table.sort(out, function(x, y) return x[1] < y[1] end)
  if ProcThisDB.sharedRules and #ProcThisDB.sharedRules > 0 then
    out[#out + 1] = { "*shared", format("Shared list before 1.15.0 (%d)", #ProcThisDB.sharedRules), #ProcThisDB.sharedRules }
  end
  return out
end
function ns.RulesOf(key)
  if key == "*shared" then return ProcThisDB.sharedRules end
  local c = ProcThisDB.chars and ProcThisDB.chars[key]
  return type(c) == "table" and c.rules or nil
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
  if ok and tex then return tex end
  -- an item's icon
  local id = ns.ItemID(spell)
  local okI, itex = pcall(function()
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
  end)
  return id and okI and itex or nil
end

---------------------------------------------------------------------------
-- Items: a rule can glow an item on your bars (a trinket, a potion...), matched by its name
---------------------------------------------------------------------------
function ns.ItemName(id)
  if not id or ns.isSecret(id) then return nil end
  local ok, n = pcall(function()
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    return GetItemInfo and (GetItemInfo(id))
  end)
  return ok and n or nil
end
-- an item's ID from its name, link or ID (nil: not an item the game knows yet)
function ns.ItemID(x)
  if not x or x == "" or ns.isSecret(x) then return nil end
  local fromLink = type(x) == "string" and tonumber(x:match("item:(%d+)"))
  if fromLink then return fromLink end
  local ok, id = pcall(function()
    if C_Item and C_Item.GetItemInfoInstant then return (C_Item.GetItemInfoInstant(x)) end
    return GetItemInfoInstant and (GetItemInfoInstant(x))
  end)
  return ok and tonumber(id) or nil
end
local function IsSpellName(s)
  if not (C_Spell and C_Spell.GetSpellInfo) then return GetSpellInfo and GetSpellInfo(s) ~= nil end
  local ok, info = pcall(C_Spell.GetSpellInfo, s)
  return ok and info ~= nil
end

-- A rule's spell (or item) as typed: a name, a spell ID, an item link or "item:ID" -> its name.
function ns.RuleSpellName(rule)
  local s = rule.spell
  if not s or s == "" then return nil end
  local itemID = s:match("item:(%d+)")
  if itemID then return ns.ItemName(tonumber(itemID)) end
  local id = tonumber(s)
  if id then return ns.SpellName(id) or ns.ItemName(id) end
  return s
end

-- the rule's item ID if it glows an item, not a spell (nil: a spell)
function ns.RuleItem(rule)
  local s = rule.spell
  if not s or s == "" then return nil end
  local linked = tonumber(s:match("item:(%d+)"))
  if linked then return linked end
  local id = tonumber(s)
  if id then return (not ns.SpellName(id)) and ns.ItemName(id) and id or nil end
  if IsSpellName(s) then return nil end
  return ns.ItemID(s)
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
