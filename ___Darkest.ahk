#Requires AutoHotkey v2.1-alpha.16
#SingleInstance Force

SimpleDarkGUI()

class SimpleDarkGUI {
    __New() {
        this.animStep := 0
        this.InitializeGui()
        this.CreateAllControls()
        this.SetupEvents()
        this.gui.Show()
    }

    InitializeGui() {
        this.gui := Gui("+Resize", "Dark Mode Control Showcase")
        this.gui.SetFont("s9", "Segoe UI")
        this.darkMode := _Dark(this.gui)
        this.controls := Map()
        this.form := GuiForm(this.gui)
    }

    CreateAllControls() {
        ; Title section
        this.darkMode.AddDarkText(GuiFormat(20, 15, 560, 30, "+Center"), "Dark Mode Control Showcase")

        ; Input Controls Section
        this.darkMode.AddDarkText(GuiFormat(30, 60, 250, 20), "━ Text Input Controls")
        this.controls["singleEdit"] := this.darkMode.AddDarkEdit(GuiFormat(30, 85, 220, 25), "Single-line edit field")
        this.controls["multiEdit"] := this.darkMode.AddDarkEdit(GuiFormat(30, 120, 220, 65, "+Multi +VScroll"), "Multi-line edit field`nLine 2`nLine 3`nLine 4")

        ; Selection Controls Section
        this.darkMode.AddDarkText(GuiFormat(320, 60, 250, 20), "━ Selection Controls")
        this.controls["check1"] := this.darkMode.AddDarkCheckBox(GuiFormat(320, 85, 200, 20, "+Checked"), "Enable notifications")
        this.controls["check2"] := this.darkMode.AddDarkCheckBox(GuiFormat(320, 110, 200, 20), "Auto-save settings")
        this.controls["radio1"] := this.darkMode.AddDarkRadio(GuiFormat(320, 135, 200, 20, "+Checked"), "High priority", "PriorityGroup", this)
        this.controls["radio2"] := this.darkMode.AddDarkRadio(GuiFormat(320, 160, 200, 20), "Normal priority", "PriorityGroup", this)
        this.controls["radio3"] := this.darkMode.AddDarkRadio(GuiFormat(320, 185, 200, 20), "Low priority", "PriorityGroup", this)

        ; Dropdown Controls Section (adjusted spacing to prevent overlap)
        this.darkMode.AddDarkText(GuiFormat(30, 210, 250, 20), "━ Dropdown & Progress")
        this.controls["comboBox"] := this.darkMode.AddDarkComboBox(GuiFormat(30, 235, 180, 0), ["Option A", "Option B", "Option C", "Option D"])
        this.controls["themeSelector"] := this.darkMode.AddDarkComboBox(GuiFormat(30, 275, 180, 0), ["Dark Gray Theme", "Dark Blue Theme", "Dark Green Theme", "Dark Purple Theme"])

        ; Slider and Progress Section (adjusted positioning)
        this.controls["hSlider"] := this.darkMode.AddDarkSlider(GuiFormat(230, 235, 150, 25, "Range0-100"), 50)
        this.controls["sliderValue"] := this.darkMode.AddDarkText(GuiFormat(230, 265, 150, 20), "Value: 50")
        this.controls["progress1"] := this.darkMode.AddDarkProgress(GuiFormat(230, 285, 150, 20), 65)

        ; Action Buttons Section (moved down to avoid overlap)
        this.darkMode.AddDarkText(GuiFormat(400, 210, 180, 20), "━ Action Controls")
        this.controls["normalBtn"] := this.darkMode.AddDarkButton(GuiFormat(400, 235, 80, 28), "Apply")
        this.controls["defaultBtn"] := this.darkMode.AddDarkButton(GuiFormat(490, 235, 80, 28, "+Default"), "OK")
        this.controls["resetBtn"] := this.darkMode.AddDarkButton(GuiFormat(400, 270, 80, 28), "Reset")
        this.controls["closeBtn"] := this.darkMode.AddDarkButton(GuiFormat(490, 270, 80, 28), "Close")

        ; Data Display Section (adjusted spacing)
        this.darkMode.AddDarkText(GuiFormat(30, 325, 200, 20), "━ Data Display Controls")

        ; List Controls Row (better spacing)
        this.darkMode.AddDarkText(GuiFormat(30, 350, 80, 18), "ListBox:")
        this.controls["listBox"] := this.darkMode.AddDarkListBox(GuiFormat(30, 370, 100, 85), ["Project Alpha", "Project Beta", "Project Gamma", "Project Delta"])

        this.darkMode.AddDarkText(GuiFormat(140, 350, 80, 18), "TreeView:")
        this.controls["treeView"] := this.darkMode.AddDarkTreeView(GuiFormat(140, 370, 120, 85))
        parent1 := this.controls["treeView"].Add("Documents")
        this.controls["treeView"].Add("Report.pdf", parent1)
        this.controls["treeView"].Add("Notes.txt", parent1)
        parent2 := this.controls["treeView"].Add("Images")
        this.controls["treeView"].Add("Photo1.jpg", parent2)
        this.controls["treeView"].Add("Photo2.png", parent2)

        ; ListView Section (with column auto-sizing)
        this.darkMode.AddDarkText(GuiFormat(280, 350, 200, 18), "File Explorer:")
        this.controls["listView"] := this.darkMode.AddListView(GuiFormat(280, 370, 290, 85, "+Grid"), ["Name", "Type", "Size", "Modified"])
        this.controls["listView"].Add("", "Document.pdf", "PDF File", "1.2 MB", "Today")
        this.controls["listView"].Add("", "Projects", "Folder", "—", "Yesterday")
        this.controls["listView"].Add("", "Script.ahk", "AutoHotkey", "5.7 KB", "2 days ago")
        this.controls["listView"].Add("", "Data.xlsx", "Excel File", "234 KB", "Last week")
        this.controls["listView"].SetFont("cFFFFFF")

        ; Set initial column widths evenly
        this.SetListViewColumnWidths()

        ; Log Output Section (adjusted spacing)
        this.darkMode.AddDarkText(GuiFormat(30, 475, 200, 18), "━ Application Log")
        this.controls["logOutput"] := this.darkMode.AddDarkEdit(GuiFormat(30, 500, 420, 65, "+Multi +VScroll +ReadOnly"), "")
        static EM_SETBKGNDCOLOR := 0x0443
        DllCall("SendMessage", "Ptr", this.controls["logOutput"].hWnd, "UInt", EM_SETBKGNDCOLOR, "Ptr", 0, "UInt", _Dark.Dark["Controls"])
        this.controls["logOutput"].Opt("Background" Format("{:X}", _Dark.Dark["Controls"]))
        this.controls["logOutput"].Text := "Application initialized successfully" . "`r`n" . "Dark mode theme applied" . "`r`n" . "All controls loaded and configured"

        ; Status Bar (adjusted positioning)
        this.controls["statusText"] := this.darkMode.AddDarkText(GuiFormat(30, 575, 420, 18), "Status: Ready - All systems operational")

        ; Quick Actions (adjusted positioning)
        this.darkMode.AddDarkText(GuiFormat(470, 475, 100, 18), "━ Quick Actions")
        this.controls["saveBtn"] := this.darkMode.AddDarkButton(GuiFormat(470, 500, 90, 25), "Save")
        this.controls["loadBtn"] := this.darkMode.AddDarkButton(GuiFormat(470, 530, 90, 25), "Load")
        this.controls["helpBtn"] := this.darkMode.AddDarkButton(GuiFormat(470, 560, 90, 25), "Help")
    }

