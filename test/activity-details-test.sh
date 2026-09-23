#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const activity = requireFromRoot('Model.js')

const storage = activity.parseStorageSnapshot([
  'schema\tactivity-storage\t1',
  'sample\t99.75',
  'storage\t/\t4096000\t3072000\t819200',
  ''
].join('\n'))

assertEqual(storage.schema, 1, 'activity parses the storage schema version')
assertEqual(storage.sample, 99.75, 'activity parses the storage monotonic sample')
assertEqual(storage.path, '/', 'activity identifies the root filesystem')
assertEqual(storage.total, 4096000, 'activity parses total storage bytes')
assertEqual(storage.used, 3072000, 'activity parses used storage bytes')
assertEqual(storage.available, 819200, 'activity parses user-available storage bytes')
assertEqual(storage.volumes.length, 1, 'activity keeps a single storage line as one volume')

const volumes = activity.parseStorageSnapshot([
  'schema\tactivity-storage\t1',
  'sample\t12',
  'storage\t/data\t200\t180\t20',
  'storage\t/\t100\t20\t80',
  ''
].join('\n'))
assertEqual(volumes.volumes.length, 2, 'activity keeps multiple storage volumes')
assertEqual(volumes.path, '/', 'activity still exposes root as the primary storage path')
assertEqual(volumes.volumes[0].path, '/', 'activity sorts the root volume first')
assertEqual(volumes.volumes[1].path, '/data', 'activity keeps additional mountpoints')
assertEqual(activity.storageVolumeLabel('/'), '/', 'activity labels the root volume as /')
assertEqual(activity.storageVolumeLabel('/mnt/data'), 'data', 'activity labels a volume by its last path component')
assertEqual(activity.tightestStorageVolume(volumes.volumes).path, '/data', 'activity prefers the fullest volume')
assertEqual(activity.selectStorageVolume(volumes.volumes, '', false).path, '/data', 'activity defaults storage to the fullest volume')
assertEqual(activity.selectStorageVolume(volumes.volumes, '/', true).path, '/', 'activity keeps a pinned storage volume')
assertEqual(activity.selectStorageVolume(volumes.volumes, '/gone', true).path, '/data', 'activity falls back when a pinned volume disappears')
assertEqual(activity.cycleItemId(volumes.volumes, '/data', 'path', 1), '/', 'activity wraps the storage pager')
assertEqual(activity.nextCycleIndex(3, 0, -1), 2, 'activity wraps a pager backward')

const invalidStorage = activity.parseStorageSnapshot(
  'schema\tactivity-storage\t1\nstorage\t/\t100\t120\t110\n'
)
assertEqual(invalidStorage.used, 100, 'activity bounds used storage by filesystem size')
assertEqual(invalidStorage.available, 100, 'activity bounds available storage by filesystem size')

const firstGpuSnapshot = activity.parseGpuSnapshot([
  'schema\tactivity-gpus\t1',
  'sample\t10',
  'gpu\t0000:00:02.0\tIntel\txe\tIntel Arc Test\t-1\t-1\t-1\tunknown\t600',
  'engine\t0000:00:02.0\tclient-a\trcs\t100\t1000\t1\tcycles',
  'engine\t0000:00:02.0\tclient-b\trcs\t50\t1000\t1\tcycles',
  'engine\t0000:00:02.0\tclient-a\tvcs\t40\t1000\t1\tcycles',
  'gpu-memory\t0000:00:02.0\tshared\t536870912',
  'gpu\t0000:04:00.0\tNVIDIA\tnvidia\tNVIDIA GeForce Test\t62\t2147483648\t8589934592\tvram\t1950',
  ''
].join('\n'))
const secondGpuSnapshot = activity.parseGpuSnapshot([
  'schema\tactivity-gpus\t1',
  'sample\t12',
  'gpu\t0000:00:02.0\tIntel\txe\tIntel Arc Test\t-1\t-1\t-1\tunknown\t700',
  'engine\t0000:00:02.0\tclient-a\trcs\t200\t1200\t1\tcycles',
  'engine\t0000:00:02.0\tclient-b\trcs\t100\t1200\t1\tcycles',
  'engine\t0000:00:02.0\tclient-a\tvcs\t80\t1200\t1\tcycles',
  'gpu-memory\t0000:00:02.0\tshared\t805306368',
  'gpu\t0000:04:00.0\tNVIDIA\tnvidia\tNVIDIA GeForce Test\t47\t3221225472\t8589934592\tvram\t1905',
  ''
].join('\n'))
const sampledGpus = activity.nextGpus(firstGpuSnapshot, secondGpuSnapshot)

assertEqual(firstGpuSnapshot.schema, 1, 'activity parses the GPU schema version')
assertEqual(firstGpuSnapshot.gpus.length, 2, 'activity keeps multiple GPU adapters separate')
assertEqual(firstGpuSnapshot.gpus[0].memoryKind, 'shared', 'activity labels DRM allocation as shared GPU memory')
assertEqual(firstGpuSnapshot.gpus[0].memoryUsed, 536870912, 'activity parses resident shared GPU memory')
assertEqual(sampledGpus[0].usage, 75, 'activity sums clients within an engine and avoids adding parallel engine classes')
assertEqual(sampledGpus[0].frequencyMHz, 700, 'activity carries the current Intel GPU clock into display metrics')
assertEqual(sampledGpus[0].memoryUsed, 805306368, 'activity carries current shared allocation into display metrics')
assertEqual(sampledGpus[1].usage, 47, 'activity prefers a native GPU utilization reading')
assertEqual(sampledGpus[1].frequencyMHz, 1905, 'activity parses the NVIDIA graphics clock')
assertEqual(sampledGpus[1].memoryTotal, 8589934592, 'activity exposes dedicated VRAM capacity')

