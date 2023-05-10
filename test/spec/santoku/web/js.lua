-- TODO: high-level javascript DSL

local assert = require("luassert")
local test = require("santoku.test")
local js = require("santoku.web.js")

test("js", function ()

  test("global", function ()

    local console = js.console
    local log = console.log

    assert.equals(type(log), "function")

  end)

end)

-- val = require("santoku.web.val")
-- js = require("santoku.web.js")
-- js[x]: val.global(...)

-- console = js.console
-- console.log(1, 2, 3, { 1, 2, 3 }): auto proxied/copied arguments
-- console.log(1, 2, 3, val({ 1, 2, 3 }, js.Array)): specify prototype

-- Map = js.Map
-- m = Map:new()
-- m:set(1, 2)
-- m:get(1)
