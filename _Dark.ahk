#Requires AutoHotkey v2.1-alpha.16
#SingleInstance Force

DarkApp()

class DarkApp {
    __New() {
        this.InitializeGui()
        this.SetupControls()
        this.SetupEvents()
    }

    InitializeGui() {
        this.gui := _Dark("+Resize", "Dark")
        this.gui.SetFont("s10 cffffff", "Segoe UI")

        this.gui.AddText("y15 x15 w300", "Basic Controls")
        this.checkbox := this.gui.AddCheckBox("y+10 x15 w250", "Enable feature")
        this.listView := this.gui.AddListView("y+10 x15 w300 h120", ["Item", "Value"])
        this.actionButton := this.gui.AddButton("y+10 x15 w120", "Run Action")
        this.edit := this.gui.AddEdit("y+10 x15 w200 h24", "Sample text input")
        this.comboBox := this.gui.AddComboBox("y+10 x15 w200", ["Option 1", "Option 2", "Option 3"])

        this.gui.AddText("y+20 x15 w300", "Advanced Controls")
        this.groupBox := this.gui.AddGroupBox("y+10 x15 w300 h80", "Group Settings")
        this.radio1 := this.gui.AddRadio("xp+15 yp+25 w250", "Option A")
        this.radio2 := this.gui.AddRadio("xp y+10 w250", "Option B")

        this.gui.AddText("y+20 x15 w300", "Enhanced Controls")
        this.slider := this.gui.AddSlider("y+10 x15 w200 h30 Range0-100", 50)
        this.progress := this.gui.AddProgress("y+15 x15 w200 h20", 50)
        this.dateTime := this.gui.AddDateTime("y+15 x15 w200")
        this.tabs := this.gui.AddTab("y+15 x15 w300 h150", ["Tab 1", "Tab 2", "Tab 3"])

        this.gui.Tab := 1
        this.gui.AddText("y+10 x25 w280", "Content for Tab 1")
        this.gui.AddEdit("y+10 x25 w280 h80", "Tab 1 content area")

        this.gui.Tab := 2
        this.gui.AddText("y+10 x25 w280", "Content for Tab 2")
        this.gui.AddButton("y+10 x25 w100", "Tab 2 Button")

        this.gui.Tab := 3
        this.gui.AddText("y+10 x25 w280", "Content for Tab 3")
        this.gui.AddListBox("y+10 x25 w200 h80", ["List Item 1", "List Item 2", "List Item 3"])

        this.gui.Tab := ""


        this.gui.AddText("y+20 x15 w300", "Theme Settings")
        this.themeSelector := this.gui.AddComboBox("y+10 x15 w200", ["Dark Blue", "Dark Gray", "Dark Green", "Dark Purple"])
        this.gui.Show()
    }

    SetupControls() {
        this.listView.Add(, "Item 1", "Value 1")
        this.listView.Add(, "Item 2", "Value 2")
        this.listView.Add(, "Item 3", "Value 3")
    }

    SetupEvents() {
        this.actionButton.OnEvent("Click", this.ButtonClicked.Bind(this))
        this.slider.OnEvent("Change", this.SliderChanged.Bind(this))
        this.themeSelector.OnEvent("Change", this.ThemeChanged.Bind(this))
    }

    ButtonClicked(*) {
        MsgBox("Button clicked!")
    }

    SliderChanged(*) {
        this.progress.Value := this.slider.Value
    }

    ThemeChanged(*) {
        themeIndex := this.themeSelector.Value
        themes := Map(
            "Dark Blue", Map("Background", 0x1A1A2E, "Controls", 0x16213E, "Font", 0xE0E0E0),
            "Dark Gray", Map("Background", 0x171717, "Controls", 0x1E1E1E, "Font", 0xE0E0E0),
            "Dark Green", Map("Background", 0x0A2A12, "Controls", 0x103619, "Font", 0xE0E0E0),
            "Dark Purple", Map("Background", 0x240041, "Controls", 0x3C096C, "Font", 0xE0E0E0)
        )

        selected := themes[this.themeSelector.Text]
        if selected
            _DarkC.SetTheme(selected)
    }
}