const firstTimedGpu = activity.parseGpuSnapshot(
  'schema\tactivity-gpus\t1\nsample\t20\ngpu\t0000:03:00.0\tAMD\tamdgpu\tAMD Test\t-1\t-1\t-1\tunknown\t1800\n'
    + 'engine\t0000:03:00.0\t7\tgfx\t1000000000\t-1\t1\ttime\n'
)
const secondTimedGpu = activity.parseGpuSnapshot(
  'schema\tactivity-gpus\t1\nsample\t22\ngpu\t0000:03:00.0\tAMD\tamdgpu\tAMD Test\t-1\t-1\t-1\tunknown\t1750\n'
    + 'engine\t0000:03:00.0\t7\tgfx\t2000000000\t-1\t1\ttime\n'
)
assertEqual(
  activity.nextGpus(firstTimedGpu, secondTimedGpu)[0].usage,
  50,
  'activity derives utilization from standard DRM nanosecond engine counters'
)
assertEqual(
  activity.nextGpus(activity.emptyGpuSnapshot(), firstGpuSnapshot)[0].usage,
  -1,
  'activity waits for a baseline before presenting counter-based GPU usage'
)

const thermals = activity.parseThermalSnapshot([
  'schema\tactivity-thermals\t1',
  'sample\t100.25',
  'temperature\thwmon0/temp1\tcoretemp\tPackage id 0\t62500',
  ''
].join('\n'))

assertEqual(thermals.schema, 1, 'activity parses the thermal schema version')
assertEqual(thermals.sample, 100.25, 'activity parses the thermal monotonic sample')
assertEqual(thermals.temperatures[0].value, 62.5, 'activity parses the CPU temperature')

const resources = activity.parseSnapshot(
  'schema\tactivity-resources\t1\nsample\t100.00\nmemory\tMemTotal\t1024\n'
)
assertEqual(
  activity.cpuTemperature(thermals.temperatures).label,
  'Package id 0',
  'activity selects CPU temperature from its independent thermal snapshot'
)
assertEqual(
  Object.prototype.hasOwnProperty.call(resources, 'temperatures'),
  false,
  'activity keeps thermal state out of resource snapshots'
)
assertDeepEqual(
  activity.emptyPower(),
  { available: false, watts: -1 },
  'activity exposes a dedicated empty power model'
)

const firstPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t200',
  'package\tintel-rapl:0\tpackage-0\t2000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t4000000\t20000000',
  ''
].join('\n'))
const secondPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t202',
  'package\tintel-rapl:0\tpackage-0\t6000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t10000000\t20000000',
  ''
].join('\n'))
const power = activity.nextPackagePower(firstPower, secondPower)
assertEqual(power.watts, 5, 'activity sums package power from raw energy deltas')
assertEqual(power.available, true, 'activity exposes complete multi-package measurements')
assertEqual(
  activity.packageEnergyReadable(secondPower),
  true,
  'activity accepts a complete set of readable package counters'
)

const metadataOnlyPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t203',
  'package\tintel-rapl:0\tpackage-0\t\t10000000',
  ''
].join('\n'))
const metadataOnlyDerived = activity.nextPackagePower(activity.emptyPackagePowerSnapshot(), metadataOnlyPower)
assertEqual(metadataOnlyPower.packages[0].energy, -1, 'activity marks an unreadable energy counter')
assertEqual(metadataOnlyDerived.available, false, 'activity does not invent watts without an energy counter')
assertEqual(
  activity.packageEnergyReadable(metadataOnlyPower),
  false,
  'activity rejects package metadata without a readable energy counter'
)

const beforeWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t300\npackage\tintel-rapl:0\tpackage-0\t9000000\t10000000\n'
)
const afterWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t302\npackage\tintel-rapl:0\tpackage-0\t1000000\t10000000\n'
)
assertEqual(
  activity.nextPackagePower(beforeWrap, afterWrap).watts,
  1,
  'activity handles a RAPL energy counter wrap'
)

const beforeReset = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t600\npackage\tintel-rapl:0\tpackage-0\t6000000\t10000000\n'
)
const afterReset = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t602\npackage\tintel-rapl:0\tpackage-0\t1000000\t10000000\n'
)
assertEqual(
  activity.nextPackagePower(beforeReset, afterReset).watts,
  -1,
  'activity rejects a decreasing RAPL counter away from its wrap boundary'
)
assertEqual(
  activity.packageEnergyDelta(beforeReset.packages[0], afterReset.packages[0]),
  0,
  'activity treats a decreasing mid-range RAPL counter as reset'
)

const beforeMultiSocketPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t200',
  'package\tintel-rapl:0\tpackage-0\t2000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t4000000\t20000000',
  ''
].join('\n'))
const partialSocketPower = activity.parsePackagePowerSnapshot([
  'schema\tactivity-process-power\t1',
  'sample\t202',
  'package\tintel-rapl:0\tpackage-0\t6000000\t10000000',
  'package\tintel-rapl:1\tpackage-1\t\t20000000',
  ''
].join('\n'))
assertEqual(
  activity.nextPackagePower(beforeMultiSocketPower, partialSocketPower).available,
  false,
  'activity does not present partial multi-socket energy as whole-system power'
)
assertEqual(
  activity.packageEnergyReadable(partialSocketPower),
  false,
  'activity retries privilege when any processor package is unreadable'
)

