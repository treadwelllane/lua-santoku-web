local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.web.async")
local wrpc = require("santoku.web.worker.rpc.client")

local navigator = js.navigator
local document = js.document
local MessageChannel = js.MessageChannel
local BroadcastChannel = js.BroadcastChannel
local AbortController = js.AbortController


return function (bundle_path, opts)
  opts = opts or {}
  local verbose = opts.verbose

  local db = nil
  local worker
  local is_provider = false
  local client_id = nil
  local provider_counter = 0
  local current_provider_port = nil
  local ready_resolver = nil
  local lock_abort = nil
  local becoming_provider = false
  local lock_release_resolver = nil

  local function hold_lock ()
    return util.promise(function (complete)
      lock_release_resolver = function ()
        lock_release_resolver = nil
        complete(true)
      end
    end)
  end

  local broadcast_channel = BroadcastChannel:new("sqlite_shared_service")

  local function release_provider ()
    if lock_abort then
      lock_abort:abort()
      lock_abort = nil
    end
    becoming_provider = false
    if not is_provider then return end
    if verbose then
      print("[proxy] Releasing provider role (tab backgrounded)")
    end
    is_provider = false
    if worker then
      worker:terminate()
      worker = nil
    end
    db = nil
    if lock_release_resolver then
      if verbose then
        print("[proxy] Releasing sqlite_db_access lock")
      end
      lock_release_resolver()
    end
    broadcast_channel:postMessage(val({
      type = "provider_backgrounded",
      clientId = client_id
    }, true))
  end

  local function setup_worker_error_handler (w)
    w.onmessage = function (_, ev)
      if ev.data and ev.data.type == "db_error" then
        if verbose then
          print("[proxy] Worker reported db_error, releasing provider role")
        end
        release_provider()
        if document and document.body then
          document.body.classList:add("db-error")
          document.body:dispatchEvent(js.CustomEvent:new("db-error", {
            detail = { error = ev.data.error }
          }))
        end
      end
    end
  end

  if verbose then
    print("[proxy] Initializing sqlite proxy")
  end

  local function get_client_id ()
    local nonce = "client_id_" .. tostring(math.random()):sub(3)
    if verbose then
      print("[proxy] Getting client ID with nonce:", nonce)
    end
    local found_client_id = nil
    navigator.locks:request(nonce, function ()
      return async(function ()
        local ok, state = navigator.locks:query():await()
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
              found_client_id = lock.clientId
              break
            end
          end
        end
        if verbose and not found_client_id then
          print("[proxy] Failed to find client ID")
        end
        return true
      end)
    end):await()
    return found_client_id
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
          db = wrpc.init_port(port)
          if ready_resolver then
            ready_resolver()
            ready_resolver = nil
          end
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

  local function create_worker_port ()
    local ch = MessageChannel:new()
    wrpc.register_port(worker, ch.port2)
    return ch.port1
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
      if is_provider and data.clientId and data.clientId ~= client_id then
        if verbose then
          print("[proxy] Another tab became provider, releasing our provider role")
        end
        release_provider()
      elseif not is_provider and client_id then
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

      local port = create_worker_port()
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
      local port = create_worker_port()
      if verbose then
        print("[proxy] Sending sw_port to SW")
      end
      controller:postMessage(
        val({ type = "sw_port" }, true),
        { port }
      )
    end
  end

  return util.promise(function (complete)
    ready_resolver = function ()
      complete(true)
    end

    async(function ()
      if verbose then
        print("[proxy] Waiting for SW ready...")
      end
      local ok = navigator.serviceWorker.ready:await()
      if verbose then
        print("[proxy] SW ready callback, ok:", ok)
      end
      if not ok then return end

      local cid = get_client_id()
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
        return hold_lock()
      end):catch(function () end)

      local function try_become_provider ()
        if verbose then
          print("[proxy] try_become_provider called, is_provider:", is_provider, "becoming_provider:", becoming_provider, "hidden:", document.hidden)
        end
        if is_provider or becoming_provider then return end
        if document.hidden then return end
        becoming_provider = true
        if verbose then
          print("[proxy] Requesting sqlite_db_access lock...")
        end
        lock_abort = AbortController:new()
        navigator.locks:request("sqlite_db_access", val({ signal = lock_abort.signal }, true), function ()
          becoming_provider = false
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
          setup_worker_error_handler(worker)

          if verbose then
            print("[proxy] Announcing as provider, clientId:", client_id)
          end
          broadcast_channel:postMessage(val({
            type = "provider",
            clientId = client_id
          }, true))

          if ready_resolver then
            if verbose then
              print("[proxy] Resolving ready promise")
            end
            ready_resolver()
            ready_resolver = nil
          end

          return hold_lock()
        end):catch(function (_, e)
          becoming_provider = false
          if e and e.name == "AbortError" then
            if verbose then
              print("[proxy] Lock request aborted (tab backgrounded)")
            end
          else
            if verbose then
              print("[proxy] Lock request failed:", e)
            end
          end
        end)
      end

      try_become_provider()

      document:addEventListener("visibilitychange", function ()
        if document.hidden then
          release_provider()
        else
          if verbose then
            print("[proxy] Tab visible, trying to become provider or consumer")
          end
          try_become_provider()
          if not is_provider and not becoming_provider then
            provider_counter = provider_counter + 1
            request_provider_port(provider_counter)
          end
        end
      end)

      if verbose then
        print("[proxy] Setting up steal_provider listener")
      end
      navigator.serviceWorker:addEventListener("message", function (_, ev)
        if ev.data and ev.data.type == "steal_provider" then
          if verbose then
            print("[proxy] Received steal_provider from SW, is_provider:", is_provider, "becoming_provider:", becoming_provider)
          end
          if is_provider then
            if verbose then
              print("[proxy] We were provider but SW thinks unresponsive, releasing without re-acquiring")
            end
            release_provider()
            return
          end
          if verbose then
            print("[proxy] Requesting lock with steal=true")
          end
          navigator.locks:request("sqlite_db_access", val({ steal = true }, true), function ()
            becoming_provider = false
            if verbose then
              print("[proxy] Acquired lock via steal, becoming provider")
            end
            is_provider = true
            db, worker = wrpc.init(bundle_path)
            if verbose then
              print("[proxy] Worker initialized after steal")
            end
            setup_worker_error_handler(worker)
            broadcast_channel:postMessage(val({
              type = "provider",
              clientId = client_id
            }, true))
            if verbose then
              print("[proxy] Broadcasted provider announcement after steal")
            end
            local controller = navigator.serviceWorker.controller
            if controller then
              local port = create_worker_port()
              controller:postMessage(val({ type = "sw_port" }, true), { port })
              if verbose then
                print("[proxy] Sent sw_port to controller after steal")
              end
            else
              if verbose then
                print("[proxy] No controller available to send sw_port after steal")
              end
            end
            if ready_resolver then
              if verbose then
                print("[proxy] Resolving ready promise after steal")
              end
              ready_resolver()
              ready_resolver = nil
            end
            return hold_lock()
          end):catch(function (_, e)
            becoming_provider = false
            if verbose then
              print("[proxy] Steal lock request failed:", e)
            end
          end)
        end
      end)

      if verbose then
        print("[proxy] Also trying to connect as consumer...")
      end
      request_provider_port(provider_counter)

      local fallback_delay = 5000 + math.floor(math.random() * 5000)
      if verbose then
        print("[proxy] Scheduling fallback timeout with jitter:", fallback_delay, "ms")
      end
      util.set_timeout(function ()
        if db or is_provider or becoming_provider then return end
        if verbose then
          print("[proxy] Fallback timeout: still no db, requesting lock normally")
        end
        becoming_provider = true
        navigator.locks:request("sqlite_db_access", function ()
          becoming_provider = false
          if verbose then
            print("[proxy] Fallback: acquired lock, becoming provider")
          end
          is_provider = true
          db, worker = wrpc.init(bundle_path)
          if verbose then
            print("[proxy] Fallback: worker initialized")
          end
          setup_worker_error_handler(worker)
          broadcast_channel:postMessage(val({
            type = "provider",
            clientId = client_id
          }, true))
          if verbose then
            print("[proxy] Fallback: broadcasted provider")
          end
          local controller = navigator.serviceWorker.controller
          if controller then
            local port = create_worker_port()
            controller:postMessage(val({ type = "sw_port" }, true), { port })
            if verbose then
              print("[proxy] Fallback: sent sw_port to controller")
            end
          end
          if ready_resolver then
            if verbose then
              print("[proxy] Fallback: resolving ready promise")
            end
            ready_resolver()
            ready_resolver = nil
          end
          return hold_lock()
        end):catch(function (_, e)
          becoming_provider = false
          if verbose then
            print("[proxy] Fallback lock request failed:", e)
          end
        end)
      end, fallback_delay)
    end)
  end)
end
