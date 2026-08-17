import QtQuick
import qs.Commons
import qs.Ui
import "BoltModel.js" as BoltModel

BarWidget {
  id: root
  moduleName: "unleashed-nick.thunderbolt"

  readonly property var thunderbolt: bar && bar.shell ? bar.shell.serviceFor("unleashed-nick.thunderbolt") : null
  readonly property bool showWhenIdle: setting("showWhenIdle", false) === true
  readonly property bool domainPresent: thunderbolt ? thunderbolt.domainPresent === true : false
  readonly property int pendingCount: thunderbolt ? thunderbolt.pendingCount : 0
  readonly property int connectedCount: thunderbolt ? thunderbolt.connectedCount : 0
  readonly property int storedCount: thunderbolt ? thunderbolt.storedCount : 0
  readonly property bool hasHardware: domainPresent || storedCount > 0 || pendingCount > 0 || connectedCount > 0
  readonly property bool shouldShow: showWhenIdle || hasHardware

  readonly property color defaultForeground: bar ? bar.foreground : Color.foreground
  readonly property color iconColor: {
    if (pendingCount > 0) return Color.urgent
    if (connectedCount > 0) return Color.accent
    return defaultForeground
  }

  readonly property string icon: BoltModel.GLYPH
  readonly property string tooltip: {
    if (!thunderbolt || !thunderbolt.boltAvailable) return "Thunderbolt unavailable"
    if (pendingCount > 0) return pendingCount === 1 ? "Thunderbolt device needs approval" : (pendingCount + " Thunderbolt devices need approval")
    if (connectedCount > 0) return connectedCount === 1 ? "Thunderbolt device connected" : (connectedCount + " Thunderbolt devices connected")
    if (domainPresent) return thunderbolt.securityCaption || "Thunderbolt"
    return "Thunderbolt"
  }

  function syncService() {
    if (root.thunderbolt && "settings" in root.thunderbolt) root.thunderbolt.settings = root.settings
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("thunderbolt" in target) target.thunderbolt = root.thunderbolt
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
    else if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: shouldShow
  implicitWidth: shouldShow ? button.implicitWidth : 0
  implicitHeight: shouldShow ? button.implicitHeight : 0

  onBarChanged: injectPanel()
  onSettingsChanged: { injectPanel(); syncService() }
  onThunderboltChanged: { injectPanel(); syncService() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.iconColor
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.MiddleButton && root.thunderbolt) root.thunderbolt.refresh()
      else root.togglePanel()
    }
  }
}
