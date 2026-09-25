# hyprsubs DMS widget

A DankMaterialShell bar widget for [hyprsubs](https://github.com/0TrashPanda/hyprsubs) that shows its groups and their subs. It takes the place of the built-in `workspaceSwitcher`, which draws one shape per workspace (so every sub shows up as its own shape).

> Status: v1 implemented. Target: DMS **1.6.2**. Needs a hyprsubs build that sends the `hyprsubs>>` change event.

## Install

```bash
ln -s "$PWD/hyprsubs" ~/.config/DankMaterialShell/plugins/hyprsubs
dms ipc call plugin-scan scan
dms ipc call plugins enable hyprsubs
```

Then in DMS settings → Bar, put the **hyprsubs** widget where `workspaceSwitcher` was (left section).

---

## Look

One pill per group, in group order. Inside each pill, one dot per existing sub. No group or sub numbers.

```
( ○ )  ( ● ○ ○ )  ( ○ ○ )  ( ○ )      ▦
  1        2         3       4        row mode on
```

- **Dots** are in sub order, left to right (sub 1 first), whatever `subs_above` is set to.
- **Current position:** the current sub's dot is filled, and the pill of the current group uses the active colour. Every other dot is hollow.
- **Gaps** (2.1 and 2.3 exist, 2.2 doesn't) are not drawn: the pill just has two dots.
- **Colours and sizes** come from the DMS theme (`Theme.*`), so the widget follows matugen colours and the bar's size and scaling like the built-in switcher.
- **Pill width** grows with the number of dots. Changes (a sub appears, you switch sub) animate with the theme's standard duration.

## Which groups are shown

- Groups that have at least one window, plus the group you are on (even if it's empty).
- This is the same set that the horizontal swipe moves between, so the bar matches what a swipe will do.
- Inside a shown group, **every existing sub** is drawn, empty ones included. That means the current empty sub, plus any sub kept alive by a persistent workspace rule.
- Only the focused monitor, like the plugin. Other monitors' bars show the same state.

## Row mode indicator

- A small icon after the last pill, shown only while the row-mode toggle is on.
- Clicking it runs `hyprsubs:rowmode off`.
- Nothing is shown while row mode is off, so there is nothing to click to turn it on. Use the bind or dispatcher for that.

## Mouse

- **Click a pill:** `hyprsubs:group N`, the same as `SUPER + N`. That means the group's last-used sub, or cycling to the next sub when you're already in that group.
- No scroll handling. There's no per-dot click either: clicking anywhere on the pill counts as clicking the group.

## Data

The state comes from the hyprsubs plugin, in the `hyprctl hyprsubs -j` shape. Each group's `windows` count tells occupied groups from empty ones:

```json
{ "group": 2, "subs": [1, 2, 3], "total": 3, "last_used": 1, "windows": 4 }
```

- **On load** (and on `configreloaded`), the widget runs `hyprctl hyprsubs -j` once.
- **After that,** the plugin pushes every change as a Hyprland IPC event carrying the same JSON on one line: `hyprsubs>>{...}`. The widget listens with Quickshell's `Hyprland.rawEvent` and doesn't poll or spawn processes. The plugin sends the event after workspace, window and monitor-focus changes and after a row-mode toggle, batched and deduplicated.

If the first query fails (hyprsubs not loaded), the widget stays hidden instead of showing stale or empty state.

## Packaging

- The DMS plugin is the `hyprsubs/` directory (`plugin.json` + `HyprsubsWidget.qml`), following the DMS plugin layout (`PLUGINS/README.md` in the DMS tree). See [Install](#install).
- No settings UI in v1.

## Not in v1

- Scroll to cycle groups or subs.
- Clicking a dot to jump to that sub.
- App icons per group or sub.
- Hover tooltip with the grid.
- Vertical bar layout (left / right bar positions). Your bar is at the top; a vertical bar would stack pills vertically, with the dots inside running top to bottom.
