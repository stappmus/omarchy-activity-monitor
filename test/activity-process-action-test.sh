#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

victim_pid=""

cleanup() {
  [[ -n $victim_pid ]] || return 0
  kill -KILL "$victim_pid" 2>/dev/null || true
  wait "$victim_pid" 2>/dev/null || true
}
trap cleanup EXIT

start_ticks_for() {
  local pid="$1"
  local stat_line stat_tail
  local -a stat_fields

  stat_line=$(<"/proc/$pid/stat")
  stat_tail="${stat_line##*) }"
  read -r -a stat_fields <<<"$stat_tail"
  printf '%s\n' "${stat_fields[19]}"
}

assert_alive() {
  local pid="$1"
  local description="$2"
  kill -0 "$pid" 2>/dev/null || fail "$description"
}

sleep 30 &
victim_pid=$!
victim_start=$(start_ticks_for "$victim_pid")

if "$ROOT/process-signal" TERM "$victim_pid" invalid 2>/dev/null; then
  fail "process action rejects malformed start ticks"
fi
assert_alive "$victim_pid" "process action rejects malformed start ticks"
pass "process action rejects malformed start ticks"

if "$ROOT/process-signal" TERM "$victim_pid" 0 2>/dev/null; then
  fail "process action rejects zero start ticks"
fi
assert_alive "$victim_pid" "process action rejects zero start ticks"
pass "process action rejects zero start ticks"

if "$ROOT/process-signal" TERM "$victim_pid" "$((victim_start + 1))" 2>/dev/null; then
  fail "process action rejects a stale PID identity"
fi
assert_alive "$victim_pid" "process action left a process alive after rejecting stale identity"
pass "process action rejects a stale PID identity"

if "$ROOT/process-signal" APP_TERM "$victim_pid" "$((victim_start + 1))" 2>/dev/null; then
  fail "app action rejects a stale selected-process identity"
fi
assert_alive "$victim_pid" "app action left a process alive after rejecting stale identity"
pass "app action rejects a stale selected-process identity"

"$ROOT/process-signal" TERM "$victim_pid" "$victim_start" >/dev/null ||
  fail "process action gracefully terminates a matching process"
wait "$victim_pid" 2>/dev/null || true
if kill -0 "$victim_pid" 2>/dev/null; then
  fail "process action gracefully terminates a matching process"
fi
victim_pid=""
pass "process action gracefully terminates a matching process"

python -c '
import time
with open("/proc/self/comm", "w", encoding="ascii") as comm:
    comm.write("quickshell")
time.sleep(30)
' &
victim_pid=$!
for _ in {1..100}; do
  [[ $(<"/proc/$victim_pid/comm") == "quickshell" ]] && break
  sleep 0.01
done
[[ $(<"/proc/$victim_pid/comm") == "quickshell" ]] ||
  fail "protected desktop-session fixture did not become ready"
victim_start=$(start_ticks_for "$victim_pid")
protected_result=$(
  "$ROOT/process-signal" TERM "$victim_pid" "$victim_start" 2>&1
) && fail "process action signaled a protected desktop-session process"
[[ $protected_result == *"protected desktop-session process"* ]] ||
  fail "process action does not explain protected desktop-session rejection" "$protected_result"
assert_alive "$victim_pid" "process action killed a protected desktop-session process"
kill -KILL "$victim_pid"
wait "$victim_pid" 2>/dev/null || true
victim_pid=""
pass "process action protects desktop-session processes in the signal helper"

python - "$ROOT/process-signal" <<'PY' ||
import os
import select
import signal
import subprocess
import sys
import textwrap
import time

helper = sys.argv[1]
app_name = "activity-app"


def start_ticks(pid):
    raw = open(f"/proc/{pid}/stat", "rb").read()
    return raw[raw.rfind(b") ") + 2:].split()[19].decode()


worker_code = textwrap.dedent(
    f"""
    import time
    with open("/proc/self/comm", "w", encoding="ascii") as comm:
        comm.write({app_name!r})
    time.sleep(30)
    """
)

app_code = textwrap.dedent(
    f"""
    import signal
    import subprocess
    import sys
    import time

    with open("/proc/self/comm", "w", encoding="ascii") as comm:
        comm.write({app_name!r})

    worker = None

    def stop_app(_signal, _frame):
        if worker is not None and worker.poll() is None:
            worker.terminate()
        # Do not return to the supervisor loop where the worker would be
        # replaced. Immediate exit also keeps this fixture deterministic when
        # SIGTERM interrupts subprocess.wait().
        sys.stdout.flush()
        sys.stderr.flush()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop_app)
    while True:
        worker = subprocess.Popen(
            [sys.executable, "-c", {worker_code!r}],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(300):
            try:
                worker_name = open(
                    f"/proc/{{worker.pid}}/comm", encoding="ascii"
                ).read().strip()
            except FileNotFoundError:
                worker_name = ""
            if worker_name == {app_name!r}:
                break
            time.sleep(0.01)
        else:
            raise SystemExit(1)
        print(worker.pid, flush=True)
        worker.wait()
        time.sleep(0.05)
    """
)

