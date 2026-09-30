# Activity Monitor

A calm glance at what your machine is doing.

Open it from the bar when you want the picture — CPU, memory, network, disk, and the processes that actually matter. Close it, and it goes quiet. Nothing sits in the background burning power or attention.

It is built to be easy on your eyes and easy on the computer. One small native reader runs only while the panel is open. No extra daemons. No blinking wall of numbers.

![Compact Activity panel](preview-compact.png)

Need more? Expand for GPU and storage, a live process table, and a little die that matches *your* CPU — performance cores, efficient cores, and low-power islands drawn the way the silicon is laid out.

![Expanded Activity panel](preview-expanded.png)

Hybrid Intel, AMD Zen 5c, and ARM big.LITTLE each get their own shape. Older, even chips stay on a simple grid.

![How Activity draws different CPUs](preview-cpu-layouts.png)

## Install

```bash
omarchy plugin add https://github.com/stappmus/omarchy-activity-monitor.git --enable
```

Or from Setup → Plugins. To turn it off later:

```bash
omarchy plugin disable stappmus.activity-monitor
omarchy plugin remove stappmus.activity-monitor
```

## Using it

- Click the bar icon to open. `e` expands, Esc collapses.
- `/` search processes. `j` / `k` move. Click a column header to sort.
- `s` opens settings — update speed, graph history, °C/°F, and whether to estimate process watts.
- Left-click a process to close it. A popup asks first; `x` does the same for the selected row.

Settings are saved with your bar layout and apply immediately.

## A few honest details

Used memory follows Linux available-memory accounting, with cache shown separately because the kernel can reclaim it. GPU memory is what the driver actually reports — shared for integrated, VRAM for discrete. A power-gated GPU clock shows as `IDLE`.

It runs on x86_64 and aarch64, including Apple Silicon under Asahi. Each ships its own prebuilt sampler; on anything else, `make` builds one next to the plugin and it is picked up automatically.

Estimated watts (`~W`) are a share of measured CPU-package energy, not wall power. They only run in the expanded view, and you can turn them off.

If your kernel hides RAPL energy from users, an optional helper package can read it without a password prompt. The plugin never asks for sudo while you are watching the panel.

```bash
makepkg --cleanbuild --install
sudo pacman -Rns omarchy-activity-monitor-power-helper   # to remove it later
```

## Test

```bash
make -B activity-sampler
./test/all.sh
qmllint -I /usr/share/omarchy/shell ActivityController.qml Panel.qml ProcessActionController.qml Sparkline.qml
omarchy plugin validate .
```

After changing the sampler, refresh the committed binary for each architecture with `make prebuilt`, cross-compiling as needed (`make prebuilt CXX=aarch64-linux-gnu-g++`).

Licensed under the MIT License. Started as an Omarchy activity panel and maintained as an independent plugin by Kristoffer Haugland.
