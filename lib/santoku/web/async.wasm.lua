local co_factory = require("santoku.co")
local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.error")

local Promise = js.Promise

local queue = {}
local resolvers = {}
local current_ctx = nil

local globalThis = val.global("globalThis")

globalThis.__luaAsyncDrain = function ()
  while #queue > 0 do
    local item = table.remove(queue, 1)
    local ctx, ok, res = item[1], item[2], item[3]
    if ctx.co.status(ctx.thread) == "suspended" then
      local prev = current_ctx
      current_ctx = ctx
      local success, ret = ctx.co.resume(ctx.thread, ok, res)
      current_ctx = prev
      if ctx.co.status(ctx.thread) == "dead" then
        local r = resolvers[ctx.thread]
        if r then
          if success then
            r.resolve:call(nil, ret)
          else
            r.reject:call(nil, ret)
          end
          resolvers[ctx.thread] = nil
        end
      end
    end
  end
end

val.global("eval"):call(nil, [[
  (function() {
    var scheduled = false;
    function drain() {
      scheduled = false;
      if (globalThis.__luaAsyncDrain) globalThis.__luaAsyncDrain();
    }
    globalThis.__luaAsyncSchedule = function() {
      if (!scheduled) {
        scheduled = true;
        setTimeout(drain, 0);
      }
    };
  })()
]])

local schedule = val.global("__luaAsyncSchedule")

local function await (p, callback)
  if callback then
    p["then"]:call(p,
      function (_, res) callback(nil, true, res) end,
      function (_, res) callback(nil, false, res) end)
    return
  end
  local ctx = current_ctx
  if not ctx then
    error("await called outside async context")
  end
  p["then"]:call(p,
    function (_, res)
      queue[#queue + 1] = { ctx, true, res }
      schedule:call(nil)
    end,
    function (_, res)
      queue[#queue + 1] = { ctx, false, res }
      schedule:call(nil)
    end)
  local ok, res = ctx.co.yield()
  if not ok then
    err.error(res)
  end
  return res
end

_G.__tk_await = await

local function async (f)
  local co = co_factory()
  local thread
  local resolve_fn, reject_fn

  local promise = Promise:new(function (_, resolve, reject)
    resolve_fn = resolve
    reject_fn = reject
  end)

  local ctx = { co = co }

  thread = co.create(function ()
    return f(await)
  end)

  ctx.thread = thread
  resolvers[thread] = { resolve = resolve_fn, reject = reject_fn }

  local prev = current_ctx
  current_ctx = ctx
  local success, ret = co.resume(thread)
  current_ctx = prev

  if co.status(thread) == "dead" then
    if success then
      resolve_fn:call(nil, ret)
    else
      reject_fn:call(nil, ret)
    end
    resolvers[thread] = nil
  end

  return promise
end

return setmetatable({
  async = async,
  await = await,
}, {
  __call = function (_, f)
    return async(f)
  end
})
