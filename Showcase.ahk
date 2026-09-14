#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\DarkModeModular.ahk

; Showcase for DarkModeModular: every control type, the button
; variants, palette presets, FollowSystem, the DPI callback and the dark
; dialogs. Uses only the public DarkGui surface. Run this file directly.
; Held in a script-lifetime variable so the instance is not reliant on
; OnMessage bindings to stay alive.
showcase := DarkModeShowcase()

class DarkModeShowcase {
    controls := Map()
    _altTheme := false

    static CMD_NEW := 101, CMD_OPEN := 102, CMD_SAVE := 103, CMD_EXIT := 104
    static CMD_UNDO := 201, CMD_CUT := 202, CMD_COPY := 203, CMD_PASTE := 204
    static CMD_THEME := 301, CMD_ABOUT := 302
    static CMD_PRESET_DEFAULT := 311, CMD_PRESET_OLED := 312
    static CMD_PRESET_SLATE := 313, CMD_PRESET_LIGHT := 314
    static CMD_PRESET_BLUE := 315
    static CMD_FOLLOW := 316

    __New() {
        ; Dark MsgBox/InputBox for the whole app (the About box demos it).
        DarkDialogs.Install()
        this.gui := DarkGui("+Resize", "Modular Dark Mode System")
        this.BuildMenuBar()
        this.BuildLayout()
        this.BindEvents()
        this.gui.Show("w880 h558")
    }

    BuildMenuBar() {
        menuOpts := Map()
        menuOpts["showToolbar"] := false
        this.menuBar := DarkMenuBar(this.gui, menuOpts)
        this.menuOffset := this.menuBar.totalHeight

        fileMenu := this.menuBar.AddMenu("File")
        fileMenu.Item("New",     DarkModeShowcase.CMD_NEW,  "Ctrl+N")
        fileMenu.Item("Open...", DarkModeShowcase.CMD_OPEN, "Ctrl+O")
        fileMenu.Item("Save",    DarkModeShowcase.CMD_SAVE, "Ctrl+S")
        fileMenu.Sep()
        fileMenu.Item("Exit",    DarkModeShowcase.CMD_EXIT)

        editMenu := this.menuBar.AddMenu("Edit")
        editMenu.Item("Undo",  DarkModeShowcase.CMD_UNDO,  "Ctrl+Z")
        editMenu.Sep()
        editMenu.Item("Cut",   DarkModeShowcase.CMD_CUT,   "Ctrl+X")
        editMenu.Item("Copy",  DarkModeShowcase.CMD_COPY,  "Ctrl+C")
        editMenu.Item("Paste", DarkModeShowcase.CMD_PASTE, "Ctrl+V")

        viewMenu := this.menuBar.AddMenu("View")
        viewMenu.Item("Toggle Accent", DarkModeShowcase.CMD_THEME)
        viewMenu.Sep()
        viewMenu.Item("Preset: Default", DarkModeShowcase.CMD_PRESET_DEFAULT)
        viewMenu.Item("Preset: OLED",    DarkModeShowcase.CMD_PRESET_OLED)
        viewMenu.Item("Preset: Slate",   DarkModeShowcase.CMD_PRESET_SLATE)
        viewMenu.Item("Preset: Blue",    DarkModeShowcase.CMD_PRESET_BLUE)
        viewMenu.Item("Preset: Light",   DarkModeShowcase.CMD_PRESET_LIGHT)
        viewMenu.Sep()
        viewMenu.Item("Follow System Theme", DarkModeShowcase.CMD_FOLLOW)
        viewMenu.Sep()
        viewMenu.Item("About...",        DarkModeShowcase.CMD_ABOUT)

        OnMessage(0x0111, this.OnMenuCommand.Bind(this))
    }

