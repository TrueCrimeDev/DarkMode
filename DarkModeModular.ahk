/*
DarkModeModular.ahk — Dark mode GUI framework for AutoHotkey v2

Usage:
  #Include DarkModeModular.ahk
  myGui := DarkGui("+Resize", "My App")
  myGui.Add("Button", "+Accent", "OK")
  myGui.Add("Edit", "w300", "text")
  myGui.Show()


Public API: DarkGui, DarkTheme, DarkTitleBar, DarkMenu, DarkMenuBar, DarkScrollbar, DarkTooltip
All controls added via DarkGui.Add() are automatically dark-styled.
Use "+Accent" on buttons for blue accent color.
*/
#Requires AutoHotkey v2.1-alpha.17
#SingleInstance Force

; Win32 struct helpers (NumGet-based for +Console engine compatibility).
class _DM_NMHDR {
    static At(ptr) {
        return {
            hwndFrom: NumGet(ptr, 0, "Ptr"),
            idFrom:   NumGet(ptr, A_PtrSize, "Ptr"),
            code:     NumGet(ptr, A_PtrSize * 2, "Int")
        }
    }
}

class _DM_NMCD {
    static At(ptr) {
        static hdrSize  := A_PtrSize * 2 + 4
        static baseOff  := (hdrSize + (A_PtrSize - 1)) & ~(A_PtrSize - 1)
        static stageOff := baseOff
        static hdcOff   := baseOff + A_PtrSize
        static rcOff    := hdcOff + A_PtrSize
        static specOff  := rcOff + 16
        static stateOff := specOff + A_PtrSize
        static paramOff := (stateOff + 4 + (A_PtrSize - 1)) & ~(A_PtrSize - 1)

        return {
            hdr: _DM_NMHDR.At(ptr),
            dwDrawStage: NumGet(ptr, stageOff, "UInt"),
            hdc:         NumGet(ptr, hdcOff, "Ptr"),
            dwItemSpec:  NumGet(ptr, specOff, "Ptr"),
            uItemState:  NumGet(ptr, stateOff, "UInt"),
            lItemlParam: NumGet(ptr, paramOff, "Ptr")
        }
    }
}

/**
 * Central theme manager for dark mode colors and GDI brushes.
 * Provides color constants, brush caching, and utility functions.
 */
class DarkTheme {
    /** @type {Map} Color palette: Background, Controls, ControlsHover, ControlsActive, Font, FontDim, Accent, Border, Selection, GridLine, Header */
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
        "ScrollThumbHover", 0x787878
    )

    /** @type {Map} Cached GDI brush handles keyed by color name */
    static Brushes := Map()
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
     * Decrements reference count. Cleans up brushes and GDI+ when
     * the last {@link DarkGui} instance is destroyed.
     */
    static Release() {
        if --this._refCount <= 0 {
            this._refCount := 0
            this.Cleanup()
            _DarkSlider.Shutdown()
        }
    }

    /**
     * Gets a cached GDI brush handle for the specified color.
     * @param {String} name - Color name from Colors map
     * @returns {Ptr} GDI brush handle or 0 if not found
     */
    static GetBrush(name) => this.Brushes.Has(name) ? this.Brushes[name] : 0

    /**
     * Updates a theme color and recreates its brush.
     * @param {String} name - Color name to update
     * @param {Integer} value - New RGB color value (0xRRGGBB)
     */
    static SetColor(name, value) {
        if this.Brushes.Has(name)
            DllCall("DeleteObject", "Ptr", this.Brushes[name])
        this.Colors[name] := value
        this.Brushes[name] := DllCall("gdi32\CreateSolidBrush", "UInt", this.RGBtoBGR(value), "Ptr")
    }

    /**
     * Scales a pixel value by the system DPI factor.
     * @param {Integer} px - Pixel value at 96 DPI
     * @returns {Integer} Scaled pixel value for current DPI
     */
    static Scale(px) => Round(px * (A_ScreenDPI / 96))

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

        GetWindowLong := A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong"
        SetWindowLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"

        ; Remove WS_BORDER from style
        style := DllCall(GetWindowLong, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr")
        DllCall(SetWindowLong, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style & ~WS_BORDER)

        ; Remove WS_EX_CLIENTEDGE and WS_EX_STATICEDGE from extended style
        exStyle := DllCall(GetWindowLong, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr")
        DllCall(SetWindowLong, "Ptr", hwnd, "Int", GWL_EXSTYLE, "Ptr", exStyle & ~(WS_EX_CLIENTEDGE | WS_EX_STATICEDGE))

        ; Force redraw with new frame
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "UInt", SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER)
    }

    /**
     * Calls undocumented AllowDarkModeForWindow (uxtheme ordinal 133).
     * Must be called BEFORE SetWindowTheme for dark mode to take effect on a control.
     * @param {Ptr} hwnd - Control window handle
     */
    static AllowDarkMode(hwnd) {
        static fn := 0
        if !fn {
            uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
            fn := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 133, "Ptr")
        }
        if fn
            DllCall(fn, "Ptr", hwnd, "Int", true)
    }

    /**
     * Frees all cached GDI brush handles.
     * Called automatically by {@link DarkTheme.Release} or on application exit.
     */
    static Cleanup() {
        for name, brush in this.Brushes
            DllCall("DeleteObject", "Ptr", brush)
        this.Brushes.Clear()
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; Prototype Extensions - Scoped inside DarkPrototypes to avoid global pollution
; ═══════════════════════════════════════════════════════════════════════════════

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
 * Enables dark mode for application menus using undocumented uxtheme APIs
 * (ordinals 135 `SetPreferredAppMode` and 136 `FlushMenuThemes`).
 */
class DarkMenu {
    /**
     * Applies dark theme to all menus in the application.
     * Call once during GUI initialization; {@link DarkGui#__New} calls this automatically.
     */
    static Apply() {
        uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
        SetPreferredAppMode := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
        FlushMenuThemes := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")
        DllCall(SetPreferredAppMode, "Int", 2)
        DllCall(FlushMenuThemes)
    }
}

/**
 * Dark-themed tracking tooltip rendered via the Win32 `tooltips_class32` control.
 * A single shared instance is reused; {@link DarkTooltip.Show} replaces any visible
 * tip and schedules an auto-hide. Colors follow {@link DarkTheme.Colors}.
 */
class DarkTooltip {
    /** @type {Ptr} Current tooltip window handle (0 when hidden) */
    static hwnd := 0
    /** @type {Func} Bound auto-hide timer callback (empty when none pending) */
    static timer := ""

    /**
     * Shows a dark tooltip just below-right of the cursor.
     * @param {String} text - Tooltip text.
     * @param {Integer} [duration=2000] - Auto-hide delay in milliseconds.
     */
    static Show(text, duration := 2000) {
        static TTS_NOPREFIX := 0x02, TTS_ALWAYSTIP := 0x01
        static TTM_ADDTOOL := 0x432, TTM_SETTIPBKCOLOR := 0x413, TTM_SETTIPTEXTCOLOR := 0x414
        static TTM_TRACKACTIVATE := 0x411, TTM_TRACKPOSITION := 0x412
        static TTF_TRACK := 0x20, TTF_ABSOLUTE := 0x80

        ; Replace any tip currently on screen
        if this.hwnd {
            DllCall("DestroyWindow", "Ptr", this.hwnd)
            this.hwnd := 0
        }

        this.hwnd := DllCall("CreateWindowEx", "UInt", 0x8, "Str", "tooltips_class32", "Ptr", 0,
            "UInt", TTS_NOPREFIX | TTS_ALWAYSTIP, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr")

        SendMessage(TTM_SETTIPBKCOLOR, DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), 0, this.hwnd)
        SendMessage(TTM_SETTIPTEXTCOLOR, DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]), 0, this.hwnd)

        pt := Buffer(8)
        DllCall("GetCursorPos", "Ptr", pt)
        x := NumGet(pt, 0, "Int") + 16
        y := NumGet(pt, 4, "Int") + 16
        SendMessage(TTM_TRACKPOSITION, 0, (y << 16) | (x & 0xFFFF), this.hwnd)

        tiSize := A_PtrSize = 8 ? 72 : 48
        ti := Buffer(tiSize, 0)
        NumPut("UInt", tiSize, ti, 0)
        NumPut("UInt", TTF_TRACK | TTF_ABSOLUTE, ti, 4)
        NumPut("Ptr", StrPtr(text), ti, A_PtrSize = 8 ? 48 : 36)

        SendMessage(TTM_ADDTOOL, 0, ti.Ptr, this.hwnd)
        SendMessage(TTM_TRACKACTIVATE, 1, ti.Ptr, this.hwnd)

        ; Bound method (not a void fat-arrow) so the timer body stays value-returning
        if this.timer
            SetTimer(this.timer, 0)
        this.timer := ObjBindMethod(this, "Hide")
        SetTimer(this.timer, -duration)
    }

    /** Hides and destroys the current tooltip, if any. */
    static Hide() {
        if this.hwnd {
            DllCall("DestroyWindow", "Ptr", this.hwnd)
            this.hwnd := 0
        }
        if this.timer {
            SetTimer(this.timer, 0)
            this.timer := ""
        }
    }
}

/**
 * Utility class for window subclassing. Provides common pattern for installing
 * and uninstalling window procedure callbacks.
 */
class Subclass {
    static SetWindowLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"

    /**
     * Installs a window procedure callback on a control.
     * @param {Ptr} hwnd - Window handle to subclass
     * @param {Func} procMethod - Bound method to use as window procedure
     * @param {Map} callbacks - Map to store callback handles
     * @param {Map} oldProcs - Map to store original window procedures
     * @returns {Boolean} true if installed, false if already subclassed
     */
    static Install(hwnd, procMethod, callbacks, oldProcs) {
        if oldProcs.Has(hwnd)
            return false
        callback := CallbackCreate(procMethod, , 4)
        callbacks[hwnd] := callback
        oldProcs[hwnd] := DllCall(this.SetWindowLong, "Ptr", hwnd, "Int", -4, "Ptr", callback, "Ptr")
        return true
    }

    /**
     * Removes subclass and restores original window procedure.
     * @param {Ptr} hwnd - Window handle to unsubclass
     * @param {Map} callbacks - Map containing callback handles
     * @param {Map} oldProcs - Map containing original window procedures
     */
    static Uninstall(hwnd, callbacks, oldProcs) {
        if !oldProcs.Has(hwnd)
            return
        DllCall(this.SetWindowLong, "Ptr", hwnd, "Int", -4, "Ptr", oldProcs[hwnd], "Ptr")
        CallbackFree(callbacks[hwnd])
        callbacks.Delete(hwnd)
        oldProcs.Delete(hwnd)
    }

