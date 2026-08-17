import QtQuick
import Quickshell
import Quickshell.Io
import "BoltModel.js" as BoltModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : BoltModel.PLUGIN_ID
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir !== "" ? sourceDir + "/bolt-helper" : ""

  property var snapshot: BoltModel.emptySnapshot()
  property var ignoredUids: ({})
  property var promptedUids: ({})
  property var pendingActions: ({})
  property string lastError: ""
  property bool snapshotReady: false
  property bool acting: false

  readonly property var manager: snapshot && snapshot.manager ? snapshot.manager : ({})
  readonly property var devices: snapshot && snapshot.devices ? snapshot.devices : []
  readonly property var groups: BoltModel.groupedDevices(devices, ignoredUids)
  readonly property var pendingDevices: groups.pending || []
  readonly property var connectedDevices: groups.connected || []
  readonly property var rememberedDevices: groups.remembered || []
  readonly property int pendingCount: pendingDevices.length
  readonly property int connectedCount: connectedDevices.length
  readonly property int rememberedCount: rememberedDevices.length
  readonly property int storedCount: BoltModel.storedCount(devices)
  readonly property bool boltAvailable: snapshot && snapshot.boltAvailable === true
  readonly property bool domainPresent: snapshot && snapshot.domainPresent === true
  readonly property bool probing: manager && manager.probing === true
  readonly property bool authEnabled: String(manager.authMode || "") !== "disabled"
  readonly property string securityLevel: snapshot ? String(snapshot.securityLevel || "") : ""
  readonly property bool iommu: snapshot ? snapshot.iommu === true : false
  readonly property string securityCaption: BoltModel.securityCaption(securityLevel, iommu)
  readonly property bool modelOk: BoltModel.selfTest() === true

  readonly property bool promptOnConnect: setting("promptOnConnect", true) === true
  readonly property bool autoEnrollUnlocked: setting("autoEnrollUnlocked", false) === true
  readonly property string defaultTrustPolicy: {
    var value = String(setting("defaultTrustPolicy", "auto") || "auto").toLowerCase()
    return value === "manual" ? "manual" : "auto"
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (!helperPath || snapshotProc.running) return
    snapshotProc.command = [helperPath, "snapshot"]
    snapshotProc.running = true
  }

  function applySnapshot(raw) {
    var next = BoltModel.parseSnapshot(raw)
    snapshot = next
    snapshotReady = true
    if (next.ok === false && next.error) lastError = next.error
    else if (next.ok) lastError = ""
    pruneSessionMaps()
    considerNewDevices()
  }

  function pruneSessionMaps() {
    var live = ({})
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (device && device.uid) live[device.uid] = device
    }
    ignoredUids = keepLiveKeys(ignoredUids, live, function(device) {
      return BoltModel.isPending(device, {})
    })
    promptedUids = keepLiveKeys(promptedUids, live, function(device) {
      return BoltModel.isPending(device, {})
    })
    pendingActions = keepLiveKeys(pendingActions, live, function() { return true })
  }

  function keepLiveKeys(map, live, keepIf) {
    var next = ({})
    var changed = false
    for (var uid in map || {}) {
      var device = live[uid]
      if (device && keepIf(device)) next[uid] = map[uid]
      else changed = true
    }
    if (!changed) {
      var count = 0
      for (var existing in map || {}) { count++; void existing }
      var kept = 0
      for (var remain in next) { kept++; void remain }
      if (count === kept) return map
    }
    return next
  }

  function considerNewDevices() {
    if (!snapshotReady) return
    var nextPrompted = BoltModel.cloneMap(promptedUids)
    var changed = false
    for (var i = 0; i < pendingDevices.length; i++) {
      var device = pendingDevices[i]
      if (!device || !device.uid || nextPrompted[device.uid]) continue
      nextPrompted[device.uid] = true
      changed = true
      if (autoEnrollUnlocked) {
        enroll(device.uid, defaultTrustPolicy)
        continue
      }
      if (promptOnConnect) {
        notifyPending(device)
        summonPanel()
      }
    }
    if (changed) promptedUids = nextPrompted
  }

  function notifyPending(device) {
    var headline = "Thunderbolt device waiting"
    var body = String(device.label || device.name || "Unknown device")
    if (device.vendor && body.indexOf(device.vendor) === -1)
      body = device.vendor + " · " + body
    Quickshell.execDetached([
      "omarchy", "notification", "send",
      "--app-name", "thunderbolt",
      "-u", "critical",
      "-g", BoltModel.GLYPH,
      "--exec", "omarchy-shell shell summon " + pluginId + " '{}'",
      headline,
      body
    ])
  }

  function summonPanel() {
    if (shell && typeof shell.summon === "function")
      shell.summon(pluginId, "{}")
  }

  function setPendingAction(uid, action) {
    if (!uid) return
    var next = BoltModel.cloneMap(pendingActions)
    if (action) next[uid] = action
    else delete next[uid]
    pendingActions = next
  }

  function pendingAction(uid) {
    return uid && pendingActions ? String(pendingActions[uid] || "") : ""
  }

  function runAction(args, uid, action) {
    if (!helperPath || actProc.running) return "busy"
    acting = true
    lastError = ""
    if (uid) setPendingAction(uid, action)
    actProc.command = [helperPath].concat(args)
    actProc.running = true
    return "ok"
  }

  function authorize(uid) {
    return runAction(["authorize", String(uid || "")], uid, "authorizing")
  }

  function enroll(uid, policy) {
    return runAction(["enroll", String(uid || ""), String(policy || defaultTrustPolicy)], uid, "enrolling")
  }

  function forget(uid) {
    return runAction(["forget", String(uid || "")], uid, "forgetting")
  }

  function setPolicy(uid, policy) {
    return runAction(["set-policy", String(uid || ""), String(policy || "auto")], uid, "updating")
  }

  function setAuthMode(enabled) {
    return runAction(["set-auth-mode", enabled ? "enabled" : "disabled"], "", "updating")
  }

  function ignore(uid) {
    if (!uid) return
    var next = BoltModel.cloneMap(ignoredUids)
    next[uid] = true
    ignoredUids = next
    var prompted = BoltModel.cloneMap(promptedUids)
    prompted[uid] = true
    promptedUids = prompted
  }

  function applyActionResult(raw) {
    acting = false
    var text = String(raw || "").trim()
    var parsed = ({})
    try { parsed = JSON.parse(text || "{}") } catch (e) { parsed = ({}) }
    if (parsed && parsed.ok === false) lastError = String(parsed.error || "Thunderbolt action failed")
    else lastError = ""
    if (parsed && parsed.uid) setPendingAction(parsed.uid, "")
    refresh()
  }

  Component.onCompleted: {
    refresh()
    startMonitor()
  }

  function startMonitor() {
    if (!helperPath || monitorProc.running) return
    monitorProc.command = [helperPath, "monitor"]
    monitorProc.running = true
  }

  Timer {
    id: refreshDebounce
    interval: 250
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollTimer
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: monitorRestart
    interval: 2000
    repeat: false
    onTriggered: root.startMonitor()
  }

  Process {
    id: snapshotProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySnapshot(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.snapshotReady)
        root.applySnapshot(JSON.stringify({ ok: false, error: "bolt helper failed" }))
    }
  }

  Process {
    id: actProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyActionResult(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && String(text).trim() !== "") root.lastError = String(text).trim()
      }
    }
    onExited: function() { root.acting = false }
  }

  Process {
    id: monitorProc
    stdout: SplitParser {
      onRead: function(line) {
        var event = BoltModel.parseEvent(line)
        if (!event) return
        refreshDebounce.restart()
      }
    }
    onExited: monitorRestart.restart()
  }
}
