#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command make
require_command g++
require_command file
require_command readelf

make -C "$ROOT" -B activity-sampler >/dev/null

file "$ROOT/activity-sampler" | grep -Fq 'ELF 64-bit' ||
  fail "activity sampler is not a native 64-bit executable"
[[ $(stat -c %s "$ROOT/activity-sampler") -lt 524288 ]] ||
  fail "activity sampler binary exceeds its 512 KiB size budget"
[[ $("$ROOT/activity-sampler" --version) == 'activity-sampler 2.2.0' ]] ||
  fail "activity sampler binary does not match its source release"
readelf -lW "$ROOT/activity-sampler" | grep -Fq 'GNU_RELRO' ||
  fail "activity sampler is missing RELRO hardening"
readelf -dW "$ROOT/activity-sampler" | grep -Fq 'BIND_NOW' ||
  fail "activity sampler is missing immediate binding hardening"
pass "activity sampler builds as a compact hardened native executable"

read_native_frame() {
  local output_fd="$1"
  local kind="$2"
  local line
  while IFS= read -r -u "$output_fd" line; do
    [[ $line == "snapshot-end"$'\t'"$kind" ]] && return 0
  done
  return 1
}

coproc NATIVE_READER { exec "$ROOT/activity-sampler" --activity-reader; }
native_reader_pid=$NATIVE_READER_PID
native_reader_input=${NATIVE_READER[1]}
native_reader_output=${NATIVE_READER[0]}

printf 'resources\n' >&"$native_reader_input"
read_native_frame "$native_reader_output" resources ||
  fail "native activity reader stopped during its resource warmup"
printf 'processes\n' >&"$native_reader_input"
read_native_frame "$native_reader_output" processes ||
  fail "native activity reader stopped during its process warmup"

children=$(<"/proc/$native_reader_pid/task/$native_reader_pid/children")
[[ -z $children ]] || fail "native activity reader launched a subprocess"
pss_kib=$(awk '/^Pss:/ { total += $2 } END { print total + 0 }' "/proc/$native_reader_pid/smaps")
(( pss_kib < 4096 )) ||
  fail "native activity reader exceeds its 4 MiB proportional-memory budget" "PSS: ${pss_kib} KiB"

exec {native_reader_input}>&-
wait "$native_reader_pid"
pass "activity reader stays below 4 MiB PSS and launches no child collectors"

grep -Fq 'dlopen("libnvidia-ml.so.1"' "$ROOT/activity-sampler.cpp" &&
  grep -Fq 'next_fd_discovery_' "$ROOT/activity-sampler.cpp" &&
  grep -Fq 'std::unordered_map<pid_t, Metadata> cache_' "$ROOT/activity-sampler.cpp" ||
  fail "activity sampler does not retain its expensive discovery state"
if grep -Eq 'nvidia-smi|popen[[:space:]]*\(|system[[:space:]]*\(|fork[[:space:]]*\(' \
    "$ROOT/activity-sampler.cpp"; then
  fail "activity sampler invokes an external collector"
fi
pass "activity sampler caches GPU/process discovery and keeps NVML in-process"
