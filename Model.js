function number(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : (fallback === undefined ? 0 : fallback)
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, number(value)))
}

function emptySnapshot() {
  return {
    schema: 0,
    sample: 0,
    cpuFrequencyMHz: -1,
    cpuName: "",
    memorySpeedMTs: -1,
    cpu: { total: 0, idle: 0 },
    cores: [],
    topology: [],
    memory: {
      total: 0,
      available: 0,
      cached: 0,
      swapTotal: 0,
      swapFree: 0
    },
    tasks: { running: 0, total: 0 },
    uptime: 0,
    networks: [],
    disks: []
  }
}

function emptyMetrics() {
  return {
    cpu: 0,
    memory: 0,
    swap: 0,
    download: 0,
    upload: 0,
    diskRead: 0,
    diskWrite: 0,
    networkInterface: "",
    cores: [],
    cpuHistory: [],
    memoryHistory: [],
    networkHistory: [],
    diskHistory: [],
    diskDevices: [],
    diskHistories: {}
  }
}

function emptyProcessSnapshot() {
  return {
    schema: 0,
    sample: 0,
    clockTicks: 100,
    systemBusyTicks: 0,
    processes: []
  }
}

function emptyThermalSnapshot() {
  return {
    schema: 0,
    sample: 0,
    temperatures: []
  }
}

function emptyPackagePowerSnapshot() {
  return {
    schema: 0,
    sample: 0,
    packages: []
  }
}

function emptyPower() {
  return {
    available: false,
    watts: -1
  }
}

function emptyStorageSnapshot() {
  return {
    schema: 0,
    sample: 0,
    path: "/",
    total: 0,
    used: 0,
    available: 0,
    volumes: []
  }
}

function emptyGpuSnapshot() {
  return {
    schema: 0,
    sample: 0,
    gpus: []
  }
}

function gpuSnapshotEntry(snapshot, id) {
  var gpuId = String(id || "")
  for (var i = 0; i < snapshot.gpus.length; i++) {
    if (snapshot.gpus[i].id === gpuId) return snapshot.gpus[i]
  }

  var gpu = {
    id: gpuId,
    vendor: "GPU",
    driver: "unknown",
    name: "GPU",
    frequencyMHz: -1,
    directUtilization: -1,
    memoryUsed: -1,
    memoryTotal: -1,
    memoryKind: "unknown",
    engines: [],
    dedicatedMemory: 0,
    sharedMemory: 0,
    dedicatedMemorySeen: false,
    sharedMemorySeen: false
  }
  snapshot.gpus.push(gpu)
  return gpu
}

function temperatureFromFields(fields) {
  return {
    id: String(fields[1] || ""),
    chip: String(fields[2] || ""),
    label: String(fields[3] || "Sensor"),
    value: number(fields[4]) / 1000
  }
}

function cpuCounters(fields) {
  return {
    total: number(fields[2]),
    idle: number(fields[3])
  }
}

function parseSnapshot(raw) {
  var snapshot = emptySnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    var kind = fields[0]

    if (kind === "schema") {
      snapshot.schema = fields[1] === "activity-resources" ? number(fields[2]) : 0
    } else if (kind === "sample") {
      snapshot.sample = number(fields[1])
    } else if (kind === "cpu") {
      var counters = cpuCounters(fields)
      if (fields[1] === "cpu") snapshot.cpu = counters
      else snapshot.cores.push({
        name: String(fields[1] || ""),
        total: counters.total,
        idle: counters.idle
      })
    } else if (kind === "cpu-name") {
      snapshot.cpuName = String(fields[1] || "")
    } else if (kind === "frequency") {
      if (fields[1] === "cpu")
        snapshot.cpuFrequencyMHz = Math.max(-1, number(fields[2], -1))
      else if (fields[1] === "memory")
        snapshot.memorySpeedMTs = Math.max(-1, number(fields[2], -1))
    } else if (kind === "memory") {
      snapshot.memory = {
        total: number(fields[1]) * 1024,
        available: number(fields[2]) * 1024,
        swapTotal: number(fields[3]) * 1024,
        swapFree: number(fields[4]) * 1024,
        cached: number(fields[5]) * 1024
      }
    } else if (kind === "tasks") {
      snapshot.tasks = {
        running: number(fields[1]),
        total: number(fields[2])
      }
    } else if (kind === "network") {
      snapshot.networks.push({
        name: String(fields[1] || ""),
        received: number(fields[2]),
        transmitted: number(fields[3]),
        state: String(fields[4] || "unknown"),
        defaultRoute: number(fields[5]) === 1,
        physical: number(fields[6]) === 1
      })
    } else if (kind === "disk") {
      snapshot.disks.push({
        id: String(fields[1] || fields[2] || ""),
        name: String(fields[2] || ""),
        read: number(fields[3]) * 512,
        written: number(fields[4]) * 512
      })
    } else if (kind === "cpu-topo") {
      snapshot.topology.push({
        id: number(fields[1]),
        cls: String(fields[2] || "performance"),
        domain: String(fields[3] || ""),
        cluster: String(fields[4] || ""),
        core: number(fields[5]),
        maxKhz: number(fields[6])
      })
    }
  }

  snapshot.uptime = snapshot.sample
  return snapshot
}

function parseProcessSnapshot(raw) {
  var snapshot = emptyProcessSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    var kind = fields[0]

    if (kind === "schema") {
      snapshot.schema = fields[1] === "activity-processes" ? number(fields[2]) : 0
    } else if (kind === "sample") {
      snapshot.sample = number(fields[1])
      snapshot.clockTicks = Math.max(1, number(fields[2], 100))
      snapshot.systemBusyTicks = Math.max(0, number(fields[3]))
    } else if (kind === "process") {
      snapshot.processes.push({
        pid: number(fields[1]),
        user: String(fields[2] || ""),
        state: String(fields[3] || ""),
        startTicks: number(fields[4]),
        cpuTicks: number(fields[5]),
        rss: Math.max(0, number(fields[6])) * 1024,
        name: String(fields.slice(7).join("\t") || "unknown")
      })
    }
  }

  return snapshot
}

function parseThermalSnapshot(raw) {
  var snapshot = emptyThermalSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    if (fields[0] === "schema") {
      snapshot.schema = fields[1] === "activity-thermals" ? number(fields[2]) : 0
    } else if (fields[0] === "sample") {
      snapshot.sample = number(fields[1])
    } else if (fields[0] === "temperature") {
      snapshot.temperatures.push(temperatureFromFields(fields))
    }
  }

  return snapshot
}

function parsePackagePowerSnapshot(raw) {
  var snapshot = emptyPackagePowerSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    if (fields[0] === "schema") {
      snapshot.schema = fields[1] === "activity-process-power" ? number(fields[2]) : 0
    } else if (fields[0] === "sample") {
      snapshot.sample = number(fields[1])
    } else if (fields[0] === "package") {
      var packageValue = {
        id: String(fields[1] || ""),
        name: String(fields[2] || fields[1] || "Package"),
        energy: !fields[3] ? -1 : Math.max(0, number(fields[3])),
        maximumEnergyRange: Math.max(0, number(fields[4]))
      }
      snapshot.packages.push(packageValue)
    }
  }

  return snapshot
}

function boundedStorageVolume(path, total, used, available) {
  var size = Math.max(0, number(total))
  return {
    path: String(path || "/"),
    total: size,
    used: Math.min(size, Math.max(0, number(used))),
    available: Math.min(size, Math.max(0, number(available)))
  }
}

function compareStoragePath(left, right) {
  var a = String(left && left.path || "")
  var b = String(right && right.path || "")
  if (a === "/") return b === "/" ? 0 : -1
  if (b === "/") return 1
  if (a < b) return -1
  if (a > b) return 1
  return 0
}

