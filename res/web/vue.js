(function () {

  var tracking = null;
  var trackingStack = [];
  var batchDepth = 0;
  var pendingEffects = new Set();
  var flushing = false;
  var tickCallbacks = [];

  function flushEffects () {
    if (flushing) return;
    flushing = true;
    queueMicrotask(function () {
      var effects = Array.from(pendingEffects);
      pendingEffects.clear();
      flushing = false;
      for (var i = 0; i < effects.length; i++) {
        effects[i]();
      }
      var cbs = tickCallbacks.splice(0);
      for (var j = 0; j < cbs.length; j++) {
        cbs[j]();
      }
    });
  }

  globalThis.__tkVueNextTick = function (fn) {
    tickCallbacks.push(fn);
    flushEffects();
  };

  var proxyMap = new WeakMap();

  globalThis.__tkVueReactive = function (obj, onChange) {
    if (typeof obj !== "object" || obj === null) return obj;
    var existing = proxyMap.get(obj);
    if (existing) return existing;
    var deps = {};
    function getDep (key) {
      if (!deps[key]) deps[key] = new Set();
      return deps[key];
    }
    var boundFns = {};
    var boundSrc = {};
    var proxy = new Proxy(obj, {
      get: function (target, key, receiver) {
        if (key === "__tkVueRaw") return target;
        if (key === "__tkVueIsReactive") return true;
        if (tracking) getDep(key).add(tracking);
        var v = Reflect.get(target, key, receiver);
        if (typeof v === "function") {
          if (boundSrc[key] !== v) {
            boundSrc[key] = v;
            boundFns[key] = v.bind(proxy);
          }
          return boundFns[key];
        }
        if (typeof v === "object" && v !== null && !v.__tkVueIsReactive) {
          var child = globalThis.__tkVueReactive(v, onChange);
          Reflect.set(target, key, child);
          return child;
        }
        return v;
      },
      set: function (target, key, value, receiver) {
        var old = Reflect.get(target, key, receiver);
        if (typeof value === "object" && value !== null && !value.__tkVueIsReactive) {
          value = globalThis.__tkVueReactive(value, onChange);
        }
        var result = Reflect.set(target, key, value, receiver);
        if (old !== value) {
          var subs = getDep(key);
          subs.forEach(function (fn) { pendingEffects.add(fn); });
          if (onChange) pendingEffects.add(onChange);
          flushEffects();
        }
        return result;
      },
      deleteProperty: function (target, key) {
        var result = Reflect.deleteProperty(target, key);
        var subs = getDep(key);
        subs.forEach(function (fn) { pendingEffects.add(fn); });
        if (onChange) pendingEffects.add(onChange);
        flushEffects();
        return result;
      }
    });
    proxyMap.set(obj, proxy);
    proxyMap.set(proxy, proxy);
    return proxy;
  };

  var evalCache = {};
  function vueEval (expr, scope, el, event) {
    try {
      var fn = evalCache[expr];
      if (!fn) {
        fn = new Function("$data", "$el", "$event", "$dispatch", "$nextTick",
          "with($data){return(" + expr + ")}");
        evalCache[expr] = fn;
      }
      return fn.call(scope, scope, el, event,
        function (name, detail) {
          el.dispatchEvent(new CustomEvent(name, { detail: detail, bubbles: true, composed: true }));
        },
        globalThis.__tkVueNextTick);
    } catch (e) {
      return undefined;
    }
  }

  var execCache = {};
  function vueExec (stmts, scope, el, event) {
    try {
      var fn = execCache[stmts];
      if (!fn) {
        fn = new Function("$data", "$el", "$event", "$dispatch", "$nextTick",
          "with($data){" + stmts + "}");
        execCache[stmts] = fn;
      }
      fn.call(scope, scope, el, event,
        function (name, detail) {
          el.dispatchEvent(new CustomEvent(name, { detail: detail, bubbles: true, composed: true }));
        },
        globalThis.__tkVueNextTick);
    } catch (e) {}
  }

  function createEffect (fn) {
    var dead = false;
    var effectFn = function () {
      if (dead) return;
      trackingStack.push(tracking);
      tracking = effectFn;
      fn();
      tracking = trackingStack.length > 0 ? trackingStack.pop() : null;
    };
    effectFn();
    return function () { dead = true; };
  }

  function addCleanup (node, fn) {
    if (!node.__tkVueCleanups) node.__tkVueCleanups = [];
    node.__tkVueCleanups.push(fn);
  }

  function createScopedEffect (el, fn) {
    addCleanup(el, createEffect(fn));
  }

  function runCleanups (node) {
    var fns = node.__tkVueCleanups;
    if (fns) {
      for (var i = 0; i < fns.length; i++) fns[i]();
      delete node.__tkVueCleanups;
    }
  }

  function runCleanupsDeep (node) {
    runCleanups(node);
    if (node.childNodes) {
      var children = Array.from(node.childNodes);
      for (var i = 0; i < children.length; i++) runCleanupsDeep(children[i]);
    }
  }

  function removeBetween (startMarker, endMarker) {
    var node = startMarker.nextSibling;
    var removed = [];
    while (node && node !== endMarker) {
      var next = node.nextSibling;
      removed.push(node);
      node.parentNode.removeChild(node);
      node = next;
    }
    return removed;
  }

  function parseModifiers (str) {
    var parts = str.split(".");
    var result = { name: parts[0], modifiers: {} };
    for (var i = 1; i < parts.length; i++) {
      var m = parts[i];
      if (m === "debounce" || m === "throttle") {
        result.modifiers[m] = true;
        var nextVal = parts[i + 1];
        if (nextVal && /^\d+ms$/.test(nextVal)) {
          result.modifiers[m + "Ms"] = parseInt(nextVal);
          i++;
        }
      } else {
        result.modifiers[m] = true;
      }
    }
    return result;
  }

  function addEventHandler (el, event, handler, modifiers) {
    var target = el;
    var opts = {};
    if (modifiers) {
      if (modifiers.window) target = window;
      else if (modifiers.document) target = document;
      if (modifiers.capture) opts.capture = true;
      if (modifiers.once) opts.once = true;
      if (modifiers.passive) opts.passive = true;
    }
    var fn = handler;
    if (modifiers) {
      if (modifiers.stop) {
        var prev = fn;
        fn = function (e) { e.stopPropagation(); return prev(e); };
      }
      if (modifiers.prevent) {
        var prev2 = fn;
        fn = function (e) { e.preventDefault(); return prev2(e); };
      }
      if (modifiers.self) {
        var prev3 = fn;
        fn = function (e) { if (e.target === el) return prev3(e); };
      }
      if (modifiers.outside) {
        var prev4 = fn;
        fn = function (e) { if (!el.contains(e.target) && el !== e.target) return prev4(e); };
        target = document;
      }
      if (modifiers.debounce) {
        var prev5 = fn;
        var dTimer;
        var dMs = modifiers.debounceMs || 300;
        fn = function (e) {
          clearTimeout(dTimer);
          dTimer = setTimeout(function () { prev5(e); }, dMs);
        };
      }
      if (modifiers.throttle) {
        var prev6 = fn;
        var tLast = 0;
        var tMs = modifiers.throttleMs || 300;
        fn = function (e) {
          var now = Date.now();
          if (now - tLast >= tMs) {
            tLast = now;
            prev6(e);
          }
        };
      }
    }
    target.addEventListener(event, fn, opts);
    return function () { target.removeEventListener(event, fn, opts); };
  }

  function getValue (el) {
    if (el.type === "checkbox") return el.checked;
    if (el.type === "radio") return el.checked ? el.value : undefined;
    if (el.tagName === "SELECT" && el.multiple) {
      var vals = [];
      for (var i = 0; i < el.options.length; i++) {
        if (el.options[i].selected) vals.push(el.options[i].value);
      }
      return vals;
    }
    return el.value;
  }

  function setValue (el, v) {
    if (el.type === "checkbox") {
      el.checked = !!v;
    } else if (el.type === "radio") {
      el.checked = (el.value === String(v));
    } else if (el.tagName === "SELECT") {
      if (el.multiple && Array.isArray(v)) {
        for (var i = 0; i < el.options.length; i++) {
          el.options[i].selected = v.indexOf(el.options[i].value) !== -1;
        }
      } else {
        el.value = v == null ? "" : v;
      }
    } else {
      if (el.value !== String(v == null ? "" : v))
        el.value = v == null ? "" : v;
    }
  }

  function parseForExpr (expr) {
    var m = expr.match(/^\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)\s+in\s+(.+)\s*$/);
    if (m) return { item: m[1], index: m[2], list: m[3] };
    m = expr.match(/^\s*(\w+)\s+in\s+(.+)\s*$/);
    if (m) return { item: m[1], index: null, list: m[2] };
    return null;
  }

  function applyClassObj (el, obj) {
    var ks = Object.keys(obj);
    for (var i = 0; i < ks.length; i++) {
      var parts = ks[i].split(/\s+/).filter(Boolean);
      if (obj[ks[i]]) el.classList.add.apply(el.classList, parts);
      else el.classList.remove.apply(el.classList, parts);
    }
  }

  function setAttr (el, name, value) {
    if (value === false || value == null) el.removeAttribute(name);
    else if (value === true) el.setAttribute(name, "");
    else el.setAttribute(name, value);
  }

  var walkTree, walkChildren, processIfChain, processFor, processDirectives;

  walkChildren = function (el, scope, ctx) {
    var children = Array.from(el.children);
    var skipSet = new Set();
    for (var i = 0; i < children.length; i++) {
      var child = children[i];
      if (skipSet.has(child)) continue;
      if (child.nodeType === 1 && child.hasAttribute("v-if")) {
        var sib = child.nextElementSibling;
        while (sib) {
          if (sib.hasAttribute("v-else-if") || sib.hasAttribute("v-else")) {
            skipSet.add(sib);
            sib = sib.nextElementSibling;
          } else {
            break;
          }
        }
      }
      walkTree(child, scope, ctx);
    }
  };

  walkTree = function (el, scope, ctx) {
    if (el.nodeType !== 1) return;
    if (el.hasAttribute("v-pre")) return;
    if (el.hasAttribute("v-cloak")) el.removeAttribute("v-cloak");

    if (el.hasAttribute("v-scope")) {
      var vscopeExpr = el.getAttribute("v-scope");
      el.removeAttribute("v-scope");
      if (vscopeExpr && vscopeExpr !== "") {
        var result = vueEval(vscopeExpr, scope, el);
        if (result) {
          var childScope = Object.create(scope);
          Object.assign(childScope, result);
          scope = globalThis.__tkVueReactive(childScope);
        }
      }
    }

    if (el.hasAttribute("v-if")) {
      processIfChain(el, scope, ctx);
      return;
    }

    if (el.hasAttribute("v-for")) {
      processFor(el, scope, ctx);
      return;
    }

    processDirectives(el, scope, ctx);
    walkChildren(el, scope, ctx);
  };

  processIfChain = function (el, scope, ctx) {
    var branches = [];
    var current = el;
    while (current) {
      if (current.hasAttribute("v-if") && branches.length === 0) {
        branches.push({ el: current, expr: current.getAttribute("v-if"), type: "if" });
        current.removeAttribute("v-if");
        current = current.nextElementSibling;
      } else if (current.hasAttribute("v-else-if") && branches.length > 0) {
        branches.push({ el: current, expr: current.getAttribute("v-else-if"), type: "else-if" });
        current.removeAttribute("v-else-if");
        var next = current.nextElementSibling;
        current.parentNode.removeChild(current);
        current = next;
      } else if (current.hasAttribute("v-else") && branches.length > 0) {
        branches.push({ el: current, type: "else" });
        current.removeAttribute("v-else");
        var next2 = current.nextElementSibling;
        current.parentNode.removeChild(current);
        current = next2;
      } else {
        break;
      }
    }

    var anchorStart = document.createComment("v-if");
    var anchorEnd = document.createComment("/v-if");
    var parent = branches[0].el.parentNode;
    parent.insertBefore(anchorStart, branches[0].el);
    parent.insertBefore(anchorEnd, branches[0].el);
    parent.removeChild(branches[0].el);

    createScopedEffect(anchorStart, function () {
      var removed = removeBetween(anchorStart, anchorEnd);
      for (var i = 0; i < removed.length; i++) runCleanupsDeep(removed[i]);

      var matched = null;
      for (var j = 0; j < branches.length; j++) {
        if (branches[j].type === "else") { matched = branches[j]; break; }
        if (vueEval(branches[j].expr, scope, anchorStart)) { matched = branches[j]; break; }
      }

      if (matched) {
        var tag = matched.el.tagName ? matched.el.tagName.toLowerCase() : "";
        if (tag === "template") {
          var content = matched.el.content;
          if (content) {
            var clone = content.cloneNode(true);
            var nodes = Array.from(clone.childNodes);
            for (var k = 0; k < nodes.length; k++) {
              parent.insertBefore(nodes[k], anchorEnd);
              walkTree(nodes[k], scope, ctx);
            }
          }
        } else {
          var clone2 = matched.el.cloneNode(true);
          parent.insertBefore(clone2, anchorEnd);
          walkTree(clone2, scope, ctx);
        }
      }
    });
  };

  processFor = function (el, scope, ctx) {
    var expr = el.getAttribute("v-for");
    el.removeAttribute("v-for");
    if (el.hasAttribute(":key")) el.removeAttribute(":key");

    var parsed = parseForExpr(expr);
    if (!parsed) return;

    var anchorStart = document.createComment("v-for");
    var anchorEnd = document.createComment("/v-for");
    var parent = el.parentNode;
    parent.insertBefore(anchorStart, el);
    parent.insertBefore(anchorEnd, el);
    parent.removeChild(el);

    var tag = el.tagName ? el.tagName.toLowerCase() : "";
    var isTemplate = (tag === "template");

    createScopedEffect(anchorStart, function () {
      var removed = removeBetween(anchorStart, anchorEnd);
      for (var ri = 0; ri < removed.length; ri++) runCleanupsDeep(removed[ri]);

      var list = vueEval(parsed.list, scope, anchorStart);
      if (!list) return;

      var isArr = Array.isArray(list);
      var keys = isArr ? null : Object.keys(list);
      var length = isArr ? list.length : (keys ? keys.length : 0);

      for (var i = 0; i < length; i++) {
        var itemVal, idxVal;
        if (isArr) {
          itemVal = list[i];
          idxVal = i;
        } else {
          itemVal = list[keys[i]];
          idxVal = keys[i];
        }

        var childScope = Object.create(scope);
        childScope[parsed.item] = itemVal;
        if (parsed.index) childScope[parsed.index] = idxVal;
        var reactiveScope = globalThis.__tkVueReactive(childScope);

        if (isTemplate) {
          var content = el.content;
          if (content) {
            var clone = content.cloneNode(true);
            var nodes = Array.from(clone.childNodes);
            for (var ni = 0; ni < nodes.length; ni++) {
              parent.insertBefore(nodes[ni], anchorEnd);
              walkTree(nodes[ni], reactiveScope, ctx);
            }
          }
        } else {
          var clone2 = el.cloneNode(true);
          parent.insertBefore(clone2, anchorEnd);
          walkTree(clone2, reactiveScope, ctx);
        }
      }
    });
  };

  processDirectives = function (el, scope, ctx) {
    var attrs = el.attributes;
    var toProcess = [];
    for (var i = 0; i < attrs.length; i++) {
      toProcess.push({ name: attrs[i].name, value: attrs[i].value });
    }

    toProcess.forEach(function (attr) {
      var name = attr.name;
      var value = attr.value;

      if (name === "v-text") {
        el.removeAttribute(name);
        createScopedEffect(el, function () {
          var result = vueEval(value, scope, el);
          el.textContent = result == null ? "" : result;
        });

      } else if (name === "v-html") {
        el.removeAttribute(name);
        createScopedEffect(el, function () {
          var result = vueEval(value, scope, el);
          el.innerHTML = result == null ? "" : result;
        });

      } else if (name === "v-show") {
        el.removeAttribute(name);
        createScopedEffect(el, function () {
          el.style.display = vueEval(value, scope, el) ? "" : "none";
        });

      } else if (name === "v-model") {
        el.removeAttribute(name);
        createScopedEffect(el, function () {
          setValue(el, vueEval(value, scope, el));
        });
        var tag = el.tagName ? el.tagName.toLowerCase() : "";
        var evt = "input";
        if (tag === "select" || el.getAttribute("type") === "checkbox" || el.getAttribute("type") === "radio") {
          evt = "change";
        }
        addCleanup(el, addEventHandler(el, evt, function () {
          new Function("$data", "$el", "__val", "with($data){" + value + " = __val}")(scope, el, getValue(el));
        }));

      } else if (name === "v-effect") {
        el.removeAttribute(name);
        createScopedEffect(el, function () {
          vueExec(value, scope, el);
        });

      } else if (name.indexOf("v-bind:") === 0 || name.charAt(0) === ":") {
        el.removeAttribute(name);
        var attrName = name.charAt(0) === ":" ? name.slice(1) : name.slice(7);

        if (attrName === "class") {
          createScopedEffect(el, function () {
            var result = vueEval(value, scope, el);
            if (result !== null && typeof result === "object" && !Array.isArray(result)) {
              applyClassObj(el, result);
            } else if (Array.isArray(result)) {
              for (var ai = 0; ai < result.length; ai++) {
                if (result[ai] !== null && typeof result[ai] === "object") applyClassObj(el, result[ai]);
              }
            } else if (typeof result === "string") {
              el.setAttribute("class", result);
            }
          });
        } else if (attrName === "style") {
          createScopedEffect(el, function () {
            var result = vueEval(value, scope, el);
            if (result !== null && typeof result === "object" && !Array.isArray(result)) {
              var ks = Object.keys(result);
              for (var si = 0; si < ks.length; si++) el.style[ks[si]] = result[ks[si]] || "";
            } else if (typeof result === "string") {
              el.setAttribute("style", result);
            }
          });
        } else {
          createScopedEffect(el, function () {
            setAttr(el, attrName, vueEval(value, scope, el));
          });
        }

      } else if (name.indexOf("v-on:") === 0 || name.charAt(0) === "@") {
        el.removeAttribute(name);
        var eventSpec = name.charAt(0) === "@" ? name.slice(1) : name.slice(5);

        if (eventSpec === "vue:mounted") {
          vueExec(value, scope, el);
        } else if (eventSpec === "vue:unmounted") {
          addCleanup(el, function () { vueExec(value, scope, el); });
        } else {
          var pm = parseModifiers(eventSpec);
          addCleanup(el, addEventHandler(el, pm.name, function (ev) {
            vueExec(value, scope, el, ev);
          }, pm.modifiers));
        }

      } else if (name.indexOf("v-") === 0) {
        var dirMatch = name.match(/^v-([^:]+)/);
        var argMatch = name.match(/^v-[^:]+:(.+)/);
        var dirName = dirMatch ? dirMatch[1] : null;
        var dirArg = argMatch ? argMatch[1] : null;
        if (dirName && ctx.customDirHandler) {
          el.removeAttribute(name);
          ctx.customDirHandler(dirName, el, dirArg || false, value, scope,
            function (fn) { createScopedEffect(el, fn); },
            function () { return vueEval(value, scope, el); });
        }
      }
    });
  };

  globalThis.__tkVueMount = function (rootArg, scopeObj, customDirHandler) {
    var root;
    var hasSel = true;
    if (rootArg === false || rootArg == null) {
      root = document.body;
      hasSel = false;
    } else if (typeof rootArg === "string") {
      root = document.querySelector(rootArg);
    } else {
      root = rootArg;
    }
    if (!root) return;

    if (!scopeObj || scopeObj === false) scopeObj = {};
    var rootScope = globalThis.__tkVueReactive(scopeObj);

    var ctx = {
      customDirHandler: (customDirHandler && customDirHandler !== false) ? customDirHandler : null
    };

    batchDepth++;

    if (hasSel || (root.hasAttribute && root.hasAttribute("v-scope"))) {
      walkTree(root, rootScope, ctx);
    } else {
      var children = Array.from(root.children);
      for (var i = 0; i < children.length; i++) {
        walkTree(children[i], rootScope, ctx);
      }
    }

    batchDepth--;
    if (batchDepth <= 0) {
      batchDepth = 0;
      flushEffects();
    }
  };

})();
