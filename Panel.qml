import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// omaFace in the bar. The mark comes alive while a scan runs (the lock
// screen, sudo, a system prompt), and the panel shows where face unlock is
// used, with a way into its settings. Without omaFace it says how to get it.
// It only reads omaFace's state and runs the omaface command; it never
// installs anything or changes PAM itself.
Panel {
  id: root
  moduleName: "io.github.l0adn9.omaface-bar"
  ipcTarget: "io.github.l0adn9.omaface-bar"

  readonly property string guideUrl: "https://github.com/L0adn9/omaface#readme"
  readonly property string installCommands: "git clone https://github.com/L0adn9/omaface \\\n  ~/.local/src/omaface\ncd ~/.local/src/omaface && ./install.sh"

  // The omaface command's path ("" when it is not installed), and its
  // `status --json`, refreshed when the panel opens and after each scan.
  property string command: ""
  property bool checked: false
  property var status: null
  // The scanner's live state, from the file it keeps in /run/omaface.
  property string scanState: "idle"
  property string copied: ""

  readonly property bool installed: command !== ""
  readonly property bool setUp: installed && status !== null && status.installed === true
  readonly property int faces: setUp && status.appearances ? status.appearances.length : 0
  readonly property bool ready: setUp && status.service === true && faces > 0 && status.lockedOut !== true

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyphMode: scanState === "scanning" || scanState.indexOf("turn-") === 0 ? "scanning"
    : scanState === "success" ? "success"
    : scanState === "failure" ? "failure" : "idle"

  readonly property string summary: {
    if (!checked) return ""
    if (!installed) return "Not installed"
    if (!setUp) return "Installed, not set up yet"
    if (status.service !== true) return "Scanner stopped"
    if (faces === 0) return "No face enrolled yet"
    if (status.lockedOut === true) return "Paused: use your password once"
    return "Ready, " + (status.cameraKind === "webcam" ? "webcam" : "IR camera")
  }

  function refresh() {
    if (!whichProc.running) whichProc.running = true
  }

  // A terminal for the commands that ask questions or for a password.
  function runInTerminal(args) {
    if (bar) bar.run("omarchy-launch-floating-terminal-with-presentation " + args)
    close()
  }

  function openSettings() {
    if (bar) bar.run(bar.shellQuote(command) + " settings")
    close()
  }

  function copy(text, what) {
    if (!bar) return
    bar.run("printf '%s\\n' " + bar.shellQuote(text) + " | wl-copy")
    copied = what
    copiedReset.restart()
  }

  function placeLabel(key) {
    return { lock: "Lock screen", login: "Login screen", sudo: "sudo", polkit: "System prompts" }[key] || key
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Process {
    id: whichProc
    command: ["bash", "-c", "command -v omaface || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.command = String(text || "").trim()
        if (root.command === "") {
          root.status = null
          root.checked = true
        } else if (!statusProc.running) {
          statusProc.running = true
        }
      }
    }
  }

  Process {
    id: statusProc
    command: [root.command, "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.status = JSON.parse(String(text || "null"))
        } catch (e) {
          root.status = null
        }
        root.checked = true
      }
    }
  }

  FileView {
    path: "/run/omaface/status"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.scanState = String(JSON.parse(String(text() || "{}")).state || "idle")
      } catch (e) {
        root.scanState = "idle"
      }
    }
  }

  // The check mark or the shake plays once, then the mark rests; a finished
  // scan may also have changed what the panel shows (a lockout).
  onScanStateChanged: if (scanState === "success" || scanState === "failure" || scanState === "timeout") settle.restart()
  Timer {
    id: settle
    interval: 1600
    onTriggered: {
      root.scanState = "idle"
      root.refresh()
    }
  }

  Timer {
    id: copiedReset
    interval: 1800
    onTriggered: root.copied = ""
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.summary !== "" ? "omaFace: " + root.summary : "omaFace"
    iconComponent: Component {
      Item {
        FaceGlyph {
          anchors.centerIn: parent
          width: Style.space(15)
          height: width
          lineWidth: Math.max(1, width / 12)
          mode: root.glyphMode
          color: root.barForeground
          errorColor: root.urgent
          opacity: root.ready || root.glyphMode !== "idle" ? 1 : 0.45
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton && root.setUp) root.openSettings()
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "omaFace"
          meta: root.summary
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.ready ? 1 : 0.5
          iconComponent: Component {
            FaceGlyph {
              width: Style.font.display
              height: width
              mode: root.glyphMode
              color: root.foreground
              errorColor: root.urgent
            }
          }
        }

        // Set up: where it is used, and the way in.
        Column {
          visible: root.setUp
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "WHERE IT IS USED"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: ["lock", "login", "sudo", "polkit"]
            Item {
              required property string modelData
              readonly property bool on: root.status && root.status.places ? root.status.places[modelData] === true : false
              readonly property bool available: modelData !== "login" || (root.status && root.status.loginSupported === true)
              width: column.width
              implicitHeight: placeName.implicitHeight

              Text {
                id: placeName
                anchors.left: parent.left
                text: root.placeLabel(modelData)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.right: parent.right
                text: !parent.available ? "not available" : parent.on ? "on" : "off"
                color: root.foreground
                opacity: parent.on && parent.available ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Text {
            width: column.width
            wrapMode: Text.WordWrap
            text: root.faces === 0 ? "Add your face in Settings to start."
              : root.faces + " of " + (root.status.maxAppearances || 3) + " appearances enrolled. Your password keeps working everywhere."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            text: root.faces === 0 ? "Add your face" : "Settings"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.openSettings()
          }
        }

        // Installed, never set up for this user.
        Column {
          visible: root.installed && root.checked && !root.setUp
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: column.width
            wrapMode: Text.WordWrap
            text: "omaFace is installed but not switched on. Setup adds it above the password for sudo, system prompts and login, and hands the lock screen to omaFace. It asks for your password once."
            color: root.foreground
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Button {
            text: "Set up omaFace"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.runInTerminal(root.bar.shellQuote(root.command) + " setup")
          }
        }

        // Not installed: how to get it, nothing run on the user's behalf.
        Column {
          visible: root.checked && !root.installed
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: column.width
            wrapMode: Text.WordWrap
            text: "Face unlock for the lock screen, login, sudo and system prompts, with an IR camera or the webcam. Your password keeps working everywhere. Install it from a terminal:"
            color: root.foreground
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Rectangle {
            width: column.width
            implicitHeight: commands.implicitHeight + Style.space(16)
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

            Text {
              id: commands
              anchors.fill: parent
              anchors.margins: Style.space(8)
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: root.installCommands
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: root.copied === "commands" ? "Copied" : "Copy commands"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.copy(root.installCommands, "commands")
            }

            Button {
              text: "Read the guide"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                Qt.openUrlExternally(root.guideUrl)
                root.close()
              }
            }
          }
        }
      }
    }
  }
}
