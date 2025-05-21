; AutoHotkey v2 script for Dark Mode Test GUI

global g_arrBrushes := []
global UserSet_TextColor := 0xDDDDDD
global UserSet_BgColor := 0x333333
global UserSet_LightBgColor := 0x404040 ; For elements like ListView header
global UserSet_TitleBarColor := 0x222222 ; For custom title bar

global MyListViewHeaderHwnd := 0
global TitleBarPanelHwnd := 0
global TitleBarTextHwnd := 0
global MinimizeBtnHwnd := 0
global CloseBtnHwnd := 0

; Define WM_CTLCOLOR* Constants
WM_CTLCOLORSTATIC := 0x0138
WM_CTLCOLOREDIT := 0x0133
WM_CTLCOLORBTN := 0x0135
WM_CTLCOLORLISTBOX := 0x0134

; --- GUI Event Handlers ---
MinimizeGui(*) {
    MyGui.Minimize()
}

CloseGui(*) {
    MyGui.Destroy() ; Triggers MyGuiClose
}

; --- Custom Title Bar Dragging ---
Func_WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global TitleBarPanelHwnd, TitleBarTextHwnd, MyGui
    ; A_GuiControlHwnd is more reliable here if available, but hwnd is the direct window
    ; For simplicity, we check if the click was on the GUI window itself,
    ; and if the Y coordinate is within the title bar height.
    ; A more robust way is to check if hwnd is TitleBarPanelHwnd or TitleBarTextHwnd.
    ; This requires getting TitleBarPanel.Hwnd and TitleBarText.Hwnd after they are created.
    
    ControlHwnd := DllCall("WindowFromPoint", "int", lParam & 0xFFFF, "int", lParam >> 16, "ptr")

    if (ControlHwnd == TitleBarPanelHwnd || ControlHwnd == TitleBarTextHwnd) {
        PostMessage(0x00A1, 2, 0,, MyGui.Hwnd) ; WM_NCLBUTTONDOWN, HTCAPTION
        Return 0
    }
    Return ; Let other controls handle it
}


; Callback Functions for Control Theming
OnCtlColorStatic(wParam, lParam, msg, hwnd) {
    global g_arrBrushes, UserSet_TextColor, UserSet_BgColor, UserSet_LightBgColor, MyListViewHeaderHwnd
    global TitleBarPanelHwnd, TitleBarTextHwnd, UserSet_TitleBarColor
    
    local bgColor := UserSet_BgColor ; Default background
    local textColor := UserSet_TextColor ; Default text color

    if (MyListViewHeaderHwnd != 0 && hwnd == MyListViewHeaderHwnd) {
        bgColor := UserSet_LightBgColor
    } else if (TitleBarPanelHwnd != 0 && hwnd == TitleBarPanelHwnd) {
        bgColor := UserSet_TitleBarColor
    } else if (TitleBarTextHwnd != 0 && hwnd == TitleBarTextHwnd) {
        bgColor := UserSet_TitleBarColor 
        textColor := UserSet_TextColor 
    }
    
    DllCall("gdi32\SetTextColor", "ptr", wParam, "int", textColor, "int")
    DllCall("gdi32\SetBkColor", "ptr", wParam, "int", bgColor, "int")
    hBrush := DllCall("gdi32\CreateSolidBrush", "int", bgColor, "ptr")
    g_arrBrushes.Push(hBrush)
    Return hBrush
}

OnCtlColorEdit(wParam, lParam, msg, hwnd) {
    global g_arrBrushes, UserSet_TextColor, UserSet_BgColor
    DllCall("gdi32\SetTextColor", "ptr", wParam, "int", UserSet_TextColor, "int")
    DllCall("gdi32\SetBkColor", "ptr", wParam, "int", UserSet_BgColor, "int")
    hBrush := DllCall("gdi32\CreateSolidBrush", "int", UserSet_BgColor, "ptr")
    g_arrBrushes.Push(hBrush)
    Return hBrush
}

OnCtlColorBtn(wParam, lParam, msg, hwnd) {
    global g_arrBrushes, UserSet_TextColor, UserSet_BgColor, UserSet_TitleBarColor
    global MinimizeBtnHwnd, CloseBtnHwnd
    
    local bgColor := UserSet_BgColor ; Default button background

    if ((MinimizeBtnHwnd != 0 && hwnd == MinimizeBtnHwnd) || (CloseBtnHwnd != 0 && hwnd == CloseBtnHwnd)) {
        bgColor := UserSet_TitleBarColor ; Title bar buttons background
    }
    
    DllCall("gdi32\SetTextColor", "ptr", wParam, "int", UserSet_TextColor, "int")
    DllCall("gdi32\SetBkMode", "ptr", wParam, "int", 1) ; 1 for TRANSPARENT
    hBrush := DllCall("gdi32\CreateSolidBrush", "int", bgColor, "ptr")
    g_arrBrushes.Push(hBrush)
    Return hBrush
}

OnCtlColorListView(wParam, lParam, msg, hwnd) {
    global g_arrBrushes, UserSet_TextColor, UserSet_BgColor
    DllCall("gdi32\SetTextColor", "ptr", wParam, "int", UserSet_TextColor, "int")
    DllCall("gdi32\SetBkColor", "ptr", wParam, "int", UserSet_BgColor, "int")
    hBrush := DllCall("gdi32\CreateSolidBrush", "int", UserSet_BgColor, "ptr")
    g_arrBrushes.Push(hBrush)
    Return hBrush
}

