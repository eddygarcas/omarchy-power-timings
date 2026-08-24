# Power Timings

An [Omarchy](https://omarchy.org/) shell plugin that adds a bar widget for
controlling how long the system waits before the screensaver, the lock
screen, and suspend kick in — plus quick "Lock now" / "Suspend now" actions.

## Why

Omarchy's built-in idle service already reads `idle.screensaver` and
`idle.lock` from `~/.config/omarchy/shell.json`, but there's no UI to change
them and no auto-suspend timeout at all. This plugin adds both: a popup with
preset buttons for all three timeouts, and a background timer that suspends
the machine after the configured idle period.

## Install

```
omarchy plugin add https://github.com/eddygarcas/omarchy-power-timings.git --enable
```

Or manually:

```
git clone https://github.com/eddygarcas/omarchy-power-timings.git \
  ~/.config/omarchy/plugins/eduard.power-timings
omarchy-shell shell rescanPlugins
omarchy plugin enable eduard.power-timings
```

## What it does

Click the bar icon to open the panel:

- **Manage power timings** — a switch at the top. Turn it off to disable
  everything below and let the system's own idle defaults apply (screensaver
  and lock keep working as Omarchy ships them; auto-suspend is disabled).
- **Screensaver after** / **Lock after** — preset buttons that write straight
  into `idle.screensaver` / `idle.lock` in `~/.config/omarchy/shell.json`,
  the same keys the built-in idle service already reads.
- **Suspend after** — a new `idle.suspend` timeout. A background service
  (`Service.qml`) watches for that much idle time and runs `systemctl
  suspend`. It respects the existing "Stay awake" indicator, so turning that
  on also pauses auto-suspend.
- **Lock now** / **Suspend now** — run `omarchy-system-lock` /
  `systemctl suspend` directly, regardless of the switch above.

Session locking before any suspend (manual or automatic) is already handled
by Omarchy's own `omarchy-sleep-lock` service, so this plugin never needs to
lock the screen itself before suspending.

## Files

| File           | Purpose                                                        |
|----------------|-----------------------------------------------------------------|
| `manifest.json`| Plugin manifest (`service` + `bar-widget`)                      |
| `Panel.qml`    | Bar icon + popup UI                                              |
| `Service.qml`  | Background auto-suspend timer                                   |
| `Model.js`     | Preset lists and duration formatting                             |

## License

MIT — see [LICENSE](LICENSE).
