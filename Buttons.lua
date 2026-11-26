-- Where the action buttons are (1.19.0): button providers. Each provider knows one kind of action
-- bar; the glow code only asks for the list of buttons, each button's action slot, and its shape.
-- A provider: { name, Present() -> is that UI loaded, Collect(add) -> add(button) for each of its
-- buttons, dynamic = its buttons come and go (the list is built again every few seconds while it's
-- present), Shape(button) -> mask, border for a shaped button (optional) }.
-- Providers: Blizzard's bars, EllesmereUI's bars, and bars built on LibActionButton-1.0 (Bartender4,
-- ElvUI and others).
local _, ns = ...
local B = {}
ns.Buttons = B
local isSecret = ns.isSecret

local providers = {}

-- Blizzard's own bars
local BAR_PREFIXES = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
  "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}
providers[#providers + 1] = {
  name = "Blizzard",
  Present = function() return true end,
  Collect = function(add)
    for _, prefix in ipairs(BAR_PREFIXES) do
      for i = 1, 12 do add(_G[prefix .. i]) end
    end
  end,
}

-- EllesmereUI's action bars: its own buttons, EABButton<action slot>, for bars 1-10
-- (its EUI_ActionBars_Secure.lua: BAR_SLOT_OFFSETS). They're made when a bar is turned on.
local EAB_SLOTS = 180
local EAB_BARS = { -- first slot -> its bar's settings key
  { 1, "MainBar" }, { 13, "Bar9" }, { 25, "Bar4" }, { 37, "Bar5" }, { 49, "Bar3" }, { 61, "Bar2" },
  { 109, "Bar10" }, { 145, "Bar6" }, { 157, "Bar7" }, { 169, "Bar8" },
}
providers[#providers + 1] = {
  name = "EllesmereUI",
  dynamic = true,
  Present = function() return ns.HasEllesmere() end,
  Collect = function(add)
    for slot = 1, EAB_SLOTS do add(_G["EABButton" .. slot]) end
  end,
  -- EllesmereUI can shape its buttons (circle, hexagon, diamond...): a square glow would stick out,
  -- so there Proc This! draws EllesmereUI's own shape glow (its public EllesmereUI.Glows). Returns
  -- the shape's mask and border textures, or nil (a square button: the usual glow).
  Shape = function(b)
    if not (EllesmereUI.Glows.StartShapeGlow and EllesmereUI.SHAPE_MASKS) then return nil end
    local slot = tonumber((b:GetName() or ""):match("^EABButton(%d+)$"))
    if not slot then return nil end
    local key
    for _, e in ipairs(EAB_BARS) do if slot >= e[1] and slot < e[1] + 12 then key = e[2] end end
    local ok, eab = pcall(function() return EllesmereUI.Lite and EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true) end)
    local bars = ok and eab and eab.db and eab.db.profile and eab.db.profile.bars
    local shape = key and type(bars) == "table" and type(bars[key]) == "table" and bars[key].buttonShape
    if not shape or shape == "none" or shape == "cropped" then return nil end
    local mask = EllesmereUI.SHAPE_MASKS[shape]
    if not mask then return nil end
    return mask, EllesmereUI.SHAPE_BORDERS and EllesmereUI.SHAPE_BORDERS[shape]
  end,
}

-- LibActionButton-1.0 (Bartender4, ElvUI...): the library keeps every button it made in
-- lib.buttonRegistry (button -> true)
local function LAB()
  if type(LibStub) ~= "table" or not LibStub.GetLibrary then return nil end
  local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibActionButton-1.0", true)
  return ok and type(lib) == "table" and lib or nil
end
providers[#providers + 1] = {
  name = "LibActionButton",
  dynamic = true,
  Present = function() local lib = LAB(); return lib ~= nil and type(lib.buttonRegistry) == "table" end,
  Collect = function(add)
    for b in pairs(LAB().buttonRegistry) do add(b) end
  end,
}

-- the action slot a button shows: Blizzard's and EllesmereUI's buttons keep it in .action (or
-- work it out); LibActionButton's in _state_action, for its "action" buttons
function B.Action(b)
  local action = b.action or (b.CalculateAction and b:CalculateAction()) or (b.GetAttribute and b:GetAttribute("action"))
  if not action and b._state_type == "action" then action = b._state_action end
  if not action or isSecret(action) or type(action) ~= "number" then return nil end
  return action
end

-- a shaped button's mask and border, from its provider
local owner = {} -- button -> its provider
function B.Shape(b)
  local p = owner[b]
  if p and p.Shape and p.Present() then return p.Shape(b) end
end

-- The buttons, built again when something may have changed (B.Rescan: a UI loaded, the world
-- entered, a restyle) or every 5 s while a provider whose buttons come and go is present. Also
-- returns the buttons that dropped out since the last list (to take their glows off).
local list, builtAt, dirty, gone = {}, -math.huge, true, {}
function B.Rescan() dirty = true end
function B.List()
  local now = GetTime()
  local due = dirty
  if not due and now - builtAt > 5 then
    for _, p in ipairs(providers) do if p.dynamic and p.Present() then due = true end end
  end
  if not due then return list, nil end
  dirty, builtAt = false, now
  local new, seen = {}, {}
  wipe(owner)
  for _, p in ipairs(providers) do
    local ok = p.Present()
    if ok then
      pcall(p.Collect, function(b)
        if b and not seen[b] and type(b) == "table" and b.IsVisible then
          seen[b] = true; owner[b] = p; new[#new + 1] = b
        end
      end)
    end
  end
  wipe(gone)
  for _, b in ipairs(list) do if not seen[b] then gone[#gone + 1] = b end end
  list = new
  return list, (#gone > 0) and gone or nil
end

-- /pt buttons: how many buttons each provider gave
function B.Report()
  local count = {}
  for _, p in pairs(owner) do count[p.name] = (count[p.name] or 0) + 1 end
  local parts = {}
  for _, p in ipairs(providers) do
    parts[#parts + 1] = format("%s %s", p.name, p.Present() and tostring(count[p.name] or 0) or "not loaded")
  end
  return "buttons: " .. table.concat(parts, ", ")
end
