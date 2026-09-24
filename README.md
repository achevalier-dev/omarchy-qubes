# omarchy-qubes

> Early: the VM path has not been run end to end yet.

Qubes-style compartments on Omarchy: KVM guests with a throwaway root, a private
`/home`, and app windows forwarded to Hyprland with a coloured border per qube.

## Pieces

- `bin/qube` — the CLI. Templates, qubes, disposables, file copy.
- `bin/qube-menu` — pickers and notifications for the menu and this widget.
- `~/.config/hypr/qubes.lua` — generated border rules, loaded from `hyprland.lua`.
- This widget — running qubes in the bar; the panel starts them and opens apps.
- `Super+Space` → Qubes — the same actions in the Omarchy menu.

## Install

```bash
omarchy pkg add qemu-base waypipe socat jq
git clone https://github.com/achevalier-dev/omarchy-qubes
omarchy-qubes/install.sh           # links qube + qube-menu, menu rows, Hyprland hook
omarchy plugin add https://github.com/achevalier-dev/omarchy-qubes --enable
```

## Use

```bash
qube template create              # downloads Arch, installs waypipe foot firefox
qube create work --label blue
qube create vault --label black --net none
qube run work firefox
qube dispvm firefox               # deleted when Firefox closes
```

Install more software for every qube with `qube template shell arch`.

## How it isolates

- Each qube is a QEMU/KVM guest under a systemd user unit (`qube-<name>`).
- Root is a fresh qcow2 overlay on the template at every start; only `/home`
  (its own disk) persists. Disposables have no `/home` disk and are deleted.
- Each guest has its own user-mode NAT, so qubes cannot reach each other.
  `--net none` cuts the network entirely.
- Windows arrive through waypipe over SSH on 127.0.0.1, titled `[qube] …`;
  Hyprland colours the border from that prefix.
- `qube copy <from|host> <to> <path…>` is the only file path between qubes.

## Known gaps versus Qubes

- The host is a full desktop with network; Qubes' dom0 has none.
- waypipe forwards the clipboard, so copy/paste crosses qubes freely.
- QEMU's user network maps 10.0.2.2 to the host's loopback, so a guest can
  reach services listening on the host's 127.0.0.1.
- A guest could set a title that imitates another qube's prefix after the
  real one; the border is the signal, not the title text.
- No sys-net/sys-vpn gateway qube yet.
