local template = require("santoku.template")
local inherit = require("santoku.inherit")
local defaults = require("santoku.web.spa.defaults")
local html = <%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/spa.html"))
%>

return template.compile(html, nil, nil, inherit.pushindex({ opts = defaults }, _G))
