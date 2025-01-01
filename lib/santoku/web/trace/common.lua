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

  local format_one
  format_one = function (x)
    if not (type(x) == "table" or type(x) == "userdata") then
      return x
    elseif x and x.constructor and x.constructor.name == "ErrorEvent" then
      return format_one(x.error)
    elseif x and x.constructor and x.constructor.name == "DOMException" then
      return { name = x.name, message = x.message, code = x.code }
    elseif x and x.constructor and x.constructor.name == "Error" then
      return { name = x.name, message = x.message, code = x.code }
    else
      return x
    end
  end

  local function format (...)
    return JSON:stringify({ opts.name or "(no label)", varg.map(format_one, ...) })
  end

  local function wrapFetch ()
    oldfetch = global.fetch
    global.fetch = function (_, ...)
      callback(format("fetch", ...))
      return oldfetch(_, ...)
    end
  end

  local function wrapPrint ()
    oldprint = print
    _G.print = function (...)
      oldprint(...)
      callback(format("print", ...))
    end
  end

  local function wrapLog (typ)
    if oldlogs[typ] then
      return
    end
    oldlogs[typ] = console[typ]
    console[typ] = function (_, ...)
      oldlogs.log(console, ...)
      callback(format("console." .. typ, ...))
    end
  end

  local function wrapLogs ()
    arr.each(logtypes, function(lt)
      wrapLog(lt)
    end)
  end

  local function wrapError ()
    if global.addEventListener then
      global:addEventListener("error", function (_, ...)
        callback(format("error", ...))
      end)
      global:addEventListener("uncaughtException", function (_, ...)
        callback(format("uncaughtException", ...))
      end)
      global:addEventListener("unhandledRejection", function (_, ...)
        callback(format("unhandledRejection", ...))
      end)
      global:addEventListener("unhandledrejection", function (_, ...)
        callback(format("unhandledrejection", ...))
      end)
    end
    if global.process and global.process.on then
      global.process:on("uncaughtException", function (_, ...)
        callback(format("uncaughtException", ...))
      end)
      global.process:on("unhandledRejection", function (_, ...)
        callback(format("unhandledRejection", ...))
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
        callback(format("error", ...))
      end
    end, pcall(run, ...))
  end

  return {
    oldlogs = oldlogs
  }

end
