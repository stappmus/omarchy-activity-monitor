import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Owns the Activity panel's sampling lifecycle and derived data. Keeping process I/O,
// framing, watchdogs, and power-reader escalation here leaves Panel.qml focused
// on presentation and interaction.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  property var settings: ({})
  property bool active: false
  property bool background: false
  property bool expanded: false
  property bool processPowerEnabled: true

  // Sampling runs in two tiers. While the panel is open (`active`) every
  // reader is scheduled. While it is closed and the bar graph is enabled
  // (`background`) only the resources reader runs, on a slower cadence, so a
  // closed panel still costs almost nothing.
  readonly property bool sampling: active || background
  property bool _sessionRunning: false

  readonly property string statsHelperPath: decodeURIComponent(
    String(Qt.resolvedUrl("activity-sampler")).replace("file://", ""))
  readonly property string powerHelperPath: decodeURIComponent(
    String(Qt.resolvedUrl("activity-power-reader")).replace("file://", ""))

  readonly property var snapshot: _snapshot
  readonly property var thermalSnapshot: _thermalSnapshot
  readonly property var storageSnapshot: _storageSnapshot
  readonly property var gpuSnapshot: _gpuSnapshot
  readonly property var gpus: _gpus
  readonly property var processPower: _processPower
  readonly property var processes: _processes
  readonly property var metrics: _metrics
  readonly property bool processMetricsReady: _processMetricsReady
  readonly property bool processPowerUnavailable: _processPowerState === powerStateUnavailable
  readonly property string processPowerState: _processPowerState

  readonly property string powerStateStopped: "stopped"
  readonly property string powerStateStartingUser: "starting-user"
  readonly property string powerStateReadyUser: "ready-user"
  readonly property string powerStateSwitchingRoot: "switching-root"
  readonly property string powerStateStartingRoot: "starting-root"
  readonly property string powerStateReadyRoot: "ready-root"
  readonly property string powerStateUnavailable: "unavailable"

  readonly property bool samplingProfileConfigured: String(setting("samplingSpeed", "")).trim() !== ""
  readonly property var samplingProfile: Model.samplingProfile(setting("samplingSpeed", "Balanced"))
  readonly property int refreshInterval: intervalSetting("refreshIntervalMs", 1500, 500, 10000, samplingProfile.resources)
  readonly property int processRefreshInterval: intervalSetting("processRefreshIntervalMs", 3000, 1000, 15000, samplingProfile.processes)
  readonly property int thermalRefreshInterval: intervalSetting("thermalRefreshIntervalMs", 10000, 3000, 60000, samplingProfile.thermals)
  readonly property int gpuRefreshInterval: intervalSetting("gpuRefreshIntervalMs", 2000, 1000, 15000, samplingProfile.gpus)
  readonly property int storageRefreshInterval: intervalSetting("storageRefreshIntervalMs", 30000, 10000, 120000, samplingProfile.storage)
  readonly property int historySamples: boundedSetting("historySamples", 60, 20, 240)
  readonly property int backgroundRefreshInterval: boundedSetting("backgroundRefreshIntervalMs", 3000, 1000, 30000)

  property var _snapshot: Model.emptySnapshot()
  property var _thermalSnapshot: Model.emptyThermalSnapshot()
  property var _storageSnapshot: Model.emptyStorageSnapshot()
  property var _gpuSnapshot: Model.emptyGpuSnapshot()
  property var _gpus: []
  property var _processPower: Model.emptyPower()
  property var _processes: []
  property var _metrics: Model.emptyMetrics()
  property bool _processMetricsReady: false

  property var _previousSnapshot: Model.emptySnapshot()
  property var _previousProcessSnapshot: Model.emptyProcessSnapshot()
  property var _previousProcessPowerSnapshot: Model.emptyPackagePowerSnapshot()
  property var _previousGpuSnapshot: Model.emptyGpuSnapshot()

  property var _statsReaderBuffer: []
  property bool _statsReaderReady: false
  property bool _resourceSamplePending: false
  property bool _processSamplePending: false
  property bool _thermalSamplePending: false
  property bool _gpuSamplePending: false
  property bool _storageSamplePending: false

  property double _resourceDue: 0
  property double _processDue: 0
  property double _thermalDue: 0
  property double _gpuDue: 0
  property double _storageDue: 0

  property var _processPowerBuffer: []
  property bool _processPowerSamplePending: false
  property string _processPowerState: powerStateStopped

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boundedSetting(name, fallback, minimum, maximum) {
    var value = Number(setting(name, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function intervalSetting(name, fallback, minimum, maximum, profileValue) {
    if (samplingProfileConfigured)
      return Math.max(minimum, Math.min(maximum, Number(profileValue) || fallback))
    return boundedSetting(name, fallback, minimum, maximum)
  }

  function nextDeadline(previous, interval, now) {
    if (previous <= 0) return now + interval
    if (previous > now) return previous
    return previous + (Math.floor((now - previous) / interval) + 1) * interval
  }

  function scheduleNextDeadline() {
    deadlineScheduler.stop()
    if (!sampling) return

    var candidates = active
      ? [_resourceDue, _processDue, _thermalDue, _storageDue, expanded ? _gpuDue : 0]
      : [_resourceDue]
    var next = 0
    for (var i = 0; i < candidates.length; i++) {
      var due = Number(candidates[i])
      if (!isFinite(due) || due <= 0) continue
      if (next <= 0 || due < next) next = due
    }
    if (next <= 0) return
    deadlineScheduler.interval = Math.max(1, Math.round(next - Date.now()))
    deadlineScheduler.start()
  }

  function resourceInterval() {
    return active ? refreshInterval : backgroundRefreshInterval
  }

  function resetPeriodicDeadlines() {
    var now = Date.now()
    _resourceDue = now + resourceInterval()
    _processDue = active ? now + processRefreshInterval : 0
    _thermalDue = active ? now + thermalRefreshInterval : 0
    _storageDue = active ? now + storageRefreshInterval : 0
    _gpuDue = active && expanded ? now + gpuRefreshInterval : 0
    scheduleNextDeadline()
  }

  function collectDueSnapshots() {
    if (!sampling) return
    var now = Date.now()
    if (_resourceDue > 0 && _resourceDue <= now + 1) {
      refreshResources()
      _resourceDue = nextDeadline(_resourceDue, resourceInterval(), now)
    }
    if (active) {
      if (_processDue > 0 && _processDue <= now + 1) {
        refreshProcessCycle()
        _processDue = nextDeadline(_processDue, processRefreshInterval, now)
      }
      if (_thermalDue > 0 && _thermalDue <= now + 1) {
        refreshThermals()
        _thermalDue = nextDeadline(_thermalDue, thermalRefreshInterval, now)
      }
      if (_storageDue > 0 && _storageDue <= now + 1) {
        refreshStorage()
        _storageDue = nextDeadline(_storageDue, storageRefreshInterval, now)
      }
      if (expanded && _gpuDue > 0 && _gpuDue <= now + 1) {
        refreshGpus()
        _gpuDue = nextDeadline(_gpuDue, gpuRefreshInterval, now)
      }
    }
    scheduleNextDeadline()
  }

  function statsPending(kind) {
    if (kind === "resources") return _resourceSamplePending
    if (kind === "processes") return _processSamplePending
    if (kind === "thermals") return _thermalSamplePending
    if (kind === "gpus") return _gpuSamplePending
    if (kind === "storage") return _storageSamplePending
    return false
  }

  function anyStatsPending() {
    return _resourceSamplePending
      || _processSamplePending
      || _thermalSamplePending
      || _gpuSamplePending
      || _storageSamplePending
  }

  function setStatsPending(kind, value) {
    if (kind === "resources") _resourceSamplePending = value
    else if (kind === "processes") _processSamplePending = value
    else if (kind === "thermals") _thermalSamplePending = value
    else if (kind === "gpus") _gpuSamplePending = value
    else if (kind === "storage") _storageSamplePending = value
  }

  function resetStatsReaderState() {
    _statsReaderReady = false
    _statsReaderBuffer = []
    _resourceSamplePending = false
    _processSamplePending = false
    _thermalSamplePending = false
    _gpuSamplePending = false
    _storageSamplePending = false
    statsReaderWatchdog.stop()
  }

  function startStatsReader() {
    if (!sampling || statsReaderProc.running) return
    _statsReaderReady = false
    _statsReaderBuffer = []
    statsReaderProc.running = true
  }

  function sendStatsRequest(kind) {
    if (!sampling || statsPending(kind)) return
    setStatsPending(kind, true)
    statsReaderWatchdog.restart()
    if (!statsReaderProc.running) startStatsReader()
    if (_statsReaderReady) statsReaderProc.write(kind + "\n")
  }

  function sendPendingStatsRequests() {
    if (!_statsReaderReady) return
    if (_resourceSamplePending) statsReaderProc.write("resources\n")
    if (_processSamplePending) statsReaderProc.write("processes\n")
    if (_thermalSamplePending) statsReaderProc.write("thermals\n")
    if (_gpuSamplePending) statsReaderProc.write("gpus\n")
    if (_storageSamplePending) statsReaderProc.write("storage\n")
  }

  function refreshResources() {
    sendStatsRequest("resources")
  }

  function refreshProcesses() {
    sendStatsRequest("processes")
  }

  function refreshThermals() {
    sendStatsRequest("thermals")
  }

  function refreshGpus() {
    if (expanded) sendStatsRequest("gpus")
  }

  function refreshStorage() {
    sendStatsRequest("storage")
  }

  function consumeStatsReaderLine(line) {
    var value = String(line || "")
    if (value.indexOf("snapshot-end\t") !== 0) {
      _statsReaderBuffer.push(value)
      return
    }

    var kind = value.slice("snapshot-end\t".length)
    var raw = _statsReaderBuffer.join("\n")
    _statsReaderBuffer = []
    setStatsPending(kind, false)
    if (anyStatsPending()) statsReaderWatchdog.restart()
    else statsReaderWatchdog.stop()
    if (kind === "resources") consumeSnapshot(raw)
    else if (kind === "processes") consumeProcesses(raw)
    else if (kind === "thermals") consumeThermals(raw)
    else if (kind === "gpus") consumeGpus(raw)
    else if (kind === "storage") consumeStorage(raw)
  }

  function processPowerUsesUserReader() {
    return _processPowerState === powerStateStartingUser
      || _processPowerState === powerStateReadyUser
  }

  function processPowerReaderReady() {
    return _processPowerState === powerStateReadyUser
      || _processPowerState === powerStateReadyRoot
  }

  function startProcessPowerReader() {
    if (!active || !expanded || !processPowerEnabled
        || processPowerUnavailable || processPowerProc.running) return

    var useRoot = _processPowerState === powerStateSwitchingRoot
    _processPowerBuffer = []
    _processPowerState = useRoot ? powerStateStartingRoot : powerStateStartingUser
    processPowerProc.command = useRoot
      ? [powerHelperPath]
      : [statsHelperPath, "--activity-process-power-reader"]
    processPowerProc.running = true
  }

  function requestProcessPowerSample() {
    if (!active || !expanded || !processPowerEnabled
        || processPowerUnavailable || _processPowerSamplePending) return
    _processPowerSamplePending = true
    processPowerWatchdog.restart()
    if (!processPowerProc.running) startProcessPowerReader()
    if (processPowerReaderReady()) processPowerProc.write("sample\n")
  }

  function stopProcessPowerReader() {
    _processPowerState = powerStateStopped
    _processPowerSamplePending = false
    _processPowerBuffer = []
    processPowerWatchdog.stop()
    if (processPowerProc.running) processPowerProc.running = false
  }

  function consumeProcessPowerLine(line) {
    var value = String(line || "")
    if (value !== "snapshot-end\tpower") {
      _processPowerBuffer.push(value)
      return
    }

    var raw = _processPowerBuffer.join("\n")
    _processPowerBuffer = []
    _processPowerSamplePending = false
    processPowerWatchdog.stop()
    consumeProcessPower(raw)
  }

  function refreshProcessCycle() {
    if (expanded && processPowerEnabled && !processPowerUnavailable) requestProcessPowerSample()
    else refreshProcesses()
  }

  function refresh() {
    refreshResources()
    if (!active) return
    refreshProcessCycle()
    refreshThermals()
    refreshGpus()
    refreshStorage()
  }

  function consumeSnapshot(raw) {
    var next = Model.parseSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    if (Model.sameTopology(_snapshot.topology, next.topology))
      next.topology = _snapshot.topology
    if (_previousSnapshot.sample <= 0) {
      _metrics = Model.baselineMetrics(next, metrics)
      _previousSnapshot = next
      _snapshot = next
      if (sampling) resourceWarmup.restart()
      return
    }
    _metrics = Model.nextMetrics(_previousSnapshot, next, metrics, historySamples)
    _previousSnapshot = next
    _snapshot = next
  }

  function consumeThermals(raw) {
    var next = Model.parseThermalSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    _thermalSnapshot = next
  }

  function consumeStorage(raw) {
    var next = Model.parseStorageSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    _storageSnapshot = next
  }

  function consumeGpus(raw) {
    if (!expanded) return
    var next = Model.parseGpuSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    if (_previousGpuSnapshot.sample <= 0) {
      if (_gpus.length === 0) _gpus = Model.nextGpus(_previousGpuSnapshot, next)
      _previousGpuSnapshot = next
      _gpuSnapshot = next
      if (active) gpuWarmup.restart()
      return
    }
    _gpus = Model.nextGpus(_previousGpuSnapshot, next)
    _previousGpuSnapshot = next
    _gpuSnapshot = next
  }

  function consumeProcessPower(raw) {
    if (!expanded || !processPowerEnabled) return
    var next = Model.parsePackagePowerSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0 || !Model.packageEnergyReadable(next)) {
      rejectProcessPowerSample()
      return
    }

    var needsWarmup = _previousProcessPowerSnapshot.sample <= 0
    _processPower = Model.nextPackagePower(_previousProcessPowerSnapshot, next)
    _previousProcessPowerSnapshot = next
    if (needsWarmup && active) powerWarmup.restart()
    refreshProcesses()
  }

  function rejectProcessPowerSample() {
    var retryAsRoot = processPowerUsesUserReader()
    if (retryAsRoot) {
      resetProcessPowerMeasurement()
      _processPowerState = powerStateSwitchingRoot
    } else {
      markProcessPowerUnavailable()
      refreshProcesses()
    }
    if (processPowerProc.running) processPowerProc.running = false
  }

  function consumeProcesses(raw) {
    var next = Model.parseProcessSnapshot(raw)
    if (next.schema !== 1 || next.sample <= 0) return
    if (_previousProcessSnapshot.sample <= 0) {
      _previousProcessSnapshot = next
      if (active) processWarmup.restart()
      return
    }
    var busyDelta = Model.processSystemBusyDelta(_previousProcessSnapshot, next)
    var nextProcesses = Model.nextProcesses(
      _previousProcessSnapshot,
      next,
      snapshot.memory.total
    )
    _processes = Model.estimateProcessPower(
      nextProcesses,
      processPower.available ? processPower.watts : -1,
      busyDelta
    )
    _previousProcessSnapshot = next
    _processMetricsReady = true
  }

  function resetProcessPowerMeasurement() {
    _previousProcessPowerSnapshot = Model.emptyPackagePowerSnapshot()
    _processPower = Model.emptyPower()
    _processes = Model.estimateProcessPower(processes, -1, -1)
  }

  function resetGpuMeasurement() {
    _previousGpuSnapshot = Model.emptyGpuSnapshot()
  }

  function markProcessPowerUnavailable() {
    _processPowerState = powerStateUnavailable
    resetProcessPowerMeasurement()
  }

  function resetSessionSampling() {
    _previousSnapshot = Model.emptySnapshot()
    _previousProcessSnapshot = Model.emptyProcessSnapshot()
    _previousProcessPowerSnapshot = Model.emptyPackagePowerSnapshot()
    _previousGpuSnapshot = Model.emptyGpuSnapshot()
    resetProcessPowerMeasurement()
    resetStatsReaderState()
    _processPowerBuffer = []
    _processPowerSamplePending = false
    _processPowerState = powerStateStopped
  }

  function startSession() {
    resetSessionSampling()
    refresh()
    resetPeriodicDeadlines()
  }

  function stopSession() {
    deadlineScheduler.stop()
    resetStatsReaderState()
    if (statsReaderProc.running) statsReaderProc.running = false
    stopProcessPowerReader()
    resourceWarmup.stop()
    processWarmup.stop()
    gpuWarmup.stop()
    powerWarmup.stop()
    statsReaderRetry.stop()
  }

  // Start/stop on the tier, not on a transition: with the bar graph enabled
  // `sampling` is already true when the component is created, so relying on the
  // change signal alone would never open the session.
  function syncSession() {
    if (sampling && !_sessionRunning) {
      _sessionRunning = true
      startSession()
    } else if (!sampling && _sessionRunning) {
      _sessionRunning = false
      stopSession()
    }
  }

  Component.onCompleted: syncSession()

  onSamplingChanged: syncSession()

  // Opening or closing the panel while the background tier keeps the session
  // alive swaps cadences in place. History survives, so the bar graph does not
  // blank out on every open.
  onActiveChanged: {
    if (!_sessionRunning) return
    if (active) refresh()
    resetPeriodicDeadlines()
  }

  onExpandedChanged: {
    if (!expanded) {
      stopProcessPowerReader()
      resetProcessPowerMeasurement()
      resetGpuMeasurement()
      _gpuDue = 0
      scheduleNextDeadline()
    } else if (active) {
      if (processPowerEnabled)
        _previousProcessPowerSnapshot = Model.emptyPackagePowerSnapshot()
      _previousGpuSnapshot = Model.emptyGpuSnapshot()
      refreshProcessCycle()
      refreshGpus()
      _gpuDue = Date.now() + gpuRefreshInterval
      scheduleNextDeadline()
    }
  }

  onProcessPowerEnabledChanged: {
    if (!processPowerEnabled) {
      stopProcessPowerReader()
      resetProcessPowerMeasurement()
      if (active) refreshProcesses()
    } else if (active && expanded) {
      _previousProcessPowerSnapshot = Model.emptyPackagePowerSnapshot()
      refreshProcessCycle()
    }
  }

  onRefreshIntervalChanged: if (active) resetPeriodicDeadlines()
  onBackgroundRefreshIntervalChanged: if (_sessionRunning && !active) resetPeriodicDeadlines()
  onProcessRefreshIntervalChanged: if (active) resetPeriodicDeadlines()
  onThermalRefreshIntervalChanged: if (active) resetPeriodicDeadlines()
  onGpuRefreshIntervalChanged: if (active) resetPeriodicDeadlines()
  onStorageRefreshIntervalChanged: if (active) resetPeriodicDeadlines()

  Process {
    id: statsReaderProc
    command: [root.statsHelperPath, "--activity-reader"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.consumeStatsReaderLine(line) }
    }
    onStarted: {
      root._statsReaderReady = true
      root.sendPendingStatsRequests()
    }
    onExited: {
      root.resetStatsReaderState()
      if (root.sampling) statsReaderRetry.restart()
    }
  }

  Process {
    id: processPowerProc
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.consumeProcessPowerLine(line) }
    }
    onStarted: {
      if (!root.active || !root.expanded || !root.processPowerEnabled) {
        root.stopProcessPowerReader()
        return
      }
      if (root._processPowerState === root.powerStateStartingUser)
        root._processPowerState = root.powerStateReadyUser
      else if (root._processPowerState === root.powerStateStartingRoot)
        root._processPowerState = root.powerStateReadyRoot
      else {
        root.stopProcessPowerReader()
        return
      }
      if (root._processPowerSamplePending) processPowerProc.write("sample\n")
    }
    onExited: {
      var exitedState = root._processPowerState
      root._processPowerSamplePending = false
      root._processPowerBuffer = []
      processPowerWatchdog.stop()

      if (!root.active || !root.expanded || !root.processPowerEnabled) {
        root._processPowerState = root.powerStateStopped
        return
      }
      if (exitedState === root.powerStateStopped) {
        root._processPowerState = root.powerStateStopped
        Qt.callLater(function() { root.requestProcessPowerSample() })
        return
      }
      if (exitedState === root.powerStateUnavailable) return

      if (exitedState === root.powerStateSwitchingRoot
          || exitedState === root.powerStateStartingUser
          || exitedState === root.powerStateReadyUser) {
        root._processPowerState = root.powerStateSwitchingRoot
        Qt.callLater(function() { root.requestProcessPowerSample() })
        return
      }

      root.markProcessPowerUnavailable()
      Qt.callLater(function() { root.refreshProcesses() })
    }
  }

  Timer {
    id: statsReaderRetry
    interval: 250
    repeat: false
    onTriggered: if (root.sampling) root.refresh()
  }

  Timer {
    id: resourceWarmup
    interval: 300
    repeat: false
    onTriggered: if (root.sampling) root.refreshResources()
  }

  Timer {
    id: processWarmup
    interval: 300
    repeat: false
    onTriggered: if (root.active) root.refreshProcesses()
  }

  Timer {
    id: gpuWarmup
    interval: 300
    repeat: false
    onTriggered: if (root.active && root.expanded) root.refreshGpus()
  }

  Timer {
    id: powerWarmup
    interval: 300
    repeat: false
    onTriggered: if (root.active && root.expanded && root.processPowerEnabled)
      root.requestProcessPowerSample()
  }

  Timer {
    id: statsReaderWatchdog
    interval: 5000
    repeat: false
    onTriggered: {
      root._statsReaderReady = false
      if (statsReaderProc.running) statsReaderProc.running = false
    }
  }

  Timer {
    id: processPowerWatchdog
    interval: 5000
    repeat: false
    onTriggered: if (processPowerProc.running) processPowerProc.running = false
  }

  Timer {
    id: deadlineScheduler
    repeat: false
    onTriggered: root.collectDueSnapshots()
  }
}
