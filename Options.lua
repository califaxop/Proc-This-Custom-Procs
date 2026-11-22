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
local EW = EDIT_W - 16 -- editor content width

---------------------------------------------------------------------------
-- Rule editor: spell, aura conditions (as many as you like), other conditions, live status
---------------------------------------------------------------------------
local CHECKS = {
  { "melee",   "Being attacked in melee" },
  { "usable",  "Castable (known, enough mana)" },
  { "ready",   "Off cooldown (GCD ignored)" },
  { "control", "I have control (not stunned)" },
  { "combat",  "Only in combat" },
  { "proc",    "The game flags it as a proc" },
}
local UNITS = { { "player", "On me" }, { "target", "On target" } }
local KINDS = { { "buff", "Buff" }, { "debuff", "Debuff" }, { "instant", "Instant" }, { "health", "Health" }, { "mana", "Mana" }, { "rule", "Rule" } }
local HPMODES = { { "below", "Below" }, { "above", "Above" } }
local IMODES = { { "present", "Is" }, { "missing", "Isn't" } }
local MODES = { { "present", "Active" }, { "missing", "Missing" } }

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
  e.secSpell = UI.Section(p, "Spell to glow", EW)
  e.spell = UI.Edit(p, 230, { function() local r = Rule(); return r and r.spell end,
    function(v) local r = Rule(); if r then r.spell = v; ui.Refresh(); Changed() end end },
    "Name or ID", true)
  e.spellNote = UI.Text(p, "note", "Every rank glows. Type it, or drag it from your spellbook.")
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

  -- status
  e.secStatus = UI.Section(p, "Right now", EW)
  e.status = UI.Text(p, "line", "")
  e.status:SetWidth(EW); e.status:SetSpacing(3)

  -- one aura row (+ a second line for your debuffs on the target)
  local function Row(i)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(EW - 24, 48)
    local function A() local r = Rule(); return r and r.auras[i] end
    local function refresh() ui.Refresh(); Changed() end
    row.unit = UI.Toggle(row, 70, UNITS, Field(A, "unit"), refresh, "On you or on your target. Click to switch.")
    row.unit:SetPoint("TOPLEFT", 0, 0)
    row.kind = UI.Toggle(row, 56, KINDS, Field(A, "kind"), refresh,
      "A buff, a debuff, Instant (the spell is instant cast right now: Maelstrom Weapon at 5, Nature's Swiftness...), Health or Mana (yours or your target's, below or above a %), or Rule (another of your rules is active, or isn't). Click to switch.")
    -- for Instant rows, in place of On me / On target: is or isn't instant
    row.imode = UI.Toggle(row, 70, IMODES, Field(A, "mode"), refresh, "Glow while the spell is instant cast, or while it isn't. Click to switch.")
    row.imode:SetPoint("TOPLEFT", 0, 0)
    row.kind:SetPoint("LEFT", row.unit, "RIGHT", 4, 0)
    row.mode = UI.Toggle(row, 62, MODES, Field(A, "mode"), refresh, "Glow while it's active, or while it's missing. Click to switch.")
    row.mode:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
    -- for Health rows, in place of Active / Missing and the name: below / at least N %
    row.hpMode = UI.Toggle(row, 62, HPMODES, { function() local a = A(); return a and a.hpMode or "below" end,
      function(v) local a = A(); if a then a.hpMode = v end end }, refresh,
      "Glow while it's below the %, or above it. Click to switch.")
    row.hpMode:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
    row.pct = UI.Edit(row, 40, { function() local a = A(); return a and (a.pct or 40) end,
      function(v) local a = A(); if a then a.pct = math.max(1, math.min(100, math.floor(tonumber(v) or 40))); refresh() end end },
      "40", false, true)
    row.pct:SetPoint("LEFT", row.hpMode, "RIGHT", 6, 0)
    row.pctSign = UI.Text(row, "line", "% health")
    row.pctSign:SetPoint("LEFT", row.pct, "RIGHT", 4, 0)
    -- for Rule rows: which other rule (the Is / Isn't switch says active or not)
    row.ruleOpts = {}
    row.ruleSel = UI.Toggle(row, 200, row.ruleOpts, { function() local a = A(); return a and a.rule end,
      function(v) local a = A(); if a then a.rule = v end end }, refresh,
      "Which rule: click to step through your rules. It's active while its own conditions are met (whether or not its spell is on your bars).")
    row.ruleSel:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
    row.ruleWord = UI.Text(row, "line", "active")
    row.ruleWord:SetPoint("LEFT", row.ruleSel, "RIGHT", 6, 0)
    row.name = UI.Edit(row, 116, { function() local a = A(); return a and a.name end,
      function(v) local a = A(); if a then a.name = v; refresh() end end }, "the spell itself", true)
    row.name:SetPoint("LEFT", row.mode, "RIGHT", 6, 0)
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
      for _, w in ipairs({ row.unit, row.imode, row.kind, row.mode, row.name, row.mine, row.dur, row.charges, row.usedBy, row.hpMode, row.pct, row.ruleSel }) do w.Refresh() end
      local instant = a.kind == "instant"
      local health = a.kind == "health" or a.kind == "mana" -- (both are a % row)
      row.pctSign:SetText(a.kind == "mana" and "% mana" or "% health")
      row.unit:SetShown(not instant and not isRule); row.mode:SetShown(not instant and not health and not isRule)
      row.imode:SetShown(instant or isRule)
      row.hpMode:SetShown(health); row.pct:SetShown(health); row.pctSign:SetShown(health)
      row.ruleSel:SetShown(isRule); row.ruleWord:SetShown(isRule)
      row.name:SetShown(not health and not isRule)
      row.dot:ClearAllPoints()
      row.dot:SetPoint("LEFT", (health and row.pctSign) or (isRule and row.ruleWord) or row.name, "RIGHT", 10, 0)
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
    place(e.secStatus, 0, 30)
    place(e.status, 0, 0)
    p:SetHeight(-y + (e.status:GetStringHeight() or 40) + 20)
  end

  e.Refresh = function()
    local r = Rule()
    local shown = r ~= nil
    for _, w in ipairs({ e.icon, e.enabled, e.secSpell, e.spell, e.spellNote, e.secAuras, e.cdmNote, e.newGroupBox, e.newGroup,
      e.secOther, e.secStatus, e.status }) do w:SetShown(shown) end
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
    e.enabled.Refresh(); e.spell.Refresh(); e.newGroupBox.Refresh()
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
    if not name then e.status:SetText("|cffff6060Type a spell name or ID.|r"); return end
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
      elseif a.kind == "health" or a.kind == "mana" then
        local unit = a.unit == "target" and "target" or "player"
        local v, why
        if a.kind == "health" then v, why = ns.State.HealthPct(unit) else v, why = ns.State.ManaPct(unit) end
        local who = (unit == "target" and "Your target's " or "Your ") .. a.kind
        local now = v and format("%d%%", math.floor(v + 0.5))
          or (why == "none" and "no target") or (why == "nomana" and "no mana")
          or "|cffffd200hidden: the game decides|r"
        lines[#lines + 1] = format("%s: %s (glows %s %d%%)", who, now, a.hpMode == "above" and "above" or "below", tonumber(a.pct) or 40)
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

local function PageLook(pg)
  local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end
  local function S(key) return { function() return ns.db[key] end, function(v) ns.db[key] = v end } end
  local sec = UI.Section(pg, "Glow", 330); sec:SetPoint("TOPLEFT", 0, 0)
  track(UI.Slider(pg, "Size", 320, 1, 2, 0.05, S("glowScale"), pct, Changed)):SetPoint("TOPLEFT", 0, -32)
  track(UI.Slider(pg, "Intensity", 320, 0.2, 1, 0.05, S("glowAlpha"), pct, Changed)):SetPoint("TOPLEFT", 0, -74)

  local sec2 = UI.Section(pg, "When it starts", 330); sec2:SetPoint("TOPLEFT", 0, -124)
  local STYLES = {
    { "glow", "Just the glow", "Fades straight into the glow." },
    { "shine", "Glow + shine", "Flares brighter for a moment, then settles." },
    { "burst", "Blizzard burst", "Blizzard's proc start: grows past the button." },
  }
  for i, st in ipairs(STYLES) do
    local cb = track(UI.Check(pg, st[2], { function() return ns.db.glowStyle == st[1] end,
      function() ns.db.glowStyle = st[1] end }, 150, function() ns.Glow.Test(3); for _, w in ipairs(refreshers) do w.Refresh() end end))
    cb:SetPoint("TOPLEFT", 0, -156 - (i - 1) * 26)
    UI.Text(pg, "note", st[3]):SetPoint("LEFT", cb, "RIGHT", 4, 0)
  end
  UI.Button(pg, "Test glow (3 s)", 140, function() ns.Glow.Test(3) end):SetPoint("TOPLEFT", 0, -244)

  local sec3 = UI.Section(pg, "Timing", 330); sec3:SetPoint("TOPLEFT", 370, 0)
  track(UI.Slider(pg, "A melee hit on me counts for", 330, 1, 10, 1, S("meleeWindow"),
    function(v) return v .. " s" end, Changed)):SetPoint("TOPLEFT", 370, -32)
  UI.Text(pg, "note", "Used by the \"Being attacked in melee\" condition."):SetPoint("TOPLEFT", 370, -72)

  local sec4 = UI.Section(pg, "Window style", 330); sec4:SetPoint("TOPLEFT", 370, -124)
  track(UI.Check(pg, "FlareUI style (needs FlareUI)", { function() return ns.db.flareStyle end,
    function(v) ns.db.flareStyle = v end }, 300, function() UI.Restyle(); if ui then ui.Refresh() end end)):SetPoint("TOPLEFT", 370, -156)
end

local function PageHelp(pg)
  local y = 0
  local function sec(t) local s = UI.Section(pg, t, 700); s:SetPoint("TOPLEFT", 0, y); y = y - 32 end
  local function para(t, color)
    local fs = UI.Text(pg, color or "line", t); fs:SetWidth(700); fs:SetPoint("TOPLEFT", 0, y)
    y = y - (fs:GetStringHeight() or 14) - 8
  end
  sec("How rules work")
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
  para("Groups: each group needs all of its rows, or any one of them (its switch). Groups are joined by AND (every group) or OR (any group). " ..
    "Example: Group 1 (Any of these): Buff X, Buff Y  AND  Group 2 (All of these): Debuff Z, Debuff Y.", "note")
  para("Rule rows: another of your rules is active (its conditions are met right now) or isn't. Example: Earth Shock glows while your Flame Shock rule is inactive. A rule can't depend on itself, and rules that depend on each other in a loop never glow.", "note")
  para("Health and Mana rows: yours or your target's, below or above a %. Example: Healing Wave glows while your target is below 40% health; Evocation while your mana is below 20%. When the game hides the value (health in combat, your mana always), the game itself checks it against your % and switches the glow: Proc This! never sees the number. A dead target, or one without mana, never counts.", "note")
  para("Instant rows: the spell is instant cast right now, from its cast time (readable in combat). Covers Maelstrom Weapon at 5 stacks, Nature's Swiftness, Presence of Mind, Shadow Trance and the like. Example: Lightning Bolt glows while Lightning Bolt is instant. /pt cast <spell> shows a spell's cast time.", "note")
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
  pg:SetScript("OnShow", function()
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
  UI.Tabs(win, { { "Rules", PageRules }, { "Look", PageLook }, { "Help", PageHelp } }, 26, -66, 708, PAGE_H)

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
    local ok, e = pcall(ns.Glow.Init)
    if not ok then ns.Print("start-up error: " .. tostring(e)) end
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
  local ok, e = pcall(ns.OpenOptions)
  if not ok then ns.Print("settings error: " .. tostring(e)) end
end
