local test = require("santoku.test")
local err = require("santoku.error")
local validate = require("santoku.validate")

local assert = err.assert
local eq = validate.isequal

collectgarbage("stop")

local dom = require("santoku.web.dom")
local val = require("santoku.web.val")
local g = val.global("globalThis"):lua()

local function get_text (id)
  local el = g.document:getElementById(id)
  return el and el.textContent or nil
end

local function get_html (id)
  local el = g.document:getElementById(id)
  return el and (el.innerHTML or "") or nil
end

local function get_attr (id, name)
  local el = g.document:getElementById(id)
  return el and el:getAttribute(name) or nil
end

local function get_data (id, name)
  local el = g.document:getElementById(id)
  return el and el.dataset and el.dataset[name] or nil
end

local function get_style (id, prop)
  local el = g.document:getElementById(id)
  return el and el.style and el.style[prop] or nil
end

local function has_class (id, cls)
  local el = g.document:getElementById(id)
  return el and el.classList:contains(cls)
end

local function el_exists (id)
  return g.document:getElementById(id) ~= nil
end

local function child_count (id)
  local el = g.document:getElementById(id)
  return el and el.children.length or 0
end

g:eval([[
  var testRoot = document.createElement("div");
  testRoot.id = "test-root";
  document.body.appendChild(testRoot);
  globalThis.__tkDomTestReset = function () {
    testRoot.innerHTML = '<div id="a" class="x" data-sync="dirty" style="color:red">hello</div>' +
      '<div id="b">world</div>' +
      '<div id="c"><span id="c1">child</span></div>' +
      '<div id="container"></div>';
  };
  __tkDomTestReset();
]])

local function reset ()
  g.__tkDomTestReset(nil)
end

test("text sets textContent", function ()
  reset()
  dom.text("a", "new text")
  dom.flush()
  assert(eq("new text", get_text("a")))
end)

test("html sets innerHTML", function ()
  reset()
  dom.html("container", "<p>hi</p>")
  dom.flush()
  assert(eq("<p>hi</p>", get_html("container")))
end)

test("attr sets and removes attribute", function ()
  reset()
  dom.attr("a", "title", "tip")
  dom.flush()
  assert(eq("tip", get_attr("a", "title")))
  dom.attr("a", "title", nil)
  dom.flush()
  assert(eq(nil, get_attr("a", "title")))
end)

test("data sets dataset property", function ()
  reset()
  dom.data("a", "sync", "clean")
  dom.flush()
  assert(eq("clean", get_data("a", "sync")))
end)

test("style sets style property", function ()
  reset()
  dom.style("a", "color", "blue")
  dom.flush()
  assert(eq("blue", get_style("a", "color")))
end)

test("class_add and class_rm", function ()
  reset()
  dom.class_add("a", "y")
  dom.flush()
  assert(has_class("a", "y"))
  assert(has_class("a", "x"))
  dom.class_rm("a", "x")
  dom.flush()
  assert(not has_class("a", "x"))
  assert(has_class("a", "y"))
end)

test("insert_html afterend", function ()
  reset()
  dom.insert_html("a", "afterend", '<div id="new1">inserted</div>')
  dom.flush()
  assert(el_exists("new1"))
  assert(eq("inserted", get_text("new1")))
end)

test("insert_html beforeend", function ()
  reset()
  dom.insert_html("container", "beforeend", '<div id="new2">appended</div>')
  dom.flush()
  assert(eq(1, child_count("container")))
end)

test("remove element", function ()
  reset()
  dom.remove("b")
  dom.flush()
  assert(not el_exists("b"))
end)

test("remove_children clears content", function ()
  reset()
  dom.remove_children("c")
  dom.flush()
  assert(eq(0, child_count("c")))
end)

test("multiple commands in one flush", function ()
  reset()
  dom.text("a", "alpha")
  dom.data("a", "sync", "clean")
  dom.class_add("b", "active")
  dom.text("b", "beta")
  dom.flush()
  assert(eq("alpha", get_text("a")))
  assert(eq("clean", get_data("a", "sync")))
  assert(has_class("b", "active"))
  assert(eq("beta", get_text("b")))
end)

test("flush with no commands is noop", function ()
  dom.flush()
end)

test("read text", function ()
  reset()
  local t = dom.read({ "text", "a" })
  assert(eq("hello", t))
end)

test("read attr", function ()
  reset()
  local v = dom.read({ "attr", "a", "class" })
  assert(eq("x", v))
end)

test("read data", function ()
  reset()
  local v = dom.read({ "data", "a", "sync" })
  assert(eq("dirty", v))
end)

test("read has_class", function ()
  reset()
  local v = dom.read({ "has_class", "a", "x" })
  assert(eq(true, v))
  local v2 = dom.read({ "has_class", "a", "nope" })
  assert(eq(false, v2))
end)

test("read multiple values", function ()
  reset()
  local t, d = dom.read(
    { "text", "a" },
    { "data", "a", "sync" }
  )
  assert(eq("hello", t))
  assert(eq("dirty", d))
end)

test("read nil for missing element", function ()
  reset()
  local v = dom.read({ "text", "nonexistent" })
  assert(eq(nil, v))
end)

test("read scroll", function ()
  local v = dom.read({ "scroll" })
  assert(type(v) == "table" or type(v) == "userdata")
end)

test("write fail fast on missing element", function ()
  reset()
  local ok = pcall(function ()
    dom.text("nonexistent", "fail")
    dom.flush()
  end)
  assert(not ok)
end)

val.global("setTimeout"):call(nil, function ()
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
end, 500)
