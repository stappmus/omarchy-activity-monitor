#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const activity = requireFromRoot('Model.js')

const first = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t1000',
  'frequency\tcpu\t2400\tMHz',
  'frequency\tmemory\t6400\tMT/s',
  'cpu\tcpu\t1000\t700',
  'cpu\tcpu0\t500\t350',
  'cpu\tcpu1\t500\t350',
  'memory\t1000\t400\t200\t150\t125',
  'tasks\t2\t100',
  'network\teth0\t10000\t20000\tup\t1\t1',
  'network\ttailscale0\t500000\t600000\tup\t0\t0',
  'disk\t8:0\tsda\t100\t200',
  ''
].join('\n'))

assertEqual(first.sample, 1000, 'activity parses the monotonic resource sample')
assertEqual(first.cpuFrequencyMHz, 2400, 'activity parses the average current CPU clock')
assertEqual(first.memorySpeedMTs, 6400, 'activity parses the configured DDR transfer rate')
assertEqual(first.cores.length, 2, 'activity parses per-core counters')
assertEqual(first.memory.cached, 125 * 1024, 'activity parses reclaimable cache')
assertEqual(first.memory.swapTotal, 200 * 1024, 'activity parses swap counters')
assertEqual(
  activity.parseSnapshot('schema\tactivity-processes\t1\nsample\t1000\n').schema,
  0,
  'activity rejects a mismatched snapshot contract'
)

const second = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t1001',
  'frequency\tcpu\t2600\tMHz',
  'frequency\tmemory\t6400\tMT/s',
  'cpu\tcpu\t1200\t800',
  'cpu\tcpu0\t600\t390',
  'cpu\tcpu1\t600\t410',
  'memory\t1000\t350\t200\t100\t120',
  'tasks\t3\t110',
  'network\teth0\t12048\t21024\tup\t1\t1',
  'network\ttailscale0\t900000\t1000000\tup\t0\t0',
  'disk\t8:0\tsda\t108\t204',
  ''
].join('\n'))

const metrics = activity.nextMetrics(first, second, {}, 2)
assertEqual(metrics.cpu, 50, 'activity derives CPU usage from counter deltas')
assertEqual(metrics.memory, 65, 'activity derives memory usage')
assertEqual(metrics.swap, 50, 'activity derives swap usage')
assertEqual(metrics.download, 2048, 'activity derives network receive rate')
assertEqual(metrics.upload, 1024, 'activity derives network transmit rate')
assertEqual(metrics.diskRead, 4096, 'activity derives disk read rate')
assertEqual(metrics.diskWrite, 2048, 'activity derives disk write rate')
assertEqual(metrics.diskDevices.length, 1, 'activity keeps a single disk as one device')
assertEqual(metrics.diskDevices[0].name, 'sda', 'activity names the sampled disk')
assertEqual(activity.diskCycleItems(metrics).length, 1, 'activity does not page a single disk')
assertEqual(metrics.cores[0].usage, 60, 'activity derives per-core usage')
assertEqual(metrics.networkInterface, 'eth0', 'activity follows the default interface without double-counting tunnels')

const firstMultiDisk = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t2000',
  'disk\t8:0\tsda\t100\t200',
  'disk\t259:0\tnvme0n1\t50\t80',
  ''
].join('\n'))
const secondMultiDisk = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t2001',
  'disk\t8:0\tsda\t108\t204',
  'disk\t259:0\tnvme0n1\t58\t88',
  ''
].join('\n'))
const multiDisk = activity.nextMetrics(firstMultiDisk, secondMultiDisk, {}, 4)
assertEqual(multiDisk.diskRead, 8192, 'activity sums read rates across disks')
assertEqual(multiDisk.diskWrite, 6144, 'activity sums write rates across disks')
assertEqual(multiDisk.diskDevices.length, 2, 'activity keeps per-disk rates')
assertEqual(multiDisk.diskDevices[0].name, 'nvme0n1', 'activity sorts disks by name')
assertEqual(multiDisk.diskDevices[0].read, 4096, 'activity derives the first disk read rate')
assertEqual(multiDisk.diskDevices[1].write, 2048, 'activity derives the second disk write rate')
const diskItems = activity.diskCycleItems(multiDisk)
assertEqual(diskItems.length, 3, 'activity prepends an All slot when there are multiple disks')
assertEqual(diskItems[0].id, 'all', 'activity starts the disk pager on the combined total')
assertEqual(diskItems[0].read, 8192, 'activity All slot uses the combined read rate')
assertEqual(activity.selectDiskItem(diskItems, '8:0').name, 'sda', 'activity can select a named disk')
assertEqual(activity.cycleItemId(diskItems, 'all', 'id', 1), '259:0', 'activity cycles from All to the first named disk')
assertEqual(activity.cycleItemId(diskItems, '8:0', 'id', 1), 'all', 'activity wraps the disk pager')

const hotplugDisk = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t2002',
  'disk\t8:0\tsda\t116\t208',
  'disk\t8:16\tsdb\t10\t20',
  'disk\t259:0\tnvme0n1\t66\t96',
  ''
].join('\n'))
const afterHotplug = activity.nextMetrics(secondMultiDisk, hotplugDisk, multiDisk, 4)
assertEqual(afterHotplug.diskRead, 8192, 'activity keeps existing disk rates when a disk appears')
assertEqual(afterHotplug.diskDevices.length, 3, 'activity adds a newly attached disk')
assertEqual(
  afterHotplug.diskDevices.find(disk => disk.name === 'sdb').read,
  0,
  'activity baselines a newly attached disk at zero'
)
assertEqual(afterHotplug.diskHistories['259:0'].length, 2, 'activity keeps per-disk sparkline history')

const withHistory = activity.nextMetrics(second, second, {
  cpuHistory: [10, 20],
  memoryHistory: [30, 40]
}, 2)
assertDeepEqual(withHistory.cpuHistory, [20, 0], 'activity caps history buffers')
assertEqual(activity.counterPercent({ total: 100, idle: 20 }, { total: 50, idle: 10 }), 0, 'activity handles reset CPU counters')
assertEqual(activity.counterRate(100, 50, 1), 0, 'activity handles reset byte counters')

const baseline = activity.baselineMetrics(second, {
  cpu: 42,
  download: 100,
  upload: 50,
  diskRead: 25,
  diskWrite: 10,
  cpuHistory: [20, 42],
  memoryHistory: [60, 65]
})
assertEqual(baseline.cpu, 42, 'activity retains the last CPU rate while taking a fresh baseline')
assertEqual(baseline.memory, 65, 'activity immediately refreshes single-sample memory usage')
assertDeepEqual(baseline.cpuHistory, [20, 42], 'activity does not add zeroes while taking a fresh baseline')