    OnMenuCommand(wParam, lParam, msg, hwnd) {
        if hwnd != this.gui.Hwnd
            return
        cmdId := wParam & 0xFFFF
        if cmdId < 100
            return
        switch cmdId {
            case DarkModeShowcase.CMD_EXIT:  ExitApp()
            case DarkModeShowcase.CMD_ABOUT: MsgBox("DarkModeModular.ahk Showcase`nAll controls dark-themed automatically.", "About")
            case DarkModeShowcase.CMD_THEME:
                ; Live re-theme: SetColor recreates the cached brush and repaints
                ; every registered DarkGui window via DarkTheme.Redraw.
                this._altTheme := !this._altTheme
                DarkTheme.SetColor("Accent", this._altTheme ? 0xA855F7 : 0x0078D7)
                if this.controls.Has("status")
                    this.controls["status"].Text := "Status: Accent → " (this._altTheme ? "Purple" : "Blue")
            case DarkModeShowcase.CMD_PRESET_DEFAULT: this.ApplyPreset("Default")
            case DarkModeShowcase.CMD_PRESET_OLED:    this.ApplyPreset("OLED")
            case DarkModeShowcase.CMD_PRESET_SLATE:   this.ApplyPreset("Slate")
            case DarkModeShowcase.CMD_PRESET_BLUE:    this.ApplyPreset("Blue")
            case DarkModeShowcase.CMD_PRESET_LIGHT:   this.ApplyPreset("Light")
            case DarkModeShowcase.CMD_FOLLOW:         this.ToggleFollowSystem()
            default:
                if this.controls.Has("status")
                    this.controls["status"].Text := "Status: Menu command " cmdId " at " FormatTime(, "HH:mm:ss")
        }
    }

