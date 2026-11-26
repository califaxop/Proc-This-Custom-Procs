-- Sharing rules as text (1.20.0): export a rule (with the rules it uses) or all of them, import
-- them on another character or another player's game.
-- The text is "PT1:" and a plain serialization of the rules (tables, strings, numbers, booleans).
-- Importing never runs any of it: a small parser reads it back, and only the fields a rule or a
-- condition has are kept, each checked for its type and its allowed values; everything else is
-- dropped. Pure Lua apart from the rule defaults (tests/run_tests.py).
local _, ns = ...
local Share = {}
ns.Share = Share

local PREFIX = "PT1:"
local MAX_LEN, MAX_DEPTH, MAX_NODES = 60000, 6, 6000

-- writing -----------------------------------------------------------------------------------
-- strings: \ " | and line breaks escaped (| would start a colour code in an edit box)
local ESC = { ["\\"] = "\\\\", ['"'] = '\\"', ["|"] = "\\p", ["\n"] = "\\n", ["\r"] = "\\r" }
local function Str(s) return '"' .. s:gsub('[\\"|\n\r]', ESC) .. '"' end
local function Num(n)
  if n == math.floor(n) and math.abs(n) < 2 ^ 31 then return format("%d", n) end
  return format("%.6g", n)
end
local function Write(v, out)
  local t = type(v)
  if t == "boolean" then out[#out + 1] = v and "T" or "F"
  elseif t == "number" then out[#out + 1] = Num(v)
  elseif t == "string" then out[#out + 1] = Str(v)
  elseif t == "table" then
    out[#out + 1] = "{"
    -- the list part first, in order, then the named fields sorted (the same rule, the same text)
    local n = #v
    for i = 1, n do Write(v[i], out); out[#out + 1] = ";" end
    local keys = {}
    for k in pairs(v) do
      if type(k) == "string" or (type(k) == "number" and (k < 1 or k > n or k ~= math.floor(k))) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local kv = v[k]
      if type(kv) ~= "function" then
        out[#out + 1] = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. (type(k) == "number" and Num(k) or Str(k)) .. "]")
        out[#out + 1] = "="; Write(kv, out); out[#out + 1] = ";"
      end
    end
    out[#out + 1] = "}"
  end
end

-- reading -----------------------------------------------------------------------------------
local UNESC = { ["\\"] = "\\", ['"'] = '"', p = "|", n = "\n", r = "\r" }
local function Read(s)
  local pos, nodes = 1, 0
  local function fail(msg) error({ msg = msg }, 0) end
  local function skip() pos = s:find("[^%s]", pos) or (#s + 1) end
  local value
  local function str()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("a text that never ends") end
      if c == '"' then pos = pos + 1; return table.concat(out) end
      if c == "\\" then
        local e = UNESC[s:sub(pos + 1, pos + 1)]
        if not e then fail("an unknown escape") end
        out[#out + 1] = e; pos = pos + 2
      else
        local j = s:find('[\\"]', pos) or (#s + 1)
        out[#out + 1] = s:sub(pos, j - 1); pos = j
      end
    end
  end
  local function num()
    local a, b = s:find("^%-?%d+%.?%d*[eE]?[%-+]?%d*", pos)
    if not a then fail("a broken number") end
    local n = tonumber(s:sub(a, b))
    if not n or n ~= n or n == math.huge or n == -math.huge then fail("a broken number") end
    pos = b + 1
    return n
  end
  local function tbl(depth)
    if depth > MAX_DEPTH then fail("nested too deep") end
    pos = pos + 1
    local t, n = {}, 0
    while true do
      skip()
      local c = s:sub(pos, pos)
      if c == "}" then pos = pos + 1; return t end
      if c == "" then fail("a list that never ends") end
      local key
      local name = s:match("^([%a_][%w_]*)%s*=", pos)
      if name and name ~= "T" and name ~= "F" then
        key = name; pos = s:find("=", pos, true) + 1
      elseif c == "[" then
        pos = pos + 1; skip()
        local kc = s:sub(pos, pos)
        key = (kc == '"') and str() or num()
        skip()
        if s:sub(pos, pos) ~= "]" then fail("a broken key") end
        pos = pos + 1; skip()
        if s:sub(pos, pos) ~= "=" then fail("a broken key") end
        pos = pos + 1
      end
      local v = value(depth + 1)
      if key == nil then n = n + 1; key = n end
      t[key] = v
      skip()
      if s:sub(pos, pos) == ";" then pos = pos + 1 end
    end
  end
  value = function(depth)
    nodes = nodes + 1
    if nodes > MAX_NODES then fail("too long") end
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then return tbl(depth) end
    if c == '"' then return str() end
    if c == "T" then pos = pos + 1; return true end
    if c == "F" then pos = pos + 1; return false end
    if c:match("[%-%d]") then return num() end
    fail("something that isn't a rule")
  end
  local ok, v = pcall(function()
    local r = value(1)
    skip()
    if pos <= #s then fail("extra text at the end") end
    return r
  end)
  if ok then return v end
  return nil, type(v) == "table" and v.msg or tostring(v)
end

-- checking ----------------------------------------------------------------------------------
local function OneOf(...) local set = {}; for _, v in ipairs({ ... }) do set[v] = true end; return set end
local function Text(maxLen) return function(v) return type(v) == "string" and #v <= maxLen end end
local function Number(lo, hi) return function(v) return type(v) == "number" and v >= lo and v <= hi end end
local function Bool(v) return type(v) == "boolean" end
local function In(set) return function(v) return set[v] == true end end

local AURA_FIELDS = {
  name = Text(200), usedBy = Text(200),
  unit = In(OneOf("player", "target")),
  kind = In(OneOf("buff", "debuff", "instant", "health", "mana", "combo", "rage", "energy", "rule")),
  mode = In(OneOf("present", "missing")),
  op = In(OneOf("gt", "ge", "lt", "le", "eq")),
  hpMode = In(OneOf("below", "above", "atleast", "atmost")), cpMode = In(OneOf("below", "above", "atleast", "atmost")),
  mine = Bool, dur = Number(0, 600), charges = Number(0, 20), group = Number(1, 50), pct = Number(0, 100000),
  rule = Number(1, 2 ^ 31),
}
local RULE_FIELDS = {
  id = Number(1, 2 ^ 31), enabled = Bool, spell = Text(300),
  melee = Bool, usable = Bool, ready = Bool, control = Bool, combat = Bool, proc = Bool,
  color = Text(20), startStyle = Text(20), motion = Text(20), glowType = Text(40),
  scale = Number(0.3, 4), alpha = Number(0, 1), join = In(OneOf("and", "or")),
}

-- a rule as read from the text -> a clean rule (only known fields, each checked; the rest from the
-- defaults), or nil
local function CleanRule(x)
  if type(x) ~= "table" then return nil end
  local r = ns.Copy(ns.NEW_RULE)
  for k, ok in pairs(RULE_FIELDS) do if x[k] ~= nil and ok(x[k]) then r[k] = x[k] end end
  if type(x.colorCustom) == "table" then
    local c = {}
    for i = 1, 3 do local v = x.colorCustom[i]; c[i] = (type(v) == "number" and v >= 0 and v <= 1) and v or 1 end
    r.colorCustom = c
  end
  if type(x.groupModes) == "table" then
    r.groupModes = {}
    for i = 1, 50 do
      local m = x.groupModes[i]
      if m == nil then break end
      r.groupModes[i] = (m == "any") and "any" or "all"
    end
  end
  r.auras = {}
  if type(x.auras) == "table" then
    for i = 1, 60 do
      local a = x.auras[i]
      if a == nil then break end
      if type(a) == "table" then
        local c = ns.Copy(ns.NEW_AURA)
        for k, ok in pairs(AURA_FIELDS) do if a[k] ~= nil and ok(a[k]) then c[k] = a[k] end end
        r.auras[#r.auras + 1] = c
      end
    end
  end
  return r
end

-- public ------------------------------------------------------------------------------------
-- the rules (and, with `rule`, only it and the rules it uses through Rule rows) as text
function Share.Export(rules, rule)
  local pick = rules
  if rule then
    pick = {}
    local want, queue = {}, { rule }
    while #queue > 0 do
      local r = table.remove(queue, 1)
      if not want[r] then
        want[r] = true
        for _, a in ipairs(r.auras or {}) do
          if a.kind == "rule" then
            for _, y in ipairs(rules) do if y.id == a.rule then queue[#queue + 1] = y end end
          end
        end
      end
    end
    for _, r in ipairs(rules) do if want[r] then pick[#pick + 1] = r end end
  end
  local out = { PREFIX }
  Write(pick, out)
  return table.concat(out)
end

-- text -> clean rules (with the ids they had, for their Rule rows), or nil and why
function Share.Import(text)
  if type(text) ~= "string" then return nil, "nothing to import" end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if #text > MAX_LEN then return nil, "the text is too long" end
  if text:sub(1, #PREFIX) ~= PREFIX then return nil, "this isn't Proc This! rules text (it starts with " .. PREFIX .. ")" end
  local v, err = Read(text:sub(#PREFIX + 1))
  if v == nil then return nil, "the text is damaged: " .. tostring(err) end
  if type(v) ~= "table" then return nil, "no rules in it" end
  local rules = {}
  for i = 1, 200 do
    if v[i] == nil then break end
    local r = CleanRule(v[i])
    if r then rules[#rules + 1] = r end
  end
  if #rules == 0 then return nil, "no rules in it" end
  return rules
end
