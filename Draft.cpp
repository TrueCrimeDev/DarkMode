#Requires AutoHotkey v2.1-alpha.16
#SingleInstance Force

Hey := "Its CPP for the highlighting"

global DarkColors := Map(
    "Background", 0x171717, 
    "Controls", 0x202020, 
    "Font", 0xFFFFFF
)

DemoApp()

class DemoApp {
    __New() {
        this.settings := Map(
            "RadialMenu", Map(
                "HotKey1", "!Capslock",
                "HotKey2", "#Capslock",
                "EnableAdvanced", true
            ),
            "Interface", Map(
                "DarkMode", true,
                "Language", "English"
            )
        )
        
        this.CreateGui()
        this.SetupControls()
        this.gui.Show()
    }
    
    CreateGui() {
        Gui.Prototype.DefineProp("AddDarkCheckBox", {Call: AddDarkCheckBox})
        
        this.gui := Gui("+Resize +AlwaysOnTop", "Task Manager")
        this.gui.SetFont("s10", "Segoe UI")
        
        this.gui.AddText("y15 x15", "Name:")
        this.nameEdit := this.gui.AddEdit("w300 x15")
        
        this.gui.AddText("y+10 x15", "Priority:")
        this.priority := this.gui.AddDropDownList("w300 Choose1", ["High", "Medium", "Low"])
        
        this.gui.AddText("y+20 x15 w300", "Hotkey Configuration")
        this.gui.AddText("y+10 x15", "Radial Menu 1:")
        this.radialHK1 := this.gui.AddComboBox("w300 x15", 
            ["!Capslock", "#Capslock", "^Capslock", "+Capslock", "!Space", "^Space"])
        
        this.gui.AddText("y+10 x15", "Radial Menu 2:")
        this.radialHK2 := this.gui.AddComboBox("w300 x15", 
            ["#Capslock", "!Capslock", "^Capslock", "+Capslock", "!Space", "^Space"])
        
        this.showComplete := this.gui.AddDarkCheckBox("y+15 x15 w300", "Show completed tasks")
        this.enableAdvanced := this.gui.AddDarkCheckBox("y+10 x15 w300", "Enable advanced features")
        
        this.gui.AddText("y+15 x15", "Language:")
        this.language := this.gui.AddDropDownList("w300 x15 Choose1", ["English", "Dutch", "German", "French"])
        
        saveBtn := this.gui.AddButton("y+20 w145 x15", "Save")
        clearBtn := this.gui.AddButton("x+10 w145", "Clear")
        
        this.listView := this.gui.AddListView("y+20 x15 w300 h200", ["Name", "Priority"])
        
        _Dark(this.gui)
        
        saveBtn.OnEvent("Click", this.SaveTask.Bind(this))
        clearBtn.OnEvent("Click", this.ClearFields.Bind(this))
        
        this.SetupHotkeys()
    }
    
    SetupControls() {
        this.radialHK1.Text := this.settings["RadialMenu"]["HotKey1"]
        this.radialHK2.Text := this.settings["RadialMenu"]["HotKey2"]
        this.enableAdvanced.Value := this.settings["RadialMenu"]["EnableAdvanced"] ? 1 : 0
        this.language.Choose(this.settings["Interface"]["Language"])
        
        this.radialHK1.OnEvent("Change", this.UpdateSettings.Bind(this))
        this.radialHK2.OnEvent("Change", this.UpdateSettings.Bind(this))
        this.enableAdvanced.OnEvent("Click", this.UpdateSettings.Bind(this))
        this.language.OnEvent("Change", this.UpdateSettings.Bind(this))
    }
    
    UpdateSettings(*) {
        this.settings["RadialMenu"]["HotKey1"] := this.radialHK1.Text
        this.settings["RadialMenu"]["HotKey2"] := this.radialHK2.Text
        this.settings["RadialMenu"]["EnableAdvanced"] := this.enableAdvanced.Value = 1
        this.settings["Interface"]["Language"] := this.language.Text
        
        ; Show a notification to demonstrate the change
        ToolTip("Settings updated: " . this.radialHK1.Text . " / " . this.radialHK2.Text)
        SetTimer () => ToolTip(), -2000
    }
    
