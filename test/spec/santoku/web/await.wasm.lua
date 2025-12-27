local test = require("santoku.test")
local js = require("santoku.web.js")
local val = require("santoku.web.val")
local async = require("santoku.web.async")
local err = require("santoku.error")
local validate = require("santoku.validate")

local assert = err.assert
local eq = validate.isequal

local Promise = js.Promise

test("await resolved promise", function ()
  async(function ()
    local result = Promise:resolve(42):await()
    assert(eq(42, result))
  end)
end)

test("chained async :await()", function ()
  async(function ()
    local result = async(function ()
      Promise:resolve("inner"):await()
      return "chained-result"
    end):await()
    assert(eq("chained-result", result))
  end)
end)

test("await rejected promise throws", function ()
  async(function ()
    local ok, e = err.pcall(function ()
      Promise:reject("error"):await()
    end)
    assert(eq(false, ok))
    assert(eq("error", e))
  end)
end)

test("await multiple promises", function ()
  async(function ()
    local r1 = Promise:resolve("first"):await()
    local r2 = Promise:resolve("second"):await()
    assert(eq("first", r1))
    assert(eq("second", r2))
  end)
end)

test("await with delay", function ()
  async(function ()
    local p = Promise:new(function (this, resolve)
      val.global("setTimeout"):call(nil, function ()
        resolve(this, "delayed")
      end, 50)
    end)
    local result = p:await()
    assert(eq("delayed", result))
  end)
end)