    SetupEvents() {
        this.controls["normalBtn"].OnEvent("Click", (*) => this.LogEvent("Apply button clicked"))
        this.controls["defaultBtn"].OnEvent("Click", (*) => this.LogEvent("OK button clicked"))
        this.controls["closeBtn"].OnEvent("Click", (*) => this.gui.Close())
        this.controls["resetBtn"].OnEvent("Click", this.ResetControls.Bind(this))
        this.controls["themeSelector"].OnEvent("Change", this.ThemeChanged.Bind(this))
        this.controls["hSlider"].OnEvent("Change", this.SliderChanged.Bind(this))
        this.controls["saveBtn"].OnEvent("Click", (*) => this.LogEvent("Configuration saved"))
        this.controls["loadBtn"].OnEvent("Click", (*) => this.LogEvent("Configuration loaded"))
        this.controls["helpBtn"].OnEvent("Click", (*) => this.LogEvent("Help documentation opened"))

        this.gui.OnEvent("Close", (*) => ExitApp())
        this.gui.Show("w600 h615")
        this.controls["normalBtn"].Focus()
    }

    SetListViewColumnWidths() {
        ; Set equal column widths for ListView
        totalWidth := 290  ; ListView width
        columnCount := 4   ; Number of columns
        columnWidth := totalWidth // columnCount

        ; Set each column width
        this.controls["listView"].ModifyCol(1, columnWidth - 5)  ; Name column slightly smaller for icon
        this.controls["listView"].ModifyCol(2, columnWidth)      ; Type column
        this.controls["listView"].ModifyCol(3, columnWidth - 10) ; Size column smaller
        this.controls["listView"].ModifyCol(4, columnWidth + 15) ; Modified column slightly larger
    }

    ResetControls(*) {
        this.controls["singleEdit"].Text := "Single-line edit field"
        this.controls["multiEdit"].Text := "Multi-line edit field`nLine 2`nLine 3`nLine 4"
        this.controls["hSlider"].Value := 50
        this.controls["sliderValue"].Text := "Value: 50"
        this.controls["progress1"].Value := 65
        this.controls["themeSelector"].Choose(1)
        this.controls["check1"].Value := 1
        this.controls["check2"].Value := 0
        this.controls["radio1"].Value := 1
        this.controls["radio2"].Value := 0
        this.controls["radio3"].Value := 0
        this.controls["comboBox"].Choose(1)  ; Reset to first option
        if this.controls.Has("treeView") {
            this.controls["treeView"].Delete()
            parent1 := this.controls["treeView"].Add("Documents")
            this.controls["treeView"].Add("Report.pdf", parent1)
            this.controls["treeView"].Add("Notes.txt", parent1)
            parent2 := this.controls["treeView"].Add("Images")
            this.controls["treeView"].Add("Photo1.jpg", parent2)
            this.controls["treeView"].Add("Photo2.png", parent2)
        }
        this.LogEvent("All controls reset to default values")
    }

    ThemeChanged(*) {
        themeName := this.controls["themeSelector"].Text
        themes := Map(
            "Dark Blue Theme", Map("Background", 0x1A1A2E, "Controls", 0x16213E, "Font", 0xE0E0E0),
            "Dark Gray Theme", Map("Background", 0x171717, "Controls", 0x1E1E1E, "Font", 0xE0E0E0),
            "Dark Green Theme", Map("Background", 0x0A2A12, "Controls", 0x103619, "Font", 0xE0E0E0),
            "Dark Purple Theme", Map("Background", 0x240041, "Controls", 0x3C096C, "Font", 0xE0E0E0),
            "Custom Theme", Map("Background", 0x2D1B69, "Controls", 0x1E3A8A, "Font", 0xF0F9FF)
        )
        if themes.Has(themeName) {
            this.darkMode.SetTheme(themes[themeName])
            this.LogEvent("Theme changed to: " . themeName)
        }
    }

    SliderChanged(*) {
        value := this.controls["hSlider"].Value
        this.controls["sliderValue"].Text := "Value: " . value
        this.controls["progress1"].Value := value
        this.LogEvent("Slider value changed to: " . value)
    }

    HandleRadioClick(clickedRadio, groupName, *) {
        this.darkMode.HandleRadioClick(clickedRadio, groupName)
        radioText := clickedRadio.Text
        if radioText
            this.LogEvent(radioText . " selected")
    }

    LogEvent(message) {
        if this.controls.Has("logOutput") {
            timestamp := FormatTime(A_Now, "HH:mm:ss")
            currentText := this.controls["logOutput"].Text
            newText := currentText . "`r`n" . timestamp . " - " . message
            this.controls["logOutput"].Text := newText

            ; Scroll to bottom of log
            static EM_SETSEL := 0x00B1
            static EM_SCROLLCARET := 0x00B7
            textLength := StrLen(newText)
            DllCall("SendMessage", "Ptr", this.controls["logOutput"].hWnd, "UInt", EM_SETSEL, "Ptr", textLength, "Ptr", textLength)
            DllCall("SendMessage", "Ptr", this.controls["logOutput"].hWnd, "UInt", EM_SCROLLCARET, "Ptr", 0, "Ptr", 0)

            static EM_SETBKGNDCOLOR := 0x0443
            DllCall("SendMessage", "Ptr", this.controls["logOutput"].hWnd, "UInt", EM_SETBKGNDCOLOR, "Ptr", 0, "UInt", _Dark.Dark["Controls"])
        }
        if this.controls.Has("statusText")
            this.controls["statusText"].Text := "Status: " . message
    }

    OnGuiResize(gui, minMax, width, height) {
        if minMax = -1
            return
    }
}

GuiFormat(x, y, w, h, opts := "") {
    return Trim(Format("x{} y{} w{} h{}", x, y, w, h) " " opts)
}

class CommandManager {
    __New() {
        this.cmds := Map()
    }

    Register(name, cb) {
        this.cmds[name] := cb
        return this
    }

    Execute(name, params*) {
        if (this.cmds.Has(name))
            return this.cmds[name](params*)
        return false
    }
}

class GuiForm {
    __New(gui) {
        this.gui := gui
    }

    Edit(opts := "", txt := "") {
        return ControlBuilder(this.gui, "Edit", txt, opts)
    }

    Button(text, opts := "") {
        return ControlBuilder(this.gui, "Button", text, opts)
    }

    Text(text, opts := "") {
        return ControlBuilder(this.gui, "Text", text, opts)
    }

    DropDownList(opts := "", items := "") {
        return ControlBuilder(this.gui, "DropDownList", items, opts)
    }

    Show() {
        this.gui.Show()
    }
}

