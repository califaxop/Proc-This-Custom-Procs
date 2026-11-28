-- Proc This!: settings window (/pt, /proc or /procthis, or Esc > Options > AddOns > Proc This!) and start-up.
-- In the game's own Settings design (Settings.lua): pages for the rules, the selected rule, settings and help.
local _, ns = ...
local UI = ns.UI

local function Changed() ns.Glow.Soon() end

local selected = 1
local win, ui
local function Rule() return ns.db.rules[selected] end
local function Field(tbl, key) return { function() local t = tbl(); return t and t[key] end, function(v) local t = tbl(); if t then t[key] = v end end } end

local LIST_W = 420 -- the rules list

-- Colour picking: the game's colour picker on a { r, g, b } table
local function OpenColorPicker(color, onChange)
  if not ColorPickerFrame then return end
  local r, g, b = color[1], color[2], color[3]
  local function apply()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    color[1], color[2], color[3] = nr, ng, nb
    onChange()
  end
  local function cancel(prev)
    if prev then
      color[1] = prev.r or prev[1]; color[2] = prev.g or prev[2]; color[3] = prev.b or prev[3]
    else
      color[1], color[2], color[3] = r, g, b
    end
    onChange()
  end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = apply, cancelFunc = cancel })
  else
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc = apply, cancel
    ColorPickerFrame.hasOpacity, ColorPickerFrame.previousValues = false, { r = r, g = g, b = b }
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Show()
  end
end

-- A glow colour choice: a switch through the palette and a swatch showing it; clicking the swatch
-- picks a custom colour. get/set read and write the key, custom() gives the custom { r, g, b }.
-- withDefault adds a "Default colour" choice first.
local function ColorChoice(parent, width, get, set, custom, withDefault, onChange, tip)
  local opts = {}
  if withDefault then opts[#opts + 1] = { "default", "Default colour" } end
  for _, c in ipairs(ns.GLOW_COLORS) do opts[#opts + 1] = { c[1], c[2] } end
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width + 24, 22)
  local t = UI.Toggle(f, width, opts, { get, set }, function() f.Refresh(); onChange() end, tip)
  t:SetPoint("LEFT", 0, 0)
  local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
  sw:SetSize(18, 18); sw:SetPoint("LEFT", t, "RIGHT", 6, 0)
  sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  local function rgb()
    local key = get()
    if key == nil then return nil end
    return ns.GlowRGB(key, custom())
  end
  f.Refresh = function()
    t.Refresh()
    local r, g, b = rgb()
    if r then sw:SetBackdropColor(r, g, b, 1) else sw:SetBackdropColor(1, 0.82, 0, 1) end -- gold
    sw:SetBackdropBorderColor(0, 0, 0, 1)
  end
  sw:SetScript("OnClick", function()
    local c = custom()
    if not c then return end
    local r, g, b = rgb()
    if r then c[1], c[2], c[3] = r, g, b end -- start from the colour shown
    set("custom")
    OpenColorPicker(c, function() f.Refresh(); onChange() end)
  end)
  sw:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Click to pick any colour", 1, 1, 1); GameTooltip:Show()
  end)
  sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end
local EW = 620 -- the rule editor's width
local EDIT = 6 -- the game's text box draws its left edge this far out: boxes sit this far in

---------------------------------------------------------------------------
-- Rule editor: spell, aura conditions (as many as you like), other conditions, live status
---------------------------------------------------------------------------
local CHECKS = {
  { "melee",   "Being attacked in melee" },
  { "usable",  "Castable (known, enough mana / rage / energy)" },
  { "ready",   "Off cooldown (GCD ignored)" },
  { "control", "I have control (not stunned)" },
  { "combat",  "Only in combat" },
  { "proc",    "The game flags it as a proc" },
}
local UNITS = { { "player", "Self" }, { "target", "Target" } }
local KINDS = { { "buff", "Buff" }, { "debuff", "Debuff" }, { "instant", "Instant Cast" }, { "health", "Health" }, { "mana", "Mana" },
  { "combo", "Combo Points" }, { "rage", "Rage" }, { "energy", "Energy" }, { "rule", "Rule" } }