const changedRange = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t304\npackage\tintel-rapl:0\tpackage-0\t2000000\t20000000\n'
)
assertEqual(
  activity.nextPackagePower(afterWrap, changedRange).watts,
  -1,
  'activity treats a changed RAPL range as a new counter'
)
assertEqual(
  activity.packageEnergyDelta(afterWrap.packages[0], changedRange.packages[0]),
  0,
  'activity rejects a changed RAPL counter range'
)
const beforePackageWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t500\npackage\tintel-rapl:0\tpackage-0\t9000000\t10000000\n'
)
const afterPackageWrap = activity.parsePackagePowerSnapshot(
  'schema\tactivity-process-power\t1\nsample\t502\npackage\tintel-rapl:0\tpackage-0\t1000000\t10000000\n'
)
assertEqual(
  activity.nextPackagePower(beforePackageWrap, afterPackageWrap).watts,
  1,
  'activity process power handles a package energy counter wrap'
)

const firstProcessPowerSample = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t400\t100\t10000',
  'process\t10\t1000\tS\t100\t1000\t100\tbrowser',
  ''
].join('\n'))
const secondProcessPowerSample = activity.parseProcessSnapshot([
  'schema\tactivity-processes\t1',
  'sample\t402\t100\t10200',
  'process\t10\t1000\tR\t100\t1100\t100\tbrowser',
  ''
].join('\n'))
const sampledPowerProcesses = activity.nextProcesses(
  firstProcessPowerSample,
  secondProcessPowerSample,
  1000
)
assertEqual(secondProcessPowerSample.systemBusyTicks, 10200, 'activity parses aggregate system busy ticks')
assertEqual(sampledPowerProcesses[0].cpuTicksDelta, 100, 'activity retains a process CPU tick delta')
assertEqual(
  activity.processSystemBusyDelta(firstProcessPowerSample, secondProcessPowerSample),
  200,
  'activity derives the matching aggregate system busy tick delta'
)

const processRows = [
  { pid: 10, name: 'browser', cpuTicksDelta: 100, memory: 10 },
  { pid: 20, name: 'music', cpuTicksDelta: 50, memory: 5 },
  { pid: 30, name: 'idle', cpuTicksDelta: 25, memory: 1 },
  { pid: 40, name: 'reset', cpuTicksDelta: -25, memory: 2 }
]
const estimatedPower = activity.estimateProcessPower(processRows, 10, 200)
assertEqual(estimatedPower[0].power, 5, 'activity allocates package power by system CPU ticks')
assertEqual(estimatedPower[1].power, 2.5, 'activity allocates a second proportional package power estimate')
assertEqual(estimatedPower[2].power, 1.25, 'activity allocates a third proportional package power estimate')
assertEqual(estimatedPower[3].power, 0, 'activity treats a negative CPU delta as no package share')
assertEqual(
  estimatedPower.reduce((total, process) => total + process.power, 0),
  8.75,
  'activity leaves kernel and unobserved package power unallocated'
)
assert(
  estimatedPower[0] !== processRows[0] && !Object.prototype.hasOwnProperty.call(processRows[0], 'power'),
  'activity process power estimation does not mutate input rows'
)
assertDeepEqual(
  activity.estimateProcessPower(processRows, -1, 200).map(process => process.power),
  [-1, -1, -1, -1],
  'activity marks process power unavailable without a package measurement'
)
assertDeepEqual(
  activity.estimateProcessPower(processRows, 10, 0).map(process => process.power),
  [-1, -1, -1, -1],
  'activity marks process power unavailable across a zero busy interval'
)
assertDeepEqual(
  activity.estimateProcessPower(processRows, 10, -50).map(process => process.power),
  [-1, -1, -1, -1],
  'activity marks process power unavailable after a system counter reset'
)
assertDeepEqual(
  activity.filterAndSortProcesses(estimatedPower, '', 'power', false)
    .map(process => process.pid),
  [10, 20, 30, 40],
  'activity sorts processes by estimated power'
)
const overAccountedPower = activity.estimateProcessPower([
  { pid: 1, cpuTicksDelta: 80 },
  { pid: 2, cpuTicksDelta: 60 }
], 10, 100)
assert(
  Math.abs(overAccountedPower.reduce((total, process) => total + process.power, 0) - 10) < 1e-9,
  'activity caps over-accounted process estimates at measured package power'
)
JS

fixture_root=$(mktemp -d)
trap 'rm -rf -- "$fixture_root"' EXIT

proc_path="$fixture_root/proc"
sys_path="$fixture_root/sys"
hwmon_path="$sys_path/class/hwmon/hwmon0"
powercap_path="$sys_path/class/powercap/intel-rapl"
package_path="$powercap_path/intel-rapl:0"
subzone_path="$powercap_path/intel-rapl:0:0"
gpu_devices="$fixture_root/gpu-devices"
gpu_drivers="$fixture_root/gpu-drivers"
cpu_policy0="$sys_path/devices/system/cpu/cpufreq/policy0"
cpu_policy1="$sys_path/devices/system/cpu/cpufreq/policy1"
intel_frequency="$gpu_devices/0000:00:02.0/tile0/gt0/freq0"
amd_hwmon="$gpu_devices/0000:03:00.0/hwmon/hwmon0"

