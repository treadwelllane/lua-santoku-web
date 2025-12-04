local js = require("santoku.web.js")
local val = require("santoku.web.val")
local arr = require("santoku.array")
local err = require("santoku.error")
local wrpc = require("santoku.web.worker.rpc.client")

local navigator = js.navigator
local document = js.document
local MessageChannel = js.MessageChannel
local BroadcastChannel = js.BroadcastChannel

-- Create a consumer client from a port
local function create_consumer_client (port)
  local callbacks = {}
  local nonce_counter = 0
  port.onmessage = function (_, ev)
    local data = ev.data
    if data and data.nonce and callbacks[data.nonce] then
      local cb = callbacks[data.nonce]
      callbacks[data.nonce] = nil
      if data.error then
        return cb(false, data.error.message or tostring(data.error))
      else
        return cb(true, data.result)
      end
    end
  end
  port:start()
  return setmetatable({}, {
    __index = function (_, method)
      return function (...)
        local n = select("#", ...)
        local callback = select(n, ...)
        local args = {}
        for i = 1, n - 1 do
          args[i] = select(i, ...)
        end
        nonce_counter = nonce_counter + 1
        local nonce = tostring(nonce_counter)
        callbacks[nonce] = callback
        port:postMessage(val({
          nonce = nonce,
          method = method,
          args = args
        }, true))
      end
    end
  })
end

return function (bundle_path, callback)
  local db = nil
  local worker
  local is_provider = false
  local client_id = nil
  local provider_counter = 0
  local current_provider_port = nil

  local broadcast_channel = BroadcastChannel:new("sqlite_shared_service")

  -- Get our client ID using Web Lock query trick (same as SharedService)
  local function get_client_id (done)
    local nonce = "client_id_" .. tostring(math.random()):sub(3)
    navigator.locks:request(nonce, function ()
      navigator.locks:query():await(function (_, ok, state)
        if ok and state and state.held then
          local held = state.held
          for i = 0, held.length - 1 do
            local lock = held[i]
            if lock.name == nonce then
              done(lock.clientId)
              return
            end
          end
        end
        done(nil)
      end)
      -- Resolve immediately to release the temporary lock
      return js.Promise:resolve()
    end)
  end

  -- Close current provider connection
  local function close_provider_connection ()
    if current_provider_port then
      current_provider_port:close()
      current_provider_port = nil
    end
    db = nil
  end

  -- Request a port from the current provider
  local function request_provider_port (counter)
    if counter ~= provider_counter then return end
    if is_provider then return end
    if db then return end

    local nonce = "req_" .. tostring(math.random()):sub(3)

    -- Listen for response from SW (provider sends port via SW)
    local function on_sw_message (_, ev)
      if ev.data and ev.data.type == "db_port" and ev.data.nonce == nonce then
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        local port = ev.ports and ev.ports[1]
        if port and counter == provider_counter and not is_provider then
          current_provider_port = port
          db = create_consumer_client(port)
          if callback then callback() end
        elseif port then
          port:close()
        end
      end
    end
    navigator.serviceWorker:addEventListener("message", on_sw_message)

    -- Broadcast request to provider
    broadcast_channel:postMessage(val({
      type = "request",
      nonce = nonce,
      clientId = client_id
    }, true))

    -- Timeout and retry if no response
    js.setTimeout(function ()
      if counter == provider_counter and not db and not is_provider then
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        request_provider_port(counter)
      end
    end, 1000)
  end

  -- Helper to create a port for RPC (used for both consumers and SW)
  local function create_rpc_port ()
    local ch = MessageChannel:new()
    local port1, port2 = ch.port1, ch.port2

    port1.onmessage = function (_, msg_ev)
      local msg_data = msg_ev.data
      if msg_data and msg_data.method and msg_data.nonce then
        local args = msg_data.args or {}
        args[#args + 1] = function (ok, result)
          local response = { nonce = msg_data.nonce }
          if ok then
            response.result = result
          else
            response.error = { message = tostring(result), name = "Error" }
          end
          port1:postMessage(val(response, true))
        end
        local method_ok, method_err = err.pcall(function ()
          return db[msg_data.method](arr.spread(args))
        end)
        if not method_ok then
          port1:postMessage(val({
            nonce = msg_data.nonce,
            error = { message = tostring(method_err), name = "Error" }
          }, true))
        end
      end
    end
    port1:start()

    return port2
  end

  -- Handle broadcast messages
  broadcast_channel.onmessage = function (_, ev)
    local data = ev.data
    if not data then return end

    if data.type == "provider" then
      -- New provider announced - reconnect if we're a consumer
      if not is_provider then
        close_provider_connection()
        provider_counter = provider_counter + 1
        request_provider_port(provider_counter)
      end

    elseif data.type == "request" and is_provider and data.clientId then
      -- Consumer requesting port (we're provider)
      local port = create_rpc_port()

      -- Send port to consumer via SW
      navigator.serviceWorker.controller:postMessage(
        val({ type = "db_port", targetClientId = data.clientId, nonce = data.nonce }, true),
        { port }
      )
    end
  end

  -- Initialize when SW is ready
  navigator.serviceWorker.ready:await(function (_, ok)
    if not ok then return end

    -- Get our client ID first
    get_client_id(function (cid)
      client_id = cid

      -- Acquire context lock (for lifetime tracking, held forever)
      navigator.locks:request(client_id, function ()
        return js.Promise:new(function () end)
      end):catch(function () end)

      -- Try to become provider via lock acquisition
      -- If another tab holds the lock, this callback queues and waits
      navigator.locks:request("sqlite_db_access", function ()
        -- We got the lock - we're the provider!
        is_provider = true

        db, worker = wrpc.init(bundle_path)

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

        -- Listen for SW port requests (SW needs db access for route handlers)
        navigator.serviceWorker:addEventListener("message", function (_, ev)
          if ev.data and ev.data.type == "sw_port_request" and is_provider then
            local port = create_rpc_port()
            navigator.serviceWorker.controller:postMessage(
              val({ type = "sw_port" }, true),
              { port }
            )
          end
        end)

        -- Announce we're the provider
        broadcast_channel:postMessage(val({
          type = "provider",
          clientId = client_id
        }, true))

        if callback then callback() end

        -- Hold lock forever (until tab closes)
        return js.Promise:new(function () end)
      end)

      -- Also try to connect as consumer immediately
      -- (in case a provider already exists and we're waiting in lock queue)
      request_provider_port(provider_counter)
    end)
  end)
end
