# Now

- Migrate html-api and devcat

- Error messages

- Object.keys, Object.values, Object.entries,
  pairs, ipairs

- Implement integrate c++ coverage
- Run tests with sanitizers
- Reduce amount of heap-allocated vals if
  possible
- Ensure no memory leaks

- Figure out how to implement :await() without a
  callback. Asyncify will work, but is there a
  way to do without it?
    - Require :await() calls to be inside a
      wrapping coroutine
    - Get a reference to the main coroutine
    - Register a .then callback that resumes the
      main coroutine
    - yield to a dummy coroutine that calls exit(0)
    - C++20 coroutines?
