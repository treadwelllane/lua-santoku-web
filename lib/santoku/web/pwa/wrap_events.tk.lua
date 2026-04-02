<% build = require("santoku.make.build") %>
return [[ <% return build.minify_js(readfile("res/pwa/wrap_events.js")), false %> ]] -- luacheck: ignore
