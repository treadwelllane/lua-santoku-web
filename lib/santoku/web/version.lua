local M = {}

local is_nginx = type(ngx) == "table" -- luacheck: ignore

local client_version = nil

function M.check(expected_version)
  if not is_nginx then return end
  local cv = ngx.var.http_x_client_version
  if cv and cv ~= expected_version then
    ngx.header["X-App-Version"] = expected_version
    ngx.status = 409
    ngx.say("Version mismatch")
    return ngx.exit(409)
  end
  ngx.header["X-App-Version"] = expected_version
end

function M.set(version)
  client_version = version
end

function M.get()
  return client_version
end

function M.attach(headers)
  if is_nginx or not client_version then return headers end
  headers = headers or {}
  headers["X-Client-Version"] = client_version
  return headers
end

function M.install_hooks (http, version, on_mismatch)
  local js = require("santoku.web.js")
  local val = require("santoku.web.val")
  local str = require("santoku.string")
  local origin = js.self and js.self.location and js.self.location.origin
  local mismatched = false
  local function is_same_origin (url)
    if type(url) == "string" then
      return str.startswith(url, "/") or (origin and str.startswith(url, origin))
    elseif url and url.url then
      return origin and str.startswith(url.url, origin)
    end
    return false
  end
  http.on("request", function (k, url, req_opts)
    if not is_same_origin(url) then return k(url, req_opts) end
    if type(url) == "string" then
      req_opts = req_opts or {}
      req_opts.headers = req_opts.headers or {}
      req_opts.headers["x-client-version"] = version
    elseif url and url.clone then
      local cloned = url:clone()
      local new_headers = js.Headers:new(cloned.headers)
      new_headers:set("x-client-version", version)
      url = js.Request:new(cloned, val({ headers = new_headers }, true))
    end
    return k(url, req_opts)
  end, true)
  http.on("response", function (k, ok, resp)
    if not mismatched and resp and resp.headers then
      local server_version = resp.headers["x-app-version"]
      if server_version and server_version ~= version then
        mismatched = true
        on_mismatch()
      end
    end
    return k(ok, resp)
  end, true)
end

return M
