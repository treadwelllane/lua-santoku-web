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
      return util.promise(function (complete) complete(true) end)
    end)
  end

  local function close_provider_connection ()
    if current_provider_port then
      current_provider_port:close()
      current_provider_port = nil
    end
    db = nil
  end

  local function request_provider_port (counter)
    if verbose then
      print("[proxy] request_provider_port called, counter:", counter, "provider_counter:", provider_counter, "is_provider:", is_provider, "db:", db)
    end
    if counter ~= provider_counter then return end
    if is_provider then return end
    if db then return end
    if not navigator.serviceWorker.controller then
      if verbose then
        print("[proxy] No SW controller yet, will retry")
      end
      util.set_timeout(function ()
        request_provider_port(counter)
      end, 500)
      return
    end

    local nonce = "req_" .. tostring(math.random()):sub(3)
    if verbose then
      print("[proxy] Requesting provider port with nonce:", nonce)
    end

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

    if verbose then
      print("[proxy] Broadcasting request to provider")
    end
    broadcast_channel:postMessage(val({
      type = "request",
      nonce = nonce
    }, true))

    util.set_timeout(function ()
      if counter == provider_counter and not db and not is_provider then
        local controller = navigator.serviceWorker.controller
        if controller then
          if verbose then
            print("[proxy] Fetching port from SW with nonce:", nonce)
          end
          controller:postMessage(val({
            type = "get_port",
            nonce = nonce
          }, true))
        end
      end
    end, 100)

    util.set_timeout(function ()
      if counter == provider_counter and not db and not is_provider then
        if verbose then
          print("[proxy] Port request timeout, retrying...")
        end
        navigator.serviceWorker:removeEventListener("message", on_sw_message)
        request_provider_port(counter)
      end
    end, 2000)
  end

  local function create_rpc_port ()
    local ch = MessageChannel:new()
    local port1, port2 = ch.port1, ch.port2

    port1.onmessage = function (_, msg_ev)
      local msg_data = msg_ev.data
      if msg_data and msg_data.method and msg_data.nonce then
        local args = {}
        local js_args = msg_data.args
        if js_args and js_args.length then
          for i = 1, js_args.length do args[i] = js_args[i] end
        end
        local method_ok, method_result = err.pcall(function ()
          return db[msg_data.method](arr.spread(args))
        end)
        local response = { nonce = msg_data.nonce }
        if method_ok then
          response.result = method_result
        else
          response.error = { message = tostring(method_result), name = "Error" }
        end
        port1:postMessage(val(response, true))
      end
    end
    port1:start()

    return port2
  end

  broadcast_channel.onmessage = function (_, ev)
    local data = ev.data
    if verbose then
      print("[proxy] Received broadcast:", data and data.type, "clientId:", data and data.clientId)
    end
    if not data then return end

    if data.type == "provider" then
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

    elseif data.type == "request" and is_provider and data.nonce then
      if verbose then
        print("[proxy] Consumer requesting port, nonce:", data.nonce)
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
        print("[proxy] Storing port in SW for consumer to fetch, nonce:", data.nonce)
      end

      controller:postMessage(
        val({ type = "store_port", nonce = data.nonce }, true),
        { port }
      )

    elseif data.type == "sw_port_request" and is_provider then
      if verbose then
        print("[proxy] SW requesting port via broadcast")
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
  end

  if verbose then
    print("[proxy] Waiting for SW ready...")
  end
  navigator.serviceWorker.ready:await(function (_, ok)
    if verbose then
      print("[proxy] SW ready callback, ok:", ok)
    end
    if not ok then return end

    get_client_id(function (cid)
      if verbose then
        print("[proxy] Got client ID:", cid)
      end
      if not cid then
        if verbose then
          print("[proxy] No client ID, cannot proceed")
        end
        return
      end
      client_id = cid

      if verbose then
        print("[proxy] Acquiring context lock for client:", client_id)
      end
      navigator.locks:request(client_id, function ()
        if verbose then
          print("[proxy] Context lock acquired")
        end
        return util.promise(function () end)
      end):catch(function () end)

      if verbose then
        print("[proxy] Requesting sqlite_db_access lock...")
      end
      navigator.locks:request("sqlite_db_access", function ()
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

        return util.promise(function () end)
      end)

      if verbose then
        print("[proxy] Also trying to connect as consumer...")
      end
      request_provider_port(provider_counter)
    end)
  end)
end
