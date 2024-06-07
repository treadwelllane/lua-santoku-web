local arr = require("santoku.array")
local varg = require("santoku.varg")

return function (callback, global, opts, run, ...)

  opts = opts or {}

  local JSON = global.JSON
  local console = global.console

  local logtypes = { "log", "error" }
  local oldlogs = {}
  local oldprint = nil
  local oldfetch = nil

  local function format (...)
    return JSON:stringify({ opts.name or "(no label)", ... })
  end

  local function wrapFetch ()
    oldfetch = global.fetch
    global.fetch = function (_, ...)
      callback(format("fetch", { ... }))
      return oldfetch(_, ...)
    end
  end

  local function wrapPrint ()
    oldprint = print
    _G.print = function (...)
      oldprint(...)
      callback(format("print", { ... }))
    end
  end

  local function wrapLog (typ)
    if oldlogs[typ] then
      return
    end
    oldlogs[typ] = console[typ]
    console[typ] = function (_, ...)
      oldlogs.log(console, ...)
      callback(format("console." .. typ, { varg.map(function (e)
        -- TODO: check if instanceof error object instead of duck type
        return e and e.message or e
      end, ...) }))
    end
  end

  local function wrapLogs ()
    arr.each(logtypes, function(lt)
      wrapLog(lt)
    end)
  end

  local function wrapError ()
    if global.addEventListener then
      global:addEventListener("error", function (_, ev)
        ev = ev and ev.error or ev
        callback(format("error", { ev }))
      end)
      global:addEventListener("uncaughtException", function (_, ev)
        ev = ev and ev.error or ev
        callback(format("uncaughtException", { ev }))
      end)
      global:addEventListener("unhandledRejection", function (_, ev)
        ev = ev and ev.error or ev
        callback(format("unhandledRejection", { ev }))
      end)
    end
    if global.process and global.process.on then
      global.process:on("uncaughtException", function (_, ev)
        ev = ev and ev.error or ev
        callback(format("uncaughtException", { ev }))
      end)
      global.process:on("unhandledRejection", function (_, ev)
        ev = ev and ev.error or ev
        callback(format("unhandledRejection", { ev }))
      end)
    end
  end

  if opts.fetch ~= false then
    wrapFetch()
  end

  if opts.print ~= false then
    wrapPrint()
  end

  if opts.logs ~= false then
    wrapLogs()
  end

  if opts.error ~= false then
    wrapError()
  end

  if run then
    varg.tup(function (ok, ...)
      if not ok then
        callback(format("error", { ... }))
      end
    end, pcall(run, ...))
  end

  return {
    oldlogs = oldlogs
  }

end
