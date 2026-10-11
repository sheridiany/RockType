local M = {}
local blocked = require("roarkt_english_blocklist")

function M.func(input, segment)
  if not input:match("^[A-Za-z][A-Za-z']+$") then return end
  local text = input:gsub("'", " ")
  if blocked.contains(text) then return end
  local candidate = Candidate("roarkt_english_echo", segment.start, segment._end, text, "〔EN〕")
  candidate.quality = 0.7
  yield(candidate)
end

return M
