-- Spell Glow: settings window (/spellglow or /sglow, or Esc > Options > AddOns > Spell Glow) and start-up.
local _, ns = ...

local function Label(parent, text, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
  fs:SetText(text)
  return fs
end

local function Button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22); b:SetText(text); b:SetScript("OnClick", onClick)
  return b
end

local function Changed() ns.Glow.Soon() end

local selected = 1
local win, ui
local function Rule() return ns.db.rules[selected] end

---------------------------------------------------------------------------
-- Rule editor (right side)
---------------------------------------------------------------------------
local CHECKS = {
  { "melee",   "I'm being attacked in melee" },
  { "usable",  "Castable (known, enough mana)" },
  { "ready",   "Off cooldown (the global cooldown doesn't count)" },
  { "control", "I have control (not stunned, feared...)" },
  { "combat",  "Only in combat" },
  { "proc",    "The game flags it as a proc" },
}
local BUFF_MODES = { { "ignore", "Don't check" }, { "missing", "Glow when it's MISSING" }, { "present", "Glow when it's ON me" } }
local TDEBUFF_MODES = { { "ignore", "Don't check" }, { "missing", "Glow when it's MISSING" }, { "present", "Glow when it's ON it" } }

-- "Don't check / missing / present" picker for a rule field
local function ModeButton(p, label, key, modes, anchor, dx)
  local l = Label(p, label, "GameFontHighlight")
  l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx or 0, -14)
  local b = Button(p, "", 200, nil)
  b:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -4)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, mouse)
    local r = Rule(); if not r then return end
    local i = 1
    for k, m in ipairs(modes) do if m[1] == r[key] then i = k end end
    i = i + (mouse == "RightButton" and -1 or 1)
    if i < 1 then i = #modes elseif i > #modes then i = 1 end
    r[key] = modes[i][1]; ui.Refresh(); Changed()
  end)
  b.Refresh = function(r) for _, m in ipairs(modes) do if m[1] == r[key] then b:SetText(m[2]) end end end
  b.label = l
  return b
end


local function SpellBox(parent, label, key, anchor, hint)
  local l = Label(parent, label, "GameFontHighlight")
  l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(230, 22); box:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 6, -4)
  box:SetAutoFocus(false)
  local function commit(self)
    local r = Rule()
    if r then r[key] = strtrim(self:GetText() or ""); ui.Refresh(); Changed() end
    self:ClearFocus()
  end
  box:SetScript("OnEnterPressed", commit)
  box:SetScript("OnEditFocusLost", commit)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ui.Refresh() end)
  -- drag a spell from your spellbook onto the box
  box:SetScript("OnReceiveDrag", function(self)
    local kind, a, b, spellID = GetCursorInfo()
    local id = (kind == "spell") and (spellID or b) or nil
    local name = id and ns.SpellName(id)
    if name then ClearCursor(); self:SetText(name); commit(self) end
  end)
  box:HookScript("OnMouseDown", function(self) if GetCursorInfo() then self:GetScript("OnReceiveDrag")(self) end end)
  if hint then
    local h = Label(parent, hint, "GameFontDisableSmall")
    h:SetPoint("LEFT", box, "RIGHT", 8, 0); h:SetWidth(120); h:SetJustifyH("LEFT")
  end
  return box
end