local OPMODES = {}
for _, op in ipairs(ns.State.OP_ORDER) do OPMODES[#OPMODES + 1] = { op, ns.State.OPS[op] } end
local POWER_UNIT = { combo = "points", rage = "rage", energy = "energy" }
-- every condition reads [Kind] [Who] [What] [State]: [Debuff] [Target] [Stormstrike] [Active],
-- [Rule] [Lightning Bolt] [Inactive], [Instant Cast] [Lightning Bolt] [Active], [Health] [Self] [Below] [40] %
local IMODES = { { "present", "Active" }, { "missing", "Inactive" } }
local RMODES = IMODES
local MODES = IMODES

local Res = ns.Result
-- a rule's result as one line (the editor's status, the list's tooltips)
local function ResultLine(st, why, set)
  if st == Res.GATED then
    local line = "|cffffd200Glowing when the game says so (hidden values)|r"
    if set.partial then line = line .. " - partly: " .. (why or "?") .. "; it may not glow every time it should" end
    return line
  end
  if st == Res.TRUE then return "|cff60ff60Glowing|r" end
  if st == Res.UNKNOWN then return "|cffffd200Not glowing: can't tell|r - " .. (why or "?") end
  if st == Res.ERROR then return "|cffff6060Not glowing: error|r - " .. (why or "?") end
  return "Not glowing: " .. (why or "?")
end
-- the list's status dots
local STATUS_DOT = { [Res.TRUE] = { 0.38, 1, 0.38 }, [Res.GATED] = { 1, 0.82, 0 }, [Res.UNKNOWN] = { 1, 0.55, 0.1 },
  [Res.ERROR] = { 1, 0.3, 0.3 } }

local function BuildEditor(p)
  local e = { rows = {} }

  -- header: icon, rule name, enabled
  e.icon = p:CreateTexture(nil, "ARTWORK")
  e.icon:SetSize(26, 26); e.icon:SetPoint("TOPLEFT", 0, 0)
  e.title = UI.Font(p, "GameFontHighlightLarge", "")
  e.title:SetPoint("LEFT", e.icon, "RIGHT", 8, 0); e.title:SetWidth(EW - 140); e.title:SetWordWrap(false)
  e.enabled = UI.LabeledCheck(p, "Enabled", Field(Rule, "enabled"), function() ui.Refresh(); Changed() end)
  e.enabled:SetPoint("TOPRIGHT", p, "TOPLEFT", EW - 70, 0)


  -- spell
  e.secSpell = UI.Font(p, "GameFontHighlightLarge", "Spell or item to glow")
  e.spell = UI.Edit(p, 230, { function() local r = Rule(); return r and r.spell end,
    function(v) local r = Rule(); if r then r.spell = v; ui.Refresh(); Changed() end end },
    "Name or ID", "items")
  e.spellNote = UI.Note(p, "Every rank glows. Type it, or drag it from your spellbook or bags (trinkets, potions...).")
  e.spellNote:SetWidth(EW - 244)

  -- aura conditions, in groups
  e.secAuras = UI.Font(p, "GameFontHighlightLarge", "Conditions")
  e.cdmNote = UI.Note(p,
    "Conditions come in groups. Each group needs all of its rows, or any one of them; " ..
    "groups are joined by AND (every group) or OR (any group). In combat the game hides auras from addons: " ..
    "add each one to Blizzard's Cooldown Manager (Tracked Buffs or Bars). The dot shows if it's tracked.")
  e.cdmNote:SetWidth(EW)
  e.none = UI.Note(p, "No conditions yet: start a group below.")
  -- "+ New group": name the first condition of a new group
  local newName = ""
  e.newGroupBox = UI.Edit(p, 200, { function() return newName end, function(v) newName = v end },
    "Buff or debuff: name or ID", true)
  e.newGroup = UI.Button(p, "+ New group", 110, function()
    local r = Rule(); if not r then return end
    local c = ns.Copy(ns.NEW_AURA); c.name = strtrim(e.newGroupBox:GetText() or "")
    local maxG = 0
    for _, x in ipairs(r.auras) do maxG = math.max(maxG, tonumber(x.group) or 1) end
    c.group = maxG + 1
    table.insert(r.auras, c)
    ns.NormalizeGroups(r)
    newName = ""; e.newGroupBox:SetText(""); e.newGroupBox:ClearFocus()
    ui.Refresh(); Changed()
  end)
  e.newGroup.tip = "Start another group of conditions. Blank name = the spell itself."
  e.newGroupBox:SetScript("OnEnterPressed", function() e.newGroup:Click() end)

  -- other conditions
  e.secOther = UI.Font(p, "GameFontHighlightLarge", "Other conditions")
  e.checks = {}
  for i, c in ipairs(CHECKS) do
    e.checks[i] = UI.LabeledCheck(p, c[2], Field(Rule, c[1]), Changed)
  end

  -- this rule's look
  e.secLook = UI.Font(p, "GameFontHighlightLarge", "Look")
  e.lookParts = {}
  local function lookField(key) return { function() local r = Rule(); return r and r[key] or ns.NEW_RULE[key] end,
    function(v) local r = Rule(); if r then r[key] = v end end } end
  local function label(text) local t = UI.Font(p, "GameFontNormal", text); e.lookParts[#e.lookParts + 1] = t; return t end
  e.lColorL = label("Colour")
  e.color = ColorChoice(p, 140, lookField("color")[1], lookField("color")[2],
    function() local r = Rule(); if not r then return nil end; r.colorCustom = r.colorCustom or { 1, 1, 1 }; return r.colorCustom end,
    false, function() ns.Glow.Restyle() end, "This rule's glow colour. Click to switch; click the swatch for any colour.")
  e.lookParts[#e.lookParts + 1] = e.color
  e.styleOpts = { { "glow", "Just the glow" }, { "shine", "Glow + shine" }, { "burst", "Blizzard burst" } }
  e.motionOpts = { { "steady", "Steady" }, { "pulse", "Pulse" } }
  e.sizeOpts = { { 1, "100%" }, { 1.2, "120%" }, { 1.4, "140%" }, { 1.6, "160%" }, { 1.8, "180%" }, { 2, "200%" } }
  e.alphaOpts = { { 0.4, "40%" }, { 0.6, "60%" }, { 0.8, "80%" }, { 1, "100%" } }
  e.lStyleL = label("When it starts")
  e.style = UI.Toggle(p, 140, e.styleOpts, lookField("startStyle"), function() ns.Glow.Restyle(); ui.Refresh() end,
    "How the glow starts: just the glow, a brief shine, or Blizzard's burst. Click to switch.")
  e.lMotionL = label("While it's on")
  e.motion = UI.Toggle(p, 120, e.motionOpts, lookField("motion"), function() ns.Glow.Restyle(); ui.Refresh() end,
    "Steady, or a gentle pulse. Click to switch.")
  e.lSizeL = label("Size")
  e.size = UI.Toggle(p, 140, e.sizeOpts, lookField("scale"), function() ns.Glow.Restyle(); ui.Refresh() end,
    "How big the glow is around the button. Click to switch.")
  -- with EllesmereUI: its glow styles too
  e.lGlowL = label("Glow")
  e.glowType = UI.Toggle(p, 140, ns.EUI_GLOWS, { function() local r = Rule(); return r and r.glowType or "blizzard" end,
    function(v) local r = Rule(); if r then r.glowType = v end end }, function() ns.Glow.Restyle(); ui.Refresh() end,
    "With EllesmereUI: Proc This!'s glow, or one of EllesmereUI's (pixel lines, autocast shine, GCD ants...). Click to switch. " ..
    "On EllesmereUI's shaped buttons it's always its shape glow.")
  e.lookParts[#e.lookParts + 1] = e.glowType
  e.lAlphaL = label("Intensity")
  e.alpha = UI.Toggle(p, 120, e.alphaOpts, lookField("alpha"), function() ns.Glow.Restyle(); ui.Refresh() end,
    "How strong the glow is. Click to switch.")
  for _, w in ipairs({ e.style, e.motion, e.size, e.alpha }) do e.lookParts[#e.lookParts + 1] = w end
  e.lookTest = UI.Button(p, "Test glow", 90, function() ns.Glow.Test(3) end)
  e.lookParts[#e.lookParts + 1] = e.lookTest
  -- copy this rule's look to every rule (a second click within 5 seconds confirms)
  local LOOK_KEYS = { "color", "startStyle", "motion", "scale", "alpha", "glowType" }
  e.lookAll = UI.Button(p, "Use for all rules", 130, function()
    local r = Rule(); if not r then return end
    UI.Confirm("ProcThisConfirm", format("Give all %d rules this look?\n|cffffd200%s|r's colour, start, pulse, size and intensity.",
      #ns.db.rules, ns.RuleLabel(r)), function()
      for _, x in ipairs(ns.db.rules) do
        for _, k in ipairs(LOOK_KEYS) do x[k] = r[k] end
        x.colorCustom = ns.Copy(r.colorCustom or { 1, 1, 1 })
      end
      ns.Glow.Restyle(); ui.Refresh()
    end)
  end)
  e.lookAll.tip = "Give every rule this rule's look (colour, start, pulse, size, intensity)."
  e.lookParts[#e.lookParts + 1] = e.lookAll
  e.RefreshLook = function()
    for _, w in ipairs({ e.color, e.style, e.motion, e.size, e.alpha, e.glowType }) do w.Refresh() end
    -- an EllesmereUI glow style has no start animation or size of ours
    local own = not (ns.HasEllesmere() and ns.EUIStyleIndex(Rule()))
    e.style.SetActive(own); e.size.SetActive(own)
  end

  -- status
  e.secStatus = UI.Font(p, "GameFontHighlightLarge", "Current Rule Status")
  e.status = UI.Font(p, "GameFontHighlight", "")
  e.status:SetWidth(EW); e.status:SetSpacing(3)

  -- one aura row (+ a second line for your debuffs on the target)
  local function Row(i)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(EW - 24, 48)
    local function A() local r = Rule(); return r and r.auras[i] end
    local function refresh() ui.Refresh(); Changed() end
    row.unit = UI.Toggle(row, 62, UNITS, Field(A, "unit"), refresh, "On you (Self) or on your target. Click to switch.")
    row.kind = UI.Toggle(row, 96, KINDS, Field(A, "kind"), refresh,
      "A buff, a debuff, Instant Cast (the spell is instant cast right now: Maelstrom Weapon at 5, Nature's Swiftness...), Health or Mana (yours or your target's, compared with a %), Combo Points, Rage or Energy (compared with an amount), or Rule (another of your rules is active, or isn't). Click to switch; right-click to go back.")
    -- for Instant rows, after the spell: instant now (Active) or not (Inactive)
    row.imode = UI.Toggle(row, 70, IMODES, Field(A, "mode"), refresh, "Active: glow while the spell is instant cast. Inactive: while it isn't. Click to switch.")
    -- for Rule rows, after the rule: Active / Inactive
    row.rmode = UI.Toggle(row, 70, RMODES, Field(A, "mode"), refresh,
      "Glow while the rule you pick is active (its conditions are met right now), or while it's inactive. Click to switch.")
    row.mode = UI.Toggle(row, 70, MODES, Field(A, "mode"), refresh, "Active: glow while it's on. Inactive: while it's missing. Click to switch.")
    -- for number rows (Health, Mana, Combo Points, Rage, Energy): the comparison, then the number
    row.op = UI.Toggle(row, 40, OPMODES, { function() return ns.State.Op(A()) end,
      function(v) local a = A(); if a then a.op = v end end }, refresh,
      "Compare with the number: > more than, >= at least, < less than, <= at most, = exactly. Click to switch; right-click to go back.")
    row.pct = UI.Edit(row, 40, { function() local a = A(); return a and (a.pct or 40) end,
      function(v)
        local a = A()
        if not a then return end
        local hi = (a.kind == "combo") and 5 or ((a.kind == "rage" or a.kind == "energy") and 150 or 100)
        local lo = 0
        a.pct = math.max(lo, math.min(hi, math.floor(tonumber(v) or 40))); refresh()
      end },
      "40", false, true)
    row.pctSign = UI.Font(row, "GameFontHighlight", "%")
    row.pctSign:SetPoint("LEFT", row.pct, "RIGHT", 4, 0)
    -- for Rule rows: which other rule (then Active / Inactive)
    row.ruleOpts = {}
    row.ruleSel = UI.Toggle(row, 200, row.ruleOpts, { function() local a = A(); return a and a.rule end,
      function(v) local a = A(); if a then a.rule = v end end }, refresh,
      "Which rule: click to step through your rules. It's active while its own conditions are met (whether or not its spell is on your bars).")
    row.name = UI.Edit(row, 116, { function() local a = A(); return a and a.name end,
      function(v) local a = A(); if a then a.name = v; refresh() end end }, "the spell itself", true)
    row.dot = CreateFrame("Frame", nil, row)
    row.dot:SetSize(12, 12); row.dot:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.dot.tex = row.dot:CreateTexture(nil, "ARTWORK")
    row.dot.tex:SetTexture("Interface\\Buttons\\WHITE8X8"); row.dot.tex:SetSize(8, 8); row.dot.tex:SetPoint("CENTER")
    row.dot:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tracked and "Tracked in the Cooldown Manager" or "Not in the Cooldown Manager", 1, 1, 1)
      GameTooltip:AddLine(self.tracked and "Followed in combat." or
        "In combat Proc This! can't see it, and the rule won't glow. Add it to the Cooldown Manager's Tracked Buffs or Tracked Bars.", 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    row.dot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.del = UI.Button(row, "\195\151", 22, function()
      local r = Rule(); if r then table.remove(r.auras, i); ns.NormalizeGroups(r); refresh() end
    end)
    row.del.tip = "Remove this condition"
    row.del:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)

    -- second line: your debuff on the target
    row.mine = UI.LabeledCheck(row, "Only mine", Field(A, "mine"), refresh)
    row.mine:SetPoint("TOPLEFT", 4, -24)
    row.lasts = UI.Note(row, "lasts")
    row.lasts:SetPoint("LEFT", row.mine.label, "RIGHT", 10, 0)
    row.dur = UI.Edit(row, 34, { function() local a = A(); return a and a.dur end,
      function(v) local a = A(); if a then a.dur = math.max(0, math.min(600, tonumber(v) or 0)); refresh() end end }, "", false, true)
    row.dur:SetPoint("LEFT", row.lasts, "RIGHT", 4 + EDIT, 0)
    row.after = UI.Note(row, "s, used up after")
    row.after:SetPoint("LEFT", row.dur, "RIGHT", 4, 0)
    row.charges = UI.Edit(row, 28, { function() local a = A(); return a and a.charges end,
      function(v) local a = A(); if a then a.charges = math.max(0, math.min(20, math.floor(tonumber(v) or 0))); refresh() end end }, "", false, true)
    row.charges:SetPoint("LEFT", row.after, "RIGHT", 4 + EDIT, 0)
    row.casts = UI.Note(row, "casts of")
    row.casts:SetPoint("LEFT", row.charges, "RIGHT", 4, 0)
    row.usedBy = UI.Edit(row, 92, { function() local a = A(); return a and a.usedBy end,
      function(v) local a = A(); if a then a.usedBy = v; refresh() end end }, "this spell", false)
    row.usedBy:SetPoint("LEFT", row.casts, "RIGHT", 4 + EDIT, 0)
    row.extra = { row.mine, row.lasts, row.dur, row.after, row.charges, row.casts, row.usedBy }
    row.dur.tip = "Backup when it isn't in the Cooldown Manager: how long it lasts after you cast it (0 = auto)."
    row.Refresh = function()
      local a = A()
      if not a then return end
      local r = Rule()
      local isRule = a.kind == "rule"
      -- the other rules to pick from (not this one, nor one that needs this one: a loop)
      wipe(row.ruleOpts)
      for _, x in ipairs(ns.db.rules) do
        if x.id and not ns.DependsOn(x, r) then row.ruleOpts[#row.ruleOpts + 1] = { x.id, ns.RuleLabel(x) } end
      end
      if #row.ruleOpts == 0 then row.ruleOpts[1] = { false, "(no other rule can be used here)" } end
      -- a Rule row points at the first of them until one is picked
      if isRule and (not ns.RuleById(a.rule) or a.rule == r.id) then a.rule = row.ruleOpts[1][1] or nil end
      local power = POWER_UNIT[a.kind] ~= nil
      -- (a combo points row starts at 5; a number from another kind of row is brought into range)
      if a.kind == "combo" and (not a.pct or a.pct > 5) then a.pct = 5 end
      if (a.kind == "rage" or a.kind == "energy") and not a.pct then a.pct = 50 end
      for _, w in ipairs({ row.unit, row.imode, row.rmode, row.kind, row.mode, row.name, row.mine, row.dur, row.charges, row.usedBy, row.op, row.pct, row.ruleSel }) do w.Refresh() end
      local instant = a.kind == "instant"
      local health = a.kind == "health" or a.kind == "mana" or power -- (a row that compares a number)
      row.pctSign:SetText(POWER_UNIT[a.kind] or "%")
      row.unit:SetShown(not instant and not isRule and not power); row.mode:SetShown(not instant and not health and not isRule)
      row.name:SetWidth(instant and 150 or 116)
      row.imode:SetShown(instant); row.rmode:SetShown(isRule)
      row.op:SetShown(health); row.pct:SetShown(health); row.pctSign:SetShown(health)
      row.ruleSel:SetShown(isRule)
      row.name:SetShown(not health and not isRule)
      -- [Kind] [Who] [What] [State], left to right (the dot and the remove button after)
      local chain
      if isRule then chain = { row.kind, row.ruleSel, row.rmode }
      elseif instant then chain = { row.kind, row.name, row.imode }
      elseif power then chain = { row.kind, row.op, row.pct, row.pctSign }
      elseif health then chain = { row.kind, row.unit, row.op, row.pct, row.pctSign }
      else chain = { row.kind, row.unit, row.name, row.mode } end
      for j, w in ipairs(chain) do
        w:ClearAllPoints()
        local gap = (w == row.pctSign or chain[j - 1] == row.pctSign) and 4 or ((w == row.name or w == row.pct) and 6 + EDIT or 6)
        if j == 1 then w:SetPoint("TOPLEFT", 0, 0) else w:SetPoint("LEFT", chain[j - 1], "RIGHT", gap, 0) end
      end
      row.dot:ClearAllPoints()
      row.dot:SetPoint("LEFT", chain[#chain], "RIGHT", 10, 0)
      row.dot:SetShown(not instant and not health and not isRule) -- these need no Cooldown Manager
      local tdebuff = a.unit == "target" and a.kind == "debuff"
      for _, w in ipairs(row.extra) do w:SetShown(tdebuff) end
      local an = ns.AuraName(r, a)
      local tracked = an and ns.State.Tracked(an) or false
      row.dot.tracked = tracked
      if tracked then row.dot.tex:SetVertexColor(0.35, 0.9, 0.35) else row.dot.tex:SetVertexColor(0.9, 0.3, 0.25) end
      row:SetHeight(tdebuff and 54 or 28)
    end
    return row
  end

  -- a group: a bordered box with its "All of these / Any of these" switch, its rows, and its own Add box
  e.boxes = {}
  local function Box(g)
    local bx = CreateFrame("Frame", nil, p, "BackdropTemplate")
    bx:SetFrameLevel(math.max(1, p:GetFrameLevel()))
    bx:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bx:SetBackdropColor(0, 0, 0, 0.25); bx:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    bx.title = UI.Font(bx, "GameFontNormal", "Group " .. g)
    bx.title:SetPoint("TOPLEFT", 10, -9)
    bx.mode = UI.Toggle(p, 210, { { "all", "All of these must hold" }, { "any", "Any one of these is enough" } },
      { function() local r = Rule(); return r and r.groupModes and r.groupModes[g] or "all" end,
        function(v) local r = Rule(); if r then r.groupModes = r.groupModes or {}; r.groupModes[g] = v end end },
      function() ui.Refresh(); Changed() end, "How the rows in this group combine. Click to switch.")
    bx.mode:SetPoint("LEFT", bx.title, "RIGHT", 10, 0)
    local name = ""
    bx.add = UI.Edit(p, 200, { function() return name end, function(v) name = v end }, "Add to this group: name or ID", true)
    bx.addBtn = UI.Button(p, "+ Add", 60, function()
      local r = Rule(); if not r then return end
      local c = ns.Copy(ns.NEW_AURA); c.name = strtrim(bx.add:GetText() or ""); c.group = g
      table.insert(r.auras, c)
      ns.NormalizeGroups(r)
      name = ""; bx.add:SetText(""); bx.add:ClearFocus()
      ui.Refresh(); Changed()
    end)
    bx.addBtn.tip = "Add a condition to this group. Blank name = the spell itself."
    bx.add:SetScript("OnEnterPressed", function() bx.addBtn:Click() end)
    -- the AND / OR between this group and the one above (one setting for the whole rule)
    bx.join = UI.Toggle(p, 64, { { "and", "AND" }, { "or", "OR" } },
      { function() local r = Rule(); return r and r.join or "and" end, function(v) local r = Rule(); if r then r.join = v end end },
      function() ui.Refresh(); Changed() end, "How groups combine: AND = every group must hold, OR = any one group is enough.")
    bx.joinNote = UI.Note(p, "")
    bx.joinNote:SetPoint("LEFT", bx.join, "RIGHT", 8, 0)
    bx.parts = { bx, bx.mode, bx.add, bx.addBtn, bx.join, bx.joinNote }
    return bx
  end

  -- place everything top to bottom; the aura list is as long as it needs to be
  e.Layout = function()
    local r = Rule()
    local y = -44
    local function place(w, x, dy) w:ClearAllPoints(); w:SetPoint("TOPLEFT", p, "TOPLEFT", x, y); y = y - dy end
    place(e.secSpell, 0, 30)
    e.spell:ClearAllPoints(); e.spell:SetPoint("TOPLEFT", p, "TOPLEFT", EDIT, y)
    e.spellNote:ClearAllPoints(); e.spellNote:SetPoint("LEFT", e.spell, "RIGHT", 12, 0)
    y = y - 36
    place(e.secAuras, 0, 30)
    place(e.cdmNote, 0, (e.cdmNote:GetStringHeight() or 24) + 10)
    local n = r and #r.auras or 0
    e.none:SetShown(n == 0)
    if n == 0 then place(e.none, 0, 24) end
    local ngroups = 0
    for _, a in ipairs(r and r.auras or {}) do ngroups = math.max(ngroups, a.group or 1) end
    local i = 1
    for g = 1, ngroups do
      local bx = e.boxes[g] or Box(g)
      e.boxes[g] = bx
      for _, w in ipairs(bx.parts) do w:Show() end
      -- AND / OR between groups
      if g > 1 then
        bx.join.Refresh()
        bx.join:ClearAllPoints(); bx.join:SetPoint("TOPLEFT", p, "TOPLEFT", 12, y - 2)
        bx.joinNote:SetText(r.join == "or" and "any one group is enough" or "every group must hold")
        y = y - 30
      else
        bx.join:Hide(); bx.joinNote:Hide()
      end
      local top = y
      bx:ClearAllPoints(); bx:SetPoint("TOPLEFT", p, "TOPLEFT", 0, top); bx:SetWidth(EW)
      bx.mode.Refresh()
      y = y - 34
      while i <= n and (r.auras[i].group or 1) == g do
        local row = e.rows[i] or Row(i)
        e.rows[i] = row
        row:Show(); row.Refresh()
        row:SetFrameLevel(bx:GetFrameLevel() + 2)
        place(row, 12, row:GetHeight() + 4)
        i = i + 1
      end
      bx.add:ClearAllPoints(); bx.add:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + EDIT, y - 2)
      bx.addBtn:ClearAllPoints(); bx.addBtn:SetPoint("LEFT", bx.add, "RIGHT", 6, 0)
      bx.add.Refresh()
      y = y - 34
      bx:SetHeight(top - y)
      y = y - 8
    end
    for k = n + 1, #e.rows do e.rows[k]:Hide() end
    for g = ngroups + 1, #e.boxes do for _, w in ipairs(e.boxes[g].parts) do w:Hide() end end
    e.newGroupBox:ClearAllPoints(); e.newGroupBox:SetPoint("TOPLEFT", p, "TOPLEFT", EDIT, y - 2)
    e.newGroup:ClearAllPoints(); e.newGroup:SetPoint("LEFT", e.newGroupBox, "RIGHT", 6, 0)
    y = y - 40
    place(e.secOther, 0, 30)
    for i, cb in ipairs(e.checks) do
      cb:ClearAllPoints()
      cb:SetPoint("TOPLEFT", p, "TOPLEFT", (i % 2 == 1) and 0 or 300, y - math.floor((i - 1) / 2) * 28)
    end
    y = y - 3 * 28 - 12
    -- "Use for all rules" sits at the right end of the Look heading
    e.lookAll:ClearAllPoints(); e.lookAll:SetPoint("TOPRIGHT", p, "TOPLEFT", EW, y + 2)
    place(e.secLook, 0, 30)
    local function pair(lbl, w, x) lbl:ClearAllPoints(); lbl:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 4)
      w:ClearAllPoints(); w:SetPoint("TOPLEFT", p, "TOPLEFT", x + 110, y) end
    pair(e.lColorL, e.color, 0)
    e.lookTest:ClearAllPoints(); e.lookTest:SetPoint("TOPLEFT", p, "TOPLEFT", 300, y)
    y = y - 28
    pair(e.lStyleL, e.style, 0); pair(e.lMotionL, e.motion, 300)
    y = y - 28
    pair(e.lSizeL, e.size, 0); pair(e.lAlphaL, e.alpha, 300)
    local eui = ns.HasEllesmere()
    e.lGlowL:SetShown(eui and Rule() ~= nil); e.glowType:SetShown(eui and Rule() ~= nil)
    if eui then y = y - 28; pair(e.lGlowL, e.glowType, 0) end
    y = y - 40
    place(e.secStatus, 0, 30)
    place(e.status, 0, 0)
    p:SetHeight(-y + (e.status:GetStringHeight() or 40) + 20)
  end

  e.Refresh = function()
    local r = Rule()
    local shown = r ~= nil
    for _, w in ipairs({ e.icon, e.enabled, e.secSpell, e.spell, e.spellNote, e.secAuras, e.cdmNote, e.newGroupBox, e.newGroup,
      e.secOther, e.secLook, e.secStatus, e.status }) do w:SetShown(shown) end
    for _, w in ipairs(e.lookParts) do w:SetShown(shown) end
    for _, cb in ipairs(e.checks) do cb:SetShown(shown) end
    if not r then
      e.title:SetText("Add a rule to start")
      for _, row in ipairs(e.rows) do row:Hide() end
      for _, bx in pairs(e.boxes) do for _, w in ipairs(bx.parts) do w:Hide() end end
      e.none:Hide()
      return
    end
    local name = ns.RuleSpellName(r)
    e.title:SetText(name and ns.RuleLabel(r) or "New rule") -- (with its #place when several rules glow one spell)
    e.icon:SetTexture(name and ns.SpellIcon(name) or "Interface\\Icons\\INV_Misc_QuestionMark")
    e.enabled.Refresh(); e.RefreshLook(); e.spell.Refresh(); e.newGroupBox.Refresh()
    for _, cb in ipairs(e.checks) do cb.Refresh() end
    e.Layout()
  end

  -- live status: glowing or not and why, buttons, how each aura is read right now
  local HOW = { aura = "read directly", exact = "read directly", hidden = "seen (details hidden)",
    cdm = "from the Cooldown Manager", estimate = "estimate", unknown = "in combat" }
  e.UpdateStatus = function()
    local r = Rule()
    if not r then return end
    ns.Glow.NewPass()
    local name = ns.RuleSpellName(r)
    if not name then e.status:SetText("|cffff6060Type a spell or item: name or ID.|r"); return end
    local lines = {}
    lines[#lines + 1] = ResultLine(ns.Glow.Evaluate(r))
    local nb = ns.Glow.CountButtons(r)
    lines[#lines + 1] = nb > 0 and format("On your action bars: %d button%s", nb, nb == 1 and "" or "s")
      or "|cffff6060Not on any shown action bar.|r"
    for _, a in ipairs(r.auras) do
      local an = ns.AuraName(r, a)
      if a.kind == "rule" then
        local other = ns.RuleById(a.rule)
        if other then
          local st2, why2 = ns.Glow.Evaluate(other)
          lines[#lines + 1] = format("Rule %s: %s", ns.RuleLabel(other),
            st2 == Res.GATED and "|cffffd200active when the game says so (hidden values)|r"
            or st2 == Res.TRUE and "|cff60ff60active|r"
            or (st2 == Res.UNKNOWN or st2 == Res.ERROR) and format("|cffffd200can't tell|r (%s)", why2 or "?")
            or "not active")
        end
      elseif ns.State.POWER[a.kind] then
        local p = ns.State.POWER[a.kind]
        local v, why = ns.State.PowerAmount(a.kind)
        local now = v and tostring(v)
          or (why == "stale" and "|cffffd200unknown since you changed target|r")
          or "|cffffd200hidden: the game decides|r"
        local cond = format("%s %d", ns.State.OPS[ns.State.Op(a)], tonumber(a.pct) or (a.kind == "combo" and 5 or 50))
        lines[#lines + 1] = format("Your %s: %s (glows at %s)", p.label, now, cond)
      elseif a.kind == "health" or a.kind == "mana" then
        local unit = a.unit == "target" and "target" or "player"
        local v, why
        if a.kind == "health" then v, why = ns.State.HealthPct(unit) else v, why = ns.State.ManaPct(unit) end
        local who = (unit == "target" and "Your target's " or "Your ") .. a.kind
        local now = v and format("%d%%", math.floor(v + 0.5))
          or (why == "none" and "no target") or (why == "nomana" and "no mana")
          or "|cffffd200hidden: the game decides|r"
        lines[#lines + 1] = format("%s: %s (glows at %s %d%%)", who, now, ns.State.OPS[ns.State.Op(a)], tonumber(a.pct) or 40)
      elseif an and a.kind == "instant" then
        local ct = ns.State.CastTime(an)
        lines[#lines + 1] = format("%s: %s", an, ct == nil and "|cffffd200cast time hidden|r"
          or (ct <= 0 and "|cff60ff60instant now|r" or format("%.1f s cast", ct / 1000)))
      elseif an then
        local selfOnly = (a.name or "") == "" or a.name == name
        local has, how, detail = ns.State.AuraPresent(a, an, selfOnly)
        local where = a.unit == "target" and "your target" or "you"
        local state = has == nil and "|cffffd200can't tell|r" or (has and "on " .. where or "not on " .. where)
        local src = HOW[how] or how or "?"
        if detail then src = src .. ": " .. detail end
        local cdm = ns.State.Tracked(an) and "|cff60ff60tracked|r" or "|cffff6060not tracked|r"
        lines[#lines + 1] = format("%s: %s (%s), Cooldown Manager: %s", an, state, src, cdm)
      end
    end
    e.status:SetText(table.concat(lines, "\n"))
    e.Layout()
  end
  return e
end

---------------------------------------------------------------------------
-- Rules list
---------------------------------------------------------------------------
local rows = {}
local function BuildList(p, top)
  local l = {}
  l.box = CreateFrame("Frame", nil, p, "BackdropTemplate")
  l.box:SetPoint("TOPLEFT", 7, top); l.box:SetSize(LIST_W, 380)
  l.box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  l.box:SetBackdropColor(0, 0, 0, 0.3); l.box:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.8)
  local scroll = CreateFrame("ScrollFrame", nil, l.box, "ScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(LIST_W - 32, 1)
  scroll:SetScrollChild(content)
  l.content, l.scroll = content, scroll

  -- the buttons, in a column right of the list
  local X = LIST_W + 24
  local function Added(r)
    if ns.char then ns.char.fresh = nil end -- (you're making this character's rules yourself)
    table.insert(ns.db.rules, r)
    selected = #ns.db.rules; ui.Refresh(); Changed()
    ns.OpenRuleEditor()
  end
  l.add = UI.Button(p, "+ Add rule", 170, function() Added(ns.NewRule()) end)
  l.add:SetPoint("TOPLEFT", X, top)
  l.edit = UI.Button(p, "Edit rule", 170, function() ns.OpenRuleEditor() end)
  l.edit.tip = "Open the selected rule (or click it twice)."
  l.edit:SetPoint("TOPLEFT", l.add, "BOTTOMLEFT", 0, -6)
  -- a copy of this rule, and its place (priority: when several rules glow one spell, the higher one
  -- wins: its look, and it's checked first)
  l.dup = UI.Button(p, "Duplicate", 170, function()
    local i = ns.DuplicateRule(selected)
    if i then selected = i; ui.Refresh(); Changed() end
  end)
  l.dup.tip = "Add a copy of this rule right below it."
  l.dup:SetPoint("TOPLEFT", l.edit, "BOTTOMLEFT", 0, -6)
  l.up = UI.Button(p, "Up", 83, function() selected = ns.MoveRule(selected, -1); ui.Refresh(); Changed() end)
  l.up.tip = "Move this rule up. When several rules glow one spell, the higher one comes first (its look wins)."
  l.up:SetPoint("TOPLEFT", l.dup, "BOTTOMLEFT", 0, -6)
  l.down = UI.Button(p, "Down", 83, function() selected = ns.MoveRule(selected, 1); ui.Refresh(); Changed() end)
  l.down.tip = l.up.tip:gsub("^Move this rule up", "Move this rule down")
  l.down:SetPoint("LEFT", l.up, "RIGHT", 4, 0)
  l.remove = UI.Button(p, "Remove", 170, function()
    if ns.db.rules[selected] then
      table.remove(ns.db.rules, selected)
      selected = math.max(1, math.min(selected, #ns.db.rules)); ui.Refresh(); Changed()
    end
  end)
  l.remove:SetPoint("TOPLEFT", l.up, "BOTTOMLEFT", 0, -6)
  -- a new rule from a template
  local tplOpts, tpl = {}, ns.TEMPLATES[1][1]
  for _, t in ipairs(ns.TEMPLATES) do tplOpts[#tplOpts + 1] = { t[1], t[2] } end
  local tl = UI.Font(p, "GameFontNormal", "From a template")
  tl:SetPoint("TOPLEFT", l.remove, "BOTTOMLEFT", 0, -20)
  l.tpl = UI.Toggle(p, 130, tplOpts, { function() return tpl end, function(v) tpl = v end }, nil,
    "Start a rule from a pattern: click to step through them (right-click to go back), then + to add it and type the spell.")
  l.tpl:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, -6)
  l.tplAdd = UI.Button(p, "+", 36, function() Added(ns.NewRule(tpl)) end)
  l.tplAdd.tip = "Add a rule from this template."
  l.tplAdd:SetPoint("LEFT", l.tpl, "RIGHT", 4, 0)
  l.share = UI.Button(p, "Share rules...", 170, function() ns.OpenShare() end)
  l.share.tip = "Export rules as text to paste into another game, or import rules someone sent you."
  l.share:SetPoint("TOPLEFT", l.tpl, "BOTTOMLEFT", 0, -20)

  local function paintRow(row, i, r)
    local on = (i == selected)
    row.text:SetFontObject(on and "GameFontHighlight" or (r.enabled and "GameFontNormal" or "GameFontDisable"))
    row.sel:SetShown(on or row.hover)
    if on or row.hover then row.sel:SetAtlas(on and "Options_List_Active" or "Options_List_Hover") end
  end
  l.Refresh = function()
    for i, r in ipairs(ns.db.rules) do
      local row = rows[i]
      if not row then
        row = CreateFrame("Button", nil, content)
        row:SetSize(LIST_W - 32, 26)
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(20, 20); row.icon:SetPoint("LEFT", 6, 0)
        -- its live status: a dot (see l.RefreshStatus)
        row.dot = row:CreateTexture(nil, "ARTWORK"); row.dot:SetSize(8, 8); row.dot:SetPoint("RIGHT", -6, 0)
        row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.text = UI.Font(row, "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0); row.text:SetPoint("RIGHT", row.dot, "LEFT", -4, 0); row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
          self.hover = true; paintRow(self, self.i, ns.db.rules[self.i] or {})
          if self.why then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.why, 1, 1, 1, 1, true); GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", function(self) self.hover = false; paintRow(self, self.i, ns.db.rules[self.i] or {}); GameTooltip:Hide() end)
        row:SetScript("OnDoubleClick", function() ns.OpenRuleEditor() end)
        rows[i] = row
      end
      row.i = i
      row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
      local name = ns.RuleSpellName(r)
      row.icon:SetTexture(name and ns.SpellIcon(name) or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.icon:SetDesaturated(not r.enabled)
      row.text:SetText(ns.RuleLabel(r)) -- (as the Rule rows name it: "Lightning Bolt (#3)")
      paintRow(row, i, r)
      row:SetScript("OnClick", function() selected = i; ui.Refresh() end)
      row:Show()
    end
    for i = #ns.db.rules + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #ns.db.rules * 26))
    local has = ns.db.rules[selected] ~= nil
    l.remove.SetActive(has); l.dup.SetActive(has); l.edit.SetActive(has)
    l.up.SetActive(selected > 1 and has); l.down.SetActive(selected < #ns.db.rules)
    l.tpl.Refresh()
    l.RefreshStatus()
  end
  -- each rule's live status, as a dot: green glowing, yellow the game decides, orange can't tell,
  -- red error, none when it doesn't hold (or is off); its line on hover
  l.RefreshStatus = function()
    ns.Glow.NewPass()
    for i, r in ipairs(ns.db.rules) do
      local row = rows[i]
      if row then
        local st, why, set = ns.Glow.Evaluate(r)
        local c = STATUS_DOT[st]
        row.dot:SetShown(r.enabled and c ~= nil)
        if c then row.dot:SetVertexColor(c[1], c[2], c[3]) end
        row.why = r.enabled and ResultLine(st, why, set) or "Off"
      end
    end
  end
  return l
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local list, editor, editWin
local function PageRules(p, R)
  R:Section("Your rules")
  R:Note("Each rule glows a spell or item on your action bars while its conditions hold. Click a rule to select it; Edit rule (or a double-click) opens it in its own window. The dot: green glowing, yellow the game decides, orange can't tell, red an error.")
  list = BuildList(p, R:Space(390))
  ui = { Refresh = function()
      list.Refresh()
      if editor and editWin:IsShown() then
        if not Rule() then editWin:Hide(); return end -- (its rule was removed)
        editor.Refresh(); editor.UpdateStatus()
        local r = Rule(); editWin:SetTitle(r and ("Edit Rule: " .. ns.RuleLabel(r)) or "Edit Rule")
      end
    end,
    Status = function() list.RefreshStatus(); if editor and editWin:IsShown() then editor.UpdateStatus() end end }
end

-- The rule editor: its own window over the settings, for the rule selected in the list
local function BuildEditWindow()
  editWin = UI.Window("ProcThisRuleEditor", EW + 70, 640, "Edit Rule")
  local scroll = CreateFrame("ScrollFrame", nil, editWin, "ScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -34); scroll:SetPoint("BOTTOMRIGHT", -34, 48)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(EW, 1)
  scroll:SetScrollChild(content)
  editor = BuildEditor(content)
  local close = UI.Button(editWin, CLOSE or "Close", 96, function() editWin:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -16, 14)
  local t = 0
  editWin:SetScript("OnUpdate", function(_, dt) t = t + dt; if t > 0.5 then t = 0; editor.UpdateStatus() end end)
  editWin:Hide()
end
function ns.OpenRuleEditor()
  if not ns.db.rules[selected] then return end
  if not editWin then BuildEditWindow() end
  if win then ns.Suite.Place(editWin, win) end
  editWin:Show(); editWin:Raise()
  ui.Refresh()
end

local function PageSettings(_, R)
  local function S(key) return { function() return ns.db[key] end, function(v) ns.db[key] = v end } end
  R:Section("Timing")
  R:Slider("A melee hit on me counts for", 1, 10, 1, S("meleeWindow"), function(v) return v .. " s" end, Changed,
    "Used by the \"Being attacked in melee\" condition.")
  R:Section("Other UIs")
  local eui = R:Row("EllesmereUI", "Found and used on its own: no settings.")
  UI.Note(eui, ns.HasEllesmere() and "In use: glows on its bars, and its glow styles in each rule's Look." or "Not installed."):SetPoint("LEFT", R.ctrl, 0)
  R:Note("Each rule's glow (colour, start, pulse, size, intensity) is set in its Look section, in the rule's own window (Rules, Edit rule).")
  -- rules are per character: copy another character's into this one
  R:Section("Rules on other characters")
  local here = R:Note("")
  local others, pick = {}, nil
  local from, row = R:Toggle("Copy from", 260, others, { function() return pick end, function(v) pick = v end }, nil,
    "Which character's rules to copy.")
  local copy = UI.Button(row, "Copy to this character", 170, function()
    local src = pick and ns.RulesOf(pick)
    if not src then return end
    local n = ns.AddRuleCopies(src)
    ns.Print(format("copied %d rule%s from %s.", n, n == 1 and "" or "s", pick == "*shared" and "the shared list" or pick))
    if ui then ui.Refresh() end
    Changed(); from.Refresh()
  end)
  copy:SetPoint("LEFT", from, "RIGHT", 8, 0)
  R:Note("Copies are added to this character's rules (nothing is replaced); remove the ones you don't need under Rules.")
  local r0 = from.Refresh
  from.Refresh = function()
    wipe(others)
    for _, o in ipairs(ns.OtherCharacters()) do others[#others + 1] = { o[1], o[2] } end
    local valid = false
    for _, o in ipairs(others) do if o[1] == pick then valid = true end end
    if not valid then pick = others[1] and others[1][1] or nil end
    if #others == 0 then others[1] = { nil, "(no other character has rules yet)" } end
    here:SetText(format("Rules on %s: %d", ns.CharKey(), #ns.db.rules))
    r0()
    copy:SetEnabled(pick ~= nil)
  end
end

local function PageHelp(p, R)
  local function para(t, note)
    local fs = note and UI.Note(p, t, 600) or UI.Font(p, "GameFontHighlight", t)
    fs:SetWidth(600); fs:SetPoint("TOPLEFT", 7, R.y)
    R:Space((fs:GetStringHeight() or 14) + 10)
  end
  R:Section("How rules work")
  para("A rule glows a spell on your action bars while ALL of its conditions hold. Add as many buffs and debuffs as you like: " ..
    "each one says who has it (you or your target), whether it's a buff or a debuff, and whether it must be active or missing.")
  para("Example: Lightning Bolt glows while Stormstrike is on your target, Maelstrom Weapon is on you, " ..
    "and Flame Shock is on your target.", true)
  para("Items work too: put a trinket, potion or any usable item in the spell box (type its name or ID, or drag it from your bags) and it glows on your action bars, as itself or in a macro that /use-s it. For an item, \"Off cooldown\" is the item's own cooldown and \"Castable\" means you have it and can use it now.", true)
  R:Section("The Cooldown Manager is required in combat")
  para("In combat, the game hides buffs and debuffs from addons. Proc This! follows them through Blizzard's Cooldown Manager instead, " ..
    "so turn it on and add every buff and debuff your rules use to its Tracked Buffs or Tracked Bars. " ..
    "A green dot next to a condition means it's tracked; red means the rule can't see it in combat and won't glow.")
  para("The Cooldown Manager only tracks your own spells' auras. Auras that other players put on you or your target " ..
    "(for example another player's curse) can only be checked out of combat.", true)
  local cdm = UI.Font(p, "GameFontHighlight", ""); cdm:SetPoint("TOPLEFT", 7, R.y); R:Space(26)
  R:Track({ Refresh = function()
    local on = GetCVarBool and GetCVarBool("cooldownViewerEnabled")
    cdm:SetText(on and "|cff60ff60Cooldown Manager: on|r" or "|cffff6060Cooldown Manager: off. Turn it on in Options > Gameplay Enhancements.|r")
  end })
  R:Section("Conditions")
  para("Every condition reads the same way, left to right: what kind, on whom, what, and its state. [Debuff] [Target] [Stormstrike] [Active]: glows while your Stormstrike debuff is on your target. [Rule] [Lightning Bolt] [Inactive]: while your Lightning Bolt rule isn't active. Click any part to switch it.", true)
  para("Groups: each group needs all of its rows, or any one of them (its switch). Groups are joined by AND (every group) or OR (any group). " ..
    "Example: Group 1 (Any of these): Buff X, Buff Y  AND  Group 2 (All of these): Debuff Z, Debuff Y.", true)
  para("Rule rows: another of your rules is active (its conditions are met right now) or isn't. Example: Earth Shock glows while your Flame Shock rule is inactive. A rule can't depend on itself, and rules that depend on each other in a loop never glow.", true)
  para("Health and Mana rows: yours or your target's, compared with a %: > (more than), >= (at least), < (less than), <= (at most) or = (exactly). Example: Healing Wave glows while your target's health is < 40%; Evocation while your mana is < 20%. When the game hides the value (health in combat, your mana always), the game itself checks it against your % and switches the glow: Proc This! never sees the number. A dead target, or one without mana, never counts.", true)
  para("Combo Points, Rage and Energy rows: yours, compared with an amount the same way. Example: Eviscerate glows while your combo points are >= 5, or = 3; Sinister Strike while your energy is >= 45. Combo points are always readable; when the game hides rage or energy (in combat), the game itself checks them.", true)
  para("Instant Cast rows: the spell is instant cast right now, from its cast time (readable in combat). Covers Maelstrom Weapon at 5 stacks, Nature's Swiftness, Presence of Mind, Shadow Trance and the like. Example: Lightning Bolt glows while Lightning Bolt is instant. /pt spell <spell> shows a spell's cast time.", true)
  para("Rules are kept per character: each character has its own list. Settings > Rules on other characters copies another character's rules into this one.", true)
  R:Section("Commands")
  para("/pt (or /proc, /procthis): this window.  /pt test: every rule's glow for 3 seconds.  " ..
    "/pt auras: the buffs and debuffs on you and your target with their spell IDs (out of combat).  " ..
    "/pt spell <spell>: its cast time, how long it lasts, charges.  /pt buttons: what each macro button reads as now.  " ..
    "/pt power: what's readable of your power.  /pt perf: how long glow updates take.  /pt api: which game functions this client has.  " ..
    "/pt debug: print each rule's status changes.  /pt report: bugs & feedback.")
end

local function BuildWindow()
  win = UI.Settings({ name = "ProcThisWindow", title = "Proc This!",
    bug = function() ns.ShowBugReport() end,
    pages = {
      { "Rules", "Your rules: add, order, edit, share.", PageRules },
      { "Settings", "Timing, other UIs, and rules on your other characters.", PageSettings },
      { "Help", "How rules work, the Cooldown Manager, and the commands.", PageHelp },
    },
    categories = { { "Proc This!", { 1, 2 } }, { "Help", { 3 } } } })
  win:HookScript("OnHide", function() if editWin then editWin:Hide() end end)
  win:HookScript("OnShow", function() ui.Refresh() end)
  local t = 0
  win:SetScript("OnUpdate", function(_, dt) t = t + dt; if t > 0.5 then t = 0; ui.Status() end end)
end

-- Share rules: export as text (this rule with the rules it uses, or all) or import text someone
-- sent (Share.lua checks every field; nothing in it is run)
local share
-- fill: text to put in the box at once, with its note
function ns.OpenShare(fill, note)
  if not share then
    share = UI.Popup("ProcThisShare", 580, 200, "Share rules")
    local text = ""
    local box = UI.Edit(share, 540, { function() return text end, function(v) text = v end }, "Paste rules text here to import")
    box:SetMaxLetters(0)
    box:SetPoint("TOPLEFT", 22, -44)
    local msg = UI.Note(share, "", 540); msg:SetPoint("TOPLEFT", 20, -76)
    local function Show(str, why)
      text = str; box:SetText(str); box:SetFocus(); box:HighlightText()
      msg:SetText(why or "Copied into the box: press Ctrl+C to copy it, then paste it where you like.")
    end
    share.Fill, share.box = Show, box
    local one = UI.Button(share, "Export this rule", 140, function()
      local r = ns.db.rules[selected]
      if r then Show(ns.Share.Export(ns.db.rules, r)) end
    end)
    one.tip = "The rule selected in the list, with any rules it uses (its Rule rows)."
    one:SetPoint("BOTTOMLEFT", 18, 16)
    local all = UI.Button(share, "Export all rules", 140, function() Show(ns.Share.Export(ns.db.rules)) end)
    all:SetPoint("LEFT", one, "RIGHT", 6, 0)
    local imp = UI.Button(share, "Import", 110, function()
      local rules, err = ns.Share.Import(box:GetText())
      if not rules then msg:SetText("|cffff6060Can't import: " .. err .. ".|r"); return end
      local n = ns.AddRuleCopies(rules)
      selected = #ns.db.rules - n + 1
      msg:SetText(format("|cff60ff60Added %d rule%s|r to this character's list.", n, n == 1 and "" or "s"))
      if ui then ui.Refresh() end
      Changed()
    end)
    imp.tip = "Add the rules in the box to this character's list (nothing is replaced)."
    imp:SetPoint("LEFT", all, "RIGHT", 6, 0)
    local close = UI.Button(share, CLOSE or "Close", 96, function() share:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 16)
    share.Reset = function()
      text = ""; box:SetText("")
      msg:SetText("Export rules to share them, or paste rules text and Import.")
    end
  end
  share.Reset()
  share:Show()
  if fill then share.Fill(fill, note) end
end

-- /pt report: what a bug report needs, as one text to copy: the version and client, what the game
-- lets Proc This! see right now, the buttons, the speed, each rule's status, the last errors
-- caught, and the rules themselves (as Share text)
local function Report()
  local L = {}
  local function add(...) L[#L + 1] = format(...) end
  local okV, version = ns.API.Call("AddOnMetadata", ns.name, "Version")
  local okB, build, number, _, toc = ns.API.Call("BuildInfo")
  add("Proc This! %s; client %s (%s), interface %s", okV and tostring(version) or "?",
    okB and tostring(build) or "?", okB and tostring(number) or "?", okB and tostring(toc) or "?")
  local _, class = UnitClass("player")
  add("%s, %s; in combat: %s; auras hidden now: %s; Cooldown Manager: %s", ns.CharKey(), tostring(class),
    InCombatLockdown() and "yes" or "no", ns.State.AurasLocked() and "yes" or "no",
    (GetCVarBool and GetCVarBool("cooldownViewerEnabled")) and "on" or "off")
  add("%s", ns.Buttons.Report())
  local missing = {}
  for _, l in ipairs(ns.API.Report()) do if l:find("not on this client", 1, true) then missing[#missing + 1] = l:match("^(%w+)") end end
  add("game functions: %s", #missing == 0 and "all present" or ("missing " .. table.concat(missing, ", ")))
  ns.Glow.NewPass()
  for i, r in ipairs(ns.db.rules) do
    local st, why = ns.Glow.Evaluate(r)
    add("rule %d %s: %s%s%s", i, ns.RuleLabel(r), r.enabled and st or "off", why and (" - " .. why) or "",
      ns.Glow.CountButtons(r) > 0 and "" or " (not on a shown button)")
  end
  if #ns.Glow.errors == 0 then add("errors caught: none") end
  for _, e in ipairs(ns.Glow.errors) do add("error (%s, x%d, %.0f s ago): %s", e.where, e.n, GetTime() - e.at, e.msg) end
  add("rules: %s", ns.Share.Export(ns.db.rules))
  -- one line for the box, " // " between parts (the window doubles any |)
  local on = 0
  for _, r in ipairs(ns.db.rules) do if r.enabled then on = on + 1 end end
  return table.concat(L, " // "), {
    { "Interface\\Icons\\Spell_Nature_LightningShield", "Rules", format("%d (%d on)", #ns.db.rules, on) },
    { "Interface\\Icons\\INV_Misc_Note_01", "Errors caught", #ns.Glow.errors },
    { "Interface\\Icons\\INV_Misc_PocketWatch_01", "Cooldown Manager", (GetCVarBool and GetCVarBool("cooldownViewerEnabled")) and "on" or "off" },
    { "Interface\\Icons\\Spell_Shadow_DetectInvisibility", "Auras hidden now", ns.State.AurasLocked() and "yes" or "no" },
  }
end
local BUG = { name = "ProcThisReportWindow", title = "Proc This! Bugs & Feedback",
  repo = "https://github.com/califaxop/Proc-This-Custom-Procs/issues/new",
  included = "Included: Proc This!'s version, the game client, your class, what the game lets it see, your action buttons' spells, each rule's status, the errors caught and your rules. Never: your name, realm, guild or other players.",
  build = Report }
function ns.ShowBugReport(kind)
  local okV, version = ns.API.Call("AddOnMetadata", ns.name, "Version")
  BUG.version = okV and version or nil
  return UI.ShowBugReport(BUG, kind)
end

-- the settings window, built the first time it's asked for
local function GetWindow()
  if not win then
    local ok, e = pcall(BuildWindow)
    if not ok then if win then win:Hide() end; win = nil; ns.Print("settings failed: " .. tostring(e)); return end
  end
  return win
end
function ns.OpenOptions()
  local w = GetWindow()
  if w then UI.ToggleWindow(w) end
  return w
end
UI.JoinSuite("Proc This!", "Custom procs: glow any spell when your conditions are met.",
  "Interface\\AddOns\\ProcThis\\media\\Logo", 2, GetWindow)

---------------------------------------------------------------------------
-- Start-up and slash commands
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ns.name then
    ns.LoadDB()
  elseif event == "PLAYER_LOGIN" then
    -- a character's first login: its rules from the old shared list (once its spellbook is in)
    local okS, eS = pcall(ns.SetUpCharacter, false)
    if not okS then ns.Print("start-up error: " .. tostring(eS)) end
    if ns.char and ns.char.fresh then
      local sc = CreateFrame("Frame")
      sc:RegisterEvent("SPELLS_CHANGED")
      sc:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        pcall(ns.SetUpCharacter, true)
        if ns.Glow.Update then pcall(ns.Glow.Update) end
        if ui and win and win:IsShown() then ui.Refresh() end
      end)
    end
    local ok, e = pcall(ns.Glow.Init)
    if not ok then ns.Print("start-up error: " .. tostring(e)) end
    -- say once when another UI is found and its mode turned on
    ns.db.seenUI = ns.db.seenUI or {}
    if ns.HasEllesmere() and not ns.db.seenUI.eui then
      ns.db.seenUI.eui = true
      ns.Print("EllesmereUI found: Proc This! glows on its bars, and its glow styles are in each rule's Look.")
    end
    -- Esc > Options > AddOns: a button that opens the window
    pcall(function()
      if Settings and Settings.RegisterCanvasLayoutCategory then
        local p = CreateFrame("Frame"); p.name = "Proc This!"
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(180, 22); b:SetText("Open Proc This!"); b:SetPoint("TOPLEFT", 16, -16)
        b:SetScript("OnClick", function()
          if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true) end
          if not (win and win:IsShown()) then ns.OpenOptions() end
        end)
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(p, p.name))
      end
    end)
    ns.Print("loaded. Type |cffffff00/pt|r to set up your glows.")
  end
end)

SLASH_PROCTHIS1 = "/pt"
SLASH_PROCTHIS2 = "/proc"
SLASH_PROCTHIS3 = "/procthis"
SLASH_PROCTHIS4 = "/sglow" -- the old commands still work
SLASH_PROCTHIS5 = "/spellglow"
-- /pt auras: your target's debuffs and buffs and your own buffs and debuffs, with spell IDs
-- (only out of combat: in combat the game won't show them to addons)
local function ListAuras()
  if ns.State.AurasLocked() then
    ns.Print("auras are hidden right now (combat). Step away, wait a few seconds and try again.")
    return
  end
  local any = false
  for _, s in ipairs({ { "target", "HARMFUL", "Target debuff" }, { "target", "HELPFUL", "Target buff" },
                       { "player", "HELPFUL", "Your buff" }, { "player", "HARMFUL", "Your debuff" } }) do
    for i = 1, 40 do
      local ok, a = ns.API.Call("AuraByIndex", s[1], i, s[2])
      if not ok or not a then break end
      if ns.Readable(a.name) then
        any = true
        print(format("|cffffd200%s:|r %s  |cff999999(ID %s)|r", s[3], a.name, tostring(a.spellId)))
      end
    end
  end
  if not any then ns.Print("no auras found on you or your target.") end
end

-- /pt spell <spell> (or /pt cast): what Proc This! knows of it right now: its cast time (0 =
-- instant, as Instant rows read it), how long its buff or debuff lasts (learned from reads, or from
-- its tooltip) and whether it has charges
local function ShowSpell(spell)
  spell = strtrim(spell or "")
  if spell == "" then spell = ns.SpellName(403) or "Lightning Bolt" end
  local ct = ns.State.CastTime(spell)
  local d, from = ns.State.Duration(spell)
  ns.Print(format("%s%s: %s; lasts %s%s", spell, InCombatLockdown() and " (in combat)" or "",
    ct == nil and "cast time hidden or unknown" or (ct <= 0 and "instant" or format("%d ms cast", ct)),
    d and format("%d s (%s)", d, from == "tooltip" and "from its tooltip" or "seen") or "unknown (not seen yet, none in its tooltip)",
    ns.State.Charged(spell) and "; has charges" or ""))
end

SlashCmdList.PROCTHIS = function(msg)
  local spellArg = (msg or ""):match("^%s*[Cc][Aa][Ss][Tt]%s*(.*)$") or (msg or ""):match("^%s*[Ss][Pp][Ee][Ll][Ll]%s*(.*)$")
  if spellArg then ShowSpell(spellArg); return end
  if (msg or ""):lower():match("^api") then for _, l in ipairs(ns.API.Report()) do ns.Print(l) end return end
  if (msg or ""):lower():match("^button") then for _, l in ipairs(ns.Glow.ButtonReport()) do ns.Print(l) end return end
  if (msg or ""):lower():match("^debug") then
    ns.Glow.debug = not ns.Glow.debug
    ns.Print("debug " .. (ns.Glow.debug and "on: each rule's status change is printed here (/pt debug again to stop)." or "off."))
    return
  end
  if (msg or ""):lower():match("^report") then
    ns.ShowBugReport()
    return
  end
  if (msg or ""):lower():match("^perf") then for _, l in ipairs(ns.Glow.PerfReport()) do ns.Print(l) end return end
  if (msg or ""):lower():match("^test") then ns.Glow.Test(3); return end
  if (msg or ""):lower():match("^aura") then ListAuras(); return end
  if (msg or ""):lower():match("^power") then
    for _, l in ipairs(ns.State.PowerReport()) do ns.Print(l) end
    return
  end
  local ok, e = pcall(ns.OpenOptions)
  if not ok then ns.Print("settings error: " .. tostring(e)) end
end
