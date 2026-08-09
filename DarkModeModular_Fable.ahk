/*
DarkModeModular_Fable.ahk — Dark mode GUI framework for AutoHotkey v2 (Fable revision)

Successor to Lib/DarkModeModular_Alpha.ahk targeting the v2.1-alpha.30+Console fork.
Same typed-Struct foundation, plus:

  Coverage    — DateTime, Hotkey, Tab/Tab2/Tab3, TreeView checkboxes, dark
                tooltips (DarkToolTip), dark Edit caret, generalized scrollbars.
  Correctness — WM_SETTEXT keeps Button/GroupBox captions in sync; native
                AddButton/AddEdit/... shorthands route through dark styling;
                menu-bar tooltips actually display; MIM_BACKGROUND uses the
                cached brush (no leak); radios expose their text/ to UIA.
  Architecture— handler registry (DarkGui.Register) so user control classes
                plug in without editing Add(); DarkGui.Attach() retrofits an
                existing plain Gui; subclassing via comctl32 SetWindowSubclass.
  Theming     — DarkTheme.SetPalette()/presets (Default/OLED/Slate/Light) +
                OnThemeChanged callbacks; palette swaps re-sync DWM title-bar
                colors and Gui.BackColor per window; DarkTheme.FollowSystem()
                tracks the OS light/dark setting; per-monitor DPI scaling via
                GetDpiForWindow plus WM_DPICHANGED handling with a
                DarkGui.OnDpiChanged() hook.

Usage:
  #Include DarkModeModular_Fable.ahk
  myGui := DarkGui("+Resize", "My App")
  myGui.Add("Button", "+Accent", "OK")
  myGui.Add("Edit", "w300", "text")
  myGui.Show()

Public API: DarkGui, DarkTheme, DarkTitleBar, DarkMenu, DarkMenuBar,
DarkScrollbar, DarkToolTip. All controls added via DarkGui.Add() are
automatically dark-styled. Use "+Accent" on buttons for blue accent color.
*/
#Requires AutoHotkey v2.1-alpha.30

; Win32 struct catalogue. Field-by-field types; alpha.30 Struct handles
; pointer size and alignment automatically.

Struct DM_RECT {
    left:   Int32
    top:    Int32
    right:  Int32
    bottom: Int32
}

Struct DM_POINT {
    x: Int32
    y: Int32
}

Struct DM_SIZE {
    cx: Int32
    cy: Int32
}

; Three contiguous POINTs for the owner-draw arrow/chevron polygons.
Struct DM_TRIANGLE {
    p: DM_POINT[3]
}

; GdiplusStartupInput — only GdiplusVersion is set; the rest stay zero.
Struct DM_GpInput {
    GdiplusVersion:           UInt32
    DebugEventCallback:       IntPtr
    SuppressBackgroundThread: Int32
    SuppressExternalCodecs:   Int32
}

Struct DM_NMHDR {
    hwndFrom: IntPtr
    idFrom:   IntPtr
    code:     Int32
}

Struct DM_NMCUSTOMDRAW {
    hdr:         DM_NMHDR
    dwDrawStage: UInt32
    hdc:         IntPtr
    rc:          DM_RECT
    dwItemSpec:  IntPtr
    uItemState:  UInt32
    lItemlParam: IntPtr
}

Struct DM_PAINTSTRUCT {
    hdc:         IntPtr
    fErase:      Int32
    rcPaint:     DM_RECT
    fRestore:    Int32
    fIncUpdate:  Int32
    rgbReserved: Int8[32]
}

Struct DM_TRACKMOUSEEVENT {
    cbSize:      UInt32
    dwFlags:     UInt32
    hwndTrack:   IntPtr
    dwHoverTime: UInt32
}

Struct DM_SCROLLBARINFO {
    cbSize:        UInt32
    rcScrollBar:   DM_RECT
    dxyLineButton: Int32
    xyThumbTop:    Int32
    xyThumbBottom: Int32
    reserved:      Int32
    rgstate:       UInt32[6]
}

Struct DM_HDITEMW {
    mask:       UInt32
    cxy:        Int32
    pszText:    IntPtr
    hbm:        IntPtr
    cchTextMax: Int32
    fmt:        Int32
    lParam:     IntPtr
    iImage:     Int32
    iOrder:     Int32
    type:       UInt32
    pvFilter:   IntPtr
    state:      UInt32
}

Struct DM_LVITEMW {
    mask:       UInt32
    iItem:      Int32
    iSubItem:   Int32
    state:      UInt32
    stateMask:  UInt32
    pszText:    IntPtr
    cchTextMax: Int32
    iImage:     Int32
    lParam:     IntPtr
    iIndent:    Int32
    iGroupId:   Int32
    cColumns:   UInt32
    puColumns:  IntPtr
    piColFmt:   IntPtr
    iGroup:     Int32
}

Struct DM_TCITEMW {
    mask:        UInt32
    dwState:     UInt32
    dwStateMask: UInt32
    pszText:     IntPtr
    cchTextMax:  Int32
    iImage:      Int32
    lParam:      IntPtr
}

Struct DM_DRAWITEMSTRUCT {
    CtlType:    UInt32
    CtlID:      UInt32
    itemID:     UInt32
    itemAction: UInt32
    itemState:  UInt32
    hwndItem:   IntPtr
    hDC:        IntPtr
    rcItem:     DM_RECT
    itemData:   IntPtr
}

Struct DM_COMBOBOXINFO {
    cbSize:      UInt32
    rcItem:      DM_RECT
    rcButton:    DM_RECT
    stateButton: UInt32
    hwndCombo:   IntPtr
    hwndItem:    IntPtr
    hwndList:    IntPtr
}

Struct DM_MENUINFO {
    cbSize:          UInt32
    fMask:           UInt32
    dwStyle:         UInt32
    cyMax:           UInt32
    hbrBack:         IntPtr
    dwContextHelpID: UInt32
    dwMenuData:      IntPtr
}

Struct DM_TEXTMETRICW {
    tmHeight:           Int32
    tmAscent:           Int32
    tmDescent:          Int32
    tmInternalLeading:  Int32
    tmExternalLeading:  Int32
    tmAveCharWidth:     Int32
    tmMaxCharWidth:     Int32
    tmWeight:           Int32
    tmOverhang:         Int32
    tmDigitizedAspectX: Int32
    tmDigitizedAspectY: Int32
    tmFirstChar:        UInt16
    tmLastChar:         UInt16
    tmDefaultChar:      UInt16
    tmBreakChar:        UInt16
    tmItalic:           Int8
    tmUnderlined:       Int8
    tmStruckOut:        Int8
    tmPitchAndFamily:   Int8
    tmCharSet:          Int8
}

Struct DM_MCHITTESTINFO {
    cbSize:  UInt32
    pt:      DM_POINT
    uHit:    UInt32
    st:      UInt16[8]
    rc:      DM_RECT
    iOffset: Int32
    iRow:    Int32
    iCol:    Int32
}

; TOOLINFOW (comctl32 v6 layout incl. lpReserved) for TTM_ADDTOOLW.
Struct DM_TOOLINFOW {
    cbSize:     UInt32
    uFlags:     UInt32
    hwnd:       IntPtr
    uId:        IntPtr
    rect:       DM_RECT
    hinst:      IntPtr
    lpszText:   IntPtr
    lParam:     IntPtr
    lpReserved: IntPtr
}

; SCROLLINFO for the generic (non-ListView) DarkScrollbar sync path.
Struct DM_SCROLLINFO {
    cbSize:    UInt32
    fMask:     UInt32
    nMin:      Int32
    nMax:      Int32
    nPage:     UInt32
    nPos:      Int32
    nTrackPos: Int32
}

/**
 * Central theme manager for dark mode colors and GDI brushes.
 * Provides color constants, brush caching, and utility functions.
 */
class DarkTheme {
    /** @type {Map} Color palette. Base tones plus owner-draw button state colors
     * (ButtonHover/ButtonPressed/ButtonBorder, AccentHover/AccentPressed/AccentBorder,
     * FlatPressed) so SetColor and theme switches can reach them — previously these
     * were hardcoded literals inside the button paint paths. */
    static Colors := Map(
        "Background", 0x1A1A1A,
        "Controls", 0x252525,
        "ControlsHover", 0x333333,
        "ControlsActive", 0x404040,
        "Font", 0xE8E8E8,
        "FontDim", 0xA0A0A0,
        "Accent", 0x0078D7,
        "Border", 0x404040,
        "Selection", 0x264F78,
        "GridLine", 0x2A2A2A,
        "Header", 0x2D2D2D,
        "ScrollTrack", 0x3C3C3C,
        "ScrollThumb", 0x5A5A5A,
        "ScrollThumbHover", 0x787878,
        "ButtonHover", 0x303030,
        "ButtonPressed", 0x1F1F1F,
        "ButtonBorder", 0x3A3A3A,
        "AccentHover", 0x1A8CFF,
        "AccentPressed", 0x005A9E,
        "AccentBorder", 0x0064B0,
        "FlatPressed", 0x282828,
        "DisabledBg", 0x202020,
        "DisabledText", 0x6E6E6E,
        "CalendarTrailing", 0x4A4A4A,
        "Link", 0x4CA0FF,
        "SliderThumb", 0xFFFFFF,
        "Error", 0xFF6B6B,
        "Success", 0x5FC95F,
        "Warning", 0xF0A030
    )

    /** @type {Map} Cached GDI brush handles keyed by color name */
    static Brushes := Map()
    /** @type {Map} Value-keyed pen/brush cache built on demand by paint code.
     * Keys: "b|<rgb>" (solid brush), "p|<width>|<rgb>" (pen). DarkTheme owns
     * these handles — paint code must never DeleteObject them. */
    static _GdiCache := Map()
    /** @type {Map} Registered DarkGui window handles, for live re-theming via SetColor */
    static Windows := Map()
    /** @type {Integer} Active DarkGui instance count */
    static _refCount := 0
    /** @type {Boolean} Whether OnExit safety net is registered */
    static _exitRegistered := false

    static __New() {
        for name, color in this.Colors
            this.Brushes[name] := DllCall("gdi32\CreateSolidBrush", "UInt", this.RGBtoBGR(color), "Ptr")
        if !this._exitRegistered {
            OnExit(DarkTheme._OnAppExit)
            this._exitRegistered := true
        }
        this._BuildPresets()
    }

    /** Builds the named preset palettes. Each is a full Colors clone with overrides. */
    static _BuildPresets() {
        this.Presets["Default"] := this.Colors.Clone()

        oled := this.Colors.Clone()
        oled["Background"] := 0x000000
        oled["Controls"] := 0x121212
        oled["ControlsHover"] := 0x1E1E1E
        oled["ControlsActive"] := 0x2A2A2A
        oled["Header"] := 0x161616
        oled["GridLine"] := 0x141414
        oled["Border"] := 0x2A2A2A
        oled["ButtonHover"] := 0x1C1C1C
        oled["ButtonPressed"] := 0x0A0A0A
        oled["ButtonBorder"] := 0x262626
        oled["FlatPressed"] := 0x101010
        oled["DisabledBg"] := 0x0E0E0E
        this.Presets["OLED"] := oled

        slate := this.Colors.Clone()
        slate["Background"] := 0x1B1E26
        slate["Controls"] := 0x252A36
        slate["ControlsHover"] := 0x303747
        slate["ControlsActive"] := 0x3A4255
        slate["Header"] := 0x232834
        slate["GridLine"] := 0x262C3A
        slate["Border"] := 0x3A4255
        slate["ButtonHover"] := 0x2E3545
        slate["ButtonPressed"] := 0x1F2430
        slate["ButtonBorder"] := 0x39415A
        slate["Selection"] := 0x2C4A6E
        this.Presets["Slate"] := slate

        ; Deep-navy palette — the accent hue carried into every surface, not
        ; just buttons and selection, for windows that should read as "blue".
        blue := this.Colors.Clone()
        blue["Background"] := 0x0D1B2E
        blue["Controls"] := 0x16283F
        blue["ControlsHover"] := 0x1E3450
        blue["ControlsActive"] := 0x264060
        blue["Header"] := 0x142438
        blue["GridLine"] := 0x1A2C44
        blue["Border"] := 0x2E4A6E
        blue["ButtonHover"] := 0x1C3350
        blue["ButtonPressed"] := 0x0F2038
        blue["ButtonBorder"] := 0x35557E
        blue["FlatPressed"] := 0x122238
        blue["DisabledBg"] := 0x112034
        blue["Selection"] := 0x1F4E79
        blue["FontDim"] := 0x9FB6D1
        blue["ScrollTrack"] := 0x122238
        blue["ScrollThumb"] := 0x33507A
        blue["ScrollThumbHover"] := 0x466A9E
        blue["CalendarTrailing"] := 0x3E5A80
        this.Presets["Blue"] := blue

        ; Light counterpart for FollowSystem consumers:
        ;   DarkTheme.FollowSystem(l => DarkTheme.ApplyPreset(l ? "Light" : "Default"))
        ; SetPalette syncs the DWM immersive-dark flag and frame colors per window,
        ; so the title bar flips with the palette.
        light := this.Colors.Clone()
        light["Background"] := 0xF3F3F3
        light["Controls"] := 0xFFFFFF
        light["ControlsHover"] := 0xE8E8E8
        light["ControlsActive"] := 0xDCDCDC
        light["Font"] := 0x1A1A1A
        light["FontDim"] := 0x5A5A5A
        light["Border"] := 0xC8C8C8
        light["Selection"] := 0xCCE4F7
        light["GridLine"] := 0xE4E4E4
        light["Header"] := 0xE9E9E9
        light["ScrollTrack"] := 0xDADADA
        light["ScrollThumb"] := 0xA8A8A8
        light["ScrollThumbHover"] := 0x8A8A8A
        light["ButtonHover"] := 0xE6E6E6
        light["ButtonPressed"] := 0xD8D8D8
        light["ButtonBorder"] := 0xBEBEBE
        light["FlatPressed"] := 0xE0E0E0
        light["DisabledBg"] := 0xEDEDED
        light["DisabledText"] := 0x9A9A9A
        light["CalendarTrailing"] := 0xB8B8B8
        light["Link"] := 0x0066CC
        light["SliderThumb"] := 0x2A2A2A
        ; Status colors need re-darkening: the dark-palette tints are chosen for
        ; contrast against 0x1A1A1A and wash out on a light background.
        light["Error"] := 0xC0392B
        light["Success"] := 0x1E7B1E
        light["Warning"] := 0xB26A00
        this.Presets["Light"] := light
    }

    /**
     * True when the active Background color is dark (relative luminance < 0.5).
     * Drives the DWM immersive-dark flag in {@link DarkTheme._SyncWindowFrames}.
     * @returns {Boolean}
     */
    static IsDarkPalette() {
        bg := this.Colors["Background"]
        lum := 0.299 * ((bg >> 16) & 0xFF) + 0.587 * ((bg >> 8) & 0xFF) + 0.114 * (bg & 0xFF)
        return lum < 128
    }

    /**
     * Re-applies DWM frame attributes (immersive dark flag; Win11 caption,
     * caption-text, and border colors) to every registered window so title
     * bars follow palette swaps — without this, ApplyPreset("Light") would
     * leave dark title bars over a light client area.
     */
    static _SyncWindowFrames() {
        if VerCompare(A_OSVersion, "10.0.17763") < 0
            return
        dark := this.IsDarkPalette()
        attr := VerCompare(A_OSVersion, "10.0.18985") >= 0 ? 20 : 19
        isWin11 := VerCompare(A_OSVersion, "10.0.22000") >= 0
        bgBGR := this.RGBtoBGR(this.Colors["Background"])
        borderBGR := this.RGBtoBGR(this.Colors["Border"])
        captionText := dark ? 0xFFFFFF : 0x000000
        for hwnd in this.Windows {
            if !DllCall("IsWindow", "Ptr", hwnd)
                continue
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", attr, "Int*", dark, "Int", 4)
            ; Attributes 34-36 exist from Win11 21H2; the isWin11 gate above is
            ; the guard, so no try is needed to swallow "unsupported".
            if isWin11 {
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 35, "UInt*", bgBGR, "Int", 4)
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 36, "UInt*", captionText, "Int", 4)
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 34, "UInt*", borderBGR, "Int", 4)
            }
            ; Client background brush is per-Gui — swap it with the palette.
            ; v2.1: GuiFromHwnd yields no value on no-match, hence `?? 0`.
            g := GuiFromHwnd(hwnd) ?? 0
            if g
                g.BackColor := this.Colors["Background"]
        }
    }

    ; OnExit handler: extracted to avoid void-result fat-arrow body (alpha.27+ rejects it)
    static _OnAppExit(*) {
        DarkTheme.Cleanup()
        _DarkSlider.Shutdown()
    }

    /**
     * Increments reference count. Called by {@link DarkGui#__New}.
     */
    static AddRef() => ++this._refCount

    /**
     * Decrements the active-window reference count.
     *
     * Deliberately does NOT free brushes here. The palette brushes are
     * process-shared and cheap to keep; freeing them when the count briefly
     * reaches zero breaks any {@link DarkGui} created afterward (the common
     * close-all-then-reopen pattern). Final teardown is {@link DarkTheme.Cleanup},
     * invoked from the {@link DarkTheme._OnAppExit} handler on normal exit.
     */
    static Release() {
        if --this._refCount < 0
            this._refCount := 0
    }

    /**
     * Gets a cached GDI brush handle for the specified color.
     * @param {String} name - Color name from Colors map
     * @returns {Ptr} GDI brush handle or 0 if not found
     */
    static GetBrush(name) => this.Brushes.Get(name, 0)

    /**
     * Updates a theme color and recreates its brush.
     * @param {String} name - Color name to update
     * @param {Integer} value - New RGB color value (0xRRGGBB)
     */
    static SetColor(name, value) {
        if this.Brushes.Has(name)
            DllCall("DeleteObject", "Ptr", this.Brushes[name], "Void")
        this.Colors[name] := value
        this.Brushes[name] := DllCall("gdi32\CreateSolidBrush", "UInt", this.RGBtoBGR(value), "Ptr")
        ; Value-keyed pens/brushes may encode the old color — drop them so the
        ; repaint below rebuilds against the new palette.
        this._FlushGdiCache()
        if name = "Background" || name = "Border"
            this._SyncWindowFrames()
        this._NotifyThemeChanged()
        this.Redraw()
    }

    /** @type {Array} Callbacks invoked with the Colors map after any palette change */
    static _themeCallbacks := []

    /**
     * Registers a callback fired after every palette change (SetColor, SetPalette,
     * ApplyPreset). Receives the live Colors map. Use for app-side recoloring that
     * the automatic Redraw can't reach (e.g. SetFont colors on Text controls).
     * @param {Func} callback - `callback(colorsMap)`
     */
    static OnThemeChanged(callback) => this._themeCallbacks.Push(callback)

    /**
     * Unregisters a callback previously passed to {@link DarkTheme.OnThemeChanged}.
     * Required for objects with a shorter life than the process — the callback
     * array holds a strong reference, so an unremoved entry both leaks the
     * subscriber and fires against its destroyed resources.
     * @param {Func} callback - The same object passed to OnThemeChanged
     * @returns {Boolean} true when an entry was removed
     */
    static OffThemeChanged(callback) {
        for i, cb in this._themeCallbacks {
            if cb = callback {
                this._themeCallbacks.RemoveAt(i)
                return true
            }
        }
        return false
    }

    static _NotifyThemeChanged() {
        for cb in this._themeCallbacks
            cb(this.Colors)
    }

    /**
     * Bulk palette update: replaces every named color present in `palette`,
     * rebuilds brushes once, fires OnThemeChanged callbacks, and repaints all
     * registered windows in a single pass. Unknown names are ignored.
     * @param {Map} palette - name -> 0xRRGGBB
     */
    static SetPalette(palette) {
        for name, value in palette {
            if !this.Colors.Has(name)
                continue
            if this.Brushes.Has(name)
                DllCall("DeleteObject", "Ptr", this.Brushes[name], "Void")
            this.Colors[name] := value
            this.Brushes[name] := DllCall("gdi32\CreateSolidBrush", "UInt", this.RGBtoBGR(value), "Ptr")
        }
        this._FlushGdiCache()
        this._SyncWindowFrames()
        this._NotifyThemeChanged()
        this.Redraw()
    }

    /** @type {Map} Named full palettes built in __New: "Default", "OLED", "Slate", "Blue", "Light" */
    static Presets := Map()

    /**
     * Applies a named preset palette from {@link DarkTheme.Presets}.
     * @param {String} name - Preset name (case-sensitive Map key)
     */
    static ApplyPreset(name) {
        if !this.Presets.Has(name)
            throw ValueError("Unknown DarkTheme preset: " name, -1)
        this.SetPalette(this.Presets[name])
    }

    /**
     * Reads the OS "apps use light theme" personalization setting.
     * @returns {Boolean} true when Windows is set to light app mode
     */
    static SystemUsesLight() {
        try {
            return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                "AppsUseLightTheme", 0) = 1
        } catch Error {
            return false
        }
    }

    static _followCallback := 0
    static _settingHandler := 0

    /**
     * Watches the OS light/dark app-theme setting. The framework itself stays
     * dark; the callback lets the app react (swap presets, show a notice, ...).
     * Invoked immediately with the current state, then on every change.
     * @param {Func} callback - `callback(systemUsesLight)`
     */
    static FollowSystem(callback) {
        static WM_SETTINGCHANGE := 0x001A
        this._followCallback := callback
        if !this._settingHandler {
            this._settingHandler := ObjBindMethod(this, "_OnSettingChange")
            OnMessage(WM_SETTINGCHANGE, this._settingHandler)
        }
        callback(this.SystemUsesLight())
    }

    /** Stops watching the OS theme setting. */
    static UnfollowSystem() {
        static WM_SETTINGCHANGE := 0x001A
        if this._settingHandler {
            OnMessage(WM_SETTINGCHANGE, this._settingHandler, 0)
            this._settingHandler := 0
        }
        this._followCallback := 0
    }

    static _OnSettingChange(wParam, lParam, msg, hwnd) {
        if lParam && StrGet(lParam) = "ImmersiveColorSet" && this._followCallback {
            cb := this._followCallback
            cb(this.SystemUsesLight())
        }
    }

    /**
     * Returns a cached solid brush for an RGB color (0xRRGGBB), created once and
     * reused. Do NOT DeleteObject the result — DarkTheme owns it. Removes the
     * per-WM_PAINT CreateSolidBrush/DeleteObject churn in owner-draw paint paths.
     * @param {Integer} rgb - Color in 0xRRGGBB.
     * @returns {Ptr} Shared GDI brush handle.
     */
    static GetSolidBrush(rgb) {
        key := "b|" rgb
        if this._GdiCache.Has(key)
            return this._GdiCache[key]
        return this._GdiCache[key] := DllCall("gdi32\CreateSolidBrush", "UInt", this.RGBtoBGR(rgb), "Ptr")
    }

    /**
     * Returns a cached solid (PS_SOLID) pen for an RGB color and width, created
     * once and reused. Do NOT DeleteObject the result — DarkTheme owns it.
     * @param {Integer} rgb - Color in 0xRRGGBB.
     * @param {Integer} [width=1] - Pen width in pixels.
     * @returns {Ptr} Shared GDI pen handle.
     */
    static GetPen(rgb, width := 1) {
        key := "p|" width "|" rgb
        if this._GdiCache.Has(key)
            return this._GdiCache[key]
        return this._GdiCache[key] := DllCall("gdi32\CreatePen", "Int", 0, "Int", width, "UInt", this.RGBtoBGR(rgb), "Ptr")
    }

    /**
     * Strokes the standard two-segment dropdown chevron centered on (cx, cy).
     *
     * Single source of truth for the glyph used by the DateTime picker, the
     * ComboBox dropdown, and the UpDown spinner, so all three stay identical by
     * construction. The spinner previously drew filled `Polygon` triangles,
     * which read noticeably heavier than the chevrons beside it.
     *
     * Selects and restores its own pen; the caller's selection is unaffected.
     *
     * @param {Ptr} hdc - Target device context.
     * @param {Integer} cx - Chevron center X.
     * @param {Integer} cy - Chevron center Y.
     * @param {Integer} half - Half-width; each arm spans this many px horizontally.
     * @param {Integer} rise - Arm height in px.
     * @param {Integer} rgb - Stroke color in 0xRRGGBB.
     * @param {Boolean} [up=false] - true points the chevron up, false down.
     * @param {Integer} [thickness=2] - Pen width in px.
     */
    static PaintChevron(hdc, cx, cy, half, rise, rgb, up := false, thickness := 2) {
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", this.GetPen(rgb, thickness), "Ptr")
        ; The tip overshoots center by 1px (as the original inline glyph did) so a
        ; 2px pen lands visually centered rather than a half-pixel high.
        tipY := up ? cy - 1 : cy + 1
        armY := up ? cy + rise : cy - rise
        DllCall("MoveToEx", "Ptr", hdc, "Int", cx - half, "Int", armY, "Ptr", 0, "Void")
        DllCall("LineTo",   "Ptr", hdc, "Int", cx,        "Int", tipY, "Void")
        DllCall("MoveToEx", "Ptr", hdc, "Int", cx,        "Int", tipY, "Ptr", 0, "Void")
        DllCall("LineTo",   "Ptr", hdc, "Int", cx + half, "Int", armY, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")
    }

    /**
     * GDI+ anti-aliased rounded-rectangle fill with an optional border. Smooth
     * corners, unlike gdi32 RoundRect's stair-stepped edges. Colors are 0xRRGGBB
     * and treated as fully opaque; GDI+ takes ARGB directly so there is NO BGR
     * swap here (contrast GetSolidBrush/GetPen, which feed gdi32).
     *
     * The caller must pre-fill the background under this rect — the antialiased
     * edge pixels blend against whatever is already on the dc.
     *
     * Relies on GDI+ being started at load by _DarkSlider.__New().
     * @param {Ptr} hdc - Target device context.
     * @param {Number} x,y,w,h - Bounding rect in pixels.
     * @param {Number} radius - True corner radius in px (clamped to w/2, h/2). Note
     *   gdi32 RoundRect's radius arg is an ellipse *diameter*, so callers porting
     *   from RoundRect pass radius/2 to keep the same visual corner size.
     * @param {Integer} fillRGB - Fill 0xRRGGBB, or -1 for border-only.
     * @param {Integer} [borderRGB=-1] - Border 0xRRGGBB, or -1 for no border.
     * @param {Number} [borderW=1.0] - Border width in px.
     */
    static GdipRoundFill(hdc, x, y, w, h, radius, fillRGB, borderRGB := -1, borderW := 1.0) {
        if w <= 0 || h <= 0
            return
        radius := Min(radius, w / 2, h / 2)
        if radius < 0
            radius := 0

        pGraphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &pGraphics)
        DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)  ; SmoothingModeAntiAlias

        ; Inset by half the pen so an antialiased border isn't clipped at the edge.
        hp := borderRGB = -1 ? 0 : borderW / 2
        path := this._GdipRoundPath(x + hp, y + hp, w - hp * 2, h - hp * 2, radius)

        if fillRGB != -1 {
            pBrush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | fillRGB, "Ptr*", &pBrush)
            DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pBrush, "Ptr", path)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
        }
        if borderRGB != -1 {
            pPen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFF000000 | borderRGB, "Float", borderW, "Int", 2, "Ptr*", &pPen)
            DllCall("gdiplus\GdipDrawPath", "Ptr", pGraphics, "Ptr", pPen, "Ptr", path)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
        }

        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
    }

    /** Builds a GDI+ GraphicsPath for a rounded rect (4 corner arcs). Caller deletes it. */
    static _GdipRoundPath(x, y, w, h, radius) {
        path := 0
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)  ; FillModeAlternate
        if radius <= 0 {
            DllCall("gdiplus\GdipAddPathRectangle", "Ptr", path, "Float", x, "Float", y, "Float", w, "Float", h)
            return path
        }
        d := radius * 2
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x,         "Float", y,         "Float", d, "Float", d, "Float", 180, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y,         "Float", d, "Float", d, "Float", 270, "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y + h - d, "Float", d, "Float", d, "Float", 0,   "Float", 90)
        DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x,         "Float", y + h - d, "Float", d, "Float", d, "Float", 90,  "Float", 90)
        DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        return path
    }

    /** Deletes every value-cached pen/brush and empties the cache. */
    static _FlushGdiCache() {
        for key, h in this._GdiCache
            DllCall("DeleteObject", "Ptr", h, "Void")
        this._GdiCache.Clear()
    }

    /**
     * Forces a full repaint of every registered DarkGui window so palette/brush
     * changes from {@link DarkTheme.SetColor} take effect immediately.
     */
    static Redraw() {
        static RDW_FLAGS := 0x1 | 0x4 | 0x80 | 0x100  ; INVALIDATE | ERASE | ALLCHILDREN | UPDATENOW
        for hwnd in this.Windows {
            if DllCall("IsWindow", "Ptr", hwnd)
                DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", RDW_FLAGS, "Void")
        }
    }

    /**
     * Scales a pixel value by DPI. With an hwnd, uses that window's monitor DPI
     * (GetDpiForWindow, Win10 1607+); otherwise falls back to the system DPI.
     * @param {Integer} px - Pixel value at 96 DPI
     * @param {Ptr} [hwnd=0] - Window whose monitor DPI should be used
     * @returns {Integer} Scaled pixel value
     */
    static Scale(px, hwnd := 0) {
        ; GetDpiForWindow is Win10 1607+; gate on the version rather than
        ; swallowing the failure, so a real error is never hidden.
        if hwnd && VerCompare(A_OSVersion, "10.0.14393") >= 0 {
            dpi := DllCall("user32\GetDpiForWindow", "Ptr", hwnd, "UInt")
            if dpi
                return Round(px * (dpi / 96))
        }
        return Round(px * (A_ScreenDPI / 96))
    }

    /**
     * Converts RGB to BGR format for Win32 GDI functions.
     * @param {Integer} RGB - Color in 0xRRGGBB format
     * @returns {Integer} Color in 0xBBGGRR format
     */
    static RGBtoBGR(RGB) => ((RGB & 0xFF) << 16) | (RGB & 0xFF00) | ((RGB >> 16) & 0xFF)
    /**
     * Converts BGR to RGB format. Same operation as {@link DarkTheme.RGBtoBGR}.
     *
     * @param {Integer} BGR - Color in `0xBBGGRR` format.
     * @returns {Integer} Color in `0xRRGGBB` format.
     */
    static BGRtoRGB(BGR) => this.RGBtoBGR(BGR)

    /**
     * Removes all border styles from a control (WS_BORDER, WS_EX_CLIENTEDGE, WS_EX_STATICEDGE).
     * @param {Ptr} hwnd - Control window handle
     */
    static RemoveBorder(hwnd) {
        static GWL_STYLE := -16
        static GWL_EXSTYLE := -20
        static WS_BORDER := 0x800000
        static WS_EX_CLIENTEDGE := 0x200
        static WS_EX_STATICEDGE := 0x20000
        static SWP_FRAMECHANGED := 0x20
        static SWP_NOMOVE := 0x2
        static SWP_NOSIZE := 0x1
        static SWP_NOZORDER := 0x4

        ; AutoHotkey64.exe is 64-bit only — always the Ptr variants.
        GetWindowLong := "GetWindowLongPtr"
        SetWindowLong := "SetWindowLongPtr"

        ; Remove WS_BORDER from style
        style := DllCall(GetWindowLong, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        DllCall(SetWindowLong, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style & ~WS_BORDER)

        ; Remove WS_EX_CLIENTEDGE and WS_EX_STATICEDGE from extended style
        exStyle := DllCall(GetWindowLong, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        DllCall(SetWindowLong, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", exStyle & ~(WS_EX_CLIENTEDGE | WS_EX_STATICEDGE))

        ; Force redraw with new frame
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "UInt", SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER, "Void")
    }

    /**
     * Calls undocumented AllowDarkModeForWindow (uxtheme ordinal 133).
     * Must be called BEFORE SetWindowTheme for dark mode to take effect on a control.
     * Single source of truth — _DarkTab and DarkMenuBar delegate here rather than
     * resolving ordinal 133 independently.
     * @param {Ptr} hwnd - Control or window handle
     * @param {Boolean} [allow=true] - Enable (true) or disable (false) dark mode for the window
     */
    static AllowDarkMode(hwnd, allow := true) {
        static fn := 0
        if !fn {
            uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
            if !uxtheme
                uxtheme := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
            if uxtheme
                fn := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 133, "Ptr")
        }
        if fn
            DllCall(fn, "Ptr", hwnd, "Int", allow ? 1 : 0)
    }

    /**
     * Frees all cached GDI brush handles.
     * Called automatically by {@link DarkTheme.Release} or on application exit.
     */
    static Cleanup() {
        for name, brush in this.Brushes
            DllCall("DeleteObject", "Ptr", brush, "Void")
        this.Brushes.Clear()
        this._FlushGdiCache()
    }
}

