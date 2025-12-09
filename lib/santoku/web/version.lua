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

return M
