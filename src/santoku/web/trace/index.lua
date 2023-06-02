local common = require("santoku.web.trace.common")
local vec = require("santoku.vector")
local js = require("santoku.web.js")
local window = js.window
local navigator = js.navigator
local WebSocket = window.WebSocket

return function (url)

  local buffer = vec()
  local connected = false
  local sock = nil

  local function emit (str)
    if (connected) then
      print("emit", str)
      sock:send(str)
    else
      print("buffer", str)
      buffer:append(str)
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

  common(emit, window)

  navigator.serviceWorker.onmessage = function (_, ev)
    if ev.data and ev.data.typ == "DEVCAT" then
      emit(ev.data.data)
    end
  end

  start()

end