; Prototype extensions — scoped inside DarkPrototypes to avoid global pollution.

/**
 * Installs SetDarkMode() on Gui control prototypes using local function scope.
 * No global function names are introduced.
 */
class DarkPrototypes {
    static __New() {
        _editDark(ctrl) {
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
            ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
            DarkTheme.RemoveBorder(ctrl.Hwnd)
        }
        Gui.Edit.Prototype.DefineProp("SetDarkMode", { Call: _editDark })

        _checkBoxDark(ctrl) {
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        }
        Gui.CheckBox.Prototype.DefineProp("SetDarkMode", { Call: _checkBoxDark })

        _radioDark(ctrl) {
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        }
        Gui.Radio.Prototype.DefineProp("SetDarkMode", { Call: _radioDark })

        ; Per-control colors for Text controls. A "cRed" creation option or
        ; SetFont("cRed") does not survive, because DarkWindowProc answers
        ; WM_CTLCOLORSTATIC for every Static in a DarkGui and sets the DC colors
        ; itself; these route through its override registry instead. Both accept
        ; an 0xRRGGBB integer or a DarkTheme.Colors key ("Error", "Success",
        ; "Warning", "FontDim", ...) — a key is re-resolved on every paint, so
        ; the control follows ApplyPreset and SetColor.
        _setTextColor(ctrl, color) {
            DarkWindowProc.SetStaticColor(ctrl.Hwnd, "text", color)
        }
        Gui.Text.Prototype.DefineProp("SetTextColor", { Call: _setTextColor })

        ; Fills the control's background, which is what lets a bare Text control
        ; act as a solid color swatch.
        _setBackColor(ctrl, color) {
            DarkWindowProc.SetStaticColor(ctrl.Hwnd, "back", color)
        }
        Gui.Text.Prototype.DefineProp("SetBackColor", { Call: _setBackColor })

        ; Returns the control to the palette defaults.
        _resetColors(ctrl) {
            DarkWindowProc.ClearStaticColor(ctrl.Hwnd)
        }
        Gui.Text.Prototype.DefineProp("ResetColors", { Call: _resetColors })

        _treeViewDark(ctrl) {
            static TVM_SETBKCOLOR := 0x111D
            static TVM_SETTEXTCOLOR := 0x111E
            static TVM_SETLINECOLOR := 0x1128
            DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
            SendMessage(TVM_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), ctrl)
            SendMessage(TVM_SETTEXTCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), ctrl)
            SendMessage(TVM_SETLINECOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"]), ctrl)
            DarkTheme.RemoveBorder(ctrl.Hwnd)
        }
        Gui.TreeView.Prototype.DefineProp("SetDarkMode", { Call: _treeViewDark })
    }
}

/**
 * Applies dark mode to window title bar using DWM attributes (Win10 1809+).
 * Uses `DwmSetWindowAttribute` with the immersive dark mode flag.
 */
class DarkTitleBar {
    /**
     * Enables dark title bar for a window.
     *
     * @param {Ptr} hwnd - Window handle.
     * @returns {Boolean} `true` if applied, `false` if OS too old.
     */
    static Apply(hwnd) {
        if VerCompare(A_OSVersion, "10.0.17763") < 0
            return false
        attr := VerCompare(A_OSVersion, "10.0.18985") >= 0 ? 20 : 19
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", attr, "Int*", true, "Int", 4)
        return true
    }
}

/**
 * Dark theming for tooltip windows (`tooltips_class32`).
 * {@link DarkMenuBar} themes its own tooltip window automatically; call
 * {@link DarkToolTip.ApplyAll} after showing AHK `ToolTip()`s to darken those too.
 */
class DarkToolTip {
    /**
     * Dark-themes a single tooltip window.
     * @param {Ptr} hTip - tooltips_class32 window handle
     */
    static Apply(hTip) {
        DarkTheme.AllowDarkMode(hTip)
        DllCall("uxtheme\SetWindowTheme", "Ptr", hTip, "Str", "DarkMode_Explorer", "Ptr", 0)
    }

    /**
     * Dark-themes every tooltip window owned by this script (including the
     * hidden, pre-created `ToolTip()` windows).
     * @returns {Integer} Count of tooltip windows themed
     */
    static ApplyAll() {
        prevDetect := A_DetectHiddenWindows
        DetectHiddenWindows true
        count := 0
        for hwnd in WinGetList("ahk_class tooltips_class32 ahk_pid " ProcessExist()) {
            this.Apply(hwnd)
            count++
        }
        DetectHiddenWindows prevDetect
        return count
    }
}

/**
 * Enables dark mode for application menus using undocumented uxtheme APIs
 * (ordinals 135 `SetPreferredAppMode` and 136 `FlushMenuThemes`).
 */
class DarkMenu {
    /** @type {Boolean} True once the process-wide app mode has been set */
    static _applied := false

    /**
     * Applies dark theme to all menus in the application.
     *
     * Process-wide and idempotent: `SetPreferredAppMode` is a global switch, so
     * repeating it per window (every {@link DarkGui#__New}, every
     * {@link DarkMenuBar}) only costs a redundant theme flush. Every handle is
     * null-checked — an unresolved ordinal previously fell through to
     * `DllCall(0)`, which faults instead of degrading.
     *
     * @returns {Boolean} true when dark menus are active
     */
    static Apply() {
        if this._applied
            return true
        uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
        if !uxtheme
            uxtheme := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
        if !uxtheme
            return false
        setPreferredAppMode := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
        flushMenuThemes := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")
        if !setPreferredAppMode || !flushMenuThemes
            return false
        DllCall(setPreferredAppMode, "Int", 2, "Void")  ; PreferredAppMode::ForceDark
        DllCall(flushMenuThemes, "Void")
        return this._applied := true
    }
}

/**
 * Utility class for window subclassing, backed by comctl32
 * `SetWindowSubclass` / `RemoveWindowSubclass` / `DefSubclassProc`.
 *
 * Safer than the old `SetWindowLongPtr(GWL_WNDPROC)` chain: comctl32 manages
 * the proc chain, uninstall order no longer matters, and multiple `_Dark*`
 * classes can subclass the same hwnd without corrupting each other.
 *
 * Bound procs keep the classic 4-parameter `(hwnd, msg, wParam, lParam)`
 * shape; the SUBCLASSPROC trailing arguments (`uIdSubclass`, `dwRefData`)
 * are simply not read by the callback thunk.
 */
class Subclass {
    /** Subclass id passed to SetWindowSubclass; the callback ptr is the proc identity. */
    static SubclassId := 1

    /** @type {Map} "<owner class>|<hwnd>" -> CallbackCreate pointer.
     *
     * Owned here rather than by each control class. Every _Dark* class used to
     * declare its own `Callbacks` and `OldProcs` pair and thread both through
     * every Install/Uninstall call — 26 declarations holding one fact each. The
     * key includes the owner class, so two classes may subclass the same window
     * (a picker and its dropdown host, say) without evicting each other. */
    static _installed := Map()

    /** Registry key. Accepts a class (static callers) or an instance (DarkScrollbar). */
    static _Key(owner, hwnd) {
        cls := owner is Class ? owner.Prototype.__Class : Type(owner)
        return cls "|" hwnd
    }

    /**
     * Installs a subclass procedure on a control.
     * @param {Object} owner - The calling class or instance; namespaces the registry
     * @param {Ptr} hwnd - Window handle to subclass
     * @param {Func} procMethod - Bound method to use as subclass procedure
     * @returns {Boolean} true if installed, false if already subclassed or API failure
     */
    static Install(owner, hwnd, procMethod) {
        key := this._Key(owner, hwnd)
        if this._installed.Has(key)
            return false
        callback := CallbackCreate(procMethod, , 4)
        if !DllCall("comctl32\SetWindowSubclass", "Ptr", hwnd, "Ptr", callback, "Ptr", this.SubclassId, "Ptr", 0) {
            CallbackFree(callback)
            return false
        }
        this._installed[key] := callback
        return true
    }

    /**
     * True when `owner` already has a subclass installed on `hwnd`.
     * @param {Object} owner - Calling class or instance
     * @param {Ptr} hwnd - Window handle
     * @returns {Boolean}
     */
    static IsInstalled(owner, hwnd) => this._installed.Has(this._Key(owner, hwnd))

    /**
     * Removes the subclass and frees the callback. No-op when not installed.
     * @param {Object} owner - Calling class or instance
     * @param {Ptr} hwnd - Window handle to unsubclass
     */
    static Uninstall(owner, hwnd) {
        key := this._Key(owner, hwnd)
        if !this._installed.Has(key)
            return
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", this._installed[key], "Ptr", this.SubclassId)
        CallbackFree(this._installed[key])
        this._installed.Delete(key)
    }

    /**
     * Forwards a message down the subclass chain (DefSubclassProc). Must be
     * called from inside a subclass procedure.
     *
     * Replaces the former `CallOriginal(oldProc, ...)`, whose first parameter was
     * never read — comctl32 tracks the chain itself, so all 42 call sites were
     * doing a map lookup purely to produce an argument that got discarded.
     *
     * @param {Ptr} hwnd - Window handle
     * @param {Integer} msg - Message
     * @param {Ptr} wParam - wParam
     * @param {Ptr} lParam - lParam
     * @returns {Ptr} Result from DefSubclassProc
     */
    static Forward(hwnd, msg, wParam, lParam) {
        return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
}

/**
 * Custom dark scrollbar control. Creates an owner-draw scrollbar that syncs
 * with the target's scroll position via a 100ms timer. ListView targets use
 * item-count messages; any other vertically scrollable control is driven
 * through GetScrollInfo / WM_VSCROLL.
 *
 * Rendering uses GDI `FillRect` with rounded thumb, hover/drag states,
 * and page-up/page-down on track clicks.
 */
class DarkScrollbar {
    /** @type {Map} Active instances keyed by scrollbar hwnd */
    static Instances := Map()
    /** @type {Integer} Fallback scrollbar width at the system DPI. Instances
     * re-scale against their own monitor in __New — this static is evaluated
     * once at load, so it cannot follow a per-monitor DPI window. */
    static ScrollbarWidth := DarkTheme.Scale(14)

