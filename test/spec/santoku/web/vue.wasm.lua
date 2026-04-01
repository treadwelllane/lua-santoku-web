local test = require("santoku.test")
local err = require("santoku.error")
local validate = require("santoku.validate")
local val = require("santoku.web.val")

local assert = err.assert
local eq = validate.isequal

collectgarbage("stop")

val.global("eval"):call(nil, [[

  (function () {

    var idCounter = 0;

    function Element (tag) {
      this.nodeType = 1;
      this.tagName = tag.toUpperCase();
      this.attributes = {};
      this.children = [];
      this.childNodes = [];
      this.parentNode = null;
      this.style = {};
      this.classList = {
        _set: {},
        add: function (c) { this._set[c] = true; },
        remove: function (c) { delete this._set[c]; },
        contains: function (c) { return !!this._set[c]; }
      };
      this._listeners = {};
      this._id = ++idCounter;
    }

    Element.prototype.getAttribute = function (name) {
      var a = this.attributes[name];
      return a !== undefined ? a : null;
    };

    Element.prototype.setAttribute = function (name, value) {
      this.attributes[name] = value;
    };

    Element.prototype.removeAttribute = function (name) {
      delete this.attributes[name];
    };

    Element.prototype.hasAttribute = function (name) {
      return this.attributes.hasOwnProperty(name);
    };

    Object.defineProperty(Element.prototype, "attributes", {
      get: function () { return this._attributes; },
      set: function (v) { this._attributes = v; }
    });

    Object.defineProperty(Element.prototype, "attributes", {
      get: function () {
        var self = this;
        var keys = Object.keys(self._attrs || {});
        var result = keys.map(function (k) { return { name: k, value: self._attrs[k] }; });
        result.length = keys.length;
        return result;
      },
      set: function (v) { this._attrs = v; }
    });

    Element.prototype.getAttribute = function (name) {
      return this._attrs && this._attrs[name] !== undefined ? this._attrs[name] : null;
    };
    Element.prototype.setAttribute = function (name, value) {
      if (!this._attrs) this._attrs = {};
      this._attrs[name] = String(value);
    };
    Element.prototype.removeAttribute = function (name) {
      if (this._attrs) delete this._attrs[name];
    };
    Element.prototype.hasAttribute = function (name) {
      return this._attrs ? this._attrs.hasOwnProperty(name) : false;
    };

    Element.prototype.appendChild = function (child) {
      if (child.nodeType === 11) {
        var kids = child.childNodes.slice();
        for (var i = 0; i < kids.length; i++) this.appendChild(kids[i]);
        return child;
      }
      if (child.parentNode) child.parentNode.removeChild(child);
      child.parentNode = this;
      this.childNodes.push(child);
      if (child.nodeType === 1 || child.nodeType === 0) {
        this.children.push(child);
      }
      return child;
    };

    Element.prototype.insertBefore = function (newNode, refNode) {
      if (newNode.nodeType === 11) {
        var kids = newNode.childNodes.slice();
        for (var i = 0; i < kids.length; i++) this.insertBefore(kids[i], refNode);
        return newNode;
      }
      if (newNode.parentNode) newNode.parentNode.removeChild(newNode);
      newNode.parentNode = this;
      if (!refNode) {
        this.childNodes.push(newNode);
      } else {
        var idx = this.childNodes.indexOf(refNode);
        if (idx === -1) this.childNodes.push(newNode);
        else this.childNodes.splice(idx, 0, newNode);
      }
      this._rebuildChildren();
      return newNode;
    };

    Element.prototype.removeChild = function (child) {
      var idx = this.childNodes.indexOf(child);
      if (idx !== -1) this.childNodes.splice(idx, 1);
      this._rebuildChildren();
      child.parentNode = null;
      return child;
    };

    Element.prototype._rebuildChildren = function () {
      this.children = this.childNodes.filter(function (n) { return n.nodeType === 1; });
    };

    Element.prototype.cloneNode = function (deep) {
      var clone;
      if (this.tagName === "TEMPLATE") {
        clone = new TemplateElement();
      } else {
        clone = new Element(this.tagName.toLowerCase());
      }
      if (this._attrs) clone._attrs = Object.assign({}, this._attrs);
      clone.style = Object.assign({}, this.style);
      if (deep) {
        for (var i = 0; i < this.childNodes.length; i++) {
          clone.appendChild(this.childNodes[i].cloneNode(true));
        }
      }
      if (this.tagName === "TEMPLATE" && this.content) {
        clone.content = this.content.cloneNode(true);
      }
      return clone;
    };

    Object.defineProperty(Element.prototype, "textContent", {
      get: function () {
        var result = "";
        for (var i = 0; i < this.childNodes.length; i++) {
          result += this.childNodes[i].textContent || "";
        }
        return result;
      },
      set: function (v) {
        this.childNodes = [];
        this.children = [];
        if (v !== "") {
          var tn = new TextNode(v);
          tn.parentNode = this;
          this.childNodes.push(tn);
        }
      }
    });

    Object.defineProperty(Element.prototype, "innerHTML", {
      get: function () { return this._innerHTML || ""; },
      set: function (v) {
        this._innerHTML = v;
        this.childNodes = [];
        this.children = [];
      }
    });

    Object.defineProperty(Element.prototype, "nextElementSibling", {
      get: function () {
        if (!this.parentNode) return null;
        var siblings = this.parentNode.children;
        var idx = siblings.indexOf(this);
        return idx >= 0 && idx < siblings.length - 1 ? siblings[idx + 1] : null;
      }
    });

    Element.prototype.addEventListener = function (event, fn, opts) {
      if (!this._listeners[event]) this._listeners[event] = [];
      this._listeners[event].push(fn);
    };

    Element.prototype.removeEventListener = function (event, fn) {
      if (!this._listeners[event]) return;
      var idx = this._listeners[event].indexOf(fn);
      if (idx !== -1) this._listeners[event].splice(idx, 1);
    };

    Element.prototype.dispatchEvent = function (ev) {
      ev.target = this;
      var fns = this._listeners[ev.type] || [];
      for (var i = 0; i < fns.length; i++) fns[i](ev);
      if (ev.bubbles && this.parentNode) this.parentNode.dispatchEvent(ev);
    };

    Element.prototype.querySelector = function (sel) {
      if (sel.charAt(0) === "#") {
        var id = sel.slice(1);
        for (var i = 0; i < this.childNodes.length; i++) {
          var c = this.childNodes[i];
          if (c.nodeType === 1) {
            if (c.getAttribute && c.getAttribute("id") === id) return c;
            var found = c.querySelector(sel);
            if (found) return found;
          }
        }
      }
      return null;
    };

    function TextNode (text) {
      this.nodeType = 3;
      this.textContent = text;
      this.parentNode = null;
    }

    TextNode.prototype.cloneNode = function () {
      return new TextNode(this.textContent);
    };

    function CommentNode (text) {
      this.nodeType = 8;
      this.textContent = text;
      this.parentNode = null;
    }

    CommentNode.prototype.cloneNode = function () {
      return new CommentNode(this.textContent);
    };

    function DocumentFragment () {
      this.nodeType = 11;
      this.childNodes = [];
      this.children = [];
    }
    DocumentFragment.prototype = Object.create(Element.prototype);
    DocumentFragment.prototype.constructor = DocumentFragment;

    DocumentFragment.prototype.cloneNode = function (deep) {
      var clone = new DocumentFragment();
      if (deep) {
        for (var i = 0; i < this.childNodes.length; i++) {
          clone.appendChild(this.childNodes[i].cloneNode(true));
        }
      }
      return clone;
    };

    function TemplateElement () {
      Element.call(this, "template");
      this.content = new DocumentFragment();
    }
    TemplateElement.prototype = Object.create(Element.prototype);
    TemplateElement.prototype.constructor = TemplateElement;

    function TreeWalker (root, filter) {
      this._root = root;
      this._filter = filter;
      this._current = root;
      this._queue = [];
      this._buildQueue(root);
      this._idx = -1;
    }

    TreeWalker.prototype._buildQueue = function (node) {
      for (var i = 0; i < (node.childNodes || []).length; i++) {
        var child = node.childNodes[i];
        if (this._filter === 4 && child.nodeType === 3) {
          this._queue.push(child);
        }
        if (child.childNodes) this._buildQueue(child);
      }
    };

    TreeWalker.prototype.nextNode = function () {
      this._idx++;
      return this._idx < this._queue.length ? this._queue[this._idx] : null;
    };

    globalThis.NodeFilter = { SHOW_TEXT: 4 };
    globalThis.CustomEvent = function (type, opts) {
      this.type = type;
      this.detail = opts && opts.detail;
      this.bubbles = opts && opts.bubbles;
    };

    globalThis.document = {
      createComment: function (text) { return new CommentNode(text || ""); },
      createTreeWalker: function (root, filter) { return new TreeWalker(root, filter); },
      querySelector: function (sel) { return globalThis.document.body.querySelector(sel); },
      body: new Element("body")
    };

    globalThis.__tkTestCreateElement = function (tag) {
      return new Element(tag);
    };

    globalThis.__tkTestCreateTemplate = function () {
      return new TemplateElement();
    };

    globalThis.__tkTestCreateTextNode = function (text) {
      return new TextNode(text);
    };

    globalThis.__tkTestAppendChild = function (parent, child) {
      return parent.appendChild(child);
    };

    globalThis.__tkTestGetTextContent = function (el) {
      return el.textContent;
    };

    globalThis.__tkTestGetInnerHTML = function (el) {
      return el.innerHTML || "";
    };

    globalThis.__tkTestGetStyle = function (el, prop) {
      return el.style[prop] || "";
    };

    globalThis.__tkTestClassContains = function (el, cls) {
      return el.classList.contains(cls);
    };

    globalThis.__tkTestChildCount = function (el) {
      return el.children.length;
    };

    globalThis.__tkTestGetChild = function (el, idx) {
      return el.children[idx];
    };

    globalThis.__tkTestSetValue = function (el, val) {
      el.value = val;
    };

    globalThis.__tkTestDispatchEvent = function (el, type) {
      el.dispatchEvent(new CustomEvent(type, { bubbles: true }));
    };

    globalThis.__tkTestSetAttribute = function (el, name, value) {
      el.setAttribute(name, value);
    };

    globalThis.__tkTestAppendToContent = function (tmpl, child) {
      tmpl.content.appendChild(child);
    };

  })();

]])

