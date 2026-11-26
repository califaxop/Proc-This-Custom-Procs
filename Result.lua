-- Evaluation results (1.16.0). Every condition and every rule answers with one of:
--   TRUE     confirmed: it holds
--   FALSE    confirmed: it doesn't hold
--   GATED    the game holds the answer (a hidden value): it decides through gates on the glow, which
--            open only when the hidden condition holds; Proc This! never reads the value
--   UNKNOWN  not enough information (hidden, not tracked, never seen, unsupported combination)
--   ERROR    reading it failed
-- Only TRUE (glow) and GATED (glow when the game says so) can light a glow. UNKNOWN and ERROR never
-- count as TRUE or as FALSE: an AND with one stays unknown unless something is confirmed FALSE, and
-- an OR stays unknown unless something holds.
--
-- A result travels as three values: status, why (for the settings window), gates (GATED only: the
-- hidden conditions, all of which must hold). Pure Lua: no game calls (tests/run_tests.py).
local _, ns = ...
local R = {}
ns.Result = R

R.TRUE, R.FALSE, R.GATED, R.UNKNOWN, R.ERROR = "true", "false", "gated", "unknown", "error"

-- AND of results (each { status, why, gates }): every one must hold.
--   a confirmed FALSE decides it; else an ERROR, else an UNKNOWN keeps it undecided; else the gates
--   of every GATED one, together (they all must hold, and gates multiply: that's exact); else TRUE
function R.All(list)
  local err, unk, gates
  for _, x in ipairs(list) do
    local st = x[1]
    if st == R.FALSE then return R.FALSE, x[2] end
    if st == R.ERROR then err = err or x
    elseif st == R.UNKNOWN then unk = unk or x
    elseif st == R.GATED then
      gates = gates or {}
      for _, g in ipairs(x[3] or {}) do gates[#gates + 1] = g end
    end
  end
  if err then return R.ERROR, err[2] end
  if unk then return R.UNKNOWN, unk[2] end
  if gates and #gates > 0 then return R.GATED, nil, gates end
  return R.TRUE
end

-- OR of results: one holding is enough.
--   a TRUE decides it. One GATED stands for the whole OR (the game opens it only when that branch
--   holds, which makes the OR true; when it doesn't, nothing glows, never wrongly). Two or more
--   GATED can't be combined with OR (gates only multiply: AND): UNKNOWN, no glow. Else an UNKNOWN,
--   else an ERROR keeps it undecided; else FALSE.
function R.Any(list)
  local gated, nGated, unk, err, whys = nil, 0, nil, nil, {}
  for _, x in ipairs(list) do
    local st = x[1]
    if st == R.TRUE then return R.TRUE end
    if st == R.GATED then gated, nGated = x, nGated + 1
    elseif st == R.UNKNOWN then unk = unk or x
    elseif st == R.ERROR then err = err or x
    else whys[#whys + 1] = x[2] end
  end
  if nGated == 1 then return R.GATED, nil, gated[3] end
  if nGated > 1 then return R.UNKNOWN, "several hidden checks joined by OR can't be decided yet" end
  if unk then return R.UNKNOWN, unk[2] end
  if err then return R.ERROR, err[2] end
  if #whys == 0 then return R.FALSE, "nothing to check" end
  return R.FALSE, (#whys == 1) and whys[1] or ("none of: " .. table.concat(whys, "; or "))
end

-- NOT: TRUE <-> FALSE; UNKNOWN and ERROR stay as they are; GATED flips only when it hangs on one
-- hidden value that can be flipped (invert(gate) -> the opposite gate, or nil): else UNKNOWN.
function R.Not(status, why, gates, invert, whyIfTrue)
  if status == R.TRUE then return R.FALSE, whyIfTrue end
  if status == R.FALSE then return R.TRUE end
  if status == R.GATED then
    if gates and #gates == 1 and invert then
      local g = invert(gates[1])
      if g then return R.GATED, nil, { g } end
    end
    return R.UNKNOWN, "it hangs on several hidden values, and their opposite can't be checked"
  end
  return status, why
end

-- words for the settings window
R.LABEL = { ["true"] = "holds", ["false"] = "doesn't hold", gated = "the game decides (hidden)",
  unknown = "can't tell", error = "error" }