    /**
     * Creates a dark scrollbar alongside a target control.
     *
     * ListView targets sync via item counts (LVM_GETTOPINDEX / LVM_ENSUREVISIBLE);
     * any other control with a standard vertical scrollbar (Edit, ListBox,
     * TreeView, custom) syncs via GetScrollInfo / WM_VSCROLL.
     *
     * @param {DarkGui} gui - Parent GUI instance.
     * @param {Gui.Control} targetCtrl - Control to sync scroll position with.
     * @param {Integer} x - X position.
     * @param {Integer} y - Y position.
     * @param {Integer} h - Height.
     */
    __New(gui, targetCtrl, x, y, h) {
        this.gui := gui
        this.target := targetCtrl
        this.isListView := (targetCtrl.Type = "ListView")
        this.x := x
        this.y := y
        this.h := h
        ; Logical Add-units — gui.Add applies the DPI scale itself; pre-scaling
        ; here double-scaled the width at non-96 DPI.
        this.w := 14

        this.isDragging := false
        this.dragStartY := 0
        this.dragStartPos := 0
        this.isHovering := false
        ; Last painted thumb extent, so the poll timer only repaints on real change.
        this._lastThumbTop := -1
        this._lastThumbBottom := -1

        ; Create the scrollbar as a Text control (we'll custom draw it)
        this.ctrl := gui.Add("Text", "x" x " y" y " w" this.w " h" h " +0x4000000")  ; WS_CLIPSIBLINGS
        this.ctrl.Opt("+Background" Format("{:X}", DarkTheme.Colors["Header"]))

        ; Raw handles for the timer/teardown paths: a control's .Hwnd getter
        ; throws once the Gui is destroyed, and the 100ms timer can outlive it.
        this.hwnd := this.ctrl.Hwnd
        this.targetHwnd := targetCtrl.Hwnd

        ; Store instance reference
        DarkScrollbar.Instances[this.hwnd] := this

        ; Subclass for custom drawing and mouse handling
        this.SubclassScrollbar()

        ; Set up scroll sync timer
        this.syncTimer := ObjBindMethod(this, "SyncFromTarget")
        SetTimer(this.syncTimer, 100)
    }

    SubclassScrollbar() {
        Subclass.Install(this, this.ctrl.Hwnd, ObjBindMethod(this, "ScrollbarProc"))
    }

    ScrollbarProc(hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        static WM_ERASEBKGND := 0x0014
        static WM_LBUTTONDOWN := 0x0201
        static WM_LBUTTONUP := 0x0202
        static WM_MOUSEMOVE := 0x0200
        static WM_MOUSELEAVE := 0x02A3
        static WM_CAPTURECHANGED := 0x0215

        if msg = WM_ERASEBKGND
            return 1

        if msg = WM_PAINT {
            this.Paint()
            return 0
        }

        if msg = WM_LBUTTONDOWN {
            this.OnMouseDown(lParam)
            return 0
        }

        if msg = WM_LBUTTONUP {
            this.OnMouseUp()
            return 0
        }

        if msg = WM_MOUSEMOVE {
            this.OnMouseMove(lParam)
            return 0
        }

        if msg = WM_MOUSELEAVE {
            this.isHovering := false
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
            return 0
        }

        if msg = WM_CAPTURECHANGED {
            this.isDragging := false
            return 0
        }

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    GetScrollInfo() {
        static LVM_GETITEMCOUNT := 0x1004
        static LVM_GETCOUNTPERPAGE := 0x1028
        static LVM_GETTOPINDEX := 0x1027
        static SB_VERT := 1
        static SIF_RANGE := 0x1, SIF_PAGE := 0x2, SIF_POS := 0x4

        if this.isListView {
            ; Get ListView scroll info from item counts
            itemCount := SendMessage(LVM_GETITEMCOUNT, 0, 0, this.targetHwnd)
            visibleCount := SendMessage(LVM_GETCOUNTPERPAGE, 0, 0, this.targetHwnd)
            topIndex := SendMessage(LVM_GETTOPINDEX, 0, 0, this.targetHwnd)

            return {
                min: 0,
                max: Max(0, itemCount - 1),
                page: visibleCount,
                pos: topIndex
            }
        }

        ; Generic path: read the control's real vertical scrollbar state
        si := DM_SCROLLINFO()
        si.cbSize := si.Size
        si.fMask := SIF_RANGE | SIF_PAGE | SIF_POS
        DllCall("GetScrollInfo", "Ptr", this.targetHwnd, "Int", SB_VERT, "Ptr", si.Ptr)
        return {
            min: si.nMin,
            max: si.nMax,
            page: Max(1, si.nPage),
            pos: si.nPos
        }
    }

    /** Physical client-pixel height of the scrollbar control. All thumb math
     * must run in physical pixels: mouse lParam coords and the paint DC are
     * physical, while `this.h` is logical Add-units (DPI-scaled by Gui.Add) —
     * mixing them confined the thumb to the top 80% of the track at 125%. */
    _TrackHeight() {
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", this.hwnd, "Ptr", rc)
        return rc.bottom
    }

    GetThumbRect() {
        info := this.GetScrollInfo()
        range := info.max - info.min + 1
        trackH := this._TrackHeight()

        if range <= info.page || range <= 0
            return {top: 0, bottom: trackH, height: trackH}

        thumbHeight := Max(DarkTheme.Scale(30, this.hwnd), (info.page * trackH) // range)
        trackSpace := trackH - thumbHeight

        scrollRange := info.max - info.min - info.page + 1
        if scrollRange <= 0
            thumbTop := 0
        else
            thumbTop := (info.pos * trackSpace) // scrollRange

        return {
            top: thumbTop,
            bottom: thumbTop + thumbHeight,
            height: thumbHeight
        }
    }

    Paint() {
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", this.ctrl.Hwnd, "Ptr", ps.Ptr, "Ptr")

        ; Get client rect
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", this.ctrl.Hwnd, "Ptr", rc)
        w := rc.right
        h := rc.bottom

        ; Draw track (cached brush — do not delete). Palette is read live, not
        ; snapshotted in __New, so SetPalette/ApplyPreset repaint correctly.
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetSolidBrush(DarkTheme.Colors["Header"]), "Void")

        ; Draw thumb
        thumb := this.GetThumbRect()
        thumbColor := this.isHovering || this.isDragging ? DarkTheme.Colors["ScrollThumbHover"] : DarkTheme.Colors["ScrollThumb"]

        ; Rounded anti-aliased pill thumb (was a square-cornered FillRect). The
        ; track fill above is the background the AA edge blends against.
        pad := DarkTheme.Scale(2, this.ctrl.Hwnd)
        tx := pad
        ty := thumb.top + pad
        tw := (w - pad) - pad
        th := (thumb.bottom - pad) - (thumb.top + pad)
        DarkTheme.GdipRoundFill(hdc, tx, ty, tw, th, tw / 2, thumbColor)

        DllCall("EndPaint", "Ptr", this.ctrl.Hwnd, "Ptr", ps.Ptr, "Void")
    }

    OnMouseDown(lParam) {
        mouseY := (lParam >> 16) & 0xFFFF
        if mouseY > 0x7FFF
            mouseY -= 0x10000

        thumb := this.GetThumbRect()

        if mouseY < thumb.top {
            ; Click above thumb - page up
            this.PageUp()
        } else if mouseY > thumb.bottom {
            ; Click below thumb - page down
            this.PageDown()
        } else {
            ; Start dragging thumb
            this.isDragging := true
            this.dragStartY := mouseY
            this.dragStartPos := this.GetScrollInfo().pos
            DllCall("SetCapture", "Ptr", this.ctrl.Hwnd, "Void")
        }

        DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")

        ; Track mouse for hover effects
        tme := DM_TRACKMOUSEEVENT()
        tme.cbSize    := tme.Size
        tme.dwFlags   := 2  ; TME_LEAVE
        tme.hwndTrack := this.ctrl.Hwnd
        DllCall("TrackMouseEvent", "Ptr", tme.Ptr, "Void")
    }

    OnMouseUp() {
        if this.isDragging {
            this.isDragging := false
            DllCall("ReleaseCapture", "Void")
            DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
        }
    }

    OnMouseMove(lParam) {
        mouseY := (lParam >> 16) & 0xFFFF
        if mouseY > 0x7FFF
            mouseY -= 0x10000

        ; Track mouse for hover effects
        if !this.isHovering {
            this.isHovering := true
            tme := DM_TRACKMOUSEEVENT()
            tme.cbSize    := tme.Size
            tme.dwFlags   := 2  ; TME_LEAVE
            tme.hwndTrack := this.ctrl.Hwnd
            DllCall("TrackMouseEvent", "Ptr", tme.Ptr, "Void")
            DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
        }

        if this.isDragging {
            info := this.GetScrollInfo()
            deltaY := mouseY - this.dragStartY

            thumb := this.GetThumbRect()
            trackSpace := this._TrackHeight() - thumb.height

            if trackSpace <= 0
                return

            scrollRange := info.max - info.min - info.page + 1
            if scrollRange <= 0
                return

            deltaPosFloat := (deltaY * scrollRange) / trackSpace
            newPos := this.dragStartPos + Round(deltaPosFloat)
            newPos := Max(info.min, Min(newPos, info.max - info.page + 1))

            this.SetScrollPos(newPos)
        }
    }

    PageUp() {
        info := this.GetScrollInfo()
        newPos := Max(info.min, info.pos - info.page)
        this.SetScrollPos(newPos)
    }

    PageDown() {
        info := this.GetScrollInfo()
        newPos := Min(info.max - info.page + 1, info.pos + info.page)
        this.SetScrollPos(newPos)
    }

    SetScrollPos(pos) {
        static LVM_SCROLL := 0x1014
        static LVM_GETITEMCOUNT := 0x1004
        static LVM_GETTOPINDEX := 0x1027
        static LVM_GETITEMRECT := 0x100E
        static WM_VSCROLL := 0x0115
        static SB_THUMBPOSITION := 4

        if this.isListView {
            ; Clamp position to valid range
            itemCount := SendMessage(LVM_GETITEMCOUNT, 0, 0, this.targetHwnd)
            pos := Max(0, Min(pos, itemCount - 1))

            ; Scroll by pixel delta. LVM_ENSUREVISIBLE (the old approach) only
            ; scrolls minimally — a below-view target lands at the BOTTOM edge,
            ; so page-down advanced one line and downward drags could never
            ; reach the last page of items.
            top := SendMessage(LVM_GETTOPINDEX, 0, 0, this.targetHwnd)
            if pos != top {
                rc := DM_RECT()
                rc.left := 0  ; LVIR_BOUNDS
                if SendMessage(LVM_GETITEMRECT, top, rc.Ptr, this.targetHwnd) {
                    itemH := rc.bottom - rc.top
                    if itemH > 0
                        SendMessage(LVM_SCROLL, 0, (pos - top) * itemH, this.targetHwnd)
                }
            }
        } else {
            ; Generic path: SB_THUMBPOSITION with the position in the high word.
            ; 16-bit limit is fine for control-sized ranges; clamp defensively.
            info := this.GetScrollInfo()
            pos := Max(info.min, Min(pos, info.max))
            DllCall("SendMessage", "Ptr", this.targetHwnd, "UInt", WM_VSCROLL,
                "Ptr", ((pos & 0xFFFF) << 16) | SB_THUMBPOSITION, "Ptr", 0)
        }

        DllCall("InvalidateRect", "Ptr", this.hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    SyncFromTarget() {
        ; Self-destroy once the window dies. Nothing else reliably stops the
        ; timer: the instance sits in static Instances holding this.gui, so
        ; DarkGui.__Delete can never run while the timer keeps the cycle alive.
        if !DllCall("IsWindow", "Ptr", this.hwnd) {
            this.Destroy()
            return
        }
        ; Repaint only when the thumb actually moved. The 100ms poll previously
        ; forced a full InvalidateRect ~10x/sec even on a static list; hover-state
        ; repaints are driven separately by the mouse handlers.
        if this.isDragging
            return
        thumb := this.GetThumbRect()
        if thumb.top = this._lastThumbTop && thumb.bottom = this._lastThumbBottom
            return
        this._lastThumbTop := thumb.top
        this._lastThumbBottom := thumb.bottom
        DllCall("InvalidateRect", "Ptr", this.hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /**
     * Moves and resizes the scrollbar control.
     *
     * @param {Integer} x - New X position.
     * @param {Integer} y - New Y position.
     * @param {Integer} h - New height.
     */
    UpdatePosition(x, y, h) {
        this.x := x
        this.y := y
        this.h := h
        this.ctrl.Move(x, y, this.w, h)
    }

    /**
     * Stops the sync timer and frees the subclass callback. Idempotent —
     * reachable from the timer backstop, DarkGui teardown, and user code.
     */
    Destroy() {
        if this.syncTimer {
            SetTimer(this.syncTimer, 0)
            this.syncTimer := 0
        }
        Subclass.Uninstall(this, this.hwnd)
        if DarkScrollbar.Instances.Has(this.hwnd)
            DarkScrollbar.Instances.Delete(this.hwnd)
    }
}

/**
 * Dark-themed ListView with custom-drawn header, items, and arrow-less scrollbar.
 * Uses NM_CUSTOMDRAW for item/header colors and hides scrollbar arrows.
 */
class _DarkListView extends Gui.ListView {
    /** @type {Map} Header control handles for scroll alignment */
    static HeaderHandles := Map()
    /** @type {Map} Active hover timer states */
    static HoverTimers := Map()
    /** @type {Map} Bound timer functions for hover effects */
    static HoverTimerFuncs := Map()

    static __New() {
        static LVM_GETHEADER := 0x101F
        super.Prototype.GetHeader := SendMessage.Bind(LVM_GETHEADER, 0, 0)
        super.Prototype.SetDarkMode := this.SetDarkMode.Bind(this)
    }

    static SubclassListView(hwnd) {
        Subclass.Install(this, hwnd, ObjBindMethod(this, "ListViewProc", hwnd))
    }

    static StopHoverTimer(hwnd) {
        if this.HoverTimers.Has(hwnd) {
            SetTimer(this.HoverTimerFuncs[hwnd], 0)
            this.HoverTimerFuncs.Delete(hwnd)
            this.HoverTimers.Delete(hwnd)
        }
    }

    /**
     * Removes subclass and frees resources for a ListView.
     * @param {Ptr} hwnd - ListView window handle
     */
    static Remove(hwnd) {
        this.StopHoverTimer(hwnd)
        Subclass.Uninstall(this, hwnd)
        this.HeaderHandles.Delete(hwnd)
        if DarkWindowProc.ListViewControls.Has(hwnd)
            DarkWindowProc.ListViewControls.Delete(hwnd)
    }

    static CreateArrowHideTimerFunc(hwnd, headerHwnd) {
        ; Create a bound function for arrow hiding timer
        return () => (_DarkListView.HideScrollbarArrows(hwnd, headerHwnd), 0)
    }

    /**
     * Temporarily sets a window region that excludes scrollbar arrow areas.
     * Used to prevent Windows from painting arrows during drag operations.
     * Call ClearArrowClipRegion() after the default proc returns.
     * @param {Ptr} hwnd - Window handle
     * @returns {Boolean} True if region was set, false if scrollbar not visible
     */
    static SetArrowClipRegion(hwnd) {
        static OBJID_VSCROLL := -5
        sbi := DM_SCROLLBARINFO()
        sbi.cbSize := sbi.Size
        if !DllCall("GetScrollBarInfo", "Ptr", hwnd, "Int", OBJID_VSCROLL, "Ptr", sbi.Ptr)
            return false
        if sbi.rgstate[1] & 0x8000  ; STATE_SYSTEM_INVISIBLE on the scrollbar itself
            return false

        sbL := sbi.rcScrollBar.left,  sbT := sbi.rcScrollBar.top
        sbR := sbi.rcScrollBar.right, sbB := sbi.rcScrollBar.bottom
        arrowH := DllCall("GetSystemMetrics", "Int", 20)

        rcWin := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
        winL := rcWin.left, winT := rcWin.top
        w := rcWin.right - winL, h := rcWin.bottom - winT

        ; Window-relative arrow coords
        aL := sbL - winL, aR := sbR - winL
        aTopT := sbT - winT, aTopB := sbT + arrowH - winT
        aBotT := sbB - arrowH - winT, aBotB := sbB - winT

        ; Full window region minus arrow rects
        fullRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr")
        topRgn := DllCall("CreateRectRgn", "Int", aL, "Int", aTopT, "Int", aR, "Int", aTopB, "Ptr")
        DllCall("CombineRgn", "Ptr", fullRgn, "Ptr", fullRgn, "Ptr", topRgn, "Int", 4, "Void")  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", topRgn, "Void")
        botRgn := DllCall("CreateRectRgn", "Int", aL, "Int", aBotT, "Int", aR, "Int", aBotB, "Ptr")
        DllCall("CombineRgn", "Ptr", fullRgn, "Ptr", fullRgn, "Ptr", botRgn, "Int", 4, "Void")  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", botRgn, "Void")

        ; System takes ownership of fullRgn - don't delete it
        DllCall("SetWindowRgn", "Ptr", hwnd, "Ptr", fullRgn, "Int", 0, "Void")
        return true
    }

    /**
     * Removes the arrow clip region, restoring full window painting.
     *
     * @param {Ptr} hwnd - Window handle.
     */
    static ClearArrowClipRegion(hwnd) {
        DllCall("SetWindowRgn", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Void")
    }

    /**
     * Creates a WM_NCPAINT region with scrollbar arrow areas excluded.
     * Prevents Windows from painting arrows by clipping them from the paint region.
     * @param {Ptr} hwnd - Window handle
     * @param {Ptr|Integer} wParam - WM_NCPAINT wParam (1=full repaint, or HRGN)
     * @returns {Ptr} New HRGN with arrows excluded, or 0 if scrollbar hidden. Caller must DeleteObject if non-zero.
     */
    static ClipArrowRegion(hwnd, wParam) {
        static OBJID_VSCROLL := -5
        sbi := DM_SCROLLBARINFO()
        sbi.cbSize := sbi.Size
        if !DllCall("GetScrollBarInfo", "Ptr", hwnd, "Int", OBJID_VSCROLL, "Ptr", sbi.Ptr)
            return 0
        if sbi.rgstate[1] & 0x8000  ; STATE_SYSTEM_INVISIBLE
            return 0

        ; Scrollbar rect in screen coords
        sbL := sbi.rcScrollBar.left,  sbT := sbi.rcScrollBar.top
        sbR := sbi.rcScrollBar.right, sbB := sbi.rcScrollBar.bottom
        arrowH := DllCall("GetSystemMetrics", "Int", 20)  ; SM_CYVSCROLL

        ; Build base region from wParam
        if wParam = 1 {
            rcWin := DM_RECT()
            DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
            hrgn := DllCall("CreateRectRgn",
                "Int", rcWin.left, "Int", rcWin.top,
                "Int", rcWin.right, "Int", rcWin.bottom, "Ptr")
        } else {
            ; Copy - must not modify the original region
            hrgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
            DllCall("CombineRgn", "Ptr", hrgn, "Ptr", wParam, "Ptr", hrgn, "Int", 5, "Void")  ; RGN_COPY
        }

        ; Subtract top arrow region (screen coords)
        topRgn := DllCall("CreateRectRgn", "Int", sbL, "Int", sbT, "Int", sbR, "Int", sbT + arrowH, "Ptr")
        DllCall("CombineRgn", "Ptr", hrgn, "Ptr", hrgn, "Ptr", topRgn, "Int", 4, "Void")  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", topRgn, "Void")

        ; Subtract bottom arrow region (screen coords)
        botRgn := DllCall("CreateRectRgn", "Int", sbL, "Int", sbB - arrowH, "Int", sbR, "Int", sbB, "Ptr")
        DllCall("CombineRgn", "Ptr", hrgn, "Ptr", hrgn, "Ptr", botRgn, "Int", 4, "Void")  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", botRgn, "Void")

        return hrgn
    }

    /**
     * Paints over scrollbar arrow areas with track color.
     * Used as fallback for non-WM_NCPAINT repaints (hover effects, scroll events).
     * @param {Ptr} hwnd - Window handle
     */
    static HideScrollbarArrows(hwnd, headerHwnd := 0) {
        static OBJID_VSCROLL := -5
        sbi := DM_SCROLLBARINFO()
        sbi.cbSize := sbi.Size
        if !DllCall("GetScrollBarInfo", "Ptr", hwnd, "Int", OBJID_VSCROLL, "Ptr", sbi.Ptr)
            return
        if sbi.rgstate[1] & 0x8000
            return

        sbLeft  := sbi.rcScrollBar.left,  sbTop    := sbi.rcScrollBar.top
        sbRight := sbi.rcScrollBar.right, sbBottom := sbi.rcScrollBar.bottom
        arrowHeight := DllCall("GetSystemMetrics", "Int", 20)

        rcWin := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
        winLeft := rcWin.left, winTop := rcWin.top

        ; Convert to window-relative coords
        sbLeftW := sbLeft - winLeft, sbTopW := sbTop - winTop
        sbRightW := sbRight - winLeft, sbBottomW := sbBottom - winTop

        hdc := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return

        trackBrush := DarkTheme.GetBrush("ScrollTrack")  ; cached — do not delete
        rc := DM_RECT()

        rc.left := sbLeftW, rc.top := sbTopW, rc.right := sbRightW, rc.bottom := sbTopW + arrowHeight
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", trackBrush, "Void")

        rc.left := sbLeftW, rc.top := sbBottomW - arrowHeight, rc.right := sbRightW, rc.bottom := sbBottomW
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", trackBrush, "Void")

        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }

    static ListViewProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_NCPAINT := 0x0085
        static WM_NCMOUSEMOVE := 0x00A0
        static WM_NCLBUTTONDOWN := 0x00A1
        static WM_NCLBUTTONUP := 0x00A2
        static WM_NCMOUSELEAVE := 0x02A2
        static WM_MOUSEWHEEL := 0x020A
        static WM_VSCROLL := 0x0115
        static WM_MOUSEMOVE := 0x0200
        static WM_LBUTTONUP := 0x0202
        static WM_CAPTURECHANGED := 0x0215
        static WM_TIMER := 0x0113
        static HTVSCROLL := 7
        static HTHSCROLL := 6

        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)

        ; Get header handle for proper alignment
        headerHwnd := this.HeaderHandles.Get(hwnd, 0)

        ; Handle NC paint - clip arrow regions BEFORE default paint
        if msg = WM_NCPAINT {
            clippedRgn := _DarkListView.ClipArrowRegion(hwnd, wParam)
            result := Subclass.Forward(hwnd, msg, clippedRgn || wParam, lParam)
            ; Fill excluded arrow areas with track color
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            if clippedRgn
                DllCall("DeleteObject", "Ptr", clippedRgn, "Void")
            return result
        }

        ; Handle scrollbar mouse interactions - let default handle, then hide arrows
        if msg = WM_NCMOUSEMOVE {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)

            ; Check if over scrollbar - start continuous redraw timer
            if wParam = HTVSCROLL || wParam = HTHSCROLL {
                ; Start high-frequency timer if not already running
                if !this.HoverTimers.Has(hwnd) {
                    timerFn := _DarkListView.CreateArrowHideTimerFunc(hwnd, headerHwnd)
                    this.HoverTimerFuncs[hwnd] := timerFn
                    this.HoverTimers[hwnd] := true
                    SetTimer(timerFn, 30)  ; ~33fps — enough to mask arrow repaints at much lower churn than 16ms/60fps
                }
                _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            } else {
                ; Mouse moved to non-scrollbar NC area - stop timer
                this.StopHoverTimer(hwnd)
            }
            return result
        }

        ; Handle scrollbar click - clip arrows via SetWindowRgn before default proc
        if msg = WM_NCLBUTTONDOWN && (wParam = HTVSCROLL || wParam = HTHSCROLL) {
            _DarkListView.SetArrowClipRegion(hwnd)
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        if msg = WM_NCLBUTTONUP {
            _DarkListView.SetArrowClipRegion(hwnd)
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        if msg = WM_NCMOUSELEAVE {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            this.StopHoverTimer(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            SetTimer(() => (_DarkListView.HideScrollbarArrows(hwnd, headerHwnd), 0), -50)
            SetTimer(() => (_DarkListView.HideScrollbarArrows(hwnd, headerHwnd), 0), -100)
            return result
        }

        ; Handle scroll events - clip during drag, paint-over otherwise
        if msg = WM_MOUSEWHEEL || msg = WM_VSCROLL {
            isDragging := DllCall("GetCapture", "Ptr") = hwnd
            if isDragging
                _DarkListView.SetArrowClipRegion(hwnd)
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            if isDragging
                _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        ; Handle mouse move during scrollbar drag - clip arrows via SetWindowRgn
        if msg = WM_MOUSEMOVE {
            if DllCall("GetCapture", "Ptr") = hwnd {
                _DarkListView.SetArrowClipRegion(hwnd)
                result := Subclass.Forward(hwnd, msg, wParam, lParam)
                _DarkListView.ClearArrowClipRegion(hwnd)
                _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
                return result
            }
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }

        ; Handle timer messages (Windows uses timers for scroll repeat)
        if msg = WM_TIMER {
            isDragging := DllCall("GetCapture", "Ptr") = hwnd
            if isDragging
                _DarkListView.SetArrowClipRegion(hwnd)
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            if isDragging
                _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        ; Handle capture change - drag ended
        if msg = WM_CAPTURECHANGED {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            this.StopHoverTimer(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /**
     * Applies dark mode to a ListView control.
     * Sets body/text/grid colors, custom-draws header and items via
     * `NM_CUSTOMDRAW`, applies `DarkMode_Explorer` theme for dark scrollbars,
     * and removes the default border.
     *
     * @param {Gui.ListView} lv - ListView control instance.
     * @param {String} [style = "Explorer"] - Theme style name.
     */
    static SetDarkMode(lv, style := "Explorer") {
        static LVS_EX_DOUBLEBUFFER := 0x10000
        static LVM_SETBKCOLOR := 0x1001
        static LVM_SETTEXTBKCOLOR := 0x1026
        static LVM_SETTEXTCOLOR := 0x1024
        static NM_CUSTOMDRAW := -12
        static UIS_SET := 1
        static UISF_HIDEFOCUS := 0x1
        static WM_CHANGEUISTATE := 0x0127
        static WM_NOTIFY := 0x4E
        static WM_THEMECHANGED := 0x031A

        lv.Header := lv.GetHeader()

        ; Set ListView body colors and grid line color
        static LVM_SETOUTLINECOLOR := 0x1047
        SendMessage(LVM_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), lv)
        SendMessage(LVM_SETTEXTBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), lv)
        SendMessage(LVM_SETTEXTCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), lv)
        SendMessage(LVM_SETOUTLINECOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["GridLine"]), lv)

        lv.OnMessage(WM_THEMECHANGED, (*) => 0)

        ; Custom draw header and ListView items
        lv.OnMessage(WM_NOTIFY, (lv, wParam, lParam, Msg) {
            static CDDS_ITEMPREPAINT := 0x10001
            static CDDS_PREPAINT := 0x1
            static CDDS_SUBITEM := 0x20000
            static CDDS_ITEMPOSTPAINT := 0x10002
            static CDRF_DODEFAULT := 0x0
            static CDRF_NOTIFYITEMDRAW := 0x20
            static CDRF_NOTIFYSUBITEMDRAW := 0x20
            static CDRF_SKIPDEFAULT := 0x4
            static CDRF_NEWFONT := 0x2
            static HDM_GETITEMCOUNT := 0x1200
            static HDM_GETITEMRECT := 0x1207
            static HDM_GETITEM := 0x120B
            static HDI_TEXT := 0x2
            static DT_CENTER := 0x1
            static DT_VCENTER := 0x4
            static DT_SINGLELINE := 0x20
            static CDIS_SELECTED := 0x1
            static CDIS_FOCUS := 0x10

            if (DM_NMHDR.At(lParam).code != NM_CUSTOMDRAW)
                return

            nmcd := DM_NMCUSTOMDRAW.At(lParam)

            ; Handle header custom draw
            if (nmcd.hdr.hwndFrom = lv.Header) {
                switch nmcd.dwDrawStage {
                    case CDDS_PREPAINT:
                        return CDRF_NOTIFYITEMDRAW
                    case CDDS_ITEMPREPAINT:
                        hdc := nmcd.hdc
                        itemIndex := nmcd.dwItemSpec

                        rc := DM_RECT()
                        SendMessage(HDM_GETITEMRECT, itemIndex, rc.Ptr, lv.Header)

                        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")

                        textBuf := Buffer(256, 0)
                        hdItem := DM_HDITEMW()
                        hdItem.mask       := HDI_TEXT
                        hdItem.pszText    := textBuf.Ptr
                        hdItem.cchTextMax := 128
                        SendMessage(HDM_GETITEM, itemIndex, hdItem.Ptr, lv.Header)

                        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
                        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")

                        left := rc.left + DarkTheme.Scale(8)
                        top := rc.top
                        right := rc.right - DarkTheme.Scale(4)
                        bottom := rc.bottom
                        rcText := DM_RECT()
                        rcText.left := left, rcText.top := top, rcText.right := right, rcText.bottom := bottom

                        DllCall("DrawTextW", "Ptr", hdc, "Ptr", textBuf.Ptr, "Int", -1, "Ptr", rcText, "UInt", DT_VCENTER | DT_SINGLELINE, "Void")

                        return CDRF_SKIPDEFAULT
                }
                return CDRF_DODEFAULT
            }

            return CDRF_DODEFAULT
        })

        ; Item colors are handled parent-side: a control's own NM_CUSTOMDRAW is
        ; sent to its PARENT window, so the control-side hook above only ever
        ; sees the child Header's notifications — an item branch there would be
        ; dead code. Routed through DarkWindowProc's WM_NOTIFY case (the SysLink
        ; pattern): OnNotify is unusable here because its return value never
        ; reaches the control as the message reply (probe-verified on this
        ; build), so item-draw stages are never requested.
        DarkWindowProc.ListViewControls[lv.Hwnd] := true

        lv.Opt("+LV" LVS_EX_DOUBLEBUFFER)
        ; MAKELONG packing: LOWORD = action, HIWORD = element mask. The old
        ; (UIS_SET << 8) form put 0x0101 in the low word — not a valid UIS_*
        ; action — so DefWindowProc ignored the message and focus rectangles
        ; were never suppressed.
        SendMessage(WM_CHANGEUISTATE, UIS_SET | (UISF_HIDEFOCUS << 16), 0, lv)

        ; Apply dark theme to header
        DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Header, "Str", "DarkMode_ItemsView", "Ptr", 0)
        DarkTheme.AllowDarkMode(lv.Hwnd)
        DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", "Explorer", "Ptr", 0)
        DarkTheme.RemoveBorder(lv.Hwnd)

        ; Replace default checkbox ImageList with dark-themed one (only if +Checked)
        static LVS_EX_CHECKBOXES := 0x4
        exStyle := SendMessage(0x1037, 0, 0, lv)  ; LVM_GETEXTENDEDLISTVIEWSTYLE
        if exStyle & LVS_EX_CHECKBOXES
            this.SetDarkCheckboxes(lv)

        ; Store header handle
        this.HeaderHandles[lv.Hwnd] := lv.Header
    }

    /**
     * Creates a state ImageList with native dark-themed checkboxes using the Windows
     * theme engine (OpenThemeData + DrawThemeBackground with BP_CHECKBOX).
     * This renders the same checkbox visuals that standalone CheckBox controls use.
     */
    static SetDarkCheckboxes(lv) {
        static LVM_SETIMAGELIST := 0x1003
        static LVSIL_STATE := 2

        hIml := this.CreateCheckboxImageList(lv.Hwnd, DarkTheme.Colors["Controls"])
        if !hIml
            return
        prev := SendMessage(LVM_SETIMAGELIST, LVSIL_STATE, hIml, lv)
        ; LVS_EX_CHECKBOXES auto-creates a light state list; once detached the
        ; control no longer tracks it, so it is ours to free. Our replacement is
        ; NOT freed here — a ListView owns its state ImageList and destroys it
        ; with the control. (TreeView differs: swapping its state list disables
        ; native checkbox toggling, so {@link _DarkTreeCheckboxes.Apply}
        ; recolors the control's own list in place instead.)
        if prev
            DllCall("comctl32\ImageList_Destroy", "Ptr", prev, "Void")

        ; Subclass the ListView to intercept item insertions and ensure
        ; new rows always get state 1 (unchecked visible box) instead of state 0 (blank)
        this.InstallCheckboxSubclass(lv)
    }

    /**
     * Builds the 2-image state ImageList (unchecked, checked) of native
     * theme-engine checkbox glyphs on a dark fill. State image indices are
     * ONE-based — state N draws list image N-1, state 0 draws nothing — so the
     * list must NOT carry a leading blank (that shifts every glyph by one:
     * unchecked rows render blank, checked rows render the unchecked box).
     * ListView path only — TreeView recolors its own auto-created list in
     * place ({@link _DarkTreeCheckboxes.Apply}) to keep native toggling.
     * @param {Ptr} hwndTheme - Dark-mode-enabled control to source the theme from
     * @param {Integer} bgRgb - Background fill behind the glyph (0xRRGGBB)
     * @returns {Ptr} ImageList handle, or 0 on theme failure
     */
    static CreateCheckboxImageList(hwndTheme, bgRgb) {
        static ILC_COLOR32 := 0x20
        static BP_CHECKBOX := 3
        static CBS_UNCHECKEDNORMAL := 1
        static CBS_CHECKEDNORMAL := 5

        hTheme := DllCall("uxtheme\OpenThemeData", "Ptr", hwndTheme, "Str", "BUTTON", "Ptr")
        if !hTheme
            return 0

        ; Query the theme for the actual checkbox glyph size
        sz := DM_SIZE()
        DllCall("uxtheme\GetThemePartSize", "Ptr", hTheme, "Ptr", 0,
            "Int", BP_CHECKBOX, "Int", CBS_CHECKEDNORMAL, "Ptr", 0, "Int", 1, "Ptr", sz.Ptr)
        glyphW := sz.cx
        glyphH := sz.cy

        ; Use glyph size with padding for the ImageList
        cxImg := glyphW + 4
        cyImg := glyphH + 4

        hIml := DllCall("comctl32\ImageList_Create", "Int", cxImg, "Int", cyImg, "UInt", ILC_COLOR32, "Int", 2, "Int", 1, "Ptr")

        ; Image 0 -> state 1 (unchecked), image 1 -> state 2 (checked)
        states := [CBS_UNCHECKEDNORMAL, CBS_CHECKEDNORMAL]

        for stateVal in states {
            hBmp := this.RenderCheckboxGlyph(hTheme, stateVal, cxImg, cyImg, glyphW, glyphH, bgRgb)
            DllCall("comctl32\ImageList_Add", "Ptr", hIml, "Ptr", hBmp, "Ptr", 0)
            DllCall("DeleteObject", "Ptr", hBmp, "Void")
        }

        DllCall("uxtheme\CloseThemeData", "Ptr", hTheme)
        return hIml
    }

    /**
     * Renders one theme-engine checkbox glyph (BP_CHECKBOX, `stateVal`) centered
     * on an opaque `bgRgb` fill, into a 32bpp top-down DIB section. The dark
     * CHECKED glyph is premultiplied-alpha, and on a plain compatible bitmap the
     * alpha is lost — checked rows showed an invisible smear on the dark fill.
     * After the theme draw, manually composite the premultiplied glyph pixels
     * over the body color and force the image fully opaque.
     * Used by {@link _DarkListView.CreateCheckboxImageList} and the in-place
     * ImageList recolor in {@link _DarkTreeCheckboxes.Apply}.
     * @returns {Ptr} HBITMAP owned by the caller (DeleteObject when done)
     */
    static RenderCheckboxGlyph(hTheme, stateVal, cxImg, cyImg, glyphW, glyphH, bgRgb) {
        static BP_CHECKBOX := 3

        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0)
        NumPut("Int", cxImg, bi, 4)
        NumPut("Int", -cyImg, bi, 8)   ; top-down
        NumPut("UShort", 1, bi, 12)
        NumPut("UShort", 32, bi, 14)
        bits := 0
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdc := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        hBmp := DllCall("CreateDIBSection", "Ptr", hdcScreen, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
        hOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hBmp, "Ptr")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen, "Void")

        ; Fill background with the host control's body color (alpha stays 0)
        rc := DM_RECT()
        rc.left := 0, rc.top := 0, rc.right := cxImg, rc.bottom := cyImg
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetSolidBrush(bgRgb), "Void")

        ; Draw the native themed checkbox glyph
        glyphRC := DM_RECT()
        glyphX := (cxImg - glyphW) // 2
        glyphY := (cyImg - glyphH) // 2
        glyphRC.left := glyphX, glyphRC.top := glyphY, glyphRC.right := glyphX + glyphW, glyphRC.bottom := glyphY + glyphH
        DllCall("uxtheme\DrawThemeBackground", "Ptr", hTheme, "Ptr", hdc,
            "Int", BP_CHECKBOX, "Int", stateVal, "Ptr", glyphRC, "Ptr", 0)
        DllCall("GdiFlush")

        ; Composite: A=0 pixels are the GDI bg fill (keep RGB); partially /
        ; fully covered pixels are premultiplied glyph — blend over the bg.
        bgR := (bgRgb >> 16) & 0xFF, bgG := (bgRgb >> 8) & 0xFF, bgB := bgRgb & 0xFF
        total := cxImg * cyImg
        i := 0
        while i < total {
            addr := bits + i * 4
            px := NumGet(addr, "UInt")
            a := (px >> 24) & 0xFF
            if a != 0 {
                r := ((px >> 16) & 0xFF) + (bgR * (255 - a)) // 255
                g := ((px >> 8) & 0xFF) + (bgG * (255 - a)) // 255
                b := (px & 0xFF) + (bgB * (255 - a)) // 255
                NumPut("UInt", 0xFF000000 | (r << 16) | (g << 8) | b, addr)
            } else {
                NumPut("UInt", 0xFF000000 | (px & 0xFFFFFF), addr)
            }
            i++
        }

        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOld, "Void")
        DllCall("DeleteDC", "Ptr", hdc, "Void")
        return hBmp
    }

    /** Parent-side NM_CUSTOMDRAW reply (invoked from DarkWindowProc.Proc):
     * palette text color on every row, with the Selection fill kept even when
     * the ListView is unfocused. */
    static _ItemCustomDraw(lParam) {
        static CDDS_PREPAINT := 0x1
        static CDDS_ITEMPREPAINT := 0x10001
        static CDRF_DODEFAULT := 0x0
        static CDRF_NOTIFYITEMDRAW := 0x20
        static CDRF_NEWFONT := 0x2
        static CDIS_SELECTED := 0x1

        nmcd := DM_NMCUSTOMDRAW.At(lParam)
        switch nmcd.dwDrawStage {
            case CDDS_PREPAINT:
                return CDRF_NOTIFYITEMDRAW
            case CDDS_ITEMPREPAINT:
                DllCall("SetTextColor", "Ptr", nmcd.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
                bgKey := (nmcd.uItemState & CDIS_SELECTED) ? "Selection" : "Controls"
                DllCall("SetBkColor", "Ptr", nmcd.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[bgKey]), "Void")
                return CDRF_NEWFONT
        }
        return CDRF_DODEFAULT
    }

    static _CheckboxSubclassCallbacks := Map()

    static InstallCheckboxSubclass(lv) {
        hwnd := lv.Hwnd
        ; Re-applying SetDarkMode must not stack a second subclass: that would
        ; orphan the first thunk (WM_DESTROY frees only the map's current entry).
        if this._CheckboxSubclassCallbacks.Has(hwnd)
            return
        cb := CallbackCreate(ObjBindMethod(this, "CheckboxSubclassProc"), , 6)
        this._CheckboxSubclassCallbacks[hwnd] := cb
        DllCall("SetWindowSubclass", "Ptr", hwnd, "Ptr", cb, "Ptr", hwnd, "Ptr", 0, "Void")

        ; Fix any existing rows with state 0
        static LVM_GETITEMCOUNT := 0x1004
        static LVM_SETITEMSTATE := 0x102B
        static LVIS_STATEIMAGEMASK := 0xF000

        rowCount := SendMessage(LVM_GETITEMCOUNT, 0, 0, lv)
        loop rowCount {
            idx := A_Index - 1
            curState := SendMessage(0x102C, idx, LVIS_STATEIMAGEMASK, lv)  ; LVM_GETITEMSTATE
            if (curState & 0xF000) = 0 {
                ; LVM_SETITEMSTATE reads only state (offset 12) and stateMask (offset 16);
                ; the item index comes from wParam, so iItem/iSubItem are ignored here.
                lvItem := DM_LVITEMW()
                lvItem.state     := 0x1000
                lvItem.stateMask := LVIS_STATEIMAGEMASK
                SendMessage(LVM_SETITEMSTATE, idx, lvItem.Ptr, lv)
            }
        }
    }

    static CheckboxSubclassProc(hwnd, msg, wParam, lParam, uIdSubclass, dwRefData) {
        static LVM_INSERTITEMA := 0x1007
        static LVM_INSERTITEMW := 0x104D
        static LVM_SETITEMSTATE := 0x102B
        static LVIS_STATEIMAGEMASK := 0xF000
        static WM_DESTROY := 0x0002

        ; Intercept item insertion — if state image is 0 (blank), set to 1 (unchecked).
        ; Overlay the incoming DM_LVITEMW so the real field offsets (state=12, stateMask=16)
        ; are used; the earlier raw-offset math clobbered iItem/iSubItem instead.
        static LVIF_STATE := 0x8
        if msg = LVM_INSERTITEMA || msg = LVM_INSERTITEMW {
            if lParam {
                item := DM_LVITEMW.At(lParam)
                if ((item.state & 0xF000) >> 12) = 0 {
                    ; LVM_INSERTITEM only honors state when LVIF_STATE is in mask
                    item.mask      |= LVIF_STATE
                    item.state     |= 0x1000
                    item.stateMask |= LVIS_STATEIMAGEMASK
                }
            }
        }

        if msg = WM_DESTROY {
            if _DarkListView._CheckboxSubclassCallbacks.Has(hwnd) {
                cb := _DarkListView._CheckboxSubclassCallbacks[hwnd]
                DllCall("RemoveWindowSubclass", "Ptr", hwnd, "Ptr", cb, "Ptr", hwnd, "Void")
                ; Freeing cb HERE would free the thunk comctl32 is executing to
                ; deliver this very message (verified corruption); defer the
                ; free until after this callback has returned.
                SetTimer(CallbackFree.Bind(cb), -1)
                _DarkListView._CheckboxSubclassCallbacks.Delete(hwnd)
            }
        }

        return DllCall("DefSubclassProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
}

/**
 * Owner-draw dark button with hover/pressed states and rounded corners.
 * Supports both standard dark buttons and accent-colored (blue) buttons.
 * Use mode `"accent"` for primary action buttons.
 *
 * Uses window subclassing for complete control rendering via {@link Subclass}.
 */
class _DarkButton extends Gui.Button {
    static __New() {
        super.Prototype.SetDarkMode := ObjBindMethod(this, "ApplyDarkMode")
    }

    /**
     * Per-button state — one object per hwnd in {@link _DarkButton.State},
     * replacing the former 14 parallel hwnd-keyed maps (one lookup and one
     * delete instead of fourteen, and impossible to forget a map on cleanup).
     */
    class BtnState {
        btn := 0             ; the Gui.Button instance
        text := ""           ; cached button caption
        mode := "default"    ; default|accent|icon|split|command|toggle|flat
        hover := false       ; mouse over the control
        pressed := false     ; mouse/space currently pressing
        focus := false       ; holds keyboard focus (drives the focus ring)
        icon := 0            ; HICON for icon/command buttons (0 = none)
        iconOwned := false   ; true if we loaded it and must DestroyIcon on Remove
        iconAlign := "left"  ; left|right|top|center
        menu := 0            ; split-button Menu shown on arrow click (0 = none)
        onDropdown := 0      ; split-button dropdown callback, alt to menu (0 = none)
        desc := ""           ; command-link description text
        toggle := false      ; latched on/off state for toggle buttons
        hoverArrow := false  ; mouse over the split dropdown-arrow region
    }

    /** @type {Map} hwnd -> {@link _DarkButton.BtnState} */
    static State := Map()

    /** Returns the BtnState for hwnd, creating it on first use. */
    static _State(hwnd) {
        if !this.State.Has(hwnd)
            this.State[hwnd] := _DarkButton.BtnState()
        return this.State[hwnd]
    }

    /**
     * Applies owner-draw dark mode to button.
     * @param {Gui.Button} btn - Button control instance
     * @param {String} mode - "default" for dark grey, "accent" for blue highlight
     */
    static ApplyDarkMode(btn, mode := "default") {
        hwnd := btn.Hwnd
        s := this._State(hwnd)
        s.btn := btn
        ; Idempotent: factories may go gui.Add → DarkGui.Add → ApplyDarkMode("default")
        ; then re-call ApplyDarkMode("icon"|"split"|...). Only install the subclass
        ; and capture the caption once (BtnState defaults cover the rest).
        if !Subclass.IsInstalled(this, hwnd) {
            s.text := btn.Text
            Subclass.Install(this, hwnd, ObjBindMethod(this, "ButtonProc", hwnd))
        }
        s.mode := mode
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /**
     * Removes subclass and frees resources for a button.
     * @param {Ptr} hwnd - Button window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        if this.State.Has(hwnd) {
            s := this.State[hwnd]
            if s.iconOwned && s.icon
                DllCall("DestroyIcon", "Ptr", s.icon, "Void")
            this.State.Delete(hwnd)
        }
    }

    /**
     * Adds an icon button: an image (HICON, image path, or `"file.dll,index"`) plus optional text.
     * @param {Gui} gui - Parent Gui (DarkGui registers automatic cleanup; plain Gui works too)
     * @param {String} options - Standard Gui.Add options (x/y/w/h/etc.)
     * @param {String} text - Button text (empty for icon-only)
     * @param {String|Integer} icon - HICON handle, image path, or `"file.dll,index"` string
     * @param {String} [align="left"] - "left" | "right" | "top" | "center"
     * @returns {Gui.Button}
     */
    static AddIcon(gui, options, text, icon, align := "left") {
        btn := gui.Add("Button", options, text)
        owned := false
        hicon := this._ResolveIcon(icon, &owned, DarkTheme.Scale(16, btn.Hwnd))
        s := this._State(btn.Hwnd)
        s.icon := hicon, s.iconOwned := owned, s.iconAlign := align
        this._RegisterWithGui(gui, btn.Hwnd)
        this.ApplyDarkMode(btn, "icon")
        return btn
    }

    /**
     * Adds a split (dropdown) button: main face fires Click; right-edge arrow opens a menu.
     * @param {Gui} gui - Parent Gui
     * @param {String} options - Standard Gui.Add options
     * @param {String} text - Button text
     * @param {Menu|Func} menuOrCallback - A Menu shown automatically, or a Func receiving (button)
     * @returns {Gui.Button}
     */
    static AddSplit(gui, options, text, menuOrCallback) {
        btn := gui.Add("Button", options, text)
        s := this._State(btn.Hwnd)
        if menuOrCallback is Menu
            s.menu := menuOrCallback
        else if HasMethod(menuOrCallback)
            s.onDropdown := menuOrCallback
        else
            throw TypeError("AddSplit: menuOrCallback must be a Menu or callable", -1)
        this._RegisterWithGui(gui, btn.Hwnd)
        this.ApplyDarkMode(btn, "split")
        return btn
    }

    /**
     * Adds a Vista-style command-link button: large title plus small description, optional left icon.
     * @param {Gui} gui - Parent Gui
     * @param {String} options - Standard Gui.Add options (give it h>=56 for legibility)
     * @param {String} title - Primary line
     * @param {String} description - Secondary line in dim text
     * @param {String|Integer} [icon=0] - Icon spec (0 paints a default chevron)
     * @returns {Gui.Button}
     */
    static AddCommand(gui, options, title, description, icon := 0) {
        btn := gui.Add("Button", options, title)
        owned := false
        hicon := this._ResolveIcon(icon, &owned, DarkTheme.Scale(20, btn.Hwnd))
        s := this._State(btn.Hwnd)
        s.icon := hicon, s.iconOwned := owned, s.desc := description
        this._RegisterWithGui(gui, btn.Hwnd)
        this.ApplyDarkMode(btn, "command")
        return btn
    }

    /**
     * Adds a sticky toggle button. Exposes an `IsToggled` property on the returned button.
     * @param {Gui} gui - Parent Gui
     * @param {String} options - Standard Gui.Add options
     * @param {String} text - Button text
     * @param {Boolean} [initialState=false] - Starting toggle value
     * @returns {Gui.Button}
     */
    static AddToggle(gui, options, text, initialState := false) {
        btn := gui.Add("Button", options, text)
        this._State(btn.Hwnd).toggle := !!initialState
        btn.DefineProp("IsToggled", {
            Get: (b) => _DarkButton._State(b.Hwnd).toggle,
            Set: (b, v) => (_DarkButton._State(b.Hwnd).toggle := !!v,
                            DllCall("InvalidateRect", "Ptr", b.Hwnd, "Ptr", 0, "Int", 1, "Void"), 0)
        })
        this._RegisterWithGui(gui, btn.Hwnd)
        this.ApplyDarkMode(btn, "toggle")
        return btn
    }

    /**
     * Adds a flat (borderless) button: no fill at idle, hover/press only.
     * @param {Gui} gui - Parent Gui
     * @param {String} options - Standard Gui.Add options
     * @param {String} text - Button text
     * @returns {Gui.Button}
     */
    static AddFlat(gui, options, text) {
        btn := gui.Add("Button", options, text)
        this._RegisterWithGui(gui, btn.Hwnd)
        this.ApplyDarkMode(btn, "flat")
        return btn
    }

    /**
     * Resolves an icon spec to an HICON handle.
     * @param {*} icon - HICON int, image path string, or `"file.dll,index"` string
     * @param {VarRef<Boolean>} owned - Set true when this call allocated the icon
     * @param {Integer} sizePx - Target size in pixels (used for LoadImage)
     * @returns {Ptr} HICON or 0
     */
    static _ResolveIcon(icon, &owned, sizePx) {
        owned := false
        if !icon
            return 0
        if IsObject(icon)
            return 0
        if icon is Integer
            return icon
        s := String(icon)
        if s = ""
            return 0
        owned := true
        if InStr(s, ",") {
            parts := StrSplit(s, ",")
            iconPath := parts[1]
            idx := Integer(parts.Get(2, 0))
            return DllCall("shell32\ExtractIconW", "Ptr", 0, "Str", iconPath, "UInt", idx, "Ptr")
        }
        static IMAGE_ICON := 1, LR_LOADFROMFILE := 0x10
        return DllCall("user32\LoadImageW", "Ptr", 0, "Str", s, "UInt", IMAGE_ICON,
                       "Int", sizePx, "Int", sizePx, "UInt", LR_LOADFROMFILE, "Ptr")
    }

    /**
     * Registers an hwnd with a DarkGui's cleanup map when applicable.
     * @param {Gui} gui
     * @param {Ptr} hwnd
     */
    static _RegisterWithGui(gui, hwnd) {
        if HasProp(gui, "_darkHwnds")
            gui._darkHwnds[hwnd] := "Button"
    }

    static ButtonProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        static WM_ENABLE := 0x000A
        static WM_ERASEBKGND := 0x0014
        static WM_MOUSEMOVE := 0x0200
        static WM_MOUSELEAVE := 0x02A3
        static WM_LBUTTONDOWN := 0x0201
        static WM_LBUTTONUP := 0x0202

        if msg = WM_ERASEBKGND
            return 1

        if msg = WM_PAINT {
            this.PaintButton(targetHwnd)
            return 0
        }

        ; Keep the cached caption in sync when code calls btn.Text := "..."
        ; (WM_SETTEXT), then repaint — otherwise the owner-draw text goes stale.
        static WM_SETTEXT := 0x000C
        if msg = WM_SETTEXT {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._State(targetHwnd).text := lParam ? StrGet(lParam) : ""
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return result
        }

        ; Every remaining handler reads/writes this button's state.
        s := this._State(targetHwnd)

        ; Repaint when the enabled state flips so the dimmed look tracks .Enabled.
        if msg = WM_ENABLE {
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }

        if msg = WM_MOUSEMOVE {
            ; Sign-extend the LOWORD/HIWORD of lParam to handle negative coords during capture
            mx := lParam & 0xFFFF
            if mx & 0x8000
                mx -= 0x10000
            inArrow := this._IsSplitButton(targetHwnd) && this._PointInArrow(targetHwnd, mx)
            ; hoverArrow defaults false on non-split buttons, so this is a no-op there.
            if s.hoverArrow != inArrow {
                s.hoverArrow := inArrow
                DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            }
            if !s.hover {
                s.hover := true
                static TME_LEAVE := 0x2
                tme := DM_TRACKMOUSEEVENT()
                tme.cbSize    := tme.Size
                tme.dwFlags   := TME_LEAVE
                tme.hwndTrack := targetHwnd
                DllCall("TrackMouseEvent", "Ptr", tme.Ptr, "Void")
                DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            }
            ; Forward, don't swallow. comctl32 tooltips attach with TTF_SUBCLASS
            ; and need the mouse messages relayed down the chain; returning 0
            ; here left every dark button tooltip-deaf. We still own WM_PAINT /
            ; WM_ERASEBKGND, so the default proc's hot-tracking can't draw.
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }

        if msg = WM_MOUSELEAVE {
            s.hover := false
            s.hoverArrow := false
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }

        if msg = WM_LBUTTONDOWN {
            ; The native BUTTON proc focuses itself here; we take the message
            ; over (to run our own capture/press/click path), so do it by hand —
            ; without this a clicked dark button never receives keyboard focus
            ; and the focus ring painted below could only be reached by Tab.
            DllCall("SetFocus", "Ptr", targetHwnd, "Ptr")
            s.pressed := true
            DllCall("SetCapture", "Ptr", targetHwnd, "Void")
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return 0
        }

        if msg = WM_LBUTTONUP {
            wasPressed := s.pressed
            s.pressed := false
            DllCall("ReleaseCapture", "Void")
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            if wasPressed {
                rc := DM_RECT()
                DllCall("GetClientRect", "Ptr", targetHwnd, "Ptr", rc)
                pt := DM_POINT()
                DllCall("GetCursorPos", "Ptr", pt.Ptr)
                DllCall("ScreenToClient", "Ptr", targetHwnd, "Ptr", pt.Ptr, "Void")
                x := pt.x, y := pt.y
                w := rc.right, h := rc.bottom
                if (x >= 0 && x < w && y >= 0 && y < h) {
                    if this._IsSplitButton(targetHwnd) && this._PointInArrow(targetHwnd, x)
                        this._ShowDropdown(targetHwnd)
                    else
                        this._FireClick(targetHwnd)
                }
            }
            return 0
        }

        ; Keyboard parity with native buttons. We own WM_PAINT, so the original
        ; proc's focus rect never shows; track focus ourselves and draw a ring.
        static WM_GETDLGCODE := 0x0087
        static WM_SETFOCUS := 0x0007
        static WM_KILLFOCUS := 0x0008
        static WM_KEYDOWN := 0x0100
        static WM_KEYUP := 0x0101
        static WM_SYSKEYDOWN := 0x0104
        static BM_CLICK := 0x00F5
        static VK_SPACE := 0x20
        static VK_DOWN := 0x28
        static DLGC_BUTTON := 0x2000
        static DLGC_WANTARROWS := 0x0001

        if msg = WM_GETDLGCODE {
            ; Split buttons claim arrow keys so Down can open the dropdown.
            return this._IsSplitButton(targetHwnd) ? DLGC_BUTTON | DLGC_WANTARROWS : DLGC_BUTTON
        }

        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS {
            s.focus := (msg = WM_SETFOCUS)
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }

        if msg = WM_KEYDOWN {
            ; Space presses in (visual only); fires on key-up like a real button.
            if wParam = VK_SPACE {
                if !s.pressed {
                    s.pressed := true
                    DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
                }
                return 0
            }
            if wParam = VK_DOWN && this._IsSplitButton(targetHwnd) {
                this._ShowDropdown(targetHwnd)
                return 0
            }
        }

        ; Alt+Down opens the split dropdown (Win32/.NET convention).
        if msg = WM_SYSKEYDOWN && wParam = VK_DOWN && this._IsSplitButton(targetHwnd) {
            this._ShowDropdown(targetHwnd)
            return 0
        }

        if msg = WM_KEYUP && wParam = VK_SPACE && s.pressed {
            s.pressed := false
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            this._FireClick(targetHwnd)
            return 0
        }

        ; Mnemonic (Alt+letter) and programmatic clicks arrive as BM_CLICK;
        ; route them through the same path so toggle state stays consistent.
        if msg = BM_CLICK {
            this._FireClick(targetHwnd)
            return 0
        }

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /** Flips toggle state when applicable, then notifies the parent with BN_CLICKED
     *  so the Gui's normal Click event fires. Shared by mouse, keyboard, and mnemonic. */
    static _FireClick(hwnd) {
        s := this._State(hwnd)
        if s.mode = "toggle"
            s.toggle := !s.toggle
        parent := DllCall("GetParent", "Ptr", hwnd, "Ptr")
        ctrlId := DllCall("GetDlgCtrlID", "Ptr", hwnd, "Int")
        static BN_CLICKED := 0, WM_COMMAND := 0x0111
        DllCall("SendMessage", "Ptr", parent, "UInt", WM_COMMAND, "Ptr", (BN_CLICKED << 16) | ctrlId, "Ptr", hwnd)
    }

    /** True when this button is registered as a split (dropdown) button. */
    static _IsSplitButton(hwnd) {
        return this.State.Has(hwnd) && this.State[hwnd].mode = "split"
    }

    /** True when client-x falls inside the dropdown-arrow region. */
    static _PointInArrow(hwnd, clientX) {
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right
        arrowW := DarkTheme.Scale(20, hwnd)
        return clientX >= w - arrowW && clientX < w
    }

    /** Shows the configured dropdown menu (or invokes the callback) anchored under the button.
     * Calls TrackPopupMenu directly so we can speak physical pixels end-to-end — GetWindowRect
     * returns physical, TrackPopupMenu takes physical. Avoids Menu.Show's DPI auto-scaling,
     * which silently mangles coordinates on high-DPI displays. The parent gui hwnd is the
     * owner so AHK's normal WM_COMMAND dispatch still fires the menu item callbacks. */
    static _ShowDropdown(hwnd) {
        s := this._State(hwnd)
        if s.onDropdown {
            s.onDropdown(s.btn)
            return
        }
        if !s.menu || !s.btn
            return
        rc := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)
        DllCall("TrackPopupMenu",
            "Ptr", s.menu.Handle,
            "UInt", 0,
            "Int", rc.left,
            "Int", rc.bottom,
            "Int", 0,
            "Ptr", s.btn.Gui.Hwnd,
            "Ptr", 0)
    }

    static PaintButton(hwnd) {
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")

        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right
        h := rc.bottom

        s := this._State(hwnd)
        mode := s.mode
        switch mode {
            case "icon":    this._PaintIcon(hwnd, hdc, w, h)
            case "split":   this._PaintSplit(hwnd, hdc, w, h)
            case "command": this._PaintCommand(hwnd, hdc, w, h)
            case "toggle":  this._PaintToggle(hwnd, hdc, w, h)
            case "flat":    this._PaintFlat(hwnd, hdc, w, h)
            default:        this._PaintBasic(hwnd, hdc, w, h)
        }

        ; Keyboard focus ring on top of whatever the mode drew.
        if s.focus
            this._PaintFocusRing(hdc, w, h, mode = "accent" ? 0xFFFFFF : DarkTheme.Colors["Accent"], hwnd)

        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
    }

    /** Draws a 1px rounded focus ring inset from the client edge (no fill).
     * GDI+ anti-aliased stroke (was gdi32 RoundRect). */
    static _PaintFocusRing(hdc, w, h, ringColor, hwnd := 0) {
        ; Halve radius to match gdi32 RoundRect's ellipse-diameter convention.
        DarkTheme.GdipRoundFill(hdc, 1, 1, w - 2, h - 2, this._Radius(hwnd) / 2, -1, ringColor, DarkTheme.Scale(1, hwnd) * 1.0)
    }

    /** Selects state-appropriate bg, text, and border colors for default/accent modes.
     * Win11-style: hover is a small lift, press is *darker* than rest (button "pushes in"). */
    static _StateColors(hwnd, mode) {
        ; A disabled button ignores hover/press and dims bg + text.
        if !DllCall("IsWindowEnabled", "Ptr", hwnd)
            return [DarkTheme.Colors["DisabledBg"], DarkTheme.Colors["DisabledText"], DarkTheme.Colors["ButtonBorder"]]
        s := this.State[hwnd]
        isHover := s.hover
        isPressed := s.pressed
        if mode = "accent" {
            bgColor := isPressed ? DarkTheme.Colors["AccentPressed"]
                     : (isHover ? DarkTheme.Colors["AccentHover"] : DarkTheme.Colors["Accent"])
            textColor := 0xFFFFFF
            borderColor := DarkTheme.Colors["AccentBorder"]
        } else {
            bgColor := isPressed ? DarkTheme.Colors["ButtonPressed"]
                     : (isHover ? DarkTheme.Colors["ButtonHover"] : DarkTheme.Colors["Controls"])
            textColor := DarkTheme.Colors["Font"]
            borderColor := DarkTheme.Colors["ButtonBorder"]
        }
        return [bgColor, textColor, borderColor]
    }

    /** Win11-feel button corner radius, scaled for the control's own monitor. */
    static _Radius(hwnd := 0) => DarkTheme.Scale(5, hwnd)

    /** Fills the entire client rect with the parent (window) color.
     * Uses the cached Background brush — never delete it. */
    static _FillParent(hdc, rc) {
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
    }

    /** Paints a rounded-rectangle fill with optional border color.
     * GDI+ anti-aliased corners (was gdi32 RoundRect). The caller fills the parent
     * bg first, so the antialiased edge blends correctly. */
    static _RoundFill(hdc, x1, y1, x2, y2, radius, bgColor, borderColor := -1, hwnd := 0) {
        ; gdi32 RoundRect's radius arg is the corner *ellipse diameter*; GdipRoundFill
        ; takes a true radius. Halve so corners match the native (pre-GDI+) size.
        DarkTheme.GdipRoundFill(hdc, x1, y1, x2 - x1, y2 - y1, radius / 2, bgColor, borderColor, DarkTheme.Scale(1, hwnd) * 1.0)
    }

    /** Selects the button's font into the dc and returns the previous font handle (0 if none). */
    static _SelectButtonFont(hwnd, hdc) {
        hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        return hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
    }

    /** Draws text using DrawText with a flag set; rect is a Buffer of DM_RECT. */
    static _DrawText(hdc, text, rect, color, flags) {
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(color), "Void")
        DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rect, "UInt", flags, "Void")
    }

    /** Draws an HICON via DrawIconEx at (x,y) sized sizePx. */
    static _DrawIcon(hdc, hicon, x, y, sizePx) {
        if !hicon
            return
        static DI_NORMAL := 0x3
        DllCall("DrawIconEx", "Ptr", hdc, "Int", x, "Int", y, "Ptr", hicon,
                "Int", sizePx, "Int", sizePx, "UInt", 0, "Ptr", 0, "UInt", DI_NORMAL, "Void")
    }

    /** Constructs a DM_RECT for use with DrawText. */
    static _MakeRect(left, top, right, bottom) {
        rc := DM_RECT()
        rc.left := left, rc.top := top, rc.right := right, rc.bottom := bottom
        return rc
    }

    /** Default + accent path: rounded fill with thin border, centered text. */
    static _PaintBasic(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        s := this.State[hwnd]
        colors := this._StateColors(hwnd, s.mode)
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius(hwnd), colors[1], colors[3], hwnd)
        oldFont := this._SelectButtonFont(hwnd, hdc)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        this._DrawText(hdc, s.text, rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
    }

    /** Icon + optional text. align="left"|"right"|"top"|"center". */
    static _PaintIcon(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        colors := this._StateColors(hwnd, "default")
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius(hwnd), colors[1], colors[3], hwnd)

        s := this.State[hwnd]
        btnText := s.text
        hicon := s.icon
        align := s.iconAlign
        iconSize := DarkTheme.Scale(16, hwnd)
        pad := DarkTheme.Scale(8, hwnd)

        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20, DT_LEFT := 0x0, DT_RIGHT := 0x2

        if !btnText {
            ; Icon-only — centered icon, no text
            if hicon {
                ix := (w - iconSize) // 2
                iy := (h - iconSize) // 2
                this._DrawIcon(hdc, hicon, ix, iy, iconSize)
            }
            return
        }

        oldFont := this._SelectButtonFont(hwnd, hdc)

        if align = "center" && hicon {
            ; Center align: icon centered, no text drawn (text-on-icon would clash)
            ix := (w - iconSize) // 2
            iy := (h - iconSize) // 2
            this._DrawIcon(hdc, hicon, ix, iy, iconSize)
        } else if align = "top" && hicon {
            ix := (w - iconSize) // 2
            iy := pad
            this._DrawIcon(hdc, hicon, ix, iy, iconSize)
            textRc := this._MakeRect(0, iy + iconSize + 2, w, h)
            this._DrawText(hdc, btnText, textRc, colors[2], DT_CENTER | DT_SINGLELINE)
        } else if align = "right" && hicon {
            ix := w - iconSize - pad
            iy := (h - iconSize) // 2
            this._DrawIcon(hdc, hicon, ix, iy, iconSize)
            textRc := this._MakeRect(pad, 0, ix - 2, h)
            this._DrawText(hdc, btnText, textRc, colors[2], DT_LEFT | DT_VCENTER | DT_SINGLELINE)
        } else if hicon {
            ; "left" (default)
            ix := pad
            iy := (h - iconSize) // 2
            this._DrawIcon(hdc, hicon, ix, iy, iconSize)
            textRc := this._MakeRect(ix + iconSize + 4, 0, w - pad, h)
            this._DrawText(hdc, btnText, textRc, colors[2], DT_LEFT | DT_VCENTER | DT_SINGLELINE)
        } else {
            ; No icon — fall back to centered text
            this._DrawText(hdc, btnText, rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        }

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
    }

    /** Split button: main text region + dropdown-arrow region with divider. */
    static _PaintSplit(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        baseColors := this._StateColors(hwnd, "default")
        this._FillParent(hdc, rc)

        arrowW := DarkTheme.Scale(20, hwnd)
        s := this.State[hwnd]
        hoverArrow := s.hoverArrow
        isHover := s.hover
        isPressed := s.pressed

        ; Win11-feel: hover lifts subtly, press goes darker than rest
        mainHover := isHover && !hoverArrow
        mainBg := isPressed && !hoverArrow ? DarkTheme.Colors["ButtonPressed"]
                : (mainHover ? DarkTheme.Colors["ButtonHover"] : DarkTheme.Colors["Controls"])
        arrowHover := isHover && hoverArrow
        arrowBg := isPressed && hoverArrow ? DarkTheme.Colors["ButtonPressed"]
                 : (arrowHover ? DarkTheme.Colors["ButtonHover"] : DarkTheme.Colors["Controls"])

        ; Single rounded backdrop with thin border, then overlay arrow region
        radius := this._Radius(hwnd)
        this._RoundFill(hdc, 0, 0, w, h, radius, mainBg, baseColors[3], hwnd)
        if arrowBg != mainBg {
            ; Overlay arrow region using a clipping intersection of the rounded rect
            arrowRc := this._MakeRect(w - arrowW, 0, w, h)
            saved := DllCall("SaveDC", "Ptr", hdc, "Int")
            rgn := DllCall("CreateRoundRectRgn", "Int", 1, "Int", 1, "Int", w, "Int", h,
                           "Int", radius - 1, "Int", radius - 1, "Ptr")
            DllCall("SelectClipRgn", "Ptr", hdc, "Ptr", rgn, "Void")
            DllCall("FillRect", "Ptr", hdc, "Ptr", arrowRc, "Ptr", DarkTheme.GetSolidBrush(arrowBg), "Void")
            DllCall("RestoreDC", "Ptr", hdc, "Int", saved, "Void")
            DllCall("DeleteObject", "Ptr", rgn, "Void")
        }

        ; Vertical divider line between regions
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetPen(DarkTheme.Colors["Border"]), "Ptr")
        divX := w - arrowW
        DllCall("MoveToEx", "Ptr", hdc, "Int", divX, "Int", DarkTheme.Scale(4, hwnd), "Ptr", 0, "Void")
        DllCall("LineTo", "Ptr", hdc, "Int", divX, "Int", h - DarkTheme.Scale(4, hwnd), "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")

        ; Main text (left region)
        oldFont := this._SelectButtonFont(hwnd, hdc)
        textRc := this._MakeRect(0, 0, w - arrowW, h)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        this._DrawText(hdc, s.text, textRc, baseColors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")

        ; Down-arrow triangle in arrow region
        this._PaintDownArrow(hdc, w - arrowW + arrowW // 2, h // 2, DarkTheme.Scale(4, hwnd), baseColors[2])
    }

    /** Filled triangle pointing down, centered at (cx, cy), with half-width radius. */
    static _PaintDownArrow(hdc, cx, cy, radius, color) {
        tri := DM_TRIANGLE()
        tri.p[1].x := cx - radius, tri.p[1].y := cy - radius // 2
        tri.p[2].x := cx + radius, tri.p[2].y := cy - radius // 2
        tri.p[3].x := cx,          tri.p[3].y := cy + radius
        brush := DarkTheme.GetSolidBrush(color)
        pen := DarkTheme.GetPen(color)
        oldB := DllCall("SelectObject", "Ptr", hdc, "Ptr", brush, "Ptr")
        oldP := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        DllCall("Polygon", "Ptr", hdc, "Ptr", tri.Ptr, "Int", 3, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldB, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldP, "Void")
    }

    /** Right-pointing chevron used as the default command-link icon. */
    static _PaintRightArrow(hdc, cx, cy, radius, color) {
        tri := DM_TRIANGLE()
        tri.p[1].x := cx - radius // 2, tri.p[1].y := cy - radius
        tri.p[2].x := cx - radius // 2, tri.p[2].y := cy + radius
        tri.p[3].x := cx + radius,      tri.p[3].y := cy
        brush := DarkTheme.GetSolidBrush(color)
        pen := DarkTheme.GetPen(color)
        oldB := DllCall("SelectObject", "Ptr", hdc, "Ptr", brush, "Ptr")
        oldP := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        DllCall("Polygon", "Ptr", hdc, "Ptr", tri.Ptr, "Int", 3, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldB, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldP, "Void")
    }

    /** Vista-style command link: title + description + optional left icon (default chevron). */
    static _PaintCommand(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        colors := this._StateColors(hwnd, "default")
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius(hwnd), colors[1], colors[3], hwnd)

        pad := DarkTheme.Scale(12, hwnd)
        iconSize := DarkTheme.Scale(20, hwnd)
        s := this.State[hwnd]
        hicon := s.icon

        iconAreaX := pad
        iconAreaY := pad
        if hicon {
            this._DrawIcon(hdc, hicon, iconAreaX, iconAreaY, iconSize)
        } else {
            this._PaintRightArrow(hdc, iconAreaX + iconSize // 2, iconAreaY + iconSize // 2,
                                  DarkTheme.Scale(7, hwnd), DarkTheme.Colors["Accent"])
        }

        textLeft := iconAreaX + iconSize + pad
        oldFont := this._SelectButtonFont(hwnd, hdc)

        cmdTitle := s.text
        desc := s.desc

        static DT_LEFT := 0x0, DT_TOP := 0x0, DT_SINGLELINE := 0x20, DT_WORDBREAK := 0x10, DT_END_ELLIPSIS := 0x8000
        titleRc := this._MakeRect(textLeft, pad, w - pad, pad + DarkTheme.Scale(22, hwnd))
        this._DrawText(hdc, cmdTitle, titleRc, colors[2], DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS)

        descRc := this._MakeRect(textLeft, pad + DarkTheme.Scale(22, hwnd) + 2, w - pad, h - pad)
        this._DrawText(hdc, desc, descRc, DarkTheme.Colors["FontDim"], DT_LEFT | DT_TOP | DT_WORDBREAK)

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
    }

    /** Sticky toggle button — on-state mimics an Accent button so the active state really pops.
     * Off-state matches the default-mode button so toggles look at home next to regular buttons. */
    static _PaintToggle(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        s := this.State[hwnd]
        colors := this._StateColors(hwnd, s.toggle ? "accent" : "default")
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius(hwnd), colors[1], colors[3], hwnd)
        oldFont := this._SelectButtonFont(hwnd, hdc)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        this._DrawText(hdc, s.text, rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
    }

    /** Borderless flat button — no fill at idle, hover/press only. */
    static _PaintFlat(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        s := this.State[hwnd]
        isEnabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        isHover := isEnabled && s.hover
        isPressed := isEnabled && s.pressed

        this._FillParent(hdc, rc)
        if isPressed
            this._RoundFill(hdc, 0, 0, w, h, this._Radius(hwnd), DarkTheme.Colors["FlatPressed"], -1, hwnd)
        else if isHover
            this._RoundFill(hdc, 0, 0, w, h, this._Radius(hwnd), DarkTheme.Colors["ButtonHover"], -1, hwnd)

        oldFont := this._SelectButtonFont(hwnd, hdc)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        textColor := isEnabled ? DarkTheme.Colors["Font"] : DarkTheme.Colors["DisabledText"]
        this._DrawText(hdc, s.text, rc, textColor, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
    }
}

/**
 * Owner-draw ComboBox with custom-drawn main control and styled dropdown.
 * Handles WM_PAINT for stable text rendering and rounded corners.
 */
class _DarkComboBox extends Gui.ComboBox {
    static __New() {
        super.Prototype.SetDarkMode := ObjBindMethod(this, "ApplyDarkMode")
    }


    /**
     * Applies dark theme with owner-draw rendering.
     * @param {Gui.ComboBox} combo - ComboBox control instance
     */
    static ApplyDarkMode(combo) {
        ; Use DarkMode_CFD for dropdown appearance
        DllCall("uxtheme\SetWindowTheme", "Ptr", combo.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)
        combo.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))

        DarkTheme.RemoveBorder(combo.Hwnd)

        ; Get and style the dropdown list (ListBox part of ComboBox)
        static CB_GETCOMBOBOXINFO := 0x0164
        cbi := DM_COMBOBOXINFO()
        cbi.cbSize := cbi.Size
        if DllCall("SendMessage", "Ptr", combo.Hwnd, "UInt", CB_GETCOMBOBOXINFO, "Ptr", 0, "Ptr", cbi.Ptr) {
            listHwnd := cbi.hwndList
            if listHwnd {
                ; Apply dark theme to dropdown list for modern scrollbar
                DllCall("uxtheme\SetWindowTheme", "Ptr", listHwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                ; Register this as a ComboBox dropdown so WM_CTLCOLORLISTBOX uses Background color
                DarkWindowProc.ComboDropdowns[listHwnd] := true
            }
        }

        ; Subclass to handle WM_NCPAINT for custom border and focus indicator
        this.SubclassCombo(combo.Hwnd)
    }

    static SubclassCombo(hwnd) {
        Subclass.Install(this, hwnd, ObjBindMethod(this, "ComboProc", hwnd))
    }

    /**
     * Removes subclass and frees resources for a ComboBox.
     * @param {Ptr} hwnd - ComboBox window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
    }

    static ComboProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        static WM_SETFOCUS := 0x0007, WM_KILLFOCUS := 0x0008, WM_COMMAND := 0x0111
        static EN_SETFOCUS := 0x0100, EN_KILLFOCUS := 0x0200

        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)

        ; Repaint on focus change so the Accent border tracks it. An editable
        ; ComboBox never gets WM_SETFOCUS itself — focus lands on its internal
        ; edit child, whose EN_SETFOCUS/EN_KILLFOCUS arrive here as WM_COMMAND
        ; because the ComboBox is that edit's parent.
        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
        else if msg = WM_COMMAND {
            notify := (wParam >> 16) & 0xFFFF
            if notify = EN_SETFOCUS || notify = EN_KILLFOCUS
                DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
        }

        ; Completely take over WM_PAINT - don't call original proc to prevent text jumping
        if msg = WM_PAINT {
            this.DrawComboBox(hwnd)
            return 0
        }

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static DrawComboBox(hwnd) {
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")
        if !hdc {
            ; Must still pair BeginPaint with EndPaint or the update region is
            ; never validated and WM_PAINT fires in a tight loop.
            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
            return
        }

        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right
        h := rc.bottom

        fontColor := DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"])

        ; Cached palette brushes — do not delete them
        bgBrush := DarkTheme.GetBrush("Background")
        ctrlBrush := DarkTheme.GetBrush("Controls")

        ; Step 1: Fill entire control with parent bg color (covers all exterior artifacts)
        fillRect := DM_RECT()
        fillRect.left := 0, fillRect.top := 0, fillRect.right := w, fillRect.bottom := h
        DllCall("FillRect", "Ptr", hdc, "Ptr", fillRect, "Ptr", bgBrush, "Void")

        ; Step 2: Fill interior with control color, outlined like the other dark
        ; fields — Accent while focused, Border otherwise (this used to draw with
        ; NULL_PEN, so a focused ComboBox looked identical to an idle one).
        focus := DllCall("GetFocus", "Ptr")
        focused := focus = hwnd || DllCall("IsChild", "Ptr", hwnd, "Ptr", focus)
        borderPen := DarkTheme.GetPen(focused ? DarkTheme.Colors["Accent"] : DarkTheme.Colors["Border"])
        hOldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", ctrlBrush, "Ptr")
        hOldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", borderPen, "Ptr")
        comboRadius := DarkTheme.Scale(6, hwnd)
        DllCall("RoundRect", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", comboRadius, "Int", comboRadius, "Void")

        ; Step 3: Draw dropdown chevron (shared glyph; manages its own cached pen)
        DarkTheme.PaintChevron(hdc, w - DarkTheme.Scale(12, hwnd), h // 2,
            DarkTheme.Scale(4, hwnd), DarkTheme.Scale(3, hwnd), DarkTheme.Colors["Font"])

        ; Step 5: Draw text
        static WM_GETTEXT := 0x000D
        static WM_GETTEXTLENGTH := 0x000E
        static WM_GETFONT := 0x0031
        textLen := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETTEXTLENGTH, "Ptr", 0, "Ptr", 0, "Int")
        if textLen > 0 {
            textBuf := Buffer((textLen + 1) * 2, 0)
            DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETTEXT, "Ptr", textLen + 1, "Ptr", textBuf)

            DllCall("SetTextColor", "Ptr", hdc, "UInt", fontColor, "Void")
            DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")  ; TRANSPARENT

            hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
            hOldFont := 0
            if hFont
                hOldFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")

            rcText := DM_RECT()
            rcText.left := DarkTheme.Scale(6), rcText.top := 0, rcText.right := w - DarkTheme.Scale(24), rcText.bottom := h
            static DT_SINGLELINE := 0x20, DT_VCENTER := 0x4, DT_NOPREFIX := 0x800
            DllCall("DrawTextW", "Ptr", hdc, "Ptr", textBuf, "Int", -1, "Ptr", rcText, "UInt", DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX, "Void")

            if hOldFont
                DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldFont, "Void")
        }

        ; Cleanup (bgBrush/ctrlBrush/arrowPen are cached — restore, don't delete)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldPen, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldBrush, "Void")
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
    }
}

/**
 * Custom-drawn Slider with GDI+ anti-aliased thumb. Features circular knob
 * with blue accent border, double-buffered rendering to prevent artifacts.
 */
class _DarkSlider extends Gui.Slider {
    /** @type {Map} Per-slider state data */
    static SliderData := Map()
    /** @type {Integer} GDI+ startup token (initialized once) */
    static GdipToken := 0

    static __New() {
        super.Prototype.SetDarkMode := ObjBindMethod(this, "ApplyDarkMode")
        ; Initialize GDI+ once for anti-aliased thumb drawing
        si := DM_GpInput()
        si.GdiplusVersion := 1
        token := 0
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si.Ptr, "Ptr", 0)
        this.GdipToken := token
    }

    /**
     * Applies custom owner-draw dark mode to slider.
     * @param {Gui.Slider} slider - Slider control instance
     */
    static ApplyDarkMode(slider) {
        ; Set empty theme to disable themed drawing
        DllCall("uxtheme\SetWindowTheme", "Ptr", slider.Hwnd, "WStr", "", "WStr", "")

        ; Store slider data
        this.SliderData[slider.Hwnd] := Map("state", "normal")

        ; Subclass for custom drawing
        this.SubclassSlider(slider.Hwnd)

        DllCall("InvalidateRect", "Ptr", slider.Hwnd, "Ptr", 0, "Int", true, "Void")
    }

    static SubclassSlider(hwnd) {
        Subclass.Install(this, hwnd, ObjBindMethod(this, "SliderProc", hwnd))
    }

    /**
     * Removes subclass and frees resources for a Slider.
     * @param {Ptr} hwnd - Slider window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        this.SliderData.Delete(hwnd)
    }

    /**
     * Releases our GDI+ token reference. Intentionally does NOT call
     * GdiplusShutdown: AHK shares gdiplus.dll for its own image handling and
     * keeps GDI+ initialized for the process lifetime. Calling GdiplusShutdown
     * here faults during process teardown (abnormal exit code) and — because
     * this also runs from {@link DarkTheme.Release} when the last DarkGui is
     * destroyed — would tear GDI+ out from under AHK mid-run. The OS reclaims
     * GDI+ on exit, so dropping the token is all that's needed.
     */
    static Shutdown() {
        this.GdipToken := 0
    }

    static SliderProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        static WM_ERASEBKGND := 0x0014
        static WM_LBUTTONDOWN := 0x0201
        static WM_MOUSEMOVE := 0x0200
        static WM_LBUTTONUP := 0x0202
        static TBM_GETCHANNELRECT := 0x41A
        static TBM_GETTHUMBRECT := 0x0419
        static TBM_GETPOS := 0x0400
        static TBM_GETRANGEMIN := 0x0401
        static TBM_GETRANGEMAX := 0x0402

        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)

        ; Force full invalidation on mouse events that move the thumb
        if msg = WM_LBUTTONDOWN || msg = WM_MOUSEMOVE || msg = WM_LBUTTONUP {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            ; Invalidate entire control to repaint cleanly
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", true, "Void")
            return result
        }

        if msg = WM_ERASEBKGND {
            ; Fill background with the cached Background brush (do not delete it)
            rc := DM_RECT()
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
            DllCall("FillRect", "Ptr", wParam, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
            return 1
        }

        if msg = WM_PAINT {
            ps := DM_PAINTSTRUCT()
            hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")

            ; Get client rect
            rcClient := DM_RECT()
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rcClient)
            clientW := rcClient.right
            clientH := rcClient.bottom

            ; Use double buffering to prevent artifacts
            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
            hBitmap := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", clientW, "Int", clientH, "Ptr")
            hOldBitmap := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")

            ; Fill background (draw to memory DC) with cached brushes — do not delete them
            DllCall("FillRect", "Ptr", hdcMem, "Ptr", rcClient, "Ptr", DarkTheme.GetBrush("Background"), "Void")

            ; Get channel rect (use actual Windows position)
            rcChannel := DM_RECT()
            SendMessage(TBM_GETCHANNELRECT, 0, rcChannel.Ptr, hwnd)

            ; Draw track/channel using actual rect from Windows
            DllCall("FillRect", "Ptr", hdcMem, "Ptr", rcChannel, "Ptr", DarkTheme.GetBrush("Controls"), "Void")

            ; Get thumb rect
            rcThumb := DM_RECT()
            SendMessage(TBM_GETTHUMBRECT, 0, rcThumb.Ptr, hwnd)
            thumbLeft := rcThumb.left
            thumbTop := rcThumb.top
            thumbRight := rcThumb.right
            thumbBottom := rcThumb.bottom

            ; Calculate perfect circle (use smaller dimension as diameter + extra size)
            thumbW := thumbRight - thumbLeft
            thumbH := thumbBottom - thumbTop
            diameter := Min(thumbW, thumbH) + DarkTheme.Scale(6)  ; Make knob larger

            ; Center the circle and move up 2px
            centerX := thumbLeft + (thumbW // 2)
            centerY := thumbTop + (thumbH // 2) - DarkTheme.Scale(2)  ; Move up
            circleLeft := centerX - (diameter // 2)
            circleTop := centerY - (diameter // 2)
            circleRight := circleLeft + diameter
            circleBottom := circleTop + diameter

            ; Palette-driven thumb. GDI+ takes ARGB directly, so no BGR swap —
            ; OR in a full alpha byte. Previously hardcoded white/blue, which
            ; survived SetColor and ApplyPreset("Light") unchanged.
            fillColor := 0xFF000000 | DarkTheme.Colors["SliderThumb"]
            borderColor := 0xFF000000 | DarkTheme.Colors["Accent"]
            borderWidth := DarkTheme.Scale(4) * 1.0

            ; Create Graphics from DC (GDI+ already initialized in __New)
            pGraphics := 0
            DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdcMem, "Ptr*", &pGraphics)

            ; Enable anti-aliasing (SmoothingModeAntiAlias = 4)
            DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)

            ; Create solid brush for fill
            pBrush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", fillColor, "Ptr*", &pBrush)

            ; Create pen for border
            pPen := 0
            DllCall("gdiplus\GdipCreatePen1", "UInt", borderColor, "Float", borderWidth, "Int", 2, "Ptr*", &pPen)

            ; Draw filled ellipse then border (adjust for pen width)
            halfPen := borderWidth / 2
            DllCall("gdiplus\GdipFillEllipse", "Ptr", pGraphics, "Ptr", pBrush,
                "Float", circleLeft + halfPen, "Float", circleTop + halfPen,
                "Float", diameter - borderWidth, "Float", diameter - borderWidth)
            DllCall("gdiplus\GdipDrawEllipse", "Ptr", pGraphics, "Ptr", pPen,
                "Float", circleLeft + halfPen, "Float", circleTop + halfPen,
                "Float", diameter - borderWidth, "Float", diameter - borderWidth)

            ; Cleanup GDI+ objects (but not the token)
            DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)

            ; Blit from memory DC to screen DC
            DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", clientW, "Int", clientH, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020, "Void")  ; SRCCOPY

            ; Clean up memory DC
            DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hOldBitmap, "Void")
            DllCall("DeleteObject", "Ptr", hBitmap, "Void")
            DllCall("DeleteDC", "Ptr", hdcMem, "Void")

            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
            return 0
        }

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }
}

/**
 * Dark-themed Progress bar with {@link DarkTheme} accent color fill.
 * Strips the default Windows theme and applies custom background/bar colors.
 */
class _DarkProgress extends Gui.Progress {
    static __New() {
        super.Prototype.SetDarkMode := ObjBindMethod(this, "ApplyDarkMode")
    }

    /**
     * Applies dark theme colors to the progress bar.
     *
     * @param {Gui.Progress} prog - Progress bar control instance.
     */
    static ApplyDarkMode(prog) {
        static PBM_SETBKCOLOR := 0x2001
        DllCall("uxtheme\SetWindowTheme", "Ptr", prog.Hwnd, "Str", "", "Ptr", 0)
        SendMessage(PBM_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), prog)
        prog.Opt("c" Format("{:X}", DarkTheme.Colors["Accent"]))
    }
}

/**
 * Dark-themed ListBox with `DarkMode_Explorer` theme for modern scrollbar
 * appearance. Removes borders and applies {@link DarkTheme} font color.
 */
class _DarkListBox extends Gui.ListBox {
    static __New() {
        super.Prototype.SetDarkMode := ObjBindMethod(this, "ApplyDarkMode")
    }

