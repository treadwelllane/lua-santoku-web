-- Service Worker SQLite client
-- Connects to SharedService provider to access db from SW context
--
-- Usage in SW:
--   local db = require("santoku.web.sqlite.sw").connect("myapp")
--   db.call("get_items", {}, function (ok, items) ... end)

local js = require("santoku.web.js")
local val = require("santoku.web.val")

local global = js.self
local BroadcastChannel = js.BroadcastChannel
local clients = js.clients
local Math = js.Math
local navigator = js.navigator
local Promise = js.Promise

local M = {}

local PROVIDER_REQUEST_TIMEOUT = 150
local PROVIDER_CALL_TIMEOUT = 300
local PROVIDER_RETRY_DELAY = 50
local PROVIDER_MAX_RETRIES = 10
local SW_CLIENT_ID = "sw-client"

local function random_string ()
  return tostring(Math:random()):gsub("0%%.", "")
end

-- Connect to a SharedService database from the service worker
M.connect = function (name)
  local service_name = name .. "-db"

  local provider_port = nil
  local provider_callbacks = {}
  local message_callbacks = {}

  -- Acquire SW client lock
  navigator.locks:request(SW_CLIENT_ID, function ()
    return Promise:new(function () end)
  end)

  local function connect_to_provider (callback)
    local client_channel = BroadcastChannel:new("SharedService")
    local nonce = random_string()

    message_callbacks[nonce] = function (_, ports)
      if ports and ports[1] then
        local port = ports[1]
        port.onmessage = function (_, msg_ev)
          local cb_data = msg_ev.data
          local cbs = provider_callbacks[cb_data.nonce]
          if cbs then
            if cb_data.error then
              cbs.reject(cb_data.error)
            else
              cbs.resolve(cb_data.result)
            end
            provider_callbacks[cb_data.nonce] = nil
          end
        end
        port:start()
        provider_port = port
        callback(true, port)
      else
        callback(false, "No port received from provider")
      end
    end

    client_channel:postMessage(val({
      type = "request",
      nonce = nonce,
      sharedService = service_name,
      clientId = SW_CLIENT_ID
    }, true))

    global:setTimeout(function ()
      if message_callbacks[nonce] then
        message_callbacks[nonce] = nil
        callback(false, "Provider request timeout")
      end
    end, PROVIDER_REQUEST_TIMEOUT)
  end

  local function call_provider (method, args, callback, retries)
    retries = retries or 0

    local function retry ()
      provider_port = nil
      if retries < PROVIDER_MAX_RETRIES then
        global:setTimeout(function ()
          call_provider(method, args, callback, retries + 1)
        end, PROVIDER_RETRY_DELAY)
      else
        callback(false, "Provider not available after retries")
      end
    end

    local function do_call (port)
      local nonce = random_string()
      local timed_out = false
      provider_callbacks[nonce] = {
        resolve = function (result)
          if not timed_out then
            callback(true, result)
          end
        end,
        reject = function (error)
          if not timed_out then
            callback(false, error.message or tostring(error))
          end
        end
      }
      port:postMessage(val({
        nonce = nonce,
        method = method,
        args = args or {}
      }, true))
      global:setTimeout(function ()
        if provider_callbacks[nonce] then
          timed_out = true
          provider_callbacks[nonce] = nil
          retry()
        end
      end, PROVIDER_CALL_TIMEOUT)
    end

    if provider_port then
      do_call(provider_port)
    else
      connect_to_provider(function (ok, result)
        if ok then
          do_call(result)
        else
          retry()
        end
      end)
    end
  end

  -- Listen for provider changes
  local client_channel = BroadcastChannel:new("SharedService")
  client_channel.onmessage = function (_, ev)
    if ev.data and ev.data.type == "provider" and ev.data.sharedService == service_name then
      if provider_port then
        provider_port:close()
        provider_port = nil
      end
    end
  end

  -- Message handler for SharedService messages routed through SW
  local function on_message (ev)
    if ev.data and ev.data.sharedService then
      clients:get(ev.data.clientId):await(function (_, ok, client)
        if ok and client then
          client:postMessage(val(ev.data, true), ev.ports)
        end
      end)
    end
    if ev.data and ev.data.nonce and message_callbacks[ev.data.nonce] then
      message_callbacks[ev.data.nonce](ev.data, ev.ports)
      message_callbacks[ev.data.nonce] = nil
    end
  end

  return {
    call = call_provider,
    on_message = on_message,
  }
end

return M