    SetupHotkeys() {
        HotIfWinActive("ahk_id " this.gui.Hwnd)
        Hotkey("Escape", (*) => this.gui.Hide())
        HotIfWinActive()
        
        Hotkey("^r", (*) => this.Reset())
    }
    
    SaveTask(*) {
        if (this.nameEdit.Value = "")
            return
        this.listView.Add(, this.nameEdit.Value, this.priority.Text)
        this.ClearFields()
    }
    
    ClearFields(*) {
        this.nameEdit.Value := ""
        this.priority.Value := 1
    }
    
    Reset(*) {
        this.ClearFields()
        this.radialHK1.Text := "!Capslock"
        this.radialHK2.Text := "#Capslock"
        this.enableAdvanced.Value := 1
        this.showComplete.Value := 0
        this.language.Choose("English")
        this.UpdateSettings()
    }
    
    SaveSettings(path := "settings.ini") {
        try {
            ; Save RadialMenu settings
            for key, value in this.settings["RadialMenu"]
                IniWrite(value, path, "RadialMenu", key)
                
            ; Save Interface settings
            for key, value in this.settings["Interface"]
                IniWrite(value, path, "Interface", key)
                
            ToolTip("Settings saved to " path)
            SetTimer () => ToolTip(), -2000
        }
        catch as e {
            MsgBox("Error saving settings: " e.Message)
        }
    }
    
    LoadSettings(path := "settings.ini") {
        if (!FileExist(path))
            return
            
        try {
            ; Load RadialMenu settings
            this.settings["RadialMenu"]["HotKey1"] := IniRead(path, "RadialMenu", "HotKey1", "!Capslock")
            this.settings["RadialMenu"]["HotKey2"] := IniRead(path, "RadialMenu", "HotKey2", "#Capslock")
            this.settings["RadialMenu"]["EnableAdvanced"] := IniRead(path, "RadialMenu", "EnableAdvanced", "true") = "true"
            
            ; Load Interface settings
            this.settings["Interface"]["DarkMode"] := IniRead(path, "Interface", "DarkMode", "true") = "true"
            this.settings["Interface"]["Language"] := IniRead(path, "Interface", "Language", "English")
            
            ; Update controls with loaded settings
            this.SetupControls()
            
            ToolTip("Settings loaded from " path)
            SetTimer () => ToolTip(), -2000
        }
        catch as e {
            MsgBox("Error loading settings: " e.Message)
        }
    }
}

class _Dark {
    static __New() {
        global DarkModeGUI_WindowProc := (hwnd, uMsg, wParam, lParam) => 
            _Dark.ProcessWindowMessage(hwnd, uMsg, wParam, lParam)
    }
    
    static Instances := Map()
    static WindowProcOldMap := Map()
    static WindowProcCallbacks := Map()
    static TextBackgroundBrush := 0
    static ButtonColors := Map()
    static ComboBoxes := Map()
    static ListViewHeaders := Map()
    
    static Dark := Map(
        "Background", 0x171717,
        "Controls", 0x1b1b1b, 
        "ComboBoxBg", 0x1E1E1E,
        "Font", 0xE0E0E0
    )
    
    static WM_CTLCOLOREDIT := 0x0133
    static WM_CTLCOLORLISTBOX := 0x0134
    static WM_CTLCOLORBTN := 0x0135
    static WM_CTLCOLORSTATIC := 0x0138
    static WM_NOTIFY := 0x004E
    static NM_CUSTOMDRAW := -12
    static HDN_FIRST := -300
    static HDN_CUSTOMDRAW := -312
    static CDDS_PREPAINT := 0x00000001
    static CDDS_ITEMPREPAINT := 0x00010001
    static CDRF_NEWFONT := 0x00000002
    static CDRF_NOTIFYITEMDRAW := 0x00000020
    static DC_BRUSH := 18
    static GWL_WNDPROC := -4
    static GWL_STYLE := -16
    