local vue = require("santoku.web.vue")

local tg = val.global("globalThis"):lua()

local function el (tag)
  return tg.__tkTestCreateElement(nil, tag)
end

local function tmpl ()
  return tg.__tkTestCreateTemplate(nil)
end

local function text (str)
  return tg.__tkTestCreateTextNode(nil, str)
end

local function append (parent, child)
  tg.__tkTestAppendChild(nil, parent, child)
end

local function append_to_content (t, child)
  tg.__tkTestAppendToContent(nil, t, child)
end

local function set_attr (e, name, value)
  tg.__tkTestSetAttribute(nil, e, name, value)
end

local function get_text (e)
  return tg.__tkTestGetTextContent(nil, e)
end

local function get_html (e)
  return tg.__tkTestGetInnerHTML(nil, e)
end

local function get_style (e, prop)
  return tg.__tkTestGetStyle(nil, e, prop)
end

local function has_class (e, cls)
  return tg.__tkTestClassContains(nil, e, cls)
end

local function child_count (e)
  return tg.__tkTestChildCount(nil, e)
end

local function get_child (e, idx)
  return tg.__tkTestGetChild(nil, e, idx)
end

local function set_value (e, v)
  tg.__tkTestSetValue(nil, e, v)
end

local function dispatch (e, event_type)
  tg.__tkTestDispatchEvent(nil, e, event_type)
