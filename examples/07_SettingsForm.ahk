#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; A settings form: every input control the framework covers, laid out on a
; Tab3, plus a Progress bar cycling through its state colours.

app := DarkGui("+Resize", "Settings form")
app.SetFont("s10", "Segoe UI")
tab := app.Add("Tab3", "x16 y16 w400 h300", ["General", "Schedule", "Advanced"])

tab.UseTab(1)
app.Add("Text", "x32 y52 w100 h26 +0x200", "Display name")
name := app.Add("Edit", "x140 y52 w260 h26")
name.SetCue("Shown to other users")
app.Add("Text", "x32 y88 w100 h26 +0x200", "Region")
region := app.Add("ComboBox", "x140 y88 w260", ["Europe", "North America", "Asia Pacific"])
region.SetCue("Pick or type a region")
app.Add("Text", "x32 y124 w100 h26 +0x200", "Quality")
quality := app.Add("DropDownList", "x140 y124 w260 Choose2", ["Low", "Balanced", "High"])
app.Add("Text", "x32 y160 w100 h26 +0x200", "Volume")
vol := app.Add("Slider", "x140 y160 w260 Range0-100 ToolTip", 70)
app.Add("Text", "x32 y196 w100 h26 +0x200", "Retries")
app.Add("Edit", "x140 y196 w70 h26 +Number", "3")
app.Add("UpDown", "Range0-10", 3)
app.Add("CheckBox", "x140 y236 w260 +Checked", "Notify when finished")
app.Add("CheckBox", "x140 y260 w260", "Keep window on top")

tab.UseTab(2)
app.Add("Text", "x32 y52 w100 h26 +0x200", "Start date")
app.Add("DateTime", "x140 y52 w160 h26")
app.Add("Text", "x32 y88 w100 h26 +0x200", "Start time")
app.Add("DateTime", "x140 y88 w110 h26", "Time")
app.Add("Text", "x32 y124 w100 h26 +0x200", "Hotkey")
app.Add("Hotkey", "x140 y124 w160 h26", "^!s")
app.Add("GroupBox", "x32 y164 w368 h72", "Repeat")
app.Add("Radio", "x44 y188 w100 +Checked", "Daily")
app.Add("Radio", "x150 y188 w100", "Weekly")
app.Add("Radio", "x256 y188 w100", "Monthly")
app.Add("Text", "x32 y250 w368 cFontDim", "Disabled controls take the disabled palette:")
app.Add("Edit", "x32 y272 w170 h26 +Disabled", "Disabled edit")
app.Add("Button", "x210 y272 w190 h26 +Disabled", "Disabled button")

tab.UseTab(3)
app.Add("Text", "x32 y52 w368 cFontDim", "Progress states: normal (Accent), error, paused, marquee")
prog := app.Add("Progress", "x32 y76 w368 h18", 45)
app.Add("Button", "x32 y106 w88 h28", "Normal").OnEvent("Click", (*) => (prog.SetMarquee(false), prog.SetState("normal"), 0))
app.Add("Button", "x126 y106 w88 h28", "Error").OnEvent("Click", (*) => (prog.SetMarquee(false), prog.SetState("error"), 0))
app.Add("Button", "x220 y106 w88 h28", "Paused").OnEvent("Click", (*) => (prog.SetMarquee(false), prog.SetState("paused"), 0))
app.Add("Button", "x314 y106 w86 h28", "Marquee").OnEvent("Click", (*) => (prog.SetMarquee(true), 0))
link := app.Add("Link", "x32 y150 w368", 'Links take the Link key: <a href="https://www.autohotkey.com/docs/v2/">AutoHotkey v2 docs</a>')
link.OnEvent("Click", (ctrl, id, href) => (Run(href), 0))
tab.UseTab()

app.Add("Button", "+Accent x232 y328 w88 h30", "Save").OnEvent("Click", Save)
app.Add("Button", "x328 y328 w88 h30", "Cancel").OnEvent("Click", (*) => (ExitApp(), 0))
status := app.Add("StatusBar", , "Unsaved")
vol.OnEvent("Change", (*) => status.Text := "Volume " vol.Value "%")
app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w432")

Save(*) {
    who := name.Value != "" ? name.Value : "(no name)"
    status.Text := Format("Saved: {} / {} / {} / volume {}", who, region.Text, quality.Text, vol.Value)
}
