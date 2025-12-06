local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.async")
local it = require("santoku.iter")
local fun = require("santoku.functional")
local tbl = require("santoku.table")
local str = require("santoku.string")
local arr = require("santoku.array")

local global = js.self
local Module = global.Module
local caches = js.caches
local clients = js.clients
local Promise = js.Promise
local URL = js.URL
local Response = js.Response
local BroadcastChannel = js.BroadcastChannel
local MessageChannel = js.MessageChannel

local defaults = {
  cache_fetch_retry_backoff_ms = 1000,
  cache_fetch_retry_backoff_multiply = 2,
  cache_fetch_retry_times = 3,
  page_ready_timeout_ms = 10000,
}

return function (opts)

  opts = tbl.merge({}, defaults, opts or {})

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

    if opts.page_ready_timeout_ms then
      util.set_timeout(function ()
        if opts.verbose and not page_ready then
          print("Page ready timeout, proceeding with pre-cache")
        end
        call_once()
      end, opts.page_ready_timeout_ms)
    end
  end

  local db_sw_port = nil
  local db_pending_queue = {}
  local db_inflight_requests = {}
  local db_request_id = 0
  local db_provider_client_id = nil
  local db_port_request_pending = false
  local db_provider_debounce_timer = nil
  local pending_consumer_ports = {}
  local version_mismatch = false

  local function broadcast_version_mismatch ()
    clients:matchAll():await(function (_, all_clients)
      for i = 0, all_clients.length - 1 do
        all_clients[i]:postMessage(val({ type = "version_mismatch" }, true))
      end
    end)
  end

  local function check_version_header (response)
    if opts.version_check == false then return end
    if not response or not response.ok then return end
    local server_version = response.headers:get("X-App-Version")
    if not server_version then return end
    if server_version ~= opts.service_worker_version then
      version_mismatch = true
      broadcast_version_mismatch()
    end
  end

  local function send_db_call (method, args, callback)
    db_request_id = db_request_id + 1
    local id = db_request_id
    local ch = MessageChannel:new()
    db_inflight_requests[id] = { method = method, args = args, callback = callback, port = ch.port1 }
    db_sw_port:postMessage(val({ method, ch.port2, arr.spread(args) }, true), { ch.port2 })
    ch.port1.onmessage = function (_, ev)
      db_inflight_requests[id] = nil
      local result = {}
      for i = 1, ev.data.length do result[i] = ev.data[i] end
      callback(arr.spread(result))
    end
  end

  local function requeue_inflight_requests ()
    for _, req in pairs(db_inflight_requests) do
      if opts.verbose then
        print("[SW] Re-queueing in-flight request:", req.method)
      end
      req.port:close()
      db_pending_queue[#db_pending_queue + 1] = {
        method = req.method,
        args = req.args,
        callback = req.callback
      }
    end
    db_inflight_requests = {}
  end

  local function flush_queue ()
    if not db_sw_port then
      return
    end
    local queue = db_pending_queue
    db_pending_queue = {}
    for i = 1, #queue do
      local req = queue[i]
      send_db_call(req.method, req.args, req.callback)
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
    send_db_call(method, args, callback)
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

    local broadcast_channel = BroadcastChannel:new("sqlite_shared_service")
    if opts.verbose then
      print("[SW] Created BroadcastChannel for sqlite_shared_service")
    end

    local function request_sw_port ()
      if opts.verbose then
        print("[SW] request_sw_port called, has provider:", db_provider_client_id ~= nil, "pending:", db_port_request_pending)
      end
      if not db_provider_client_id then return end
      if db_sw_port then return end
      if db_port_request_pending then return end

      db_port_request_pending = true
      if opts.verbose then
        print("[SW] Broadcasting sw_port_request on BroadcastChannel")
      end

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
        if data.clientId == db_provider_client_id and db_sw_port then
          if opts.verbose then
            print("[SW] Ignoring duplicate provider announcement")
          end
          return
        end
        if opts.verbose then
          print("[SW] New provider announced:", data.clientId)
        end
        db_provider_client_id = data.clientId
        if db_sw_port then
          if opts.verbose then
            print("[SW] Closing old db_sw_port immediately")
          end
          db_sw_port:close()
          db_sw_port = nil
          requeue_inflight_requests()
        end
        if db_provider_debounce_timer then
          util.clear_timeout(db_provider_debounce_timer)
        end
        db_provider_debounce_timer = util.set_timeout(function ()
          db_provider_debounce_timer = nil
          if opts.verbose then
            print("[SW] Requesting port after debounce:", db_provider_client_id)
          end
          db_port_request_pending = false
          request_sw_port()
        end, 200)
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
    local is_update = global.registration.active ~= nil
    if opts.verbose then
      print("Installing service worker (is_update: " .. tostring(is_update) .. ", version: " .. opts.service_worker_version .. ")")
    end
    return util.promise(function (complete)
      return async.pipe(function (done)
        if is_update then
          return done(true)
        end
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
            local full_url = URL:new(file, global.location.origin).href
            return cache:put(full_url, res):await(fun.sel(done, 2))
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
      if opts.verbose then
        print("Fetching:", request.url)
      end
      return async.pipe(function (done)
        return caches:open(opts.service_worker_version):await(fun.sel(done, 2))
      end, function (done, cache)
        cache_ref = cache
        return cache:match(request.url, val({
          ignoreSearch = true,
          ignoreVary = true,
          ignoreMethod = true
        }, true)):await(fun.sel(done, 2))
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
        if was_miss and resp then
          check_version_header(resp)
        end
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

    if opts.verbose then
      print("on_fetch:", pathname)
    end

    if opts.index_html and (pathname == "/" or pathname == "/index.html") then
      return util.promise(function (complete)
        local headers = Headers:new()
        headers:set("Content-Type", "text/html")
        complete(true, Response:new(opts.index_html, { headers = headers }))
      end)
    end

    local handler, path, params = match_route(pathname, request.url)
    if handler then
      if version_mismatch then
        return util.promise(function (complete)
          complete(true, create_error_response("Version mismatch", 503))
        end)
      end
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

    if data.type == "skip_waiting" then
      return global:skipWaiting()
    end

    if data.type == "page_resources_loaded" then
      return on_page_resources_loaded()
    end

    if data.type == "store_port" and data.nonce then
      if opts.verbose then
        print("[SW] Storing port for nonce:", data.nonce)
      end
      local port = ev.ports and ev.ports[1]
      if port then
        pending_consumer_ports[data.nonce] = port
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
