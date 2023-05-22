local val = require("santoku.web.val")

return setmetatable({}, {
  __index = function (_, k)
    return val.global(k):lua()
  end
})
