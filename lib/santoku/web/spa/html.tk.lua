local template = require("santoku.template")
return template.compile(<%
  local serialize = require("santoku.serialize")
  return serialize(readfile("res/spa.tk.html"))
%>)  -- luacheck: ignore