mkdir -p \
  "$proc_path/net" \
  "$fixture_root/root filesystem" \
  "$sys_path/class/block" \
  "$sys_path/class/drm/card0" \
  "$sys_path/class/drm/card1" \
  "$sys_path/class/drm/card2" \
  "$sys_path/class/net/eth0/device" \
  "$cpu_policy0" \
  "$cpu_policy1" \
  "$gpu_devices/0000:00:02.0" \
  "$gpu_devices/0000:03:00.0" \
  "$gpu_devices/0000:04:00.0" \
  "$gpu_drivers/xe" \
  "$gpu_drivers/amdgpu" \
  "$gpu_drivers/nvidia" \
  "$intel_frequency" \
  "$amd_hwmon" \
  "$proc_path/500/fd" \
  "$proc_path/500/fdinfo" \
  "$proc_path/501/fd" \
  "$proc_path/501/fdinfo" \
  "$hwmon_path" \
  "$package_path" \
  "$subzone_path"

printf '321.50 100.00\n' >"$proc_path/uptime"
printf 'cpu 100 0 50 800 10 5 5 0 0 0\ncpu0 50 0 25 400 5 2 3 0 0 0\n' >"$proc_path/stat"
printf 'MemTotal: 1024 kB\nHugePages_Total: 0\nMemAvailable: 512 kB\nCached: 128 kB\nSReclaimable: 32 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' >"$proc_path/meminfo"
printf '0.50 0.25 0.10 1/100 123\n' >"$proc_path/loadavg"
printf 'Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\neth0\t00000000\t00000000\t0001\t0\t0\t25\t00000000\t0\t0\t0\n' \
  >"$proc_path/net/route"
printf 'Inter-| Receive | Transmit\n face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\neth0: 1000 1 0 0 0 0 0 0 2000 1 0 0 0 0 0 0\n' \
  >"$proc_path/net/dev"
printf 'up\n' >"$sys_path/class/net/eth0/operstate"
printf 'DRIVER=test\n' >"$sys_path/class/net/eth0/device/uevent"
printf '2400000\n' >"$cpu_policy0/scaling_cur_freq"
printf '3200000\n' >"$cpu_policy1/scaling_cur_freq"

printf 'coretemp\n' >"$hwmon_path/name"
printf '62500\n' >"$hwmon_path/temp1_input"
printf 'Package id 0\n' >"$hwmon_path/temp1_label"

ln -s "$gpu_devices/0000:00:02.0" "$sys_path/class/drm/card0/device"
ln -s "$gpu_devices/0000:03:00.0" "$sys_path/class/drm/card1/device"
ln -s "$gpu_devices/0000:04:00.0" "$sys_path/class/drm/card2/device"
ln -s "$gpu_drivers/xe" "$gpu_devices/0000:00:02.0/driver"
ln -s "$gpu_drivers/amdgpu" "$gpu_devices/0000:03:00.0/driver"
ln -s "$gpu_drivers/nvidia" "$gpu_devices/0000:04:00.0/driver"
printf '0x8086\n' >"$gpu_devices/0000:00:02.0/vendor"
printf 'Intel Arc Fixture\n' >"$gpu_devices/0000:00:02.0/product_name"
printf '600\n' >"$intel_frequency/act_freq"
printf '0x1002\n' >"$gpu_devices/0000:03:00.0/vendor"
printf 'AMD Radeon Fixture\n' >"$gpu_devices/0000:03:00.0/product_name"
printf '47\n' >"$gpu_devices/0000:03:00.0/gpu_busy_percent"
printf '268435456\n' >"$gpu_devices/0000:03:00.0/mem_info_vram_used"
printf '2147483648\n' >"$gpu_devices/0000:03:00.0/mem_info_vram_total"
printf '1800000000\n' >"$amd_hwmon/freq1_input"
printf '0x10de\n' >"$gpu_devices/0000:04:00.0/vendor"
printf 'NVIDIA Fixture\n' >"$gpu_devices/0000:04:00.0/product_name"

printf '%s\n' \
  $'drm-driver:\txe' \
  $'drm-client-id:\t77' \
  $'drm-pdev:\t0000:00:02.0' \
  $'drm-resident-gtt:\t64 MiB' \
  $'drm-cycles-rcs:\t100' \
  $'drm-total-cycles-rcs:\t1000' \
  >"$proc_path/500/fdinfo/5"
cp "$proc_path/500/fdinfo/5" "$proc_path/500/fdinfo/6"
ln -s /dev/dri/renderD128 "$proc_path/500/fd/5"
ln -s /dev/dri/renderD128 "$proc_path/500/fd/6"
printf '%s\n' \
  $'drm-driver:\txe' \
  $'drm-client-id:\t78' \
  $'drm-pdev:\t0000:00:02.0' \
  $'drm-resident-gtt:\t32 MiB' \
  $'drm-cycles-rcs:\t50' \
  $'drm-total-cycles-rcs:\t1000' \
  >"$proc_path/501/fdinfo/8"
ln -s /dev/dri/renderD128 "$proc_path/501/fd/8"

printf '4096\t1000\t250\t200\n' >"$fixture_root/statfs"
printf '00000000:04:00.0\tNVIDIA GeForce Fixture\t62\t2147483648\t8589934592\t1950\n' \
  >"$fixture_root/nvidia.tsv"
printf 'E:MEMORY_DEVICE_0_SPEED_MTS=7200\nE:MEMORY_DEVICE_0_CONFIGURED_SPEED_GTS=6.4\n' \
  >"$fixture_root/udev-data"

