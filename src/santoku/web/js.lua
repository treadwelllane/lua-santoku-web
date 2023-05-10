local val = require("santoku.web.val")
local tup = require("santoku.tuple")

local function wrap (v, parent, prop)
  local t = v:typeof():str()
  if t == "string" then
    return v:str()
  elseif t == "number" then
    return v:num()
  elseif t == "boolean" then
    return v:bool()
  elseif t == "undefined" or t == "null" then
    return nil
  elseif t == "function" then
    return function (...)
      return wrap(parent:call(prop, tup.map(val.from, ...)))
    end
  else
    return setmetatable({}, {
      __index = function (_, k)
        return wrap(v:get(k), v, k)
      end
    })
  end
end

return setmetatable({}, {
  __index = function (_, k)
    return wrap(val.global(k))
  end
})
