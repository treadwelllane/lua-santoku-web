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
  var swReadyFired = false;

  function loadBundle() {
    if (bundleLoaded || !bundlePath) return;
    bundleLoaded = true;
    var s = document.createElement('script');
    s.src = bundlePath;
    document.head.appendChild(s);
  }

  function swReady() {
    if (swReadyFired) return;
    swReadyFired = true;
    if (document.body) {
      document.body.classList.add('sw-ready');
      document.body.dispatchEvent(new CustomEvent('sw-ready'));
    }
  }

  function onReady() {
    loadBundle();
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', swReady);
    } else {
      swReady();
    }
  }

  // Signal the SW that page resources are loaded so it can pre-cache from HTTP cache
  function signalPageReady(worker) {
    if (!worker) return;
    function doSignal() {
      worker.postMessage({ type: 'page_resources_loaded' });
    }
    if (document.readyState === 'complete') {
      doSignal();
    } else {
      window.addEventListener('load', doSignal, { once: true });
    }
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

      // Signal the installing worker when page resources are ready
      signalPageReady(reg.installing || reg.waiting);

      reg.addEventListener('updatefound', function() {
        var newWorker = reg.installing;
        newWorker.addEventListener('statechange', function() {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller && document.body) {
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

-- Script for sw_inline mode (HTML served by SW, no registration needed)
local inline_script_template = [=[
(function() {
  var bundlePath = '{{bundle}}';

  // Load the bundle
  var s = document.createElement('script');
  s.src = bundlePath;
  document.head.appendChild(s);

  // Dispatch sw-ready event
  function swReady() {
    if (document.body) {
      document.body.classList.add('sw-ready');
      document.body.dispatchEvent(new CustomEvent('sw-ready'));
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', swReady);
  } else {
    swReady();
  }

  // Signal page resources loaded to SW for pre-cache coordination
  function signalPageReady() {
    if (navigator.serviceWorker && navigator.serviceWorker.controller) {
      navigator.serviceWorker.controller.postMessage({ type: 'page_resources_loaded' });
    }
  }

  if (document.readyState === 'complete') {
    signalPageReady();
  } else {
    window.addEventListener('load', signalPageReady, { once: true });
  }
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
    -- Traditional mode: register SW, load bundle after ready
    local bundle = opts.bundle and ("'" .. opts.bundle .. "'") or "null"
    local script = init_script_template:gsub("{{sw}}", opts.sw):gsub("{{bundle}}", bundle)
    opts.sw_script = "<script defer>" .. script .. "</script>"
  elseif opts.sw_inline and opts.bundle then
    -- Inline mode: HTML served by SW, just load bundle
    local script = inline_script_template:gsub("{{bundle}}", opts.bundle)
    opts.sw_script = "<script defer>" .. script .. "</script>"
  end
  return mustache(template)(opts)
end