    /**
     * Applies dark theme to the ListBox.
     *
     * @param {Gui.ListBox} lb - ListBox control instance.
     */
    static ApplyDarkMode(lb) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", lb.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        lb.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
        DarkTheme.RemoveBorder(lb.Hwnd)
    }
}

/**
 * Applies native Windows dark mode to CheckBox controls.
 * Uses AllowDarkModeForWindow (uxtheme ordinal 133) + SetWindowTheme("Explorer")
 * to get the native dark checkbox indicators rendered by Windows itself.
 */
class _DarkCheckBox {
    static ApplyDarkMode(chk) {
        DarkTheme.AllowDarkMode(chk.Hwnd)
        DllCall("uxtheme\SetWindowTheme", "Ptr", chk.Hwnd, "Str", "Explorer", "Ptr", 0)
        chk.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
    }
}

/**
 * Dark state-image checkboxes for TreeView controls created with `+Checked`
 * (TVS_CHECKBOXES). The control's auto-created state ImageList is recolored
 * IN PLACE via ImageList_Replace with theme-engine glyphs on the dark
 * Controls fill. Installing a replacement list (the old approach) makes
 * comctl32 flag state images as app-managed and it stops toggling checkboxes
 * on state-icon clicks and Space — repainting the list the control owns keeps
 * the native toggle behavior. Idempotent: safe to re-call after a palette
 * swap. Glyphs come from {@link _DarkListView.RenderCheckboxGlyph}.
 */
class _DarkTreeCheckboxes {
    static Apply(tv) {
        static TVM_GETIMAGELIST := 0x1108
        static TVSIL_STATE := 2
        static TVS_CHECKBOXES := 0x100
        static GWL_STYLE := -16
        static BP_CHECKBOX := 3
        static CBS_UNCHECKEDNORMAL := 1
        static CBS_CHECKEDNORMAL := 5

        hIml := SendMessage(TVM_GETIMAGELIST, TVSIL_STATE, 0, tv)
        if !hIml {
            ; State list not materialized yet: pulse TVS_CHECKBOXES off/on — the
            ; off->on transition makes comctl32 build its own list. Safe here
            ; because Apply runs right after Add, before any items exist.
            style := DllCall("GetWindowLongPtr", "Ptr", tv.Hwnd, "Int", GWL_STYLE, "Ptr")
            DllCall("SetWindowLongPtr", "Ptr", tv.Hwnd, "Int", GWL_STYLE, "Ptr", style & ~TVS_CHECKBOXES, "Ptr")
            DllCall("SetWindowLongPtr", "Ptr", tv.Hwnd, "Int", GWL_STYLE, "Ptr", style | TVS_CHECKBOXES, "Ptr")
            hIml := SendMessage(TVM_GETIMAGELIST, TVSIL_STATE, 0, tv)
            if !hIml
                return
        }
        ; TreeView state indices map DIRECTLY into the state list — image[0] is
        ; the blank "no state image" placeholder, image[1] unchecked, image[2]
        ; checked (verified by pixel probe; comctl32's auto list has 3 images).
        ; ListView differs: its state N draws image N-1, hence its 2-image list.
        count := DllCall("comctl32\ImageList_GetImageCount", "Ptr", hIml, "Int")
        if count < 2
            return
        base := count >= 3 ? 1 : 0
        cx := 0, cy := 0
        if !DllCall("comctl32\ImageList_GetIconSize", "Ptr", hIml, "Int*", &cx, "Int*", &cy, "Int")
            return

        hTheme := DllCall("uxtheme\OpenThemeData", "Ptr", tv.Hwnd, "Str", "BUTTON", "Ptr")
        if !hTheme
            return
        ; Glyph at theme size, clamped to the existing list's cell geometry
        sz := DM_SIZE()
        DllCall("uxtheme\GetThemePartSize", "Ptr", hTheme, "Ptr", 0,
            "Int", BP_CHECKBOX, "Int", CBS_CHECKEDNORMAL, "Ptr", 0, "Int", 1, "Ptr", sz.Ptr)
        glyphW := Min(sz.cx, cx)
        glyphH := Min(sz.cy, cy)

        states := [CBS_UNCHECKEDNORMAL, CBS_CHECKEDNORMAL]
        for i, stateVal in states {
            hBmp := _DarkListView.RenderCheckboxGlyph(hTheme, stateVal, cx, cy, glyphW, glyphH, DarkTheme.Colors["Controls"])
            DllCall("comctl32\ImageList_Replace", "Ptr", hIml, "Int", base + i - 1, "Ptr", hBmp, "Ptr", 0, "Int")
            DllCall("DeleteObject", "Ptr", hBmp, "Void")
        }
        DllCall("uxtheme\CloseThemeData", "Ptr", hTheme)
        DllCall("InvalidateRect", "Ptr", tv.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }
}

/**
 * Wider (2px) caret for dark Edit controls. The default 1px caret nearly
 * vanishes against the dark Controls fill; recreating it on every WM_SETFOCUS
 * at 2px x line-height keeps it visible. The system still renders it by
 * inversion, so no color management is needed.
 */
class _DarkCaret {

    static Apply(hwnd) {
        Subclass.Install(this, hwnd, ObjBindMethod(this, "Proc", hwnd))
    }

    static Remove(hwnd) => Subclass.Uninstall(this, hwnd)

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_SETFOCUS := 0x0007
        result := Subclass.Forward(hwnd, msg, wParam, lParam)
        if msg = WM_SETFOCUS {
            ; Replace the caret the edit just created with a wider one.
            DllCall("CreateCaret", "Ptr", targetHwnd, "Ptr", 0, "Int", 2, "Int", this._LineHeight(targetHwnd))
            DllCall("ShowCaret", "Ptr", targetHwnd, "Void")
        }
        return result
    }

    static _LineHeight(hwnd) {
        static WM_GETFONT := 0x0031
        hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
        old := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        tm := DM_TEXTMETRICW()
        DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", tm.Ptr)
        if old
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old, "Void")
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
        return tm.tmHeight
    }
}

/**
 * Dark-themed MonthCal (SysMonthCal32) date picker.
 *
 * The visual-styled MonthCal ignores `MCM_SETCOLOR` and always renders with the
 * light system theme. Stripping the theme (`SetWindowTheme(hwnd, "", "")`) forces
 * classic rendering, which DOES honor `MCM_SETCOLOR` — so the background, day
 * text, title bar, and trailing (adjacent-month) days all go dark. Classic
 * rendering draws light 3D prev/next nav buttons, so a `WM_PAINT` subclass
 * overpaints those two buttons dark with a flat chevron.
 */
class _DarkMonthCal {

