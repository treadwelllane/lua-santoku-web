local js = require("santoku.web.js")
local test = require("santoku.test")
local assert = require("luassert")

local global = js.global
local Promise = js.Promise

 test("errors", function ()

   test("promise rejection", function ()
     local ok, err = Promise:new(function (this, _, reject)
       reject(this, "test")
     end):await()
     assert.equals(false, ok)
     assert.equals("test", err)
   end)

   test("promise lua exception", function ()
     local ok, err = Promise:new(function ()
       error("test")
     end):await()
     assert.equals(false, ok)
     assert.equals("test", err)
   end)

   test("promise js exception", function ()
     local ok, err = Promise:new(function ()
       js.eval(nil, "throw 'test'")
     end):await()
     assert.equals(false, ok)
     assert.equals("test", err)
   end)

   test("promise resolve", function ()
     local ok, res = Promise:resolve(10):await()
     assert.equals(true, ok)
     assert.equals(10, res)
   end)

   test("promise reject", function ()
     local ok, err = Promise:reject("failed"):await()
     assert.equals(false, ok)
     assert.equals("failed", err)
   end)

 end)
