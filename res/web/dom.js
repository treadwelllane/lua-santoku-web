(function () {

  var elCache = {};
  var POS = { beforebegin: "beforebegin", afterbegin: "afterbegin", beforeend: "beforeend", afterend: "afterend" };

  function getEl (id) {
    var el = elCache[id];
    if (!el) {
      el = id === "body" ? document.body : document.getElementById(id);
      if (!el) throw new Error("dom: element not found: " + id);
      elCache[id] = el;
    }
    return el;
  }

  function readStr (heap, off) {
    var end = off;
    while (heap[end] !== 0) end++;
    return (new TextDecoder()).decode(heap.subarray(off, end));
  }

  function readU32 (view, pos) {
    return view.getUint32(pos, true);
  }

  function setCursor (el, offset) {
    var node = el.firstChild;
    if (!node) {
      node = document.createTextNode("");
      el.appendChild(node);
    }
    var len = node.length || 0;
    if (offset > len) offset = len;
    var range = document.createRange();
    range.setStart(node, offset);
    range.collapse(true);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  }

  function getCursor (el) {
    var sel = window.getSelection();
    if (!sel.rangeCount) return 0;
    var range = sel.getRangeAt(0);
    var pre = document.createRange();
    pre.setStart(el, 0);
    pre.setEnd(range.startContainer, range.startOffset);
    return pre.toString().length;
  }

  Module.__tk_dom_flush = function (cmdPtr, cmdLen, strPtr, count) {
    var heap = Module.HEAPU8;
    var view = new DataView(heap.buffer, heap.byteOffset);
    var pos = cmdPtr;
    for (var i = 0; i < count; i++) {
      var op = heap[pos]; pos++;
      switch (op) {
        case 0x01: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var soff = readU32(view, pos); pos += 4;
          var slen = readU32(view, pos); pos += 4;
          getEl(id).textContent = (new TextDecoder()).decode(heap.subarray(strPtr + soff, strPtr + soff + slen));
          break;
        }
        case 0x02: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var soff = readU32(view, pos); pos += 4;
          var slen = readU32(view, pos); pos += 4;
          getEl(id).innerHTML = (new TextDecoder()).decode(heap.subarray(strPtr + soff, strPtr + soff + slen));
          break;
        }
        case 0x03: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var name = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var val = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).setAttribute(name, val);
          break;
        }
        case 0x04: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var name = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).removeAttribute(name);
          break;
        }
        case 0x05: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var name = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var val = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).dataset[name] = val;
          break;
        }
        case 0x06: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var prop = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var val = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = getEl(id);
          if (prop.charAt(0) === "-")
            el.style.setProperty(prop, val);
          else
            el.style[prop] = val;
          break;
        }
        case 0x07: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var cls = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).classList.add(cls);
          break;
        }
        case 0x08: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var cls = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).classList.remove(cls);
          break;
        }
        case 0x09: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var position = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var soff = readU32(view, pos); pos += 4;
          var slen = readU32(view, pos); pos += 4;
          var html = (new TextDecoder()).decode(heap.subarray(strPtr + soff, strPtr + soff + slen));
          var el = getEl(id);
          el.insertAdjacentHTML(POS[position] || position, html);
          if (position === "afterend" || position === "beforebegin") delete elCache[id];
          break;
        }
        case 0x0A: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = getEl(id);
          el.remove();
          delete elCache[id];
          break;
        }
        case 0x0B: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).innerHTML = "";
          break;
        }
        case 0x0C: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var offset = view.getInt32(pos, true); pos += 4;
          var el = getEl(id);
          el.focus();
          if (offset >= 0) setCursor(el, offset);
          break;
        }
        case 0x0D: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).blur();
          break;
        }
        case 0x0E: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).showPopover();
          break;
        }
        case 0x0F: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          getEl(id).hidePopover();
          break;
        }
        case 0x10: {
          var x = view.getInt32(pos, true); pos += 4;
          var y = view.getInt32(pos, true); pos += 4;
          window.scrollTo(x, y);
          break;
        }
      }
    }
  };

  Module.__tk_dom_read_flush = function (cmdPtr, cmdLen, strPtr, count, resPtr, resSize, resStrPtr, resStrSize) {
    var heap = Module.HEAPU8;
    var view = new DataView(heap.buffer, heap.byteOffset);
    var resView = new DataView(heap.buffer, heap.byteOffset);
    var pos = cmdPtr;
    var rpos = resPtr;
    var rspos = 0;
    var encoder = new TextEncoder();

    function writeNil () { heap[rpos] = 0; rpos++; }
    function writeStr (s) {
      var bytes = encoder.encode(s);
      heap[rpos] = 1; rpos++;
      resView.setUint32(rpos, rspos, true); rpos += 4;
      resView.setUint32(rpos, bytes.length, true); rpos += 4;
      heap.set(bytes, resStrPtr + rspos);
      rspos += bytes.length;
    }
    function writeI32 (v) { heap[rpos] = 2; rpos++; resView.setInt32(rpos, v, true); rpos += 4; }
    function writeRect (r) {
      heap[rpos] = 3; rpos++;
      resView.setFloat32(rpos, r.top, true); rpos += 4;
      resView.setFloat32(rpos, r.left, true); rpos += 4;
      resView.setFloat32(rpos, r.bottom, true); rpos += 4;
      resView.setFloat32(rpos, r.right, true); rpos += 4;
      resView.setFloat32(rpos, r.width, true); rpos += 4;
      resView.setFloat32(rpos, r.height, true); rpos += 4;
    }
    function writeScroll () {
      heap[rpos] = 4; rpos++;
      resView.setFloat32(rpos, window.scrollX, true); rpos += 4;
      resView.setFloat32(rpos, window.scrollY, true); rpos += 4;
      resView.setFloat32(rpos, window.innerWidth, true); rpos += 4;
      resView.setFloat32(rpos, window.innerHeight, true); rpos += 4;
      resView.setFloat32(rpos, document.documentElement.scrollHeight, true); rpos += 4;
    }
    function writeBool (v) { heap[rpos] = 5; rpos++; heap[rpos] = v ? 1 : 0; rpos++; }

    for (var i = 0; i < count; i++) {
      var op = heap[pos]; pos++;
      switch (op) {
        case 0x80: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = id === "body" ? document.body : document.getElementById(id);
          if (!el) { writeNil(); break; }
          writeStr(el.textContent || "");
          break;
        }
        case 0x81: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var name = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = id === "body" ? document.body : document.getElementById(id);
          if (!el) { writeNil(); break; }
          var v = el.getAttribute(name);
          if (v == null) writeNil(); else writeStr(v);
          break;
        }
        case 0x82: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var name = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = id === "body" ? document.body : document.getElementById(id);
          if (!el) { writeNil(); break; }
          var v = el.dataset[name];
          if (v == null) writeNil(); else writeStr(v);
          break;
        }
        case 0x83: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = id === "body" ? document.body : document.getElementById(id);
          if (!el) { writeNil(); break; }
          writeRect(el.getBoundingClientRect());
          break;
        }
        case 0x84: {
          writeScroll();
          break;
        }
        case 0x85: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = id === "body" ? document.body : document.getElementById(id);
          if (!el) { writeNil(); break; }
          writeI32(getCursor(el));
          break;
        }
        case 0x87: {
          var id = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var cls = readStr(heap, strPtr + readU32(view, pos)); pos += 4;
          var el = id === "body" ? document.body : document.getElementById(id);
          if (!el) { writeNil(); break; }
          writeBool(el.classList.contains(cls));
          break;
        }
        case 0x88: {
          var x = readU32(view, pos); pos += 4;
          var y = readU32(view, pos); pos += 4;
          var el = document.elementFromPoint(x, y);
          if (!el) { writeNil(); break; }
          var bullet = el.closest ? el.closest("[data-id]") : null;
          if (bullet && bullet.id) writeStr(bullet.id); else writeNil();
          break;
        }
        default:
          writeNil();
      }
    }
  };

})();
