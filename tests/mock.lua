-- A mock of the game client, just enough for Proc This!'s files to load and run (tests/run_tests.py).
-- Hidden ("secret") values are tables marked secret; the real client is stricter (it errors on
-- comparing or testing one), so these tests can't prove a hidden value is never read.
MOCK = { now = 100, locked = false, inCombat = false, control = true, usable = true,
  cooldown = { isActive = false, isOnGCD = false }, buffs = {}, targetDebuffs = {}, myDebuffs = {},
  target = "Creature-1", targetName = "Mob", guidHidden = false, cdmOn = false, cdm = {}, events = {}, sounds = 0 }

function MOCK.Secret(v) return { secret = true, v = v } end
issecretvalue = function(v) return type(v) == "table" and v.secret == true end
canaccessvalue = function(v) return not issecretvalue(v) end

-- frames ----------------------------------------------------------------------------------
local function obj(name)
  local o = { _scripts = {}, _shown = true, _alpha = 1, _name = name }
  if name then _G[name] = o end
  return setmetatable(o, { __index = function(_, k)
    local m = MOCK.methods[k]
    if m then return m end
    if not k:find("^%u") or k:find("_") then return nil end -- (fields: unset; methods: CamelCase)
    if k:find("^Create") then return function() return obj() end end
    if k:find("^Get") then return function() return nil end end
    return function() end
  end })
end
MOCK.obj = obj
MOCK.methods = {
  Show = function(s) s._shown = true end, Hide = function(s) s._shown = false end,
  SetShown = function(s, v) s._shown = v and true or false end,
  IsShown = function(s) return s._shown end, IsVisible = function(s) return s._shown end,
  SetAlpha = function(s, a) s._alpha = a end, GetAlpha = function(s) return s._alpha end,
  SetAlphaFromBoolean = function(s, v, a, b)
    if issecretvalue(v) then s._alpha = { gate = v.v, ifTrue = a, ifFalse = b } else s._alpha = v and a or b end
  end,
  SetScript = function(s, n, f) s._scripts[n] = f end, HookScript = function(s, n, f) s._scripts[n] = f end,
  GetScript = function(s, n) return s._scripts[n] end,
  RegisterEvent = function(s, e) MOCK.events[e] = MOCK.events[e] or {}; table.insert(MOCK.events[e], s) end,
  RegisterUnitEvent = function(s, e) MOCK.events[e] = MOCK.events[e] or {}; table.insert(MOCK.events[e], s) end,
  GetSize = function() return 45, 45 end, GetWidth = function() return 600 end, GetHeight = function() return 800 end,
  GetFrameLevel = function() return 5 end, GetName = function(s) return s._name end,
  Play = function(s) s._playing = true end, Stop = function(s) s._playing = false end, IsPlaying = function(s) return s._playing end,
  SetText = function(s, t) s._text = t end, GetText = function(s) return s._text or "" end,
  SetFormattedText = function(s, f, ...) s._text = string.format(f, ...) end,
  GetStringHeight = function() return 40 end, GetStringWidth = function() return 40 end,
  HasFocus = function() return false end, GetChecked = function() return false end, GetValue = function() return 1 end,
  GetParent = function(s) return s._parent end, IsForbidden = function() return false end,
  EnumerateActive = function(s) local i = 0 return function() i = i + 1 return (s._items or {})[i] end end,
  GetChildren = function() end, GetRegions = function() end,
  SetVertexColor = function() MOCK.tints = (MOCK.tints or 0) + 1 end,
}
CreateFrame = function(kind, name, parent, template)
  local o = obj(name)
  o._parent = parent
  if template == "ActionButtonSpellAlertTemplate" then
    o._shown = false
    o.ProcStartAnim, o.ProcLoop = obj(), obj()
    o.ProcStartFlipbook, o.ProcLoopFlipbook, o.ProcAltGlow = obj(), obj(), obj()
  end
  return o
end
UIParent = obj("UIParent"); GameTooltip = obj("GameTooltip")

-- spells, items and the action bars -------------------------------------------------------
MOCK.spells = { [945] = "Lightning Shield", [403] = "Lightning Bolt", [8050] = "Flame Shock",
  [8042] = "Earth Shock", [17364] = "Stormstrike", [370] = "Purge" }
MOCK.slots = { [1] = { "spell", 945 }, [2] = { "spell", 403 }, [3] = { "spell", 8050 }, [4] = { "spell", 8042 },
  [5] = { "spell", 17364 } }
for i = 1, 5 do local b = obj("ActionButton" .. i); b.action = i end
GetActionInfo = function(a) local s = MOCK.slots[a]; if s then return s[1], s[2], s[3] end end
local function NameOf(x) return type(x) == "number" and MOCK.spells[x] or x end
C_Spell = {
  GetSpellName = function(id) return MOCK.spells[id] end,
  GetSpellTexture = function() return 1 end,
  GetSpellInfo = function(n) n = NameOf(n); for id, nm in pairs(MOCK.spells) do if nm == n then return { spellID = id, castTime = 1500 } end end end,
  IsSpellUsable = function() if MOCK.usableError then error("boom") end return MOCK.usable end,
  GetSpellCooldown = function(n) if MOCK.noCooldownInfo then return nil end return MOCK.cooldown end,
}
C_SpellBook = { FindSpellBookSlotForSpell = function() return 1 end }

