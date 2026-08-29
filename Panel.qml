import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "stappmus.activity-monitor"
  ipcTarget: "stappmus.activity-monitor"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Bar orientation is lifted off the host the same way Ui/BarWidget does it.
  readonly property bool vertical: bar ? bar.vertical : false

  property bool expanded: false
  property bool settingsOpen: false
  property bool settingsControlActive: false
  property bool hintsVisible: false
  property bool cursorActive: false
  property int selectedProcessIndex: 0
  property string selectedProcessKey: ""
  property string processQuery: ""
  property string sortKey: "cpu"
  property bool sortAscending: false
  property Item searchField: null
  property var processViewport: null

  readonly property color foreground: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Color.muted
  readonly property var snapshot: activity.snapshot
  readonly property var storageSnapshot: activity.storageSnapshot
  readonly property var gpuSnapshot: activity.gpuSnapshot
  readonly property var gpus: activity.gpus
  readonly property var processPower: activity.processPower
  readonly property var processes: activity.processes
  readonly property var metrics: activity.metrics
  readonly property bool processMetricsReady: activity.processMetricsReady
  readonly property bool processPowerUnavailable: activity.processPowerUnavailable
  readonly property bool hasSnapshot: snapshot.sample > 0
  readonly property int processPidColumnWidth: Style.space(54)
  readonly property int processUserColumnWidth: Style.space(96)
  readonly property int processMetricColumnWidth: Style.space(66)
  readonly property bool showProcessUserColumn: panel.contentWidth >= Style.space(650)
  readonly property bool showProcessTimeColumn: panel.contentWidth >= Style.space(560)
  readonly property string processPowerTooltip: !powerEstimatesEnabled
    ? "Process power estimates are disabled in Activity settings"
    : (processPowerUnavailable
      ? "CPU package energy is unavailable on this system"
    : (processPower.available
        ? "Estimated CPU-time share of measured CPU package power"
        : "Measuring CPU package energy…"))
  readonly property var cpuTemperature: Model.cpuTemperature(activity.thermalSnapshot.temperatures)
  property string selectedDiskId: "all"
  property string selectedStoragePath: ""
  property bool storageSelectionPinned: false
  readonly property var diskItems: Model.diskCycleItems(metrics)
  readonly property var storageItems: Model.storageVolumes(storageSnapshot)
  readonly property var activeDisk: Model.selectDiskItem(diskItems, selectedDiskId)
  readonly property var activeStorage: Model.selectStorageVolume(
    storageItems,
    selectedStoragePath,
    storageSelectionPinned
  )
  readonly property real storageUsedFraction: Model.storageUsedFraction(activeStorage)
  readonly property bool canCycleDisks: diskItems.length > 1
  readonly property bool canCycleStorage: storageItems.length > 1
  readonly property int dieGapCompact: Style.space(2)
  readonly property int dieGapExpanded: Style.space(3)
  readonly property var corePaintSizesCompact: ({
    gap: dieGapCompact,
    domainGap: Style.space(4),
    pad: Style.space(3),
    performance: Style.space(10),
    efficiency: Style.space(7),
    same: Style.space(7)
  })
  readonly property var corePaintSizesExpanded: ({
    gap: dieGapExpanded,
    domainGap: Style.space(6),
    pad: Style.space(5),
    performance: Style.space(16),
    efficiency: Style.space(11),
    same: Style.space(11)
  })
  readonly property var corePaintCompact: expanded
    ? Model.emptyCorePaint()
    : Model.paintCoreLayout(metrics.cores, snapshot.topology, corePaintSizesCompact, "compact")
  readonly property var corePaintExpanded: expanded
    ? Model.paintCoreLayout(metrics.cores, snapshot.topology, corePaintSizesExpanded, "expanded")
    : Model.emptyCorePaint()
  readonly property var sortedProcesses: expanded
    ? Model.filterAndSortProcesses(processes, processQuery, sortKey, sortAscending)
    : []
  readonly property var topProcesses: expanded
    ? []
    : Model.filterAndSortProcesses(processes, "", "cpu", false).slice(0, 3)
  readonly property var selectedProcess: sortedProcesses.length > 0
    ? sortedProcesses[Math.max(0, Math.min(selectedProcessIndex, sortedProcesses.length - 1))]
    : null
  readonly property string samplingSpeedSetting: normalizedSamplingSpeed(setting("samplingSpeed", "Balanced"))
  readonly property int historySamplesSetting: Math.max(20, Math.min(240,
    Math.round(Number(setting("historySamples", 60)) || 60)))
  readonly property string temperatureUnitSetting: normalizedTemperatureUnit(setting("temperatureUnit", "Celsius"))
  readonly property string barGraphSetting: normalizedBarGraph(setting("barGraph", "Off"))
  readonly property bool barGraphEnabled: barGraphSetting !== "Off"
  // 0 means "square": match the bar's thickness so the graph reads as a tile.
  readonly property int barGraphLengthSetting: Math.max(0, Math.min(160,
    Number(setting("barGraphLength", 0)) || 0))
  // Square means "the footprint the icon just gave up", so the graph lines up
  // with every other widget slot on the bar.
  readonly property int barGraphLength: barGraphLengthSetting > 0
    ? barGraphLengthSetting
    : Style.bar.iconSlot
  readonly property var barGraphValues: barGraphSetting === "Memory"
    ? metrics.memoryHistory
    : metrics.cpuHistory
  readonly property real barGraphLatest: barGraphSetting === "Memory" ? metrics.memory : metrics.cpu
  readonly property string barGraphSummary: "CPU " + percentText(metrics.cpu)
    + "  ·  RAM " + percentText(metrics.memory)
  readonly property color barGraphTone: barGraphLatest >= 90 ? root.urgent : root.accent
  readonly property bool showFrequencies: booleanSetting("showFrequencies", true)
  readonly property bool openExpandedByDefault: booleanSetting("openExpanded", false)
  readonly property bool powerEstimatesEnabled: booleanSetting("processPowerEnabled", true)

  function refresh() {
    activity.refresh()
  }

  function setExpanded(value) {
    if (!value && processActions.confirmationOpen) processActions.cancel()
    expanded = value
    cursorActive = false
    selectedProcessIndex = 0
    selectedProcessKey = ""
    if (!expanded) {
      processQuery = ""
      hintsVisible = false
    }
    if (!expanded && sortKey === "power") {
      sortKey = "cpu"
      sortAscending = false
    }
    Qt.callLater(function() {
      if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function setSettingsOpen(value) {
    settingsOpen = value
    settingsControlActive = value
    if (!value) {
      Qt.callLater(function() {
        if (root.opened && keyCatcher) keyCatcher.forceActiveFocus()
      })
    }
  }

  function clampProcessCursor() {
    if (sortedProcesses.length === 0) {
      selectedProcessIndex = 0
      selectedProcessKey = ""
      return
    }
    selectedProcessIndex = Math.max(0, Math.min(selectedProcessIndex, sortedProcesses.length - 1))
    selectedProcessKey = Model.processIdentityKey(sortedProcesses[selectedProcessIndex])
  }

  function restoreProcessCursor() {
    if (sortedProcesses.length === 0) {
      selectedProcessIndex = 0
      selectedProcessKey = ""
      return
    }
    if (selectedProcessKey) {
      for (var i = 0; i < sortedProcesses.length; i++) {
        if (Model.processIdentityKey(sortedProcesses[i]) === selectedProcessKey) {
          selectedProcessIndex = i
          return
        }
      }
    }
    clampProcessCursor()
  }

  function selectProcess(index) {
    if (sortedProcesses.length === 0) return
    selectedProcessIndex = Math.max(0, Math.min(sortedProcesses.length - 1, index))
    selectedProcessKey = Model.processIdentityKey(sortedProcesses[selectedProcessIndex])
  }

  function moveProcess(delta) {
    if (!expanded || sortedProcesses.length === 0) return
    cursorActive = true
    selectProcess(selectedProcessIndex + delta)
    pointerGate.reset()
    Qt.callLater(function() {
      if (root.processViewport && root.processViewport.ensureSelected) root.processViewport.ensureSelected()
    })
  }

  function setSort(nextKey) {
    if (nextKey === "power" && (!powerEstimatesEnabled || !processPower.available)) return
    if (sortKey === nextKey) sortAscending = !sortAscending
    else {
      sortKey = nextKey
      sortAscending = nextKey === "name"
    }
  }

  function cycleSort(delta) {
    var keys = powerEstimatesEnabled && processPower.available
      ? ["cpu", "memory", "power", "pid", "runtime", "name"]
      : ["cpu", "memory", "pid", "runtime", "name"]
    var index = keys.indexOf(sortKey)
    if (index < 0) index = 0
    index = (index + delta + keys.length) % keys.length
    setSort(keys[index])
  }

  function focusSearch() {
    if (!expanded || !searchField) return
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function finishSearch() {
    if (searchField) searchField.focus = false
    keyCatcher.forceActiveFocus()
  }

  function percentText(value) {
    return Math.round(Number(value) || 0) + "%"
  }

  function booleanSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    if (typeof value === "string") {
      var normalized = value.trim().toLowerCase()
      if (normalized === "true" || normalized === "on" || normalized === "yes") return true
      if (normalized === "false" || normalized === "off" || normalized === "no") return false
    }
    return value === undefined || value === null ? fallback : !!value
  }

  function normalizedBarGraph(value) {
    var normalized = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
    if (normalized === "cpu") return "CPU"
    if (normalized === "memory" || normalized === "ram") return "Memory"
    return "Off"
  }

  function normalizedSamplingSpeed(value) {
    return Model.samplingProfile(value).name
  }

  function normalizedTemperatureUnit(value) {
    return String(value || "Celsius").toLowerCase() === "fahrenheit"
      ? "Fahrenheit"
      : "Celsius"
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    var current = root.settings || ({})
    for (var existing in current) if (existing !== "id") entry[existing] = current[existing]
    for (var key in values) entry[key] = values[key]
    if (values.samplingSpeed !== undefined) {
      delete entry.refreshIntervalMs
      delete entry.processRefreshIntervalMs
      delete entry.thermalRefreshIntervalMs
      delete entry.gpuRefreshIntervalMs
      delete entry.storageRefreshIntervalMs
    }

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function resetPreferences() {
    persistSettings({
      samplingSpeed: "Balanced",
      historySamples: 60,
      temperatureUnit: "Celsius",
      showFrequencies: true,
      openExpanded: false,
      processPowerEnabled: true,
      barGraph: "Off",
      barGraphLength: 0
    })
  }

  function swapBadgeText() {
    if (!hasSnapshot || !snapshot.memory.swapTotal) return ""
    return "Swap " + percentText(metrics.swap)
  }

  function memoryBreakdownText() {
    if (!snapshot.memory.total) return "used — · cache —"
    var usedText = Model.formatBytes(snapshot.memory.total - snapshot.memory.available)
    var cacheText = Model.formatBytes(snapshot.memory.cached)
    var usedSeparator = usedText.lastIndexOf(" ")
    var cacheSeparator = cacheText.lastIndexOf(" ")
    var usedUnit = usedSeparator >= 0 ? usedText.slice(usedSeparator + 1) : ""
    var cacheUnit = cacheSeparator >= 0 ? cacheText.slice(cacheSeparator + 1) : ""
    if (usedUnit && usedUnit === cacheUnit) usedText = usedText.slice(0, usedSeparator)
    return "used " + usedText + " · cache " + cacheText
  }

  function cpuCardDetail() {
    var parts = []
    if (cpuTemperature)
      parts.push(Model.formatTemperature(cpuTemperature.value, temperatureUnitSetting))
    if (powerEstimatesEnabled && processPower.available) {
      var watts = measuredPackagePowerText(processPower.watts)
      if (watts) parts.push(watts)
    }
    return parts.join(" · ")
  }

  function frequencyText(value, unit) {
    if (!showFrequencies) return ""
    var frequency = Number(value)
    if (!isFinite(frequency) || frequency < 0) return ""
    return Math.round(frequency) + " " + unit
  }

  function gpuFrequencyText(gpu) {
    if (!showFrequencies) return ""
    var frequency = Number(gpu && gpu.frequencyMHz)
    if (!isFinite(frequency) || frequency < 0) return ""
    if (frequency === 0) return "IDLE"
    return Math.round(frequency) + " MHz"
  }

  function cpuCardLabel() {
    var frequency = frequencyText(snapshot.cpuFrequencyMHz, "MHz")
    return frequency ? "CPU · " + frequency : "CPU"
  }

  function memoryCardLabel() {
    var speed = frequencyText(snapshot.memorySpeedMTs, "MT/s")
    return speed ? "RAM · " + speed : "RAM USAGE"
  }

  function compactGpuName(gpu) {
    var name = String(gpu && gpu.name || "GPU")
    name = name.replace(/^Intel Corporation[ ]*/i, "")
      .replace(/^NVIDIA Corporation[ ]*/i, "")
      .replace(/^NVIDIA[ ]*/i, "")
      .replace(/^Advanced Micro Devices[^]]*\][ ]*/i, "")
      .replace(/^AMD[ ]*/i, "")
    return name || "GPU"
  }

  function gpuHeadingText() {
    var adapters = Array.isArray(gpus) ? gpus : []
    if (adapters.length === 0) return "GPU"
    if (adapters.length > 1) return "GPU · " + adapters.length + " adapters"
    var name = compactGpuName(adapters[0])
    var bracketed = name.match(/\[([^\]]+)\]/g)
    if (bracketed && bracketed.length > 0)
      name = bracketed[bracketed.length - 1].slice(1, -1)
    var frequency = gpuFrequencyText(adapters[0])
    return "GPU · " + name + (frequency ? " · " + frequency : "")
  }

  function gpuUsageText(gpu) {
    var usage = Number(gpu && gpu.usage)
    return isFinite(usage) && usage >= 0 ? Math.round(usage) + "%" : "Sampling"
  }

  function gpuUsageAndClockText(gpu) {
    var usage = gpuUsageText(gpu)
    var frequency = gpuFrequencyText(gpu)
    return frequency ? usage + " · " + frequency : usage
  }

  function gpuMemoryLabel(gpu) {
    if (gpu && gpu.memoryKind === "shared") return "Shared"
    if (gpu && gpu.memoryKind === "vram") return "VRAM"
    return "Memory"
  }

  function gpuMemoryText(gpu) {
    var used = Number(gpu && gpu.memoryUsed)
    var total = Number(gpu && gpu.memoryTotal)
    if (!isFinite(used) || used < 0) return "Unavailable"
    var usedText = Model.formatBytes(used)
    if (!isFinite(total) || total <= 0) return usedText
    var totalText = Model.formatBytes(total)
    var usedSeparator = usedText.lastIndexOf(" ")
    var totalSeparator = totalText.lastIndexOf(" ")
    if (usedSeparator >= 0 && totalSeparator >= 0
        && usedText.slice(usedSeparator + 1) === totalText.slice(totalSeparator + 1))
      usedText = usedText.slice(0, usedSeparator)
    return usedText + " / " + totalText
  }

  function primaryGpuUsage() {
    var adapters = Array.isArray(gpus) ? gpus : []
    if (adapters.length === 0) return -1
    var usage = Number(adapters[0].usage)
    return isFinite(usage) ? usage : -1
  }

  function primaryGpuUsageText() {
    var adapters = Array.isArray(gpus) ? gpus : []
    if (gpuSnapshot.sample <= 0) return "…"
    if (adapters.length === 0) return "—"
    return gpuUsageText(adapters[0])
  }

  function gpuCardDetail() {
    var adapters = Array.isArray(gpus) ? gpus : []
    if (adapters.length === 0)
      return gpuSnapshot.sample <= 0 ? "Detecting" : "Not detected"
    if (adapters.length === 1)
      return gpuMemoryLabel(adapters[0]) + " " + gpuMemoryText(adapters[0])
    var parts = []
    for (var i = 0; i < Math.min(2, adapters.length); i++)
      parts.push(compactGpuName(adapters[i]) + " " + gpuUsageAndClockText(adapters[i]))
    if (adapters.length > 2) parts.push(adapters.length + " adapters")
    return parts.join(" · ")
  }

  function resetDriveSelection() {
    selectedDiskId = "all"
    selectedStoragePath = ""
    storageSelectionPinned = false
  }

  function cycleDisk(delta) {
    var next = Model.cycleItemId(diskItems, selectedDiskId, "id", delta)
    if (next !== "") selectedDiskId = next
  }

  function cycleStorage(delta) {
    var current = activeStorage ? activeStorage.path : selectedStoragePath
    var next = Model.cycleItemId(storageItems, current, "path", delta)
    if (next === "") return
    storageSelectionPinned = true
    selectedStoragePath = next
  }

  function pagerText(items, currentId, key) {
    if (!items || items.length <= 1) return ""
    var wanted = String(currentId || "")
    var index = 0
    for (var i = 0; i < items.length; i++) {
      if (String(items[i][key]) === wanted) {
        index = i
        break
      }
    }
    return (index + 1) + "/" + items.length
  }

  function diskCardLabel() {
    if (!canCycleDisks) return "Disk"
    return activeDisk && activeDisk.id !== "all" ? String(activeDisk.name || "Disk") : "Disk"
  }

  function diskPagerText() {
    return pagerText(diskItems, activeDisk ? activeDisk.id : selectedDiskId, "id")
  }

  function diskCardRead() {
    return activeDisk ? Number(activeDisk.read || 0) : Number(metrics.diskRead || 0)
  }

  function diskCardWrite() {
    return activeDisk ? Number(activeDisk.write || 0) : Number(metrics.diskWrite || 0)
  }

  function diskCardHistory() {
    return activeDisk && Array.isArray(activeDisk.history) ? activeDisk.history : metrics.diskHistory
  }

  function storageCardLabel() {
    if (!canCycleStorage) return "Storage"
    return Model.storageVolumeLabel(activeStorage && activeStorage.path)
  }

  function storagePagerText() {
    return pagerText(storageItems, activeStorage ? activeStorage.path : selectedStoragePath, "path")
  }

  function storageCardValue() {
    if (storageSnapshot.sample <= 0) return "—"
    return activeStorage ? Model.formatBytes(activeStorage.used) : "—"
  }

  function storageCardDetail() {
    if (storageSnapshot.sample <= 0) return ""
    return activeStorage ? Model.formatBytes(activeStorage.available) + " free" : ""
  }

  function pressureColor(value) {
    return Number(value) >= 90 ? urgent : accent
  }

  function estimatedPowerText(value) {
    var watts = Number(value)
    if (!isFinite(watts) || watts < 0) return "—"
    if (watts < 0.005) return "~0 W"
    if (watts < 1) return "~" + watts.toFixed(2) + " W"
    if (watts < 10) return "~" + watts.toFixed(1) + " W"
    return "~" + Math.round(watts) + " W"
  }

  function measuredPackagePowerText(value) {
    var watts = Number(value)
    if (!isFinite(watts) || watts < 0) return ""
    if (watts < 10) return watts.toFixed(2) + " W"
    if (watts < 100) return watts.toFixed(1) + " W"
    return Math.round(watts) + " W"
  }

  function sortLabel(key, label) {
    if (sortKey !== key) return label
    return label + (sortAscending ? " ↑" : " ↓")
  }

  function shortcutHintText() {
    return "e collapse  ·  / search  ·  "
      + (powerEstimatesEnabled ? "c/m/w/p/t/n" : "c/m/p/t/n")
      + " sort  ·  r refresh  ·  s settings  ·  j/k select  ·  x end app"
      + ((canCycleDisks || canCycleStorage) ? "  ·  d/v cycle drives" : "")
      + "  ·  ? hide"
  }

  function selectProcessFromPointer(index, item, mouse) {
    // Pointer events can arrive at the mouse polling rate. Once this row owns
    // the cursor, avoid coordinate mapping and QML property writes until the
    // pointer actually reaches a different row.
    if (cursorActive && selectedProcessIndex === index) return
    if (!pointerGate.moved(item, mouse)) return
    cursorActive = true
    selectProcess(index)
  }

  function processNameColumnWidth(availableWidth, spacing) {
    var fixedWidth = processPidColumnWidth
      + processMetricColumnWidth * (powerEstimatesEnabled ? 3 : 2)
    var gaps = powerEstimatesEnabled ? 4 : 3
    if (showProcessUserColumn) {
      fixedWidth += processUserColumnWidth
      gaps++
    }
    if (showProcessTimeColumn) {
      fixedWidth += processMetricColumnWidth
      gaps++
    }
    return Math.max(0, availableWidth - fixedWidth - spacing * gaps)
  }

  onSortedProcessesChanged: {
    pointerGate.reset()
    restoreProcessCursor()
  }

  onProcessPowerUnavailableChanged: {
    if (processPowerUnavailable && sortKey === "power") {
      sortKey = "cpu"
      sortAscending = false
    }
  }

  onPowerEstimatesEnabledChanged: {
    if (!powerEstimatesEnabled && sortKey === "power") {
      sortKey = "cpu"
      sortAscending = false
    }
  }

  onOpenedChanged: {
    if (opened) {
      expanded = openExpandedByDefault
      settingsOpen = false
      settingsControlActive = false
      cursorActive = false
      selectedProcessIndex = 0
      selectedProcessKey = ""
      processQuery = ""
      hintsVisible = false
      resetDriveSelection()
    } else {
      expanded = false
      settingsOpen = false
      settingsControlActive = false
      hintsVisible = false
      processQuery = ""
      resetDriveSelection()
    }
  }

  ActivityController {
    id: activity
    settings: root.settings
    active: root.opened
    background: root.barGraphEnabled
    expanded: root.expanded
    processPowerEnabled: root.powerEstimatesEnabled
  }

  ProcessActionController {
    id: processActions
    active: root.opened
    enabled: root.expanded && !root.settingsOpen
    onConfirmationRequested: processConfirm.selectedIndex = 0
    onFocusRequested: if (root.opened) keyCatcher.forceActiveFocus()
    onRefreshRequested: activity.refreshProcessCycle()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: root.processViewport
  }

  // The graph rides inside the bar's own button rather than a bare MouseArea:
  // ModuleSlot overlays every widget with its drag-reorder pointer and only
  // dispatches presses to registered click targets, so a plain MouseArea would
  // never see a click. iconComponent is the supported way in, and it brings the
  // tooltip and hover handling with it.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf201"
    iconComponent: root.barGraphEnabled ? barGraphComponent : null
    slotSize: root.barGraphEnabled ? root.barGraphLength : Style.bar.iconSlot
    opticalSize: root.barGraphEnabled ? root.barGraphLength : Style.bar.iconCanvas
    tooltipText: root.barGraphEnabled ? root.barGraphSummary : "Activity"
    onPressed: function(buttonCode) { root.toggle() }
  }

  Component {
    id: barGraphComponent

    // The optical canvas is square at the graph's length; the trace keeps its
    // own bounded height and centers, so a wide graph stays a bar-height strip.
    Item {
      Sparkline {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(Style.space(10), Math.min(parent.height, Style.bar.iconCanvas))
        values: root.barGraphValues
        ceiling: 100
        lineColor: root.barGraphTone
        fillColor: Util.alpha(root.barGraphTone, 0.16)
      }
    }
  }

  // showTooltip takes a snapshot of the text, so a tooltip opened over the
  // graph would otherwise freeze at the reading it had on entry.
  HoverHandler { id: barHover }

  Connections {
    target: root
    function onBarGraphSummaryChanged() {
      if (barHover.hovered && root.bar && root.barGraphEnabled)
        root.bar.showTooltip(button, root.barGraphSummary)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Keep both layouts attached to the invoking widget. When the wider
    // layout reaches a screen edge, KeyboardPanel grows it inward instead of
    // moving the card to the center of the display.
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(root.settingsOpen
      ? Style.space(600)
      : (root.expanded ? Style.space(780) : Style.space(380)))
    // Settings gets its own cap: the preference grid is a row taller than the
    // detail view's budget allows, and a clipped settings page hides controls
    // rather than merely cropping a view. fittedContentHeight still clamps to
    // the space the screen actually has.
    contentHeight: panel.fittedContentHeight(
      contentLoader.item ? contentLoader.item.implicitHeight : Style.space(320),
      root.settingsOpen
        ? Style.space(860)
        : (root.expanded ? Style.space(720) : Style.space(560)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: !!(root.searchField && root.searchField.activeFocus) || root.settingsControlActive

      onMoveRequested: function(dx, dy) {
        if (processActions.confirmationOpen) {
          if (dx !== 0) processConfirm.selectedIndex = processConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        if (!root.expanded || root.settingsOpen) return
        if (dy !== 0) root.moveProcess(dy)
        else if (dx !== 0) root.cycleSort(dx)
      }
      onActivateRequested: {
        if (processActions.confirmationOpen) {
          if (processConfirm.selectedIndex === 0) processActions.cancel()
          else processActions.confirm()
          return
        }
        if (!root.expanded && !root.settingsOpen) root.setExpanded(true)
      }
      onCloseRequested: {
        if (processActions.confirmationOpen) {
          processActions.cancel()
          return
        }
        if (root.settingsOpen) root.setSettingsOpen(false)
        else if (root.expanded) root.setExpanded(false)
        else root.close()
      }
      onDeleteRequested: {
        if (!root.settingsOpen && !processActions.confirmationOpen && root.cursorActive)
          processActions.request(root.selectedProcess)
      }
      onTabRequested: function(direction) {
        if (processActions.confirmationOpen) {
          processConfirm.selectedIndex = processConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        root.switchPanel(direction)
      }
      onTextKey: function(text) {
        if (processActions.confirmationOpen) return
        var raw = String(text || "")
        var key = raw.toLowerCase()
        if (key === "s") root.setSettingsOpen(!root.settingsOpen)
        else if (key === "?") root.hintsVisible = !root.hintsVisible
        else if (root.settingsOpen) return
        else if (key === "e") root.setExpanded(!root.expanded)
        else if (key === "r") root.refresh()
        else if (key === "/" && root.expanded) root.focusSearch()
        else if (key === "d" && root.expanded) root.cycleDisk(raw === "D" ? -1 : 1)
        else if (key === "v" && root.expanded) root.cycleStorage(raw === "V" ? -1 : 1)
        else if (key === "c" && root.expanded) root.setSort("cpu")
        else if (key === "m" && root.expanded) root.setSort("memory")
        else if (key === "w" && root.expanded) root.setSort("power")
        else if (key === "p" && root.expanded) root.setSort("pid")
        else if (key === "t" && root.expanded) root.setSort("runtime")
        else if (key === "n" && root.expanded) root.setSort("name")
      }

      Loader {
        id: contentLoader
        width: parent.width
        sourceComponent: root.settingsOpen
          ? settingsContent
          : (root.expanded ? expandedContent : compactContent)
      }

      ConfirmDialog {
        id: processConfirm
        anchors.fill: parent
        opened: processActions.confirmationOpen
        z: 20
        message: processActions.pendingAction
          ? "End " + processActions.pendingAction.name + "?\nPID " + processActions.pendingAction.pid
            + " · " + processActions.pendingAction.user
            + "\nCloses its verified parent app and windows."
            + "\nForce-closes it after 3 seconds if needed."
          : ""
        confirmText: "End app"
        background: Color.popups.background
        foreground: root.foreground
        selectedText: root.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        cornerRadius: Style.cornerRadius
        onCanceled: processActions.cancel()
        onConfirmed: processActions.confirm()
      }
    }
  }

  Component {
    id: activityIcon

    Text {
      text: "\uf201"
      color: root.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.display
    }
  }

  Component {
    id: compactContent

    Column {
      width: contentLoader.width
      spacing: Style.spacing.panelGap

      ActivityHeader {
        width: parent.width
        expanded: false
      }

      Row {
        width: parent.width
        spacing: Style.spacing.md

        MetricCard {
          width: (parent.width - parent.spacing) / 2
          label: root.cpuCardLabel()
          value: root.hasSnapshot ? root.percentText(root.metrics.cpu) : "—"
          detail: root.cpuCardDetail()
          paint: root.corePaintCompact
          history: root.metrics.cpuHistory
          ceiling: 100
          tone: root.pressureColor(root.metrics.cpu)
        }

        MetricCard {
          width: (parent.width - parent.spacing) / 2
          label: root.memoryCardLabel()
          value: root.hasSnapshot ? root.percentText(root.metrics.memory) : "—"
          detail: root.memoryBreakdownText()
          badge: root.swapBadgeText()
          badgeTone: root.snapshot.memory.swapTotal
            ? root.pressureColor(root.metrics.swap)
            : root.dim
          history: root.metrics.memoryHistory
          ceiling: 100
          tone: root.pressureColor(root.metrics.memory)
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.panelGap

        ActivityPair {
          width: (parent.width - parent.spacing) / 2
          iconText: "\uf019"
          label: "Network"
          value: Model.formatBytes(root.metrics.download, "/s")
          secondary: "\uf093  " + Model.formatBytes(root.metrics.upload, "/s")
        }

        ActivityPair {
          width: (parent.width - parent.spacing) / 2
          iconText: "\uf0a0"
          label: "Disk"
          value: Model.formatBytes(root.metrics.diskRead, "/s")
          secondary: "\uf093  " + Model.formatBytes(root.metrics.diskWrite, "/s")
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          text: "Busiest"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Text {
          visible: root.topProcesses.length === 0
          text: root.processMetricsReady ? "No running processes" : "Sampling process activity…"
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.topProcesses

          ProcessRow {
            required property var modelData
            width: parent.width
            processData: modelData
            compact: true
          }
        }
      }

      Text {
        width: parent.width
        visible: root.hintsVisible
        text: "e details  ·  s settings  ·  ? hide"
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }
  }

  Component {
    id: settingsContent

    Column {
      id: settingsPage

      width: contentLoader.width
      spacing: Style.spacing.panelGap

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || String(event.text || "").toLowerCase() === "s") {
          root.setSettingsOpen(false)
          event.accepted = true
        }
      }
      Component.onCompleted: Qt.callLater(function() { updateSpeedDropdown.forceActiveFocus() })
      Component.onDestruction: root.settingsControlActive = false

      ActivityHeader {
        width: parent.width
        expanded: root.expanded
      }

      DetailSurface {
        width: parent.width
        height: settingsBody.implicitHeight + Style.spacing.xl * 2

        Column {
          id: settingsBody
          x: Style.spacing.xl
          y: Style.spacing.xl
          width: Math.max(1, parent.width - Style.spacing.xl * 2)
          spacing: Style.spacing.md

          PanelSectionHeader {
            text: "Settings"
            foreground: root.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Text {
            width: parent.width
            text: "Changes apply immediately and are saved with your Omarchy bar layout."
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Grid {
            id: preferenceGrid
            width: parent.width
            columns: width >= Style.space(500) ? 2 : 1
            columnSpacing: Style.spacing.xl
            rowSpacing: Style.spacing.md

            Dropdown {
              id: updateSpeedDropdown
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Update speed"
              value: root.samplingSpeedSetting
              options: [
                { value: "Efficient", label: "Efficient · 3 s" },
                { value: "Balanced", label: "Balanced · 1.5 s" },
                { value: "Fast", label: "Fast · 0.75 s" }
              ]
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onChanged: function(next) { root.persistSettings({ samplingSpeed: next }) }
            }

            Dropdown {
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Graph history"
              value: String(root.historySamplesSetting)
              options: [
                { value: "30", label: "Short · 30 samples" },
                { value: "60", label: "Medium · 60 samples" },
                { value: "120", label: "Long · 120 samples" }
              ]
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onChanged: function(next) { root.persistSettings({ historySamples: Number(next) }) }
            }

            Dropdown {
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Temperature"
              value: root.temperatureUnitSetting
              options: ["Celsius", "Fahrenheit"]
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onChanged: function(next) { root.persistSettings({ temperatureUnit: next }) }
            }

            Dropdown {
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Bar graph"
              value: root.barGraphSetting
              options: [
                { value: "Off", label: "Off · panel only" },
                { value: "CPU", label: "CPU · always sampling" },
                { value: "Memory", label: "Memory · always sampling" }
              ]
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onChanged: function(next) { root.persistSettings({ barGraph: next }) }
            }

            Dropdown {
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Bar graph width"
              value: String(root.barGraphLengthSetting)
              options: [
                { value: "0", label: "Square · matches the bar" },
                { value: "44", label: "Wide · 44 px" },
                { value: "72", label: "Wider · 72 px" },
                { value: "110", label: "Widest · 110 px" }
              ]
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onChanged: function(next) { root.persistSettings({ barGraphLength: Number(next) }) }
            }

            Toggle {
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Open detailed view"
              description: "Start with GPU, graphs, and the full process table."
              checked: root.openExpandedByDefault
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.persistSettings({ openExpanded: !root.openExpandedByDefault })
            }

            Toggle {
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Show hardware speeds"
              description: "Include CPU, RAM, and GPU speeds in headings."
              checked: root.showFrequencies
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.persistSettings({ showFrequencies: !root.showFrequencies })
            }

            Toggle {
              width: (preferenceGrid.width
                - preferenceGrid.columnSpacing * (preferenceGrid.columns - 1))
                / preferenceGrid.columns
              label: "Process power estimates"
              description: "Measure package energy in detailed view; disable for less work."
              checked: root.powerEstimatesEnabled
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.persistSettings({ processPowerEnabled: !root.powerEstimatesEnabled })
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.md

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Reset defaults"
          iconText: "\uf2ea"
          foreground: root.dim
          accent: root.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          focusable: true
          bordered: true
          onClicked: root.resetPreferences()
        }

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Done"
          iconText: "\uf00c"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          focusable: true
          bordered: true
          onClicked: root.setSettingsOpen(false)
        }
      }
    }
  }

  Component {
    id: expandedContent

    Column {
      id: expandedPage

      width: contentLoader.width
      spacing: Style.spacing.panelGap

      ActivityHeader {
        width: parent.width
        expanded: true
      }

      Grid {
        id: summaryGrid
        width: parent.width
        columns: width >= Style.space(640) ? 3 : 2
        spacing: Style.spacing.md

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: root.cpuCardLabel()
          value: root.hasSnapshot ? root.percentText(root.metrics.cpu) : "—"
          detail: root.cpuCardDetail()
          paint: root.corePaintExpanded
          tall: true
          history: root.metrics.cpuHistory
          ceiling: 100
          tone: root.pressureColor(root.metrics.cpu)
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: root.memoryCardLabel()
          value: root.hasSnapshot ? root.percentText(root.metrics.memory) : "—"
          detail: root.memoryBreakdownText()
          badge: root.swapBadgeText()
          badgeTone: root.snapshot.memory.swapTotal
            ? root.pressureColor(root.metrics.swap)
            : root.dim
          history: root.metrics.memoryHistory
          ceiling: 100
          tall: true
          tone: root.pressureColor(root.metrics.memory)
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: root.gpuHeadingText()
          value: root.primaryGpuUsageText()
          detail: root.gpuCardDetail()
          tone: root.primaryGpuUsage() >= 0
            ? root.pressureColor(root.primaryGpuUsage())
            : root.accent
          tall: true
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: "Network"
          value: Model.formatBytes(root.metrics.download, "/s")
          detail: "\uf093  " + Model.formatBytes(root.metrics.upload, "/s")
          history: root.metrics.networkHistory
          tone: root.accent
          tall: true
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: root.diskCardLabel()
          badge: root.diskPagerText()
          value: Model.formatBytes(root.diskCardRead(), "/s")
          detail: "\uf093  " + Model.formatBytes(root.diskCardWrite(), "/s")
          history: root.diskCardHistory()
          tone: root.accent
          tall: true
          interactive: root.canCycleDisks
          tooltipText: root.canCycleDisks ? "Next disk" : ""
          onActivated: function(delta) { root.cycleDisk(delta) }
        }

        MetricCard {
          width: (summaryGrid.width - summaryGrid.spacing * (summaryGrid.columns - 1)) / summaryGrid.columns
          label: root.storageCardLabel()
          badge: root.storagePagerText()
          value: root.storageCardValue()
          detail: root.storageCardDetail()
          bar: root.storageSnapshot.sample > 0 ? root.storageUsedFraction : -1
          tone: root.pressureColor(root.storageUsedFraction * 100)
          tall: true
          interactive: root.canCycleStorage
          tooltipText: root.canCycleStorage ? "Next volume" : ""
          onActivated: function(delta) { root.cycleStorage(delta) }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          text: "Processes"
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: Math.max(0, parent.width - parent.children[0].implicitWidth
            - searchBox.width - parent.spacing * 2)
          height: 1
        }

        TextField {
          id: searchBox
          width: Math.max(Style.space(120), Math.min(Style.space(180), parent.width * 0.24))
          placeholderText: "\uf002 Search"
          foreground: root.foreground
          accent: root.accent
          font.pixelSize: Style.font.bodySmall
          verticalPadding: Style.spacing.sm
          onTextChanged: {
            root.processQuery = text
            root.selectedProcessIndex = 0
            root.selectedProcessKey = ""
            root.cursorActive = false
            pointerGate.reset()
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.finishSearch()
              event.accepted = true
            }
          }
          Component.onCompleted: {
            text = root.processQuery
            root.searchField = searchBox
          }
          Component.onDestruction: if (root.searchField === searchBox) root.searchField = null
        }
      }

      ProcessHeader {
        width: parent.width
      }

      Item {
        id: processListHost

        width: parent.width
        height: Math.max(Style.space(120), Style.space(300) - processFooterReserve)
        clip: true

        // Expanded height is capped; shrink the list so the footer stays in-card.
        readonly property int processFooterReserve: {
          var extra = 0
          if (endProcessHost.visible)
            extra += Math.max(0, endProcessHost.implicitHeight) + expandedPage.spacing
          if (expandedHint.visible)
            extra += Math.max(0, expandedHint.implicitHeight) + expandedPage.spacing
          return extra
        }

        ListView {
          id: processList
          anchors.fill: parent
          model: root.sortedProcesses
          spacing: Style.spacing.xxs
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          reuseItems: true

          function ensureSelected() {
            if (root.selectedProcessIndex >= 0 && root.selectedProcessIndex < count)
              positionViewAtIndex(root.selectedProcessIndex, ListView.Contain)
          }

          Component.onCompleted: root.processViewport = processList
          Component.onDestruction: if (root.processViewport === processList) root.processViewport = null

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }

          delegate: ProcessRow {
            required property var modelData
            required property int index
            width: ListView.view.width
            processData: modelData
            rowIndex: index
            compact: false
            selected: root.cursorActive
              && root.selectedProcessKey === Model.processIdentityKey(modelData)
          }
        }

        Text {
          anchors.centerIn: parent
          visible: processList.count === 0
          text: root.processQuery
            ? "No processes match “" + root.processQuery + "”"
            : (root.processMetricsReady ? "No running processes" : "Sampling process activity…")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      Item {
        id: endProcessHost

        width: parent.width
        implicitHeight: endProcessButton.visible ? endProcessButton.implicitHeight : 0
        height: implicitHeight
        visible: endProcessButton.visible

        Button {
          id: endProcessButton
          readonly property string blockReason: processActions.blockReason(root.selectedProcess)
          readonly property bool targetAllowed: blockReason === ""

          visible: root.cursorActive && root.selectedProcess !== null
          enabled: !processActions.running && targetAllowed
          opacity: targetAllowed || processActions.running ? 1 : 0.48
          anchors.right: parent.right
          iconText: "\uf2ed"
          text: processActions.running
            ? "Ending…"
            : (targetAllowed ? "End app" : "Unavailable")
          tooltipText: targetAllowed
            ? "Close the selected app; force-close after 3 seconds if needed"
            : blockReason
          foreground: targetAllowed ? root.urgent : root.dim
          accent: targetAllowed ? root.urgent : root.dim
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.xs
          bordered: true
          onClicked: processActions.request(root.selectedProcess)
        }
      }

      Text {
        id: expandedHint
        width: parent.width
        visible: processActions.status !== "" || root.hintsVisible
        text: processActions.status || root.shortcutHintText()
        textFormat: Text.PlainText
        color: processActions.failed ? root.urgent : root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }
  }

  component ActivityHeader: Row {
    property bool expanded: false

    spacing: Style.spacing.md

    PanelHero {
      id: hero
      width: Math.max(1, parent.width - headerActions.implicitWidth - parent.spacing)
      anchors.verticalCenter: parent.verticalCenter
      iconComponent: activityIcon
      title: "Activity"
      meta: root.hasSnapshot ? Model.formatDuration(root.snapshot.uptime) : "Reading system"
      foreground: root.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    }

    Row {
      id: headerActions
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.sm

      PanelActionButton {
        visible: !root.settingsOpen
        iconText: "\uf128"
        tooltipText: root.hintsVisible ? "Hide keyboard shortcuts" : "Keyboard shortcuts"
        foreground: root.hintsVisible ? root.accent : root.foreground
        hoverColor: root.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        bordered: true
        onClicked: root.hintsVisible = !root.hintsVisible
      }

      PanelActionButton {
        id: settingsButton
        iconText: "\uf013"
        tooltipText: root.settingsOpen ? "Close settings" : "Activity settings"
        foreground: root.settingsOpen ? root.accent : root.foreground
        hoverColor: root.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        bordered: true
        onClicked: root.setSettingsOpen(!root.settingsOpen)
      }

      PanelActionButton {
        id: expandButton
        visible: !root.settingsOpen
        iconText: expanded ? "\uf066" : "\uf065"
        tooltipText: expanded ? "Collapse details" : "Expand details"
        foreground: root.foreground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        bordered: true
        onClicked: root.setExpanded(!expanded)
      }
    }
  }

  component MetricCard: BorderSurface {
    id: metricCard

    property string label: ""
    property string badge: ""
    property string value: ""
    property string detail: ""
    property var history: []
    property var paint: ({ width: 0, height: 0, frames: [], cells: [] })
    property real ceiling: 0
    property real bar: -1
    property bool tall: false
    property bool interactive: false
    property string tooltipText: ""
    property color tone: root.accent
    property color badgeTone: root.dim
    readonly property bool showCores: !!(paint && Array.isArray(paint.cells) && paint.cells.length > 0)
    signal activated(int delta)

    implicitHeight: Style.space(tall ? 124 : 92)
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    radius: Style.cornerRadius

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.lg
      spacing: Style.spacing.xxs

      Item {
        width: parent.width
        implicitHeight: Math.max(cardLabel.implicitHeight, cardBadge.implicitHeight)

        PanelSectionHeader {
          id: cardLabel
          anchors.left: parent.left
          anchors.right: cardBadge.visible ? cardBadge.left : parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.rightMargin: cardBadge.visible ? Style.spacing.sm : 0
          text: metricCard.label
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          elide: Text.ElideRight
        }

        Text {
          id: cardBadge
          visible: metricCard.badge !== ""
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: metricCard.badge
          color: metricCard.badgeTone
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Item {
        width: parent.width
        implicitHeight: Math.max(valueBlock.implicitHeight, coreDie.implicitHeight)

        Column {
          id: valueBlock
          anchors.left: parent.left
          anchors.right: coreDie.visible ? coreDie.left : parent.right
          anchors.rightMargin: coreDie.visible ? Style.spacing.sm : 0
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            text: value
            color: tone
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: detail
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        CoreHeatGrid {
          id: coreDie
          visible: metricCard.showCores
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          paint: metricCard.paint
        }
      }
    }

    Sparkline {
      visible: metricCard.bar < 0 && Array.isArray(history) && history.length > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.spacing.lg
      anchors.rightMargin: Style.spacing.lg
      anchors.bottomMargin: Style.spacing.sm
      height: Style.space(20)
      values: history
      ceiling: parent.ceiling
      lineColor: tone
      fillColor: Util.alpha(tone, 0.10)
    }

    Rectangle {
      visible: metricCard.bar >= 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.spacing.lg
      anchors.rightMargin: Style.spacing.lg
      anchors.bottomMargin: Style.spacing.sm
      height: Style.space(4)
      radius: height / 2
      color: Util.alpha(root.foreground, 0.12)

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, metricCard.bar))
        height: parent.height
        radius: parent.radius
        color: metricCard.tone
      }
    }

    MouseArea {
      id: cardClick
      anchors.fill: parent
      enabled: metricCard.interactive
      hoverEnabled: metricCard.interactive
      cursorShape: metricCard.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
      acceptedButtons: Qt.LeftButton
      onClicked: function(mouse) {
        metricCard.activated((mouse.modifiers & Qt.ShiftModifier) ? -1 : 1)
      }

      PanelToolTip {
        visible: metricCard.interactive && metricCard.tooltipText !== "" && cardClick.containsMouse
        text: metricCard.tooltipText
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      }
    }
  }

  component ActivityPair: Row {
    property string iconText: ""
    property string label: ""
    property string value: ""
    property string secondary: ""

    spacing: Style.spacing.md

    Text {
      id: icon
      anchors.verticalCenter: parent.verticalCenter
      text: iconText
      color: root.accent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.title
    }

    Column {
      id: labels
      width: Math.max(1, parent.width - icon.implicitWidth - parent.spacing)
      spacing: Style.spacing.xxs

      Text {
        text: label
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        width: parent.width
        text: value
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: secondary
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  component DetailSurface: BorderSurface {
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    radius: Style.cornerRadius
  }

  component CoreHeatGrid: Item {
    id: heat

    property var paint: ({ width: 0, height: 0, frames: [], cells: [] })

    readonly property var frames: paint && Array.isArray(paint.frames) ? paint.frames : []
    readonly property var cells: paint && Array.isArray(paint.cells) ? paint.cells : []

    implicitWidth: Math.max(0, Number(paint && paint.width || 0))
    implicitHeight: Math.max(0, Number(paint && paint.height || 0))

    function cellLabel(cell) {
      var kind = String(cell && cell.kind || "same")
      var index = String(cell && cell.name || "").replace(/^cpu/i, "")
      var usage = Math.round(Number(cell && cell.usage || 0))
      if (kind === "performance") return "P-core " + index + " · " + usage + "%"
      if (kind === "efficiency") return "E-core " + index + " · " + usage + "%"
      if (kind === "lowpower") return "LP-E " + index + " · " + usage + "%"
      return "Core " + index + " · " + usage + "%"
    }

    Repeater {
      model: heat.frames.length

      Rectangle {
        required property int index
        readonly property var frame: heat.frames[index] || ({})
        x: Number(frame.x || 0)
        y: Number(frame.y || 0)
        width: Number(frame.w || 0)
        height: Number(frame.h || 0)
        radius: 2
        color: "transparent"
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.28)
      }
    }

    Repeater {
      model: heat.cells.length

      CoreDieCell {
        required property int index
        readonly property var cell: heat.cells[index] || ({})
        x: Number(cell.x || 0)
        y: Number(cell.y || 0)
        size: Number(cell.size || 0)
        usage: Number(cell.usage || 0)
        tooltipText: heat.cellLabel(cell)
      }
    }
  }

  component CoreDieCell: Rectangle {
    property int size: Style.space(7)
    property real usage: 0
    property string tooltipText: ""

    width: size
    height: size
    radius: 1
    color: "transparent"
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.22)

    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: 0
      color: root.pressureColor(parent.usage)
      opacity: parent.usage < 8 ? 0 : 0.28 + 0.72 * Math.pow(parent.usage / 100, 1.35)
    }

    MouseArea {
      id: cellHover
      anchors.fill: parent
      hoverEnabled: true

      PanelToolTip {
        visible: cellHover.containsMouse && cellHover.parent.tooltipText !== ""
        text: cellHover.parent.tooltipText
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      }
    }
  }

  component ProcessHeader: Item {
    implicitHeight: headerRow.implicitHeight

    Row {
      id: headerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md

      ProcessSortCell {
        width: root.processNameColumnWidth(parent.width, parent.spacing)
        sortKey: "name"
        label: "Name"
      }
      ProcessSortCell {
        width: root.processPidColumnWidth
        sortKey: "pid"
        label: "PID"
        alignment: Text.AlignRight
      }
      ProcessCell {
        visible: root.showProcessUserColumn
        width: root.processUserColumnWidth
        text: "User"
        dimmed: true
      }
      ProcessSortCell {
        width: root.processMetricColumnWidth
        sortKey: "cpu"
        label: "CPU"
        alignment: Text.AlignRight
      }
      ProcessSortCell {
        width: root.processMetricColumnWidth
        sortKey: "memory"
        label: "RAM"
        alignment: Text.AlignRight
      }
      ProcessSortCell {
        visible: root.powerEstimatesEnabled
        width: root.processMetricColumnWidth
        sortKey: "power"
        label: "~W"
        alignment: Text.AlignRight
        tooltipText: root.processPowerTooltip
      }
      ProcessSortCell {
        visible: root.showProcessTimeColumn
        width: root.processMetricColumnWidth
        sortKey: "runtime"
        label: "Time"
        alignment: Text.AlignRight
      }
    }
  }

  component ProcessSortCell: Item {
    id: sortCell

    property string sortKey: ""
    property string label: ""
    property string tooltipText: ""
    property int alignment: Text.AlignLeft

    implicitHeight: labelText.implicitHeight

    ProcessCell {
      id: labelText
      width: parent.width
      text: root.sortLabel(sortCell.sortKey, sortCell.label)
      dimmed: root.sortKey !== sortCell.sortKey
      emphasized: root.sortKey === sortCell.sortKey
      alignment: sortCell.alignment
    }

    MouseArea {
      id: sortHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setSort(sortCell.sortKey)

      PanelToolTip {
        visible: sortCell.tooltipText !== "" && sortHover.containsMouse
        text: sortCell.tooltipText
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      }
    }
  }

  component ProcessRow: CursorSurface {
    property var processData: ({})
    property int rowIndex: -1
    property bool compact: false
    property bool selected: false

    hasCursor: selected
    foreground: root.foreground
    accent: root.accent
    implicitHeight: compact ? Style.space(34) : Style.space(28)

    Row {
      anchors.fill: parent
      anchors.leftMargin: compact ? Style.spacing.sm : Style.spacing.md
      anchors.rightMargin: compact ? Style.spacing.sm : Style.spacing.md
      spacing: Style.spacing.md

      Column {
        width: compact
          ? Math.max(1, parent.width - cpuValue.width - memoryValue.width - parent.spacing * 2)
          : root.processNameColumnWidth(parent.width, parent.spacing)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: parent.width
          text: String(processData.name || "unknown")
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: compact ? Style.font.body : Style.font.bodySmall
          font.bold: compact
          elide: Text.ElideRight
        }

        Text {
          visible: compact
          width: parent.width
          text: String(processData.user || "") + "  ·  " + String(processData.pid || "")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ProcessCell {
        visible: !compact
        width: root.processPidColumnWidth
        text: String(processData.pid || "")
        alignment: Text.AlignRight
      }

      ProcessCell {
        visible: !compact && root.showProcessUserColumn
        width: root.processUserColumnWidth
        text: String(processData.user || "")
      }

      ProcessCell {
        id: cpuValue
        width: compact ? Style.space(46) : root.processMetricColumnWidth
        text: Number(processData.cpu || 0).toFixed(1) + "%"
        alignment: Text.AlignRight
        emphasized: Number(processData.cpu || 0) >= 25
      }

      ProcessCell {
        id: memoryValue
        width: compact ? Style.space(46) : root.processMetricColumnWidth
        text: Number(processData.memory || 0).toFixed(1) + "%"
        alignment: Text.AlignRight
      }

      ProcessCell {
        visible: !compact && root.powerEstimatesEnabled
        width: root.processMetricColumnWidth
        text: root.estimatedPowerText(processData.power)
        alignment: Text.AlignRight
      }

      ProcessCell {
        visible: !compact && root.showProcessTimeColumn
        width: root.processMetricColumnWidth
        text: Model.formatDuration(processData.elapsed)
        alignment: Text.AlignRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: !compact
      cursorShape: compact ? Qt.ArrowCursor : Qt.PointingHandCursor
      onPositionChanged: function(mouse) {
        if (!compact) root.selectProcessFromPointer(parent.rowIndex, parent, mouse)
      }
      onClicked: {
        if (!compact) {
          root.cursorActive = true
          root.selectProcess(parent.rowIndex)
        }
      }
    }
  }

  component ProcessCell: Text {
    property bool dimmed: false
    property bool emphasized: false
    property int alignment: Text.AlignLeft

    color: emphasized ? root.accent : (dimmed ? root.dim : root.foreground)
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: dimmed ? Style.font.caption : Style.font.bodySmall
    font.bold: emphasized || dimmed
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: alignment
    verticalAlignment: Text.AlignVCenter
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  }
}
