
#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook True

; ============================================================
; conputed's piano autoplayer
; version 2.5
; ============================================================
;
; v2.5 changelog:
; - fixed a missed-release recovery issue in the watchdog.
; - watchdog now checks physical hotkey state even if the
;   internal NoteKeyDown flag has already been cleared.
; - protected chord-release cleanup against hotkey/timer
;   interruptions that could race with a newly pressed chord.
; - kept support note breaks off by default.
; - kept maximum chord-release variation at 40 ms by default.
; - retained the v2.4 GUI footer, links, and saved-sheet library.
;
; v2.4 changelog:
; - support note breaks defaults to off.
; - maximum chord-release variation defaults to 40 ms.
; - added "made by conputed" under the instruction text.
; - added clickable github, help, sheets, and roblox links.
; - added the v2.4 label to the bottom-right of the main GUI.
;
; ============================================================

SendMode("Event")
SetKeyDelay(-1, -1)

; -------------------- paths and first-run storage --------------------

global SettingsFile := A_ScriptDir "\settings.ini"
global SheetsDir := A_ScriptDir "\sheets"

; -------------------- settings --------------------

global SupportBreaks := false
global RealisticChordStart := true
global RealisticChordRelease := true
global StartDelayMax := 8
global ReleaseDelayMax := 40

global NoteHotkey := "]"
global ToggleHotkey := "\"

; dark palette
global UiBackground := "1B1B1F"
global UiField := "27272D"
global UiText := "E8E8EE"

; progress statistics
global TotalItems := 0
global PlayedItems := 0

; sheet library state
global SheetFiles := []
global SheetButtons := []
global SheetEmptyText := 0
global SheetScrollOffset := 0
global SheetPanelHeight := 285
global SheetButtonHeight := 28
global SheetButtonSpacing := 4
global SheetScrollStep := 96

InitializeStorage()
LoadSettings()

; -------------------- main gui --------------------

global MainGui := Gui("+AlwaysOnTop -Theme", "conputed's piano autoplayer")
MainGui.BackColor := UiBackground
MainGui.SetFont("s10 c" UiText, "Segoe UI")

global MusicLabel := MainGui.AddText(
    "w420 BackgroundTrans",
    "put sheet music here:"
)
MusicLabel.SetFont("s10 bold", "Segoe UI")

global MusicEdit := MainGui.AddEdit(
    "R10 w420 Background" UiField " c" UiText
)
MusicEdit.SetFont("s10", "Consolas")

global ProgressLabel := MainGui.AddText(
    "w420 BackgroundTrans",
    "stats: 0/0"
)
ProgressLabel.SetFont("s10", "Consolas")

global PlayButton := MainGui.AddButton("w100", "play")
global SettingsButton := MainGui.AddButton("x+8 w100", "settings")
global RefreshSheetsButton := MainGui.AddButton(
    "x+8 w112",
    "refresh sheets"
)

PlayButton.OnEvent("Click", TogglePlayback)
SettingsButton.OnEvent("Click", ShowSettings)
RefreshSheetsButton.OnEvent("Click", RefreshSheetList)
MainGui.OnEvent("Close", ExitScript)

global InfoText := MainGui.AddText(
    "xm y+10 w420 BackgroundTrans",
    "press ] to play notes/chords. hold to sustain notes.`n"
    . "press \ to enter/leave autoplay state.`n"
    . "made by conputed"
)

; -------------------- saved sheets column --------------------

global SheetsHeading := MainGui.AddText(
    "x450 y10 w164 BackgroundTrans",
    "saved sheets"
)
SheetsHeading.SetFont("s10 bold", "Segoe UI")

; Child GUI clips the sheet buttons to the visible panel.
global SheetPanel := Gui(
    "+Parent" MainGui.Hwnd " -Caption -Border -Theme",
    "saved sheets"
)
SheetPanel.BackColor := UiField
SheetPanel.SetFont("s9 c" UiText, "Segoe UI")

global ScrollUpButton := MainGui.AddButton(
    "x594 y30 w24 h28",
    "^"
)
global ScrollDownButton := MainGui.AddButton(
    "x594 y287 w24 h28",
    "v"
)

ScrollUpButton.OnEvent("Click", ScrollSheets.Bind(-96))
ScrollDownButton.OnEvent("Click", ScrollSheets.Bind(96))