    static GetWindowLong := A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong"
    static SetWindowLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"
    
    Gui := ""
    
    __New(GuiObj) {
        if (!_Dark.TextBackgroundBrush)
            _Dark.TextBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", _Dark.Dark["Background"], "Ptr")
        
        this.Gui := GuiObj
        this.SetWindowDarkMode()
        this.SetControlsTheme()
        this.SetupWindowProc()
    }
    
    SetWindowDarkMode() {
        this.Gui.BackColor := _Dark.Dark["Background"]
        
        if (VerCompare(A_OSVersion, "10.0.17763") >= 0) {
            DWMWA_USE_IMMERSIVE_DARK_MODE := 19
            if (VerCompare(A_OSVersion, "10.0.18985") >= 0)
                DWMWA_USE_IMMERSIVE_DARK_MODE := 20
            
            uxtheme := DllCall("kernel32\GetModuleHandle", "Str", "uxtheme", "Ptr")
            SetPreferredAppMode := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
            FlushMenuThemes := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")
            
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Gui.hWnd, 
                   "Int", DWMWA_USE_IMMERSIVE_DARK_MODE, "Int*", true, "Int", 4)
            DllCall(SetPreferredAppMode, "Int", 2)
            DllCall(FlushMenuThemes)
        }
    }
    
    SetControlsTheme() {
        for hWnd, GuiCtrlObj in this.Gui {
            switch GuiCtrlObj.Type {
                case "Button", "CheckBox", "Radio", "ListBox", "UpDown":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                
                case "ComboBox", "DDL":
                    _Dark.ComboBoxes[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_CFD", "Ptr", 0)
                    try {
                        DllCall("uxtheme\SetWindowThemeAttribute",
                            "Ptr", GuiCtrlObj.hWnd,
                            "Int", 3,
                            "Int*", 0x404040,
                            "Int", 4)
                    }
                
                case "Edit":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                
                case "ListView":
                    ; Set ListView text and background colors
                    _Dark.SendMessage(0x1024, 0, _Dark.Dark["Font"], GuiCtrlObj.hWnd)         ; LVM_SETTEXTCOLOR
                    _Dark.SendMessage(0x1026, 0, _Dark.Dark["Background"], GuiCtrlObj.hWnd)   ; LVM_SETBKCOLOR
                    _Dark.SendMessage(0x1001, 0, _Dark.Dark["Background"], GuiCtrlObj.hWnd)   ; LVM_SETTEXTBKCOLOR
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    
                    ; Get ListView header control
                    LV_Header := _Dark.SendMessage(0x101F, 0, 0, GuiCtrlObj.hWnd) ; LVM_GETHEADER
                    if (LV_Header) {
                        ; Register the header for processing notifications
                        _Dark.ListViewHeaders[LV_Header] := true
                        
                        ; Set the theme for the header
                        DllCall("uxtheme\SetWindowTheme", "Ptr", LV_Header, "Str", "DarkMode_ItemsView", "Ptr", 0)
                        
                        ; Custom draw for header colors - direct approach to set colors
                        ; This gets the HDC (device context) for the header and sets the text color
                        headerDC := DllCall("GetDC", "Ptr", LV_Header, "Ptr")
                        if (headerDC) {
                            DllCall("SetTextColor", "Ptr", headerDC, "UInt", 0xFFFFFF)  ; White text
                            DllCall("ReleaseDC", "Ptr", LV_Header, "Ptr", headerDC)
                        }
                        
                        ; Force a redraw of the header
                        DllCall("InvalidateRect", "Ptr", LV_Header, "Ptr", 0, "Int", 1)
                    }
            }
        }
    }
    
    SetupWindowProc() {
        _Dark.Instances[this.Gui.Hwnd] := this
        
        if (!_Dark.WindowProcOldMap.Has(this.Gui.Hwnd)) {
            oldProc := DllCall("user32\" _Dark.GetWindowLong, "Ptr", this.Gui.Hwnd, "Int", _Dark.GWL_WNDPROC, "Ptr")
            _Dark.WindowProcOldMap[this.Gui.Hwnd] := oldProc
            
            callback := CallbackCreate(DarkModeGUI_WindowProc, , 4)
            _Dark.WindowProcCallbacks[this.Gui.Hwnd] := callback
            DllCall("user32\" _Dark.SetWindowLong, "Ptr", this.Gui.Hwnd, "Int", _Dark.GWL_WNDPROC, "Ptr", callback, "Ptr")
        }
    }
    
    SetButtonColor(buttonCtrl, bgColor, textColor) {
        if (IsInteger(bgColor))
            bgColorInt := bgColor
        else
            bgColorInt := Integer("0x" . RegExReplace(bgColor, "^0x"))
            
        if (IsInteger(textColor))
            textColorInt := textColor
        else
            textColorInt := Integer("0x" . RegExReplace(textColor, "^0x"))
        
        _Dark.ButtonColors[buttonCtrl.Hwnd] := Map(
            "bg", bgColorInt,
            "text", textColorInt
        )
        
        DllCall("InvalidateRect", "Ptr", buttonCtrl.Hwnd, "Ptr", 0, "Int", true)
    }
    
    static ProcessWindowMessage(hwnd, uMsg, wParam, lParam) {
        Critical
        
        switch uMsg {
            case _Dark.WM_CTLCOLOREDIT, _Dark.WM_CTLCOLORLISTBOX:
                if (_Dark.ComboBoxes.Has(lParam) || _Dark.IsComboBoxListBox(lParam)) {
                    try {
                        DllCall("comctl32\DarkMode_ComboBox", "Ptr", wParam)
                    }
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _Dark.Dark["Font"])
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _Dark.Dark["ComboBoxBg"])
                    DllCall("gdi32\SetDCBrushColor", "Ptr", wParam, "UInt", _Dark.Dark["ComboBoxBg"])
                } else {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _Dark.Dark["Font"])
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _Dark.Dark["Controls"])
                    DllCall("gdi32\SetDCBrushColor", "Ptr", wParam, "UInt", _Dark.Dark["Controls"])
                }
                return DllCall("gdi32\GetStockObject", "Int", _Dark.DC_BRUSH, "Ptr")
                
            case _Dark.WM_CTLCOLORBTN:
                if (_Dark.ButtonColors.Has(lParam)) {
                    btnColors := _Dark.ButtonColors[lParam]
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", btnColors["text"])
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", btnColors["bg"])
                    DllCall("gdi32\SetDCBrushColor", "Ptr", wParam, "UInt", btnColors["bg"])
                } else {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _Dark.Dark["Font"])
                    DllCall("gdi32\SetDCBrushColor", "Ptr", wParam, "UInt", _Dark.Dark["Background"])
                }
                return DllCall("gdi32\GetStockObject", "Int", _Dark.DC_BRUSH, "Ptr")
                
            case _Dark.WM_CTLCOLORSTATIC:
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", _Dark.Dark["Font"])
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _Dark.Dark["Background"])
                return _Dark.TextBackgroundBrush
                
            case _Dark.WM_NOTIFY:
                hwndFrom := NumGet(lParam, 0, "Ptr")
                code := NumGet(lParam, A_PtrSize + 4, "Int")
                
                ; Special handling for ListView header custom drawing
                if (_Dark.ListViewHeaders.Has(hwndFrom) && code == _Dark.HDN_CUSTOMDRAW) {
                    ; Get info about the custom draw stage
                    nmcd := lParam
                    drawStage := NumGet(nmcd, A_PtrSize * 2 + 8, "UInt")
                    hdc := NumGet(nmcd, A_PtrSize * 2 + 12, "Ptr")
                    
                    if (drawStage == _Dark.CDDS_PREPAINT) {
                        ; Request notifications for each item
                        return _Dark.CDRF_NOTIFYITEMDRAW
                    } 
                    else if (drawStage == _Dark.CDDS_ITEMPREPAINT) {
                        ; Set white text color for each header item
                        DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", 0xFFFFFF)
                        
                        ; Keep the background dark
                        DllCall("gdi32\SetBkColor", "Ptr", hdc, "UInt", _Dark.Dark["Controls"])
                        DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", 1)  ; TRANSPARENT
                        
                        ; Use these color settings
                        return _Dark.CDRF_NEWFONT
                    }
                }
        }
        
        if (_Dark.WindowProcOldMap.Has(hwnd))
            return DllCall("CallWindowProc", "Ptr", _Dark.WindowProcOldMap[hwnd], 
                          "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam)
        return 0
    }
    
    static IsComboBoxListBox(hwnd) {
        static className := Buffer(64)
        if DllCall("GetClassName", "Ptr", hwnd, "Ptr", className, "Int", 32) {
            return StrGet(className) == "ComboLBox"
        }
        return false
    }
    
    static AddDarkCheckBox(obj, Options, Text) {
        static SM_CXMENUCHECK := 71
        static SM_CYMENUCHECK := 72
        static checkBoxW := SysGet(SM_CXMENUCHECK)
        static checkBoxH := SysGet(SM_CYMENUCHECK)
        
        chbox := obj.Add("Checkbox", Options " r1.5 +0x4000000", Text)
        if !InStr(Options, "right")
            txt := obj.Add("Text", "xp+" (checkBoxW+8) " yp+2 HP-4 +0x4000200", Text)
        else
            txt := obj.Add("Text", "xp+8 yp+2 HP-4 +0x4000200", Text)
        
        chbox.Text := ""
        chbox.DeleteProp("Text")
        chbox.DefineProp("Text", {
            Get: this => txt.Text,
            Set: (this, value) => txt.Text := value
        })
        
        _Dark.SetWindowPos(txt.hwnd, 0, , , , , 0x43)
        return chbox
    }
    
    static SetWindowPos(hWnd, hWndInsertAfter, X := 0, Y := 0, cx := 0, cy := 0, uFlags := 0x40) {
        return DllCall("User32\SetWindowPos", "ptr", hWnd, "ptr", hWndInsertAfter, "int", X, "int", Y, "int", cx, "int", cy, "uint", uFlags, "int")
    }
    
    static SendMessage(msg, wParam, lParam, hwnd) {
        return DllCall("user32\SendMessage", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    
    __Delete() {
        if (_Dark.WindowProcOldMap.Has(this.Gui.Hwnd)) {
            DllCall("user32\" _Dark.SetWindowLong, "Ptr", this.Gui.Hwnd, 
                   "Int", _Dark.GWL_WNDPROC, "Ptr", _Dark.WindowProcOldMap[this.Gui.Hwnd], "Ptr")
                   
            CallbackFree(_Dark.WindowProcCallbacks[this.Gui.Hwnd])
            _Dark.WindowProcCallbacks.Delete(this.Gui.Hwnd)
            _Dark.WindowProcOldMap.Delete(this.Gui.Hwnd)
        }
        
        if (_Dark.Instances.Has(this.Gui.Hwnd))
            _Dark.Instances.Delete(this.Gui.Hwnd)
    }
}

AddDarkCheckBox(obj, Options, Text) {
    return _Dark.AddDarkCheckBox(obj, Options, Text)
}

SetWindowPos(hWnd, hWndInsertAfter, X := 0, Y := 0, cx := 0, cy := 0, uFlags := 0x40) {
    return _Dark.SetWindowPos(hWnd, hWndInsertAfter, X, Y, cx, cy, uFlags)
}

SendMessage(msg, wParam, lParam, hwnd) {
    return _Dark.SendMessage(msg, wParam, lParam, hwnd)
}
