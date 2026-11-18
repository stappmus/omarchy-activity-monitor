import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Owns the guarded process-action lifecycle. The visual panel decides when to
// offer an action; this controller owns its immutable identity, helper process,
// result interpretation, and transient status.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  property bool active: false

  readonly property string signalHelperPath: decodeURIComponent(
    String(Qt.resolvedUrl("process-signal")).replace("file://", ""))

  readonly property string windowHelperPath: decodeURIComponent(
    String(Qt.resolvedUrl("app-windows")).replace("file://", ""))

  readonly property string currentUser: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property bool confirmationOpen: _pendingAction !== null
  readonly property var pendingAction: _pendingAction
  readonly property bool running: signalProc.running
  readonly property string status: _status
  readonly property bool failed: _failed

  property var _pendingAction: null
  property var _activeAction: null
  property string _status: ""
  property bool _failed: false

  signal confirmationRequested()
  signal focusRequested()
  signal refreshRequested()

  property var windowsByProcess: ({})
  Process {
    id: windowReader
    command: [root.windowHelperPath, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.windowsByProcess = JSON.parse(text) }
        catch (e) { root.windowsByProcess = ({}) }
      }
    }
  }

  readonly property bool readingWindows: windowReader.running

  function refreshWindows() {
    windowsByProcess = ({})
    windowReader.running = true
  }

  function blockReason(process) {
    return Model.processActionBlockReason(process, currentUser)
  }

  function request(process, directClose, window) {
    if (!active || !enabled || running) return false

    var reason = blockReason(process)
    if (reason !== "") {
      _pendingAction = null
      _failed = true
      _status = reason
      clearStatus.restart()
      focusRequested()
      return false
    }

    _failed = false
    _status = ""
    clearStatus.stop()
    if (directClose) {
      _activeAction = { name: window ? (window.title || window.app) : process.name, directClose: true }
      _status = "Closing " + _activeAction.name + "…"
      signalProc.command = [windowHelperPath, "close", String(process.pid), String(process.startTicks),
                            window ? String(window.id) : ""]
      signalProc.running = true
      return true
    }
    _pendingAction = {
      pid: Number(process.pid),
      startTicks: Number(process.startTicks),
      name: String(process.name || "process"),
      user: String(process.user || ""),
      action: "APP_TERM"
    }
    confirmationRequested()
    focusRequested()
    return true
  }

  function cancel() {
    _pendingAction = null
    focusRequested()
  }

  function confirm() {
    if (!_pendingAction || running) {
      cancel()
      return
    }

    _activeAction = _pendingAction
    _pendingAction = null
    _failed = false
    _status = "Ending " + _activeAction.name + "…"
    signalProc.command = [
      signalHelperPath,
      _activeAction.action,
      String(_activeAction.pid),
      String(_activeAction.startTicks)
    ]
    signalProc.running = true
  }

  function finish(exitCode) {
    var action = _activeAction
    var error = String(signalStderr.text || "").trim().split("\n")[0]
    var result = String(signalStdout.text || "").trim().split(/\s+/)
    var disposition = result.length ? result[result.length - 1] : ""

    if (active) {
      if (exitCode === 0) {
        _failed = false
        if (!action) _status = "App ended"
        else if (action.directClose) _status = "Close requested for " + action.name
        else if (disposition === "graceful") _status = "Closed " + action.name
        else if (disposition === "escalated") _status = "Force-closed " + action.name
        else _status = "Ended " + action.name
      } else {
        _failed = true
        _status = error || "Could not end the selected app"
      }
    }

    _activeAction = null
    if (!active) return
    refreshRequested()
    clearStatus.restart()
    focusRequested()
  }

  function clearSessionState() {
    _pendingAction = null
    _status = ""
    _failed = false
    clearStatus.stop()
  }

  onActiveChanged: if (!active) clearSessionState()
  onEnabledChanged: if (!enabled) _pendingAction = null

  Process {
    id: signalProc
    stdout: StdioCollector {
      id: signalStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: signalStderr
      waitForEnd: true
    }
    onExited: function(exitCode) { root.finish(exitCode) }
  }

  Timer {
    id: clearStatus
    interval: 4000
    repeat: false
    onTriggered: {
      root._status = ""
      root._failed = false
    }
  }
}