    static ApplyDarkMode(mc) => this.ApplyToHwnd(mc.Hwnd)

    /**
     * Hwnd-based variant so non-Gui calendars can be themed too — e.g. the
     * MonthCal that drops down from a DateTime picker ({@link _DarkDateTime}).
     * @param {Ptr} hwnd - SysMonthCal32 window handle
     */
    static ApplyToHwnd(hwnd) {
        static MCM_SETCOLOR := 0x100A
        static MCSC_BACKGROUND := 0, MCSC_TEXT := 1, MCSC_TITLEBK := 2
        static MCSC_TITLETEXT := 3, MCSC_MONTHBK := 4, MCSC_TRAILINGTEXT := 5
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "", "Str", "")
        SendMessage(MCM_SETCOLOR, MCSC_BACKGROUND,   DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]), hwnd)
        SendMessage(MCM_SETCOLOR, MCSC_MONTHBK,      DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]), hwnd)
        SendMessage(MCM_SETCOLOR, MCSC_TEXT,         DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), hwnd)
        SendMessage(MCM_SETCOLOR, MCSC_TITLEBK,      DarkTheme.RGBtoBGR(DarkTheme.Colors["Header"]), hwnd)
        SendMessage(MCM_SETCOLOR, MCSC_TITLETEXT,    DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), hwnd)
        SendMessage(MCM_SETCOLOR, MCSC_TRAILINGTEXT, DarkTheme.RGBtoBGR(DarkTheme.Colors["CalendarTrailing"]), hwnd)
        this.EnsureMinSize(hwnd)
        Subclass.Install(this, hwnd, ObjBindMethod(this, "Proc", hwnd))
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /**
     * Grows the calendar to its post-theme-strip minimum size. The control was
     * sized with *themed* metrics; classic rendering needs slightly more room,
     * otherwise the bottom row (the blue today-legend box) is clipped. Grow
     * only — never shrink a user-specified layout.
     * @param {Ptr} hwnd - SysMonthCal32 window handle
     */
    static EnsureMinSize(hwnd) {
        static MCM_GETMINREQRECT := 0x1009
        static MCM_GETMAXTODAYWIDTH := 0x1015
        static SWP_NOMOVE := 0x2, SWP_NOZORDER := 0x4, SWP_NOACTIVATE := 0x10
        rcMin := DM_RECT()
        if !DllCall("SendMessage", "Ptr", hwnd, "UInt", MCM_GETMINREQRECT, "Ptr", 0, "Ptr", rcMin.Ptr)
            return
        todayW := DllCall("SendMessage", "Ptr", hwnd, "UInt", MCM_GETMAXTODAYWIDTH, "Ptr", 0, "Ptr", 0, "Int")
        rcWin := DM_RECT()
        rcCli := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rcCli)
        curW := rcWin.right - rcWin.left
        curH := rcWin.bottom - rcWin.top
        ; min-req is a client size; add the window frame.
        needW := Max(rcMin.right, todayW) + (curW - rcCli.right)
        needH := rcMin.bottom + (curH - rcCli.bottom)
        if curW >= needW && curH >= needH
            return
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0,
            "Int", Max(curW, needW), "Int", Max(curH, needH),
            "UInt", SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE, "Void")
    }

    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
    }

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        if msg = WM_PAINT {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._PaintNavButtons(targetHwnd)
            this._PaintWeekdays(targetHwnd)
            this._PaintTodayRow(targetHwnd)
            return ret
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /**
     * Repaints the today-legend row: erases the native rendering (which draws a
     * redundant marker-sample box left of the text) and redraws just the
     * "Today: <date>" string, bold and centered in the row. The MCHT_TODAYLINK
     * hit area is unchanged, so clicking the row still jumps to today.
     */
    static _PaintTodayRow(hwnd) {
        static MCHT_TODAYLINK := 0x30000
        static WM_GETFONT := 0x0031
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20, DT_NOPREFIX := 0x800

        rcClient := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rcClient)
        cw := rcClient.right
        ch := rcClient.bottom

        ; The today link sits on the bottom row; probe a few offsets up from it.
        rcT := 0
        for dy in [6, 10, 14] {
            ht := this._HitTest(hwnd, cw // 2, ch - dy)
            if ht.uHit = MCHT_TODAYLINK {
                rcT := [ht.rc.left, ht.rc.top, ht.rc.right, ht.rc.bottom]
                break
            }
        }
        if !rcT
            return

        hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        row := DM_RECT()
        ; Cover the full control width — the hit rect excludes the swatch margin.
        row.left := rcClient.left, row.top := rcT[2]
        row.right := rcClient.right, row.bottom := rcT[4]
        DllCall("FillRect", "Ptr", hdc, "Ptr", row, "Ptr", DarkTheme.GetBrush("Background"), "Void")

        hBase := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
        hBold := hBase ? this._BoldFont(hBase) : 0
        oldFont := hBold ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hBold, "Ptr") : 0
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
        text := "Today: " FormatTime(, "ShortDate")
        DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", row,
            "UInt", DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX, "Void")
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }

    /** @type {Map} base HFONT -> derived bold HFONT (process-lifetime cache) */
    static _BoldFonts := Map()

    /** Returns a bold variant of the given font, created once and cached. */
    static _BoldFont(hBase) {
        if this._BoldFonts.Has(hBase)
            return this._BoldFonts[hBase]
        lf := Buffer(92, 0)  ; LOGFONTW
        if !DllCall("GetObjectW", "Ptr", hBase, "Int", 92, "Ptr", lf)
            return 0
        NumPut("Int", 700, lf, 16)  ; lfWeight = FW_BOLD
        return this._BoldFonts[hBase] := DllCall("CreateFontIndirectW", "Ptr", lf, "Ptr")
    }

    /**
     * Overpaints the day-of-week header row. Classic MonthCal draws the weekday
     * abbreviations in the *title background* color — with a dark Header that
     * makes them nearly unreadable. MCM_HITTEST reports the weekday header as
     * ONE full-row rect, so the seven column rects are taken from the first
     * date row instead (those hits are per-cell). Each name is redrawn in
     * FontDim; mod-7 indexing keeps locale first-day and multi-month right.
     */
    static _PaintWeekdays(hwnd) {
        static MCM_GETFIRSTDAYOFWEEK := 0x1010
        static MCHT_CALENDARDAY := 0x20002
        static MCHT_CALENDARDATE := 0x20001   ; PREV/NEXT variants add high flags
        static WM_GETFONT := 0x0031
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20, DT_NOPREFIX := 0x800

        rcClient := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rcClient)
        cw := rcClient.right
        ch := rcClient.bottom

        ; Find the weekday band by scanning down the middle column.
        bandTop := -1, bandBottom := -1
        y := 0
        while y < ch {
            ht := this._HitTest(hwnd, cw // 2, y)
            if ht.uHit = MCHT_CALENDARDAY {
                bandTop := ht.rc.top
                bandBottom := ht.rc.bottom
                break
            }
            y += 3
        }
        if bandTop < 0
            return

        ; First date row below the band: row top (clamps the erase so date-cell
        ; selection/focus boxes are never touched) and the per-column rects.
        dateTop := -1, dateMidY := -1
        y := bandBottom
        while y < ch {
            ht := this._HitTest(hwnd, cw // 2, y)
            if (ht.uHit & 0xFFFFFF) = MCHT_CALENDARDATE {
                dateTop := ht.rc.top
                dateMidY := (ht.rc.top + ht.rc.bottom) // 2
                break
            }
            y += 2
        }
        if dateTop < 0
            return
        ; Names center within the hit-test band; the erase extends to dateTop so
        ; the native divider (drawn in the light text color in the gap between
        ; band and dates) is repainted too. FillRect bottoms are exclusive, so
        ; nothing at y >= dateTop (selection/focus boxes) is touched.
        nameBottom := Min(bandBottom, dateTop)
        fillBottom := dateTop

        cells := Map()   ; left -> right, from the date row's cell rects
        x := 2
        while x < cw {
            ht := this._HitTest(hwnd, x, dateMidY)
            if (ht.uHit & 0xFFFFFF) = MCHT_CALENDARDATE && !cells.Has(ht.rc.left)
                cells[ht.rc.left] := ht.rc.right
            x += 4
        }
        if !cells.Count
            return

        ; Sort column lefts ascending (insertion sort; at most 14 entries).
        lefts := []
        for l in cells
            lefts.Push(l)
        i := 2
        while i <= lefts.Length {
            v := lefts[i]
            j := i - 1
            while j >= 1 && lefts[j] > v {
                lefts[j + 1] := lefts[j]
                j--
            }
            lefts[j + 1] := v
            i++
        }

        names := this._DayNames()
        firstDay := SendMessage(MCM_GETFIRSTDAYOFWEEK, 0, 0, hwnd) & 0xFFFF  ; 0=Mon .. 6=Sun

        hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["FontDim"]), "Void")

        ; Erase the band plus the gap below it (covers the native light divider),
        ; then draw one name per column and a muted divider above the dates.
        band := DM_RECT()
        band.left := rcClient.left, band.top := bandTop
        band.right := rcClient.right, band.bottom := fillBottom
        DllCall("FillRect", "Ptr", hdc, "Ptr", band, "Ptr", DarkTheme.GetBrush("Background"), "Void")

        for idx, left in lefts {
            rcCell := DM_RECT()
            rcCell.left := left, rcCell.top := bandTop
            rcCell.right := cells[left], rcCell.bottom := nameBottom - 1
            name := names[Mod(firstDay + idx - 1, 7) + 1]
            DllCall("DrawTextW", "Ptr", hdc, "Str", name, "Int", -1, "Ptr", rcCell,
                "UInt", DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX, "Void")
        }

        sepPen := DarkTheme.GetPen(DarkTheme.Colors["DisabledText"])
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", sepPen, "Ptr")
        DllCall("MoveToEx", "Ptr", hdc, "Int", lefts[1], "Int", fillBottom - 2, "Ptr", 0, "Void")
        DllCall("LineTo", "Ptr", hdc, "Int", cells[lefts[lefts.Length]], "Int", fillBottom - 2, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }

    /** Generic MCM_HITTEST returning the filled DM_MCHITTESTINFO struct. */
    static _HitTest(hwnd, x, y) {
        static MCM_HITTEST := 0x100E
        ht := DM_MCHITTESTINFO()
        ht.cbSize := ht.Size
        ht.pt.x := x, ht.pt.y := y
        DllCall("SendMessage", "Ptr", hwnd, "UInt", MCM_HITTEST, "Ptr", 0, "Ptr", ht.Ptr)
        return ht
    }

    /** Locale short weekday names, Monday-first (LOCALE_SABBREVDAYNAME1..7), cached. */
    static _DayNames() {
        static names := 0
        if names
            return names
        static LOCALE_USER_DEFAULT := 0x400
        names := []
        loop 7 {
            buf := Buffer(64, 0)
            ; LOCALE_SABBREVDAYNAME1 = 0x31 (Monday) ... 0x37 (Sunday)
            DllCall("GetLocaleInfoW", "UInt", LOCALE_USER_DEFAULT, "UInt", 0x30 + A_Index, "Ptr", buf, "Int", 32)
            names.Push(StrGet(buf))
        }
        return names
    }

    /** Overpaints the two classic 3D nav buttons with the title background and a flat chevron. */
    static _PaintNavButtons(hwnd) {
        rects := this._NavButtonRects(hwnd)
        if !rects
            return
        hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        for i, b in rects {
            ; Pad 1px so the classic 3D edge is fully covered; the title bar behind is also Header.
            rc := DM_RECT()
            rc.left := b[1] - 1, rc.top := b[2] - 1, rc.right := b[3] + 1, rc.bottom := b[4] + 1
            DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetSolidBrush(DarkTheme.Colors["Header"]), "Void")
            this._Chevron(hdc, (b[1] + b[3]) // 2, (b[2] + b[4]) // 2, DarkTheme.Scale(4), i = 1)
        }
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }

    /** Returns [prevRect, nextRect] (client coords) by hit-testing each nav button
     *  directly, or 0 if either hit didn't land on a button. */
    static _NavButtonRects(hwnd) {
        rcClient := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rcClient)
        cw := rcClient.right
        prev := this._HitRect(hwnd, DarkTheme.Scale(20), DarkTheme.Scale(12), cw)
        next := this._HitRect(hwnd, cw - DarkTheme.Scale(20), DarkTheme.Scale(12), cw)
        return (prev && next) ? [prev, next] : 0
    }

    /** Hit-tests (x,y) and returns the hit area's rect [L,T,R,B] when it's a small
     *  (button-sized) area, else 0. comctl6+ fills MCHITTESTINFO.rc with the area rect. */
    static _HitRect(hwnd, x, y, cw) {
        static MCM_HITTEST := 0x100E
        ht := DM_MCHITTESTINFO()
        ht.cbSize := ht.Size
        ht.pt.x := x, ht.pt.y := y
        DllCall("SendMessage", "Ptr", hwnd, "UInt", MCM_HITTEST, "Ptr", 0, "Ptr", ht.Ptr)
        w := ht.rc.right - ht.rc.left
        if w <= 0 || w >= cw // 2
            return 0
        return [ht.rc.left, ht.rc.top, ht.rc.right, ht.rc.bottom]
    }

    /** Filled flat chevron — left-pointing when prev, right-pointing otherwise. */
    static _Chevron(hdc, cx, cy, r, prev) {
        tri := DM_TRIANGLE()
        if prev {
            tri.p[1].x := cx + r, tri.p[1].y := cy - r
            tri.p[2].x := cx + r, tri.p[2].y := cy + r
            tri.p[3].x := cx - r, tri.p[3].y := cy
        } else {
            tri.p[1].x := cx - r, tri.p[1].y := cy - r
            tri.p[2].x := cx - r, tri.p[2].y := cy + r
            tri.p[3].x := cx + r, tri.p[3].y := cy
        }
        col := DarkTheme.Colors["Font"]
        oB := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetSolidBrush(col), "Ptr")
        oP := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetPen(col), "Ptr")
        DllCall("Polygon", "Ptr", hdc, "Ptr", tri.Ptr, "Int", 3, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oB, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oP, "Void")
    }
}

/**
 * Dark DateTime picker (SysDateTimePick32).
 *
 * Full owner-draw: rounded dark field, the formatted date in the control's
 * own window font (identical rendering to the other dark fields), a flat
 * dropdown chevron, and an Accent border while focused. The field text is
 * drawn by us because every native render-to-DC path (WM_PRINTCLIENT and
 * WM_PAINT(hdc), themed or classic) composes its text font from an empty
 * LOGFONT and falls back to a serif — only the screen path uses the window
 * font, and that can't be captured without flicker. Trade-off: the active
 * segment isn't highlighted while editing (keyboard/typing still works).
 * The dropdown calendar is themed on DTN_DROPDOWN via
 * {@link _DarkMonthCal.ApplyToHwnd}, dispatched from {@link DarkWindowProc}.
 */
/**
 * Shared painter for the single-line dark "field" controls (DateTime, Hotkey).
 *
 * Both draw identical chrome — parent-colored surround, rounded `Controls` fill,
 * `Accent` border while focused, and their text in the control's own window font
 * (so face and ClearType match every other dark field). Only the text source and
 * the optional dropdown chevron differ, so those are parameters and the geometry
 * lives here once instead of being maintained twice.
 */
class _DarkField {
    /**
     * Paints one field. Owns the BeginPaint/EndPaint pair.
     *
     * @param {Ptr} hwnd - Control handle.
     * @param {String} text - Text to render, already formatted by the caller.
     * @param {Boolean} [chevron=false] - Draw a dropdown chevron at the right edge
     *   and reserve the native button's width so the text cannot run under it.
     */
    static Paint(hwnd, text, chevron := false) {
        static WM_GETFONT := 0x0031
        static DT_SINGLELINE := 0x20, DT_VCENTER := 0x4, DT_NOPREFIX := 0x800
        static SM_CXVSCROLL := 2
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")
        if !hdc {
            ; Must still pair BeginPaint with EndPaint or the update region is
            ; never validated and WM_PAINT fires in a tight loop.
            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
            return
        }
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right
        h := rc.bottom

        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
        focused := DllCall("GetFocus", "Ptr") = hwnd
        borderPen := DarkTheme.GetPen(focused ? DarkTheme.Colors["Accent"] : DarkTheme.Colors["Border"])
        oldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetBrush("Controls"), "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", borderPen, "Ptr")
        radius := DarkTheme.Scale(6, hwnd)
        DllCall("RoundRect", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", radius, "Int", radius, "Void")

        pad := DarkTheme.Scale(6, hwnd)
        rightPad := pad
        if chevron {
            btnW := DllCall("GetSystemMetrics", "Int", SM_CXVSCROLL) + 2
            DarkTheme.PaintChevron(hdc, w - btnW // 2 - 1, h // 2,
                DarkTheme.Scale(4, hwnd), DarkTheme.Scale(3, hwnd), DarkTheme.Colors["Font"])
            rightPad := btnW + 4
        }

        if text != "" {
            DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
            DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")
            hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
            oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
            rcText := DM_RECT()
            rcText.left := pad, rcText.top := 0
            rcText.right := w - rightPad, rcText.bottom := h
            DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rcText,
                "UInt", DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX, "Void")
            if oldFont
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
        }

        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldBrush, "Void")
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
    }
}

class _DarkDateTime {
    /** @type {Map} hwnd -> true; consulted by DarkWindowProc for DTN_DROPDOWN */
    static Instances := Map()
    /** DTN_FIRST2 - 1 */
    static DTN_DROPDOWN := -754

    static ApplyDarkMode(ctrl) {
        DarkTheme.RemoveBorder(ctrl.Hwnd)
        this.Instances[ctrl.Hwnd] := true
        Subclass.Install(this, ctrl.Hwnd, ObjBindMethod(this, "Proc", ctrl.Hwnd))
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        if this.Instances.Has(hwnd)
            this.Instances.Delete(hwnd)
    }


    /** Paints the dropdown host's client (the inset margin around the
     *  calendar) with the theme Background instead of the light class brush;
     *  re-overpaints the ring after every host repaint. */
    static HostProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_ERASEBKGND := 0x0014, WM_PAINT := 0x000F, GW_CHILD := 5
        if msg = WM_ERASEBKGND {
            rc := DM_RECT()
            DllCall("GetClientRect", "Ptr", targetHwnd, "Ptr", rc)
            DllCall("FillRect", "Ptr", wParam, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
            return 1
        }
        if msg = WM_PAINT {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._PaintHostFrame(targetHwnd, DllCall("GetWindow", "Ptr", targetHwnd, "UInt", GW_CHILD, "Ptr"))
            return ret
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /** Dark-themes the MonthCal that just dropped down from this picker. */
    static OnDropDown(hwnd) {
        static DTM_GETMONTHCAL := 0x1008
        hMC := DllCall("SendMessage", "Ptr", hwnd, "UInt", DTM_GETMONTHCAL, "Ptr", 0, "Ptr", 0, "Ptr")
        if !hMC
            return
        ; The picker creates a fresh calendar per dropdown; an existing map entry
        ; is a stale (destroyed, possibly hwnd-reused) one — clear it first.
        if Subclass.IsInstalled(_DarkMonthCal, hMC)
            _DarkMonthCal.Remove(hMC)
        _DarkMonthCal.ApplyToHwnd(hMC)
        ; Kill the light ring around the dark dropdown: the "DropDown" host
        ; keeps the calendar inset ~3px and erases that margin with a light
        ; brush — subclass its erase to fill with the theme Background instead.
        ; Strip border styles too, and recolor the DWM popup border.
        DarkTheme.RemoveBorder(hMC)
        host := DllCall("GetParent", "Ptr", hMC, "Ptr")
        if host && host != hwnd {
            DarkTheme.RemoveBorder(host)
            ; Per-dropdown host window: clear a stale (hwnd-reused) entry first.
            if Subclass.IsInstalled(this, host)
                Subclass.Uninstall(this, host)
            Subclass.Install(this, host, ObjBindMethod(this, "HostProc", host))
            DllCall("InvalidateRect", "Ptr", host, "Ptr", 0, "Int", 1, "Void")
        }
        static DWMWA_BORDER_COLOR := 34
        popupWnd := (host && host != hwnd) ? host : hMC
        borderBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"])
        if VerCompare(A_OSVersion, "10.0.22000") >= 0
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", popupWnd, "UInt", DWMWA_BORDER_COLOR, "UInt*", borderBGR, "Int", 4)
        ; The picker positions/sizes the popup AFTER DTN_DROPDOWN returns and
        ; animates it open (~200ms); it can also re-layout once more after
        ; that. Run the (idempotent) fit twice to outlast it — two distinct
        ; bound objects, since SetTimer keys timers by function identity.
        SetTimer(ObjBindMethod(this, "_FitDropdown", hwnd, hMC), -250)
        SetTimer(ObjBindMethod(this, "_FitDropdown", hwnd, hMC), -600)
    }

    /**
     * Resizes the dropped-down calendar (and its popup host) to the calendar's
     * own minimum-required rect. The picker sizes the popup with *themed*
     * metrics before the theme is stripped, so the classic-rendered calendar
     * otherwise sits in a slightly wrong frame (clipped today row / excess
     * padding). Repositioning during DTN_DROPDOWN is the documented hook.
     */
    static _FitDropdown(hwndPicker, hMC) {
        static MCM_GETMINREQRECT := 0x1009
        static MCM_GETMAXTODAYWIDTH := 0x1015
        static SWP_NOMOVE := 0x2, SWP_NOZORDER := 0x4, SWP_NOACTIVATE := 0x10

        ; Deferred via timer — the dropdown may already be gone.
        if !DllCall("IsWindow", "Ptr", hMC)
            return
        rcMin := DM_RECT()
        if !DllCall("SendMessage", "Ptr", hMC, "UInt", MCM_GETMINREQRECT, "Ptr", 0, "Ptr", rcMin.Ptr)
            return
        todayW := DllCall("SendMessage", "Ptr", hMC, "UInt", MCM_GETMAXTODAYWIDTH, "Ptr", 0, "Ptr", 0, "Int")

        ; MCM_GETMINREQRECT is a CLIENT size — add the window frame (border) so
        ; SetWindowPos, which takes window dimensions, doesn't clip the bottom.
        rcCur := DM_RECT()
        rcCli := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hMC, "Ptr", rcCur)
        DllCall("GetClientRect", "Ptr", hMC, "Ptr", rcCli)
        frameW := (rcCur.right - rcCur.left) - rcCli.right
        frameH := (rcCur.bottom - rcCur.top) - rcCli.bottom
        needW := Max(rcMin.right, todayW) + frameW
        needH := rcMin.bottom + frameH

        dw := needW - (rcCur.right - rcCur.left)
        dh := needH - (rcCur.bottom - rcCur.top)
        host := DllCall("GetParent", "Ptr", hMC, "Ptr")

        if dw != 0 || dh != 0 {
            ; Size only — the picker owns the calendar's position (it keeps a
            ; ~3px inset inside the host).
            DllCall("SetWindowPos", "Ptr", hMC, "Ptr", 0, "Int", 0, "Int", 0, "Int", needW, "Int", needH,
                "UInt", SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE, "Void")

            ; Grow/shrink the popup host (class "DropDown") by the same delta.
            ; When the calendar itself is the popup, GetParent yields the picker.
            if host && host != hwndPicker {
                rcHost := DM_RECT()
                DllCall("GetWindowRect", "Ptr", host, "Ptr", rcHost)
                DllCall("SetWindowPos", "Ptr", host, "Ptr", 0, "Int", 0, "Int", 0,
                    "Int", rcHost.right - rcHost.left + dw, "Int", rcHost.bottom - rcHost.top + dh,
                    "UInt", SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE, "Void")
            }
        }

        ; The host paints the inset around the calendar with a light brush —
        ; overpaint that ring with the theme Background.
        if host && host != hwndPicker
            this._PaintHostFrame(host, hMC)
    }

