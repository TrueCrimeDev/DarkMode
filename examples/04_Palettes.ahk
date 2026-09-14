#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; Palettes. The five presets, a custom palette, live tracking of the Windows
; light/dark setting, and reacting to a swap from app code (OnThemeChanged).
; Colour words in options may name a palette key ("cAccent", "cFontDim",
; "BackgroundHeader"); a Text control keeps the key and follows every swap.
; DefineColor adds a key of your own to the palette and every preset.

DarkTheme.DefineColor("Brand", 0xE07A5F, 0xB5533A)

app := DarkGui("+Resize", "Palettes")
app.SetFont("s10", "Segoe UI")
app.Add("Text", "x16 y16 w120 h26 +0x200", "Preset")
presets := app.Add("DropDownList", "x140 y16 w180 Choose1", ["Default", "OLED", "Slate", "Blue", "Light"])
presets.OnEvent("Change", (*) => (DarkTheme.ApplyPreset(presets.Text), 0))
app.Add("Button", "x16 y52 w304 h30", "Custom palette (green accent)").OnEvent("Click", ApplyCustom)
follow := app.Add("CheckBox", "x16 y92 w304", "Follow the Windows light/dark setting")
follow.OnEvent("Click", ToggleFollow)

app.Add("GroupBox", "x16 y124 w304 h176", "Sample controls")
app.Add("Text", "x28 y148 w280 cAccent", "This text uses the Accent key")
app.Add("Text", "x28 y170 w280 cFontDim", "This text uses the FontDim key")
app.Add("Text", "x28 y192 w280 cBrand", "This text uses the Brand key defined above")
app.Add("Edit", "x28 y218 w280 h26", "Edit")
app.Add("Button", "+Accent x28 y254 w130 h30", "Accent button")
app.Add("Button", "x166 y254 w142 h30", "Plain button")
app.Add("Progress", "x16 y312 w304 h16", 65)
readout := app.Add("Text", "x16 y338 w304")
app.Add("StatusBar", , "")

; Fired after every SetColor, SetPalette and ApplyPreset with the live Colors map.
DarkTheme.OnThemeChanged(UpdateReadout)
UpdateReadout(DarkTheme.Colors)
app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w336")

UpdateReadout(colors) {
    name := DarkTheme.CurrentPreset != "" ? DarkTheme.CurrentPreset : "custom"
    readout.Text := Format("{}: Background {:06X}, Accent {:06X}", name, colors["Background"], colors["Accent"])
}

ApplyCustom(*) {
    pal := Map()
    pal["Background"] := 0x101614
    pal["Controls"] := 0x18211E
    pal["Header"] := 0x1E2925
    pal["Border"] := 0x2C3B35
    pal["Accent"] := 0x2FBF71
    pal["AccentHover"] := 0x45D486
    pal["AccentPressed"] := 0x239B5B
    pal["Selection"] := 0x1E4D36
    DarkTheme.SetPalette(pal)
}

ToggleFollow(*) {
    if follow.Value
        DarkTheme.FollowSystem(OnSystemTheme)
    else
        DarkTheme.UnfollowSystem()
}

OnSystemTheme(systemUsesLight) {
    DarkTheme.ApplyPreset(systemUsesLight ? "Light" : "Default")
    presets.Choose(systemUsesLight ? "Light" : "Default")
}
