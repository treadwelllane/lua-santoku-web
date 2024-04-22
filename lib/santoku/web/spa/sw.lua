local js = require("santoku.web.js")
local str = require("santoku.string")
local fs = require("santoku.fs")
local arr = require("santoku.array")
local util = require("santoku.web.util")
local async = require("santoku.async")
local it = require("santoku.iter")
local fun = require("santoku.functional")
local global = js.self
local Module = global.Module
local caches = js.caches
local clients = js.clients
local Promise = js.Promise

return function (opts)

  opts = opts or {}

  opts.cached_files = opts.cached_files ~= false and
    opts.cached_files or
      arr.push(it.collect(it.flatten(it.map(function (fp)
        return it.ivals({ fp, fs.stripextensions(fp) })
      end, it.ivals(opts.public_files or {})))), "/")

  Module.on_install = function ()
    print("Installing service worker")
    return util.promise(function (complete)
      return async.pipe(function (done)
        return caches:open(opts.service_worker_version):await(fun.sel(done, 2))
      end, function (done, cache)
        return async.each(it.ivals(opts.cached_files), function (each_done, file)
          return async.pipe(function (done)
            return util.fetch(file, {
              -- TODO: This is not currently implemented
              retry_times = opts.cache_fetch_retry_times,
              backoff_ms = opts.cache_fetch_retry_backoff_ms,
              backoff_multiply = opts.cache_fetch_retry_backoff_multiply,
            }):await(fun.sel(done, 2))
          end, function (done, res)
            return cache:put(file, res):await(fun.sel(done, 2))
          end, function (ok, err, ...)
            if not ok then
              print("Failed caching", file, err and err.message)
            end
            print("Cached", file)
            return each_done(ok, ...)
          end)
        end, done)
      end, function (done)
        return global:skipWaiting():await(fun.sel(done, 2))
      end, function (ok, ...)
        if ok then
          print("Installed service worker")
        else
          print("Error installing service worker", (...) and (...).message or (...))
        end
        return complete(ok, ...)
      end)
    end)
  end

  Module.on_activate = function ()
    print("Activating service worker")
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
        if ok then
          print("Activated service worker")
        else
          print("Error activating service worker")
        end
        return complete(ok, ...)
      end)
    end)
  end

  Module.on_fetch = function (_, request)
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
          print("Cache miss", request.url)
          return util.fetch(request):await(fun.sel(done, 2))
        else
          return done(true, resp:clone())
        end
      end, complete)
    end)
  end

  Module:start()

end