const firstProcesses = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t100\t100',
  'process\t42\talice\tS\t1000\t500\t100\tcode helper',
  ''
].join('\n'))
const secondProcesses = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t102\t100',
  'process\t42\talice\tR\t1000\t600\t100\tcode helper',
  ''
].join('\n'))
const sampledProcesses = activity.nextProcesses(firstProcesses, secondProcesses, 1000 * 1024)
assertEqual(sampledProcesses[0].name, 'code helper', 'activity preserves process names with spaces')
assertEqual(sampledProcesses[0].user, 'alice', 'activity resolves process users')
assertEqual(sampledProcesses[0].cpu, 50, 'activity derives sampled process CPU')
assertEqual(sampledProcesses[0].memory, 10, 'activity derives process memory share')
assertEqual(sampledProcesses[0].elapsed, 92, 'activity derives process runtime from monotonic uptime')
const reusedPid = activity.parseProcessSnapshot(
  'schema\tactivity-processes\t1\nsample\t104\t100\nprocess\t42\talice\tR\t2000\t900\t100\tnew process\n'
)
assertEqual(
  activity.nextProcesses(secondProcesses, reusedPid, 1000 * 1024)[0].cpu,
  0,
  'activity does not carry CPU history across PID reuse'
)

const processes = [
  { pid: 3, name: 'firefox', user: 'alice', cpu: 4, memory: 10, elapsed: 50 },
  { pid: 1, name: 'quickshell', user: 'alice', cpu: 8, memory: 2, elapsed: 100 },
  { pid: 2, name: 'postgres', user: 'postgres', cpu: 1, memory: 20, elapsed: 200 }
]
assertDeepEqual(
  activity.filterAndSortProcesses(processes, '', 'cpu', false).map(process => process.pid),
  [1, 3, 2],
  'activity sorts processes by CPU'
)
assertDeepEqual(
  activity.filterAndSortProcesses(processes, 'post', 'memory', false).map(process => process.pid),
  [2],
  'activity filters processes by name and user'
)
assertEqual(
  activity.processIdentityKey({ pid: 42, startTicks: 1234 }),
  '42:1234',
  'activity ties process selection to PID and sampled start time'
)
assertEqual(
  activity.processActionBlockReason(
    { pid: 42, startTicks: 1234, state: 'S', user: 'alice', name: 'firefox' },
    'alice'
  ),
  '',
  'activity allows an actionable same-user app'
)
assertEqual(
  activity.processActionBlockReason(
    { pid: 42, startTicks: 1234, state: 'S', user: 'alice', name: 'quickshell' },
    'alice'
  ),
  'Desktop session is protected',
  'activity gives immediate feedback for a protected session process'
)
assertEqual(
  activity.processActionBlockReason(
    { pid: 42, startTicks: 1234, state: 'S', user: 'root', name: 'worker' },
    'alice'
  ),
  'Only your own processes can be ended',
  'activity gives immediate feedback for a foreign process'
)
assertEqual(activity.formatBytes(1536, '/s'), '1.50 KiB/s', 'activity formats byte rates')
assertEqual(activity.formatDuration(42), '42s', 'activity formats short process runtimes')
assertEqual(activity.formatDuration(90061), '1d 1h', 'activity formats long durations')
assertEqual(activity.samplingProfile('Efficient').resources, 3000, 'activity offers a low-overhead sampling profile')
assertEqual(activity.samplingProfile('Balanced').processes, 3000, 'activity keeps the balanced process cadence')
assertEqual(activity.samplingProfile('Fast').resources, 750, 'activity offers a responsive sampling profile')
assertEqual(activity.samplingProfile('unknown').name, 'Balanced', 'activity safely defaults unknown sampling profiles')
assertEqual(activity.formatTemperature(20, 'Celsius'), '20°C', 'activity formats Celsius temperatures')
assertEqual(activity.formatTemperature(20, 'Fahrenheit'), '68°F', 'activity converts temperatures to Fahrenheit')

function topo(id, cls, domain, cluster, core) {
  return { id, cls, domain, cluster, core, maxKhz: 0 }
}
function usages(count) {
  return Array.from({ length: count }, (_, i) => ({ name: 'cpu' + i, usage: i + 1 }))
}
const panther = []
for (let i = 0; i < 4; i++) panther.push(topo(i, 'performance', '0-11', String(i), i))
for (let i = 4; i < 8; i++) panther.push(topo(i, 'efficiency', '0-11', '4-7', i))
for (let i = 8; i < 12; i++) panther.push(topo(i, 'efficiency', '0-11', '8-11', i))
for (let i = 12; i < 16; i++) panther.push(topo(i, 'lowpower', '12-15', '12-15', i))
const pantherDie = activity.coreLayout(usages(16), panther)
assertEqual(pantherDie.mode, 'die', 'activity uses a specialized die for P+E+LP-E')
assertEqual(pantherDie.domains.length, 2, 'activity separates Panther Lake cache domains')
assertDeepEqual(pantherDie.domains[0].rows.map(row => row.kind + ':' + row.cells.length),
  ['performance:4', 'efficiency:4', 'efficiency:4'],
  'activity places 4 P-cores above two E-core rows in the shared-cache square')
