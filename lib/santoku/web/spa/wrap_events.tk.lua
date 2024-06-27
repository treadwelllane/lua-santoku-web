local template = require("santoku.template")
local html = <%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/wrap_events.tk.js"))
%> -- luacheck: ignore

return template.compile(html)