    /** Fills the dropdown host's client margin (client minus calendar rect)
     *  with the theme Background, removing the light ring around the popup. */
    static _PaintHostFrame(host, hMC) {
        static RGN_DIFF := 4
        if !DllCall("IsWindow", "Ptr", host) || !DllCall("IsWindow", "Ptr", hMC)
            return
        hdc := DllCall("GetDC", "Ptr", host, "Ptr")
        if !hdc
            return
        rcC := DM_RECT()
        DllCall("GetClientRect", "Ptr", host, "Ptr", rcC)
        rcMC := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hMC, "Ptr", rcMC)
        pt := DM_POINT()
        pt.x := rcMC.left, pt.y := rcMC.top
        DllCall("ScreenToClient", "Ptr", host, "Ptr", pt.Ptr, "Void")
        rgnAll := DllCall("gdi32\CreateRectRgn", "Int", 0, "Int", 0, "Int", rcC.right, "Int", rcC.bottom, "Ptr")
        rgnMC := DllCall("gdi32\CreateRectRgn", "Int", pt.x, "Int", pt.y,
            "Int", pt.x + (rcMC.right - rcMC.left), "Int", pt.y + (rcMC.bottom - rcMC.top), "Ptr")
        DllCall("gdi32\CombineRgn", "Ptr", rgnAll, "Ptr", rgnAll, "Ptr", rgnMC, "Int", RGN_DIFF)
        DllCall("gdi32\FillRgn", "Ptr", hdc, "Ptr", rgnAll, "Ptr", DarkTheme.GetBrush("Background"), "Void")
        DllCall("DeleteObject", "Ptr", rgnAll, "Void")
        DllCall("DeleteObject", "Ptr", rgnMC, "Void")
        DllCall("ReleaseDC", "Ptr", host, "Ptr", hdc, "Void")
    }

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F, WM_ERASEBKGND := 0x0014
        static WM_SETFOCUS := 0x0007, WM_KILLFOCUS := 0x0008
        if msg = WM_ERASEBKGND
            return 1
        if msg = WM_PAINT {
            this.Paint(targetHwnd)
            return 0
        }
        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static Paint(hwnd) {
        ; The formatted date comes from the control's window text; every native
        ; render-to-DC path composes its font from an empty LOGFONT and falls back
        ; to a serif, so we draw it ourselves (see the class comment).
        buf := Buffer(512, 0)
        DllCall("GetWindowText", "Ptr", hwnd, "Ptr", buf, "Int", 256)
        _DarkField.Paint(hwnd, StrGet(buf), true)
    }
}

/**
 * Dark Hotkey control (msctls_hotkey32).
 *
 * Full WM_PAINT takeover: the control ignores WM_CTLCOLOR* and has no color
 * messages, so the field and its current binding text ("Ctrl + Alt + K" /
 * "None") are drawn directly. Unlike DateTime there is no internal selection
 * state to preserve, so plain owner-draw is lossless here.
 */
class _DarkHotkey {

    static ApplyDarkMode(ctrl) {
        DarkTheme.AllowDarkMode(ctrl.Hwnd)
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        DarkTheme.RemoveBorder(ctrl.Hwnd)
        Subclass.Install(this, ctrl.Hwnd, ObjBindMethod(this, "Proc", ctrl.Hwnd))
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    static Remove(hwnd) => Subclass.Uninstall(this, hwnd)

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F, WM_ERASEBKGND := 0x0014
        static WM_SETFOCUS := 0x0007, WM_KILLFOCUS := 0x0008
        if msg = WM_ERASEBKGND
            return 1
        if msg = WM_PAINT {
            this.Paint(targetHwnd)
            return 0
        }
        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static Paint(hwnd) {
        _DarkField.Paint(hwnd, this._HotkeyText(hwnd))
    }

    /**
     * Formats the control's current binding. msctls_hotkey32 does NOT implement
     * WM_GETTEXT (the display string is internal state), so the text must be
     * composed from the HKM_GETHOTKEY vk/modifier word — the earlier
     * GetWindowText approach showed a permanent "None" regardless of input.
     */
    static _HotkeyText(hwnd) {
        static HKM_GETHOTKEY := 0x0402
        static HOTKEYF_SHIFT := 1, HOTKEYF_CONTROL := 2, HOTKEYF_ALT := 4, HOTKEYF_EXT := 8
        hk := DllCall("SendMessage", "Ptr", hwnd, "UInt", HKM_GETHOTKEY, "Ptr", 0, "Ptr", 0, "Int") & 0xFFFF
        vk := hk & 0xFF
        mods := (hk >> 8) & 0xFF
        if !vk
            return "None"
        text := ""
        if mods & HOTKEYF_CONTROL
            text .= "Ctrl + "
        if mods & HOTKEYF_SHIFT
            text .= "Shift + "
        if mods & HOTKEYF_ALT
            text .= "Alt + "
        return text this._KeyName(vk, mods & HOTKEYF_EXT)
    }

    /** Key display name via GetKeyNameText (locale-aware, matches native). */
    static _KeyName(vk, ext) {
        static MAPVK_VK_TO_VSC := 0
        sc := DllCall("MapVirtualKeyW", "UInt", vk, "UInt", MAPVK_VK_TO_VSC, "UInt")
        lp := sc << 16
        if ext
            lp |= 1 << 24
        buf := Buffer(128, 0)
        if DllCall("GetKeyNameTextW", "Int", lp, "Ptr", buf, "Int", 64, "Int")
            return StrGet(buf)
        return Format("VK {:02X}", vk)
    }
}

/**
 * Owner-draw dark status bar (msctls_statusbar32).
 *
 * The control has no text-color message, so each part is flagged SBT_OWNERDRAW and
 * painted in {@link DarkWindowProc}'s WM_DRAWITEM handler ({@link _DarkStatusBar.DrawPart}).
 * `SB_SETBKCOLOR` darkens the bar fill and the sizing-grip area. An instance `Text`
 * property is added so `sb.Text := "..."` works alongside the native `SetText`.
 */
class _DarkStatusBar {
    /** @type {Map} sbHwnd -> Map(partIndex -> text string) */
    static Texts := Map()

    static ApplyDarkMode(sb) {
        static SB_SETBKCOLOR := 0x2001
        hwnd := sb.Hwnd
        ; Strip visual styles (both strings empty) so the classic flat renderer honors
        ; SBT_NOBORDERS and our owner-draw fill. The status bar class has no dark theme,
        ; so "DarkMode_Explorer" would leave a light SP_PANE border framing each part.
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "", "Str", "")
        SendMessage(SB_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), sb)
        ; SBARS_SIZEGRIP can't be cleared after creation — COMCTL32 ignores WM_STYLECHANGED
        ; (MS KB Q177341), and AHK creates the bar internally. So subclass WM_PAINT and
        ; overpaint the light grip corner dark instead (see GripProc / _PaintGripOver).
        ; The window still resizes from its frame and the (now invisible) grip still drags.
        Subclass.Install(this, hwnd, ObjBindMethod(this, "GripProc", hwnd))
        this.Texts[hwnd] := Map()

        ; No SB_SETTEXTCOLOR exists — override SetText to store the string and flag the
        ; part SBT_OWNERDRAW, then paint it dark from the parent's WM_DRAWITEM.
        sb.DefineProp("SetText", { Call: ObjBindMethod(this, "_SetText") })
        ; Convenience: sb.Text := "..." routes to the owner-draw SetText (part 1).
        sb.DefineProp("Text", {
            Get: (s) => _DarkStatusBar.Texts.Get(s.Hwnd, Map()).Get(0, ""),
            Set: (s, value) => (_DarkStatusBar._SetText(s, value, 1), value)
        })
        ; Establish owner-draw mode on part 0 (Gui.StatusBar has no GetText, so the
        ; caller's creation text is re-applied by DarkGui.Add right after this).
        sb.SetText("")
    }

    static _SetText(sb, text, part := 1, *) {
        static SB_SETTEXTW := 0x40B
        static SBT_OWNERDRAW := 0x1000
        static SBT_NOBORDERS := 0x0100  ; drop the sunken 3D part border
        idx := part - 1
        if this.Texts.Has(sb.Hwnd)
            this.Texts[sb.Hwnd][idx] := text
        ; wParam = part index | type flags; lParam = app data (reuse the index)
        SendMessage(SB_SETTEXTW, idx | SBT_OWNERDRAW | SBT_NOBORDERS, idx, sb)
    }

    /** Paints one owner-drawn part. Called from DarkWindowProc on WM_DRAWITEM. */
    static DrawPart(dis) {
        static DT_SINGLELINE := 0x20, DT_VCENTER := 0x4, DT_LEFT := 0x0, DT_END_ELLIPSIS := 0x8000
        texts := this.Texts.Get(dis.hwndItem, "")
        if !texts
            return
        text := texts.Has(dis.itemID) ? texts[dis.itemID] : ""
        rc := DM_RECT()
        rc.left := dis.rcItem.left, rc.top := dis.rcItem.top
        rc.right := dis.rcItem.right, rc.bottom := dis.rcItem.bottom
        DllCall("FillRect", "Ptr", dis.hDC, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Controls"), "Void")
        if text = ""
            return
        rc.left += DarkTheme.Scale(4)
        DllCall("SetBkMode", "Ptr", dis.hDC, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", dis.hDC, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
        DllCall("DrawTextW", "Ptr", dis.hDC, "Str", text, "Int", -1, "Ptr", rc,
            "UInt", DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS, "Void")
    }

    /**
     * Status-bar subclass proc. After the control paints itself (parts owner-draw via
     * the parent's WM_DRAWITEM), overpaint the light sizing-grip corner with the dark
     * Header brush so the grip disappears into the bar.
     */
    static GripProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        if msg = WM_PAINT {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._PaintGripOver(hwnd)
            return ret
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /** Fills the bottom-right grip square (side = bar height) with the Controls brush. */
    static _PaintGripOver(hwnd) {
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        grip := DM_RECT()
        grip.left := rc.right - rc.bottom, grip.top := 0
        grip.right := rc.right, grip.bottom := rc.bottom
        hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        DllCall("FillRect", "Ptr", hdc, "Ptr", grip, "Ptr", DarkTheme.GetBrush("Controls"), "Void")
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }

    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        this.Texts.Delete(hwnd)
    }
}

/**
 * Owner-draw dark up-down (spinner) control.
 *
 * Keeps the native increment / auto-repeat logic — only WM_PAINT and WM_ERASEBKGND
 * are taken over, so clicks still reach the original proc and drive the buddy Edit.
 * Pairs with a dark numeric Edit for a NumericUpDown look.
 */
class _DarkUpDown {

    static ApplyDarkMode(ud) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", ud.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        Subclass.Install(this, ud.Hwnd, ObjBindMethod(this, "Proc", ud.Hwnd))
        DllCall("InvalidateRect", "Ptr", ud.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
    }

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        static WM_ERASEBKGND := 0x0014
        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        if msg = WM_ERASEBKGND
            return 1
        if msg = WM_PAINT {
            this.Paint(hwnd)
            return 0
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static Paint(hwnd) {
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right, h := rc.bottom

        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Controls"), "Void")
        midY := h // 2

        ; Divider between the two arrow halves
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetPen(DarkTheme.Colors["ButtonBorder"]), "Ptr")
        DllCall("MoveToEx", "Ptr", hdc, "Int", 0, "Int", midY, "Ptr", 0, "Void")
        DllCall("LineTo", "Ptr", hdc, "Int", w, "Int", midY, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")

        ; Same stroked chevron as the DateTime picker and ComboBox dropdown, so a
        ; spinner sitting next to either reads as the same control family.
        ; Clamped to the spinner's narrow halves: it is ~17px wide and each half
        ; only ~11px tall, where the unclamped picker sizes would collide.
        cx := w // 2
        half := Max(3, Min(DarkTheme.Scale(4, hwnd), w // 2 - 2))
        rise := Max(2, Min(DarkTheme.Scale(3, hwnd), midY // 2 - 2))
        fontColor := DarkTheme.Colors["Font"]
        DarkTheme.PaintChevron(hdc, cx, midY // 2, half, rise, fontColor, true)
        DarkTheme.PaintChevron(hdc, cx, midY + midY // 2, half, rise, fontColor, false)

        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
    }
}

/**
 * Dark SysLink (hyperlink) control.
 *
 * The surrounding text and background are handled by {@link DarkWindowProc}'s
 * WM_CTLCOLORSTATIC; the clickable link segments are recolored to
 * `DarkTheme.Colors["Link"]` via NM_CUSTOMDRAW (dispatched from DarkWindowProc's
 * WM_NOTIFY), since SysLink exposes no link-color message.
 */
class _DarkLink {
    static ApplyDarkMode(link) {
        DarkTheme.AllowDarkMode(link.Hwnd)
        link.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
        DarkWindowProc.LinkControls[link.Hwnd] := true
    }

    /** NM_CUSTOMDRAW handler; returns the CDRF_* result for the parent window proc. */
    static OnCustomDraw(lParam) {
        static CDDS_PREPAINT := 0x1, CDDS_ITEMPREPAINT := 0x10001
        static CDRF_DODEFAULT := 0x0, CDRF_NOTIFYITEMDRAW := 0x20
        nmcd := DM_NMCUSTOMDRAW.At(lParam)
        switch nmcd.dwDrawStage {
            case CDDS_PREPAINT:
                return CDRF_NOTIFYITEMDRAW
            case CDDS_ITEMPREPAINT:
                DllCall("SetTextColor", "Ptr", nmcd.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Link"]), "Void")
                return CDRF_DODEFAULT
        }
        return CDRF_DODEFAULT
    }

    static Remove(hwnd) {
        DarkWindowProc.LinkControls.Delete(hwnd)
    }
}

/**
 * Custom-draw GroupBox: fills background, draws dim border, renders title in Font color.
 * WM_CTLCOLORBTN does not control GroupBox text color — a WM_PAINT subclass is required.
 */
class _DarkGroupBox {
    static GroupTexts := Map()

    /**
     * Applies dark theme to a GroupBox control.
     * Subclasses the control for custom WM_PAINT rendering.
     *
     * @param {Gui.GroupBox} ctrl - GroupBox control instance.
     */
    static ApplyDarkMode(ctrl) {
        hwnd := ctrl.Hwnd
        buf := Buffer(256, 0)
        DllCall("GetWindowText", "Ptr", hwnd, "Ptr", buf, "Int", 256)
        this.GroupTexts[hwnd] := StrGet(buf)
        ; The standard pattern layers controls ON the box, and siblings created
        ; AFTER the box land BELOW it in the Z order — so this paint may never
        ; fill the interior (it would cover those controls; see Proc/Paint,
        ; border + title only). Clip the siblings above us out of our region
        ; and stay at the bottom so earlier controls are unaffected too.
        static GWL_STYLE := -16, WS_CLIPSIBLINGS := 0x04000000
        static HWND_BOTTOM := 1, SWP_NOMOVE := 0x2, SWP_NOSIZE := 0x1, SWP_NOACTIVATE := 0x10
        style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style | WS_CLIPSIBLINGS)
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", HWND_BOTTOM, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "UInt", SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE, "Void")
        Subclass.Install(this, hwnd, ObjBindMethod(this, "Proc", hwnd))
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /**
     * Removes subclass and frees resources for a GroupBox.
     *
     * @param {Ptr} hwnd - GroupBox window handle.
     */
    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        this.GroupTexts.Delete(hwnd)
    }

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT      := 0x000F
        static WM_ERASEBKGND := 0x0014
        static WM_SETTEXT    := 0x000C
        if msg = WM_ERASEBKGND {
            ; No interior fill — controls created after the box sit BELOW it in
            ; the Z order, so any fill here paints straight over them (invisible
            ; radios/edits inside group boxes). The parent's identical dark
            ; background already shows through; Paint draws border + title only.
            return 1
        }
        if msg = WM_PAINT {
            this.Paint(targetHwnd)
            return 0
        }
        ; Keep the cached title in sync when code calls gb.Text := "..." and repaint.
        if msg = WM_SETTEXT {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            this.GroupTexts[targetHwnd] := lParam ? StrGet(lParam) : ""
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return result
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static Paint(hwnd) {
        ps  := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")

        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right
        h := rc.bottom

        ; NO interior fill — see Proc's WM_ERASEBKGND note. Border + title only.

        ; Select control font so text metrics are accurate
        hFont   := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0

        ; Measure font height
        tm := DM_TEXTMETRICW()
        DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", tm.Ptr)
        tmH := tm.tmHeight

        ; Measure title text width
        groupText := this.GroupTexts.Get(hwnd, "")
        sz := DM_SIZE()
        DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", groupText, "Int", StrLen(groupText), "Ptr", sz.Ptr)
        textW := sz.cx

        textX   := DarkTheme.Scale(9)
        borderY := tmH // 2

        ; Draw hollow border rectangle (NULL_BRUSH = stock 5, no fill).
        ; Border pen is cached by DarkTheme — do not delete it.
        hNull := DllCall("GetStockObject", "Int", 5, "Ptr")
        oPen  := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetPen(DarkTheme.Colors["Border"]), "Ptr")
        oBr   := DllCall("SelectObject", "Ptr", hdc, "Ptr", hNull, "Ptr")
        DllCall("RoundRect", "Ptr", hdc, "Int", 0, "Int", borderY, "Int", w, "Int", h, "Int", 8, "Int", 8, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oPen, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oBr, "Void")

        ; Punch a background-colored gap in the top border line where the title sits
        if StrLen(groupText) > 0 {
            gapRc := DM_RECT()
            gapRc.left := textX - 2,        gapRc.top := borderY - 1
            gapRc.right := textX + textW + 2, gapRc.bottom := borderY + 1
            DllCall("FillRect", "Ptr", hdc, "Ptr", gapRc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
        }

        ; Draw title text in Font color. With no interior fill, clear the title
        ; strip first so caption changes don't leave stale glyphs behind.
        DllCall("SetBkMode",    "Ptr", hdc, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
        textRc := DM_RECT()
        textRc.left := textX, textRc.top := 0, textRc.right := textX + textW + 4, textRc.bottom := tmH
        DllCall("FillRect", "Ptr", hdc, "Ptr", textRc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
        static DT_SINGLELINE := 0x20
        DllCall("DrawTextW", "Ptr", hdc, "Str", groupText, "Int", -1, "Ptr", textRc, "UInt", DT_SINGLELINE, "Void")

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
    }
}

/**
 * Dark mode for Tab3 (SysTabControl32) controls.
 *
 * Win32 layered approach (from research):
 *   1. SetWindowTheme("DarkMode_Explorer") — registers control as dark-aware;
 *      on Win11 22H2+ the OS native rendering already draws white tab text.
 *   2. AllowDarkModeForWindow (uxtheme ordinal 133) — required dark-mode flag.
 *   3. WM_THEMECHANGED suppressed — prevents OS from resetting our theme.
 *   4. WM_ERASEBKGND — suppressed (return 1, no fill); background is drawn
 *      atomically inside the WM_PAINT double-buffer, eliminating the flash
 *      that would appear if erase and paint were separate screen writes.
 *   5. WM_PAINT — double-buffered: BeginPaint DC + CreateCompatibleDC +
 *      PaintTabs (fills memory DC) + BitBlt + EndPaint. Production pattern
 *      confirmed by darkmodelib / Notepad++ dark-mode tab implementation.
 */
class _DarkTab {

    /**
     * Applies dark theme to a Tab3 control.
     * Registers with OS dark-mode engine, removes sunken border, and
     * subclasses for double-buffered custom WM_PAINT via {@link _DarkTab.PaintTabs}.
     *
     * @param {Gui.Tab} ctrl - Tab3 control instance.
     */
    static ApplyDarkMode(ctrl) {
        hwnd := ctrl.Hwnd
        ; Register this control as dark-aware with the OS theme engine
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        DarkTheme.AllowDarkMode(hwnd, true)
        ; Remove sunken edge — we draw our own border (none, by design)
        DarkTheme.RemoveBorder(hwnd)
        Subclass.Install(this, hwnd, ObjBindMethod(this, "Proc", hwnd))
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /**
     * Removes dark mode subclass and restores default rendering.
     *
     * @param {Ptr} hwnd - Tab3 window handle.
     */
    static Remove(hwnd) {
        DarkTheme.AllowDarkMode(hwnd, false)
        Subclass.Uninstall(this, hwnd)
    }

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT        := 0x000F
        static WM_ERASEBKGND   := 0x0014
        static WM_NCPAINT      := 0x0085
        static WM_THEMECHANGED := 0x031A
        ; Suppress default background erase — WM_PAINT handles it inside the
        ; double-buffer, so no separate screen write occurs before the blit.
        if msg = WM_ERASEBKGND
            return 1
        ; Suppress non-client paint — prevents the tab control from drawing its
        ; angled content-area frame border over the custom-painted background.
        if msg = WM_NCPAINT
            return 0
        ; Suppress theme changes — prevents OS from resetting SetWindowTheme
        if msg = WM_THEMECHANGED
            return 0
        if msg = WM_PAINT {
            ; Production pattern (darkmodelib / Notepad++):
            ;   1. BeginPaint validates the update region (stops WM_PAINT loop).
            ;   2. Paint into a full-size memory DC (no clip restriction).
            ;   3. BitBlt from memory DC to BeginPaint DC atomically.
            ;   4. EndPaint releases BeginPaint state.
            ; This eliminates the flash that comes from WM_ERASEBKGND + WM_PAINT
            ; writing to the screen twice, and GetDCEx/GetDC reliability issues.
            static SRCCOPY := 0xCC0020
            ps := DM_PAINTSTRUCT()
            hdc := DllCall("BeginPaint", "Ptr", targetHwnd, "Ptr", ps.Ptr, "Ptr")
            rcBuf := DM_RECT()
            DllCall("GetClientRect", "Ptr", targetHwnd, "Ptr", rcBuf)
            w := rcBuf.right
            h := rcBuf.bottom
            hdcMem  := DllCall("CreateCompatibleDC",     "Ptr", hdc, "Ptr")
            hBmp    := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", w, "Int", h, "Ptr")
            hBmpOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBmp, "Ptr")
            this.PaintTabs(targetHwnd, hdcMem)
            DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h,
                "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", SRCCOPY, "Void")
            DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBmpOld, "Void")
            DllCall("DeleteObject", "Ptr", hBmp, "Void")
            DllCall("DeleteDC",     "Ptr", hdcMem, "Void")
            DllCall("EndPaint", "Ptr", targetHwnd, "Ptr", ps.Ptr, "Void")
            return 0
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /**
     * Full owner-draw for Tab3 WM_PAINT.
     *
     * Layout:
     *   • Entire client area → Background fill (no outer border)
     *   • Unselected tabs    → transparent background, FontDim text
     *   • Selected tab       → Controls fill, rounded corners (6px), Font text
     *   • Separator line     → 1px Border color between tab strip and content
     *
     * Pattern mirrors _DarkGroupBox.Paint / _DarkButton.PaintButton.
     */
    static PaintTabs(hwnd, hdc) {
        static TCM_GETITEMCOUNT := 0x1304  ; TCM_FIRST + 4
        static TCM_GETITEMRECT  := 0x130A  ; TCM_FIRST + 10
        static TCM_GETCURSEL    := 0x130B  ; TCM_FIRST + 11
        static TCM_GETITEM      := 0x133C  ; TCM_FIRST + 60 (W)
        static TCM_ADJUSTRECT   := 0x1328  ; TCM_FIRST + 40
        static TCIF_TEXT        := 0x1
        static DT_CENTER        := 0x1
        static DT_VCENTER       := 0x4
        static DT_SINGLELINE    := 0x20
        static NULL_PEN         := 8      ; GetStockObject(8)

        ; Geometry
        clientRc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", clientRc)
        w := clientRc.right
        h := clientRc.bottom

        ; Fill entire background — no tab-control border
        DllCall("FillRect", "Ptr", hdc, "Ptr", clientRc, "Ptr", DarkTheme.GetBrush("Background"), "Void")

        selIdx := DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETCURSEL,    "Ptr", 0, "Ptr", 0, "Int")
        tabCount := DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETITEMCOUNT, "Ptr", 0, "Ptr", 0, "Int")
        if tabCount <= 0
            return

        ; Content area top = tab strip bottom (for separator line)
        adjRc := DM_RECT()
        adjRc.left := 0, adjRc.top := 0, adjRc.right := w, adjRc.bottom := h
        DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_ADJUSTRECT, "Ptr", 0, "Ptr", adjRc)
        tabStripBottom := adjRc.top

        ; Select control font
        hFont   := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")  ; TRANSPARENT

        hNullPen := DllCall("GetStockObject", "Int", NULL_PEN, "Ptr")

        loop tabCount {
            i := A_Index - 1
            itemRc := DM_RECT()
            DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETITEMRECT, "Ptr", i, "Ptr", itemRc)
            left   := itemRc.left
            top    := itemRc.top
            right  := itemRc.right
            bottom := itemRc.bottom

            if (i = selIdx) {
                ; Rounded pill: top corners round, bottom corners square.
                ; Draw full RoundRect, then overdraw bottom 6px with FillRect
                ; using same brush — squares off the bottom corner curves.
                tabBrush := DarkTheme.GetSolidBrush(DarkTheme.Colors["ControlsHover"])  ; cached — do not delete
                oPen   := DllCall("SelectObject", "Ptr", hdc, "Ptr", hNullPen, "Ptr")
                oBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", tabBrush, "Ptr")
                DllCall("RoundRect", "Ptr", hdc,
                    "Int", left+2, "Int", top, "Int", right-1, "Int", bottom+1,
                    "Int", 6, "Int", 6, "Void")
                squareRc := DM_RECT()
                squareRc.left := left+2,  squareRc.top := bottom-6
                squareRc.right := right-1, squareRc.bottom := bottom+1
                DllCall("FillRect", "Ptr", hdc, "Ptr", squareRc, "Ptr", tabBrush, "Void")
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oPen, "Void")
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oBrush, "Void")
                DllCall("SetTextColor", "Ptr", hdc, "UInt",
                    DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
            } else {
                DllCall("SetTextColor", "Ptr", hdc, "UInt",
                    DarkTheme.RGBtoBGR(DarkTheme.Colors["FontDim"]), "Void")
            }

            ; Fetch label text via TCM_GETITEMW and draw centered
            textBuf := Buffer(512, 0)
            tcItem  := DM_TCITEMW()
            tcItem.mask       := TCIF_TEXT
            tcItem.pszText    := textBuf.Ptr
            tcItem.cchTextMax := 255
            DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETITEM, "Ptr", i, "Ptr", tcItem.Ptr)
            tabText := StrGet(textBuf)
            DllCall("DrawTextW", "Ptr", hdc, "Str", tabText, "Int", -1, "Ptr", itemRc,
                "UInt", DT_CENTER | DT_VCENTER | DT_SINGLELINE, "Void")
        }

        ; 1px separator line between tab strip and content area
        if tabStripBottom > 0 {
            sepRc := DM_RECT()
            sepRc.left := 0, sepRc.top := tabStripBottom - 1, sepRc.right := w, sepRc.bottom := tabStripBottom
            DllCall("FillRect", "Ptr", hdc, "Ptr", sepRc, "Ptr", DarkTheme.GetBrush("Border"), "Void")
        }

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
    }
}

/**
 * Window procedure subclass for handling WM_CTLCOLOR* messages.
 * Provides dark background brushes for Edit, ListBox, Button, and Static controls.
 */
class DarkWindowProc {
    /** @type {Map} Radio button text control handles for WM_CTLCOLORSTATIC */
    static RadioTextControls := Map()
    /** @type {Map} Menu bar control handles that need Header background instead of Background */
    static MenuBarControls := Map()
    /** @type {Map} ComboBox dropdown list handles for WM_CTLCOLORLISTBOX */
    static ComboDropdowns := Map()
    /** @type {Map} SysLink control handles whose link segments get recolored via NM_CUSTOMDRAW */
    static LinkControls := Map()
    /** @type {Map} ListView hwnds whose item NM_CUSTOMDRAW is answered here —
     * the reply from control-side OnNotify never reaches the control. */
    static ListViewControls := Map()

    /** @type {Map} hwnd -> Map of per-control color overrides consulted when
     * answering WM_CTLCOLORSTATIC. Slots: "text" and "back". */
    static StaticColors := Map()

    /**
     * Pins a color on one Static control, overriding the palette default for
     * that control only. Without this every Static in a DarkGui is painted in
     * Colors["Font"] over Colors["Background"] — a `cRed` creation option or a
     * SetFont("cRed") is overwritten by the WM_CTLCOLORSTATIC reply below — so
     * a status label could not go red and a Text control could not serve as a
     * solid color swatch.
     *
     * Prefer the {@link Gui.Text} wrappers `SetTextColor` / `SetBackColor`.
     *
     * @param {Ptr} hwnd - Static control handle.
     * @param {String} slot - "text" or "back".
     * @param {Integer|String} color - An 0xRRGGBB value, or a DarkTheme.Colors
     *   key ("Error", "Success", "Warning", "FontDim", ...). A key is resolved
     *   at paint time, so the control follows palette swaps; a raw integer is
     *   fixed.
     */
    static SetStaticColor(hwnd, slot, color) {
        if !this.StaticColors.Has(hwnd)
            this.StaticColors[hwnd] := Map()
        this.StaticColors[hwnd][slot] := color
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /** Drops a control's overrides so it follows the palette again. */
    static ClearStaticColor(hwnd) {
        if !this.StaticColors.Has(hwnd)
            return
        this.StaticColors.Delete(hwnd)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /**
     * Resolves one override slot. Uses Has rather than a blank test so that a
     * legitimate 0x000000 (black) is not mistaken for "unset".
     * @param {Map} spec - The control's override map.
     * @param {String} slot - "text" or "back".
     * @param {String} fallbackKey - Palette key used when the slot is unset.
     * @returns {Integer} Color in 0xRRGGBB.
     */
    static _ResolveStaticColor(spec, slot, fallbackKey) {
        if !spec.Has(slot)
            return DarkTheme.Colors[fallbackKey]
        value := spec[slot]
        if value is String
            return DarkTheme.Colors.Has(value) ? DarkTheme.Colors[value] : DarkTheme.Colors[fallbackKey]
        return value
    }

    /**
     * Installs dark window procedure on a window.
     * @param {Ptr} hwnd - Window handle
     */
    static Install(hwnd) {
        Subclass.Install(this, hwnd, ObjBindMethod(this, "Proc", hwnd))
    }

    /**
     * Removes dark window procedure and restores original.
     * @param {Ptr} hwnd - Window handle
     */
    static Uninstall(hwnd) {
        Subclass.Uninstall(this, hwnd)
    }

    /**
     * Handles `WM_CTLCOLOR*` messages to apply dark background brushes
     * and text colors for Edit, ListBox, Button, and Static controls.
     *
     * @param {Ptr} targetHwnd - Subclassed window handle.
     * @param {Ptr} hwnd - Message target window handle.
     * @param {Integer} msg - Windows message ID.
     * @param {Ptr} wParam - HDC of the control.
     * @param {Ptr} lParam - HWND of the control.
     * @returns {Ptr} GDI brush handle for the control background.
     */
    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_CTLCOLOREDIT := 0x0133
        static WM_CTLCOLORLISTBOX := 0x0134
        static WM_CTLCOLORBTN := 0x0135
        static WM_CTLCOLORSTATIC := 0x0138
        static WM_DRAWITEM := 0x002B
        static WM_NOTIFY := 0x004E
        static WM_DPICHANGED := 0x02E0
        static NM_CUSTOMDRAW := -12
        static TRANSPARENT := 1

        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)

        switch msg {
            case WM_CTLCOLOREDIT:
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush("Controls")

            case WM_CTLCOLORLISTBOX:
                ; lParam = listbox hwnd - check if it's a ComboBox dropdown or standalone ListBox
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                if this.ComboDropdowns.Has(lParam) {
                    ; ComboBox dropdown - use Background color to match GUI
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]))
                    return DarkTheme.GetBrush("Background")
                } else {
                    ; Standalone ListBox - use Controls color
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]))
                    return DarkTheme.GetBrush("Controls")
                }

            case WM_CTLCOLORBTN:
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush("Background")

            case WM_CTLCOLORSTATIC:
                ; lParam = control handle in WM_CTLCOLOR messages
                ; Per-control overrides win over the palette default: a status
                ; label painted Error red, or a Text used as a color swatch.
                if this.StaticColors.Has(lParam) {
                    spec := this.StaticColors[lParam]
                    fore := this._ResolveStaticColor(spec, "text", "Font")
                    back := this._ResolveStaticColor(spec, "back", "Background")
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(fore))
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(back))
                    DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                    return DarkTheme.GetSolidBrush(back)
                }
                ; Menu bar controls use same background as GUI
                if this.MenuBarControls.Has(lParam) {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                    DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                    return DllCall("gdi32\GetStockObject", "Int", 5, "Ptr")  ; HOLLOW_BRUSH - preserve BackgroundTrans
                }
                ; Radio text controls
                if this.RadioTextControls.Has(lParam) {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]))
                    DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                    return DarkTheme.GetBrush("Background")
                }
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush("Background")

            case WM_DRAWITEM:
                ; Owner-drawn dark status bar parts (no SB text-color message exists).
                dis := DM_DRAWITEMSTRUCT.At(lParam)
                if _DarkStatusBar.Texts.Has(dis.hwndItem) {
                    _DarkStatusBar.DrawPart(dis)
                    return 1
                }

            case WM_NOTIFY:
                nm := DM_NMHDR.At(lParam)
                ; Dark-theme the calendar dropping down from a DateTime picker.
                if nm.code = _DarkDateTime.DTN_DROPDOWN && _DarkDateTime.Instances.Has(nm.hwndFrom)
                    _DarkDateTime.OnDropDown(nm.hwndFrom)
                ; Recolor SysLink link segments via NM_CUSTOMDRAW; clicks fall through
                ; to AHK so OnEvent("Click") still fires.
                if nm.code = NM_CUSTOMDRAW && this.LinkControls.Has(nm.hwndFrom)
                    return _DarkLink.OnCustomDraw(lParam)
                ; ListView item colors (selection kept on palette when unfocused)
                if nm.code = NM_CUSTOMDRAW && this.ListViewControls.Has(nm.hwndFrom)
                    return _DarkListView._ItemCustomDraw(lParam)

            case WM_DPICHANGED:
                ; Per-monitor DPI move: honor the OS-suggested rect (required for
                ; a clean transition), repaint, and hand control repositioning to
                ; the app via DarkGui.OnDpiChanged. Only fires when the process
                ; is per-monitor DPI aware; otherwise this case is dormant.
                static SWP_NOZORDER := 0x4, SWP_NOACTIVATE := 0x10
                static RDW_FLAGS := 0x1 | 0x4 | 0x80 | 0x100  ; INVALIDATE | ERASE | ALLCHILDREN | UPDATENOW
                rcNew := DM_RECT.At(lParam)
                DllCall("SetWindowPos", "Ptr", targetHwnd, "Ptr", 0,
                    "Int", rcNew.left, "Int", rcNew.top,
                    "Int", rcNew.right - rcNew.left, "Int", rcNew.bottom - rcNew.top,
                    "UInt", SWP_NOZORDER | SWP_NOACTIVATE, "Void")
                if DarkGui.DpiChangedCallbacks.Has(targetHwnd) {
                    cb := DarkGui.DpiChangedCallbacks[targetHwnd]
                    cb(targetHwnd, wParam & 0xFFFF, rcNew)
                }
                DllCall("RedrawWindow", "Ptr", targetHwnd, "Ptr", 0, "Ptr", 0, "UInt", RDW_FLAGS, "Void")
                return 0
        }

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }
}

