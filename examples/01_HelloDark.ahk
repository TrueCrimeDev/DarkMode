#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; The smallest dark window. DarkGui() is a drop-in for Gui(); every control
; added through it is styled the moment it is created. Nothing else to call.

app := DarkGui("+Resize", "Hello, dark")
app.SetFont("s10", "Segoe UI")
app.Add("Text", "x16 y16 w320", "Everything below is a stock Win32 control.")
name := app.Add("Edit", "x16 y44 w320 h26")
name.SetCue("Type your name")
app.Add("CheckBox", "x16 y82 w320 +Checked", "Remember me")
app.Add("Button", "+Accent x16 y116 w100 h30", "Say hello").OnEvent("Click", SayHello)
app.Add("Button", "x124 y116 w100 h30", "Close").OnEvent("Click", (*) => (ExitApp(), 0))
status := app.Add("StatusBar", , "Ready")
app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w352")

SayHello(*) {
    who := name.Value != "" ? name.Value : "stranger"
    status.Text := "Hello, " who "!"
}
