-- TODO: low-level binding to emscripten/val.h

local val = require("santoku.web.val")

describe("val", function ()

  describe("global", function () 
    it("should return a javascript global", function ()
      local v = val.global("console")
      assert.equals(v:typeof(), "object")
    end)
  end)

end)

-- val.take_ownership(handle)
-- val.module_property(prop)

-- val.global(ident): find a global val
-- val.object(): create an empty object val
-- val.array(): create an empty array val
-- val.undefined(): create an undefined val
-- val.null(): create a null val

-- val(string): create a val copy of a string
-- val(number): create a val copy of a number
-- val(nil): create a val copy of nil
-- val(bool): create a val copy of a bool
-- val(fn): create a val copy of a fn
-- val(table, prototype?): create a proxy val to the given table

-- v:string(): cast to a string
-- v:number(): cast to a number
-- v:nil(): cast to a nil
-- v:bool(): cast to a boolean
-- v:fn(): cast to a function
-- v:table(): create a table that proxies to the val (object or array)

-- v:as_handle()
-- v:set(key, value)
-- v:get(key)
-- v:typeof()
-- v:await()
-- v:call(prop, ...args)
-- v:new(...args)
