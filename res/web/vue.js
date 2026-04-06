(function () {

  var tracking = null;
  var trackingStack = [];
  var batchDepth = 0;
  var pendingEffects = new Set();
  var scheduled = false;
  var tickCallbacks = [];

  function scheduleFlush () {
    if (scheduled) return;
    scheduled = true;
    queueMicrotask(function () {
      scheduled = false;
      var limit = 100;
      while (pendingEffects.size > 0 && limit-- > 0) {
        var effects = Array.from(pendingEffects);
        pendingEffects.clear();
        for (var i = 0; i < effects.length; i++) {
          effects[i]();
        }
      }
      var cbs = tickCallbacks.splice(0);
      for (var j = 0; j < cbs.length; j++) {
        cbs[j]();
      }
    });
  }

  globalThis.__tkVueNextTick = function (fn) {
    tickCallbacks.push(fn);
    scheduleFlush();
  };

  var proxyMap = new WeakMap();
  var arrayMethods = { push: 1, pop: 1, shift: 1, unshift: 1, splice: 1, sort: 1, reverse: 1 };

  globalThis.__tkVueReactive = function (obj, onChange) {
    if (typeof obj !== "object" || obj === null) return obj;
    var existing = proxyMap.get(obj);
    if (existing) return existing;
    var deps = {};
    function getDep (key) {
      if (!deps[key]) deps[key] = new Set();
      return deps[key];
    }
    function notifyDeps () {
      var ks = Object.keys(deps);
      for (var i = 0; i < ks.length; i++) {
        deps[ks[i]].forEach(function (fn) { pendingEffects.add(fn); });
      }
      if (onChange) pendingEffects.add(onChange);
      scheduleFlush();
    }
    function notifyRange (from, to) {
      for (var i = from; i <= to; i++) {
        var s = deps[i];
        if (s) s.forEach(function (fn) { pendingEffects.add(fn); });
      }
      var lenDep = deps["length"];
      if (lenDep) lenDep.forEach(function (fn) { pendingEffects.add(fn); });
      if (onChange) pendingEffects.add(onChange);
      scheduleFlush();
    }
    var boundFns = {};
    var boundSrc = {};
    var isArray = Array.isArray(obj);
    var proxy = new Proxy(obj, {
      get: function (target, key, receiver) {
        if (key === "__tkVueRaw") return target;
        if (key === "__tkVueIsReactive") return true;
        if (isArray && arrayMethods[key]) {
          if (boundSrc[key] !== "array") {
            boundSrc[key] = "array";
            boundFns[key] = function () {
              var args = Array.prototype.slice.call(arguments);
              var oldLen = target.length;
              var start = (key === "splice") ? 2 : (key === "push" || key === "unshift") ? 0 : -1;
              if (start >= 0) {
                for (var ai = start; ai < args.length; ai++) {
                  if (typeof args[ai] === "object" && args[ai] !== null && !args[ai].__tkVueIsReactive) {
                    args[ai] = globalThis.__tkVueReactive(args[ai], onChange);
                  }
                }
              }
              var result = Array.prototype[key].apply(target, args);
              var newLen = target.length;
              if (key === "push") {
                notifyRange(oldLen, newLen - 1);
              } else if (key === "pop") {
                notifyRange(oldLen - 1, oldLen - 1);
              } else if (key === "unshift") {
                notifyRange(0, newLen - 1);
              } else if (key === "shift") {
                notifyRange(0, oldLen - 1);
              } else if (key === "splice") {
                var si = (args[0] == null) ? 0 : +args[0];
                var spliceStart = si < 0 ? Math.max(0, oldLen + si) : Math.min(si, oldLen);
                notifyRange(spliceStart, Math.max(oldLen, newLen) - 1);
              } else {
                notifyDeps();
              }
              return result;
            };
          }
          return boundFns[key];
        }
        if (tracking) {
          var dep = getDep(key);
          dep.add(tracking);
          if (tracking._depSets) tracking._depSets.push(dep);
        }
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
          scheduleFlush();
        }
        return result;
      },
      deleteProperty: function (target, key) {
        var result = Reflect.deleteProperty(target, key);
        var subs = getDep(key);
        subs.forEach(function (fn) { pendingEffects.add(fn); });
        if (onChange) pendingEffects.add(onChange);
        scheduleFlush();
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
    var depSets = [];
    var effectFn = function () {
      if (dead) return;
      for (var i = 0; i < depSets.length; i++) {
        depSets[i].delete(effectFn);
      }
      depSets.length = 0;
      trackingStack.push(tracking);
      tracking = effectFn;
      fn();
      tracking = trackingStack.length > 0 ? trackingStack.pop() : null;
    };
    effectFn._depSets = depSets;
    effectFn();
    return function () {
      dead = true;
      for (var i = 0; i < depSets.length; i++) {
        depSets[i].delete(effectFn);
      }
      depSets.length = 0;
    };
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
    if (el.hasAttribute && el.hasAttribute("contenteditable")) return el.textContent;
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
    if (el.hasAttribute && el.hasAttribute("contenteditable")) {
      var str = v == null ? "" : String(v);
      if (el.textContent !== str) el.textContent = str;
      return;
    }
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

    var keyExpr = null;
    if (el.hasAttribute(":key")) {
      keyExpr = el.getAttribute(":key");
      el.removeAttribute(":key");
    }

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

    var keyMap = keyExpr ? new Map() : null;

    if (keyMap) {
      addCleanup(anchorStart, function () {
        keyMap.forEach(function (entry) {
          for (var ni = 0; ni < entry.nodes.length; ni++) {
            runCleanupsDeep(entry.nodes[ni]);
          }
        });
        keyMap.clear();
      });
    }

    function createEntry (itemVal, idxVal) {
      var childScope = Object.create(scope);
      childScope[parsed.item] = itemVal;
      if (parsed.index) childScope[parsed.index] = idxVal;
      var reactiveScope = globalThis.__tkVueReactive(childScope);
      var nodes = [];
      if (isTemplate) {
        var content = el.content;
        if (content) {
          var clone = content.cloneNode(true);
          var cn = Array.from(clone.childNodes);
          for (var ni = 0; ni < cn.length; ni++) nodes.push(cn[ni]);
        }
      } else {
        nodes.push(el.cloneNode(true));
      }
      return { nodes: nodes, scope: reactiveScope };
    }

    createScopedEffect(anchorStart, function () {
      var list = vueEval(parsed.list, scope, anchorStart);

      if (!list) {
        if (keyMap) {
          keyMap.forEach(function (entry) {
            for (var ni = 0; ni < entry.nodes.length; ni++) {
              runCleanupsDeep(entry.nodes[ni]);
              if (entry.nodes[ni].parentNode) entry.nodes[ni].parentNode.removeChild(entry.nodes[ni]);
            }
          });
          keyMap.clear();
        } else {
          var rem = removeBetween(anchorStart, anchorEnd);
          for (var ri = 0; ri < rem.length; ri++) runCleanupsDeep(rem[ri]);
        }
        return;
      }

      var isArr = Array.isArray(list);
      var keys = isArr ? null : Object.keys(list);
      var length = isArr ? list.length : (keys ? keys.length : 0);

      if (!keyExpr) {
        var removed = removeBetween(anchorStart, anchorEnd);
        for (var ri = 0; ri < removed.length; ri++) runCleanupsDeep(removed[ri]);
        for (var i = 0; i < length; i++) {
          var itemVal = isArr ? list[i] : list[keys[i]];
          var idxVal = isArr ? i : keys[i];
          var entry = createEntry(itemVal, idxVal);
          for (var ni = 0; ni < entry.nodes.length; ni++) {
            parent.insertBefore(entry.nodes[ni], anchorEnd);
            walkTree(entry.nodes[ni], entry.scope, ctx);
          }
        }
        return;
      }

      var usedKeys = new Set();
      var ordered = [];

      for (var i = 0; i < length; i++) {
        var itemVal = isArr ? list[i] : list[keys[i]];
        var idxVal = isArr ? i : keys[i];

        var tempScope = Object.create(scope);
        tempScope[parsed.item] = itemVal;
        if (parsed.index) tempScope[parsed.index] = idxVal;
        var keyVal = vueEval(keyExpr, tempScope, anchorStart);

        usedKeys.add(keyVal);

        if (keyMap.has(keyVal)) {
          var existing = keyMap.get(keyVal);
          existing.scope[parsed.item] = itemVal;
          if (parsed.index) existing.scope[parsed.index] = idxVal;
          ordered.push(existing);
        } else {
          var created = createEntry(itemVal, idxVal);
          keyMap.set(keyVal, created);
          ordered.push(created);
          created._isNew = true;
        }
      }

      keyMap.forEach(function (entry, k) {
        if (!usedKeys.has(k)) {
          for (var ni = 0; ni < entry.nodes.length; ni++) {
            runCleanupsDeep(entry.nodes[ni]);
            if (entry.nodes[ni].parentNode) entry.nodes[ni].parentNode.removeChild(entry.nodes[ni]);
          }
          keyMap.delete(k);
        }
      });

      for (var oi = 0; oi < ordered.length; oi++) {
        var e = ordered[oi];
        for (var ni = 0; ni < e.nodes.length; ni++) {
          parent.insertBefore(e.nodes[ni], anchorEnd);
        }
        if (e._isNew) {
          for (var wi = 0; wi < e.nodes.length; wi++) {
            walkTree(e.nodes[wi], e.scope, ctx);
          }
          delete e._isNew;
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
      scheduleFlush();
    }
  };

})();
