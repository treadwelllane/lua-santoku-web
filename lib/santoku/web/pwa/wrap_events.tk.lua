<% build = dofile("lib/santoku/web/build.lua") %>
return [[ <% return build.minify_js(readfile("res/pwa/wrap_events.js")), false %> ]] -- luacheck: ignore
