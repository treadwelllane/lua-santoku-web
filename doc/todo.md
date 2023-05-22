# Now

- Refine how new works in the :lua() interface
    - Wrap js functions in tables with call
      metamethod
    - When converting LUA_TTABLE to an object,
      first check if it's a wrapped function
      with a call metamethod

- Object.keys, Object.values, Object.entries,
  pairs, ipairs

- Implement & test direct js function calls
  without obj:call("method", ...) protocol (see
  wrapfn for example)

- Implement integrate c++ coverage
- Run tests with sanitizers
- Reduce amount of heap-allocated vals if
  possible
- Ensure no memory leaks

- Fix Asyncify await
