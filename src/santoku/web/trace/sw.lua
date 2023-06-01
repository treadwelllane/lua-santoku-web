local common = require("santoku.web.trace.common")
local vec = require("santoku.vector")
local js = require("santoku.web.js")
local global = js.window
local JSON = global.JSON
local clients = global.clients

return function ()

  local buffer = vec()

  local function emitTo (cs, str)
    cs:forEach(function (_, client)
      client:postMessage({
        typ = "DEVCAT",
        data = str
      })
    end)
  end

  local function emit (str)
    clients:matchAll():await(function (_, ok, cs)
      assert(ok)
      if cs.length == 0 then
        buffer:append(str)
      else
        buffer:each(function (str0)
          emitTo(cs, str0)
        end)
        buffer:trunc()
        emitTo(cs, str)
      end
    end)
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
