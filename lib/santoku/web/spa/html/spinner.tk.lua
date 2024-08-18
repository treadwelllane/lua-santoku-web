local html = <%
  local serialize = require("santoku.serialize")
  return serialize(renderfile("res/spinner.tk.svg"))
%> -- luacheck: ignore

return html
