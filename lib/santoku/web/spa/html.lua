local template = require("santoku.template")
local defaults = require("santoku.web.spa.defaults")
local html = <%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/spa.html"))
%> -- luacheck: ignore

return template.compile(html)