class _Dark extends Gui {
    Static OriginalWindowProc := 0

    Static __New() {
    }

    __New(Options := "", Title := A_ScriptName, EventObj?) {
        super.__New(Options, Title, EventObj ?? this)

        this.BackColor := _DarkC.Theme["Background"]

        if (VerCompare(A_OSVersion, "10.0.17763") >= 0) {
            DWMWA_USE_IMMERSIVE_DARK_MODE := 19
            if (VerCompare(A_OSVersion, "10.0.18985") >= 0)
                DWMWA_USE_IMMERSIVE_DARK_MODE := 20

            uxtheme := DllCall("kernel32\GetModuleHandle", "Str", "uxtheme", "Ptr")
            SetPreferredAppMode := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
            FlushMenuThemes := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")

            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.hWnd,
                "Int", DWMWA_USE_IMMERSIVE_DARK_MODE, "Int*", true, "Int", 4)
            DllCall(SetPreferredAppMode, "Int", 2)
            DllCall(FlushMenuThemes)
        }

        this.SetDarkMenu()

        if (!_Dark.OriginalWindowProc) {
            _Dark.OriginalWindowProc := DllCall("GetWindowLongPtr", "Ptr", this.Hwnd, "Int", -4, "Ptr")
            WindowProc := CallbackCreate(_DarkC.ProcessWindowMessage, "Fast")
            DllCall("SetWindowLongPtr", "Ptr", this.Hwnd, "Int", -4, "Ptr", WindowProc)
        }
    }

    Show(Options := "") {
        result := super.Show(Options)
        DllCall("RedrawWindow", "Ptr", this.Hwnd, "Ptr", 0, "Ptr", 0,
            "UInt", 0x0287)

        return result
    }

    SetDarkMenu() {
        uxtheme := DllCall("GetModuleHandle", "Ptr", StrPtr("uxtheme"), "Ptr")
        SetPreferredAppMode := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
        FlushMenuThemes := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")
        DllCall(SetPreferredAppMode, "Int", 1)
        DllCall(FlushMenuThemes)
    }

    SetWindowAttribute(dwAttribute, pvAttribute?) {
        return DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Hwnd, "Uint", dwAttribute, "Uint*", pvAttribute, "Int", 4)
    }

    CreateStructs() {
        RECT := Map(
            "left", 0,
            "top", 0,
            "right", 0,
            "bottom", 0
        )

        NMHDR := Map(
            "hwndFrom", 0,
            "idFrom", 0,
            "code", 0
        )

        NMCUSTOMDRAW := Map(
            "hdr", NMHDR,
            "dwDrawStage", 0,
            "hdc", 0,
            "rc", RECT,
            "dwItemSpec", 0,
            "uItemState", 0,
            "lItemlParam", 0
        )

        ProcessCustomDraw(lParam) {

            NMCD := CreateStructs()
            NMCD["hdr"]["hwndFrom"] := NumGet(lParam, 0, "Ptr")
            NMCD["hdr"]["idFrom"] := NumGet(lParam, A_PtrSize, "Ptr")
            NMCD["hdr"]["code"] := NumGet(lParam, A_PtrSize * 2, "UInt")

            rectOffset := A_PtrSize * 2 + 4 + A_PtrSize
            NMCD["rc"]["left"] := NumGet(lParam, rectOffset, "Int")
            NMCD["rc"]["top"] := NumGet(lParam, rectOffset + 4, "Int")
            NMCD["rc"]["right"] := NumGet(lParam, rectOffset + 8, "Int")
            NMCD["rc"]["bottom"] := NumGet(lParam, rectOffset + 12, "Int")

            dwItemSpecOffset := rectOffset + 16
            NMCD["dwItemSpec"] := NumGet(lParam, dwItemSpecOffset, "UPtr")
            NMCD["uItemState"] := NumGet(lParam, dwItemSpecOffset + A_PtrSize, "UInt")
            NMCD["lItemlParam"] := NumGet(lParam, dwItemSpecOffset + A_PtrSize + 4, "Ptr")
            return NMCD
        }
        return NMCUSTOMDRAW
    }
}