    /**
     * Calls the original window procedure.
     * @param {Ptr} oldProc - Original window procedure
     * @param {Ptr} hwnd - Window handle
     * @param {Integer} msg - Message
     * @param {Ptr} wParam - wParam
     * @param {Ptr} lParam - lParam
     * @returns {Ptr} Result from CallWindowProc
     */
    static CallOriginal(oldProc, hwnd, msg, wParam, lParam) {
        return DllCall("CallWindowProc", "Ptr", oldProc, "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
}

/**
 * Custom dark scrollbar control for ListView. Creates an owner-draw scrollbar
 * that syncs with ListView scroll position via a 100ms timer.
 *
 * Rendering uses GDI `FillRect` with rounded thumb, hover/drag states,
 * and page-up/page-down on track clicks.
 */
class DarkScrollbar {
    /** @type {Map} Active instances keyed by scrollbar hwnd */
    static Instances := Map()
    /** @type {Map} Window procedure callbacks keyed by hwnd */
    static Callbacks := Map()
    /** @type {Map} Original window procedures for restoration */
    static OldProcs := Map()
    /** @type {Integer} Scrollbar width in DPI-scaled pixels */
    static ScrollbarWidth := DarkTheme.Scale(14)

    /**
     * Creates a dark scrollbar alongside a target ListView.
     *
     * @param {DarkGui} gui - Parent GUI instance.
     * @param {Gui.ListView} targetCtrl - ListView to sync scroll position with.
     * @param {Integer} x - X position.
     * @param {Integer} y - Y position.
     * @param {Integer} h - Height.
     */
    __New(gui, targetCtrl, x, y, h) {
        this.gui := gui
        this.target := targetCtrl
        this.x := x
        this.y := y
        this.h := h
        this.w := DarkScrollbar.ScrollbarWidth

        this.trackColor := DarkTheme.Colors["Header"]
        this.thumbColor := DarkTheme.Colors["ScrollThumb"]
        this.thumbHoverColor := DarkTheme.Colors["ScrollThumbHover"]

        this.isDragging := false
        this.dragStartY := 0
        this.dragStartPos := 0
        this.isHovering := false

        ; Create the scrollbar as a Text control (we'll custom draw it)
        this.ctrl := gui.Add("Text", "x" x " y" y " w" this.w " h" h " +0x4000000")  ; WS_CLIPSIBLINGS
        this.ctrl.Opt("+Background" Format("{:X}", this.trackColor))

        ; Store instance reference
        DarkScrollbar.Instances[this.ctrl.Hwnd] := this

        ; Subclass for custom drawing and mouse handling
        this.SubclassScrollbar()

        ; Set up scroll sync timer
        this.syncTimer := ObjBindMethod(this, "SyncFromTarget")
        SetTimer(this.syncTimer, 100)
    }

    SubclassScrollbar() {
        Subclass.Install(this.ctrl.Hwnd, ObjBindMethod(this, "ScrollbarProc"), DarkScrollbar.Callbacks, DarkScrollbar.OldProcs)
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
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
            return 0
        }

        if msg = WM_CAPTURECHANGED {
            this.isDragging := false
            return 0
        }

        return Subclass.CallOriginal(DarkScrollbar.OldProcs[this.ctrl.Hwnd], hwnd, msg, wParam, lParam)
    }

    GetScrollInfo() {
        static LVM_GETITEMCOUNT := 0x1004
        static LVM_GETCOUNTPERPAGE := 0x1028
        static LVM_GETTOPINDEX := 0x1027

        ; Get ListView scroll info from item counts
        itemCount := SendMessage(LVM_GETITEMCOUNT, 0, 0, this.target.Hwnd)
        visibleCount := SendMessage(LVM_GETCOUNTPERPAGE, 0, 0, this.target.Hwnd)
        topIndex := SendMessage(LVM_GETTOPINDEX, 0, 0, this.target.Hwnd)

        return {
            min: 0,
            max: Max(0, itemCount - 1),
            page: visibleCount,
            pos: topIndex
        }
    }

    GetThumbRect() {
        info := this.GetScrollInfo()
        range := info.max - info.min + 1

        if range <= info.page || range <= 0
            return {top: 0, bottom: this.h, height: this.h}

        thumbHeight := Max(DarkTheme.Scale(30), (info.page * this.h) // range)
        trackSpace := this.h - thumbHeight

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
        static PAINTSTRUCT_SIZE := A_PtrSize = 8 ? 72 : 64
        ps := Buffer(PAINTSTRUCT_SIZE, 0)
        hdc := DllCall("BeginPaint", "Ptr", this.ctrl.Hwnd, "Ptr", ps, "Ptr")

        ; Get client rect
        rc := Buffer(16)
        DllCall("GetClientRect", "Ptr", this.ctrl.Hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int")
        h := NumGet(rc, 12, "Int")

        ; Draw track
        trackBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(this.trackColor), "Ptr")
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", trackBrush)
        DllCall("DeleteObject", "Ptr", trackBrush)

        ; Draw thumb
        thumb := this.GetThumbRect()
        thumbColor := this.isHovering || this.isDragging ? this.thumbHoverColor : this.thumbColor

        thumbBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(thumbColor), "Ptr")
        rcThumb := Buffer(16)
        pad := DarkTheme.Scale(2)
        NumPut("Int", pad, "Int", thumb.top + pad, "Int", w - pad, "Int", thumb.bottom - pad, rcThumb)
        DllCall("FillRect", "Ptr", hdc, "Ptr", rcThumb, "Ptr", thumbBrush)
        DllCall("DeleteObject", "Ptr", thumbBrush)

        DllCall("EndPaint", "Ptr", this.ctrl.Hwnd, "Ptr", ps)
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
            DllCall("SetCapture", "Ptr", this.ctrl.Hwnd)
        }

        DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1)

        ; Track mouse for hover effects
        tme := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut("UInt", A_PtrSize = 8 ? 24 : 16, tme, 0)
        NumPut("UInt", 2, tme, 4)  ; TME_LEAVE
        NumPut("Ptr", this.ctrl.Hwnd, tme, 8)
        DllCall("TrackMouseEvent", "Ptr", tme)
    }

    OnMouseUp() {
        if this.isDragging {
            this.isDragging := false
            DllCall("ReleaseCapture")
            DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1)
        }
    }

    OnMouseMove(lParam) {
        mouseY := (lParam >> 16) & 0xFFFF
        if mouseY > 0x7FFF
            mouseY -= 0x10000

        ; Track mouse for hover effects
        if !this.isHovering {
            this.isHovering := true
            tme := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            NumPut("UInt", A_PtrSize = 8 ? 24 : 16, tme, 0)
            NumPut("UInt", 2, tme, 4)  ; TME_LEAVE
            NumPut("Ptr", this.ctrl.Hwnd, tme, 8)
            DllCall("TrackMouseEvent", "Ptr", tme)
            DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1)
        }

        if this.isDragging {
            info := this.GetScrollInfo()
            deltaY := mouseY - this.dragStartY

            thumb := this.GetThumbRect()
            trackSpace := this.h - thumb.height

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
        static LVM_ENSUREVISIBLE := 0x1013
        static LVM_GETITEMCOUNT := 0x1004

        ; Clamp position to valid range
        itemCount := SendMessage(LVM_GETITEMCOUNT, 0, 0, this.target.Hwnd)
        pos := Max(0, Min(pos, itemCount - 1))

        ; Scroll to make the item at position visible at the top
        SendMessage(LVM_ENSUREVISIBLE, pos, 0, this.target.Hwnd)

        DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1)
    }

    SyncFromTarget() {
        ; Update our display to match target's scroll position
        if !this.isDragging
            DllCall("InvalidateRect", "Ptr", this.ctrl.Hwnd, "Ptr", 0, "Int", 1)
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
     * Stops the sync timer and frees the subclass callback.
     */
    Destroy() {
        if this.syncTimer
            SetTimer(this.syncTimer, 0)
        Subclass.Uninstall(this.ctrl.Hwnd, DarkScrollbar.Callbacks, DarkScrollbar.OldProcs)
        DarkScrollbar.Instances.Delete(this.ctrl.Hwnd)
    }
}

/**
 * Dark-themed ListView with custom-drawn header, items, and arrow-less scrollbar.
 * Uses NM_CUSTOMDRAW for item/header colors and hides scrollbar arrows.
 */
class _DarkListView extends Gui.ListView {
    /** @type {Map} Window procedure callbacks keyed by hwnd */
    static Callbacks := Map()
    /** @type {Map} Original window procedures for restoration */
    static OldProcs := Map()
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
        Subclass.Install(hwnd, ObjBindMethod(this, "ListViewProc", hwnd), this.Callbacks, this.OldProcs)
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
        Subclass.Uninstall(hwnd, this.Callbacks, this.OldProcs)
        this.HeaderHandles.Delete(hwnd)
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
        sbi := Buffer(60, 0)
        NumPut("UInt", 60, sbi, 0)
        if !DllCall("GetScrollBarInfo", "Ptr", hwnd, "Int", OBJID_VSCROLL, "Ptr", sbi)
            return false
        if NumGet(sbi, 36, "UInt") & 0x8000
            return false

        sbL := NumGet(sbi, 4, "Int"), sbT := NumGet(sbi, 8, "Int")
        sbR := NumGet(sbi, 12, "Int"), sbB := NumGet(sbi, 16, "Int")
        arrowH := DllCall("GetSystemMetrics", "Int", 20)

        rcWin := Buffer(16)
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
        winL := NumGet(rcWin, 0, "Int"), winT := NumGet(rcWin, 4, "Int")
        w := NumGet(rcWin, 8, "Int") - winL, h := NumGet(rcWin, 12, "Int") - winT

        ; Window-relative arrow coords
        aL := sbL - winL, aR := sbR - winL
        aTopT := sbT - winT, aTopB := sbT + arrowH - winT
        aBotT := sbB - arrowH - winT, aBotB := sbB - winT

        ; Full window region minus arrow rects
        fullRgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr")
        topRgn := DllCall("CreateRectRgn", "Int", aL, "Int", aTopT, "Int", aR, "Int", aTopB, "Ptr")
        DllCall("CombineRgn", "Ptr", fullRgn, "Ptr", fullRgn, "Ptr", topRgn, "Int", 4)  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", topRgn)
        botRgn := DllCall("CreateRectRgn", "Int", aL, "Int", aBotT, "Int", aR, "Int", aBotB, "Ptr")
        DllCall("CombineRgn", "Ptr", fullRgn, "Ptr", fullRgn, "Ptr", botRgn, "Int", 4)  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", botRgn)

