<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
  fs = require("santoku.fs")
  readfile = fs.readfile
%>

local str = require("santoku.string")
return str.from_base64(<% return squote(to_base64(readfile("res/pwa/wrap_events.js"))) %>) -- luacheck: ignore