class _DarkCtl extends Gui.Control {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }
    ApplyDarkTheme() {
    }
    Redraw() {
        DllCall("InvalidateRect", "Ptr", this.hwnd, "Ptr", 0, "Int", true)
    }
}

class _Text extends Gui.Text {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        this.Opt("c" . Format("{:X}", _DarkC.Theme["Font"]))
        this.Redraw()
    }
}

class _Button extends Gui.Button {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.ButtonColors[this.Hwnd] := Map(
            "bg", _DarkC.Theme["Controls"],
            "text", _DarkC.Theme["Font"]
        )
        this.Redraw()
    }
}

class _Edit extends Gui.Edit {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        this.Redraw()
    }
}

class _ListView extends Gui.ListView {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

ApplyDarkTheme() {
    static LVM_SETTEXTCOLOR := 0x1033
    static LVM_SETBKCOLOR := 0x1001
    static LVM_SETTEXTBKCOLOR := 0x1026
    static LVM_GETHEADER := 0x101F

    SendMessage(LVM_SETTEXTCOLOR, 0, _DarkC.Theme["Font"], this.Hwnd)
    SendMessage(LVM_SETBKCOLOR, 0, _DarkC.Theme["Background"], this.Hwnd)
    SendMessage(LVM_SETTEXTBKCOLOR, 0, _DarkC.Theme["Background"], this.Hwnd)

    this.Opt("+Grid +LV0x10000")

    this.Header := SendMessage(LVM_GETHEADER, 0, 0, this.Hwnd)

    DllCall("uxtheme\SetWindowTheme", "Ptr", this.Header, "Str", "DarkMode_ItemsView", "Ptr", 0)
    DllCall("uxtheme\SetWindowTheme", "Ptr", this.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

    this.SetupCustomDraw()
    this.Redraw()
}

SetupCustomDraw() {
    static NM_CUSTOMDRAW := -12
    static CDDS_PREPAINT := 0x1
    static CDDS_ITEMPREPAINT := 0x10001
    static CDRF_NOTIFYITEMDRAW := 0x20
    static CDRF_NEWFONT := 0x2

    LV_CustomDraw(ctrl, lParam) {
        code := NumGet(lParam, A_PtrSize*2, "Int")
        if (code != NM_CUSTOMDRAW)
            return
        dwDrawStage := NumGet(lParam, A_PtrSize*3, "UInt")
        if (dwDrawStage == CDDS_PREPAINT)
            return CDRF_NOTIFYITEMDRAW
        if (dwDrawStage == CDDS_ITEMPREPAINT) {
            hdc := NumGet(lParam, A_PtrSize*3 + 4, "UPtr")
            DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", _DarkC.Theme["Font"])
            DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", 1)
            return CDRF_NEWFONT
        }
        return 0
    }

    HDR_CustomDraw(ctrl, lParam) {
        code := NumGet(lParam, A_PtrSize*2, "Int")
        if (code != NM_CUSTOMDRAW)
            return
        dwDrawStage := NumGet(lParam, A_PtrSize*3, "UInt")
        if (dwDrawStage == CDDS_PREPAINT)
            return CDRF_NOTIFYITEMDRAW
        if (dwDrawStage == CDDS_ITEMPREPAINT) {
            hdc := NumGet(lParam, A_PtrSize*3 + 4, "UPtr")
            DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", _DarkC.Theme["Font"])
            DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", 1)
            return CDRF_NEWFONT
        }
        return 0
    }

    this.OnNotify(NM_CUSTOMDRAW, LV_CustomDraw)
    this.OnNotify(NM_CUSTOMDRAW, HDR_CustomDraw, this.Header)
}
}

class _ComboBox extends Gui.ComboBox {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_CFD", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.ComboBoxes[this.Hwnd] := true
        this.Redraw()
    }
}

