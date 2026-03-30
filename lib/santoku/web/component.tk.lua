local lp = require("santoku.web.lpeg")

local skeleton = [[ <% return readfile("res/web/component.js"), false %> ]]

local function replace(s, old, new)
  local i, j = s:find(old, 1, true)
  if not i then return s end
  return s:sub(1, i - 1) .. (new or "") .. s:sub(j + 1)
end

return function (tag, html)
  local parts = lp.component_parts(html)
  local deps_parts = {}
  for i = 1, #parts.deps do
    deps_parts[i] = "\"" .. parts.deps[i]:gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\""
  end
  local out = skeleton
  out = replace(out, "%TAG%", tag)
  out = replace(out, "%STYLE%", parts.style)
  out = replace(out, "%BODY%", parts.body)
  out = replace(out, "%INIT%", parts.init)
  out = replace(out, "%DEPS%", table.concat(deps_parts, ","))
  return out
end
