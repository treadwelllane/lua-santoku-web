-- Base cases that could trigger memory leaks

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

test("memory", function ()

  test("object get str", function ()
    local o = val({ a = 1 })
    assert.equals(1, o:get("a"):lua())
  end)

  test("object get num", function ()
    local o = val({ [1] = 1 })
    assert.equals(1, o:get(0):lua())
  end)

  test("object construct", function ()
    local obj = val.global("Object"):call(nil)
    assert.equals("object", obj:typeof():lua())
  end)

end)
