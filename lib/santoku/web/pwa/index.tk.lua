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
  function swError() {
    if (document.body) {
      document.body.classList.add('sw-error');
      document.body.dispatchEvent(new CustomEvent('sw-error'));
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
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', swError);
    } else {
      swError();
    }
    return;
  }
  if (navigator.serviceWorker.controller) {
    onReady();
    navigator.serviceWorker.ready.then(function(reg) {
      window.swRegistration = reg;
      navigator.serviceWorker.addEventListener('message', function(event) {
        if (event.data && event.data.type === 'version_mismatch' && document.body) {
          document.body.classList.add('sw-update');
          document.body.classList.add('sw-blocking');
        }
      });
    });
    navigator.serviceWorker.addEventListener('controllerchange', function() {
      window.location.reload();
    });
    return;
  }
  navigator.serviceWorker.register(swPath).then(function(reg) {
    window.swRegistration = reg;
    signalPageReady(reg.installing || reg.waiting);
    reg.addEventListener('updatefound', function() {
      var newWorker = reg.installing;
      newWorker.addEventListener('statechange', function() {
        if (newWorker.state === 'installed' && navigator.serviceWorker.controller && document.body) {
          document.body.classList.add('sw-update');
        }
      });
    });
    if (navigator.serviceWorker.controller) {
      onReady();
      navigator.serviceWorker.addEventListener('controllerchange', function() {
        window.location.reload();
      });
      return;
    }
    navigator.serviceWorker.addEventListener('controllerchange', function() {
      onReady();
    }, { once: true });
    setTimeout(loadBundle, 5000);
  }).catch(function() {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', swError);
    } else {
      swError();
    }
  });
})();
]=]

local inline_script_template = [=[
(function() {
  var bundlePath = '{{bundle}}';
  var bundleLoaded = false;
  function loadBundle() {
    if (bundleLoaded) return;
    bundleLoaded = true;
    var s = document.createElement('script');
    s.src = bundlePath;
    document.head.appendChild(s);
  }
  function swReady() {
    if (document.body) {
      document.body.classList.add('sw-ready');
      document.body.dispatchEvent(new CustomEvent('sw-ready'));
    }
  }
  function swError() {
    if (document.body) {
      document.body.classList.add('sw-error');
      document.body.dispatchEvent(new CustomEvent('sw-error'));
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
  if (navigator.serviceWorker && navigator.serviceWorker.controller) {
    onReady();
  } else if (navigator.serviceWorker) {
    var timeout = setTimeout(function() {
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', swError);
      } else {
        swError();
      }
    }, 10000);
    navigator.serviceWorker.addEventListener('controllerchange', function() {
      clearTimeout(timeout);
      onReady();
    }, { once: true });
  } else {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', swError);
    } else {
      swError();
    }
  }
  if (navigator.serviceWorker) {
    navigator.serviceWorker.ready.then(function(reg) {
      window.swRegistration = reg;
      navigator.serviceWorker.addEventListener('message', function(event) {
        if (event.data && event.data.type === 'version_mismatch' && document.body) {
          document.body.classList.add('sw-update');
          document.body.classList.add('sw-blocking');
        }
      });
      reg.addEventListener('updatefound', function() {
        var newWorker = reg.installing;
        newWorker.addEventListener('statechange', function() {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller && document.body) {
            document.body.classList.add('sw-update');
          }
        });
      });
      navigator.serviceWorker.addEventListener('controllerchange', function() {
        window.location.reload();
      });
    });
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
    local bundle = opts.bundle and ("'" .. opts.bundle .. "'") or "null"
    local script = init_script_template:gsub("{{sw}}", opts.sw):gsub("{{bundle}}", bundle)
    opts.sw_script = "<script defer>" .. script .. "</script>"
  elseif opts.sw_inline and opts.bundle then
    local script = inline_script_template:gsub("{{bundle}}", opts.bundle)
    opts.sw_script = "<script defer>" .. script .. "</script>"
  end
  return mustache(template)(opts)
end