; --- Menu Handlers ---
FileExit() {
    MyGui.Destroy()
}

HelpAbout() {
    MsgBox("Dark Mode Test GUI v1.0`nImplemented in AutoHotkey v2", "About", "i")
}

; --- GUI Definition ---
WindowWidth := 320 ; Define a window width for layout
TitleBarHeight := 35

MyGui := Gui(, "Dark Mode Test")
MyGui.Opt("-Caption") ; Make window frameless - MUST be before controls are added
MyGui.BackColor := UserSet_BgColor
MyGui.SetFont("c" . Format("{:X}", UserSet_TextColor))

; Custom Title Bar Elements
global TitleBarPanel := MyGui.Add("Text", "x0 y0 w" . WindowWidth . " h" . TitleBarHeight . " Background" . Format("{:06X}", UserSet_TitleBarColor))
global TitleBarText := MyGui.Add("Text", "x10 y5 w" . (WindowWidth - 80) . " h25 Background" . Format("{:06X}", UserSet_TitleBarColor) . " c" . Format("{:06X}", UserSet_TextColor), "Dark Mode Test")
global MinimizeBtn := MyGui.Add("Button", "x" . (WindowWidth - 65) . " y5 w30 h25", "_")
global CloseBtn := MyGui.Add("Button", "x" . (WindowWidth - 35) . " y5 w30 h25", "X")

; Store HWNDs for theming and dragging
TitleBarPanelHwnd := TitleBarPanel.Hwnd
TitleBarTextHwnd := TitleBarText.Hwnd
MinimizeBtnHwnd := MinimizeBtn.Hwnd
CloseBtnHwnd := CloseBtn.Hwnd

MinimizeBtn.OnEvent("Click", MinimizeGui)
CloseBtn.OnEvent("Click", CloseGui)

; Create and Theme MenuBar (Positioned below custom title bar)
MyMenuBar := MenuBar()
FileMenu := Menu()
FileMenu.Add("Exit", FileExit)
HelpMenu := Menu()
HelpMenu.Add("About", HelpAbout)
MyMenuBar.Add("File", FileMenu)
MyMenuBar.Add("Help", HelpMenu)
MyGui.MenuBar := MyMenuBar ; This will place it at the top of the client area, below the custom title bar if y offset is used for subsequent controls.
MyMenuBar.SetColor(UserSet_BgColor)

; Apply -Theme option to the GUI (classic controls)
MyGui.Opt("-Theme")

; Register Callbacks for WM_CTLCOLOR* messages
OnMessage(WM_CTLCOLORSTATIC, OnCtlColorStatic)
OnMessage(WM_CTLCOLOREDIT, OnCtlColorEdit)
OnMessage(WM_CTLCOLORBTN, OnCtlColorBtn)
OnMessage(WM_CTLCOLORLISTBOX, OnCtlColorListView)
OnMessage(0x0201, Func_WM_LBUTTONDOWN) ; WM_LBUTTONDOWN for dragging

; Adjust Y offset for subsequent controls to be below the title bar and menubar
CurrentY := TitleBarHeight

; Text control
MyGui.Add("Text", "x10 y" . (CurrentY + 10), "This is sample text.")

; Edit control
MyGui.Add("Edit", "x10 y" . (CurrentY + 40) . " w200", "Edit me.")

; Button
MyGui.Add("Button", "x10 y" . (CurrentY + 70) . " Default", "Click Me")

; ListView
MyListView := MyGui.Add("ListView", "x10 y" . (CurrentY + 100) . " w250 r5 vMyListView", ["Header 1", "Header 2"])
MyListView.Add(,"Row 1 Col 1", "Row 1 Col 2")
MyListView.Add(,"Row 2 Col 1", "Row 2 Col 2")

; Attempt to Theme ListView Header (Must be after ListView is created)
if MyListView.Hwnd {
    LVM_GETHEADER := 0x101F
    global MyListViewHeaderHwnd := DllCall("SendMessage", "ptr", MyListView.Hwnd, "int", LVM_GETHEADER, "ptr", 0, "ptr", 0)
    if MyListViewHeaderHwnd {
        DllCall("UxTheme\SetWindowTheme", "ptr", MyListViewHeaderHwnd, "ptr", 0, "wstr", "")
        DllCall("RedrawWindow", "ptr", MyListViewHeaderHwnd, "ptr", 0, "ptr", 0, "int", 0x0101)
    }
}

; ComboBox
CB := MyGui.Add("ComboBox", "x10 y" . (CurrentY + 200) . " w200")
CB.Add(["Choice 1", "Choice 2", "Choice 3"])
CB.Choose(1)

; GroupBox
MyGui.Add("GroupBox", "x10 y" . (CurrentY + 230) . " w250 h50", "Sample GroupBox")

; CheckBox
MyGui.Add("CheckBox", "x20 y" . (CurrentY + 250) . " vMyCheck", "Sample CheckBox")

; Radio button
MyGui.Add("Radio", "x120 y" . (CurrentY + 250) . " vMyRadio", "Sample Radio")

; Show the GUI
MyGui.Show("w" . WindowWidth . " h" . (CurrentY + 300)) ; Adjust height as needed

return

MyGuiClose(GuiObj) {
    global g_arrBrushes
    for brush in g_arrBrushes {
        if brush DllCall("gdi32\DeleteObject", "ptr", brush)
    }
    g_arrBrushes := []
    ExitApp
}
