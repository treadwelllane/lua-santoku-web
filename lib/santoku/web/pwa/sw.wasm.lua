local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.async")
local it = require("santoku.iter")
local fun = require("santoku.functional")
local tbl = require("santoku.table")

local global = js.self
local Module = global.Module
local caches = js.caches
local clients = js.clients
local Promise = js.Promise
local URL = js.URL
local Response = js.Response
local Math = js.Math
local navigator = global.navigator

local defaults = {
  cache_fetch_retry_backoff_ms = 1000,
  cache_fetch_retry_backoff_multiply = 2,
  cache_fetch_retry_times = 3,
  page_ready_timeout_ms = 10000,
}

local function random_string ()
  return tostring(Math:random()):gsub("0%%.", "")
end

return function (opts)

  opts = tbl.merge({}, defaults, opts or {})

  local db_provider_client_id = nil
  local db_provider_port = nil
  local db_registered_clients = {}
  local db_sw_port = nil
  local db_sw_callbacks = {}
  local db_pending_queue = {}

  local trigger_failover

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
      global:setTimeout(function ()
        if opts.verbose and not page_ready then
          print("Page ready timeout, proceeding with pre-cache")
        end
        call_once()
      end, opts.page_ready_timeout_ms)
    end
  end

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
    return util.promise(function (complete)
      return async.pipe(function (done)
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
              cache = "force-cache",
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

  local function match_route (pathname)
    if not opts.routes then
      return nil
    end
    if opts.routes[pathname] then
      return opts.routes[pathname], {}
    end
    for pattern, handler in pairs(opts.routes) do
      local params = {}
      local regex = "^" .. pattern:gsub(":([^/]+)", function (name)
        params[#params + 1] = name
        return "([^/]+)"
      end) .. "$"
      local captures = { pathname:match(regex) }
      if #captures > 0 then
        local result = {}
        for i, name in ipairs(params) do
          result[name] = captures[i]
        end
        return handler, result
      end
    end
    return nil
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
        headers:set("Cross-Origin-Opener-Policy", "same-origin")
        headers:set("Cross-Origin-Embedder-Policy", "require-corp")
        complete(true, Response:new(opts.index_html, { headers = headers }))
      end)
    end

    local handler, params = match_route(pathname)
    if handler then
      return util.promise(function (complete)
        handler(request, params, function (ok, result, content_type)
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

  local function setup_sw_port_to_provider ()
    if not db_provider_port then
      return
    end
    local original_handler = db_provider_port.onmessage
    db_provider_port.onmessage = function (_, ev)
      local sw_port = ev.ports[1]
      if sw_port then
        db_sw_port = sw_port
        db_sw_port.onmessage = function (_, msg_ev)
          local data = msg_ev.data
          if data and data.nonce and db_sw_callbacks[data.nonce] then
            local callback = db_sw_callbacks[data.nonce]
            db_sw_callbacks[data.nonce] = nil
            if data.error then
              return callback(false, data.error.message or tostring(data.error))
            else
              return callback(true, data.result)
            end
          end
        end
        db_sw_port:start()
        flush_queue()
      end
      db_provider_port.onmessage = original_handler
    end
    db_provider_port:postMessage("sw")
  end

  local function connect_client_to_provider (client_id)
    if not db_provider_port then
      return
    end
    local original_handler = db_provider_port.onmessage
    db_provider_port.onmessage = function (_, ev)
      local client_port = ev.ports[1]
      if client_port then
        clients:get(client_id):await(function (_, ok, client)
          if ok and client then
            client:postMessage(val({ type = "db_consumer" }, true), { client_port })
          end
        end)
      end
      db_provider_port.onmessage = original_handler
    end
    db_provider_port:postMessage(client_id)
  end

  local failover_in_progress = false
  local provider_lock_controller = nil

  local function monitor_provider_lock (client_id)
    if provider_lock_controller then
      provider_lock_controller:abort()
      provider_lock_controller = nil
    end
    if not navigator or not navigator.locks then
      return
    end
    provider_lock_controller = js.AbortController:new()
    local lock_name = "db_provider_" .. client_id
    navigator.locks:request(lock_name, {
      mode = "exclusive",
      ifAvailable = false,
      signal = provider_lock_controller.signal
    }, function ()
      return Promise:new(function (resolve)
        if db_provider_client_id == client_id then
          db_sw_port = nil
          db_provider_port = nil
          db_provider_client_id = nil
          db_registered_clients[client_id] = nil
          trigger_failover()
        end
        resolve()
      end)
    end):catch(function () end)
  end

  local function promote_provider (client_id, port)
    db_provider_client_id = client_id
    db_provider_port = port
    db_provider_port:start()
    setup_sw_port_to_provider()
    for cid, _ in pairs(db_registered_clients) do
      if cid ~= client_id then
        connect_client_to_provider(cid)
      end
    end
  end

  trigger_failover = function ()
    if failover_in_progress then return end
    if db_sw_port then return end

    failover_in_progress = true

    db_provider_client_id = nil
    db_provider_port = nil
    db_sw_port = nil

    local cid, port = next(db_registered_clients)
    if not cid then
      failover_in_progress = false
      return
    end

    clients:get(cid):await(function (_, ok, client)
      failover_in_progress = false
      if db_sw_port then return end
      if ok and client then
        promote_provider(cid, port)
        client:postMessage(val({ type = "db_provider", client_id = cid }, true))
      else
        db_registered_clients[cid] = nil
        trigger_failover()
      end
    end)
  end

  Module.on_message = function (_, ev, client_id)
    local data = ev.data
    if not data then
      return
    end

    -- Handle page resources loaded signal for coordinated pre-caching
    if data.type == "page_resources_loaded" then
      return on_page_resources_loaded()
    end

    if opts.sqlite then
      local port = ev.ports[1]
      if data.type == "db_register" and port then
        db_registered_clients[client_id] = port
        if not db_provider_client_id then
          promote_provider(client_id, port)
          clients:get(client_id):await(function (_, ok, client)
            if ok and client then
              client:postMessage(val({ type = "db_provider", client_id = client_id }, true))
            end
          end)
        else
          connect_client_to_provider(client_id)
        end
      elseif data.type == "db_unregister" then
        db_registered_clients[client_id] = nil
        if client_id == db_provider_client_id then
          trigger_failover()
        end
      elseif data.type == "lock_acquired" then
        if client_id == db_provider_client_id then
          monitor_provider_lock(client_id)
        end
      end
    end

    if opts.on_message then
      return opts.on_message(ev)
    end
  end

  Module:start()

end