storage_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_ROOT_PATH="$fixture_root/root filesystem" \
    OMARCHY_SYSTEM_STATS_STATFS_FIXTURE_PATH="$fixture_root/statfs" \
    "$ROOT/activity-stats" --activity-storage
)
expected_storage=$'schema\tactivity-storage\t1\nsample\t321.50\nstorage\t/\t4096000\t3072000\t819200'
[[ $storage_snapshot == "$expected_storage" ]] ||
  fail "activity root storage output is exact, versioned, and byte-based" "$storage_snapshot"
pass "activity root storage output is exact, versioned, and byte-based"

printf '%s\n' \
  $'/data 4096 2000 100 50' \
  $'/ 4096 1000 250 200' \
  >"$fixture_root/statfs-multi"
multi_storage_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_ROOT_PATH="$fixture_root/root filesystem" \
    OMARCHY_SYSTEM_STATS_STATFS_FIXTURE_PATH="$fixture_root/statfs-multi" \
    "$ROOT/activity-stats" --activity-storage
)
expected_multi_storage=$'schema\tactivity-storage\t1\nsample\t321.50\nstorage\t/\t4096000\t3072000\t819200\nstorage\t/data\t8192000\t7782400\t204800'
[[ $multi_storage_snapshot == "$expected_multi_storage" ]] ||
  fail "activity storage output lists local volumes in stable order" "$multi_storage_snapshot"
pass "activity storage output lists local volumes in stable order"

live_storage=$("$ROOT/activity-stats" --activity-storage)
grep -Eq $'^storage\t/' <<<"$live_storage" ||
  fail "activity live storage does not include the root filesystem" "$live_storage"
if findmnt -n -o FSTYPE /tmp >/dev/null 2>&1 && [[ $(findmnt -n -o FSTYPE /tmp) == tmpfs ]]; then
  if grep -Eq $'^storage\t/tmp\t' <<<"$live_storage"; then
    fail "activity live storage includes tmpfs" "$live_storage"
  fi
fi
root_source=$(findmnt -n -o SOURCE / 2>/dev/null || true)
home_source=$(findmnt -n -o SOURCE /home 2>/dev/null || true)
if [[ -n $home_source && $home_source == "$root_source" ]] &&
   grep -Eq $'^storage\t/home\t' <<<"$live_storage"; then
  fail "activity storage splits subvolumes of the same device" "$live_storage"
fi
pass "activity live storage stays on local filesystems"

thermal_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-thermals
)
expected_thermals=$'schema\tactivity-thermals\t1\nsample\t321.50\ntemperature\thwmon0/temp1\tcoretemp\tPackage id 0\t62500'
[[ $thermal_snapshot == "$expected_thermals" ]] ||
  fail "activity CPU thermal output is exact and versioned" "$thermal_snapshot"
pass "activity CPU thermal output is exact and versioned"

gpu_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    OMARCHY_SYSTEM_STATS_NVIDIA_FIXTURE_PATH="$fixture_root/nvidia.tsv" \
    "$ROOT/activity-stats" --activity-gpus
)
grep -Fxq $'schema\tactivity-gpus\t1' <<<"$gpu_snapshot" ||
  fail "activity GPU output has its own schema"
grep -Fxq $'gpu\t0000:00:02.0\tIntel\txe\tIntel Arc Fixture\t-1\t-1\t-1\tunknown\t600' \
  <<<"$gpu_snapshot" ||
  fail "activity GPU output reads an Intel/Xe graphics clock"
grep -Fxq $'gpu\t0000:03:00.0\tAMD\tamdgpu\tAMD Radeon Fixture\t47\t268435456\t2147483648\tvram\t1800' \
  <<<"$gpu_snapshot" ||
  fail "activity GPU output reads AMD busy, VRAM, and graphics clock counters"
grep -Fxq $'gpu\t0000:04:00.0\tNVIDIA\tnvidia\tNVIDIA GeForce Fixture\t62\t2147483648\t8589934592\tvram\t1950' \
  <<<"$gpu_snapshot" ||
  fail "activity GPU output reads NVIDIA utilization, VRAM, and graphics clock through persistent NVML"
grep -Fxq $'gpu-memory\t0000:00:02.0\tshared\t100663296' <<<"$gpu_snapshot" ||
  fail "activity GPU output does not aggregate shared DRM memory"
[[ $(grep -c $'^engine\t0000:00:02.0\t77\trcs\t' <<<"$gpu_snapshot") -eq 1 ]] ||
  fail "activity GPU output double-counts duplicated DRM file descriptors"
[[ $(grep -c $'^engine\t0000:00:02.0\t78\trcs\t' <<<"$gpu_snapshot") -eq 1 ]] ||
  fail "activity GPU output loses a distinct DRM client"
pass "activity GPU collector supports shared Intel, AMD, NVIDIA, and multiple adapters"

read_gpu_frame() {
  local output_fd="$1"
  local result_name="$2"
  local line
  local -n result="$result_name"
  result=""

  while IFS= read -r -u "$output_fd" line; do
    [[ $line == $'snapshot-end\tgpus' ]] && return 0
    result+="$line"$'\n'
  done
  return 1
}

