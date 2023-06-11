local common = require("santoku.web.trace.common")
local js = require("santoku.web.js")

local global = js.self
local BroadcastChannel = global.BroadcastChannel
local JSON = global.JSON

local channel = BroadcastChannel:new("santoku.web.trace")

return function ()

  local function emit (str)
    channel:postMessage(str)
  end

  common(emit, global)

  global:addEventListener("fetch", function (_, ev)
    emit(JSON:stringify({
      source = "fetch-event",
      request = {
        url = ev.request.url,
        method = ev.request.method
      }
    }))
  end)

end
