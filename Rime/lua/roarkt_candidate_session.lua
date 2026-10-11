local M = {}

local function snapshot(context, ai)
  if not context:is_composing() then return nil end
  local segment = context.composition:back()
  if not segment then return nil end
  local candidate = segment:get_selected_candidate()
  if not candidate or candidate.text == "" then return nil end
  local genuine = candidate.get_genuine and candidate:get_genuine()
  local learned = genuine and genuine.to_phrase and genuine:to_phrase()
      and (genuine.type == "user_phrase" or genuine.type == "user_table")
  local raw = context.input or ""
  local prefix = {}
  local complete_prefix = true
  for _, previous in ipairs(context.composition:toSegmentation():get_segments()) do
    if previous._end <= candidate._start then
      local selected = previous:get_selected_candidate()
      if selected and (previous.status == "kSelected" or previous.status == "kConfirmed") then
        table.insert(prefix, selected.text)
      else
        complete_prefix = false
      end
    end
  end
  if ai and not complete_prefix then return nil end
  local whole = candidate._end == #raw and complete_prefix
  return {
    raw = raw,
    source = ((whole or ai) and table.concat(prefix) or "") .. candidate.text,
    identity = candidate._start .. ":" .. candidate._end .. ":" .. segment.selected_index,
    scope = whole and "whole" or (ai and "prefix" or "segment"),
    segment = segment,
    candidate = candidate,
    learned = learned and true or false,
  }
end

local function publish(context, value, namespace)
  if namespace == "roarkt_panel_" then
    context:set_property("roarkt_panel_can_forget", value and value.learned and "1" or "0")
  end
  for _, field in ipairs({"raw", "source", "identity", "scope"}) do
    context:set_property(namespace .. field, value and value[field] or "")
  end
end

function M.func(key, env)
  local context = env.engine.context
  if context:get_property("roarkt_translation_presentation") ~= "panel" then return 2 end
  local repr = key:repr()
  if repr == "F19" then
    publish(context, snapshot(context), "roarkt_panel_")
    publish(context, snapshot(context, true), "roarkt_ai_")
    return 1
  end
  if repr ~= "F20" then return 2 end

  local text = context:get_property("roarkt_panel_commit_text")
  context:set_property("roarkt_panel_commit_text", "")
  context:set_property("roarkt_panel_committed", "")
  local ai = context:get_property("roarkt_panel_commit_ai") == "1"
  context:set_property("roarkt_panel_commit_ai", "")
  local current = snapshot(context, ai)
  if not current or not text or text == "" then return 1 end
  for _, field in ipairs({"raw", "source", "identity", "scope"}) do
    if context:get_property("roarkt_panel_commit_" .. field) ~= current[field] then return 1 end
  end

  if ai then
    -- Replace exactly the confirmed prefix + selected candidate; keep unconverted suffix.
    local remaining = current.raw:sub(current.candidate._end + 1)
    env.engine:commit_text(text)
    context:clear()
    if remaining ~= "" then context:push_input(remaining) end
  elseif current.scope == "whole" then
    env.engine:commit_text(text)
    context:clear()
  else
    -- A fresh SimpleCandidate avoids modifying/learning an existing dictionary
    -- entry. Let Rime confirm this segment and retain the remaining composition.
    local translated = Candidate("roarkt_panel_translation", current.candidate._start,
      current.candidate._end, text, "")
    local menu = Menu()
    menu:add_translation(Translation(function() yield(translated) end))
    menu:prepare(1)
    current.segment.menu = menu
    current.segment.selected_index = 0
    context:confirm_current_selection()
  end
  context:set_property("roarkt_panel_committed", "1")
  return 1
end

return M
