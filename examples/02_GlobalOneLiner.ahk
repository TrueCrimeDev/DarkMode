#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; One line makes every window in the script dark. DarkGui.Global() hooks the
; Gui constructor, so a plain Gui(), a class that extends Gui, and windows
; that other libraries create are all attached the moment they exist. It also
; installs DarkDialogs, so MsgBox and InputBox come out dark as well.
DarkGui.Global()

; A plain Gui: nothing here mentions dark mode.
main := Gui("+Resize", "Global: plain Gui()")
main.SetFont("s10", "Segoe UI")
main.Add("Text", "x16 y16 w300", "This window was created with plain Gui().")
main.Add("Edit", "x16 y44 w300 h26", "So was this Edit.")
main.Add("DropDownList", "x16 y80 w300 Choose1", ["And this list", "Second", "Third"])
main.Add("Button", "+Accent x16 y118 w148 h30", "Open a class window").OnEvent("Click", (*) => (SettingsWindow().Show(), 0))
main.Add("Button", "x172 y118 w144 h30", "Ask something").OnEvent("Click", AskSomething)
main.OnEvent("Close", (*) => (ExitApp(), 0))
main.Show("w332")

AskSomething(*) {
    answer := InputBox("InputBox is dark as well.", "Global dialogs", "w320 h130")
    if answer.Result = "OK"
        MsgBox("You typed: " answer.Value, "Global dialogs")
}

; A class that extends Gui is attached too, controls included.
class SettingsWindow extends Gui {
    __New() {
        super.__New("+Owner", "Global: class extends Gui")
        this.SetFont("s10", "Segoe UI")
        this.Add("GroupBox", "x12 y10 w280 h96", "Startup")
        this.Add("CheckBox", "x24 y34 w250 +Checked", "Launch at sign-in")
        this.Add("CheckBox", "x24 y58 w250", "Start minimized")
        this.Add("Radio", "x24 y82 w120 +Checked", "Light load")
        this.Add("Radio", "x150 y82 w120", "Full load")
        this.Add("Button", "+Accent x196 y118 w96 h30", "Done").OnEvent("Click", (*) => (this.Destroy(), 0))
    }
}