function applyPrimaryStorage(snapshot) {
  var volumes = snapshot && Array.isArray(snapshot.volumes) ? snapshot.volumes : []
  var primary = null
  for (var i = 0; i < volumes.length; i++) {
    if (volumes[i].path === "/") {
      primary = volumes[i]
      break
    }
  }
  if (!primary && volumes.length > 0) primary = volumes[0]
  if (!primary) return snapshot
  snapshot.path = primary.path
  snapshot.total = primary.total
  snapshot.used = primary.used
  snapshot.available = primary.available
  return snapshot
}

function parseStorageSnapshot(raw) {
  var snapshot = emptyStorageSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    if (fields[0] === "schema") {
      snapshot.schema = fields[1] === "activity-storage" ? number(fields[2]) : 0
    } else if (fields[0] === "sample") {
      snapshot.sample = number(fields[1])
    } else if (fields[0] === "storage") {
      snapshot.volumes.push(boundedStorageVolume(
        fields[1],
        fields[2],
        fields[3],
        fields[4]
      ))
    }
  }

  snapshot.volumes.sort(compareStoragePath)
  return applyPrimaryStorage(snapshot)
}

function parseGpuSnapshot(raw) {
  var snapshot = emptyGpuSnapshot()
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    var fields = lines[i].split("\t")
    var kind = fields[0]

    if (kind === "schema") {
      snapshot.schema = fields[1] === "activity-gpus" ? number(fields[2]) : 0
    } else if (kind === "sample") {
      snapshot.sample = number(fields[1])
    } else if (kind === "gpu") {
      var gpu = gpuSnapshotEntry(snapshot, fields[1])
      gpu.vendor = String(fields[2] || "GPU")
      gpu.driver = String(fields[3] || "unknown")
      gpu.name = String(fields[4] || gpu.vendor + " GPU")
      gpu.frequencyMHz = Math.max(-1, number(fields[9], -1))
      gpu.directUtilization = Math.max(-1, number(fields[5], -1))
      gpu.memoryUsed = Math.max(-1, number(fields[6], -1))
      gpu.memoryTotal = Math.max(-1, number(fields[7], -1))
      gpu.memoryKind = String(fields[8] || "unknown")
    } else if (kind === "engine") {
      gpuSnapshotEntry(snapshot, fields[1]).engines.push({
        client: String(fields[2] || ""),
        name: String(fields[3] || "engine"),
        busy: Math.max(0, number(fields[4])),
        total: number(fields[5], -1),
        capacity: Math.max(1, number(fields[6], 1)),
        kind: String(fields[7] || "time")
      })
    } else if (kind === "gpu-memory") {
      var memoryGpu = gpuSnapshotEntry(snapshot, fields[1])
      var memoryValue = Math.max(0, number(fields[3]))
      if (fields[2] === "vram") {
        memoryGpu.dedicatedMemory += memoryValue
        memoryGpu.dedicatedMemorySeen = true
      } else if (fields[2] === "shared") {
        memoryGpu.sharedMemory += memoryValue
        memoryGpu.sharedMemorySeen = true
      }
    }
  }

  for (var j = 0; j < snapshot.gpus.length; j++) {
    var value = snapshot.gpus[j]
    if (value.memoryUsed < 0 && value.dedicatedMemorySeen) {
      value.memoryUsed = value.dedicatedMemory
      value.memoryKind = "vram"
    } else if (value.memoryUsed < 0 && value.sharedMemorySeen) {
      value.memoryUsed = value.sharedMemory
      value.memoryKind = "shared"
    }
    if (value.memoryTotal > 0 && value.memoryUsed > value.memoryTotal)
      value.memoryUsed = value.memoryTotal
  }
  return snapshot
}

function gpuEngineKey(engine) {
  return String(engine && engine.client || "") + ":"
    + String(engine && engine.name || "") + ":"
    + String(engine && engine.kind || "")
}

function nextGpus(previous, current) {
  var result = []
  var previousGpus = previous && Array.isArray(previous.gpus) ? previous.gpus : []
  var currentGpus = current && Array.isArray(current.gpus) ? current.gpus : []
  var beforeByGpu = {}
  var seconds = previous && current && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0

  for (var i = 0; i < previousGpus.length; i++) beforeByGpu[previousGpus[i].id] = previousGpus[i]

  for (var j = 0; j < currentGpus.length; j++) {
    var gpu = currentGpus[j]
    var usage = number(gpu.directUtilization, -1)
    if (usage < 0) {
      var oldGpu = beforeByGpu[gpu.id]
      var oldEngines = {}
      var engineUsage = {}
      var comparable = false
      var oldValues = oldGpu && Array.isArray(oldGpu.engines) ? oldGpu.engines : []
      var newValues = Array.isArray(gpu.engines) ? gpu.engines : []

      for (var k = 0; k < oldValues.length; k++) oldEngines[gpuEngineKey(oldValues[k])] = oldValues[k]
      for (var m = 0; m < newValues.length; m++) {
        var engine = newValues[m]
        var oldEngine = oldEngines[gpuEngineKey(engine)]
        if (!oldEngine) continue
        var busyDelta = number(engine.busy) - number(oldEngine.busy)
        if (busyDelta < 0) continue
        var percent = -1
        if (engine.kind === "cycles") {
          var totalDelta = number(engine.total, -1) - number(oldEngine.total, -1)
          if (totalDelta > 0) percent = busyDelta / totalDelta / engine.capacity * 100
        } else if (seconds > 0) {
          percent = busyDelta / (seconds * 1000000000) / engine.capacity * 100
        }
        if (!isFinite(percent) || percent < 0) continue
        comparable = true
        engineUsage[engine.name] = number(engineUsage[engine.name]) + percent
      }

      usage = -1
      if (comparable) {
        usage = 0
        // Different engine classes can run in parallel. Their maximum is a
        // stable whole-GPU indicator without double-counting that overlap.
        for (var engineName in engineUsage)
          usage = Math.max(usage, engineUsage[engineName])
      }
    }

    result.push({
      id: gpu.id,
      vendor: gpu.vendor,
      driver: gpu.driver,
      name: gpu.name,
      frequencyMHz: gpu.frequencyMHz,
      usage: usage < 0 ? -1 : clamp(usage, 0, 100),
      memoryUsed: gpu.memoryUsed,
      memoryTotal: gpu.memoryTotal,
      memoryKind: gpu.memoryKind
    })
  }
  return result
}

function packageEnergyReadable(snapshot) {
  var packages = snapshot && Array.isArray(snapshot.packages) ? snapshot.packages : []
  if (packages.length === 0) return false

  for (var i = 0; i < packages.length; i++) {
    if (number(packages[i].energy, -1) < 0
        || number(packages[i].maximumEnergyRange) <= 0) {
      return false
    }
  }
  return true
}

function packageCountersComparable(previous, current) {
  if (!previous || !current) return 0

  var before = number(previous.energy, -1)
  var after = number(current.energy, -1)
  var previousMaximum = number(previous.maximumEnergyRange)
  var currentMaximum = number(current.maximumEnergyRange)
  var validRange = before >= 0
    && after >= 0
    && currentMaximum > 0
    && previousMaximum === currentMaximum
    && before <= currentMaximum
    && after <= currentMaximum
  if (!validRange || after >= before) return validRange

  // A real RAPL wrap crosses the end of the published counter range. Treat
  // other decreases as a reset/new counter instead of inventing a large draw.
  return before >= currentMaximum * 0.75
    && after <= currentMaximum * 0.25
}

function packageEnergyDelta(previous, current) {
  if (!packageCountersComparable(previous, current)) return 0

  var before = number(previous.energy)
  var after = number(current.energy)
  var currentMaximum = number(current.maximumEnergyRange)
  if (after >= before) return after - before
  return currentMaximum - before + after
}