        ; System takes ownership of fullRgn - don't delete it
        DllCall("SetWindowRgn", "Ptr", hwnd, "Ptr", fullRgn, "Int", 0)
        return true
    }

    /**
     * Removes the arrow clip region, restoring full window painting.
     *
     * @param {Ptr} hwnd - Window handle.
     */
    static ClearArrowClipRegion(hwnd) {
        DllCall("SetWindowRgn", "Ptr", hwnd, "Ptr", 0, "Int", 0)
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
        sbi := Buffer(60, 0)
        NumPut("UInt", 60, sbi, 0)
        if !DllCall("GetScrollBarInfo", "Ptr", hwnd, "Int", OBJID_VSCROLL, "Ptr", sbi)
            return 0
        if NumGet(sbi, 36, "UInt") & 0x8000  ; STATE_SYSTEM_INVISIBLE
            return 0

        ; Scrollbar rect in screen coords
        sbL := NumGet(sbi, 4, "Int"), sbT := NumGet(sbi, 8, "Int")
        sbR := NumGet(sbi, 12, "Int"), sbB := NumGet(sbi, 16, "Int")
        arrowH := DllCall("GetSystemMetrics", "Int", 20)  ; SM_CYVSCROLL

        ; Build base region from wParam
        if wParam = 1 {
            rcWin := Buffer(16)
            DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
            hrgn := DllCall("CreateRectRgn",
                "Int", NumGet(rcWin, 0, "Int"), "Int", NumGet(rcWin, 4, "Int"),
                "Int", NumGet(rcWin, 8, "Int"), "Int", NumGet(rcWin, 12, "Int"), "Ptr")
        } else {
            ; Copy - must not modify the original region
            hrgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
            DllCall("CombineRgn", "Ptr", hrgn, "Ptr", wParam, "Ptr", hrgn, "Int", 5)  ; RGN_COPY
        }

        ; Subtract top arrow region (screen coords)
        topRgn := DllCall("CreateRectRgn", "Int", sbL, "Int", sbT, "Int", sbR, "Int", sbT + arrowH, "Ptr")
        DllCall("CombineRgn", "Ptr", hrgn, "Ptr", hrgn, "Ptr", topRgn, "Int", 4)  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", topRgn)

        ; Subtract bottom arrow region (screen coords)
        botRgn := DllCall("CreateRectRgn", "Int", sbL, "Int", sbB - arrowH, "Int", sbR, "Int", sbB, "Ptr")
        DllCall("CombineRgn", "Ptr", hrgn, "Ptr", hrgn, "Ptr", botRgn, "Int", 4)  ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", botRgn)

        return hrgn
    }

    /**
     * Paints over scrollbar arrow areas with track color.
     * Used as fallback for non-WM_NCPAINT repaints (hover effects, scroll events).
     * @param {Ptr} hwnd - Window handle
     */
    static HideScrollbarArrows(hwnd, headerHwnd := 0) {
        static OBJID_VSCROLL := -5
        sbi := Buffer(60, 0)
        NumPut("UInt", 60, sbi, 0)
        if !DllCall("GetScrollBarInfo", "Ptr", hwnd, "Int", OBJID_VSCROLL, "Ptr", sbi)
            return
        if NumGet(sbi, 36, "UInt") & 0x8000
            return

        sbLeft := NumGet(sbi, 4, "Int"), sbTop := NumGet(sbi, 8, "Int")
        sbRight := NumGet(sbi, 12, "Int"), sbBottom := NumGet(sbi, 16, "Int")
        arrowHeight := DllCall("GetSystemMetrics", "Int", 20)

        rcWin := Buffer(16)
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rcWin)
        winLeft := NumGet(rcWin, 0, "Int"), winTop := NumGet(rcWin, 4, "Int")

        ; Convert to window-relative coords
        sbLeftW := sbLeft - winLeft, sbTopW := sbTop - winTop
        sbRightW := sbRight - winLeft, sbBottomW := sbBottom - winTop

        hdc := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
        if !hdc
            return

        trackBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["ScrollTrack"]), "Ptr")
        rc := Buffer(16)

        NumPut("Int", sbLeftW, "Int", sbTopW, "Int", sbRightW, "Int", sbTopW + arrowHeight, rc)
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", trackBrush)

        NumPut("Int", sbLeftW, "Int", sbBottomW - arrowHeight, "Int", sbRightW, "Int", sbBottomW, rc)
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", trackBrush)

        DllCall("DeleteObject", "Ptr", trackBrush)
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)
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
            return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)

        ; Get header handle for proper alignment
        headerHwnd := this.HeaderHandles.Has(hwnd) ? this.HeaderHandles[hwnd] : 0

        ; Handle NC paint - clip arrow regions BEFORE default paint
        if msg = WM_NCPAINT {
            clippedRgn := _DarkListView.ClipArrowRegion(hwnd, wParam)
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, clippedRgn ? clippedRgn : wParam, lParam)
            ; Fill excluded arrow areas with track color
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            if clippedRgn
                DllCall("DeleteObject", "Ptr", clippedRgn)
            return result
        }

        ; Handle scrollbar mouse interactions - let default handle, then hide arrows
        if msg = WM_NCMOUSEMOVE {
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)

            ; Check if over scrollbar - start continuous redraw timer
            if wParam = HTVSCROLL || wParam = HTHSCROLL {
                ; Start high-frequency timer if not already running
                if !this.HoverTimers.Has(hwnd) {
                    timerFn := _DarkListView.CreateArrowHideTimerFunc(hwnd, headerHwnd)
                    this.HoverTimerFuncs[hwnd] := timerFn
                    this.HoverTimers[hwnd] := true
                    SetTimer(timerFn, 16)  ; ~60fps to cover scrollbar arrow repaints
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
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
            _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        if msg = WM_NCLBUTTONUP {
            _DarkListView.SetArrowClipRegion(hwnd)
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
            _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        if msg = WM_NCMOUSELEAVE {
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
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
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
            if isDragging
                _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        ; Handle mouse move during scrollbar drag - clip arrows via SetWindowRgn
        if msg = WM_MOUSEMOVE {
            if DllCall("GetCapture", "Ptr") = hwnd {
                _DarkListView.SetArrowClipRegion(hwnd)
                result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
                _DarkListView.ClearArrowClipRegion(hwnd)
                _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
                return result
            }
            return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
        }

        ; Handle timer messages (Windows uses timers for scroll repeat)
        if msg = WM_TIMER {
            isDragging := DllCall("GetCapture", "Ptr") = hwnd
            if isDragging
                _DarkListView.SetArrowClipRegion(hwnd)
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
            if isDragging
                _DarkListView.ClearArrowClipRegion(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        ; Handle capture change - drag ended
        if msg = WM_CAPTURECHANGED {
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
            this.StopHoverTimer(hwnd)
            _DarkListView.HideScrollbarArrows(hwnd, headerHwnd)
            return result
        }

        return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
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

            if (_DM_NMHDR.At(lParam).code != NM_CUSTOMDRAW)
                return

            nmcd := _DM_NMCD.At(lParam)

            ; Handle header custom draw
            if (nmcd.hdr.hwndFrom = lv.Header) {
                switch nmcd.dwDrawStage {
                    case CDDS_PREPAINT:
                        return CDRF_NOTIFYITEMDRAW
                    case CDDS_ITEMPREPAINT:
                        hdc := nmcd.hdc
                        itemIndex := nmcd.dwItemSpec

                        rc := Buffer(16, 0)
                        SendMessage(HDM_GETITEMRECT, itemIndex, rc.Ptr, lv.Header)

                        hBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]), "Ptr")
                        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", hBrush)
                        DllCall("DeleteObject", "Ptr", hBrush)

                        textBuf := Buffer(256, 0)
                        hdItem := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
                        NumPut("UInt", HDI_TEXT, hdItem, 0)
                        NumPut("Ptr", textBuf.Ptr, hdItem, 8)
                        NumPut("Int", 128, hdItem, A_PtrSize = 8 ? 24 : 16)
                        SendMessage(HDM_GETITEM, itemIndex, hdItem.Ptr, lv.Header)

                        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                        DllCall("SetBkMode", "Ptr", hdc, "Int", 1)

                        left := NumGet(rc, 0, "Int") + DarkTheme.Scale(8)
                        top := NumGet(rc, 4, "Int")
                        right := NumGet(rc, 8, "Int") - DarkTheme.Scale(4)
                        bottom := NumGet(rc, 12, "Int")
                        rcText := Buffer(16, 0)
                        NumPut("Int", left, "Int", top, "Int", right, "Int", bottom, rcText)

                        DllCall("DrawTextW", "Ptr", hdc, "Ptr", textBuf.Ptr, "Int", -1, "Ptr", rcText, "UInt", DT_VCENTER | DT_SINGLELINE)

                        return CDRF_SKIPDEFAULT
                }
                return CDRF_DODEFAULT
            }

            ; Handle ListView item custom draw
            if (nmcd.hdr.hwndFrom = lv.Hwnd) {
                switch nmcd.dwDrawStage {
                    case CDDS_PREPAINT:
                        return CDRF_NOTIFYITEMDRAW
                    case CDDS_ITEMPREPAINT:
                        isSelected := nmcd.uItemState & CDIS_SELECTED

                        if isSelected {
                            ; Keep selection blue even when ListView loses focus
                            DllCall("SetTextColor", "Ptr", nmcd.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                            DllCall("SetBkColor", "Ptr", nmcd.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Selection"]))
                        } else {
                            DllCall("SetTextColor", "Ptr", nmcd.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
                            DllCall("SetBkColor", "Ptr", nmcd.hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]))
                        }
                        return CDRF_NEWFONT
                }
                return CDRF_DODEFAULT
            }

            return CDRF_DODEFAULT
        })

        lv.Opt("+LV" LVS_EX_DOUBLEBUFFER)
        SendMessage(WM_CHANGEUISTATE, (UIS_SET << 8) | UISF_HIDEFOCUS, 0, lv)

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
        static ILC_COLOR32 := 0x20
        static BP_CHECKBOX := 3
        static CBS_UNCHECKEDNORMAL := 1
        static CBS_CHECKEDNORMAL := 5

        ; Get the theme handle from the dark-mode-enabled ListView
        hTheme := DllCall("uxtheme\OpenThemeData", "Ptr", lv.Hwnd, "Str", "BUTTON", "Ptr")
        if !hTheme
            return

        ; Query the theme for the actual checkbox glyph size
        szBuf := Buffer(8, 0)
        DllCall("uxtheme\GetThemePartSize", "Ptr", hTheme, "Ptr", 0,
            "Int", BP_CHECKBOX, "Int", CBS_CHECKEDNORMAL, "Ptr", 0, "Int", 1, "Ptr", szBuf)
        glyphW := NumGet(szBuf, 0, "Int")
        glyphH := NumGet(szBuf, 4, "Int")

        ; Use glyph size with padding for the ImageList
        cxImg := glyphW + 4
        cyImg := glyphH + 4

        hIml := DllCall("comctl32\ImageList_Create", "Int", cxImg, "Int", cyImg, "UInt", ILC_COLOR32, "Int", 2, "Int", 1, "Ptr")

        ; Standard 2-image state list: index 0 = unchecked, index 1 = checked.
        ; The LVITEM state-image value is 1-based (1 -> unchecked, 2 -> checked),
        ; which is what LVS_EX_CHECKBOXES, GetNext("C") and click-toggle expect.
        ; A 3rd "blank" image here shifts every index and breaks all three.
        states := [CBS_UNCHECKEDNORMAL, CBS_CHECKEDNORMAL]

        for stateVal in states {
            hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
            hdc := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
            hBmp := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", cxImg, "Int", cyImg, "Ptr")
            hOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hBmp, "Ptr")
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

            ; Fill background with ListView body color
            rc := Buffer(16)
            NumPut("Int", 0, "Int", 0, "Int", cxImg, "Int", cyImg, rc)
            bgBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), "Ptr")
            DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", bgBrush)
            DllCall("DeleteObject", "Ptr", bgBrush)

            ; Draw the native themed checkbox glyph (skip for state 0 = blank)
            if stateVal > 0 {
                glyphRC := Buffer(16)
                glyphX := (cxImg - glyphW) // 2
                glyphY := (cyImg - glyphH) // 2
                NumPut("Int", glyphX, "Int", glyphY, "Int", glyphX + glyphW, "Int", glyphY + glyphH, glyphRC)
                DllCall("uxtheme\DrawThemeBackground", "Ptr", hTheme, "Ptr", hdc,
                    "Int", BP_CHECKBOX, "Int", stateVal, "Ptr", glyphRC, "Ptr", 0)
            }

            DllCall("SelectObject", "Ptr", hdc, "Ptr", hOld)
            DllCall("comctl32\ImageList_Add", "Ptr", hIml, "Ptr", hBmp, "Ptr", 0)
            DllCall("DeleteObject", "Ptr", hBmp)
            DllCall("DeleteDC", "Ptr", hdc)
        }

        DllCall("uxtheme\CloseThemeData", "Ptr", hTheme)
        SendMessage(LVM_SETIMAGELIST, LVSIL_STATE, hIml, lv)

        ; Subclass the ListView to intercept item insertions and ensure
        ; new rows always get state 1 (unchecked visible box) instead of state 0 (blank)
        this.InstallCheckboxSubclass(lv)
    }

    static _CheckboxSubclassCallbacks := Map()

    static InstallCheckboxSubclass(lv) {
        hwnd := lv.Hwnd
        cb := CallbackCreate(ObjBindMethod(this, "CheckboxSubclassProc"), , 6)
        this._CheckboxSubclassCallbacks[hwnd] := cb
        DllCall("SetWindowSubclass", "Ptr", hwnd, "Ptr", cb, "Ptr", hwnd, "Ptr", 0)

        ; Fix any existing rows with state 0
        static LVM_GETITEMCOUNT := 0x1004
        static LVM_SETITEMSTATE := 0x102B
        static LVIS_STATEIMAGEMASK := 0xF000

        rowCount := SendMessage(LVM_GETITEMCOUNT, 0, 0, lv)
        loop rowCount {
            idx := A_Index - 1
            curState := SendMessage(0x102C, idx, LVIS_STATEIMAGEMASK, lv)  ; LVM_GETITEMSTATE
            if (curState & 0xF000) = 0 {
                ; LVITEM: state at offset 12, stateMask at offset 16.
                lvItem := Buffer(A_PtrSize = 8 ? 88 : 60, 0)
                NumPut("UInt", 0x1000, lvItem, 12)               ; state: stateImage 1 (unchecked)
                NumPut("UInt", LVIS_STATEIMAGEMASK, lvItem, 16)  ; stateMask
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

        ; Intercept item insertion — if state image is 0 (blank), set to 1 (unchecked)
        if msg = LVM_INSERTITEMA || msg = LVM_INSERTITEMW {
            if lParam {
                ; LVITEM: mask @0, state @12, stateMask @16.
                state := NumGet(lParam, 12, "UInt")
                stateImg := (state & 0xF000) >> 12
                if stateImg = 0 {
                    ; Force unchecked (stateImage 1) and flag LVIF_STATE so the
                    ; control honors the state fields on insertion.
                    NumPut("UInt", NumGet(lParam, 0, "UInt") | 0x8, lParam, 0)               ; LVIF_STATE
                    NumPut("UInt", (state & ~0xF000) | 0x1000, lParam, 12)                   ; stateImage 1
                    NumPut("UInt", NumGet(lParam, 16, "UInt") | LVIS_STATEIMAGEMASK, lParam, 16)
                }
            }
        }

        if msg = WM_DESTROY {
            if _DarkListView._CheckboxSubclassCallbacks.Has(hwnd) {
                DllCall("RemoveWindowSubclass", "Ptr", hwnd, "Ptr", _DarkListView._CheckboxSubclassCallbacks[hwnd], "Ptr", hwnd)
                CallbackFree(_DarkListView._CheckboxSubclassCallbacks[hwnd])
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

    /** @type {Map} Button control instances keyed by hwnd */
    static Instances := Map()
    /** @type {Map} Window procedure callbacks */
    static Callbacks := Map()
    /** @type {Map} Original window procedures for restoration */
    static OldProcs := Map()
    /** @type {Map} Cached button text strings */
    static ButtonTexts := Map()
    /** @type {Map} Mouse hover state flags */
    static HoverStates := Map()
    /** @type {Map} Button rendering mode: "default", "accent", "icon", "split", "command", "toggle", or "flat" */
    static ButtonModes := Map()
    /** @type {Map} Mouse pressed state flags */
    static PressedStates := Map()
    /** @type {Map} HICON per hwnd for icon/command-link buttons (0 if none) */
    static Icons := Map()
    /** @type {Map} Whether the icon was loaded by us and needs DestroyIcon on Remove */
    static IconOwned := Map()
    /** @type {Map} Icon alignment: "left" | "right" | "top" | "center" */
    static IconAligns := Map()
    /** @type {Map} Menu object shown when split-button arrow is clicked */
    static Menus := Map()
    /** @type {Map} Callback invoked when split-button arrow is clicked (alternative to Menus) */
    static OnDropdownCbs := Map()
    /** @type {Map} Description text for command-link buttons */
    static Descriptions := Map()
    /** @type {Map} Latched on/off state for toggle buttons */
    static ToggleStates := Map()
    /** @type {Map} True when mouse is over the dropdown-arrow region of a split button */
    static HoverArrow := Map()
    /** @type {Map} True while the button holds keyboard focus (drives the focus ring) */
    static FocusStates := Map()

    /**
     * Applies owner-draw dark mode to button.
     * @param {Gui.Button} btn - Button control instance
     * @param {String} mode - "default" for dark grey, "accent" for blue highlight
     */
    static ApplyDarkMode(btn, mode := "default") {
        hwnd := btn.Hwnd
        ; Idempotent: factories may go gui.Add → DarkGui.Add → ApplyDarkMode("default")
        ; then re-call ApplyDarkMode("icon"|"split"|...). Only install the subclass once.
        if !this.OldProcs.Has(hwnd) {
            this.ButtonTexts[hwnd] := btn.Text
            this.HoverStates[hwnd] := false
            this.PressedStates[hwnd] := false
            this.FocusStates[hwnd] := false
            this.Instances[hwnd] := btn
            Subclass.Install(hwnd, ObjBindMethod(this, "ButtonProc", hwnd), this.Callbacks, this.OldProcs)
        }
        this.ButtonModes[hwnd] := mode
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    }

    /**
     * Removes subclass and frees resources for a button.
     * @param {Ptr} hwnd - Button window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this.Callbacks, this.OldProcs)
        if this.Icons.Has(hwnd) && this.IconOwned.Get(hwnd, false) && this.Icons[hwnd]
            DllCall("DestroyIcon", "Ptr", this.Icons[hwnd])
        for prop in [this.ButtonTexts, this.HoverStates, this.PressedStates, this.Instances, this.ButtonModes,
                     this.Icons, this.IconOwned, this.IconAligns, this.Menus, this.OnDropdownCbs,
                     this.Descriptions, this.ToggleStates, this.HoverArrow, this.FocusStates, this.IdleFills]
            if prop.Has(hwnd)
                prop.Delete(hwnd)
    }

    /**
     * Updates a dark button's label and repaints it.
     *
     * The owner-draw paint reads from {@link _DarkButton.ButtonTexts}, so assigning
     * the live control's `.Text` alone won't change the visible label — call this.
     * No-op if the button isn't dark-styled.
     *
     * @param {Ptr} hwnd - Button window handle.
     * @param {String} text - New button text.
     */
    static SetText(hwnd, text) {
        if this.ButtonTexts.Has(hwnd) {
            this.ButtonTexts[hwnd] := text
            if this.Instances.Has(hwnd)
                this.Instances[hwnd].Text := text
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
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
        hicon := this._ResolveIcon(icon, &owned, DarkTheme.Scale(16))
        this.Icons[btn.Hwnd] := hicon
        this.IconOwned[btn.Hwnd] := owned
        this.IconAligns[btn.Hwnd] := align
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
        if menuOrCallback is Menu
            this.Menus[btn.Hwnd] := menuOrCallback
        else if HasMethod(menuOrCallback)
            this.OnDropdownCbs[btn.Hwnd] := menuOrCallback
        else
            throw TypeError("AddSplit: menuOrCallback must be a Menu or callable", -1)
        this.HoverArrow[btn.Hwnd] := false
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
        hicon := this._ResolveIcon(icon, &owned, DarkTheme.Scale(20))
        this.Icons[btn.Hwnd] := hicon
        this.IconOwned[btn.Hwnd] := owned
        this.Descriptions[btn.Hwnd] := description
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
        this.ToggleStates[btn.Hwnd] := !!initialState
        btn.DefineProp("IsToggled", {
            Get: (b) => _DarkButton.ToggleStates.Get(b.Hwnd, false),
            Set: (b, v) => (_DarkButton.ToggleStates[b.Hwnd] := !!v,
                            DllCall("InvalidateRect", "Ptr", b.Hwnd, "Ptr", 0, "Int", 1), 0)
        })
        this._RegisterWithGui(gui, btn.Hwnd)
        this.ApplyDarkMode(btn, "toggle")
        return btn
    }

    /** @type {Map} Optional per-button idle fill color for flat buttons that sit
     * on a surface other than the Gui background (e.g. embedded in an Edit). */
    static IdleFills := Map()

    /**
     * Adds a flat (borderless) button: no fill at idle, hover/press only.
     * @param {Gui} gui - Parent Gui
     * @param {String} options - Standard Gui.Add options
     * @param {String} text - Button text
     * @param {Integer} [idleFill] - Idle fill color (0xRRGGBB); defaults to the
     *   Gui background. Pass DarkTheme.Colors["Controls"] when the button is
     *   overlaid on an Edit so it blends into the field.
     * @returns {Gui.Button}
     */
    static AddFlat(gui, options, text, idleFill := -1) {
        btn := gui.Add("Button", options, text)
        this._RegisterWithGui(gui, btn.Hwnd)
        if idleFill != -1
            this.IdleFills[btn.Hwnd] := idleFill
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
            idx := Integer(parts.Has(2) ? parts[2] : 0)
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

        if msg = WM_MOUSEMOVE {
            ; Sign-extend the LOWORD/HIWORD of lParam to handle negative coords during capture
            mx := lParam & 0xFFFF
            if mx & 0x8000
                mx -= 0x10000
            inArrow := this._IsSplitButton(targetHwnd) && this._PointInArrow(targetHwnd, mx)
            if this.HoverArrow.Has(targetHwnd) && this.HoverArrow[targetHwnd] != inArrow {
                this.HoverArrow[targetHwnd] := inArrow
                DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
            }
            if !this.HoverStates[targetHwnd] {
                this.HoverStates[targetHwnd] := true
                static TME_LEAVE := 0x2
                tme := Buffer(24, 0)
                NumPut("UInt", 24, tme, 0)
                NumPut("UInt", TME_LEAVE, tme, 4)
                NumPut("Ptr", targetHwnd, tme, 8)
                DllCall("TrackMouseEvent", "Ptr", tme)
                DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
            }
            return 0
        }

        if msg = WM_MOUSELEAVE {
            this.HoverStates[targetHwnd] := false
            if this.HoverArrow.Has(targetHwnd)
                this.HoverArrow[targetHwnd] := false
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
            return 0
        }

        if msg = WM_LBUTTONDOWN {
            this.PressedStates[targetHwnd] := true
            DllCall("SetCapture", "Ptr", targetHwnd)
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
            return 0
        }

        if msg = WM_LBUTTONUP {
            wasPressed := this.PressedStates[targetHwnd]
            this.PressedStates[targetHwnd] := false
            DllCall("ReleaseCapture")
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
            if wasPressed {
                rc := Buffer(16)
                DllCall("GetClientRect", "Ptr", targetHwnd, "Ptr", rc)
                pt := Buffer(8)
                DllCall("GetCursorPos", "Ptr", pt)
                DllCall("ScreenToClient", "Ptr", targetHwnd, "Ptr", pt)
                x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
                w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")
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
            this.FocusStates[targetHwnd] := (msg = WM_SETFOCUS)
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
            return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
        }

        if msg = WM_KEYDOWN {
            ; Space presses in (visual only); fires on key-up like a real button.
            if wParam = VK_SPACE {
                if !this.PressedStates[targetHwnd] {
                    this.PressedStates[targetHwnd] := true
                    DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
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

        if msg = WM_KEYUP && wParam = VK_SPACE && this.PressedStates[targetHwnd] {
            this.PressedStates[targetHwnd] := false
            DllCall("InvalidateRect", "Ptr", targetHwnd, "Ptr", 0, "Int", 1)
            this._FireClick(targetHwnd)
            return 0
        }

        ; Mnemonic (Alt+letter) and programmatic clicks arrive as BM_CLICK;
        ; route them through the same path so toggle state stays consistent.
        if msg = BM_CLICK {
            this._FireClick(targetHwnd)
            return 0
        }

        return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
    }

    /** Flips toggle state when applicable, then notifies the parent with BN_CLICKED
     *  so the Gui's normal Click event fires. Shared by mouse, keyboard, and mnemonic. */
    static _FireClick(hwnd) {
        if this.ButtonModes.Get(hwnd, "") = "toggle"
            this.ToggleStates[hwnd] := !this.ToggleStates.Get(hwnd, false)
        parent := DllCall("GetParent", "Ptr", hwnd, "Ptr")
        ctrlId := DllCall("GetDlgCtrlID", "Ptr", hwnd, "Int")
        static BN_CLICKED := 0, WM_COMMAND := 0x0111
        DllCall("SendMessage", "Ptr", parent, "UInt", WM_COMMAND, "Ptr", (BN_CLICKED << 16) | ctrlId, "Ptr", hwnd)
    }

    /** True when this button is registered as a split (dropdown) button. */
    static _IsSplitButton(hwnd) {
        return this.ButtonModes.Get(hwnd, "") = "split"
    }

    /** True when client-x falls inside the dropdown-arrow region. */
    static _PointInArrow(hwnd, clientX) {
        rc := Buffer(16)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int")
        arrowW := DarkTheme.Scale(20)
        return clientX >= w - arrowW && clientX < w
    }

    /** Shows the configured dropdown menu (or invokes the callback) anchored under the button.
     * Calls TrackPopupMenu directly so we can speak physical pixels end-to-end — GetWindowRect
     * returns physical, TrackPopupMenu takes physical. Avoids Menu.Show's DPI auto-scaling,
     * which silently mangles coordinates on high-DPI displays. The parent gui hwnd is the
     * owner so AHK's normal WM_COMMAND dispatch still fires the menu item callbacks. */
    static _ShowDropdown(hwnd) {
        if this.OnDropdownCbs.Has(hwnd) {
            cb := this.OnDropdownCbs[hwnd]
            cb(this.Instances.Get(hwnd, ""))
            return
        }
        if !this.Menus.Has(hwnd) || !this.Instances.Has(hwnd)
            return
        rc := Buffer(16, 0)
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)
        DllCall("TrackPopupMenu",
            "Ptr", this.Menus[hwnd].Handle,
            "UInt", 0,
            "Int", NumGet(rc, 0, "Int"),
            "Int", NumGet(rc, 12, "Int"),
            "Int", 0,
            "Ptr", this.Instances[hwnd].Gui.Hwnd,
            "Ptr", 0)
    }

    static PaintButton(hwnd) {
        ps := Buffer(72, 0)
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")

        rc := Buffer(16)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int")
        h := NumGet(rc, 12, "Int")

        mode := this.ButtonModes.Get(hwnd, "default")
        switch mode {
            case "icon":    this._PaintIcon(hwnd, hdc, w, h)
            case "split":   this._PaintSplit(hwnd, hdc, w, h)
            case "command": this._PaintCommand(hwnd, hdc, w, h)
            case "toggle":  this._PaintToggle(hwnd, hdc, w, h)
            case "flat":    this._PaintFlat(hwnd, hdc, w, h)
            default:        this._PaintBasic(hwnd, hdc, w, h)
        }

        ; Keyboard focus ring on top of whatever the mode drew.
        if this.FocusStates.Get(hwnd, false)
            this._PaintFocusRing(hdc, w, h, mode = "accent" ? 0xFFFFFF : DarkTheme.Colors["Accent"])

        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
    }

    /** Draws a 1px rounded focus ring inset from the client edge (no fill). */
    static _PaintFocusRing(hdc, w, h, ringColor) {
        pen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", DarkTheme.RGBtoBGR(ringColor), "Ptr")
        nullBrush := DllCall("GetStockObject", "Int", 5, "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        oldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", nullBrush, "Ptr")
        r := this._Radius
        DllCall("RoundRect", "Ptr", hdc, "Int", 1, "Int", 1, "Int", w - 1, "Int", h - 1, "Int", r, "Int", r)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldBrush)
        DllCall("DeleteObject", "Ptr", pen)
    }

    /** Selects state-appropriate bg, text, and border colors for default/accent modes.
     * Win11-style: hover is a small lift, press is *darker* than rest (button "pushes in"). */
    static _StateColors(hwnd, mode) {
        isHover := this.HoverStates[hwnd]
        isPressed := this.PressedStates[hwnd]
        if mode = "accent" {
            bgColor := isPressed ? 0x005A9E : (isHover ? 0x1A8CFF : DarkTheme.Colors["Accent"])
            textColor := 0xFFFFFF
            borderColor := 0x0064B0
        } else {
            bgColor := isPressed ? 0x1F1F1F : (isHover ? 0x303030 : DarkTheme.Colors["Controls"])
            textColor := DarkTheme.Colors["Font"]
            borderColor := 0x3A3A3A
        }
        return [bgColor, textColor, borderColor]
    }

    /** Win11-feel button corner radius in DPI-scaled pixels. */
    static _Radius => DarkTheme.Scale(5)

    /** Fills the entire client rect with the parent (window) color. */
    static _FillParent(hdc, rc) {
        b := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]), "Ptr")
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", b)
        DllCall("DeleteObject", "Ptr", b)
    }

    /** Paints a rounded-rectangle fill with optional border color. */
    static _RoundFill(hdc, x1, y1, x2, y2, radius, bgColor, borderColor := -1) {
        bg := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(bgColor), "Ptr")
        bcol := borderColor = -1 ? bgColor : borderColor
        pen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", DarkTheme.RGBtoBGR(bcol), "Ptr")
        oldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", bg, "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        DllCall("RoundRect", "Ptr", hdc, "Int", x1, "Int", y1, "Int", x2, "Int", y2, "Int", radius, "Int", radius)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldBrush)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen)
        DllCall("DeleteObject", "Ptr", bg)
        DllCall("DeleteObject", "Ptr", pen)
    }

    /** Selects the button's font into the dc and returns the previous font handle (0 if none). */
    static _SelectButtonFont(hwnd, hdc) {
        hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        return hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
    }

    /** Draws text using DrawText with a flag set; rect is a Buffer of RECT. */
    static _DrawText(hdc, text, rect, color, flags) {
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(color))
        DllCall("DrawText", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rect, "UInt", flags)
    }

    /** Draws an HICON via DrawIconEx at (x,y) sized sizePx. */
    static _DrawIcon(hdc, hicon, x, y, sizePx) {
        if !hicon
            return
        static DI_NORMAL := 0x3
        DllCall("DrawIconEx", "Ptr", hdc, "Int", x, "Int", y, "Ptr", hicon,
                "Int", sizePx, "Int", sizePx, "UInt", 0, "Ptr", 0, "UInt", DI_NORMAL)
    }

    /** Constructs a RECT buffer for use with DrawText. */
    static _MakeRect(left, top, right, bottom) {
        rc := Buffer(16)
        NumPut("Int", left, rc, 0)
        NumPut("Int", top, rc, 4)
        NumPut("Int", right, rc, 8)
        NumPut("Int", bottom, rc, 12)
        return rc
    }

    /** Default + accent path: rounded fill with thin border, centered text. */
    static _PaintBasic(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        mode := this.ButtonModes.Get(hwnd, "default")
        colors := this._StateColors(hwnd, mode)
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius, colors[1], colors[3])
        oldFont := this._SelectButtonFont(hwnd, hdc)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        this._DrawText(hdc, this.ButtonTexts[hwnd], rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    }

    /** Icon + optional text. align="left"|"right"|"top"|"center". */
    static _PaintIcon(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        colors := this._StateColors(hwnd, "default")
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius, colors[1], colors[3])

        btnText := this.ButtonTexts[hwnd]
        hicon := this.Icons.Get(hwnd, 0)
        align := this.IconAligns.Get(hwnd, "left")
        iconSize := DarkTheme.Scale(16)
        pad := DarkTheme.Scale(8)

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
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    }

    /** Split button: main text region + dropdown-arrow region with divider. */
    static _PaintSplit(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        baseColors := this._StateColors(hwnd, "default")
        this._FillParent(hdc, rc)

        arrowW := DarkTheme.Scale(20)
        hoverArrow := this.HoverArrow.Get(hwnd, false)
        isHover := this.HoverStates[hwnd]
        isPressed := this.PressedStates[hwnd]

        ; Win11-feel: hover lifts subtly, press goes darker than rest
        mainHover := isHover && !hoverArrow
        mainBg := isPressed && !hoverArrow ? 0x1F1F1F
                : (mainHover ? 0x303030 : DarkTheme.Colors["Controls"])
        arrowHover := isHover && hoverArrow
        arrowBg := isPressed && hoverArrow ? 0x1F1F1F
                 : (arrowHover ? 0x303030 : DarkTheme.Colors["Controls"])

        ; Single rounded backdrop with thin border, then overlay arrow region
        radius := this._Radius
        this._RoundFill(hdc, 0, 0, w, h, radius, mainBg, baseColors[3])
        if arrowBg != mainBg {
            ; Overlay arrow region using a clipping intersection of the rounded rect
            arrowRc := this._MakeRect(w - arrowW, 0, w, h)
            saved := DllCall("SaveDC", "Ptr", hdc, "Int")
            rgn := DllCall("CreateRoundRectRgn", "Int", 1, "Int", 1, "Int", w, "Int", h,
                           "Int", radius - 1, "Int", radius - 1, "Ptr")
            DllCall("SelectClipRgn", "Ptr", hdc, "Ptr", rgn)
            ab := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(arrowBg), "Ptr")
            DllCall("FillRect", "Ptr", hdc, "Ptr", arrowRc, "Ptr", ab)
            DllCall("DeleteObject", "Ptr", ab)
            DllCall("RestoreDC", "Ptr", hdc, "Int", saved)
            DllCall("DeleteObject", "Ptr", rgn)
        }

        ; Vertical divider line between regions
        divPen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"]), "Ptr")
        oldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", divPen, "Ptr")
        divX := w - arrowW
        DllCall("MoveToEx", "Ptr", hdc, "Int", divX, "Int", DarkTheme.Scale(4), "Ptr", 0)
        DllCall("LineTo", "Ptr", hdc, "Int", divX, "Int", h - DarkTheme.Scale(4))
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldPen)
        DllCall("DeleteObject", "Ptr", divPen)

        ; Main text (left region)
        oldFont := this._SelectButtonFont(hwnd, hdc)
        textRc := this._MakeRect(0, 0, w - arrowW, h)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        this._DrawText(hdc, this.ButtonTexts[hwnd], textRc, baseColors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)

        ; Down-arrow triangle in arrow region
        this._PaintDownArrow(hdc, w - arrowW + arrowW // 2, h // 2, DarkTheme.Scale(4), baseColors[2])
    }

    /** Filled triangle pointing down, centered at (cx, cy), with half-width radius. */
    static _PaintDownArrow(hdc, cx, cy, radius, color) {
        pts := Buffer(24)
        NumPut("Int", cx - radius, pts, 0),  NumPut("Int", cy - radius // 2, pts, 4)
        NumPut("Int", cx + radius, pts, 8),  NumPut("Int", cy - radius // 2, pts, 12)
        NumPut("Int", cx,          pts, 16), NumPut("Int", cy + radius,      pts, 20)
        brush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(color), "Ptr")
        pen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", DarkTheme.RGBtoBGR(color), "Ptr")
        oldB := DllCall("SelectObject", "Ptr", hdc, "Ptr", brush, "Ptr")
        oldP := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        DllCall("Polygon", "Ptr", hdc, "Ptr", pts, "Int", 3)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldB)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldP)
        DllCall("DeleteObject", "Ptr", brush)
        DllCall("DeleteObject", "Ptr", pen)
    }

    /** Right-pointing chevron used as the default command-link icon. */
    static _PaintRightArrow(hdc, cx, cy, radius, color) {
        pts := Buffer(24)
        NumPut("Int", cx - radius // 2, pts, 0),  NumPut("Int", cy - radius, pts, 4)
        NumPut("Int", cx - radius // 2, pts, 8),  NumPut("Int", cy + radius, pts, 12)
        NumPut("Int", cx + radius,      pts, 16), NumPut("Int", cy,          pts, 20)
        brush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(color), "Ptr")
        pen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", DarkTheme.RGBtoBGR(color), "Ptr")
        oldB := DllCall("SelectObject", "Ptr", hdc, "Ptr", brush, "Ptr")
        oldP := DllCall("SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        DllCall("Polygon", "Ptr", hdc, "Ptr", pts, "Int", 3)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldB)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldP)
        DllCall("DeleteObject", "Ptr", brush)
        DllCall("DeleteObject", "Ptr", pen)
    }

    /** Vista-style command link: title + description + optional left icon (default chevron). */
    static _PaintCommand(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        colors := this._StateColors(hwnd, "default")
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius, colors[1], colors[3])

        pad := DarkTheme.Scale(12)
        iconSize := DarkTheme.Scale(20)
        hicon := this.Icons.Get(hwnd, 0)

        iconAreaX := pad
        iconAreaY := pad
        if hicon {
            this._DrawIcon(hdc, hicon, iconAreaX, iconAreaY, iconSize)
        } else {
            this._PaintRightArrow(hdc, iconAreaX + iconSize // 2, iconAreaY + iconSize // 2,
                                  DarkTheme.Scale(7), DarkTheme.Colors["Accent"])
        }

        textLeft := iconAreaX + iconSize + pad
        oldFont := this._SelectButtonFont(hwnd, hdc)

        cmdTitle := this.ButtonTexts[hwnd]
        desc := this.Descriptions.Get(hwnd, "")

        static DT_LEFT := 0x0, DT_TOP := 0x0, DT_SINGLELINE := 0x20, DT_WORDBREAK := 0x10, DT_END_ELLIPSIS := 0x8000
        titleRc := this._MakeRect(textLeft, pad, w - pad, pad + DarkTheme.Scale(22))
        this._DrawText(hdc, cmdTitle, titleRc, colors[2], DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS)

        descRc := this._MakeRect(textLeft, pad + DarkTheme.Scale(22) + 2, w - pad, h - pad)
        this._DrawText(hdc, desc, descRc, DarkTheme.Colors["FontDim"], DT_LEFT | DT_TOP | DT_WORDBREAK)

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    }

    /** Sticky toggle button — on-state mimics an Accent button so the active state really pops.
     * Off-state matches the default-mode button so toggles look at home next to regular buttons. */
    static _PaintToggle(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        isToggled := this.ToggleStates.Get(hwnd, false)
        colors := this._StateColors(hwnd, isToggled ? "accent" : "default")
        this._FillParent(hdc, rc)
        this._RoundFill(hdc, 0, 0, w, h, this._Radius, colors[1], colors[3])
        oldFont := this._SelectButtonFont(hwnd, hdc)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        this._DrawText(hdc, this.ButtonTexts[hwnd], rc, colors[2], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    }

    /** Borderless flat button — no fill at idle, hover/press only. */
    static _PaintFlat(hwnd, hdc, w, h) {
        rc := this._MakeRect(0, 0, w, h)
        isHover := this.HoverStates[hwnd]
        isPressed := this.PressedStates[hwnd]

        if this.IdleFills.Has(hwnd) {
            b := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(this.IdleFills[hwnd]), "Ptr")
            DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", b)
            DllCall("DeleteObject", "Ptr", b)
        } else
            this._FillParent(hdc, rc)
        if isPressed
            this._RoundFill(hdc, 0, 0, w, h, this._Radius, 0x282828)
        else if isHover
            this._RoundFill(hdc, 0, 0, w, h, this._Radius, 0x303030)

        oldFont := this._SelectButtonFont(hwnd, hdc)
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        this._DrawText(hdc, this.ButtonTexts[hwnd], rc, DarkTheme.Colors["Font"], DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
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

    /** @type {Map} Window procedure callbacks */
    static Callbacks := Map()
    /** @type {Map} Original window procedures */
    static OldProcs := Map()

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
        cbi := Buffer(A_PtrSize = 8 ? 64 : 52, 0)
        NumPut("UInt", cbi.Size, cbi, 0)
        if DllCall("SendMessage", "Ptr", combo.Hwnd, "UInt", CB_GETCOMBOBOXINFO, "Ptr", 0, "Ptr", cbi) {
            listHwnd := NumGet(cbi, A_PtrSize = 8 ? 56 : 44, "Ptr")
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
        Subclass.Install(hwnd, ObjBindMethod(this, "ComboProc", hwnd), this.Callbacks, this.OldProcs)
    }

    /**
     * Removes subclass and frees resources for a ComboBox.
     * @param {Ptr} hwnd - ComboBox window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this.Callbacks, this.OldProcs)
    }

    static ComboProc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F

        if hwnd != targetHwnd
            return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)

        ; Completely take over WM_PAINT - don't call original proc to prevent text jumping
        if msg = WM_PAINT {
            this.DrawComboBox(hwnd)
            return 0
        }

        return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
    }

    static DrawComboBox(hwnd) {
        ; Use BeginPaint/EndPaint for proper WM_PAINT handling
        ps := Buffer(72, 0)  ; PAINTSTRUCT
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        if !hdc
            return

        rc := Buffer(16)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int")
        h := NumGet(rc, 12, "Int")

        bgColor := DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"])
        ctrlColor := DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"])
        fontColor := DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"])

        bgBrush := DllCall("CreateSolidBrush", "UInt", bgColor, "Ptr")
        ctrlBrush := DllCall("CreateSolidBrush", "UInt", ctrlColor, "Ptr")

        ; Step 1: Fill entire control with parent bg color (covers all exterior artifacts)
        fillRect := Buffer(16)
        NumPut("Int", 0, "Int", 0, "Int", w, "Int", h, fillRect)
        DllCall("FillRect", "Ptr", hdc, "Ptr", fillRect, "Ptr", bgBrush)

        ; Step 2: Fill interior with control color (rounded rect, no border)
        hOldBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", ctrlBrush, "Ptr")
        nullPen := DllCall("GetStockObject", "Int", 8, "Ptr")  ; NULL_PEN
        hOldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", nullPen, "Ptr")
        comboRadius := DarkTheme.Scale(6)
        DllCall("RoundRect", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", comboRadius, "Int", comboRadius)

        ; Step 3: Draw dropdown arrow
        arrowPen := DllCall("CreatePen", "Int", 0, "Int", 2, "UInt", fontColor, "Ptr")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", arrowPen, "Ptr")

        arrowCenterX := w - DarkTheme.Scale(12)
        arrowCenterY := h // 2
        arrowHalfWidth := DarkTheme.Scale(4)
        arrowHeight := DarkTheme.Scale(3)

        DllCall("MoveToEx", "Ptr", hdc, "Int", arrowCenterX - arrowHalfWidth, "Int", arrowCenterY - arrowHeight, "Ptr", 0)
        DllCall("LineTo", "Ptr", hdc, "Int", arrowCenterX, "Int", arrowCenterY + 1)
        DllCall("MoveToEx", "Ptr", hdc, "Int", arrowCenterX, "Int", arrowCenterY + 1, "Ptr", 0)
        DllCall("LineTo", "Ptr", hdc, "Int", arrowCenterX + arrowHalfWidth, "Int", arrowCenterY - arrowHeight)

        ; Step 5: Draw text
        static WM_GETTEXT := 0x000D
        static WM_GETTEXTLENGTH := 0x000E
        static WM_GETFONT := 0x0031
        textLen := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETTEXTLENGTH, "Ptr", 0, "Ptr", 0, "Int")
        if textLen > 0 {
            textBuf := Buffer((textLen + 1) * 2, 0)
            DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETTEXT, "Ptr", textLen + 1, "Ptr", textBuf)

            DllCall("SetTextColor", "Ptr", hdc, "UInt", fontColor)
            DllCall("SetBkMode", "Ptr", hdc, "Int", 1)  ; TRANSPARENT

            hFont := DllCall("SendMessage", "Ptr", hwnd, "UInt", WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
            hOldFont := 0
            if hFont
                hOldFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")

            rcText := Buffer(16)
            NumPut("Int", DarkTheme.Scale(6), "Int", 0, "Int", w - DarkTheme.Scale(24), "Int", h, rcText)
            static DT_SINGLELINE := 0x20, DT_VCENTER := 0x4, DT_NOPREFIX := 0x800
            DllCall("DrawTextW", "Ptr", hdc, "Ptr", textBuf, "Int", -1, "Ptr", rcText, "UInt", DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX)

            if hOldFont
                DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldFont, "Ptr")
        }

        ; Cleanup
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldPen)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldBrush)
        DllCall("DeleteObject", "Ptr", bgBrush)
        DllCall("DeleteObject", "Ptr", ctrlBrush)
        DllCall("DeleteObject", "Ptr", arrowPen)
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
    }
}

/**
 * Custom-drawn Slider with GDI+ anti-aliased thumb. Features circular knob
 * with blue accent border, double-buffered rendering to prevent artifacts.
 */
class _DarkSlider extends Gui.Slider {
    /** @type {Map} Window procedure callbacks */
    static Callbacks := Map()
    /** @type {Map} Original window procedures */
    static OldProcs := Map()
    /** @type {Map} Per-slider state data */
    static SliderData := Map()
    /** @type {Integer} GDI+ startup token (initialized once) */
    static GdipToken := 0

    static __New() {
        super.Prototype.SetDarkMode := ObjBindMethod(this, "ApplyDarkMode")
        ; Initialize GDI+ once for anti-aliased thumb drawing
        si := Buffer(24, 0)
        NumPut("UInt", 1, si, 0)
        token := 0
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
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

        DllCall("InvalidateRect", "Ptr", slider.Hwnd, "Ptr", 0, "Int", true)
    }

    static SubclassSlider(hwnd) {
        Subclass.Install(hwnd, ObjBindMethod(this, "SliderProc", hwnd), this.Callbacks, this.OldProcs)
    }

    /**
     * Removes subclass and frees resources for a Slider.
     * @param {Ptr} hwnd - Slider window handle
     */
    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this.Callbacks, this.OldProcs)
        this.SliderData.Delete(hwnd)
    }

    /**
     * Shuts down GDI+ (call on application exit).
     */
    static Shutdown() {
        if this.GdipToken {
            ; AHK shares gdiplus.dll for image loading; by __Delete time
            ; the token can already be invalid. OS reclaims GDI+ on exit.
            try DllCall("gdiplus\GdiplusShutdown", "Ptr", this.GdipToken)
            this.GdipToken := 0
        }
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
            return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)

        ; Force full invalidation on mouse events that move the thumb
        if msg = WM_LBUTTONDOWN || msg = WM_MOUSEMOVE || msg = WM_LBUTTONUP {
            result := Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
            ; Invalidate entire control to repaint cleanly
            DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", true)
            return result
        }

        if msg = WM_ERASEBKGND {
            ; Fill background
            rc := Buffer(16)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
            hBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]), "Ptr")
            DllCall("FillRect", "Ptr", wParam, "Ptr", rc, "Ptr", hBrush)
            DllCall("DeleteObject", "Ptr", hBrush)
            return 1
        }

        if msg = WM_PAINT {
            ps := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
            hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")

            ; Get client rect
            rcClient := Buffer(16)
            DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rcClient)
            clientW := NumGet(rcClient, 8, "Int")
            clientH := NumGet(rcClient, 12, "Int")

            ; Use double buffering to prevent artifacts
            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
            hBitmap := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", clientW, "Int", clientH, "Ptr")
            hOldBitmap := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")

            ; Fill background (draw to memory DC)
            hBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"]), "Ptr")
            DllCall("FillRect", "Ptr", hdcMem, "Ptr", rcClient, "Ptr", hBrush)
            DllCall("DeleteObject", "Ptr", hBrush)

            ; Get channel rect (use actual Windows position)
            rcChannel := Buffer(16, 0)
            SendMessage(TBM_GETCHANNELRECT, 0, rcChannel.Ptr, hwnd)

            ; Draw track/channel using actual rect from Windows
            hBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Controls"]), "Ptr")
            DllCall("FillRect", "Ptr", hdcMem, "Ptr", rcChannel, "Ptr", hBrush)
            DllCall("DeleteObject", "Ptr", hBrush)

            ; Get thumb rect
            rcThumb := Buffer(16, 0)
            SendMessage(TBM_GETTHUMBRECT, 0, rcThumb.Ptr, hwnd)
            thumbLeft := NumGet(rcThumb, 0, "Int")
            thumbTop := NumGet(rcThumb, 4, "Int")
            thumbRight := NumGet(rcThumb, 8, "Int")
            thumbBottom := NumGet(rcThumb, 12, "Int")

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

            ; Draw thumb as white circle with blue border using GDI+ for anti-aliasing
            fillColor := 0xFFFFFFFF  ; White fill (ARGB: fully opaque white)
            borderColor := 0xFF0078D7  ; Blue border (ARGB: fully opaque accent blue)
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
            DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", clientW, "Int", clientH, "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY

            ; Clean up memory DC
            DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hOldBitmap, "Ptr")
            DllCall("DeleteObject", "Ptr", hBitmap)
            DllCall("DeleteDC", "Ptr", hdcMem)

            DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
            return 0
        }

        return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
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
 * Custom-draw GroupBox: fills background, draws dim border, renders title in Font color.
 * WM_CTLCOLORBTN does not control GroupBox text color — a WM_PAINT subclass is required.
 */
