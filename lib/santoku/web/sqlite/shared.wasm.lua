-- SharedService pattern for cross-tab OPFS SQLite coordination
-- This module handles all the complexity of BroadcastChannel, MessageChannel,
-- Web Locks, and provider/consumer coordination internally.

local js = require("santoku.web.js")
local val = require("santoku.web.val")
local arr = require("santoku.array")
local err = require("santoku.error")

local global = js.window or js.self
local navigator = js.navigator
local BroadcastChannel = js.BroadcastChannel
local MessageChannel = js.MessageChannel
local AbortController = js.AbortController
local Promise = js.Promise
local Math = js.Math

local M = {}

local PROVIDER_REQUEST_TIMEOUT = 150

local function random_string ()
  return tostring(Math:random()):gsub("0%%.", "")
end

-- Create a port that handles RPC calls to a target object
M.create_provider_port = function (target, async)
  local ch = MessageChannel:new()
  local port1, port2 = ch.port1, ch.port2

  port1.onmessage = function (_, ev)
    local client_id = ev.data

    local client_ch = MessageChannel:new()
    local client_port1, client_port2 = client_ch.port1, client_ch.port2

    navigator.locks:request(client_id, function ()
      client_port1:close()
    end)

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
        client_port1:postMessage(val(response, true))
      end

      if not target[method] then
        send_response(false, "Unknown method: " .. tostring(method))
        return
      end

      if async then
        local call_args = {}
        for i = 0, (args.length or 0) - 1 do
          call_args[i + 1] = args[i]
        end
        call_args[#call_args + 1] = function (ok, result)
          send_response(ok, result)
        end
        local ok, call_err = err.pcall(function ()
          target[method](arr.spread(call_args))
        end)
        if not ok then
          send_response(false, call_err)
        end
      else
        local ok, result = err.pcall(function ()
          return target[method](arr.spread(args))
        end)
        send_response(ok, result)
      end
    end

    client_port1:start()
    port1:postMessage(nil, { client_port2 })
  end

  port1:start()
  return port2
end

-- SharedService manages cross-tab database coordination
-- Only one tab becomes the "provider" that owns the actual db connection
M.SharedService = function (service_name, port_provider_func)

  local self = {}

  local client_id = nil
  local client_channel = BroadcastChannel:new("SharedService")
  local on_deactivate = nil
  local provider_port = nil
  local provider_callbacks = {}
  local provider_counter = 0

  local function get_client_id (callback)
    navigator.serviceWorker.ready:await(function (_, ok)
      if not ok then
        return
      end
      local try_fetch
      local function wait_for_controller ()
        if not navigator.serviceWorker.controller then
          global:setTimeout(wait_for_controller, 50)
          return
        end
        try_fetch()
      end
      try_fetch = function ()
        global:fetch("/clientId"):await(function (_, ok, resp)
          if not ok or not resp.ok then
            global:setTimeout(try_fetch, 100)
            return
          end
          resp:text():await(function (_, ok, text)
            if ok then
              client_id = text
              navigator.locks:request(client_id, function ()
                return Promise:new(function () end)
              end)
              callback(client_id)
            end
          end)
        end)
      end
      wait_for_controller()
    end)
  end

  navigator.serviceWorker:addEventListener("message", function (_, ev)
    if ev.data and ev.data.nonce then
      local cb = self._message_callbacks and self._message_callbacks[ev.data.nonce]
      if cb then
        cb(ev.data, ev.ports)
        self._message_callbacks[ev.data.nonce] = nil
      end
    end
  end)
  self._message_callbacks = {}

  local function provider_change (callback)
    provider_counter = provider_counter + 1
    local my_counter = provider_counter
    local function try_connect ()
      if my_counter ~= provider_counter then
        callback(nil)
        return
      end
      local nonce = random_string()
      self._message_callbacks[nonce] = function (_, ports)
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
          callback(port)
        end
      end
      client_channel:postMessage(val({
        type = "request",
        nonce = nonce,
        sharedService = service_name,
        clientId = client_id
      }, true))
      global:setTimeout(function ()
        if self._message_callbacks[nonce] then
          self._message_callbacks[nonce] = nil
          try_connect()
        end
      end, PROVIDER_REQUEST_TIMEOUT)
    end
    try_connect()
  end

  get_client_id(function ()
    provider_change(function (port)
      provider_port = port
    end)
    client_channel.onmessage = function (_, ev)
      if ev.data and ev.data.type == "provider" and ev.data.sharedService == service_name then
        if provider_port then
          provider_port:close()
        end
        for _, cbs in pairs(provider_callbacks) do
          cbs.reject({ message = "Provider changed" })
        end
        provider_callbacks = {}
        provider_change(function (port)
          provider_port = port
        end)
      end
    end
  end)

  self.activate = function ()
    if on_deactivate then return end
    on_deactivate = AbortController:new()
    navigator.locks:request("SharedService-" .. service_name, { signal = on_deactivate.signal }, function ()
      local port = port_provider_func()
      port:start()
      local provider_channel = BroadcastChannel:new("SharedService")
      provider_channel.onmessage = function (_, ev)
        if ev.data and ev.data.type == "request" and ev.data.sharedService == service_name then
          port.onmessage = function (_, port_ev)
            navigator.serviceWorker.ready:await(function (_, ok, reg)
              if ok and reg.active then
                reg.active:postMessage(val(ev.data, true), port_ev.ports)
              end
            end)
          end
          port:postMessage(ev.data.clientId)
        end
      end
      provider_channel:postMessage(val({
        type = "provider",
        sharedService = service_name,
        providerId = client_id
      }, true))
      return Promise:new(function (_, _, reject)
        on_deactivate.signal.onabort = function ()
          provider_channel:close()
          reject()
        end
      end)
    end)
  end

  self.deactivate = function ()
    if on_deactivate then
      on_deactivate:abort()
      on_deactivate = nil
    end
  end

  self.close = function ()
    self.deactivate()
    for _, cbs in pairs(provider_callbacks) do
      cbs.reject({ message = "SharedService closed" })
    end
  end

  self.call = function (method, args, callback)
    if not provider_port then
      callback(false, "No provider available")
      return
    end
    local nonce = random_string()
    provider_callbacks[nonce] = {
      resolve = function (result)
        callback(true, result)
      end,
      reject = function (error)
        callback(false, error.message or tostring(error))
      end
    }
    provider_port:postMessage(val({
      nonce = nonce,
      method = method,
      args = args or {}
    }, true))
  end

  return self
end

return M
