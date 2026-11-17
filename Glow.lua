-- The glow itself, on Blizzard's action buttons: Blizzard's own retail alert
-- (ActionButtonSpellAlertTemplate), as its own frame on the button. Blizzard's alert manager is
-- never touched, so the buttons stay untainted.
local _, ns = ...
local G = {}
ns.Glow = G
local S = ns.State
local isSecret = ns.isSecret

local BAR_PREFIXES = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
  "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local buttons
local function Buttons()
  if buttons then return buttons end
  buttons = {}
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do
      local b = _G[prefix .. i]
      if b then buttons[#buttons + 1] = b end
    end
  end
  return buttons
end

-- The spell name on a button (spells and macros that cast a spell).
local slotCache = {}
local function ButtonSpell(b)
  local action = b.action or (b.CalculateAction and b:CalculateAction())
  if not action or isSecret(action) then return nil end
  local cached = slotCache[action]
  if cached ~= nil then return cached or nil end
  local kind, id = GetActionInfo(action)
  local name
  if kind == "spell" then name = ns.SpellName(id)
  elseif kind == "macro" and GetMacroSpell then name = ns.SpellName(GetMacroSpell(id)) end
  slotCache[action] = name or false
  return name
end
function G.ForgetSlots() wipe(slotCache) end

-- The glow sits inside a chain of "gate" frames on the button. Alphas multiply, so each gate
-- is one more condition: open (1) or shut (0). Gates are how conditions the game hides
-- (usable, stack counts) still work: the client sets their alpha from the hidden value,
-- without Spell Glow ever reading it.
local MAX_GATES = 4
local function GlowFrame(b)
  local glow = b.SG_Glow
  if not glow then
    b.SG_Gates = {}
    local parent = b
    for i = 1, MAX_GATES do
      local g = CreateFrame("Frame", nil, parent)
      g:SetAllPoints(b)
      b.SG_Gates[i] = g
      parent = g
    end
    glow = CreateFrame("Frame", nil, parent, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.SG_Glow = glow
  end
  local w, h = b:GetSize()
  glow:SetSize(w * ns.db.glowScale, h * ns.db.glowScale)
  return glow
end

-- "at least N stacks" for a hidden stack count: the client's step curve (0 below N, 1 from N up)
local curves = {}
ns.curveState = "untested"
local function StackCurve(min)
  if curves[min] then return curves[min] end
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then ns.curveState = "unsupported"; return nil end
  local ok, c = pcall(C_CurveUtil.CreateCurve)
  if not ok or not c then ns.curveState = "unsupported"; return nil end
  if Enum and Enum.LuaCurveType and c.SetType then pcall(c.SetType, c, Enum.LuaCurveType.Step) end
  if not (pcall(c.AddPoint, c, 0, 0) and pcall(c.AddPoint, c, min, 1)) then ns.curveState = "unsupported"; return nil end
  curves[min] = c
  return c
end

-- set one gate from a hidden value; false if the client can't do it
local function SetGate(g, gate)
  if gate.kind == "bool" then
    if g.SetAlphaFromBoolean then g:SetAlphaFromBoolean(gate.v, 1, 0); return true end
    return false
  end
  local c = StackCurve(gate.min)
  if not c then return false end
  local ok, v = pcall(c.Evaluate, c, gate.v)
  if ok and v ~= nil and pcall(g.SetAlpha, g, v) then ns.curveState = "works"; return true end
  ns.curveState = "unsupported"
  return false
end

-- Shine: a second copy of the glow, added on top (additive) and faded out, so the glow flares
-- briefly when it starts, then settles at its normal intensity.
local function ShineFrame(b, glow)
  local sh = b.SG_Shine
  if not sh then
    sh = CreateFrame("Frame", nil, glow:GetParent(), "ActionButtonSpellAlertTemplate")
    sh:SetPoint("CENTER", b, "CENTER", 0, 0)
    sh:SetFrameLevel(glow:GetFrameLevel() + 1)
    if sh.ProcStartFlipbook then sh.ProcStartFlipbook:SetAlpha(0) end
    if sh.ProcLoopFlipbook then sh.ProcLoopFlipbook:SetBlendMode("ADD"); sh.ProcLoopFlipbook:SetAlpha(1) end
    if sh.ProcAltGlow then sh.ProcAltGlow:SetAlpha(0) end
    local ag = sh:CreateAnimationGroup()
    local up = ag:CreateAnimation("Alpha"); up:SetOrder(1); up:SetDuration(0.12); up:SetFromAlpha(0); up:SetToAlpha(1)
    local down = ag:CreateAnimation("Alpha"); down:SetOrder(2); down:SetDuration(0.75)
    down:SetFromAlpha(1); down:SetToAlpha(0); down:SetSmoothing("OUT")
    ag:SetToFinalAlpha(true)
    ag:SetScript("OnFinished", function() sh.ProcLoop:Stop(); sh:Hide() end)
    sh.SG_Anim = ag
    sh:Hide()
    b.SG_Shine = sh
  end
  sh:SetSize(glow:GetSize())
  return sh
end

local function StopShine(b)
  local sh = b.SG_Shine
  if sh and sh:IsShown() then sh.SG_Anim:Stop(); sh.ProcLoop:Stop(); sh:Hide() end
end

local function Hide(b)
  local glow = b.SG_Glow
  StopShine(b)
  if not glow or not glow:IsShown() then return end
  glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop()
  glow:Hide()
end

-- start the glow in the chosen style:
--   "glow"  = just the looping glow, no start animation
--   "shine" = the looping glow, with a brief flare when it starts
--   "burst" = Blizzard's own start (the zoom-in burst), then the loop
local function Start(b, glow)
  local style = ns.db.glowStyle or "shine"
  glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop()
  if style == "burst" then
    if glow.ProcStartFlipbook then glow.ProcStartFlipbook:SetAlpha(1) end
    glow:Show()
    glow.ProcStartAnim:Play()
  else
    if glow.ProcStartFlipbook then glow.ProcStartFlipbook:SetAlpha(0) end
    if glow.ProcLoopFlipbook then glow.ProcLoopFlipbook:SetAlpha(1) end
    glow:Show()
    glow.ProcLoop:Play()
    if style == "shine" then
      local sh = ShineFrame(b, glow)
      sh.SG_Anim:Stop(); sh:SetAlpha(0); sh:Show()
      sh.ProcLoop:Play(); sh.SG_Anim:Play()
    end
  end
end

-- gates: nil/empty = glow plainly; otherwise the hidden conditions the client decides
local function Show(b, gates)
  local glow = GlowFrame(b)
  local n = gates and #gates or 0
  for i, g in ipairs(b.SG_Gates) do
    if i <= n then
      if not SetGate(g, gates[i]) then Hide(b); return end
    else
      g:SetAlpha(1)
    end
  end
  glow:SetAlpha(ns.db.glowAlpha or 1)
  if not glow:IsShown() then Start(b, glow) end
end

-- style or size changed: restart every glow so the change shows
function G.Restyle()
  for _, b in ipairs(Buttons()) do Hide(b) end
  G.Update()
end

-- A rule's verdict: on (true/false), why (for the settings window), and the hidden conditions
-- (gates) the client still has to decide when on is true.
function G.Evaluate(rule)
  local name = ns.RuleSpellName(rule)
  if not rule.enabled or not name then return false, "off" end
  local gates = {}
  if rule.combat and not S.InCombat() then return false, "not in combat" end
  if rule.control and not S.HasControl() then return false, "no control (stunned...)" end
  if rule.melee and not S.BeingMeleed() then return false, "not being hit in melee" end
  for _, a in ipairs(rule.auras or {}) do
    local an = ns.AuraLabel(rule, a)
    if not an then return false, "name the aura" end
    local who = (a.unit == "target") and "your target" or "you"
    local has = S.AuraPresent(a, an)
    if has == nil then
      if a.match == "type" then return false, format("can't tell if %s is on %s right now", an, who) end
      return false, format("%s on %s is hidden in combat (track it in the Cooldown Manager)", an, who)
    end
    if a.mode == "missing" then
      if has then return false, format("%s is on %s", an, who) end
    else
      if not has then return false, format("%s is not on %s", an, who) end
      local min = (a.match ~= "type") and tonumber(a.stacks) or 0
      if min > 1 then
        local st = S.AuraStacks(a, an)
        if st == nil then return false, an .. ": stacks can't be read (track it in the Cooldown Manager)" end
        if isSecret(st) then gates[#gates + 1] = { kind = "stacks", v = st, min = min }
        elseif st < min then return false, format("%s: %d of %d stacks", an, st, min) end
      end
    end
  end
  if rule.proc and not S.Flagged(name) then return false, "not flagged as a proc" end
  if rule.ready and not S.Ready(name) then return false, "on cooldown" end
  if rule.usable then
    local u = S.Usable(name)
    if isSecret(u) then gates[#gates + 1] = { kind = "bool", v = u }
    elseif not u then return false, "not castable (mana / not known)" end
  end
  if #gates > MAX_GATES then return false, "too many hidden conditions at once" end
  if #gates > 0 then return true, "decided by the game (hidden values)", gates end
  return true, "glowing"
end

local testUntil = 0
function G.Test(seconds)
  testUntil = GetTime() + (seconds or 3)
  for _, b in ipairs(Buttons()) do Hide(b) end -- so the start shows again
  G.Update()
end

function G.Update()
  -- per spell: "plain" (glow), a gates list (the client decides), or nothing
  local verdict = {}
  local testing = GetTime() < testUntil
  for _, rule in ipairs(ns.db.rules) do
    local name = ns.RuleSpellName(rule)
    if name and verdict[name] ~= "plain" then
      if testing then
        if rule.enabled then verdict[name] = "plain" end
      else
        local on, _, gates = G.Evaluate(rule)
        if on then
          -- several rules for one spell: a plain yes wins, else the first rule the game decides
          if not gates or #gates == 0 then verdict[name] = "plain"
          elseif verdict[name] == nil then verdict[name] = gates end
        end
      end
    end
  end
  for _, b in ipairs(Buttons()) do
    local name = b:IsVisible() and ButtonSpell(b)
    local v = name and verdict[name]
    if v == "plain" then Show(b, nil)
    elseif type(v) == "table" then Show(b, v)
    else Hide(b) end
  end
end

-- buttons showing a rule's spell (for the settings window)
function G.CountButtons(rule)
  local name = ns.RuleSpellName(rule)
  if not name then return 0 end
  local n = 0
  for _, b in ipairs(Buttons()) do if ButtonSpell(b) == name then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------
-- Events: update on anything that can change a condition, plus a light safety tick.
---------------------------------------------------------------------------
local pending = false
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(0, function() pending = false; G.Update() end)
end
G.Soon = Soon

function G.Init()
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "ACTIONBAR_PAGE_CHANGED",
    "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_COMBAT", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
  end
  pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player", "target")
  ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
    -- remember the aura instance IDs the game hands out with "your auras changed" (for /sglow probe)
    if event == "UNIT_AURA" and a1 == "player" and type(a2) == "table" and not ns.isSecret(a2) then
      pcall(function()
        for _, au in ipairs(a2.addedAuras or {}) do
          ns.seenAuraIDs = ns.seenAuraIDs or {}
          table.insert(ns.seenAuraIDs, 1, au.auraInstanceID)
          ns.seenAuraIDs[9] = nil
        end
      end)
    end
    if event == "UNIT_COMBAT" then
      S.OnUnitCombat(a2, a3, a4, a5)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      S.OnCast(a3)
    elseif event == "PLAYER_TARGET_CHANGED" then
      S.OnTargetChanged()
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
      S.OnOverlay(true, a1)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
      S.OnOverlay(false, a1)
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" or event == "SPELLS_CHANGED"
      or event == "ACTIONBAR_PAGE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
      G.ForgetSlots()
    end
    Soon()
  end)
  -- safety net: the melee window running out and Cooldown Manager changes have no event of their own
  C_Timer.NewTicker(0.25, G.Update)
  G.Update()
end