class _DarkGroupBox {
    static Callbacks  := Map()
    static OldProcs   := Map()
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
        Subclass.Install(hwnd, ObjBindMethod(this, "Proc", hwnd), this.Callbacks, this.OldProcs)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    }

    /**
     * Removes subclass and frees resources for a GroupBox.
     *
     * @param {Ptr} hwnd - GroupBox window handle.
     */
    static Remove(hwnd) {
        Subclass.Uninstall(hwnd, this.Callbacks, this.OldProcs)
        this.GroupTexts.Delete(hwnd)
    }

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT      := 0x000F
        static WM_ERASEBKGND := 0x0014
        if msg = WM_ERASEBKGND {
            rc := Buffer(16)
            DllCall("GetClientRect", "Ptr", targetHwnd, "Ptr", rc)
            DllCall("FillRect", "Ptr", wParam, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"))
            return 1
        }
        if msg = WM_PAINT {
            this.Paint(targetHwnd)
            return 0
        }
        return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
    }

    static Paint(hwnd) {
        ps  := Buffer(72, 0)
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")

        rc := Buffer(16)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int")
        h := NumGet(rc, 12, "Int")

        ; Fill entire background
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Background"))

        ; Select control font so text metrics are accurate
        hFont   := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0

        ; Measure font height
        tm := Buffer(60, 0)
        DllCall("GetTextMetrics", "Ptr", hdc, "Ptr", tm)
        tmH := NumGet(tm, 0, "Int")  ; tmHeight

        ; Measure title text width
        groupText := this.GroupTexts.Has(hwnd) ? this.GroupTexts[hwnd] : ""
        sz    := Buffer(8, 0)
        DllCall("GetTextExtentPoint32", "Ptr", hdc, "Str", groupText, "Int", StrLen(groupText), "Ptr", sz)
        textW := NumGet(sz, 0, "Int")

        textX   := DarkTheme.Scale(9)
        borderY := tmH // 2

        ; Draw hollow border rectangle (NULL_BRUSH = stock 5, no fill)
        borderBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"])
        hPen  := DllCall("CreatePen",      "Int", 0, "Int", 1, "UInt", borderBGR, "Ptr")
        hNull := DllCall("GetStockObject", "Int", 5, "Ptr")
        oPen  := DllCall("SelectObject", "Ptr", hdc, "Ptr", hPen,  "Ptr")
        oBr   := DllCall("SelectObject", "Ptr", hdc, "Ptr", hNull, "Ptr")
        DllCall("RoundRect", "Ptr", hdc, "Int", 0, "Int", borderY, "Int", w, "Int", h, "Int", 8, "Int", 8)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oPen)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oBr)
        DllCall("DeleteObject", "Ptr", hPen)

        ; Punch a background-colored gap in the top border line where the title sits
        if StrLen(groupText) > 0 {
            gapRc := Buffer(16)
            NumPut("Int", textX - 2,         "Int", borderY - 1,
                   "Int", textX + textW + 2,  "Int", borderY + 1, gapRc)
            DllCall("FillRect", "Ptr", hdc, "Ptr", gapRc, "Ptr", DarkTheme.GetBrush("Background"))
        }

        ; Draw title text in Font color (TRANSPARENT background mode)
        DllCall("SetBkMode",    "Ptr", hdc, "Int", 1)
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
        textRc := Buffer(16)
        NumPut("Int", textX, "Int", 0, "Int", textX + textW + 4, "Int", tmH, textRc)
        static DT_SINGLELINE := 0x20
        DllCall("DrawText", "Ptr", hdc, "Str", groupText, "Int", -1, "Ptr", textRc, "UInt", DT_SINGLELINE)

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
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
    static Callbacks := Map()
    static OldProcs  := Map()

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
        this._AllowDarkMode(hwnd, true)
        ; Remove sunken edge — we draw our own border (none, by design)
        DarkTheme.RemoveBorder(hwnd)
        Subclass.Install(hwnd, ObjBindMethod(this, "Proc", hwnd), this.Callbacks, this.OldProcs)
        DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", 1)
    }

    static _AllowDarkMode(hwnd, allow) {
        try {
            uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
            if uxtheme {
                fn := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 133, "Ptr")
                if fn
                    DllCall(fn, "Ptr", hwnd, "Int", allow ? 1 : 0)
            }
        }
    }

    /**
     * Removes dark mode subclass and restores default rendering.
     *
     * @param {Ptr} hwnd - Tab3 window handle.
     */
    static Remove(hwnd) {
        this._AllowDarkMode(hwnd, false)
        Subclass.Uninstall(hwnd, this.Callbacks, this.OldProcs)
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
            ps := Buffer(72, 0)
            hdc := DllCall("BeginPaint", "Ptr", targetHwnd, "Ptr", ps, "Ptr")
            rcBuf := Buffer(16)
            DllCall("GetClientRect", "Ptr", targetHwnd, "Ptr", rcBuf)
            w := NumGet(rcBuf, 8, "Int")
            h := NumGet(rcBuf, 12, "Int")
            hdcMem  := DllCall("CreateCompatibleDC",     "Ptr", hdc, "Ptr")
            hBmp    := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", w, "Int", h, "Ptr")
            hBmpOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBmp, "Ptr")
            this.PaintTabs(targetHwnd, hdcMem)
            DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h,
                "Ptr", hdcMem, "Int", 0, "Int", 0, "UInt", SRCCOPY)
            DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBmpOld)
            DllCall("DeleteObject", "Ptr", hBmp)
            DllCall("DeleteDC",     "Ptr", hdcMem)
            DllCall("EndPaint", "Ptr", targetHwnd, "Ptr", ps)
            return 0
        }
        return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
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
        clientRc := Buffer(16)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", clientRc)
        w := NumGet(clientRc, 8, "Int")
        h := NumGet(clientRc, 12, "Int")

        ; Fill entire background — no tab-control border
        DllCall("FillRect", "Ptr", hdc, "Ptr", clientRc, "Ptr", DarkTheme.GetBrush("Background"))

        selIdx := DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETCURSEL,    "Ptr", 0, "Ptr", 0, "Int")
        tabCount := DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETITEMCOUNT, "Ptr", 0, "Ptr", 0, "Int")
        if tabCount <= 0
            return

        ; Content area top = tab strip bottom (for separator line)
        adjRc := Buffer(16)
        NumPut("Int", 0, "Int", 0, "Int", w, "Int", h, adjRc)
        DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_ADJUSTRECT, "Ptr", 0, "Ptr", adjRc)
        tabStripBottom := NumGet(adjRc, 4, "Int")

        ; Select control font
        hFont   := DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := hFont ? DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr") : 0
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1)  ; TRANSPARENT

        hNullPen := DllCall("GetStockObject", "Int", NULL_PEN, "Ptr")

        ; TCITEMW struct offsets (64-bit: pszText@16, cchTextMax@24; 32-bit: @12, @16)
        pszTextOff := A_PtrSize = 8 ? 16 : 12
        cchMaxOff  := A_PtrSize = 8 ? 24 : 16
        tcItemSz   := A_PtrSize = 8 ? 40 : 28

        loop tabCount {
            i := A_Index - 1
            itemRc := Buffer(16)
            DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETITEMRECT, "Ptr", i, "Ptr", itemRc)
            left   := NumGet(itemRc, 0,  "Int")
            top    := NumGet(itemRc, 4,  "Int")
            right  := NumGet(itemRc, 8,  "Int")
            bottom := NumGet(itemRc, 12, "Int")

            if (i = selIdx) {
                ; Rounded pill: top corners round, bottom corners square.
                ; Draw full RoundRect, then overdraw bottom 6px with FillRect
                ; using same brush — squares off the bottom corner curves.
                tabBrush := DllCall("CreateSolidBrush", "UInt",
                    DarkTheme.RGBtoBGR(DarkTheme.Colors["ControlsHover"]), "Ptr")
                oPen   := DllCall("SelectObject", "Ptr", hdc, "Ptr", hNullPen, "Ptr")
                oBrush := DllCall("SelectObject", "Ptr", hdc, "Ptr", tabBrush, "Ptr")
                DllCall("RoundRect", "Ptr", hdc,
                    "Int", left+2, "Int", top, "Int", right-1, "Int", bottom+1,
                    "Int", 6, "Int", 6)
                squareRc := Buffer(16)
                NumPut("Int", left+2,    squareRc,  0)
                NumPut("Int", bottom-6,  squareRc,  4)
                NumPut("Int", right-1,   squareRc,  8)
                NumPut("Int", bottom+1,  squareRc, 12)
                DllCall("FillRect", "Ptr", hdc, "Ptr", squareRc, "Ptr", tabBrush)
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oPen)
                DllCall("SelectObject", "Ptr", hdc, "Ptr", oBrush)
                DllCall("DeleteObject", "Ptr", tabBrush)
                DllCall("SetTextColor", "Ptr", hdc, "UInt",
                    DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
            } else {
                DllCall("SetTextColor", "Ptr", hdc, "UInt",
                    DarkTheme.RGBtoBGR(DarkTheme.Colors["FontDim"]))
            }

            ; Fetch label text via TCM_GETITEMW and draw centered
            textBuf := Buffer(512, 0)
            tcItem  := Buffer(tcItemSz, 0)
            NumPut("UInt", TCIF_TEXT,   tcItem, 0)
            NumPut("Ptr",  textBuf.Ptr, tcItem, pszTextOff)
            NumPut("Int",  255,         tcItem, cchMaxOff)
            DllCall("SendMessage", "Ptr", hwnd, "UInt", TCM_GETITEM, "Ptr", i, "Ptr", tcItem)
            tabText := StrGet(textBuf)
            DllCall("DrawText", "Ptr", hdc, "Str", tabText, "Int", -1, "Ptr", itemRc,
                "UInt", DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        }

        ; 1px separator line between tab strip and content area
        if tabStripBottom > 0 {
            sepRc := Buffer(16)
            NumPut("Int", 0, "Int", tabStripBottom - 1, "Int", w, "Int", tabStripBottom, sepRc)
            DllCall("FillRect", "Ptr", hdc, "Ptr", sepRc, "Ptr", DarkTheme.GetBrush("Border"))
        }

        if oldFont
            DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    }
}

