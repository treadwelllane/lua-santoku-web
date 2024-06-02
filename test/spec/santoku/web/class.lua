local test = require("santoku.test")
local val = require("santoku.web.val")

test("class", function ()

  local Parent = val.class(function (proto)
    proto.fn_parent = function ()
      return "parent"
    end
  end)

  local Child = val.class(function (proto)
    proto.fn_child = function ()
      return "child"
    end
  end, Parent)

  Parent:new():lua()
  Child:new():lua()

end)
