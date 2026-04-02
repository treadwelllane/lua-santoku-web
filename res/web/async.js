(function() {
  var scheduled = false;
  function drain() {
    scheduled = false;
    if (globalThis.__luaAsyncDrain) globalThis.__luaAsyncDrain();
  }
  globalThis.__luaAsyncSchedule = function() {
    if (!scheduled) {
      scheduled = true;
      setTimeout(drain, 0);
    }
  };
})()
