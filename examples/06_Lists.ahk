#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Force
#Include %A_LineFile%\..\..\DarkModeModular.ahk

; Lists. A ListView with checkboxes and click-to-sort columns, a TreeView with
; checkboxes, a ListBox with an owner-drawn DarkScrollbar rail, and a search
; box with a cue banner that filters the ListView as you type.

app := DarkGui("+Resize", "Lists")
app.SetFont("s10", "Segoe UI")
search := app.Add("Edit", "x16 y16 w360 h26")
search.SetCue("Filter files")
search.OnEvent("Change", Filter)

lv := app.Add("ListView", "x16 y50 w360 h170 +Checked -Multi", ["Name", "Type", "Size (KB)"])
files := [["Document.pdf", "PDF", 1240], ["Script.ahk", "AHK", 5], ["Image.png", "PNG", 234],
    ["Archive.zip", "ZIP", 12288], ["Video.mp4", "MP4", 159744], ["Music.mp3", "MP3", 8601],
    ["Database.db", "DB", 46080], ["Notes.txt", "TXT", 2]]
Fill("")
lv.ModifyCol(1, 160)
lv.ModifyCol(2, 80)
lv.ModifyCol(3, "96 Integer Right")
lv.OnEvent("ColClick", (ctrl, col) => (ctrl.ModifyCol(col, "Sort"), 0))

app.Add("Text", "x392 y16 w200 cFontDim", "TreeView with checkboxes")
tv := app.Add("TreeView", "x392 y50 w200 h170 Checked")
docs := tv.Add("Documents", , "Expand")
tv.Add("Report.pdf", docs)
tv.Add("Notes.txt", docs)
img := tv.Add("Images", , "Expand")
tv.Add("Photo.jpg", img)
tv.Add("Logo.png", img)

app.Add("Text", "x16 y232 w360 cFontDim", "ListBox with a DarkScrollbar rail")
lb := app.Add("ListBox", "x16 y254 w360 h96", ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta",
    "Eta", "Theta", "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi"])
rail := DarkScrollbar(app, lb)

status := app.Add("StatusBar", , files.Length " files")
lv.OnEvent("ItemCheck", (ctrl, row, checked) => status.Text := ctrl.GetText(row) (checked ? " checked" : " unchecked"))
app.OnEvent("Close", (*) => (ExitApp(), 0))
app.Show("w608")

Fill(needle) {
    lv.Delete()
    for f in files {
        if needle = "" || InStr(f[1], needle)
            lv.Add("", f[1], f[2], f[3])
    }
}

Filter(*) {
    Fill(search.Value)
    status.Text := lv.GetCount() " of " files.Length " files"
}