; Clickable footer links beneath the saved-sheets panel.
global FooterLinks := MainGui.Add(
    "Link",
    "x450 y318 w168 h18 Center",
    '<a href="https://github.com/RealConputed">github</a> | '
    . '<a href="https://github.com/RealConputed/Conputeds-Virtual-Piano-Autoplayer">help</a> | '
    . '<a href="https://vp-sheets.arijan.dev/">sheets</a> | '
    . '<a href="https://www.roblox.com/users/4684928452/profile">roblox</a>'
)
FooterLinks.SetFont("s8 c" UiText, "Segoe UI")

global VersionLabel := MainGui.AddText(
    "x450 y336 w168 h14 Right BackgroundTrans",
    "v2.5"
)
VersionLabel.SetFont("s8 c" UiText, "Segoe UI")

; -------------------- settings gui --------------------

global SettingsGui := Gui("+AlwaysOnTop -Theme", "settings")
SettingsGui.BackColor := UiBackground
SettingsGui.SetFont("s10 c" UiText, "Segoe UI")

global HotkeysHeading := SettingsGui.AddText(
    "w360 BackgroundTrans",
    "hotkeys"
)
HotkeysHeading.SetFont("s10 bold", "Segoe UI")

SettingsGui.AddText("xm y+6 BackgroundTrans", "play notes/chords")

global NoteHotkeyControl := SettingsGui.Add(
    "Hotkey",
    "w140 c" UiText,
    "]"
)

SettingsGui.AddText("xm y+6 BackgroundTrans", "enter/leave autoplay state")

global ToggleHotkeyControl := SettingsGui.Add(
    "Hotkey",
    "w140 c" UiText,
    "\"
)

SettingsGui.AddText(
    "xm y+4 w360 BackgroundTrans",
    "use single keys without ctrl, alt, shift or win modifiers."
)

global PlaybackHeading := SettingsGui.AddText(
    "xm y+10 w360 BackgroundTrans",
    "playback settings"
)
PlaybackHeading.SetFont("s10 bold", "Segoe UI")

global BreaksCheck := SettingsGui.AddCheckBox(
    "w360 Background" UiBackground,
    "support note breaks (-, _, |)"
)

global StartCheck := SettingsGui.AddCheckBox(
    "w360 Background" UiBackground,
    "realistic chord start"
)

global ReleaseCheck := SettingsGui.AddCheckBox(
    "w360 Background" UiBackground,
    "realistic chord release"
)

SettingsGui.AddText(
    "xm y+8 BackgroundTrans",
    "maximum chord-start variation (ms):"
)
global StartDelayEdit := SettingsGui.AddEdit(
    "w70 Number Background" UiField " c" UiText
)

SettingsGui.AddText(
    "x+12 yp BackgroundTrans",
    "maximum release variation (ms):"
)
global ReleaseDelayEdit := SettingsGui.AddEdit(
    "w70 Number Background" UiField " c" UiText
)

global ChangelogHeading := SettingsGui.AddText(
    "xm y+10 w360 BackgroundTrans",
    "changelog — v2.5"
)
ChangelogHeading.SetFont("s10 bold", "Segoe UI")

global ChangelogEdit := SettingsGui.AddEdit(
    "ReadOnly R8 VScroll w360 Background" UiField " c" UiText,
    "• improved recovery from missed note releases.`r`n"
    . "• watchdog retries release when the hotkey is physically up.`r`n"
    . "• protected chord cleanup from hotkey interruptions.`r`n"
    . "• support note breaks defaults to off.`r`n"
    . "• maximum release variation defaults to 40 ms.`r`n"
    . "• retained footer links and saved-sheet library."
)

global SaveSettingsButton := SettingsGui.AddButton("xm w120", "save settings")
global CloseSettingsButton := SettingsGui.AddButton("x+8 w100", "close")

SaveSettingsButton.OnEvent("Click", SaveSettings)
CloseSettingsButton.OnEvent("Click", (*) => SettingsGui.Hide())
SettingsGui.OnEvent("Close", (*) => SettingsGui.Hide())

SyncSettingsToGui()

; -------------------- playback state --------------------

global Playing := false
global CurrentPos := 1
global SheetCache := ""
global ToggleKeyDown := false
global NoteKeyDown := false

global Slots := Map("note", Map())
global KeyOwners := Map()

global RegisteredNoteDown := ""
global RegisteredNoteUp := ""
global RegisteredToggleDown := ""
global RegisteredToggleUp := ""

