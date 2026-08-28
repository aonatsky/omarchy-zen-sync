import QtQuick
import Quickshell
import Quickshell.Io

// Headless service: watches the active Omarchy theme's colors.toml and runs
// sync.sh, which renders Zen's userChrome.css and restarts Zen only when the
// rendered CSS actually changed. Also runs once on shell startup, which makes
// enabling the plugin self-installing (profile wiring is idempotent).
Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string syncScript: Qt.resolvedUrl("sync.sh").toString().replace("file://", "")

  property bool syncPending: false

  property FileView colorsFile: FileView {
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: syncTimer.restart()
    // Theme switches replace the file; route through reload() so the watch
    // re-arms and onLoaded fires with fresh content.
    onFileChanged: reload()
  }

  // Debounce: a theme switch touches the state dir several times in a row.
  Timer {
    id: syncTimer
    interval: 800
    repeat: false
    onTriggered: {
      if (syncProcess.running) {
        root.syncPending = true
      } else {
        syncProcess.running = true
      }
    }
  }

  Process {
    id: syncProcess
    command: ["bash", root.syncScript]
    onExited: {
      if (root.syncPending) {
        root.syncPending = false
        syncTimer.restart()
      }
    }
  }
}
