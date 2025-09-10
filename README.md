# Santoku Web

Santoku Web is a Lua library extending
[Santoku](https://github.com/treadwelllane/lua-santoku) with web development
capabilities for WebAssembly environments.

## Module Reference

### `santoku.web.js`
Direct access to JavaScript global objects through a proxy interface.

### `santoku.web.val`
Core bidirectional Lua-JavaScript value conversion and object marshaling.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `val` | `lua_value, [recurse]` | `js_value` | Converts Lua value to JavaScript |
| `val.global` | `name` | `js_object` | Gets JavaScript global by name |
| `val.bytes` | `string` | `uint8array` | Converts Lua string to JavaScript Uint8Array |
| `val.class` | `config_fn, [parent_class]` | `js_class` | Creates JavaScript class |
| `val.lua` | `js_value, [recurse]` | `lua_value` | Converts JavaScript value to Lua |

JavaScript objects accessed through val provide:

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `:lua` | `[recurse]` | `lua_value` | Convert to Lua value |
| `:val` | `-` | `js_value` | Get underlying val object |
| `:typeof` | `-` | `string` | Get JavaScript type |
| `:instanceof` | `constructor` | `boolean` | Test instanceof relationship |
| `:call` | `this, ...args` | `result` | Call as function |
| `:new` | `...args` | `instance` | Call as constructor |

Promise objects additionally provide:

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `:await` | `callback` | `-` | Attach promise resolution handler |

JavaScript arrays provide:

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `:str` | `-` | `string` | Convert Uint8Array to Lua string |

### `santoku.web.util`
Web utilities for HTTP requests, WebSocket connections, DOM manipulation, and templating.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `request` | `url/opts, [done], [retry], [raw]` | `request_object` | Creates HTTP request |
| `get` | `url/opts, [done], [retry], [raw]` | `cancel_function` | Makes GET request |
| `post` | `url/opts, [done], [retry], [raw]` | `cancel_function` | Makes POST request |
| `http_client` | `-` | `client_object` | Creates HTTP client with events |
| `ws` | `url, [opts], each, [retries], [backoffs]` | `send_fn, close_fn` | Creates WebSocket connection |
| `clone` | `template, [data], [parent], [before], [pre_append]` | `element, [elements]` | Clones and populates template |
| `clone_all` | `options` | `cancel_fn, events` | Clones multiple templates asynchronously |
| `populate` | `element, data, [root], [elements]` | `element, elements, data` | Populates element with data |
| `template` | `content` | `template_element` | Creates template element |
| `static` | `html_string` | `page_object` | Creates static page object |
| `component` | `[tag], callback` | `class` | Creates custom web component |
| `promise` | `executor_fn` | `promise` | Creates JavaScript promise |
| `after_frame` | `callback` | `id` | Executes after next animation frame |
| `throttle` | `function, time_ms` | `function` | Creates throttled function |
| `debounce` | `function, time_ms` | `function` | Creates debounced function |
| `fit_image` | `img_element, container, [ratio]` | `-` | Fits image to container |
| `parse_path` | `url, [path], [params], [modal_sep]` | `path_object` | Parses URL path and query |
| `encode_path` | `path_object, [params], [modal_sep]` | `string` | Encodes path object to URL |
| `set_local` | `key, value` | `-` | Sets localStorage item |
| `get_local` | `key` | `string/nil` | Gets localStorage item |
| `utc_date` | `seconds` | `date_object` | Creates Date from UTC seconds |
| `date_utc` | `date_object` | `number` | Converts Date to UTC seconds |

Template attributes for `populate`:

| Attribute | Description |
|-----------|-------------|
| `tk-text="property"` | Sets element text content |
| `tk-html="property"` | Sets element innerHTML |
| `tk-href="property"` | Sets href attribute |
| `tk-value="property"` | Sets input value |
| `tk-src="property"` | Sets src attribute |
| `tk-checked="property"` | Sets checked state |
| `tk-id="path"` | Adds element to elements object at path |
| `tk-on:event="handler"` | Attaches event listener |
| `tk-repeat="array_property"` | Repeats element for array items |
| `tk-show:property[=value]` | Shows element if condition met |
| `tk-hide:property[=value]` | Hides element if condition met |
| `tk-shadow="mode"` | Attaches shadow DOM |

### `santoku.web.spa`
Single-page application framework with routing, navigation, modals, and UI components.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `spa` | `options` | `spa_object` | Creates SPA instance |

SPA object methods:

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `setup_ripple` | `element` | `-` | Adds material ripple effect |
| `add_page` | `name, page_object` | `-` | Registers page component |
| `add_modal` | `name, modal_object` | `-` | Registers modal component |
| `navigate` | `path, [replace], [force]` | `-` | Navigates to path |
| `back` | `-` | `-` | Navigates back |
| `show_modal` | `name, [data]` | `-` | Shows modal |
| `hide_modal` | `-` | `-` | Hides current modal |

Page/modal objects provide lifecycle hooks:
- `init(view, data)` - Called when page/modal loads
- `show(view, data)` - Called when page/modal becomes visible
- `hide(view, data)` - Called when page/modal becomes hidden
- `destroy(view, data)` - Called when page/modal unloads

Configuration options include theming (`theme_color`, `background_color`), layout (`header_height`, `nav_width`), and behavior settings (`modal_separator`, `transition_time`, screen breakpoints).

### `santoku.web.sqlite`
SQLite database operations in the browser using OPFS.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `open_opfs` | `dbfile, callback` | `-` | Opens SQLite database via OPFS |

The callback receives `(ok, db_or_error)` where `db` is a database object compatible with the [santoku.sqlite](https://github.com/treadwelllane/lua-santoku-sqlite) interface.

Note: SQLite functionality requires building SQLite for WASM and providing the Emscripten flag `--pre-js /path/to/sqlite/ext/wasm/jswasm/sqlite3.js`. Additionally, `sqlite3.wasm` and `sqlite3-opfs-async-proxy.js` must be hosted alongside your compiled script.

### `santoku.web.worker.rpc.client`
Client-side RPC communication with web workers.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `init` | `worker_script_path` | `rpc_client, worker` | Creates RPC client and worker |
| `create_port` | `worker` | `message_port` | Creates communication port |
| `register_port` | `worker, port` | `-` | Registers port with worker |
| `init_port` | `port` | `rpc_client` | Creates RPC client from port |

The RPC client is a proxy object where any property access returns a function that makes an RPC call to the worker.

### `santoku.web.worker.rpc.server`
Server-side RPC handling within web workers.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `init` | `handler_object, on_message` | `message_handler` | Creates RPC server |

Handler objects provide synchronous methods (returning results directly) and asynchronous methods (under the `async` key, with callback as last argument).

### `santoku.web.trace`
Debugging and logging utilities for web applications.

- `santoku.web.trace.common` - Common tracing functionality
- `santoku.web.trace.index` - Main thread tracing
- `santoku.web.trace.sw` - Service worker tracing

## License

MIT License

Copyright 2025 Matthew Brooks

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
