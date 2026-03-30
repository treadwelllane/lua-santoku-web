(function () {
  function _loadScript(src) {
    return new Promise(function (resolve, reject) {
      var el = document.querySelector('script[src="' + src + '"]');
      if (el) {
        if (el.dataset.loaded) return resolve();
        el.addEventListener("load", resolve);
        el.addEventListener("error", reject);
        return;
      }
      var attempts = 0;
      (function tryLoad() {
        var s = document.createElement("script");
        s.src = src;
        s.defer = true;
        s.onload = function () { s.dataset.loaded = "1"; resolve(); };
        s.onerror = function () {
          s.remove();
          if (++attempts < 3) setTimeout(tryLoad, 1000 * attempts);
          else reject(new Error("Failed to load " + src));
        };
        document.head.appendChild(s);
      })();
    });
  }
  var _Ctor = function () {
    var el = Reflect.construct(HTMLElement, [], _Ctor);
    el._shadow = el.attachShadow({ mode: "closed" });
    return el;
  };
  _Ctor.prototype = Object.create(HTMLElement.prototype);
  _Ctor.prototype.constructor = _Ctor;
  _Ctor.prototype.connectedCallback = function () {
    var el = this;
    var root = el._shadow;
    var cp = el.getAttribute("context-path") || "";
    root.innerHTML = `<style>%STYLE%</style>%BODY%`;
    var _deps = [%DEPS%];
    (_deps.length
      ? Promise.all(_deps.map(function (d) { return _loadScript(cp + d); }))
      : Promise.resolve()
    ).then(function () {
%INIT%
    });
  };
  _Ctor.prototype.disconnectedCallback = function () {
    this._shadow.innerHTML = "";
  };
  customElements.define("%TAG%", _Ctor);
})();
