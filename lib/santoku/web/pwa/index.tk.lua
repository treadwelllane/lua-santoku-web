<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
  fs = require("santoku.fs")
  readfile = fs.readfile
%>

local mustache = require("santoku.mustache")
local str = require("santoku.string")
local tbl = require("santoku.table")

local template = str.from_base64(<% return squote(to_base64(readfile("res/pwa/index.mustache"))) %>) -- luacheck: ignore

local init_script_template = [=[
(function() {
  var swPath = '{{sw}}';
  var bundlePath = {{bundle}};
  var bundleLoaded = false;

  function loadBundle() {
    if (bundleLoaded || !bundlePath) return;
    bundleLoaded = true;
    var s = document.createElement('script');
    s.src = bundlePath;
    document.head.appendChild(s);
  }

  function swReady() {
    document.body.classList.add('sw-ready');
    document.body.dispatchEvent(new CustomEvent('sw-ready'));
  }

  function onReady() {
    loadBundle();
    swReady();
  }

  if (!('serviceWorker' in navigator)) {
    loadBundle();
    return;
  }

  if (navigator.serviceWorker.controller) {
    onReady();
    return;
  }

  navigator.serviceWorker.register(swPath)
    .then(function(reg) {
      window.swRegistration = reg;

      reg.addEventListener('updatefound', function() {
        var newWorker = reg.installing;
        newWorker.addEventListener('statechange', function() {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
            document.body.classList.add('sw-update-available');
          }
        });
      });

      if (navigator.serviceWorker.controller) {
        onReady();
        return;
      }

      navigator.serviceWorker.addEventListener('controllerchange', function() {
        onReady();
      }, { once: true });

      setTimeout(loadBundle, 5000);
    })
    .catch(function(err) {
      console.warn('SW registration failed:', err);
      loadBundle();
    });
})();
]=]

local defaults = {
  charset = "utf-8",
  lang = "en",
  manifest = "/manifest.json",
  theme_color = "#000000",
}

return function(opts)
  opts = tbl.merge({}, defaults, opts or {})
  if opts.sw then
    local bundle = opts.sw_post and ("'" .. opts.sw_post .. "'") or "null"
    local script = init_script_template:gsub("{{sw}}", opts.sw):gsub("{{bundle}}", bundle)
    opts.sw_script = "<script defer>" .. script .. "</script>"
  end
  return mustache(template, opts)
end
