local template = require("santoku.template")
local wrap_events = (<%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/wrap_events.tk.js"), true)
%>) -- luacheck: ignore
local tbl = require("santoku.table")
local def = require("santoku.web.spa.defaults")
local tpl = template.compile(wrap_events)
return function (opts)
  local opts = tbl.merge({}, opts or {}, def.wrap_events)
  return tpl({ opts = opts }, _G)
end