class _CheckBox extends Gui.CheckBox {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.ButtonColors[this.Hwnd] := Map(
            "bg", _DarkC.Theme["Background"],
            "text", _DarkC.Theme["Font"]
        )
        this.Redraw()
    }
}

class _Radio extends Gui.Radio {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.ButtonColors[this.Hwnd] := Map(
            "bg", _DarkC.Theme["Background"],
            "text", _DarkC.Theme["Font"]
        )
        _DarkC.RadioButtons[this.Hwnd] := true
        this.Redraw()
    }
}

class _GroupBox extends Gui.GroupBox {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ; Helper method to create a rectangle buffer
    Static BufferFromRect(left, top, right, bottom) {
        rect := Buffer(16, 0)
        NumPut("Int", left, rect, 0)
        NumPut("Int", top, rect, 4)
        NumPut("Int", right, rect, 8)
        NumPut("Int", bottom, rect, 12)
        return rect
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.GroupBoxes[this.Hwnd] := true

        this.ApplyCustomBorder()
        this.Redraw()
    }

    ApplyCustomBorder() {
        static WM_PAINT := 0x000F
        static callbacks := Map()

        ; Remove previous callback if it exists
        if callbacks.Has(this.Hwnd)
            OnMessage(WM_PAINT, callbacks[this.Hwnd], 0)

        ; Create new callback with appropriate parameters
        callback := this.PaintGroupBox.Bind(this)
        callbacks[this.Hwnd] := callback

        ; Register the callback for WM_PAINT
        OnMessage(WM_PAINT, callback, this.Hwnd)
    }

    PaintGroupBox(wParam, lParam, msg, hwnd) {
        static DT_CALCRECT := 0x00000400
        static DT_SINGLELINE := 0x00000020
        static DT_LEFT := 0x00000000
        static PS_SOLID := 0

        ; Skip if this isn't our control
        if (hwnd != this.Hwnd)
            return

        ; Begin painting
        ps := Buffer(8 + A_PtrSize * 6, 0)
        hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")

        ; Get client rectangle
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)

        ; Create pen for border
        borderColor := _DarkC.Theme["Font"]
        hPen := DllCall("CreatePen", "Int", PS_SOLID, "Int", 1, "UInt", borderColor, "Ptr")
        DllCall("SelectObject", "Ptr", hdc, "Ptr", hPen)

        ; Set text color and background
        DllCall("SetTextColor", "Ptr", hdc, "UInt", _DarkC.Theme["Font"])
        DllCall("SetBkColor", "Ptr", hdc, "UInt", _DarkC.Theme["Background"])
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1) ; TRANSPARENT

        ; Calculate text size
        textRect := Buffer(16, 0)
        DllCall("DrawText", "Ptr", hdc, "Str", this.Text, "Int", -1, "Ptr", textRect, "UInt", DT_CALCRECT)
        textWidth := NumGet(textRect, 8, "Int") - NumGet(textRect, 0, "Int")
        textHeight := NumGet(textRect, 12, "Int") - NumGet(textRect, 4, "Int")

        ; Draw the frame but leave space for text
        padding := 8
        left := NumGet(rect, 0, "Int")
        top := NumGet(rect, 4, "Int") + textHeight / 2
        right := NumGet(rect, 8, "Int")
        bottom := NumGet(rect, 12, "Int")

        ; Draw the frame in segments, leaving space for text
        DllCall("MoveToEx", "Ptr", hdc, "Int", left, "Int", top, "Ptr", 0)
        DllCall("LineTo", "Ptr", hdc, "Int", left, "Int", bottom - 1)
        DllCall("LineTo", "Ptr", hdc, "Int", right - 1, "Int", bottom - 1)
        DllCall("LineTo", "Ptr", hdc, "Int", right - 1, "Int", top)
        DllCall("LineTo", "Ptr", hdc, "Int", left + padding + textWidth + padding, "Int", top)

        ; Draw the text
        textX := left + padding
        textY := NumGet(rect, 4, "Int")
        textRect := _GroupBox.BufferFromRect(textX, textY, textX + textWidth, textY + textHeight)
        DllCall("DrawText", "Ptr", hdc, "Str", this.Text, "Int", -1,
            "Ptr", textRect,
            "UInt", DT_LEFT | DT_SINGLELINE)

        ; Clean up
        DllCall("DeleteObject", "Ptr", hPen)
        DllCall("EndPaint", "Ptr", hwnd, "Ptr", ps)

        return true
    }
}