function nextPackagePower(previous, current) {
  var before = {}
  var totalWatts = 0
  var previousPackages = previous && Array.isArray(previous.packages) ? previous.packages : []
  var currentPackages = current && Array.isArray(current.packages) ? current.packages : []
  var seconds = previous && previous.sample > 0 && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0
  var complete = seconds > 0
    && currentPackages.length > 0
    && currentPackages.length === previousPackages.length

  for (var i = 0; i < previousPackages.length; i++) {
    before[previousPackages[i].id] = previousPackages[i]
  }

  for (var j = 0; j < currentPackages.length; j++) {
    var value = currentPackages[j]
    var delta = packageEnergyDelta(before[value.id], value)
    var comparable = seconds > 0 && packageCountersComparable(before[value.id], value)
    var watts = comparable ? delta / 1000000 / seconds : -1
    if (!isFinite(watts) || watts < 0) watts = -1
    if (watts < 0) complete = false
    if (watts >= 0) totalWatts += watts
  }

  return {
    available: complete,
    watts: complete ? totalWatts : -1
  }
}

function counterPercent(previous, current) {
  if (!previous || !current) return 0
  var total = number(current.total) - number(previous.total)
  var idle = number(current.idle) - number(previous.idle)
  if (total <= 0 || idle < 0) return 0
  return clamp((1 - idle / total) * 100, 0, 100)
}

function counterRate(previous, current, seconds) {
  if (seconds <= 0) return 0
  var delta = number(current) - number(previous)
  return delta < 0 ? 0 : delta / seconds
}

function memoryPercent(memory) {
  var total = number(memory && memory.total)
  if (total <= 0) return 0
  return clamp((total - number(memory.available)) / total * 100, 0, 100)
}

function swapPercent(memory) {
  var total = number(memory && memory.swapTotal)
  if (total <= 0) return 0
  return clamp((total - number(memory.swapFree)) / total * 100, 0, 100)
}

function appendHistory(values, value, limit) {
  var history = Array.isArray(values) ? values.slice() : []
  history.push(number(value))
  var cap = Math.max(1, Math.round(number(limit, 60)))
  if (history.length > cap) history.splice(0, history.length - cap)
  return history
}

function coreUsage(previous, current) {
  var before = {}
  var result = []
  var previousCores = previous && Array.isArray(previous.cores) ? previous.cores : []
  var currentCores = current && Array.isArray(current.cores) ? current.cores : []

  for (var i = 0; i < previousCores.length; i++) before[previousCores[i].name] = previousCores[i]
  for (var j = 0; j < currentCores.length; j++) {
    result.push({
      name: currentCores[j].name,
      usage: counterPercent(before[currentCores[j].name], currentCores[j])
    })
  }
  return result
}

function networkByName(networks, name) {
  var values = Array.isArray(networks) ? networks : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].name === name) return values[i]
  }
  return null
}

function selectNetwork(previous, current, preferredName) {
  var values = current && Array.isArray(current.networks) ? current.networks : []
  if (values.length === 0) return null

  var preferred = networkByName(values, preferredName)
  if (preferred && preferred.defaultRoute) return preferred

  for (var i = 0; i < values.length; i++) {
    if (values[i].defaultRoute) return values[i]
  }
  if (preferred && preferred.state === "up") return preferred

  var previousValues = previous && Array.isArray(previous.networks) ? previous.networks : []
  var best = null
  var bestDelta = -1
  for (var j = 0; j < values.length; j++) {
    if (values[j].state !== "up") continue
    if (!values[j].physical && best && best.physical) continue
    var before = networkByName(previousValues, values[j].name)
    var delta = before
      ? Math.max(0, values[j].received - before.received) + Math.max(0, values[j].transmitted - before.transmitted)
      : 0
    if (!best || (values[j].physical && !best.physical) || delta > bestDelta) {
      best = values[j]
      bestDelta = delta
    }
  }
  return best || values[0]
}

function diskId(disk) {
  return String(disk && (disk.id || disk.name) || "")
}

function copyNumberArrays(value) {
  var copied = {}
  if (!value || typeof value !== "object") return copied
  for (var key in value) {
    if (!Object.prototype.hasOwnProperty.call(value, key) || !Array.isArray(value[key]))
      continue
    copied[key] = value[key].slice()
  }
  return copied
}

function aggregateDisks(disks) {
  var values = Array.isArray(disks) ? disks : []
  var selected = []
  var read = 0
  var written = 0
  for (var i = 0; i < values.length; i++) {
    selected.push(diskId(values[i]))
    read += number(values[i].read)
    written += number(values[i].written)
  }
  selected.sort()
  return {
    signature: selected.join(","),
    read: read,
    written: written
  }
}

function compareDiskName(left, right) {
  var a = String(left && left.name || "")
  var b = String(right && right.name || "")
  if (a < b) return -1
  if (a > b) return 1
  var leftId = diskId(left)
  var rightId = diskId(right)
  if (leftId < rightId) return -1
  if (leftId > rightId) return 1
  return 0
}

function diskDeviceRates(previous, current, seconds) {
  var previousDisks = previous && Array.isArray(previous.disks) ? previous.disks : []
  var currentDisks = current && Array.isArray(current.disks) ? current.disks : []
  var before = {}
  for (var i = 0; i < previousDisks.length; i++) before[diskId(previousDisks[i])] = previousDisks[i]

  var devices = []
  var read = 0
  var written = 0
  for (var j = 0; j < currentDisks.length; j++) {
    var disk = currentDisks[j]
    var id = diskId(disk)
    var prior = id ? before[id] : null
    var deviceRead = seconds > 0 && prior ? counterRate(prior.read, disk.read, seconds) : 0
    var deviceWrite = seconds > 0 && prior ? counterRate(prior.written, disk.written, seconds) : 0
    devices.push({
      id: id,
      name: String(disk.name || id),
      read: deviceRead,
      write: deviceWrite
    })
    read += deviceRead
    written += deviceWrite
  }
  devices.sort(compareDiskName)
  return {
    devices: devices,
    read: read,
    write: written
  }
}

function nextDiskHistories(oldHistories, devices, allRead, allWrite, historyLimit) {
  var previous = copyNumberArrays(oldHistories)
  var next = {
    all: appendHistory(previous.all, number(allRead) + number(allWrite), historyLimit)
  }
  var values = Array.isArray(devices) ? devices : []
  for (var i = 0; i < values.length; i++) {
    var id = diskId(values[i])
    if (!id) continue
    next[id] = appendHistory(previous[id], number(values[i].read) + number(values[i].write), historyLimit)
  }
  return next
}

function diskCycleItems(metrics) {
  var values = metrics || emptyMetrics()
  var devices = Array.isArray(values.diskDevices) ? values.diskDevices : []
  var histories = values.diskHistories || {}
  if (devices.length <= 1) {
    if (devices.length === 0) {
      return [{
        id: "all",
        name: "All",
        read: number(values.diskRead),
        write: number(values.diskWrite),
        history: Array.isArray(values.diskHistory) ? values.diskHistory : []
      }]
    }
    return [{
      id: devices[0].id,
      name: devices[0].name,
      read: number(devices[0].read),
      write: number(devices[0].write),
      history: Array.isArray(values.diskHistory) ? values.diskHistory : []
    }]
  }

  var items = [{
    id: "all",
    name: "All",
    read: number(values.diskRead),
    write: number(values.diskWrite),
    history: Array.isArray(values.diskHistory) ? values.diskHistory : []
  }]
  for (var i = 0; i < devices.length; i++) {
    var id = diskId(devices[i])
    items.push({
      id: id,
      name: String(devices[i].name || id),
      read: number(devices[i].read),
      write: number(devices[i].write),
      history: Array.isArray(histories[id]) ? histories[id] : []
    })
  }
  return items
}

function selectDiskItem(items, selectedId) {
  var values = Array.isArray(items) ? items : []
  if (values.length === 0) return null
  var wanted = String(selectedId || "")
  for (var i = 0; i < values.length; i++) {
    if (String(values[i].id) === wanted) return values[i]
  }
  return values[0]
}

