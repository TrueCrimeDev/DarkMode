#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; Retrofitting. The window exists, controls and all, before dark mode is
; mentioned. DarkGui.Attach(gui) themes it in place and keeps styling whatever
; is added afterwards; DarkGui.Detach(gui) hands the controls back.

win := Gui("+Resize", "Attach / Detach")
win.SetFont("s10", "Segoe UI")
win.Add("Text", "x16 y16 w300", "Built as a plain Gui, then attached.")
win.Add("Edit", "x16 y44 w300 h26", "Edit created before Attach")
win.Add("ListBox", "x16 y80 w300 h72", ["One", "Two", "Three", "Four", "Five", "Six"])
win.Add("Slider", "x16 y160 w300 Range0-100", 40)
win.Add("Progress", "x16 y192 w300 h18", 40)
toggle := win.Add("Button", "x16 y222 w300 h30", "Detach (back to light)")
toggle.OnEvent("Click", ToggleDark)
win.OnEvent("Close", (*) => (ExitApp(), 0))

DarkGui.Attach(win)
; Added after Attach: styled automatically, no DarkGui in sight.
win.Add("CheckBox", "x16 y262 w300 +Checked", "Added after Attach, still dark")
win.Show("w332")

dark := true
ToggleDark(*) {
    global dark
    dark := !dark
    if dark {
        DarkGui.Attach(win)
    } else {
        DarkGui.Detach(win)
        win.BackColor := "Default"
    }
    toggle.Text := dark ? "Detach (back to light)" : "Attach (dark again)"
}
