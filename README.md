# napd — KDE Plasma applet

A Plasma 6 panel widget / system-tray applet for [**napd**](https://github.com/metallcorn/napd),
the user-space "App Nap for Linux" power manager. It shows, at a glance, what is
draining the battery and which background apps napd is putting to sleep.

The applet is a **thin client**: it only calls napd's D-Bus `Status()` /
`DailyUsage()` methods and renders the result. It stores nothing and holds no
logic of its own — the [D-Bus contract](https://github.com/metallcorn/napd/blob/main/INTERFACE.md)
lives with the service.

## What it shows

- **Panel / compact rep** — a power *donut*: current watts in the centre, ring
  split between what napd **manages** vs. what it **can't**; a red dot when the
  camera/mic is recording. Display mode is configurable (donut + value, value
  only, donut only).
- **Popup / full rep** — total system draw, the apps currently using CPU,
  anomaly flags (⚠ when an app runs above its own usual), and an expandable
  *"Today's battery use"* breakdown per app.
- **Show only when relevant** — the tray icon is active on battery, passive on AC.

## Requirements

- KDE Plasma 6 (Wayland or X11)
- [napd](https://github.com/metallcorn/napd) running as a `systemd --user` service
- `qdbus6` (ships with Qt 6 / Plasma 6)

## Install

```sh
kpackagetool6 -t Plasma/Applet --install .
# to update after changes:
kpackagetool6 -t Plasma/Applet --upgrade .
# then restart the shell so it reloads:
kquitapp6 plasmashell && kstart plasmashell
```

Then add *"napd"* to a panel or the system tray.

> Judge the theming in the real panel/tray — `plasmawindowed` does **not** apply
> the full Plasma theme.

## License

MIT — see [LICENSE](LICENSE).