end

local setTimeout = val.global("setTimeout")

local function after (ms, fn)
  setTimeout:call(nil, fn, ms)
end

test("v-text", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, "v-text", "msg")
  append(root, span)

  vue.createApp({ msg = "hello" }):mount(root)

  after(10, function ()
    assert(eq("hello", get_text(span)))
  end)
end)

test("v-show", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, "v-show", "visible")
  append(root, span)

  vue.createApp({ visible = false }):mount(root)

  after(10, function ()
    assert(eq("none", get_style(span, "display")))
  end)
end)

test("v-html", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local div2 = el("div")
  set_attr(div2, "v-html", "content")
  append(root, div2)

  vue.createApp({ content = "<b>bold</b>" }):mount(root)

  after(10, function ()
    assert(eq("<b>bold</b>", get_html(div2)))
  end)
end)

test("v-bind", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, ":title", "tip")
  append(root, span)

  vue.createApp({ tip = "hello" }):mount(root)

  after(10, function ()
    assert(eq("hello", span:getAttribute("title")))
  end)
end)

test("v-bind:class object", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, ":class", "{ active: isActive }")
  append(root, span)

  vue.createApp({ isActive = true }):mount(root)

  after(10, function ()
    assert(has_class(span, "active"))
  end)
end)

test("v-on click", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local btn = el("button")
  set_attr(btn, "@click", "count++")
  append(root, btn)
  local span = el("span")
  set_attr(span, "v-text", "count")
  append(root, span)

  vue.createApp({ count = 0 }):mount(root)

  dispatch(btn, "click")

  after(10, function ()
    assert(eq("1", get_text(span)))
  end)
end)

