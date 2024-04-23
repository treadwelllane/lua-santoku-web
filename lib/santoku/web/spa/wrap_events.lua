local template = require("santoku.template")
local inherit = require("santoku.inherit")
local defaults = require("santoku.web.spa.defaults")
local html = <%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/wrap_events.js"))
%> -- luacheck: ignore

return template.compile(html)
