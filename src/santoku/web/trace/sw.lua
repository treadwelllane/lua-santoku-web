local common = require("santoku.web.trace.common")
local js = require("santoku.web.js")

local global = js.self
local BroadcastChannel = global.BroadcastChannel

local channel = BroadcastChannel:new("santoku.web.trace")

return function (opts)

  opts = opts or {}

  local function emit (str)
    channel:postMessage(str)
  end

  common(emit, global, opts)

end
