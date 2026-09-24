import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button plus popup for qubes. Everything comes from `qube list --json`,
// which reads local files and systemd, so a short poll costs next to nothing.
// Actions go through qube-menu, the same script the Omarchy menu uses, so the
// two front ends cannot drift apart.
Panel {
  id: root
  moduleName: "io.github.achevalier-dev.qubes"
  ipcTarget: "io.github.achevalier-dev.qubes"

  property var qubes: []
  property bool installed: true

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property int pollSeconds: Math.max(2, setting("pollSeconds", 5))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string glyph: "󰆧"

  readonly property var named: qubes.filter(function (q) { return !q.disposable })
  readonly property var runningQubes: qubes.filter(function (q) { return q.state === "running" })

  // One running qube lends the glyph its colour; several leave it plain, and
  // the tooltip names them.
  readonly property color glyphColor: {
    if (runningQubes.length === 1) return runningQubes[0].color
    return runningQubes.length > 0 ? foreground : dim
  }

  readonly property string summary: {
    if (!installed) return "qube is not installed"
    if (runningQubes.length === 0) return named.length === 0 ? "No qubes yet" : "Nothing running"
    return runningQubes.map(function (q) { return q.name }).join(", ")
  }

  // Qubes first, then the actions that stand on their own, as one list so the
  // keyboard cursor walks through both.
  readonly property var rows: {
    var list = []
    for (var i = 0; i < named.length; i++) {
      var q = named[i]
      list.push({kind: "qube", key: q.name, label: q.name, color: q.color,
        detail: q.state === "running" ? "running · open app" : "halted · start", running: q.state === "running"})
    }
    list.push({kind: "action", key: "dispvm", label: "Disposable…"})
    if (runningQubes.length > 0) list.push({kind: "action", key: "stop", label: "Stop a qube…"})
    list.push({kind: "action", key: "create", label: "Create qube…"})
    list.push({kind: "action", key: "template-update", label: "Update template…"})
    return list
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function activate(row, alternate) {
    if (!row || !bar) return
    close()
    if (row.kind === "qube") {
      var verb = alternate ? (row.running ? "stop" : "terminal") : (row.running ? "run" : "start")
      bar.run("qube-menu " + verb + " " + shellQuote(row.key))
    } else {
      bar.run("qube-menu " + row.key)
    }
    settle.kick()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function clampCursor() {
    var count = rows.length
    cursorIndex = count === 0 ? 0 : Math.max(0, Math.min(cursorIndex, count - 1))
  }

  function refresh() {
    if (listProc.running) return
    listProc.collected = ""
    listProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      refresh()
    }
  }

  Process {
    id: listProc
    property string collected: ""
    command: ["bash", "-c", "command -v qube >/dev/null || exit 127; timeout 5 qube list --json 2>/dev/null"]
    running: true
    stdout: SplitParser {
      onRead: function (data) { listProc.collected += String(data) }
    }
    onExited: function (code) {
      root.installed = code !== 127
      if (code !== 0) {
        root.qubes = []
        return
      }
      try {
        root.qubes = JSON.parse(listProc.collected.trim() || "[]")
      } catch (e) {
        root.qubes = []
      }
      root.clampCursor()
    }
  }

  Timer {
    interval: root.pollSeconds * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Starting a qube takes a boot's worth of seconds; look again soon after an
  // action rather than waiting for the next poll.
  Timer {
    id: settle
    interval: 3000
    repeat: true
    property int left: 0
    onTriggered: {
      root.refresh()
      if (--left <= 0) stop()
    }
    function kick() {
      left = 10
      start()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    dimmed: root.runningQubes.length === 0
    tooltipText: "Qubes · " + root.summary

    iconComponent: Component {
      Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.glyphColor
        font.family: root.fontFamily
        font.pixelSize: Style.bar.iconFont
      }
    }

    onPressed: function (b) {
      if (b === Qt.RightButton) root.activate({kind: "action", key: "dispvm"})
      else if (b === Qt.MiddleButton) root.activate({kind: "action", key: "run"})
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        root.cursorIndex += dy
        root.clampCursor()
      }
      onActivateRequested: root.activate(root.rows[root.cursorIndex], false)
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "Qubes"
            meta: root.runningQubes.length + " running · " + root.named.length + " defined"
            detail: ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.runningQubes.length > 0 ? 1.0 : 0.5

            iconComponent: Component {
              Text {
                text: root.glyph
                color: root.glyphColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.installed || root.named.length === 0
            text: !root.installed
              ? "The qube CLI is not on PATH. Put it in ~/.local/bin, then install QEMU and waypipe: omarchy pkg add qemu-base waypipe"
              : "No qubes yet. Build a template once with `qube template create`, then create a qube from here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.installed ? root.rows : []

              Rectangle {
                id: row
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: Style.space(32)
                radius: Style.cornerRadius > 0 ? Style.space(8) : 0
                color: root.cursorActive && root.cursorIndex === index
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                  : "transparent"

                Rectangle {
                  id: swatch
                  visible: row.modelData.kind === "qube"
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(10)
                  height: width
                  radius: width / 2
                  color: row.modelData.running ? row.modelData.color : "transparent"
                  border.width: 2
                  border.color: row.modelData.color || root.dim
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: swatch.visible ? swatch.right : parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: detailText.left
                  anchors.rightMargin: Style.space(8)
                  text: row.modelData.label
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  id: detailText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  text: row.modelData.detail || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onEntered: {
                    root.cursorActive = true
                    root.cursorIndex = row.index
                  }
                  onClicked: function (mouse) {
                    root.activate(row.modelData, mouse.button === Qt.RightButton)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "enter open · right click terminal/stop · esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
