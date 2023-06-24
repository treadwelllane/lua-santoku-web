local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

-- TODO
--
-- val(x [, false]): converts lua value 'x' to a
-- javascript value, returning a val userdata.
-- If 'x' is a table, the val userdata returned
-- is a javascript Proxy object which wraps the
-- lua table.
--
-- val(x, true): similar to val(x [, false]),
-- except that if 'x' is a table, the table and
-- its keys and values are traversed and
-- converted to javascript primitives, objects,
-- and arrays by recursively calling this
-- function. Recursion stops whenever a
-- javascript value that is not a lua Proxy is
-- encountered.
--
-- x:val([, false]): called on an existing val,
-- promise, object, etc., returning it as a val.
--
-- x:val(true): called on an existing val. If
-- the val is a proxy to a lua table, behaves
-- like val(x, true), otherwise returns the val
-- as-is.
--
-- x:lua([, false]): converts a javascript value
-- to a lua value, and either returns the lua
-- primitive or a proxy-table that wraps the
-- underlying javascript object.
--
-- x:lua(true): similar to x:lua([, false]),
-- except that if the javascript value is an
-- object, the object and its keys and values
-- are traversed and converted to lua primitives
-- and tables by recursively calling this
-- function. Recursion stops whenever a lua
-- value that is not a javascript proxy is
-- encountered.

test("js", function ()

  -- test("convert lua to js recursively", function ()
  --   local t = { 1, { 2, 3 }, 4 }
  --   local j = val(t, true)
  --   print(j:typeof())
  --   -- TODO
  -- end)

  -- test("convert js to lua recursively", function ()
  --   local j = val.object()
  --   j:set("a", 1)
  --   j:set("b", 2)
  --   local t = j:lua(true)
  --   print(t)
  --   -- TODO
  -- end)

end)
