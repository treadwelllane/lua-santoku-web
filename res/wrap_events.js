const buffers = { fetch: [], activate: [], install: [], message: [] }

function push_buffer (name, item) {
  if (!buffers[name])
    return
  if (buffers[name].length >= <% return opts.event_buffer_max or 128 %>)
    buffers[name].shift()
  buffers[name].push(item)
}

Module.start = function () {

  if (Module.on_fetch) {
    buffers.fetch.forEach(([ ev, resolve, reject ]) => {
      Module.on_fetch(ev.request, ev.clientId)
        .then(resolve)
        .catch(reject)
    })
    buffers.fetch.length = 0
  }

  if (Module.on_install) {
    buffers.install.forEach(([ ev, resolve, reject ]) => {
      Module.on_install()
        .then(resolve)
        .catch(reject)
    })
    buffers.install.length = 0
  }

  if (Module.on_activate) {
    buffers.activate.forEach(([ ev, resolve, reject ]) => {
      Module.on_activate()
        .then(resolve)
        .catch(reject)
    })
    buffers.activate.length = 0
  }

  if (Module.on_message) {
    buffers.message.forEach(ev => {
      Module.on_message(ev)
    })
    buffers.message.length = 0
  }

}

self.addEventListener("fetch", ev => {
  ev.respondWith(new Promise((resolve, reject) => {
    if (Module.on_fetch) {
      Module.on_fetch(ev.request, ev.clientId)
        .then(resolve)
        .catch(reject)
    } else {
      push_buffer("fetch", [ ev, resolve, reject ])
    }
  }))
})

self.addEventListener("install", ev => {
  ev.waitUntil(new Promise((resolve, reject) => {
    if (Module.on_install) {
      Module.on_install()
        .then(resolve)
        .catch(reject)
    } else {
      push_buffer("install", [ ev, resolve, reject ])
    }
  }))
})

self.addEventListener("activate", ev => {
  ev.waitUntil(new Promise((resolve, reject) => {
    if (Module.on_activate) {
      Module.on_activate()
        .then(resolve)
        .catch(reject)
    } else {
      push_buffer("activate", [ ev, resolve, reject ])
    }
  }))
})

self.addEventListener("message", ev => {
  if (Module.on_message) {
    Module.on_message(ev)
  } else {
    push_buffer("message", ev)
  }
})
