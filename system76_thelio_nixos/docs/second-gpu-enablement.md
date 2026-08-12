# Enabling the second GPU (RTX 2080 Ti) — staged plan

**Status: DEFERRED until after Mecha ships (Peter, 2026-07-31).**
Written down now so the sequence is not lost or re-derived badly later.
**Do not begin this without Peter physically at the console.**

Derived from the 2026-07-31 `nixos-perf-review` measurements.

## Current state (measured, not assumed)

- RTX 2080 Ti at `0000:21:00.0` is bound to **`pci-stub`**, deliberately hidden
  by `pci-stub.ids=10de:1e07` in the kernel command line. **It is not missing
  and not shown to be defective — it is intentionally withheld.**
- RTX 3080 Ti at `0000:49:00.0` is bound to `nvidia`, has `boot_vga=1`, owns the
  only connected DP connector, and is the sole device in `nvidia-smi -L`,
  `/proc/driver/nvidia/gpus`, `/dev/nvidia*` and `/dev/dri/by-path`.
- Session is GNOME 50 on **Wayland**, GDM. Driver 595.84 proprietary,
  DRM modesetting on, `nvidia-persistenced` active.
- **Zero NVIDIA Xid events this boot.**

## Two corrections to prior beliefs — read before planning

1. **The "dual GPU broke Darktide" claim is overstated.** The config comment at
   `configuration.nix:250-260` treats repeated DXGI "monitors not associated
   with any adapter" warnings as evidence that two visible adapters caused
   presentation failure. **A newer counterexample falsifies that implication:**
   the 2026-07-30 Darktide launcher log, on the *current single-GPU* setup,
   emits the same warning for adapter 0, then selects the 3080 Ti and runs
   cleanly for ~71 minutes. The historical two-GPU failure also involved Flatpak
   Steam and beta driver 595.45.04, so adapter count was **confounded** with
   packaging and driver changes. The stub is a valuable known-working baseline;
   it is **not** a proven root-cause fix.
2. **Making the 2080 visible will NOT speed up inference by itself.** Peter's
   Ollama fork (`server/sched.go:981-1039`) selects a *single* GPU when the
   model fits and `OLLAMA_SCHED_SPREAD=false`; it only splits when nothing fits.
   All three installed models (1.6 / 5.2 / 7.6 GB) fit either card. To use the
   2080 you must **bind Ollama to its stable GPU UUID** via
   `CUDA_VISIBLE_DEVICES` and keep spread false.

## The intended end state

**3080 Ti → display + games. 2080 Ti → Ollama inference.**

This removes cross-workload GPU contention: inference stops competing with the
compositor and games for the 3080's 12 GiB and its compute. A single embedding
request may be *slower* on the 2080; measure that trade only after stability.

## Staged plan — one variable at a time, Peter present

### 0. Preflight

- Confirm **Ctrl-Alt-F3 reaches a usable TTY**.
- Confirm **Tailscale/SSH works from another device** (independent way in).
- Confirm `/boot/efi` is genuinely mounted — the config marks it `nofail`.
- **Record the current working generation.** GRUB retains ten.

### 1. One-boot experiment — NO persistent config change

At the GRUB menu, edit the current entry **for this boot only** and remove
exactly `pci-stub.ids=10de:1e07`. Change nothing else. Rebooting the unedited
default automatically restores the known-good stub.

### 2. Gate A — before graphical login (from TTY or SSH)

- Both `21:00.0` and `49:00.0` bound to `nvidia`.
- `nvidia-smi -L` lists both cards.
- Only the 3080's physical DP connector is connected.
- Kernel journal has **no Xid**.
- **Capture the 2080's stable GPU UUID**, and re-run `nvidia-smi topo -m` —
  card *ordinals are not stable* across topology changes, so never rely on
  index numbers.

### 3. Gate B — desktop

Let GDM start. Confirm the session is still **Wayland**, resolution/refresh are
correct, the 3080 remains connector owner, and there is no black screen or
flicker. **Do not start inference yet.**

### 4. Gate C — gaming

Set a **Darktide-only** `VKD3D_FILTER_DEVICE_NAME` substring for "RTX 3080 Ti"
and keep `gamemoderun`. Run a real session; verify the log selects the 3080 and
presentation succeeds.

- **The existing global `DXVK_FILTER_DEVICE_NAME` does NOT apply here** — that
  is D3D8-11/DXVK. Darktide is D3D12 → VKD3D.
- Do **not** use the numeric `VKD3D_VULKAN_DEVICE` index (unstable ordinals).
- Gamescope SDL is a fallback only if direct presentation regresses; it can add
  composition overhead.

### 5. Gate D — inference

With the game closed, expose **only the captured 2080 UUID** to Ollama, keep
`OLLAMA_SCHED_SPREAD=false`, load the embedding model, and verify the runner and
its VRAM appear **only on the 2080**. Then measure codescan throughput and
desktop responsiveness.

### 6. Persistent adoption

Only after **all** gates pass: create a **boot** generation removing the hide
parameter. **Do not live-switch a GPU-binding change.** Reboot with Peter
present and repeat the abbreviated gates.

### 7. Rollback

Bad graphical boot → Ctrl-Alt-F3 or SSH, switch back to the prior generation,
reboot. If neither is reachable, hard reboot and pick the recorded prior
generation from GRUB's NixOS generations submenu. **Restore the declarative
hide before producing another boot generation.**

## Do NOT bundle these with the experiment

Each is a separate one-variable change, later:

- The rejected forced console mode (`video=3440x1440@100`, rejected 3×) and the
  four G-SYNC initialisation failures. 40 `NVRM: VM: invalid mmap context` lines
  also present. Real, but **not proven freeze causes**.
- NVIDIA package version, proprietary-vs-open module choice, Wayland/GDM
  settings, `hardware.nvidia.powerManagement` (correctly left off — it concerns
  experimental suspend/VRAM preservation and laptop PRIME, not desktop gaming),
  or Gamescope defaults.

## VFIO note

The 2080's companion functions are **not all stubbed** — `snd_hda_intel`,
`xhci_hcd` and `nvidia-gpu` own other functions. Any future VFIO/passthrough
plan must check **all functions and their IOMMU groups**. VFIO is not warranted
as the first design.