coproc GPU_READER {
  exec env \
    OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    OMARCHY_SYSTEM_STATS_NVIDIA_FIXTURE_PATH="$fixture_root/nvidia.tsv" \
    OMARCHY_SYSTEM_STATS_GPU_DISCOVERY_INTERVAL_MS=500 \
    "$ROOT/activity-sampler" --activity-reader
}
gpu_reader_pid=$GPU_READER_PID
gpu_reader_input=${GPU_READER[1]}
gpu_reader_output=${GPU_READER[0]}
printf 'gpus\n' >&"$gpu_reader_input"
read_gpu_frame "$gpu_reader_output" first_gpu_frame ||
  fail "activity GPU reader stopped before its first frame"

mkdir -p "$proc_path/502/fd" "$proc_path/502/fdinfo"
printf '%s\n' \
  $'drm-driver:\txe' \
  $'drm-client-id:\t79' \
  $'drm-pdev:\t0000:00:02.0' \
  $'drm-resident-gtt:\t16 MiB' \
  $'drm-cycles-rcs:\t25' \
  $'drm-total-cycles-rcs:\t1000' \
  >"$proc_path/502/fdinfo/9"
ln -s /dev/dri/renderD128 "$proc_path/502/fd/9"

printf 'gpus\n' >&"$gpu_reader_input"
read_gpu_frame "$gpu_reader_output" cached_gpu_frame ||
  fail "activity GPU reader stopped during its cached frame"
if grep -Fq $'engine\t0000:00:02.0\t79\t' <<<"$cached_gpu_frame"; then
  fail "activity GPU reader rescanned every process file descriptor on every sample"
fi

sleep 0.55
printf 'gpus\n' >&"$gpu_reader_input"
read_gpu_frame "$gpu_reader_output" rediscovered_gpu_frame ||
  fail "activity GPU reader stopped before its discovery refresh"
exec {gpu_reader_input}>&-
wait "$gpu_reader_pid"
grep -Fq $'engine\t0000:00:02.0\t79\trcs\t25\t1000\t1\tcycles' \
  <<<"$rediscovered_gpu_frame" ||
  fail "activity GPU reader did not discover a new client after its cache interval"
pass "activity GPU reader refreshes counters without rescanning process FDs every sample"

apple_sys="$fixture_root/apple-sys"
apple_proc="$fixture_root/apple-proc"
apple_gpu="$fixture_root/apple-gpu"
apple_display="$fixture_root/apple-display"
apple_drivers="$fixture_root/apple-drivers"
mkdir -p \
  "$apple_sys/class/drm/card0" \
  "$apple_sys/class/drm/card1" \
  "$apple_gpu" \
  "$apple_display" \
  "$apple_drivers/asahi" \
  "$apple_drivers/apple-drm" \
  "$apple_proc"
ln -s "$apple_gpu" "$apple_sys/class/drm/card0/device"
ln -s "$apple_display" "$apple_sys/class/drm/card1/device"
ln -s "$apple_drivers/asahi" "$apple_gpu/driver"
ln -s "$apple_drivers/apple-drm" "$apple_display/driver"
ln -s "$apple_gpu" "$apple_gpu/supplier:platform:406408000.mbox"
printf '%s\n' \
  'DRIVER=asahi' \
  'OF_COMPATIBLE_0=apple,agx-t6021' \
  'OF_COMPATIBLE_1=apple,agx-g14x' \
  >"$apple_gpu/uevent"
printf '%s\n' \
  'DRIVER=apple-drm' \
  'OF_COMPATIBLE_0=apple,display-subsystem' \
  >"$apple_display/uevent"
printf '321.50 100.00\n' >"$apple_proc/uptime"
printf '%s\n' \
  '           CPU0       CPU1' \
  ' 61:       1000       1000     AIC2 66682 Level     406408000.mbox-recv' \
  >"$apple_proc/interrupts"

apple_gpu_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$apple_proc" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$apple_sys" \
    "$ROOT/activity-stats" --activity-gpus
)
grep -Fxq $'gpu\tcard0\tApple\tasahi\tApple M2 Max\t-1\t-1\t-1\tunknown\t-1' \
  <<<"$apple_gpu_snapshot" ||
  fail "activity GPU output names an Apple AGX adapter from its device tree" "$apple_gpu_snapshot"
[[ $(grep -c $'^gpu\t' <<<"$apple_gpu_snapshot") -eq 1 ]] ||
  fail "activity GPU output includes the Apple display controller" "$apple_gpu_snapshot"
pass "activity GPU output names Apple AGX and skips the display controller"

printf '%s\n' \
  'DRIVER=asahi' \
  'OF_COMPATIBLE_0=apple,agx-t8122' \
  'OF_COMPATIBLE_1=apple,agx-g15g' \
  >"$apple_gpu/uevent"
apple_generation_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$apple_proc" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$apple_sys" \
    "$ROOT/activity-stats" --activity-gpus
)
grep -Fxq $'gpu\tcard0\tApple\tasahi\tApple G15g\t-1\t-1\t-1\tunknown\t-1' \
  <<<"$apple_generation_snapshot" ||
  fail "activity GPU output falls back to the Apple G-series compatible" "$apple_generation_snapshot"
pass "activity GPU output falls back to the Apple G-series compatible"

printf '%s\n' \
  'DRIVER=asahi' \
  'OF_COMPATIBLE_0=apple,agx-t6021' \
  'OF_COMPATIBLE_1=apple,agx-g14x' \
  >"$apple_gpu/uevent"
