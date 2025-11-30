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
local MessageChannel = js.MessageChannel
local URL = js.URL
local Response = js.Response
local Math = js.Math

local defaults = {
  cache_fetch_retry_backoff_ms = 1000,
  cache_fetch_retry_backoff_multiply = 2,
  cache_fetch_retry_times = 3,
}

local function random_string ()
  return tostring(Math:random()):gsub("0%%.", "")
end

return function (opts)

  opts = tbl.merge({}, defaults, opts or {})

  -- Database coordination state (when db_name is set)
  local db_provider_client_id = nil
  local db_provider_port = nil
  local db_registered_clients = {}  -- { client_id = port }
  local db_sw_port = nil  -- SW's own port to provider for routes
  local db_sw_callbacks = {}  -- pending SW db call callbacks

  -- Create a db proxy for SW to make db calls
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
          -- Call provider via SW's port
          if not db_sw_port then
            return callback(false, "No db provider available")
          end
          local nonce = random_string()
          db_sw_callbacks[nonce] = callback
          return db_sw_port:postMessage(val({
            nonce = nonce,
            method = method,
            args = args
          }, true))
        end
      end
    })
  end

  -- If routes is a function, call it with db to get routes table
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
        return global:skipWaiting():await(fun.sel(done, 2))
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
      return async.pipe(function (done)
        return caches:open(opts.service_worker_version):await(fun.sel(done, 2))
      end, function (done, cache)
        return cache:match(request, {
          ignoreSearch = true,
          ignoreVary = true,
          ignoreMethod = true
        }):await(fun.sel(done, 2))
      end, function (done, resp)
        if not resp then
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
      end, complete)
    end)
  end

  -- Route matching helper
  local function match_route (pathname)
    if not opts.routes then
      return nil
    end
    -- Exact match first
    if opts.routes[pathname] then
      return opts.routes[pathname], {}
    end
    -- Pattern match (e.g., "/items/:id")
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

  -- Create response from route handler result
  local function create_response (body, content_type)
    content_type = content_type or "text/html"
    return Response:new(body, {
      headers = { ["Content-Type"] = content_type }
    })
  end

  -- Create error response
  local function create_error_response (message, status)
    status = status or 500
    return Response:new("Error: " .. tostring(message), {
      status = status,
      headers = { ["Content-Type"] = "text/plain" }
    })
  end

  Module.on_fetch = function (_, request, client_id)
    local url = URL:new(request.url)
    local pathname = url.pathname

    -- Check for route match
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

    -- Fall through to custom on_fetch or default handler
    if opts.on_fetch then
      return opts.on_fetch(request, client_id, default_fetch_handler)
    end
    return default_fetch_handler(request)
  end

  -- Database coordination message handler
  local function setup_sw_port_to_provider ()
    if not db_provider_port then
      return
    end
    -- Request a channel from provider port
    -- Provider will respond with a port in the transfer list
    local original_handler = db_provider_port.onmessage
    db_provider_port.onmessage = function (_, ev)
      if ev.ports and ev.ports[0] then
        db_sw_port = ev.ports[0]
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
      end
      -- Restore original handler for future channel requests
      db_provider_port.onmessage = original_handler
    end
    -- Send request for a channel
    db_provider_port:postMessage("sw")
  end

  local function connect_client_to_provider (client_id)
    if not db_provider_port then
      return
    end
    -- Request a channel from provider, then forward to client
    local original_handler = db_provider_port.onmessage
    db_provider_port.onmessage = function (_, ev)
      if ev.ports and ev.ports[0] then
        local client_port = ev.ports[0]
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

  local function promote_provider (client_id, port)
    db_provider_client_id = client_id
    db_provider_port = port
    db_provider_port:start()
    -- Setup SW's own connection
    setup_sw_port_to_provider()
    -- Connect any waiting clients
    for cid, _ in pairs(db_registered_clients) do
      if cid ~= client_id then
        connect_client_to_provider(cid)
      end
    end
  end

  local function check_provider_alive ()
    if not db_provider_client_id then
      return
    end
    clients:get(db_provider_client_id):await(function (_, ok, client)
      if not ok or not client then
        -- Provider is gone, promote another
        db_provider_client_id = nil
        db_provider_port = nil
        db_sw_port = nil
        for cid, port in pairs(db_registered_clients) do
          if cid ~= db_provider_client_id then
            promote_provider(cid, port)
            clients:get(cid):await(function (_, ok, c)
              if ok and c then
                c:postMessage(val({ type = "db_provider" }, true))
              end
            end)
            return
          end
        end
      end
    end)
  end

  if opts.sqlite then
    Module.on_message = function (_, ev, client_id)
      local data = ev.data
      if not data then
        return
      end

      if data.type == "db_register" and ev.ports and ev.ports[0] then
        -- Client registering its Worker port
        local port = ev.ports[0]
        db_registered_clients[client_id] = port
        if not db_provider_client_id then
          -- First client becomes provider
          promote_provider(client_id, port)
          clients:get(client_id):await(function (_, ok, client)
            if ok and client then
              client:postMessage(val({ type = "db_provider" }, true))
            end
          end)
        else
          -- Connect to existing provider
          connect_client_to_provider(client_id)
        end
      elseif data.type == "db_unregister" then
        db_registered_clients[client_id] = nil
        if client_id == db_provider_client_id then
          check_provider_alive()
        end
      end

      -- Also call custom on_message if provided
      if opts.on_message then
        return opts.on_message(ev)
      end
    end
  elseif opts.on_message then
    Module.on_message = function (_, ev)
      return opts.on_message(ev)
    end
  end

  Module:start()

end
