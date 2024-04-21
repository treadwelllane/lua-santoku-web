local template = require("santoku.template")
local inherit = require("santoku.inherit")
local defaults = require("santoku.web.spa.defaults")
<% serialize = require("santoku.serialize") %>
local html = <% return serialize(readfile("res/wrap_events.js")) %> -- luacheck: ignore

return template.compile(html, nil, nil, inherit.pushindex({ opts = defaults }, _G))
