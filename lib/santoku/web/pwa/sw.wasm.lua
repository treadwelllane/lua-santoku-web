local js = require("santoku.web.js")
local util = require("santoku.web.util")
local async = require("santoku.async")
local it = require("santoku.iter")
local fun = require("santoku.functional")
local tbl = require("santoku.table")

local global = js.self
local Module = global.Module
local caches = js.caches
local clients = js.clients
local Promise = js.Promise

local defaults = {
  cache_fetch_retry_backoff_ms = 1000,
  cache_fetch_retry_backoff_multiply = 2,
  cache_fetch_retry_times = 3,
}

return function (opts)

  opts = tbl.merge({}, defaults, opts or {})

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

  Module.on_fetch = function (_, request, client_id)
    if opts.on_fetch then
      return opts.on_fetch(request, client_id, default_fetch_handler)
    end
    return default_fetch_handler(request)
  end

  Module:start()

end