assertEqual(pantherDie.domains[1].rows[0].kind, 'lowpower', 'activity keeps LP-E cores in their own square')
assertEqual(pantherDie.domains[1].rows[0].cells.length, 4, 'activity shows four LP-E cores')
const pantherPaint = activity.flattenCoreLayout(pantherDie, {
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
assertEqual(pantherPaint.frames.length, 2, 'activity paints a frame per cache domain')
assertEqual(pantherPaint.frames[0].h, pantherPaint.frames[1].h,
  'activity keeps both cache squares the same height')
assertEqual(pantherPaint.frames[1].w < pantherPaint.frames[0].w, true,
  'activity rotates the LP-E cache into a narrower column')
assertEqual(pantherPaint.cells.length, 16, 'activity paints every hybrid core as a positioned cell')
assertEqual(pantherPaint.cells[0].size, 9, 'activity draws P-cores larger than E-cores')
assertEqual(pantherPaint.cells[4].size, 6, 'activity draws E-cores at the cluster size')
assertEqual(pantherPaint.cells[4].kind, 'efficiency', 'activity starts the E-core rows after the P-cores')
assertEqual(pantherPaint.cells[8].kind, 'efficiency', 'activity keeps a second E-core row in the shared-cache square')
assertEqual(pantherPaint.cells[12].kind, 'lowpower', 'activity paints LP-E cores after the shared-cache square')
assertEqual(pantherPaint.cells[12].x === pantherPaint.cells[15].x, true,
  'activity stacks LP-E cores in a column')
assertEqual(pantherPaint.cells[15].y > pantherPaint.cells[12].y, true,
  'activity spreads the LP-E column down the tall cache')
assertEqual(Math.abs(pantherPaint.cells[4].x - pantherPaint.cells[0].x) < 1, true,
  'activity does not place the leftmost E-core outside the P-core row')
assertEqual(
  Math.abs((pantherPaint.cells[7].x + pantherPaint.cells[7].size)
    - (pantherPaint.cells[3].x + pantherPaint.cells[3].size)) < 1,
  true,
  'activity does not place the rightmost E-core outside the P-core row'
)
assertEqual(pantherPaint.cells[5].x > pantherPaint.cells[4].x, true,
  'activity spreads E-cores between the P-core edges')
const lpFrame = pantherPaint.frames[1]
const lpMidX = pantherPaint.cells[12].x + pantherPaint.cells[12].size / 2
assertEqual(Math.abs(lpMidX - (lpFrame.x + lpFrame.w / 2)) < 1, true,
  'activity centers LP-E cores horizontally in the small cache')
const lpTop = pantherPaint.cells[12].y - lpFrame.y
const lpBottom = (lpFrame.y + lpFrame.h) - (pantherPaint.cells[15].y + pantherPaint.cells[15].size)
assertEqual(Math.abs(lpTop - lpBottom) <= 1, true,
  'activity centers the LP-E column vertically in the small cache')
const paintedAgain = activity.paintCoreLayout(
  usages(16).map(core => ({ name: core.name, usage: core.usage + 5 })),
  panther,
  { gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7 },
  'live'
)
const paintedFirst = activity.paintCoreLayout(
  usages(16),
  panther,
  { gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7 },
  'live'
)
assertEqual(paintedFirst.cells[0].x, paintedAgain.cells[0].x,
  'activity reuses die geometry when only usage changes')
assertEqual(paintedFirst.frames, paintedAgain.frames,
  'activity keeps cache-domain frames stable across usage samples')
assertEqual(paintedAgain.cells[3].usage > paintedFirst.cells[3].usage, true,
  'activity still refreshes per-core usage on a cached die')

const meteor = []
for (let i = 0; i < 6; i++) meteor.push(topo(i, 'performance', '0-13', String(i), i))
for (let i = 6; i < 14; i++) meteor.push(topo(i, 'efficiency', '0-13', i < 10 ? '6-9' : '10-13', i))
for (let i = 14; i < 16; i++) meteor.push(topo(i, 'lowpower', '14-15', '14-15', i))
const meteorDie = activity.coreLayout(usages(16), meteor)
assertEqual(meteorDie.domains[0].rows[0].cells.length, 6, 'activity keeps six Meteor Lake P-cores in one row')
assertEqual(meteorDie.domains[1].rows[0].cells.length, 2, 'activity isolates Meteor Lake LP-E cores')
const meteorPaint = activity.flattenCoreLayout(meteorDie, {
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
const meteorE = meteorPaint.cells.filter(cell => cell.kind === 'efficiency')
assertEqual(meteorE.length, 8, 'activity paints eight Meteor Lake E-cores')
assertEqual(meteorE.every(cell => cell.y === meteorE[0].y), true,
  'activity keeps Meteor Lake E-cores on one row under six P-cores')

const alder = []
for (let i = 0; i < 16; i += 2) alder.push(topo(i, 'performance', '0-23', String(i), i), topo(i + 1, 'performance', '0-23', String(i), i))
for (let i = 16; i < 20; i++) alder.push(topo(i, 'efficiency', '0-23', '16-19', i))
for (let i = 20; i < 24; i++) alder.push(topo(i, 'efficiency', '0-23', '20-23', i))
const alderDie = activity.coreLayout(usages(24), alder)
assertEqual(alderDie.mode, 'die', 'activity specializes Alder Lake P+E')
assertEqual(alderDie.domains.length, 1, 'activity keeps a single Alder Lake cache domain together')
assertEqual(alderDie.domains[0].rows[0].cells.length, 8, 'activity collapses SMT siblings into one P-core cell')
assertEqual(alderDie.domains[0].rows[0].cells[0].logicals.length, 2, 'activity tracks both threads inside a P-core cell')
const alderPaint = activity.flattenCoreLayout(alderDie, {
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
const alderE = alderPaint.cells.filter(cell => cell.kind === 'efficiency')
assertEqual(alderE.length, 8, 'activity paints eight Alder Lake E-cores')
assertEqual(alderE.every(cell => cell.y === alderE[0].y), true,
  'activity keeps Alder Lake E-cores on one row under eight P-cores')

const raptor = []
for (let i = 0; i < 6; i++) raptor.push(topo(i, 'performance', '0-13', String(i), i))
for (let i = 6; i < 14; i++) raptor.push(topo(i, 'efficiency', '0-13', i < 10 ? '6-9' : '10-13', i))
const raptorPaint = activity.flattenCoreLayout(activity.coreLayout(usages(14), raptor), {
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
const raptorE = raptorPaint.cells.filter(cell => cell.kind === 'efficiency')
assertEqual(raptorE.length, 8, 'activity paints eight Raptor Lake E-cores')
assertEqual(raptorE.every(cell => cell.y === raptorE[0].y), true,
  'activity keeps Raptor Lake E-cores on one row under six P-cores')

const lunar = []
for (let i = 0; i < 4; i++) lunar.push(topo(i, 'performance', '0-3', String(i), i))
for (let i = 4; i < 8; i++) lunar.push(topo(i, 'lowpower', '4-7', '4-7', i))
const lunarDie = activity.coreLayout(usages(8), lunar)
assertEqual(lunarDie.domains.length, 2, 'activity splits Lunar Lake P-cores from LP-E')
assertEqual(lunarDie.domains[0].rows[0].kind, 'performance', 'activity shows Lunar Lake P-cores as the primary square')
const lunarPaint = activity.flattenCoreLayout(lunarDie, {
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
assertEqual(lunarPaint.frames[1].y > lunarPaint.frames[0].y, true,
  'activity stacks Lunar Lake cache squares instead of placing them in a row')
assertEqual(lunarPaint.frames[1].x >= lunarPaint.frames[0].x, true,
  'activity centers the narrower Lunar Lake LP-E square under the P-cores')
const lunarP = lunarPaint.cells.filter(cell => cell.kind === 'performance')
const lunarLp = lunarPaint.cells.filter(cell => cell.kind === 'lowpower')
assertEqual(lunarP.every(cell => cell.y === lunarP[0].y), true,
  'activity keeps Lunar Lake P-cores on one row')
assertEqual(lunarLp.every(cell => cell.y === lunarLp[0].y), true,
  'activity keeps Lunar Lake LP-E cores on one row')
assertEqual(lunarLp[0].y > lunarP[0].y, true,
  'activity places Lunar Lake LP-E under the P-cores')
assertEqual(lunarPaint.width < lunarPaint.frames[0].w + lunarPaint.frames[1].w,
  true, 'activity stacks Lunar Lake caches to take less width')

const strix = []
for (let i = 0; i < 4; i++) strix.push(topo(i, 'performance', '0-3', '0-3', i))
for (let i = 4; i < 12; i++) strix.push(topo(i, 'efficiency', '4-11', '4-11', i))
const strixDie = activity.coreLayout(usages(12), strix)
assertEqual(strixDie.domains.length, 2, 'activity splits Strix Point Zen 5 and Zen 5c CCX squares')
assertEqual(strixDie.domains[0].rows[0].cells.length, 4, 'activity shows four Zen 5 cores in the larger square')
assertEqual(strixDie.domains[1].rows.length, 2, 'activity keeps Zen 5c cores as two rows in their CCX')
assertEqual(strixDie.domains[1].rows[0].cells.length, 4, 'activity shows four Zen 5c cores per row')
const strixPaint = activity.flattenCoreLayout(strixDie, {
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
assertEqual(strixPaint.frames[1].y > strixPaint.frames[0].y, true,
  'activity stacks Strix Point CCX squares instead of placing them in a row')
const strixP = strixPaint.cells.filter(cell => cell.kind === 'performance')
const strixE = strixPaint.cells.filter(cell => cell.kind === 'efficiency')
assertEqual(strixE[0].y > strixP[0].y, true,
  'activity places Strix Point Zen 5c under the Zen 5 cores')
assertEqual(strixPaint.width < strixPaint.frames[0].w + strixPaint.frames[1].w,
  true, 'activity stacks Strix Point caches to take less width')

const arm = []
for (let i = 0; i < 1; i++) arm.push(topo(i, 'performance', '0-7', '0', i))
for (let i = 1; i < 4; i++) arm.push(topo(i, 'efficiency', '0-7', '1-3', i))
for (let i = 4; i < 8; i++) arm.push(topo(i, 'lowpower', '0-7', '4-7', i))
const armDie = activity.coreLayout(usages(8), arm)
assertEqual(armDie.domains.length, 1, 'activity keeps a shared-DSU ARM cluster in one square')
assertDeepEqual(armDie.domains[0].rows.map(row => row.kind + ':' + row.cells.length),
  ['performance:1', 'efficiency:3', 'lowpower:4'],
  'activity stacks ARM big.LITTLE tiers by class')
const armPaint = activity.flattenCoreLayout(armDie, {
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
const armP = armPaint.cells.filter(cell => cell.kind === 'performance')
const armE = armPaint.cells.filter(cell => cell.kind === 'efficiency')
const armLp = armPaint.cells.filter(cell => cell.kind === 'lowpower')
assertEqual(armP.length, 1, 'activity paints one ARM big core')
assertEqual(armE.length, 3, 'activity paints three ARM middle cores')
assertEqual(armLp.length, 4, 'activity paints four ARM little cores')
assertEqual(armE.every(cell => cell.y === armE[0].y), true, 'activity keeps ARM middle cores on one row')
assertEqual(armLp.every(cell => cell.y === armLp[0].y), true, 'activity keeps ARM little cores on one row')
assertEqual(armE[0].y > armP[0].y, true, 'activity stacks ARM tiers with the big core on top')
assertEqual(armLp[0].y > armE[0].y, true, 'activity stacks ARM little cores under the middle row')
const armMid = armPaint.frames[0].x + armPaint.frames[0].w / 2
assertEqual(Math.abs(armP[0].x + armP[0].size / 2 - armMid) < 1, true,
  'activity centers the ARM big core over the shared DSU')
assertEqual(Math.abs((armLp[0].x + armLp[3].x + armLp[3].size) / 2 - armMid) < 1, true,
  'activity centers the ARM little-core row in the shared DSU')

const uniform = Array.from({ length: 16 }, (_, i) => topo(i, 'performance', '0-15', String(i), i))
assertEqual(activity.coreLayout(usages(16), uniform).mode, 'uniform',
  'activity keeps a homogeneous desktop CPU on the regular grid')
assertEqual(activity.coreLayout(usages(8), []).mode, 'uniform',
  'activity falls back to the regular grid without topology')
const catalog = activity.previewCoreCatalog({
  gap: 2, domainGap: 4, pad: 2, performance: 9, efficiency: 6, same: 7
})
assertEqual(catalog.length >= 8, true, 'activity offers a review catalog of CPU layouts')
assertDeepEqual(catalog.map(entry => entry.id), [
  'panther-16', 'panther-8', 'meteor-16', 'alder-24', 'raptor-14',
  'strix-12', 'arm-8', 'oryon-12', 'desktop-16'
], 'activity previews the researched hybrid and homogeneous layouts')
assertEqual(catalog[0].paint.frames.length, 2, 'activity catalog paints the Panther Lake die')
assertEqual(catalog[7].mode, 'uniform', 'activity catalog keeps Snapdragon X Elite on the regular grid')

const parsedTopo = activity.parseSnapshot([
  'schema\tactivity-resources\t1',
  'sample\t1',
  'cpu-topo\t0\tperformance\t0-11\t0\t0\t4800000',
  'cpu-topo\t4\tefficiency\t0-11\t4-7\t4\t3700000',
  'cpu-topo\t12\tlowpower\t12-15\t12-15\t12\t3300000',
  ''
].join('\n'))
assertEqual(parsedTopo.topology.length, 3, 'activity parses cpu-topo lines into the resource snapshot')
assertEqual(parsedTopo.topology[2].cls, 'lowpower', 'activity preserves LP-E classification')

const manifest = requireFromRoot('manifest.json')
const settingKeys = manifest.barWidget.schema.map(entry => entry.key)
assertDeepEqual(
  settingKeys,
  ['samplingSpeed', 'historySamples', 'temperatureUnit', 'barGraph', 'barGraphLength', 'showFrequencies', 'openExpanded', 'processPowerEnabled'],
  'activity publishes the same focused preferences offered by its settings menu'
)
assertEqual(
  manifest.barWidget.defaults.barGraph,
  'Off',
  'activity leaves the bar graph off until it is asked for'
)
JS

snapshot=$("$ROOT/activity-stats" --activity-resources)
grep -Eq '^schema[[:space:]]+activity-resources[[:space:]]+1$' <<<"$snapshot" || fail "activity collector emits its schema"
grep -Eq '^sample[[:space:]][0-9]+([.][0-9]+)?$' <<<"$snapshot" || fail "activity collector emits a monotonic sample"
grep -Eq '^cpu[[:space:]]+cpu[[:space:]]' <<<"$snapshot" || fail "activity collector emits CPU counters"
grep -Eq '^memory[[:space:]]' <<<"$snapshot" || fail "activity collector emits memory counters"
grep -Eq '^network[[:space:]]' <<<"$snapshot" || fail "activity collector emits network counters"
grep -Eq '^disk[[:space:]]' <<<"$snapshot" || fail "activity collector emits disk counters"
pass "activity collector emits the resource snapshot contract"

write_cpu_topo() {
  local sys="$1" id="$2" core="$3" cluster="$4" l2="$5" l3="$6" khz="$7"
  local cpu="$sys/devices/system/cpu/cpu$id"
  mkdir -p "$cpu/topology" "$cpu/cache/index2" "$cpu/cpufreq"
  printf '%s\n' "$core" >"$cpu/topology/core_id"
  printf '%s\n' "$cluster" >"$cpu/topology/cluster_cpus_list"
  printf '2\n' >"$cpu/cache/index2/level"
  printf 'Unified\n' >"$cpu/cache/index2/type"
  printf '%s\n' "$l2" >"$cpu/cache/index2/shared_cpu_list"
  if [[ -n $l3 ]]; then
    mkdir -p "$cpu/cache/index3"
    printf '3\n' >"$cpu/cache/index3/level"
    printf 'Unified\n' >"$cpu/cache/index3/type"
    printf '%s\n' "$l3" >"$cpu/cache/index3/shared_cpu_list"
  fi
  printf '%s\n' "$khz" >"$cpu/cpufreq/cpuinfo_max_freq"
}

topo_root=$(mktemp -d)
mkdir -p "$topo_root/sys/devices/cpu_core" "$topo_root/sys/devices/cpu_atom"
printf '0-3\n' >"$topo_root/sys/devices/cpu_core/cpus"
printf '4-15\n' >"$topo_root/sys/devices/cpu_atom/cpus"
for id in 0 1 2 3; do
  write_cpu_topo "$topo_root/sys" "$id" "$id" "$id" "$id" "0-11" 4800000
done
for id in 4 5 6 7; do
  write_cpu_topo "$topo_root/sys" "$id" "$id" "4-7" "4-7" "0-11" 3700000
done
for id in 8 9 10 11; do
  write_cpu_topo "$topo_root/sys" "$id" "$id" "8-11" "8-11" "0-11" 3700000
done
for id in 12 13 14 15; do
  write_cpu_topo "$topo_root/sys" "$id" "$id" "12-15" "12-15" "" 3300000
done
topo_snapshot=$(
  OMARCHY_SYSTEM_STATS_SYS_PATH="$topo_root/sys" \
    "$ROOT/activity-stats" --activity-resources
)
rm -rf -- "$topo_root"
[[ $(grep -c $'^cpu-topo\t' <<<"$topo_snapshot") -eq 16 ]] ||
  fail "activity collector does not emit a topology row for every logical CPU"
[[ $(grep -c $'^cpu-topo\t[0-9]\tperformance\t0-11\t' <<<"$topo_snapshot") -eq 4 ]] ||
  fail "activity collector does not classify Intel P-cores"
[[ $(grep -c $'\tefficiency\t0-11\t' <<<"$topo_snapshot") -eq 8 ]] ||
  fail "activity collector does not classify Intel E-cores that share the P-core L3"
[[ $(grep -c $'\tlowpower\t12-15\t' <<<"$topo_snapshot") -eq 4 ]] ||
  fail "activity collector does not isolate LP-E cores without that L3"
pass "activity collector classifies hybrid CPU cache domains"

gpu_snapshot=$("$ROOT/activity-stats" --activity-gpus)
grep -Eq '^schema[[:space:]]+activity-gpus[[:space:]]+1$' <<<"$gpu_snapshot" ||
  fail "activity GPU collector emits its schema"
grep -Eq '^sample[[:space:]][0-9]+([.][0-9]+)?$' <<<"$gpu_snapshot" ||
  fail "activity GPU collector emits a monotonic sample"
pass "activity collector emits the independent GPU snapshot contract"

process_snapshot=$("$ROOT/activity-stats" --activity-processes)
grep -Eq '^schema[[:space:]]+activity-processes[[:space:]]+1$' <<<"$process_snapshot" || fail "activity process collector emits its schema"
grep -Eq '^sample[[:space:]][0-9]+([.][0-9]+)?[[:space:]][0-9]+[[:space:]][0-9]+$' <<<"$process_snapshot" ||
  fail "activity process collector emits its sample and CPU clocks"
grep -Eq '^process[[:space:]]' <<<"$process_snapshot" || fail "activity process collector emits process rows"
pass "activity collector emits the process snapshot contract"

[[ -x $ROOT/activity-sampler ]] || fail "native activity sampler is executable"
[[ $("$ROOT/activity-sampler" --version) == "activity-sampler 2.1.1" ]] ||
  fail "native activity sampler reports the release protocol version"
[[ ! -e $ROOT/activity-process-stats ]] ||
  fail "legacy process helper remains beside the unified native sampler"
pass "activity ships one native sampler instead of a process-helper chain"

reader_snapshot=$(
  printf 'resources\nprocesses\nprocesses\nthermals\ngpus\nstorage\n' |
    "$ROOT/activity-stats" --activity-reader
)
[[ $(grep -c '^snapshot-end' <<<"$reader_snapshot") -eq 6 ]] ||
  fail "activity reader does not frame every requested snapshot"
grep -Fq $'snapshot-end\tresources' <<<"$reader_snapshot" ||
  fail "activity reader does not frame resource snapshots"
grep -Fq $'snapshot-end\tprocesses' <<<"$reader_snapshot" ||
  fail "activity reader does not frame process snapshots"
[[ $(grep -c $'^snapshot-end\tprocesses$' <<<"$reader_snapshot") -eq 2 ]] ||
  fail "activity reader does not serve repeated process snapshots"
grep -Fq $'snapshot-end\tthermals' <<<"$reader_snapshot" ||
  fail "activity reader does not frame thermal snapshots"
grep -Fq $'snapshot-end\tgpus' <<<"$reader_snapshot" ||
  fail "activity reader does not frame GPU snapshots"
grep -Fq $'snapshot-end\tstorage' <<<"$reader_snapshot" ||
  fail "activity reader does not frame storage snapshots"
pass "activity reader serves independently requested snapshots in one native process"

coproc SELF_READER { exec "$ROOT/activity-stats" --activity-reader; }
self_reader_pid=$SELF_READER_PID
self_reader_input=${SELF_READER[1]}
self_reader_output=${SELF_READER[0]}
self_reader_snapshot=""
printf 'processes\n' >&"$self_reader_input"
while IFS= read -r -u "$self_reader_output" line; do
  [[ $line == $'snapshot-end\tprocesses' ]] && break
  self_reader_snapshot+="$line"$'\n'
done
process_children=$(<"/proc/$self_reader_pid/task/$self_reader_pid/children")
[[ -z $process_children ]] ||
  fail "native activity reader spawned a child collector"

printf 'processes\n' >&"$self_reader_input"
while IFS= read -r -u "$self_reader_output" line; do
  [[ $line == $'snapshot-end\tprocesses' ]] && break
done
process_children=$(<"/proc/$self_reader_pid/task/$self_reader_pid/children")
[[ -z $process_children ]] ||
  fail "native activity reader spawned a child between process snapshots"

exec {self_reader_input}>&-
wait "$self_reader_pid"
pass "activity reader keeps all unprivileged sampling in one native process"

if grep -Fq $'process\t'"$self_reader_pid"$'\t' <<<"$self_reader_snapshot"; then
  fail "activity reader reports its own sampling process as workload"
fi
pass "activity reader excludes its own sampling process"

fixture_root=$(mktemp -d)
trap 'rm -rf -- "$fixture_root"' EXIT

mkdir -p "$fixture_root/proc/101" "$fixture_root/proc/102" "$fixture_root/proc/103"
printf '200.00 100.00\n' >"$fixture_root/proc/uptime"
printf '%s\n' \
  '101 (worker task) R 1 1 1 0 -1 0 0 0 0 0 12 8 0 0 20 0 3 0 1000 4096000 25' \
  >"$fixture_root/proc/101/stat"
printf 'Name:\tworker task\nUid:\t1000\t1000\t1000\t1000\nVmRSS:\t120 kB\n' \
  >"$fixture_root/proc/101/status"
printf '%s\n' \
  '103 (kernel worker) I 2 0 0 0 0 2097152 0 0 0 0 0 0 0 0 20 0 1 0 1000 0 0' \
  >"$fixture_root/proc/103/stat"
printf 'alice:x:1000:1000:Alice:/home/alice:/bin/bash\n' >"$fixture_root/passwd"

fixture_process_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$fixture_root/proc" \
    OMARCHY_SYSTEM_STATS_PASSWD_PATH="$fixture_root/passwd" \
    OMARCHY_SYSTEM_STATS_CLOCK_TICKS=100 \
    OMARCHY_SYSTEM_STATS_PAGE_SIZE=4096 \
    "$ROOT/activity-stats" --activity-processes
)
grep -Fq $'process\t101\talice\tR\t1000\t20\t100\tworker task' \
  <<<"$fixture_process_snapshot" || fail "activity process collector reads a stable fixture process"
[[ $(grep -c '^process' <<<"$fixture_process_snapshot") -eq 1 ]] ||
  fail "activity process collector did not skip a vanished fixture PID"
pass "activity process collector skips PIDs that vanish during a snapshot"

if grep -Fq $'process\t103\t' <<<"$fixture_process_snapshot"; then
  fail "activity process collector included a kernel thread"
fi
pass "activity process collector omits non-actionable kernel threads"

grep -Fq 'centerOnBar: false' "$ROOT/Panel.qml" ||
  fail "activity panel keeps compact and expanded layouts on the same bar anchor"
pass "activity panel expansion preserves its bar anchor"

grep -Eq 'implicitWidth: .*button\.implicitWidth' "$ROOT/Panel.qml" ||
  fail "activity bar widget does not expose its icon width"
grep -Eq 'implicitHeight: .*button\.implicitHeight' "$ROOT/Panel.qml" ||
  fail "activity bar widget does not expose its icon height"
pass "activity bar widget exposes its icon geometry"

grep -Fq 'background: root.barGraphEnabled' "$ROOT/Panel.qml" ||
  fail "activity bar graph does not drive the background sampling tier"
grep -Fq 'readonly property bool sampling: active || background' "$ROOT/ActivityController.qml" ||
  fail "activity controller does not gate sampling on the background tier"
grep -Fq 'if (!active) return' "$ROOT/ActivityController.qml" ||
  fail "activity controller fans out to every reader outside the open panel"
pass "activity bar graph samples resources only while the panel is closed"

grep -Fq 'id: headerActions' "$ROOT/Panel.qml" ||
  fail "activity header actions do not share a header row"
grep -A3 -F 'id: headerActions' "$ROOT/Panel.qml" |
  grep -Fq 'anchors.verticalCenter: parent.verticalCenter' ||
  fail "activity header controls are not vertically centered together"
pass "activity header actions stay aligned"

panel_file="$ROOT/Panel.qml"
controller_file="$ROOT/ActivityController.qml"
action_controller_file="$ROOT/ProcessActionController.qml"
if grep -Eq 'label: "LOAD"|detail: .*"LOAD ' "$panel_file"; then
  fail "activity panel exposes the Linux load average"
fi
if grep -Fq 'LOGICAL CPUS' "$panel_file"; then
  fail "activity panel still advertises logical CPU count as card filler"
fi
grep -Fq 'function cpuCardDetail()' "$panel_file" &&
  grep -Fq 'Model.formatTemperature(cpuTemperature.value, temperatureUnitSetting)' "$panel_file" ||
  fail "activity CPU card does not own the CPU temperature"
if grep -Fq 'component TemperatureBadge' "$panel_file"; then
  fail "activity temperature still lives in the header"
fi
pass "activity keeps CPU temperature on the CPU card"

grep -Fq 'label: root.storageCardLabel()' "$panel_file" ||
  fail "activity expanded details do not show disk storage"
grep -Fq 'label: root.gpuHeadingText()' "$panel_file" &&
  grep -Fq 'gpuUsageText(adapters[0])' "$panel_file" ||
  fail "activity expanded details do not show GPU adapters"
grep -Fq 'return "Shared"' "$panel_file" ||
  fail "activity panel does not distinguish integrated shared GPU memory"
grep -Fq 'return "VRAM"' "$panel_file" ||
  fail "activity panel does not label dedicated GPU memory"
grep -Fq 'function storageCardValue()' "$panel_file" &&
  grep -Fq 'function storageCardDetail()' "$panel_file" &&
  grep -Fq '" free"' "$panel_file" ||
  fail "activity storage card does not show used storage and free space"
grep -Fq 'function cycleDisk(' "$panel_file" &&
  grep -Fq 'function cycleStorage(' "$panel_file" &&
  grep -Fq 'interactive: root.canCycleDisks' "$panel_file" &&
  grep -Fq 'interactive: root.canCycleStorage' "$panel_file" &&
  grep -Fq 'raw === "D" ? -1 : 1' "$panel_file" &&
  grep -Fq 'raw === "V" ? -1 : 1' "$panel_file" &&
  grep -Fq 'd/v cycle drives' "$panel_file" ||
  fail "activity does not page Disk and Storage with click and d/v"
grep -Fq 'resetDriveSelection()' "$panel_file" ||
  fail "activity does not reset drive selection when the panel closes"
if grep -Fq 'POWER & THERMALS' "$panel_file"; then
  fail "activity expanded details still show power and thermals"
fi
if grep -Fq 'label: "RAM TOTAL"' "$panel_file" || grep -Fq 'label: "CORES"' "$panel_file"; then
  fail "activity GPU card is still padded with unrelated system facts"
fi
pass "activity shows GPU and storage without filler metrics"

grep -Fq 'ActivityController {' "$panel_file" &&
  grep -Fq 'active: root.opened' "$panel_file" &&
  grep -Fq 'expanded: root.expanded' "$panel_file" ||
  fail "activity panel does not delegate sampling lifecycle to its controller"
grep -Fq 'readonly property var snapshot: _snapshot' "$controller_file" &&
  grep -Fq 'readonly property var processes: _processes' "$controller_file" ||
  fail "activity controller does not expose read-only sampled state"
if grep -Eq '^[[:space:]]*Process[[:space:]]*[{]' "$panel_file"; then
  fail "activity visual panel still owns a helper process"
fi
grep -Fq 'command: [root.statsHelperPath, "--activity-reader"]' "$controller_file" ||
  fail "activity panel does not reuse a single unprivileged stats reader"
grep -Fq 'String(Qt.resolvedUrl("activity-sampler"))' "$controller_file" ||
  fail "activity panel does not launch the native sampler directly"
grep -Fq '? [powerHelperPath]' "$controller_file" ||
  fail "activity panel does not use the persistent guarded CPU-energy reader"
grep -Fq 'if (!active || !expanded || !processPowerEnabled' "$controller_file" &&
  grep -Fq '|| processPowerUnavailable || _processPowerSamplePending) return' "$controller_file" ||
  fail "activity panel samples process power outside the advanced view"
grep -Fq 'onExpandedChanged:' "$controller_file" &&
  grep -Fq 'resetProcessPowerMeasurement()' "$controller_file" ||
  fail "activity panel carries an energy baseline across collapsed time"
grep -Fq 'root.markProcessPowerUnavailable()' "$controller_file" ||
  fail "activity panel does not clear stale watts after an energy read failure"
grep -Fq 'refreshProcessCycle()' "$controller_file" ||
  fail "activity panel does not coordinate energy and process refreshes"
grep -Fq 'id: deadlineScheduler' "$controller_file" &&
  grep -Fq 'function collectDueSnapshots()' "$controller_file" &&
  grep -Fq '_resourceDue = nextDeadline(_resourceDue, resourceInterval(), now)' "$controller_file" &&
  grep -Fq '_processDue = nextDeadline(_processDue, processRefreshInterval, now)' "$controller_file" &&
  grep -Fq '_thermalDue = nextDeadline(_thermalDue, thermalRefreshInterval, now)' "$controller_file" &&
  grep -Fq '_gpuDue = nextDeadline(_gpuDue, gpuRefreshInterval, now)' "$controller_file" &&
  grep -Fq '_storageDue = nextDeadline(_storageDue, storageRefreshInterval, now)' "$controller_file" ||
  fail "activity panel does not coalesce its independent deadlines"
if grep -Fq 'repeat: true' "$controller_file"; then
  fail "activity panel still wakes separate recurring timers"
fi
grep -Fq 'id: statsReaderWatchdog' "$controller_file" &&
  grep -Fq 'id: processPowerWatchdog' "$controller_file" ||
  fail "activity readers can remain stuck indefinitely"
grep -Fq 'powerStateSwitchingRoot: "switching-root"' "$controller_file" &&
  grep -Fq 'readonly property string processPowerState: _processPowerState' "$controller_file" ||
  fail "activity power reader lifecycle is not represented by an explicit state"
if grep -Eq 'processPowerRestartWithSudo|processPowerUseSudo|processPowerReaderReady[[:space:]]*:' "$controller_file"; then
  fail "activity power reader still uses overlapping lifecycle booleans"
fi
if grep -Eq 'activity-package-power|refreshPackagePower|packagePowerProc' "$controller_file"; then
  fail "activity panel still polls package power"
fi
grep -Fq 'if (expanded) sendStatsRequest("gpus")' "$controller_file" &&
  grep -Fq '_gpuDue = 0' "$controller_file" &&
  grep -Fq 'resetGpuMeasurement()' "$controller_file" ||
  fail "activity panel samples GPU details while the advanced view is collapsed"
grep -Fq '_metrics = Model.baselineMetrics(next, metrics)' "$controller_file" &&
  grep -Fq 'function resetSessionSampling()' "$controller_file" &&
  grep -Fq 'if (_gpus.length === 0)' "$controller_file" ||
  fail "activity panel does not retain valid display data while taking fresh baselines"
if grep -Fq '    _snapshot = Model.emptySnapshot()' "$controller_file" ||
   grep -Fq '    _processes = []' "$controller_file" ||
   grep -Fq '    _gpus = []' "$controller_file"; then
  fail "activity panel clears stale display data when a sampling session changes"
fi
pass "activity controller coalesces deadlines and refreshes retained values without blanking"

grep -Fq 'label: "~W"' "$panel_file" ||
  fail "activity process table does not label estimated CPU watts"
grep -Fq 'measuredPackagePowerText(processPower.watts)' "$panel_file" ||
  fail "activity CPU summary does not expose measured total CPU-package power"
grep -Fq 'return "~" + watts.toFixed' "$panel_file" ||
  fail "activity process watts are not visibly marked as estimates"
grep -Fq 'root.setSort("power")' "$panel_file" ||
  fail "activity process power cannot be sorted"
grep -Fq 'if (nextKey === "power" && (!powerEstimatesEnabled || !processPower.available)) return' "$panel_file" ||
  fail "activity process power sorting remains active without a measurement"
grep -Fq 'showProcessUserColumn' "$panel_file" &&
  grep -Fq 'showProcessTimeColumn' "$panel_file" ||
  fail "activity process table does not adapt its optional columns on narrow screens"
grep -Fq 'model: root.sortedProcesses' "$panel_file" ||
  fail "activity process table silently caps the virtualized process list"
grep -Fq 'Model.formatBytes(snapshot.memory.cached)' "$panel_file" ||
  fail "activity panel does not expose reclaimable memory cache"
[[ $(grep -Fc 'label: root.memoryCardLabel()' "$panel_file") -eq 2 ]] ||
  fail "activity panel does not place RAM speed in both card headings"
[[ $(grep -Fc 'label: root.cpuCardLabel()' "$panel_file") -eq 2 ]] ||
  fail "activity panel does not place CPU frequency in both card headings"
grep -Fq 'function memoryBreakdownText()' "$panel_file" &&
  grep -Fq 'if (usedUnit && usedUnit === cacheUnit)' "$panel_file" &&
  grep -Fq '" · cache " + cacheText' "$panel_file" ||
  fail "activity RAM card does not show used memory and cache together"
grep -Fq 'snapshot.memorySpeedMTs, "MT/s"' "$panel_file" &&
  grep -Fq 'snapshot.cpuFrequencyMHz, "MHz"' "$panel_file" &&
  grep -Fq 'var frequency = gpuFrequencyText(adapters[0])' "$panel_file" &&
  grep -Fq 'if (frequency === 0) return "IDLE"' "$panel_file" ||
  fail "activity card headings do not distinguish DDR transfer rate from CPU and GPU clocks"
[[ $(grep -Fc 'badge: root.swapBadgeText()' "$panel_file") -eq 2 ]] &&
  grep -Fq 'return "Swap " + percentText(metrics.swap)' "$panel_file" ||
  fail "activity RAM cards do not expose swap usage"
if grep -Fq 'label: "DISK"' "$panel_file"; then
  fail "activity disk card still shouts its heading"
fi
if grep -Fq 'component CoreLine' "$panel_file"; then
  fail "activity still draws a labeled bar for every logical core"
fi
grep -Fq 'component CoreHeatGrid' "$panel_file" &&
  grep -Fq 'paint: root.corePaintCompact' "$panel_file" &&
  grep -Fq 'paint: root.corePaintExpanded' "$panel_file" &&
  grep -Fq 'corePaintSizesExpanded' "$panel_file" &&
  grep -Fq 'id: coreDie' "$panel_file" ||
  fail "activity does not draw per-core load as a die on the CPU card"
if grep -Fq 'text: "Cores"' "$panel_file"; then
  fail "activity still treats cores as a separate strip under the cards"
fi
grep -Fq 'component ProcessSortCell' "$panel_file" &&
  grep -Fq 'sortKey: "cpu"' "$panel_file" &&
  grep -Fq 'sortKey: "runtime"' "$panel_file" ||
  fail "activity process column headers are not the sort controls"
if grep -Fq 'text: "More details"' "$panel_file"; then
  fail "activity compact view still duplicates the expand control"
fi
grep -Fq 'property bool hintsVisible: false' "$panel_file" &&
  grep -Fq 'function shortcutHintText()' "$panel_file" ||
  fail "activity keyboard hints are not opt-in"
if grep -Fq 'Preview CPU layouts' "$panel_file" || grep -Fq 'layoutPreviewContent' "$panel_file"; then
  fail "activity still ships the CPU layout preview in the production panel"
fi
if grep -Fq 'label: "GPU"' "$panel_file"; then
  fail "activity compact view still shows a GPU row"
fi
grep -Fq 'id: settingsContent' "$panel_file" &&
  grep -Fq 'label: "Update speed"' "$panel_file" &&
  grep -Fq 'label: "Graph history"' "$panel_file" &&
  grep -Fq 'label: "Temperature"' "$panel_file" &&
  grep -Fq 'function persistSettings(values)' "$panel_file" &&
  grep -Fq 'root.bar.shell.updateEntryInline(root.moduleName, entry)' "$panel_file" ||
  fail "activity panel does not expose persistent personalization controls"
grep -Fq 'processPowerEnabled: root.powerEstimatesEnabled' "$panel_file" &&
  grep -Fq 'onProcessPowerEnabledChanged:' "$controller_file" &&
  grep -Fq 'visible: !compact && root.powerEstimatesEnabled' "$panel_file" ||
  fail "activity power preference does not stop sampling and simplify the process table"
if grep -Fq 'text: "POWER"' "$panel_file"; then
  fail "activity presents estimated per-process power as an exact measurement"
fi
pass "activity clearly labels and sorts estimated per-process CPU power"

grep -Fq 'if (cursorActive && selectedProcessIndex === index) return' "$panel_file" ||
  fail "activity process rows remap pointer coordinates after already being selected"
grep -Fq 'hoverEnabled: !compact' "$panel_file" ||
  fail "activity compact process rows subscribe to unused hover movement"
if grep -Fq 'animateCursor: true' "$panel_file"; then
  fail "activity process row selection starts multi-frame hover animations"
fi
pass "activity process rows avoid input-rate pointer and animation work"

grep -Fq 'ConfirmDialog {' "$panel_file" ||
  fail "activity process actions are not confirmed"
grep -Fq 'processConfirm.selectedIndex = 0' "$panel_file" ||
  fail "activity process confirmation does not default to Cancel"
grep -Fq 'if (!root.settingsOpen && !processActions.confirmationOpen && root.cursorActive)' "$panel_file" ||
  fail "activity process shortcut can act without an explicit selection"
grep -Fq 'ProcessActionController {' "$panel_file" &&
  grep -Fq 'active: root.opened' "$panel_file" &&
  grep -Fq 'enabled: root.expanded && !root.settingsOpen' "$panel_file" ||
  fail "activity panel does not delegate guarded app actions to their controller"
grep -Fq 'Model.processIdentityKey' "$panel_file" ||
  fail "activity process selection is not tied to its sampled start time"
grep -Fq 'signalHelperPath,' "$action_controller_file" ||
  fail "activity panel does not use the guarded process signal helper"
grep -Fq 'action: "APP_TERM"' "$action_controller_file" ||
  fail "activity panel does not resolve worker processes to their parent app"
grep -Fq 'confirmText: "End app"' "$panel_file" ||
  fail "activity panel does not describe the app-wide process action"
grep -Fq 'Force-closes it after 3 seconds if needed.' "$panel_file" ||
  fail "activity panel does not disclose force-close escalation"
grep -Fq '"hyprland"' "$ROOT/Model.js" ||
  fail "activity panel does not protect the desktop compositor"
grep -Fq '"systemd-executo"' "$ROOT/Model.js" ||
  fail "activity panel does not protect the kernel-truncated systemd executor name"
grep -Fq 'disposition === "graceful"' "$action_controller_file" &&
  grep -Fq 'disposition === "escalated"' "$action_controller_file" ||
  fail "activity app action status does not distinguish normal and forced closure"
if grep -Eq 'bash[[:space:]]+-c|pkexec' "$panel_file" "$action_controller_file"; then
  fail "activity process actions invoke a shell or privilege prompt"
fi
pass "activity app actions use guarded identity and safe confirmation"