test("v-on method call", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local btn = el("button")
  set_attr(btn, "@click", "inc()")
  append(root, btn)
  local span = el("span")
  set_attr(span, "v-text", "count")
  append(root, span)

  vue.createApp({
    count = 0,
    inc = function (self)
      self.count = self.count + 1
    end
  }):mount(root)

  dispatch(btn, "click")

  after(10, function ()
    assert(eq("1", get_text(span)))
  end)
end)

test("v-if", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, "v-if", "show")
  set_attr(span, "v-text", "'visible'")
  append(root, span)

  vue.createApp({ show = true }):mount(root)

  after(10, function ()
    assert(eq(1, child_count(root)))
  end)
end)

test("v-if false", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, "v-if", "show")
  set_attr(span, "v-text", "'visible'")
  append(root, span)

  vue.createApp({ show = false }):mount(root)

  after(10, function ()
    assert(eq(0, child_count(root)))
  end)
end)

test("v-for array", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local li = el("li")
  set_attr(li, "v-for", "item in items")
  set_attr(li, "v-text", "item")
  append(root, li)

  vue.createApp({ items = { "a", "b", "c" } }):mount(root)

  after(10, function ()
    assert(eq(3, child_count(root)))
    assert(eq("a", get_text(get_child(root, 0))))
    assert(eq("b", get_text(get_child(root, 1))))
    assert(eq("c", get_text(get_child(root, 2))))
  end)
end)

test("v-effect", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, "v-effect", "$el.textContent = 'effect: ' + count")
  append(root, span)

  vue.createApp({ count = 5 }):mount(root)

  after(10, function ()
    assert(eq("effect: 5", get_text(span)))
  end)
end)

test("v-cloak removed", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  set_attr(root, "v-cloak", "")

  vue.createApp({}):mount(root)

  assert(eq(false, root:hasAttribute("v-cloak")))
end)

test("v-pre skips compilation", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local span = el("span")
  set_attr(span, "v-pre", "")
  set_attr(span, "v-text", "msg")
  append(root, span)

  vue.createApp({ msg = "hello" }):mount(root)

  after(10, function ()
    assert(eq("", get_text(span)))
    assert(eq(true, span:hasAttribute("v-text")))
  end)
end)

test("reactive updates propagate", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local btn = el("button")
  set_attr(btn, "@click", "count++")
  append(root, btn)
  local span = el("span")
  set_attr(span, "v-text", "count")
  append(root, span)

  vue.createApp({ count = 0 }):mount(root)

  dispatch(btn, "click")
  dispatch(btn, "click")
  dispatch(btn, "click")

  after(50, function ()
    assert(eq("3", get_text(span)))
  end)
end)

test("nested v-scope", function ()
  local root = el("div")
  set_attr(root, "v-scope", "")
  local inner = el("div")
  set_attr(inner, "v-scope", "{ msg: 'inner' }")
  local span = el("span")
  set_attr(span, "v-text", "msg")
  append(inner, span)
  append(root, inner)

  vue.createApp({ msg = "outer" }):mount(root)

  after(10, function ()
    assert(eq("inner", get_text(span)))
  end)
end)

val.global("setTimeout"):call(nil, function ()

  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")

  val.global("setTimeout"):call(nil, function ()

    assert(val.IDX_REF_TBL.n == 2, "IDX_REF_TBL.n ~= 2")

    if os.getenv("TK_WEB_PROFILE") == "1" then
      require("santoku.profile")()
    end

  end)

end, 500)
