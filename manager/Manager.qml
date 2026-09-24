import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Qubes Manager: every qube, its state and label, the apps its template ships,
// and forms for new qubes and templates. Summoned from Setup › Qubes, the bar
// panel, or: omarchy-shell shell summon io.github.achevalier-dev.qubes-manager '{}'
//
// Reads go through `qube list --json`, `qube template list` and `qube apps`.
// Quick changes (create, label, delete) run here so their errors can be shown;
// anything that boots a VM is handed to qube-menu or a terminal, detached, so
// closing this window never interrupts it.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var qubes: []
  property var templates: []
  property var apps: []
  property string selected: ""
  property string mode: "qube"   // qube | create | templates
  property string message: ""
  property bool messageIsError: false
  property string armedDelete: ""

  property string newLabel: "blue"
  property string newNet: "user"
  property string newMem: "2G"
  property string newTemplate: ""

  readonly property var labels: [
    {name: "red", color: "#e06c75"}, {name: "orange", color: "#e5a050"},
    {name: "yellow", color: "#e5c07b"}, {name: "green", color: "#98c379"},
    {name: "gray", color: "#8b929e"}, {name: "blue", color: "#61afef"},
    {name: "purple", color: "#c678dd"}, {name: "black", color: "#3b3f4a"}
  ]

  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color bg: Color.popups.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family

  readonly property var named: qubes.filter(function (q) { return !q.disposable })
  readonly property var current: {
    for (var i = 0; i < named.length; i++) if (named[i].name === selected) return named[i]
    return null
  }
  readonly property bool currentRunning: current !== null && current.state === "running"

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (payload.qube) { selected = String(payload.qube); mode = "qube" }
    if (payload.mode) mode = String(payload.mode)
    message = ""
    armedDelete = ""
    opened = true
    refresh()
    Qt.callLater(function () { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
    armedDelete = ""
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "io.github.achevalier-dev.qubes-manager")
    else close()
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!templateProc.running) templateProc.running = true
  }

  function loadApps() {
    apps = []
    if (!selected) return
    appsProc.command = ["qube", "apps", selected]
    appsProc.running = true
  }

  function say(text, isError) {
    message = text
    messageIsError = !!isError
  }

  // Quick, fallible changes: run here, report stderr in the window.
  function change(args, done) {
    if (actionProc.running) return
    actionProc.done = done || ""
    actionProc.command = ["qube"].concat(args)
    actionProc.running = true
  }

  function detached(args, note) {
    Quickshell.execDetached(args)
    if (note) say(note, false)
    settle.kick()
  }

  function terminal(command) {
    detached(["omarchy-launch-floating-terminal-with-presentation", command])
  }

  function select(name) {
    selected = name
    mode = "qube"
    armedDelete = ""
    message = ""
    loadApps()
  }

  function colorOf(label) {
    for (var i = 0; i < labels.length; i++) if (labels[i].name === label) return labels[i].color
    return dim
  }

  function createQube(name) {
    name = String(name).trim()
    if (!/^[a-z][a-z0-9-]{0,30}$/.test(name)) {
      say("Names are lowercase letters, digits and dashes, starting with a letter.", true)
      return
    }
    var args = ["create", name, "--label", newLabel, "--net", newNet, "--mem", newMem]
    if (newTemplate) args = args.concat(["--template", newTemplate])
    change(args, "created:" + name)
  }

  Process {
    id: listProc
    command: ["qube", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.qubes = JSON.parse(String(text || "[]").trim() || "[]") } catch (e) { root.qubes = [] }
        if (root.selected === "" && root.named.length > 0) root.select(root.named[0].name)
        if (root.selected !== "" && root.current === null && root.mode === "qube")
          root.selected = root.named.length > 0 ? root.named[0].name : ""
      }
    }
  }

  Process {
    id: templateProc
    command: ["qube", "template", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.templates = String(text || "").split("\n").filter(function (t) { return t !== "" })
        if (root.newTemplate === "" || root.templates.indexOf(root.newTemplate) === -1)
          root.newTemplate = root.templates.length > 0 ? root.templates[0] : ""
      }
    }
  }

  Process {
    id: appsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.apps = String(text || "").split("\n").filter(function (l) { return l.indexOf("\t") > 0 })
          .map(function (l) { var p = l.split("\t"); return {name: p[0], exec: p[1]} })
      }
    }
  }

  Process {
    id: actionProc
    property string done: ""
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (code) {
      var err = String(actionErr.text || "").trim().split("\n").pop().replace(/^qube: /, "")
      if (code !== 0) {
        root.say(err || "qube failed", true)
      } else if (actionProc.done.indexOf("created:") === 0) {
        var name = actionProc.done.slice(8)
        root.say("Created " + name + ".", false)
        root.select(name)
        nameField.text = ""
      } else if (actionProc.done === "deleted") {
        root.say("Deleted.", false)
        root.selected = ""
      } else if (err) {
        root.say(err, false)
      }
      root.refresh()
    }
  }

  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // Boots take a while; look often for a bit after one is kicked off.
  Timer {
    id: settle
    interval: 1000
    repeat: true
    property int left: 0
    onTriggered: { root.refresh(); if (--left <= 0) stop() }
    function kick() { left = 30; start() }
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  component SectionLabel: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.5
  }

  component Swatches: Row {
    id: swatches
    property string value: ""
    signal picked(string label)
    spacing: Style.space(8)
    Repeater {
      model: root.labels
      Rectangle {
        required property var modelData
        width: Style.space(22)
        height: width
        radius: width / 2
        color: modelData.color
        border.width: swatches.value === modelData.name ? Style.space(3) : 0
        border.color: root.fg
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: swatches.picked(parent.modelData.name)
        }
      }
    }
  }

  // ── window ────────────────────────────────────────────────────────────────

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-qubes-manager"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(32), Style.space(860))
        height: Math.min(parent.height - Style.space(32), Style.space(560))
        color: root.bg
        radius: Style.cornerRadius
        border.width: Math.max(1, Style.space(2))
        border.color: Color.popups.border

        MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.panelGap

          // Header
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            Text {
              text: "󰆧"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
            Text {
              text: "Qubes"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: root.qubes.filter(function (q) { return q.state === "running" }).length + " running"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Item { Layout.fillWidth: true }
            Button {
              text: "Disposable terminal"
              iconText: "󰈸"
              bordered: true
              onClicked: root.detached(["qube", "dispvm", "foot"], "Starting a disposable terminal…")
            }
            Button {
              text: "Disposable browser"
              iconText: "󰈸"
              bordered: true
              onClicked: root.detached(["qube", "dispvm", "firefox"], "Starting a disposable browser…")
            }
            Button {
              iconText: "󰅖"
              tooltipText: "Close (Esc)"
              onClicked: root.dismiss()
            }
          }

          Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15) }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.panelGap

            // Qube list
            ColumnLayout {
              Layout.preferredWidth: Style.space(220)
              Layout.fillHeight: true
              spacing: Style.space(6)

              SectionLabel { text: "QUBES" }

              ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Style.space(2)
                model: root.named

                delegate: Rectangle {
                  id: qubeRow
                  required property var modelData
                  readonly property bool isSelected: root.mode === "qube" && root.selected === modelData.name
                  width: ListView.view.width
                  implicitHeight: Style.space(34)
                  radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                  color: isSelected ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                    : (rowMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent")

                  Rectangle {
                    id: dot
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(10)
                    height: width
                    radius: width / 2
                    color: qubeRow.modelData.state === "running" ? qubeRow.modelData.color : "transparent"
                    border.width: 2
                    border.color: qubeRow.modelData.color
                  }
                  Text {
                    anchors.left: dot.right
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: qubeRow.modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: qubeRow.modelData.net === "none" ? "offline" : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.select(qubeRow.modelData.name)
                  }
                }
              }

              Text {
                visible: root.named.length === 0
                Layout.fillWidth: true
                text: root.templates.length === 0 ? "No template yet. Start under Templates." : "No qubes yet."
                color: root.dim
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Button {
                Layout.fillWidth: true
                text: "New qube"
                iconText: "󰐕"
                leftAlign: true
                selected: root.mode === "create"
                onClicked: { root.mode = "create"; root.message = "" }
              }
              Button {
                Layout.fillWidth: true
                text: "Templates"
                iconText: "󰏗"
                leftAlign: true
                selected: root.mode === "templates"
                onClicked: { root.mode = "templates"; root.message = "" }
              }
            }

            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15) }

            // Detail
            StackLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              currentIndex: root.mode === "create" ? 1 : (root.mode === "templates" ? 2 : 0)

              // ── one qube ──
              Flickable {
                clip: true
                contentHeight: qubeCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                  width: parent.width
                  visible: root.current === null
                  spacing: Style.space(12)
                  Text {
                    text: root.templates.length === 0 ? "Start with a template" : "No qube selected"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }
                  Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.templates.length === 0
                      ? "A template is the Arch system every qube boots from. Build one once; it takes a few minutes."
                      : "Pick a qube on the left, create one, or open a disposable from the header. Disposables vanish when their app closes."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Button {
                    text: root.templates.length === 0 ? "Create Arch template" : "New qube"
                    iconText: "󰐕"
                    bordered: true
                    onClicked: root.templates.length === 0 ? root.terminal("qube template create arch") : root.mode = "create"
                  }
                }

                ColumnLayout {
                  id: qubeCol
                  width: parent.width
                  spacing: Style.space(14)
                  visible: root.current !== null

                  RowLayout {
                    spacing: Style.space(10)
                    Rectangle {
                      width: Style.space(14); height: width; radius: width / 2
                      color: root.current ? root.current.color : "transparent"
                    }
                    Text {
                      text: root.current ? root.current.name : ""
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.display
                      font.bold: true
                    }
                  }
                  Text {
                    text: root.current
                      ? [root.current.state, root.current.label, "template " + root.current.template,
                         root.current.net === "none" ? "no network" : "online"].join("  ·  ")
                      : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  RowLayout {
                    spacing: Style.space(8)
                    Button {
                      text: root.currentRunning ? "Stop" : "Start"
                      iconText: root.currentRunning ? "󰓛" : "󰐊"
                      bordered: true
                      onClicked: root.detached(["qube-menu", root.currentRunning ? "stop" : "start", root.selected],
                        (root.currentRunning ? "Stopping " : "Starting ") + root.selected + "…")
                    }
                    Button {
                      text: "Terminal"
                      iconText: "󰆍"
                      bordered: true
                      onClicked: root.detached(["qube-menu", "terminal", root.selected], "Opening a terminal in " + root.selected + "…")
                    }
                    Button {
                      text: "Shell"
                      iconText: "󰞷"
                      bordered: true
                      tooltipText: "SSH session, for admin work"
                      onClicked: root.terminal("qube shell " + root.selected)
                    }
                  }

                  SectionLabel { text: "APPS" }
                  Flow {
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    Repeater {
                      model: root.apps
                      Button {
                        required property var modelData
                        text: modelData.name
                        bordered: true
                        tooltipText: modelData.exec
                        onClicked: root.detached(["qube", "run", root.selected].concat(modelData.exec.split(/\s+/).filter(function (w) { return w !== "" })),
                          "Opening " + modelData.name + " in " + root.selected + "…")
                      }
                    }
                  }
                  Text {
                    visible: root.apps.length === 0
                    text: "No apps cached for this template. Update it under Templates."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  SectionLabel { text: "LABEL" }
                  Swatches {
                    value: root.current ? root.current.label : ""
                    onPicked: function (label) { root.change(["label", root.selected, label]) }
                  }

                  SectionLabel { text: "DANGER" }
                  Button {
                    text: root.armedDelete === root.selected ? "Click again to delete " + root.selected + " and its /home" : "Delete qube"
                    iconText: "󰆴"
                    bordered: true
                    foreground: root.armedDelete === root.selected ? Color.urgent : root.fg
                    onClicked: {
                      if (root.armedDelete !== root.selected) { root.armedDelete = root.selected; return }
                      root.armedDelete = ""
                      root.change(["delete", root.selected], "deleted")
                    }
                  }
                }
              }

              // ── new qube ──
              ColumnLayout {
                spacing: Style.space(12)

                Text {
                  text: "New qube"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }

                SectionLabel { text: "NAME" }
                TextField {
                  id: nameField
                  Layout.preferredWidth: Style.space(260)
                  placeholderText: "work"
                  onAccepted: root.createQube(text)
                }

                SectionLabel { text: "LABEL" }
                Swatches {
                  value: root.newLabel
                  onPicked: function (label) { root.newLabel = label }
                }

                SectionLabel { text: "NETWORK" }
                ButtonGroup {
                  options: [{value: "user", label: "Online"}, {value: "none", label: "Offline"}]
                  value: root.newNet
                  onChanged: function (v) { root.newNet = v }
                }

                SectionLabel { text: "MEMORY" }
                ButtonGroup {
                  options: ["1G", "2G", "4G", "8G"]
                  value: root.newMem
                  onChanged: function (v) { root.newMem = v }
                }

                SectionLabel { text: "TEMPLATE"; visible: root.templates.length > 1 }
                ButtonGroup {
                  visible: root.templates.length > 1
                  options: root.templates
                  value: root.newTemplate
                  onChanged: function (v) { root.newTemplate = v }
                }

                Button {
                  text: root.templates.length === 0 ? "Create a template first" : "Create"
                  iconText: "󰐕"
                  bordered: true
                  onClicked: root.templates.length === 0 ? root.mode = "templates" : root.createQube(nameField.text)
                }
                Item { Layout.fillHeight: true }
              }

              // ── templates ──
              ColumnLayout {
                spacing: Style.space(12)

                Text {
                  text: "Templates"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
                Text {
                  Layout.fillWidth: true
                  text: "Every qube boots a fresh copy of its template, so software installed here reaches all of them on their next start. Qubes on a template must be stopped while it is updated."
                  wrapMode: Text.WordWrap
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Repeater {
                  model: root.templates
                  RowLayout {
                    required property string modelData
                    spacing: Style.space(8)
                    Text {
                      Layout.preferredWidth: Style.space(120)
                      text: modelData
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Button {
                      text: "Update"
                      iconText: "󰚰"
                      bordered: true
                      onClicked: root.terminal("qube template update " + modelData)
                    }
                    Button {
                      text: "Install software"
                      iconText: "󰏗"
                      bordered: true
                      tooltipText: "Shell in the template; run sudo pacman -S …"
                      onClicked: root.terminal("qube template shell " + modelData)
                    }
                  }
                }

                Button {
                  visible: root.templates.indexOf("arch") === -1
                  text: "Create Arch template"
                  iconText: "󰐕"
                  bordered: true
                  tooltipText: "Downloads the Arch cloud image and installs waypipe, foot and Firefox. Takes a few minutes."
                  onClicked: root.terminal("qube template create arch")
                }
                Item { Layout.fillHeight: true }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.message !== ""
            text: root.message
            color: root.messageIsError ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