test("multiple independent async blocks", function ()
  local results = {}
  async(function ()
    local r = Promise:resolve("a"):await()
    results[#results + 1] = r
  end)
  async(function ()
    local r = Promise:resolve("b"):await()
    results[#results + 1] = r
  end)
  val.global("setTimeout"):call(nil, function ()
    assert(#results == 2)
  end, 100)
end)

test("nested async blocks", function ()
  local order = {}
  async(function ()
    order[#order + 1] = "outer-start"
    local r1 = Promise:resolve("outer-1"):await()
    order[#order + 1] = r1
    local inner = async(function ()
      order[#order + 1] = "inner-start"
      local r2 = Promise:resolve("inner-1"):await()
      order[#order + 1] = r2
      local r3 = Promise:resolve("inner-2"):await()
      order[#order + 1] = r3
      order[#order + 1] = "inner-end"
      return "inner-done"
    end)
    local r4 = Promise:resolve("outer-2"):await()
    order[#order + 1] = r4
    local innerResult = inner:await()
    assert(innerResult == "inner-done")
    order[#order + 1] = "outer-end"
  end)
  val.global("setTimeout"):call(nil, function ()
    assert(#order == 8, "expected 8 entries, got " .. #order)
    assert(order[1] == "outer-start")
    assert(order[8] == "outer-end")
  end, 200)
end)

test("await promise that resolves with another promise", function ()
  async(function ()
    local innerPromise = Promise:resolve("inner-value")
    local outerPromise = Promise:resolve(innerPromise)
    local result = outerPromise:await()
    assert(result == "inner-value")
  end)
end)

test("interleaved async blocks", function ()
  local log = {}
  async(function ()
    log[#log + 1] = "A1"
    Promise:new(function (this, resolve)
      val.global("setTimeout"):call(nil, function ()
        resolve(this, "A")
      end, 30)
    end):await()
    log[#log + 1] = "A2"
  end)
  async(function ()
    log[#log + 1] = "B1"
    Promise:new(function (this, resolve)
      val.global("setTimeout"):call(nil, function ()
        resolve(this, "B")
      end, 10)
    end):await()
    log[#log + 1] = "B2"
  end)
  val.global("setTimeout"):call(nil, function ()
    assert(log[1] == "A1")
    assert(log[2] == "B1")
    assert(log[3] == "B2")
    assert(log[4] == "A2")
  end, 100)
end)

test("async returns promise", function ()
  async(function ()
    local promise = async(function ()
      local v = Promise:resolve(21):await()
      return v * 2
    end)
    assert(promise:instanceof(Promise))
    local result = promise:await()
    assert(eq(42, result))
  end)
end)

test("async promise rejects on error", function ()
  async(function ()
    local promise = async(function ()
      Promise:resolve("before error"):await()
      error("intentional error")
    end)
    local ok = err.pcall(function ()
      promise:await()
    end)
    assert(eq(false, ok))
  end)
end)

test("async with no awaits resolves immediately", function ()
  local resolved = false
  local result = nil
  async(function ()
    return "sync-result"
  end):await(function (_, _, v)
    resolved = true
    result = v
  end)
  val.global("setTimeout"):call(nil, function ()
    assert(resolved, "promise should have resolved")
    assert(result == "sync-result", "expected sync-result, got " .. tostring(result))
  end, 50)
end)

test("error before any await", function ()
  async(function ()
    local promise = async(function ()
      error("immediate error")
    end)
    local ok, e = err.pcall(function ()
      promise:await()
    end)
    assert(eq(false, ok))
    assert(e:match("immediate error"))
  end)
end)

test("deeply nested async (3 levels)", function ()
  local trace = {}
  async(function ()
    trace[#trace + 1] = "L1-start"
    local p1 = async(function ()
      trace[#trace + 1] = "L2-start"
      local p2 = async(function ()
        trace[#trace + 1] = "L3-start"
        local v = Promise:resolve("deep"):await()
        trace[#trace + 1] = "L3-end"
        return v .. "-L3"
      end)
      local v = p2:await()
      trace[#trace + 1] = "L2-end"
      return v .. "-L2"
    end)
    local v = p1:await()
    trace[#trace + 1] = "L1-end"
    assert(v == "deep-L3-L2", "expected deep-L3-L2, got " .. tostring(v))
  end)
  val.global("setTimeout"):call(nil, function ()
    assert(#trace == 6, "expected 6 trace entries, got " .. #trace)
  end, 200)
end)

test("return value from async", function ()
  async(function ()
    local promise = async(function ()
      Promise:resolve("waiting"):await()
      return "result-value"
    end)
    local v = promise:await()
    assert(v == "result-value", "expected result-value, got " .. tostring(v))
  end)
end)

test("many concurrent async blocks", function ()
  local count = 0
  local n = 20
  for i = 1, n do
    async(function ()
      Promise:resolve(i):await()
      count = count + 1
    end)
  end
  val.global("setTimeout"):call(nil, function ()
    assert(count == n, "expected " .. n .. " completions, got " .. count)
  end, 200)
end)

test("await in loop with varying delays resolves in order", function ()
  local results = {}
  async(function ()
    for i = 3, 1, -1 do
      local v = Promise:new(function (this, resolve)
        val.global("setTimeout"):call(nil, function ()
          resolve(this, i)
        end, i * 10)
      end):await()
      results[#results + 1] = v
    end
  end)
  val.global("setTimeout"):call(nil, function ()
    assert(#results == 3)
    assert(results[1] == 3, "first should be 3")
    assert(results[2] == 2, "second should be 2")
    assert(results[3] == 1, "third should be 1")
  end, 200)
end)

test("classic sequential promise chain", function ()
  local log = {}
  local function delay(ms, value)
    return Promise:new(function (this, resolve)
      val.global("setTimeout"):call(nil, function ()
        resolve(this, value)
      end, ms)
    end)
  end
  async(function ()
    log[#log + 1] = "start"
    local userId = delay(10, "user-123"):await()
    log[#log + 1] = "got user: " .. userId
    local profile = delay(10, { name = "Alice", age = 30 }):await()
    log[#log + 1] = "got profile: " .. profile.name
    local posts = delay(10, { "post1", "post2", "post3" }):await()
    log[#log + 1] = "got " .. #posts .. " posts"
    local saved = delay(10, true):await()
    log[#log + 1] = saved and "saved" or "failed"
    log[#log + 1] = "done"
  end)
  val.global("setTimeout"):call(nil, function ()
    assert(#log == 6, "expected 6 log entries, got " .. #log)
    assert(log[1] == "start")
    assert(log[2] == "got user: user-123")
    assert(log[3] == "got profile: Alice")
    assert(log[4] == "got 3 posts")
    assert(log[5] == "saved")
    assert(log[6] == "done")
  end, 200)
end)

val.global("setTimeout"):call(nil, function ()
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
end, 500)