    BuildLayout() {
        y0 := this.menuOffset

        this.gui.Add("Text", "x20 y" (y0 + 15) " w200", "━ Text Input")
        this.controls["edit1"] := this.gui.Add("Edit", "x20 y" (y0 + 40) " w200 h25", "Single-line edit")
        this.controls["edit2"] := this.gui.Add("Edit", "x20 y" (y0 + 75) " w200 h68 +Multi", "Item A`nItem B`nItem C`nItem D`nItem E")

        this.gui.Add("Text", "x240 y" (y0 + 15) " w180", "━ Selection")
        this.controls["chk1"] := this.gui.Add("CheckBox", "x240 y" (y0 + 40) " w160 +Checked", "Feature enabled")
        this.controls["chk2"] := this.gui.Add("CheckBox", "x240 y" (y0 + 65) " w160", "Auto-save")
        ; GroupBox added before the radios so it stays under them in z-order.
        this.controls["radioGroup"] := this.gui.Add("GroupBox", "x232 y" (y0 + 90) " w180 h72", "Radio group")
        this.controls["rad1"] := this.gui.Add("Radio", "x244 y" (y0 + 110) " w160 +Checked", "Option A")
        this.controls["rad2"] := this.gui.Add("Radio", "x244 y" (y0 + 135) " w160", "Option B")

        this.gui.Add("Text", "x420 y" (y0 + 15) " w180", "━ Actions")
        this.controls["btn1"] := this.gui.Add("Button", "x420 y" (y0 + 40) " w80 h28", "Apply")
        this.controls["btn2"] := this.gui.Add("Button", "+Accent x510 y" (y0 + 40) " w80 h28", "OK")
        this.controls["btn3"] := this.gui.Add("Button", "x420 y" (y0 + 78) " w170 h28", "Reset All")

        this.splitMenu := Menu()
        this.splitMenu.Add("First action", (*) => this.controls["status"].Text := "Status: Split menu -> First action")
        this.splitMenu.Add("Second action", (*) => this.controls["status"].Text := "Status: Split menu -> Second action")
        this.splitMenu.Add("Third action", (*) => this.controls["status"].Text := "Status: Split menu -> Third action")
        this.controls["btnToggle"] := this.gui.AddToggleButton("x420 y" (y0 + 116) " w80 h28", "Toggle", false)
        this.controls["btnFlat"]   := this.gui.AddFlatButton("x510 y" (y0 + 116) " w80 h28", "Flat")
        this.controls["btnIcon"]   := this.gui.AddIconButton("x420 y" (y0 + 154) " w80 h28", "Browse", "shell32.dll,4")
        this.controls["btnSplit"]  := this.gui.AddSplitButton("x510 y" (y0 + 154) " w80 h28", "Split", this.splitMenu)

        this.gui.Add("Text", "x20 y" (y0 + 200) " w200", "━ Dropdowns && Progress")
        this.controls["combo"] := this.gui.Add("ComboBox", "x20 y" (y0 + 225) " w95", ["Option 1", "Option 2", "Option 3"])
        this.controls["ddl"] := this.gui.Add("DropDownList", "x120 y" (y0 + 225) " w100", ["Alpha", "Beta", "Gamma"])
        this.controls["slider"] := this.gui.Add("Slider", "x20 y" (y0 + 265) " w200 Range0-100", 50)
        this.controls["sliderLabel"] := this.gui.Add("Text", "x20 y" (y0 + 295) " w200", "Value: 50")
        this.controls["progress"] := this.gui.Add("Progress", "x20 y" (y0 + 320) " w200 h20", 50)

        this.gui.Add("Text", "x240 y" (y0 + 200) " w350", "━ ListView (with checkboxes)")
        this.controls["lv"] := this.gui.Add("ListView", "x240 y" (y0 + 225) " w350 h115 +Checked", ["Name", "Type", "Size"])
        this.controls["lv"].Add("", "Document.pdf", "PDF", "1.2 MB")
        this.controls["lv"].Add("", "Script.ahk", "AHK", "5 KB")
        this.controls["lv"].Add("", "Image.png", "PNG", "234 KB")
        this.controls["lv"].Add("", "Archive.zip", "ZIP", "12 MB")
        this.controls["lv"].Add("", "Video.mp4", "MP4", "156 MB")
        this.controls["lv"].Add("", "Music.mp3", "MP3", "8.4 MB")
        this.controls["lv"].Add("", "Database.db", "DB", "45 MB")
        this.controls["lv"].ModifyCol(1, 150)
        this.controls["lv"].ModifyCol(2, 90)
        this.controls["lv"].ModifyCol(3, 85)

        this.gui.Add("Text", "x20 y" (y0 + 355) " w200", "━ ListBox + DarkScrollbar")
        this.controls["listbox"] := this.gui.Add("ListBox", "x20 y" (y0 + 380) " w200 h90",
            ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa", "Lambda", "Mu"])
        ; Owner-drawn scrollbar synced to the ListBox via the generic
        ; GetScrollInfo / WM_VSCROLL path. Attached form: no coordinates, so it
        ; tracks the ListBox -- which snaps its own height to whole rows.
        this.controls["sb"] := DarkScrollbar(this.gui, this.controls["listbox"])

        this.gui.Add("Text", "x240 y" (y0 + 355) " w350", "━ TreeView (with checkboxes)")
        this.controls["tv"] := this.gui.Add("TreeView", "x240 y" (y0 + 380) " w350 h83 Checked")
        p1 := this.controls["tv"].Add("Documents")
        this.controls["tv"].Add("Report.pdf", p1)
        this.controls["tv"].Add("Notes.txt", p1)
        p2 := this.controls["tv"].Add("Images")
        this.controls["tv"].Add("Photo.jpg", p2)

        ; Third column: the round-2 control coverage.
        this.gui.Add("Text", "x610 y" (y0 + 15) " w250", "━ Date / Time / Input")
        this.controls["dt"] := this.gui.Add("DateTime", "x610 y" (y0 + 40) " w150 h26")
        ; Time format = DTS_UPDOWN: no dropdown, internal spinner routed
        ; through _DarkUpDown and no chevron drawn.
        this.controls["dtTime"] := this.gui.Add("DateTime", "x770 y" (y0 + 40) " w90 h26", "Time")
        this.controls["hk"] := this.gui.Add("Hotkey", "x610 y" (y0 + 78) " w250 h26")

        this.gui.Add("Text", "x610 y" (y0 + 116) " w250", "━ Tabs")
        tab := this.controls["tab"] := this.gui.Add("Tab3", "x610 y" (y0 + 141) " w250 h120", ["General", "Advanced"])
        tab.UseTab(1)
        this.gui.Add("Text", "x625 y" (y0 + 175) " w220", "Tab page one content")
        this.controls["tabBtn"] := this.gui.AddCommandLink("x625 y" (y0 + 196) " w220 h60",
            "Page Action", "Command-link button variant")
        tab.UseTab(2)
        this.gui.Add("Text", "x625 y" (y0 + 175) " w220", "Advanced settings here")
        this.controls["tabChk"] := this.gui.Add("CheckBox", "x625 y" (y0 + 200) " w220", "Verbose logging")
        tab.UseTab()

        this.gui.Add("Text", "x610 y" (y0 + 276) " w250", "━ MonthCal")
        this.controls["mc"] := this.gui.Add("MonthCal", "x610 y" (y0 + 301))

        ; Spinner (numeric Edit + UpDown) and SysLink, then a real docked StatusBar.
        this.gui.Add("Text", "x20 y" (y0 + 482) " w40 +0x200", "Spin:")
        this.controls["spinEdit"] := this.gui.Add("Edit", "x60 y" (y0 + 478) " w52 h24 +Number", "10")
        this.controls["spin"] := this.gui.Add("UpDown", "Range0-100", 10)
        this.controls["link"] := this.gui.Add("Link", "x130 y" (y0 + 482) " w460",
            'Docs: <a href="https://www.autohotkey.com/docs/">AutoHotkey</a> · <a href="https://github.com/">GitHub</a>')

        this.controls["status"] := this.gui.Add("StatusBar", , "Status: Ready")
    }

    BindEvents() {
        this.controls["btn1"].OnEvent("Click", this.OnApply.Bind(this))
        this.controls["btn2"].OnEvent("Click", (*) => (this.gui.Hide(), 0))
        this.controls["btn3"].OnEvent("Click", this.OnReset.Bind(this))
        this.controls["slider"].OnEvent("Change", this.OnSliderChange.Bind(this))
        this.controls["btnToggle"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Toggle " (this.controls["btnToggle"].IsToggled ? "ON" : "OFF"))
        this.controls["btnFlat"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Flat clicked")
        this.controls["btnIcon"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Icon clicked")
        this.controls["btnSplit"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Split (face) clicked")
        this.controls["spin"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Spin = " this.controls["spinEdit"].Value)
        this.controls["link"].OnEvent("Click", this.OnLink.Bind(this))
        this.controls["dt"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Date → " FormatTime(this.controls["dt"].Value, "yyyy-MM-dd"))
        this.controls["dtTime"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Time → " FormatTime(this.controls["dtTime"].Value, "HH:mm:ss"))
        this.gui.OnDpiChanged(this.OnDpiChange.Bind(this))
        this.controls["hk"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Hotkey → " (this.controls["hk"].Value != "" ? this.controls["hk"].Value : "(none)"))
        this.controls["mc"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Calendar → " FormatTime(this.controls["mc"].Value, "yyyy-MM-dd"))
        this.controls["tab"].OnEvent("Change", (*) => this.controls["status"].Text := "Status: Tab page " this.controls["tab"].Value)
        this.controls["tabBtn"].OnEvent("Click", (*) => this.controls["status"].Text := "Status: Page action clicked")
        this.gui.OnEvent("Close", (*) => (ExitApp(), 0))
    }

    /** Swaps the whole palette; frames, BackColor, and brushes re-sync centrally. */
    ApplyPreset(name) {
        DarkTheme.ApplyPreset(name)
        this.controls["status"].Text := "Status: Preset → " name
    }

    OnApply(*) {
        this.controls["status"].Text := "Status: Applied at " FormatTime(, "HH:mm:ss")
        ; Dark tooltip demo: AHK ToolTip() windows are only darkened by an
        ; explicit ApplyAll — the library can't see them being created.
        ToolTip("Applied (dark tooltip)")
        DarkToolTip.ApplyAll()
        SetTimer(() => (ToolTip(), 0), -1200)
    }

    /** View menu: track the OS light/dark app setting via FollowSystem. */
    ToggleFollowSystem() {
        this._follow := !(this.HasProp("_follow") && this._follow)
        if this._follow {
            DarkTheme.FollowSystem(this._onSystemTheme := this.OnSystemTheme.Bind(this))
            this.controls["status"].Text := "Status: Following system theme"
        } else {
            DarkTheme.UnfollowSystem()
            this.controls["status"].Text := "Status: Stopped following system theme"
        }
    }

    OnSystemTheme(systemUsesLight) {
        DarkTheme.ApplyPreset(systemUsesLight ? "Light" : "Default")
    }

    OnDpiChange(hwnd, dpi, rcNew) {
        this.controls["status"].Text := "Status: DPI → " dpi " (" Round(dpi / 96.0 * 100) "%)"
    }

    OnReset(*) {
        this.controls["edit1"].Value := "Single-line edit"
        this.controls["edit2"].Value := "Multi-line`nedit control"
        this.controls["chk1"].Value := 1
        this.controls["chk2"].Value := 0
        this.controls["rad1"].Value := 1
        this.controls["slider"].Value := 50
        this.controls["progress"].Value := 50
        this.controls["sliderLabel"].Text := "Value: 50"
        this.controls["status"].Text := "Status: Reset complete"
    }

    OnSliderChange(*) {
        sliderVal := this.controls["slider"].Value
        this.controls["progress"].Value := sliderVal
        this.controls["sliderLabel"].Text := "Value: " sliderVal
    }

    ; Link Click fires with (ctrl, info, href). Registering a callback suppresses
    ; AHK's automatic HREF launch, so open it ourselves.
    OnLink(ctrl, info, href := "") {
        if href
            Run(href)
        this.controls["status"].Text := "Status: Link → " href
    }
}
