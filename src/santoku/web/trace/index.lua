local common = require("santoku.web.trace.common")
local vec = require("santoku.vector")
local js = require("santoku.web.js")

local window = js.window
local BroadcastChannel = window.BroadcastChannel
local WebSocket = window.WebSocket

local channel = BroadcastChannel:new("santoku.web.trace")

return function (url, callback, maxbuflen)

  maxbuflen = maxbuflen or 50

  local buffer = vec()
  local connected = false
  local sock = nil

  local function emit (str)
    if (connected) then
      sock:send(str)
    else
      buffer:append(str)
      if buffer:len() > maxbuflen then
        buffer:remove(1, 1)
      end
    end
  end

  local function start ()

    print("Connecting to trace websocket: " .. url)

    sock = WebSocket:new(url)

    sock.onopen = function ()
      connected = true
      buffer:each(emit)
      buffer:trunc()
    end

    sock.onmessage = function (_, ev)
      window:eval(ev.data)
    end

    sock.onclose = function ()
      connected = false
      window:setTimeout(start, 1000)
    end

  end

  local onErr = common(emit, window).onErr

  channel:addEventListener("message", function (_, ev)
    emit(ev.data)
  end)

  start()

  if callback then
    local ok, err = pcall(callback)
    if not ok then
      onErr(err)
    end
  end

end
