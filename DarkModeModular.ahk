/*
DarkModeModular.ahk — Dark mode GUI framework for AutoHotkey v2 (alpha.30, MAIN)

The stable, polished build of the framework, targeting the v2.1-alpha.30+Console
fork (stock alpha.30/.31 runs it too). Role swap 2026-09-13: this file took the
canonical role over from DarkModeModular_Alpha.ahk, which is now the
EXPERIMENTAL copy — new work lands there first and is promoted here only after
the gates pass (Tests/DarkMode_Registry_Test.ahk, DarkModeFable_Merge_Test.ahk,
DarkMode_Leak_Test.ahk all ALL PASS, /validate clean; queue and promotion notes
in Lib/DarkModeModular_Alpha.roadmap.md). The pre-swap classic library
(alpha.17-.28, NumGet-era) lives on as DarkModeModular_Classic.ahk.
Never include this file together with _Alpha or _Classic: they declare the
same classes and the second include fails to load.

Typed-Struct foundation, plus:

  Coverage    — DateTime, Hotkey, Tab/Tab2/Tab3, TreeView checkboxes, dark
                tooltips (DarkToolTip), dark Edit caret, generalized scrollbars.
  Correctness — WM_SETTEXT keeps Button/GroupBox captions in sync; native
                AddButton/AddEdit/... shorthands route through dark styling;
                menu-bar tooltips actually display; MIM_BACKGROUND uses the
                cached brush (no leak); native radios expose captions to UIA.
  Architecture— ONE handler registry (DarkGui.Handlers): every built-in type
                is registered in DarkGui.static __New and user types via
                DarkGui.Register(type, handler[, windowClass]); Add, Attach,
                teardown and palette refresh all dispatch through it. Handler
                protocol: Apply(owner, ctrl, options, content?) + Remove(hwnd),
                optional Refresh(ctrl) / OnDestroyed(hwnd). ctrl.SetDarkMode()
                is sugar over DarkGui.ApplyTo. Subclassing via comctl32
                SetWindowSubclass (Subclass), which reclaims thunks AND owner
                state on WM_NCDESTROY. Parent-side messages (WM_CTLCOLOR*,
                WM_NOTIFY, WM_DRAWITEM) dispatch through DarkWindowProc's
                hwnd-keyed child registry (RegisterChild), so the window proc
                names no control class.
  Options     — DarkGui.ParseOptions grammar: +Accent, +Flat, +Toggle[=on],
                +Icon=<spec> [+Align=..] on Button; c<X> / Background<X> where
                X is hex, an AHK colour name or a DarkTheme.Colors key (Text
                gets a live per-control override). Control-owned palette keys
                are declared with DarkTheme.DefineColor and follow presets.
  Theming     — DarkTheme.SetPalette()/presets (Default/OLED/Slate/Blue/Light) +
                OnThemeChanged callbacks; palette swaps re-sync DWM title-bar
                colors and Gui.BackColor per window; DarkTheme.FollowSystem()
                tracks the OS light/dark setting; per-monitor DPI scaling via
                GetDpiForWindow plus WM_DPICHANGED handling with a
                DarkGui.OnDpiChanged() hook.

Usage — whole script, one line (every Gui() after it is dark, controls included):
  #Include DarkModeModular.ahk
  DarkGui.Global()

Usage — per window:
  #Include DarkModeModular.ahk
  myGui := DarkGui("+Resize", "My App")          ; new window
  DarkGui.Attach(existingGui)                     ; or retrofit one you already have
  myGui.Add("Button", "+Accent", "OK")
  myGui.Add("Edit", "w300", "text")
  myGui.Show()
Showcase: Demo\DarkModeModular_Showcase.ahk (run it directly). This file has
no auto-execute section.

Public API: DarkGui, DarkTheme, DarkTitleBar, DarkMenu, DarkMenuBar,
DarkScrollbar, DarkToolTip (Apply/ApplyAll/AutoApply, plus the cursor-anchored
Show/Hide helper), DarkDialogs (opt-in dark MsgBox/InputBox via
DarkDialogs.Install()). All controls added via DarkGui.Add() are
automatically dark-styled; "+Accent" on buttons for the accent color.
Button variants ride instance methods: AddIconButton / AddSplitButton /
AddCommandLink / AddToggleButton / AddFlatButton.
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

; Vista layout: dwItemType tells a group header (LVCDI_GROUP) from a row, and
; clrFace is the group header's line colour.
Struct DM_NMLVCUSTOMDRAW {
    nmcd:        DM_NMCUSTOMDRAW
    clrText:     UInt32
    clrTextBk:   UInt32
    iSubItem:    Int32
    dwItemType:  UInt32
    clrFace:     UInt32
    iIconEffect: Int32
    iIconPhase:  Int32
    iPartId:     Int32
    iStateId:    Int32
    rcText:      DM_RECT
    uAlign:      UInt32
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

; Undocumented UAH menubar payloads (WM_UAHDRAWMENU 0x91 / WM_UAHDRAWMENUITEM
; 0x92) — the win32-darkmode recipe for a dark native menu BAR; popup menus
; are already dark process-wide via DarkMenu. Only the fields DarkWindowProc
; reads are typed precisely; the metrics unions are opaque DWORD blocks.
Struct DM_UAHMENU {
    hmenu:   IntPtr
    hdc:     IntPtr
    dwFlags: UInt32
}

Struct DM_UAHMENUITEM {
    iPosition: Int32
    umim:      UInt32[8]   ; UAHMENUITEMMETRICS union (32 bytes)
    umpm:      UInt32[5]   ; UAHMENUPOPUPMETRICS (20 bytes)
}

Struct DM_UAHDRAWMENUITEM {
    dis: DM_DRAWITEMSTRUCT
    um:  DM_UAHMENU
    umi: DM_UAHMENUITEM
}

Struct DM_MENUBARINFO {
    cbSize:   UInt32
    rcBar:    DM_RECT
    hMenu:    IntPtr
    hwndMenu: IntPtr
    fFlags:   Int32
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
    static Colors := Map()

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
    /** @type {Integer} GDI+ startup token. Started here at load so every
     * painter (buttons, scrollbar, slider knob) can rely on it without the
     * base layer depending on a control class. Never GdiplusShutdown — see
     * {@link DarkTheme._OnAppExit}. */
    static _gdipToken := 0

    static __New() {
        c := this.Colors
        c["Background"] := 0x1A1A1A
        c["Controls"] := 0x252525
        c["ControlsHover"] := 0x333333
        c["ControlsActive"] := 0x404040
        c["Font"] := 0xE8E8E8
        c["FontDim"] := 0xA0A0A0
        c["Accent"] := 0x0078D7
        c["Border"] := 0x404040
        c["Selection"] := 0x264F78
        c["GridLine"] := 0x2A2A2A
        c["Header"] := 0x2D2D2D
        c["ScrollTrack"] := 0x3C3C3C
        c["ScrollThumb"] := 0x5A5A5A
        c["ScrollThumbHover"] := 0x787878
        c["ButtonHover"] := 0x303030
        c["ButtonPressed"] := 0x1F1F1F
        c["ButtonBorder"] := 0x3A3A3A
        c["AccentHover"] := 0x1A8CFF
        c["AccentPressed"] := 0x005A9E
        c["AccentBorder"] := 0x0064B0
        c["FlatPressed"] := 0x282828
        c["DisabledBg"] := 0x202020
        c["DisabledText"] := 0x6E6E6E
        ; CalendarTrailing, Link and SliderThumb are declared by their owning
        ; control classes through DarkTheme.DefineColor — the pattern for any
        ; control-specific key, in-library or external.
        c["Error"] := 0xFF6B6B
        c["Success"] := 0x5FC95F
        c["Warning"] := 0xF0A030
        for name, color in this.Colors
            this.Brushes[name] := DllCall("gdi32\CreateSolidBrush", "UInt", this.RGBtoBGR(color), "Ptr")
        if !this._exitRegistered {
            OnExit(DarkTheme._OnAppExit)
            this._exitRegistered := true
        }
        this._BuildPresets()
        this._StartGdip()
    }

    /** Starts GDI+ once at load (anti-aliased rounded fills and the slider knob). */
    static _StartGdip() {
        if this._gdipToken
            return
        si := DM_GpInput()
        si.GdiplusVersion := 1
        token := 0
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si.Ptr, "Ptr", 0)
        this._gdipToken := token
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
        ; Link / SliderThumb / CalendarTrailing light values live in their
        ; owners' DefineColor calls.
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
        ; Drop the GDI+ token WITHOUT GdiplusShutdown: AHK shares gdiplus.dll
        ; for its own image handling and keeps it initialized for the process
        ; lifetime; shutting it down here faults during teardown. The OS
        ; reclaims GDI+ on exit.
        DarkTheme._gdipToken := 0
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
        if !this.Colors.Has(name)
            throw ValueError("DarkTheme.SetColor: unknown color '" name "' — declare it with DarkTheme.DefineColor first", -1)
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

    /** @type {String} Preset last applied via ApplyPreset; "" after a custom
     *  SetPalette. Lets DefineColor pick the right starting value for a key
     *  declared after the app already switched presets. */
    static CurrentPreset := "Default"

    /**
     * Declares a palette key owned by a control or an extension, so it exists
     * in Colors AND in every preset — SetPalette skips names it does not know,
     * so a key that only lived in Colors would never follow ApplyPreset.
     * Idempotent: an existing key is left untouched (returns false).
     *
     *     DarkTheme.DefineColor("Link", 0x4CA0FF, 0x0066CC)
     *     blue := Map(), blue["Blue"] := 0x3E5A80
     *     DarkTheme.DefineColor("CalendarTrailing", 0x4A4A4A, 0xB8B8B8, blue)
     *
     * @param {String} name - Palette key (case-sensitive, like every Colors key)
     * @param {Integer} dark - 0xRRGGBB for the dark presets
     * @param {Integer} [light] - 0xRRGGBB for the Light preset (defaults to dark)
     * @param {Map} [overrides] - presetName -> 0xRRGGBB per-preset tuning
     * @returns {Boolean} true when the key was added
     */
    static DefineColor(name, dark, light := unset, overrides := unset) {
        if this.Colors.Has(name)
            return false
        for presetName, preset in this.Presets {
            if preset.Has(name)
                continue
            value := (presetName = "Light" && IsSet(light)) ? light : dark
            if IsSet(overrides) && overrides.Has(presetName)
                value := overrides[presetName]
            preset[name] := value
        }
        current := dark
        if this.CurrentPreset != "" && this.Presets.Has(this.CurrentPreset)
            current := this.Presets[this.CurrentPreset][name]
        this.Colors[name] := current
        this.Brushes[name] := DllCall("gdi32\CreateSolidBrush", "UInt", this.RGBtoBGR(current), "Ptr")
        return true
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

    /** @type {Error|Integer} Last exception raised by a theme callback (0 = none). */
    static LastThemeError := 0

    /** Fires every subscriber. One throwing callback must not abort the rest
     *  or SetPalette's closing Redraw; the error is kept in LastThemeError. */
    static _NotifyThemeChanged() {
        for cb in this._themeCallbacks {
            try
                cb(this.Colors)
            catch Error as e
                this.LastThemeError := e
        }
    }

    /**
     * Bulk palette update: replaces every named color present in `palette`,
     * rebuilds brushes once, fires OnThemeChanged callbacks, and repaints all
     * registered windows in a single pass. Unknown names are ignored.
     * @param {Map} palette - name -> 0xRRGGBB
     */
    static SetPalette(palette) {
        this.CurrentPreset := ""
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
        this.CurrentPreset := name
    }

    /**
     * True when the user is running a Windows high-contrast theme.
     *
     * High contrast is an accessibility setting: the user has chosen an
     * explicit color scheme for readability, and visual styles are disabled
     * process-wide (every SetWindowTheme call silently no-ops). Painting the
     * dark palette over it would override exactly what the user asked for, so
     * the framework stands down — see {@link DarkTheme.StandDown}.
     * @returns {Boolean}
     */
    static IsHighContrast() {
        static SPI_GETHIGHCONTRAST := 0x42, HCF_HIGHCONTRASTON := 0x1
        hc := Buffer(16, 0)          ; HIGHCONTRASTW { UINT cbSize; DWORD dwFlags; LPWSTR lpszDefaultScheme; }
        NumPut("UInt", hc.Size, hc, 0)
        if !DllCall("SystemParametersInfoW", "UInt", SPI_GETHIGHCONTRAST, "UInt", hc.Size, "Ptr", hc, "UInt", 0)
            return false
        return (NumGet(hc, 4, "UInt") & HCF_HIGHCONTRASTON) != 0
    }

    /**
     * True when dark styling should be skipped entirely. Consulted at the
     * three installation choke points (DarkGui.__New, DarkGui.Attach,
     * DarkDialogs.Install) — all-or-nothing by design, since a half-applied
     * palette reads worse than either extreme. Apps can force styling on with
     * `DarkTheme.IgnoreHighContrast := true` before creating any window.
     * @returns {Boolean}
     */
    static StandDown() => !this.IgnoreHighContrast && this.IsHighContrast()

    /** @type {Boolean} Set true to keep dark styling even under high contrast. */
    static IgnoreHighContrast := false

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
    ; Last state delivered to the callback; -1 = none yet. WM_SETTINGCHANGE is
    ; broadcast to every top-level window the script owns and Windows emits
    ; "ImmersiveColorSet" several times per toggle, so without this latch one
    ; OS theme flip would run the callback (and its full repaint pipeline) N times.
    static _lastSystemLight := -1

    /**
     * Watches the OS light/dark app-theme setting. The framework itself stays
     * dark; the callback lets the app react (swap presets, show a notice, ...).
     * Invoked immediately with the current state, then once per actual change.
     * Single-slot: a second call replaces the previous subscriber.
     * @param {Func} callback - `callback(systemUsesLight)`
     */
    static FollowSystem(callback) {
        static WM_SETTINGCHANGE := 0x001A
        this._followCallback := callback
        if !this._settingHandler {
            this._settingHandler := ObjBindMethod(this, "_OnSettingChange")
            OnMessage(WM_SETTINGCHANGE, this._settingHandler)
        }
        this._lastSystemLight := this.SystemUsesLight()
        callback(this._lastSystemLight)
    }

    /** Stops watching the OS theme setting. */
    static UnfollowSystem() {
        static WM_SETTINGCHANGE := 0x001A
        if this._settingHandler {
            OnMessage(WM_SETTINGCHANGE, this._settingHandler, 0)
            this._settingHandler := 0
        }
        this._followCallback := 0
        this._lastSystemLight := -1
    }

    static _OnSettingChange(wParam, lParam, msg, hwnd) {
        if lParam && StrGet(lParam) = "ImmersiveColorSet" && this._followCallback {
            cur := this.SystemUsesLight()
            if cur = this._lastSystemLight
                return
            this._lastSystemLight := cur
            cb := this._followCallback
            cb(cur)
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
     * Relies on GDI+ being started at load by DarkTheme._StartGdip().
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
        ; swallowing the failure, so a real error is never hidden. Hoisted —
        ; Scale runs 5-8 times per control paint and the OS version can't change.
        static hasDpiForWindow := VerCompare(A_OSVersion, "10.0.14393") >= 0
        if hwnd && hasDpiForWindow {
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
    /** Keyboard-cue flags returned by {@link DarkTheme.UiState}. */
    static UISF_HIDEFOCUS := 0x1
    static UISF_HIDEACCEL := 0x2

    /**
     * The window's keyboard-cue state (WM_QUERYUISTATE): UISF_HIDEFOCUS means
     * focus rectangles stay hidden until the keyboard is used, UISF_HIDEACCEL
     * that mnemonic underlines stay hidden until Alt is pressed. Native
     * controls follow this, so owner-drawn ones consult it before painting a
     * ring or an underline; the state is inherited from the top-level window.
     * @param {Ptr} hwnd - Control handle
     * @returns {Integer} UISF_* bit mask
     */
    static UiState(hwnd) {
        static WM_QUERYUISTATE := 0x0129
        return SendMessage(WM_QUERYUISTATE, 0, 0, hwnd)
    }

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
     * Called from the OnExit handler (_OnAppExit). {@link DarkTheme.Release}
     * deliberately does NOT free brushes — see its docstring.
     */
    static Cleanup() {
        for name, brush in this.Brushes
            DllCall("DeleteObject", "Ptr", brush, "Void")
        this.Brushes.Clear()
        this._FlushGdiCache()
    }
}

/**
 * Dark styling for static Text controls. DarkWindowProc answers
 * WM_CTLCOLORSTATIC from the palette on every paint, so Apply only seeds the
 * font colour for the retrofit path and leaves a caller-pinned colour
 * ("cRed") alone. Per-control colours go through
 * {@link DarkWindowProc.SetStaticColor} (ctrl.SetTextColor / SetBackColor).
 */
class _DarkText {
    /** @type {Map} hwnd -> "horz" | "vert" | "eframe" | "frame" for Statics
     *  whose 3D edge is replaced by a palette Border line (see _ApplyFrame). */
    static Frames := Map()

    /** A creation colour ("cRed", "cError", "BackgroundAccent") becomes a
     *  per-control override, which is the only way it can render — the
     *  default WM_CTLCOLORSTATIC reply would otherwise repaint it in Font. */
    static Apply(owner, ctrl, options := "", content?) {
        opts := DarkGui.ParseOptions(options)
        if opts.Has("color")
            DarkWindowProc.SetStaticColor(ctrl.Hwnd, "text", opts["color"])
        else
            ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
        if opts.Has("background")
            DarkWindowProc.SetStaticColor(ctrl.Hwnd, "back", opts["background"])
        this._ApplyFrame(ctrl.Hwnd)
    }

    /** Drops the colour override and the frame subclass so the Static
     *  follows the palette again (the stripped 3D edge is not restored). */
    static Remove(hwnd) {
        DarkWindowProc.ClearStaticColor(hwnd)
        Subclass.Uninstall(this, hwnd)
        this.OnDestroyed(hwnd)
    }

    static OnDestroyed(hwnd) {
        if this.Frames.Has(hwnd)
            this.Frames.Delete(hwnd)
    }

    /**
     * Etched separators (SS_ETCHEDHORZ/VERT/FRAME) and sunken or bordered
     * text Statics (SS_SUNKEN, +Border, WS_EX_STATICEDGE) draw their edges
     * with DrawEdge in COLOR_3DSHADOW/COLOR_3DHILIGHT, which no brush reply
     * can recolour — they stay light gray and white on the dark window.
     * Strip the edge and repaint it as a 1px palette Border line after every
     * default paint. `Add("Text", "+0x10 w300 h2")` is the separator idiom.
     */
    static _ApplyFrame(hwnd) {
        static GWL_STYLE := -16, GWL_EXSTYLE := -20
        static SS_TYPEMASK := 0x1F, SS_ETCHEDHORZ := 0x10, SS_ETCHEDVERT := 0x11, SS_ETCHEDFRAME := 0x12
        static SS_SUNKEN := 0x1000, WS_BORDER := 0x800000
        static WS_EX_STATICEDGE := 0x20000, WS_EX_CLIENTEDGE := 0x200
        style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        exStyle := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        kind := ""
        switch style & SS_TYPEMASK {
            case SS_ETCHEDHORZ: kind := "horz"
            case SS_ETCHEDVERT: kind := "vert"
            case SS_ETCHEDFRAME: kind := "eframe"
        }
        if kind = "" && ((style & SS_SUNKEN) || (style & WS_BORDER) || (exStyle & (WS_EX_STATICEDGE | WS_EX_CLIENTEDGE))) {
            ; A text Static with a 3D edge: drop the edge (RemoveBorder handles
            ; WS_BORDER and the ex edges; SS_SUNKEN is a style bit of its own)
            ; and frame the client instead.
            if style & SS_SUNKEN
                DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style & ~SS_SUNKEN)
            DarkTheme.RemoveBorder(hwnd)
            kind := "frame"
        }
        if kind = ""
            return
        this.Frames[hwnd] := kind
        Subclass.InstallProc(this, hwnd)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /** Overpaints the edge after the default paint (same pattern as the
     *  StatusBar grip); reclaimed by Subclass._Wrap on WM_NCDESTROY. */
    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        if msg = WM_PAINT {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._PaintFrame(targetHwnd)
            return ret
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /**
     * Paints the palette edge for one framed Static. Etched kinds have no
     * text, so the client is erased to Background first; a text "frame" only
     * gets the outline. `hdc` lets tests rasterise into a memory DC.
     */
    static _PaintFrame(hwnd, hdc := 0) {
        kind := this.Frames.Get(hwnd, "")
        if kind = ""
            return
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right, h := rc.bottom
        own := !hdc
        if own
            hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        border := DarkTheme.GetBrush("Border")
        line := DM_RECT()
        if kind != "frame"
            DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
        switch kind {
            case "horz":
                line.left := 0, line.top := 0, line.right := w, line.bottom := 1
                DllCall("FillRect", "Ptr", hdc, "Ptr", line, "Ptr", border, "Void")
                if h > 3 {
                    line.top := h - 1, line.bottom := h
                    DllCall("FillRect", "Ptr", hdc, "Ptr", line, "Ptr", border, "Void")
                }
            case "vert":
                line.left := 0, line.top := 0, line.right := 1, line.bottom := h
                DllCall("FillRect", "Ptr", hdc, "Ptr", line, "Ptr", border, "Void")
                if w > 3 {
                    line.left := w - 1, line.right := w
                    DllCall("FillRect", "Ptr", hdc, "Ptr", line, "Ptr", border, "Void")
                }
            default:
                DllCall("FrameRect", "Ptr", hdc, "Ptr", rc, "Ptr", border, "Void")
        }
        if own
            DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }
}

/**
 * Applies dark mode to window title bar using DWM attributes (Win10 1809+).
 * Uses `DwmSetWindowAttribute` with the immersive dark mode flag.
 */
class DarkTitleBar {
    /**
     * Enables (or disables) the immersive dark title bar for a window.
     *
     * @param {Ptr} hwnd - Window handle.
     * @param {Boolean} dark - false paints the light frame; callers creating
     * windows should pass DarkTheme.IsDarkPalette() so a window constructed
     * under the Light preset doesn't get a dark frame until the next re-sync.
     * @returns {Boolean} `true` if applied, `false` if OS too old.
     */
    static Apply(hwnd, dark := true) {
        if VerCompare(A_OSVersion, "10.0.17763") < 0
            return false
        attr := VerCompare(A_OSVersion, "10.0.18985") >= 0 ? 20 : 19
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", attr, "Int*", dark ? 1 : 0, "Int", 4)
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

    /** @type {Ptr} Cursor-anchored tip shown by {@link DarkToolTip.Show} (0 when hidden) */
    static _hShow := 0
    /** @type {Buffer} Text buffer backing the shown tip (comctl32 reads it lazily) */
    static _showText := ""
    /** @type {Func} Auto-hide timer callback while a shown tip is pending */
    static _showTimer := ""

    /**
     * Shows a palette-coloured tracking tooltip just below-right of the cursor
     * and hides it after `duration` ms — the classic `DarkTooltip.Show` API.
     * A second call replaces the tip on screen. The window is theme-stripped so
     * TTM_SETTIPBKCOLOR/TEXTCOLOR take the Controls/Font palette entries.
     * @param {String} text - Tooltip text
     * @param {Integer} [duration=2000] - Auto-hide delay in ms; 0 keeps it until {@link DarkToolTip.Hide}
     * @returns {Ptr} Tooltip window handle, 0 when the window could not be created
     */
    static Show(text, duration := 2000) {
        static WS_EX_TOPMOST := 0x8, WS_POPUP := 0x80000000
        static TTS_ALWAYSTIP := 0x01, TTS_NOPREFIX := 0x02
        static TTM_ADDTOOLW := 0x0432, TTM_TRACKACTIVATE := 0x0411, TTM_TRACKPOSITION := 0x0412
        static TTM_SETTIPBKCOLOR := 0x0413, TTM_SETTIPTEXTCOLOR := 0x0414
        static TTF_TRACK := 0x20, TTF_ABSOLUTE := 0x80
        this.Hide()
        hTip := DllCall("CreateWindowEx", "UInt", WS_EX_TOPMOST, "Str", "tooltips_class32", "Ptr", 0,
            "UInt", WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX,
            "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")
        if !hTip
            return 0
        DllCall("uxtheme\SetWindowTheme", "Ptr", hTip, "Str", "", "Str", "")
        SendMessage(TTM_SETTIPBKCOLOR, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), 0, hTip)
        SendMessage(TTM_SETTIPTEXTCOLOR, DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), 0, hTip)
        buf := Buffer(StrPut(text, "UTF-16"), 0)
        StrPut(text, buf, "UTF-16")
        ti := DM_TOOLINFOW()
        ti.cbSize   := ti.Size
        ti.uFlags   := TTF_TRACK | TTF_ABSOLUTE
        ti.lpszText := buf.Ptr
        SendMessage(TTM_ADDTOOLW, 0, ti.Ptr, hTip)
        pt := DM_POINT()
        DllCall("GetCursorPos", "Ptr", pt.Ptr, "Void")
        x := pt.x + 16
        y := pt.y + 16
        SendMessage(TTM_TRACKPOSITION, 0, ((y & 0xFFFF) << 16) | (x & 0xFFFF), hTip)
        SendMessage(TTM_TRACKACTIVATE, 1, ti.Ptr, hTip)
        this._hShow := hTip
        this._showText := buf
        if duration > 0 {
            this._showTimer := ObjBindMethod(this, "Hide")
            SetTimer(this._showTimer, -duration)
        }
        return hTip
    }

    /** Hides and destroys the tip shown by {@link DarkToolTip.Show}, if any. */
    static Hide() {
        if this._showTimer {
            SetTimer(this._showTimer, 0)
            this._showTimer := ""
        }
        if this._hShow {
            DllCall("DestroyWindow", "Ptr", this._hShow, "Void")
            this._hShow := 0
        }
        this._showText := ""
    }

    /** @type {Ptr} SetWinEventHook handle while AutoApply is active */
    static _hEventHook := 0
    /** @type {Ptr} CallbackCreate thunk for the event hook */
    static _hookProc := 0

    /**
     * Darkens every tooltip the script shows from now on, automatically —
     * without this, plain `ToolTip()` windows are only darkened by a manual
     * {@link DarkToolTip.ApplyAll} after each show. Installed once (idempotent)
     * by {@link DarkGui.__New}; a WinEvent hook fires on EVENT_OBJECT_SHOW for
     * this process only and themes any tooltips_class32 window it sees.
     */
    static AutoApply() {
        static EVENT_OBJECT_SHOW := 0x8002
        static WINEVENT_OUTOFCONTEXT := 0x0000
        if this._hEventHook
            return
        this._hookProc := CallbackCreate(ObjBindMethod(this, "_OnWinEvent"), , 7)
        this._hEventHook := DllCall("SetWinEventHook",
            "UInt", EVENT_OBJECT_SHOW, "UInt", EVENT_OBJECT_SHOW,
            "Ptr", 0, "Ptr", this._hookProc,
            "UInt", DllCall("GetCurrentProcessId", "UInt"), "UInt", 0,
            "UInt", WINEVENT_OUTOFCONTEXT, "Ptr")
        if !this._hEventHook {
            CallbackFree(this._hookProc)
            this._hookProc := 0
        }
    }

    /** Stops the automatic tooltip theming installed by AutoApply. */
    static StopAutoApply() {
        if this._hEventHook {
            DllCall("UnhookWinEvent", "Ptr", this._hEventHook, "Void")
            this._hEventHook := 0
        }
        if this._hookProc {
            CallbackFree(this._hookProc)
            this._hookProc := 0
        }
    }

    static _OnWinEvent(hHook, event, hwnd, idObject, idChild, thread, time) {
        static OBJID_WINDOW := 0
        if !hwnd || idObject != OBJID_WINDOW
            return
        static clsBuf := Buffer(64, 0)
        DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", clsBuf, "Int", 32)
        if StrGet(clsBuf) = "tooltips_class32"
            this.Apply(hwnd)
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
 * Dark MsgBox and InputBox. Install() wraps the built-ins' Call property so
 * every dialog the script shows afterwards is restyled from the live
 * DarkTheme palette (themed frame and controls, dark body, darker button
 * strip); Uninstall() restores stock behavior. Opt-in — DarkGui does not
 * install it automatically, since a script may deliberately want stock
 * system dialogs.
 *
 * Mechanism (after nperovic's DarkMsgBox, reworked for this framework):
 * AHK's MsgBox raises WM_COMMNOTIFY (wParam 1027) and InputBox raises
 * WM_INITDIALOG while the #32770 dialog is being created; a temporary
 * OnMessage monitor catches that moment, themes the dialog and its
 * children, and installs a {@link Subclass} proc answering WM_CTLCOLOR* and
 * WM_ERASEBKGND from the palette. The generic Subclass WM_NCDESTROY reclaim
 * frees the proc when the dialog closes, so nothing leaks per dialog.
 */
class DarkDialogs {
    static _active := false
    static _origMsgBox := 0
    static _origInputBox := 0

    static Install() {
        if this._active
            return
        ; See DarkGui.__New — stand down under a high-contrast scheme.
        if DarkTheme.StandDown()
            return
        this._active := true
        this._origMsgBox := MsgBox.Call.Bind(MsgBox)
        this._origInputBox := InputBox.Call.Bind(InputBox)
        MsgBox.DefineProp("Call", { Call: ObjBindMethod(this, "_CallMsgBox") })
        InputBox.DefineProp("Call", { Call: ObjBindMethod(this, "_CallInputBox") })
    }

    static Uninstall() {
        if !this._active
            return
        this._active := false
        ; DeleteProp restores the Func.Prototype.Call lookup.
        MsgBox.DeleteProp("Call")
        InputBox.DeleteProp("Call")
        this._origMsgBox := 0
        this._origInputBox := 0
    }

    static _CallMsgBox(fn, params*) {
        static WM_COMMNOTIFY := 0x44
        handler := ObjBindMethod(this, "_OnCommNotify")
        OnMessage(WM_COMMNOTIFY, handler)
        try
            return this._origMsgBox(params*)
        finally
            OnMessage(WM_COMMNOTIFY, handler, 0)
    }

    static _OnCommNotify(wParam, lParam, msg, hwnd) {
        ; AHK raises this with wParam 1027 while its MsgBox dialog spins up.
        if wParam = 1027
            this._StyleThreadDialogs()
    }

    static _CallInputBox(fn, params*) {
        static WM_INITDIALOG := 0x0110
        handler := ObjBindMethod(this, "_OnInitDialog")
        OnMessage(WM_INITDIALOG, handler, -1)
        try
            return this._origInputBox(params*)
        finally
            OnMessage(WM_INITDIALOG, handler, 0)
    }

    static _OnInitDialog(wParam, lParam, msg, hwnd) {
        this._StyleDialog(hwnd)
    }

    /** Finds this thread's #32770 dialog and styles it. */
    static _StyleThreadDialogs() {
        cb := CallbackCreate(ObjBindMethod(this, "_EnumProc"), , 2)
        DllCall("EnumThreadWindows", "UInt", DllCall("GetCurrentThreadId", "UInt"), "Ptr", cb, "Ptr", 0)
        CallbackFree(cb)
    }

    static _EnumProc(hwnd, lParam) {
        static clsBuf := Buffer(64, 0)
        DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", clsBuf, "Int", 32)
        if StrGet(clsBuf) = "#32770" {
            ; Stop only after styling a NEW dialog. Halting on the first
            ; #32770 found left a second concurrent dialog light whenever an
            ; already-styled one enumerated first (EnumThreadWindows order is
            ; unspecified, and a topmost MsgBox reliably comes first).
            if !Subclass.IsInstalled(this, hwnd) {
                this._StyleDialog(hwnd)
                return 0
            }
        }
        return 1
    }

    static _StyleDialog(hwnd) {
        static GWL_STYLE := -16, GWL_EXSTYLE := -20
        static WS_CLIPCHILDREN := 0x02000000, WS_CLIPSIBLINGS := 0x04000000
        static WS_EX_COMPOSITED := 0x02000000
        static RDW_FLAGS := 0x1 | 0x4 | 0x80  ; INVALIDATE | ERASE | ALLCHILDREN
        if Subclass.IsInstalled(this, hwnd)
            return
        style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style | WS_CLIPCHILDREN | WS_CLIPSIBLINGS)
        ex := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", ex | WS_EX_COMPOSITED)
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        DarkTitleBar.Apply(hwnd, DarkTheme.IsDarkPalette())
        if VerCompare(A_OSVersion, "10.0.22000") >= 0 {
            bgBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"])
            borderBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"])
            captionText := DarkTheme.IsDarkPalette() ? 0xFFFFFF : 0x000000
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 35, "UInt*", bgBGR, "Int", 4)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 36, "UInt*", captionText, "Int", 4)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 34, "UInt*", borderBGR, "Int", 4)
        }

        ; Theme the children; remember the buttons for the strip fill.
        btns := []
        _child(child, lp) {
            static buf := Buffer(64, 0)
            DllCall("GetClassNameW", "Ptr", child, "Ptr", buf, "Int", 32)
            cls := StrGet(buf)
            DllCall("uxtheme\SetWindowTheme", "Ptr", child, "Str", cls = "Edit" ? "DarkMode_CFD" : "DarkMode_Explorer", "Ptr", 0)
            if cls = "Button"
                btns.Push(child)
            return 1
        }
        childCb := CallbackCreate(_child, , 2)
        DllCall("EnumChildWindows", "Ptr", hwnd, "Ptr", childCb, "Ptr", 0)
        CallbackFree(childCb)

        Subclass.Install(this, hwnd, ObjBindMethod(this, "_DlgProc", hwnd, btns))
        DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", RDW_FLAGS, "Void")
    }

    static _DlgProc(targetHwnd, btns, hwnd, msg, wParam, lParam) {
        static WM_CTLCOLORDLG := 0x0136
        static WM_CTLCOLORSTATIC := 0x0138
        static WM_CTLCOLORBTN := 0x0135
        static WM_CTLCOLOREDIT := 0x0133
        static WM_ERASEBKGND := 0x0014
        static TRANSPARENT := 1

        switch msg {
            case WM_CTLCOLORDLG:
                return DarkTheme.GetBrush("Background")
            case WM_CTLCOLORSTATIC:
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush("Background")
            case WM_CTLCOLORBTN:
                return DarkTheme.GetBrush("Controls")
            case WM_CTLCOLOREDIT:
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush("Controls")
            case WM_ERASEBKGND:
                ; Body in Background; the strip behind the buttons (and its
                ; mirror-margin above them) in Controls — the dark analogue of
                ; the dialog's two-tone white/gray layout.
                static rc := DM_RECT(), rcBtn := DM_RECT(), stripRc := DM_RECT(), pt := DM_POINT()
                DllCall("GetClientRect", "Ptr", targetHwnd, "Ptr", rc)
                DllCall("FillRect", "Ptr", wParam, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
                if btns.Length {
                    top := rc.bottom
                    bottom := 0
                    for b in btns {
                        DllCall("GetWindowRect", "Ptr", b, "Ptr", rcBtn)
                        pt.x := rcBtn.left, pt.y := rcBtn.top
                        DllCall("ScreenToClient", "Ptr", targetHwnd, "Ptr", pt.Ptr, "Void")
                        top := Min(top, pt.y)
                        bottom := Max(bottom, pt.y + (rcBtn.bottom - rcBtn.top))
                    }
                    stripRc.left := 0, stripRc.top := top - (rc.bottom - bottom)
                    stripRc.right := rc.right, stripRc.bottom := rc.bottom
                    if stripRc.top > 0 && stripRc.top < rc.bottom
                        DllCall("FillRect", "Ptr", wParam, "Ptr", stripRc, "Ptr", DarkTheme.GetBrush("Controls"), "Void")
                }
                return 1
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
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

    /** Registry key. Accepts a class (static callers) or an instance (DarkScrollbar).
     * Instances are namespaced by identity: without ObjPtr, two instances of one
     * class subclassing the same hwnd would share a key — the second Install
     * would silently no-op and either instance's Uninstall would free the
     * other's live thunk. */
    static _Key(owner, hwnd) {
        ; owner.Base.__Class, not Type(owner): a caller with a global variable
        ; named `type` shadows the built-in for every function in the script,
        ; this one included.
        cls := owner is Class ? owner.Prototype.__Class : (owner.Base.__Class "@" ObjPtr(owner))
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
        callback := CallbackCreate(this._Wrap(owner, hwnd, procMethod), , 4)
        if !DllCall("comctl32\SetWindowSubclass", "Ptr", hwnd, "Ptr", callback, "Ptr", this.SubclassId, "Ptr", 0) {
            CallbackFree(callback)
            return false
        }
        this._installed[key] := callback
        return true
    }

    /**
     * Installs a subclass whose procedure is a static method on `owner`, doing
     * the hwnd binding here so the proc shape is checked ONCE at install time
     * instead of failing as "too many parameters" inside the message loop.
     * The method must be `Proc(targetHwnd, hwnd, msg, wParam, lParam)`.
     * @param {Class} owner - Class that owns the proc (namespaces the registry)
     * @param {Ptr} hwnd - Window handle to subclass
     * @param {String} [methodName="Proc"] - Name of the static proc method
     * @returns {Boolean} true if installed, false if already subclassed or API failure
     */
    static InstallProc(owner, hwnd, methodName := "Proc") {
        fn := GetMethod(owner, methodName)
        if !fn.IsVariadic && (fn.MaxParams < 6 || fn.MinParams > 6)
            throw ValueError("Subclass.InstallProc: " methodName " must be (targetHwnd, hwnd, msg, wParam, lParam)", -1)
        return this.Install(owner, hwnd, ObjBindMethod(owner, methodName, hwnd))
    }

    /**
     * Wraps the owner's proc with a generic WM_NCDESTROY reclaim so EVERY
     * subclass frees its registry entry and thunk when its window dies.
     * Teardown via DarkGui.__Delete can be blocked indefinitely by lingering
     * object references (a held control variable, a DarkScrollbar's gui ref),
     * and per-proc reclaim branches only existed in a handful of classes.
     * The owner's proc runs first — its own reclaim, if any, makes ours a
     * no-op — and the free is deferred because the thunk being released is
     * the one executing this message.
     */
    static _Wrap(owner, hwnd, procMethod) {
        wrapped(h, msg, wParam, lParam) {
            static WM_NCDESTROY := 0x0082
            if msg = WM_NCDESTROY && h = hwnd {
                ; finally: the reclaim is this wrapper's whole purpose, so a
                ; throwing owner proc must not leak the thunk and leave a dead
                ; hwnd key that silently blocks re-styling on hwnd reuse.
                ; Uninstall is a no-op when the owner already reclaimed.
                ; OnDestroyed(hwnd) lets a stateful owner drop its per-hwnd
                ; records (Texts, Instances, Geometry, ...) on this same path,
                ; so a window destroyed without _Teardown leaks nothing.
                try
                    return procMethod(h, msg, wParam, lParam)
                finally {
                    try {
                        if HasMethod(owner, "OnDestroyed")
                            owner.OnDestroyed(hwnd)
                    } finally {
                        Subclass.Uninstall(owner, hwnd, true)
                    }
                }
            }
            return procMethod(h, msg, wParam, lParam)
        }
        return wrapped
    }

    /**
     * True when `owner` already has a subclass installed on `hwnd`.
     * @param {Object} owner - Calling class or instance
     * @param {Ptr} hwnd - Window handle
     * @returns {Boolean}
     */
    static IsInstalled(owner, hwnd) => this._installed.Has(this._Key(owner, hwnd))

    /** Number of live subclass installations (tests and diagnostics). */
    static Count => this._installed.Count

    /**
     * Removes the subclass and frees the callback. No-op when not installed.
     * @param {Object} owner - Calling class or instance
     * @param {Ptr} hwnd - Window handle to unsubclass
     * @param {Boolean} deferFree - Free the thunk via a one-shot timer instead
     * of immediately. Required when uninstalling from inside the subclass
     * procedure itself (a WM_NCDESTROY branch): freeing there would free the
     * thunk comctl32 is executing to deliver that very message.
     */
    static Uninstall(owner, hwnd, deferFree := false) {
        key := this._Key(owner, hwnd)
        if !this._installed.Has(key)
            return
        callback := this._installed[key]
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", callback, "Ptr", this.SubclassId)
        if deferFree
            SetTimer(CallbackFree.Bind(callback), -1)
        else
            CallbackFree(callback)
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
 * Custom dark scrollbar: an owner-drawn rail that replaces the target's own
 * vertical scrollbar. Attached mode (`DarkScrollbar(gui, ctrl)`) follows the
 * target's rect; the native bar is hidden and the rail serves the wheel and
 * drives each class the way it answers (LB_SETTOPINDEX, EM_LINESCROLL,
 * TreeView line steps, LVM_SCROLL). Sync is event-driven off the target's
 * paint/scroll/size messages.
 *
 * Rendering is double-buffered: a resting hairline that tweens to the full
 * anti-aliased pill on hover, drag, and page-up/page-down on track clicks.
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
     * Omit x/y/h for attached mode: the rail takes its geometry from the
     * target's own rect and follows it on every move and resize. Passing
     * coordinates keeps the legacy manual placement.
     *
     * @param {DarkGui} gui - Parent GUI instance.
     * @param {Gui.Control} targetCtrl - Control to sync scroll position with.
     * @param {Integer} [x] - X position. Omit to attach to the target.
     * @param {Integer} [y] - Y position.
     * @param {Integer} [h] - Height.
     */
    __New(gui, targetCtrl, x?, y?, h?) {
        this.gui := gui
        this.target := targetCtrl
        this.isListView := (targetCtrl.Type = "ListView")
        this.isEdit := (targetCtrl.Type = "Edit")
        this.isListBox := (targetCtrl.Type = "ListBox")
        this.isTreeView := (targetCtrl.Type = "TreeView")
        this._wheelAccum := 0
        ; Logical Add-units — gui.Add applies the DPI scale itself; pre-scaling
        ; here double-scaled the width at non-96 DPI.
        this.w := 14
        ; A caller-supplied height is taken literally, and a control that snaps
        ; its own height (a ListBox rounds down to whole rows) then wears a rail
        ; that overhangs it. Attached mode reads the size the control actually
        ; settled on instead.
        this.attached := !IsSet(x)
        if this.attached {
            targetCtrl.GetPos(&tx, &ty, &tw, &th)
            this.x := tx + tw, this.y := ty, this.h := th
        } else {
            this.x := x, this.y := y ?? 0, this.h := h ?? 0
        }

        this.isDragging := false
        this.dragStartY := 0
        this.dragStartPos := 0
        this.isHovering := false
        ; Rail expansion tween: 0 = resting hairline, 1 = fully expanded.
        this._railT := 0.0
        this._railTarget := 0.0
        this._animFn := 0
        this._nativeHidden := false
        this._destroyed := false
        ; Last painted thumb extent, so the poll timer only repaints on real change.
        this._lastThumbTop := -1
        this._lastThumbBottom := -1

        ; Create the scrollbar as a Text control (we'll custom draw it).
        ; SS_NOTIFY is load-bearing, not cosmetic: without it a static answers
        ; WM_NCHITTEST with HTTRANSPARENT, so every mouse message falls through
        ; to the parent Gui and the rail never sees a hover, a track click or a
        ; thumb drag.
        this.ctrl := gui.Add("Text", "x" this.x " y" this.y " w" this.w " h" this.h " +0x4000000 +0x100")  ; WS_CLIPSIBLINGS | SS_NOTIFY
        this.ctrl.Opt("+Background" Format("{:X}", DarkTheme.Colors["Controls"]))

        ; Raw handles for the timer/teardown paths: a control's .Hwnd getter
        ; throws once the Gui is destroyed, and the 100ms timer can outlive it.
        this.hwnd := this.ctrl.Hwnd
        this.targetHwnd := targetCtrl.Hwnd

        ; Store instance reference
        DarkScrollbar.Instances[this.hwnd] := this

        ; Subclass for custom drawing and mouse handling
        this.SubclassScrollbar()

        ; Event-driven sync: a lightweight subclass on the TARGET re-syncs the
        ; thumb after anything that can change scroll state. This replaced a
        ; per-instance 100ms poll timer (~30 SendMessages/sec each while idle,
        ; running even for hidden windows). The target's WM_PAINT is the
        ; catch-all — content and scroll changes always repaint the target,
        ; and SyncFromTarget early-outs when the thumb didn't move.
        this.syncTimer := 0
        Subclass.Install(this, this.targetHwnd, ObjBindMethod(this, "TargetProc"))
        this._HideNativeBar()
    }

    /** The rail stands in for the target's own bar; leaving both visible stacks
     * two scrollbars side by side. Re-applied from TargetProc because a control
     * re-shows its bar whenever its content or size changes. */
    _HideNativeBar() {
        static SB_VERT := 1
        ; Subclasses are uninstalled deferred, so TargetProc still runs for a
        ; few messages after Destroy — without this guard the next repaint
        ; takes the bar straight back off the target we just handed it to.
        if this._destroyed || !DllCall("IsWindow", "Ptr", this.targetHwnd)
            return
        DllCall("ShowScrollBar", "Ptr", this.targetHwnd, "Int", SB_VERT, "Int", 0)
        this._nativeHidden := true
    }

    /** Hands the bar back on teardown — a rail destroyed before its target
     * would otherwise leave the control with no way to scroll by mouse. */
    _RestoreNativeBar() {
        static SB_VERT := 1
        if this._nativeHidden && DllCall("IsWindow", "Ptr", this.targetHwnd)
            DllCall("ShowScrollBar", "Ptr", this.targetHwnd, "Int", SB_VERT, "Int", 1)
        this._nativeHidden := false
    }

    /** Attached mode: follow the target's rect. GetPos reports the control's
     * real size in the same logical units Move takes, so a snapped height
     * comes back snapped. */
    _SyncGeometry() {
        if !this.attached || !DllCall("IsWindow", "Ptr", this.targetHwnd)
            return
        try
            this.target.GetPos(&tx, &ty, &tw, &th)
        catch
            return
        if tx + tw = this.x && ty = this.y && th = this.h
            return
        this.x := tx + tw, this.y := ty, this.h := th
        this.ctrl.Move(this.x, this.y, this.w, this.h)
    }

    TargetProc(hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        static WM_VSCROLL := 0x0115
        static WM_MOUSEWHEEL := 0x020A
        static WM_KEYDOWN := 0x0100
        static WM_SIZE := 0x0005
        static WM_WINDOWPOSCHANGED := 0x0047
        ; A control gates its own wheel handling on having a VISIBLE scrollbar,
        ; and this rail hides it — so the wheel is ours to serve now. Measured:
        ; a bar-hidden ListBox and Edit ignore the wheel entirely otherwise.
        if msg = WM_MOUSEWHEEL {
            this.OnWheel(wParam)
            return 0
        }
        if msg = WM_PAINT || msg = WM_VSCROLL || msg = WM_KEYDOWN || msg = WM_SIZE || msg = WM_WINDOWPOSCHANGED {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._HideNativeBar()
            if msg = WM_SIZE || msg = WM_WINDOWPOSCHANGED
                this._SyncGeometry()
            this.SyncFromTarget()
            return ret
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
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
        static WM_MOUSEWHEEL := 0x020A

        if msg = WM_ERASEBKGND
            return 1

        ; A native scrollbar lives in the target's non-client area, so wheeling
        ; over it scrolls the target. This replacement is a separate Text
        ; control sitting exactly where users aim the wheel, and the default
        ; proc would bubble the message to the parent Gui instead — relay it.
        ; TargetProc re-syncs the thumb on the target's own wheel handling.
        if msg = WM_MOUSEWHEEL {
            if DllCall("IsWindow", "Ptr", this.targetHwnd)
                DllCall("SendMessage", "Ptr", this.targetHwnd, "UInt", WM_MOUSEWHEEL, "Ptr", wParam, "Ptr", lParam)
            return 0
        }

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
            ; A drag that wanders off the rail keeps it expanded until the
            ; button comes up — collapsing mid-drag loses the thumb the user
            ; is still holding.
            this._SetRail(this.isDragging ? 1 : 0)
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
            return 0
        }

        if msg = WM_CAPTURECHANGED {
            this.isDragging := false
            return 0
        }

        static WM_NCDESTROY := 0x0082
        if msg = WM_NCDESTROY {
            ; Host died without teardown: stop the 100ms sync timer and drop
            ; the instance registration. Deferred Uninstall FIRST, so
            ; Destroy's own immediate Uninstall no-ops instead of freeing the
            ; thunk this frame is executing.
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            Subclass.Uninstall(this, hwnd, true)
            this.Destroy()
            return ret
        }

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    GetScrollInfo() {
        static LVM_GETITEMCOUNT := 0x1004
        static LVM_GETCOUNTPERPAGE := 0x1028
        static LVM_GETTOPINDEX := 0x1027
        static SB_VERT := 1
        static SIF_RANGE := 0x1, SIF_PAGE := 0x2, SIF_POS := 0x4

        ; The target may outlive or predecease the scrollbar host (they can
        ; live in different windows). AHK's SendMessage THROWS on a dead hwnd,
        ; so an unguarded ListView read would raise one error dialog per paint
        ; once the target's window closes first. The generic path below fails
        ; silently to zeros via DllCall, but guard both for one exit shape.
        if !DllCall("IsWindow", "Ptr", this.targetHwnd)
            return {min: 0, max: 0, page: 1, pos: 0}

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

        ; An Edit stops maintaining nPos once its bar is hidden, so read the
        ; control's own notion of the top line instead of the bar's.
        if this.isEdit {
            static EM_GETFIRSTVISIBLELINE := 0x00CE, EM_GETLINECOUNT := 0x00BA
            lines := SendMessage(EM_GETLINECOUNT, 0, 0, this.targetHwnd)
            return {
                min: 0,
                max: Max(0, lines - 1),
                page: this._EditPage(),
                pos: SendMessage(EM_GETFIRSTVISIBLELINE, 0, 0, this.targetHwnd)
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

    /** Visible line count of an Edit target, for the thumb proportion and the
     * page-click step. Derived from the control's own font metrics — an Edit
     * reports no page size of its own. */
    _EditPage() {
        static WM_GETFONT := 0x0031
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", this.targetHwnd, "Ptr", rc)
        hdc := DllCall("GetDC", "Ptr", this.targetHwnd, "Ptr")
        if !hdc
            return 1
        hFont := SendMessage(WM_GETFONT, 0, 0, this.targetHwnd)
        hOld := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        tm := Buffer(64, 0)
        lineH := DllCall("GetTextMetrics", "Ptr", hdc, "Ptr", tm) ? NumGet(tm, 0, "Int") : 0
        if hOld
            DllCall("SelectObject", "Ptr", hdc, "Ptr", hOld, "Ptr")
        DllCall("ReleaseDC", "Ptr", this.targetHwnd, "Ptr", hdc, "Int")
        return lineH > 0 ? Max(1, rc.bottom // lineH) : 1
    }

    /** Lines per wheel notch from the user's mouse settings. WHEEL_PAGESCROLL
     * (0xFFFFFFFF) means "one page", which the caller resolves against the
     * target's own page size. */
    static _WheelLines() {
        static SPI_GETWHEELSCROLLLINES := 0x0068
        lines := 0
        DllCall("SystemParametersInfo", "UInt", SPI_GETWHEELSCROLLLINES, "UInt", 0, "UInt*", &lines, "UInt", 0)
        return lines
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

        ; Nothing to scroll: report the full track so the paging hit-test has
        ; sane bounds, but flag it so Paint draws no thumb at all -- a
        ; full-length pill on a control that cannot scroll reads as stuck.
        if range <= info.page || range <= 0
            return {top: 0, bottom: trackH, height: trackH, scrollable: false}

        thumbHeight := Max(DarkTheme.Scale(30, this.hwnd), (info.page * trackH) // range)
        trackSpace := trackH - thumbHeight

        scrollRange := info.max - info.min - info.page + 1
        if scrollRange <= 0
            thumbTop := 0
        else
            ; Offset by info.min — the generic path reports real nMin, and a
            ; raw pos would draw the thumb past the track for nMin != 0.
            thumbTop := ((info.pos - info.min) * trackSpace) // scrollRange

        return {
            top: thumbTop,
            bottom: thumbTop + thumbHeight,
            height: thumbHeight,
            scrollable: true
        }
    }

    /** Linear RGB mix, `t` running 0 (colour a) to 1 (colour b). */
    static _Blend(a, b, t) {
        r := Round(((a >> 16) & 0xFF) + (((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * t)
        g := Round(((a >> 8) & 0xFF) + (((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * t)
        bl := Round((a & 0xFF) + ((b & 0xFF) - (a & 0xFF)) * t)
        return (r << 16) | (g << 8) | bl
    }

    Paint() {
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", this.ctrl.Hwnd, "Ptr", ps.Ptr, "Ptr")

        ; Get client rect
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", this.ctrl.Hwnd, "Ptr", rc)
        w := rc.right
        h := rc.bottom

        ; Double-buffered: the rail tweens its width on hover, and painting
        ; track-then-thumb straight to the window DC strobes through the tween.
        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", w, "Int", h, "Ptr")
        hOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

        ; Track (cached brush — do not delete). At rest it is the surface colour
        ; of the control it serves, so the rail reads as part of that control
        ; instead of a lighter strip parked beside it; the ScrollTrack tint
        ; fades in with the expansion. Palette is read live, not snapshotted in
        ; __New, so SetPalette/ApplyPreset repaint correctly.
        trackColor := this._railT > 0
            ? DarkScrollbar._Blend(DarkTheme.Colors["Controls"], DarkTheme.Colors["ScrollTrack"], this._railT)
            : DarkTheme.Colors["Controls"]
        DllCall("FillRect", "Ptr", hdcMem, "Ptr", rc, "Ptr", DarkTheme.GetSolidBrush(trackColor), "Void")

        ; Draw thumb
        thumb := this.GetThumbRect()
        thumbColor := this.isHovering || this.isDragging ? DarkTheme.Colors["ScrollThumbHover"] : DarkTheme.Colors["ScrollThumb"]

        ; Rounded anti-aliased pill thumb (was a square-cornered FillRect). The
        ; track fill above is the background the AA edge blends against. Width
        ; tweens from a resting hairline to the full pill on hover — the Win11
        ; overlay shape. The hit area stays the whole control either way, so
        ; the resting width never costs the user aim.
        pad := DarkTheme.Scale(2, this.ctrl.Hwnd)
        maxW := w - pad * 2
        minW := Min(DarkTheme.Scale(4, this.ctrl.Hwnd), maxW)
        tw := Round(minW + (maxW - minW) * this._railT)
        tx := (w - tw) // 2
        ty := thumb.top + pad
        th := (thumb.bottom - pad) - (thumb.top + pad)
        if thumb.scrollable && th > 0 && tw > 0
            DarkTheme.GdipRoundFill(hdcMem, tx, ty, tw, th, tw / 2, thumbColor)

        DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h,
            "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020, "Void")  ; SRCCOPY
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hOld, "Void")
        DllCall("DeleteObject", "Ptr", hbm, "Void")
        DllCall("DeleteDC", "Ptr", hdcMem, "Void")

        DllCall("EndPaint", "Ptr", this.ctrl.Hwnd, "Ptr", ps.Ptr, "Void")
    }

    /** Drives the expand/collapse tween. Steps on a 15ms timer that stops
     * itself at either end, so a rail nobody is pointing at costs nothing. */
    _SetRail(target) {
        this._railTarget := target
        if this._railT = target {
            this._StopAnim()
            return
        }
        if !this._animFn {
            this._animFn := ObjBindMethod(this, "_AnimStep")
            SetTimer(this._animFn, 15)
        }
    }

    _AnimStep() {
        static STEP := 0.25
        if !DllCall("IsWindow", "Ptr", this.hwnd) {
            this._StopAnim()
            return
        }
        this._railT := this._railT < this._railTarget
            ? Min(this._railTarget, this._railT + STEP)
            : Max(this._railTarget, this._railT - STEP)
        DllCall("InvalidateRect", "Ptr", this.hwnd, "Ptr", 0, "Int", 1, "Void")
        if this._railT = this._railTarget
            this._StopAnim()
    }

    _StopAnim() {
        if this._animFn {
            SetTimer(this._animFn, 0)
            this._animFn := 0
        }
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
        this._SetRail(1)

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
            this._SetRail(this.isHovering ? 1 : 0)
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
            this._SetRail(1)
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

    /** Turns a wheel notch into a scroll of the user's configured line count.
     * Sub-notch deltas (precision touchpads) accumulate rather than round to
     * zero and stall. */
    OnWheel(wParam) {
        delta := (wParam >> 16) & 0xFFFF
        if delta > 0x7FFF
            delta -= 0x10000
        info := this.GetScrollInfo()
        lines := DarkScrollbar._WheelLines()
        ; WHEEL_PAGESCROLL: the user asked for a page per notch.
        step := (lines = 0xFFFFFFFF || lines = -1) ? info.page : Max(1, lines)
        this._wheelAccum += delta * step
        moved := this._wheelAccum // 120
        if !moved
            return
        this._wheelAccum -= moved * 120
        newPos := Max(info.min, Min(info.pos - moved, info.max - info.page + 1))
        if newPos != info.pos
            this.SetScrollPos(newPos)
        this.SyncFromTarget()
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

        ; Dead target: nothing to scroll, and SendMessage would throw.
        if !DllCall("IsWindow", "Ptr", this.targetHwnd)
            return

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
        } else if this.isListBox {
            ; The bar is hidden, so the control's own WM_VSCROLL handling is
            ; off; its top-index message is not.
            static LB_SETTOPINDEX := 0x0197
            info := this.GetScrollInfo()
            SendMessage(LB_SETTOPINDEX, Max(info.min, Min(pos, info.max)), 0, this.targetHwnd)
        } else if this.isEdit {
            static EM_LINESCROLL := 0x00B6, EM_GETFIRSTVISIBLELINE := 0x00CE
            info := this.GetScrollInfo()
            pos := Max(info.min, Min(pos, info.max))
            delta := pos - SendMessage(EM_GETFIRSTVISIBLELINE, 0, 0, this.targetHwnd)
            if delta
                SendMessage(EM_LINESCROLL, 0, delta, this.targetHwnd)
        } else if this.isTreeView {
            ; A TreeView ignores SB_THUMBPOSITION but honours line steps, so
            ; walk it. Capped so a huge jump cannot spin the message loop.
            static SB_LINEUP := 0, SB_LINEDOWN_TV := 1
            info := this.GetScrollInfo()
            pos := Max(info.min, Min(pos, info.max))
            delta := pos - info.pos
            code := delta > 0 ? SB_LINEDOWN_TV : SB_LINEUP
            steps := Min(Abs(delta), 500)
            Loop steps
                DllCall("SendMessage", "Ptr", this.targetHwnd, "UInt", WM_VSCROLL, "Ptr", code, "Ptr", 0)
        } else {
            ; Generic path: SB_THUMBPOSITION with the position in the high word.
            ; WM_VSCROLL carries only 16 bits of position, so saturate at
            ; [0, 0xFFFF] — masking alone would WRAP out-of-range positions
            ; (pos 65536 -> 0, negative nMin -> huge) instead of clamping.
            info := this.GetScrollInfo()
            pos := Max(info.min, Min(pos, info.max))
            pos := Max(0, Min(pos, 0xFFFF))
            DllCall("SendMessage", "Ptr", this.targetHwnd, "UInt", WM_VSCROLL,
                "Ptr", (pos << 16) | SB_THUMBPOSITION, "Ptr", 0)
        }

        DllCall("InvalidateRect", "Ptr", this.hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    SyncFromTarget() {
        ; Self-destroy once the host dies (normally the host's NCDESTROY branch
        ; handles this; this is the belt-and-braces path when TargetProc
        ; outlives the host, e.g. target and host in different windows).
        if !DllCall("IsWindow", "Ptr", this.hwnd) {
            this.Destroy()
            return
        }
        ; Repaint only when the thumb actually moved — TargetProc calls this on
        ; every target repaint, so the early-out keeps the steady-state cost at
        ; a few messages per actual scroll change, not per paint.
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
     * Moves and resizes the scrollbar control. Manual placement only — an
     * attached rail re-derives its geometry from the target on the next move
     * or resize and will overwrite this.
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
        this._destroyed := true
        this._StopAnim()
        this._RestoreNativeBar()
        if this.syncTimer {
            SetTimer(this.syncTimer, 0)
            this.syncTimer := 0
        }
        ; Deferred frees throughout: Destroy can be reached from inside either
        ; proc (host NCDESTROY, or SyncFromTarget's dead-host check running in
        ; TargetProc), and an immediate CallbackFree would release the thunk
        ; that is executing this very call.
        Subclass.Uninstall(this, this.hwnd, true)
        Subclass.Uninstall(this, this.targetHwnd, true)
        if DarkScrollbar.Instances.Has(this.hwnd)
            DarkScrollbar.Instances.Delete(this.hwnd)
    }
}

/**
 * Dark-themed ListView with custom-drawn header and items.
 * Uses NM_CUSTOMDRAW for item/header colors; scrollbars come from the
 * DarkMode_Explorer theme. (An owner-clipped arrow-hiding subclass existed
 * here once but was never wired to SetDarkMode — removed as dead code.)
 */
class _DarkListView {

    static __New() {
        static LVM_GETHEADER := 0x101F
        Gui.ListView.Prototype.GetHeader := SendMessage.Bind(LVM_GETHEADER, 0, 0)
    }

    /** Distinct Subclass owner key for the checkbox-state subclass, so it can
     *  never collide with another subclass this class installs on the hwnd. */
    class Checkbox {
    }

    /** Handler protocol entry ({@link DarkGui.Register}). */
    static Apply(owner, ctrl, options := "", content?) {
        this.SetDarkMode(ctrl)
    }

    /** Palette swap: re-send the LVM colours and rebuild the checkbox glyphs. */
    static Refresh(ctrl) {
        this.RefreshColors(ctrl.Hwnd)
    }

    /** Parent-side NM_CUSTOMDRAW (item colours) via DarkWindowProc's child registry. */
    static OnNotify(nm, lParam, &handled) {
        static NM_CUSTOMDRAW := -12
        handled := (nm.code = NM_CUSTOMDRAW)
        return handled ? this._ItemCustomDraw(lParam) : 0
    }

    /** Control-side proc: the stored LVM colours follow the enabled state, and
     *  a `+Checked` added after styling (lv.Opt) gets the dark state list. */
    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_ENABLE := 0x000A
        static LVM_SETEXTENDEDLISTVIEWSTYLE := 0x1036, LVM_GETEXTENDEDLISTVIEWSTYLE := 0x1037
        static LVS_EX_CHECKBOXES := 0x4
        if msg = WM_ENABLE {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            this.RefreshColors(targetHwnd)
            return result
        }
        if msg = LVM_SETEXTENDEDLISTVIEWSTYLE {
            ; comctl32 builds its LIGHT state list on the off->on transition;
            ; swap in the dark one right after (SetDarkCheckboxes frees the
            ; auto-created list and installs the insert-state subclass).
            hadBoxes := SendMessage(LVM_GETEXTENDEDLISTVIEWSTYLE, 0, 0, targetHwnd) & LVS_EX_CHECKBOXES
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            hasBoxes := SendMessage(LVM_GETEXTENDEDLISTVIEWSTYLE, 0, 0, targetHwnd) & LVS_EX_CHECKBOXES
            if !hadBoxes && hasBoxes {
                ctrl := GuiCtrlFromHwnd(targetHwnd) ?? 0
                if ctrl
                    this.SetDarkCheckboxes(ctrl)
            }
            return result
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /**
     * Removes the tracking entry and the checkbox subclass for a ListView.
     * @param {Ptr} hwnd - ListView window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        Subclass.Uninstall(_DarkListView.Checkbox, hwnd)
        DarkWindowProc.UnregisterChild(hwnd)
    }

    /**
     * Applies dark mode to a ListView control.
     * Sets body/text/grid colors, custom-draws header and items via
     * `NM_CUSTOMDRAW`, applies `DarkMode_Explorer` theme for dark scrollbars,
     * and removes the default border.
     *
     * @param {Gui.ListView} lv - ListView control instance.
     */
    static SetDarkMode(lv) {
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
        ; Hot-track so the header painter gets CDIS_HOT for the hovered column.
        static GWL_STYLE := -16, HDS_HOTTRACK := 0x4
        if lv.Header {
            hdrStyle := DllCall("GetWindowLongPtr", "Ptr", lv.Header, "Int", GWL_STYLE, "Ptr")
            if !(hdrStyle & HDS_HOTTRACK)
                DllCall("SetWindowLongPtr", "Ptr", lv.Header, "Int", GWL_STYLE, "Ptr", hdrStyle | HDS_HOTTRACK)
        }

        ; Set ListView body colors, grid line and drag insert-mark colors
        static LVM_SETOUTLINECOLOR := 0x1047, LVM_SETINSERTMARKCOLOR := 0x10AA
        SendMessage(LVM_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), lv)
        SendMessage(LVM_SETTEXTBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), lv)
        SendMessage(LVM_SETTEXTCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), lv)
        SendMessage(LVM_SETOUTLINECOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["GridLine"]), lv)
        SendMessage(LVM_SETINSERTMARKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Accent"]), lv)

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
                        static HDI_FORMAT := 0x4
                        static HDF_RIGHT := 0x1, HDF_CENTER := 0x2, HDF_JUSTIFYMASK := 0x3
                        static HDF_SORTUP := 0x400, HDF_SORTDOWN := 0x200
                        static DT_RIGHT := 0x2
                        hdc := nmcd.hdc
                        itemIndex := nmcd.dwItemSpec

                        ; Static scratch — this fires per header item per paint
                        ; (every column hover/track), so don't re-allocate.
                        static rc := DM_RECT(), rcText := DM_RECT()
                        static textBuf := Buffer(256, 0)
                        static hdItem := DM_HDITEMW()
                        SendMessage(HDM_GETITEMRECT, itemIndex, rc.Ptr, lv.Header)

                        ; Hover feedback: HDS_HOTTRACK (set in SetDarkMode) makes
                        ; the header report CDIS_HOT for the column under the mouse.
                        static CDIS_HOT := 0x40
                        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush((nmcd.uItemState & CDIS_HOT) ? "ControlsHover" : "Background"), "Void")

                        hdItem.mask       := HDI_TEXT | HDI_FORMAT
                        hdItem.pszText    := textBuf.Ptr
                        hdItem.cchTextMax := 128
                        hdItem.fmt        := 0
                        SendMessage(HDM_GETITEM, itemIndex, hdItem.Ptr, lv.Header)

                        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
                        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")

                        left := rc.left + DarkTheme.Scale(8)
                        top := rc.top
                        right := rc.right - DarkTheme.Scale(4)
                        bottom := rc.bottom
                        rcText.left := left, rcText.top := top, rcText.right := right, rcText.bottom := bottom

                        ; CDRF_SKIPDEFAULT suppresses ALL native drawing, so
                        ; column alignment and sort indicators must be redrawn
                        ; here or HDF_RIGHT/HDF_CENTER and HDM_SETITEM sort
                        ; arrows silently vanish on dark headers.
                        align := (hdItem.fmt & HDF_JUSTIFYMASK) = HDF_RIGHT ? DT_RIGHT
                            : (hdItem.fmt & HDF_JUSTIFYMASK) = HDF_CENTER ? DT_CENTER : 0
                        DllCall("DrawTextW", "Ptr", hdc, "Ptr", textBuf.Ptr, "Int", -1, "Ptr", rcText, "UInt", DT_VCENTER | DT_SINGLELINE | align, "Void")

                        if hdItem.fmt & (HDF_SORTUP | HDF_SORTDOWN) {
                            cx := (rc.left + rc.right) // 2
                            cy := rc.top + DarkTheme.Scale(4)
                            DarkTheme.PaintChevron(hdc, cx, cy, DarkTheme.Scale(3), DarkTheme.Scale(2),
                                DarkTheme.Colors["FontDim"], (hdItem.fmt & HDF_SORTUP) != 0)
                        }

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
        DarkWindowProc.RegisterChild(lv.Hwnd, _DarkListView)
        ; Enabled-state transitions re-push the stored LVM colours (disabled
        ; lists dim); reclaimed by Subclass._Wrap on WM_NCDESTROY.
        Subclass.InstallProc(this, lv.Hwnd)

        ; Item colors need the parent to answer NM_CUSTOMDRAW. Two cases lack
        ; that: inside a Tab3 the parent is the tab's internal #32770 page
        ; dialog (not the DarkGui frame), and a direct SetDarkMode call on a
        ; plain Gui has no DarkWindowProc at all. Relay both.
        DarkWindowProc.EnsureParentRelay(lv)

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
    }

    /**
     * Re-sends the message-baked body/text/grid colors from the live palette
     * and rebuilds the dark checkbox state list when +Checked is active.
     * SetPalette rebuilds brushes, but colors a control STORES (sent once via
     * LVM_SET*COLOR, or baked into checkbox glyph pixels) go stale on a
     * palette swap — {@link _DarkPaletteSync} calls this for every tracked
     * ListView. Safe to call repeatedly; registers no message hooks.
     * @param {Ptr} hwnd - ListView window handle
     */
    static RefreshColors(hwnd) {
        static LVM_SETBKCOLOR := 0x1001
        static LVM_SETTEXTBKCOLOR := 0x1026
        static LVM_SETTEXTCOLOR := 0x1024
        static LVM_SETOUTLINECOLOR := 0x1047, LVM_SETINSERTMARKCOLOR := 0x10AA
        static LVM_GETEXTENDEDLISTVIEWSTYLE := 0x1037
        static LVS_EX_CHECKBOXES := 0x4
        enabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        bg := enabled ? "Controls" : "DisabledBg"
        SendMessage(LVM_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors[bg]), hwnd)
        SendMessage(LVM_SETTEXTBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors[bg]), hwnd)
        SendMessage(LVM_SETTEXTCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? "Font" : "DisabledText"]), hwnd)
        SendMessage(LVM_SETOUTLINECOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["GridLine"]), hwnd)
        SendMessage(LVM_SETINSERTMARKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Accent"]), hwnd)
        if SendMessage(LVM_GETEXTENDEDLISTVIEWSTYLE, 0, 0, hwnd) & LVS_EX_CHECKBOXES {
            ctrl := GuiCtrlFromHwnd(hwnd) ?? 0
            if ctrl
                this.SetDarkCheckboxes(ctrl)
        }
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
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

    /** Parent-side NM_CUSTOMDRAW reply (invoked from DarkWindowProc.Proc and
     * DarkWindowProc.NotifyRelayProc): palette text color on every row, with
     * the Selection fill kept even when the ListView is unfocused.
     *
     * ListView custom draw takes its colors from NMLVCUSTOMDRAW.clrText /
     * clrTextBk — SetTextColor/SetBkColor on the hdc are ignored here. And the
     * themed (Explorer) painter draws its own light selection fill over
     * clrTextBk on rows carrying CDIS_SELECTED, so a selected row is filled
     * with the palette Selection brush manually and CDIS_SELECTED is stripped
     * before default paint — the standard dark-mode recipe. */
    static _ItemCustomDraw(lParam) {
        static CDDS_PREPAINT := 0x1
        static CDDS_ITEMPREPAINT := 0x10001
        static CDRF_DODEFAULT := 0x0
        static CDRF_NOTIFYITEMDRAW := 0x20
        static CDRF_NEWFONT := 0x2
        static CDIS_SELECTED := 0x1
        static LVM_GETITEMRECT := 0x100E
        static LVM_GETITEMSTATE := 0x102C
        static LVIS_SELECTED := 0x2
        static LVIR_BOUNDS := 0

        static LVCDI_ITEM := 0x0, LVCDI_GROUP := 0x1, LVCDI_ITEMSLIST := 0x2

        lvcd := DM_NMLVCUSTOMDRAW.At(lParam)
        switch lvcd.nmcd.dwDrawStage {
            case CDDS_PREPAINT:
                return CDRF_NOTIFYITEMDRAW
            case CDDS_ITEMPREPAINT:
                ; With LVM_ENABLEGROUPVIEW the group headers arrive at this
                ; stage too, with dwItemSpec = group id, so the row logic below
                ; would query item states with a group id. Colour them from
                ; the palette (header text + rule line) and stop.
                if lvcd.dwItemType = LVCDI_GROUP {
                    lvcd.clrText := DarkTheme.RGBtoBGR(DarkTheme.Colors["FontDim"])
                    lvcd.clrFace := DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"])
                    return CDRF_NEWFONT
                }
                if lvcd.dwItemType = LVCDI_ITEMSLIST
                    return CDRF_DODEFAULT
                ; A disabled list dims rows like every other message-colored
                ; control and drops the selection highlight.
                enabled := DllCall("IsWindowEnabled", "Ptr", lvcd.nmcd.hdr.hwndFrom)
                lvcd.clrText := DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? "Font" : "DisabledText"])
                if !enabled {
                    lvcd.clrTextBk := DarkTheme.RGBtoBGR(DarkTheme.Colors["DisabledBg"])
                    lvcd.nmcd.uItemState := lvcd.nmcd.uItemState & ~CDIS_SELECTED
                    return CDRF_NEWFONT
                }
                ; uItemState's CDIS_SELECTED is unreliable in ListView custom
                ; draw (set on unselected rows too) — query the real state.
                selected := SendMessage(LVM_GETITEMSTATE, lvcd.nmcd.dwItemSpec, LVIS_SELECTED, lvcd.nmcd.hdr.hwndFrom) & LVIS_SELECTED
                if selected {
                    rcItem := DM_RECT()
                    rcItem.left := LVIR_BOUNDS
                    if SendMessage(LVM_GETITEMRECT, lvcd.nmcd.dwItemSpec, rcItem.Ptr, lvcd.nmcd.hdr.hwndFrom)
                        DllCall("FillRect", "Ptr", lvcd.nmcd.hdc, "Ptr", rcItem.Ptr,
                            "Ptr", DarkTheme.GetSolidBrush(DarkTheme.Colors["Selection"]), "Int")
                    lvcd.clrTextBk := DarkTheme.RGBtoBGR(DarkTheme.Colors["Selection"])
                    lvcd.nmcd.uItemState := lvcd.nmcd.uItemState & ~CDIS_SELECTED
                } else {
                    lvcd.clrTextBk := DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"])
                }
                return CDRF_NEWFONT
        }
        return CDRF_DODEFAULT
    }

    static InstallCheckboxSubclass(lv) {
        hwnd := lv.Hwnd
        ; Re-applying SetDarkMode must not stack a second subclass: Subclass
        ; refuses a duplicate (owner, hwnd) pair and reclaims on WM_NCDESTROY.
        if !Subclass.Install(_DarkListView.Checkbox, hwnd, ObjBindMethod(this, "CheckboxSubclassProc", hwnd))
            return

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

    static CheckboxSubclassProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static LVM_INSERTITEMA := 0x1007
        static LVM_INSERTITEMW := 0x104D
        static LVM_SETITEMSTATE := 0x102B
        static LVIS_STATEIMAGEMASK := 0xF000

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

        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }
}

/**
 * Owner-draw dark button with hover/pressed states and rounded corners.
 * Supports both standard dark buttons and accent-colored (blue) buttons.
 * Use mode `"accent"` for primary action buttons.
 *
 * Uses window subclassing for complete control rendering via {@link Subclass}.
 */
class _DarkButton {

    /**
     * Handler protocol entry ({@link DarkGui.Register}). Reads the dark option
     * grammar — "+Accent", "+Flat", "+Toggle[=on]", "+Icon=<spec> [+Align=..]"
     * — so every variant except Split (which needs a Menu object) can be
     * created through a plain Add("Button", ...). The legacy positional mode
     * string ("accent") is still accepted.
     */
    static Apply(owner, ctrl, options := "", content?) {
        opts := DarkGui.ParseOptions(options)
        if options = "accent"
            opts["accent"] := true
        s := this._State(ctrl.Hwnd)
        mode := "default"
        if opts.Has("icon") && opts["icon"] is String {
            owned := false
            s.icon := this._ResolveIcon(opts["icon"], &owned, DarkTheme.Scale(16, ctrl.Hwnd))
            s.iconOwned := owned
            s.iconAlign := opts.Has("align") ? StrLower(opts["align"]) : "left"
            mode := "icon"
        } else if opts.Has("toggle") {
            s.toggle := opts["toggle"] is String && (opts["toggle"] = "on" || opts["toggle"] = "1")
            this._DefineToggleProp(ctrl)
            mode := "toggle"
        } else if opts.Has("flat") {
            mode := "flat"
        } else if opts.Has("accent") {
            mode := "accent"
        }
        this.ApplyDarkMode(ctrl, mode)
    }

    /** NCDESTROY reclaim via {@link Subclass._Wrap}: frees an owned icon and
     *  the state record when the window dies without _Teardown. */
    static OnDestroyed(hwnd) {
        if !this.State.Has(hwnd)
            return
        s := this.State[hwnd]
        if s.iconOwned && s.icon
            DllCall("DestroyIcon", "Ptr", s.icon, "Void")
        this.State.Delete(hwnd)
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
        this._DefineToggleProp(btn)
        this._RegisterWithGui(gui, btn.Hwnd)
        this.ApplyDarkMode(btn, "toggle")
        return btn
    }

    /** Exposes the latch as `btn.IsToggled` (get/set; a set repaints). */
    static _DefineToggleProp(btn) {
        btn.DefineProp("IsToggled", {
            Get: (b) => _DarkButton._State(b.Hwnd).toggle,
            Set: (b, v) => (_DarkButton._State(b.Hwnd).toggle := !!v,
                            DllCall("InvalidateRect", "Ptr", b.Hwnd, "Ptr", 0, "Int", 1, "Void"), 0)
        })
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
            hicon := DllCall("shell32\ExtractIconW", "Ptr", 0, "Str", iconPath, "UInt", idx, "Ptr")
            ; ExtractIconW returns 1 (not NULL) for a file that isn't an
            ; exe/DLL/icon — treating that sentinel as an HICON makes every
            ; paint silently draw nothing and Remove later DestroyIcon(1).
            if hicon <= 1 {
                owned := false
                return 0
            }
            return hicon
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
    static _RegisterWithGui(owner, hwnd) {
        DarkGui._Track(owner, hwnd, "button")
    }

    static ButtonProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F
        static WM_ENABLE := 0x000A
        static WM_ERASEBKGND := 0x0014
        static WM_MOUSEMOVE := 0x0200
        static WM_MOUSELEAVE := 0x02A3
        static WM_LBUTTONDOWN := 0x0201
        static WM_LBUTTONUP := 0x0202
        static WM_LBUTTONDBLCLK := 0x0203
        static WM_CAPTURECHANGED := 0x0215
        static WM_NCDESTROY := 0x0082

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

        if msg = WM_NCDESTROY {
            ; Reclaim (thunk, registry key, owned icon, state record) happens in
            ; Subclass._Wrap via OnDestroyed. Return BEFORE the _State() call
            ; below so the record isn't recreated on the way out.
            return Subclass.Forward(hwnd, msg, wParam, lParam)
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

        ; WM_LBUTTONDBLCLK: BUTTON registers CS_DBLCLKS, so the second press of
        ; a double-click arrives as DBLCLK — treat it as a plain press or every
        ; second click is silently lost (native buttons fire twice).
        if msg = WM_LBUTTONDOWN || msg = WM_LBUTTONDBLCLK {
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
            ; Keep native default/nondefault push-button and mnemonic flags.
            ; Split buttons additionally claim arrows for their Down action.
            nativeCode := Subclass.Forward(hwnd, msg, wParam, lParam)
            return nativeCode | (this._IsSplitButton(targetHwnd) ? DLGC_WANTARROWS : 0)
        }

        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS {
            s.focus := (msg = WM_SETFOCUS)
            ; Focus loss also cancels a held Space press — otherwise Alt+Tab
            ; mid-press leaves s.pressed latched and a stray space-up after
            ; refocus fires a phantom click.
            if msg = WM_KILLFOCUS
                s.pressed := false
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }

        ; Keyboard-cue transitions (Alt pressed, Tab used, a mouse click):
        ; repaint so the ring and the mnemonic underline come and go like native.
        static WM_UPDATEUISTATE := 0x0128
        if msg = WM_UPDATEUISTATE {
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }

        ; Capture stolen mid-press (menu popped, foreground change): the release
        ; will go elsewhere, so cancel the press or the button renders pressed
        ; forever and a later bare WM_LBUTTONUP fires a phantom click.
        if msg = WM_CAPTURECHANGED {
            if s.pressed || s.hoverArrow {
                s.pressed := false
                s.hoverArrow := false
                DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            }
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
        if !DllCall("IsWindowEnabled", "Ptr", hwnd, "Int")
            return
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
        if !DllCall("IsWindowEnabled", "Ptr", hwnd, "Int")
            return
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

        ; Keyboard focus ring on top of whatever the mode drew — only while the
        ; window shows keyboard cues. Native buttons hide the rect after a
        ; mouse click until the keyboard is used (UISF_HIDEFOCUS).
        if s.focus && !(DarkTheme.UiState(hwnd) & DarkTheme.UISF_HIDEFOCUS)
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
    /** Draws caption text; the "&" mnemonic underline follows the window's
     *  keyboard-cue state (UISF_HIDEACCEL -> DT_HIDEPREFIX) like native controls. */
    static _DrawText(hwnd, hdc, text, rect, color, flags) {
        static DT_HIDEPREFIX := 0x00100000
        if DarkTheme.UiState(hwnd) & DarkTheme.UISF_HIDEACCEL
            flags |= DT_HIDEPREFIX
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
        this._DrawText(hwnd, hdc, s.text, rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
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
            this._DrawText(hwnd, hdc, btnText, textRc, colors[2], DT_CENTER | DT_SINGLELINE)
        } else if align = "right" && hicon {
            ix := w - iconSize - pad
            iy := (h - iconSize) // 2
            this._DrawIcon(hdc, hicon, ix, iy, iconSize)
            textRc := this._MakeRect(pad, 0, ix - 2, h)
            this._DrawText(hwnd, hdc, btnText, textRc, colors[2], DT_LEFT | DT_VCENTER | DT_SINGLELINE)
        } else if hicon {
            ; "left" (default)
            ix := pad
            iy := (h - iconSize) // 2
            this._DrawIcon(hdc, hicon, ix, iy, iconSize)
            textRc := this._MakeRect(ix + iconSize + 4, 0, w - pad, h)
            this._DrawText(hwnd, hdc, btnText, textRc, colors[2], DT_LEFT | DT_VCENTER | DT_SINGLELINE)
        } else {
            ; No icon — fall back to centered text
            this._DrawText(hwnd, hdc, btnText, rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
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

        ; Win11-feel: hover lifts subtly, press goes darker than rest.
        ; Disabled: use the dimmed base fill and skip the hover/press ladder —
        ; every other mode paints baseColors[1], and without this a disabled
        ; split button kept the full-strength Controls fill (only text dimmed).
        if !DllCall("IsWindowEnabled", "Ptr", hwnd) {
            mainBg := baseColors[1]
            arrowBg := baseColors[1]
        } else {
            mainHover := isHover && !hoverArrow
            mainBg := isPressed && !hoverArrow ? DarkTheme.Colors["ButtonPressed"]
                    : (mainHover ? DarkTheme.Colors["ButtonHover"] : DarkTheme.Colors["Controls"])
            arrowHover := isHover && hoverArrow
            arrowBg := isPressed && hoverArrow ? DarkTheme.Colors["ButtonPressed"]
                     : (arrowHover ? DarkTheme.Colors["ButtonHover"] : DarkTheme.Colors["Controls"])
        }

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
        this._DrawText(hwnd, hdc, s.text, textRc, baseColors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
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
        cmdTitle := s.text
        desc := s.desc

        oldFont := this._SelectButtonFont(hwnd, hdc)
        ; Layout from the real font height, not a fixed 22px band: the title
        ; sits in the top band and the description below it. When the caller's
        ; height cannot fit a description line (h52 at 125% DPI left 6px), the
        ; title is centred instead of the description being clipped away.
        tm := DM_TEXTMETRICW()
        DllCall("GetTextMetricsW", "Ptr", hdc, "Ptr", tm.Ptr)
        lineH := tm.tmHeight
        gap := DarkTheme.Scale(2, hwnd)
        bottomPad := DarkTheme.Scale(6, hwnd)
        descTop := pad + lineH + gap
        showDesc := desc != "" && h - descTop - bottomPad >= lineH

        iconAreaX := pad
        iconAreaY := showDesc ? pad : (h - iconSize) // 2
        if hicon {
            this._DrawIcon(hdc, hicon, iconAreaX, iconAreaY, iconSize)
        } else {
            this._PaintRightArrow(hdc, iconAreaX + iconSize // 2, iconAreaY + iconSize // 2,
                                  DarkTheme.Scale(7, hwnd), DarkTheme.Colors["Accent"])
        }

        textLeft := iconAreaX + iconSize + pad
        static DT_LEFT := 0x0, DT_TOP := 0x0, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20, DT_WORDBREAK := 0x10, DT_END_ELLIPSIS := 0x8000
        if showDesc {
            titleRc := this._MakeRect(textLeft, pad, w - pad, pad + lineH)
            this._DrawText(hwnd, hdc, cmdTitle, titleRc, colors[2], DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS)
            descRc := this._MakeRect(textLeft, descTop, w - pad, h - bottomPad)
            this._DrawText(hwnd, hdc, desc, descRc, DarkTheme.Colors["FontDim"], DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS)
        } else {
            titleRc := this._MakeRect(textLeft, 0, w - pad, h)
            this._DrawText(hwnd, hdc, cmdTitle, titleRc, colors[2], DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS)
        }

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
        this._DrawText(hwnd, hdc, s.text, rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
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
        this._DrawText(hwnd, hdc, s.text, rc, textColor, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
    }
}

/**
 * Owner-draw ComboBox with custom-drawn main control and styled dropdown.
 * Handles WM_PAINT for stable text rendering and rounded corners.
 */
class _DarkComboBox {

    static Cues := Map()

    static __New() {
        ; Placeholder text (CB_SETCUEBANNER): `combo.SetCue("Pick one")`. Shown
        ; in the edit of a ComboBox, or in the face of a DDL with no selection.
        Gui.ComboBox.Prototype.DefineProp("SetCue", { Call: (ctrl, text) => _DarkComboBox.SetCue(ctrl, text) })
        Gui.DDL.Prototype.DefineProp("SetCue", { Call: (ctrl, text) => _DarkComboBox.SetCue(ctrl, text) })
    }

    static SetCue(ctrl, text) {
        static CB_SETCUEBANNER := 0x1703
        text := String(text)
        SendMessage(CB_SETCUEBANNER, 0, StrPtr(text), ctrl)
        ; The DDL face is painted here, so Windows cannot draw its cue for us.
        ; Keep state only for controls whose lifetime this subclass observes.
        if Subclass.IsInstalled(this, ctrl.Hwnd) {
            this.Cues[ctrl.Hwnd] := text
            DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
        }
        return text
    }

    static OnDestroyed(hwnd) {
        if this.Cues.Has(hwnd)
            this.Cues.Delete(hwnd)
    }

    /** Handler protocol entry for ComboBox AND DDL (full parity: same
     *  owner-draw face; DDL additionally opts into the OS dark-mode engine). */
    static Apply(owner, ctrl, options := "", content?) {
        if ctrl.Type = "DDL"
            DarkTheme.AllowDarkMode(ctrl.Hwnd)
        this.ApplyDarkMode(ctrl)
    }

    /** Palette swap: the caption colour is font-baked, re-push it. */
    static Refresh(ctrl) {
        ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
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

        ; Style the dropdown list (the ListBox part): dark scrollbar theme, and
        ; a child handler so WM_CTLCOLORLISTBOX fills it with Background.
        listHwnd := this._ListHwnd(combo.Hwnd)
        if listHwnd {
            DllCall("uxtheme\SetWindowTheme", "Ptr", listHwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
            DarkWindowProc.RegisterChild(listHwnd, _DarkComboBox.DropdownList)
        }
        ; An editable ComboBox types into an internal Edit whose 1px caret
        ; vanishes on the dark fill exactly like a plain Edit's; give it the
        ; same 2px caret. The combo reflects that edit's WM_CTLCOLOREDIT to
        ; the parent, so its colours are already dark.
        editHwnd := this._EditHwnd(combo.Hwnd)
        if editHwnd && editHwnd != combo.Hwnd
            _DarkCaret.Apply(editHwnd)

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
        this.OnDestroyed(hwnd)
        if !DllCall("IsWindow", "Ptr", hwnd)
            return
        listHwnd := this._ListHwnd(hwnd)
        if listHwnd
            DarkWindowProc.UnregisterChild(listHwnd)
        editHwnd := this._EditHwnd(hwnd)
        if editHwnd && editHwnd != hwnd
            _DarkCaret.Remove(editHwnd)
    }

    /** Child handler for the dropdown list: Background fill to match the window. */
    class DropdownList {
        static OnCtlColor(hwndCtl, hdc, msg) {
            return DarkWindowProc.CtlColorReply(hdc, "Font", "Background")
        }
    }

    /** The ComboBox's internal Edit hwnd (0 for a DDL or when unavailable). */
    static _EditHwnd(hwnd) {
        static CB_GETCOMBOBOXINFO := 0x0164
        cbi := DM_COMBOBOXINFO()
        cbi.cbSize := cbi.Size
        if !DllCall("SendMessage", "Ptr", hwnd, "UInt", CB_GETCOMBOBOXINFO, "Ptr", 0, "Ptr", cbi.Ptr)
            return 0
        return cbi.hwndItem
    }

    /** The ComboBox's internal dropdown ListBox hwnd (0 when unavailable). */
    static _ListHwnd(hwnd) {
        static CB_GETCOMBOBOXINFO := 0x0164
        cbi := DM_COMBOBOXINFO()
        cbi.cbSize := cbi.Size
        if !DllCall("SendMessage", "Ptr", hwnd, "UInt", CB_GETCOMBOBOXINFO, "Ptr", 0, "Ptr", cbi.Ptr)
            return 0
        return cbi.hwndList
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

        ; Disabled combos dim like the owner-draw buttons do — full-bright
        ; Font/Controls here read as still-enabled.
        enabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        fontColor := DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? "Font" : "DisabledText"])

        ; Cached palette brushes — do not delete them
        bgBrush := DarkTheme.GetBrush("Background")
        ctrlBrush := DarkTheme.GetBrush(enabled ? "Controls" : "DisabledBg")

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
            DarkTheme.Scale(4, hwnd), DarkTheme.Scale(3, hwnd), DarkTheme.Colors[enabled ? "Font" : "DisabledText"])

        ; Step 5: Draw text
        static WM_GETTEXT := 0x000D
        static WM_GETTEXTLENGTH := 0x000E
        static WM_GETFONT := 0x0031
        textLen := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETTEXTLENGTH, "Ptr", 0, "Ptr", 0, "Int")
        static CB_GETCURSEL := 0x0147, GWL_STYLE := -16, CBS_DROPDOWNLIST := 3
        isDDL := (DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr") & 0x3) = CBS_DROPDOWNLIST
        noSelection := DllCall("SendMessage", "Ptr", hwnd, "UInt", CB_GETCURSEL, "Ptr", 0, "Ptr", 0, "Int") = -1
        cue := isDDL && noSelection ? this.Cues.Get(hwnd, "") : ""
        if cue != "" {
            textLen := StrLen(cue)
            fontColor := DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? "FontDim" : "DisabledText"])
        }
        if textLen > 0 {
            textBuf := Buffer((textLen + 1) * 2, 0)
            if cue != ""
                StrPut(cue, textBuf, "UTF-16")
            else
                DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETTEXT, "Ptr", textLen + 1, "Ptr", textBuf)

            DllCall("SetTextColor", "Ptr", hdc, "UInt", fontColor, "Void")
            DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")  ; TRANSPARENT

            hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
            hOldFont := 0
            if hFont
                hOldFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")

            rcText := DM_RECT()
            ; Per-window DPI like the chevron above — mixing Scale(n) (system
            ; DPI) with Scale(n, hwnd) breaks the 12px text/chevron clearance
            ; on a monitor whose DPI differs from the system DPI.
            rcText.left := DarkTheme.Scale(6, hwnd), rcText.top := 0, rcText.right := w - DarkTheme.Scale(24, hwnd), rcText.bottom := h
            static DT_SINGLELINE := 0x20, DT_VCENTER := 0x4, DT_NOPREFIX := 0x800
            DllCall("DrawTextW", "Ptr", hdc, "Ptr", textBuf, "Int", -1, "Ptr", rcText, "UInt", DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX, "Void")

            if hOldFont
                DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldFont, "Void")
        }

        ; Cleanup (bgBrush/ctrlBrush are cached — restore, don't delete)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldPen, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldBrush, "Void")
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Void")
    }
}

/**
 * Custom-drawn Slider with GDI+ anti-aliased thumb. Features circular knob
 * with blue accent border, double-buffered rendering to prevent artifacts.
 */
class _DarkSlider {

    static __New() {
        DarkTheme.DefineColor("SliderThumb", 0xFFFFFF, 0x2A2A2A)
    }

    /** Handler protocol entry ({@link DarkGui.Register}). */
    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    /**
     * Applies custom owner-draw dark mode to slider. GDI+ (the anti-aliased
     * thumb) is started by DarkTheme at load.
     * @param {Gui.Slider} slider - Slider control instance
     */
    static ApplyDarkMode(slider) {
        ; Set empty theme to disable themed drawing
        DllCall("uxtheme\SetWindowTheme", "Ptr", slider.Hwnd, "WStr", "", "WStr", "")

        ; Subclass for custom drawing
        this.SubclassSlider(slider.Hwnd)

        DllCall("InvalidateRect", "Ptr", slider.Hwnd, "Ptr", 0, "Int", true, "Void")
    }

    static SubclassSlider(hwnd) {
        Subclass.Install(this, hwnd, ObjBindMethod(this, "SliderProc", hwnd))
    }

    /** 1px line with the currently selected pen. */
    static _Line(hdc, x1, y1, x2, y2) {
        DllCall("MoveToEx", "Ptr", hdc, "Int", x1, "Int", y1, "Ptr", 0, "Void")
        DllCall("LineTo", "Ptr", hdc, "Int", x2, "Int", y2, "Void")
    }

    /**
     * Removes subclass and frees resources for a Slider.
     * @param {Ptr} hwnd - Slider window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
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

        ; Force full invalidation on mouse events that move the thumb. Plain
        ; hover moves (no button, no capture) can't move it — skipping them
        ; avoids a full double-buffered GDI+ repaint per pixel of mouse travel.
        if msg = WM_LBUTTONDOWN || msg = WM_MOUSEMOVE || msg = WM_LBUTTONUP {
            static MK_LBUTTON := 0x1
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            if msg != WM_MOUSEMOVE || (wParam & MK_LBUTTON) || DllCall("GetCapture", "Ptr") = hwnd
                DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", true, "Void")
            return result
        }

        ; Keyboard and programmatic moves need the same full invalidation: our
        ; knob is drawn LARGER than the native thumb rect, but the trackbar
        ; invalidates only the union of the old/new NATIVE rects — BeginPaint
        ; then clips our redraw to it and the oversized knob's outer ring
        ; survives as residue. `slider.Value := x` arrives as TBM_SETPOS.
        static WM_KEYDOWN := 0x0100, WM_KEYUP := 0x0101
        static TBM_SETPOS := 0x0405, TBM_SETRANGE := 0x0406
        static TBM_SETRANGEMIN := 0x0407, TBM_SETRANGEMAX := 0x0408
        static TBM_SETPOSNOTIFY := 0x0422
        if msg = WM_KEYDOWN || msg = WM_KEYUP || msg = TBM_SETPOS || msg = TBM_SETPOSNOTIFY
            || msg = TBM_SETRANGE || msg = TBM_SETRANGEMIN || msg = TBM_SETRANGEMAX {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", true, "Void")
            return result
        }

        ; Enabled, focus and keyboard-cue transitions repaint the whole control
        ; (WM_ERASEBKGND is answered here, so nothing else would).
        static WM_ENABLE := 0x000A, WM_SETFOCUS := 0x0007, WM_KILLFOCUS := 0x0008, WM_UPDATEUISTATE := 0x0128
        if msg = WM_ENABLE || msg = WM_SETFOCUS || msg = WM_KILLFOCUS || msg = WM_UPDATEUISTATE {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
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

            ; TBM_GETCHANNELRECT reports the channel in HORIZONTAL orientation
            ; even for TBS_VERT trackbars (probe-verified: a 30x200 vertical
            ; slider returns a 230px-wide, 5px-high band). Transpose it, or a
            ; vertical slider renders a clipped stripe across the top and no
            ; track at all.
            static GWL_STYLE := -16, TBS_VERT := 0x2
            isVert := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr") & TBS_VERT
            if isVert {
                l := rcChannel.left, t := rcChannel.top
                r := rcChannel.right, b := rcChannel.bottom
                rcChannel.left := t, rcChannel.top := l
                rcChannel.right := b, rcChannel.bottom := r
            }

            ; Draw track/channel using actual rect from Windows; a disabled
            ; slider dims like every other message-colored control.
            enabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
            DllCall("FillRect", "Ptr", hdcMem, "Ptr", rcChannel, "Ptr", DarkTheme.GetBrush(enabled ? "Controls" : "DisabledBg"), "Void")

            ; Tick marks (TBS_AUTOTICKS / TBM_SETTIC), which the native paint
            ; drew and the owner-draw used to drop: the two end ticks at the
            ; channel ends plus the TBM_GETTICPOS interior ticks, on the side
            ; the style asks for (TBS_TOP/TBS_LEFT = before, TBS_BOTH = both).
            static TBS_NOTICKS := 0x10, TBS_TOP := 0x4, TBS_BOTH := 0x8
            static TBM_GETNUMTICS := 0x0410, TBM_GETTICPOS := 0x040F
            style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
            if !(style & TBS_NOTICKS) {
                positions := []
                positions.Push(isVert ? rcChannel.top : rcChannel.left)
                numTics := SendMessage(TBM_GETNUMTICS, 0, 0, hwnd)
                loop Max(numTics - 2, 0) {
                    pos := SendMessage(TBM_GETTICPOS, A_Index - 1, 0, hwnd)
                    if pos >= 0
                        positions.Push(pos)
                }
                positions.Push(isVert ? rcChannel.bottom - 1 : rcChannel.right - 1)
                tickLen := DarkTheme.Scale(4, hwnd)
                gap := DarkTheme.Scale(3, hwnd)
                before := (style & TBS_TOP) || (style & TBS_BOTH)
                after := !(style & TBS_TOP) || (style & TBS_BOTH)
                hPen := DarkTheme.GetPen(DarkTheme.Colors[enabled ? "FontDim" : "DisabledText"])
                oldPen := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hPen, "Ptr")
                for pos in positions {
                    if isVert {
                        if before
                            this._Line(hdcMem, rcChannel.left - gap - tickLen, pos, rcChannel.left - gap, pos)
                        if after
                            this._Line(hdcMem, rcChannel.right + gap, pos, rcChannel.right + gap + tickLen, pos)
                    } else {
                        if before
                            this._Line(hdcMem, pos, rcChannel.top - gap - tickLen, pos, rcChannel.top - gap)
                        if after
                            this._Line(hdcMem, pos, rcChannel.bottom + gap, pos, rcChannel.bottom + gap + tickLen)
                    }
                }
                DllCall("SelectObject", "Ptr", hdcMem, "Ptr", oldPen, "Void")
            }

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

            ; Center the circle; the 2px aesthetic lift applies along the
            ; slider's own axis (left for vertical, up for horizontal).
            centerX := thumbLeft + (thumbW // 2) - (isVert ? DarkTheme.Scale(2) : 0)
            centerY := thumbTop + (thumbH // 2) - (isVert ? 0 : DarkTheme.Scale(2))
            circleLeft := centerX - (diameter // 2)
            circleTop := centerY - (diameter // 2)
            circleRight := circleLeft + diameter
            circleBottom := circleTop + diameter

            ; Palette-driven thumb. GDI+ takes ARGB directly, so no BGR swap —
            ; OR in a full alpha byte. Previously hardcoded white/blue, which
            ; survived SetColor and ApplyPreset("Light") unchanged.
            fillColor := 0xFF000000 | DarkTheme.Colors[enabled ? "SliderThumb" : "DisabledBg"]
            borderColor := 0xFF000000 | DarkTheme.Colors[enabled ? "Accent" : "DisabledText"]
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

            ; Keyboard focus ring around the control, gated on the window's
            ; keyboard-cue state exactly like the buttons.
            if enabled && DllCall("GetFocus", "Ptr") = hwnd && !(DarkTheme.UiState(hwnd) & DarkTheme.UISF_HIDEFOCUS)
                DarkTheme.GdipRoundFill(hdcMem, 1, 1, clientW - 2, clientH - 2, DarkTheme.Scale(3, hwnd), -1, DarkTheme.Colors["Accent"], DarkTheme.Scale(1, hwnd) * 1.0)

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
 * Dark-themed Progress bar. Strips the visual style (the only way PBM
 * colours are honoured), forces PBS_SMOOTH so the classic renderer does not
 * fall back to segmented blocks, and paints the bar from the palette by
 * state: `prog.SetState("normal" | "error" | "paused")` selects Accent /
 * Error / Warning and survives palette swaps; `prog.SetMarquee(on, ms)`
 * toggles PBS_MARQUEE + PBM_SETMARQUEE. A disabled bar dims like every
 * other message-coloured control.
 */
class _DarkProgress {
    /** @type {Map} hwnd -> "normal" | "error" | "paused" */
    static States := Map()
    /** @type {Map} hwnd -> determinate position parked while marquee runs */
    static MarqueePos := Map()

    static __New() {
        Gui.Progress.Prototype.DefineProp("SetState", { Call: (p, state) => _DarkProgress.SetState(p, state) })
        Gui.Progress.Prototype.DefineProp("SetMarquee", { Call: (p, on := true, intervalMs := 30) => _DarkProgress.SetMarquee(p, on, intervalMs) })
    }

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        this.OnDestroyed(hwnd)
    }

    /** NCDESTROY reclaim via {@link Subclass._Wrap}. */
    static OnDestroyed(hwnd) {
        if this.States.Has(hwnd)
            this.States.Delete(hwnd)
        if this.MarqueePos.Has(hwnd)
            this.MarqueePos.Delete(hwnd)
    }

    /** Palette swap: PBM colours are stored by the control, re-send them. */
    static Refresh(ctrl) {
        this.ApplyDarkMode(ctrl)
    }

    /**
     * Applies dark theme colors to the progress bar.
     *
     * @param {Gui.Progress} prog - Progress bar control instance.
     */
    static ApplyDarkMode(prog) {
        static PBM_SETBKCOLOR := 0x2001, PBM_SETBARCOLOR := 0x0409
        static PBM_SETPOS := 0x0402, PBM_GETPOS := 0x0408
        static GWL_STYLE := -16, PBS_SMOOTH := 0x1
        hwnd := prog.Hwnd
        ; AHK sets PBS_SMOOTH only for callers who pass "Smooth"; without it the
        ; theme-stripped renderer draws 1990s blocks. The classic path reads
        ; the bit at paint time, so setting it after creation is enough.
        style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        if !(style & PBS_SMOOTH) {
            ; The style write zeroes the bar position, so save and restore it --
            ; otherwise a control created with a starting value paints empty.
            pos := SendMessage(PBM_GETPOS, 0, 0, hwnd)
            DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style | PBS_SMOOTH)
            if pos
                SendMessage(PBM_SETPOS, pos, 0, hwnd)
        }
        ; Both args must be empty strings -- a NULL pSubIdList leaves the themed
        ; renderer in place, which paints green-on-light and ignores PBM colours.
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "", "Str", "")
        enabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        SendMessage(PBM_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? "Controls" : "DisabledBg"]), hwnd)
        SendMessage(PBM_SETBARCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? this._BarKey(hwnd) : "DisabledText"]), hwnd)
        Subclass.InstallProc(this, hwnd)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /** Palette key for the bar fill in the control's current state. */
    static _BarKey(hwnd) {
        switch this.States.Get(hwnd, "normal") {
            case "error": return "Error"
            case "paused": return "Warning"
        }
        return "Accent"
    }

    /**
     * Sets the bar's state colour: "normal" (Accent), "error" (Error) or
     * "paused" (Warning). Remembered per control, so Refresh re-applies it
     * after ApplyPreset. Installed as `prog.SetState(state)`.
     * @returns {String} The state set
     */
    static SetState(prog, state) {
        state := StrLower(state)
        if state != "normal" && state != "error" && state != "paused"
            throw ValueError("SetState: state must be normal, error or paused", -1)
        this.States[prog.Hwnd] := state
        this.ApplyDarkMode(prog)
        return state
    }

    /**
     * Turns marquee (indeterminate) mode on or off. Installed as
     * `prog.SetMarquee(on := true, intervalMs := 30)`.
     * @returns {Boolean} true when marquee is on
     */
    static SetMarquee(prog, on := true, intervalMs := 30) {
        static GWL_STYLE := -16, PBS_MARQUEE := 0x08, PBM_SETMARQUEE := 0x040A
        static PBM_SETPOS := 0x0402, PBM_GETPOS := 0x0408
        hwnd := prog.Hwnd
        style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        newStyle := on ? style | PBS_MARQUEE : style & ~PBS_MARQUEE
        ; Entering marquee discards the determinate position, so park it here
        ; and put it back on the way out.
        if on && !this.MarqueePos.Has(hwnd)
            this.MarqueePos[hwnd] := SendMessage(PBM_GETPOS, 0, 0, hwnd)
        if newStyle != style
            DllCall("SetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", newStyle)
        SendMessage(PBM_SETMARQUEE, on ? 1 : 0, intervalMs, hwnd)
        if !on && this.MarqueePos.Has(hwnd) {
            SendMessage(PBM_SETPOS, this.MarqueePos[hwnd], 0, hwnd)
            this.MarqueePos.Delete(hwnd)
        }
        return !!on
    }

    /** Control-side proc: the stored PBM colours follow the enabled state. */
    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_ENABLE := 0x000A
        if msg = WM_ENABLE {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            ctrl := GuiCtrlFromHwnd(targetHwnd) ?? 0
            if ctrl
                this.ApplyDarkMode(ctrl)
            return result
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }
}

/**
 * Dark-themed ListBox with `DarkMode_Explorer` theme for modern scrollbar
 * appearance. Removes borders and applies {@link DarkTheme} font color.
 */
class _DarkListBox {

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    static Remove(*) {
    }

    /** Palette swap: the font colour is baked, re-push it. */
    static Refresh(ctrl) {
        this.ApplyDarkMode(ctrl)
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

    /** Handler protocol entry for native CheckBox controls. */
    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    static Remove(*) {
    }

    /** Palette swap: the caption colour is font-baked, re-push it. */
    static Refresh(ctrl) {
        this.ApplyDarkMode(ctrl)
    }

    static ApplyDarkMode(chk) {
        DarkTheme.AllowDarkMode(chk.Hwnd)
        DllCall("uxtheme\SetWindowTheme", "Ptr", chk.Hwnd, "Str", "Explorer", "Ptr", 0)
        chk.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
    }
}

/**
 * A single native Radio HWND, with its real caption and auto-radio style.
 * NM_CUSTOMDRAW changes appearance only: Windows retains caption hit testing,
 * enabled/visible state, keyboard groups, mnemonics and accessibility metadata.
 */
class _DarkRadio {
    static Apply(owner, ctrl, options := "", content?) {
        DarkTheme.AllowDarkMode(ctrl.Hwnd)
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "Explorer", "Ptr", 0)
        DarkWindowProc.RegisterChild(ctrl.Hwnd, this)
        DarkWindowProc.EnsureParentRelay(ctrl)
    }

    static Refresh(ctrl) {
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    static Remove(hwnd) {
        DarkWindowProc.UnregisterChild(hwnd)
    }

    static OnNotify(nm, lParam, &handled) {
        static NM_CUSTOMDRAW := -12, CDDS_PREPAINT := 1, CDRF_SKIPDEFAULT := 4
        handled := false
        if nm.code != NM_CUSTOMDRAW || DarkTheme.StandDown()
            return 0
        draw := DM_NMCUSTOMDRAW.At(lParam)
        if draw.dwDrawStage != CDDS_PREPAINT
            return 0
        this.Paint(nm.hwndFrom, draw.hdc, draw.uItemState)
        handled := true
        return CDRF_SKIPDEFAULT
    }

    static Paint(hwnd, hdc, itemState) {
        saved := DllCall("SaveDC", "Ptr", hdc, "Int")
        try {
            rc := DM_RECT()
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
            DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"), "Void")
            enabled := DllCall("IsWindowEnabled", "Ptr", hwnd, "Int")
            checked := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0xF0, "Ptr", 0, "Ptr", 0, "Int") = 1
            style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", -16, "Ptr")
            ; BP_RADIOBUTTON states: unchecked normal/hot/pressed/disabled = 1..4;
            ; checked equivalents = 5..8. The theme handle belongs to Windows.
            state := (checked ? 4 : 0) + (!enabled ? 4 : itemState & 1 ? 3 : itemState & 0x40 ? 2 : 1)
            theme := DllCall("uxtheme\GetWindowTheme", "Ptr", hwnd, "Ptr")
            size := DM_SIZE()
            glyphW := DarkTheme.Scale(16, hwnd), glyphH := glyphW
            if theme && DllCall("uxtheme\GetThemePartSize", "Ptr", theme, "Ptr", hdc,
                "Int", 2, "Int", state, "Ptr", 0, "Int", 1, "Ptr", size, "Int") >= 0 {
                glyphW := size.cx, glyphH := size.cy
            }
            glyphY := Max(0, (rc.bottom - glyphH) // 2)
            glyphX := style & 0x20 ? Max(0, rc.right - glyphW) : 0 ; BS_LEFTTEXT
            glyph := _DarkButton._MakeRect(glyphX, glyphY, glyphX + glyphW, glyphY + glyphH)
            if !theme || DllCall("uxtheme\DrawThemeBackground", "Ptr", theme, "Ptr", hdc,
                "Int", 2, "Int", state, "Ptr", glyph, "Ptr", 0, "Int") < 0 {
                ; Deterministic palette fallback if no theme data is available.
                color := DarkTheme.Colors[enabled ? "Accent" : "DisabledText"]
                oldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetBrush("Controls"), "Ptr")
                oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetPen(color), "Ptr")
                DllCall("Ellipse", "Ptr", hdc, "Int", glyph.left, "Int", glyph.top, "Int", glyph.right, "Int", glyph.bottom, "Int")
                if checked {
                    DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetSolidBrush(color), "Ptr")
                    inset := Max(3, glyphW // 4)
                    DllCall("Ellipse", "Ptr", hdc, "Int", glyph.left + inset, "Int", glyph.top + inset,
                        "Int", glyph.right - inset, "Int", glyph.bottom - inset, "Int")
                }
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Ptr")
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oldBrush, "Ptr")
            }
            hfont := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
            if hfont
                DllCall("SelectObject", "Ptr", hdc, "Ptr", hfont, "Ptr")
            len := DllCall("GetWindowTextLengthW", "Ptr", hwnd, "Int")
            textBuf := Buffer((len + 1) * 2, 0)
            DllCall("GetWindowTextW", "Ptr", hwnd, "Ptr", textBuf, "Int", len + 1, "Int")
            gap := DarkTheme.Scale(6, hwnd)
            textRect := _DarkButton._MakeRect(style & 0x20 ? 0 : glyphW + gap, 0,
                style & 0x20 ? glyphX - gap : rc.right, rc.bottom)
            ; Preserve native alignment and multiline style; _DrawText honours
            ; WM_QUERYUISTATE so Alt toggles mnemonic visibility normally.
            flags := style & 0x2000 ? 0x10 : 0x24 ; BS_MULTILINE: WORDBREAK, otherwise SINGLELINE|VCENTER
            align := style & 0x300
            flags |= align = 0x300 ? 1 : align = 0x200 ? 2 : 0
            caption := StrGet(textBuf)
            _DarkButton._DrawText(hwnd, hdc, caption, textRect, DarkTheme.Colors[enabled ? "Font" : "DisabledText"], flags)
            uiState := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x129, "Ptr", 0, "Ptr", 0, "Int")
            if enabled && DllCall("GetFocus", "Ptr") = hwnd && !(uiState & 1) {
                focusRect := _DarkButton._MakeRect(0, 0, rc.right, rc.bottom)
                DllCall("DrawFocusRect", "Ptr", hdc, "Ptr", focusRect, "Int")
            }
        } finally {
            if saved
                DllCall("RestoreDC", "Ptr", hdc, "Int", saved, "Int")
        }
    }
}

/**
 * Dark TreeView: OS dark-mode theme plus TVM_SET*COLOR from the palette, and
 * dark state-image checkboxes when the control has TVS_CHECKBOXES. The style
 * probe (not the options string) covers both the create and the Attach path.
 */
class _DarkTreeView {
    /** @type {Map} hwnd -> true while a deferred checkbox recolour is scheduled */
    static _pending := Map()

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    /** Colours are messages and the state list is recolored in place; only
     *  the style-change proc needs undoing. */
    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        this.OnDestroyed(hwnd)
    }

    static OnDestroyed(hwnd) {
        if this._pending.Has(hwnd)
            this._pending.Delete(hwnd)
    }

    /** Palette swap: TVM colours are stored by the control, re-send them. */
    static Refresh(ctrl) {
        this.ApplyDarkMode(ctrl)
    }

    static ApplyDarkMode(tv) {
        static TVM_SETBKCOLOR := 0x111D
        static TVM_SETTEXTCOLOR := 0x111E
        static TVM_SETLINECOLOR := 0x1128
        static TVS_CHECKBOXES := 0x100, GWL_STYLE := -16
        DllCall("uxtheme\SetWindowTheme", "Ptr", tv.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        SendMessage(TVM_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), tv)
        SendMessage(TVM_SETTEXTCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), tv)
        SendMessage(TVM_SETLINECOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"]), tv)
        DarkTheme.RemoveBorder(tv.Hwnd)
        ; TVS_CHECKBOXES added later (tv.Opt("+0x100") / ControlSetStyle — AHK's
        ; Opt("+Checked") is a no-op on a live TreeView) arrives as
        ; WM_STYLECHANGED; the proc recolours the state list comctl32 builds.
        Subclass.InstallProc(this, tv.Hwnd)
        if DllCall("GetWindowLongPtr", "Ptr", tv.Hwnd, "Int", GWL_STYLE, "Ptr") & TVS_CHECKBOXES
            _DarkTreeCheckboxes.Apply(tv)
    }

    /** Control-side proc: TVS_CHECKBOXES switched on after styling, a first
     *  insert on a list that was not there at Apply, and the state-list free
     *  on destroy. */
    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_STYLECHANGED := 0x7D, GWL_STYLE := -16, TVS_CHECKBOXES := 0x100
        static WM_DESTROY := 0x0002, TVM_INSERTITEMA := 0x1100, TVM_INSERTITEMW := 0x1132
        static TVM_GETIMAGELIST := 0x1108, TVSIL_STATE := 2
        if msg = WM_DESTROY {
            ; Once TVM_GETIMAGELIST has handed the TVS_CHECKBOXES state list out
            ; (which every recolour does), comctl32 treats it as app-owned and no
            ; longer frees it with the control — measured at 4 GDI objects per
            ; TreeView. Take the handle while the control is still whole, let the
            ; control finish its own destroy, then free the list ourselves.
            hIml := DllCall("SendMessage", "Ptr", hwnd, "UInt", TVM_GETIMAGELIST, "Ptr", TVSIL_STATE, "Ptr", 0, "Ptr")
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            if hIml
                DllCall("comctl32\ImageList_Destroy", "Ptr", hIml)
            return result
        }
        if (msg = TVM_INSERTITEMW || msg = TVM_INSERTITEMA) && this._pending.Has(targetHwnd) {
            ; The state list did not exist at Apply; the first insert is where
            ; comctl32 builds it, so recolour now that it has.
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._pending.Delete(targetHwnd)
            ctrl := GuiCtrlFromHwnd(targetHwnd) ?? 0
            if ctrl
                _DarkTreeCheckboxes.Apply(ctrl)
            return result
        }
        if msg = WM_STYLECHANGED && (wParam & 0xFFFFFFFF) = (GWL_STYLE & 0xFFFFFFFF) {
            styleOld := NumGet(lParam, 0, "UInt")
            styleNew := NumGet(lParam, 4, "UInt")
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
            ; Deferred: comctl32 materialises the state list while handling
            ; this message, and _DarkTreeCheckboxes.Apply may pulse the style
            ; itself, so recolour on the next timer tick, once per transition.
            if !(styleOld & TVS_CHECKBOXES) && (styleNew & TVS_CHECKBOXES) && !this._pending.Has(targetHwnd) {
                this._pending[targetHwnd] := true
                SetTimer(ObjBindMethod(this, "_ApplyCheckboxesLater", targetHwnd), -1)
            }
            return result
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static _ApplyCheckboxesLater(hwnd) {
        if this._pending.Has(hwnd)
            this._pending.Delete(hwnd)
        if !DllCall("IsWindow", "Ptr", hwnd)
            return
        ctrl := GuiCtrlFromHwnd(hwnd) ?? 0
        if ctrl
            _DarkTreeCheckboxes.Apply(ctrl)
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
        static BP_CHECKBOX := 3
        static CBS_UNCHECKEDNORMAL := 1
        static CBS_CHECKEDNORMAL := 5

        ; The query itself materialises the list on comctl32 v6 (and hands it to
        ; us to free — see _DarkTreeView.Proc WM_DESTROY). The old fallback,
        ; pulsing TVS_CHECKBOXES off/on, built a SECOND list comctl32 then
        ; orphaned; if the query ever comes back empty, the first insert
        ; recolours instead.
        hIml := SendMessage(TVM_GETIMAGELIST, TVSIL_STATE, 0, tv)
        if !hIml {
            _DarkTreeView._pending[tv.Hwnd] := true
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
 * Dark Edit: OS dark-mode theme (dark scrollbars), palette font colour, no
 * border, and a 2px caret ({@link _DarkCaret}) so the cursor stays visible on
 * the dark field. WM_CTLCOLOREDIT colours come from DarkWindowProc per paint.
 */
class _DarkEdit {

    static __New() {
        ; Placeholder text (EM_SETCUEBANNER), which AHK does not expose:
        ;   edit.SetCue("Search", showWhenFocused := false)
        ; The message copies the string, so a temporary is fine. Returns the text.
        Gui.Edit.Prototype.DefineProp("SetCue", { Call: (ctrl, text, showWhenFocused := false) => _DarkEdit.SetCue(ctrl, text, showWhenFocused) })
    }

    static SetCue(ctrl, text, showWhenFocused := false) {
        static EM_SETCUEBANNER := 0x1501
        SendMessage(EM_SETCUEBANNER, showWhenFocused ? 1 : 0, StrPtr(text), ctrl)
        return text
    }

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    static Remove(hwnd) {
        _DarkCaret.Remove(hwnd)
    }

    /** Palette swap: the font colour is baked, re-push it. */
    static Refresh(ctrl) {
        this.ApplyDarkMode(ctrl)
    }

    static ApplyDarkMode(ctrl) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
        DarkTheme.RemoveBorder(ctrl.Hwnd)
        _DarkCaret.Apply(ctrl.Hwnd)
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

    static __New() {
        blue := Map()
        blue["Blue"] := 0x3E5A80
        DarkTheme.DefineColor("CalendarTrailing", 0x4A4A4A, 0xB8B8B8, blue)
    }

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyToHwnd(ctrl.Hwnd)
    }

    /** Palette swap: MCM_SETCOLOR values are stored by the control, re-send
     *  them. ApplyToHwnd is idempotent (Install refuses a duplicate,
     *  EnsureMinSize only grows). */
    static Refresh(ctrl) {
        this.ApplyToHwnd(ctrl.Hwnd)
    }

    /** NCDESTROY reclaim via {@link Subclass._Wrap}. */
    static OnDestroyed(hwnd) {
        if this.Geometry.Has(hwnd)
            this.Geometry.Delete(hwnd)
    }

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
        if this.Geometry.Has(hwnd)
            this.Geometry.Delete(hwnd)
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
        ; WM_NCDESTROY (transient DateTime dropdown calendars die on every
        ; close-up) is reclaimed by Subclass._Wrap + OnDestroyed.
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /** @type {Map} hwnd -> cached overpaint geometry; see {@link _DarkMonthCal._Geometry} */
    static Geometry := Map()

    /**
     * Cached geometry for the overpaint passes, revalidated per paint by
     * client size alone — the weekday bands, day columns, nav buttons, and
     * today row do not move when the user navigates months, and WM_PAINT
     * fires on every selection change, nav hover, and repeatedly during the
     * DateTime dropdown's ~200ms open animation. Discovery costs ~110
     * MCM_HITTEST SendMessage round-trips (per month row); a cache hit costs
     * one GetClientRect. Weekday NAMES are not cached — the paint pass reads
     * the locale first-day itself. Dropped on WM_NCDESTROY and Remove.
     */
    static _Geometry(hwnd) {
        static rcClient := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rcClient)
        cw := rcClient.right
        ch := rcClient.bottom
        if this.Geometry.Has(hwnd) {
            g := this.Geometry[hwnd]
            if g.cw = cw && g.ch = ch
                return g
        }
        g := this._BuildGeometry(hwnd, cw, ch)
        ; Don't cache a failed discovery (a paint before layout settles) —
        ; the size wouldn't change, so the empty result would stick forever.
        if g.rows.Length
            this.Geometry[hwnd] := g
        return g
    }

    /** Full geometry discovery via MCM_HITTEST scans. See _PaintWeekdays for
     *  what each row field means; the scan skips date cells (CALENDARDATE),
     *  the today row (TODAYLINK) and titles, so resuming just below a row's
     *  first date line lands on the next month row's weekday band. */
    static _BuildGeometry(hwnd, cw, ch) {
        static MCHT_CALENDARDAY := 0x20002
        static MCHT_CALENDARDATE := 0x20001   ; PREV/NEXT variants add high flags
        static MCHT_TODAYLINK := 0x30000

        rows := []
        scanY := 0
        while scanY < ch {
            ; Next weekday band down the middle column.
            bandTop := -1, bandBottom := -1
            y := scanY
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
                break

            ; First date row below the band: its top clamps the erase so
            ; date-cell selection/focus boxes are never touched.
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
                break

            cells := Map()   ; left -> right, from the date row's cell rects
            x := 2
            while x < cw {
                ht := this._HitTest(hwnd, x, dateMidY)
                if (ht.uHit & 0xFFFFFF) = MCHT_CALENDARDATE && !cells.Has(ht.rc.left)
                    cells[ht.rc.left] := ht.rc.right
                x += 4
            }
            if !cells.Count
                break

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

            rows.Push({bandTop: bandTop, nameBottom: Min(bandBottom, dateTop),
                fillBottom: dateTop, lefts: lefts, cells: cells})
            scanY := dateTop + 1
        }

        ; Today-legend row: probe a few offsets up from the bottom edge.
        today := 0
        for dy in [6, 10, 14] {
            ht := this._HitTest(hwnd, cw // 2, ch - dy)
            if ht.uHit = MCHT_TODAYLINK {
                today := [ht.rc.left, ht.rc.top, ht.rc.right, ht.rc.bottom]
                break
            }
        }

        return {cw: cw, ch: ch, rows: rows, today: today, nav: this._NavButtonRects(hwnd)}
    }

    /**
     * Repaints the today-legend row: erases the native rendering (which draws a
     * redundant marker-sample box left of the text) and redraws just the
     * "Today: <date>" string, bold and centered in the row. The MCHT_TODAYLINK
     * hit area is unchanged, so clicking the row still jumps to today.
     */
    static _PaintTodayRow(hwnd) {
        static WM_GETFONT := 0x0031
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20, DT_NOPREFIX := 0x800

        g := this._Geometry(hwnd)
        rcT := g.today
        if !rcT
            return

        hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        static row := DM_RECT()
        ; Cover the full control width — the hit rect excludes the swatch margin.
        row.left := 0, row.top := rcT[2]
        row.right := g.cw, row.bottom := rcT[4]
        DllCall("FillRect", "Ptr", hdc, "Ptr", row, "Ptr", DarkTheme.GetBrush("Background"), "Void")

        hBase := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
        hBold := hBase ? this._BoldFont(hBase) : 0
        oldFont := hBold ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hBold, "Ptr") : 0
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), "Void")
        text := this._TodayLabel() " " FormatTime(, "ShortDate")
        DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", row,
            "UInt", DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX, "Void")
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }

    /** @type {String} Cached localized "Today:" legend prefix; "" until loaded.
     * (Named _todayText, not _todayLabel — AHK identifiers are case-insensitive
     * and the latter would collide with the _TodayLabel method.) */
    static _todayText := ""

    /**
     * Localized "Today:" prefix from comctl32 v6's string table (id 4432 —
     * undocumented but verified on Win11 26100; the erase-and-redraw would
     * otherwise replace the OS-localized legend with hardcoded English).
     * Any failure falls back to the English literal.
     */
    static _TodayLabel() {
        if this._todayText != ""
            return this._todayText
        label := "Today:"
        hMod := DllCall("GetModuleHandleW", "Str", "comctl32.dll", "Ptr")
        if hMod {
            buf := Buffer(128, 0)
            len := DllCall("LoadStringW", "Ptr", hMod, "UInt", 4432, "Ptr", buf, "Int", 64, "Int")
            if len > 0 && len < 32
                label := StrGet(buf)
        }
        return this._todayText := label
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
     * FontDim; mod-7 indexing keeps locale first-day right, side-by-side months
     * share one band, and a calendar tall enough for multiple month ROWS gets
     * every row's band repainted (one weekday header renders per row).
     */
    static _PaintWeekdays(hwnd) {
        static MCM_GETFIRSTDAYOFWEEK := 0x1010
        static WM_GETFONT := 0x0031
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20, DT_NOPREFIX := 0x800

        g := this._Geometry(hwnd)
        if !g.rows.Length
            return

        names := this._DayNames()
        firstDay := SendMessage(MCM_GETFIRSTDAYOFWEEK, 0, 0, hwnd) & 0xFFFF  ; 0=Mon .. 6=Sun

        hdc := DllCall("GetDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["FontDim"]), "Void")

        static band := DM_RECT(), rcCell := DM_RECT()
        for rowGeo in g.rows {
            ; Erase the band plus the gap below it (covers the native light
            ; divider); FillRect bottoms are exclusive, so nothing at
            ; y >= fillBottom (selection/focus boxes) is touched. Then one
            ; name per column and a muted divider above the dates.
            band.left := 0, band.top := rowGeo.bandTop
            band.right := g.cw, band.bottom := rowGeo.fillBottom
            DllCall("FillRect", "Ptr", hdc, "Ptr", band, "Ptr", DarkTheme.GetBrush("Background"), "Void")

            for idx, left in rowGeo.lefts {
                rcCell.left := left, rcCell.top := rowGeo.bandTop
                rcCell.right := rowGeo.cells[left], rcCell.bottom := rowGeo.nameBottom - 1
                name := names[Mod(firstDay + idx - 1, 7) + 1]
                DllCall("DrawTextW", "Ptr", hdc, "Str", name, "Int", -1, "Ptr", rcCell,
                    "UInt", DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX, "Void")
            }

            sepPen := DarkTheme.GetPen(DarkTheme.Colors["DisabledText"])
            oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", sepPen, "Ptr")
            DllCall("MoveToEx", "Ptr", hdc, "Int", rowGeo.lefts[1], "Int", rowGeo.fillBottom - 2, "Ptr", 0, "Void")
            DllCall("LineTo", "Ptr", hdc, "Int", rowGeo.cells[rowGeo.lefts[rowGeo.lefts.Length]], "Int", rowGeo.fillBottom - 2, "Void")
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")
        }

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Void")
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
    }

    /** Generic MCM_HITTEST returning the filled DM_MCHITTESTINFO struct. */
    static _HitTest(hwnd, x, y) {
        static MCM_HITTEST := 0x100E
        ; Static scratch — geometry discovery calls this ~110 times in a burst,
        ; and every caller reads the result before probing again.
        static ht := DM_MCHITTESTINFO()
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
        rects := this._Geometry(hwnd).nav
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
        ; Disabled fields dim like every other control: the message-colored
        ; ones via WM_CTLCOLOR*, buttons and combos via their own paint paths.
        ; Without this a disabled DateTime/Hotkey looked fully enabled.
        enabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        focused := enabled && DllCall("GetFocus", "Ptr") = hwnd
        fillKey := enabled ? "Controls" : "DisabledBg"
        textKey := enabled ? "Font" : "DisabledText"
        borderPen := DarkTheme.GetPen(focused ? DarkTheme.Colors["Accent"] : DarkTheme.Colors["Border"])
        oldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetBrush(fillKey), "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", borderPen, "Ptr")
        radius := DarkTheme.Scale(6, hwnd)
        DllCall("RoundRect", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", radius, "Int", radius, "Void")

        pad := DarkTheme.Scale(6, hwnd)
        rightPad := pad
        if chevron {
            btnW := DllCall("GetSystemMetrics", "Int", SM_CXVSCROLL) + 2
            DarkTheme.PaintChevron(hdc, w - btnW // 2 - 1, h // 2,
                DarkTheme.Scale(4, hwnd), DarkTheme.Scale(3, hwnd), DarkTheme.Colors[textKey])
            rightPad := btnW + 4
        }

        if text != "" {
            DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[textKey]), "Void")
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
    /** DTN_FIRST2 - 1 */
    static DTN_DROPDOWN := -754

    /** Parent-side DTN_DROPDOWN via the child registry: theme the transient
     *  dropdown calendar, then let default processing continue. */
    static OnNotify(nm, lParam, &handled) {
        handled := false
        if nm.code = this.DTN_DROPDOWN
            this.OnDropDown(nm.hwndFrom)
        return 0
    }

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    /** NCDESTROY reclaim via {@link Subclass._Wrap}; a no-op for the dropdown
     *  host hwnd this class also subclasses. */
    static OnDestroyed(hwnd) {
        DarkWindowProc.UnregisterChild(hwnd)
    }

    static ApplyDarkMode(ctrl) {
        static GWL_STYLE := -16, DTS_UPDOWN := 0x1, GW_CHILD := 5
        DarkTheme.RemoveBorder(ctrl.Hwnd)
        DarkWindowProc.RegisterChild(ctrl.Hwnd, _DarkDateTime)
        Subclass.Install(this, ctrl.Hwnd, ObjBindMethod(this, "Proc", ctrl.Hwnd))
        ; DTN_DROPDOWN is answered by the parent's WM_NOTIFY; inside a Tab3
        ; page that parent is the tab's #32770, not the DarkGui frame.
        DarkWindowProc.EnsureParentRelay(ctrl)
        ; Time-format pickers (DTS_UPDOWN, from AddDateTime's "Time" format)
        ; have no dropdown — comctl32 creates a child msctls_updown32 spinner
        ; instead, a separate hwnd our WM_PAINT takeover never touches. Route
        ; it through the UpDown owner-draw. Created during the picker's
        ; WM_CREATE, so it exists by now; guard anyway.
        style := DllCall("GetWindowLongPtr", "Ptr", ctrl.Hwnd, "Int", GWL_STYLE, "Ptr")
        if style & DTS_UPDOWN {
            hSpin := DllCall("GetWindow", "Ptr", ctrl.Hwnd, "UInt", GW_CHILD, "Ptr")
            if hSpin
                _DarkUpDown.ApplyToHwnd(hSpin)
        }
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
        DarkWindowProc.UnregisterChild(hwnd)
    }


    /** Paints the dropdown host's client (the inset margin around the
     *  calendar) with the theme Background instead of the light class brush;
     *  re-overpaints the ring after every host repaint. */
    static HostProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_ERASEBKGND := 0x0014, WM_PAINT := 0x000F, GW_CHILD := 5
        ; The transient per-dropdown host dies on every close-up; its thunk is
        ; reclaimed by Subclass._Wrap on WM_NCDESTROY.
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
        ; WM_ENABLE too: WM_ERASEBKGND is suppressed here, so without an
        ; explicit invalidate the stale enabled look persists until some other
        ; repaint happens to come along.
        static WM_ENABLE := 0x000A
        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS || msg = WM_ENABLE
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static Paint(hwnd) {
        static GWL_STYLE := -16, DTS_UPDOWN := 0x1
        ; The formatted date comes from the control's window text; every native
        ; render-to-DC path composes its font from an empty LOGFONT and falls back
        ; to a serif, so we draw it ourselves (see the class comment).
        ; No chevron on DTS_UPDOWN (Time-format) pickers — they have no dropdown;
        ; a child spinner sits at the right edge instead.
        buf := Buffer(512, 0)
        DllCall("GetWindowText", "Ptr", hwnd, "Ptr", buf, "Int", 256)
        style := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        _DarkField.Paint(hwnd, StrGet(buf), !(style & DTS_UPDOWN))
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

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

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
        ; WM_ENABLE too: WM_ERASEBKGND is suppressed here, so without an
        ; explicit invalidate the stale enabled look persists until some other
        ; repaint happens to come along.
        static WM_ENABLE := 0x000A
        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS || msg = WM_ENABLE
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

    /** Handler protocol entry. Creation text was set natively (light) before
     *  styling, so re-push it through the owner-draw SetText. */
    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
        if IsSet(content) && content != ""
            ctrl.SetText(content)
    }

    /** Palette swap: SB_SETBKCOLOR is stored by the control, re-send it. */
    static Refresh(ctrl) {
        static SB_SETBKCOLOR := 0x2001
        SendMessage(SB_SETBKCOLOR, 0, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), ctrl)
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /** Parent-side WM_DRAWITEM via the child registry (no SB text-colour message exists). */
    static OnDrawItem(dis) {
        this.DrawPart(dis)
        return true
    }

    /** NCDESTROY reclaim via {@link Subclass._Wrap}. */
    static OnDestroyed(hwnd) {
        DarkWindowProc.UnregisterChild(hwnd)
        if this.Texts.Has(hwnd)
            this.Texts.Delete(hwnd)
    }

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
        DarkWindowProc.RegisterChild(hwnd, _DarkStatusBar)

        ; No SB_SETTEXTCOLOR exists — override SetText to store the string and flag the
        ; part SBT_OWNERDRAW, then paint it dark from the parent's WM_DRAWITEM.
        sb.DefineProp("SetText", { Call: ObjBindMethod(this, "_SetText") })
        ; Convenience: sb.Text := "..." routes to the owner-draw SetText (part 1).
        sb.DefineProp("Text", {
            Get: (s) => _DarkStatusBar.Texts.Get(s.Hwnd, Map()).Get(0, ""),
            Set: (s, value) => (_DarkStatusBar._SetText(s, value, 1), value)
        })
        this._RetrofitParts(sb)
    }

    /**
     * Puts every part that is not yet owner-drawn onto the owner-draw path,
     * preserving its text. An Attach retrofit arrives with live text, and a
     * later sb.SetParts() creates classic parts — both would otherwise render
     * their text in the classic light-theme colour, near-black on the dark
     * bar, and never enter Texts so nothing could heal them. Read via
     * SB_GETTEXTW (Gui.StatusBar has no GetText). Parts already owner-drawn
     * are skipped: SB_GETTEXT returns their app data, not a string, so
     * re-reading them would corrupt the cached text. The HIWORD of
     * SB_GETTEXTLENGTH is the raw SBT_* type (probe-verified: 0x1100 for
     * OWNERDRAW|NOBORDERS).
     * @param {Gui.StatusBar} sb - The dark status bar
     */
    static _RetrofitParts(sb) {
        static SB_GETTEXTLENGTHW := 0x40C, SB_GETTEXTW := 0x40D, SB_GETPARTS := 0x406
        static SBT_OWNERDRAW := 0x1000
        parts := SendMessage(SB_GETPARTS, 0, 0, sb)
        if parts < 1
            parts := 1
        idx := 0
        while idx < parts {
            lenInfo := SendMessage(SB_GETTEXTLENGTHW, idx, 0, sb)
            if (lenInfo >> 16) & SBT_OWNERDRAW {
                idx++
                continue
            }
            len := lenInfo & 0xFFFF
            existing := ""
            if len > 0 {
                buf := Buffer((len + 1) * 2, 0)
                SendMessage(SB_GETTEXTW, idx, buf.Ptr, sb)
                existing := StrGet(buf)
            }
            this._SetText(sb, existing, idx + 1)
            idx++
        }
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
        static SB_GETICON := 0x0414, DI_NORMAL := 0x3
        texts := this.Texts.Get(dis.hwndItem, "")
        if !texts
            return
        text := texts.Has(dis.itemID) ? texts[dis.itemID] : ""
        rc := DM_RECT()
        rc.left := dis.rcItem.left, rc.top := dis.rcItem.top
        rc.right := dis.rcItem.right, rc.bottom := dis.rcItem.bottom
        DllCall("FillRect", "Ptr", dis.hDC, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Controls"), "Void")
        pad := DarkTheme.Scale(4, dis.hwndItem)
        rc.left += pad
        ; A part icon (sb.SetIcon) is painted here too: the full-rect fill
        ; above covers whatever comctl32 would have drawn for the part.
        hIcon := SendMessage(SB_GETICON, dis.itemID, 0, dis.hwndItem)
        if hIcon {
            iconSz := Min(DarkTheme.Scale(16, dis.hwndItem), rc.bottom - rc.top - 2)
            DllCall("DrawIconEx", "Ptr", dis.hDC, "Int", rc.left, "Int", rc.top + (rc.bottom - rc.top - iconSz) // 2,
                "Ptr", hIcon, "Int", iconSz, "Int", iconSz, "UInt", 0, "Ptr", 0, "UInt", DI_NORMAL, "Void")
            rc.left += iconSz + pad
        }
        if text = ""
            return
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
        static WM_PAINT := 0x000F, SB_SETPARTS := 0x0404
        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        if msg = WM_PAINT {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._PaintGripOver(hwnd)
            return ret
        }
        if msg = SB_SETPARTS {
            ; Parts created by a later sb.SetParts() arrive classic; put them
            ; on the owner-draw path (parts already owner-drawn are skipped).
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            ctrl := GuiCtrlFromHwnd(targetHwnd) ?? 0
            if ctrl
                this._RetrofitParts(ctrl)
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
        this.OnDestroyed(hwnd)
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

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyToHwnd(ctrl.Hwnd)
    }

    static ApplyDarkMode(ud) => this.ApplyToHwnd(ud.Hwnd)

    /**
     * Hwnd-based variant so non-Gui spinners can be themed too — e.g. the
     * msctls_updown32 a Time-format DateTime picker creates internally.
     * @param {Ptr} hwnd - msctls_updown32 window handle
     */
    static ApplyToHwnd(hwnd) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        Subclass.Install(this, hwnd, ObjBindMethod(this, "Proc", hwnd))
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
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
        ; Picker-internal spinners die with their parent window, never via
        ; _Teardown; Subclass._Wrap reclaims the thunk on WM_NCDESTROY.
        static WM_ENABLE := 0x000A
        if msg = WM_ENABLE
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    static Paint(hwnd) {
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps.Ptr, "Ptr")
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := rc.right, h := rc.bottom

        enabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush(enabled ? "Controls" : "DisabledBg"), "Void")
        static UDS_HORZ := 0x40, GWL_STYLE := -16
        horizontal := DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", GWL_STYLE, "Ptr") & UDS_HORZ
        midX := w // 2
        midY := h // 2

        ; Divider between the two arrow halves
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetPen(DarkTheme.Colors["ButtonBorder"]), "Ptr")
        DllCall("MoveToEx", "Ptr", hdc, "Int", horizontal ? midX : 0, "Int", horizontal ? 0 : midY, "Ptr", 0, "Void")
        DllCall("LineTo", "Ptr", hdc, "Int", horizontal ? midX : w, "Int", horizontal ? h : midY, "Void")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")

        ; Same stroked chevron as the DateTime picker and ComboBox dropdown, so a
        ; spinner sitting next to either reads as the same control family.
        ; Clamped to the spinner's narrow halves: it is ~17px wide and each half
        ; only ~11px tall, where the unclamped picker sizes would collide.
        cx := w // 2
        half := Max(3, Min(DarkTheme.Scale(4, hwnd), w // 2 - 2))
        rise := Max(2, Min(DarkTheme.Scale(3, hwnd), midY // 2 - 2))
        fontColor := DarkTheme.Colors[enabled ? "Font" : "DisabledText"]
        if horizontal {
            half := Max(2, Min(DarkTheme.Scale(4, hwnd), h // 2 - 2))
            rise := Max(2, Min(DarkTheme.Scale(3, hwnd), midX // 2 - 2))
            oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", DarkTheme.GetPen(fontColor, 2), "Ptr")
            for i, centerX in [midX // 2, midX + (w - midX) // 2] {
                tipX := centerX + (i = 1 ? -1 : 1)
                armX := centerX + (i = 1 ? rise : -rise)
                DllCall("MoveToEx", "Ptr", hdc, "Int", armX, "Int", midY - half, "Ptr", 0, "Void")
                DllCall("LineTo", "Ptr", hdc, "Int", tipX, "Int", midY, "Void")
                DllCall("LineTo", "Ptr", hdc, "Int", armX, "Int", midY + half, "Void")
            }
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen, "Void")
        } else {
            DarkTheme.PaintChevron(hdc, cx, midY // 2, half, rise, fontColor, true)
            DarkTheme.PaintChevron(hdc, cx, midY + midY // 2, half, rise, fontColor, false)
        }

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

    static __New() {
        DarkTheme.DefineColor("Link", 0x4CA0FF, 0x0066CC)
    }

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    /** Palette swap: the plain-text colour is font-baked, re-push it (link
     *  segments are recolored per paint via NM_CUSTOMDRAW). */
    static Refresh(ctrl) {
        ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
    }

    /** Parent-side NM_CUSTOMDRAW (link-segment colour) via the child registry. */
    static OnNotify(nm, lParam, &handled) {
        static NM_CUSTOMDRAW := -12
        handled := (nm.code = NM_CUSTOMDRAW)
        return handled ? this.OnCustomDraw(lParam) : 0
    }

    static ApplyDarkMode(link) {
        DarkTheme.AllowDarkMode(link.Hwnd)
        link.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
        DarkWindowProc.RegisterChild(link.Hwnd, _DarkLink)
        DarkWindowProc.EnsureParentRelay(link)
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
        DarkWindowProc.UnregisterChild(hwnd)
    }
}

/**
 * Custom-draw GroupBox: fills background, draws dim border, renders title in Font color.
 * WM_CTLCOLORBTN does not control GroupBox text color — a WM_PAINT subclass is required.
 */
class _DarkGroupBox {
    static GroupTexts := Map()
    /** @type {Map} hwnd -> last painted title width; erases the union so a
     * shrinking caption can't leave stale glyphs (no interior fill heals it) */
    static LastTitleW := Map()

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

    /** NCDESTROY reclaim via {@link Subclass._Wrap}: drop the caption caches
     *  so a recycled hwnd cannot inherit a stale erase width. */
    static OnDestroyed(hwnd) {
        if this.GroupTexts.Has(hwnd)
            this.GroupTexts.Delete(hwnd)
        if this.LastTitleW.Has(hwnd)
            this.LastTitleW.Delete(hwnd)
    }

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
        this.OnDestroyed(hwnd)
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
        ; The caption dims when disabled; WM_ERASEBKGND is suppressed here, so
        ; repaint explicitly.
        static WM_ENABLE := 0x000A
        if msg = WM_ENABLE {
            result := Subclass.Forward(hwnd, msg, wParam, lParam)
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

        ; Erase the title strip across the UNION of the current and previously
        ; painted title extents BEFORE the border pass — with no interior fill,
        ; this is the only thing that clears a shrinking caption's old glyphs,
        ; and doing it first lets RoundRect redraw the border line straight
        ; through the vacated span.
        fillW := Max(textW, this.LastTitleW.Get(hwnd, 0))
        this.LastTitleW[hwnd] := textW
        if fillW > 0 {
            strip := DM_RECT()
            strip.left := textX - 2, strip.top := 0
            strip.right := textX + fillW + 4, strip.bottom := tmH
            DllCall("FillRect", "Ptr", hdc, "Ptr", strip, "Ptr", DarkTheme.GetBrush("Background"), "Void")
        }

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

        ; Draw title text in Font color (strip already cleared above).
        DllCall("SetBkMode",    "Ptr", hdc, "Int", 1, "Void")
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[DllCall("IsWindowEnabled", "Ptr", hwnd) ? "Font" : "DisabledText"]), "Void")
        textRc := DM_RECT()
        textRc.left := textX, textRc.top := 0, textRc.right := textX + textW + 4, textRc.bottom := tmH
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

    static Apply(owner, ctrl, options := "", content?) {
        this.ApplyDarkMode(ctrl)
    }

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
        ; Retrofit case: an overflow scroller may already exist (see Proc's
        ; WM_PARENTNOTIFY branch for the lazily created one).
        this._ThemeScroller(DllCall("GetWindow", "Ptr", hwnd, "UInt", 5, "Ptr"))  ; GW_CHILD
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /** Routes the tab strip's overflow spinner through the dark UpDown
     *  owner-draw. SysTabControl32 creates it lazily when tabs overflow, and
     *  it would otherwise keep native light arrows over the dark strip. */
    static _ThemeScroller(childHwnd) {
        if !childHwnd
            return
        static clsBuf := Buffer(64, 0)
        DllCall("GetClassNameW", "Ptr", childHwnd, "Ptr", clsBuf, "Int", 32)
        if StrGet(clsBuf) = "msctls_updown32" && !Subclass.IsInstalled(_DarkUpDown, childHwnd)
            _DarkUpDown.ApplyToHwnd(childHwnd)
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
        ; The overflow scroller is created on demand when tabs no longer fit.
        static WM_PARENTNOTIFY := 0x0210, WM_CREATE := 0x0001
        if msg = WM_PARENTNOTIFY && (wParam & 0xFFFF) = WM_CREATE {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._ThemeScroller(lParam)
            return ret
        }
        ; Focus and keyboard-cue transitions repaint the strip so the ring on
        ; the selected tab tracks native behaviour.
        static WM_SETFOCUS := 0x0007, WM_KILLFOCUS := 0x0008, WM_UPDATEUISTATE := 0x0128, WM_ENABLE := 0x000A
        if msg = WM_SETFOCUS || msg = WM_KILLFOCUS || msg = WM_UPDATEUISTATE || msg = WM_ENABLE {
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1, "Void")
            return Subclass.Forward(hwnd, msg, wParam, lParam)
        }
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

        ; Keyboard cues, as native: a focus ring on the selected tab only while
        ; the control has focus and the window is showing focus rectangles;
        ; mnemonic underlines only while accelerators are shown.
        static DT_HIDEPREFIX := 0x00100000
        uiState := DarkTheme.UiState(hwnd)
        enabled := DllCall("IsWindowEnabled", "Ptr", hwnd)
        focusRing := DllCall("GetFocus", "Ptr") = hwnd && !(uiState & DarkTheme.UISF_HIDEFOCUS)
        textFlags := DT_CENTER | DT_VCENTER | DT_SINGLELINE | ((uiState & DarkTheme.UISF_HIDEACCEL) ? DT_HIDEPREFIX : 0)

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
                tabBrush := DarkTheme.GetSolidBrush(DarkTheme.Colors[enabled ? "ControlsHover" : "DisabledBg"])  ; cached — do not delete
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
                if focusRing
                    DarkTheme.GdipRoundFill(hdc, left + 4, top + 2, right - left - 7, bottom - top - 4,
                        DarkTheme.Scale(3, hwnd), -1, DarkTheme.Colors["Accent"], DarkTheme.Scale(1, hwnd) * 1.0)
                DllCall("SetTextColor", "Ptr", hdc, "UInt",
                    DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? "Font" : "DisabledText"]), "Void")
            } else {
                DllCall("SetTextColor", "Ptr", hdc, "UInt",
                    DarkTheme.RGBtoBGR(DarkTheme.Colors[enabled ? "FontDim" : "DisabledText"]), "Void")
            }

            ; Fetch label text via TCM_GETITEMW and draw centered
            ; Static scratch — runs per tab per paint.
            static textBuf := Buffer(512, 0)
            static tcItem  := DM_TCITEMW()
            tcItem.mask       := TCIF_TEXT
            tcItem.pszText    := textBuf.Ptr
            tcItem.cchTextMax := 255
            DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETITEM, "Ptr", i, "Ptr", tcItem.Ptr)
            tabText := StrGet(textBuf)
            DllCall("DrawTextW", "Ptr", hdc, "Str", tabText, "Int", -1, "Ptr", itemRc,
                "UInt", textFlags, "Void")
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
 * Internal palette-change subscriber. SetPalette/ApplyPreset rebuild brushes
 * and repaint, but colors a control STORES — sent once via LVM_/TVM_/PBM_
 * messages, SetFont("c..."), or baked into checkbox glyph pixels — go stale
 * on a swap; before this hook every consumer app had to hand-roll the
 * re-apply in its own OnThemeChanged handler. Registered once, lazily, by
 * DarkGui.__New / DarkGui.Attach. All appliers it calls are idempotent.
 */
class _DarkPaletteSync {
    static _registered := false

    static Ensure() {
        if this._registered
            return
        this._registered := true
        DarkTheme.OnThemeChanged(ObjBindMethod(this, "_Refresh"))
    }

    /**
     * Handler-driven refresh: every tracked control whose handler declares
     * Refresh(ctrl) gets it, so "does it survive SetPalette" is a property of
     * the handler rather than of a switch here. Controls that read the
     * palette per paint (buttons, fields, tabs, ...) declare no Refresh.
     */
    static _Refresh(*) {
        ; High contrast: the windows are stock; leave them alone.
        if DarkTheme.StandDown()
            return
        done := Map()
        for hwnd in DarkTheme.Windows.Clone() {
            owner := GuiFromHwnd(hwnd) ?? 0
            if !owner || !HasProp(owner, "_darkHwnds")
                continue
            for ctrlHwnd, label in owner._darkHwnds.Clone() {
                done[ctrlHwnd] := true
                this._RefreshOne(DarkGui.Handlers.Get(label, 0), ctrlHwnd)
            }
        }
        ; Controls styled by a direct SetDarkMode on a plain Gui are in no
        ; tracking map, but the parent-side ones (ListView, Link, ...) sit in
        ; DarkWindowProc's child registry with their handler.
        for ctrlHwnd, h in DarkWindowProc.Children.Clone() {
            if !done.Has(ctrlHwnd)
                this._RefreshOne(h, ctrlHwnd)
        }
    }

    /** Refreshes one control through its handler. A throwing handler must
     *  not abort the remaining controls, the remaining windows, or (via
     *  _NotifyThemeChanged) SetPalette's closing Redraw. */
    static _RefreshOne(h, ctrlHwnd) {
        if !h || !HasMethod(h, "Refresh") || !DllCall("IsWindow", "Ptr", ctrlHwnd)
            return
        ctrl := GuiCtrlFromHwnd(ctrlHwnd) ?? 0
        if !ctrl
            return
        try
            h.Refresh(ctrl)
        catch Error as e
            DarkGui.LastHandlerError := e
    }
}

/**
 * Window procedure subclass for handling WM_CTLCOLOR* messages.
 * Provides dark background brushes for Edit, ListBox, Button, and Static controls.
 */
class DarkWindowProc {
    /** @type {Map} hwnd -> child handler. The ONE parent-side registry: a
     * control (or a small helper object) that needs the parent window to
     * answer a message on its behalf registers here, and Proc dispatches by
     * hwnd lookup. Handlers are duck-typed; every method is optional:
     *   OnCtlColor(hwndCtl, hdc, msg)  -> HBRUSH, or 0 to fall through to the defaults
     *   OnNotify(nm, lParam, &handled) -> reply; set handled when it must be returned
     *   OnDrawItem(dis)                -> true when it painted the item
     * A control-side OnNotify reply never reaches the control as the message
     * result (probe-verified on this build), which is why NM_CUSTOMDRAW,
     * DTN_DROPDOWN and WM_DRAWITEM are answered from here. */
    static _children := Map()

    /** Read-only view of the child registry (palette refresh, tests). */
    static Children => this._children

    /**
     * Registers the parent-side handler for a child hwnd. Called from a
     * handler's Apply (ListView, Link, DateTime, StatusBar, the ComboBox
     * dropdown list, menu-bar labels) — and undone from its Remove/OnDestroyed.
     * @param {Ptr} hwnd - Child window handle
     * @param {Object} handler - Class or object with any of the methods above
     */
    static RegisterChild(hwnd, handler) {
        this._children[hwnd] := handler
    }

    static UnregisterChild(hwnd) {
        if this._children.Has(hwnd)
            this._children.Delete(hwnd)
    }

    /** @returns {Object|Integer} The child handler for hwnd, or 0 */
    static ChildOf(hwnd) => this._children.Get(hwnd, 0)

    /**
     * Sets the DC text/background colours and returns the matching palette
     * brush — the whole of a WM_CTLCOLOR* reply, for handlers to reuse.
     * @param {Ptr} hdc - The control's DC (wParam of the WM_CTLCOLOR message)
     * @param {String} textKey - DarkTheme.Colors key for the text
     * @param {String} backKey - DarkTheme.Colors key for the fill
     * @returns {Ptr} HBRUSH owned by DarkTheme (never DeleteObject it)
     */
    static CtlColorReply(hdc, textKey, backKey) {
        static TRANSPARENT := 1
        DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[textKey]))
        DllCall("gdi32\SetBkColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[backKey]))
        DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", TRANSPARENT)
        return DarkTheme.GetBrush(backKey)
    }

    /**
     * Per-control colour override for a Static, installed as its child
     * handler by SetStaticColor. Slots "text"/"back" hold an 0xRRGGBB or a
     * DarkTheme.Colors key; a key is resolved on every paint so presets keep
     * working. Uses Has rather than a blank test so a legitimate 0x000000
     * (black) is not mistaken for "unset".
     */
    class StaticColorSpec {
        slots := Map()

        OnCtlColor(hwndCtl, hdc, msg) {
            static TRANSPARENT := 1
            fore := this.Resolve("text", "Font")
            back := this.Resolve("back", "Background")
            DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(fore))
            DllCall("gdi32\SetBkColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(back))
            DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", TRANSPARENT)
            return DarkTheme.GetSolidBrush(back)
        }

        Resolve(slot, fallbackKey) {
            if !this.slots.Has(slot)
                return DarkTheme.Colors[fallbackKey]
            value := this.slots[slot]
            if value is String
                return DarkTheme.Colors.Has(value) ? DarkTheme.Colors[value] : DarkTheme.Colors[fallbackKey]
            return value
        }
    }

    /** Subclass owner key for the Tab3 page-dialog relay — distinct from the
     *  frame proc so a dialog and a frame can never collide in the registry. */
    class Relay {
    }

    /** @type {Array} Every hwnd-keyed tracking Map, listed ONCE so the
     *  NCDESTROY sweep, DarkGui._Teardown and the regression test agree. */
    static Trackers := [this._children]

    /** Drops every tracking entry whose window no longer exists. */
    static SweepDead() {
        for tracker in this.Trackers {
            stale := []
            for staleHwnd, _ in tracker
                if !DllCall("IsWindow", "Ptr", staleHwnd)
                    stale.Push(staleHwnd)
            for staleHwnd in stale
                tracker.Delete(staleHwnd)
        }
    }

    /**
     * Tab3 hosts its tab clients inside an internal #32770 dialog, so a hosted
     * control's WM_NOTIFY — the NM_CUSTOMDRAW item stages ListView and SysLink
     * coloring depend on, and DTN_DROPDOWN — lands on that dialog and never
     * reaches Proc on the DarkGui frame. Subclass the dialog once (through
     * Subclass, so it reclaims on WM_NCDESTROY like every other proc) and
     * answer the same notifications via _DispatchNotify.
     */
    static EnsureNotifyRelay(hwndDlg) {
        if !hwndDlg
            return
        Subclass.Install(DarkWindowProc.Relay, hwndDlg, ObjBindMethod(this, "NotifyRelayProc", hwndDlg))
    }

    /**
     * Framework-owned relay decision, called by every notify-based handler
     * after Apply: relay when the control's parent is not the DarkGui frame
     * (a Tab3 page) or when no frame proc exists at all (a direct SetDarkMode
     * on a plain Gui).
     * @param {Gui.Control} ctrl - The control just styled
     */
    static EnsureParentRelay(ctrl) {
        parentWnd := DllCall("GetParent", "Ptr", ctrl.Hwnd, "Ptr")
        if !parentWnd
            return
        frameHwnd := ctrl.Gui.Hwnd
        if parentWnd != frameHwnd || !Subclass.IsInstalled(DarkWindowProc, frameHwnd)
            this.EnsureNotifyRelay(parentWnd)
    }

    static NotifyRelayProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_NOTIFY := 0x004E
        if msg = WM_NOTIFY {
            reply := this._DispatchNotify(lParam, &handled)
            if handled
                return reply
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    /**
     * The one WM_NOTIFY answer table, shared by the frame Proc and the Tab3
     * relay so the two cannot drift. A control-side OnNotify reply never
     * reaches the control as the message result (probe-verified), which is
     * why NM_CUSTOMDRAW must be answered from the parent.
     * @param {Ptr} lParam - NMHDR pointer
     * @param {Boolean} &handled - true when the reply must be returned as-is
     * @returns {Integer} The message reply (meaningful only when handled)
     */
    static _DispatchNotify(lParam, &handled) {
        handled := false
        nm := DM_NMHDR.At(lParam)
        h := this._children.Get(nm.hwndFrom, 0)
        if h && HasMethod(h, "OnNotify")
            return h.OnNotify(nm, lParam, &handled)
        return 0
    }

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
        spec := this._children.Get(hwnd, 0)
        if !(spec is DarkWindowProc.StaticColorSpec) {
            spec := DarkWindowProc.StaticColorSpec()
            this._children[hwnd] := spec
        }
        spec.slots[slot] := color
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /** Drops a control's overrides so it follows the palette again. */
    static ClearStaticColor(hwnd) {
        if !(this._children.Get(hwnd, 0) is DarkWindowProc.StaticColorSpec)
            return
        this._children.Delete(hwnd)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    /**
     * Installs dark window procedure on a window.
     * @param {Ptr} hwnd - Window handle
     */
    static Install(hwnd) {
        Subclass.Install(this, hwnd, ObjBindMethod(this, "Proc", hwnd))
    }

    /** Overpaints the 1px light line the OS draws under a native menu bar.
     *  Window-DC coordinates; called after default WM_NCPAINT/WM_NCACTIVATE. */
    static _PaintMenuBarBottomLine(hwnd) {
        mbi := DM_MENUBARINFO()
        mbi.cbSize := mbi.Size
        if !DllCall("GetMenuBarInfo", "Ptr", hwnd, "Int", -3, "Int", 0, "Ptr", mbi.Ptr)  ; OBJID_MENU
            return
        rcWin := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
        hdc := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return
        line := DM_RECT()
        line.left := mbi.rcBar.left - rcWin.left
        line.top := mbi.rcBar.bottom - rcWin.top
        line.right := mbi.rcBar.right - rcWin.left
        line.bottom := line.top + 1
        DllCall("FillRect", "Ptr", hdc, "Ptr", line, "Ptr", DarkTheme.GetBrush("Header"), "Void")
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc, "Void")
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
        static TRANSPARENT := 1
        static WM_NCDESTROY := 0x0082

        if hwnd != targetHwnd
            return Subclass.Forward(hwnd, msg, wParam, lParam)

        ; Native menu BAR dark rendering (undocumented UAH messages; sent only
        ; to windows carrying a native Gui.MenuBar). Without these a stock
        ; MenuBar renders as a light strip over the dark window.
        static WM_UAHDRAWMENU := 0x0091
        static WM_UAHDRAWMENUITEM := 0x0092
        static WM_NCPAINT := 0x0085, WM_NCACTIVATE := 0x0086

        if msg = WM_UAHDRAWMENU {
            um := DM_UAHMENU.At(lParam)
            mbi := DM_MENUBARINFO()
            mbi.cbSize := mbi.Size
            ; OBJID_MENU = -3. Bar rect is in screen coords; the UAH DC is a
            ; window DC, so map via the window origin.
            if !DllCall("GetMenuBarInfo", "Ptr", targetHwnd, "Int", -3, "Int", 0, "Ptr", mbi.Ptr)
                return Subclass.Forward(hwnd, msg, wParam, lParam)
            rcWin := DM_RECT()
            DllCall("GetWindowRect", "Ptr", targetHwnd, "Ptr", rcWin)
            bar := DM_RECT()
            bar.left := mbi.rcBar.left - rcWin.left
            bar.top := mbi.rcBar.top - rcWin.top
            bar.right := mbi.rcBar.right - rcWin.left
            bar.bottom := mbi.rcBar.bottom - rcWin.top
            DllCall("FillRect", "Ptr", um.hdc, "Ptr", bar, "Ptr", DarkTheme.GetBrush("Header"), "Void")
            return 1
        }

        if msg = WM_UAHDRAWMENUITEM {
            static MIIM_STRING := 0x40
            static ODS_SELECTED := 0x1, ODS_GRAYED := 0x2, ODS_HOTLIGHT := 0x40, ODS_NOACCEL := 0x100
            static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20, DT_HIDEPREFIX := 0x100000
            udmi := DM_UAHDRAWMENUITEM.At(lParam)
            ; Item caption via position (the UAH payload carries no text).
            static textBuf := Buffer(512, 0)
            static mii := Buffer(80, 0)  ; MENUITEMINFOW, x64 layout
            NumPut("UInt", 80, mii, 0)               ; cbSize
            NumPut("UInt", MIIM_STRING, mii, 4)      ; fMask
            NumPut("Ptr", textBuf.Ptr, mii, 56)      ; dwTypeData
            NumPut("UInt", 255, mii, 64)             ; cch
            DllCall("GetMenuItemInfoW", "Ptr", udmi.um.hmenu, "UInt", udmi.umi.iPosition, "Int", 1, "Ptr", mii)

            state := udmi.dis.itemState
            bg := (state & ODS_SELECTED) ? "ControlsActive"
                : (state & ODS_HOTLIGHT) ? "ControlsHover" : "Header"
            fg := (state & ODS_GRAYED) ? "DisabledText" : "Font"
            ; DRAWITEMSTRUCT.rcItem sits at offset 40 on x64.
            rcItem := DM_RECT.At(lParam + 40)
            DllCall("FillRect", "Ptr", udmi.um.hdc, "Ptr", rcItem.Ptr, "Ptr", DarkTheme.GetBrush(bg), "Void")
            DllCall("SetBkMode", "Ptr", udmi.um.hdc, "Int", 1, "Void")
            DllCall("SetTextColor", "Ptr", udmi.um.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[fg]), "Void")
            flags := DT_CENTER | DT_VCENTER | DT_SINGLELINE | ((state & ODS_NOACCEL) ? DT_HIDEPREFIX : 0)
            DllCall("DrawTextW", "Ptr", udmi.um.hdc, "Ptr", textBuf.Ptr, "Int", -1, "Ptr", rcItem.Ptr, "UInt", flags, "Void")
            return 1
        }

        ; The OS draws a 1px light line under the menu bar during non-client
        ; painting — overpaint it after the default handling.
        if (msg = WM_NCPAINT || msg = WM_NCACTIVATE) && DllCall("GetMenu", "Ptr", targetHwnd, "Ptr") {
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            this._PaintMenuBarBottomLine(targetHwnd)
            return ret
        }

        if msg = WM_NCDESTROY {
            ; The dark window itself is dying. Drop its per-window
            ; registrations and sweep dead control hwnds out of the tracking
            ; maps — _Teardown does the same, but it only runs from
            ; __Delete/Detach, which lingering object references can block.
            ; Children get WM_NCDESTROY before their parent, so every child
            ; hwnd already fails IsWindow here.
            ret := Subclass.Forward(hwnd, msg, wParam, lParam)
            Subclass.Uninstall(this, targetHwnd, true)
            if DarkTheme.Windows.Has(targetHwnd)
                DarkTheme.Windows.Delete(targetHwnd)
            if DarkGui.DpiChangedCallbacks.Has(targetHwnd)
                DarkGui.DpiChangedCallbacks.Delete(targetHwnd)
            ; An Attach'd plain Gui has no __Delete to give back the theme
            ; ref it took; release it here when it dies without Detach.
            if DarkGui._attached.Has(targetHwnd) {
                DarkGui._attached.Delete(targetHwnd)
                DarkTheme.Release()
            }
            this.SweepDead()
            return ret
        }

        ; Parent-side replies a child registered for (WM_CTLCOLOR*: lParam is
        ; the control). A handler returning 0 falls through to the defaults.
        if msg = WM_CTLCOLOREDIT || msg = WM_CTLCOLORLISTBOX || msg = WM_CTLCOLORBTN || msg = WM_CTLCOLORSTATIC {
            h := this._children.Get(lParam, 0)
            if h && HasMethod(h, "OnCtlColor") {
                brush := h.OnCtlColor(lParam, wParam, msg)
                if brush
                    return brush
            }
        }

        switch msg {
            case WM_CTLCOLOREDIT:
                ; Disabled controls dim via the palette's Disabled pair — the
                ; palette defines them, but only owner-draw classes consulted
                ; them before; message-colored controls stayed full-bright.
                enabled := DllCall("IsWindowEnabled", "Ptr", lParam)
                fg := enabled ? "Font" : "DisabledText"
                bg := enabled ? "Controls" : "DisabledBg"
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[fg]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[bg]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush(bg)

            case WM_CTLCOLORLISTBOX:
                ; Standalone ListBox: Controls fill, dimmed when disabled. A
                ; ComboBox dropdown list is answered above by its child handler.
                enabled := DllCall("IsWindowEnabled", "Ptr", lParam)
                return this.CtlColorReply(wParam, enabled ? "Font" : "DisabledText", enabled ? "Controls" : "DisabledBg")

            case WM_CTLCOLORBTN:
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush("Background")

            case WM_CTLCOLORSTATIC:
                ; lParam = control handle in WM_CTLCOLOR messages. Per-control
                ; overrides (SetTextColor/SetBackColor) and menu-bar labels are
                ; answered above by their child handlers.
                ; Read-only and disabled Edit controls arrive HERE, not as
                ; WM_CTLCOLOREDIT — without the class check they flip to the
                ; window Background fill and stop reading as fields.
                static clsBuf := Buffer(64, 0)
                DllCall("GetClassNameW", "Ptr", lParam, "Ptr", clsBuf, "Int", 32)
                isEdit := StrGet(clsBuf) = "Edit"
                enabled := DllCall("IsWindowEnabled", "Ptr", lParam)
                fg := enabled ? "Font" : "DisabledText"
                bg := isEdit ? (enabled ? "Controls" : "DisabledBg") : "Background"
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[fg]))
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors[bg]))
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return DarkTheme.GetBrush(bg)

            case WM_DRAWITEM:
                ; Owner-drawn parts (the dark StatusBar) paint via their child handler.
                dis := DM_DRAWITEMSTRUCT.At(lParam)
                h := this._children.Get(dis.hwndItem, 0)
                if h && HasMethod(h, "OnDrawItem") && h.OnDrawItem(dis)
                    return 1

            case WM_NOTIFY:
                reply := this._DispatchNotify(lParam, &handled)
                if handled
                    return reply

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
     * @param {Map} [options] - Configuration options (omit for all defaults).
     * @param {Integer} [options.menuBarHeight = 24] - Menu bar height in pixels.
     * @param {Integer} [options.toolbarHeight = 32] - Toolbar row height.
     * @param {Integer} [options.menuItemPadding = 12] - Horizontal padding per menu label.
     * @param {Integer} [options.menuFontSize = 9] - Font size for menu labels.
     * @param {Integer} [options.toolbarIconSize = 20] - Toolbar button icon size.
     * @param {Integer} [options.toolbarButtonSpacing = 4] - Gap between toolbar buttons.
     * @param {Integer} [options.toolbarSeparatorWidth = 1] - Toolbar separator line width.
     * @param {Boolean} [options.showToolbar = true] - Whether to show the toolbar row.
     * @param {Integer} [options.popupOffsetX = 0] - Popup menu X offset from label.
     * @param {Integer} [options.popupOffsetY = 0] - Popup menu Y offset from label.
     * @param {Integer} [options.menuBarBg / menuBarText / menuBarHover / menuBarActive]
     *   - Color overrides for the bar (default from the live palette).
     * @param {Integer} [options.popupBg / toolbarBg / toolbarBorder]
     *   - Color overrides for popups and the toolbar row.
     */
    __New(parentGui, options := unset) {
        options := options ?? Map()
        this.gui := parentGui
        ; Cached for Destroy: Gui.Hwnd throws once the window is gone.
        this._guiHwnd := parentGui.Hwnd
        this.menuItems := []
        this.toolbarBtns := []
        this.hoveredMenu := ""

        this.layout := Map()
        this.layout["menuBarHeight"] := options.Get("menuBarHeight", 24)
        this.layout["toolbarHeight"] := options.Get("toolbarHeight", 32)
        this.layout["menuItemPadding"] := options.Get("menuItemPadding", 12)
        this.layout["menuFontSize"] := options.Get("menuFontSize", 9)
        this.layout["toolbarIconSize"] := options.Get("toolbarIconSize", 20)
        this.layout["toolbarButtonSpacing"] := options.Get("toolbarButtonSpacing", 4)
        this.layout["toolbarSeparatorWidth"] := options.Get("toolbarSeparatorWidth", 1)
        this.layout["showToolbar"] := options.Get("showToolbar", true)
        this.layout["popupOffsetX"] := options.Get("popupOffsetX", 0)
        this.layout["popupOffsetY"] := options.Get("popupOffsetY", 0)

        this.colors := Map()
        ; Strip fills default to the window Background: the Header default was
        ; never rendered before the Text `Background<X>` option became real
        ; (DarkWindowProc used to force Background on every Static), so the
        ; look people actually saw is the window colour. Pass menuBarBg /
        ; toolbarBg for a distinct strip.
        this.colors["menuBarBg"] := options.Get("menuBarBg", DarkTheme.Colors["Background"])
        this.colors["menuBarText"] := options.Get("menuBarText", DarkTheme.Colors["Font"])
        this.colors["menuBarHover"] := options.Get("menuBarHover", DarkTheme.Colors["ControlsActive"])
        this.colors["menuBarActive"] := options.Get("menuBarActive", DarkTheme.Colors["Accent"])
        this.colors["popupBg"] := options.Get("popupBg", DarkTheme.Colors["Header"])
        this.colors["toolbarBg"] := options.Get("toolbarBg", DarkTheme.Colors["Background"])
        this.colors["toolbarBorder"] := options.Get("toolbarBorder", DarkTheme.Colors["Border"])

        ; Popup background brush is owned by this menu bar, not by DarkTheme's
        ; value cache — see ApplyDarkThemeToPopup for why. Track whether popupBg
        ; was caller-supplied so palette swaps only retint the defaulted case.
        this._popupBrush := 0
        this._popupBgDefault := !options.Has("popupBg")
        this._destroyed := false

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

        ; Keyboard path: Alt+mnemonic arrives as WM_SYSCHAR, F10 as
        ; WM_SYSKEYDOWN — both open the popup like a native menu bar.
        this._switchTo := 0
        this._onSysChar := this.OnSysChar.Bind(this)
        OnMessage(0x0106, this._onSysChar)
        this._onSysKeyDown := this.OnSysKeyDown.Bind(this)
        OnMessage(0x0104, this._onSysKeyDown)

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
        ; Ride the strip's WM_NCDESTROY so the popups, brush and process-wide
        ; OnMessage hooks go with the window. Before this the only trigger was
        ; the 0x200 monitor's self-heal — i.e. the next mouse move anywhere in
        ; the script — and until then every one of them outlived the Gui.
        Subclass.Install(this, this.menuBar.Hwnd, ObjBindMethod(this, "_StripProc"))

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

        menuItemData := Map()
        menuItemData["name"] := menuName
        menuItemData["label"] := menuLabel
        menuItemData["hitArea"] := hitArea
        menuItemData["popup"] := hPopup
        menuItemData["x"] := this.menuBarStartX
        menuItemData["width"] := itemWidth
        ; Alt+<mnemonic> opens this menu: the char after "&" when present
        ; (the Text control already renders it underlined), else the first.
        amp := InStr(menuName, "&")
        menuItemData["mnemonic"] := StrUpper(amp && amp < StrLen(menuName)
            ? SubStr(menuName, amp + 1, 1) : SubStr(menuName, 1, 1))

        this.menuItems.Push(menuItemData)
        this.popupMenus[menuName] := hPopup

        ; Register both statics as child handlers so WM_CTLCOLORSTATIC returns
        ; HOLLOW_BRUSH (preserves BackgroundTrans and the Font colour on the bar).
        menuItemData["labelHwnd"] := menuLabel.Hwnd
        menuItemData["hitHwnd"] := hitArea.Hwnd
        DarkWindowProc.RegisterChild(menuLabel.Hwnd, DarkMenuBar.LabelColors)
        DarkWindowProc.RegisterChild(hitArea.Hwnd, DarkMenuBar.LabelColors)

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

        btnData := Map()
        btnData["bg"] := btnBg
        btnData["icon"] := btnIcon
        btnData["hit"] := btnHit
        btnData["x"] := btnX
        btnData["y"] := btnY
        btnData["tooltip"] := tooltip
        btnData["tipBuf"] := tipBuf

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
        ; Hover-switching loop: while a popup is open, sliding the pointer
        ; onto another top-level item ends the current track and opens the
        ; neighbor — the native menu-bar behavior a single modal
        ; TrackPopupMenu call can't provide.
        while hPopup
            hPopup := this._TrackOnce(hPopup)
    }

    /** Tracks one popup; returns the neighbor popup to open when the hover
     *  watcher ended the track, else 0. */
    _TrackOnce(hPopup) {
        popupX := 0
        popupY := 0
        cur := ""

        for item in this.menuItems {
            if item["popup"] = hPopup {
                cur := item
                ctrlRect := DM_RECT()
                DllCall("GetWindowRect", "Ptr", item["hitArea"].Hwnd, "Ptr", ctrlRect)

                popupX := ctrlRect.left   ; Left
                popupY := ctrlRect.bottom  ; Bottom

                item["label"].Opt("Background" . Format("{:06X}", this.colors["menuBarActive"]))
                labelRef := item["label"]
                lblHwnd := labelRef.Hwnd
                ; Reset hoveredMenu too — with only the label reset, a pointer
                ; still resting on the item compared equal and the hover
                ; background never re-applied until the mouse left and re-entered.
                ; IsWindow guard: AHK timers can't run inside TrackPopupMenu's
                ; modal loop, so this closure is already overdue when the menu
                ; closes and the chosen command runs FIRST — a command that
                ; destroys the window would leave .Opt touching a dead control.
                SetTimer(() => (DllCall("IsWindow", "Ptr", lblHwnd) ? labelRef.Opt("BackgroundTrans") : 0,
                    this.hoveredMenu := "", 0), -200)
                break
            }
        }

        popupX += this.layout["popupOffsetX"]
        popupY += this.layout["popupOffsetY"]

        ; The watcher must tick INSIDE TrackPopupMenu's modal loop, which
        ; blocks AHK's own timers — a native WM_TIMER with a TIMERPROC is
        ; dispatched by any message loop, including the menu's.
        this._switchTo := 0
        watcherProc := CallbackCreate(ObjBindMethod(this, "_HoverWatcher", cur), , 4)
        DllCall("SetTimer", "Ptr", this._guiHwnd, "Ptr", 0xDA7C, "UInt", 40, "Ptr", watcherProc)
        DllCall("TrackPopupMenu", "Ptr", hPopup, "UInt", 0x0000, "Int", popupX, "Int", popupY, "Int", 0, "Ptr", this._guiHwnd, "Ptr", 0)
        DllCall("KillTimer", "Ptr", this._guiHwnd, "Ptr", 0xDA7C)
        CallbackFree(watcherProc)
        return this._switchTo
    }

    /** TIMERPROC (runs inside the menu modal loop): when the pointer enters a
     *  DIFFERENT top-level item, remember it and dismiss the open popup. */
    _HoverWatcher(curItem, hwnd, msg, idEvent, tickCount) {
        static pt := DM_POINT(), rc := DM_RECT()
        DllCall("GetCursorPos", "Ptr", pt.Ptr)
        for item in this.menuItems {
            if item = curItem
                continue
            DllCall("GetWindowRect", "Ptr", item["hitArea"].Hwnd, "Ptr", rc)
            if pt.x >= rc.left && pt.x < rc.right && pt.y >= rc.top && pt.y < rc.bottom {
                this._switchTo := item["popup"]
                DllCall("EndMenu")
                return
            }
        }
    }

    /** WM_SYSCHAR: Alt+<mnemonic> opens the matching menu. */
    OnSysChar(wParam, lParam, msg, hwnd) {
        static GA_ROOT := 2
        if !DllCall("IsWindow", "Ptr", this._guiHwnd)
            || DllCall("GetAncestor", "Ptr", hwnd, "UInt", GA_ROOT, "Ptr") != this._guiHwnd
            return
        ch := StrUpper(Chr(wParam))
        for item in this.menuItems {
            if item["mnemonic"] = ch {
                this.ShowPopupMenu(item["popup"], item["x"])
                return 0
            }
        }
    }

    /** WM_SYSKEYDOWN: F10 opens the first menu, like a native bar. */
    OnSysKeyDown(wParam, lParam, msg, hwnd) {
        static VK_F10 := 0x79, GA_ROOT := 2
        if wParam != VK_F10 || !this.menuItems.Length
            return
        if !DllCall("IsWindow", "Ptr", this._guiHwnd)
            || DllCall("GetAncestor", "Ptr", hwnd, "UInt", GA_ROOT, "Ptr") != this._guiHwnd
            return
        this.ShowPopupMenu(this.menuItems[1]["popup"], this.menuItems[1]["x"])
        return 0
    }

    OnMouseMove(wParam, lParam, msg, hwnd) {
        ; Self-heal: this is a process-wide 0x200 monitor. If the parent window
        ; died without Destroy(), tear down now — otherwise every subsequent
        ; mouse move over any script window would dereference the dead Gui.
        if !DllCall("IsWindow", "Ptr", this._guiHwnd) {
            this.Destroy()
            return
        }
        ; The interactive rects are covered by SS_NOTIFY hit-area statics, so
        ; real moves arrive addressed to those CHILD hwnds — a gui-hwnd filter
        ; here discarded them all and hover highlighting never fired. Accept
        ; anything rooted in our window and hit-test in SCREEN space against
        ; the live control rects (which also sidesteps the logical-vs-physical
        ; DPI mismatch of comparing client px to stored layout coords).
        static GA_ROOT := 2
        if DllCall("GetAncestor", "Ptr", hwnd, "UInt", GA_ROOT, "Ptr") != this._guiHwnd
            return

        pt := DM_POINT()
        pt.x := lParam & 0xFFFF
        pt.y := (lParam >> 16) & 0xFFFF
        if pt.x & 0x8000
            pt.x -= 0x10000
        if pt.y & 0x8000
            pt.y -= 0x10000
        DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt.Ptr, "Void")
        sx := pt.x
        sy := pt.y

        hoveredItem := ""
        rc := DM_RECT()
        for item in this.menuItems {
            DllCall("GetWindowRect", "Ptr", item["hitArea"].Hwnd, "Ptr", rc)
            if sx >= rc.left && sx < rc.right && sy >= rc.top && sy < rc.bottom {
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

        if this.layout["showToolbar"]
            this.HandleToolbarHover(sx, sy)
    }

    HandleToolbarHover(sx, sy) {
        hoveredBtn := ""
        rc := DM_RECT()
        for btn in this.toolbarBtns {
            DllCall("GetWindowRect", "Ptr", btn["hit"].Hwnd, "Ptr", rc)
            if sx >= rc.left && sx < rc.right && sy >= rc.top && sy < rc.bottom {
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
        ; GetTextExtentPoint32W returns PHYSICAL pixels, but the caller feeds
        ; this into Gui.Add/Move options, which are LOGICAL units that AHK
        ; scales by the window DPI — passing physical straight through made
        ; every menu label ~25% too wide at 125%. Convert back to logical.
        dpi := DllCall("user32\GetDpiForWindow", "Ptr", ctrl.Hwnd, "UInt")
        if !dpi
            dpi := A_ScreenDPI
        return Round(sz.cx * 96 / dpi)
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
    /** Pass-through proc on the strip Static; it exists for the NCDESTROY
     *  reclaim {@link Subclass._Wrap} adds, which lands in OnDestroyed. */
    _StripProc(hwnd, msg, wParam, lParam) {
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    OnDestroyed(hwnd) {
        this.Destroy()
    }

    Destroy() {
        ; Idempotent: reachable from user code, the mouse-move self-heal and the
        ; strip's NCDESTROY, in any order.
        if this._destroyed
            return
        this._destroyed := true
        OnMessage(0x200, this._onMouseMove, 0)
        OnMessage(0x0106, this._onSysChar, 0)
        OnMessage(0x0104, this._onSysKeyDown, 0)
        DarkTheme.OffThemeChanged(this._onPaletteChanged)
        ; Unhook the Size handler only while the window still exists —
        ; OnEvent on a destroyed Gui throws, and the handler dies with it.
        ; try: IsWindow tests the raw handle system-wide, so a recycled hwnd
        ; can false-positive on a disposed Gui — a throw here must not abort
        ; the DestroyMenu/DeleteObject/DestroyWindow cleanup below.
        if DllCall("IsWindow", "Ptr", this._guiHwnd)
            try this.gui.OnEvent("Size", this._onParentSize, 0)
        for item in this.menuItems {
            if item.Has("popup")
                DllCall("DestroyMenu", "Ptr", item["popup"], "Void")
            if item.Has("labelHwnd")
                DarkWindowProc.UnregisterChild(item["labelHwnd"])
            if item.Has("hitHwnd")
                DarkWindowProc.UnregisterChild(item["hitHwnd"])
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

    /** Child handler for the menu-bar label statics: Font text over a hollow
     *  brush so the BackgroundTrans strip shows through. */
    class LabelColors {
        static OnCtlColor(hwndCtl, hdc, msg) {
            static TRANSPARENT := 1, HOLLOW_BRUSH := 5
            DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
            DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", TRANSPARENT)
            return DllCall("gdi32\GetStockObject", "Int", HOLLOW_BRUSH, "Ptr")
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
    /** @type {Boolean} False when construction stood down (high contrast) —
     * teardown must then not Release a refcount it never took. */
    _darkActive := false

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
        ; High contrast: leave the window entirely stock so the user's chosen
        ; accessibility scheme shows through. Add() still works — _AddStyled
        ; checks the same flag — so the app needs no conditional code.
        if DarkTheme.StandDown()
            return
        this._darkActive := true
        DarkTheme.AddRef()
        DarkTheme.Windows[this._hwnd] := true
        _DarkPaletteSync.Ensure()
        this.BackColor := DarkTheme.Colors["Background"]
        this.SetFont("s9", "Segoe UI")
        ; Frame flag follows the palette — a window constructed under the
        ; Light preset must not get an immersive-dark frame until re-sync.
        DarkTitleBar.Apply(this.Hwnd, DarkTheme.IsDarkPalette())
        DarkMenu.Apply()
        DarkToolTip.AutoApply()
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

    /** @type {Error|Integer} Last exception raised by a handler's Remove or
     *  Refresh (0 = none). Teardown and palette refresh keep going past one
     *  failing control; the error is kept here for diagnosis. */
    static LastHandlerError := 0

    /** @type {Map} hwnd -> callback(hwnd, newDpi, suggestedRect) for WM_DPICHANGED */
    static DpiChangedCallbacks := Map()

    /**
     * Registers every built-in handler, installs the prototype sugar and
     * generates the AddXxx shorthands. Runs once when DarkGui is first
     * referenced (or reached by the auto-execute section), which is also what
     * initialises every control class — so DarkGui() / DarkGui.Attach() work
     * even when this file is #Included below a `return`. Inherited by
     * subclasses (`_Dark`): guard so it runs for DarkGui only.
     */
    static __New() {
        if this != DarkGui
            return
        this.Handlers.CaseSense := "Off"
        this.Register("Text", _DarkText)
        this.Register("Button", _DarkButton)
        this.Register("CheckBox", _DarkCheckBox)
        this.Register("Radio", _DarkRadio)
        this.Register("Edit", _DarkEdit)
        this.Register("DDL", _DarkComboBox)
        this.Register("ComboBox", _DarkComboBox)
        this.Register("ListView", _DarkListView)
        this.Register("TreeView", _DarkTreeView)
        this.Register("ListBox", _DarkListBox)
        this.Register("Progress", _DarkProgress)
        this.Register("Slider", _DarkSlider)
        this.Register("GroupBox", _DarkGroupBox)
        this.Register("Tab", _DarkTab)
        this.Register("Tab2", _DarkTab)
        this.Register("Tab3", _DarkTab)
        this.Register("UpDown", _DarkUpDown)
        this.Register("StatusBar", _DarkStatusBar)
        this.Register("Link", _DarkLink)
        this.Register("MonthCal", _DarkMonthCal)
        this.Register("DateTime", _DarkDateTime)
        this.Register("Hotkey", _DarkHotkey)
        this._InstallPrototypes()
        this._InstallShorthands()
    }

    /**
     * Registers a per-monitor DPI-change callback for this window. The window
     * is already moved to the OS-suggested rect before the callback runs; use
     * it to re-Scale and reposition controls (`DarkTheme.Scale(px, hwnd)`).
     * Fires only in per-monitor-DPI-aware processes.
     * @param {Func} callback - `callback(hwnd, newDpi, suggestedRect)`
     */
    OnDpiChanged(callback) => DarkGui.DpiChangedCallbacks[this._hwnd] := callback

    /**
     * Registers a dark-styling handler for a control type — the ONE dispatch
     * table behind Add, Attach, teardown and palette refresh. Built-ins are
     * registered by DarkGui's static __New; registering a type again replaces
     * it, so an app can override "Button" or "ListView" wholesale.
     *
     * Handler protocol (duck-typed, checked with HasMethod):
     *   Apply(owner, ctrl, options := "", content?)  required. `options` are
     *       the ORIGINAL creation options ("+Accent" still present; "" on a
     *       retrofit). `content` is passed only when Apply declares a 4th
     *       parameter, so external 3-parameter handlers keep working.
     *   Remove(hwnd)        optional. Undo Apply for a live window (Detach) or
     *       at DarkGui teardown. Uninstalling a Subclass is enough for most.
     *   Refresh(ctrl)       optional. Re-push colours the control STORES
     *       (LVM/TVM/MCM/SB messages, SetFont) after SetPalette/ApplyPreset.
     *       Controls that read DarkTheme.Colors per paint need none.
     *   OnDestroyed(hwnd)   optional. Called by Subclass._Wrap on WM_NCDESTROY
     *       for any hwnd the handler subclassed — drop per-hwnd state there.
     *
     * Keys are normalised so the name passed to Add() and the name ctrl.Type
     * reports both resolve ("Picture"/"Pic", "DropDownList"/"DDL"). A windowed
     * "Custom" control can be keyed by its Win32 class:
     *     DarkGui.Register("Custom", DarkRichEdit, "RICHEDIT50W")
     * which is tried before the plain "custom" slot.
     *
     * @param {String} controlType - Type name as passed to Add() or reported by ctrl.Type
     * @param {Object} handler - Class or object implementing the protocol
     * @param {String} [windowClass=""] - Win32 class name, for Type "Custom" only
     */
    static Register(controlType, handler, windowClass := "") {
        if !HasMethod(handler, "Apply")
            throw ValueError("DarkGui.Register: handler must have an Apply(owner, ctrl, options) method", -1)
        fn := GetMethod(handler, "Apply")
        if !fn.IsVariadic && fn.MaxParams < 4
            throw ValueError("DarkGui.Register: Apply must accept (owner, ctrl, options)", -1)
        this.Handlers[DarkGui._TypeKey(controlType, windowClass)] := handler
    }

    /**
     * Removes a handler registered with {@link DarkGui.Register}. Controls
     * already styled keep their styling; only future Adds are affected.
     * @returns {Boolean} true when an entry was removed
     */
    static Unregister(controlType, windowClass := "") {
        key := DarkGui._TypeKey(controlType, windowClass)
        if !this.Handlers.Has(key)
            return false
        this.Handlers.Delete(key)
        return true
    }

    /** Registry key for a type name: lowercase, aliases folded to what
     *  ctrl.Type reports, optional ":WINDOWCLASS" suffix for Custom. */
    static _TypeKey(controlType, windowClass := "") {
        key := StrLower(controlType)
        switch key {
            case "picture": key := "pic"
            case "dropdownlist": key := "ddl"
        }
        if windowClass != ""
            key .= ":" StrUpper(windowClass)
        return key
    }

    /**
     * Resolves the handler for a control: a window-class key first for Custom
     * controls, then the plain type key. Sets `key` to the key that matched,
     * which is also the label stored in `_darkHwnds`.
     * @returns {Object|Integer} Handler, or 0 when the type is unregistered
     */
    static _HandlerFor(ctrl, &key) {
        key := DarkGui._TypeKey(ctrl.Type)
        if key = "custom" {
            clsKey := key ":" StrUpper(WinGetClass(ctrl.Hwnd))
            if this.Handlers.Has(clsKey) {
                key := clsKey
                return this.Handlers[clsKey]
            }
        }
        return this.Handlers.Get(key, 0)
    }

    /** True when a handler's Apply declares the optional 4th (content) parameter. */
    static _AcceptsContent(handler) {
        fn := GetMethod(handler, "Apply")
        return fn.IsVariadic || fn.MaxParams >= 5
    }

    /**
     * The dark option grammar, parsed out of a normal Gui options string.
     * Dark tokens are removed from the native options (AHK would reject
     * them); everything else passes through untouched.
     *   +Accent                 accent button
     *   +Flat / +Toggle[=on]    flat / latching button
     *   +Icon=<spec>            icon button; spec = "file.dll,index" or a path (no spaces)
     *   +Align=left|right|top|center    icon placement
     *   c<X> / Background<X>    X = 6-digit hex, an AHK colour name, or a
     *                           DarkTheme.Colors key (case-sensitive). A key is
     *                           handed to the native control as its current
     *                           hex; a Text control receives the key itself
     *                           (SetTextColor) so it follows presets.
     * Returns a Map: "accent"/"flat"/"toggle"/"icon"/"align" as given (true
     * for a bare token), and "color"/"background" as an 0xRRGGBB integer or a
     * palette-key string. Handlers call this on the options Apply receives.
     * @param {String} options - Gui.Add options
     * @returns {Map}
     */
    static ParseOptions(options) {
        return DarkGui._ParseOptions(options, &native)
    }

    /** ParseOptions plus the native remainder in `native`. */
    static _ParseOptions(options, &native) {
        static tokenRe := "i)(?<=^|\s)\+(Accent|Flat|Toggle|Icon|Align)(?:=(\S+))?(?=\s|$)"
        static colorRe := "i)(?<=^|\s)(c|Background)([0-9A-Fa-f]{6}|[A-Za-z][A-Za-z0-9]*)(?=\s|$)"
        opts := Map()
        native := options
        pos := 1
        loop {
            pos := RegExMatch(native, tokenRe, &m, pos)
            if !pos
                break
            opts[StrLower(m[1])] := (m.Count >= 2 && m[2] != "") ? m[2] : true
            native := SubStr(native, 1, m.Pos - 1) SubStr(native, m.Pos + m.Len)
        }
        pos := 1
        loop {
            pos := RegExMatch(native, colorRe, &m, pos)
            if !pos
                break
            pos := m.Pos + 1
            if !DarkGui._ColorValue(m[2], &value, &isKey)
                continue
            opts[StrLower(m[1]) = "c" ? "color" : "background"] := value
            if isKey {
                ; AHK cannot parse a palette key; hand it the key's current hex.
                hex := m[1] Format("{:06X}", DarkTheme.Colors[value])
                native := SubStr(native, 1, m.Pos - 1) hex SubStr(native, m.Pos + m.Len)
            }
        }
        return opts
    }

    /**
     * Resolves one colour word. A DarkTheme.Colors key is returned as the key
     * (isKey true); a 6-digit hex or an AHK colour name as 0xRRGGBB. Anything
     * else ("enter" from "Center", "hecked" from "Checked", "Trans") is not a
     * colour and returns false.
     */
    static _ColorValue(word, &value, &isKey) {
        static names := 0
        if !names {
            names := Map()
            names.CaseSense := "Off"
            names["Black"] := 0x000000, names["Silver"] := 0xC0C0C0, names["Gray"] := 0x808080
            names["White"] := 0xFFFFFF, names["Maroon"] := 0x800000, names["Red"] := 0xFF0000
            names["Purple"] := 0x800080, names["Fuchsia"] := 0xFF00FF, names["Green"] := 0x008000
            names["Lime"] := 0x00FF00, names["Olive"] := 0x808000, names["Yellow"] := 0xFFFF00
            names["Navy"] := 0x000080, names["Blue"] := 0x0000FF, names["Teal"] := 0x008080
            names["Aqua"] := 0x00FFFF
        }
        isKey := false
        if DarkTheme.Colors.Has(word) {
            value := word
            isKey := true
            return true
        }
        if names.Has(word) {
            value := names[word]
            return true
        }
        if RegExMatch(word, "^[0-9A-Fa-f]{6}$") {
            value := Integer("0x" word)
            return true
        }
        return false
    }

    /**
     * The single seam for styling one control in place — what
     * `ctrl.SetDarkMode(options)` calls. Honours the high-contrast stand-down
     * like Add does, dispatches through the registry, and tracks the control
     * when its Gui is dark-managed (a DarkGui or an Attach'd Gui).
     * @param {Gui.Control} ctrl - Control to style
     * @param {String} [options=""] - Dark options ("+Accent"); native options are ignored here
     * @param {*} [content] - Creation content, when styling right after Add
     * @returns {Gui.Control} The same control
     */
    static ApplyTo(ctrl, options := "", content?) {
        if DarkTheme.StandDown()
            return ctrl
        DarkGui._ApplyType(ctrl.Gui, ctrl, options, content?)
        return ctrl
    }

    /**
     * Installs the control-level sugar once, on the base prototypes:
     *   ctrl.SetDarkMode(options := "")          -> DarkGui.ApplyTo (every type)
     *   text.SetTextColor / SetBackColor / ResetColors -> DarkWindowProc overrides
     */
    static _InstallPrototypes() {
        Gui.Control.Prototype.DefineProp("SetDarkMode", { Call: (ctrl, options := "") => DarkGui.ApplyTo(ctrl, options) })
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
    }

    /**
     * Generates the AddXxx shorthands and button-variant factories on
     * DarkGui.Prototype from the two tables, so a new type or variant is one
     * table line — Attach and Detach loop the same tables.
     */
    static _InstallShorthands() {
        for name, controlType in DarkGui._Shorthands()
            DarkGui.Prototype.DefineProp(name, { Call: DarkGui._ShorthandFor(controlType) })
        for name, fn in DarkGui._Variants()
            DarkGui.Prototype.DefineProp(name, { Call: fn })
    }

    /** @type {Func|Integer} Gui.Prototype.__New as it was before Global() wrapped it (0 = not wrapped). */
    static _origGuiNew := 0

    /** @type {Map} hwnd -> true for every plain Gui attached by Attach/Global.
     *  Such a window has no DarkGui.__Delete to give back the theme ref it
     *  took, so DarkWindowProc releases it on WM_NCDESTROY instead. */
    static _attached := Map()

    /**
     * One-line dark mode for a whole script. Every Gui constructed after this
     * call — a plain `Gui()`, a `class X extends Gui`, a Gui created inside
     * some other library — is attached to the framework the moment it exists:
     * frame, menus, the controls it already has, and every control added later
     * through Add or any AddXxx shorthand, exactly as {@link DarkGui.Attach}.
     * DarkGui instances are untouched (they style themselves).
     *
     *     #Include DarkModeModular.ahk
     *     DarkGui.Global()
     *
     * Guis constructed BEFORE the call are not affected — Attach them, or move
     * the call up. Idempotent. Global(false) unhooks the constructor (windows
     * already attached stay dark) and, with `dialogs`, uninstalls the dialogs.
     * @param {Boolean} [enable=true] - false to unhook
     * @param {Boolean} [dialogs=true] - also DarkDialogs.Install() / Uninstall() (dark MsgBox/InputBox)
     * @returns {Boolean} true when the constructor hook is active after the call
     */
    static Global(enable := true, dialogs := true) {
        if enable {
            if !this._origGuiNew {
                this._origGuiNew := Gui.Prototype.GetOwnPropDesc("__New").Call
                ; A named nested function, not `{ Call: DarkGui._method }`: a bare
                ; static Func in Call is invoked with the Gui in its hidden
                ; `this` slot, shifting every argument left.
                _globalNew(self, params*) {
                    (DarkGui._origGuiNew)(self, params*)
                    DarkGui.Attach(self)
                }
                Gui.Prototype.DefineProp("__New", { Call: _globalNew })
            }
            if dialogs
                DarkDialogs.Install()
            return true
        }
        if this._origGuiNew {
            Gui.Prototype.DefineProp("__New", { Call: this._origGuiNew })
            this._origGuiNew := 0
        }
        if dialogs
            DarkDialogs.Uninstall()
        return false
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
     * Radio uses the same native control and custom drawing as DarkGui. DPI callbacks
     * work: the retrofit Gui gains an OnDpiChanged(callback) registrar wired
     * to the same WM_DPICHANGED routing DarkGui uses. Teardown is not
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
        ; See DarkGui.__New — stand down under a high-contrast scheme.
        if DarkTheme.StandDown()
            return owner
        DarkTheme.AddRef()
        DarkTheme.Windows[owner.Hwnd] := true
        DarkGui._attached[owner.Hwnd] := true
        _DarkPaletteSync.Ensure()
        owner._darkHwnds := Map()
        owner._darkHwnd := owner.Hwnd
        owner.BackColor := DarkTheme.Colors["Background"]
        DarkTitleBar.Apply(owner.Hwnd, DarkTheme.IsDarkPalette())
        DarkMenu.Apply()
        DarkWindowProc.Install(owner.Hwnd)
        DarkGui._ApplyWin11Frame(owner.Hwnd)

        ; DPI parity with a real DarkGui: WM_DPICHANGED routing already works
        ; for attached windows (DarkWindowProc is installed above), so expose
        ; the same ergonomic registrar instead of forcing callers to write to
        ; DarkGui.DpiChangedCallbacks by hand.
        owner.DefineProp("OnDpiChanged", { Call: (self, cb) => DarkGui.DpiChangedCallbacks[self.Hwnd] := cb })

        ; Wrap in a closure rather than handing the static Func straight to Call:
        ; a bare `{ Call: DarkGui._AddStyled }` is invoked WITHOUT the object, so
        ; every argument shifts left and the control type lands in the Gui slot.
        owner.DefineProp("Add", { Call: (self, controlType, options := "", content?)
            => DarkGui._AddStyled(self, controlType, options, content?) })
        for name, controlType in DarkGui._Shorthands()
            owner.DefineProp(name, { Call: DarkGui._ShorthandFor(controlType) })

        ; Button-variant factories, from the same table DarkGui.Prototype uses.
        for name, fn in DarkGui._Variants()
            owner.DefineProp(name, { Call: fn })

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
        ; DarkGui instances tear down via __Delete and declare _darkHwnds as an
        ; instance field — Detach is strictly for Attach'd plain Guis.
        if owner is DarkGui || !HasProp(owner, "_darkHwnds")
            return
        DarkGui._Teardown(owner, owner._darkHwnd)
        if DarkGui._attached.Has(owner._darkHwnd)
            DarkGui._attached.Delete(owner._darkHwnd)
        DarkTheme.Release()
        ; Remove the attach markers so Attach/Detach round-trips: without this
        ; a later Attach hits the idempotence guard and returns a window whose
        ; window proc and theme registration are already gone (half-dark, no
        ; error), and a second Detach double-releases the theme refcount.
        owner.DeleteProp("_darkHwnds")
        owner.DeleteProp("_darkHwnd")
        ; Drop the installed method overrides too, so a Detached Gui really is
        ; a plain Gui again: Add() would otherwise keep dark-styling new
        ; controls into a torn-down window, and _Track silently drops them
        ; (no _darkHwnds), leaving controls no teardown can ever reach.
        for name in ["Add", "OnDpiChanged"]
            if owner.HasOwnProp(name)
                owner.DeleteProp(name)
        for name, controlType in DarkGui._Shorthands()
            if owner.HasOwnProp(name)
                owner.DeleteProp(name)
        for name, fn in DarkGui._Variants()
            if owner.HasOwnProp(name)
                owner.DeleteProp(name)
    }

    ; Cache fields are NOT named after the methods that fill them:
    ; identifiers are case-insensitive, so `_shorthands` and `_Shorthands()`
    ; would be one property (and the method wins — "Property is read-only").
    /** @type {Map|Integer} Cached shorthand table (built on first use). */
    static _shorthandTable := 0
    /** @type {Map|Integer} Cached variant-factory table (built on first use). */
    static _variantTable := 0

    /**
     * Button-variant factories: name -> Call closure taking the Gui as `self`.
     * The public, documented surface over the _DarkButton statics; this one
     * table feeds DarkGui.Prototype, Attach and Detach.
     * @returns {Map}
     */
    static _Variants() {
        if this._variantTable
            return this._variantTable
        m := Map()
        m["AddIconButton"] := (self, options, text, icon, align := "left") => _DarkButton.AddIcon(self, options, text, icon, align)
        m["AddSplitButton"] := (self, options, text, menuOrCallback) => _DarkButton.AddSplit(self, options, text, menuOrCallback)
        m["AddCommandLink"] := (self, options, title, description, icon := 0) => _DarkButton.AddCommand(self, options, title, description, icon)
        m["AddToggleButton"] := (self, options, text, initialState := false) => _DarkButton.AddToggle(self, options, text, initialState)
        m["AddFlatButton"] := (self, options, text) => _DarkButton.AddFlat(self, options, text)
        return this._variantTable := m
    }

    /** @returns {Map} AddXxx shorthand name -> control type it creates. */
    static _Shorthands() {
        if this._shorthandTable
            return this._shorthandTable
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
        ; Untyped-styling types: Picture needs none, ActiveX/Custom style only
        ; via a registered handler — but the forwarders must still route
        ; through _AddStyled so tracking and the Handlers registry fire.
        m["AddPicture"] := "Picture"
        m["AddPic"] := "Picture"
        m["AddActiveX"] := "ActiveX"
        m["AddCustom"] := "Custom"
        return this._shorthandTable := m
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
        DarkGui._ParseOptions(options, &native)
        options := native
        ; Stood down (high contrast): create the control stock. The dark tokens
        ; are stripped above either way so they never reach the native Add.
        if DarkTheme.StandDown()
            return Gui.Prototype.Add.Call(owner, controlType, options, content?)
        options := DarkGui._DefaultFontColor(controlType, options)
        ; The owning-Gui parameter is NOT named `gui`: identifiers are
        ; case-insensitive, so that name shadows the global Gui class and
        ; `Gui.Prototype` would resolve to the parameter instead.
        ctrl := Gui.Prototype.Add.Call(owner, controlType, options, content?)
        ; Retain the legacy group array for scripts calling _SelectRadio.
        ; Native HWND creation/input owns actual grouping; this adds no label
        ; controls or event handlers that could break native radio navigation.
        if ctrl.Type = "Radio" {
            if RegExMatch(options, "i)\bGroup\b") || !owner.HasOwnProp("_radioGroup")
                owner._radioGroup := []
            owner._radioGroup.Push(ctrl)
        } else if owner.HasOwnProp("_radioGroup")
            owner.DeleteProp("_radioGroup")
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
     * Dispatches through {@link DarkGui.Handlers}: the key that matched is the
     * label stored in `_darkHwnds`, so teardown and palette refresh reach the
     * same handler that styled the control. Radio follows this same path for both creation and retrofit.
     *
     * @param {Gui} owner - Owning Gui
     * @param {Gui.Control} ctrl - Control to style
     * @param {String} [options=""] - Original creation options ("" when retrofitting)
     * @param {*} [content] - Original creation content
     * @returns {Boolean} true when the type was recognised and styled
     */
    static _ApplyType(owner, ctrl, options := "", content?) {
        h := DarkGui._HandlerFor(ctrl, &key)
        if !h
            return false
        if IsSet(content) && DarkGui._AcceptsContent(h)
            h.Apply(owner, ctrl, options, content)
        else
            h.Apply(owner, ctrl, options)
        DarkGui._Track(owner, ctrl.Hwnd, key)
        return true
    }

    /**
     * Cleans up all dark mode resources for this GUI.
     * Removes subclasses from all tracked controls, clears stale entries from
     * {@link DarkWindowProc} tracking maps, and calls {@link DarkTheme.Release}.
     */
    __Delete() {
        ; Nothing was installed when construction stood down — Release() here
        ; would decrement a refcount this window never took.
        if !this._darkActive
            return
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
        ; Undo every tracked control through the handler that styled it. One
        ; failing Remove must not leak the rest; the error is kept for diagnosis.
        for ctrlHwnd, label in owner._darkHwnds {
            h := DarkGui.Handlers.Get(label, 0)
            if !h || !HasMethod(h, "Remove")
                continue
            try
                h.Remove(ctrlHwnd)
            catch Error as e
                DarkGui.LastHandlerError := e
        }
        owner._darkHwnds.Clear()

        ; DarkScrollbar instances live only in their static map (the host is a
        ; plain Text control, never in _darkHwnds); sweep the ones this gui owns
        ; so their sync timers stop with the window.
        for sbHwnd, sb in DarkScrollbar.Instances.Clone()
            if sb.gui = owner
                sb.Destroy()

        ; Clean stale entries from the DarkWindowProc tracking maps.
        DarkWindowProc.SweepDead()

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

    ; The AddXxx shorthands (AddButton, AddEdit, ... AddCustom) and the
    ; button-variant factories (AddIconButton, AddSplitButton, AddCommandLink,
    ; AddToggleButton, AddFlatButton) are generated onto DarkGui.Prototype by
    ; _InstallShorthands from _Shorthands() and _Variants(). The native
    ; Gui.AddButton/... methods bind to Gui.Prototype and would bypass the dark
    ; Add() override, so every styled type is forwarded through _AddStyled.

    /** Manually selects a radio and unchecks all others in its group */
    static _SelectRadio(selected, group) {
        for r in group
            r.Value := (r = selected)
    }

    /**
     * Sets a control's UIA/MSAA accessible name via IAccPropServices —
     * lets screen readers announce controls whose visual label lives in a
     * separate control. Retained for existing callers; native radios carry
     * their own caption now. Best-effort: returns false on failure.
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

    /** Compatibility entry for callers of the former split-radio factory. */
    static _AddRadio(owner, options, text?) {
        return this._AddStyled(owner, "Radio", options, text?)
    }
}

/**
 * Backward-compatibility alias — `_Dark(...)` constructs a {@link DarkGui}.
 * Declared as an (empty) subclass rather than a `_Dark := DarkGui` global
 * assignment so that merely including this file has no auto-execute side effect.
 */
class _Dark extends DarkGui {
}
