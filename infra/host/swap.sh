#!/usr/bin/env bash
# Emergency swap for a receptor host: 4 GB, vm.swappiness=1, so the kernel swaps only when
# the alternative is the OOM killer taking an emulator (decision.md §9 note, 2026-09-25).
# Swap in real use is an alarm (SwapUsedMB), not a capacity plan. Idempotent.
#   sudo infra/host/swap.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
SWAPFILE=/swapfile
active_names=$(swapon --show=NAME --noheadings)
if [[ $'\n'$active_names$'\n' != *$'\n'"$SWAPFILE"$'\n'* ]]; then
  [[ -f $SWAPFILE ]] || { fallocate -l 4G "$SWAPFILE"; chmod 600 "$SWAPFILE"; mkswap "$SWAPFILE" >/dev/null; }
  swapon "$SWAPFILE"
fi
grep -q "^$SWAPFILE " /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
echo "vm.swappiness=1" > /etc/sysctl.d/90-aea-swap.conf
sysctl -q -p /etc/sysctl.d/90-aea-swap.conf
active=$(swapon --show=NAME,SIZE --noheadings)
[[ $active == *"$SWAPFILE"* && $(cat /proc/sys/vm/swappiness) == 1 ]] || { echo "SWAP_FAILED: $active" >&2; exit 1; }
echo "SWAP_OK $active swappiness=1"
