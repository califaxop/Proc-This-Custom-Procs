-- The glow itself, on Blizzard's action buttons: Blizzard's own retail alert
-- (ActionButtonSpellAlertTemplate), as its own frame on the button. Blizzard's alert manager is
-- never touched, so the buttons stay untainted.
local _, ns = ...
local G = {}
ns.Glow = G
local S = ns.State
local isSecret = ns.isSecret
local API = ns.API

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
local function HasEllesmere() return ns.HasEllesmere() end

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
local function ButtonAction(b)
  local action = b.action or (b.CalculateAction and b:CalculateAction()) or (b.GetAttribute and b:GetAttribute("action"))
  if not action or isSecret(action) then return nil end
  return action
end
local function ButtonSpell(b)
  local action = ButtonAction(b)
  if not action then return nil end
  local cached = slotCache[action]
  if cached ~= nil then return cached or nil end
  local ok, kind, id, subType = API.Call("ActionInfo", action)
  if not ok or isSecret(kind) or isSecret(id) then return nil end
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
    if not name then
      local okS, sid = API.Call("MacroSpell", id)
      if okS and not isSecret(sid) then name = ns.SpellName(sid) end
    end
    if not name and subType == "item" then name = ns.ItemName(id) end
    if not name then -- (a macro that uses an item: /use Healing Potion)
      local okI, iname = API.Call("MacroItem", id)
      if okI and not isSecret(iname) and type(iname) == "string" then name = iname end
    end
    return name -- not cached: a macro with [conditions] can switch spells at any moment
  end
  slotCache[action] = name or false
  return name
end
function G.ForgetSlots() wipe(slotCache) end

-- /pt buttons: every shown button with a macro, or a rule's spell or item: what it holds and what
-- Proc This! reads it as right now (macros follow their [conditions])
function G.ButtonReport()
  local ruled, lines = {}, {}
  for _, r in ipairs(ns.db.rules) do local n = ns.RuleSpellName(r); if n then ruled[n] = true end end
  for _, b in ipairs(Buttons()) do
    local action = b:IsVisible() and ButtonAction(b)
    if action then
      local ok, kind = API.Call("ActionInfo", action)
      kind = ok and not isSecret(kind) and kind or nil
      local name = ButtonSpell(b)
      if kind == "macro" or (name and ruled[name]) then
        lines[#lines + 1] = format("%s (slot %d): %s%s%s", b:GetName() or "?", action, kind or "?",
          kind == "macro" and (" -> " .. (name or "|cffff6060nothing Proc This! can read|r")) or (" " .. (name or "?")),
          (name and ruled[name]) and " |cff60ff60(has a rule)|r" or "")
      end
    end
  end
  if #lines == 0 then lines[1] = "no shown buttons with a macro or a rule's spell." end
  return lines
end

-- The glow sits inside a chain of "gate" frames on the button. Alphas multiply, so each gate
-- is one more condition: open (1) or shut (0). Gates are how conditions the game hides
-- (e.g. castable) still work: the client sets their alpha from the hidden value,
-- without Proc This! ever reading it.
-- A button can carry several such glows ("layers", 1.17.0): one per term of a gate set (Result.lua),
-- made exclusive, so an OR of hidden conditions works too and only one layer shows at a time.
-- A layer: { btn, gates (frames), pulse, pulseAnim, lead, leadAnim, glow, shine, burst, shapeHost,
-- shapeWrap, shapeOn, scale, w, h }, kept in btn.SG_Layers.
local R = ns.Result
local MAX_GATES = R.MAX_GATES
local MAX_LAYERS = 4
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

local function Layer(b, i)
  b.SG_Layers = b.SG_Layers or {}
  local L = b.SG_Layers[i]
  if not L then L = { btn = b }; b.SG_Layers[i] = L end
  return L
end

