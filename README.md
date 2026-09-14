# AutoHotkey v2 Dark Mode GUI Class

A self-contained dark mode GUI framework for AHK v2. One `#Include`, no external dependencies — `DarkGui()` is a drop-in replacement for `Gui()` that handles all the WinAPI custom drawing for you.

```autohotkey
#Include DarkModeModular.ahk

myGui := DarkGui("+Resize", "My App")
myGui.Add("Button", "+Accent", "OK")
myGui.Add("Edit", "w300", "text")
myGui.Show()
```

Or make every window in a script dark with one line. Every `Gui()` constructed after it — including `class X extends Gui` and windows that other libraries create — is attached with all of its controls:

```autohotkey
#Include DarkModeModular.ahk
DarkGui.Global()
```

`DarkGui.Attach(existingGui)` does the same for a single window you already have.

## Which file do I use?

| File | Requires | Role |
|---|---|---|
| `DarkModeModular.ahk` | v2.1-alpha.30 | **Main — use this.** The polished, gated build. |
| `DarkModeModular_Alpha.ahk` | v2.1-alpha.30 | Experimental. New features land here first and are promoted to the main file once the test gates pass. Same API, may carry unfinished work. |
| `DarkModeModular_Classic.ahk` | v2.1-alpha.17 – .28 | Frozen older generation for interpreters before alpha.30 (hand-rolled struct offsets, smaller control coverage). |
| `DarkModeModular_Fable.ahk` | v2.1-alpha.30 | Compatibility shim that includes the main file, so existing `#Include DarkModeModular_Fable.ahk` lines keep working. |

Never include two of these in one script — they declare the same classes.

## What the main build does

- **Coverage** — Button (icon, split, command-link, toggle and flat variants), Edit (dark caret, cue banners), ComboBox and DDL, ListBox, ListView (custom-draw rows, groups, header, checkboxes), TreeView (checkboxes), Tab/Tab2/Tab3, GroupBox, CheckBox and Radio, Slider, Progress (states and marquee), UpDown, DateTime, MonthCal, Hotkey, Link, StatusBar, menu bar and popup menus, tooltips, scrollbars, and opt-in dark MsgBox/InputBox via `DarkDialogs.Install()`.
- **Architecture** — one handler registry (`DarkGui.Handlers`). `DarkGui.Register(type, handler)` plugs user control classes in without editing `Add()`. Subclassing goes through comctl32 `SetWindowSubclass` and reclaims thunks and owner state on `WM_NCDESTROY`; parent-side messages (`WM_CTLCOLOR*`, `WM_NOTIFY`, `WM_DRAWITEM`) dispatch through an hwnd-keyed child registry.
- **Options** — `+Accent`, `+Flat`, `+Toggle[=on]`, `+Icon=<spec> [+Align=..]` on buttons; `c<X>` / `Background<X>` accept a hex value, an AHK colour name or a `DarkTheme.Colors` key that follows palette swaps.
- **Theming** — `DarkTheme.SetPalette()` with presets (Default, OLED, Slate, Blue, Light) and `OnThemeChanged` callbacks. Palette swaps re-sync DWM title-bar colors and `Gui.BackColor` per window. `DarkTheme.FollowSystem()` tracks the OS light/dark setting. Per-monitor DPI via `GetDpiForWindow` and `WM_DPICHANGED` with a `DarkGui.OnDpiChanged()` hook. High-contrast mode stands the theme down automatically.
- **Typed-Struct foundation** — Win32 structs are declared with the alpha.30 `Struct` keyword and class-ref properties (`IntPtr`, `Int32`, `UInt32`, ...); no hand-rolled offset math.

Public API: `DarkGui`, `DarkTheme`, `DarkTitleBar`, `DarkMenu`, `DarkMenuBar`, `DarkScrollbar`, `DarkToolTip`, `DarkDialogs`.

## Showcase

The library has no auto-execute section. Run `Showcase.ahk` for a window that exercises every supported control, the button variants, the palette presets (View menu) and the dark dialogs.

## Built with this system

Real GUIs from the wider script collection, each just `#Include`-ing `DarkModeModular.ahk`:

Teleprompter — WPM-paced reading with strike-through for read words and live font/speed controls:

![Teleprompter](screenshots/App_Teleprompter.png)

Pipeline Monitor — async pipeline visualizer with per-stage status boxes, timings, and live streamed output:

![Pipeline Monitor](screenshots/App_PipelineMonitor.png)

DarkPropertyGrid — editable property-grid custom control with category rows, in-place cell editors, and a change log:

![DarkPropertyGrid demo](screenshots/App_PropertyGrid.png)

DarkRichEdit — themed RICHEDIT50W with named styles, per-run colors, and palette-swap re-theming:

![DarkRichEdit demo](screenshots/App_RichEdit.png)

Advanced button styles — icon, split/dropdown, command-link, toggle, and flat buttons:

![Advanced buttons demo](screenshots/App_AdvancedButtons.png)

Search bar with an embedded flat button inside the Edit's border and a live-filtered list:

![Embedded search demo](screenshots/App_SearchBar.png)

## Screenshots

### Main (`DarkModeModular.ahk`)

Default palette, with DateTime, Hotkey, Tab3, checkbox TreeView, and MonthCal coverage:

![Main showcase, Default palette](screenshots/DarkModeModular_Default.png)

Live palette swap via `DarkTheme.SetPalette()` — OLED and Slate presets applied from the View menu:

![Main showcase, OLED preset](screenshots/DarkModeModular_OLED.png)

![Main showcase, Slate preset](screenshots/DarkModeModular_Slate.png)

The Blue preset carries the accent hue into every surface — background, controls, borders, scrollbars — for windows that should read as blue rather than gray:

![Main showcase, Blue preset](screenshots/DarkModeModular_Blue.png)

### Classic (`DarkModeModular_Classic.ahk`)

![Classic showcase](screenshots/DarkModeModular_Classic.png)

Screenshots are produced with `tools/compose.ps1`, which renders the target window off-screen via `PrintWindow`, then composites it onto the Windows 11 Bloom wallpaper with rounded corners and a drop shadow — no clean desktop required. `tools/capture.ps1` is the simpler live-screen variant.