coproc APPLE_GPU_READER {
  exec env \
    OMARCHY_SYSTEM_STATS_PROC_PATH="$apple_proc" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$apple_sys" \
    "$ROOT/activity-sampler" --activity-reader
}
apple_reader_pid=$APPLE_GPU_READER_PID
apple_reader_input=${APPLE_GPU_READER[1]}
apple_reader_output=${APPLE_GPU_READER[0]}
printf 'gpus\n' >&"$apple_reader_input"
read_gpu_frame "$apple_reader_output" apple_first_frame ||
  fail "activity Apple GPU reader stopped before its first frame"
grep -Fxq $'gpu\tcard0\tApple\tasahi\tApple M2 Max\t-1\t-1\t-1\tunknown\t-1' \
  <<<"$apple_first_frame" ||
  fail "activity Apple GPU utilization is reported before a mailbox baseline" "$apple_first_frame"

sleep 0.4
printf 'gpus\n' >&"$apple_reader_input"
read_gpu_frame "$apple_reader_output" apple_idle_frame ||
  fail "activity Apple GPU reader stopped during its idle frame"
grep -Fxq $'gpu\tcard0\tApple\tasahi\tApple M2 Max\t0\t-1\t-1\tunknown\t-1' \
  <<<"$apple_idle_frame" ||
  fail "activity Apple GPU utilization stays idle when the mailbox is quiet" "$apple_idle_frame"

printf '%s\n' \
  '           CPU0       CPU1' \
  ' 61:      21000      21000     AIC2 66682 Level     406408000.mbox-recv' \
  >"$apple_proc/interrupts"
sleep 0.4
printf 'gpus\n' >&"$apple_reader_input"
read_gpu_frame "$apple_reader_output" apple_busy_frame ||
  fail "activity Apple GPU reader stopped during its busy frame"
exec {apple_reader_input}>&-
wait "$apple_reader_pid"
apple_busy_line=$(grep $'^gpu\t' <<<"$apple_busy_frame" || true)
IFS=$'\t' read -r _ _ _ _ _ apple_busy_util _ <<<"$apple_busy_line"
awk -v value="$apple_busy_util" 'BEGIN { exit !(value+0 >= 50) }' ||
  fail "activity Apple GPU utilization rises with command completions" "$apple_busy_frame"
pass "activity Apple GPU utilization follows the command mailbox"

read_thermal_frame() {
  local output_fd="$1"
  local result_name="$2"
  local line
  local -n result="$result_name"
  result=""

  while IFS= read -r -u "$output_fd" line; do
    [[ $line == $'snapshot-end\tthermals' ]] && return 0
    result+="$line"$'\n'
  done
  return 1
}

coproc THERMAL_READER {
  exec env \
    OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-reader
}
thermal_reader_pid=$THERMAL_READER_PID
thermal_reader_input=${THERMAL_READER[1]}
thermal_reader_output=${THERMAL_READER[0]}
printf 'thermals\n' >&"$thermal_reader_input"
read_thermal_frame "$thermal_reader_output" first_thermal_frame ||
  fail "activity thermal reader stopped before its first frame"
grep -Fq $'temperature\thwmon0/temp1\tcoretemp\tPackage id 0\t62500' \
  <<<"$first_thermal_frame" ||
  fail "activity thermal reader did not cache its selected CPU sensor"

rm -- "$hwmon_path/temp1_input"
fallback_hwmon_path="$sys_path/class/hwmon/hwmon1"
mkdir -p "$fallback_hwmon_path"
printf 'k10temp\n' >"$fallback_hwmon_path/name"
printf '55000\n' >"$fallback_hwmon_path/temp1_input"
printf 'Tctl\n' >"$fallback_hwmon_path/temp1_label"
printf 'thermals\n' >&"$thermal_reader_input"
read_thermal_frame "$thermal_reader_output" second_thermal_frame ||
  fail "activity thermal reader stopped before its fallback frame"
exec {thermal_reader_input}>&-
wait "$thermal_reader_pid"
grep -Fq $'temperature\thwmon1/temp1\tk10temp\tTctl\t55000' \
  <<<"$second_thermal_frame" ||
  fail "activity thermal reader did not rescan after its cached sensor vanished"
pass "activity thermal reader caches and safely invalidates its CPU sensor"

resource_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    OMARCHY_SYSTEM_STATS_UDEV_DATA_PATH="$fixture_root/udev-data" \
    "$ROOT/activity-stats" --activity-resources
)
grep -Fxq $'schema\tactivity-resources\t1' <<<"$resource_snapshot" ||
  fail "activity resources output has its own schema"
grep -Fxq $'memory\t1024\t512\t0\t0\t160' <<<"$resource_snapshot" ||
  fail "activity resources output includes page cache and reclaimable slabs"
grep -Fxq $'frequency\tcpu\t2800\tMHz' <<<"$resource_snapshot" ||
  fail "activity resources output averages current CPU policy frequencies"
grep -Fxq $'frequency\tmemory\t6400\tMT/s' <<<"$resource_snapshot" ||
  fail "activity resources output reads the configured DDR transfer rate"
grep -Fxq $'network\teth0\t1000\t2000\tup\t1\t1' <<<"$resource_snapshot" ||
  fail "activity resources do not follow an up default route without a gateway"
if grep -q '^temperature' <<<"$resource_snapshot"; then
  fail "activity resources output avoids detailed sensor reads"
fi
pass "activity resources output avoids detailed sensor reads"

rm -- "$proc_path/net/route"
resource_without_route=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    OMARCHY_SYSTEM_STATS_UDEV_DATA_PATH="$fixture_root/udev-data" \
    "$ROOT/activity-stats" --activity-resources
)
grep -Fxq $'schema\tactivity-resources\t1' <<<"$resource_without_route" ||
  fail "activity resources fail when optional route metadata is absent"