function storageVolumes(snapshot) {
  var volumes = snapshot && Array.isArray(snapshot.volumes) ? snapshot.volumes.slice() : []
  if (volumes.length === 0 && snapshot && number(snapshot.total) > 0) {
    volumes.push(boundedStorageVolume(
      snapshot.path,
      snapshot.total,
      snapshot.used,
      snapshot.available
    ))
  }
  volumes.sort(compareStoragePath)
  return volumes
}

function storageUsedFraction(volume) {
  var total = number(volume && volume.total)
  if (total <= 0) return 0
  return clamp(number(volume.used) / total, 0, 1)
}

function tightestStorageVolume(volumes) {
  var values = Array.isArray(volumes) ? volumes : []
  var best = null
  var bestFraction = -1
  for (var i = 0; i < values.length; i++) {
    var fraction = storageUsedFraction(values[i])
    if (!best || fraction > bestFraction || (fraction === bestFraction && values[i].path === "/")) {
      best = values[i]
      bestFraction = fraction
    }
  }
  return best
}

function selectStorageVolume(volumes, selectedPath, pinned) {
  var values = Array.isArray(volumes) ? volumes : []
  if (values.length === 0) return null
  if (pinned) {
    var wanted = String(selectedPath || "")
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].path) === wanted) return values[i]
    }
  }
  return tightestStorageVolume(values) || values[0]
}

function storageVolumeLabel(path) {
  var value = String(path || "")
  if (!value || value === "/") return "/"
  var trimmed = value.replace(/\/+$/, "")
  var slash = trimmed.lastIndexOf("/")
  return slash >= 0 ? trimmed.slice(slash + 1) : trimmed
}

function nextCycleIndex(length, current, delta) {
  var count = Math.max(0, Math.round(number(length)))
  if (count <= 0) return 0
  var step = Math.round(number(delta, 1))
  if (step === 0) step = 1
  return ((Math.round(number(current)) + step) % count + count) % count
}

function cycleItemId(items, currentId, key, delta) {
  var values = Array.isArray(items) ? items : []
  var field = key || "id"
  if (values.length === 0) return ""
  if (values.length === 1) return String(values[0][field] || "")
  var wanted = String(currentId || "")
  var index = 0
  for (var i = 0; i < values.length; i++) {
    if (String(values[i][field]) === wanted) {
      index = i
      break
    }
  }
  return String(values[nextCycleIndex(values.length, index, delta)][field] || "")
}

// A counter-based metric needs two samples. While the fresh baseline is being
// established, retain the last derived rates so reopening the panel does not
// flash zero, but immediately refresh values that are valid from one sample.
function baselineMetrics(current, existing) {
  var old = existing || emptyMetrics()
  var network = selectNetwork(null, current, old.networkInterface || "")
  var oldCores = Array.isArray(old.cores) ? old.cores : []
  return {
    cpu: number(old.cpu),
    memory: memoryPercent(current && current.memory),
    swap: swapPercent(current && current.memory),
    download: number(old.download),
    upload: number(old.upload),
    diskRead: number(old.diskRead),
    diskWrite: number(old.diskWrite),
    networkInterface: network ? network.name : String(old.networkInterface || ""),
    cores: oldCores.length > 0 ? oldCores : coreUsage(null, current),
    cpuHistory: Array.isArray(old.cpuHistory) ? old.cpuHistory.slice() : [],
    memoryHistory: Array.isArray(old.memoryHistory) ? old.memoryHistory.slice() : [],
    networkHistory: Array.isArray(old.networkHistory) ? old.networkHistory.slice() : [],
    diskHistory: Array.isArray(old.diskHistory) ? old.diskHistory.slice() : [],
    diskDevices: Array.isArray(old.diskDevices) ? old.diskDevices.slice() : [],
    diskHistories: copyNumberArrays(old.diskHistories)
  }
}

function nextMetrics(previous, current, existing, historyLimit) {
  var old = existing || {}
  var seconds = previous && previous.sample > 0 && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0
  var cpu = counterPercent(previous && previous.cpu, current.cpu)
  var memory = memoryPercent(current.memory)
  var network = selectNetwork(previous, current, old.networkInterface || "")
  var previousNetwork = network ? networkByName(previous && previous.networks, network.name) : null
  var download = seconds > 0 && previousNetwork
    ? counterRate(previousNetwork.received, network.received, seconds)
    : 0
  var upload = seconds > 0 && previousNetwork
    ? counterRate(previousNetwork.transmitted, network.transmitted, seconds)
    : 0
  var disks = diskDeviceRates(previous, current, seconds)
  var diskHistories = nextDiskHistories(
    old.diskHistories,
    disks.devices,
    disks.read,
    disks.write,
    historyLimit
  )

  return {
    cpu: cpu,
    memory: memory,
    swap: swapPercent(current.memory),
    download: download,
    upload: upload,
    diskRead: disks.read,
    diskWrite: disks.write,
    networkInterface: network ? network.name : "",
    cores: coreUsage(previous, current),
    cpuHistory: appendHistory(old.cpuHistory, cpu, historyLimit),
    memoryHistory: appendHistory(old.memoryHistory, memory, historyLimit),
    networkHistory: appendHistory(old.networkHistory, download + upload, historyLimit),
    diskHistory: diskHistories.all || [],
    diskDevices: disks.devices,
    diskHistories: diskHistories
  }
}

function nextProcesses(previous, current, totalMemory) {
  var before = {}
  var result = []
  var previousProcesses = previous && Array.isArray(previous.processes) ? previous.processes : []
  var currentProcesses = current && Array.isArray(current.processes) ? current.processes : []
  var seconds = previous && previous.sample > 0 && current.sample > previous.sample
    ? current.sample - previous.sample
    : 0
  var clockTicks = Math.max(1, number(current && current.clockTicks, 100))
  var memoryTotal = Math.max(0, number(totalMemory))

  for (var i = 0; i < previousProcesses.length; i++) {
    var previousKey = previousProcesses[i].pid + ":" + previousProcesses[i].startTicks
    before[previousKey] = previousProcesses[i]
  }

  for (var j = 0; j < currentProcesses.length; j++) {
    var process = currentProcesses[j]
    var key = process.pid + ":" + process.startTicks
    var old = before[key]
    var cpuTicksDelta = old && seconds > 0
      ? Math.max(0, process.cpuTicks - old.cpuTicks)
      : 0
    var cpu = cpuTicksDelta / clockTicks / (seconds > 0 ? seconds : 1) * 100
    result.push({
      pid: process.pid,
      user: process.user,
      state: process.state,
      startTicks: process.startTicks,
      cpu: cpu,
      cpuTicksDelta: cpuTicksDelta,
      memory: memoryTotal > 0 ? process.rss / memoryTotal * 100 : 0,
      rss: process.rss,
      elapsed: Math.max(0, current.sample - process.startTicks / clockTicks),
      name: process.name
    })
  }
  return result
}

function processSystemBusyDelta(previous, current) {
  if (!previous || !current) return -1
  if (number(previous.schema) <= 0 || number(current.schema) <= 0) return -1
  if (number(current.sample) <= number(previous.sample)) return -1

  var before = number(previous.systemBusyTicks, -1)
  var after = number(current.systemBusyTicks, -1)
  if (before < 0 || after < before) return -1
  return after - before
}

