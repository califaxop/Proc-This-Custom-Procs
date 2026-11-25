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

-- EllesmereUI's action bars: its own buttons, EABButton<action slot>, for bars 1-10
-- (its EUI_ActionBars_Secure.lua: BAR_SLOT_OFFSETS). They're made when a bar is turned on, so the
-- list is looked at again every few seconds while EllesmereUI is loaded.
local EAB_SLOTS = 180
local EAB_BARS = { -- first slot -> its bar's settings key
  { 1, "MainBar" }, { 13, "Bar9" }, { 25, "Bar4" }, { 37, "Bar5" }, { 49, "Bar3" }, { 61, "Bar2" },
  { 109, "Bar10" }, { 145, "Bar6" }, { 157, "Bar7" }, { 169, "Bar8" },
}
local function HasEllesmere() return ns.EllesmereMode() end

local buttons, builtAt
local function Buttons()
  if buttons and not (HasEllesmere() and GetTime() - builtAt > 5) then return buttons end
  buttons, builtAt = {}, GetTime()
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do
      local b = _G[prefix .. i]
      if b then buttons[#buttons + 1] = b end
    end
  end
  if HasEllesmere() then
    for slot = 1, EAB_SLOTS do
      local b = _G["EABButton" .. slot]
      if b then buttons[#buttons + 1] = b end
    end
  end
  return buttons
end

-- EllesmereUI can shape its buttons (circle, hexagon, diamond...): a square glow would stick out, so
-- there Proc This! draws EllesmereUI's own shape glow (its public EllesmereUI.Glows), in the rule's
-- colour. Returns the shape's mask and border textures, or nil (a square button: our usual glow).
local function EllesmereShape(b)
  if not (HasEllesmere() and EllesmereUI.Glows.StartShapeGlow and EllesmereUI.SHAPE_MASKS) then return nil end
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
end

-- The spell (or item) name on a button: spells, items, and macros that cast a spell or use an item.
local slotCache = {}
local function ButtonSpell(b)
  local action = b.action or (b.CalculateAction and b:CalculateAction()) or (b.GetAttribute and b:GetAttribute("action"))
  if not action or isSecret(action) then return nil end
  local cached = slotCache[action]
  if cached ~= nil then return cached or nil end
  local kind, id, subType = GetActionInfo(action)
  if isSecret(kind) or isSecret(id) then return nil end
  local name
  if kind == "spell" then
    name = ns.SpellName(id)
  elseif kind == "item" then
    name = ns.ItemName(id)
    if not name then return nil end -- (not loaded yet: ask again next time)
  elseif kind == "macro" then
    -- newer clients hand back the spell the macro casts (subType "spell"); older ones the
    -- macro's index, to ask which spell it casts
    if subType == "spell" then name = ns.SpellName(id) end
    if not name and GetMacroSpell then
      local ok, sid = pcall(GetMacroSpell, id)
      if ok and not isSecret(sid) then name = ns.SpellName(sid) end
    end
    if not name and subType == "item" then name = ns.ItemName(id) end
    if not name and GetMacroItem then -- (a macro that uses an item: /use Healing Potion)
      local ok, iname = pcall(GetMacroItem, id)
      if ok and not isSecret(iname) and type(iname) == "string" then name = iname end
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
-- The burst (Blizzard's 0.7 s start) plays on a copy of its own, and the steady glow fades in
-- under its last part while it fades out: the two overlap, so there's no snap where they meet
-- (Blizzard's burst ends a little smaller than the glow).
local BURST_HANDOVER_AT, BURST_HANDOVER = 0.45, 0.25

-- Blizzard's burst (the start flipbook) is a fixed 150 px, drawn for its own alert frame of 63 px
-- (a 45 px button at 1.4x), while the steady glow fills the frame. With any other button size or
-- glow size the burst would end bigger or smaller than the glow and snap. Keep it in proportion.
local BURST_RATIO = 150 / 63
local function FitBurst(frame, w, h) -- w, h: the glow frame's size
  local t = frame and frame.ProcStartFlipbook
  if not t then return end
  if type(w) == "number" and w > 0 then t:SetSize(w * BURST_RATIO, h * BURST_RATIO) end
end

local function GlowFrame(b, scale)
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
    -- the pulse ("while on: pulse"): a frame of its own around the glow that gently breathes
    local pulse = CreateFrame("Frame", nil, parent)
    pulse:SetAllPoints(b)
    local ag = pulse:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0.35); fade:SetDuration(0.75); fade:SetSmoothing("IN_OUT")
    b.SG_Pulse, b.SG_PulseAnim = pulse, ag
    -- the steady glow's fade-in under a burst (see Start)
    local lead = CreateFrame("Frame", nil, pulse)
    lead:SetAllPoints(b)
    local la = lead:CreateAnimationGroup()
    la:SetToFinalAlpha(true)
    local hold = la:CreateAnimation("Alpha"); hold:SetOrder(1); hold:SetFromAlpha(0); hold:SetToAlpha(0); hold:SetDuration(BURST_HANDOVER_AT)
    local rise = la:CreateAnimation("Alpha"); rise:SetOrder(2); rise:SetFromAlpha(0); rise:SetToAlpha(1); rise:SetDuration(BURST_HANDOVER); rise:SetSmoothing("OUT")
    b.SG_Lead, b.SG_LeadAnim = lead, la
    glow = CreateFrame("Frame", nil, lead, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.SG_Glow = glow
  end
  scale = scale or ns.NEW_RULE.scale
  local w, h = b:GetSize()
  -- resized only when the size or the button changes (Edit Mode icon size): this runs on every update
  if b.SG_Scale ~= scale or b.SG_W ~= w or b.SG_H ~= h then
    b.SG_Scale, b.SG_W, b.SG_H = scale, w, h
    glow:SetSize(w * scale, h * scale)
    if b.SG_Shine then b.SG_Shine:SetSize(w * scale, h * scale) end
    FitBurst(glow, w * scale, h * scale); FitBurst(b.SG_Shine, w * scale, h * scale)
  end
  return glow
end


-- set one gate from a hidden value; false if the client can't do it
local function SetGate(g, gate)
  if gate.kind == "bool" then
    -- (inverted: open when the hidden value is false, for "Rule X is inactive")
    if g.SetAlphaFromBoolean then g:SetAlphaFromBoolean(gate.v, gate.invert and 0 or 1, gate.invert and 1 or 0); return true end
    return false
  end
  if gate.kind == "pct" then
    -- the game turns the hidden health / mana into 1 (condition holds) or 0 through the curve
    local ok, v
    if gate.what == "health" then
      if not UnitHealthPercent then return false end
      ok, v = pcall(UnitHealthPercent, gate.unit, true, gate.curve)
    else
      if not UnitPowerPercent then return false end
      local pt = gate.powerType or ((Enum and Enum.PowerType and Enum.PowerType.Mana) or 0)
      ok, v = pcall(UnitPowerPercent, gate.unit, pt, false, gate.curve)
    end
    if not ok or v == nil then return false end
    return (pcall(g.SetAlpha, g, v))
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
  local gw, gh = glow:GetSize()
  sh:SetSize(gw, gh)
  FitBurst(sh, gw, gh)
  return sh
end

-- the burst's own frame (made once per button)
local function BurstFrame(b, glow)
  local bf = b.SG_Burst
  if not bf then
    bf = CreateFrame("Frame", nil, glow:GetParent():GetParent(), "ActionButtonSpellAlertTemplate") -- beside the glow's fade frame
    bf:SetPoint("CENTER", b, "CENTER", 0, 0)
    if bf.ProcLoopFlipbook then bf.ProcLoopFlipbook:SetAlpha(0) end
    if bf.ProcAltGlow then bf.ProcAltGlow:SetAlpha(0) end
    -- just the burst: when it ends it doesn't go on into a loop of its own
    bf.ProcStartAnim:SetScript("OnFinished", function() bf:Hide() end)
    local out = bf:CreateAnimationGroup()
    local keep = out:CreateAnimation("Alpha"); keep:SetOrder(1); keep:SetFromAlpha(1); keep:SetToAlpha(1); keep:SetDuration(BURST_HANDOVER_AT)
    local fall = out:CreateAnimation("Alpha"); fall:SetOrder(2); fall:SetFromAlpha(1); fall:SetToAlpha(0); fall:SetDuration(BURST_HANDOVER); fall:SetSmoothing("IN")
    out:SetToFinalAlpha(true)
    bf.SG_Out = out
    bf:Hide()
    b.SG_Burst = bf
  end
  local gw, gh = glow:GetSize()
  bf:SetSize(gw, gh)
  FitBurst(bf, gw, gh)
  bf:SetFrameLevel(glow:GetFrameLevel() + 1)
  return bf
end
local function StopBurst(b)
  local bf = b.SG_Burst
  if bf and bf:IsShown() then bf.ProcStartAnim:Stop(); bf.SG_Out:Stop(); bf:Hide() end
  if b.SG_LeadAnim and b.SG_LeadAnim:IsPlaying() then b.SG_LeadAnim:Stop() end
  if b.SG_Lead then b.SG_Lead:SetAlpha(1) end
end

local function StopShine(b)
  local sh = b.SG_Shine
  if sh and sh:IsShown() then sh.SG_Anim:Stop(); sh.ProcLoop:Stop(); sh:Hide() end
end

local function StopShape(b)
  if b.SG_ShapeOn then
    local G2 = type(EllesmereUI) == "table" and EllesmereUI.Glows
    local stop = G2 and (G2.StopAllGlows or G2.StopShapeGlow)
    if stop then pcall(stop, b.SG_ShapeWrap) end
    b.SG_ShapeHost:Hide()
    b.SG_ShapeOn = nil
  end
end

local function Hide(b)
  local glow = b.SG_Glow
  StopShine(b); StopBurst(b); StopShape(b)
  if not glow or not glow:IsShown() then return end
  glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop()
  glow:Hide()
end

-- start the glow in the chosen style:
--   "glow"  = just the looping glow, no start animation
--   "shine" = the looping glow, with a brief flare when it starts
--   "burst" = Blizzard's own start (the zoom-in burst), then the loop
-- the glow's colour: Blizzard's gold art as is, or a grey copy tinted (clean colours, not muddy)
local function Tint(frame, r, g, b)
  if not frame then return end
  for _, key in ipairs({ "ProcStartFlipbook", "ProcLoopFlipbook", "ProcAltGlow" }) do
    local t = frame[key]
    if t and t.SetVertexColor then
      if r then t:SetDesaturated(true); t:SetVertexColor(r, g, b)
      else t:SetDesaturated(false); t:SetVertexColor(1, 1, 1) end
    end
  end
end

local function Start(b, glow, style)
  style = style or ns.NEW_RULE.startStyle
  glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop()
  StopBurst(b)
  if style == "burst" then
    -- the glow itself goes straight to its loop, faded in as the burst (on its own frame) fades out
    if glow.ProcStartFlipbook then glow.ProcStartFlipbook:SetAlpha(0) end
    if glow.ProcLoopFlipbook then glow.ProcLoopFlipbook:SetAlpha(1) end
    glow:Show()
    glow.ProcLoop:Play()
    b.SG_Lead:SetAlpha(0); b.SG_LeadAnim:Play()
    local bf = BurstFrame(b, glow)
    if bf.ProcStartFlipbook then bf.ProcStartFlipbook:SetAlpha(1) end
    bf:SetAlpha(1); bf:Show()
    bf.ProcStartAnim:Play(); bf.SG_Out:Play()
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
local function Show(b, gates, rule)
  local style, motion, scale, alpha = ns.RuleLook(rule) -- this rule's look
  local glow = GlowFrame(b, scale)
  local n = gates and #gates or 0
  for i, g in ipairs(b.SG_Gates) do
    if i <= n then
      if not SetGate(g, gates[i]) then Hide(b); return end
    else
      g:SetAlpha(1)
    end
  end
  glow:SetAlpha(alpha)
  -- colour (and the shine's, so its flare matches)
  local r, gg, bb = ns.RuleGlowRGB(rule)
  -- EllesmereUI mode: on its shaped buttons, its shape glow; elsewhere, the rule's EllesmereUI glow style
  -- if it has one. Both drawn inside the same gates, so the conditions work the same.
  local mask, border = EllesmereShape(b)
  local euiIdx = (not mask) and ns.EUIStyleIndex(rule) or nil
  if mask or euiIdx then
    if glow:IsShown() then glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop(); glow:Hide() end
    StopShine(b); StopBurst(b)
    if not b.SG_ShapeHost then
      local host = CreateFrame("Frame", nil, b.SG_Lead)
      host:SetAllPoints(b)
      b.SG_ShapeHost = host
      b.SG_ShapeWrap = CreateFrame("Frame", nil, host)
      b.SG_ShapeWrap:SetAllPoints(b)
    end
    b.SG_Lead:SetAlpha(1)
    b.SG_ShapeHost:SetAlpha(alpha)
    local w, h = b:GetSize()
    local key = table.concat({ mask or "", euiIdx or 0, tostring(r), tostring(gg), tostring(bb), w or 0, h or 0 }, "|")
    if b.SG_ShapeOn ~= key then
      local E = EllesmereUI.Glows
      if b.SG_ShapeOn and E.StopAllGlows then pcall(E.StopAllGlows, b.SG_ShapeWrap) end
      b.SG_ShapeHost:Show(); b.SG_ShapeWrap:Show()
      local ok
      if mask then
        ok = pcall(E.StartShapeGlow, b.SG_ShapeWrap, math.min(w or 36, h or 36),
          r or 1, gg or 0.79, bb or 0.14, 1.2, { maskPath = mask, borderPath = border, anchorFrame = b.SG_ShapeHost })
      else
        ok = pcall(E.StartGlow, b.SG_ShapeWrap, euiIdx, w or 36, r or 1, gg or 0.79, bb or 0.14, nil, h or 36)
      end
      if ok then b.SG_ShapeOn = key else b.SG_ShapeHost:Hide(); b.SG_ShapeOn = nil end
    end
    if b.SG_ShapeOn then
      if motion == "pulse" then
        if not b.SG_PulseAnim:IsPlaying() then b.SG_PulseAnim:Play() end
      elseif b.SG_PulseAnim:IsPlaying() then
        b.SG_PulseAnim:Stop(); b.SG_Pulse:SetAlpha(1)
      end
      return
    end
  elseif b.SG_ShapeOn then
    StopShape(b)
  end
  Tint(glow, r, gg, bb); Tint(b.SG_Shine, r, gg, bb); Tint(b.SG_Burst, r, gg, bb)
  -- while on: steady, or a gentle pulse
  if motion == "pulse" then
    if not b.SG_PulseAnim:IsPlaying() then b.SG_PulseAnim:Play() end
  elseif b.SG_PulseAnim:IsPlaying() then
    b.SG_PulseAnim:Stop(); b.SG_Pulse:SetAlpha(1)
  end
  if not glow:IsShown() then Start(b, glow, style); Tint(b.SG_Shine, r, gg, bb); Tint(b.SG_Burst, r, gg, bb) end
end

-- style or size changed: restart every glow so the change shows
function G.Restyle()
  for _, b in ipairs(Buttons()) do Hide(b) end
  buttons = nil -- (look again: EllesmereUI mode adds or drops its buttons)
  G.Update()
end

-- One condition row: true, or false and why. A health row in combat returns true plus a gate
-- (the game decides it).
function G.CheckAura(rule, a)
  if a.kind == "health" or a.kind == "mana" then
    local what = a.kind
    local unit = (a.unit == "target") and "target" or "player"
    local who = unit == "target" and "your target" or "you"
    local pct = math.max(0, math.min(100, tonumber(a.pct) or 40))
    local op = S.Op(a)
    local words = S.OPS[op]
    if not UnitExists(unit) then return false, "no target" end
    if S.IsDead(unit) then return false, who .. (unit == "target" and " is dead" or " are dead") end
    local v, why
    if what == "health" then v, why = S.HealthPct(unit) else v, why = S.ManaPct(unit) end
    if why == "nomana" then return false, who .. (unit == "target" and " has no mana" or " have no mana") end
    if v then
      if S.OpMeets(op, v, pct) then return true end
      return false, format("%s at %d%% %s (needs %s %d%%)", who, math.floor(v + 0.5), what, words, pct)
    end
    local api = (what == "health") and UnitHealthPercent or UnitPowerPercent
    local gs = {}
    for _, st in ipairs(S.OpSteps(op, pct, 1)) do
      local curve = S.StepCurve(st[1], st[2])
      if not (curve and api) then return false, format("%s %s is hidden, and this client can't check it", who, what) end
      gs[#gs + 1] = { kind = "pct", what = what, unit = unit, mode = st[1], pct = st[2], curve = curve }
    end
    return true, nil, gs
  end
  if S.POWER[a.kind] then
    -- Combo Points, Rage and Energy: >, >=, <, <=, = an amount
    local kind, p = a.kind, S.POWER[a.kind]
    local max = S.PowerMax(kind)
    local n = math.floor(tonumber(a.pct) or (kind == "combo" and 5 or 50))
    n = math.max(0, math.min(max, n))
    local op = S.Op(a)
    local words = S.OPS[op]
    local v, why = S.PowerAmount(kind)
    if v then
      if S.OpMeets(op, v, n) then return true end
      return false, format("%d %s (needs %s %d)", v, p.label, words, n)
    end
    if why == "stale" then return false, "combo points unknown since you changed target (until you gain one)" end
    if not UnitPowerPercent then return false, format("your %s are hidden, and this client can't check them", p.label) end
    local gs = {}
    for _, st in ipairs(S.OpSteps(op, n, 100 / max)) do
      local curve = S.StepCurve(st[1], st[2])
      if not curve then return false, format("your %s are hidden, and this client can't check them", p.label) end
      gs[#gs + 1] = { kind = "pct", what = kind, unit = "player", mode = st[1], pct = st[2], curve = curve, powerType = p.type }
    end
    return true, nil, gs
  end
  if a.kind == "rule" then
    -- "Rule X is (not) active": that rule's own conditions met right now
    local other = ns.RuleById(a.rule)
    if not other then return false, "pick a rule" end
    if other == rule then return false, "a rule can't depend on itself" end
    local label = ns.RuleLabel(other)
    local on, why, gs = G.Evaluate(other)
    if a.mode ~= "missing" then
      if not on then return false, format("rule %s isn't active (%s)", label, why or "?") end
      return true, nil, gs
    end
    if not on then return true end
    if not gs or #gs == 0 then return false, format("rule %s is active", label) end
    -- it hangs on a hidden value: "inactive" is that value flipped, which works for one of them
    if #gs == 1 then
      local g = gs[1]
      if g.kind == "bool" then return true, nil, { { kind = "bool", v = g.v, invert = not g.invert } } end
      if g.kind == "pct" then
        local mode = S.OPPOSITE[g.mode]
        local curve = mode and S.StepCurve(mode, g.pct)
        if curve then return true, nil, { { kind = "pct", what = g.what, unit = g.unit, mode = mode, pct = g.pct, curve = curve, powerType = g.powerType } } end
      end
    end
    return false, format("can't tell in combat whether rule %s is inactive: it hangs on several hidden values", label)
  end
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
local evaluating = {}
local Evaluate
-- (a rule that needs another rule that needs it back can't be decided: say so instead of looping)
function G.Evaluate(rule)
  if evaluating[rule] then return false, "rules depend on each other in a loop" end
  evaluating[rule] = true
  local ok, on, why, gates = pcall(Evaluate, rule)
  evaluating[rule] = nil
  if not ok then return false, "error: " .. tostring(on) end
  return on, why, gates
end

function Evaluate(rule)
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
  -- Gates (conditions the game decides, like health in combat) can only all-hold together:
  -- they're layers of alpha that multiply. So within "any one of" (or across OR groups) one
  -- gated choice can stand in for the rest; two can't.
  local function GroupOK(g)
    local any = (rule.groupModes and rule.groupModes[g]) == "any"
    local whys, gated, gatedN, mine = {}, nil, 0, {}
    for _, a in ipairs(groups[g]) do
      local ok, why, gs = G.CheckAura(rule, a)
      if any then
        if ok and not gs then return true end -- plainly true: enough
        if ok then gated, gatedN = gs, gatedN + 1 else whys[#whys + 1] = why end
      else
        if not ok then return false, why end
        for _, x in ipairs(gs or {}) do mine[#mine + 1] = x end
      end
    end
    if any then
      if gatedN == 1 then return true, nil, gated end
      if gatedN > 1 then return false, "two hidden health / mana checks in one \"any one\" group can't be decided" end
      return false, (#whys == 1) and whys[1] or ("none of: " .. table.concat(whys, "; or "))
    end
    return true, nil, mine
  end
  if #gids > 0 then
    if rule.join == "or" then
      local whys, gatedSets = {}, {}
      local okPlain = false
      for _, g in ipairs(gids) do
        local ok, why, gs = GroupOK(g)
        if ok and (not gs or #gs == 0) then okPlain = true; break end
        if ok then gatedSets[#gatedSets + 1] = gs else whys[#whys + 1] = why end
      end
      if not okPlain then
        if #gatedSets == 1 then
          for _, x in ipairs(gatedSets[1]) do gates[#gates + 1] = x end
        elseif #gatedSets > 1 then
          return false, "two OR groups with hidden health / mana checks can't be decided"
        else
          return false, (#whys == 1) and whys[1] or ("no group holds: " .. table.concat(whys, " / "))
        end
      end
    else
      for _, g in ipairs(gids) do
        local ok, why, gs = GroupOK(g)
        if not ok then return false, why end
        for _, x in ipairs(gs or {}) do gates[#gates + 1] = x end
      end
    end
  end
  if rule.proc and not S.Flagged(name) then return false, "not flagged as a proc" end
  local item = ns.RuleItem(rule)
  if rule.ready and not S.Ready(name, item) then return false, "on cooldown" end
  if rule.usable then
    local u = S.Usable(name, item)
    if isSecret(u) then gates[#gates + 1] = { kind = "bool", v = u }
    elseif not u then return false, item and "not usable (none in your bags, or can't use it now)" or "not castable (mana / not known)" end
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

local verdict, byRule, lastUpdate, idle = {}, {}, 0, false
function G.Update()
  lastUpdate = GetTime()
  -- no rules: hide whatever still glows once, then there's nothing to do
  if #ns.db.rules == 0 then
    if not idle then for _, b in ipairs(Buttons()) do Hide(b) end; idle = true end
    return
  end
  idle = false
  -- per spell: "plain" (glow), a gates list (the client decides), or nothing
  wipe(verdict); wipe(byRule) -- byRule: which rule's colour a spell glows in
  local testing = GetTime() < testUntil
  for _, rule in ipairs(ns.db.rules) do
    local name = ns.RuleSpellName(rule)
    if name and verdict[name] ~= "plain" then
      if testing then
        if rule.enabled then verdict[name] = "plain"; byRule[name] = rule end
      else
        local on, _, gates = G.Evaluate(rule)
        if on then
          -- several rules for one spell: a plain yes wins, else the first rule the game decides
          if not gates or #gates == 0 then verdict[name] = "plain"; byRule[name] = rule
          elseif verdict[name] == nil then verdict[name] = gates; byRule[name] = rule end
        end
      end
    end
  end
  for _, b in ipairs(Buttons()) do
    local name = b:IsVisible() and ButtonSpell(b)
    local v = name and verdict[name]
    if v == "plain" then Show(b, nil, byRule[name])
    elseif type(v) == "table" then Show(b, v, byRule[name])
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
-- events can come many times a second in combat (power, auras, cooldowns): update at most
-- every 0.05 s, which still feels instant
local pending = false
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(math.max(0, 0.05 - (GetTime() - lastUpdate)), function() pending = false; G.Update() end)
end
G.Soon = Soon

function G.Init()
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "ACTIONBAR_PAGE_CHANGED",
    "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_COMBAT", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(ev.RegisterUnitEvent, ev, e, "player")
  end
  pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player", "target")
  -- health rows (outside combat: read; in combat: the game re-applies the curve when we update)
  pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "player", "target")
  pcall(ev.RegisterUnitEvent, ev, "UNIT_MAXHEALTH", "player", "target")
  -- mana rows (your target's too)
  pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_FREQUENT", "player", "target")
  pcall(ev.RegisterUnitEvent, ev, "UNIT_MAXPOWER", "player", "target")
  ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
    if event == "UNIT_COMBAT" then
      S.OnUnitCombat(a2, a3, a4, a5)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      S.OnCast(a3)
    elseif event == "PLAYER_TARGET_CHANGED" then
      S.OnTargetChanged()
    elseif event == "COMBO_TARGET_CHANGED" then
      S.OnComboTarget()
    elseif (event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE") and a1 == "player" then
      S.OnPower(a2)
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
