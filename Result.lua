-- Evaluation results. Every condition and every rule answers with one of:
--   TRUE     confirmed: it holds
--   FALSE    confirmed: it doesn't hold
--   GATED    the game holds the answer (hidden values): it decides through gates on the glow, which
--            open only when the hidden conditions hold; Proc This! never reads the values
--   UNKNOWN  not enough information (hidden, not tracked, never seen, too complex)
--   ERROR    reading it failed
-- Only TRUE (glow) and GATED (glow when the game says so) can light a glow. UNKNOWN and ERROR never
-- count as TRUE or as FALSE.
--
-- A result travels as three values: status, why (for the settings window), and for GATED its gate
-- set. Pure Lua: no game calls (tests/run_tests.py).
--
-- Gate sets (1.17.0). A gate is one hidden condition the game can check on a frame. Gates on one
-- frame chain multiply: AND. So a gate set is an OR of ANDs: a list of terms, each a list of gates
-- that must all hold. The glow draws one layer per term (Glow.lua), made exclusive (Disjoint) so
-- that only one shows at a time.
--   set.partial = true: some branches had to be left out (too many, or one couldn't be told). It
--   can then miss a glow it should show, never show one it shouldn't; and its opposite (NOT)
--   can't be taken.
-- A gate may know its opposite (gate.inv, set by the invert function): a term holding both can
-- never hold, and is dropped.
local _, ns = ...
local R = {}
ns.Result = R

R.TRUE, R.FALSE, R.GATED, R.UNKNOWN, R.ERROR = "true", "false", "gated", "unknown", "error"
R.MAX_GATES = 6 -- in one term (one glow layer's gate frames)
R.MAX_TERMS = 8 -- kept while combining

local TOO_MANY = "too many hidden conditions at once"

-- a term from a list of gates: each gate once; nil if it holds a gate and its opposite
local function Term(list)
  local t, seen = {}, {}
  for _, g in ipairs(list) do
    if not seen[g] then
      if g.inv and seen[g.inv] then return nil end
      seen[g] = true
      t[#t + 1] = g
    end
  end
  return t
end

-- is every gate of term a in term b? (then b adds nothing to an OR holding a)
local function Within(a, b)
  if #a > #b then return false end
  for _, g in ipairs(a) do
    local found = false
    for _, h in ipairs(b) do if h == g then found = true; break end end
    if not found then return false end
  end
  return true
end

-- add a term to a set: skipped if the set already covers it; covers (drops) terms it holds
local function Add(set, t)
  if #t > R.MAX_GATES then set.partial = true; return end
  for _, u in ipairs(set) do if Within(u, t) then return end end
  for i = #set, 1, -1 do if Within(t, set[i]) then table.remove(set, i) end end
  if #set >= R.MAX_TERMS then set.partial = true; return end
  set[#set + 1] = t
end

-- AND of two sets: every term of one with every term of the other
local function Product(a, b)
  local out = { partial = a.partial or b.partial }
  for _, ta in ipairs(a) do
    for _, tb in ipairs(b) do
      local list = {}
      for _, g in ipairs(ta) do list[#list + 1] = g end
      for _, g in ipairs(tb) do list[#list + 1] = g end
      local t = Term(list)
      if t then Add(out, t) end
    end
  end
  return out
end

-- a set that came out empty: nothing it holds can ever hold (FALSE), or everything that could was
-- left out (UNKNOWN)
local function Empty(set, why)
  if set.partial then return R.UNKNOWN, TOO_MANY end
  return R.FALSE, why
end

-- A set of one term: these gates, all holding.
function R.Gates(list) return { Term(list) } end

-- AND of results (each { status, why, set }): every one must hold.
--   a confirmed FALSE decides it; else an ERROR, else an UNKNOWN keeps it undecided; else the gate
--   sets of the GATED ones, multiplied out; else TRUE
function R.All(list)
  local err, unk, set
  for _, x in ipairs(list) do
    local st = x[1]
    if st == R.FALSE then return R.FALSE, x[2] end
    if st == R.ERROR then err = err or x
    elseif st == R.UNKNOWN then unk = unk or x
    elseif st == R.GATED then set = set and Product(set, x[3]) or Product({ {} }, x[3]) end
  end
  if err then return R.ERROR, err[2] end
  if unk then return R.UNKNOWN, unk[2] end
  if not set then return R.TRUE end
  if #set == 0 then return Empty(set, "these hidden conditions can't all hold at once") end
  if #set[1] == 0 then return R.TRUE end
  return R.GATED, set.partial and TOO_MANY or nil, set
end

-- OR of results: one holding is enough.
--   a TRUE decides it. The GATED ones together: the game opens the glow when any of their terms
--   holds. With an UNKNOWN or ERROR beside them it's partial (that branch can't light it). Without
--   any GATED: an UNKNOWN, else an ERROR keeps it undecided; else FALSE.
function R.Any(list)
  local set, unk, err, whys = nil, nil, nil, {}
  for _, x in ipairs(list) do
    local st = x[1]
    if st == R.TRUE then return R.TRUE end
    if st == R.GATED then
      set = set or { partial = false }
      if x[3].partial then set.partial = true end
      for _, t in ipairs(x[3]) do Add(set, t) end
    elseif st == R.UNKNOWN then unk = unk or x
    elseif st == R.ERROR then err = err or x
    else whys[#whys + 1] = x[2] end
  end
  if set then
    local other = unk or err
    if other then set.partial = true end
    if set[1] and #set[1] == 0 then return R.TRUE end
    return R.GATED, other and other[2] or (set.partial and TOO_MANY or nil), set
  end
  if unk then return R.UNKNOWN, unk[2] end
  if err then return R.ERROR, err[2] end
  if #whys == 0 then return R.FALSE, "nothing to check" end
  return R.FALSE, (#whys == 1) and whys[1] or ("none of: " .. table.concat(whys, "; or "))
end

-- NOT: TRUE <-> FALSE; UNKNOWN and ERROR stay as they are. GATED: NOT (t1 or t2 ...) =
-- (not t1) and (not t2) ..., each (not t) = (not g1) or (not g2) ...: needs every gate's opposite
-- (invert(gate) -> the opposite gate, or nil), and a set that isn't partial.
function R.Not(status, why, set, invert, whyIfTrue)
  if status == R.TRUE then return R.FALSE, whyIfTrue end
  if status == R.FALSE then return R.TRUE end
  if status ~= R.GATED then return status, why end
  if set.partial or not invert then
    return R.UNKNOWN, "it hangs on hidden values only partly known, so its opposite can't be checked"
  end
  local out = { {} }
  for _, t in ipairs(set) do
    local factor = { partial = false }
    for _, g in ipairs(t) do
      local ng = invert(g)
      if not ng then return R.UNKNOWN, "a hidden value it hangs on can't be checked the other way round" end
      Add(factor, { ng })
    end
    out = Product(out, factor)
  end
  if #out == 0 then return Empty(out, whyIfTrue) end
  if #out[1] == 0 then return R.TRUE end
  return R.GATED, out.partial and TOO_MANY or nil, out
end

-- The terms of a set made exclusive, so that at most one holds at a time (one glow layer shows,
-- never two on top of each other): term k becomes term k AND NOT (each term before it). Earlier
-- terms come first (a rule higher in the list keeps its look). Each piece keeps its term's `rule`.
-- Returns the pieces (at most `max`) and whether any had to be left out.
function R.Disjoint(set, invert, max)
  local out, partial = {}, set.partial or false
  for k, t in ipairs(set) do
    local pieces = { t }
    for j = 1, k - 1 do
      local p, next = set[j], {}
      for _, piece in ipairs(pieces) do
        -- piece AND NOT p = piece AND (not p1, or p1 and not p2, or ...)
        local excludes = false -- (it already holds the opposite of one of p's gates)
        for _, g in ipairs(p) do
          for _, h in ipairs(piece) do if g.inv and h == g.inv then excludes = true end end
        end
        if excludes then
          next[#next + 1] = piece
        elseif not Within(p, piece) then
          local prefix, ok = {}, true
          for _, g in ipairs(p) do
            local ng = invert(g)
            if not ng then ok = false; break end
            local list = {}
            for _, h in ipairs(piece) do list[#list + 1] = h end
            for _, h in ipairs(prefix) do list[#list + 1] = h end
            list[#list + 1] = ng
            local nt = Term(list)
            if nt then
              if #nt <= R.MAX_GATES then next[#next + 1] = nt else partial = true end
            end
            prefix[#prefix + 1] = g
          end
          if not ok then partial = true; next = {}; break end
        end
      end
      pieces = next
    end
    for _, piece in ipairs(pieces) do
      if #out >= max then return out, true end
      piece.rule = t.rule
      out[#out + 1] = piece
    end
  end
  return out, partial
end

