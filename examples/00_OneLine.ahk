#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk
DarkGui.Global()

; That line is the whole integration. Everything below is an ordinary AHK
; script written the ordinary way: delete the line and this is a stock
; light-mode window; keep it and every control is dark, dialogs included.

app := Gui("+Resize", "One line")
app.SetFont("s10", "Segoe UI")
app.Add("Text", "x16 y16 w120 h26 +0x200", "Project")
app.Add("Edit", "x140 y16 w260 h26", "Quarterly report")
app.Add("Text", "x16 y52 w120 h26 +0x200", "Owner")
app.Add("DropDownList", "x140 y52 w260 Choose1", ["Alex", "Sam", "Jordan"])
app.Add("CheckBox", "x140 y88 w260 +Checked", "Send a reminder")
lv := app.Add("ListView", "x16 y122 w384 h120", ["Task", "Status"])
lv.Add("", "Draft outline", "Done")
lv.Add("", "Collect figures", "In progress")
lv.Add("", "Review", "Pending")
lv.ModifyCol(1, 240)
lv.ModifyCol(2, 120)
app.Add("Button", "x208 y254 w92 h30 Default", "Save").OnEvent("Click", (*) => MsgBox("Saved.", "One line"))
app.Add("Button", "x308 y254 w92 h30", "Cancel").OnEvent("Click", (*) => (ExitApp(), 0))
app.Add("StatusBar", , "3 tasks")
app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w416")
