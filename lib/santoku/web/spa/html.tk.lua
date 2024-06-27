local template = require("santoku.template")
local html = <%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/spa.tk.html"))
%> -- luacheck: ignore

return template.compile(html)