class _ListBox extends Gui.ListBox {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.ListBoxControls[this.Hwnd] := true
        this.Redraw()
    }
}

class _Slider extends Gui.Slider {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        _DarkC.SliderControls[this.Hwnd] := true
        this.Redraw()
    }
}

class _Progress extends Gui.Progress {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        _DarkC.ProgressControls[this.Hwnd] := true
        this.Redraw()
    }
}

class _DateTime extends Gui.DateTime {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.DateTimeControls[this.Hwnd] := true
        this.Redraw()
    }
}

class _Tab extends Gui.Tab {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    ApplyDarkTheme() {
        DllCall("uxtheme\SetWindowTheme", "Ptr", this.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        this.SetFont("c" . Format("{:X}", _DarkC.Theme["Font"]))
        _DarkC.TabControls[this.Hwnd] := true
        this.Redraw()
    }
}

class _DarkC {
    Static ButtonColors := Map()
    Static ComboBoxes := Map()
    Static ListViewHeaders := Map()
    Static CheckboxTextControls := Map()
    Static TextControls := Map()
    Static DarkCheckboxPairs := Map()
    Static GroupBoxes := Map()
    Static RadioButtons := Map()
    Static SliderControls := Map()
    Static ProgressControls := Map()
    Static DateTimeControls := Map()
    Static TabControls := Map()
    Static ListBoxControls := Map()

    Static Theme := Map(
        "Background", 0x171717,
        "Controls", 0x1b1b1b,
        "ComboBoxBg", 0x1E1E1E,
        "Font", 0xE0E0E0,
        "SliderThumb", 0x3E3E3E,
        "SliderTrack", 0x2D2D2D,
        "ProgressFill", 0x0078D7
    )

    Static WM_CTLCOLOREDIT := 0x0133
    Static WM_CTLCOLORLISTBOX := 0x0134
    Static WM_CTLCOLORBTN := 0x0135
    Static WM_CTLCOLORSTATIC := 0x0138
    Static WM_ERASEBKGND := 0x0014
    Static DC_BRUSH := 18

    Static TextBackgroundBrush := 0
    Static ControlsBackgroundBrush := 0

    Static __New() {
        _DarkCtl.__New()

        _Text.__New()
        _Button.__New()
        _Edit.__New()
        _ListView.__New()
        _ComboBox.__New()
        _CheckBox.__New()
        _Radio.__New()
        _GroupBox.__New()
        _ListBox.__New()
        _Slider.__New()
        _Progress.__New()
        _DateTime.__New()
        _Tab.__New()

        this.TextBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", this.Theme["Background"], "Ptr")
        this.ControlsBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", this.Theme["Controls"], "Ptr")
    }