/**
 * Window procedure subclass for handling WM_CTLCOLOR* messages.
 * Provides dark background brushes for Edit, ListBox, Button, and Static controls.
 */
class DarkWindowProc {
    /** @type {Map} Window procedure callbacks */
    static Callbacks := Map()
    /** @type {Map} Original window procedures */
    static OldProcs := Map()
    /** @type {Map} Radio button text control handles for WM_CTLCOLORSTATIC */
    static RadioTextControls := Map()
    /** @type {Map} Menu bar control handles that need Header background instead of Background */
    static MenuBarControls := Map()
    /** @type {Map} ComboBox dropdown list handles for WM_CTLCOLORLISTBOX */
    static ComboDropdowns := Map()

    /**
     * Installs dark window procedure on a window.
     * @param {Ptr} hwnd - Window handle
     */
    static Install(hwnd) {
        Subclass.Install(hwnd, ObjBindMethod(this, "Proc", hwnd), this.Callbacks, this.OldProcs)
    }

    /**
     * Removes dark window procedure and restores original.
     * @param {Ptr} hwnd - Window handle
     */
    static Uninstall(hwnd) {
        Subclass.Uninstall(hwnd, this.Callbacks, this.OldProcs)
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
        static TRANSPARENT := 1

        if hwnd != targetHwnd
            return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)

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
        }

        return Subclass.CallOriginal(this.OldProcs[targetHwnd], hwnd, msg, wParam, lParam)
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
        DllCall("AppendMenu", "Ptr", this.hPopup, "UInt", 0x0000, "Ptr", id, "Str", itemText)
        return this
    }

    /**
     * Appends a separator line.
     * @returns {_DarkMenuBuilder} this (chainable)
     */
    Sep() {
        DllCall("AppendMenu", "Ptr", this.hPopup, "UInt", 0x0800, "Ptr", 0, "Ptr", 0)
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
        this.menuItems := []
        this.toolbarBtns := []
        this.hoveredMenu := ""

        this.layout := Map(
            "menuBarHeight", options.Has("menuBarHeight") ? options["menuBarHeight"] : 24,
            "toolbarHeight", options.Has("toolbarHeight") ? options["toolbarHeight"] : 32,
            "menuItemPadding", options.Has("menuItemPadding") ? options["menuItemPadding"] : 12,
            "menuFontSize", options.Has("menuFontSize") ? options["menuFontSize"] : 9,
            "toolbarIconSize", options.Has("toolbarIconSize") ? options["toolbarIconSize"] : 20,
            "toolbarButtonSpacing", options.Has("toolbarButtonSpacing") ? options["toolbarButtonSpacing"] : 4,
            "toolbarSeparatorWidth", options.Has("toolbarSeparatorWidth") ? options["toolbarSeparatorWidth"] : 1,
            "showToolbar", options.Has("showToolbar") ? options["showToolbar"] : true,
            "popupOffsetX", options.Has("popupOffsetX") ? options["popupOffsetX"] : 0,
            "popupOffsetY", options.Has("popupOffsetY") ? options["popupOffsetY"] : 0
        )

        this.colors := Map(
            "menuBarBg", options.Has("menuBarBg") ? options["menuBarBg"] : DarkTheme.Colors["Header"],
            "menuBarText", options.Has("menuBarText") ? options["menuBarText"] : DarkTheme.Colors["Font"],
            "menuBarHover", options.Has("menuBarHover") ? options["menuBarHover"] : DarkTheme.Colors["ControlsActive"],
            "menuBarActive", options.Has("menuBarActive") ? options["menuBarActive"] : DarkTheme.Colors["Accent"],
            "popupBg", options.Has("popupBg") ? options["popupBg"] : DarkTheme.Colors["Header"],
            "toolbarBg", options.Has("toolbarBg") ? options["toolbarBg"] : DarkTheme.Colors["Header"],
            "toolbarBorder", options.Has("toolbarBorder") ? options["toolbarBorder"] : DarkTheme.Colors["Border"]
        )

        this.totalHeight := this.layout["showToolbar"] ?
            (this.layout["menuBarHeight"] + this.layout["toolbarHeight"] + 1) :
            this.layout["menuBarHeight"]

        DarkMenu.Apply()
        this._AllowDarkModeForWindow()
        this.CreateMenuBar()
        if this.layout["showToolbar"] {
            this.CreateToolbar()
        }

        this._onMouseMove := this.OnMouseMove.Bind(this)
        OnMessage(0x200, this._onMouseMove)
        this._lastHoveredBtn := ""
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

        itemWidth := StrLen(menuName) * 7 + this.layout["menuItemPadding"]

        ; Center label vertically in menu bar using SS_CENTERIMAGE (0x200)
        menuLabel := this.gui.AddText("x" . this.menuBarStartX . " y0 w" . itemWidth . " h" . this.layout["menuBarHeight"] . " +0x200 Center BackgroundTrans c" . Format("{:06X}", this.colors["menuBarText"]), menuName)
        menuLabel.SetFont("s" . this.layout["menuFontSize"], "Segoe UI")

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
        btnHit.ToolTip := tooltip

        btnData := Map(
            "bg", btnBg,
            "icon", btnIcon,
            "hit", btnHit,
            "x", btnX,
            "y", btnY,
            "tooltip", tooltip
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
                ctrlRect := Buffer(16, 0)
                DllCall("GetWindowRect", "Ptr", item["hitArea"].Hwnd, "Ptr", ctrlRect)

                popupX := NumGet(ctrlRect, 0, "Int")   ; Left
                popupY := NumGet(ctrlRect, 12, "Int")  ; Bottom

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

    ApplyDarkThemeToPopup(hPopup) {
        darkBrush := DllCall("CreateSolidBrush", "UInt", DarkTheme.RGBtoBGR(this.colors["popupBg"]), "Ptr")

        mi := Buffer(28, 0)
        NumPut("UInt", mi.Size, mi, 0)
        NumPut("UInt", 0x10, mi, 4)
        NumPut("Ptr", darkBrush, mi, 16)
        DllCall("SetMenuInfo", "Ptr", hPopup, "Ptr", mi)
    }

    _AllowDarkModeForWindow() {
        try {
            uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
            if !uxtheme
                uxtheme := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
            if uxtheme {
                fn := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 133, "Ptr")
                if fn
                    DllCall(fn, "Ptr", this.gui.Hwnd, "Int", 1)
            }
        }
    }

    /**
     * Unregisters the mouse move handler and destroys popup menu handles.
     * Call before disposing the parent {@link DarkGui}.
     */
    Destroy() {
        OnMessage(0x200, this._onMouseMove, 0)
        for item in this.menuItems {
            if item.Has("popup")
                DllCall("DestroyMenu", "Ptr", item["popup"])
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

    /**
     * Creates a new dark-themed GUI window.
     * @param {String} options - Gui options
     * @param {String} title - Window title
     */
    __New(options := "", title := A_ScriptName) {
        super.__New(options, title)
        DarkTheme.AddRef()
        this.BackColor := DarkTheme.Colors["Background"]
        this.SetFont("s9", "Segoe UI")
        DarkTitleBar.Apply(this.Hwnd)
        DarkMenu.Apply()
        DarkWindowProc.Install(this.Hwnd)

        ; Win11: set title bar and border colors to match theme
        if VerCompare(A_OSVersion, "10.0.22000") >= 0 {
            bgBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Background"])
            borderBGR := DarkTheme.RGBtoBGR(DarkTheme.Colors["Border"])
            try {
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Hwnd, "UInt", 35, "UInt*", bgBGR, "Int", 4)
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Hwnd, "UInt", 36, "UInt*", 0xFFFFFF, "Int", 4)
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Hwnd, "UInt", 34, "UInt*", borderBGR, "Int", 4)
            }
        }
    }

    /**
     * Cleans up all dark mode resources for this GUI.
     * Removes subclasses from all tracked controls, clears stale entries from
     * {@link DarkWindowProc} tracking maps, and calls {@link DarkTheme.Release}.
     */
    __Delete() {
        ; Remove subclasses from all tracked dark controls
        for hwnd, ctrlType in this._darkHwnds {
            switch ctrlType {
                case "ListView": _DarkListView.Remove(hwnd)
                case "Button":   _DarkButton.Remove(hwnd)
                case "ComboBox": _DarkComboBox.Remove(hwnd)
                case "Slider":   _DarkSlider.Remove(hwnd)
                case "GroupBox": _DarkGroupBox.Remove(hwnd)
                case "Tab3":     _DarkTab.Remove(hwnd)
            }
        }
        this._darkHwnds.Clear()

        ; Clean stale entries from DarkWindowProc tracking maps
        for map in [DarkWindowProc.RadioTextControls, DarkWindowProc.MenuBarControls, DarkWindowProc.ComboDropdowns] {
            stale := []
            for hwnd, _ in map
                if !DllCall("IsWindow", "Ptr", hwnd)
                    stale.Push(hwnd)
            for hwnd in stale
                map.Delete(hwnd)
        }

        try DarkWindowProc.Uninstall(this.Hwnd)
        DarkTheme.Release()
    }

    /**
     * Adds a control with automatic dark mode styling.
     *
     * Delegates to the appropriate `_Dark*` class based on `controlType`.
     * Use `"+Accent"` in options for accent-colored buttons via {@link _DarkButton}.
     *
     * @param {String} controlType - Control type (`"Button"`, `"Edit"`, `"ListView"`, etc.).
     * @param {String} [options = ""] - Control options. Include `"+Accent"` for blue buttons.
     * @param {*} [content] - Control content (text, items array, etc.).
     * @returns {Gui.Control} The created and dark-styled control.
     */
    Add(controlType, options := "", content?) {
        isAccent := InStr(options, "+Accent")
        if isAccent
            options := StrReplace(options, "+Accent", "")

        switch controlType, false {
            case "Text":
                ; Add font color if not specified
                if !RegExMatch(options, "i)\bc[0-9A-Fa-f]+\b")
                    options .= " c" Format("{:X}", DarkTheme.Colors["Font"])
                return super.Add(controlType, options, content?)

            case "ListView":
                ; Add cWhite for text color if not specified
                if !RegExMatch(options, "i)\bc[0-9A-Fa-f]+\b|\bcWhite\b|\bcBlack\b")
                    options .= " cWhite"
                ctrl := super.Add(controlType, options, content?)
                ctrl.SetDarkMode()
                this._darkHwnds[ctrl.Hwnd] := "ListView"
                return ctrl

            case "Radio":
                return this._AddRadio(options, content?)

            case "Button":
                ctrl := super.Add(controlType, options, content?)
                ctrl.SetDarkMode(isAccent ? "accent" : "default")
                this._darkHwnds[ctrl.Hwnd] := "Button"
                return ctrl

            case "CheckBox":
                ctrl := super.Add(controlType, options, content?)
                _DarkCheckBox.ApplyDarkMode(ctrl)
                return ctrl

            case "DropDownList", "DDL":
                ctrl := super.Add(controlType, options, content?)
                DarkTheme.AllowDarkMode(ctrl.Hwnd)
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)
                ctrl.SetFont("c" Format("{:X}", DarkTheme.Colors["Font"]))
                DarkTheme.RemoveBorder(ctrl.Hwnd)
                ; Dark the dropdown list portion
                static CB_GETCOMBOBOXINFO := 0x0164
                cbi := Buffer(A_PtrSize = 8 ? 64 : 52, 0)
                NumPut("UInt", cbi.Size, cbi, 0)
                if DllCall("SendMessage", "Ptr", ctrl.Hwnd, "UInt", CB_GETCOMBOBOXINFO, "Ptr", 0, "Ptr", cbi) {
                    listHwnd := NumGet(cbi, A_PtrSize = 8 ? 56 : 44, "Ptr")
                    if listHwnd {
                        DllCall("uxtheme\SetWindowTheme", "Ptr", listHwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                        DarkWindowProc.ComboDropdowns[listHwnd] := true
                    }
                }
                return ctrl

            case "ComboBox":
                ctrl := super.Add(controlType, options, content?)
                ctrl.SetDarkMode()
                DarkTheme.RemoveBorder(ctrl.Hwnd)
                this._darkHwnds[ctrl.Hwnd] := controlType
                return ctrl

            case "Edit", "Slider", "Progress", "ListBox", "TreeView":
                ctrl := super.Add(controlType, options, content?)
                ctrl.SetDarkMode()
                if controlType = "Slider"
                    this._darkHwnds[ctrl.Hwnd] := controlType
                return ctrl

            case "GroupBox":
                ctrl := super.Add(controlType, options, content?)
                _DarkGroupBox.ApplyDarkMode(ctrl)
                this._darkHwnds[ctrl.Hwnd] := "GroupBox"
                return ctrl

            case "Tab3":
                ctrl := super.Add(controlType, options, content?)
                _DarkTab.ApplyDarkMode(ctrl)
                this._darkHwnds[ctrl.Hwnd] := "Tab3"
                return ctrl

            default:
                return super.Add(controlType, options, content?)
        }
    }

    /** Manually selects a radio and unchecks all others in its group */
    static _SelectRadio(selected, group) {
        for r in group
            r.Value := (r = selected) ? 1 : 0
    }

    /** Internal: Adds Radio with separate text control for proper dark styling */
    _AddRadio(options, text?) {
        static SM_CXMENUCHECK := 71
        static radioW := DllCall("GetSystemMetrics", "Int", SM_CXMENUCHECK)

        ; Track radio groups - new group starts with +Group or first radio
        isNewGroup := RegExMatch(options, "i)\bGroup\b") || !this.HasOwnProp("_radioGroup")
        if isNewGroup
            this._radioGroup := []
        group := this._radioGroup

        radio := super.Add("Radio", options " +0x4000000", "")
        group.Push(radio)

        ; SS_NOTIFY (0x100) enables click events on the text label
        if !InStr(options, "right")
            txt := super.Add("Text", "xp+" (radioW + 8) " yp+2 HP-4 +0x4000300 cFFFFFF", text?)
        else
            txt := super.Add("Text", "xp+8 yp+2 HP-4 +0x4000300 cFFFFFF", text?)

        DarkWindowProc.RadioTextControls[txt.Hwnd] := true

        static SWP_NOSIZE := 0x1, SWP_NOMOVE := 0x2, SWP_NOACTIVATE := 0x10
        DllCall("SetWindowPos", "Ptr", txt.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
            "UInt", SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | 0x40)

        DllCall("uxtheme\SetWindowTheme", "Ptr", radio.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

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

/** @type {DarkGui} Backward compatibility alias — `_Dark` resolves to {@link DarkGui}. */
_Dark := DarkGui

; Run standalone showcase when executed directly, skip when #Included as library
if A_LineFile = A_ScriptFullPath
    DarkModeShowcase()

class DarkModeShowcase {
    controls := Map()

    static CMD_NEW := 101, CMD_OPEN := 102, CMD_SAVE := 103, CMD_EXIT := 104
    static CMD_UNDO := 201, CMD_CUT := 202, CMD_COPY := 203, CMD_PASTE := 204
    static CMD_THEME := 301, CMD_ABOUT := 302

    __New() {
        this.gui := DarkGui("+Resize", "Modular Dark Mode System")
        this.BuildMenuBar()
        this.BuildLayout()
        this.BindEvents()
        this.gui.Show("w620 h560")
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
        viewMenu.Item("Toggle Theme", DarkModeShowcase.CMD_THEME)
        viewMenu.Sep()
        viewMenu.Item("About...",     DarkModeShowcase.CMD_ABOUT)

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
        this.controls["rad1"] := this.gui.Add("Radio", "x240 y" (y0 + 95) " w160 +Checked", "Option A")
        this.controls["rad2"] := this.gui.Add("Radio", "x240 y" (y0 + 120) " w160", "Option B")

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

        this.gui.Add("Text", "x20 y" (y0 + 200) " w200", "━ Dropdowns & Progress")
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

        this.gui.Add("Text", "x240 y" (y0 + 355) " w350", "━ TreeView")
        this.controls["tv"] := this.gui.Add("TreeView", "x240 y" (y0 + 380) " w350 h83")
        p1 := this.controls["tv"].Add("Documents")
        this.controls["tv"].Add("Report.pdf", p1)
        this.controls["tv"].Add("Notes.txt", p1)
        p2 := this.controls["tv"].Add("Images")
        this.controls["tv"].Add("Photo.jpg", p2)

        this.controls["status"] := this.gui.Add("Text", "x20 y" (y0 + 480) " w580", "Status: Ready")
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
        this.gui.OnEvent("Close", (*) => (ExitApp(), 0))
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
}
