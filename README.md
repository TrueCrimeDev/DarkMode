# AutoHotkey v2 Dark Mode GUI Class

Working on a single, self-contained dark mode GUI class for AHK v2. The goal is one class that handles all the WinAPI custom drawing without external dependencies.

## What I'm Building

A single `_Dark` class that you can just drop into any AHK v2 script:

```autohotkey
gui := Gui()
dark := _Dark(gui)
dark.AddDarkButton("x10 y10", "Button")
gui.Show()
```

## Current Issues - Need Help

### 1. Inconsistent Custom Drawing

Controls randomly load with different styling. Sometimes borders are missing, sometimes background colors don't apply. Same control types behave differently between runs.

### 2. Slider Progress Bar Won't Color

The slider track stays Windows default blue. I'm hooking `NM_CUSTOMDRAW` but can't get the progress portion to use my dark colors.

### 3. Border Rendering Problems  

Some controls lose their borders entirely. Others get partial borders. Can't figure out which `CDDS_*` stages I'm missing or what `CDRF_*` codes to return.

## Current Approach

Using `OnMessage(0x004E)` to catch `WM_NOTIFY` messages and intercept `NM_CUSTOMDRAW`. Setting colors with `SetBkColor`/`SetTextColor` and returning appropriate `CDRF_*` codes.

The latest version is in `___Darkest.ahk` - run it and you'll see the inconsistent behavior.

If you know WinAPI custom drawing or have dealt with similar issues in AHK, any help would be appreciated.

## Screenshots

![Dark Mode GUI Example 1](screenshot1.png)

![Dark Mode GUI Example 2](screenshot2.png)