RegisterHotkeys()
UpdateInfoText()
UpdateProgress()

RefreshSheetList()

MainGui.Show("w620 h350")
SheetPanel.Show("x450 y30 w140 h285 NA")

OnMessage(0x020A, HandleSheetMouseWheel)

SetTimer(Watchdog, 100)

; ============================================================
; first-run storage initialization
; ============================================================

InitializeStorage() {
    global SettingsFile, SheetsDir

    if !DirExist(SheetsDir) {
        try {
            DirCreate(SheetsDir)
        } catch as err {
            MsgBox(
                "could not create the sheets folder:`n`n"
                . SheetsDir . "`n`n" . err.Message,
                "folder initialization error",
                "Iconx"
            )
        }
    }

    ; Create defaults only if settings.ini is absent.
    ; Existing settings are never overwritten here.
    if !FileExist(SettingsFile) {
        try {
            IniWrite(0, SettingsFile, "Playback", "SupportBreaks")
            IniWrite(1, SettingsFile, "Playback", "RealisticChordStart")
            IniWrite(1, SettingsFile, "Playback", "RealisticChordRelease")
            IniWrite(8, SettingsFile, "Playback", "StartDelayMax")
            IniWrite(40, SettingsFile, "Playback", "ReleaseDelayMax")
            IniWrite("]", SettingsFile, "Hotkeys", "NoteHotkey")
            IniWrite("\", SettingsFile, "Hotkeys", "ToggleHotkey")
        } catch as err {
            MsgBox(
                "the settings file could not be initialized.`n`n"
                . "The script will continue using its built-in defaults.`n`n"
                . err.Message,
                "settings initialization error",
                "Icon!"
            )
        }
    }
}

; ============================================================
; settings loading and saving
; ============================================================

LoadSettings() {
    global SettingsFile
    global SupportBreaks, RealisticChordStart, RealisticChordRelease
    global StartDelayMax, ReleaseDelayMax
    global NoteHotkey, ToggleHotkey

    SupportBreaks := IniRead(SettingsFile, "Playback", "SupportBreaks", "0") = "1"
    RealisticChordStart := IniRead(SettingsFile, "Playback", "RealisticChordStart", "1") = "1"
    RealisticChordRelease := IniRead(SettingsFile, "Playback", "RealisticChordRelease", "1") = "1"

    try StartDelayMax := Integer(IniRead(SettingsFile, "Playback", "StartDelayMax", "8"))
    catch
        StartDelayMax := 8

    try ReleaseDelayMax := Integer(IniRead(SettingsFile, "Playback", "ReleaseDelayMax", "40"))
    catch
        ReleaseDelayMax := 40

    NoteHotkey := IniRead(SettingsFile, "Hotkeys", "NoteHotkey", "]")
    ToggleHotkey := IniRead(SettingsFile, "Hotkeys", "ToggleHotkey", "\")

    StartDelayMax := Clamp(StartDelayMax, 0, 40)
    ReleaseDelayMax := Clamp(ReleaseDelayMax, 0, 40)

    if !IsSingleKeyHotkey(NoteHotkey)
        NoteHotkey := "]"

    if !IsSingleKeyHotkey(ToggleHotkey)
        ToggleHotkey := "\"

    if SamePhysicalKey(NoteHotkey, ToggleHotkey) {
        NoteHotkey := "]"
        ToggleHotkey := "\"
    }
}

SyncSettingsToGui() {
    global BreaksCheck, StartCheck, ReleaseCheck
    global StartDelayEdit, ReleaseDelayEdit
    global SupportBreaks, RealisticChordStart, RealisticChordRelease
    global StartDelayMax, ReleaseDelayMax
    global NoteHotkeyControl, ToggleHotkeyControl
    global NoteHotkey, ToggleHotkey

    BreaksCheck.Value := SupportBreaks ? 1 : 0
    StartCheck.Value := RealisticChordStart ? 1 : 0
    ReleaseCheck.Value := RealisticChordRelease ? 1 : 0

    StartDelayEdit.Value := StartDelayMax
    ReleaseDelayEdit.Value := ReleaseDelayMax

    NoteHotkeyControl.Value := NoteHotkey
    ToggleHotkeyControl.Value := ToggleHotkey
}

ShowSettings(*) {
    global SettingsGui
    SyncSettingsToGui()
    SettingsGui.Show("w390")
}

SaveSettings(*) {
    global SettingsFile
    global SupportBreaks, RealisticChordStart, RealisticChordRelease
    global StartDelayMax, ReleaseDelayMax
    global BreaksCheck, StartCheck, ReleaseCheck
    global StartDelayEdit, ReleaseDelayEdit
    global NoteHotkeyControl, ToggleHotkeyControl
    global NoteHotkey, ToggleHotkey

    newNoteHotkey := Trim(NoteHotkeyControl.Value)
    newToggleHotkey := Trim(ToggleHotkeyControl.Value)

    if !IsSingleKeyHotkey(newNoteHotkey) {
        MsgBox(
            "choose a single key for playing notes/chords. modifier combinations aren't supported here.",
            "invalid note hotkey",
            "Icon!"
        )
        return
    }

    if !IsSingleKeyHotkey(newToggleHotkey) {
        MsgBox(
            "choose a single key for the autoplay toggle. modifier combinations aren't supported here.",
            "invalid autoplay hotkey",
            "Icon!"
        )
        return
    }

    if SamePhysicalKey(newNoteHotkey, newToggleHotkey) {
        MsgBox(
            "the note key and autoplay toggle must be different keys.",
            "duplicate hotkeys",
            "Icon!"
        )
        return
    }

    SupportBreaks := BreaksCheck.Value = 1
    RealisticChordStart := StartCheck.Value = 1
    RealisticChordRelease := ReleaseCheck.Value = 1

    StartDelayMax := Clamp(SafeInteger(StartDelayEdit.Value, 8), 0, 40)
    ReleaseDelayMax := Clamp(SafeInteger(ReleaseDelayEdit.Value, 40), 0, 40)

    ReleaseAllSlots()
    NoteKeyDown := false
    ToggleKeyDown := false

    oldNoteHotkey := NoteHotkey
    oldToggleHotkey := ToggleHotkey

    NoteHotkey := newNoteHotkey
    ToggleHotkey := newToggleHotkey

    try {
        RegisterHotkeys()
    } catch as err {
        NoteHotkey := oldNoteHotkey
        ToggleHotkey := oldToggleHotkey

        try RegisterHotkeys()

        MsgBox(
            "could not apply those hotkeys.`n`n" . err.Message,
            "hotkey error",
            "Iconx"
        )
        return
    }

    StartDelayEdit.Value := StartDelayMax
    ReleaseDelayEdit.Value := ReleaseDelayMax

    try {
        IniWrite(SupportBreaks ? 1 : 0, SettingsFile, "Playback", "SupportBreaks")
        IniWrite(RealisticChordStart ? 1 : 0, SettingsFile, "Playback", "RealisticChordStart")
        IniWrite(RealisticChordRelease ? 1 : 0, SettingsFile, "Playback", "RealisticChordRelease")
        IniWrite(StartDelayMax, SettingsFile, "Playback", "StartDelayMax")
        IniWrite(ReleaseDelayMax, SettingsFile, "Playback", "ReleaseDelayMax")
        IniWrite(NoteHotkey, SettingsFile, "Hotkeys", "NoteHotkey")
        IniWrite(ToggleHotkey, SettingsFile, "Hotkeys", "ToggleHotkey")

        UpdateInfoText()
        ToolTip("settings saved")
        SetTimer(() => ToolTip(), -1200)
    } catch as err {
        MsgBox(
            "hotkeys were applied, but settings could not be saved to the ini file.`n`n"
            . err.Message,
            "settings save error",
            "Iconx"
        )
    }
}

SafeInteger(value, fallback) {
    try return Integer(value)
    catch
        return fallback
}

Clamp(value, minimum, maximum) {
    return Max(minimum, Min(maximum, value))
}

IsSingleKeyHotkey(keyName) {
    if keyName = ""
        return false

    if InStr(keyName, "^") || InStr(keyName, "!") || InStr(keyName, "+")
        || InStr(keyName, "#") || InStr(keyName, "<") || InStr(keyName, ">")
        return false

    try {
        vk := GetKeyVK(keyName)
        return vk != 0
    } catch {
        return false
    }
}

SamePhysicalKey(keyA, keyB) {
    try {
        return GetKeyVK(keyA) = GetKeyVK(keyB)
    } catch {
        return StrLower(keyA) = StrLower(keyB)
    }
}

; ============================================================
; saved sheet library
; ============================================================

RefreshSheetList(*) {
    global SheetsDir, SheetFiles, SheetButtons
    global SheetEmptyText, SheetScrollOffset

    if !DirExist(SheetsDir) {
        try {
            DirCreate(SheetsDir)
        } catch as err {
            MsgBox(
                "could not access or create the sheets folder:`n`n"
                . SheetsDir . "`n`n" . err.Message,
                "sheets folder error",
                "Iconx"
            )
            return
        }
    }

    ; Build the replacement list separately. The currently visible
    ; buttons remain intact until scanning and sorting both succeed.
    newSheetFiles := []

    try {
        Loop Files, SheetsDir "\*.txt", "F" {
            displayName := SubStr(
                A_LoopFileName,
                1,
                StrLen(A_LoopFileName) - 4
            )

            newSheetFiles.Push({
                name: displayName,
                path: A_LoopFileFullPath
            })
        }

        ; Case-insensitive alphabetical insertion sort.
        i := 2

        while i <= newSheetFiles.Length {
            j := i

            while j > 1 {
                comparison := StrCompare(
                    newSheetFiles[j - 1].name,
                    newSheetFiles[j].name,
                    false
                )

                if comparison <= 0
                    break

                temp := newSheetFiles[j - 1]
                newSheetFiles[j - 1] := newSheetFiles[j]
                newSheetFiles[j] := temp

                j -= 1
            }

            i += 1
        }
    } catch as err {
        MsgBox(
            "could not refresh the saved-sheet library.`n`n"
            . err.Message,
            "sheet refresh error",
            "Iconx"
        )
        return
    }

    ; Scanning and sorting succeeded. Replace the previous list.
    for button in SheetButtons {
        try button.Destroy()
    }

    SheetButtons := []

    if IsObject(SheetEmptyText) {
        try SheetEmptyText.Destroy()
        SheetEmptyText := 0
    }

    SheetFiles := newSheetFiles
    SheetScrollOffset := 0

    if SheetFiles.Length = 0 {
        SheetEmptyText := SheetPanel.AddText(
            "x5 y112 w130 Center BackgroundTrans",
            "no sheets found"
        )
        SheetEmptyText.SetFont("s9 cAFAFBC", "Segoe UI")
        return
    }

    for index, sheet in SheetFiles {
        y := 4 + (index - 1) * (
            SheetButtonHeight + SheetButtonSpacing
        )

        button := SheetPanel.AddButton(
            "x4 y" y " w132 h28",
            sheet.name
        )

        button.OnEvent("Click", LoadSavedSheet.Bind(sheet.path))
        SheetButtons.Push(button)
    }

    PositionSheetButtons()
}

LoadSavedSheet(filePath, *) {
    global MusicEdit, SheetCache, CurrentPos
    global TotalItems, PlayedItems

    if !FileExist(filePath) {
        MsgBox(
            "this sheet no longer exists:`n`n"
            . filePath . "`n`n"
            . "Click refresh sheets to update the library.",
            "sheet not found",
            "Icon!"
        )
        return
    }

    try {
        sheetText := FileRead(filePath, "UTF-8")
    } catch as err {
        MsgBox(
            "could not read this sheet:`n`n"
            . filePath . "`n`n" . err.Message,
            "sheet loading error",
            "Iconx"
        )
        return
    }

    StopPlayback()

    MusicEdit.Value := StrReplace(sheetText, "`r", "")

    SheetCache := MusicEdit.Value
    CurrentPos := 1
    TotalItems := CountSheetItems(SheetCache)
    PlayedItems := 0

    UpdateProgress()
}

ScrollSheets(amount, *) {
    global SheetScrollOffset, SheetFiles
    global SheetPanelHeight, SheetButtonHeight, SheetButtonSpacing

    contentHeight := SheetFiles.Length * (
        SheetButtonHeight + SheetButtonSpacing
    )

    maxOffset := Max(0, contentHeight - SheetPanelHeight)

    SheetScrollOffset := Clamp(
        SheetScrollOffset + amount,
        0,
        maxOffset
    )

    PositionSheetButtons()
}

PositionSheetButtons() {
    global SheetButtons, SheetScrollOffset
    global SheetButtonHeight, SheetButtonSpacing

    for index, button in SheetButtons {
        y := 4 + (index - 1) * (
            SheetButtonHeight + SheetButtonSpacing
        ) - SheetScrollOffset

        button.Move(4, y, 132, SheetButtonHeight)
    }
}

HandleSheetMouseWheel(wParam, lParam, msg, hwnd) {
    global SheetPanel

    MouseGetPos(&mouseX, &mouseY)

    try {
        WinGetPos(
            &panelX,
            &panelY,
            &panelW,
            &panelH,
            "ahk_id " SheetPanel.Hwnd
        )
    } catch {
        return
    }

    if mouseX < panelX || mouseX >= panelX + panelW
        || mouseY < panelY || mouseY >= panelY + panelH
        return

    delta := (wParam >> 16) & 0xFFFF

    if delta > 32767
        delta -= 65536

    if delta > 0
        ScrollSheets(-64)
    else if delta < 0
        ScrollSheets(64)

    return 0
}

; ============================================================
; dynamic hotkey registration
; ============================================================

RegisterHotkeys() {
    global NoteHotkey, ToggleHotkey
    global RegisteredNoteDown, RegisteredNoteUp
    global RegisteredToggleDown, RegisteredToggleUp

    if RegisteredNoteDown != "" {
        Hotkey(RegisteredNoteDown, "Off")
        Hotkey(RegisteredNoteUp, "Off")
    }

    if RegisteredToggleDown != "" {
        Hotkey(RegisteredToggleDown, "Off")
        Hotkey(RegisteredToggleUp, "Off")
    }

    RegisteredNoteDown := "*" . NoteHotkey
    RegisteredNoteUp := "*" . NoteHotkey . " up"
    RegisteredToggleDown := "*" . ToggleHotkey
    RegisteredToggleUp := "*" . ToggleHotkey . " up"

    Hotkey(RegisteredNoteDown, NoteDownHandler, "On")
    Hotkey(RegisteredNoteUp, NoteUpHandler, "On")
    Hotkey(RegisteredToggleDown, ToggleDownHandler, "On")
    Hotkey(RegisteredToggleUp, ToggleUpHandler, "On")
}

UpdateInfoText() {
    global InfoText, NoteHotkey, ToggleHotkey

    InfoText.Value := "press " . NoteHotkey . " to play notes/chords. hold to sustain notes.`n"
        . "press " . ToggleHotkey . " to enter/leave autoplay state.`n"
        . "made by conputed"
}

; ============================================================
; play / stop
; ============================================================

TogglePlayback(*) {
    global Playing, PlayButton, CurrentPos, SheetCache
    global MusicEdit, TotalItems, PlayedItems

    if Playing {
        StopPlayback()
        return
    }

    sheet := StrReplace(MusicEdit.Value, "`r", "")

    if Trim(sheet) = "" {
        MsgBox(
            "put sheet music in the box first.",
            "no sheet music",
            "Icon!"
        )
        return
    }

    Playing := true
    PlayButton.Text := "stop"

    CurrentPos := 1
    SheetCache := sheet
    TotalItems := CountSheetItems(sheet)
    PlayedItems := 0

    UpdateProgress()
}

StopPlayback() {
    global Playing, PlayButton, CurrentPos, SheetCache
    global NoteKeyDown, ToggleKeyDown
    global MusicEdit, TotalItems, PlayedItems

    Playing := false
    PlayButton.Text := "play"

    ReleaseAllSlots()

    NoteKeyDown := false
    ToggleKeyDown := false

    CurrentPos := 1
    SheetCache := StrReplace(MusicEdit.Value, "`r", "")
    TotalItems := CountSheetItems(SheetCache)
    PlayedItems := 0

    UpdateProgress()
}

ExitScript(*) {
    StopPlayback()
    ExitApp()
}

ToggleDownHandler(*) {
    global ToggleKeyDown

    if ToggleKeyDown
        return

    ToggleKeyDown := true
    TogglePlayback()
}

ToggleUpHandler(*) {
    global ToggleKeyDown
    ToggleKeyDown := false
}

; ============================================================
; note trigger handling
; ============================================================

NoteDownHandler(*) {
    global Playing, NoteKeyDown

    if !Playing || NoteKeyDown
        return

    NoteKeyDown := true
    PlayNextChord("note")
}

NoteUpHandler(*) {
    global NoteKeyDown

    NoteKeyDown := false
    ReleaseSlot("note")
}

; Recovery watchdog:
; always checks physical key state, not only NoteKeyDown.
; If the hotkey is physically up, any remaining notes are released.
Watchdog() {
    global NoteKeyDown, ToggleKeyDown
    global NoteHotkey, ToggleHotkey

    if !GetKeyState(NoteHotkey, "P") {
        NoteKeyDown := false
        ReleaseSlot("note")
    }

    if ToggleKeyDown && !GetKeyState(ToggleHotkey, "P")
        ToggleKeyDown := false
}

; ============================================================
; sheet parsing
; ============================================================

PlayNextChord(trigger) {
    global MusicEdit, CurrentPos, SheetCache, SupportBreaks
    global TotalItems, PlayedItems

    sheet := StrReplace(MusicEdit.Value, "`r", "")

    if sheet != SheetCache {
        ReleaseSlot(trigger)
        SheetCache := sheet
        CurrentPos := 1
        TotalItems := CountSheetItems(sheet)
        PlayedItems := 0
        UpdateProgress()
    }

    length := StrLen(sheet)

    while CurrentPos <= length {
        ch := SubStr(sheet, CurrentPos, 1)

        if ch = " " || ch = "`n" || ch = "`t" || ch = "/" {
            CurrentPos += 1
            continue
        }

        if IsBreakCharacter(ch) {
            CurrentPos += 1

            if SupportBreaks {
                UpdateProgress()
                Sleep(120)
                return
            }

            continue
        }

        if ch = "[" {
            closePos := InStr(sheet, "]", true, CurrentPos + 1)

            if !closePos {
                CurrentPos += 1
                continue
            }

            chordText := SubStr(
                sheet,
                CurrentPos + 1,
                closePos - CurrentPos - 1
            )

            CurrentPos := closePos + 1
            notes := []

            Loop Parse chordText {
                note := A_LoopField

                if IsBreakCharacter(note)
                    continue

                if IsSupportedNote(note)
                    notes.Push(note)
            }

            if notes.Length {
                PressChord(trigger, notes)
                PlayedItems += 1
                UpdateProgress()
                return
            }

            continue
        }

        CurrentPos += 1

        if !IsSupportedNote(ch)
            continue

        PressChord(trigger, [ch])
        PlayedItems += 1
        UpdateProgress()
        return
    }

    CurrentPos := 1
    PlayedItems := 0
    UpdateProgress()
}

IsBreakCharacter(ch) {
    return ch = "-" || ch = "_" || ch = "|"
}

IsSupportedNote(ch) {
    if StrLen(ch) != 1
        return false

    code := Ord(ch)

    if (code >= 48 && code <= 57) || (code >= 65 && code <= 90)
        || (code >= 97 && code <= 122)
        return true

    switch code {
        case 33, 34, 35, 36, 37, 38, 39:
            return true
        case 40, 41, 42, 43, 44, 45, 46, 47:
            return true
        case 58, 59, 60, 61, 62, 63, 64:
            return true
        case 94, 95, 96, 124, 126:
            return true
        default:
            return false
    }
}

CountSheetItems(sheet) {
    sheet := StrReplace(sheet, "`r", "")
    length := StrLen(sheet)
    position := 1
    total := 0

    while position <= length {
        ch := SubStr(sheet, position, 1)

        if ch = " " || ch = "`n" || ch = "`t" || ch = "/"
            || IsBreakCharacter(ch) {
            position += 1
            continue
        }

        if ch = "[" {
            closePos := InStr(sheet, "]", true, position + 1)

            if !closePos {
                position += 1
                continue
            }

            chordText := SubStr(
                sheet,
                position + 1,
                closePos - position - 1
            )

            hasNotes := false

            Loop Parse chordText {
                note := A_LoopField

                if IsBreakCharacter(note)
                    continue

                if IsSupportedNote(note) {
                    hasNotes := true
                    break
                }
            }

            if hasNotes
                total += 1

            position := closePos + 1
            continue
        }

        if IsSupportedNote(ch)
            total += 1

        position += 1
    }

    return total
}

UpdateProgress() {
    global ProgressLabel, TotalItems, PlayedItems

    if TotalItems <= 0 {
        ProgressLabel.Text := "stats: 0/0"
        return
    }

    nextItem := PlayedItems + 1

    if nextItem > TotalItems
        nextItem := 1

    ProgressLabel.Text := "stats: " . nextItem . "/" . TotalItems
}

; ============================================================
; chord start / note ownership
; ============================================================

PressChord(trigger, notes) {
    global RealisticChordStart, StartDelayMax

    first := true

    for note in notes {
        if !first && RealisticChordStart && StartDelayMax > 0
            Sleep(Random(1, StartDelayMax))

        PressNote(trigger, note)
        first := false
    }
}

PressNote(trigger, note) {
    global Slots, KeyOwners

    mapped := MapNote(note)
    key := mapped.key
    shift := mapped.shift
    slot := Slots[trigger]

    if slot.Has(key)
        return

    if !KeyOwners.Has(key)
        KeyOwners[key] := 0

    if KeyOwners[key] > 0
        SendEvent("{" . key . " up}")

    SendKeyDown(key, shift)

    KeyOwners[key] += 1
    slot[key] := true
}

SendKeyDown(key, shift) {
    if shift {
        SendEvent("{LShift down}")
        SendEvent("{" . key . " down}")
        SendEvent("{LShift up}")
    } else {
        SendEvent("{" . key . " down}")
    }
}

; ============================================================
; note release
; ============================================================

ReleaseSlot(trigger) {
    global Slots, KeyOwners
    global RealisticChordRelease, ReleaseDelayMax

    ; Prevent new hotkey/timer threads from modifying Slots or
    ; KeyOwners while this release pass is in progress.
    Critical("On")

    slot := Slots[trigger]

    if slot.Count {
        releaseCount := slot.Count
        keysToRelease := []

        for key, owned in slot
            keysToRelease.Push(key)

        first := true

        for key in keysToRelease {
            if !first && RealisticChordRelease && ReleaseDelayMax > 0 {
                if releaseCount = 2 {
                    delayMin := Max(1, ReleaseDelayMax)
                    delayMax := ReleaseDelayMax * 2
                    Sleep(Random(delayMin, delayMax))
                } else {
                    Sleep(Random(1, ReleaseDelayMax))
                }
            }

            if KeyOwners.Has(key) {
                KeyOwners[key] -= 1

                if KeyOwners[key] <= 0 {
                    SendEvent("{" . key . " up}")
                    KeyOwners.Delete(key)
                }
            } else {
                ; Fail-safe: if ownership bookkeeping was lost,
                ; explicitly release the key instead of leaving it held.
                SendEvent("{" . key . " up}")
            }

            first := false
        }

        slot.Clear()
    }

    Critical("Off")
}

ReleaseAllSlots() {
    global Slots, KeyOwners

    for trigger, slot in Slots
        ReleaseSlot(trigger)

    ; Final safety net: send key-up for any keys still tracked.
    for key, owners in KeyOwners
        SendEvent("{" . key . " up}")

    KeyOwners.Clear()
}

; ============================================================
; character -> physical key mapping
; ============================================================

MapNote(note) {
    code := Ord(note)

    if code >= 65 && code <= 90
        return {key: Chr(code + 32), shift: true}

    if code >= 97 && code <= 122
        return {key: note, shift: false}

    if code >= 48 && code <= 57
        return {key: note, shift: false}

    switch code {
        case 33:
            return {key: "1", shift: true}
        case 34:
            return {key: "vkDE", shift: true}
        case 35:
            return {key: "3", shift: true}
        case 36:
            return {key: "4", shift: true}
        case 37:
            return {key: "5", shift: true}
        case 38:
            return {key: "7", shift: true}
        case 39:
            return {key: "vkDE", shift: false}
        case 40:
            return {key: "9", shift: true}
        case 41:
            return {key: "0", shift: true}
        case 42:
            return {key: "8", shift: true}
        case 43:
            return {key: "vkBB", shift: true}
        case 44:
            return {key: "vkBC", shift: false}
        case 45:
            return {key: "vkBD", shift: false}
        case 46:
            return {key: "vkBE", shift: false}
        case 47:
            return {key: "vkBF", shift: false}
        case 58:
            return {key: "vkBA", shift: true}
        case 59:
            return {key: "vkBA", shift: false}
        case 60:
            return {key: "vkBC", shift: true}
        case 61:
            return {key: "vkBB", shift: false}
        case 62:
            return {key: "vkBE", shift: true}
        case 63:
            return {key: "vkBF", shift: true}
        case 64:
            return {key: "2", shift: true}
        case 94:
            return {key: "6", shift: true}
        case 95:
            return {key: "vkBD", shift: true}
        case 96:
            return {key: "vkC0", shift: false}
        case 124:
            return {key: "vkDC", shift: true}
        case 126:
            return {key: "vkC0", shift: true}
        default:
            return {key: note, shift: false}
    }
}
