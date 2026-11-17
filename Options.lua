-- Spell Glow: settings window (/spellglow or /sglow, or Esc > Options > AddOns > Spell Glow) and start-up.
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
local KINDS = { { "buff", "Buff" }, { "debuff", "Debuff" } }
local MODES = { { "present", "Active" }, { "missing", "Missing" } }
local DTYPES = { { "Poison", "Poison" }, { "Curse", "Curse" }, { "Disease", "Disease" }, { "Magic", "Magic" },
  { "any", "Any dispellable" } }

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

  -- aura conditions
  e.secAuras = UI.Section(p, "Buffs and debuffs (all must hold)", EW)
  e.cdmNote = UI.Text(p, "note",
    "In combat the game hides auras from addons: add each one to Blizzard's Cooldown Manager " ..
    "(Tracked Buffs or Tracked Bars) so Spell Glow can follow it. The dot shows if it's tracked.")
  e.cdmNote:SetWidth(EW)
  e.none = UI.Text(p, "note", "No buff or debuff conditions yet.")
  local newName = ""
  e.newAura = UI.Edit(p, 230, { function() return newName end, function(v) newName = v end },
    "Buff or debuff: name or ID", true)
  e.addAura = UI.Button(p, "+ Add", 70, function()
    local r = Rule(); if not r then return end
    newName = strtrim(e.newAura:GetText() or "")
    local c = ns.Copy(ns.NEW_AURA); c.name = newName
    table.insert(r.auras, c)
    newName = ""; e.newAura:SetText(""); e.newAura:ClearFocus()
    ui.Refresh(); Changed()
  end)
  e.newAura:SetScript("OnEnterPressed", function() e.addAura:Click() end)
  e.addType = UI.Button(p, "+ Add type", 90, function()
    local r = Rule(); if not r then return end
    local c = ns.Copy(ns.NEW_AURA); c.match = "type"; c.kind = "debuff"; c.dtype = "Poison"
    table.insert(r.auras, c)
    ui.Refresh(); Changed()
  end)
  e.addType.tip = "A condition on any debuff (or buff) of one type: poison, curse, disease or magic. No names needed, and no Cooldown Manager."
  e.addNote = UI.Text(p, "note", "Blank = the spell itself.")

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
    row:SetSize(EW, 48)
    local function A() local r = Rule(); return r and r.auras[i] end
    local function refresh() ui.Refresh(); Changed() end
    row.unit = UI.Toggle(row, 76, UNITS, Field(A, "unit"), refresh, "On you or on your target. Click to switch.")
    row.unit:SetPoint("TOPLEFT", 0, 0)
    row.kind = UI.Toggle(row, 62, KINDS, Field(A, "kind"), refresh, "A buff or a debuff. Click to switch.")
    row.kind:SetPoint("LEFT", row.unit, "RIGHT", 4, 0)
    row.mode = UI.Toggle(row, 66, MODES, Field(A, "mode"), refresh, "Glow while it's active, or while it's missing. Click to switch.")
    row.mode:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
    row.name = UI.Edit(row, 130, { function() local a = A(); return a and a.name end,
      function(v) local a = A(); if a then a.name = v; refresh() end end }, "the spell itself", true)
    row.name:SetPoint("LEFT", row.mode, "RIGHT", 6, 0)
    row.dtype = UI.Toggle(row, 130, DTYPES, Field(A, "dtype"), refresh, "Which type. Click to switch.")
    row.dtype:SetPoint("LEFT", row.mode, "RIGHT", 6, 0)
    row.ge = UI.Text(row, "note", ">=")
    row.ge:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.stacks = UI.Edit(row, 28, { function() local a = A(); return a and a.stacks end,
      function(v) local a = A(); if a then a.stacks = math.max(0, math.min(99, math.floor(tonumber(v) or 0))); refresh() end end },
      "", false, true)
    row.stacks:SetPoint("LEFT", row.ge, "RIGHT", 4, 0)
    row.dot = CreateFrame("Frame", nil, row)
    row.dot:SetSize(12, 12); row.dot:SetPoint("LEFT", row.stacks, "RIGHT", 8, 0)
    row.dot.tex = row.dot:CreateTexture(nil, "ARTWORK")
    row.dot.tex:SetTexture("Interface\\Buttons\\WHITE8X8"); row.dot.tex:SetSize(8, 8); row.dot.tex:SetPoint("CENTER")
    row.dot:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tracked and "Tracked in the Cooldown Manager" or "Not in the Cooldown Manager", 1, 1, 1)
      GameTooltip:AddLine(self.tracked and "Followed in combat." or
        "In combat Spell Glow can't see it, and the rule won't glow. Add it to the Cooldown Manager's Tracked Buffs or Tracked Bars.", 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    row.dot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.del = UI.Button(row, "\195\151", 22, function()
      local r = Rule(); if r then table.remove(r.auras, i); refresh() end
    end)
    row.del.tip = "Remove this condition"
    row.del:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)

    -- second line: your debuff on the target
    row.mine = UI.Check(row, "Only mine", Field(A, "mine"), 92, refresh)
    row.mine:SetPoint("TOPLEFT", 18, -26)
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
    row.usedBy = UI.Edit(row, 104, { function() local a = A(); return a and a.usedBy end,
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
      for _, w in ipairs({ row.unit, row.kind, row.mode, row.name, row.dtype, row.stacks, row.mine, row.dur, row.charges, row.usedBy }) do w.Refresh() end
      local byType = a.match == "type"
      row.name:SetShown(not byType); row.dtype:SetShown(byType)
      local stackable = a.mode ~= "missing" and not byType
      row.stacks:SetShown(stackable); row.ge:SetShown(stackable)
      row.dot:SetShown(not byType) -- types are read directly: no Cooldown Manager needed
      local tdebuff = a.unit == "target" and a.kind == "debuff" and not byType
      for _, w in ipairs(row.extra) do w:SetShown(tdebuff) end
      local an = (not byType) and ns.AuraName(r, a)
      local tracked = an and ns.State.Tracked(an) or false
      row.dot.tracked = tracked
      if tracked then row.dot.tex:SetVertexColor(0.35, 0.9, 0.35) else row.dot.tex:SetVertexColor(0.9, 0.3, 0.25) end
      row:SetHeight(tdebuff and 50 or 26)
    end
    return row
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
    for i = 1, n do
      local row = e.rows[i] or Row(i)
      e.rows[i] = row
      row:Show(); row.Refresh()
      place(row, 0, row:GetHeight() + 4)
    end
    for i = n + 1, #e.rows do e.rows[i]:Hide() end
    e.newAura:ClearAllPoints(); e.newAura:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y - 2)
    e.addAura:ClearAllPoints(); e.addAura:SetPoint("LEFT", e.newAura, "RIGHT", 6, 0)
    e.addType:ClearAllPoints(); e.addType:SetPoint("LEFT", e.addAura, "RIGHT", 6, 0)
    e.addNote:ClearAllPoints(); e.addNote:SetPoint("TOPLEFT", e.newAura, "BOTTOMLEFT", 0, -4)
    y = y - 50
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
    for _, w in ipairs({ e.icon, e.enabled, e.secSpell, e.spell, e.spellNote, e.secAuras, e.cdmNote, e.newAura, e.addAura,
      e.addType, e.addNote, e.secOther, e.secStatus, e.status }) do w:SetShown(shown) end
    for _, cb in ipairs(e.checks) do cb:SetShown(shown) end
    if not r then
      e.title:SetText("Add a rule to start")
      for _, row in ipairs(e.rows) do row:Hide() end
      e.none:Hide()
      return
    end
    local name = ns.RuleSpellName(r)
    e.title:SetText(name or "New rule")
    e.icon:SetTexture(name and ns.SpellIcon(name) or "Interface\\Icons\\INV_Misc_QuestionMark")
    e.enabled.Refresh(); e.spell.Refresh(); e.newAura.Refresh()
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
      local an = ns.AuraLabel(r, a)
      if an then
        local has, how = ns.State.AuraPresent(a, an)
        local where = a.unit == "target" and "your target" or "you"
        local state = has == nil and "|cffffd200can't tell|r" or (has and "on " .. where or "not on " .. where)
        if a.match == "type" then
          lines[#lines + 1] = format("%s: %s (%s)", an:gsub("^%l", string.upper), state, HOW[how] or how or "?")
        else
          local cdm = ns.State.Tracked(an) and "|cff60ff60tracked|r" or "|cffff6060not tracked|r"
          lines[#lines + 1] = format("%s: %s (%s), Cooldown Manager: %s", an, state, HOW[how] or how or "?", cdm)
        end
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
    table.insert(ns.db.rules, ns.Copy(ns.NEW_RULE))
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
  para("Example: Lightning Bolt glows while Stormstrike is on your target, Maelstrom Weapon is on you with at least 5 stacks, " ..
    "and Flame Shock is on your target.", "note")
  para("+ Add type matches any debuff (or buff) of a type instead of a name: Poison, Curse, Disease, Magic or any dispellable. " ..
    "Example: Cure Poison glows while a Poison debuff is on you. Types on you are read even in combat, no Cooldown Manager needed.", "note")
  sec("The Cooldown Manager is required in combat")
  para("In combat, the game hides buffs and debuffs from addons. Spell Glow follows them through Blizzard's Cooldown Manager instead, " ..
    "so turn it on and add every buff and debuff your rules use to its Tracked Buffs or Tracked Bars. " ..
    "A green dot next to a condition means it's tracked; red means the rule can't see it in combat and won't glow.")
  para("The Cooldown Manager only tracks your own spells' auras. Auras that other players put on you or your target " ..
    "(for example another player's curse) can only be checked out of combat.", "note")
  local cdm = UI.Text(pg, "line", ""); cdm:SetPoint("TOPLEFT", 0, y); y = y - 26
  sec("Commands")
  para("/sglow types  shows your debuffs and their types as Spell Glow sees them (try it in combat)", "line")
  para("/sglow  opens this window      /sglow test  shows every rule's glow for 3 seconds      " ..
    "/sglow auras  lists buffs and debuffs on you and your target with their spell IDs (out of combat)")
  pg:SetScript("OnShow", function()
    local on = GetCVarBool and GetCVarBool("cooldownViewerEnabled")
    cdm:SetText(on and "|cff60ff60Cooldown Manager: on|r" or "|cffff6060Cooldown Manager: off. Turn it on in Options > Gameplay Enhancements.|r")
  end)
end

local function BuildWindow()
  win = UI.Window("SpellGlowWindow", 760, 580)
  win:SetPoint("CENTER")
  local title = UI.Text(win, "title", "Spell Glow")
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
        local p = CreateFrame("Frame"); p.name = "Spell Glow"
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(180, 22); b:SetText("Open Spell Glow"); b:SetPoint("TOPLEFT", 16, -16)
        b:SetScript("OnClick", function()
          if SettingsPanel and SettingsPanel.Close then pcall(SettingsPanel.Close, SettingsPanel, true) end
          if not (win and win:IsShown()) then ns.OpenOptions() end
        end)
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(p, p.name))
      end
    end)
    ns.Print("loaded. Type |cffffff00/spellglow|r to set up your glows.")
  end
end)

