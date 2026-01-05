local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.web.async")
local socket = require("santoku.web.socket")
local http_factory = require("santoku.http")
local str = require("santoku.string")
local arr = require("santoku.array")
local err = require("santoku.error")

local global = js.self
local Module = global.Module
local caches = js.caches
local clients = js.clients
local Promise = js.Promise
local URL = js.URL
local BroadcastChannel = js.BroadcastChannel
local MessageChannel = js.MessageChannel

return function (opts)

  opts = opts or {}

  local function extract_error_msg (err)
    if not err then return "unknown error" end
    if type(err) == "string" then return err end
    return err.message
      or (err.error and err.error.message)
      or (err.status and ("HTTP " .. tostring(err.status)))
      or tostring(err)
  end

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

  local function wait_for_page_ready ()
    if page_ready then
      return util.resolved()
    end
    return util.promise(function (complete)
      local called = false
      local function call_once ()
        if called then return end
        called = true
        complete(true)
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
    end)
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
    async(function ()
      local ok, all_clients = clients:matchAll():await()
      if not ok or not all_clients then return end
      all_clients:forEach(function (_, client)
        client:postMessage(val({ type = "version_mismatch" }, true))
      end)
    end)
  end

  local function is_same_origin (url)
    if type(url) == "string" then
      return str.startswith(url, "/") or str.startswith(url, global.location.origin)
    elseif url and url.url then
      return str.startswith(url.url, global.location.origin)
    end
    return false
  end

  local function matches_no_cache_pattern (pathname)
    if not opts.no_cache_patterns then return false end
    for i = 1, #opts.no_cache_patterns do
      if pathname:match(opts.no_cache_patterns[i]) then return true end
    end
    return false
  end

  local function send_db_call (method, args)
    return util.promise(function (complete)
      db_request_id = db_request_id + 1
      local id = db_request_id
      local ch = MessageChannel:new()
      db_inflight_requests[id] = { method = method, args = args, complete = complete, port = ch.port1 }
      db_sw_port:postMessage(val({ method, ch.port2, arr.spread(args) }, true), { ch.port2 })
      ch.port1.onmessage = function (_, ev)
        db_inflight_requests[id] = nil
        complete(true, ev.data)
      end
    end)
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
        complete = req.complete
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
      send_db_call(req.method, req.args):await(function (_, ...)
        req.complete(...)
      end)
    end
  end

  local function ping_provider (timeout)
    if not db_sw_port then return util.resolved(false) end
    return util.promise(function (complete)
      local done = false
      local timer = util.set_timeout(function ()
        if not done then done = true; complete(true, false) end
      end, timeout)
      local ch = MessageChannel:new()
      ch.port1.onmessage = function ()
        if not done then done = true; util.clear_timeout(timer); complete(true, true) end
      end
      db_sw_port:postMessage(val({ type = "ping" }, true), { ch.port2 })
    end)
  end

  local function elect_new_provider ()
    return async(function ()
      local ok, all_clients = clients:matchAll(val({ type = "window" }, true)):await()
      if not ok or not all_clients then return end
      local candidates = {}
      for i = 1, all_clients.length do
        if all_clients[i].id ~= db_provider_client_id then
          candidates[#candidates + 1] = all_clients[i]
        end
      end
      if #candidates == 0 then return end
      local new_provider = candidates[math.random(#candidates)]
      if opts.verbose then
        print("[SW] Electing new provider:", new_provider.id)
      end
      new_provider:postMessage(val({ type = "steal_provider" }, true))
      if db_sw_port then db_sw_port:close() end
      db_sw_port = nil
      db_provider_client_id = nil
    end)
  end

  local debounced_health_check = util.debounce(function ()
    async(function ()
      local alive = ping_provider(1000):await()
      if not alive then
        if opts.verbose then
          print("[SW] Provider ping failed, electing new provider")
        end
        elect_new_provider():await()
      end
    end)
  end, 1000)

  local function db_call (method, args)
    if opts.sqlite then
      debounced_health_check()
    end
    if not db_sw_port then
      return util.promise(function (complete)
        db_pending_queue[#db_pending_queue + 1] = {
          method = method,
          args = args,
          complete = complete
        }
      end)
    end
    return send_db_call(method, args)
  end

  local db = nil
  if opts.sqlite then
    db = setmetatable({}, {
      __index = function (_, method)
        return function (...)
          local _, result = db_call(method, { ... }):await()
          return err.checkok(arr.spread(val.lua(result, true)))
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
      elseif data and data.type == "provider_backgrounded" then
        if opts.verbose then
          print("[SW] Provider backgrounded:", data.clientId)
        end
        if db_sw_port then
          db_sw_port:close()
          db_sw_port = nil
        end
        requeue_inflight_requests()
        db_provider_client_id = nil
        db_port_request_pending = false
      end
    end
  end

  local http = http_factory(socket)

  local version_check_enabled = type(opts.version) == "string"
  local client_version = version_check_enabled and opts.version or nil

  http.on("request", function (k, url, req_opts)
    if not version_check_enabled or not is_same_origin(url) then
      return k(url, req_opts)
    end
    if type(url) == "string" then
      req_opts = req_opts or {}
      req_opts.headers = req_opts.headers or {}
      req_opts.headers["x-client-version"] = client_version
    elseif url and url.clone then
      local cloned = url:clone()
      local new_headers = js.Headers:new(cloned.headers)
      new_headers:set("x-client-version", client_version)
      url = js.Request:new(cloned, val({ headers = new_headers }, true))
    end
    return k(url, req_opts)
  end, true)

  opts.nonce = opts.nonce and tostring(opts.nonce) or "0"
  opts.precache = opts.precache or {}

  http.on("response", function (k, ok, resp)
    if not version_check_enabled then
      return k(ok, resp)
    end
    if not version_mismatch and resp and resp.headers then
      local server_version = resp.headers["x-app-version"]
      if server_version and server_version ~= client_version then
        version_mismatch = true
        broadcast_version_mismatch()
      end
    end
    return k(ok, resp)
  end, true)

  local function broadcast (name, data)
    async(function ()
      local ok, all_clients = clients:matchAll():await()
      if not ok or not all_clients then return end
      all_clients:forEach(function (_, client)
        client:postMessage(val({ type = "sw-broadcast", name = name, data = data }, true))
      end)
    end)
  end

  if type(opts.routes) == "function" then
    opts.routes = opts.routes(db, http, broadcast)
  end

  local hash_manifest = global.HASH_MANIFEST
  local function resolve_hashed(file)
    if hash_manifest then
      local hashed = hash_manifest[file]
      if hashed then
        return hashed
      end
    end
    return file
  end

  Module.on_install = function ()
    return async(function ()
      local is_update = global.registration.active ~= nil
      if opts.verbose then
        print("Installing service worker (is_update: " .. tostring(is_update) .. ", version: " .. opts.nonce .. ")")
      end

      if not is_update then
        wait_for_page_ready():await()
      end

      local ok, cache = caches:open(opts.nonce):await()
      if not ok then
        if opts.verbose then
          print("Error installing service worker:", extract_error_msg(cache))
        end
        return false, cache
      end

      for _, file in ipairs(opts.precache) do
        if matches_no_cache_pattern("/" .. file) then
          if opts.verbose then
            print("Skipping precache (no_cache_pattern):", file)
          end
        else
          local hashed_file = resolve_hashed(file)
          local full_url = URL:new(hashed_file, global.location.origin).href
          local _, existing = cache:match(full_url):await()
          if existing then
            if opts.verbose then
              print("Already cached", hashed_file)
            end
          else
            local resp_ok, resp = http.get(hashed_file, { retry = false })
            if not resp_ok or not resp or not resp.raw then
              local msg = extract_error_msg(resp)
              if opts.verbose then
                print("Failed caching", hashed_file, msg)
              end
              return false, "Failed to cache: " .. hashed_file .. " (" .. msg .. ")"
            else
              cache:put(full_url, resp.raw):await()
              if opts.verbose then
                print("Cached", hashed_file)
              end
            end
          end
        end
      end

      if opts.self_alias then
        local hashed_alias = resolve_hashed(opts.self_alias)
        if hashed_alias ~= opts.self_alias then
          local full_alias_url = URL:new("/" .. hashed_alias, global.location.origin).href
          local _, existing = cache:match(full_alias_url):await()
          if not existing then
            local ok1, resp = http.get("/sw.js", { retry = false })
            if ok1 and resp and resp.raw then
              cache:put(full_alias_url, resp.raw):await()
              if opts.verbose then
                print("Cached self alias:", hashed_alias)
              end
            else
              if opts.verbose then
                print("Failed to fetch /sw.js for self alias caching")
              end
              return false, "Failed to cache self alias: " .. hashed_alias
            end
          elseif opts.verbose then
            print("Self alias already cached:", hashed_alias)
          end
        end
      end

      if not global.registration.active then
        global:skipWaiting():await()
      end

      if opts.verbose then
        print("Installed service worker")
      end
      return true
    end)
  end

  Module.on_activate = function ()
    return async(function ()
      if opts.verbose then
        print("Activating service worker")
      end

      local ok, keys = caches:keys():await()
      if not ok then
        if opts.verbose then
          print("Error activating service worker")
        end
        return false, keys
      end

      Promise:all(keys:filter(function (_, k)
        return k ~= opts.nonce
      end):map(function (_, k)
        return caches:delete(k)
      end)):await()

      clients:claim():await()

      if opts.verbose then
        print("Activated service worker")
      end
      return true
    end)
  end

  local function default_fetch_handler(request)
    return async(function ()
      local url_obj = URL:new(request.url)
      local pathname = url_obj.pathname
      if matches_no_cache_pattern(pathname) then
        if opts.verbose then
          print("Bypassing cache (no_cache_pattern):", pathname)
        end
        local _, resp = http.fetch(request, { retry = false })
        return resp and resp.raw
      end

      if opts.verbose then
        print("Fetching:", request.url)
      end

      local _, cache = caches:open(opts.nonce):await()
      local _, cached_resp = cache:match(request.url, val({
        ignoreSearch = true,
        ignoreVary = true,
        ignoreMethod = true
      }, true)):await()

      if cached_resp then
        if opts.verbose then
          print("Cache hit:", request.url)
        end
        return cached_resp:clone()
      end

      if opts.verbose then
        print("Cache miss:", request.url)
      end
      local _, resp = http.fetch(request, { retry = false })
      local raw = resp and resp.raw
      if raw and raw.ok then
        cache:put(request, raw:clone()):await()
      end
      return raw
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

  Module.on_fetch = function (_, request, client_id)
    local url = URL:new(request.url)
    local pathname = url.pathname

    if opts.verbose then
      print("on_fetch:", pathname)
    end

    if opts.index_html and (pathname == "/" or pathname == "/index.html") then
      return async(function ()
        return util.response(opts.index_html, { content_type = "text/html" })
      end)
    end

    local update_path = opts.update_path or "/update"
    if pathname == update_path then
      local function wait_for_worker_state (sw, target_state)
        if sw.state == target_state then
          return util.resolved(true)
        end
        if sw.state == "redundant" then
          return util.resolved(false)
        end
        return util.promise(function (complete)
          sw:addEventListener("statechange", function ()
            if sw.state == target_state then
              complete(true, true)
            elseif sw.state == "redundant" then
              complete(true, false)
            end
          end)
        end)
      end
      return async(function ()
        if opts.verbose then
          print("[SW] /update called")
        end
        if global.registration.waiting then
          if opts.verbose then
            print("[SW] Activating waiting worker")
          end
          global.registration.waiting:postMessage(val({ type = "skip_waiting" }, true))
          return util.response("")
        end
        if global.registration.installing then
          if opts.verbose then
            print("[SW] Waiting for installing worker")
          end
          local ok = wait_for_worker_state(global.registration.installing, "installed"):await()
          if ok and global.registration.waiting then
            global.registration.waiting:postMessage(val({ type = "skip_waiting" }, true))
            return util.response("")
          end
          return util.response("update_failed")
        end
        if opts.verbose then
          print("[SW] Checking for updates")
        end
        global.registration:update():await()
        if global.registration.waiting then
          if opts.verbose then
            print("[SW] Found waiting worker after update check")
          end
          global.registration.waiting:postMessage(val({ type = "skip_waiting" }, true))
          return util.response("")
        end
        if global.registration.installing then
          if opts.verbose then
            print("[SW] Found installing worker after update check")
          end
          local ok = wait_for_worker_state(global.registration.installing, "installed"):await()
          if ok and global.registration.waiting then
            global.registration.waiting:postMessage(val({ type = "skip_waiting" }, true))
            return util.response("")
          end
          return util.response("update_failed")
        end
        if opts.verbose then
          print("[SW] No update available")
        end
        return util.response("no_update")
      end)
    end

    local handler, path, params = match_route(pathname, request.url)
    if handler then
      return async(function ()
        if request.method == "POST" then
          local content_type = request.headers and request.headers:get("Content-Type") or ""
          local body_params
          if content_type:match("application/json") then
            body_params = util.request_json(request)
          else
            body_params = util.request_formdata(request)
          end
          if body_params then
            for k, v in pairs(body_params) do
              params[k] = v
            end
          end
        end
        local req = { path = path, params = params, raw = request }
        local result, content_type, extra_headers = handler(req, path, params)
        if type(result) == "table" and (result.body ~= nil or result.status or result.headers) then
          return util.response(result.body or "", {
            status = result.status,
            content_type = result.content_type,
            headers = result.headers
          })
        end
        return util.response(result, { content_type = content_type, headers = extra_headers })
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
      if opts.verbose then
        print("[SW] Received skip_waiting message, calling skipWaiting()")
      end
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
