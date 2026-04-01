local js = require("santoku.web.js")
local val = require("santoku.web.val")

local window = js.window
local history = window.history

return function (opts)
  opts = opts or {}
  local anchors = {}
  if opts.anchors then
    for _, path in ipairs(opts.anchors) do
      anchors[path] = true
    end
  else
    anchors["/"] = true
  end
  local prune_distance = opts.prune_distance or 10

  local popmark_target = nil
  local popstate_callbacks = {}

  local function get_current_id()
    return (history.state and history.state.id) or 0
  end

  local function get_marks()
    local mark = history.state and history.state.mark
    if mark then
      return val.lua(mark, true)
    end
    return {}
  end

  local function prune_marks(marks, current_id)
    local pruned = {}
    for path, mark_id in pairs(marks) do
      local distance = current_id - mark_id
      if anchors[path] or distance <= prune_distance then
        pruned[path] = mark_id
      end
    end
    return pruned
  end

  local function push(path, data)
    local current_id = get_current_id()
    local new_id = current_id + 1
    local marks = get_marks()
    marks = prune_marks(marks, new_id)
    if not marks[path] then
      marks[path] = new_id
    end

    local state = {
      id = new_id,
      mark = marks,
      data = data or {}
    }

    history:pushState(val(state, true), "", "#" .. path)
  end

  local function replace(path, data)
    local current_id = get_current_id()
    local marks = get_marks()
    marks = prune_marks(marks, current_id)
    if not marks[path] then
      marks[path] = current_id
    end

    local state = {
      id = current_id,
      mark = marks,
      data = data or {}
    }

    history:replaceState(val(state, true), "", "#" .. path)
  end

  local function mark(path)
    local current_id = get_current_id()
    local marks = get_marks()
    if not marks[path] then
      marks[path] = current_id
    end

    local state = {
      id = current_id,
      mark = marks,
      data = (history.state and history.state.data) or {}
    }

    history:replaceState(val(state, true), "", "#" .. path)
  end

  local function back_to(path)
    local current_id = get_current_id()
    local marks = get_marks()
    local mark_id = marks[path]

    if mark_id and mark_id < current_id then
      local diff = current_id - mark_id
      popmark_target = path
      history:go(-diff)
      return true
    else
      replace(path)
      return false
    end
  end

  local function back()
    history:back()
  end

  local function on_popstate(callback)
    table.insert(popstate_callbacks, callback)
  end

  window:addEventListener("popstate", function()
    if popmark_target then
      local target = popmark_target
      popmark_target = nil
      replace(target)
    end
    for _, callback in ipairs(popstate_callbacks) do
      callback()
    end
  end)

  return {
    push = push,
    replace = replace,
    mark = mark,
    back_to = back_to,
    back = back,
    get_current_id = get_current_id,
    get_marks = get_marks,
    on_popstate = on_popstate,
  }
end
