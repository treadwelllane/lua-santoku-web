local js = require("santoku.web.js")
local util = require("santoku.web.util")
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

return function (bundle_path, callback, opts)
  opts = opts or {}
  local verbose = opts.verbose

  local db = nil
  local worker
  local is_provider = false
  local client_id = nil
  local provider_counter = 0
  local current_provider_port = nil

  local broadcast_channel = BroadcastChannel:new("sqlite_shared_service")

  if verbose then
    print("[proxy] Initializing sqlite proxy")
  end

  -- Get our client ID using Web Lock query trick (same as SharedService)
  local function get_client_id (done)
    local nonce = "client_id_" .. tostring(math.random()):sub(3)
    if verbose then
      print("[proxy] Getting client ID with nonce:", nonce)
    end
    navigator.locks:request(nonce, function ()
      navigator.locks:query():await(function (_, ok, state)
        if verbose then
          print("[proxy] Lock query result - ok:", ok, "state:", state)
        end
        if ok and state and state.held then
          local held = state.held
          if verbose then
            print("[proxy] Held locks count:", held.length)
          end
          -- Use 1-based indexing (santoku JS interop convention)
          for i = 1, held.length do
            local lock = held[i]
            if verbose then
              print("[proxy] Checking lock", i, "name:", lock and lock.name, "clientId:", lock and lock.clientId)
            end
            if lock and lock.name == nonce then
              if verbose then
                print("[proxy] Found our lock, clientId:", lock.clientId)
              end
              done(lock.clientId)
              return
            end
          end
        end
        if verbose then
          print("[proxy] Failed to find client ID")
        end
        done(nil)
      end)
      -- Resolve immediately to release the temporary lock
      return util.promise(function (complete) complete(true) end)
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
    if verbose then
      print("[proxy] request_provider_port called, counter:", counter, "provider_counter:", provider_counter, "is_provider:", is_provider, "db:", db, "client_id:", client_id)
    end
    if counter ~= provider_counter then return end
    if is_provider then return end
    if db then return end
    if not client_id then return end

    local nonce = "req_" .. tostring(math.random()):sub(3)
    if verbose then
      print("[proxy] Requesting provider port with nonce:", nonce)
    end

    -- Listen for response from SW (provider sends port via SW)
    local function on_sw_message (_, ev)
      if verbose then
        print("[proxy] Received SW message:", ev.data and ev.data.type, "nonce:", ev.data and ev.data.nonce, "expected nonce:", nonce)
      end
      if ev.data and ev.data.type == "db_port" and ev.data.nonce == nonce then
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        local port = ev.ports and ev.ports[1]
        if verbose then
          print("[proxy] Received db_port, port:", port, "counter:", counter, "provider_counter:", provider_counter, "is_provider:", is_provider)
        end
        if port and counter == provider_counter and not is_provider then
          if verbose then
            print("[proxy] Becoming consumer with port")
          end
          current_provider_port = port
          db = create_consumer_client(port)
          if callback then callback() end
        elseif port then
          if verbose then
            print("[proxy] Closing stale port")
          end
          port:close()
        end
      end
    end
    navigator.serviceWorker:addEventListener("message", on_sw_message)

    -- Broadcast request to provider
    if verbose then
      print("[proxy] Broadcasting request to provider")
    end
    broadcast_channel:postMessage(val({
      type = "request",
      nonce = nonce,
      clientId = client_id
    }, true))

    -- Timeout and retry if no response
    util.set_timeout(function ()
      if counter == provider_counter and not db and not is_provider then
        if verbose then
          print("[proxy] Port request timeout, retrying...")
        end
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
    if verbose then
      print("[proxy] Received broadcast:", data and data.type, "clientId:", data and data.clientId)
    end
    if not data then return end

    if data.type == "provider" then
      -- New provider announced - reconnect if we're a consumer
      -- Only process if we're initialized (have client_id)
      if verbose then
        print("[proxy] Provider announced, is_provider:", is_provider, "client_id:", client_id)
      end
      if not is_provider and client_id then
        if verbose then
          print("[proxy] Reconnecting to new provider")
        end
        close_provider_connection()
        provider_counter = provider_counter + 1
        request_provider_port(provider_counter)
      end

    elseif data.type == "request" and is_provider and data.clientId then
      -- Consumer requesting port (we're provider)
      if verbose then
        print("[proxy] Consumer requesting port, clientId:", data.clientId, "nonce:", data.nonce)
      end
      local controller = navigator.serviceWorker.controller
      if not controller then
        if verbose then
          print("[proxy] No SW controller, cannot send port")
        end
        return
      end

      local port = create_rpc_port()
      if verbose then
        print("[proxy] Sending port to consumer via SW")
      end

      -- Send port to consumer via SW
      controller:postMessage(
        val({ type = "db_port", targetClientId = data.clientId, nonce = data.nonce }, true),
        { port }
      )
    end
  end

  -- Initialize when SW is ready
  if verbose then
    print("[proxy] Waiting for SW ready...")
  end
  navigator.serviceWorker.ready:await(function (_, ok)
    if verbose then
      print("[proxy] SW ready callback, ok:", ok)
    end
    if not ok then return end

    -- Get our client ID first
    get_client_id(function (cid)
      if verbose then
        print("[proxy] Got client ID:", cid)
      end
      if not cid then
        -- Failed to get client ID, can't proceed
        if verbose then
          print("[proxy] No client ID, cannot proceed")
        end
        return
      end
      client_id = cid

      -- Acquire context lock (for lifetime tracking, held forever)
      if verbose then
        print("[proxy] Acquiring context lock for client:", client_id)
      end
      navigator.locks:request(client_id, function ()
        if verbose then
          print("[proxy] Context lock acquired")
        end
        return util.promise(function () end)
      end):catch(function () end)

      -- Try to become provider via lock acquisition
      -- If another tab holds the lock, this callback queues and waits
      if verbose then
        print("[proxy] Requesting sqlite_db_access lock...")
      end
      navigator.locks:request("sqlite_db_access", function ()
        -- We got the lock - we're the provider!
        if verbose then
          print("[proxy] Acquired sqlite_db_access lock - becoming provider!")
        end
        is_provider = true

        if verbose then
          print("[proxy] Initializing database worker...")
        end
        db, worker = wrpc.init(bundle_path)
        if verbose then
          print("[proxy] Database worker initialized, db:", db, "worker:", worker)
        end

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
          if verbose then
            print("[proxy] Provider received SW message:", ev.data and ev.data.type)
          end
          if ev.data and ev.data.type == "sw_port_request" and is_provider then
            if verbose then
              print("[proxy] SW requesting port")
            end
            local controller = navigator.serviceWorker.controller
            if not controller then
              if verbose then
                print("[proxy] No SW controller for sw_port response")
              end
              return
            end
            local port = create_rpc_port()
            if verbose then
              print("[proxy] Sending sw_port to SW")
            end
            controller:postMessage(
              val({ type = "sw_port" }, true),
              { port }
            )
          end
        end)

        -- Announce we're the provider
        if verbose then
          print("[proxy] Announcing as provider, clientId:", client_id)
        end
        broadcast_channel:postMessage(val({
          type = "provider",
          clientId = client_id
        }, true))

        if callback then
          if verbose then
            print("[proxy] Calling ready callback")
          end
          callback()
        end

        -- Hold lock forever (until tab closes)
        return util.promise(function () end)
      end)

      -- Also try to connect as consumer immediately
      -- (in case a provider already exists and we're waiting in lock queue)
      if verbose then
        print("[proxy] Also trying to connect as consumer...")
      end
      request_provider_port(provider_counter)
    end)
  end)
end
