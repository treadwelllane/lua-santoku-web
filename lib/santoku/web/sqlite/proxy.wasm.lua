local js = require("santoku.web.js")
local val = require("santoku.web.val")
local arr = require("santoku.array")
local err = require("santoku.error")
local wrpc = require("santoku.web.worker.rpc.client")

local navigator = js.navigator
local document = js.document
local MessageChannel = js.MessageChannel

local function create_provider_port (target, async)
  local ch = MessageChannel:new()
  local port1, port2 = ch.port1, ch.port2
  port1.onmessage = function (_, _)
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
        for i = 1, #args do
          call_args[i] = args[i]
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
    port1:postMessage(nil, { client_port2 })
  end
  port1:start()
  return port2
end

return function (bundle_path, callback)
  local db, worker = wrpc.init(bundle_path)

  worker.onmessage = function (_, ev)
    if ev.data and ev.data.type == "db_error" then
      if document and document.body then
        document.body.classList:add("db-error")
        document.body:dispatchEvent(js.CustomEvent:new("db-error", {
          detail = { error = ev.data.error }
        }))
      end
    end
  end

  local provider_port = create_provider_port(db, true)
  local provider_lock_held = false
  local function acquire_provider_lock (client_id)
    if provider_lock_held then return end
    if not client_id then return end
    provider_lock_held = true
    if not navigator or not navigator.locks then
      navigator.serviceWorker.controller:postMessage(val({ type = "lock_acquired" }, true))
      return
    end
    local lock_name = "db_provider_" .. client_id
    navigator.locks:request(lock_name, function ()
      navigator.serviceWorker.controller:postMessage(val({ type = "lock_acquired" }, true))
      return js.Promise:new(function () end)
    end):catch(function () end)
  end
  local function register_with_sw ()
    navigator.serviceWorker.controller:postMessage(val({ type = "db_register" }, true), { provider_port })
  end

  navigator.serviceWorker.ready:await(function (_, ok)
    if not ok then
      return
    end
    navigator.serviceWorker:addEventListener("message", function (_, ev)
      if ev.data and ev.data.type == "db_provider" then
        acquire_provider_lock(ev.data.client_id)
        if callback then
          return callback()
        end
      elseif ev.data and ev.data.type == "db_consumer" then
        local consumer_port = ev.ports and ev.ports[1]
        if consumer_port and callback then
          return callback()
        end
      end
    end)
    if navigator.serviceWorker.controller then
      register_with_sw()
    else
      navigator.serviceWorker:addEventListener("controllerchange", function ()
        register_with_sw()
      end, { once = true })
    end
  end)
end