local function GlowFrame(L, scale)
  local b = L.btn
  local glow = L.glow
  if not glow then
    L.gates = {}
    local parent = b
    for i = 1, MAX_GATES do
      local g = CreateFrame("Frame", nil, parent)
      g:SetAllPoints(b)
      L.gates[i] = g
      parent = g
    end
    -- the pulse ("while on: pulse"): a frame of its own around the glow that gently breathes
    local pulse = CreateFrame("Frame", nil, parent)
    pulse:SetAllPoints(b)
    local ag = pulse:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0.35); fade:SetDuration(0.75); fade:SetSmoothing("IN_OUT")
    L.pulse, L.pulseAnim = pulse, ag
    -- the steady glow's fade-in under a burst (see Start)
    local lead = CreateFrame("Frame", nil, pulse)
    lead:SetAllPoints(b)
    local la = lead:CreateAnimationGroup()
    la:SetToFinalAlpha(true)
    local hold = la:CreateAnimation("Alpha"); hold:SetOrder(1); hold:SetFromAlpha(0); hold:SetToAlpha(0); hold:SetDuration(BURST_HANDOVER_AT)
    local rise = la:CreateAnimation("Alpha"); rise:SetOrder(2); rise:SetFromAlpha(0); rise:SetToAlpha(1); rise:SetDuration(BURST_HANDOVER); rise:SetSmoothing("OUT")
    L.lead, L.leadAnim = lead, la
    glow = CreateFrame("Frame", nil, lead, "ActionButtonSpellAlertTemplate")
    glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    L.glow = glow
  end
  scale = scale or ns.NEW_RULE.scale
  local w, h = b:GetSize()
  -- resized only when the size or the button changes (Edit Mode icon size): this runs on every update
  if L.scale ~= scale or L.w ~= w or L.h ~= h then
    L.scale, L.w, L.h = scale, w, h
    glow:SetSize(w * scale, h * scale)
    if L.shine then L.shine:SetSize(w * scale, h * scale) end
    FitBurst(glow, w * scale, h * scale); FitBurst(L.shine, w * scale, h * scale)
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
      ok, v = API.Call("HealthPercent", gate.unit, true, gate.curve)
    else
      local pt = gate.powerType or ((Enum and Enum.PowerType and Enum.PowerType.Mana) or 0)
      ok, v = API.Call("PowerPercent", gate.unit, pt, false, gate.curve)
    end
    if not ok or v == nil then return false end
    return (pcall(g.SetAlpha, g, v))
  end
  return false
end

-- Shine: a second copy of the glow, added on top (additive) and faded out, so the glow flares
-- briefly when it starts, then settles at its normal intensity.
local function ShineFrame(L, glow)
  local b = L.btn
  local sh = L.shine
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
    L.shine = sh
  end
  local gw, gh = glow:GetSize()
  sh:SetSize(gw, gh)
  FitBurst(sh, gw, gh)
  return sh
end

-- the burst's own frame (made once per button)
local function BurstFrame(L, glow)
  local b = L.btn
  local bf = L.burst
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
    L.burst = bf
  end
  local gw, gh = glow:GetSize()
  bf:SetSize(gw, gh)
  FitBurst(bf, gw, gh)
  bf:SetFrameLevel(glow:GetFrameLevel() + 1)
  return bf
end
local function StopBurst(L)
  local bf = L.burst
  if bf and bf:IsShown() then bf.ProcStartAnim:Stop(); bf.SG_Out:Stop(); bf:Hide() end
  if L.leadAnim and L.leadAnim:IsPlaying() then L.leadAnim:Stop() end
  if L.lead then L.lead:SetAlpha(1) end
end

local function StopShine(L)
  local sh = L.shine
  if sh and sh:IsShown() then sh.SG_Anim:Stop(); sh.ProcLoop:Stop(); sh:Hide() end
end

local function StopShape(L)
  if L.shapeOn then
    local G2 = type(EllesmereUI) == "table" and EllesmereUI.Glows
    local stop = G2 and (G2.StopAllGlows or G2.StopShapeGlow)
    if stop then pcall(stop, L.shapeWrap) end
    L.shapeHost:Hide()
    L.shapeOn = nil
  end
end

local function HideLayer(L)
  local glow = L.glow
  StopShine(L); StopBurst(L); StopShape(L)
  if not glow or not glow:IsShown() then return end
  glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop()
  glow:Hide()
end

-- every layer on a button, from layer `from` on (default: all)
local function Hide(b, from)
  for i, L in ipairs(b.SG_Layers or {}) do if i >= (from or 1) then HideLayer(L) end end
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