unrelated = subprocess.Popen(
    [sys.executable, "-c", worker_code],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
app = subprocess.Popen(
    [sys.executable, "-c", app_code],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
selected_pid = None
selected_start = None

try:
    ready, _, _ = select.select([app.stdout], [], [], 3)
    if not ready:
        raise SystemExit(1)
    selected_pid = int(app.stdout.readline().strip())
    selected_start = start_ticks(selected_pid)
    result = subprocess.run(
        [helper, "APP_TERM", str(selected_pid), selected_start],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(1)
    fields = result.stdout.strip().split("\t")
    if fields != ["signaled", str(app.pid), "APP_TERM", "graceful"]:
        raise SystemExit(1)
    if app.wait(timeout=3) != 0:
        raise SystemExit(1)
    if app.stdout.read().strip():
        # Signaling only the selected child would make the app supervisor
        # replace it and announce another PID here.
        raise SystemExit(1)
    if unrelated.poll() is not None:
        # A same-name process outside the selected direct ancestry is not part
        # of the app action.
        raise SystemExit(1)

    stubborn_worker_code = textwrap.dedent(
        f"""
        import ctypes
        import os
        import signal
        import time

        with open("/proc/self/comm", "w", encoding="ascii") as comm:
            comm.write({app_name!r})
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "prctl")
        if os.getppid() == 1:
            raise SystemExit(1)
        time.sleep(30)
        """
    )
    stubborn_app_code = textwrap.dedent(
        f"""
        import signal
        import subprocess
        import sys
        import time

        with open("/proc/self/comm", "w", encoding="ascii") as comm:
            comm.write({app_name!r})
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        worker = subprocess.Popen(
            [sys.executable, "-c", {stubborn_worker_code!r}],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(300):
            try:
                worker_name = open(
                    f"/proc/{{worker.pid}}/comm", encoding="ascii"
                ).read().strip()
            except FileNotFoundError:
                worker_name = ""
            if worker_name == {app_name!r}:
                break
            time.sleep(0.01)
        else:
            raise SystemExit(1)
        print(worker.pid, flush=True)
        while True:
            worker.wait()
            worker = subprocess.Popen(
                [sys.executable, "-c", {stubborn_worker_code!r}],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            print(worker.pid, flush=True)
        """
    )
    app = subprocess.Popen(
        [sys.executable, "-c", stubborn_app_code],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    ready, _, _ = select.select([app.stdout], [], [], 3)
    if not ready:
        raise SystemExit(1)
    selected_pid = int(app.stdout.readline().strip())
    selected_start = start_ticks(selected_pid)
    escalation_started = time.monotonic()
    result = subprocess.run(
        [helper, "APP_TERM", str(selected_pid), selected_start],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(1)
    fields = result.stdout.strip().split("\t")
    if fields != ["signaled", str(app.pid), "APP_TERM", "escalated"]:
        raise SystemExit(1)
    if time.monotonic() - escalation_started < 2.8:
      raise SystemExit(1)
    if app.wait(timeout=5) != -signal.SIGKILL:
        raise SystemExit(1)
    if unrelated.poll() is not None:
        raise SystemExit(1)
finally:
    if app.poll() is None:
        app.terminate()
        try:
            app.wait(timeout=3)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
    if selected_pid is not None:
        try:
            if start_ticks(selected_pid) == selected_start:
                os.kill(selected_pid, signal.SIGKILL)
        except (FileNotFoundError, ProcessLookupError):
            pass
    if unrelated.poll() is None:
        unrelated.kill()
        unrelated.wait()
PY
  fail "app action gracefully closes or escalates app roots without crossing boundaries"
pass "app action gracefully closes or escalates app roots without crossing boundaries"

python - "$ROOT/process-signal" <<'PY' ||
import signal
import subprocess
import sys

helper = sys.argv[1]
victim = subprocess.Popen(["sleep", "30"])
try:
    raw = open(f"/proc/{victim.pid}/stat", "rb").read()
    start_ticks = raw[raw.rfind(b") ") + 2:].split()[19].decode()
    result = subprocess.run(
        [helper, "KILL", str(victim.pid), start_ticks],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(1)
    if victim.wait(timeout=3) != -signal.SIGKILL:
        raise SystemExit(1)
finally:
    if victim.poll() is None:
        victim.kill()
        victim.wait()
PY
  fail "process action force kills a matching disposable process"
pass "process action force kills a matching disposable process"

python - "$ROOT/process-signal" <<'PY' ||
import os
import subprocess
import sys

helper = sys.argv[1]


def start_ticks(pid):
    raw = open(f"/proc/{pid}/stat", "rb").read()
    return raw[raw.rfind(b") ") + 2:].split()[19].decode()


ancestor_pid = os.getpid()
ancestor_start = start_ticks(ancestor_pid)

# Direct parent: the helper is subprocess.run()'s child.
result = subprocess.run(
    [helper, "TERM", str(ancestor_pid), ancestor_start],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    text=True,
    check=False,
)
if result.returncode == 0 or "ancestor chain" not in result.stderr:
    raise SystemExit(1)

# Grandparent: the forked intermediary starts the helper while its parent
# remains the protected target.
intermediary_pid = os.fork()
if intermediary_pid == 0:
    nested = subprocess.run(
        [helper, "TERM", str(ancestor_pid), ancestor_start],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    os._exit(0 if nested.returncode != 0 and "ancestor chain" in nested.stderr else 1)

_, status = os.waitpid(intermediary_pid, 0)
if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    raise SystemExit(1)
PY
  fail "process action protects its helper ancestor chain"
pass "process action protects its helper ancestor chain"

python - "$ROOT/process-signal" <<'PY' ||
import os
import subprocess
import sys
import time

helper = sys.argv[1]
zombie_pid = os.fork()
if zombie_pid == 0:
    os._exit(0)

try:
    for _ in range(100):
        status = open(f"/proc/{zombie_pid}/status", encoding="ascii").read()
        if "\nState:\tZ " in "\n" + status:
            break
        time.sleep(0.01)
    else:
        raise SystemExit(1)

    raw = open(f"/proc/{zombie_pid}/stat", "rb").read()
    start_ticks = raw[raw.rfind(b") ") + 2:].split()[19].decode()
    result = subprocess.run(
        [helper, "TERM", str(zombie_pid), start_ticks],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode == 0 or "zombie or dead" not in result.stderr:
        raise SystemExit(1)
finally:
    os.waitpid(zombie_pid, 0)
PY
  fail "process action rejects zombie processes"
pass "process action rejects zombie processes"

foreign_uid_test=$(python - "$ROOT/process-signal" <<'PY'
import os
from pathlib import Path
import subprocess
import sys

helper = sys.argv[1]
current_uid = os.getuid()
target = None

for status_path in Path("/proc").glob("[0-9]*/status"):
    try:
        status_lines = status_path.read_text(encoding="ascii").splitlines()
        status = {
            line.partition(":")[0]: line.partition(":")[2].strip()
            for line in status_lines
            if ":" in line
        }
        pid = int(status["Pid"])
        user_ids = tuple(int(value) for value in status["Uid"].split())
        raw = (status_path.parent / "stat").read_bytes()
        fields = raw[raw.rfind(b") ") + 2:].split()
        flags = int(fields[6])
        start_ticks = int(fields[19])
    except (FileNotFoundError, KeyError, OSError, ValueError, IndexError):
        continue
    if pid > 1 and current_uid not in user_ids and not flags & 0x00200000:
        target = (pid, start_ticks)
        break

if target is None:
    print("skip")
    raise SystemExit(0)

result = subprocess.run(
    [helper, "TERM", str(target[0]), str(target[1])],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    text=True,
    check=False,
)
if result.returncode == 0 or "another user" not in result.stderr:
    raise SystemExit(1)
print("checked")
PY
) || fail "process action validates ownership from process status"

if [[ $foreign_uid_test == "checked" ]]; then
  pass "process action validates ownership from process status"
else
  pass "no foreign userspace process; skipping ownership rejection test"
fi

kernel_thread_pid=""
kernel_thread_start=""
for stat_file in /proc/[0-9]*/stat; do
  [[ -r $stat_file ]] || continue
  stat_line=$(<"$stat_file") || continue
  stat_tail="${stat_line##*) }"
  read -r -a stat_fields <<<"$stat_tail"
  ((${#stat_fields[@]} > 19)) || continue
  # Early kernel threads can report start time 0, which the helper rejects as malformed.
  if ((stat_fields[6] & 0x00200000 && stat_fields[19] > 0)); then
    kernel_thread_pid="${stat_file%/stat}"
    kernel_thread_pid="${kernel_thread_pid##*/}"
    kernel_thread_start="${stat_fields[19]}"
    break
  fi
done

if [[ -n $kernel_thread_pid ]]; then
  kernel_result=$("$ROOT/process-signal" TERM "$kernel_thread_pid" "$kernel_thread_start" 2>&1) &&
    fail "process action rejects kernel threads"
  [[ $kernel_result == *"kernel thread"* ]] ||
    fail "process action rejects kernel threads" "$kernel_result"
  pass "process action rejects kernel threads"
else
  pass "no visible kernel thread; skipping kernel-thread rejection test"
fi

if "$ROOT/process-signal" TERM 1 0 2>/dev/null; then
  fail "process action protects PID 1"
fi
pass "process action protects PID 1"