    Static SetTheme(themeColors) {
        if (themeColors.Has("Background"))
            this.Theme["Background"] := themeColors["Background"]

        if (themeColors.Has("Controls"))
            this.Theme["Controls"] := themeColors["Controls"]

        if (themeColors.Has("Font"))
            this.Theme["Font"] := themeColors["Font"]

        if (themeColors.Has("ComboBoxBg"))
            this.Theme["ComboBoxBg"] := themeColors["ComboBoxBg"]
        else
            this.Theme["ComboBoxBg"] := this.Theme["Controls"]

        if (themeColors.Has("SliderThumb"))
            this.Theme["SliderThumb"] := themeColors["SliderThumb"]
        else
            this.Theme["SliderThumb"] := this.Theme["Controls"]

        if (themeColors.Has("SliderTrack"))
            this.Theme["SliderTrack"] := themeColors["SliderTrack"]
        else
            this.Theme["SliderTrack"] := this.Theme["Background"]

        if (themeColors.Has("ProgressFill"))
            this.Theme["ProgressFill"] := themeColors["ProgressFill"]

        if (this.TextBackgroundBrush) {
            DllCall("DeleteObject", "Ptr", this.TextBackgroundBrush)
            this.TextBackgroundBrush := 0
        }

        if (this.ControlsBackgroundBrush) {
            DllCall("DeleteObject", "Ptr", this.ControlsBackgroundBrush)
            this.ControlsBackgroundBrush := 0
        }

        this.TextBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", this.Theme["Background"], "Ptr")
        this.ControlsBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", this.Theme["Controls"], "Ptr")

        for hwnd, gui in Gui.Prototype.GUIs {
            try {
                gui.BackColor := this.Theme["Background"]

                for ctlHwnd, control in gui {
                    try {
                        if HasMethod(control, "ApplyDarkTheme")
                            control.ApplyDarkTheme()
                    }
                }

                DllCall("RedrawWindow", "Ptr", gui.Hwnd, "Ptr", 0, "Ptr", 0,
                    "UInt", 0x0287)
            }
        }
    }


    Static IsComboBoxListBox(hwnd) {
        parent := DllCall("GetParent", "Ptr", hwnd, "Ptr")
        if !parent
            return false

        className := Buffer(64)
        if !DllCall("GetClassName", "Ptr", parent, "Ptr", className, "Int", 32)
            return false

        return StrGet(className) == "ComboBox"
    }

    Static ProcessWindowMessage(hwnd, uMsg, wParam, lParam) {
        switch uMsg {
            case _DarkC.WM_ERASEBKGND:
                ; Handle background erasing properly
                dc := wParam
                rect := Buffer(16, 0)
                DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
                DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", _DarkC.TextBackgroundBrush)
                return 1

            case _DarkC.WM_CTLCOLOREDIT, _DarkC.WM_CTLCOLORLISTBOX:
                ; Handle edit controls and listboxes
                if (_DarkC.ComboBoxes.Has(lParam) || _DarkC.IsComboBoxListBox(lParam)) {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _DarkC.Theme["Font"])
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _DarkC.Theme["ComboBoxBg"])
                    return _DarkC.ControlsBackgroundBrush  ; Return our brush instead of stock one
                } else {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _DarkC.Theme["Font"])
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _DarkC.Theme["Controls"])
                    return _DarkC.ControlsBackgroundBrush  ; Return our brush instead of stock one
                }

            case _DarkC.WM_CTLCOLORBTN:
                ; NEW - Add specific button handling
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _DarkC.Theme["Font"])
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _DarkC.Theme["Controls"])
                return _DarkC.ControlsBackgroundBrush

            case _DarkC.WM_CTLCOLORSTATIC:
                if (_DarkC.GroupBoxes.Has(lParam) || _DarkC.RadioButtons.Has(lParam)) {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _DarkC.Theme["Font"])
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _DarkC.Theme["Background"])
                    return _DarkC.TextBackgroundBrush
                } else {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _DarkC.Theme["Font"])
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _DarkC.Theme["Background"])
                    return _DarkC.TextBackgroundBrush
                }
        }

        return DllCall("CallWindowProc", "Ptr", _Dark.OriginalWindowProc, "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam)
    }
}

class _DarkControlExt extends Gui.Control {
    Static __New() {
        For p in this.Prototype.OwnProps()
            if (p != "__Class")
                super.Prototype.DefineProp(p, this.Prototype.GetOwnPropDesc(p))
    }

    Destroy() => DllCall("DestroyWindow", "UPtr", this.hwnd)

    ExStyle {
        get => ControlGetExStyle(this.hwnd)
        set => ControlSetExStyle(Value, this.hwnd)
    }

    Style {
        get => ControlGetStyle(this.hwnd)
        set => ControlSetStyle(Value, this.hwnd)
    }

    Redraw() {
        DllCall("InvalidateRect", "Ptr", this.hwnd, "Ptr", 0, "Int", true)
    }
}