local function Start(L, glow, style)
  style = style or ns.NEW_RULE.startStyle
  glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop()
  StopBurst(L)
  if style == "burst" then
    -- the glow itself goes straight to its loop, faded in as the burst (on its own frame) fades out
    if glow.ProcStartFlipbook then glow.ProcStartFlipbook:SetAlpha(0) end
    if glow.ProcLoopFlipbook then glow.ProcLoopFlipbook:SetAlpha(1) end
    glow:Show()
    glow.ProcLoop:Play()
    L.lead:SetAlpha(0); L.leadAnim:Play()
    local bf = BurstFrame(L, glow)
    if bf.ProcStartFlipbook then bf.ProcStartFlipbook:SetAlpha(1) end
    bf:SetAlpha(1); bf:Show()
    bf.ProcStartAnim:Play(); bf.SG_Out:Play()
  else
    if glow.ProcStartFlipbook then glow.ProcStartFlipbook:SetAlpha(0) end
    if glow.ProcLoopFlipbook then glow.ProcLoopFlipbook:SetAlpha(1) end
    glow:Show()
    glow.ProcLoop:Play()
    if style == "shine" then
      local sh = ShineFrame(L, glow)
      sh.SG_Anim:Stop(); sh:SetAlpha(0); sh:Show()
      sh.ProcLoop:Play(); sh.SG_Anim:Play()
    end
  end
end

