# AutoHotkey v2 Dark Mode GUI Class

A self-contained dark mode GUI framework for AHK v2. One `#Include`, no external dependencies — `DarkGui()` is a drop-in replacement for `Gui()` that handles all the WinAPI custom drawing for you.

```autohotkey
#Include DarkModeModular_Fable.ahk

myGui := DarkGui("+Resize", "My App")
myGui.Add("Button", "+Accent", "OK")
myGui.Add("Edit", "w300", "text")
myGui.Show()
```

## Which file do I use?

Three generations of the framework, newest last. Pick the one matching your interpreter:

| File | Requires | Status |
|---|---|---|
| `DarkModeModular.ahk` | v2.1-alpha.17+ | Classic — for scripts on alpha.17 through alpha.28 |
| `DarkModeModular_Alpha.ahk` | v2.1-alpha.30 | Typed-Struct port — Win32 structs declared with typed `Struct` + class-ref properties (`IntPtr`, `Int32`, `UInt32`, ...), no hand-rolled offset math |
| `DarkModeModular_Fable.ahk` | v2.1-alpha.30 | **Current — use this for anything new** |

### What the Fable revision adds

- **Coverage** — DateTime, Hotkey, Tab/Tab2/Tab3, TreeView checkboxes, dark tooltips (`DarkToolTip`), dark Edit caret, generalized scrollbars.
- **Correctness** — `WM_SETTEXT` keeps Button/GroupBox captions in sync; native `AddButton`/`AddEdit`/... shorthands route through dark styling; menu-bar tooltips actually display; `MIM_BACKGROUND` uses the cached brush (no leak); radios expose their text to UIA.
- **Architecture** — handler registry (`DarkGui.Register`) so user control classes plug in without editing `Add()`; `DarkGui.Attach()` retrofits an existing plain `Gui`; subclassing via comctl32 `SetWindowSubclass`.
- **Theming** — `DarkTheme.SetPalette()` with presets (Default/OLED/Slate/Blue/Light) plus `OnThemeChanged` callbacks; palette swaps re-sync DWM title-bar colors and `Gui.BackColor` per window; `DarkTheme.FollowSystem()` tracks the OS light/dark setting; per-monitor DPI scaling via `GetDpiForWindow` with `WM_DPICHANGED` handling and a `DarkGui.OnDpiChanged()` hook.

Public API: `DarkGui`, `DarkTheme`, `DarkTitleBar`, `DarkMenu`, `DarkMenuBar`.

## Built with this system

Real GUIs from the wider script collection, each just `#Include`-ing one of the `DarkModeModular*` files:

Win11 chrome demo — live Mica/Acrylic backdrop and caption-color toggles on a DarkGui window:

![Win11 chrome demo](screenshots/App_Win11Chrome.png)

Responsive layout engine settings dialog — anchored controls reflow on resize:

![GuiLayout demo](screenshots/App_GuiLayout.png)

Advanced button styles — icon, split/dropdown, command-link, toggle, and flat buttons:

![Advanced buttons demo](screenshots/App_AdvancedButtons.png)

Search bar with embedded button and live-filtered list:

![Embedded search demo](screenshots/App_SearchBar.png)

## Legacy experiments

`_Dark.ahk`, `_Dark2.ahk`, `__Darkest.ahk`, `___Darkest.ahk`, `Attempt_500.ahk`, `Draft.ahk`, and the `DarkGUI/` folder are earlier iterations kept for reference. They predate the modular rewrite — use the `DarkModeModular*` files instead.

## Screenshots

Each library ships with a built-in showcase — run the file directly (instead of `#Include`-ing it) to open a window exercising every supported control.

### Classic (`DarkModeModular.ahk`)

![Classic showcase](screenshots/DarkModeModular_Classic.png)

### Alpha port (`DarkModeModular_Alpha.ahk`)

![Alpha showcase](screenshots/DarkModeModular_Alpha.png)

### Fable revision (`DarkModeModular_Fable.ahk`)

Default palette, with DateTime, Hotkey, Tab3, checkbox TreeView, and MonthCal coverage:

![Fable showcase, Default palette](screenshots/DarkModeModular_Fable_Default.png)

Live palette swap via `DarkTheme.SetPalette()` — OLED and Slate presets applied from the View menu:

![Fable showcase, OLED preset](screenshots/DarkModeModular_Fable_OLED.png)

![Fable showcase, Slate preset](screenshots/DarkModeModular_Fable_Slate.png)

The Blue preset carries the accent hue into every surface — background, controls, borders, scrollbars — for windows that should read as blue rather than gray:

![Fable showcase, Blue preset](screenshots/DarkModeModular_Fable_Blue.png)

Screenshots are captured with `tools/capture.ps1`, which launches a showcase, finds its window by process ID, and saves the DWM frame bounds to PNG.
