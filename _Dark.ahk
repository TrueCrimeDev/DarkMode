class _Dark {
    static DarkColors := Map(
        "Background", 0x171717, 
        "Controls", 0x202020, 
        "Font", 0xFFFFFF
    )
    
    class RECT {
        left := 0
        top := 0
        right := 0
        bottom := 0
    }
    
    class NMHDR {
        hwndFrom := 0
        idFrom := 0
        code := 0
    }
    
    class NMCUSTOMDRAW {
        hdr := 0
        dwDrawStage := 0
        hdc := 0
        rc := 0
        dwItemSpec := 0
        uItemState := 0
        lItemlParam := 0
        
        __New() {
            this.hdr := _Dark.NMHDR()
            this.rc := _Dark.RECT()
        }
    }
    
    static StructFromPtr(StructClass, ptr) {
        obj := StructClass()
        
        if (StructClass.Prototype.__Class = "NMHDR") {
            obj.hwndFrom := NumGet(ptr, 0, "UPtr")
            obj.idFrom := NumGet(ptr, A_PtrSize, "UPtr")
            obj.code := NumGet(ptr, A_PtrSize * 2, "Int")
        }
        else if (StructClass.Prototype.__Class = "NMCUSTOMDRAW") {
            obj.hdr := _Dark.NMHDR()
            obj.hdr.hwndFrom := NumGet(ptr, 0, "UPtr")
            obj.hdr.idFrom := NumGet(ptr, A_PtrSize, "UPtr")
            obj.hdr.code := NumGet(ptr, A_PtrSize * 2, "Int")
            
            obj.dwDrawStage := NumGet(ptr, A_PtrSize * 3, "UInt")
            obj.hdc := NumGet(ptr, A_PtrSize * 3 + 4, "UPtr")
            
            obj.rc := _Dark.RECT()
            rectOffset := A_PtrSize * 3 + 4 + A_PtrSize
            obj.rc.left := NumGet(ptr, rectOffset, "Int")
            obj.rc.top := NumGet(ptr, rectOffset + 4, "Int")
            obj.rc.right := NumGet(ptr, rectOffset + 8, "Int")
            obj.rc.bottom := NumGet(ptr, rectOffset + 12, "Int")
            
            obj.dwItemSpec := NumGet(ptr, rectOffset + 16, "UPtr")
            obj.uItemState := NumGet(ptr, rectOffset + 16 + A_PtrSize, "UInt")
            obj.lItemlParam := NumGet(ptr, rectOffset + 16 + A_PtrSize + 4, "IPtr")
        }
        
        return obj
    }
    
    static __New() {
        global _Dark_WindowProc := (hwnd, uMsg, wParam, lParam) => 
            _Dark.ProcessWindowMessage(hwnd, uMsg, wParam, lParam)
        
        static LVM_GETHEADER := 0x101F
        Gui.ListView.Prototype.GetHeader := SendMessage.Bind(LVM_GETHEADER, 0, 0)
        Gui.ListView.Prototype.SetDarkMode := this.SetDarkMode.Bind(this)
    }
    
    static Instances := Map()
    static WindowProcOldMap := Map()
    static WindowProcCallbacks := Map()
    static TextBackgroundBrush := 0
    static ButtonColors := Map()
    static ComboBoxes := Map()
    static ListViewHeaders := Map()
    static HeaderCallbacks := Map()
    
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
    static CDDS_PREPAINT := 0x00000001
    static CDDS_ITEMPREPAINT := 0x00010001
    static CDRF_DODEFAULT := 0x0
    static CDRF_NEWFONT := 0x00000002
    static CDRF_NOTIFYITEMDRAW := 0x00000020
    static DC_BRUSH := 18
    static GWL_WNDPROC := -4
    static GWL_STYLE := -16
    static LVM_GETHEADER := 0x101F
    static HDM_SETIMAGELIST := 0x1208
    static HDM_SETITEM := 0x120C
    
    static GetWindowLong := A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong"
    static SetWindowLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"
    
    static SetWindowPos(hWnd, hWndInsertAfter, X := 0, Y := 0, cx := 0, cy := 0, uFlags := 0x40) {
        return DllCall("User32\SetWindowPos", "ptr", hWnd, "ptr", hWndInsertAfter, "int", X, "int", Y, "int", cx, "int", cy, "uint", uFlags, "int")
    }
    
    static SendMessage(msg, wParam, lParam, hwnd) {
        return DllCall("user32\SendMessage", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    static SetDarkMode(lv, style := "Explorer") {
        static LVS_EX_DOUBLEBUFFER := 0x10000
        static NM_CUSTOMDRAW := -12
        static UIS_SET := 1
        static UISF_HIDEFOCUS := 0x1
        static WM_CHANGEUISTATE := 0x0127
        static WM_NOTIFY := 0x4E
        static WM_THEMECHANGED := 0x031A

        lv.Header := lv.GetHeader()
        
        lv.OnMessage(WM_THEMECHANGED, (*) => 0)
        
        lv.OnMessage(WM_NOTIFY, (lv, wParam, lParam, Msg) {
            static CDDS_ITEMPREPAINT := 0x10001
            static CDDS_PREPAINT := 0x1
            static CDRF_DODEFAULT := 0x0
            static CDRF_NOTIFYITEMDRAW := 0x20
    
            if (_Dark.StructFromPtr(_Dark.NMHDR, lParam).code != NM_CUSTOMDRAW) 
                return 

            nmcd := _Dark.StructFromPtr(_Dark.NMCUSTOMDRAW, lParam)
            
            if (nmcd.hdr.hwndFrom != lv.Header)
                return

            switch nmcd.dwDrawStage {
            case CDDS_PREPAINT: return CDRF_NOTIFYITEMDRAW
            case CDDS_ITEMPREPAINT: SetTextColor(nmcd.hdc, 0xFFFFFF)
            }

            return CDRF_DODEFAULT
        })

        lv.Opt("+LV" LVS_EX_DOUBLEBUFFER)
        
        SendMessage(WM_CHANGEUISTATE, (UIS_SET << 8) | UISF_HIDEFOCUS, 0, lv)

        SetWindowTheme(lv.Header, "DarkMode_ItemsView")
        SetWindowTheme(lv.Hwnd, "DarkMode_" style)

        SetTextColor(hdc, color) => DllCall("SetTextColor", "Ptr", hdc, "UInt", color)

        SetWindowTheme(hwnd, appName, subIdList?) => DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "ptr", StrPtr(appName), "ptr", subIdList ?? 0)
    }
    
    static AddDarkCheckBox(GuiObj, Options, Text) {
        static SM_CXMENUCHECK := 71
        static SM_CYMENUCHECK := 72
        static checkBoxW := SysGet(SM_CXMENUCHECK)
        static checkBoxH := SysGet(SM_CYMENUCHECK)

        chbox := GuiObj.Add("Checkbox", Options " r1.5 +0x4000000", Text)
        if !InStr(Options, "right")
            txt := GuiObj.Add("Text", "xp+" (checkBoxW+8) " yp+2 HP-4 +0x4000200", Text)
        else
            txt := GuiObj.Add("Text", "xp+8 yp+2 HP-4 +0x4000200", Text)

        chbox.Text := ""
        chbox.DeleteProp("Text")
        chbox.DefineProp("Text", {
            Get: this => txt.Text,
            Set: (this, value) => txt.Text := value
        })

        _Dark.SetWindowPos(txt.hwnd, 0, , , , , 0x43)
        return chbox
    }

    static SetHeaderTextColor(hwndHeader) {
        static NM_CUSTOMDRAW := -12
        static CDDS_PREPAINT := 0x00000001
        static CDDS_ITEMPREPAINT := 0x00010001
        static CDRF_NOTIFYITEMDRAW := 0x00000020
        static CDRF_NEWFONT := 0x00000002
        
        if _Dark.HeaderCallbacks.Has(hwndHeader)
            return
            
        headerCallbackFunc := ObjBindMethod(_Dark, "HeaderNotifyHandler", hwndHeader)
        hwndParent := DllCall("GetParent", "Ptr", hwndHeader, "Ptr")
        
        _Dark.HeaderCallbacks[hwndHeader] := headerCallbackFunc
        OnMessage(_Dark.WM_NOTIFY, headerCallbackFunc)
    }
    
    static HeaderNotifyHandler(hwndHeader, wParam, lParam, msg, hwnd) {
        static NM_CUSTOMDRAW := -12
        static CDDS_PREPAINT := 0x00000001
        static CDDS_ITEMPREPAINT := 0x00010001
        static CDRF_NOTIFYITEMDRAW := 0x00000020
        static CDRF_NEWFONT := 0x00000002
        
        if (hwnd != DllCall("GetParent", "Ptr", hwndHeader, "Ptr"))
            return
            
        code := NumGet(lParam + A_PtrSize*2, "Int")
        hwndFrom := NumGet(lParam, "Ptr")
        
        if (hwndFrom != hwndHeader || code != NM_CUSTOMDRAW)
            return
            
        drawStage := NumGet(lParam + A_PtrSize*3, "UInt")
        hdc := NumGet(lParam + A_PtrSize*3 + 4, "Ptr")
        
        if (drawStage = CDDS_PREPAINT)
            return CDRF_NOTIFYITEMDRAW
            
        if (drawStage = CDDS_ITEMPREPAINT) {
            DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", 0xFFFFFF)
            return CDRF_NEWFONT
        }
        
        return
    }
    
    Gui := ""
    
    __New(GuiObj) {
        if (!_Dark.TextBackgroundBrush)
            _Dark.TextBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", _Dark.Dark["Background"], "Ptr")
        
        this.Gui := GuiObj
        this.SetWindowDarkMode()
        this.SetControlsTheme()
        this.SetupWindowProc()
        
        OnMessage(_Dark.WM_NOTIFY, this.HandleNotifyMessages.Bind(this))
    }
    
    HandleNotifyMessages(wParam, lParam, msg, hwnd) {
        if (hwnd != this.Gui.Hwnd)
            return

        nmhdr := _Dark.StructFromPtr(_Dark.NMHDR, lParam)
        
        if (nmhdr.code != _Dark.NM_CUSTOMDRAW)
            return
            
        for hWnd, GuiCtrlObj in this.Gui {
            if (GuiCtrlObj.Type = "ListView") {
                hHeader := _Dark.SendMessage(_Dark.LVM_GETHEADER, 0, 0, GuiCtrlObj.Hwnd)
                
                if (nmhdr.hwndFrom = hHeader) {
                    nmcd := _Dark.StructFromPtr(_Dark.NMCUSTOMDRAW, lParam)
                    
                    switch nmcd.dwDrawStage {
                        case _Dark.CDDS_PREPAINT:
                            return _Dark.CDRF_NOTIFYITEMDRAW
                            
                        case _Dark.CDDS_ITEMPREPAINT:
                            DllCall("gdi32\SetTextColor", "Ptr", nmcd.hdc, "UInt", 0xFFFFFF)
                            return _Dark.CDRF_NEWFONT
                    }
                }
            }
        }
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
                    _Dark.SendMessage(0x1024, 0, _Dark.Dark["Font"], GuiCtrlObj.hWnd)
                    _Dark.SendMessage(0x1026, 0, _Dark.Dark["Background"], GuiCtrlObj.hWnd)
                    _Dark.SendMessage(0x1001, 0, _Dark.Dark["Background"], GuiCtrlObj.hWnd)
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    
                    header := _Dark.SendMessage(_Dark.LVM_GETHEADER, 0, 0, GuiCtrlObj.hWnd)
                    if (header) {
                        DllCall("uxtheme\SetWindowTheme", "Ptr", header, "Str", "DarkMode_ItemsView", "Ptr", 0)
                        
                        GuiCtrlObj.SetDarkMode()
                    }
            }
        }
    }
    
    SetupWindowProc() {
        _Dark.Instances[this.Gui.Hwnd] := this
        
        if (!_Dark.WindowProcOldMap.Has(this.Gui.Hwnd)) {
            oldProc := DllCall("user32\" _Dark.GetWindowLong, "Ptr", this.Gui.Hwnd, "Int", _Dark.GWL_WNDPROC, "Ptr")
            _Dark.WindowProcOldMap[this.Gui.Hwnd] := oldProc
            
            callback := CallbackCreate(_Dark_WindowProc, , 4)
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
