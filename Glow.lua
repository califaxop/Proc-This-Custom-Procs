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
  local kind, id, subType = GetActionInfo(action)
  if isSecret(kind) or isSecret(id) then return nil end
  local name
  if kind == "spell" then
    name = ns.SpellName(id)
  elseif kind == "macro" then
    -- newer clients hand back the spell the macro casts (subType "spell"); older ones the
    -- macro's index, to ask which spell it casts
    if subType == "spell" then name = ns.SpellName(id) end
    if not name and GetMacroSpell then
      local ok, sid = pcall(GetMacroSpell, id)
      if ok and not isSecret(sid) then name = ns.SpellName(sid) end
    end
    return name -- not cached: a macro with [conditions] can switch spells at any moment
  end
  slotCache[action] = name or false
  return name
end
function G.ForgetSlots() wipe(slotCache) end

-- The glow sits inside a chain of "gate" frames on the button. Alphas multiply, so each gate
-- is one more condition: open (1) or shut (0). Gates are how conditions the game hides
-- (e.g. castable) still work: the client sets their alpha from the hidden value,
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


-- set one gate from a hidden value; false if the client can't do it
local function SetGate(g, gate)
  if gate.kind == "bool" then
    if g.SetAlphaFromBoolean then g:SetAlphaFromBoolean(gate.v, 1, 0); return true end
    return false
  end
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

-- One buff / debuff row: true, or false and why.
function G.CheckAura(rule, a)
  if a.kind == "instant" then
    -- "Spell X is (not) instant cast": from its current cast time
    local sp = ns.AuraName(rule, a)
    if not sp then return false, "name the spell" end
    local ct = S.CastTime(sp)
    if ct == nil then return false, format("can't read %s's cast time", sp) end
    local instant = ct <= 0
    if a.mode == "missing" then
      if instant then return false, format("%s is instant now", sp) end
      return true
    end
    if not instant then return false, format("%s isn't instant (%.1f s cast)", sp, ct / 1000) end
    return true
  end
  local an = ns.AuraLabel and ns.AuraLabel(rule, a) or ns.AuraName(rule, a)
  if not an then return false, "name the aura" end
  local who = (a.unit == "target") and "your target" or "you"
  local has = S.AuraPresent(a, an)
  if has == nil then
    return false, format("%s on %s is hidden in combat (track it in the Cooldown Manager)", an, who)
  end
  if a.mode == "missing" then
    if has then return false, format("%s is on %s", an, who) end
    return true
  end
  if not has then return false, format("%s is not on %s", an, who) end
  return true
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
  -- buff / debuff conditions, in groups: a group holds when all its rows do ("all") or any one
  -- does ("any"); the rule needs every group ("and") or any one group ("or")
  local groups = {}
  for _, a in ipairs(rule.auras or {}) do
    local g = tonumber(a.group) or 1
    groups[g] = groups[g] or {}
    table.insert(groups[g], a)
  end
  local gids = {}
  for g in pairs(groups) do gids[#gids + 1] = g end
  table.sort(gids)
  local function GroupOK(g)
    local any = (rule.groupModes and rule.groupModes[g]) == "any"
    local whys = {}
    for _, a in ipairs(groups[g]) do
      local ok, why = G.CheckAura(rule, a)
      if any and ok then return true end
      if not any and not ok then return false, why end
      if not ok then whys[#whys + 1] = why end
    end
    if any then return false, (#whys == 1) and whys[1] or ("none of: " .. table.concat(whys, "; or ")) end
    return true
  end
  if #gids > 0 then
    if rule.join == "or" then
      local whys = {}
      local okAny = false
      for _, g in ipairs(gids) do
        local ok, why = GroupOK(g)
        if ok then okAny = true; break end
        whys[#whys + 1] = why
      end
      if not okAny then return false, (#whys == 1) and whys[1] or ("no group holds: " .. table.concat(whys, " / ")) end
    else
      for _, g in ipairs(gids) do
        local ok, why = GroupOK(g)
        if not ok then return false, why end
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