function estimateProcessPower(processes, packageWatts, systemBusyDelta) {
  var values = Array.isArray(processes) ? processes : []
  var result = []
  var measuredWatts = Number(packageWatts)
  var busyDelta = Number(systemBusyDelta)
  var observedDelta = 0
  var powerAvailable = packageWatts !== null
    && packageWatts !== ""
    && isFinite(measuredWatts)
    && measuredWatts >= 0
    && isFinite(busyDelta)
    && busyDelta > 0

  for (var i = 0; i < values.length; i++) {
    observedDelta += Math.max(0, number(values[i] && values[i].cpuTicksDelta))
  }
  var denominator = Math.max(busyDelta, observedDelta)

  for (var j = 0; j < values.length; j++) {
    var source = values[j] || {}
    var clone = {}
    for (var key in source) clone[key] = source[key]
    var cpuTicksDelta = Math.max(0, number(source.cpuTicksDelta))
    clone.power = powerAvailable
      ? measuredWatts * cpuTicksDelta / denominator
      : -1
    result.push(clone)
  }
  return result
}

function specializedTopology(topology) {
  var values = Array.isArray(topology) ? topology : []
  var seen = {}
  var count = 0
  for (var i = 0; i < values.length; i++) {
    var cls = String(values[i] && values[i].cls || "")
    if (cls !== "performance" && cls !== "efficiency" && cls !== "lowpower") continue
    if (seen[cls]) continue
    seen[cls] = true
    count++
  }
  return count >= 2
}

function coreUsageLookup(metricCores) {
  var usage = {}
  var values = Array.isArray(metricCores) ? metricCores : []
  for (var i = 0; i < values.length; i++) {
    usage[String(values[i].name || "")] = number(values[i].usage)
  }
  return usage
}

function physicalCoreKey(entry) {
  return String(number(entry && entry.core, entry && entry.id))
}

function topologyCell(members, usageByName) {
  var logicals = []
  var usage = 0
  var name = "cpu0"
  for (var i = 0; i < members.length; i++) {
    var logical = "cpu" + number(members[i].id)
    logicals.push(logical)
    if (i === 0) name = logical
    usage = Math.max(usage, number(usageByName[logical]))
  }
  return { name: name, logicals: logicals, usage: usage }
}

function coreLayout(metricCores, topology) {
  var values = Array.isArray(metricCores) ? metricCores : []
  var topo = Array.isArray(topology) ? topology : []
  var usageByName = coreUsageLookup(values)
  if (!specializedTopology(topo)) {
    return {
      mode: "uniform",
      domains: [{
        id: "all",
        rows: [{
          kind: "same",
          cells: values.map(function(core) {
            return {
              name: String(core.name || "cpu"),
              logicals: [String(core.name || "cpu")],
              usage: number(core.usage)
            }
          })
        }]
      }]
    }
  }

  var domains = {}
  var domainOrder = []
  for (var i = 0; i < topo.length; i++) {
    var entry = topo[i]
    var domain = String(entry.domain || "all")
    if (!domains[domain]) {
      domains[domain] = []
      domainOrder.push(domain)
    }
    domains[domain].push(entry)
  }

  domainOrder.sort(function(left, right) {
    var leftScore = 0
    var rightScore = 0
    for (var a = 0; a < domains[left].length; a++) {
      if (domains[left][a].cls === "performance") leftScore += 10
      leftScore += 1
    }
    for (var b = 0; b < domains[right].length; b++) {
      if (domains[right][b].cls === "performance") rightScore += 10
      rightScore += 1
    }
    if (leftScore !== rightScore) return rightScore - leftScore
    return left < right ? -1 : 1
  })

  var kinds = ["performance", "efficiency", "lowpower"]
  var result = { mode: "die", domains: [] }

  for (var d = 0; d < domainOrder.length; d++) {
    var members = domains[domainOrder[d]]
    var rows = []
    for (var k = 0; k < kinds.length; k++) {
      var kind = kinds[k]
      var ofKind = []
      for (var m = 0; m < members.length; m++) {
        if (members[m].cls === kind) ofKind.push(members[m])
      }
      if (ofKind.length === 0) continue

      var coreOrder = []
      var byCore = {}
      for (var p = 0; p < ofKind.length; p++) {
        var key = physicalCoreKey(ofKind[p])
        if (!byCore[key]) {
          byCore[key] = []
          coreOrder.push(key)
        }
        byCore[key].push(ofKind[p])
      }
      var cells = []
      for (var o = 0; o < coreOrder.length; o++) cells.push(topologyCell(byCore[coreOrder[o]], usageByName))
      var wrap = kind === "performance" ? 8 : 4
      for (var slice = 0; slice < cells.length; slice += wrap)
        rows.push({ kind: kind, cells: cells.slice(slice, slice + wrap) })
    }
    if (rows.length > 0) result.domains.push({ id: domainOrder[d], rows: rows })
  }

  if (result.domains.length === 0) {
    return coreLayout(values, [])
  }
  return result
}

function uniformColumnCount(count) {
  if (count <= 0) return 1
  if (count <= 4) return count
  if (count <= 6) return 3
  if (count <= 16) return 4
  if (count <= 24) return 6
  return 8
}

function coreCellSize(kind, sizes) {
  if (kind === "performance") return number(sizes && sizes.performance, 9)
  if (kind === "same") return number(sizes && sizes.same, 7)
  return number(sizes && sizes.efficiency, 6)
}

