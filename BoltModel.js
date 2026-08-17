.pragma library

var GLYPH = "󰠠"
var PLUGIN_ID = "unleashed-nick.thunderbolt"

function emptySnapshot() {
  return {
    ok: false,
    boltAvailable: false,
    error: "",
    manager: {},
    domains: [],
    devices: [],
    domainPresent: false,
    securityLevel: "",
    iommu: false
  }
}

function asArray(value) {
  if (!value) return []
  if (Array.isArray(value)) return value.slice()
  var length = Number(value.length || 0)
  if (!isFinite(length) || length <= 0) return []
  var list = []
  for (var i = 0; i < length; i++) list.push(value[i])
  return list
}

function cloneMap(map) {
  var next = ({})
  for (var key in map || {}) next[key] = map[key]
  return next
}

function parseSnapshot(raw) {
  var text = String(raw || "").trim()
  if (text === "") return emptySnapshot()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return emptySnapshot()
    var devices = []
    var source = asArray(parsed.devices)
    for (var i = 0; i < source.length; i++) {
      var row = deviceRow(source[i])
      if (row) devices.push(row)
    }
    var domains = asArray(parsed.domains)
    var manager = parsed.manager && typeof parsed.manager === "object" ? parsed.manager : {}
    return {
      ok: parsed.ok === true,
      boltAvailable: parsed.boltAvailable === true,
      error: String(parsed.error || ""),
      manager: manager,
      domains: domains,
      devices: devices,
      domainPresent: parsed.domainPresent === true || domains.length > 0,
      securityLevel: String(parsed.securityLevel || manager.securityLevel || ""),
      iommu: parsed.iommu === true
    }
  } catch (e) {
    var failed = emptySnapshot()
    failed.error = "invalid snapshot"
    return failed
  }
}

function parseEvent(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return null
    return {
      ok: parsed.ok !== false,
      event: String(parsed.event || ""),
      line: String(parsed.line || "")
    }
  } catch (e) {
    return null
  }
}

function deviceRow(device) {
  if (!device) return null
  var uid = String(device.uid || "")
  if (uid === "") return null
  var status = String(device.status || "unknown")
  var type = String(device.type || "")
  return {
    uid: uid,
    path: String(device.path || ""),
    name: String(device.name || ""),
    vendor: String(device.vendor || ""),
    label: String(device.label || device.name || uid),
    type: type,
    generation: Number(device.generation || 0),
    status: status,
    authFlags: String(device.authFlags || ""),
    parent: String(device.parent || ""),
    stored: device.stored === true,
    policy: String(device.policy || ""),
    key: String(device.key || ""),
    authorized: device.authorized === true || status === "authorized",
    connected: device.connected === true
      || status === "connected"
      || status === "connecting"
      || status === "authorizing"
      || status === "authorized"
      || status === "auth-error",
    isHost: type === "host",
    isPeripheral: type === "peripheral" || type === ""
  }
}

function isPending(device, ignored) {
  if (!device || device.isHost) return false
  if (ignored && ignored[device.uid]) return false
  if (device.authorized) return false
  return device.status === "connected"
    || device.status === "authorizing"
    || device.status === "auth-error"
}

function isConnectedAuthorized(device) {
  return !!(device && !device.isHost && device.authorized)
}

function isRemembered(device) {
  return !!(device && !device.isHost && device.stored && !device.connected)
}

function sortByLabel(list) {
  var next = asArray(list)
  next.sort(function(a, b) {
    return String(a && a.label || "").localeCompare(String(b && b.label || ""))
  })
  return next
}

function groupedDevices(devices, ignored) {
  var source = asArray(devices)
  var pending = []
  var connected = []
  var remembered = []
  for (var i = 0; i < source.length; i++) {
    var device = source[i]
    if (!device || device.isHost) continue
    if (isPending(device, ignored)) pending.push(device)
    else if (isConnectedAuthorized(device)) connected.push(device)
    else if (isRemembered(device)) remembered.push(device)
  }
  return {
    pending: sortByLabel(pending),
    connected: sortByLabel(connected),
    remembered: sortByLabel(remembered)
  }
}

function storedCount(devices) {
  var source = asArray(devices)
  var count = 0
  for (var i = 0; i < source.length; i++) {
    if (source[i] && !source[i].isHost && source[i].stored) count++
  }
  return count
}

function generationLabel(generation) {
  var n = Number(generation || 0)
  if (n >= 4) return "USB4"
  if (n === 3) return "Thunderbolt 3"
  if (n === 2) return "Thunderbolt 2"
  if (n === 1) return "Thunderbolt"
  return ""
}

function securityCaption(level, iommu) {
  var name = String(level || "").toLowerCase()
  var suffix = iommu ? " · IOMMU on" : " · IOMMU off"
  if (name === "none") return "No security" + suffix
  if (name === "user") return "User authorization" + suffix
  if (name === "secure") return "Secure authorization" + suffix
  if (name === "dponly") return "DisplayPort only" + suffix
  if (name === "usbonly") return "USB only" + suffix
  return (level ? String(level) : "Unknown") + suffix
}

function statusCaption(device, pendingAction) {
  var action = String(pendingAction || "")
  if (action === "authorizing" || action === "enrolling") return "Authorizing…"
  if (action === "forgetting") return "Forgetting…"
  if (action === "updating") return "Updating…"
  if (!device) return ""
  if (device.status === "authorizing") return "Authorizing…"
  if (device.status === "auth-error") return "Authorization failed"
  if (device.status === "connecting") return "Connecting…"
  if (device.authorized) {
    var gen = generationLabel(device.generation)
    if (device.stored && device.policy === "auto") return gen ? gen + " · trusted" : "Trusted"
    return gen || "Authorized"
  }
  if (device.status === "connected") return "Needs approval"
  if (device.stored) {
    if (device.policy === "auto") return "Remembered · auto"
    if (device.policy === "manual") return "Remembered · ask next time"
    return "Remembered"
  }
  return device.status || ""
}

function shortUid(uid) {
  var text = String(uid || "")
  if (text.length <= 13) return text
  return text.slice(0, 13)
}

function fixtureSnapshot() {
  return {
    ok: true,
    boltAvailable: true,
    error: "",
    manager: { authMode: "enabled", securityLevel: "user", probing: false },
    domains: [{ uid: "domain-1", securityLevel: "user", iommu: false }],
    devices: [
      deviceRow({
        uid: "host-1",
        label: "Lenovo T480",
        type: "host",
        status: "disconnected",
        stored: true
      }),
      deviceRow({
        uid: "dock-1",
        name: "Thunderbolt 4 Pro Dock",
        vendor: "CalDigit, Inc.",
        label: "CalDigit, Inc. Thunderbolt 4 Pro Dock",
        type: "peripheral",
        status: "connected",
        stored: false,
        generation: 4
      }),
      deviceRow({
        uid: "display-1",
        name: "Studio Display",
        vendor: "Apple Inc.",
        label: "Apple Inc. Studio Display",
        type: "peripheral",
        status: "disconnected",
        stored: true,
        policy: "auto",
        generation: 3
      })
    ],
    domainPresent: true,
    securityLevel: "user",
    iommu: false
  }
}

function selfTest() {
  var groups = groupedDevices(fixtureSnapshot().devices, { "ignored-1": true })
  return groups.pending.length === 1
    && groups.pending[0].uid === "dock-1"
    && groups.remembered.length === 1
    && groups.remembered[0].uid === "display-1"
    && groups.connected.length === 0
}