/**
 * Builder returned by {@link DarkMenuBar#AddMenu}. Wraps an `HMENU` handle and
 * exposes chainable `Item` / `Sep` methods so menu construction reads top-to-bottom
 * at the call site without `Map(...)` boilerplate per entry.
 */
class _DarkMenuBuilder {
    __New(hPopup) {
        this.hPopup := hPopup
    }

    /**
     * Appends a normal menu item.
     * @param {String} text - Display text.
     * @param {Integer} id - Command id dispatched via `WM_COMMAND`.
     * @param {String} [shortcut=""] - Right-aligned hint (e.g. "Ctrl+N"); not a real accelerator.
     * @returns {_DarkMenuBuilder} this (chainable)
     */
    Item(text, id, shortcut := "") {
        itemText := shortcut ? text "`t" shortcut : text
        DllCall("AppendMenuW", "Ptr", this.hPopup, "UInt", 0x0000, "Ptr", id, "Str", itemText, "Void")
        return this
    }

    /**
     * Appends a separator line.
     * @returns {_DarkMenuBuilder} this (chainable)
     */
    Sep() {
        DllCall("AppendMenuW", "Ptr", this.hPopup, "UInt", 0x0800, "Ptr", 0, "Ptr", 0, "Void")
        return this
    }
}

/**
 * Custom dark menu bar using Win32 popup menus with dark theme.
 * Uses `SetMenuInfo` for dark popup backgrounds + uxtheme dark mode APIs.
 * `WM_COMMAND` (`0x0111`) handled externally by consumer class.
 *
 * Construct with a {@link DarkGui} parent and a `Map` of layout/color options.
 * Call {@link DarkMenuBar#AddMenu} to define menus with popup items,
 * and {@link DarkMenuBar#AddToolbarButton} for icon toolbar buttons.
 */
class DarkMenuBar {
    /**
     * Creates a dark menu bar with optional toolbar.
     *
     * @param {DarkGui} parentGui - The parent GUI instance.
     * @param {Map} options - Configuration options.
     * @param {Integer} [options.menuBarHeight = 24] - Menu bar height in pixels.
     * @param {Integer} [options.toolbarHeight = 32] - Toolbar row height.
     * @param {Integer} [options.menuItemPadding = 12] - Horizontal padding per menu label.
     * @param {Integer} [options.menuFontSize = 9] - Font size for menu labels.
     * @param {Integer} [options.toolbarIconSize = 20] - Toolbar button icon size.
     * @param {Boolean} [options.showToolbar = true] - Whether to show the toolbar row.
     * @param {Integer} [options.popupOffsetX = 0] - Popup menu X offset from label.
     * @param {Integer} [options.popupOffsetY = 0] - Popup menu Y offset from label.
     */
    __New(parentGui, options) {
        this.gui := parentGui
        ; Cached for Destroy: Gui.Hwnd throws once the window is gone.
        this._guiHwnd := parentGui.Hwnd
        this.menuItems := []
        this.toolbarBtns := []
        this.hoveredMenu := ""

        this.layout := Map(
            "menuBarHeight", options.Get("menuBarHeight", 24),
            "toolbarHeight", options.Get("toolbarHeight", 32),
            "menuItemPadding", options.Get("menuItemPadding", 12),
            "menuFontSize", options.Get("menuFontSize", 9),
            "toolbarIconSize", options.Get("toolbarIconSize", 20),
            "toolbarButtonSpacing", options.Get("toolbarButtonSpacing", 4),
            "toolbarSeparatorWidth", options.Get("toolbarSeparatorWidth", 1),
            "showToolbar", options.Get("showToolbar", true),
            "popupOffsetX", options.Get("popupOffsetX", 0),
            "popupOffsetY", options.Get("popupOffsetY", 0)
        )

        this.colors := Map(
            "menuBarBg", options.Get("menuBarBg", DarkTheme.Colors["Header"]),
            "menuBarText", options.Get("menuBarText", DarkTheme.Colors["Font"]),
            "menuBarHover", options.Get("menuBarHover", DarkTheme.Colors["ControlsActive"]),
            "menuBarActive", options.Get("menuBarActive", DarkTheme.Colors["Accent"]),
            "popupBg", options.Get("popupBg", DarkTheme.Colors["Header"]),
            "toolbarBg", options.Get("toolbarBg", DarkTheme.Colors["Header"]),
            "toolbarBorder", options.Get("toolbarBorder", DarkTheme.Colors["Border"])
        )

        ; Popup background brush is owned by this menu bar, not by DarkTheme's
        ; value cache — see ApplyDarkThemeToPopup for why. Track whether popupBg
        ; was caller-supplied so palette swaps only retint the defaulted case.
        this._popupBrush := 0
        this._popupBgDefault := !options.Has("popupBg")

        this.totalHeight := this.layout["showToolbar"] ?
            (this.layout["menuBarHeight"] + this.layout["toolbarHeight"] + 1) :
            this.layout["menuBarHeight"]

        DarkMenu.Apply()
        DarkTheme.AllowDarkMode(this.gui.Hwnd, true)
        this.CreateMenuBar()
        if this.layout["showToolbar"] {
            this.CreateToolbar()
        }

        this._onMouseMove := this.OnMouseMove.Bind(this)
        OnMessage(0x200, this._onMouseMove)
        this._lastHoveredBtn := ""

        ; Rebuild the popup brush whenever the palette changes; unregistered in
        ; Destroy so this bar doesn't outlive its window inside DarkTheme.
        this._onPaletteChanged := this.OnPaletteChanged.Bind(this)
        DarkTheme.OnThemeChanged(this._onPaletteChanged)

        ; Menu/toolbar bars are added at a fixed width; stretch them to the
        ; client width whenever the parent (e.g. +Resize) window changes size.
        this._onParentSize := this.OnParentSize.Bind(this)
        this.gui.OnEvent("Size", this._onParentSize)
    }

    /** Stretches the menu bar, toolbar, and toolbar border to the client width. */
    OnParentSize(guiObj, minMax, width, height) {
        if minMax = -1  ; minimized
            return
        if this.HasProp("menuBar")
            this.menuBar.Move(, , width)
        if this.HasProp("toolbar") {
            this.toolbar.Move(, , width)
            this.toolbarBorder.Move(, , width)
        }
    }

    CreateMenuBar() {
        this.menuBar := this.gui.AddText("x0 y0 w800 h" . this.layout["menuBarHeight"] . " Background" . Format("{:06X}", this.colors["menuBarBg"]))

        this.popupMenus := Map()
        this.menuStructure := Map()

        x := 8
        this.menuBarStartX := x
    }

    /**
     * Adds a named menu to the menu bar with a popup of items.
     *
     * Each item in `menuItems` is a `Map` with keys:
     * - `"text"` `{String}` - Menu item label.
     * - `"id"` `{Integer}` - Command ID for `WM_COMMAND`.
     * - `"shortcut"` `{String}` - Optional keyboard shortcut hint.
     * - `"separator"` `{Boolean}` - If `true`, draws a separator line.
     *
     * @param {String} menuName - Label displayed in the menu bar.
     * @param {Array} menuItems - Array of `Map` objects defining popup items.
     * @returns {Ptr} Handle to the created popup menu (`HMENU`).
     */
    /**
     * Creates an empty popup menu and the clickable label that opens it.
     * Returns a {@link _DarkMenuBuilder} — call `.Item()` / `.Sep()` on it to
     * populate. The dark theme is applied to the popup before items are added,
     * so they inherit the dark background automatically.
     *
     * @param {String} menuName - Top-level label shown on the menu bar.
     * @returns {_DarkMenuBuilder}
     */
    AddMenu(menuName) {
        hPopup := DllCall("CreatePopupMenu", "Ptr")
        this.ApplyDarkThemeToPopup(hPopup)

        ; Center label vertically using SS_CENTERIMAGE (0x200). Create it at a
        ; placeholder width, set the font, then size to the *measured* text so
        ; the label fits any font size / non-ASCII name — the old StrLen*7 guess
        ; clipped wide glyphs and over-padded narrow ones.
        menuLabel := this.gui.AddText("x" . this.menuBarStartX . " y0 w10 h" . this.layout["menuBarHeight"] . " +0x200 Center BackgroundTrans c" . Format("{:06X}", this.colors["menuBarText"]), menuName)
        menuLabel.SetFont("s" . this.layout["menuFontSize"], "Segoe UI")
        itemWidth := this._MeasureLabelWidth(menuLabel, menuName) + this.layout["menuItemPadding"]
        menuLabel.Move(, , itemWidth)

        hitArea := this.gui.AddText("x" . this.menuBarStartX . " y0 w" . itemWidth . " h" . this.layout["menuBarHeight"] . " BackgroundTrans")
        hitArea.OnEvent("Click", this.ShowPopupMenu.Bind(this, hPopup, this.menuBarStartX))

        menuItemData := Map(
            "name", menuName,
            "label", menuLabel,
            "hitArea", hitArea,
            "popup", hPopup,
            "x", this.menuBarStartX,
            "width", itemWidth
        )

        this.menuItems.Push(menuItemData)
        this.popupMenus[menuName] := hPopup

        ; Register with DarkWindowProc so WM_CTLCOLORSTATIC returns HOLLOW_BRUSH
        ; (preserves BackgroundTrans and white text on menu bar)
        DarkWindowProc.MenuBarControls[menuLabel.Hwnd] := true
        DarkWindowProc.MenuBarControls[hitArea.Hwnd] := true

        this.menuBarStartX += itemWidth + 4

        return _DarkMenuBuilder(hPopup)
    }

    CreateToolbar() {
        toolbarY := this.layout["menuBarHeight"]

        this.toolbar := this.gui.AddText("x0 y" . toolbarY . " w800 h" . this.layout["toolbarHeight"] . " Background" . Format("{:06X}", this.colors["toolbarBg"]))
        this.toolbarBorder := this.gui.AddText("x0 y" . (toolbarY + this.layout["toolbarHeight"]) . " w800 h1 Background" . Format("{:06X}", this.colors["toolbarBorder"]))

        this.toolbarStartX := 6
        this.toolbarY := toolbarY + Integer((this.layout["toolbarHeight"] - this.layout["toolbarIconSize"]) / 2)
    }

    /**
     * Adds an icon button to the toolbar row below the menu bar.
     *
     * @param {String} icon - Single character or emoji used as button label.
     * @param {String} tooltip - Tooltip text shown on hover.
     * @param {Func} callback - Called with no arguments when clicked.
     */
    AddToolbarButton(icon, tooltip, callback) {
        btnX := this.toolbarStartX
        btnY := this.toolbarY
        btnSize := this.layout["toolbarIconSize"]

        btnBg := this.gui.AddText("x" . btnX . " y" . btnY . " w" . btnSize . " h" . btnSize . " BackgroundTrans")
        btnIcon := this.gui.AddText("x" . btnX . " y" . btnY . " w" . btnSize . " h" . btnSize . " Center BackgroundTrans c" . Format("{:06X}", this.colors["menuBarText"]), icon)
        btnIcon.SetFont("s10")

        btnHit := this.gui.AddText("x" . btnX . " y" . btnY . " w" . btnSize . " h" . btnSize . " BackgroundTrans")
        btnHit.OnEvent("Click", (*) => (callback(), 0))
        tipBuf := this._AddToolTip(btnHit, tooltip)

        btnData := Map(
            "bg", btnBg,
            "icon", btnIcon,
            "hit", btnHit,
            "x", btnX,
            "y", btnY,
            "tooltip", tooltip,
            "tipBuf", tipBuf
        )

        this.toolbarBtns.Push(btnData)

        this.toolbarStartX += btnSize + this.layout["toolbarButtonSpacing"]
    }

    AddToolbarSeparator() {
        btnX := this.toolbarStartX
        btnY := this.toolbarY
        btnSize := this.layout["toolbarIconSize"]

        this.gui.AddText("x" . btnX . " y" . (btnY + 1) . " w" . this.layout["toolbarSeparatorWidth"] . " h" . (btnSize - 2) . " Background" . Format("{:06X}", this.colors["toolbarBorder"]))
        this.toolbarStartX += 6
    }

    ShowPopupMenu(hPopup, x, *) {
        popupX := 0
        popupY := 0

        for item in this.menuItems {
            if item["popup"] = hPopup {
                ctrlRect := DM_RECT()
                DllCall("GetWindowRect", "Ptr", item["hitArea"].Hwnd, "Ptr", ctrlRect)

                popupX := ctrlRect.left   ; Left
                popupY := ctrlRect.bottom  ; Bottom

                item["label"].Opt("Background" . Format("{:06X}", this.colors["menuBarActive"]))
                labelRef := item["label"]
                SetTimer(() => (labelRef.Opt("BackgroundTrans"), 0), -200)
                break
            }
        }

        popupX += this.layout["popupOffsetX"]
        popupY += this.layout["popupOffsetY"]

        DllCall("TrackPopupMenu", "Ptr", hPopup, "UInt", 0x0000, "Int", popupX, "Int", popupY, "Int", 0, "Ptr", this.gui.Hwnd, "Ptr", 0)
    }

    OnMouseMove(wParam, lParam, msg, hwnd) {
        if hwnd != this.gui.Hwnd
            return

        x := lParam & 0xFFFF
        y := (lParam >> 16) & 0xFFFF

        if this.layout["showToolbar"] && y > this.layout["menuBarHeight"] && y <= (this.layout["menuBarHeight"] + this.layout["toolbarHeight"]) {
            this.HandleToolbarHover(x, y)
            return
        }

        if y > this.layout["menuBarHeight"] {
            if this.hoveredMenu != "" {
                this.ClearHover()
            }
            return
        }

        hoveredItem := ""
        for item in this.menuItems {
            if x >= item["x"] && x <= item["x"] + item["width"] {
                hoveredItem := item["name"]
                break
            }
        }

        if hoveredItem != this.hoveredMenu {
            this.ClearHover()
            if hoveredItem != "" {
                for item in this.menuItems {
                    if item["name"] = hoveredItem {
                        item["label"].Opt("Background" . Format("{:06X}", this.colors["menuBarHover"]))
                        this.hoveredMenu := hoveredItem
                        break
                    }
                }
            }
        }
    }

    HandleToolbarHover(x, y) {
        hoveredBtn := ""
        for btn in this.toolbarBtns {
            btnSize := this.layout["toolbarIconSize"]
            if x >= btn["x"] && x <= btn["x"] + btnSize && y >= btn["y"] && y <= btn["y"] + btnSize {
                hoveredBtn := btn
                break
            }
        }

        if hoveredBtn != this._lastHoveredBtn {
            for btn in this.toolbarBtns {
                btn["bg"].Opt("BackgroundTrans")
            }

            if hoveredBtn != "" {
                hoveredBtn["bg"].Opt("Background" . Format("{:06X}", this.colors["menuBarHover"]))
            }

            this._lastHoveredBtn := hoveredBtn
        }
    }

    ClearHover() {
        for item in this.menuItems {
            item["label"].Opt("BackgroundTrans")
        }
        this.hoveredMenu := ""
    }

    /**
     * Measures a label's pixel width using the control's own selected font.
     * @param {Gui.Text} ctrl - The label control (font already applied).
     * @param {String} text - Text to measure.
     * @returns {Integer} Width in pixels.
     */
    _MeasureLabelWidth(ctrl, text) {
        hdc := DllCall("GetDC", "Ptr", ctrl.Hwnd, "Ptr")
        hFont := SendMessage(0x31, 0, 0, ctrl)  ; WM_GETFONT
        old := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        sz := DM_SIZE()
        DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", text, "Int", StrLen(text), "Ptr", sz.Ptr)
        if old
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old, "Void")
        DllCall("ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", hdc, "Void")
        return sz.cx
    }

    ApplyDarkThemeToPopup(hPopup) {
        ; MIM_BACKGROUND does NOT transfer brush ownership — the menu keeps the
        ; raw handle for its whole life. So this brush must NOT come from
        ; DarkTheme's value cache: SetColor/SetPalette flush that cache wholesale
        ; (_FlushGdiCache DeleteObjects every entry), which left every live HMENU
        ; painting from freed GDI memory after a palette swap. One brush per menu
        ; bar, owned here, rebuilt in OnPaletteChanged, freed in Destroy.
        if !this._popupBrush {
            this._popupBrush := DllCall("gdi32\CreateSolidBrush",
                "UInt", DarkTheme.RGBtoBGR(this.colors["popupBg"]), "Ptr")
        }
        mi := DM_MENUINFO()
        mi.cbSize  := mi.Size
        mi.fMask   := 0x10  ; MIM_BACKGROUND
        mi.hbrBack := this._popupBrush
        DllCall("SetMenuInfo", "Ptr", hPopup, "Ptr", mi.Ptr, "Void")
    }

    /**
     * Palette-change hook. Rebuilds the popup brush and re-points every live
     * popup at the new handle before releasing the old one — menus hold the
     * handle by value, so the order matters.
     * @param {Map} colors - The live DarkTheme.Colors map
     */
    OnPaletteChanged(colors) {
        if this._popupBgDefault
            this.colors["popupBg"] := colors["Header"]
        old := this._popupBrush
        this._popupBrush := 0
        for item in this.menuItems
            this.ApplyDarkThemeToPopup(item["popup"])
        if old
            DllCall("DeleteObject", "Ptr", old, "Void")
    }

    /**
     * Lazily creates this menu bar's dark-themed tooltip window
     * (`tooltips_class32`, TTS_ALWAYSTIP | TTS_NOPREFIX).
     * @returns {Ptr} Tooltip window handle
     */
    _EnsureToolTipWindow() {
        if this.HasProp("_hTip") && this._hTip
            return this._hTip
        static WS_EX_TOPMOST := 0x8
        static WS_POPUP := 0x80000000
        static TTS_ALWAYSTIP := 0x01, TTS_NOPREFIX := 0x02
        static CW_USEDEFAULT := 0x80000000
        this._hTip := DllCall("CreateWindowEx", "UInt", WS_EX_TOPMOST, "Str", "tooltips_class32", "Ptr", 0,
            "UInt", WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX,
            "Int", CW_USEDEFAULT, "Int", CW_USEDEFAULT, "Int", CW_USEDEFAULT, "Int", CW_USEDEFAULT,
            "Ptr", this.gui.Hwnd, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
        if this._hTip
            DarkToolTip.Apply(this._hTip)
        return this._hTip
    }

    /**
     * Registers hover tooltip text for a control (TTM_ADDTOOLW with
     * TTF_IDISHWND | TTF_SUBCLASS — comctl32 handles all mouse tracking).
     * @param {Gui.Control} ctrl - Control the tooltip attaches to
     * @param {String} text - Tooltip text
     * @returns {Buffer} Text buffer; caller must keep it alive with the button
     */
    _AddToolTip(ctrl, text) {
        static TTM_ADDTOOLW := 0x0432
        static TTF_IDISHWND := 0x01, TTF_SUBCLASS := 0x10
        hTip := this._EnsureToolTipWindow()
        buf := Buffer(StrPut(text, "UTF-16"), 0)
        StrPut(text, buf, "UTF-16")
        if hTip {
            ti := DM_TOOLINFOW()
            ti.cbSize   := ti.Size
            ti.uFlags   := TTF_IDISHWND | TTF_SUBCLASS
            ti.hwnd     := this.gui.Hwnd
            ti.uId      := ctrl.Hwnd
            ti.lpszText := buf.Ptr
            SendMessage(TTM_ADDTOOLW, 0, ti.Ptr, hTip)
        }
        return buf
    }

    /**
     * Unregisters the mouse move handler and destroys popup menu handles.
     * Call before disposing the parent {@link DarkGui}.
     */
    Destroy() {
        OnMessage(0x200, this._onMouseMove, 0)
        DarkTheme.OffThemeChanged(this._onPaletteChanged)
        ; Unhook the Size handler only while the window still exists —
        ; OnEvent on a destroyed Gui throws, and the handler dies with it.
        if DllCall("IsWindow", "Ptr", this._guiHwnd)
            this.gui.OnEvent("Size", this._onParentSize, 0)
        for item in this.menuItems {
            if item.Has("popup")
                DllCall("DestroyMenu", "Ptr", item["popup"], "Void")
        }
        ; After the menus are gone nothing references the brush any more.
        if this._popupBrush {
            DllCall("DeleteObject", "Ptr", this._popupBrush, "Void")
            this._popupBrush := 0
        }
        if this.HasProp("_hTip") && this._hTip {
            DllCall("DestroyWindow", "Ptr", this._hTip, "Void")
            this._hTip := 0
        }
    }

    /**
     * Returns the Y offset where content should begin below the menu/toolbar.
     *
     * @returns {Integer} Pixel offset accounting for menu bar and optional toolbar.
     */
    GetContentY() {
        return this.totalHeight
    }
}

/**
 * Dark-themed Gui class. All controls added via Add() are automatically styled.
 * Use "+Accent" option for accent-colored buttons.
 * Backward compatible: `_Dark` is an alias for `DarkGui`.
 */
class DarkGui extends Gui {
    /** @type {Map} Tracks dark-styled controls: hwnd -> controlType */
    _darkHwnds := Map()
    /** @type {Integer} HWND cached at construction for safe teardown */
    _hwnd := 0

    /**
     * Creates a new dark-themed GUI window.
     * @param {String} options - Gui options
     * @param {String} title - Window title
     */
    __New(options := "", title := A_ScriptName) {
        super.__New(options, title)
        ; Cache the HWND: Gui.Prototype.Hwnd throws "Gui has no window" once the
        ; window is destroyed, which can occur before __Delete runs at app exit.
        ; Teardown bookkeeping uses this cached value instead of the getter.
        this._hwnd := this.Hwnd
        DarkTheme.AddRef()
        DarkTheme.Windows[this._hwnd] := true
        this.BackColor := DarkTheme.Colors["Background"]
        this.SetFont("s9", "Segoe UI")
        DarkTitleBar.Apply(this.Hwnd)
        DarkMenu.Apply()
        DarkWindowProc.Install(this.Hwnd)
        DarkGui._ApplyWin11Frame(this.Hwnd)
    }