local function BuildEditor(p)
  local e = {}
  e.title = Label(p, "Rule", "GameFontNormalLarge")
  e.title:SetPoint("TOPLEFT", 0, 0)
  e.enabled = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  e.enabled:SetSize(24, 24); e.enabled:SetPoint("LEFT", e.title, "RIGHT", 12, 0)
  local el = Label(p, "Enabled", "GameFontHighlight"); el:SetPoint("LEFT", e.enabled, "RIGHT", 2, 0)
  e.enabled:SetScript("OnClick", function(self) local r = Rule(); if r then r.enabled = self:GetChecked() and true or false; ui.Refresh(); Changed() end end)

  e.spell = SpellBox(p, "Spell to glow (name or ID - or drag it from your spellbook)", "spell", e.title, "every rank")

  -- Buffs on me: up to 3 rows, all must hold. Each: on me / missing, which buff, at least N stacks.
  local MAX_BUFF_ROWS = 3
  local bh = Label(p, "Buffs on me (all must hold)", "GameFontHighlight")
  bh:SetPoint("TOPLEFT", e.spell, "BOTTOMLEFT", -6, -14)
  e.buffRows = {}
  for i = 1, MAX_BUFF_ROWS do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(390, 24)
    row:SetPoint("TOPLEFT", bh, "BOTTOMLEFT", 0, -4 - (i - 1) * 26)
    row.mode = Button(row, "", 82, nil)
    row.mode:SetPoint("LEFT", 0, 0)
    row.mode:SetScript("OnClick", function()
      local r = Rule(); local c = r and r.buffs[i]; if not c then return end
      c.mode = (c.mode == "missing") and "present" or "missing"; ui.Refresh(); Changed()
    end)
    row.name = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.name:SetSize(140, 20); row.name:SetPoint("LEFT", row.mode, "RIGHT", 10, 0); row.name:SetAutoFocus(false)
    local function commitName(self)
      local r = Rule(); local c = r and r.buffs[i]
      if c then c.name = strtrim(self:GetText() or ""); Changed() end
      self:ClearFocus()
    end
    row.name:SetScript("OnEnterPressed", commitName)
    row.name:SetScript("OnEditFocusLost", commitName)
    row.name:SetScript("OnReceiveDrag", function(self)
      local kind, _, b2, spellID = GetCursorInfo()
      local n = kind == "spell" and ns.SpellName(spellID or b2)
      if n then ClearCursor(); self:SetText(n); commitName(self) end
    end)
    row.ge = Label(row, ">=", "GameFontHighlightSmall"); row.ge:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.stacks = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.stacks:SetSize(26, 20); row.stacks:SetPoint("LEFT", row.ge, "RIGHT", 6, 0); row.stacks:SetAutoFocus(false)
    row.stacks:SetJustifyH("CENTER")
    local function commitStacks(self)
      local r = Rule(); local c = r and r.buffs[i]
      if c then c.stacks = math.max(0, math.min(99, math.floor(tonumber(self:GetText()) or 0))); Changed() end
      self:ClearFocus(); ui.Refresh()
    end
    row.stacks:SetScript("OnEnterPressed", commitStacks)
    row.stacks:SetScript("OnEditFocusLost", commitStacks)
    row.st = Label(row, "stacks", "GameFontHighlightSmall"); row.st:SetPoint("LEFT", row.stacks, "RIGHT", 4, 0)
    row.del = Button(row, "X", 24, function()
      local r = Rule(); if r then table.remove(r.buffs, i); ui.Refresh(); Changed() end
    end)
    row.del:SetPoint("LEFT", row.st, "RIGHT", 8, 0)
    e.buffRows[i] = row
  end
  e.addBuff = Button(p, "+ Add buff condition", 160, function()
    local r = Rule()
    if r and #r.buffs < MAX_BUFF_ROWS then
      table.insert(r.buffs, { mode = "present", name = "", stacks = 0 }); ui.Refresh(); Changed()
    end
  end)
  e.addBuff:SetPoint("TOPLEFT", bh, "BOTTOMLEFT", 0, -4 - MAX_BUFF_ROWS * 26)
  local bhint = Label(p, "Blank name = the spell itself. Stacks only count for \"on me\" (0 = any).", "GameFontDisableSmall")
  bhint:SetPoint("LEFT", e.addBuff, "RIGHT", 8, 0); bhint:SetWidth(220); bhint:SetJustifyH("LEFT")

  e.tdMode = ModeButton(p, "Debuff on my target", "tdebuff", TDEBUFF_MODES, e.addBuff, 0)
  e.tdName = SpellBox(p, "Which debuff (blank = the spell itself)", "tdebuffName", e.tdMode, nil)
  e.tdMine = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  e.tdMine:SetSize(24, 24); e.tdMine:SetPoint("TOPLEFT", e.tdName, "BOTTOMLEFT", -6, -4)
  local ml = Label(p, "Only mine", "GameFontHighlight"); ml:SetPoint("LEFT", e.tdMine, "RIGHT", 2, 0)
  e.tdMine:SetScript("OnClick", function(self) local r = Rule(); if r then r.tdebuffMine = self:GetChecked() and true or false; Changed() end end)
  local dl = Label(p, "lasts", "GameFontHighlight"); dl:SetPoint("LEFT", ml, "RIGHT", 18, 0)
  e.tdDur = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  e.tdDur:SetSize(36, 20); e.tdDur:SetPoint("LEFT", dl, "RIGHT", 8, 0); e.tdDur:SetAutoFocus(false)
  e.tdDur:SetJustifyH("CENTER")
  local sl = Label(p, "s  (0 = auto)", "GameFontDisableSmall"); sl:SetPoint("LEFT", e.tdDur, "RIGHT", 4, 0)
  local function commitDur(self)
    local r = Rule()
    if r then r.tdebuffDur = math.max(0, math.min(600, tonumber(self:GetText()) or 0)); Changed() end
    self:SetText(tostring(r and r.tdebuffDur or 0)); self:ClearFocus()
  end
  e.tdDur:SetScript("OnEnterPressed", commitDur)
  e.tdDur:SetScript("OnEditFocusLost", commitDur)

  -- used up by casts: "after [N] cast(s) of [spells]"
  local ul = Label(p, "Used up after", "GameFontHighlight")
  ul:SetPoint("TOPLEFT", e.tdMine, "BOTTOMLEFT", 4, -8)
  e.tdCharges = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  e.tdCharges:SetSize(28, 20); e.tdCharges:SetPoint("LEFT", ul, "RIGHT", 8, 0); e.tdCharges:SetAutoFocus(false)
  e.tdCharges:SetJustifyH("CENTER")
  local ol = Label(p, "cast(s) of", "GameFontHighlight"); ol:SetPoint("LEFT", e.tdCharges, "RIGHT", 6, 0)
  local function commitCharges(self)
    local r = Rule()
    if r then r.tdebuffCharges = math.max(0, math.min(20, math.floor(tonumber(self:GetText()) or 0))); Changed() end
    self:SetText(tostring(r and r.tdebuffCharges or 0)); self:ClearFocus()
  end
  e.tdCharges:SetScript("OnEnterPressed", commitCharges)
  e.tdCharges:SetScript("OnEditFocusLost", commitCharges)
  e.tdUsedBy = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  e.tdUsedBy:SetSize(150, 20); e.tdUsedBy:SetPoint("LEFT", ol, "RIGHT", 10, 0); e.tdUsedBy:SetAutoFocus(false)
  local function commitUsed(self)
    local r = Rule()
    if r then r.tdebuffUsedBy = strtrim(self:GetText() or ""); Changed() end
    self:ClearFocus()
  end
  e.tdUsedBy:SetScript("OnEnterPressed", commitUsed)
  e.tdUsedBy:SetScript("OnEditFocusLost", commitUsed)
  local uh = Label(p, "0 = not used up. Spells comma-separated; blank = this rule's spell. Only matters in combat.", "GameFontDisableSmall")
  uh:SetPoint("TOPLEFT", ul, "BOTTOMLEFT", 0, -6); uh:SetWidth(380); uh:SetJustifyH("LEFT")
  e.tdUsedHint = uh

  e.tbMode = ModeButton(p, "Buff on my target", "tbuff", TDEBUFF_MODES, uh, -4)
  e.tbName = SpellBox(p, "Which buff (its name or ID)", "tbuffName", e.tbMode, nil)

  e.pdMode = ModeButton(p, "Debuff on me", "pdebuff", BUFF_MODES, e.tbName, -6)
  e.pdName = SpellBox(p, "Which debuff (its name or ID)", "pdebuffName", e.pdMode, nil)

  local prev = e.pdName
  e.checks = {}
  for i, c in ipairs(CHECKS) do
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", i == 1 and -6 or 0, i == 1 and -12 or -2)
    local l = Label(p, c[2], "GameFontHighlight"); l:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnClick", function(self) local r = Rule(); if r then r[c[1]] = self:GetChecked() and true or false; Changed() end end)
    e.checks[c[1]] = cb
    prev = cb
  end
  local allNote = Label(p, "It glows only while ALL checked conditions are true.", "GameFontDisableSmall")
  allNote:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)

  e.status = Label(p, "", "GameFontHighlightSmall")
  e.status:SetPoint("TOPLEFT", allNote, "BOTTOMLEFT", 0, -12)
  e.status:SetWidth(380); e.status:SetJustifyH("LEFT")

  e.Refresh = function()
    local r = Rule()
    for _, w in ipairs({ e.enabled, e.spell, e.addBuff, e.tdMode, e.tdName, e.tdMine, e.tdDur, e.tdCharges, e.tdUsedBy, e.tbMode, e.tbName, e.pdMode, e.pdName }) do w:SetShown(r ~= nil) end
    for _, cb in pairs(e.checks) do cb:SetShown(r ~= nil) end
    if not r then e.title:SetText("No rule selected"); e.status:SetText(""); return end
    e.title:SetText(ns.RuleSpellName(r) or "New rule")
    e.enabled:SetChecked(r.enabled)
    if not e.spell:HasFocus() then e.spell:SetText(r.spell or "") end
    e.tdMode.Refresh(r); e.tbMode.Refresh(r); e.pdMode.Refresh(r)
    if not e.tbName:HasFocus() then e.tbName:SetText(r.tbuffName or "") end
    e.tbName:SetEnabled(r.tbuff ~= "ignore")
    -- buff rows
    for i, row in ipairs(e.buffRows) do
      local c = r and r.buffs[i]
      row:SetShown(c ~= nil)
      if c then
        row.mode:SetText(c.mode == "missing" and "MISSING" or "ON me")
        if not row.name:HasFocus() then row.name:SetText(c.name or "") end
        if not row.stacks:HasFocus() then row.stacks:SetText(tostring(c.stacks or 0)) end
        local stackable = c.mode ~= "missing"
        row.stacks:SetEnabled(stackable); row.ge:SetAlpha(stackable and 1 or 0.4); row.st:SetAlpha(stackable and 1 or 0.4)
      end
    end
    e.addBuff:SetEnabled(#r.buffs < #e.buffRows)
    if not e.tdName:HasFocus() then e.tdName:SetText(r.tdebuffName or "") end
    if not e.pdName:HasFocus() then e.pdName:SetText(r.pdebuffName or "") end
    if not e.tdDur:HasFocus() then e.tdDur:SetText(tostring(r.tdebuffDur or 0)) end
    e.tdMine:SetChecked(r.tdebuffMine)
    if not e.tdCharges:HasFocus() then e.tdCharges:SetText(tostring(r.tdebuffCharges or 0)) end
    if not e.tdUsedBy:HasFocus() then e.tdUsedBy:SetText(r.tdebuffUsedBy or "") end
    e.tdName:SetEnabled(r.tdebuff ~= "ignore"); e.pdName:SetEnabled(r.pdebuff ~= "ignore")
    for key, cb in pairs(e.checks) do cb:SetChecked(r[key]) end
  end

  -- live status: is it glowing, why not, how many buttons, can the buff be followed in combat
  e.UpdateStatus = function()
    local r = Rule()
    if not r then return end
    local name = ns.RuleSpellName(r)
    if not name then e.status:SetText("|cffff6060Type a spell name or ID.|r"); return end
    local lines = {}
    local on, why = ns.Glow.Evaluate(r)
    local _, _, gates = ns.Glow.Evaluate(r)
    if on and gates and #gates > 0 then lines[#lines + 1] = "|cffffd200Now: decided by the game (" .. why .. ")|r"
    elseif on then lines[#lines + 1] = "|cff60ff60Now: glowing|r"
    else lines[#lines + 1] = "Now: not glowing - " .. why end
    local n = ns.Glow.CountButtons(r)
    lines[#lines + 1] = n > 0 and format("On your action bars: %d button%s", n, n == 1 and "" or "s")
      or "|cffff6060Not on any of Blizzard's action bars.|r"
    for _, c in ipairs(r.buffs or {}) do
      local bn = ns.BuffCondName(r, c)
      if bn then
        local stackText = ""
        if c.mode ~= "missing" and (tonumber(c.stacks) or 0) > 1 then
          local st, src = ns.State.BuffStacks(bn)
          if ns.isSecret(st) then
            stackText = ns.curveState == "unsupported" and " - stacks hidden, and this client can't compare them"
              or " - stacks hidden: the client compares them"
          elseif st then stackText = format(" - %d of %d stacks", st, c.stacks)
          else stackText = " - stacks can't be read" end
        end
        if ns.State.BuffTracked(bn) then
          lines[#lines + 1] = "|cff60ff60" .. bn .. ": tracked in the Cooldown Manager, followed in combat" .. stackText .. "|r"
        else
          lines[#lines + 1] = "|cffffd200" .. bn .. ": not tracked in Blizzard's Cooldown Manager, so in combat Spell Glow can't see it change. Add it to the Cooldown Manager's Tracked Buffs." .. stackText .. "|r"
        end
      end
    end
    -- how the debuff conditions are being read right now
    local HOW = { exact = "read exactly", hidden = "seen (details hidden by the game)",
      cdm = "|cff60ff60from the Cooldown Manager (exact)|r", ["your cast"] = "from your casts (combat hides it)", unknown = "|cffffd200hidden in combat - can't be checked until it ends|r" }
    if r.tdebuff ~= "ignore" then
      local dn = ns.RuleTargetDebuffName(r)
      local has, how = ns.State.TargetDebuff(dn, r.tdebuffMine, r.tdebuffDur)
      lines[#lines + 1] = format("Target: %s %s - %s", dn or "?", has and "is on it" or "not seen", HOW[how] or how or "")
      if dn and not ns.State.Tracked(dn) then
        lines[#lines + 1] = "|cffffd200Tip: add " .. dn .. " to Blizzard's Cooldown Manager (Tracked Buffs) and it's followed exactly in combat.|r"
      end
    end
    if r.tbuff ~= "ignore" then
      local bn = ns.RuleTargetBuffName(r)
      if bn then
        local has, how = ns.State.TargetBuff(bn)
        lines[#lines + 1] = format("Target: %s %s - %s", bn, has and "is on it" or "not seen", HOW[how] or how or "")
      end
    end
    if r.pdebuff ~= "ignore" then
      local dn = ns.RuleMyDebuffName(r)
      if dn then
        local has, how = ns.State.MyDebuff(dn)
        lines[#lines + 1] = format("You: %s %s - %s", dn, has and "is on you" or "not on you", HOW[how] or how or "")
      end
    end
    e.status:SetText(table.concat(lines, "\n"))
  end
  return e
end

---------------------------------------------------------------------------
-- Rules list (left side)
---------------------------------------------------------------------------
local rows = {}
local function BuildList(p)
  local l = {}
  l.title = Label(p, "Rules", "GameFontNormalLarge"); l.title:SetPoint("TOPLEFT", 0, 0)
  l.box = CreateFrame("Frame", nil, p, "BackdropTemplate")
  l.box:SetPoint("TOPLEFT", l.title, "BOTTOMLEFT", 0, -8); l.box:SetSize(190, 300)
  l.box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  l.box:SetBackdropColor(0, 0, 0, 0.5)
  l.scroll = CreateFrame("ScrollFrame", nil, l.box)
  l.scroll:SetPoint("TOPLEFT", 6, -6); l.scroll:SetPoint("BOTTOMRIGHT", -6, 6)
  l.content = CreateFrame("Frame", nil, l.scroll); l.content:SetSize(178, 1)
  l.scroll:SetScrollChild(l.content)
  l.scroll:EnableMouseWheel(true)
  l.scroll:SetScript("OnMouseWheel", function(self, d)
    local max = math.max(0, l.content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 40)))
  end)

  l.add = Button(p, "Add rule", 92, function()
    table.insert(ns.db.rules, ns.Copy(ns.NEW_RULE))
    selected = #ns.db.rules; ui.Refresh(); Changed()
  end)
  l.add:SetPoint("TOPLEFT", l.box, "BOTTOMLEFT", 0, -8)
  l.remove = Button(p, "Remove", 92, function()
    if ns.db.rules[selected] then
      table.remove(ns.db.rules, selected)
      selected = math.max(1, math.min(selected, #ns.db.rules)); ui.Refresh(); Changed()
    end
  end)
  l.remove:SetPoint("LEFT", l.add, "RIGHT", 6, 0)

  l.Refresh = function()
    for i, r in ipairs(ns.db.rules) do
      local row = rows[i]
      if not row then
        row = CreateFrame("Button", nil, l.content)
        row:SetSize(178, 24)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.25)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(20, 20); row.icon:SetPoint("LEFT", 2, 0)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0); row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
        rows[i] = row
      end
      row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
      local name = ns.RuleSpellName(r)
      row.icon:SetTexture(name and ns.SpellIcon(name) or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.text:SetText(name or "(no spell)")
      row.text:SetTextColor(r.enabled and 1 or 0.5, r.enabled and 1 or 0.5, r.enabled and 1 or 0.5)
      row.sel:SetShown(i == selected)
      row:SetScript("OnClick", function() selected = i; ui.Refresh() end)
      row:Show()
    end
    for i = #ns.db.rules + 1, #rows do rows[i]:Hide() end
    l.content:SetHeight(math.max(1, #ns.db.rules * 24))
  end
  return l
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Slider(parent, label, minV, maxV, step, key, fmt, anchor)
  local text = Label(parent, "", "GameFontHighlight")
  text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
  local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
  s:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6); s:SetSize(180, 16)
  s:SetOrientation("HORIZONTAL"); s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
  s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 } })
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / step + 0.5) * step
    ns.db[key] = v; text:SetText(label .. ": " .. fmt(v)); Changed()
  end)
  s.Refresh = function() s:SetValue(ns.db[key]); text:SetText(label .. ": " .. fmt(ns.db[key])) end
  return s
end

local function BuildWindow()
  win = CreateFrame("Frame", "SpellGlowWindow", UIParent, "BackdropTemplate")
  win:SetSize(680, 1040); win:SetPoint("CENTER"); win:SetFrameStrata("DIALOG")
  win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "SpellGlowWindow")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
  local title = Label(win, "Spell Glow", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 24, -20)
  local sub = Label(win, "Retail-style glow on your action bar spells, when your conditions are met.", "GameFontDisableSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

  local left = CreateFrame("Frame", nil, win); left:SetPoint("TOPLEFT", 24, -64); left:SetSize(200, 400)
  local right = CreateFrame("Frame", nil, win); right:SetPoint("TOPLEFT", 250, -64); right:SetSize(400, 960)
  local list, editor = BuildList(left), BuildEditor(right)

  local melee = Slider(left, "Melee hit counts for", 1, 10, 1, "meleeWindow", function(v) return v .. " s" end, list.add)
  local size = Slider(left, "Glow size", 1, 2, 0.05, "glowScale", function(v) return math.floor(v * 100 + 0.5) .. "%" end, melee)
  local intensity = Slider(left, "Glow intensity", 0.2, 1, 0.05, "glowAlpha", function(v) return math.floor(v * 100 + 0.5) .. "%" end, size)

  -- how the glow starts: click to cycle, right-click to go back
  local STYLES = { { "glow", "Just the glow" }, { "shine", "Glow + shine" }, { "burst", "Blizzard burst (zoom)" } }
  local styleLabel = Label(left, "When it starts", "GameFontHighlight")
  styleLabel:SetPoint("TOPLEFT", intensity, "BOTTOMLEFT", 0, -12)
  local style = Button(left, "", 180, nil)
  style:SetPoint("TOPLEFT", styleLabel, "BOTTOMLEFT", 0, -6)
  style:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local styleHint = Label(left, "", "GameFontDisableSmall")
  styleHint:SetPoint("TOPLEFT", style, "BOTTOMLEFT", 0, -4); styleHint:SetWidth(190); styleHint:SetJustifyH("LEFT")
  local HINTS = { glow = "Fades straight into the glow.", shine = "Flares brighter for a moment, then settles.",
    burst = "Blizzard's proc start: grows past the button." }
  function style.Refresh()
    for _, st in ipairs(STYLES) do
      if st[1] == ns.db.glowStyle then style:SetText(st[2]); styleHint:SetText(HINTS[st[1]]) end
    end
  end
  style:SetScript("OnClick", function(_, mouse)
    local i = 1
    for k, st in ipairs(STYLES) do if st[1] == ns.db.glowStyle then i = k end end
    i = (mouse == "RightButton") and (i - 2) % #STYLES + 1 or i % #STYLES + 1
    ns.db.glowStyle = STYLES[i][1]; style.Refresh(); ns.Glow.Test(3)
  end)

  local test = Button(left, "Test glow (3 s)", 180, function() ns.Glow.Test(3) end)
  test:SetPoint("TOPLEFT", styleHint, "BOTTOMLEFT", 0, -14)

  ui = { Refresh = function() list.Refresh(); editor.Refresh(); editor.UpdateStatus() end }
  win:SetScript("OnShow", function(self)
    -- shrink to fit smaller screens (the window is tall)
    local fit = (UIParent:GetHeight() - 40) / self:GetHeight()
    self:SetScale(math.max(0.5, math.min(1, fit)))
    melee.Refresh(); size.Refresh(); intensity.Refresh(); style.Refresh(); ui.Refresh()
  end)
  local t = 0
  win:SetScript("OnUpdate", function(_, dt) t = t + dt; if t > 0.5 then t = 0; editor.UpdateStatus() end end)
  win:Hide()
end

function ns.OpenOptions()
  if not win then BuildWindow() end
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
        local b = Button(p, "Open Spell Glow", 180, function() ns.OpenOptions() end); b:SetPoint("TOPLEFT", 16, -16)
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

SlashCmdList.SPELLGLOW = function(msg)
  if (msg or ""):lower():match("^test") then ns.Glow.Test(3); return end
  if (msg or ""):lower():match("^aura") then ListAuras(); return end
  local ok, e = pcall(ns.OpenOptions)
  if not ok then ns.Print("settings error: " .. tostring(e)) end
end
