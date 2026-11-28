-- Proc This!'s windows are the game's own Settings design (Settings.lua, shared with the author's
-- other addons), whatever UI is installed. Here: the parts of its own.
local _, ns = ...
local UI = {}
ns.UI = UI

-- a checkbox with its name to the right (the rule editor's lists of conditions)
function UI.LabeledCheck(parent, label, opt, onChange)
  local c = UI.Check(parent, opt, onChange)
  c.label = UI.Font(c, "GameFontHighlight", label)
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  local sa = c.SetActive
  c.SetActive = function(on) sa(on); c.label:SetFontObject(on and "GameFontHighlight" or "GameFontDisable") end
  return c
end

-- a Yes / No question over the settings window; onYes runs on Yes
function UI.Confirm(name, text, onYes)
  local w = _G[name]
  if not w then
    w = UI.Popup(name, 380, 150, "Proc This!")
    w.text = UI.Font(w, "GameFontHighlight")
    w.text:SetPoint("TOP", 0, -40); w.text:SetWidth(340); w.text:SetJustifyH("CENTER")
    local yes = UI.Button(w, YES or "Yes", 100, function() w:Hide(); if w.onYes then w.onYes() end end)
    yes:SetPoint("BOTTOMRIGHT", w, "BOTTOM", -4, 16)
    local no = UI.Button(w, NO or "No", 100, function() w:Hide() end)
    no:SetPoint("BOTTOMLEFT", w, "BOTTOM", 4, 16)
  end
  w.onYes = onYes
  w.text:SetText(text)
  w:Place(); w:Show()
end