function flattenCoreLayout(layout, sizes) {
  var gap = number(sizes && sizes.gap, 2)
  var domainGap = number(sizes && sizes.domainGap, 4)
  var pad = number(sizes && sizes.pad, 2)
  var source = layout && typeof layout === "object" ? layout : { mode: "uniform", domains: [] }
  var domains = Array.isArray(source.domains) ? source.domains : []
  var frames = []
  var cells = []
  var die = source.mode === "die"

  if (!die) {
    var uniform = domains[0] && domains[0].rows && domains[0].rows[0]
      ? domains[0].rows[0].cells
      : []
    var count = Array.isArray(uniform) ? uniform.length : 0
    var columns = uniformColumnCount(count)
    var size = coreCellSize("same", sizes)
    var rows = Math.ceil(Math.max(1, count) / columns)
    for (var i = 0; i < count; i++) {
      var col = i % columns
      var row = Math.floor(i / columns)
      cells.push({
        x: col * (size + gap),
        y: row * (size + gap),
        size: size,
        kind: "same",
        name: String(uniform[i].name || "cpu"),
        usage: number(uniform[i].usage),
        logicals: uniform[i].logicals || [String(uniform[i].name || "cpu")]
      })
    }
    return {
      width: count === 0 ? 0 : columns * size + Math.max(0, columns - 1) * gap,
      height: count === 0 ? 0 : rows * size + Math.max(0, rows - 1) * gap,
      frames: [],
      cells: cells
    }
  }

  function mergeEfficiencyIfFits(domainRows) {
    var source = Array.isArray(domainRows) ? domainRows : []
    var pWidth = 0
    var eCells = []
    var eRows = 0
    for (var r = 0; r < source.length; r++) {
      var kind = String(source[r].kind || "same")
      var rowCells = Array.isArray(source[r].cells) ? source[r].cells : []
      if (kind === "performance") {
        pWidth = Math.max(pWidth,
          rowCells.length * coreCellSize(kind, sizes) + Math.max(0, rowCells.length - 1) * gap)
      }
      if (kind === "efficiency") {
        eRows++
        for (var i = 0; i < rowCells.length; i++) eCells.push(rowCells[i])
      }
    }
    if (eRows < 2 || eCells.length === 0 || pWidth <= 0) return source
    var eSize = coreCellSize("efficiency", sizes)
    var oneRowWidth = eCells.length * eSize + Math.max(0, eCells.length - 1) * gap
    if (oneRowWidth > pWidth) return source
    var merged = []
    var inserted = false
    for (r = 0; r < source.length; r++) {
      if (String(source[r].kind || "") === "efficiency") {
        if (!inserted) {
          merged.push({ kind: "efficiency", cells: eCells })
          inserted = true
        }
        continue
      }
      merged.push(source[r])
    }
    return merged
  }

  function domainHasStack(domainRows) {
    return Array.isArray(domainRows) && domainRows.length > 1
  }

  var prepared = []
  for (var s = 0; s < domains.length; s++) {
    prepared.push({
      id: domains[s].id,
      rows: mergeEfficiencyIfFits(domains[s].rows)
    })
  }

  var anyStack = false
  var mixedDomain = false
  for (s = 0; s < prepared.length; s++) {
    if (domainHasStack(prepared[s].rows)) anyStack = true
    var kindsSeen = {}
    var kindCount = 0
    var preparedRows = prepared[s].rows
    for (var kr = 0; kr < preparedRows.length; kr++) {
      var rowKind = String(preparedRows[kr].kind || "same")
      if (kindsSeen[rowKind]) continue
      kindsSeen[rowKind] = true
      kindCount++
    }
    if (kindCount >= 2) mixedDomain = true
  }
  var stackDomains = prepared.length >= 2 && !mixedDomain

  function packedRows(domainRows) {
    var rows = []
    var source = Array.isArray(domainRows) ? domainRows : []
    for (var r = 0; r < source.length; r++) {
      var kind = String(source[r].kind || "same")
      var rowCells = Array.isArray(source[r].cells) ? source[r].cells.slice() : []
      var size = coreCellSize(kind, sizes)
      var rotate = kind !== "performance"
        && source.length === 1
        && rowCells.length >= 2
        && rowCells.length <= 4
        && anyStack
        && !stackDomains
      if (rotate) {
        for (var c = 0; c < rowCells.length; c++)
          rows.push({ kind: kind, size: size, cells: [rowCells[c]], column: true })
        continue
      }
      rows.push({ kind: kind, size: size, cells: rowCells, column: false })
    }
    return rows
  }

  function rowWidth(row) {
    var n = row.cells.length
    if (n === 0) return 0
    return n * row.size + Math.max(0, n - 1) * gap
  }

  function rowsHeight(rows) {
    var height = 0
    for (var r = 0; r < rows.length; r++) {
      if (r > 0) height += gap
      height += rows[r].size
    }
    return height
  }

  var packed = []
  var primaryInnerHeight = 0
  for (var d = 0; d < prepared.length; d++) {
    var measured = packedRows(Array.isArray(prepared[d].rows) ? prepared[d].rows : [])
    var innerWidth = 0
    var column = measured.length > 0
    for (var r = 0; r < measured.length; r++) {
      innerWidth = Math.max(innerWidth, rowWidth(measured[r]))
      if (!measured[r].column) column = false
    }
    var innerHeight = rowsHeight(measured)
    packed.push({
      rows: measured,
      innerWidth: innerWidth,
      innerHeight: innerHeight,
      column: column
    })
    if (!column && innerHeight > primaryInnerHeight) primaryInnerHeight = innerHeight
  }
  if (primaryInnerHeight <= 0) {
    for (d = 0; d < packed.length; d++)
      if (packed[d].innerHeight > primaryInnerHeight) primaryInnerHeight = packed[d].innerHeight
  }

  var placed = []
  var maxFrameWidth = 0
  for (d = 0; d < packed.length; d++) {
    var spec = packed[d]
    var contentHeight = stackDomains ? spec.innerHeight : primaryInnerHeight
    var frameWidth = spec.innerWidth + pad * 2
    placed.push({
      spec: spec,
      frameWidth: frameWidth,
      frameHeight: contentHeight + pad * 2,
      contentHeight: contentHeight
    })
    if (frameWidth > maxFrameWidth) maxFrameWidth = frameWidth
  }

  var x = 0
  var y = 0
  for (d = 0; d < placed.length; d++) {
    var item = placed[d]
    spec = item.spec
    var originX = stackDomains ? Math.round((maxFrameWidth - item.frameWidth) / 2) : x
    var originY = stackDomains ? y : 0
    frames.push({ x: originX, y: originY, w: item.frameWidth, h: item.frameHeight })

    var rowSize = []
    for (var m = 0; m < spec.rows.length; m++) rowSize.push(spec.rows[m].size)

    if (spec.column && spec.rows.length > 0) {
      var columnSpan = spec.rows.length * rowSize[0] + Math.max(0, spec.rows.length - 1) * gap
      if (columnSpan > item.contentHeight) {
        var fitted = Math.max(2, Math.floor(
          (item.contentHeight - Math.max(0, spec.rows.length - 1) * gap) / spec.rows.length
        ))
        for (m = 0; m < rowSize.length; m++) rowSize[m] = fitted
      }
    }

    var stackHeight = 0
    for (m = 0; m < spec.rows.length; m++) {
      if (m > 0) stackHeight += gap
      stackHeight += rowSize[m]
    }
    var cy = originY + pad + Math.round((item.contentHeight - stackHeight) / 2)
    var spanWidth = spec.innerWidth
    for (m = 0; m < spec.rows.length; m++) {
      if (spec.rows[m].kind === "performance") {
        spanWidth = rowWidth(spec.rows[m])
        break
      }
    }

    for (m = 0; m < spec.rows.length; m++) {
      var row = spec.rows[m]
      var n = row.cells.length
      var size = rowSize[m]
      var packedWidth = n * size + Math.max(0, n - 1) * gap
      var cx = originX + pad
      var step = gap
      if (spec.column || row.kind === "performance" || n <= 1) {
        cx = originX + pad + Math.round((spec.innerWidth - packedWidth) / 2)
      } else if (spanWidth > 0 && packedWidth <= spanWidth) {
        cx = originX + pad + Math.round((spec.innerWidth - spanWidth) / 2)
        step = n > 1 ? (spanWidth - n * size) / (n - 1) : gap
      } else {
        cx = originX + pad + Math.round((spec.innerWidth - packedWidth) / 2)
      }
      for (var c = 0; c < n; c++) {
        var cell = row.cells[c]
        cells.push({
          x: cx,
          y: cy,
          size: size,
          kind: row.kind,
          name: String(cell.name || "cpu"),
          usage: number(cell.usage),
          logicals: cell.logicals || [String(cell.name || "cpu")]
        })
        cx += size + step
      }
      cy += size + gap
    }
    if (stackDomains) y += item.frameHeight + domainGap
    else x += item.frameWidth + domainGap
  }

  return {
    width: cells.length === 0 ? 0 : (stackDomains ? maxFrameWidth : Math.max(0, x - domainGap)),
    height: cells.length === 0 ? 0 : (stackDomains ? Math.max(0, y - domainGap) : primaryInnerHeight + pad * 2),
    frames: frames,
    cells: cells
  }
}

var flattenMemo = {}
var catalogMemo = { key: "", value: null }
var emptyPaint = { width: 0, height: 0, frames: [], cells: [] }

function sizesKey(sizes) {
  return [
    number(sizes && sizes.gap, 2),
    number(sizes && sizes.domainGap, 4),
    number(sizes && sizes.pad, 2),
    number(sizes && sizes.performance, 9),
    number(sizes && sizes.efficiency, 6),
    number(sizes && sizes.same, 7)
  ].join(",")
}

function topologySignature(topology) {
  var values = Array.isArray(topology) ? topology : []
  var parts = new Array(values.length)
  for (var i = 0; i < values.length; i++) {
    var entry = values[i] || {}
    parts[i] = number(entry.id) + ":" + String(entry.cls || "") + ":"
      + String(entry.domain || "") + ":" + String(entry.cluster || "") + ":"
      + number(entry.core)
  }
  return parts.join("|")
}

function sameTopology(left, right) {
  if (left === right) return true
  var a = Array.isArray(left) ? left : []
  var b = Array.isArray(right) ? right : []
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    if (number(a[i].id) !== number(b[i].id)
      || String(a[i].cls || "") !== String(b[i].cls || "")
      || String(a[i].domain || "") !== String(b[i].domain || "")
      || String(a[i].cluster || "") !== String(b[i].cluster || "")
      || number(a[i].core) !== number(b[i].core)) {
      return false
    }
  }
  return true
}

