-- Proc This!: settings window (/pt, /proc or /procthis, or Esc > Options > AddOns > Proc This!) and start-up.
-- Drawn in the same style as XP Planner (see UI.lua): tabs for Rules, Look and Help.
local _, ns = ...
local UI = ns.UI

local function Changed() ns.Glow.Soon() end

local selected = 1
local win, ui
local function Rule() return ns.db.rules[selected] end
local function Field(tbl, key) return { function() local t = tbl(); return t and t[key] end, function(v) local t = tbl(); if t then t[key] = v end end } end

local LIST_W, EDIT_X, EDIT_W, PAGE_H = 196, 220, 486, 470

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
local EW = EDIT_W - 16 -- editor content width

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

local function BuildEditor(p)
  local e = { rows = {} }

  -- header: icon, rule name, enabled
  e.icon = p:CreateTexture(nil, "ARTWORK")
  e.icon:SetSize(26, 26); e.icon:SetPoint("TOPLEFT", 0, 0)
  e.title = UI.Text(p, "title", "")
  e.title:SetPoint("LEFT", e.icon, "RIGHT", 8, 0); e.title:SetWidth(EW - 140); e.title:SetWordWrap(false)
  e.enabled = UI.Check(p, "Enabled", Field(Rule, "enabled"), 90, function() ui.Refresh(); Changed() end)
  e.enabled:SetPoint("TOPRIGHT", p, "TOPLEFT", EW, -3)


  -- spell
  e.secSpell = UI.Section(p, "Spell or item to glow", EW)
  e.spell = UI.Edit(p, 230, { function() local r = Rule(); return r and r.spell end,
    function(v) local r = Rule(); if r then r.spell = v; ui.Refresh(); Changed() end end },
    "Name or ID", "items")
  e.spellNote = UI.Text(p, "note", "Every rank glows. Type it, or drag it from your spellbook or bags (trinkets, potions...).")
  e.spellNote:SetWidth(EW - 244)

  -- aura conditions, in groups
  e.secAuras = UI.Section(p, "Buffs, debuffs and health", EW)
  e.cdmNote = UI.Text(p, "note",
    "Conditions come in groups. Each group needs all of its rows, or any one of them; " ..
    "groups are joined by AND (every group) or OR (any group). In combat the game hides auras from addons: " ..
    "add each one to Blizzard's Cooldown Manager (Tracked Buffs or Bars). The dot shows if it's tracked.")
  e.cdmNote:SetWidth(EW)
  e.none = UI.Text(p, "note", "No buff or debuff conditions yet: start a group below.")
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
  e.secOther = UI.Section(p, "Other conditions", EW)
  e.checks = {}
  for i, c in ipairs(CHECKS) do
    e.checks[i] = UI.Check(p, c[2], Field(Rule, c[1]), 228, Changed)
  end

  -- this rule's look
  e.secLook = UI.Section(p, "Look", EW)
  e.lookParts = {}
  local function lookField(key) return { function() local r = Rule(); return r and r[key] or ns.NEW_RULE[key] end,
    function(v) local r = Rule(); if r then r[key] = v end end } end
  local function label(text) local t = UI.Text(p, "note", text); e.lookParts[#e.lookParts + 1] = t; return t end
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
  -- EllesmereUI mode: its glow styles too
  e.lGlowL = label("Glow")
  e.glowType = UI.Toggle(p, 140, ns.EUI_GLOWS, { function() local r = Rule(); return r and r.glowType or "blizzard" end,
    function(v) local r = Rule(); if r then r.glowType = v end end }, function() ns.Glow.Restyle(); ui.Refresh() end,
    "EllesmereUI mode: Proc This!'s glow, or one of EllesmereUI's (pixel lines, autocast shine, GCD ants...). Click to switch. " ..
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
  e.lookAll:SetHeight(18) -- slim, to sit on the Look heading above its line
  e.lookParts[#e.lookParts + 1] = e.lookAll
  e.RefreshLook = function()
    for _, w in ipairs({ e.color, e.style, e.motion, e.size, e.alpha, e.glowType }) do w.Refresh() end
    -- an EllesmereUI glow style has no start animation or size of ours
    local own = not (ns.EllesmereMode() and ns.EUIStyleIndex(Rule()))
    e.style.SetActive(own); e.size.SetActive(own)
  end

  -- status
  e.secStatus = UI.Section(p, "Current Rule Status", EW)
  e.status = UI.Text(p, "line", "")
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
    row.pctSign = UI.Text(row, "line", "%")
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
    row.mine = UI.Check(row, "Only mine", Field(A, "mine"), 92, refresh)
    row.mine:SetPoint("TOPLEFT", 10, -26)
    row.lasts = UI.Text(row, "note", "lasts")
    row.lasts:SetPoint("LEFT", row.mine, "RIGHT", 2, 0)
    row.dur = UI.Edit(row, 34, { function() local a = A(); return a and a.dur end,
      function(v) local a = A(); if a then a.dur = math.max(0, math.min(600, tonumber(v) or 0)); refresh() end end }, "", false, true)
    row.dur:SetPoint("LEFT", row.lasts, "RIGHT", 4, 0)
    row.after = UI.Text(row, "note", "s, used up after")
    row.after:SetPoint("LEFT", row.dur, "RIGHT", 4, 0)
    row.charges = UI.Edit(row, 28, { function() local a = A(); return a and a.charges end,
      function(v) local a = A(); if a then a.charges = math.max(0, math.min(20, math.floor(tonumber(v) or 0))); refresh() end end }, "", false, true)
    row.charges:SetPoint("LEFT", row.after, "RIGHT", 4, 0)
    row.casts = UI.Text(row, "note", "casts of")
    row.casts:SetPoint("LEFT", row.charges, "RIGHT", 4, 0)
    row.usedBy = UI.Edit(row, 92, { function() local a = A(); return a and a.usedBy end,
      function(v) local a = A(); if a then a.usedBy = v; refresh() end end }, "this spell", false)
    row.usedBy:SetPoint("LEFT", row.casts, "RIGHT", 4, 0)
    row.extra = { row.mine, row.lasts, row.dur, row.after, row.charges, row.casts, row.usedBy }
    for _, w in ipairs(row.extra) do
      if w.SetScript and w ~= row.mine and w ~= row.lasts and w ~= row.after and w ~= row.casts then end
    end
    row.dur.tip = "Backup when it isn't in the Cooldown Manager: how long it lasts after you cast it (0 = auto)."
    row.Refresh = function()
      local a = A()
      if not a then return end
      local r = Rule()
      local isRule = a.kind == "rule"
      -- the other rules to pick from (not this one)
      wipe(row.ruleOpts)
      for _, x in ipairs(ns.db.rules) do
        if x ~= r and x.id then row.ruleOpts[#row.ruleOpts + 1] = { x.id, ns.RuleLabel(x) } end
      end
      if #row.ruleOpts == 0 then row.ruleOpts[1] = { false, "(add another rule first)" } end
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
        if j == 1 then w:SetPoint("TOPLEFT", 0, 0) else w:SetPoint("LEFT", chain[j - 1], "RIGHT", (w == row.pctSign or chain[j - 1] == row.pctSign) and 4 or 6, 0) end
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
      row:SetHeight(tdebuff and 50 or 26)
    end
    return row
  end

  -- a group: a bordered box with its "All of these / Any of these" switch, its rows, and its own Add box
  e.boxes = {}
  local function Box(g)
    local bx = CreateFrame("Frame", nil, p, "BackdropTemplate")
    bx:SetFrameLevel(math.max(1, p:GetFrameLevel()))
    bx:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    UI.Skin(function(th) bx:SetBackdropColor(UI.RGB(th.box, 0.10)); bx:SetBackdropBorderColor(UI.RGB(th.accent, 0.55)) end)
    local function R() return Rule() end
    bx.title = UI.Text(bx, "value", "Group " .. g)
    bx.title:SetPoint("TOPLEFT", 10, -9)
    bx.mode = UI.Toggle(p, 210, { { "all", "All of these must hold" }, { "any", "Any one of these is enough" } },
      { function() local r = R(); return r and r.groupModes and r.groupModes[g] or "all" end,
        function(v) local r = R(); if r then r.groupModes = r.groupModes or {}; r.groupModes[g] = v end end },
      function() ui.Refresh(); Changed() end, "How the rows in this group combine. Click to switch.")
    bx.mode:SetPoint("LEFT", bx.title, "RIGHT", 10, 0)
    local name = ""
    bx.add = UI.Edit(p, 200, { function() return name end, function(v) name = v end }, "Add to this group: name or ID", true)
    bx.addBtn = UI.Button(p, "+ Add", 60, function()
      local r = R(); if not r then return end
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
      { function() local r = R(); return r and r.join or "and" end, function(v) local r = R(); if r then r.join = v end end },
      function() ui.Refresh(); Changed() end, "How groups combine: AND = every group must hold, OR = any one group is enough.")
    bx.joinNote = UI.Text(p, "note", "")
    bx.joinNote:SetPoint("LEFT", bx.join, "RIGHT", 8, 0)
    bx.parts = { bx, bx.mode, bx.add, bx.addBtn, bx.join, bx.joinNote }
    return bx
  end

  -- place everything top to bottom; the aura list is as long as it needs to be
  e.Layout = function()
    local r = Rule()
    local y = -40
    local function place(w, x, dy) w:ClearAllPoints(); w:SetPoint("TOPLEFT", p, "TOPLEFT", x, y); y = y - dy end
    place(e.secSpell, 0, 30)
    e.spell:ClearAllPoints(); e.spell:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
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
      bx.add:ClearAllPoints(); bx.add:SetPoint("TOPLEFT", p, "TOPLEFT", 12, y - 2)
      bx.addBtn:ClearAllPoints(); bx.addBtn:SetPoint("LEFT", bx.add, "RIGHT", 6, 0)
      bx.add.Refresh()
      y = y - 32
      bx:SetHeight(top - y)
      y = y - 8
    end
    for k = n + 1, #e.rows do e.rows[k]:Hide() end
    for g = ngroups + 1, #e.boxes do for _, w in ipairs(e.boxes[g].parts) do w:Hide() end end
    e.newGroupBox:ClearAllPoints(); e.newGroupBox:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y - 2)
    e.newGroup:ClearAllPoints(); e.newGroup:SetPoint("LEFT", e.newGroupBox, "RIGHT", 6, 0)
    y = y - 40
    place(e.secOther, 0, 30)
    for i, cb in ipairs(e.checks) do
      cb:ClearAllPoints()
      cb:SetPoint("TOPLEFT", p, "TOPLEFT", (i % 2 == 1) and 0 or 240, y - math.floor((i - 1) / 2) * 24)
    end
    y = y - 3 * 24 - 12
    -- "Use for all rules" sits at the right end of the Look heading
    e.lookAll:ClearAllPoints(); e.lookAll:SetPoint("TOPRIGHT", p, "TOPLEFT", EW, y + 1)
    place(e.secLook, 0, 30)
    local function pair(lbl, w, x) lbl:ClearAllPoints(); lbl:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 4)
      w:ClearAllPoints(); w:SetPoint("TOPLEFT", p, "TOPLEFT", x + 92, y) end
    pair(e.lColorL, e.color, 0)
    e.lookTest:ClearAllPoints(); e.lookTest:SetPoint("TOPLEFT", p, "TOPLEFT", 270, y)
    y = y - 28
    pair(e.lStyleL, e.style, 0); pair(e.lMotionL, e.motion, 250)
    y = y - 28
    pair(e.lSizeL, e.size, 0); pair(e.lAlphaL, e.alpha, 250)
    local eui = ns.EllesmereMode()
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
    e.title:SetText(name or "New rule")
    e.icon:SetTexture(name and ns.SpellIcon(name) or "Interface\\Icons\\INV_Misc_QuestionMark")
    e.enabled.Refresh(); e.RefreshLook(); e.spell.Refresh(); e.newGroupBox.Refresh()
    for _, cb in ipairs(e.checks) do cb.Refresh() end
    e.Layout()
  end

  -- live status: glowing or not and why, buttons, how each aura is read right now
  local HOW = { aura = "read directly", exact = "read directly", hidden = "seen (details hidden)",
    cdm = "from the Cooldown Manager", ["your cast"] = "from your casts", guess = "last known (not in the Cooldown Manager)",
    unknown = "hidden in combat" }
  e.UpdateStatus = function()
    local r = Rule()
    if not r then return end
    local name = ns.RuleSpellName(r)
    if not name then e.status:SetText("|cffff6060Type a spell or item: name or ID.|r"); return end
    local lines = {}
    local on, why, gates = ns.Glow.Evaluate(r)
    if on and gates and #gates > 0 then lines[#lines + 1] = "|cffffd200Glowing when the game says so (hidden values)|r"
    elseif on then lines[#lines + 1] = "|cff60ff60Glowing|r"
    else lines[#lines + 1] = "Not glowing: " .. why end
    local nb = ns.Glow.CountButtons(r)
    lines[#lines + 1] = nb > 0 and format("On your action bars: %d button%s", nb, nb == 1 and "" or "s")
      or "|cffff6060Not on any of Blizzard's action bars.|r"
    for _, a in ipairs(r.auras) do
      local an = ns.AuraName(r, a)
      if a.kind == "rule" then
        local other = ns.RuleById(a.rule)
        if other then
          local on2, _, gs2 = ns.Glow.Evaluate(other)
          lines[#lines + 1] = format("Rule %s: %s", ns.RuleLabel(other),
            (on2 and gs2 and #gs2 > 0) and "|cffffd200active when the game says so (hidden values)|r"
            or (on2 and "|cff60ff60active|r" or "not active"))
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
        local has, how = ns.State.AuraPresent(a, an)
        local where = a.unit == "target" and "your target" or "you"
        local state = has == nil and "|cffffd200can't tell|r" or (has and "on " .. where or "not on " .. where)
        local cdm = ns.State.Tracked(an) and "|cff60ff60tracked|r" or "|cffff6060not tracked|r"
        lines[#lines + 1] = format("%s: %s (%s), Cooldown Manager: %s", an, state, HOW[how] or how or "?", cdm)
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
local function BuildList(p)
  local l = {}
  local sec = UI.Section(p, "Rules", LIST_W); sec:SetPoint("TOPLEFT", 0, 0)
  l.box = CreateFrame("Frame", nil, p, "BackdropTemplate")
  l.box:SetPoint("TOPLEFT", 0, -32); l.box:SetSize(LIST_W, 360)
  l.box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  UI.Skin(function(th) l.box:SetBackdropColor(0, 0, 0, 0.35); l.box:SetBackdropBorderColor(UI.RGB(th.accent, 0.6)) end)
  local scroll, content = UI.Scroll(l.box, LIST_W - 8, 352)
  scroll:SetPoint("TOPLEFT", 4, -4)
  l.content, l.scroll = content, scroll

  l.add = UI.Button(p, "+ Add rule", 96, function()
    local r = ns.Copy(ns.NEW_RULE); r.id = ns.NewRuleId()
    if ns.char then ns.char.fresh = nil end -- (you're making this character's rules yourself)
    table.insert(ns.db.rules, r)
    selected = #ns.db.rules; ui.Refresh(); Changed()
  end)
  l.add:SetPoint("TOPLEFT", l.box, "BOTTOMLEFT", 0, -8)
  l.remove = UI.Button(p, "Remove", 96, function()
    if ns.db.rules[selected] then
      table.remove(ns.db.rules, selected)
      selected = math.max(1, math.min(selected, #ns.db.rules)); ui.Refresh(); Changed()
    end
  end)
  l.remove:SetPoint("LEFT", l.add, "RIGHT", 4, 0)

  l.Refresh = function()
    local th = UI.Theme()
    for i, r in ipairs(ns.db.rules) do
      local row = rows[i]
      if not row then
        row = CreateFrame("Button", nil, content)
        row:SetSize(LIST_W - 18, 26)
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
        row.bar = row:CreateTexture(nil, "ARTWORK"); row.bar:SetWidth(2)
        row.bar:SetPoint("TOPLEFT"); row.bar:SetPoint("BOTTOMLEFT")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(20, 20); row.icon:SetPoint("LEFT", 6, 0)
        row.text = UI.Text(row, "line", "")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0); row.text:SetPoint("RIGHT", -4, 0); row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.hover = true; l.Refresh() end)
        row:SetScript("OnLeave", function(self) self.hover = false; l.Refresh() end)
        rows[i] = row
      end
      row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
      local name = ns.RuleSpellName(r)
      row.icon:SetTexture(name and ns.SpellIcon(name) or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.icon:SetDesaturated(not r.enabled)
      row.text:SetText(name or "(no spell)")
      local on = (i == selected)
      local c = on and th.title or (row.hover and th.hover or (r.enabled and th.line or th.dim))
      row.text:SetTextColor(UI.RGB(c))
      row.sel:SetColorTexture(UI.RGB(th.box, on and 0.45 or (row.hover and 0.2 or 0)))
      row.bar:SetColorTexture(UI.RGB(th.title)); row.bar:SetShown(on)
      row:SetScript("OnClick", function() selected = i; ui.Refresh() end)
      row:Show()
    end
    for i = #ns.db.rules + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #ns.db.rules * 26))
    l.remove.SetActive(ns.db.rules[selected] ~= nil)
    scroll.Update()
  end
  return l
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local refreshers = {}
local function track(w) refreshers[#refreshers + 1] = w; return w end

local function PageRules(pg)
  local left = CreateFrame("Frame", nil, pg); left:SetPoint("TOPLEFT"); left:SetSize(LIST_W, PAGE_H)
  local list = BuildList(left)
  local scroll, content = UI.Scroll(pg, EDIT_W, PAGE_H)
  scroll:SetPoint("TOPLEFT", EDIT_X, 0)
  local editor = BuildEditor(content)
  ui = { Refresh = function() list.Refresh(); editor.Refresh(); editor.UpdateStatus(); scroll.Update() end,
    Status = function() editor.UpdateStatus(); scroll.Update() end }
end

local function PageSettings(pg)
  local function S(key) return { function() return ns.db[key] end, function(v) ns.db[key] = v end } end
  local sec3 = UI.Section(pg, "Timing", 330); sec3:SetPoint("TOPLEFT", 0, 0)
  track(UI.Slider(pg, "A melee hit on me counts for", 330, 1, 10, 1, S("meleeWindow"),
    function(v) return v .. " s" end, Changed)):SetPoint("TOPLEFT", 0, -32)
  UI.Text(pg, "note", "Used by the \"Being attacked in melee\" condition."):SetPoint("TOPLEFT", 0, -72)

  -- other UIs: each mode turns itself on when that UI is installed
  local sec4 = UI.Section(pg, "Other UIs", 330); sec4:SetPoint("TOPLEFT", 370, 0)
  local function mode(label, has, key, onChange, tip, y)
    local c = track(UI.Check(pg, label .. (has and "" or "  (not installed)"),
      { function() return ns.db[key] ~= false end, function(v) ns.db[key] = v end }, 320, onChange))
    c:SetPoint("TOPLEFT", 370, y)
    local r0 = c.Refresh
    c.Refresh = function() r0(); c.SetActive(has) end
    c:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label, 1, 1, 1)
      GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, true)
      if not has then GameTooltip:AddLine("Turns on by itself when it's installed.", 1, 0.82, 0, true) end
      GameTooltip:Show()
    end)
    c:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end
  mode("EllesmereUI mode", ns.HasEllesmere(), "euiMode", function() ns.Glow.Restyle(); UI.Restyle(); if ui then ui.Refresh() end end,
    "Glows on EllesmereUI's action bars, its shape glow on shaped buttons, its glow styles (pixel lines, autocast shine, GCD ants...) in each rule's Look, and this window in EllesmereUI's style (its theme, accent colour and font). Turning it off restyles the window after a /reload.", -32)
  mode("FlareUI mode", ns.HasFlare(), "flareStyle", function() UI.Restyle(); if ui then ui.Refresh() end end,
    "This window in FlareUI's style (when EllesmereUI mode isn't styling it). FlareUI restyles Blizzard's own bars, so glows already show there.", -56)

  local note = UI.Text(pg, "note", "Each rule's glow (colour, start, pulse, size, intensity) is set in its Look section, in the Rules tab.")
  note:SetPoint("TOPLEFT", 0, -112); note:SetWidth(700)

  -- rules are per character: copy another character's into this one
  local sec5 = UI.Section(pg, "Rules on other characters", 700); sec5:SetPoint("TOPLEFT", 0, -150)
  local here = UI.Text(pg, "line", ""); here:SetPoint("TOPLEFT", 0, -182); here:SetWidth(700)
  local others, pick = {}, nil
  local from = track(UI.Toggle(pg, 300, others, { function() return pick end, function(v) pick = v end }, nil,
    "Which character's rules to copy. Click to switch; right-click to go back."))
  from:SetPoint("TOPLEFT", 0, -206)
  local copy = UI.Button(pg, "Copy to this character", 170, function()
    local src = pick and ns.RulesOf(pick)
    if not src then return end
    local n = ns.AddRuleCopies(src)
    ns.Print(format("copied %d rule%s from %s.", n, n == 1 and "" or "s", pick == "*shared" and "the shared list" or pick))
    if ui then ui.Refresh() end
    Changed(); from.Refresh()
  end)
  copy:SetPoint("LEFT", from, "RIGHT", 8, 0)
  local cnote = UI.Text(pg, "note", "Copies are added to this character's rules (nothing is replaced); remove the ones you don't need in the Rules tab.")
  cnote:SetPoint("TOPLEFT", 0, -236); cnote:SetWidth(700)
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
    copy.SetActive(pick ~= nil)
  end
end

local function PageHelp(page)
  -- (more than fits: it scrolls)
  local scroll, pg = UI.Scroll(page, 708, PAGE_H)
  scroll:SetPoint("TOPLEFT")
  local y = 0
  local function sec(t) local s = UI.Section(pg, t, 684); s:SetPoint("TOPLEFT", 0, y); y = y - 32 end
  local function para(t, color)
    local fs = UI.Text(pg, color or "line", t); fs:SetWidth(684); fs:SetPoint("TOPLEFT", 0, y)
    y = y - (fs:GetStringHeight() or 14) - 8
  end
  sec("How rules work")
  para("Items work too: put a trinket, potion or any usable item in the spell box (type its name or ID, or drag it from your bags) and it glows on your action bars, as itself or in a macro that /use-s it. For an item, \"Off cooldown\" is the item's own cooldown and \"Castable\" means you have it and can use it now.", "note")
  para("A rule glows a spell on your action bars while ALL of its conditions hold. Add as many buffs and debuffs as you like: " ..
    "each one says who has it (you or your target), whether it's a buff or a debuff, and whether it must be active or missing.")
  para("Example: Lightning Bolt glows while Stormstrike is on your target, Maelstrom Weapon is on you, " ..
    "and Flame Shock is on your target.", "note")
  sec("The Cooldown Manager is required in combat")
  para("In combat, the game hides buffs and debuffs from addons. Proc This! follows them through Blizzard's Cooldown Manager instead, " ..
    "so turn it on and add every buff and debuff your rules use to its Tracked Buffs or Tracked Bars. " ..
    "A green dot next to a condition means it's tracked; red means the rule can't see it in combat and won't glow.")
  para("The Cooldown Manager only tracks your own spells' auras. Auras that other players put on you or your target " ..
    "(for example another player's curse) can only be checked out of combat.", "note")
  local cdm = UI.Text(pg, "line", ""); cdm:SetPoint("TOPLEFT", 0, y); y = y - 26
  sec("Commands")
  para("Every condition reads the same way, left to right: what kind, on whom, what, and its state. [Debuff] [Target] [Stormstrike] [Active]: glows while your Stormstrike debuff is on your target. [Rule] [Lightning Bolt] [Inactive]: while your Lightning Bolt rule isn't active. Click any part to switch it.", "note")
  para("Groups: each group needs all of its rows, or any one of them (its switch). Groups are joined by AND (every group) or OR (any group). " ..
    "Example: Group 1 (Any of these): Buff X, Buff Y  AND  Group 2 (All of these): Debuff Z, Debuff Y.", "note")
  para("Rule rows: another of your rules is active (its conditions are met right now) or isn't. Example: Earth Shock glows while your Flame Shock rule is inactive. A rule can't depend on itself, and rules that depend on each other in a loop never glow.", "note")
  para("Health and Mana rows: yours or your target's, compared with a %: > (more than), >= (at least), < (less than), <= (at most) or = (exactly). Example: Healing Wave glows while your target's health is < 40%; Evocation while your mana is < 20%. When the game hides the value (health in combat, your mana always), the game itself checks it against your % and switches the glow: Proc This! never sees the number. A dead target, or one without mana, never counts.", "note")
  para("Combo Points, Rage and Energy rows: yours, compared with an amount the same way. Example: Eviscerate glows while your combo points are >= 5, or = 3; Sinister Strike while your energy is >= 45. Combo points are always readable; when the game hides rage or energy (in combat), the game itself checks them.", "note")
  para("Rules are kept per character: each character has its own list. Settings > Rules on other characters copies another character's rules into this one.", "note")
  para("Instant Cast rows: the spell is instant cast right now, from its cast time (readable in combat). Covers Maelstrom Weapon at 5 stacks, Nature's Swiftness, Presence of Mind, Shadow Trance and the like. Example: Lightning Bolt glows while Lightning Bolt is instant. /pt cast <spell> shows a spell's cast time.", "note")
  para("/pt (or /proc, /procthis)  opens this window      /pt test  shows every rule's glow for 3 seconds      " ..
    "/pt auras  lists buffs and debuffs on you and your target with their spell IDs (out of combat)      /pt cast <spell>  its cast time now")
  sec("Feedback")
  local fb = UI.Button(pg, "Report a bug / suggest", 180, function()
    UI.ShowLink("ProcThisLinkWindow", "Proc This!: bugs and ideas", "https://github.com/califaxop/Proc-This-Custom-Procs/issues/new/choose")
  end)
  fb:SetPoint("TOPLEFT", 0, y)
  local fbn = UI.Text(pg, "note", "Opens a link to copy: a short form for bugs or ideas.")
  fbn:SetPoint("LEFT", fb, "RIGHT", 10, 0)
  y = y - 30
  pg:SetHeight(-y + 10)
  page:SetScript("OnShow", function()
    scroll:SetVerticalScroll(0); scroll.Update()
    local on = GetCVarBool and GetCVarBool("cooldownViewerEnabled")
    cdm:SetText(on and "|cff60ff60Cooldown Manager: on|r" or "|cffff6060Cooldown Manager: off. Turn it on in Options > Gameplay Enhancements.|r")
  end)
end

local function BuildWindow()
  win = UI.Window("ProcThisWindow", 760, 580)
  win:SetPoint("CENTER")
  UI.SetHost(win) -- pop-ups (the bug / idea link) sit over this window
  local title = UI.Text(win, "title", "Proc This!")
  title:SetPoint("TOPLEFT", 26, -20)
  UI.Text(win, "note", "Custom procs: glow any spell when your conditions are met."):SetPoint("LEFT", title, "RIGHT", 10, -1)
  UI.Tabs(win, { { "Rules", PageRules }, { "Settings", PageSettings }, { "Help", PageHelp } }, 26, -66, 708, PAGE_H)

  win:SetScript("OnShow", function(self)
    local fit = (UIParent:GetHeight() - 40) / self:GetHeight()
    self:SetScale(math.max(0.5, math.min(1, fit)))
    for _, w in ipairs(refreshers) do w.Refresh() end
    ui.Refresh()
  end)
  local t = 0
  win:SetScript("OnUpdate", function(_, dt) t = t + dt; if t > 0.5 then t = 0; ui.Status() end end)
  win:Hide()
end

function ns.OpenOptions()
  if not win then
    local ok, e = pcall(BuildWindow)
    if not ok then if win then win:Hide() end; win = nil; ns.Print("settings failed: " .. tostring(e)); return end
  end
  UI.Restyle()
  win:SetShown(not win:IsShown())
end

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
    if ns.EllesmereMode() and not ns.db.seenUI.eui then
      ns.db.seenUI.eui = true
      ns.Print("EllesmereUI found: EllesmereUI mode is on (glows on its bars, its glow styles in each rule's Look). /pt to change.")
    end
    if ns.HasFlare() and ns.db.flareStyle ~= false and not ns.db.seenUI.flare then
      ns.db.seenUI.flare = true
      ns.Print("FlareUI found: FlareUI mode is on. /pt to change.")
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
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, s[1], i, s[2])
      if not ok or not a then break end
      if ns.Readable(a.name) then
        any = true
        print(format("|cffffd200%s:|r %s  |cff999999(ID %s)|r", s[3], a.name, tostring(a.spellId)))
      end
    end
  end
  if not any then ns.Print("no auras found on you or your target.") end
end

-- /pt cast <spell>: its cast time right now (0 = instant), as Instant rows read it
local function ShowCast(spell)
  spell = strtrim(spell or "")
  if spell == "" then spell = ns.SpellName(403) or "Lightning Bolt" end
  local ct = ns.State.CastTime(spell)
  ns.Print(format("%s%s: %s", spell, InCombatLockdown() and " (in combat)" or "",
    ct == nil and "cast time hidden or unknown" or (ct <= 0 and "instant" or format("%d ms cast", ct))))
end

SlashCmdList.PROCTHIS = function(msg)
  local castArg = (msg or ""):match("^%s*[Cc][Aa][Ss][Tt]%s*(.*)$")
  if castArg then ShowCast(castArg); return end
  if (msg or ""):lower():match("^test") then ns.Glow.Test(3); return end
  if (msg or ""):lower():match("^aura") then ListAuras(); return end
  if (msg or ""):lower():match("^power") then
    for _, l in ipairs(ns.State.PowerReport()) do ns.Print(l) end
    return
  end
  local ok, e = pcall(ns.OpenOptions)
  if not ok then ns.Print("settings error: " .. tostring(e)) end
end
