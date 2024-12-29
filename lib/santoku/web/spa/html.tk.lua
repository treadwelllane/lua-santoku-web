local template = require("santoku.template")
-- luacheck: push ignore
local spa = [[ <% return readfile("res/spa.tk.html"), false %> ]]
-- luacheck: pop
local tbl = require("santoku.table")
local def = require("santoku.web.spa.defaults")
local tpl = template.compile(spa)
return function (opts)
  local opts = tbl.merge({}, opts or {}, def.spa or {}, _G)
  return tpl({ opts = opts }, _G)
end