function cellUsage(cell, usageByName) {
  var logicals = cell && cell.logicals
  if (!logicals || logicals.length === 0)
    return number(usageByName[String(cell && cell.name || "")])
  var usage = 0
  for (var i = 0; i < logicals.length; i++)
    usage = Math.max(usage, number(usageByName[String(logicals[i])]))
  return usage
}

function applyPaintUsage(paint, metricCores) {
  if (!paint || !Array.isArray(paint.cells)) return paint
  var usageByName = coreUsageLookup(metricCores)
  var source = paint.cells
  var nextCells = new Array(source.length)
  for (var i = 0; i < source.length; i++) {
    var usage = cellUsage(source[i], usageByName)
    if (usage === source[i].usage) {
      nextCells[i] = source[i]
      continue
    }
    nextCells[i] = {
      x: source[i].x,
      y: source[i].y,
      size: source[i].size,
      kind: source[i].kind,
      name: source[i].name,
      usage: usage,
      logicals: source[i].logicals
    }
  }
  return {
    width: paint.width,
    height: paint.height,
    frames: paint.frames,
    cells: nextCells
  }
}

function pruneFlattenMemo() {
  var keys = Object.keys(flattenMemo)
  if (keys.length <= 8) return
  for (var i = 0; i < keys.length - 8; i++) delete flattenMemo[keys[i]]
}

function emptyCorePaint() {
  return emptyPaint
}

function paintCoreLayout(metricCores, topology, sizes, slot) {
  var cores = Array.isArray(metricCores) ? metricCores : []
  var topo = Array.isArray(topology) ? topology : []
  var key = String(slot || "default") + ":" + sizesKey(sizes) + ":"
    + (specializedTopology(topo) ? topologySignature(topo) : "u" + cores.length)
  var geometry = flattenMemo[key]
  if (!geometry) {
    geometry = flattenCoreLayout(coreLayout(cores, topo), sizes)
    flattenMemo[key] = geometry
    pruneFlattenMemo()
  }
  return applyPaintUsage(geometry, cores)
}

function previewTopo(id, cls, domain, cluster, core) {
  return {
    id: id,
    cls: cls,
    domain: domain,
    cluster: String(cluster),
    core: core,
    maxKhz: 0
  }
}

function previewCoresFor(topology) {
  var values = Array.isArray(topology) ? topology : []
  var cores = []
  for (var i = 0; i < values.length; i++) {
    var cls = String(values[i].cls || "same")
    var usage = 12 + (i % 7) * 5
    if (cls === "performance") usage = 48 + (i % 4) * 12
    else if (cls === "efficiency") usage = 16 + (i % 5) * 7
    else if (cls === "lowpower") usage = 5 + (i % 3) * 4
    cores.push({ name: "cpu" + number(values[i].id), usage: usage })
  }
  return cores
}

function previewCoreEntry(id, title, detail, topology, sizes) {
  var cores = previewCoresFor(topology)
  var layout = coreLayout(cores, topology)
  return {
    id: id,
    title: title,
    detail: detail,
    mode: layout.mode,
    paint: flattenCoreLayout(layout, sizes)
  }
}

function previewCoreCatalog(sizes) {
  var key = sizesKey(sizes)
  if (catalogMemo.key === key && catalogMemo.value) return catalogMemo.value

  var panther = []
  var i
  for (i = 0; i < 4; i++) panther.push(previewTopo(i, "performance", "0-11", i, i))
  for (i = 4; i < 8; i++) panther.push(previewTopo(i, "efficiency", "0-11", "4-7", i))
  for (i = 8; i < 12; i++) panther.push(previewTopo(i, "efficiency", "0-11", "8-11", i))
  for (i = 12; i < 16; i++) panther.push(previewTopo(i, "lowpower", "12-15", "12-15", i))

  var pantherSlim = []
  for (i = 0; i < 4; i++) pantherSlim.push(previewTopo(i, "performance", "0-3", i, i))
  for (i = 4; i < 8; i++) pantherSlim.push(previewTopo(i, "lowpower", "4-7", "4-7", i))

  var meteor = []
  for (i = 0; i < 6; i++) meteor.push(previewTopo(i, "performance", "0-13", i, i))
  for (i = 6; i < 14; i++) meteor.push(previewTopo(i, "efficiency", "0-13", i < 10 ? "6-9" : "10-13", i))
  for (i = 14; i < 16; i++) meteor.push(previewTopo(i, "lowpower", "14-15", "14-15", i))

  var alder = []
  for (i = 0; i < 16; i += 2) {
    alder.push(previewTopo(i, "performance", "0-23", i, i))
    alder.push(previewTopo(i + 1, "performance", "0-23", i, i))
  }
  for (i = 16; i < 20; i++) alder.push(previewTopo(i, "efficiency", "0-23", "16-19", i))
  for (i = 20; i < 24; i++) alder.push(previewTopo(i, "efficiency", "0-23", "20-23", i))

  var raptor = []
  for (i = 0; i < 6; i++) raptor.push(previewTopo(i, "performance", "0-13", i, i))
  for (i = 6; i < 14; i++) raptor.push(previewTopo(i, "efficiency", "0-13", i < 10 ? "6-9" : "10-13", i))

  var strix = []
  for (i = 0; i < 4; i++) strix.push(previewTopo(i, "performance", "0-3", "0-3", i))
  for (i = 4; i < 12; i++) strix.push(previewTopo(i, "efficiency", "4-11", "4-11", i))

  var arm = []
  arm.push(previewTopo(0, "performance", "0-7", "0", 0))
  for (i = 1; i < 4; i++) arm.push(previewTopo(i, "efficiency", "0-7", "1-3", i))
  for (i = 4; i < 8; i++) arm.push(previewTopo(i, "lowpower", "0-7", "4-7", i))

  var oryon = []
  for (i = 0; i < 12; i++) oryon.push(previewTopo(i, "performance", "0-11", String(Math.floor(i / 4)), i))

  var desktop = []
  for (i = 0; i < 16; i++) desktop.push(previewTopo(i, "performance", "0-15", i, i))

  var catalog = [
    previewCoreEntry("panther-16", "Panther Lake · 4P + 8E + 4LP-E",
      "Your class of chip. P and E share one L3; LP-E sit in their own square.",
      panther, sizes),
    previewCoreEntry("panther-8", "Panther / Lunar slim · 4P + 4LP-E",
      "No mid E-cluster. Two cache squares stacked.",
      pantherSlim, sizes),
    previewCoreEntry("meteor-16", "Meteor Lake · 6P + 8E + 2LP-E",
      "Compute-tile P+E with a two-core LP-E island on the SoC tile.",
      meteor, sizes),
    previewCoreEntry("alder-24", "Alder / Raptor Lake · 8P SMT + 8E",
      "One shared cache. Hyperthreads collapse into eight larger P-cells.",
      alder, sizes),
    previewCoreEntry("raptor-14", "Raptor Lake · 6P + 8E",
      "Two core classes, one last-level cache.",
      raptor, sizes),
    previewCoreEntry("strix-12", "Strix Point · 4 Zen 5 + 8 Zen 5c",
      "Two CCX squares stacked. Zen 5 over Zen 5c.",
      strix, sizes),
    previewCoreEntry("arm-8", "ARM big.LITTLE · 1 + 3 + 4",
      "One shared DSU. Three size tiers in a single square.",
      arm, sizes),
    previewCoreEntry("oryon-12", "Snapdragon X Elite · 12 equal cores",
      "Three identical clusters. Regular grid, not a hybrid die.",
      oryon, sizes),
    previewCoreEntry("desktop-16", "Homogeneous desktop · 16 threads",
      "Older or all-P packages keep the regular mosaic.",
      desktop, sizes)
  ]
  catalogMemo = { key: key, value: catalog }
  return catalog
}