SLASH_SPELLGLOW1 = "/spellglow"
SLASH_SPELLGLOW2 = "/sglow"
-- /sglow auras: your target's debuffs and buffs and your own buffs and debuffs, with spell IDs
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

-- /sglow types: what Spell Glow can see of your debuffs' types right now (to check combat)
local function ListTypes()
  local sec = ns.isSecret
  ns.Print("your debuffs, as Spell Glow sees them" .. (InCombatLockdown() and " (in combat):" or ":"))
  local any = false
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
    if not ok then print("  the game refused: " .. tostring(a)); return end
    if not a then break end
    any = true
    if sec(a) then print("  #" .. i .. ": hidden") else
      local okN, n = pcall(function() return a.name end)
      local okD, d = pcall(function() return a.dispelName end)
      print(format("  #%d: %s - type: %s", i, (okN and not sec(n)) and tostring(n) or "hidden",
        not okD and "error" or (sec(d) and "hidden" or tostring(d or "none"))))
    end
  end
  if not any then print("  none") end
end

-- /sglow probe: which in-combat routes to your debuffs' types this client allows an addon
-- (instance IDs from the game or Blizzard's own debuff icons, the hidden type color, applying it)
local function Probe()
  local sec = ns.isSecret
  local function show(v) if sec(v) then return "hidden" end return tostring(v) end
  ns.Print("probe (" .. (InCombatLockdown() and "in combat" or "out of combat") .. "), get a NEW debuff in this fight, then run it:")
  local ids = {}
  -- 1) the game's list of your debuffs' instance IDs
  local f = C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs
  if not f then print("  1. GetUnitAuraInstanceIDs: not in this client")
  else
    local ok, r = pcall(f, "player", "HARMFUL")
    if not ok then print("  1. GetUnitAuraInstanceIDs: refused (" .. tostring(r) .. ")")
    elseif sec(r) then print("  1. GetUnitAuraInstanceIDs: hidden list")
    elseif type(r) == "table" then
      print("  1. GetUnitAuraInstanceIDs: " .. #r .. " ID(s), first: " .. show(r[1]))
      for _, id in ipairs(r) do ids[#ids + 1] = id end
    else print("  1. GetUnitAuraInstanceIDs: " .. show(r)) end
  end
  -- 2) Blizzard's own debuff icons by the minimap
  local df = _G.DebuffFrame
  local frames = df and (df.auraFrames or (df.AuraContainer and { df.AuraContainer:GetChildren() }))
  if type(frames) ~= "table" then print("  2. Blizzard's debuff icons: not found")
  else
    local n, got = 0, 0
    for _, b in ipairs(frames) do
      if b.IsShown and b:IsShown() then
        n = n + 1
        local id = b.auraInstanceID or (b.buttonInfo and b.buttonInfo.auraInstanceID)
        if id ~= nil then got = got + 1; if #ids == 0 or got == 1 then ids[#ids + 1] = id end end
        if n == 1 then print("  2. first debuff icon's instance ID: " .. show(id)) end
      end
    end
    print(format("  2. Blizzard's debuff icons: %d shown, %d with an instance ID", n, got))
    -- what Forever keeps on its debuff icons (field names only)
    for _, b in ipairs(frames) do
      if b.IsShown and b:IsShown() then
        local keys = {}
        for k, v in pairs(b) do
          if type(k) == "string" and type(v) ~= "function" and type(v) ~= "userdata" then
            keys[#keys + 1] = k .. (type(v) == "table" and "{}" or ("=" .. show(v)))
          end
        end
        table.sort(keys)
        print("  2. icon fields: " .. table.concat(keys, ", "):sub(1, 230))
        break
      end
    end
  end
  -- 2c) the border Blizzard colours by debuff type: can an addon see that colour?
  if type(frames) == "table" then
    local shown = 0
    for _, b in ipairs(frames) do
      if b.IsShown and b:IsShown() and shown < 3 then
        shown = shown + 1
        local nm = b.GetName and b:GetName()
        local border = b.Border or b.border or (nm and _G[nm .. "Border"])
        if not border and b.GetRegions then
          for _, r in ipairs({ b:GetRegions() }) do
            local rn = r.GetName and r:GetName()
            if rn and rn:find("Border") then border = r end
          end
        end
        if not border then print(format("  2c. icon %d (%s): no border found", shown, tostring(nm)))
        else
          local ok, r, g, bl = pcall(border.GetVertexColor, border)
          local vis = border.IsShown and border:IsShown()
          print(format("  2c. icon %d border: shown=%s color=%s", shown, show(vis),
            not ok and "refused" or (sec(r) and "hidden" or format("%.2f %.2f %.2f", r or -1, g or -1, bl or -1))))
        end
      end
    end
    local p = DebuffTypeColor and DebuffTypeColor.Poison
    if p then print(format("  2c. (Blizzard's poison color: %.2f %.2f %.2f)", p.r, p.g, p.b)) end
  end
  -- 2b) instance IDs from the game's "your auras changed" notices
  local seen = ns.seenAuraIDs or {}
  print(format("  2b. from aura-change notices: %d ID(s), latest: %s", #seen, show(seen[1])))
  if #ids == 0 then for _, id in ipairs(seen) do ids[#ids + 1] = id end end
  if #ids == 0 then print("  no instance IDs to test further"); return end
  -- 3) the hidden type color, through a color curve (Poison = opaque, everything else = clear)
  local okC, curve = pcall(function() return C_CurveUtil.CreateColorCurve() end)
  if not okC or not curve then print("  3. CreateColorCurve: failed (" .. tostring(curve) .. ")"); return end
  local POISON = (Enum and Enum.AuraDispelType and Enum.AuraDispelType.Poison) or 4
  pcall(curve.SetType, curve, Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step)
  local okP = pcall(function()
    curve:AddPoint(0, CreateColor(1, 1, 1, 0)); curve:AddPoint(POISON, CreateColor(1, 1, 1, 1))
    curve:AddPoint(POISON + 1, CreateColor(1, 1, 1, 0))
  end)
  print("  3. color curve points: " .. (okP and "ok" or "failed") .. " (Poison = " .. tostring(POISON) .. ")")
  local okG, col = pcall(C_UnitAuras.GetAuraDispelTypeColor, "player", ids[1], curve)
  if not okG then print("  3. GetAuraDispelTypeColor: refused (" .. tostring(col) .. ")"); return end
  local a = col and (col.a or (col.GetRGBA and select(4, col:GetRGBA())))
  print("  3. GetAuraDispelTypeColor: got " .. (col == nil and "nothing" or ("a color, alpha " .. show(a))))
  -- 4) can a frame take that hidden alpha? (that's how the glow would be shown or hidden)
  local t = CreateFrame("Frame")
  local okA, e = pcall(t.SetAlpha, t, a)
  print("  4. frame:SetAlpha(hidden alpha): " .. (okA and "ok" or ("refused (" .. tostring(e) .. ")")))
end

SlashCmdList.SPELLGLOW = function(msg)
  if (msg or ""):lower():match("^probe") then Probe(); return end
  if (msg or ""):lower():match("^type") then ListTypes(); return end
  if (msg or ""):lower():match("^test") then ns.Glow.Test(3); return end
  if (msg or ""):lower():match("^aura") then ListAuras(); return end
  local ok, e = pcall(ns.OpenOptions)
  if not ok then ns.Print("settings error: " .. tostring(e)) end
end