-- one layer: gates nil/empty = glow plainly; otherwise the hidden conditions the client decides
local function ShowLayer(L, gates, rule)
  local b = L.btn
  local style, motion, scale, alpha = ns.RuleLook(rule) -- this rule's look
  local glow = GlowFrame(L, scale)
  local n = gates and #gates or 0
  for i, g in ipairs(L.gates) do
    if i <= n then
      if not SetGate(g, gates[i]) then HideLayer(L); return end
    else
      g:SetAlpha(1)
    end
  end
  glow:SetAlpha(alpha)
  -- colour (and the shine's, so its flare matches)
  local r, gg, bb = ns.RuleGlowRGB(rule)
  -- with EllesmereUI: on its shaped buttons, its shape glow; elsewhere, the rule's EllesmereUI glow style
  -- if it has one. Both drawn inside the same gates, so the conditions work the same.
  local mask, border = EllesmereShape(b)
  local euiIdx = (not mask) and ns.EUIStyleIndex(rule) or nil
  if mask or euiIdx then
    if glow:IsShown() then glow.ProcStartAnim:Stop(); glow.ProcLoop:Stop(); glow:Hide() end
    StopShine(L); StopBurst(L)
    if not L.shapeHost then
      local host = CreateFrame("Frame", nil, L.lead)
      host:SetAllPoints(b)
      L.shapeHost = host
      L.shapeWrap = CreateFrame("Frame", nil, host)
      L.shapeWrap:SetAllPoints(b)
    end
    L.lead:SetAlpha(1)
    L.shapeHost:SetAlpha(alpha)
    local w, h = b:GetSize()
    local key = table.concat({ mask or "", euiIdx or 0, tostring(r), tostring(gg), tostring(bb), w or 0, h or 0 }, "|")
    if L.shapeOn ~= key then
      local E = EllesmereUI.Glows
      if L.shapeOn and E.StopAllGlows then pcall(E.StopAllGlows, L.shapeWrap) end
      L.shapeHost:Show(); L.shapeWrap:Show()
      local ok
      if mask then
        ok = pcall(E.StartShapeGlow, L.shapeWrap, math.min(w or 36, h or 36),
          r or 1, gg or 0.79, bb or 0.14, 1.2, { maskPath = mask, borderPath = border, anchorFrame = L.shapeHost })
      else
        ok = pcall(E.StartGlow, L.shapeWrap, euiIdx, w or 36, r or 1, gg or 0.79, bb or 0.14, nil, h or 36)
      end
      if ok then L.shapeOn = key else L.shapeHost:Hide(); L.shapeOn = nil end
    end
    if L.shapeOn then
      if motion == "pulse" then
        if not L.pulseAnim:IsPlaying() then L.pulseAnim:Play() end
      elseif L.pulseAnim:IsPlaying() then
        L.pulseAnim:Stop(); L.pulse:SetAlpha(1)
      end
      return
    end
  elseif L.shapeOn then
    StopShape(L)
  end
  Tint(glow, r, gg, bb); Tint(L.shine, r, gg, bb); Tint(L.burst, r, gg, bb)
  -- while on: steady, or a gentle pulse
  if motion == "pulse" then
    if not L.pulseAnim:IsPlaying() then L.pulseAnim:Play() end
  elseif L.pulseAnim:IsPlaying() then
    L.pulseAnim:Stop(); L.pulse:SetAlpha(1)
  end
  if not glow:IsShown() then Start(L, glow, style); Tint(L.shine, r, gg, bb); Tint(L.burst, r, gg, bb) end
end

-- a button's glow: layers = { { gates, rule }, ... } (one plain layer: { { rule = r } })
local function Show(b, layers)
  for i, l in ipairs(layers) do ShowLayer(Layer(b, i), l, l.rule) end
  Hide(b, #layers + 1)
end

-- style or size changed: restart every glow so the change shows
function G.Restyle()
  for _, b in ipairs(Buttons()) do Hide(b) end
  buttons = nil -- (look again: EllesmereUI adds or drops its buttons)
  G.Update()
end

-- Results (Result.lua): TRUE / FALSE / GATED / UNKNOWN / ERROR, with why and (GATED) the gate set.

-- a gate's opposite (for "Rule X is inactive", "missing" rows, and exclusive layers), or nil if it
-- has none. The two know each other (gate.inv): a term holding both can never hold.
local function InvertGate(g)
  if g.inv then return g.inv end
  local ng
  if g.kind == "bool" then ng = { kind = "bool", v = g.v, invert = not g.invert } end
  if g.kind == "pct" then
    local mode = S.OPPOSITE[g.mode]
    local curve = mode and S.StepCurve(mode, g.pct)
    if curve then ng = { kind = "pct", what = g.what, unit = g.unit, mode = mode, pct = g.pct, curve = curve, powerType = g.powerType } end
  end
  if ng then g.inv, ng.inv = ng, g end
  return ng
end
G.InvertGate = InvertGate

-- how an aura was told, for the explanations
local SOURCE = { aura = "read directly", exact = "read directly", hidden = "seen (details hidden)",
  cdm = "the Cooldown Manager", estimate = "estimate", unknown = "can't tell" }
G.SOURCE = SOURCE

-- One condition row: status, why, gates (see Result.lua). A health row in combat is GATED (the
-- game decides).
function G.CheckAura(rule, a)
  if a.kind == "health" or a.kind == "mana" then
    local what = a.kind
    local unit = (a.unit == "target") and "target" or "player"
    local who = unit == "target" and "your target" or "you"
    local pct = math.max(0, math.min(100, tonumber(a.pct) or 40))
    local op = S.Op(a)
    local words = S.OPS[op]
    if not UnitExists(unit) then return R.FALSE, "no target" end
    if S.IsDead(unit) then return R.FALSE, who .. (unit == "target" and " is dead" or " are dead") end
    local v, why
    if what == "health" then v, why = S.HealthPct(unit) else v, why = S.ManaPct(unit) end
    if why == "nomana" then return R.FALSE, who .. (unit == "target" and " has no mana" or " have no mana") end
    if v then
      if S.OpMeets(op, v, pct) then return R.TRUE end
      return R.FALSE, format("%s at %d%% %s (needs %s %d%%)", who, math.floor(v + 0.5), what, words, pct)
    end
    local api = API.Has((what == "health") and "HealthPercent" or "PowerPercent")
    local gs = {}
    for _, st in ipairs(S.OpSteps(op, pct, 1)) do
      local curve = S.StepCurve(st[1], st[2])
      if not (curve and api) then return R.UNKNOWN, format("%s %s is hidden, and this client can't check it", who, what) end
      gs[#gs + 1] = { kind = "pct", what = what, unit = unit, mode = st[1], pct = st[2], curve = curve }
    end
    return R.GATED, nil, R.Gates(gs)
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
      if S.OpMeets(op, v, n) then return R.TRUE end
      return R.FALSE, format("%d %s (needs %s %d)", v, p.label, words, n)
    end
    if why == "stale" then return R.UNKNOWN, "combo points unknown since you changed target (until you gain one)" end
    if not API.Has("PowerPercent") then return R.UNKNOWN, format("your %s are hidden, and this client can't check them", p.label) end
    local gs = {}
    for _, st in ipairs(S.OpSteps(op, n, 100 / max)) do
      local curve = S.StepCurve(st[1], st[2])
      if not curve then return R.UNKNOWN, format("your %s are hidden, and this client can't check them", p.label) end
      gs[#gs + 1] = { kind = "pct", what = kind, unit = "player", mode = st[1], pct = st[2], curve = curve, powerType = p.type }
    end
    return R.GATED, nil, R.Gates(gs)
  end
  if a.kind == "rule" then
    -- "Rule X is (not) active": that rule's own result right now
    local other = ns.RuleById(a.rule)
    if not other then return R.UNKNOWN, "pick a rule" end
    if other == rule then return R.ERROR, "a rule can't depend on itself" end
    local label = ns.RuleLabel(other)
    local st, why, gs = G.Evaluate(other)
    if a.mode ~= "missing" then
      if st == R.FALSE then return R.FALSE, format("rule %s isn't active (%s)", label, why or "?") end
      if st == R.UNKNOWN or st == R.ERROR then return st, format("rule %s: %s", label, why or "?") end
      return st, nil, gs
    end
    local nst, nwhy, ngs = R.Not(st, why, gs, InvertGate, format("rule %s is active", label))
    if nst == R.UNKNOWN or nst == R.ERROR then return nst, format("rule %s: %s", label, nwhy or "?") end
    return nst, nwhy, ngs
  end
  if a.kind == "instant" then
    -- "Spell X is (not) instant cast": from its current cast time
    local sp = ns.AuraName(rule, a)
    if not sp then return R.UNKNOWN, "name the spell" end
    local ct = S.CastTime(sp)
    if ct == nil then return R.UNKNOWN, format("can't read %s's cast time", sp) end
    local instant = ct <= 0
    if a.mode == "missing" then
      if instant then return R.FALSE, format("%s is instant now", sp) end
      return R.TRUE
    end
    if not instant then return R.FALSE, format("%s isn't instant (%.1f s cast)", sp, ct / 1000) end
    return R.TRUE
  end
  local an = ns.AuraLabel and ns.AuraLabel(rule, a) or ns.AuraName(rule, a)
  if not an then return R.UNKNOWN, "name the aura" end
  local who = (a.unit == "target") and "your target" or "you"
  local selfOnly = (a.name or "") == "" or a.name == ns.RuleSpellName(rule)
  local has, how, detail = S.AuraPresent(a, an, selfOnly)
  if has == nil then
    return R.UNKNOWN, format("%s on %s: can't tell in combat%s (track it in the Cooldown Manager)", an, who,
      detail and (" - " .. detail) or "")
  end
  local est = (how == "estimate") and format(" (estimate: %s)", detail or "from your casts") or ""
  if a.mode == "missing" then
    if has then return R.FALSE, format("%s is on %s%s", an, who, est) end
    return R.TRUE
  end
  if not has then return R.FALSE, format("%s is not on %s%s", an, who, est) end
  return R.TRUE
end

-- A rule's result: status (Result.lua), why (for the settings window), and for GATED the gate set
-- the game decides.
-- Each rule is worked out once per pass (an update, or the settings window's status): rules that
-- several others depend on aren't evaluated again, and the hidden values read in one pass are the
-- same gates everywhere (so Result.lua can tell a gate from its opposite). A rule that needs
-- another rule that needs it back can't be decided: ERROR, naming the loop.
local pass, stack = {}, {}
function G.NewPass() wipe(pass) end

-- a reader's result, once per pass (same spell, same gate)
local function Once(key, fn, ...)
  local v = pass[key]
  if not v then v = { fn(...) }; pass[key] = v end
  return v[1], v[2], v[3]
end

local Evaluate
function G.Evaluate(rule)
  local done = pass[rule]
  if done then return done[1], done[2], done[3] end
  for i, r in ipairs(stack) do
    if r == rule then
      local names = {}
      for j = i, #stack do names[#names + 1] = ns.RuleLabel(stack[j]) end
      names[#names + 1] = ns.RuleLabel(rule)
      return R.ERROR, "rules depend on each other in a loop: " .. table.concat(names, " > ")
    end
  end
  stack[#stack + 1] = rule
  local ok, st, why, gates = pcall(Evaluate, rule)
  stack[#stack] = nil
  if not ok then st, why, gates = R.ERROR, "error: " .. tostring(st), nil end
  pass[rule] = { st, why, gates }
  return st, why, gates
end

-- one check as a result entry (a gate becomes a set of one)
local function Entry(st, why, gate)
  if st == R.GATED and gate and gate.kind then return { st, why, R.Gates({ gate }) } end
  return { st, why, gate }
end

function Evaluate(rule)
  local name = ns.RuleSpellName(rule)
  if not rule.enabled or not name then return R.FALSE, "off" end
  local checks = {}
  -- the simple checks first: a confirmed "no" here decides the rule
  if rule.combat then
    local st, why, g = Once("combat", S.InCombat)
    if st == R.FALSE then return R.FALSE, why end
    checks[#checks + 1] = Entry(st, why, g)
  end
  if rule.control then
    local st, why, g = Once("control", S.HasControl)
    if st == R.FALSE then return R.FALSE, why end
    checks[#checks + 1] = Entry(st, why, g)
  end
  if rule.melee and not S.BeingMeleed() then return R.FALSE, "not being hit in melee" end
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
  local function Group(g)
    local rows = {}
    for _, a in ipairs(groups[g]) do rows[#rows + 1] = { G.CheckAura(rule, a) } end
    if (rule.groupModes and rule.groupModes[g]) == "any" then return R.Any(rows) end
    return R.All(rows)
  end
  if #gids > 0 then
    local gres = {}
    for _, g in ipairs(gids) do gres[#gres + 1] = { Group(g) } end
    local st, why, gs
    if rule.join == "or" then st, why, gs = R.Any(gres) else st, why, gs = R.All(gres) end
    if st == R.FALSE then return R.FALSE, why end
    checks[#checks + 1] = { st, why, gs }
  end
  if rule.proc and not S.Flagged(name) then return R.FALSE, "not flagged as a proc" end
  local item = ns.RuleItem(rule)
  if rule.ready then
    local st, why, g = Once("ready|" .. name .. "|" .. tostring(item), S.Ready, name, item)
    if st == R.FALSE then return R.FALSE, why end
    checks[#checks + 1] = Entry(st, why, g)
  end
  if rule.usable then
    local st, why, g = Once("usable|" .. name .. "|" .. tostring(item), S.Usable, name, item)
    if st == R.FALSE then return R.FALSE, why end
    checks[#checks + 1] = Entry(st, why, g)
  end
  local st, why, set = R.All(checks)
  if st == R.GATED then return R.GATED, why, set end
  if st == R.TRUE then return R.TRUE, "glowing" end
  return st, why
end

local testUntil = 0
function G.Test(seconds)
  testUntil = GetTime() + (seconds or 3)
  for _, b in ipairs(Buttons()) do Hide(b) end -- so the start shows again
  G.Update()
end

-- per spell: "plain" (glow) with its rule, or the gate-set terms of its GATED rules, in rule order
local plain, terms, lastUpdate, idle = {}, {}, 0, false
function G.Update()
  lastUpdate = GetTime()
  G.NewPass()
  -- no rules: hide whatever still glows once, then there's nothing to do
  if #ns.db.rules == 0 then
    if not idle then for _, b in ipairs(Buttons()) do Hide(b) end; idle = true end
    return
  end
  idle = false
  wipe(plain); wipe(terms)
  local testing = GetTime() < testUntil
  for _, rule in ipairs(ns.db.rules) do
    local name = ns.RuleSpellName(rule)
    if name and not plain[name] then
      if testing then
        if rule.enabled then plain[name] = { { rule = rule } } end
      else
        local st, _, set = G.Evaluate(rule)
        -- several rules for one spell: a plain yes wins (the first one's look); else every GATED
        -- rule's terms, in order (the game opens whichever holds); FALSE, UNKNOWN, ERROR never glow
        if st == R.TRUE then plain[name] = { { rule = rule } }
        elseif st == R.GATED then
          local list = terms[name] or {}
          terms[name] = list
          for _, t in ipairs(set) do
            local c = { rule = rule }
            for i, g in ipairs(t) do c[i] = g end
            list[#list + 1] = c
          end
        end
      end
    end
  end
  -- the GATED terms of each spell made exclusive: one layer each
  for name, list in pairs(terms) do
    if not plain[name] then terms[name] = (R.Disjoint(list, InvertGate, MAX_LAYERS)) end
  end
  for _, b in ipairs(Buttons()) do
    local name = b:IsVisible() and ButtonSpell(b)
    local layers = name and (plain[name] or terms[name])
    if layers and #layers > 0 then Show(b, layers) else Hide(b) end
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
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED",
    "MODIFIER_STATE_CHANGED" }) do -- (a macro with [mod] conditions shows another spell)
    pcall(ev.RegisterEvent, ev, e)
  end
  for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_COMBAT", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
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
    elseif event == "UNIT_SPELLCAST_SENT" then
      S.OnSent(a2, a3)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      S.OnCast(a3, a2)
    elseif event == "PLAYER_TARGET_CHANGED" then
      S.OnTargetChanged()
    elseif event == "PLAYER_REGEN_ENABLED" then
      S.OnCombatEnd()
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
