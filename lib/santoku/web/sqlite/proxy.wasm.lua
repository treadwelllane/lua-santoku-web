local js = require("santoku.web.js")
local val = require("santoku.web.val")
local arr = require("santoku.array")
local err = require("santoku.error")
local wrpc = require("santoku.web.worker.rpc.client")

local navigator = js.navigator
local MessageChannel = js.MessageChannel
local Math = js.Math

local function random_string ()
  return tostring(Math:random()):gsub("0%%.", "")
end

-- Create a provider port that spawns new channels for each client
local function create_provider_port (target, async)
  local ch = MessageChannel:new()
  local port1, port2 = ch.port1, ch.port2

  port1.onmessage = function (_, ev)
    -- Each message requests a new channel
    local client_ch = MessageChannel:new()
    local client_port1, client_port2 = client_ch.port1, client_ch.port2

    client_port1.onmessage = function (_, msg_ev)
      local data = msg_ev.data
      local nonce = data.nonce
      local method = data.method
      local args = data.args or {}

      local function send_response (ok, result)
        local response = { nonce = nonce }
        if ok then
          response.result = result
        else
          response.error = {
            message = tostring(result),
            name = "Error"
          }
        end
        return client_port1:postMessage(val(response, true))
      end

      if not target[method] then
        return send_response(false, "Unknown method: " .. tostring(method))
      end

      if async then
        local call_args = {}
        for i = 0, (args.length or 0) - 1 do
          call_args[i + 1] = args[i]
        end
        call_args[#call_args + 1] = function (ok, result)
          return send_response(ok, result)
        end
        local ok, call_err = err.pcall(function ()
          return target[method](arr.spread(call_args))
        end)
        if not ok then
          return send_response(false, call_err)
        end
      else
        local ok, result = err.pcall(function ()
          return target[method](arr.spread(args))
        end)
        return send_response(ok, result)
      end
    end

    client_port1:start()
    -- Send the client's port back
    port1:postMessage(nil, { client_port2 })
  end

  port1:start()
  return port2
end

return function (bundle_path, callback)
  -- Create Worker and get RPC client
  local db = wrpc.init(bundle_path)

  -- Create provider port that can spawn channels
  local provider_port = create_provider_port(db, true)

  -- Register with SW
  navigator.serviceWorker.ready:await(function (_, ok)
    if not ok then
      return
    end

    -- Listen for SW messages
    navigator.serviceWorker:addEventListener("message", function (_, ev)
      if ev.data and ev.data.type == "db_provider" then
        -- We're the provider, proceed
        if callback then
          return callback()
        end
      elseif ev.data and ev.data.type == "db_consumer" and ev.ports and ev.ports[0] then
        -- We're a consumer, but we already created a Worker
        -- In future optimization, consumers wouldn't create Workers
        -- For now, just proceed
        if callback then
          return callback()
        end
      end
    end)

    -- Send our provider port to SW
    navigator.serviceWorker.controller:postMessage(
      val({ type = "db_register" }, true),
      { provider_port }
    )
  end)
end