-- auras -----------------------------------------------------------------------------------
-- MOCK.buffs[name] = { duration, expirationTime, applications (stacks / charges) } (on you); MOCK.targetDebuffs[name] = { mine = true };
-- in combat (MOCK.locked) the game refuses aura queries
C_Secrets = { ShouldAurasBeSecret = function() return MOCK.locked end }
C_UnitAuras = {
  GetAuraDataBySpellName = function(unit, name, filter)
    if MOCK.locked then error("Auras cannot be accessed when secret") end
    if unit == "player" and filter == "HELPFUL" then
      local b = MOCK.buffs[name]; if b then return { name = name, duration = b.duration, expirationTime = b.expirationTime, applications = b.applications or 0 } end
      return nil
    end
    if unit == "target" and filter and filter:find("HARMFUL") then
      local d = MOCK.targetDebuffs[name]; if d then return { name = name, duration = d.duration or 12 } end
    end
    return nil
  end,
  GetAuraDataByIndex = function() if MOCK.locked then error("Auras cannot be accessed when secret") end return nil end,
}
GetCVarBool = function() return MOCK.cdmOn end
-- the Cooldown Manager: MOCK.cdm[spellID] = true / false (tracked, active or not)
C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(cid) return { spellID = cid } end }
local viewer = obj("BuffIconCooldownViewer")
viewer.itemFramePool = { EnumerateActive = function()
  local list = {}
  for id, active in pairs(MOCK.cdm) do list[#list + 1] = { cooldownID = id, isActive = active } end
  local i = 0 return function() i = i + 1 return list[i] end
end }

-- units -----------------------------------------------------------------------------------
UnitExists = function(u) if u == "target" then return MOCK.target ~= nil end return true end
UnitGUID = function(u)
  if u == "target" then if MOCK.guidHidden then return MOCK.Secret(MOCK.target) end return MOCK.target end
  return "Player-1"
end
UnitName = function(u) if u == "target" then return MOCK.targetName end return "Tester" end
GetRealmName = function() return "Realm" end
UnitClass = function() return "Shaman", "SHAMAN" end
UnitAffectingCombat = function() return MOCK.inCombat end
HasFullControl = function() return MOCK.control end
UnitIsDeadOrGhost = function() return false end
InCombatLockdown = function() return MOCK.inCombat end
GetTime = function() return MOCK.now end

-- the rest --------------------------------------------------------------------------------
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
format = string.format; tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
UISpecialFrames = {}; SlashCmdList = {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
PRINTS = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end PRINTS[#PRINTS + 1] = table.concat(t, " ") end

function MOCK.Fire(event, ...)
  for _, f in ipairs(MOCK.events[event] or {}) do
    if f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
-- you cast a spell (UNIT_SPELLCAST_SUCCEEDED: unit, castGUID, spellID)
function MOCK.Cast(id) MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", id) end
-- the cast in two steps, as the game sends them: UNIT_SPELLCAST_SENT (unit, target name, castGUID,
-- spellID) when it starts, UNIT_SPELLCAST_SUCCEEDED (unit, castGUID, spellID) when it goes off
function MOCK.Sent(id, to, guid) MOCK.Fire("UNIT_SPELLCAST_SENT", "player", to or "", guid, id) end
function MOCK.Done(id, guid) MOCK.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id) end
-- something hits you (UNIT_COMBAT: unit, action, descriptor, amount, school)
function MOCK.Hit(action) MOCK.Fire("UNIT_COMBAT", "player", action or "WOUND", "", 10, 1) end
-- combat: the game starts hiding auras
function MOCK.Combat(on)
  MOCK.locked, MOCK.inCombat = on, on
  MOCK.Fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
function MOCK.Start()
  MOCK.Fire("ADDON_LOADED", "ProcThis")
  MOCK.Fire("PLAYER_LOGIN")
end
-- a rule for these tests (the addon's defaults, with the given fields)
function MOCK.Rule(fields)
  local r = NS.Copy(NS.NEW_RULE)
  r.id = NS.NewRuleId()
  for k, v in pairs(fields) do r[k] = v end
  for _, a in ipairs(r.auras or {}) do for k, v in pairs(NS.NEW_AURA) do if a[k] == nil then a[k] = v end end end
  table.insert(NS.db.rules, r)
  return r
end
-- is the glow on a button showing? "glow", "gated" (the game decides), or ""; and how many layers
function MOCK.Glow(button)
  local b = _G[button]
  local res, n = "", 0
  for _, L in ipairs(b.SG_Layers or {}) do
    if L.glow and L.glow._shown then
      n = n + 1
      local gated = false
      for _, gate in ipairs(L.gates) do if type(gate._alpha) == "table" then gated = true end end
      res = (gated and res ~= "glow") and "gated" or "glow"
    end
  end
  return res, n
end
-- the open layers of a button for these hidden values (gate.v as stored by SetAlphaFromBoolean):
-- vals[v] = true / false. Counts the layers whose every gate is open.
function MOCK.OpenLayers(button, vals)
  local open = 0
  for _, L in ipairs(_G[button].SG_Layers or {}) do
    if L.glow and L.glow._shown then
      local ok = true
      for _, gate in ipairs(L.gates) do
        local a = gate._alpha
        if type(a) == "table" then
          local on = vals[a.gate]
          if (on and a.ifTrue or a.ifFalse) == 0 then ok = false end
        elseif a == 0 then ok = false end
      end
      if ok then open = open + 1 end
    end
  end
  return open
end
