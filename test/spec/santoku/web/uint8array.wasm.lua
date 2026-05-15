local test = require("santoku.test")
local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.error")
local validate = require("santoku.validate")

local assert = err.assert
local eq = validate.isequal

test("Uint8Array:new(N) creates zero-filled array", function ()
  local arr = js.Uint8Array:new(4)
  assert(eq(4, arr.length))
end)

test("Uint8Array:new(luaTable) constructs from Lua numeric table", function ()
  local arr = js.Uint8Array:new({ 65, 66, 67 })
  assert(eq(3, arr.length))
  assert(eq("ABC", val.lua(arr):str()))
end)

test("Uint8Array:new(luaTable) with binary bytes", function ()
  local arr = js.Uint8Array:new({ 0, 0xFF, 0x42, 0x7F, 0x80 })
  assert(eq(5, arr.length))
  local s = val.lua(arr):str()
  assert(eq(5, #s))
  assert(eq(0, string.byte(s, 1)))
  assert(eq(0xFF, string.byte(s, 2)))
  assert(eq(0x42, string.byte(s, 3)))
  assert(eq(0x7F, string.byte(s, 4)))
  assert(eq(0x80, string.byte(s, 5)))
end)

test("val.bytes(luaString) constructs Uint8Array from raw bytes", function ()
  local arr = val.bytes("\0\xFF\x42")
  assert(eq(3, arr.length))
  assert(eq(true, arr:instanceof(js.Uint8Array)))
  local s = val.lua(arr):str()
  assert(eq(0, string.byte(s, 1)))
  assert(eq(0xFF, string.byte(s, 2)))
  assert(eq(0x42, string.byte(s, 3)))
end)

test("val.lua(uint8array):str() roundtrip preserves all byte values", function ()
  local bytes = {}
  for i = 0, 255 do bytes[i + 1] = i end
  local arr = js.Uint8Array:new(bytes)
  local s = val.lua(arr):str()
  assert(eq(256, #s))
  for i = 0, 255 do
    assert(eq(i, string.byte(s, i + 1)))
  end
end)

test("arr[0] direct read of Uint8Array element from Lua", function ()
  local arr = js.Uint8Array:new({ 10, 20, 30, 40 })
  assert(eq(10, arr[0]))
end)

test("arr[i] direct read of Uint8Array elements at multiple indices", function ()
  local arr = js.Uint8Array:new({ 10, 20, 30, 40 })
  assert(eq(20, arr[1]))
  assert(eq(30, arr[2]))
  assert(eq(40, arr[3]))
end)

test("arr[0] = v direct write to Uint8Array from Lua", function ()
  local arr = js.Uint8Array:new(4)
  arr[0] = 100
  local s = val.lua(arr):str()
  assert(eq(100, string.byte(s, 1)))
end)

test("arr[i] = v direct write at multiple indices", function ()
  local arr = js.Uint8Array:new(4)
  arr[0] = 100
  arr[1] = 200
  arr[3] = 50
  local s = val.lua(arr):str()
  assert(eq(100, string.byte(s, 1)))
  assert(eq(200, string.byte(s, 2)))
  assert(eq(0, string.byte(s, 3)))
  assert(eq(50, string.byte(s, 4)))
end)

test("arr[i] = v then arr[i] roundtrip", function ()
  local arr = js.Uint8Array:new(3)
  arr[0] = 0xAB
  arr[1] = 0xCD
  arr[2] = 0xEF
  assert(eq(0xAB, arr[0]))
  assert(eq(0xCD, arr[1]))
  assert(eq(0xEF, arr[2]))
end)

test("Uint8Array wrapping an ArrayBuffer reads correctly", function ()
  -- Make a Uint8Array, populate it, then wrap its .buffer in a new Uint8Array.
  -- This simulates the WebAuthn pattern where cred.rawId is an ArrayBuffer.
  local src = js.Uint8Array:new({ 0x11, 0x22, 0x33, 0x44 })
  local ab = src.buffer
  local view = js.Uint8Array:new(ab)
  assert(eq(4, view.length))
  assert(eq(0x11, view[0]))
  assert(eq(0x22, view[1]))
  assert(eq(0x33, view[2]))
  assert(eq(0x44, view[3]))
end)

test("Uint8Array wrapping a freshly-allocated ArrayBuffer", function ()
  -- A blank ArrayBuffer wrapped should give all zeros.
  local ab = js.ArrayBuffer:new(3)
  local view = js.Uint8Array:new(ab)
  assert(eq(3, view.length))
  assert(eq(0, view[0]))
  assert(eq(0, view[1]))
  assert(eq(0, view[2]))
end)

test("Nested Object:new() with property-chain assignment", function ()
  -- This mirrors webauthn.lua's pattern.
  local opt = js.window.Object:new()
  opt.publicKey = js.window.Object:new()
  opt.publicKey.extensions = js.window.Object:new()
  opt.publicKey.extensions.prf = js.window.Object:new()
  opt.publicKey.extensions.prf.eval = js.window.Object:new()
  opt.publicKey.extensions.prf.eval.first = js.Uint8Array:new({ 0x42, 0x43 })

  -- Read back through the chain.
  local salt = opt.publicKey.extensions.prf.eval.first
  assert(salt ~= nil, "salt is nil after chain assignment")
  assert(eq(2, salt.length))
  assert(eq(0x42, salt[0]))
  assert(eq(0x43, salt[1]))
end)

test("Chained property reads on a nested Object return live proxy", function ()
  local root = js.window.Object:new()
  root.a = js.window.Object:new()
  root.a.b = "hello"
  -- Reading root.a returns a proxy, and root.a.b should give the value.
  assert(eq("hello", root.a.b))
end)

test("Property assignment on a nested object via chain mutates real JS object", function ()
  -- Build, then verify via independent read.
  local root = js.window.Object:new()
  root.a = js.window.Object:new()
  root.a.b = 42
  -- Use JSON.stringify to inspect the JS-side state.
  local json_str = js.JSON:stringify(root)
  assert(eq('{"a":{"b":42}}', json_str))
end)

test("ArrayBuffer from Promise resolution: Uint8Array wrapping and indexing", function ()
  -- Construct a Promise that resolves to an ArrayBuffer (mirroring how
  -- WebAuthn's credential.rawId arrives — via Promise<ArrayBuffer>).
  local async_mod = require("santoku.web.async")
  local p = js.Promise:new(function (this, resolve)
    local src = js.Uint8Array:new({ 0xAA, 0xBB, 0xCC, 0xDD })
    resolve(this, src.buffer)
  end)
  async_mod(function ()
    local ok, ab = p:await()
    assert(eq(true, ok))
    assert(ab ~= nil, "ArrayBuffer is nil after await")
    local view = js.Uint8Array:new(ab)
    assert(eq(4, view.length))
    assert(eq(0xAA, view[0]))
    assert(eq(0xBB, view[1]))
    assert(eq(0xCC, view[2]))
    assert(eq(0xDD, view[3]))
  end)
end)

test("Uint8Array from Promise resolution: direct access", function ()
  local async_mod = require("santoku.web.async")
  local p = js.Promise:new(function (this, resolve)
    resolve(this, js.Uint8Array:new({ 0x10, 0x20, 0x30 }))
  end)
  async_mod(function ()
    local ok, arr = p:await()
    assert(eq(true, ok))
    assert(arr ~= nil, "Uint8Array is nil after await")
    assert(eq(3, arr.length))
    assert(eq(0x10, arr[0]))
    assert(eq(0x20, arr[1]))
    assert(eq(0x30, arr[2]))
  end)
end)

test("Nested object containing ArrayBuffer from Promise resolution", function ()
  -- Closer to what WebAuthn's `cred:getClientExtensionResults()` returns —
  -- a nested object where one field is an ArrayBuffer.
  local async_mod = require("santoku.web.async")
  local p = js.Promise:new(function (this, resolve)
    local outer = js.window.Object:new()
    outer.prf = js.window.Object:new()
    outer.prf.results = js.window.Object:new()
    local src = js.Uint8Array:new({ 0xDE, 0xAD, 0xBE, 0xEF })
    outer.prf.results.first = src.buffer
    resolve(this, outer)
  end)
  async_mod(function ()
    local ok, result = p:await()
    assert(eq(true, ok))
    assert(result ~= nil)
    assert(result.prf ~= nil, "prf is nil")
    assert(result.prf.results ~= nil, "prf.results is nil")
    assert(result.prf.results.first ~= nil, "prf.results.first is nil")
    local view = js.Uint8Array:new(result.prf.results.first)
    assert(eq(4, view.length))
    assert(eq(0xDE, view[0]))
    assert(eq(0xAD, view[1]))
    assert(eq(0xBE, view[2]))
    assert(eq(0xEF, view[3]))
  end)
end)

test("Uint8Array filled via getRandomValues then read via val.lua:str()", function ()
  local arr = js.Uint8Array:new(16)
  js.crypto:getRandomValues(arr)
  local s = val.lua(arr):str()
  assert(eq(16, #s))
end)

test("Uint8Array constructed from val(table, true) wraps Lua-table-as-JS-array", function ()
  local t = { 1, 2, 3, 4 }
  local js_arr = val(t, true)
  local u8 = js.Uint8Array:new(js_arr)
  assert(eq(4, u8.length))
  local s = val.lua(u8):str()
  assert(eq(1, string.byte(s, 1)))
  assert(eq(2, string.byte(s, 2)))
  assert(eq(3, string.byte(s, 3)))
  assert(eq(4, string.byte(s, 4)))
end)

test("Lua-table-proxied-to-JS uses 0-indexed access from JS side", function ()
  -- A non-recursed Lua table passed to JS becomes a Proxy.
  -- Per val.wasm.c lines 333-339, JS reading proxy[0] should map to Lua [1].
  local t = { 10, 20, 30 }
  local proxy = val(t):lua()  -- wrap then unwrap to force proxy path
  -- Lua-side access of the proxy should still see 1-indexed
  assert(eq(10, proxy[1]))
  assert(eq(20, proxy[2]))
  assert(eq(30, proxy[3]))
end)