pass "activity resources tolerate missing optional procfs inputs"

mkdir -p "$proc_path/device-tree"
printf 'apple,j414c\0apple,t6021\0apple,arm-platform\0' >"$proc_path/device-tree/compatible"
printf 'Apple MacBook Pro (14-inch, M2 Max, 2023)\0' >"$proc_path/device-tree/model"
apple_cpu_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-resources
)
grep -Fxq $'cpu-name\tApple M2 Max' <<<"$apple_cpu_snapshot" ||
  fail "activity names an Apple SoC from its device tree" "$apple_cpu_snapshot"
printf 'apple,t8122\0' >"$proc_path/device-tree/compatible"
printf 'Apple MacBook Pro (14-inch, M3, 2024)\0' >"$proc_path/device-tree/model"
apple_model_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-resources
)
grep -Fxq $'cpu-name\tApple M3' <<<"$apple_model_snapshot" ||
  fail "activity names an unlisted Apple SoC from the device-tree model" "$apple_model_snapshot"
rm -rf -- "$proc_path/device-tree"
printf 'model name\t: Intel(R) Core(TM) i7-12700K CPU @ 3.60GHz\n' >"$proc_path/cpuinfo"
intel_cpu_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-resources
)
grep -Fxq $'cpu-name\tCore i7-12700K' <<<"$intel_cpu_snapshot" ||
  fail "activity names an Intel processor from cpuinfo" "$intel_cpu_snapshot"
printf 'model name\t: ARMv8 Processor rev 0 (v8l)\n' >"$proc_path/cpuinfo"
generic_cpu_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-resources
)
if grep -q $'^cpu-name\t' <<<"$generic_cpu_snapshot"; then
  fail "activity presents a generic ARM model string as the processor name" "$generic_cpu_snapshot"
fi
pass "activity names the processor when the platform identifies it"

process_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_PASSWD_PATH="$fixture_root/missing-passwd" \
    OMARCHY_SYSTEM_STATS_CLOCK_TICKS=100 \
    "$ROOT/activity-stats" --activity-processes
)
expected_process_snapshot=$'schema\tactivity-processes\t1\nsample\t321.50\t100\t160'
[[ $process_snapshot == "$expected_process_snapshot" ]] ||
  fail "activity process output includes exact aggregate busy ticks" "$process_snapshot"
pass "activity process output includes exact aggregate busy ticks"

printf 'package-0\n' >"$package_path/name"
printf '9000000\n' >"$package_path/energy_uj"
printf '10000000\n' >"$package_path/max_energy_range_uj"
printf 'core\n' >"$subzone_path/name"
printf '0\n' >"$subzone_path/enabled"
printf '1000000\n' >"$subzone_path/energy_uj"
printf '10000000\n' >"$subzone_path/max_energy_range_uj"

psys_path="$powercap_path/intel-rapl:1"
non_package_path="$powercap_path/intel-rapl:2"
uncore_path="$powercap_path/intel-rapl:0:1"
dram_path="$powercap_path/intel-rapl:0:2"
mmio_package_path="$sys_path/class/powercap/intel-rapl-mmio/intel-rapl-mmio:0"
mkdir -p "$psys_path" "$non_package_path" "$uncore_path" "$dram_path" "$mmio_package_path"
printf 'psys\n' >"$psys_path/name"
printf '8000000\n' >"$psys_path/energy_uj"
printf '10000000\n' >"$psys_path/max_energy_range_uj"
printf 'dram\n' >"$non_package_path/name"
printf '7000000\n' >"$non_package_path/energy_uj"
printf '10000000\n' >"$non_package_path/max_energy_range_uj"
printf 'uncore\n' >"$uncore_path/name"
printf '6000000\n' >"$uncore_path/energy_uj"
printf '10000000\n' >"$uncore_path/max_energy_range_uj"
printf 'dram\n' >"$dram_path/name"
printf '5000000\n' >"$dram_path/energy_uj"
printf '10000000\n' >"$dram_path/max_energy_range_uj"
printf 'package-0\n' >"$mmio_package_path/name"
printf '8000000\n' >"$mmio_package_path/energy_uj"
printf '10000000\n' >"$mmio_package_path/max_energy_range_uj"

process_power_snapshot=$(
  OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
    OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
    "$ROOT/activity-stats" --activity-process-power
)
expected_process_power=$'schema\tactivity-process-power\t1\nsample\t321.50\npackage\tintel-rapl:0\tpackage-0\t9000000\t10000000'
[[ $process_power_snapshot == "$expected_process_power" ]] ||
  fail "activity process power output is exact and includes only the RAPL package domain" "$process_power_snapshot"
pass "activity process power output is exact and includes only the RAPL package domain"

process_power_reader_snapshot=$(
  printf 'ignored\nsample\nsample\n' |
    OMARCHY_SYSTEM_STATS_PROC_PATH="$proc_path" \
      OMARCHY_SYSTEM_STATS_SYS_PATH="$sys_path" \
      "$ROOT/activity-stats" --activity-process-power-reader
)
[[ $(grep -c '^snapshot-end' <<<"$process_power_reader_snapshot") -eq 2 ]] ||
  fail "activity process power reader does not frame each requested sample"
[[ $(grep -c '^package' <<<"$process_power_reader_snapshot") -eq 2 ]] ||
  fail "activity process power reader does not reuse its process for requested samples"
pass "activity process power reader serves framed samples until its input closes"