class ControlBuilder {
    __New(gui, type, text := "", opts := "") {
        this.gui := gui
        this.type := type
        this.text := text
        this.opts := opts
        this.dim := Map("x", 0, "y", 0, "w", 0, "h", 0)
        this.events := []
    }

    Pos(x?, y?) {
        if IsSet(x)
            this.dim["x"] := x
        if IsSet(y)
            this.dim["y"] := y
        return this
    }

    Size(w?, h?) {
        if IsSet(w)
            this.dim["w"] := w
        if IsSet(h)
            this.dim["h"] := h
        return this
    }

    Opt(opt) {
        if opt
            this.opts := Trim(this.opts " " opt)
        return this
    }

    Default() {
        this.opts := Trim(this.opts " Default")
        return this
    }

    OnEvent(evt, cb) {
        this.events.Push([evt, cb])
        return this
    }

    Add() {
        spec := Trim(Format("x{1} y{2} w{3} h{4}", this.dim["x"], this.dim["y"], this.dim["w"], this.dim["h"]) " " this.opts)
        ctrl := ""
        switch this.type {
            case "Edit":
                ctrl := this.gui.AddEdit(spec, this.text)
            case "Button":
                ctrl := this.gui.AddButton(spec, this.text)
            case "Text":
                ctrl := this.gui.AddText(spec, this.text)
            case "DropDownList":
                ctrl := this.gui.AddDropDownList(spec, this.text)
        }
        if IsObject(ctrl) {
            if (ctrl.Type = "Edit" || ctrl.Type = "Text" || ctrl.Type = "DDL" || ctrl.Type = "ComboBox")
                ctrl.SetFont("cFFFFFF")
            for _, evt in this.events
                ctrl.OnEvent(evt[1], evt[2])
        }
        return GuiForm(this.gui)
    }
}

