#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; Extending the framework. DarkGui.Register(type, handler[, windowClass])
; plugs a handler into the same dispatch table the built-ins use. A handler
; is any class with Apply(owner, ctrl, options, content?) and, optionally,
; Remove(hwnd), Refresh(ctrl) and OnDestroyed(hwnd). This one themes the
; comctl32 IP-address control, which the library has no built-in for, keyed
; by its Win32 class so Add("Custom", "ClassSysIPAddress32") finds it. It
; uses the same tools the built-ins use: Subclass for the window procedure,
; DarkWindowProc.CtlColorReply for the WM_CTLCOLOR answer, DarkTheme brushes
; and colours for painting, so it follows every palette swap for free.

class DarkIPAddress {
    static Apply(owner, ctrl, options := "", content?) {
        DarkTheme.AllowDarkMode(ctrl.Hwnd)
        DarkTheme.RemoveBorder(ctrl.Hwnd)
        ; The four fields are child Edits of the control itself, so their
        ; WM_CTLCOLOREDIT goes to the control rather than to the DarkGui
        ; window. A subclass answers it and paints the frame and the dots.
        Subclass.InstallProc(this, ctrl.Hwnd, "Proc")
        for hField in this.Fields(ctrl.Hwnd) {
            DarkTheme.AllowDarkMode(hField)
            DllCall("uxtheme\SetWindowTheme", "Ptr", hField, "Str", "DarkMode_Explorer", "Ptr", 0)
        }
        DllCall("InvalidateRect", "Ptr", ctrl.Hwnd, "Ptr", 0, "Int", 1, "Void")
    }

    static Remove(hwnd) {
        Subclass.Uninstall(this, hwnd)
    }

    ; The field Edits, left to right.
    static Fields(hwnd) {
        static GW_CHILD := 5, GW_HWNDNEXT := 2
        found := []
        h := DllCall("GetWindow", "Ptr", hwnd, "UInt", GW_CHILD, "Ptr")
        while h {
            rc := DM_RECT()
            DllCall("GetWindowRect", "Ptr", h, "Ptr", rc)
            pos := found.Length + 1
            while pos > 1 && found[pos - 1].left > rc.left
                pos--
            found.InsertAt(pos, { hwnd: h, left: rc.left })
            h := DllCall("GetWindow", "Ptr", h, "UInt", GW_HWNDNEXT, "Ptr")
        }
        list := []
        for f in found
            list.Push(f.hwnd)
        return list
    }

    static Proc(targetHwnd, hwnd, msg, wParam, lParam) {
        static WM_PAINT := 0x000F, WM_ERASEBKGND := 0x0014, WM_CTLCOLOREDIT := 0x0133
        switch msg {
            case WM_CTLCOLOREDIT: return DarkWindowProc.CtlColorReply(wParam, "Font", "Controls")
            case WM_ERASEBKGND:   return 1
            case WM_PAINT:
                this.Paint(hwnd)
                return 0
        }
        return Subclass.Forward(hwnd, msg, wParam, lParam)
    }

    ; Fill with Controls, outline with Border, draw a dot between each pair of fields.
    static Paint(hwnd) {
        static WM_GETFONT := 0x0031, TRANSPARENT := 1
        static DT_CENTER := 0x1, DT_VCENTER := 0x4, DT_SINGLELINE := 0x20
        ps := DM_PAINTSTRUCT()
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
        rc := DM_RECT()
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        DllCall("FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Controls"))
        DllCall("FrameRect", "Ptr", hdc, "Ptr", rc, "Ptr", DarkTheme.GetBrush("Border"))
        hFont := SendMessage(WM_GETFONT, 0, 0, hwnd)
        oldFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
        DllCall("SetBkMode", "Ptr", hdc, "Int", TRANSPARENT)
        DllCall("SetTextColor", "Ptr", hdc, "UInt", DarkTheme.RGBtoBGR(DarkTheme.Colors["Font"]))
        fields := this.Fields(hwnd)
        gap := DM_RECT()
        gap.top := rc.top
        gap.bottom := rc.bottom
        loop fields.Length - 1 {
            gap.left := this.ClientX(hwnd, fields[A_Index], true)
            gap.right := this.ClientX(hwnd, fields[A_Index + 1], false)
            DllCall("DrawTextW", "Ptr", hdc, "Str", ".", "Int", 1, "Ptr", gap, "UInt", DT_CENTER | DT_VCENTER | DT_SINGLELINE)
        }
        DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont, "Ptr")
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)
    }

    ; A field's right (or left) edge in the control's client coordinates.
    static ClientX(hwnd, hField, rightEdge) {
        rc := DM_RECT()
        DllCall("GetWindowRect", "Ptr", hField, "Ptr", rc)
        pt := DM_POINT()
        pt.x := rightEdge ? rc.right : rc.left
        pt.y := rc.top
        DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", pt)
        return pt.x
    }
}

; ICC_INTERNET_CLASSES registers SysIPAddress32.
icc := Buffer(8)
NumPut("UInt", 8, "UInt", 0x800, icc)
DllCall("comctl32\InitCommonControlsEx", "Ptr", icc)
DarkGui.Register("Custom", DarkIPAddress, "SysIPAddress32")

app := DarkGui("+Resize", "Custom control handler")
app.SetFont("s10", "Segoe UI")
app.Add("Text", "x16 y16 w360", "SysIPAddress32 through a registered handler:")
ip := app.Add("Custom", "ClassSysIPAddress32 x16 y44 w220 h26")
SendMessage(0x0465, 0, (192 << 24) | (168 << 16) | (1 << 8) | 10, ip)
app.Add("Button", "+Accent x244 y42 w132 h30", "Read address").OnEvent("Click", ReadAddress)
app.Add("Text", "x16 y84 w120 h26 +0x200", "Preset")
presets := app.Add("DropDownList", "x140 y84 w236 Choose1", ["Default", "OLED", "Slate", "Blue", "Light"])
presets.OnEvent("Change", (*) => (DarkTheme.ApplyPreset(presets.Text), 0))
status := app.Add("StatusBar", , DarkGui.Handlers.Count " handlers registered")
app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w392")

ReadAddress(*) {
    addr := Buffer(4, 0)
    SendMessage(0x0466, 0, addr.Ptr, ip)
    v := NumGet(addr, 0, "UInt")
    status.Text := Format("{}.{}.{}.{}", (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
}
