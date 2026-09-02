import QtQuick
import Quickshell
import Quickshell.Io

// Headless service: watches the active Omarchy theme's colors.toml and runs
// sync.py, which renders Zen's userChrome.css and restarts Zen only when the
// rendered CSS actually changed. Also runs once on startup, which makes
// enabling the plugin self-installing (profile wiring is idempotent).
//
// The FileView never loads the file's content (preload: false, text() unused):
// it is only a change signal, so an unexpected file type can't block the
// shell. All reads and validation happen in sync.py with descriptor-bound
// file I/O.
Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string syncScript: {
    const url = Qt.resolvedUrl("sync.py").toString()
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  property bool syncPending: false

  readonly property string colorsPath: root.home + "/.local/state/omarchy/current/theme/colors.toml"

  // Theme switches replace colors.toml, which kills the underlying file
  // watch. Re-arm it by resetting the path; with preload false this never
  // reads the file's content.
  function rearmWatch() {
    colorsFile.path = ""
    colorsFile.path = root.colorsPath
  }

  property FileView colorsFile: FileView {
    path: root.colorsPath
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: syncTimer.restart()
  }

  // Debounce: a theme switch touches the state dir several times in a row.
  // By the time the timer fires the new colors.toml is in place, so this is
  // also the safe moment to re-arm the watch.
  Timer {
    id: syncTimer
    interval: 800
    repeat: false
    onTriggered: {
      root.rearmWatch()
      if (syncProcess.running) {
        root.syncPending = true
      } else {
        syncProcess.running = true
      }
    }
  }

  Process {
    id: syncProcess
    command: ["python3", root.syncScript]
    onExited: {
      if (root.syncPending) {
        root.syncPending = false
        syncTimer.restart()
      }
    }
  }

  Component.onCompleted: syncTimer.restart()
}