_DarkSliderCustomDrawCallback(hWnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    static WM_PAINT := 0x000F
    static WM_MOUSEMOVE := 0x0200
    static WM_MOUSELEAVE := 0x02A3
    static WM_LBUTTONDOWN := 0x0201
    static WM_LBUTTONUP := 0x0202
    static TME_LEAVE := 0x00000002
    if (uMsg = WM_MOUSEMOVE) {
        if !_Dark.SliderControls[hWnd].Has("tracking") {
            trackStruct := Buffer(16, 0)
            NumPut("UInt", 16, trackStruct, 0)
            NumPut("UInt", TME_LEAVE, trackStruct, 4)
            NumPut("Ptr", hWnd, trackStruct, 8)
            DllCall("TrackMouseEvent", "Ptr", trackStruct)
            _Dark.SliderControls[hWnd]["tracking"] := true
            _Dark.SliderControls[hWnd]["state"] := "hover"
            DllCall("InvalidateRect", "Ptr", hWnd, "Ptr", 0, "Int", true)
        }
    } else if (uMsg = WM_MOUSELEAVE) {
        _Dark.SliderControls[hWnd].Delete("tracking")
        _Dark.SliderControls[hWnd]["state"] := "normal"
        DllCall("InvalidateRect", "Ptr", hWnd, "Ptr", 0, "Int", true)
    } else if (uMsg = WM_LBUTTONDOWN) {
        _Dark.SliderControls[hWnd]["state"] := "active"
        DllCall("InvalidateRect", "Ptr", hWnd, "Ptr", 0, "Int", true)
    } else if (uMsg = WM_LBUTTONUP) {
        if _Dark.SliderControls[hWnd].Has("tracking") {
            _Dark.SliderControls[hWnd]["state"] := "hover"
        } else {
            _Dark.SliderControls[hWnd]["state"] := "normal"
        }
        DllCall("InvalidateRect", "Ptr", hWnd, "Ptr", 0, "Int", true)
    } else if (uMsg = 0x02) {
        if _Dark.ControlCallbacks.Has(hWnd) {
            callback := _Dark.ControlCallbacks[hWnd]
            DllCall("RemoveWindowSubclass", "Ptr", hWnd, "Ptr", callback, "Ptr", hWnd)
            CallbackFree(callback)
            _Dark.ControlCallbacks.Delete(hWnd)
        }
    }
    return DllCall("DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

_DarkHeaderCustomDrawCallback(hWnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    static HDM_GETITEM := 0x120B
    static NM_CUSTOMDRAW := -12
    static CDRF_DODEFAULT := 0x00000000
    static CDRF_SKIPDEFAULT := 0x00000004
    static CDRF_NOTIFYITEMDRAW := 0x00000020
    static CDDS_PREPAINT := 0x00000001
    static CDDS_ITEMPREPAINT := 0x00010001
    static DC_BRUSH := 18
    static OHWND := 0
    static OMsg := (2 * A_PtrSize)
    static ODrawStage := OMsg + A_PtrSize
    static OHDC := ODrawStage + A_PtrSize
    static ORect := OHDC + A_PtrSize
    static OItemSpec := OHDC + 16 + A_PtrSize
    static LM := 4
    static TM := 6
    static TRANSPARENT := 1
    if (uMsg = 0x4E) {
        HWND := NumGet(lParam + OHWND, "UPtr")
        if _Dark.HeaderColors.Has(HWND) && HC := _Dark.HeaderColors[HWND] {
            Code := NumGet(lParam + OMsg, "Int")
            if (Code = NM_CUSTOMDRAW) {
                DrawStage := NumGet(lParam + ODrawStage, "UInt")
                if (DrawStage = CDDS_ITEMPREPAINT) {
                    Item := NumGet(lParam + OItemSpec, "Ptr")
                    HDITEM := Buffer(24 + (6 * A_PtrSize), 0)
                    ItemTxt := Buffer(520, 0)
                    NumPut("UInt", 0x86, HDITEM, 0)
                    NumPut("ptr", ItemTxt.Ptr, HDITEM, 8)
                    NumPut("int", 260, HDITEM, 8 + (2 * A_PtrSize))
                    DllCall("SendMessage", "Ptr", HWND, "UInt", HDM_GETITEM, "Ptr", Item, "Ptr", HDITEM)
                    Fmt := NumGet(HDITEM, 12 + (2 * A_PtrSize), "UInt") & 3
                    Order := NumGet(HDITEM, 20 + (3 * A_PtrSize), "Int")
                    HDC := NumGet(lParam + OHDC, "Ptr")
                    if (Item = 0) && (Order = 0)
                        NumPut("Int", NumGet(lParam, ORect, "Int") + LM, lParam + ORect)
                    dcBrush := DllCall("GetStockObject", "UInt", DC_BRUSH, "ptr")
                    DllCall("SetDCBrushColor", "Ptr", HDC, "UInt", HC["Bkg"])
                    DllCall("FillRect", "Ptr", HDC, "Ptr", lParam + ORect, "Ptr", dcBrush)
                    if (Item = 0) && (Order = 0)
                        NumPut("Int", NumGet(lParam, ORect, "Int") - LM, lParam, ORect)
                    DllCall("SetBkMode", "Ptr", HDC, "UInt", TRANSPARENT)
                    DllCall("SetTextColor", "Ptr", HDC, "UInt", 0xFFFFFF)
                    DllCall("InflateRect", "Ptr", lParam + ORect, "Int", -TM, "Int", 0)
                    DT_ALIGN := 0x0224 + ((Fmt & 1) ? 2 : (Fmt & 2) ? 1 : 0)
                    DllCall("DrawText", "Ptr", HDC, "Ptr", ItemTxt, "Int", -1, "Ptr", lParam + ORect, "UInt", DT_ALIGN)
                    return CDRF_SKIPDEFAULT
                }
                return (DrawStage = CDDS_PREPAINT) ? CDRF_NOTIFYITEMDRAW : CDRF_DODEFAULT
            }
        }
    } else if (uMsg = 0x02) {
        if _Dark.ControlCallbacks.Has(hWnd) {
            callback := _Dark.ControlCallbacks[hWnd]
            DllCall("RemoveWindowSubclass", "Ptr", hWnd, "Ptr", callback, "Ptr", hWnd)
            CallbackFree(callback)
            _Dark.ControlCallbacks.Delete(hWnd)
        }
    }
    return DllCall("DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

class _Dark {
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
        } else if (StructClass.Prototype.__Class = "NMCUSTOMDRAW") {
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

    static DarkColors := Map("Background", 0x171717, "Controls", 0x202020, "Font", 0xFFFFFF)
    static Dark := Map("Background", 0x171717, "Controls", 0x1b1b1b, "ComboBoxBg", 0x1E1E1E, "Font", 0xE0E0E0, "SliderThumb", 0x3E3E3E, "SliderTrack", 0x2D2D2D, "ProgressFill", 0x0078D7)
    static Instances := Map()
    static WindowProcOldMap := Map()
    static WindowProcCallbacks := Map()
    static TextBackgroundBrush := 0
    static ControlsBackgroundBrush := 0
    static ButtonColors := Map()
    static ComboBoxes := Map()
    static ListViewHeaders := Map()
    static HeaderCallbacks := Map()
    static CheckboxTextControls := Map()
    static TextControls := Map()
    static DarkCheckboxPairs := Map()
    static DarkRadioPairs := Map()
    static GroupBoxes := Map()
    static RadioButtons := Map()
    static SliderControls := Map()
    static ProgressControls := Map()
    static DateTimeControls := Map()
    static TabControls := Map()
    static ListBoxControls := Map()
    static TreeViewControls := Map()
    static ControlCallbacks := Map()
    static HeaderColors := Map()
    static WM_CTLCOLOREDIT := 0x0133
    static WM_CTLCOLORLISTBOX := 0x0134
    static WM_CTLCOLORBTN := 0x0135
    static WM_CTLCOLORSTATIC := 0x0138
    static WM_NOTIFY := 0x004E
    static WM_PAINT := 0x000F
    static WM_ERASEBKGND := 0x0014
    static DC_BRUSH := 18
    static GWL_WNDPROC := -4
    static GWL_STYLE := -16
    static GetWindowLong := A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong"
    static SetWindowLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"

    static __New() {
        global _Dark_WindowProc := ObjBindMethod(_Dark, "ProcessWindowMessage")
        if (!_Dark.TextBackgroundBrush)
            _Dark.TextBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", _Dark.Dark["Background"], "Ptr")
        if (!_Dark.ControlsBackgroundBrush)
            _Dark.ControlsBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", _Dark.Dark["Controls"], "Ptr")
    }

    static ProcessWindowMessage(hwnd, msg, wParam, lParam, *) {
        static WM_CTLCOLOREDIT := 0x0133
        static WM_CTLCOLORLISTBOX := 0x0134
        static WM_CTLCOLORBTN := 0x0135
        static WM_CTLCOLORSTATIC := 0x0138
        static WM_NOTIFY := 0x004E
        static TRANSPARENT := 1
        static NM_CUSTOMDRAW := -12
        static CDDS_PREPAINT := 0x00000001
        static CDDS_ITEMPREPAINT := 0x00010001
        static CDRF_DODEFAULT := 0x0
        static CDRF_NOTIFYITEMDRAW := 0x00000020
        if _Dark.WindowProcOldMap.Has(hwnd) {
            oldProc := _Dark.WindowProcOldMap[hwnd]
        } else {
            return DllCall("DefWindowProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
        }
        ctrlHwnd := lParam
        switch msg {
            case WM_CTLCOLOREDIT, WM_CTLCOLORLISTBOX:
                DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0xFFFFFF)
                DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _Dark.Dark["Controls"])
                DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                return _Dark.ControlsBackgroundBrush
            case WM_CTLCOLORBTN:
                if _Dark.ButtonColors.Has(ctrlHwnd) {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0xFFFFFF)
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _Dark.ButtonColors[ctrlHwnd]["bg"])
                    DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                    return _Dark.ControlsBackgroundBrush
                }
            case WM_CTLCOLORSTATIC:
                if _Dark.TextControls.Has(ctrlHwnd) || _Dark.GroupBoxes.Has(ctrlHwnd) || _Dark.DarkCheckboxPairs.Has(ctrlHwnd) || _Dark.DarkRadioPairs.Has(ctrlHwnd) {
                    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0xFFFFFF)
                    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", _Dark.Dark["Background"])
                    DllCall("gdi32\SetBkMode", "Ptr", wParam, "Int", TRANSPARENT)
                    return _Dark.TextBackgroundBrush
                }
        }
        return DllCall("CallWindowProc", "Ptr", oldProc, "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    static SetWindowPos(hWnd, hWndInsertAfter, X := 0, Y := 0, cx := 0, cy := 0, uFlags := 0x40) {
        return DllCall("User32\SetWindowPos", "ptr", hWnd, "ptr", hWndInsertAfter, "int", X, "int", Y, "int", cx, "int", cy, "uint", uFlags, "int")
    }

    static SendMessage(msg, wParam, lParam, hwndOrControl) {
        hwnd := HasProp(hwndOrControl, "Hwnd") ? hwndOrControl.Hwnd : hwndOrControl
        return DllCall("user32\SendMessage", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    static SetTextColor(hdc, color) {
        return DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", color)
    }

    static SetBkMode(hdc, mode) {
        return DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", mode)
    }

    __New(GuiObj) {
        _Dark.__New()
        this.Gui := GuiObj
        this.darkCheckboxes := Map()
        this.darkRadios := Map()
        this.radioGroups := Map()
        this.Gui.BackColor := _Dark.Dark["Background"]
        if (VerCompare(A_OSVersion, "10.0.17763") >= 0) {
            DWMWA_USE_IMMERSIVE_DARK_MODE := 19
            if (VerCompare(A_OSVersion, "10.0.18985") >= 0)
                DWMWA_USE_IMMERSIVE_DARK_MODE := 20
            uxtheme := DllCall("kernel32\GetModuleHandle", "Str", "uxtheme", "Ptr")
            SetPreferredAppMode := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
            FlushMenuThemes := DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr")
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.Gui.hWnd, "Int", DWMWA_USE_IMMERSIVE_DARK_MODE, "Int*", true, "Int", 4)
            DllCall(SetPreferredAppMode, "Int", 2)
            DllCall(FlushMenuThemes)
        }
        this.SetControlsTheme()
        this.SetupWindowProc()
        this.RedrawAllControls()
        _Dark.Instances[this.Gui.Hwnd] := this
        return this
    }

    SetupWindowProc() {
        hwnd := this.Gui.Hwnd
        if _Dark.WindowProcOldMap.Has(hwnd)
            return
        callback := CallbackCreate(_Dark_WindowProc, , 4)
        _Dark.WindowProcCallbacks[hwnd] := callback
        originalProc := DllCall(_Dark.SetWindowLong, "Ptr", hwnd, "Int", _Dark.GWL_WNDPROC, "Ptr", callback, "Ptr")
        _Dark.WindowProcOldMap[hwnd] := originalProc
    }

    SetTheme(themeMap) {
        if themeMap.Has("Background")
            _Dark.Dark["Background"] := themeMap["Background"]
        if themeMap.Has("Controls")
            _Dark.Dark["Controls"] := themeMap["Controls"]
        if themeMap.Has("Font")
            _Dark.Dark["Font"] := themeMap["Font"]
        this.Gui.BackColor := _Dark.Dark["Background"]
        if (_Dark.TextBackgroundBrush) {
            DllCall("DeleteObject", "Ptr", _Dark.TextBackgroundBrush)
            _Dark.TextBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", _Dark.Dark["Background"], "Ptr")
        }
        if (_Dark.ControlsBackgroundBrush) {
            DllCall("DeleteObject", "Ptr", _Dark.ControlsBackgroundBrush)
            _Dark.ControlsBackgroundBrush := DllCall("gdi32\CreateSolidBrush", "UInt", _Dark.Dark["Controls"], "Ptr")
        }
        this.RedrawAllControls()
    }

    AddDarkCheckBox(Options, Text) {
        static SM_CXMENUCHECK := 71
        static SM_CYMENUCHECK := 72
        static checkBoxW := SysGet(SM_CXMENUCHECK)
        static checkBoxH := SysGet(SM_CYMENUCHECK)
        chbox := this.Gui.AddCheckBox(Options " r1.5 +0x4000000", "")
        if !InStr(Options, "right")
            txt := this.Gui.AddText("xp+" (checkBoxW + 8) " yp+2 HP-4 +0x4000200 cFFFFFF", Text)
        else
            txt := this.Gui.AddText("xp+8 yp+2 HP-4 +0x4000200 cFFFFFF", Text)
        this.darkCheckboxes[chbox.Hwnd] := txt
        chbox.DeleteProp("Text")
        chbox.DefineProp("Text", { Get: ObjBindMethod(txt, "GetText"), Set: ObjBindMethod(txt, "SetText") })
        _Dark.SetWindowPos(txt.Hwnd, 0, 0, 0, 0, 0, 0x43)
        DllCall("uxtheme\SetWindowTheme", "Ptr", chbox.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        pair := Map()
        pair["checkbox"] := chbox
        pair["text"] := txt
        _Dark.DarkCheckboxPairs[chbox.Hwnd] := pair
        DllCall("InvalidateRect", "Ptr", chbox.Hwnd, "Ptr", 0, "Int", true)
        DllCall("InvalidateRect", "Ptr", txt.Hwnd, "Ptr", 0, "Int", true)
        return chbox
    }

    AddListView(Options, Headers) {
        lv := this.Gui.Add("ListView", Options, Headers)
        static LVM_SETBKCOLOR := 0x1001
        static LVM_SETTEXTCOLOR := 0x1033
        static LVM_SETTEXTBKCOLOR := 0x1026
        static LVM_GETHEADER := 0x101F
        static LVM_SETOUTLINECOLOR := 0x10B1
        static LVS_EX_DOUBLEBUFFER := 0x10000
        static LVS_EX_GRIDLINES := 0x00000001
        static LVM_SETEXTENDEDLISTVIEWSTYLE := 0x1036
        static UIS_SET := 1
        static UISF_HIDEFOCUS := 0x1
        static WM_CHANGEUISTATE := 0x0127
        static WM_THEMECHANGED := 0x031A

        Background := _Dark.Dark["Background"]
        Foreground := 0xFFFFFF
        GridColor := 0x1A1A1A  ; Very dark grey for grid lines

        ; Set basic colors (don't change these - user specified)
        _Dark.SendMessage(LVM_SETBKCOLOR, 0, Background, lv.hWnd)
        _Dark.SendMessage(LVM_SETTEXTCOLOR, 0, Foreground, lv.hWnd)
        _Dark.SendMessage(LVM_SETTEXTBKCOLOR, 0, Background, lv.hWnd)

        ; Enable gridlines first, then set color
        _Dark.SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, LVS_EX_GRIDLINES, LVS_EX_GRIDLINES, lv.hWnd)
        _Dark.SendMessage(LVM_SETOUTLINECOLOR, 0, GridColor, lv.hWnd)

        HeaderHwnd := _Dark.SendMessage(LVM_GETHEADER, 0, 0, lv.Hwnd)
        lv.Header := HeaderHwnd
        DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        DllCall("uxtheme\SetWindowTheme", "Ptr", HeaderHwnd, "Str", "", "Ptr", 0)
        lv.Opt("+Grid +LV" LVS_EX_DOUBLEBUFFER)
        _Dark.SendMessage(WM_CHANGEUISTATE, (UIS_SET << 8) | UISF_HIDEFOCUS, 0, lv.Hwnd)
        lv.OnMessage(WM_THEMECHANGED, (*) => 0)
        _Dark.SetListViewHeaderColors(lv, _Dark.Dark["Controls"], 0xFFFFFF)
        lv.SetFont("cFFFFFF")

        ; Force grid color update after everything is set up
        SetTimer(() => _Dark.SendMessage(LVM_SETOUTLINECOLOR, 0, GridColor, lv.hWnd), -100)

        DllCall("InvalidateRect", "Ptr", HeaderHwnd, "Ptr", 0, "Int", true)
        DllCall("InvalidateRect", "Ptr", lv.Hwnd, "Ptr", 0, "Int", true)
        DllCall("UpdateWindow", "Ptr", HeaderHwnd)
        DllCall("UpdateWindow", "Ptr", lv.Hwnd)
        return lv
    }

    static SetListViewHeaderColors(ListViewCtrl, BackgroundColor?, TextColor?) {
        HHDR := _Dark.SendMessage(0x101F, 0, 0, ListViewCtrl.Hwnd)
        if !(IsSet(BackgroundColor) || IsSet(TextColor)) && (_Dark.HeaderColors.Has(HHDR)) {
            return (_Dark.HeaderColors.Delete(HHDR), DllCall("RedrawWindow", "Ptr", ListViewCtrl.Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0001))
        } else if (IsSet(BackgroundColor) && IsSet(TextColor)) {
            if !(_Dark.HeaderColors.Has(HHDR)) {
                _Dark.SubclassControl(ListViewCtrl, _DarkHeaderCustomDrawCallback)
            }
            BackgroundColor := _Dark.RGBtoBGR(BackgroundColor)
            TextColor := TextColor = 0xFFFFFF ? 0xFFFFFF : _Dark.RGBtoBGR(TextColor)
            _Dark.HeaderColors[HHDR] := Map("Txt", TextColor, "Bkg", BackgroundColor)
        }
        DllCall("RedrawWindow", "Ptr", ListViewCtrl.Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0001)
    }

    static SubclassSlider(sliderControl) {
        if _Dark.ControlCallbacks.Has(sliderControl.Hwnd) {
            DllCall("RemoveWindowSubclass", "Ptr", sliderControl.Hwnd, "Ptr", _Dark.ControlCallbacks[sliderControl.Hwnd], "Ptr", sliderControl.Hwnd)
            CallbackFree(_Dark.ControlCallbacks[sliderControl.Hwnd])
            _Dark.ControlCallbacks.Delete(sliderControl.Hwnd)
        }
        _Dark.SliderControls[sliderControl.Hwnd]["state"] := "normal"
        CB := CallbackCreate(_DarkSliderCustomDrawCallback, "F", 6)
        if CB && DllCall("SetWindowSubclass", "Ptr", sliderControl.Hwnd, "Ptr", CB, "Ptr", sliderControl.Hwnd, "Ptr", 0) {
            _Dark.ControlCallbacks[sliderControl.Hwnd] := CB
            return true
        }
        if CB
            CallbackFree(CB)
        return false
    }

    static SubclassControl(HCTL, FuncObj, Data := 0) {
        if _Dark.ControlCallbacks.Has(HCTL) {
            DllCall("RemoveWindowSubclass", "Ptr", HCTL.Hwnd, "Ptr", _Dark.ControlCallbacks[HCTL], "Ptr", HCTL.Hwnd)
            CallbackFree(_Dark.ControlCallbacks[HCTL])
            _Dark.ControlCallbacks.Delete(HCTL)
        }
        if !(FuncObj is Func && FuncObj.MaxParams == 6) && FuncObj != "" {
            return false
        }
        if FuncObj == "" {
            return true
        }
        CB := CallbackCreate(FuncObj, "F", 6)
        if !CB {
            return false
        }
        if !DllCall("SetWindowSubclass", "Ptr", HCTL.Hwnd, "Ptr", CB, "Ptr", HCTL.Hwnd, "Ptr", Data) {
            CallbackFree(CB)
            return false
        }
        return (_Dark.ControlCallbacks[HCTL] := CB)
    }

    static RGBtoBGR(RGB) {
        if (!IsNumber(RGB)) {
            RGB := "0x" . RGB
        }
        return ((RGB & 0xFF) << 16) | (RGB & 0xFF00) | ((RGB & 0xFF0000) >> 16)
    }

    AddDarkButton(Options, Text) {
        btn := this.Gui.AddButton(Options, Text)
        DllCall("uxtheme\SetWindowTheme", "Ptr", btn.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        buttonColorMap := Map("bg", _Dark.Dark["Controls"], "text", _Dark.Dark["Font"])
        _Dark.ButtonColors[btn.Hwnd] := buttonColorMap
        btn.SetFont("cFFFFFF")
        DllCall("InvalidateRect", "Ptr", btn.hWnd, "Ptr", 0, "Int", true)
        return btn
    }

    AddDarkEdit(Options, Text := "") {
        edit := this.Gui.AddEdit(Options, Text)
        DllCall("uxtheme\SetWindowTheme", "Ptr", edit.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        edit.SetFont("cFFFFFF")
        if InStr(Options, "ReadOnly") {
            DllCall("SendMessage", "Ptr", edit.hWnd, "UInt", 0x000C, "Ptr", 0, "AStr", Text)
            static SWP_FRAMECHANGED := 0x0020
            static SWP_NOMOVE := 0x0002
            static SWP_NOSIZE := 0x0001
            _Dark.SetWindowPos(edit.hWnd, 0, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE)
        }
        DllCall("InvalidateRect", "Ptr", edit.hWnd, "Ptr", 0, "Int", true)
        return edit
    }

    AddDarkComboBox(Options, Items := "") {
        ; Calculate dropdown height based on number of items
        itemCount := Items is Array ? Items.Length : (Items != "" ? StrSplit(Items, "|").Length : 0)
        itemHeight := 18  ; Height per item in dropdown
        baseHeight := 25  ; Base height for edit portion
        dropdownHeight := baseHeight + (itemCount * itemHeight) + 6  ; Add padding

        ; Remove h0 if present and replace with calculated height
        Options := RegExReplace(Options, "\bh0\b", "")
        if RegExMatch(Options, "h\d+", &match) {
            Options := StrReplace(Options, match[0], "h" . dropdownHeight)
        } else {
            Options .= " h" . dropdownHeight
        }

        combo := this.Gui.AddComboBox(Options, Items)
        DllCall("uxtheme\SetWindowTheme", "Ptr", combo.hWnd, "Str", "DarkMode_CFD", "Ptr", 0)
        _Dark.ComboBoxes[combo.Hwnd] := true
        combo.SetFont("cFFFFFF")
        DllCall("InvalidateRect", "Ptr", combo.hWnd, "Ptr", 0, "Int", true)
        return combo
    }

    AddDarkText(Options, Text := "") {
        txt := this.Gui.AddText(Options " cFFFFFF", Text)
        _Dark.TextControls[txt.Hwnd] := true
        DllCall("InvalidateRect", "Ptr", txt.Hwnd, "Ptr", 0, "Int", true)
        return txt
    }

    AddDarkGroupBox(Options, Text := "") {
        groupBox := this.Gui.AddGroupBox(Options, Text)
        DllCall("uxtheme\SetWindowTheme", "Ptr", groupBox.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        groupBox.SetFont("cFFFFFF")
        _Dark.GroupBoxes[groupBox.Hwnd] := true
        DllCall("InvalidateRect", "Ptr", groupBox.hWnd, "Ptr", 0, "Int", true)
        DllCall("UpdateWindow", "Ptr", groupBox.hWnd)
        return groupBox
    }

    AddDarkRadio(Options, Text := "", GroupName := "DefaultRadioGroup", GuiInstance := "") {
        static SM_CXMENUCHECK := 71
        static SM_CYMENUCHECK := 72
        static radioW := SysGet(SM_CXMENUCHECK)
        static radioH := SysGet(SM_CYMENUCHECK)
        radio := this.Gui.AddRadio(Options " r1.5 +0x4000000", "")
        if !InStr(Options, "right")
            txt := this.Gui.AddText("xp+" (radioW + 8) " yp+2 HP-4 +0x4000200 cFFFFFF", Text)
        else
            txt := this.Gui.AddText("xp+8 yp+2 HP-4 +0x4000200 cFFFFFF", Text)
        this.darkRadios[radio.Hwnd] := txt
        radio.DeleteProp("Text")
        radio.DefineProp("Text", { Get: GetRadioText, Set: SetRadioText })
        GetRadioText(*) {
            return txt.Text
        }
        SetRadioText(value) {
            txt.Text := value
        }
        _Dark.SetWindowPos(txt.Hwnd, 0, 0, 0, 0, 0, 0x43)
        DllCall("uxtheme\SetWindowTheme", "Ptr", radio.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        pair := Map()
        pair["radio"] := radio
        pair["text"] := txt
        pair["group"] := GroupName
        _Dark.DarkRadioPairs[radio.Hwnd] := pair
        _Dark.RadioButtons[radio.Hwnd] := true
        if !this.radioGroups.Has(GroupName)
            this.radioGroups[GroupName] := []
        this.radioGroups[GroupName].Push(radio)
        if GuiInstance && GuiInstance.HasMethod("HandleRadioClick") {
            radio.OnEvent("Click", GuiInstance.HandleRadioClick.Bind(GuiInstance, radio, GroupName))
            txt.OnEvent("Click", (*) => this.HandleTextClick(radio, GroupName, GuiInstance))
        } else {
            radio.OnEvent("Click", this.HandleRadioClick.Bind(this, radio, GroupName))
            txt.OnEvent("Click", (*) => this.HandleTextClick(radio, GroupName, ""))
        }
        DllCall("InvalidateRect", "Ptr", radio.Hwnd, "Ptr", 0, "Int", true)
        DllCall("InvalidateRect", "Ptr", txt.Hwnd, "Ptr", 0, "Int", true)
        return radio
    }

    HandleRadioClick(clickedRadio, groupName, *) {
        if this.radioGroups.Has(groupName) {
            for radio in this.radioGroups[groupName] {
                if radio != clickedRadio {
                    radio.Value := 0
                }
            }
        }
    }

    HandleTextClick(radio, groupName, GuiInstance, *) {
        radio.Value := 1
        if GuiInstance && GuiInstance.HasMethod("HandleRadioClick") {
            GuiInstance.HandleRadioClick(radio, groupName)
        } else {
            this.HandleRadioClick(radio, groupName)
        }
    }

    AddDarkListBox(Options, Items := "") {
        listBox := this.Gui.AddListBox(Options, Items)
        DllCall("uxtheme\SetWindowTheme", "Ptr", listBox.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        _Dark.ListBoxControls[listBox.Hwnd] := true
        listBox.SetFont("cFFFFFF")
        DllCall("InvalidateRect", "Ptr", listBox.hWnd, "Ptr", 0, "Int", true)
        return listBox
    }

    AddDarkSlider(Options, StartingValue := 0) {
        slider := this.Gui.AddSlider(Options, StartingValue)
        DllCall("uxtheme\SetWindowTheme", "Ptr", slider.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        _Dark.SliderControls[slider.Hwnd] := Map("hover", 0x3A3A3A, "active", 0x2A2A2A, "normal", 0x1A1A1A)
        _Dark.SubclassSlider(slider)
        DllCall("InvalidateRect", "Ptr", slider.hWnd, "Ptr", 0, "Int", true)
        return slider
    }

    AddDarkProgress(Options, StartingValue := 0) {
        progress := this.Gui.AddProgress(Options, StartingValue)

        ; Remove default theming first
        DllCall("uxtheme\SetWindowTheme", "Ptr", progress.hWnd, "Str", "", "Ptr", 0)

        ; Set lighter background color for progress bar
        lightBackgroundColor := 0x2A2A2A  ; Lighter than controls (0x1b1b1b)
        bgBGR := ((lightBackgroundColor & 0xFF) << 16) | (lightBackgroundColor & 0xFF00) | ((lightBackgroundColor & 0xFF0000) >> 16)

        ; Set progress bar background
        static PBM_SETBKCOLOR := 0x2001
        DllCall("SendMessage", "Ptr", progress.hWnd, "UInt", PBM_SETBKCOLOR, "Ptr", 0, "UInt", bgBGR)

        ; Set initial progress bar color (blue theme)
        startColorRGB := 0x0078D7
        progress.Opt("c" Format("{:X}", startColorRGB))

        ; Set up color changing for gradient effect
        endColorRGB := 0x34C1FB
        _Dark.ProgressControls[progress.Hwnd] := ChangeProgressColor(progress, endColorRGB)

        ; Force redraw
        DllCall("InvalidateRect", "Ptr", progress.hWnd, "Ptr", 0, "Int", true)
        DllCall("UpdateWindow", "Ptr", progress.hWnd)

        return progress
    }

    AddDarkDateTime(Options := "") {
        dateTime := this.Gui.AddDateTime(Options)
        DllCall("uxtheme\SetWindowTheme", "Ptr", dateTime.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        _Dark.DateTimeControls[dateTime.Hwnd] := true
        dateTime.SetFont("cFFFFFF")
        DllCall("InvalidateRect", "Ptr", dateTime.hWnd, "Ptr", 0, "Int", true)
        return dateTime
    }

    AddDarkTab3(Options, Tabs) {
        tab := this.Gui.AddTab3(Options, Tabs)
        DllCall("uxtheme\SetWindowTheme", "Ptr", tab.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        _Dark.TabControls[tab.Hwnd] := true
        tab.SetFont("cFFFFFF")
        DllCall("InvalidateRect", "Ptr", tab.hWnd, "Ptr", 0, "Int", true)
        return tab
    }

    AddDarkTreeView(Options := "") {
        treeView := this.Gui.AddTreeView(Options)
        static TVM_SETBKCOLOR := 0x111D
        static TVM_SETTEXTCOLOR := 0x111E
        static TVM_SETLINECOLOR := 0x1128
        DllCall("uxtheme\SetWindowTheme", "Ptr", treeView.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        _Dark.SendMessage(TVM_SETBKCOLOR, 0, 0x202020, treeView.hWnd)
        _Dark.SendMessage(TVM_SETTEXTCOLOR, 0, 0xFFFFFF, treeView.hWnd)
        _Dark.SendMessage(TVM_SETLINECOLOR, 0, 0x404040, treeView.hWnd)
        treeView.SetFont("cFFFFFF")
        _Dark.TreeViewControls[treeView.Hwnd] := true
        DllCall("InvalidateRect", "Ptr", treeView.hWnd, "Ptr", 0, "Int", true)
        DllCall("UpdateWindow", "Ptr", treeView.hWnd)
        return treeView
    }

    RedrawAllControls() {
        DllCall("RedrawWindow", "Ptr", this.Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0285)
        for hWnd, GuiCtrlObj in this.Gui {
            DllCall("RedrawWindow", "Ptr", GuiCtrlObj.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0001)
            DllCall("InvalidateRect", "Ptr", GuiCtrlObj.Hwnd, "Ptr", 0, "Int", true)
        }
    }

    SetControlsTheme() {
        for hWnd, GuiCtrlObj in this.Gui {
            switch GuiCtrlObj.Type {
                case "Button":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    buttonColorMap := Map("bg", _Dark.Dark["Controls"], "text", _Dark.Dark["Font"])
                    _Dark.ButtonColors[GuiCtrlObj.Hwnd] := buttonColorMap
                case "CheckBox", "Radio":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    if (GuiCtrlObj.Type == "Radio") {
                        _Dark.RadioButtons[GuiCtrlObj.Hwnd] := true
                    }
                case "ComboBox", "DDL":
                    _Dark.ComboBoxes[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_CFD", "Ptr", 0)
                case "Edit":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    GuiCtrlObj.SetFont("cFFFFFF")
                    style := DllCall(_Dark.GetWindowLong, "Ptr", GuiCtrlObj.hWnd, "Int", _Dark.GWL_STYLE, "Ptr")
                    if (style & 0x800) {
                        DllCall("InvalidateRect", "Ptr", GuiCtrlObj.hWnd, "Ptr", 0, "Int", true)
                        DllCall("UpdateWindow", "Ptr", GuiCtrlObj.hWnd)
                        static SWP_FRAMECHANGED := 0x0020, SWP_NOMOVE := 0x0002, SWP_NOSIZE := 0x0001
                        _Dark.SetWindowPos(GuiCtrlObj.hWnd, 0, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE)
                    }
                case "ListView":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    GuiCtrlObj.SetFont("cFFFFFF")
                case "ListBox", "UpDown":
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                case "Text", "Link":
                    _Dark.TextControls[GuiCtrlObj.Hwnd] := true
                    GuiCtrlObj.Opt("cFFFFFF")
                case "GroupBox":
                    _Dark.GroupBoxes[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    GuiCtrlObj.SetFont("cFFFFFF")
                    DllCall("InvalidateRect", "Ptr", GuiCtrlObj.hWnd, "Ptr", 0, "Int", true)
                    DllCall("UpdateWindow", "Ptr", GuiCtrlObj.hWnd)
                case "Slider":
                    _Dark.SliderControls[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                case "Progress":
                    _Dark.ProgressControls[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                case "DateTime":
                    _Dark.DateTimeControls[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    GuiCtrlObj.SetFont("cFFFFFF")
                case "Tab3":
                    _Dark.TabControls[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    GuiCtrlObj.SetFont("cFFFFFF")
                case "TreeView":
                    static TVM_SETBKCOLOR := 0x111D
                    static TVM_SETTEXTCOLOR := 0x111E
                    static TVM_SETLINECOLOR := 0x1128
                    _Dark.TreeViewControls[GuiCtrlObj.Hwnd] := true
                    DllCall("uxtheme\SetWindowTheme", "Ptr", GuiCtrlObj.hWnd, "Str", "DarkMode_Explorer", "Ptr", 0)
                    _Dark.SendMessage(TVM_SETBKCOLOR, 0, 0x202020, GuiCtrlObj.hWnd)
                    _Dark.SendMessage(TVM_SETTEXTCOLOR, 0, 0xFFFFFF, GuiCtrlObj.hWnd)
                    _Dark.SendMessage(TVM_SETLINECOLOR, 0, 0x404040, GuiCtrlObj.hWnd)
                    GuiCtrlObj.SetFont("cFFFFFF")
                    DllCall("UpdateWindow", "Ptr", GuiCtrlObj.hWnd)
            }
            DllCall("InvalidateRect", "Ptr", GuiCtrlObj.Hwnd, "Ptr", 0, "Int", true)
        }
    }
}

class ChangeProgressColor {
    static info := Map()
    static EVENT_OBJECT_DESTROY := 0x8001
    static EVENT_OBJECT_VALUECHANGE := 0x800E
    static Hook := ""

    __New(ProgressObj, secondColorRGB) {
        static PBM_GETRANGE := 0x407
        static PBM_GETBARCOLOR := 0x40F

        ; Store reference to the class
        classRef := ChangeProgressColor

        ; Initialize the data Map for this progress control
        data := Map()
        data.hGui := ProgressObj.Gui.hwnd
        data.CtrlObj := ProgressObj

        ; Store hwnd and add to class info
        this.hwnd := ProgressObj.hwnd
        classRef.info[this.hwnd] := data

        ; Get progress range
        SendMessage(PBM_GETRANGE, , PBRANGE := Buffer(8), ProgressObj)
        data.start := NumGet(PBRANGE, 0, 'Int')
        range := NumGet(PBRANGE, 4, 'Int') - data.start

        ; Get current color and calculate color steps
        startColorBGR := SendMessage(PBM_GETBARCOLOR, , , ProgressObj)
        classRef.SplitColor(startColorBGR, &rStart, &gStart, &bStart, 'BGR')
        classRef.SplitColor(secondColorRGB, &rEnd, &gEnd, &bEnd)

        ; Calculate color steps for gradient
        for v in ['r', 'g', 'b'] {
            data[v "Start"] := %v%Start
            data[v "Step"] := (%v%End - %v%Start) / range
        }

        ; Set up hook if this is the first progress control
        if classRef.info.Count = 1 {
            classRef.Hook := WinEventHook(
                classRef.EVENT_OBJECT_DESTROY,
                classRef.EVENT_OBJECT_VALUECHANGE,
                ObjBindMethod(classRef, 'HookProc'),
                'F',
                DllCall('GetCurrentProcessId')
            )
        }
    }

    __Delete() {
        classRef := ChangeProgressColor
        if !classRef.info.Has(this.hwnd)
            return
        classRef.info.Delete(this.hwnd)
        if !classRef.info.Count
            classRef.Hook := ''
    }

    static SplitColor(colorRGBorBGR, &r := 0, &g := 0, &b := 0, mode := 'RGB') {
        g := (colorRGBorBGR >> 8) & 0xFF
        r := (mode = 'RGB' ? colorRGBorBGR >> 16 : colorRGBorBGR & 0xFF)
        b := (mode = 'BGR' ? colorRGBorBGR >> 16 : colorRGBorBGR & 0xFF)
    }

    static HookProc(hWinEventHook, event, hwnd, idObject, *) {
        static OBJID_WINDOW := 0
        classRef := ChangeProgressColor

        if (event = classRef.EVENT_OBJECT_VALUECHANGE && classRef.info.Has(hwnd)) {
            data := classRef.info[hwnd]
            try
                value := data.CtrlObj.Value
            catch
                return
            r := g := b := 0
            for v in ['r', 'g', 'b'] {
                %v% := Round(data[v "Start"] + data[v "Step"] * (value - data.start))
                if (%v% > 255)
                    %v% := 255
                if (%v% < 0)
                    %v% := 0
            }
            data.CtrlObj.Opt(Format('c{:X}', r << 16 | g << 8 | b))
        }
        if (event = classRef.EVENT_OBJECT_DESTROY && idObject = OBJID_WINDOW) {
            found := []
            for hProgress, data in classRef.info {
                if (data.hGui = hwnd)
                    found.Push(hProgress)
            }
            for hProgress in found
                classRef.info.Delete(hProgress)
            if !classRef.info.Count
                classRef.Hook := ''
        }
    }
}

class WinEventHook {
    __New(eventMin, eventMax, hookProc, options := '', idProcess := 0, idThread := 0, dwFlags := 0) {
        this.pCallback := CallbackCreate(hookProc, options, 7)
        this.hHook := DllCall('SetWinEventHook', 'UInt', eventMin, 'UInt', eventMax, 'Ptr', 0, 'Ptr', this.pCallback, 'UInt', idProcess, 'UInt', idThread, 'UInt', dwFlags, 'Ptr')
    }
    __Delete() {
        DllCall('UnhookWinEvent', 'Ptr', this.hHook)
        CallbackFree(this.pCallback)
    }
}