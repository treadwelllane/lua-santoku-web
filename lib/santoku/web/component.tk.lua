local lp = require("santoku.web.lpeg")

local skeleton = [[ <% return readfile("res/web/component.js"), false %> ]]

local function replace(s, old, new)
  local i, j = s:find(old, 1, true)
  if not i then return s end
  return s:sub(1, i - 1) .. (new or "") .. s:sub(j + 1)
end

local function escape_tl(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub("`", "\\`")
  s = s:gsub("${", "\\${")
  return s
end

return function (tag, html, opts)
  local parts = lp.component_parts(html)
  local style = parts.style
  local body = parts.body
  local init = parts.init
  if opts then
    if opts.css then style = opts.css(style) end
    if opts.html then body = opts.html(body) end
    if opts.js then init = opts.js(init) end
  end
  local deps_parts = {}
  for i = 1, #parts.deps do
    deps_parts[i] = "\"" .. parts.deps[i]:gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\""
  end
  local out = skeleton
  out = replace(out, "%TAG%", tag)
  out = replace(out, "%STYLE%", escape_tl(style))
  out = replace(out, "%BODY%", escape_tl(body))
  out = replace(out, "%INIT%", init)
  out = replace(out, "%DEPS%", table.concat(deps_parts, ","))
  if opts and opts.js then out = opts.js(out) end
  return out
end
