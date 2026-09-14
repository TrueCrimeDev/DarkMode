#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; DarkMenuBar: a dark menu strip with popup menus and an icon toolbar row,
; wired through WM_COMMAND, plus a multi-part StatusBar, dark dialogs and a
; DarkToolTip.Show tip.

CMD_NEW := 101, CMD_OPEN := 102, CMD_EXIT := 103, CMD_SELECTALL := 201, CMD_ABOUT := 301

app := DarkGui("+Resize", "Menu bar and toolbar")
app.SetFont("s10", "Segoe UI")
DarkDialogs.Install()

opts := Map()
opts["showToolbar"] := true
bar := DarkMenuBar(app, opts)
file := bar.AddMenu("File")
file.Item("New", CMD_NEW, "Ctrl+N")
file.Item("Open", CMD_OPEN, "Ctrl+O")
file.Sep()
file.Item("Exit", CMD_EXIT)
edit := bar.AddMenu("Edit")
edit.Item("Select all", CMD_SELECTALL, "Ctrl+A")
help := bar.AddMenu("Help")
help.Item("About", CMD_ABOUT)
bar.AddToolbarButton("+", "New (Ctrl+N)", (*) => (Command(CMD_NEW), 0))
bar.AddToolbarButton("O", "Open (Ctrl+O)", (*) => (Command(CMD_OPEN), 0))
bar.AddToolbarButton("?", "About", (*) => (Command(CMD_ABOUT), 0))

top := bar.totalHeight
editor := app.Add("Edit", "x0 y" top " w520 h300 +Multi +WantTab", "Type here.`r`nThe strip above is a DarkMenuBar; the row of icons is its toolbar.")
status := app.Add("StatusBar")
status.SetParts(160, 140)
status.SetText("Ready", 1)
status.SetText("Plain text", 2)
status.SetText("UTF-8", 3)

OnMessage(0x0111, OnCommand)
app.OnEvent("Size", OnSize)
app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w520 h" (top + 324))

; WM_COMMAND: popup menu items arrive here with their id in the low word.
OnCommand(wParam, lParam, msg, hwnd) {
    if hwnd = app.Hwnd && (wParam & 0xFFFF) >= 100
        Command(wParam & 0xFFFF)
}

OnSize(g, minMax, w, h) {
    if minMax = -1
        return
    editor.Move(0, top, w, h - top - 24)
}

Command(id) {
    switch id {
        case CMD_NEW:
            editor.Value := ""
            status.SetText("New document", 1)
        case CMD_OPEN:
            status.SetText("Open is a demo stub", 1)
            DarkToolTip.Show("Open is a demo stub", 1500)
        case CMD_SELECTALL:
            editor.Focus()
            SendMessage(0x00B1, 0, -1, editor)
        case CMD_ABOUT:
            MsgBox("Dark menu bar, toolbar, status bar and dialogs, all from DarkModeModular.ahk.", "About")
        case CMD_EXIT:
            ExitApp()
    }
}
