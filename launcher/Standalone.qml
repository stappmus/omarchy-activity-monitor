import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  Loader {
    id: monitor
    source: "file://" + Quickshell.env("ACTIVITY_MONITOR_PANEL")
    onLoaded: {
      item.standalone = true
      item.settings = item.savedOptions
      if (Quickshell.env("ACTIVITY_MONITOR_START_MODE") === "searchApps") item.openAppSearch()
      else item.openWindow()
    }
    onStatusChanged: if (status === Loader.Error) Qt.exit(1)
  }
  IpcHandler {
    target: "activityWindow"
    function searchApps(): void { if (monitor.item) monitor.item.openAppSearch() }
    function focus(): void { if (monitor.item) monitor.item.focusDetachedWindow() }
  }
}
