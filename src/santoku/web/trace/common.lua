local vec = require("santoku.vector")

return function (callback, global, opts)

  opts = opts or {}

  local JSON = global.JSON
  local console = global.console

  local logtypes = vec("log", "error")
  local oldlogs = {}
  local oldprint = nil

  local function wrapPrint ()
    oldprint = print
    _G.print = function (...)
      oldprint(...)
      callback(JSON:stringify({ "print", { ... } }))
    end
  end

  local function wrapLog (typ)
    if oldlogs[typ] then
      return
    end
    oldlogs[typ] = console[typ]
    console[typ] = function (_, ...)
      oldlogs.log(console, ...)
      callback(JSON:stringify({ "console." .. typ, { ... } }))
    end
  end

  local function wrapLogs ()
    logtypes:each(function(lt)
      wrapLog(lt)
    end)
  end

  local function wrapError ()
    if global.addEventListener then
      global:addEventListener("error", function (_, ev)
        callback(JSON:stringify({ "error", ev and ev.message or ev }))
      end)
      global:addEventListener("uncaughtException", function (_, ev)
        callback(JSON:stringify({ "uncaughtException", ev and ev.message or ev }))
      end)
      global:addEventListener("unhandledRejection", function (_, ev)
        callback(JSON:stringify({ "unhandledRejection", ev and ev.message or ev }))
      end)
    end
    if global.process and global.process.on then
      global.process:on("uncaughtException", function (_, ev)
        callback(JSON:stringify({ "uncaughtException", ev and ev.message or ev }))
      end)
      global.process:on("unhandledRejection", function (_, ev)
        callback(JSON:stringify({ "unhandledRejection", ev and ev.message or ev }))
      end)
    end
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

  return {
    oldlogs = oldlogs
  }

end
