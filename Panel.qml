pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "BoltModel.js" as BoltModel

Panel {
  id: root
  moduleName: "unleashed-nick.thunderbolt"
  ipcTarget: "unleashed-nick.thunderbolt"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var thunderbolt: null
  property bool openedFromHotkey: false
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    if (root.thunderbolt) root.thunderbolt.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    if (root.thunderbolt) root.thunderbolt.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  readonly property var pendingDevices: thunderbolt ? thunderbolt.pendingDevices : []
  readonly property var connectedDevices: thunderbolt ? thunderbolt.connectedDevices : []
  readonly property var rememberedDevices: thunderbolt ? thunderbolt.rememberedDevices : []
  readonly property bool authEnabled: thunderbolt ? thunderbolt.authEnabled === true : true
  readonly property bool acting: thunderbolt ? thunderbolt.acting === true : false
  readonly property string lastError: thunderbolt ? String(thunderbolt.lastError || "") : ""
  readonly property string heroMeta: thunderbolt ? thunderbolt.securityCaption : ""
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  property string focusSection: "header"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var visibleSections: {
    var sections = []
    if (pendingDevices.length > 0) sections.push("pending")
    if (connectedDevices.length > 0) sections.push("connected")
    if (rememberedDevices.length > 0) sections.push("remembered")
    return sections
  }

  function devicesFor(section) {
    if (section === "pending") return pendingDevices
    if (section === "connected") return connectedDevices
    if (section === "remembered") return rememberedDevices
    return []
  }

  function sectionCount(section) {
    return devicesFor(section).length
  }

  function deviceAt(section, index) {
    var list = devicesFor(section)
    return index >= 0 && index < list.length ? list[index] : null
  }

  function pendingAction(uid) {
    return thunderbolt ? thunderbolt.pendingAction(uid) : ""
  }

  function trustDevice(device) {
    if (!thunderbolt || !device) return
    thunderbolt.enroll(device.uid, thunderbolt.defaultTrustPolicy)
  }

  function allowOnce(device) {
    if (!thunderbolt || !device) return
    thunderbolt.authorize(device.uid)
  }

  function ignoreDevice(device) {
    if (!thunderbolt || !device) return
    thunderbolt.ignore(device.uid)
  }

  function forgetDevice(device) {
    if (!thunderbolt || !device) return
    thunderbolt.forget(device.uid)
  }

  function togglePolicy(device) {
    if (!thunderbolt || !device) return
    thunderbolt.setPolicy(device.uid, device.policy === "auto" ? "manual" : "auto")
  }

  function toggleAuthMode() {
    if (!thunderbolt) return
    thunderbolt.setAuthMode(!authEnabled)
  }

  function activateCursor() {
    if (focusSection === "header") {
      toggleAuthMode()
      return
    }
    var device = deviceAt(focusSection, selectedIndex)
    if (!device) return
    if (focusSection === "pending") trustDevice(device)
    else if (focusSection === "remembered") togglePolicy(device)
  }

  function deleteSelected() {
    var device = deviceAt(focusSection, selectedIndex)
    if (!device) return
    if (focusSection === "pending") ignoreDevice(device)
    else forgetDevice(device)
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (focusSection === "header") {
      if (delta > 0 && sections.length > 0) {
        focusSection = sections[0]
        selectedIndex = 0
      }
      return
    }
    if (sections.length === 0) {
      focusSection = "header"
      return
    }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1
    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = 0
      }
    } else {
      if (idx > 0) { selectedIndex = idx - 1; return }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = Math.max(0, sectionCount(focusSection) - 1)
      } else {
        focusSection = "header"
      }
    }
  }

  function clampCursor() {
    if (focusSection === "header") return
    var sections = visibleSections
    if (sections.length === 0) {
      focusSection = "header"
      selectedIndex = 0
      return
    }
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    var count = sectionCount(focusSection)
    if (selectedIndex > count - 1) selectedIndex = Math.max(0, count - 1)
    if (selectedIndex < 0) selectedIndex = 0
  }

  onOpenedChanged: {
    if (!opened) return
    if (pendingDevices.length > 0) { focusSection = "pending"; selectedIndex = 0 }
    else if (connectedDevices.length > 0) { focusSection = "connected"; selectedIndex = 0 }
    else if (rememberedDevices.length > 0) { focusSection = "remembered"; selectedIndex = 0 }
    else focusSection = "header"
    cursorActive = false
  }

  onVisibleSectionsChanged: clampCursor()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: if (root.cursorActive) root.deleteSelected()

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        PanelHero {
          title: "Thunderbolt"
          meta: root.heroMeta
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          iconComponent: Text {
            text: BoltModel.GLYPH
            color: root.pendingDevices.length > 0 ? Color.urgent : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.display
          }
          trailingControl: ToggleSwitch {
            checked: root.authEnabled
            busy: root.acting
            foreground: root.contentForeground
            hasCursor: root.cursorActive && root.focusSection === "header"
            onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "header" } }
            onToggled: root.toggleAuthMode()
          }
        }

        Text {
          width: parent.width
          visible: root.lastError !== ""
          text: root.lastError
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: !root.thunderbolt || !root.thunderbolt.boltAvailable
          text: root.thunderbolt && root.thunderbolt.lastError
            ? root.thunderbolt.lastError
            : "bolt is not available. Install the bolt package and start bolt.service."
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        DeviceSection {
          title: "NEEDS APPROVAL"
          sectionName: "pending"
          model: root.pendingDevices
        }

        DeviceSection {
          title: "CONNECTED"
          sectionName: "connected"
          model: root.connectedDevices
        }

        DeviceSection {
          title: "REMEMBERED"
          sectionName: "remembered"
          model: root.rememberedDevices
        }

        Text {
          width: parent.width
          visible: root.pendingDevices.length === 0
            && root.connectedDevices.length === 0
            && root.rememberedDevices.length === 0
            && root.thunderbolt
            && root.thunderbolt.boltAvailable
          text: root.thunderbolt && root.thunderbolt.domainPresent
            ? "No Thunderbolt devices connected."
            : "No Thunderbolt controller found."
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component DeviceSection: Column {
    id: section
    required property string title
    required property string sectionName
    required property var model
    width: column.width
    spacing: Style.space(10)
    visible: model && model.length > 0

    PanelSeparator { foreground: root.contentForeground }

    PanelSectionHeader {
      text: section.title
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
    }

    Repeater {
      model: section.model
      DeviceRow {
        required property var modelData
        required property int index
        width: section.width
        dev: modelData
        rowIndex: index
        sectionName: section.sectionName
      }
    }
  }

  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    required property int rowIndex
    required property string sectionName

    readonly property bool rowSelected: root.cursorActive && root.focusSection === sectionName && root.selectedIndex === rowIndex
    readonly property string action: root.pendingAction(dev ? dev.uid : "")
    readonly property string statusText: BoltModel.statusCaption(dev, action)

    hasCursor: rowSelected
    current: !!(dev && dev.authorized)
    foreground: root.contentForeground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = row.sectionName
        root.selectedIndex = row.rowIndex
      }
    }

    Column {
      id: rowContent
      width: parent.width
      spacing: Style.space(8)
      leftPadding: Style.space(10)
      rightPadding: Style.space(10)
      topPadding: Style.space(8)
      bottomPadding: Style.space(8)

      Column {
        width: parent.width - rowContent.leftPadding - rowContent.rightPadding
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: row.dev ? (row.dev.label || "Device") : "Device"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: row.statusText !== ""
          text: row.statusText
          color: row.dev && row.dev.status === "auth-error" ? Color.urgent : Qt.darker(root.contentForeground, 1.45)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Flow {
        width: parent.width - rowContent.leftPadding - rowContent.rightPadding
        spacing: Style.space(8)
        visible: row.sectionName !== "connected" || (row.dev && row.dev.stored)

        Button {
          visible: row.sectionName === "pending"
          text: "Trust"
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          enabled: !root.acting
          onClicked: root.trustDevice(row.dev)
        }

        Button {
          visible: row.sectionName === "pending"
          text: "Allow once"
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          enabled: !root.acting
          onClicked: root.allowOnce(row.dev)
        }

        Button {
          visible: row.sectionName === "pending"
          text: "Ignore"
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          enabled: !root.acting
          onClicked: root.ignoreDevice(row.dev)
        }

        Button {
          visible: row.sectionName === "remembered" || (row.sectionName === "connected" && row.dev && row.dev.stored)
          text: row.dev && row.dev.policy === "auto" ? "Ask next time" : "Trust next time"
          bordered: true
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          enabled: !root.acting && !!(row.dev && row.dev.stored)
          onClicked: root.togglePolicy(row.dev)
        }

        Button {
          visible: row.sectionName === "remembered" || (row.sectionName === "connected" && row.dev && row.dev.stored)
          text: "Forget"
          bordered: true
          foreground: Color.urgent
          accent: Color.urgent
          fontFamily: root.contentFontFamily
          enabled: !root.acting
          onClicked: root.forgetDevice(row.dev)
        }
      }
    }
  }
}
