#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; Every button style. Two routes to the same result: the option grammar on a
; plain Add("Button") (+Accent, +Flat, +Toggle[=on], +Icon=file,n
; [+Align=right]) or the AddXxxButton factories.

app := DarkGui("+Resize", "Buttons")
app.SetFont("s10", "Segoe UI")
status := app.Add("StatusBar", , "Click anything")

app.Add("Text", "x16 y14 w320 cFontDim", "Option grammar on Add(`"Button`")")
Wire(app.Add("Button", "x16 y36 w150 h30", "Default"), "Default")
Wire(app.Add("Button", "+Accent x176 y36 w150 h30", "+Accent"), "Accent")
Wire(app.Add("Button", "+Flat x16 y74 w150 h30", "+Flat"), "Flat")
tog := app.Add("Button", "+Toggle=on x176 y74 w150 h30", "+Toggle=on")
tog.OnEvent("Click", (*) => status.Text := "Toggle is " (tog.IsToggled ? "ON" : "OFF"))
Wire(app.Add("Button", "+Icon=shell32.dll,4 x16 y112 w150 h30", "+Icon"), "Icon, left")
Wire(app.Add("Button", "+Icon=shell32.dll,4 +Align=right x176 y112 w150 h30", "+Align=right"), "Icon, right")

app.Add("Text", "x16 y160 w320 cFontDim", "Factories")
Wire(app.AddIconButton("x16 y182 w150 h30", "Browse", "shell32.dll,4"), "AddIconButton")
splitMenu := Menu()
splitMenu.Add("Save as copy", (*) => status.Text := "Split menu: Save as copy")
splitMenu.Add("Save all", (*) => status.Text := "Split menu: Save all")
Wire(app.AddSplitButton("x176 y182 w150 h30", "Save", splitMenu), "AddSplitButton face")
mute := app.AddToggleButton("x16 y220 w150 h30", "Mute", false)
mute.OnEvent("Click", (*) => status.Text := "Mute " (mute.IsToggled ? "ON" : "OFF"))
Wire(app.AddFlatButton("x176 y220 w150 h30", "Flat"), "AddFlatButton")
Wire(app.AddCommandLink("x16 y258 w310 h60", "Command link", "A title plus a description line, Vista style"), "AddCommandLink")

app.Add("Button", "x16 y326 w150 h30 +Disabled", "Disabled")
app.Add("Button", "+Accent x176 y326 w150 h30 +Disabled", "Disabled accent")

app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w342")

Wire(btn, label) {
    btn.OnEvent("Click", (*) => status.Text := label " clicked")
}
