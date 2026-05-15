local js = require("santoku.web.js")
local util = require("santoku.web.util")
local val = require("santoku.web.val")
local async = require("santoku.web.async")
local socket = require("santoku.web.socket")
local http_factory = require("santoku.http")

local global = js.self
local Module = global.Module
local caches = js.caches
local clients = js.clients
local Promise = js.Promise
local URL = js.URL
local Response = js.Response

return function (opts)

  opts = opts or {}
  opts.nonce = opts.nonce and tostring(opts.nonce) or "0"
  opts.precache = opts.precache or {}

  local function extract_error_msg (err)
    if not err then return "unknown error" end
    if type(err) == "string" then return err end
    return err.message
      or (err.error and err.error.message)
      or (err.status and ("HTTP " .. tostring(err.status)))
      or tostring(err)
  end

  local function matches_no_cache_pattern (pathname)
    if not opts.no_cache_patterns then return false end
    for i = 1, #opts.no_cache_patterns do
      if pathname:match(opts.no_cache_patterns[i]) then return true end
    end
    return false
  end

  local http = http_factory(socket)

  local hash_manifest = global.HASH_MANIFEST
  local function resolve_hashed (file)
    if hash_manifest then
      local hashed = hash_manifest[file]
      if hashed then return hashed end
    end
    return file
  end

  Module.on_install = function ()
    return async(function ()
      if opts.verbose then
        print("Installing service worker (version: " .. opts.nonce .. ")")
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
          if opts.verbose then print("Skipping precache (no_cache_pattern):", file) end
        else
          local hashed_file = resolve_hashed(file)
          local full_url = URL:new(hashed_file, global.location.origin).href
          local _, existing = cache:match(full_url):await()
          if existing then
            if opts.verbose then print("Already cached", hashed_file) end
          else
            local resp_ok, resp = http.get(hashed_file, { retry = false })
            if not resp_ok or not resp or not resp.raw then
              local msg = extract_error_msg(resp)
              if opts.verbose then print("Failed caching", hashed_file, msg) end
              return false, "Failed to cache: " .. hashed_file .. " (" .. msg .. ")"
            end
            cache:put(full_url, resp.raw):await()
            if opts.verbose then print("Cached", hashed_file) end
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
              if opts.verbose then print("Cached self alias:", hashed_alias) end
            else
              if opts.verbose then print("Failed to fetch /sw.js for self alias caching") end
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
      if opts.verbose then print("Installed service worker") end
      return true
    end)
  end

  Module.on_activate = function ()
    return async(function ()
      if opts.verbose then print("Activating service worker") end
      local ok, keys = caches:keys():await()
      if not ok then
        if opts.verbose then print("Error activating service worker") end
        return false, keys
      end
      Promise:all(keys:filter(function (_, k)
        return k ~= opts.nonce
      end):map(function (_, k)
        return caches:delete(k)
      end)):await()
      clients:claim():await()
      if opts.verbose then print("Activated service worker") end
      return true
    end)
  end

  local function offline_response ()
    return Response:new("", val({ status = 503, statusText = "offline" }, true))
  end

  local function fetch_handler (request)
    return async(function ()
      local url_obj = URL:new(request.url)
      local pathname = url_obj.pathname
      if matches_no_cache_pattern(pathname) then
        if opts.verbose then print("Bypassing cache (no_cache_pattern):", pathname) end
        local _, resp = http.fetch(request, { retry = false })
        local raw = resp and resp.raw
        if not raw then return offline_response() end
        return raw
      end
      local _, cache = caches:open(opts.nonce):await()
      local _, cached_resp = cache:match(request.url, val({
        ignoreSearch = true,
        ignoreVary = true,
        ignoreMethod = true
      }, true)):await()
      if cached_resp then
        if opts.verbose then print("Cache hit:", request.url) end
        return cached_resp:clone()
      end
      if opts.verbose then print("Cache miss:", request.url) end
      local _, resp = http.fetch(request, { retry = false })
      local raw = resp and resp.raw
      if not raw then return offline_response() end
      if raw.ok then
        cache:put(request, raw:clone()):await()
      end
      return raw
    end)
  end

  Module.on_fetch = function (_, request)
    local url = URL:new(request.url)
    local pathname = url.pathname
    if opts.index_html and (pathname == "/" or pathname == "/index.html") then
      return async(function ()
        return util.response(opts.index_html, { content_type = "text/html" })
      end)
    end
    return fetch_handler(request)
  end

  local pending_consumer_ports = {}

  Module.on_message = function (_, ev)
    local data = ev.data
    if not data then return end
    if data.type == "skip_waiting" then
      if opts.verbose then print("[SW] Received skip_waiting, calling skipWaiting()") end
      return global:skipWaiting()
    end
    if data.type == "store_port" and data.nonce then
      if opts.verbose then print("[SW] Storing port for nonce:", data.nonce) end
      local port = ev.ports and ev.ports[1]
      if port then
        pending_consumer_ports[data.nonce] = port
        util.set_timeout(function ()
          if pending_consumer_ports[data.nonce] then
            if opts.verbose then print("[SW] Cleaning up unclaimed port for nonce:", data.nonce) end
            pending_consumer_ports[data.nonce]:close()
            pending_consumer_ports[data.nonce] = nil
          end
        end, 30000)
      end
      return
    end
    if data.type == "get_port" and data.nonce then
      if opts.verbose then print("[SW] Consumer fetching port for nonce:", data.nonce) end
      local port = pending_consumer_ports[data.nonce]
      if port then
        pending_consumer_ports[data.nonce] = nil
        ev.source:postMessage(val({
          type = "db_port",
          nonce = data.nonce
        }, true), { port })
      end
      return
    end
  end

  Module:start()

end
