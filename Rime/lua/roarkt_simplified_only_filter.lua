local M = {}

-- OpenCC deliberately preserves a few semantically distinct Taiwan variants.
-- RoarkT is simplified-only, so these must not leak into the candidate list.
local disallowed_variants = {
  "妳",
}

local function contains_disallowed_variant(text)
  for _, variant in ipairs(disallowed_variants) do
    if text:find(variant, 1, true) then
      return true
    end
  end
  return false
end

function M.func(input)
  for candidate in input:iter() do
    if not contains_disallowed_variant(candidate.text) then
      yield(candidate)
    end
  end
end

return M