    /** Win11: sets title bar, caption text, and border colors to match the theme. */
    static _ApplyWin11Frame(hwnd) {
        if VerCompare(A_OSVersion, "10.0.22000") < 0
            return
        bgBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"])
        borderBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"])
        ; Caption text must follow the palette, not assume dark: a window
        ; constructed while the Light preset is active got white-on-light until
        ; the next SetPalette. Matches _SyncWindowFrames.
        captionText := DarkTheme.IsDarkPalette() ? 0xFFFFFF : 0x000000
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 35, "UInt*", bgBGR, "Int", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 36, "UInt*", captionText, "Int", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 34, "UInt*", borderBGR, "Int", 4)
    }

    /**
     * Handler registry: maps a lowercase control-type name to a handler object
     * with `Apply(gui, ctrl, options)` and optional `Remove(hwnd)`. Registered
     * types are styled by {@link DarkGui#Add} without editing this class —
     * user code can plug in its own dark control implementations.
     * @type {Map}
     */
    static Handlers := Map()

    /** @type {Map} hwnd -> callback(hwnd, newDpi, suggestedRect) for WM_DPICHANGED */
    static DpiChangedCallbacks := Map()

    /**
     * Registers a per-monitor DPI-change callback for this window. The window
     * is already moved to the OS-suggested rect before the callback runs; use
     * it to re-Scale and reposition controls (`DarkTheme.Scale(px, hwnd)`).
     * Fires only in per-monitor-DPI-aware processes.
     * @param {Func} callback - `callback(hwnd, newDpi, suggestedRect)`
     */
    OnDpiChanged(callback) => DarkGui.DpiChangedCallbacks[this._hwnd] := callback

    /**
     * Registers a custom dark-styling handler for a control type.
     * @param {String} controlType - Type name as passed to Add() (e.g. "Custom")
     * @param {Object} handler - Object with Apply(gui, ctrl, options) and optional Remove(hwnd)
     */
    static Register(controlType, handler) {
        if !HasMethod(handler, "Apply")
            throw ValueError("DarkGui.Register: handler must have an Apply(gui, ctrl, options) method", -1)
        this.Handlers[StrLower(controlType)] := handler
    }

    /**
     * Retrofits dark mode onto a plain Gui, in place, and keeps it dark: the
     * window frame, menus and WM_CTLCOLOR proc are installed, every control
     * already on the window is styled, AND `Add` plus every `AddXxx` shorthand
     * are overridden on the instance so controls added *afterwards* are styled
     * automatically too. Returns the same Gui, so the whole thing is one line:
     *
     *     myGui := DarkGui.Attach(Gui("+Resize", "My App"))
     *     myGui.AddButton("x10 y10 w80 h28", "OK")   ; already dark
     *
     * The shorthands each need their own override: they are built-ins that do
     * NOT route through Gui.Add, so overriding Add alone would miss them.
     *
     * Idempotent — attaching twice is a no-op, and passing a {@link DarkGui}
     * (which already styles its adds) just returns it untouched.
     *
     * Best-effort vs. a real DarkGui: Radio keeps its native themed text
     * rendering rather than the split label/hitbox treatment. Teardown is not
     * automatic (a plain Gui has no DarkGui.__Delete); call
     * {@link DarkGui.Detach} for early cleanup, otherwise comctl32 unhooks the
     * subclasses when the window is destroyed.
     *
     * @param {Gui} owner - Existing Gui instance to dark-theme in place
     * @returns {Gui} The same instance, now dark and self-styling
     */
    static Attach(owner) {
        if HasProp(owner, "_darkHwnds")
            return owner
        DarkTheme.AddRef()
        DarkTheme.Windows[owner.Hwnd] := true
        owner._darkHwnds := Map()
        owner._darkHwnd := owner.Hwnd
        owner.BackColor := DarkTheme.Colors["Background"]
        DarkTitleBar.Apply(owner.Hwnd)
        DarkMenu.Apply()
        DarkWindowProc.Install(owner.Hwnd)
        DarkGui._ApplyWin11Frame(owner.Hwnd)

        ; Wrap in a closure rather than handing the static Func straight to Call:
        ; a bare `{ Call: DarkGui._AddStyled }` is invoked WITHOUT the object, so
        ; every argument shifts left and the control type lands in the Gui slot.
        owner.DefineProp("Add", { Call: (self, controlType, options := "", content?)
            => DarkGui._AddStyled(self, controlType, options, content?) })
        for name, controlType in DarkGui._Shorthands()
            owner.DefineProp(name, { Call: DarkGui._ShorthandFor(controlType) })

        for hwnd, ctrl in owner
            DarkGui._ApplyType(owner, ctrl)
        return owner
    }

    /**
     * Tears down an attached Gui early: removes every control subclass tracked
     * during {@link DarkGui.Attach} and releases the theme reference. Only
     * needed when the Gui outlives its need for dark mode; window destruction
     * unhooks the subclasses anyway.
     * @param {Gui} owner - A Gui previously passed to Attach
     */
    static Detach(owner) {
        if !HasProp(owner, "_darkHwnds")
            return
        DarkGui._Teardown(owner, owner._darkHwnd)
        DarkTheme.Release()
    }

    /** @returns {Map} AddXxx shorthand name -> control type it creates. */
    static _Shorthands() {
        m := Map()
        m["AddButton"] := "Button"
        m["AddCheckBox"] := "CheckBox"
        m["AddComboBox"] := "ComboBox"
        m["AddDateTime"] := "DateTime"
        m["AddDDL"] := "DropDownList"
        m["AddDropDownList"] := "DropDownList"
        m["AddEdit"] := "Edit"
        m["AddGroupBox"] := "GroupBox"
        m["AddHotkey"] := "Hotkey"
        m["AddLink"] := "Link"
        m["AddListBox"] := "ListBox"
        m["AddListView"] := "ListView"
        m["AddMonthCal"] := "MonthCal"
        m["AddProgress"] := "Progress"
        m["AddRadio"] := "Radio"
        m["AddSlider"] := "Slider"
        m["AddStatusBar"] := "StatusBar"
        m["AddTab"] := "Tab"
        m["AddTab2"] := "Tab2"
        m["AddTab3"] := "Tab3"
        m["AddText"] := "Text"
        m["AddTreeView"] := "TreeView"
        m["AddUpDown"] := "UpDown"
        return m
    }

    /** Builds the instance-level override for one AddXxx shorthand. */
    static _ShorthandFor(controlType) {
        return (self, options := "", content?) => DarkGui._AddStyled(self, controlType, options, content?)
    }

    /**
     * Creates a control through the native Gui.Add and dark-styles it. The
     * single create path behind DarkGui#Add, the AddXxx forwarders, and the
     * instance overrides that {@link DarkGui.Attach} installs — reached through
     * `Gui.Prototype.Add` rather than `super.Add`, which is what lets it serve a
     * plain attached Gui as well as a DarkGui.
     *
     * @param {Gui} owner - Owning Gui
     * @param {String} controlType - Type as passed to Add ("Button", "DDL", ...)
     * @param {String} [options=""] - Control options; "+Accent" selects the accent button
     * @param {*} [content] - Control content (text, items array, ...)
     * @returns {Gui.Control} The created, styled control
     */
    static _AddStyled(owner, controlType, options := "", content?) {
        ; _ApplyType reads the ORIGINAL options (for "+Accent", "Checked", an
        ; explicit "c<hex>"), so keep them before "+Accent" is stripped for the
        ; native Add and before any creation-time default is appended.
        raw := options
        if InStr(options, "+Accent")
            options := StrReplace(options, "+Accent", "")
        if StrLower(controlType) = "radio"
            return DarkGui._AddRadio(owner, options, content?)
        options := DarkGui._DefaultFontColor(controlType, options)
        ; The owning-Gui parameter is NOT named `gui`: identifiers are
        ; case-insensitive, so that name shadows the global Gui class and
        ; `Gui.Prototype` would resolve to the parameter instead.
        ctrl := Gui.Prototype.Add.Call(owner, controlType, options, content?)
        DarkGui._ApplyType(owner, ctrl, raw, content?)
        return ctrl
    }

    /** Appends a palette Font color to types that render their own text and
     *  would otherwise inherit the system default, unless the caller set one. */
    static _DefaultFontColor(controlType, options) {
        switch StrLower(controlType) {
            case "text", "listview", "link":
                if !RegExMatch(options, "i)\bc[0-9A-Fa-f]+\b|\bcWhite\b|\bcBlack\b")
                    options .= " c" Format("{:X}", DarkTheme.Colors["Font"])
        }
        return options
    }

    /** Records a control against its owning Gui so teardown can reach it.
     *  Silently skips Guis with no tracking map (a bare Gui.Add caller). */
    static _Track(owner, hwnd, label) {
        if HasProp(owner, "_darkHwnds")
            owner._darkHwnds[hwnd] := label
    }

    /**
     * Per-type dark styling — the one place that knows how each control type is
     * darkened. Shared by the create path ({@link DarkGui._AddStyled}) and the
     * retrofit path ({@link DarkGui.Attach}), so the two cannot drift apart the
     * way the old parallel switches did; retrofit also gets the `_darkHwnds`
     * tracking it previously missed.
     *
     * Switches on `ctrl.Type`, which normalizes the aliases the caller may have
     * used ("DropDownList" and "DDL" both report "DDL"). Tab/Tab2/Tab3 stay
     * distinct, so all three are listed.
     *
     * @param {Gui} owner - Owning Gui
     * @param {Gui.Control} ctrl - Control to style
     * @param {String} [options=""] - Original creation options ("" when retrofitting)
     * @param {*} [content] - Original creation content
     * @returns {Boolean} true when the type was recognised and styled
     */
    static _ApplyType(owner, ctrl, options := "", content?) {
        switch ctrl.Type, false {
            case "Text":
                ; Skip when the caller pinned a color — don't stomp "cRed".
                if !RegExMatch(options, "i)\bc[0-9A-Fa-f]+\b|\bcWhite\b|\bcBlack\b")
                    ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
            case "Button":
                ctrl.SetDarkMode(InStr(options, "+Accent") ? "accent" : "default")
                DarkGui._Track(owner, ctrl.Hwnd, "Button")
            case "CheckBox":
                _DarkCheckBox.ApplyDarkMode(ctrl)
            case "Radio":
                ; Reached only when retrofitting; the create path builds the
                ; split radio + label pair in _AddRadio instead.
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
            case "Edit":
                ctrl.SetDarkMode()
                _DarkCaret.Apply(ctrl.Hwnd)
                DarkGui._Track(owner, ctrl.Hwnd, "Edit")
            case "DDL":
                DarkGui._ThemeDropDown(ctrl)
            case "ComboBox":
                ctrl.SetDarkMode()
                DarkGui._Track(owner, ctrl.Hwnd, "ComboBox")
            case "ListView":
                ctrl.SetDarkMode()
                DarkGui._Track(owner, ctrl.Hwnd, "ListView")
            case "TreeView":
                ctrl.SetDarkMode()
                if RegExMatch(options, "i)\bChecked\b")
                    _DarkTreeCheckboxes.Apply(ctrl)
            case "ListBox", "Progress":
                ctrl.SetDarkMode()
            case "Slider":
                ctrl.SetDarkMode()
                DarkGui._Track(owner, ctrl.Hwnd, "Slider")
            case "GroupBox":
                _DarkGroupBox.ApplyDarkMode(ctrl)
                DarkGui._Track(owner, ctrl.Hwnd, "GroupBox")
            case "Tab", "Tab2", "Tab3":
                _DarkTab.ApplyDarkMode(ctrl)
                DarkGui._Track(owner, ctrl.Hwnd, "Tab3")
            case "UpDown":
                _DarkUpDown.ApplyDarkMode(ctrl)
                DarkGui._Track(owner, ctrl.Hwnd, "UpDown")
            case "StatusBar":
                _DarkStatusBar.ApplyDarkMode(ctrl)
                ; Re-apply creation text through the owner-draw path so it renders dark
                if IsSet(content) && content != ""
                    ctrl.SetText(content)
                DarkGui._Track(owner, ctrl.Hwnd, "StatusBar")
            case "Link":
                _DarkLink.ApplyDarkMode(ctrl)
                DarkGui._Track(owner, ctrl.Hwnd, "Link")
            case "MonthCal":
                _DarkMonthCal.ApplyDarkMode(ctrl)
                DarkGui._Track(owner, ctrl.Hwnd, "MonthCal")
            case "DateTime":
                _DarkDateTime.ApplyDarkMode(ctrl)
                DarkGui._Track(owner, ctrl.Hwnd, "DateTime")
            case "Hotkey":
                _DarkHotkey.ApplyDarkMode(ctrl)
                DarkGui._Track(owner, ctrl.Hwnd, "Hotkey")
            default:
                key := StrLower(ctrl.Type)
                if !DarkGui.Handlers.Has(key)
                    return false
                DarkGui.Handlers[key].Apply(owner, ctrl, options)
                DarkGui._Track(owner, ctrl.Hwnd, key)
        }
        return true
    }

    /**
     * Shared DropDownList/dropdown theming: dark-mode flag, CFD theme, font
     * color, border removal, and dark dropdown-list registration. Used by the
     * DDL branch of Add() and by {@link DarkGui.Attach}.
     */
    static _ThemeDropDown(ctrl) {
        static CB_GETCOMBOBOXINFO := 0x0164
        DarkTheme.AllowDarkMode(ctrl.Hwnd)
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)
        ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
        DarkTheme.RemoveBorder(ctrl.Hwnd)
        cbi := DM_COMBOBOXINFO()
        cbi.cbSize := cbi.Size
        if DllCall("SendMessage", "Ptr", ctrl.Hwnd, "UInt", CB_GETCOMBOBOXINFO, "Ptr", 0, "Ptr", cbi.Ptr) {
            if cbi.hwndList {
                DllCall("uxtheme\SetWindowTheme", "Ptr", cbi.hwndList, "Str", "DarkMode_Explorer", "Ptr", 0)
                DarkWindowProc.ComboDropdowns[cbi.hwndList] := true
            }
        }
    }

    /**
     * Cleans up all dark mode resources for this GUI.
     * Removes subclasses from all tracked controls, clears stale entries from
     * {@link DarkWindowProc} tracking maps, and calls {@link DarkTheme.Release}.
     */
    __Delete() {
        DarkGui._Teardown(this, this._hwnd)
        DarkTheme.Release()
    }

    /**
     * Shared teardown for both lifetimes: {@link DarkGui#__Delete} and
     * {@link DarkGui.Detach}. Removes every tracked control subclass, sweeps
     * dead hwnds out of the {@link DarkWindowProc} maps, and drops this window's
     * registrations. Does NOT call {@link DarkTheme.Release} — the caller owns
     * the refcount, since Detach and __Delete each release exactly once.
     *
     * @param {Gui} owner - The Gui being torn down
     * @param {Ptr} hwnd - Cached window handle; the live getter throws once the
     *   window is destroyed, which can happen before __Delete runs at exit.
     */
    static _Teardown(owner, hwnd) {
        ; Remove subclasses from all tracked dark controls
        for ctrlHwnd, ctrlType in owner._darkHwnds {
            switch ctrlType, false {
                case "ListView": _DarkListView.Remove(ctrlHwnd)
                case "Button":   _DarkButton.Remove(ctrlHwnd)
                case "ComboBox": _DarkComboBox.Remove(ctrlHwnd)
                case "Slider":   _DarkSlider.Remove(ctrlHwnd)
                case "Edit":      _DarkCaret.Remove(ctrlHwnd)
                case "GroupBox":  _DarkGroupBox.Remove(ctrlHwnd)
                case "Tab", "Tab2", "Tab3": _DarkTab.Remove(ctrlHwnd)
                case "UpDown":    _DarkUpDown.Remove(ctrlHwnd)
                case "StatusBar": _DarkStatusBar.Remove(ctrlHwnd)
                case "Link":      _DarkLink.Remove(ctrlHwnd)
                case "MonthCal":  _DarkMonthCal.Remove(ctrlHwnd)
                case "DateTime":  _DarkDateTime.Remove(ctrlHwnd)
                case "Hotkey":    _DarkHotkey.Remove(ctrlHwnd)
                default:
                    if DarkGui.Handlers.Has(ctrlType) && HasMethod(DarkGui.Handlers[ctrlType], "Remove")
                        DarkGui.Handlers[ctrlType].Remove(ctrlHwnd)
            }
        }
        owner._darkHwnds.Clear()

        ; DarkScrollbar instances live only in their static map (the host is a
        ; plain Text control, never in _darkHwnds); sweep the ones this gui owns
        ; so their sync timers stop with the window.
        for sbHwnd, sb in DarkScrollbar.Instances.Clone()
            if sb.gui = owner
                sb.Destroy()

        ; Clean stale entries from DarkWindowProc tracking maps. The loop variable
        ; is NOT named `map`: AHK identifiers are case-insensitive, so that would
        ; shadow the built-in Map class for this whole scope.
        for tracker in [DarkWindowProc.RadioTextControls, DarkWindowProc.MenuBarControls, DarkWindowProc.ComboDropdowns, DarkWindowProc.ListViewControls, DarkWindowProc.StaticColors] {
            stale := []
            for staleHwnd, _ in tracker
                if !DllCall("IsWindow", "Ptr", staleHwnd)
                    stale.Push(staleHwnd)
            for staleHwnd in stale
                tracker.Delete(staleHwnd)
        }

        DarkTheme.Windows.Delete(hwnd)
        if DarkGui.DpiChangedCallbacks.Has(hwnd)
            DarkGui.DpiChangedCallbacks.Delete(hwnd)
        DarkWindowProc.Uninstall(hwnd)
    }

    /**
     * Adds a control with automatic dark mode styling.
     *
     * Thin wrapper over {@link DarkGui._AddStyled}, which also backs the AddXxx
     * forwarders below and the instance overrides {@link DarkGui.Attach}
     * installs — one create path, one styling switch, no drift.
     *
     * @param {String} controlType - Control type (`"Button"`, `"Edit"`, `"ListView"`, etc.).
     * @param {String} [options = ""] - Control options. Include `"+Accent"` for blue buttons.
     * @param {*} [content] - Control content (text, items array, etc.).
     * @returns {Gui.Control} The created and dark-styled control.
     */
    Add(controlType, options := "", content?) => DarkGui._AddStyled(this, controlType, options, content?)

    ; Native Gui.AddButton/AddEdit/... shorthands bind to Gui.Prototype methods
    ; and would silently bypass the dark Add() override; forward every styled
    ; type so shorthand callers get identical treatment.
    AddButton(options := "", text?) => this.Add("Button", options, text?)
    AddCheckBox(options := "", text?) => this.Add("CheckBox", options, text?)
    AddComboBox(options := "", items?) => this.Add("ComboBox", options, items?)
    AddDateTime(options := "", dateTime?) => this.Add("DateTime", options, dateTime?)
    AddDDL(options := "", items?) => this.Add("DropDownList", options, items?)
    AddDropDownList(options := "", items?) => this.Add("DropDownList", options, items?)
    AddEdit(options := "", text?) => this.Add("Edit", options, text?)
    AddGroupBox(options := "", text?) => this.Add("GroupBox", options, text?)
    AddHotkey(options := "", value?) => this.Add("Hotkey", options, value?)
    AddLink(options := "", text?) => this.Add("Link", options, text?)
    AddListBox(options := "", items?) => this.Add("ListBox", options, items?)
    AddListView(options := "", titles?) => this.Add("ListView", options, titles?)
    AddMonthCal(options := "", dateTime?) => this.Add("MonthCal", options, dateTime?)
    AddProgress(options := "", value?) => this.Add("Progress", options, value?)
    AddRadio(options := "", text?) => this.Add("Radio", options, text?)
    AddSlider(options := "", value?) => this.Add("Slider", options, value?)
    AddStatusBar(options := "", text?) => this.Add("StatusBar", options, text?)
    AddTab(options := "", pages?) => this.Add("Tab", options, pages?)
    AddTab2(options := "", pages?) => this.Add("Tab2", options, pages?)
    AddTab3(options := "", pages?) => this.Add("Tab3", options, pages?)
    AddText(options := "", text?) => this.Add("Text", options, text?)
    AddTreeView(options := "", text?) => this.Add("TreeView", options, text?)
    AddUpDown(options := "", value?) => this.Add("UpDown", options, value?)

    /** Manually selects a radio and unchecks all others in its group */
    static _SelectRadio(selected, group) {
        for r in group
            r.Value := (r = selected)
    }

    /**
     * Sets a control's UIA/MSAA accessible name via IAccPropServices —
     * lets screen readers announce controls whose visual label lives in a
     * separate control (split radios). Best-effort: returns false on failure.
     * @param {Ptr} hwnd - Control handle
     * @param {String} name - Accessible name
     * @returns {Boolean} true when the annotation was set
     */
    static _SetAccName(hwnd, name) {
        static CLSID_AccPropServices := "{B5F8350B-0548-48B1-A6EE-88BD00B4A5E7}"
        static IID_IAccPropServices := "{6E26E776-04F0-495D-80E4-3330352E3169}"
        static PROPID_ACC_NAME := "{608D3DF8-8128-4AA7-A428-F55E49267291}"
        static OBJID_CLIENT := 0xFFFFFFFC
        try {
            svc := ComObject(CLSID_AccPropServices, IID_IAccPropServices)
            propGuid := Buffer(16, 0)
            DllCall("ole32\CLSIDFromString", "Str", PROPID_ACC_NAME, "Ptr", propGuid)
            ; vtable 7 = SetHwndPropStr(hwnd, idObject, idChild, idProp, str)
            ComCall(7, svc, "Ptr", hwnd, "UInt", OBJID_CLIENT, "UInt", 0, "Ptr", propGuid, "WStr", name)
            return true
        } catch Error {
            return false
        }
    }

    /**
     * Internal: Adds a Radio with a separate Text label so the caption can be
     * dark-styled (a native Radio renders its own caption in a color we cannot
     * reach). Static and gui-parameterised so an attached plain Gui gets the
     * same treatment as a DarkGui; the native Add is reached through
     * Gui.Prototype rather than `super`, which a static method has no access to.
     * @param {Gui} owner - Owning Gui
     * @param {String} options - Radio options; "Group" starts a new group
     * @param {String} [text] - Label text
     * @returns {Gui.Radio} The radio, with .Text proxied to its label
     */
    static _AddRadio(owner, options, text?) {
        static SM_CXMENUCHECK := 71
        static radioW := DllCall("GetSystemMetrics", "Int", SM_CXMENUCHECK)
        nativeAdd := Gui.Prototype.Add

        ; Track radio groups - new group starts with +Group or first radio
        isNewGroup := RegExMatch(options, "i)\bGroup\b") || !owner.HasOwnProp("_radioGroup")
        if isNewGroup
            owner._radioGroup := []
        group := owner._radioGroup

        radio := nativeAdd.Call(owner, "Radio", options " +0x4000000", "")
        group.Push(radio)

        ; SS_NOTIFY (0x100) enables click events on the text label. Font color
        ; comes from the palette — a hardcoded cFFFFFF rendered the label
        ; white-on-white under ApplyPreset("Light").
        fontOpt := " c" Format("{:X}", DarkTheme.Colors["Font"])
        if !InStr(options, "right") {
            txt := nativeAdd.Call(owner, "Text", "xp+" (radioW + 8) " yp+2 HP-4 +0x4000300" fontOpt, text?)
            ; The radio's caption is empty, but it still spans whatever width the
            ; caller asked for — so the keyboard focus rectangle would outline
            ; that whole empty run, detached from the label beside it. Shrink the
            ; control to its glyph so the rect hugs the button. Clicking the
            ; caption still selects: the label carries its own Click handler.
            ; Skipped for "right" (BS_RIGHTBUTTON draws the glyph at the control's
            ; right edge, so narrowing would drag it away from the label).
            radio.Move(, , radioW + 4)
        } else
            txt := nativeAdd.Call(owner, "Text", "xp+8 yp+2 HP-4 +0x4000300" fontOpt, text?)

        DarkWindowProc.RadioTextControls[txt.Hwnd] := true

        static SWP_NOSIZE := 0x1, SWP_NOMOVE := 0x2, SWP_NOACTIVATE := 0x10
        ; New controls are created at the BOTTOM of the sibling Z order, and this
        ; radio carries WS_CLIPSIBLINGS — inside a GroupBox (a higher sibling) its
        ; painting would be clipped to nothing. Raise the radio to the top like
        ; its label (label raised after, so it stays above the radio).
        DllCall("SetWindowPos", "Ptr", radio.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "UInt", SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE, "Void")
        DllCall("SetWindowPos", "Ptr", txt.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "UInt", SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | 0x40, "Void")

        DllCall("uxtheme\SetWindowTheme", "Ptr", radio.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

        ; The radio's own caption is empty (the separate Text control renders it),
        ; which leaves UIA/Narrator with a nameless control — annotate it.
        DarkGui._SetAccName(radio.Hwnd, text ?? "")

        radio.TextCtrl := txt
        radio.DefineProp("Text", {
            Get: (this) => this.TextCtrl.Text,
            Set: (this, value) => this.TextCtrl.Text := value
        })

        ; Manual radio group management - text controls break native auto-grouping
        radio.OnEvent("Click", (*) => (DarkGui._SelectRadio(radio, group), 0))
        txt.OnEvent("Click", (*) => (DarkGui._SelectRadio(radio, group), 0))

        return radio
    }
}

/**
 * Backward-compatibility alias — `_Dark(...)` constructs a {@link DarkGui}.
 * Declared as an (empty) subclass rather than a `_Dark := DarkGui` global
 * assignment so that merely including this file has no auto-execute side effect.
 */
class _Dark extends DarkGui {
}

; Run standalone showcase when executed directly, skip when #Included as library.
; Held in a script-lifetime variable so the instance isn't reliant on OnMessage
; bindings to stay alive.
if A_LineFile = A_ScriptFullPath
    _darkShowcase := DarkModeShowcase()

class DarkModeShowcase {
    controls := Map()
    _altTheme := false

    static CMD_NEW := 101, CMD_OPEN := 102, CMD_SAVE := 103, CMD_EXIT := 104
    static CMD_UNDO := 201, CMD_CUT := 202, CMD_COPY := 203, CMD_PASTE := 204
    static CMD_THEME := 301, CMD_ABOUT := 302
    static CMD_PRESET_DEFAULT := 311, CMD_PRESET_OLED := 312
    static CMD_PRESET_SLATE := 313, CMD_PRESET_LIGHT := 314
    static CMD_PRESET_BLUE := 315

    __New() {
        this.gui := DarkGui("+Resize", "Modular Dark Mode System")
        this.BuildMenuBar()
        this.BuildLayout()
        this.BindEvents()
        ; Re-color creation-time font colors when the palette swaps (presets).
        DarkTheme.OnThemeChanged(this.OnPaletteChanged.Bind(this))
        this.gui.Show("w880 h558")
    }

    BuildMenuBar() {
        this.menuBar := DarkMenuBar(this.gui, Map("showToolbar", false))
        this.menuOffset := this.menuBar.totalHeight

        fileMenu := this.menuBar.AddMenu("File")
        fileMenu.Item("New",     DarkModeShowcase.CMD_NEW,  "Ctrl+N")
        fileMenu.Item("Open...", DarkModeShowcase.CMD_OPEN, "Ctrl+O")
        fileMenu.Item("Save",    DarkModeShowcase.CMD_SAVE, "Ctrl+S")
        fileMenu.Sep()
        fileMenu.Item("Exit",    DarkModeShowcase.CMD_EXIT)

        editMenu := this.menuBar.AddMenu("Edit")
        editMenu.Item("Undo",  DarkModeShowcase.CMD_UNDO,  "Ctrl+Z")
        editMenu.Sep()
        editMenu.Item("Cut",   DarkModeShowcase.CMD_CUT,   "Ctrl+X")
        editMenu.Item("Copy",  DarkModeShowcase.CMD_COPY,  "Ctrl+C")
        editMenu.Item("Paste", DarkModeShowcase.CMD_PASTE, "Ctrl+V")

        viewMenu := this.menuBar.AddMenu("View")
        viewMenu.Item("Toggle Accent", DarkModeShowcase.CMD_THEME)
        viewMenu.Sep()
        viewMenu.Item("Preset: Default", DarkModeShowcase.CMD_PRESET_DEFAULT)
        viewMenu.Item("Preset: OLED",    DarkModeShowcase.CMD_PRESET_OLED)
        viewMenu.Item("Preset: Slate",   DarkModeShowcase.CMD_PRESET_SLATE)
        viewMenu.Item("Preset: Blue",    DarkModeShowcase.CMD_PRESET_BLUE)
        viewMenu.Item("Preset: Light",   DarkModeShowcase.CMD_PRESET_LIGHT)
        viewMenu.Sep()
        viewMenu.Item("About...",        DarkModeShowcase.CMD_ABOUT)

        OnMessage(0x0111, this.OnMenuCommand.Bind(this))
    }

    OnMenuCommand(wParam, lParam, msg, hwnd) {
        if hwnd != this.gui.Hwnd
            return
        cmdId := wParam & 0xFFFF
        if cmdId < 100
            return
        switch cmdId {
            case DarkModeShowcase.CMD_EXIT:  ExitApp()
            case DarkModeShowcase.CMD_ABOUT: MsgBox("DarkModeModular.ahk Showcase`nAll controls dark-themed automatically.", "About")
            case DarkModeShowcase.CMD_THEME:
                ; Live re-theme: SetColor recreates the cached brush and repaints
                ; every registered DarkGui window via DarkTheme.Redraw.
                this._altTheme := !this._altTheme
                DarkTheme.SetColor("Accent", this._altTheme ? 0xA855F7 : 0x0078D7)
                if this.controls.Has("status")
                    this.controls["status"].Text := "Status: Accent → " (this._altTheme ? "Purple" : "Blue")
            case DarkModeShowcase.CMD_PRESET_DEFAULT: this.ApplyPreset("Default")
            case DarkModeShowcase.CMD_PRESET_OLED:    this.ApplyPreset("OLED")
            case DarkModeShowcase.CMD_PRESET_SLATE:   this.ApplyPreset("Slate")
            case DarkModeShowcase.CMD_PRESET_BLUE:    this.ApplyPreset("Blue")
            case DarkModeShowcase.CMD_PRESET_LIGHT:   this.ApplyPreset("Light")
            default:
                if this.controls.Has("status")
                    this.controls["status"].Text := "Status: Menu command " cmdId " at " FormatTime(, "HH:mm:ss")
        }
    }

    BuildLayout() {
        y0 := this.menuOffset

        this.gui.Add("Text", "x20 y" (y0 + 15) " w200", "━ Text Input")
        this.controls["edit1"] := this.gui.Add("Edit", "x20 y" (y0 + 40) " w200 h25", "Single-line edit")
        this.controls["edit2"] := this.gui.Add("Edit", "x20 y" (y0 + 75) " w200 h68 +Multi", "Item A`nItem B`nItem C`nItem D`nItem E")

        this.gui.Add("Text", "x240 y" (y0 + 15) " w180", "━ Selection")
        this.controls["chk1"] := this.gui.Add("CheckBox", "x240 y" (y0 + 40) " w160 +Checked", "Feature enabled")
        this.controls["chk2"] := this.gui.Add("CheckBox", "x240 y" (y0 + 65) " w160", "Auto-save")
        ; GroupBox added before the radios so it stays under them in z-order.
        this.controls["radioGroup"] := this.gui.Add("GroupBox", "x232 y" (y0 + 90) " w180 h72", "Radio group")
        this.controls["rad1"] := this.gui.Add("Radio", "x244 y" (y0 + 110) " w160 +Checked", "Option A")
        this.controls["rad2"] := this.gui.Add("Radio", "x244 y" (y0 + 135) " w160", "Option B")

        this.gui.Add("Text", "x420 y" (y0 + 15) " w180", "━ Actions")
        this.controls["btn1"] := this.gui.Add("Button", "x420 y" (y0 + 40) " w80 h28", "Apply")
        this.controls["btn2"] := this.gui.Add("Button", "+Accent x510 y" (y0 + 40) " w80 h28", "OK")
        this.controls["btn3"] := this.gui.Add("Button", "x420 y" (y0 + 78) " w170 h28", "Reset All")

        this.splitMenu := Menu()
        this.splitMenu.Add("First action", (*) => this.controls["status"].Text := "Status: Split menu -> First action")
        this.splitMenu.Add("Second action", (*) => this.controls["status"].Text := "Status: Split menu -> Second action")
        this.splitMenu.Add("Third action", (*) => this.controls["status"].Text := "Status: Split menu -> Third action")
        this.controls["btnToggle"] := _DarkButton.AddToggle(this.gui, "x420 y" (y0 + 116) " w80 h28", "Toggle", false)
        this.controls["btnFlat"]   := _DarkButton.AddFlat(this.gui,   "x510 y" (y0 + 116) " w80 h28", "Flat")
        this.controls["btnIcon"]   := _DarkButton.AddIcon(this.gui,   "x420 y" (y0 + 154) " w80 h28", "Browse", "shell32.dll,4")
        this.controls["btnSplit"]  := _DarkButton.AddSplit(this.gui,  "x510 y" (y0 + 154) " w80 h28", "Split", this.splitMenu)

        this.gui.Add("Text", "x20 y" (y0 + 200) " w200", "━ Dropdowns && Progress")
        this.controls["combo"] := this.gui.Add("ComboBox", "x20 y" (y0 + 225) " w95", ["Option 1", "Option 2", "Option 3"])
        this.controls["ddl"] := this.gui.Add("DropDownList", "x120 y" (y0 + 225) " w100", ["Alpha", "Beta", "Gamma"])
        this.controls["slider"] := this.gui.Add("Slider", "x20 y" (y0 + 265) " w200 Range0-100", 50)
        this.controls["sliderLabel"] := this.gui.Add("Text", "x20 y" (y0 + 295) " w200", "Value: 50")
        this.controls["progress"] := this.gui.Add("Progress", "x20 y" (y0 + 320) " w200 h20", 50)

        this.gui.Add("Text", "x240 y" (y0 + 200) " w350", "━ ListView (with checkboxes)")
        this.controls["lv"] := this.gui.Add("ListView", "x240 y" (y0 + 225) " w350 h115 +Checked", ["Name", "Type", "Size"])
        this.controls["lv"].Add("", "Document.pdf", "PDF", "1.2 MB")
        this.controls["lv"].Add("", "Script.ahk", "AHK", "5 KB")
        this.controls["lv"].Add("", "Image.png", "PNG", "234 KB")
        this.controls["lv"].Add("", "Archive.zip", "ZIP", "12 MB")
        this.controls["lv"].Add("", "Video.mp4", "MP4", "156 MB")
        this.controls["lv"].Add("", "Music.mp3", "MP3", "8.4 MB")
        this.controls["lv"].Add("", "Database.db", "DB", "45 MB")
        this.controls["lv"].ModifyCol(1, 150)
        this.controls["lv"].ModifyCol(2, 90)
        this.controls["lv"].ModifyCol(3, 85)

        this.gui.Add("Text", "x20 y" (y0 + 355) " w200", "━ ListBox")
        this.controls["listbox"] := this.gui.Add("ListBox", "x20 y" (y0 + 380) " w200 h90", ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"])

        this.gui.Add("Text", "x240 y" (y0 + 355) " w350", "━ TreeView (with checkboxes)")
        this.controls["tv"] := this.gui.Add("TreeView", "x240 y" (y0 + 380) " w350 h83 Checked")
        p1 := this.controls["tv"].Add("Documents")
        this.controls["tv"].Add("Report.pdf", p1)
        this.controls["tv"].Add("Notes.txt", p1)
        p2 := this.controls["tv"].Add("Images")
        this.controls["tv"].Add("Photo.jpg", p2)

        ; Third column: the round-2 control coverage.
        this.gui.Add("Text", "x610 y" (y0 + 15) " w250", "━ Date / Time / Input")
        this.controls["dt"] := this.gui.Add("DateTime", "x610 y" (y0 + 40) " w250 h26")
        this.controls["hk"] := this.gui.Add("Hotkey", "x610 y" (y0 + 78) " w250 h26")

        this.gui.Add("Text", "x610 y" (y0 + 116) " w250", "━ Tabs")
        tab := this.controls["tab"] := this.gui.Add("Tab3", "x610 y" (y0 + 141) " w250 h120", ["General", "Advanced"])
        tab.UseTab(1)
        this.gui.Add("Text", "x625 y" (y0 + 175) " w220", "Tab page one content")
        this.controls["tabBtn"] := this.gui.Add("Button", "x625 y" (y0 + 200) " w120 h26", "Page Action")
        tab.UseTab(2)
        this.gui.Add("Text", "x625 y" (y0 + 175) " w220", "Advanced settings here")
        this.controls["tabChk"] := this.gui.Add("CheckBox", "x625 y" (y0 + 200) " w220", "Verbose logging")
        tab.UseTab()

        this.gui.Add("Text", "x610 y" (y0 + 276) " w250", "━ MonthCal")
        this.controls["mc"] := this.gui.Add("MonthCal", "x610 y" (y0 + 301))

        ; Spinner (numeric Edit + UpDown) and SysLink, then a real docked StatusBar.
        this.gui.Add("Text", "x20 y" (y0 + 482) " w40 +0x200", "Spin:")
        this.controls["spinEdit"] := this.gui.Add("Edit", "x60 y" (y0 + 478) " w52 h24 +Number", "10")
        this.controls["spin"] := this.gui.Add("UpDown", "Range0-100", 10)
        this.controls["link"] := this.gui.Add("Link", "x130 y" (y0 + 482) " w460",
            'Docs: <a href="https://www.autohotkey.com/docs/">AutoHotkey</a> · <a href="https://github.com/">GitHub</a>')

        this.controls["status"] := this.gui.Add("StatusBar", , "Status: Ready")
    }

    BindEvents() {
        this.controls["btn1"].OnEvent("Click", this.OnApply.Bind(this))
        this.controls["btn2"].OnEvent("Click", (*) => (this.gui.Hide(), 0))
        this.controls["btn3"].OnEvent("Click", this.OnReset.Bind(this))
        this.controls["slider"].OnEvent("Change", this.OnSliderChange.Bind(this))
        this.controls["btnToggle"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Toggle " (this.controls["btnToggle"].IsToggled ? "ON" : "OFF"))
        this.controls["btnFlat"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Flat clicked")
        this.controls["btnIcon"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Icon clicked")
        this.controls["btnSplit"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Split (face) clicked")
        this.controls["spin"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Spin = " this.controls["spinEdit"].Value)
        this.controls["link"].OnEvent("Click", this.OnLink.Bind(this))
        this.controls["dt"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Date → " FormatTime(this.controls["dt"].Value, "yyyy-MM-dd"))
        this.controls["hk"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Hotkey → " (this.controls["hk"].Value != "" ? this.controls["hk"].Value : "(none)"))
        this.controls["mc"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Calendar → " FormatTime(this.controls["mc"].Value, "yyyy-MM-dd"))
        this.controls["tab"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Tab page " this.controls["tab"].Value)
        this.controls["tabBtn"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Page action clicked")
        this.gui.OnEvent("Close", (*) => (ExitApp(), 0))
    }

    /** Swaps the whole palette; frames, BackColor, and brushes re-sync centrally. */
    ApplyPreset(name) {
        DarkTheme.ApplyPreset(name)
        this.controls["status"].Text := "Status: Preset → " name
    }

    /**
     * OnThemeChanged hook: repaints handle palette-driven colors automatically,
     * but font colors baked in at creation (SetFont "c...") need a refresh.
     */
    OnPaletteChanged(colors) {
        fontOpt := "c" Format("{:X}", colors["Font"])
        for hwnd, ctrl in this.gui {
            switch ctrl.Type, false {
                case "Text", "CheckBox", "DDL", "ComboBox", "Edit":
                    ctrl.SetFont(fontOpt)
            }
        }
        this.controls["lv"].Opt(fontOpt)
        this.controls["tv"].SetDarkMode()  ; re-sends TVM_SET*COLOR from the palette
    }

    OnApply(*) {
        this.controls["status"].Text := "Status: Applied at " FormatTime(, "HH:mm:ss")
    }

    OnReset(*) {
        this.controls["edit1"].Value := "Single-line edit"
        this.controls["edit2"].Value := "Multi-line`nedit control"
        this.controls["chk1"].Value := 1
        this.controls["chk2"].Value := 0
        this.controls["rad1"].Value := 1
        this.controls["slider"].Value := 50
        this.controls["progress"].Value := 50
        this.controls["sliderLabel"].Text := "Value: 50"
        this.controls["status"].Text := "Status: Reset complete"
    }

    OnSliderChange(*) {
        sliderVal := this.controls["slider"].Value
        this.controls["progress"].Value := sliderVal
        this.controls["sliderLabel"].Text := "Value: " sliderVal
    }

    ; Link Click fires with (ctrl, info, href). Registering a callback suppresses
    ; AHK's automatic HREF launch, so open it ourselves.
    OnLink(ctrl, info, href := "") {
        if href
            Run(href)
        this.controls["status"].Text := "Status: Link → " href
    }
}
