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

  if opts.print ~= false then
    wrapPrint()
  end

  if opts.logs ~= false then
    wrapLogs()
  end

  return {
    oldlogs = oldlogs
  }

end
