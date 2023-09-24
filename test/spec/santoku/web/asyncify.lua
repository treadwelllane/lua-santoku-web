local js = require("santoku.web.js")
local val = require("santoku.web.val")
local test = require("santoku.test")
local assert = require("luassert")

local global = js.global
local Promise = js.Promise

test("asyncify", function ()

<% template:show(os.getenv("ASYNCIFY") == "1") %>

  test("promise setTimeout", function ()
    local p = Promise:new(function (this, resolve)
      global:setTimeout(function ()
        resolve(this, 10)
      end, 100)
    end)
    local ok, res = p:await()
    assert.equals(true, ok)
    assert.equals(10, res)
  end)

<% template:show(os.getenv("ASYNCIFY") ~= "1") %>

<% template:show() %>

end)
