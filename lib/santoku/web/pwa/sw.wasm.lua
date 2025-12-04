local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.async")
local it = require("santoku.iter")
local fun = require("santoku.functional")
local tbl = require("santoku.table")
local str = require("santoku.string")
local rand = require("santoku.random")

local global = js.self
local Module = global.Module
local caches = js.caches
local clients = js.clients
local Promise = js.Promise
local URL = js.URL
local Response = js.Response
local BroadcastChannel = js.BroadcastChannel

local defaults = {
  cache_fetch_retry_backoff_ms = 1000,
  cache_fetch_retry_backoff_multiply = 2,
  cache_fetch_retry_times = 3,
  page_ready_timeout_ms = 10000,
}

local function random_string ()
  return rand.alnum(16)
end

return function (opts)

  opts = tbl.merge({}, defaults, opts or {})

  -- Page ready signaling for coordinated pre-caching
  local page_ready = false
  local page_ready_callbacks = {}

  local function on_page_resources_loaded ()
    if page_ready then return end
    page_ready = true
    if opts.verbose then
      print("Page resources loaded, proceeding with pre-cache")
    end
    for i = 1, #page_ready_callbacks do
      page_ready_callbacks[i]()
    end
    page_ready_callbacks = {}
  end

  local function wait_for_page_ready (callback)
    if page_ready then
      return callback()
    end

    local called = false
    local function call_once ()
      if called then return end
      called = true
      callback()
    end

    page_ready_callbacks[#page_ready_callbacks + 1] = call_once

    -- Timeout fallback in case page never signals
    if opts.page_ready_timeout_ms then
      util.set_timeout(function ()
        if opts.verbose and not page_ready then
          print("Page ready timeout, proceeding with pre-cache")
        end
        call_once()
      end, opts.page_ready_timeout_ms)
    end
  end

  -- SW database access via SharedService pattern
  -- SW connects to provider as a consumer via BroadcastChannel
  local db_sw_port = nil
  local db_sw_callbacks = {}
  local db_pending_queue = {}
  local db_provider_client_id = nil
  local db_port_request_pending = false
  local pending_consumer_ports = {} -- Ports waiting for consumers to fetch

  local function flush_queue ()
    if not db_sw_port then
      return
    end
    local queue = db_pending_queue
    db_pending_queue = {}
    for i = 1, #queue do
      local req = queue[i]
      local nonce = random_string()
      db_sw_callbacks[nonce] = req.callback
      db_sw_port:postMessage(val({
        nonce = nonce,
        method = req.method,
        args = req.args
      }, true))
    end
  end

  local function db_call (method, args, callback)
    if not db_sw_port then
      db_pending_queue[#db_pending_queue + 1] = {
        method = method,
        args = args,
        callback = callback
      }
      return
    end

    local nonce = random_string()

    db_sw_callbacks[nonce] = function (ok, result)
      return callback(ok, result)
    end

    db_sw_port:postMessage(val({
      nonce = nonce,
      method = method,
      args = args
    }, true))
  end

  local db = nil
  if opts.sqlite then
    db = setmetatable({}, {
      __index = function (_, method)
        return function (...)
          local n = select("#", ...)
          local callback = select(n, ...)
          local args = {}
          for i = 1, n - 1 do
            args[i] = select(i, ...)
          end
          return db_call(method, args, callback)
        end
      end
    })

    -- Listen for provider announcements via BroadcastChannel
    local broadcast_channel = BroadcastChannel:new("sqlite_shared_service")
    if opts.verbose then
      print("[SW] Created BroadcastChannel for sqlite_shared_service")
    end

    local function request_sw_port ()
      if opts.verbose then
        print("[SW] request_sw_port called, has provider:", db_provider_client_id ~= nil, "pending:", db_port_request_pending)
      end
      if not db_provider_client_id then return end
      if db_sw_port then return end -- Already have a port
      if db_port_request_pending then return end -- Request already in flight

      db_port_request_pending = true
      if opts.verbose then
        print("[SW] Broadcasting sw_port_request on BroadcastChannel")
      end

      -- Broadcast request for port - provider will respond via controller.postMessage
      broadcast_channel:postMessage(val({
        type = "sw_port_request"
      }, true))
    end

    broadcast_channel.onmessage = function (_, ev)
      local data = ev.data
      if opts.verbose then
        print("[SW] Received broadcast:", data and data.type, "clientId:", data and data.clientId)
      end
      if data and data.type == "provider" and data.clientId then
        -- New provider announced - ignore if same provider and we have a port
        if data.clientId == db_provider_client_id and db_sw_port then
          if opts.verbose then
            print("[SW] Ignoring duplicate provider announcement")
          end
          return
        end
        if opts.verbose then
          print("[SW] New provider announced:", data.clientId)
        end
        if db_sw_port then
          if opts.verbose then
            local count = 0
            for _ in pairs(db_sw_callbacks) do count = count + 1 end
            print("[SW] Closing old db_sw_port, pending callbacks:", count)
          end
          -- Fail all pending callbacks - they were sent to old provider
          for nonce, callback in pairs(db_sw_callbacks) do
            if opts.verbose then
              print("[SW] Failing pending callback:", nonce)
            end
            callback(false, "Provider changed")
          end
          db_sw_callbacks = {}
          db_sw_port:close()
          db_sw_port = nil
        end
        db_port_request_pending = false
        db_provider_client_id = data.clientId
        request_sw_port()
      end
    end
  end

  if type(opts.routes) == "function" then
    opts.routes = opts.routes(db)
  end

  opts.service_worker_version = opts.service_worker_version
    and tostring(opts.service_worker_version) or "0"

  opts.cached_files = opts.cached_files or {}

  Module.on_install = function ()
    if opts.verbose then
      print("Installing service worker")
    end
    -- Check if this is an update (existing active SW) or first install
    local is_update = global.registration.active ~= nil
    return util.promise(function (complete)
      return async.pipe(function (done)
        if is_update then
          -- Skip waiting for page ready on updates - we need fresh files
          return done(true)
        end
        -- Wait for page to signal that its resources are loaded
        -- This allows us to pull from HTTP cache instead of network
        return wait_for_page_ready(function ()
          return done(true)
        end)
      end, function (done)
        return caches:open(opts.service_worker_version):await(fun.sel(done, 2))
      end, function (done, cache)
        return async.each(it.ivals(opts.cached_files), function (each_done, file)
          return async.pipe(function (done)
            return util.get({
              url = file,
              raw = true,
              done = done,
              retries = opts.cache_fetch_retry_times,
              backoffs = opts.cache_fetch_retry_backoff_ms
                and (opts.cache_fetch_retry_backoff_ms * 1000)
                or nil,
            })
          end, function (done, res)
            return cache:put(file, res):await(fun.sel(done, 2))
          end, function (ok, err, ...)
            if not ok and opts.verbose then
              print("Failed caching", file, err and err.message)
            elseif opts.verbose then
              print("Cached", file)
            end
            return each_done(ok, ...)
          end)
        end, done)
      end, function (done)
        if not global.registration.active then
          return global:skipWaiting():await(fun.sel(done, 2))
        else
          return done(true)
        end
      end, function (ok, ...)
        if ok and opts.verbose then
          print("Installed service worker")
        elseif not ok and opts.verbose then
          print("Error installing service worker", (...) and (...).message or (...))
        end
        return complete(ok, ...)
      end)
    end)
  end

  Module.on_activate = function ()
    if opts.verbose then
      print("Activating service worker")
    end
    return util.promise(function (complete)
      return async.pipe(function (done)
        return caches:keys():await(fun.sel(done, 2))
      end, function (done, keys)
        return Promise:all(keys:filter(function (_, k)
          return k ~= opts.service_worker_version
        end):map(function (_, k)
          return caches:delete(k)
        end)):await(fun.sel(done, 2))
      end, function (done)
        return clients:claim():await(fun.sel(done, 2))
      end, function (ok, ...)
        if ok and opts.verbose then
          print("Activated service worker")
        elseif not ok and opts.verbose then
          print("Error activating service worker")
        end
        return complete(ok, ...)
      end)
    end)
  end

  local function default_fetch_handler(request)
    return util.promise(function (complete)
      local cache_ref = nil
      local was_miss = false
      return async.pipe(function (done)
        return caches:open(opts.service_worker_version):await(fun.sel(done, 2))
      end, function (done, cache)
        cache_ref = cache
        return cache:match(request, {
          ignoreSearch = true,
          ignoreVary = true,
          ignoreMethod = true
        }):await(fun.sel(done, 2))
      end, function (done, resp)
        if not resp then
          was_miss = true
          if opts.verbose then
            print("Cache miss", request.url)
          end
          return util.fetch(request, nil, {
            done = done,
            retries = 0,
            raw = true,
          })
        else
          return done(true, resp:clone())
        end
      end, function (done, resp)
        -- Cache the response on miss for offline support
        if was_miss and cache_ref and resp and resp.ok then
          cache_ref:put(request, resp:clone()):await(function ()
            return done(true, resp)
          end)
        else
          return done(true, resp)
        end
      end, complete)
    end)
  end

  local function match_route (pathname, url)
    if not opts.routes then
      return nil
    end
    for pattern, handler in pairs(opts.routes) do
      if pathname:match(pattern) then
        local parsed = str.parse_url(url)
        return handler, parsed.path, parsed.params
      end
    end
  end

  local Headers = js.Headers

  local function create_response (body, content_type)
    content_type = content_type or "text/html"
    local headers = Headers:new()
    headers:set("Content-Type", content_type)
    return Response:new(body, { headers = headers })
  end

  local function create_error_response (message, status)
    status = status or 500
    if opts.verbose then
      print("SW error response:", status, tostring(message))
    end
    local headers = Headers:new()
    headers:set("Content-Type", "text/plain")
    return Response:new("Error: " .. tostring(message), {
      status = status,
      headers = headers
    })
  end

  Module.on_fetch = function (_, request, client_id)
    local url = URL:new(request.url)
    local pathname = url.pathname

    -- Serve embedded index.html directly for root route
    if opts.index_html and (pathname == "/" or pathname == "/index.html") then
      return util.promise(function (complete)
        local headers = Headers:new()
        headers:set("Content-Type", "text/html")
        complete(true, Response:new(opts.index_html, { headers = headers }))
      end)
    end

    local handler, path, params = match_route(pathname, request.url)
    if handler then
      local req = { path = path, params = params, raw = request }
      return util.promise(function (complete)
        handler(req, path, params, function (ok, result, content_type)
          if ok then
            complete(true, create_response(result, content_type))
          else
            complete(true, create_error_response(result))
          end
        end)
      end)
    end

    if opts.on_fetch then
      return opts.on_fetch(request, client_id, default_fetch_handler)
    end
    return default_fetch_handler(request)
  end

  Module.on_message = function (_, ev)
    local data = ev.data
    if not data then
      return
    end

    -- Handle skip waiting request from page
    if data.type == "skip_waiting" then
      return global:skipWaiting()
    end

    -- Handle page resources loaded signal for coordinated pre-caching
    if data.type == "page_resources_loaded" then
      return on_page_resources_loaded()
    end

    -- Store port from provider for consumer to fetch
    if data.type == "store_port" and data.nonce then
      if opts.verbose then
        print("[SW] Storing port for nonce:", data.nonce)
      end
      local port = ev.ports and ev.ports[1]
      if port then
        pending_consumer_ports[data.nonce] = port
        -- Clean up after timeout (30 seconds)
        util.set_timeout(function ()
          if pending_consumer_ports[data.nonce] then
            if opts.verbose then
              print("[SW] Cleaning up unclaimed port for nonce:", data.nonce)
            end
            pending_consumer_ports[data.nonce]:close()
            pending_consumer_ports[data.nonce] = nil
          end
        end, 30000)
      end
      return
    end

    -- Consumer fetching their port (uses event.source, no ID lookup needed)
    if data.type == "get_port" and data.nonce then
      if opts.verbose then
        print("[SW] Consumer fetching port for nonce:", data.nonce)
      end
      local port = pending_consumer_ports[data.nonce]
      if port then
        pending_consumer_ports[data.nonce] = nil
        if opts.verbose then
          print("[SW] Sending port to consumer via event.source")
        end
        ev.source:postMessage(val({
          type = "db_port",
          nonce = data.nonce
        }, true), { port })
      else
        if opts.verbose then
          print("[SW] No pending port for nonce:", data.nonce)
        end
      end
      return
    end

    -- Handle SW port from provider (response to sw_port_request)
    if opts.sqlite and data.type == "sw_port" then
      if opts.verbose then
        print("[SW] Received sw_port from provider")
      end
      local port = ev.ports and ev.ports[1]
      if port then
        if opts.verbose then
          print("[SW] Setting up db_sw_port")
        end
        db_port_request_pending = false
        db_sw_port = port
        db_sw_port.onmessage = function (_, msg_ev)
          local msg_data = msg_ev.data
          if opts.verbose then
            print("[SW] Received response on db_sw_port, nonce:", msg_data and msg_data.nonce)
          end
          if msg_data and msg_data.nonce and db_sw_callbacks[msg_data.nonce] then
            local callback = db_sw_callbacks[msg_data.nonce]
            db_sw_callbacks[msg_data.nonce] = nil
            if msg_data.error then
              return callback(false, msg_data.error.message or tostring(msg_data.error))
            else
              return callback(true, msg_data.result)
            end
          end
        end
        db_sw_port:start()
        if opts.verbose then
          print("[SW] Flushing pending queue, size:", #db_pending_queue)
        end
        flush_queue()
      else
        if opts.verbose then
          print("[SW] No port in sw_port message")
        end
      end
      return
    end

    if opts.on_message then
      return opts.on_message(ev)
    end
  end

  Module:start()

end
