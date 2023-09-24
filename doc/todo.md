# Now

- If ASYNCIFY is not specified, make test and
  iterate should run both

- Clean up map/unmap_lua/js

- Correctly propagate lua errors

- Clean up which functions return with push_val_lua
  and which with push_val_lua: get, call,
  typeof, etc

- Date and other object gt, lt, etc. comparisons

- Wrapped object equality checks

- Basic README
- Documentation

- Fix x:val(false/true) and x:lua(false/true)

# Next

- Better error messages
- Run tests with sanitizers
- Ensure no memory leaks
- Coverage
- Linting

- Support Object.keys, Object.values,
  Object.entries, pairs, ipairs

# Eventually

- Implement c++ coverage and linting

- Figure out trace onerror and fetch events,
  currently they don't work because they're
  registered asynchronously instead of on
  initial script evaluation.

- Implement optional support for Asyncify which
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