function processIdentityKey(process) {
  if (!process) return ""
  return String(number(process.pid)) + ":" + String(number(process.startTicks))
}

// This list only gives immediate UI feedback. The plugin-local process helper remains
// authoritative and revalidates identity, ownership, state, and protection
// against live procfs data immediately before taking action.
var protectedProcessNames = [
  "quickshell",
  "hyprland",
  "uwsm",
  "systemd",
  "systemd-executo",
  "systemd-executor",
  "(sd-pam)",
  "dbus-broker",
  "dbus-broker-lau",
  "omarchy-hyprlan"
]

function processActionBlockReason(process, currentUser) {
  if (!process || number(process.pid) <= 1) return "Protected system process"
  if (number(process.startTicks) <= 0) return "Process identity is unavailable"
  if (/^[ZXx]$/.test(String(process.state || ""))) return "Process has already stopped"
  if (String(process.user || "") !== String(currentUser || ""))
    return "Only your own processes can be ended"
  if (protectedProcessNames.indexOf(String(process.name || "").toLowerCase()) >= 0)
    return "Desktop session is protected"
  return ""
}

function processValue(process, key) {
  if (key === "memory") return number(process.memory)
  if (key === "power") return number(process.power, -1)
  if (key === "pid") return number(process.pid)
  if (key === "runtime") return number(process.elapsed)
  if (key === "name") return String(process.name || "").toLowerCase()
  return number(process.cpu)
}

function filterAndSortProcesses(processes, query, sortKey, ascending) {
  var values = Array.isArray(processes) ? processes.slice() : []
  var needle = String(query || "").trim().toLowerCase()
  if (needle) {
    values = values.filter(function(process) {
      return String(process.pid).indexOf(needle) >= 0
        || String(process.name || "").toLowerCase().indexOf(needle) >= 0
        || String(process.user || "").toLowerCase().indexOf(needle) >= 0
    })
  }

  var key = sortKey || "cpu"
  var direction = ascending ? 1 : -1
  values.sort(function(left, right) {
    var a = processValue(left, key)
    var b = processValue(right, key)
    if (a < b) return -1 * direction
    if (a > b) return 1 * direction
    return number(left.pid) - number(right.pid)
  })
  return values
}

function formatBytes(value, suffix) {
  var bytes = Math.max(0, number(value))
  var units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var unit = 0
  while (bytes >= 1024 && unit < units.length - 1) {
    bytes /= 1024
    unit++
  }
  var precision = bytes >= 100 || unit === 0 ? 0 : (bytes >= 10 ? 1 : 2)
  return bytes.toFixed(precision) + " " + units[unit] + (suffix || "")
}

function formatDuration(value) {
  var seconds = Math.max(0, Math.floor(number(value)))
  var days = Math.floor(seconds / 86400)
  var hours = Math.floor((seconds % 86400) / 3600)
  var minutes = Math.floor((seconds % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + minutes + "m"
  if (minutes === 0) return seconds + "s"
  return minutes + "m"
}

function samplingProfile(value) {
  var name = String(value || "balanced").trim().toLowerCase()
  if (name === "efficient") {
    return {
      name: "Efficient",
      resources: 3000,
      processes: 6000,
      thermals: 15000,
      gpus: 4000,
      storage: 60000
    }
  }
  if (name === "fast" || name === "responsive") {
    return {
      name: "Fast",
      resources: 750,
      processes: 1500,
      thermals: 5000,
      gpus: 1000,
      storage: 15000
    }
  }
  return {
    name: "Balanced",
    resources: 1500,
    processes: 3000,
    thermals: 10000,
    gpus: 2000,
    storage: 30000
  }
}

function formatTemperature(value, unit) {
  var celsius = Number(value)
  if (!isFinite(celsius)) return "—"
  var fahrenheit = String(unit || "Celsius").toLowerCase() === "fahrenheit"
  var displayed = fahrenheit ? celsius * 9 / 5 + 32 : celsius
  return Math.round(displayed) + (fahrenheit ? "°F" : "°C")
}

function temperatureRank(temperature) {
  var chip = String(temperature && temperature.chip || "").toLowerCase()
  var label = String(temperature && temperature.label || "").toLowerCase()
  if (chip === "coretemp" && label.indexOf("package id") >= 0) return 0
  if (chip === "k10temp" && label === "tctl") return 1
  if (label.indexOf("cpu") >= 0 || label.indexOf("package") >= 0 || label === "tctl") return 2
  if (chip === "coretemp" || chip === "k10temp") return 3
  return 100
}

function cpuTemperature(temperatures) {
  var values = Array.isArray(temperatures) ? temperatures : []
  var selected = null
  var selectedRank = 100
  for (var i = 0; i < values.length; i++) {
    var value = number(values[i].value)
    if (value <= 0 || value >= 150) continue
    var rank = temperatureRank(values[i])
    if (rank < selectedRank || (rank === selectedRank && selected && value > selected.value)) {
      selected = values[i]
      selectedRank = rank
    }
  }
  return selectedRank < 100 ? selected : null
}

if (typeof module !== "undefined") {
  module.exports = {
    clamp: clamp,
    emptySnapshot: emptySnapshot,
    emptyMetrics: emptyMetrics,
    emptyProcessSnapshot: emptyProcessSnapshot,
    emptyThermalSnapshot: emptyThermalSnapshot,
    emptyPackagePowerSnapshot: emptyPackagePowerSnapshot,
    emptyPower: emptyPower,
    emptyStorageSnapshot: emptyStorageSnapshot,
    emptyGpuSnapshot: emptyGpuSnapshot,
    parseSnapshot: parseSnapshot,
    parseProcessSnapshot: parseProcessSnapshot,
    parseThermalSnapshot: parseThermalSnapshot,
    parsePackagePowerSnapshot: parsePackagePowerSnapshot,
    parseStorageSnapshot: parseStorageSnapshot,
    parseGpuSnapshot: parseGpuSnapshot,
    packageEnergyReadable: packageEnergyReadable,
    packageCountersComparable: packageCountersComparable,
    packageEnergyDelta: packageEnergyDelta,
    nextPackagePower: nextPackagePower,
    nextGpus: nextGpus,
    counterPercent: counterPercent,
    counterRate: counterRate,
    memoryPercent: memoryPercent,
    swapPercent: swapPercent,
    appendHistory: appendHistory,
    coreUsage: coreUsage,
    selectNetwork: selectNetwork,
    diskId: diskId,
    aggregateDisks: aggregateDisks,
    diskDeviceRates: diskDeviceRates,
    diskCycleItems: diskCycleItems,
    selectDiskItem: selectDiskItem,
    storageVolumes: storageVolumes,
    storageUsedFraction: storageUsedFraction,
    tightestStorageVolume: tightestStorageVolume,
    selectStorageVolume: selectStorageVolume,
    storageVolumeLabel: storageVolumeLabel,
    nextCycleIndex: nextCycleIndex,
    cycleItemId: cycleItemId,
    baselineMetrics: baselineMetrics,
    nextMetrics: nextMetrics,
    nextProcesses: nextProcesses,
    specializedTopology: specializedTopology,
    sameTopology: sameTopology,
    coreLayout: coreLayout,
    flattenCoreLayout: flattenCoreLayout,
    paintCoreLayout: paintCoreLayout,
    emptyCorePaint: emptyCorePaint,
    previewCoreCatalog: previewCoreCatalog,
    processSystemBusyDelta: processSystemBusyDelta,
    estimateProcessPower: estimateProcessPower,
    processIdentityKey: processIdentityKey,
    processActionBlockReason: processActionBlockReason,
    filterAndSortProcesses: filterAndSortProcesses,
    formatBytes: formatBytes,
    formatDuration: formatDuration,
    samplingProfile: samplingProfile,
    formatTemperature: formatTemperature,
    cpuTemperature: cpuTemperature
  }
}
