local common = require("santoku.web.trace.common")
local js = require("santoku.web.js")

local global = js.self
local BroadcastChannel = global.BroadcastChannel
local JSON = global.JSON

local channel = BroadcastChannel:new("santoku.web.trace")

return function (callback)

  local function emit (str)
    channel:postMessage(str)
  end

  local onErr = common(emit, global).onErr

  global:addEventListener("fetch", function (_, ev)
    emit(JSON:stringify({
      source = "fetch-event",
      request = {
        url = ev.request.url,
        method = ev.request.method
      }
    }))
  end)

  if callback then
    local ok, err = pcall(callback)
    if not ok then
      onErr(err)
    end
  end

end
