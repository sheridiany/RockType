-- Internal read-only snapshots must not reach ascii_composer: any ordinary
-- key between Shift press/release cancels its toggle gesture. F20 stays in the
-- normal processor chain because committing a translation is a user action.
local session = require("roarkt_candidate_session")
local M = {}
function M.func(key, env)
  if key:repr() == "F19" then return session.func(key, env) end
  return 2
end
return M
