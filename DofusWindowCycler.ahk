#Requires AutoHotkey v2.0
#SingleInstance Force

if HasArg("--validate")
    ExitApp

APP_NAME := "Dofus Window Cycler"
SETTINGS_DIR := A_AppData "\DofusWindowCycler"
SETTINGS_FILE := SETTINGS_DIR "\settings.ini"
DEBUG_LOG_FILE := SETTINGS_DIR "\debug.log"

Windows := []
SavedOrder := LoadSavedOrder()
DEFAULT_CYCLE_HOTKEY := "F21"
CycleHotkey := ""
CycleHotkeyRegistered := ""
AllowedCaptureKeys := BuildAllowedCaptureKeys()
BlockedCaptureKeys := ["LButton", "RButton", "WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
MainGui := 0
WindowListView := 0
StatusText := 0
CycleShortcutText := 0
HotkeyStatusText := 0
DebugCheckbox := 0
DebugEdit := 0
DebugLines := []
DebugEnabled := false
IsPaused := false
IsCycling := false
ListeningForHotkey := false
LastNoWindowTipAt := 0
LastCycleIndex := 0
LastCycleHwnd := 0

SetWinDelay 0
A_IconTip := APP_NAME
BuildTrayMenu()
RefreshWindows(false, false)
if !SetCycleHotkey(LoadCycleHotkey(), false, false)
    SetCycleHotkey(DEFAULT_CYCLE_HOTKEY, true, false)
if HasArg("--smoke-test") {
    ListeningForHotkey := true
    MouseButtonDispatcher("XButton1", false)
    if !HotkeyMatches(CycleHotkey, "*XButton1")
        ExitApp 3
    ListeningForHotkey := true
    MouseButtonDispatcher("XButton2", false)
    if !HotkeyMatches(CycleHotkey, "*XButton2")
        ExitApp 4
    SetCaptureHotkeys(true)
    SetCaptureHotkeys(false)
    if !SetCycleHotkey(DEFAULT_CYCLE_HOTKEY, false, false)
        ExitApp 5
    ExitApp
}
if HasArg("--test-xbutton2") {
    if !SetCycleHotkey("*XButton2", false, false)
        ExitApp 3
    ExitApp
}
Persistent

HasArg(expected) {
    for _, arg in A_Args {
        if (arg = expected)
            return true
    }
    return false
}

BuildAllowedCaptureKeys() {
    keys := ["MButton", "Space", "Tab", "Enter", "Backspace", "Delete", "Insert", "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right"]

    Loop 24
        keys.Push("F" A_Index)

    Loop 26
        keys.Push(Chr(64 + A_Index))

    Loop 10
        keys.Push(String(A_Index - 1))

    Loop 10
        keys.Push("Numpad" (A_Index - 1))

    for _, key in ["NumpadDiv", "NumpadMult", "NumpadAdd", "NumpadSub", "NumpadDot", "NumpadEnter"]
        keys.Push(key)

    return keys
}

LoadCycleHotkey() {
    global SETTINGS_FILE, DEFAULT_CYCLE_HOTKEY

    hotkey := Trim(IniRead(SETTINGS_FILE, "Hotkeys", "Cycle", DEFAULT_CYCLE_HOTKEY))
    return hotkey = "" ? DEFAULT_CYCLE_HOTKEY : NormalizeCycleHotkey(hotkey)
}

SaveCycleHotkey(hotkey) {
    global SETTINGS_DIR, SETTINGS_FILE

    DirCreate SETTINGS_DIR
    IniWrite hotkey, SETTINGS_FILE, "Hotkeys", "Cycle"
}

SetCycleHotkey(hotkey, persist := true, notify := true) {
    global CycleHotkey, CycleHotkeyRegistered, IsPaused

    hotkey := NormalizeCycleHotkey(hotkey)
    if (hotkey = "")
        return false

    oldHotkey := CycleHotkeyRegistered
    if (oldHotkey != "" && oldHotkey != hotkey)
        try Hotkey oldHotkey, "Off"

    if IsStaticMouseHotkey(hotkey) {
        CycleHotkeyRegistered := ""
    } else {
        if !EnsureDynamicHotkey(hotkey, IsPaused ? "Off" : "On") {
            if (oldHotkey != "")
                EnsureDynamicHotkey(oldHotkey, IsPaused ? "Off" : "On")
            return false
        }
        CycleHotkeyRegistered := hotkey
    }

    CycleHotkey := hotkey

    if persist
        SaveCycleHotkey(hotkey)

    UpdateHotkeyUi()

    if notify
        ShowTip("Cycle shortcut set to " FormatHotkeyForDisplay(hotkey) ".")

    return true
}

SetCycleHotkeyEnabled(enabled) {
    global CycleHotkeyRegistered

    if (CycleHotkeyRegistered != "")
        try Hotkey CycleHotkeyRegistered, enabled ? "On" : "Off"
}

EnsureDynamicHotkey(hotkey, state := "Off") {
    try {
        Hotkey hotkey, HotkeyDispatcher, state
        return true
    } catch {
        return false
    }
}

NormalizeCycleHotkey(hotkey) {
    hotkey := Trim(hotkey)
    if (hotkey = "")
        return ""

    if RegExMatch(hotkey, "i)^\*?(mbutton|xbutton1|xbutton2)$", &match)
        return "*" CanonicalMouseButton(match[1])

    return hotkey
}

IsStaticMouseHotkey(hotkey) {
    hotkey := NormalizeCycleHotkey(hotkey)
    return hotkey = "*XButton1" || hotkey = "*XButton2"
}

CanonicalMouseButton(button) {
    button := StrLower(button)
    if (button = "mbutton")
        return "MButton"
    if (button = "xbutton1")
        return "XButton1"
    if (button = "xbutton2")
        return "XButton2"
    return button
}

HotkeyDispatcher(hotkeyName) {
    global ListeningForHotkey, CycleHotkey, IsPaused

    if ListeningForHotkey {
        HandleCapturedHotkey(hotkeyName)
        return
    }

    if (!IsPaused && HotkeyMatches(hotkeyName, CycleHotkey))
        CycleWindows()
}

MouseButtonDispatcher(buttonName, persist := true) {
    global ListeningForHotkey, CycleHotkey, IsPaused

    hotkey := NormalizeCycleHotkey(buttonName)

    if ListeningForHotkey {
        SaveCapturedHotkey(hotkey, persist)
        return
    }

    if (!IsPaused && HotkeyMatches(hotkey, CycleHotkey))
        CycleWindows()
}

HotkeyMatches(actualHotkey, configuredHotkey) {
    return NormalizeCompareHotkey(actualHotkey) = NormalizeCompareHotkey(configuredHotkey)
}

NormalizeCompareHotkey(hotkey) {
    hotkey := NormalizeCycleHotkey(hotkey)
    hotkey := RegExReplace(hotkey, "^[~$]+", "")
    return StrLower(hotkey)
}

StartHotkeyListen(*) {
    global ListeningForHotkey

    if ListeningForHotkey
        return

    ListeningForHotkey := true
    SetCycleHotkeyEnabled(false)
    SetCaptureHotkeys(true)
    SetHotkeyStatus("Press a key or side/middle mouse button. Esc cancels.")
}

StopHotkeyListen(restoreCycle := true) {
    global ListeningForHotkey, CycleHotkey

    if !ListeningForHotkey
        return

    SetCaptureHotkeys(false)
    ListeningForHotkey := false

    if (restoreCycle && CycleHotkey != "")
        SetCycleHotkey(CycleHotkey, false, false)
}

SetCaptureHotkeys(enable) {
    global AllowedCaptureKeys, BlockedCaptureKeys

    state := enable ? "On" : "Off"

    for _, key in AllowedCaptureKeys
        try Hotkey "*" key, HotkeyDispatcher, state

    for _, key in BlockedCaptureKeys
        try Hotkey "~*" key, HotkeyDispatcher, state

    try Hotkey "*Esc", HotkeyDispatcher, state
}

HandleCapturedHotkey(hotkeyName) {
    baseKey := GetBaseHotkeyName(hotkeyName)

    if (baseKey = "Esc") {
        StopHotkeyListen(true)
        SetHotkeyStatus("Shortcut capture canceled.")
        return
    }

    if IsBlockedCaptureKey(baseKey) {
        SetHotkeyStatus(baseKey " is blocked. Use a keyboard key, MButton, XButton1, or XButton2.")
        return
    }

    SaveCapturedHotkey(ComposeCapturedHotkey(baseKey))
}

SaveCapturedHotkey(newHotkey, persist := true) {
    global CycleHotkey

    StopHotkeyListen(false)

    if SetCycleHotkey(newHotkey, persist, true)
        SetHotkeyStatus("Cycle shortcut saved as " FormatHotkeyForDisplay(newHotkey) ".")
    else {
        SetHotkeyStatus("Could not use " FormatHotkeyForDisplay(newHotkey) ". Keeping " FormatHotkeyForDisplay(CycleHotkey) ".")
        SetCycleHotkey(CycleHotkey, false, false)
    }
}

GetBaseHotkeyName(hotkeyName) {
    return RegExReplace(hotkeyName, "^[~*$]+", "")
}

IsBlockedCaptureKey(baseKey) {
    global BlockedCaptureKeys

    for _, blocked in BlockedCaptureKeys {
        if (baseKey = blocked)
            return true
    }
    return false
}

ComposeCapturedHotkey(baseKey) {
    modifiers := ""

    if GetKeyState("Ctrl", "P")
        modifiers .= "^"
    if GetKeyState("Alt", "P")
        modifiers .= "!"
    if GetKeyState("Shift", "P")
        modifiers .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        modifiers .= "#"

    if (modifiers = "" && IsMouseCycleKey(baseKey))
        return "*" baseKey

    return modifiers baseKey
}

IsMouseCycleKey(baseKey) {
    return baseKey = "MButton" || baseKey = "XButton1" || baseKey = "XButton2"
}

ResetCycleHotkey(*) {
    global DEFAULT_CYCLE_HOTKEY

    StopHotkeyListen(false)
    if SetCycleHotkey(DEFAULT_CYCLE_HOTKEY, true, true)
        SetHotkeyStatus("Cycle shortcut reset to " FormatHotkeyForDisplay(DEFAULT_CYCLE_HOTKEY) ".")
}

UpdateHotkeyUi() {
    global CycleHotkey, CycleShortcutText, HotkeyStatusText, IsPaused, ListeningForHotkey

    if CycleShortcutText
        CycleShortcutText.Value := FormatHotkeyForDisplay(CycleHotkey)

    if HotkeyStatusText {
        if ListeningForHotkey
            HotkeyStatusText.Value := "Listening for a new shortcut..."
        else if IsPaused
            HotkeyStatusText.Value := "Cycling is paused."
        else
            HotkeyStatusText.Value := ""
    }
}

SetHotkeyStatus(message) {
    global HotkeyStatusText

    if HotkeyStatusText
        HotkeyStatusText.Value := message
}

DebugLog(message) {
    global SETTINGS_DIR, DEBUG_LOG_FILE, DebugLines, DebugEnabled

    if !DebugEnabled
        return

    timestamp := Format("{:02}:{:02}:{:02}.{:03}", A_Hour, A_Min, A_Sec, Mod(A_TickCount, 1000))
    line := timestamp " " message
    DebugLines.Push(line)

    while (DebugLines.Length > 160)
        DebugLines.RemoveAt(1)

    try {
        DirCreate SETTINGS_DIR
        FileAppend line "`r`n", DEBUG_LOG_FILE, "UTF-8"
    }

    UpdateDebugUi()
}

UpdateDebugUi() {
    global DebugEdit, DebugLines

    if !DebugEdit
        return

    text := ""
    for index, line in DebugLines {
        if (index > 1)
            text .= "`r`n"
        text .= line
    }
    DebugEdit.Value := text
}

ClearDebugLog(*) {
    global DebugLines, DEBUG_LOG_FILE

    DebugLines := []
    try FileDelete DEBUG_LOG_FILE
    UpdateDebugUi()
    DebugLog("debug cleared")
}

CopyDebugLog(*) {
    global DebugLines

    text := ""
    for index, line in DebugLines {
        if (index > 1)
            text .= "`r`n"
        text .= line
    }
    A_Clipboard := text
    ShowTip("Debug log copied.")
}

HwndHex(hwnd) {
    return hwnd ? Format("0x{:X}", Integer(hwnd)) : "0x0"
}

ShortText(text, maxLen := 80) {
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    return StrLen(text) > maxLen ? SubStr(text, 1, maxLen - 3) "..." : text
}

DescribeHwnd(hwnd) {
    if !hwnd
        return "hwnd=0x0"

    title := ""
    process := ""
    pid := ""
    try title := WinGetTitle("ahk_id " hwnd)
    try process := WinGetProcessName("ahk_id " hwnd)
    try pid := WinGetPID("ahk_id " hwnd)
    return "hwnd=" HwndHex(hwnd) " pid=" pid " process=" process " title=" ShortText(title)
}

DescribeWindow(win) {
    return "hwnd=" HwndHex(win["hwnd"]) " pid=" win["pid"] " process=" win["process"] " title=" ShortText(win["title"])
}

FormatHotkeyForDisplay(hotkey) {
    text := hotkey
    text := RegExReplace(text, "^\*", "")
    text := StrReplace(text, "^", "Ctrl+")
    text := StrReplace(text, "!", "Alt+")
    text := StrReplace(text, "+", "Shift+")
    text := StrReplace(text, "#", "Win+")
    return text
}

BuildTrayMenu() {
    global APP_NAME

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open", ShowMainGui)
    A_TrayMenu.Add("Refresh Dofus Windows", RefreshFromTray)
    A_TrayMenu.Add("Pause Cycling", TogglePause)
    A_TrayMenu.Add("Debug Enabled", ToggleDebug)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Open"
    A_TrayMenu.ClickCount := 1
}

ShowMainGui(*) {
    global MainGui

    RefreshWindows(false, false)
    if !MainGui
        BuildMainGui()

    UpdateListView()
    MainGui.Show("w720 h610")
}

BuildMainGui() {
    global APP_NAME, MainGui, WindowListView, StatusText, CycleShortcutText, HotkeyStatusText, DebugCheckbox, DebugEdit, DebugEnabled

    MainGui := Gui("+MinSize720x610", APP_NAME)
    MainGui.SetFont("s9", "Segoe UI")
    MainGui.Add("Text", "xm ym w680", "Detected Dofus windows. The cycle shortcut follows this order.")
    WindowListView := MainGui.Add("ListView", "xm y+8 w680 h220 -Multi", ["#", "HWND", "PID", "Process", "Title"])

    btnRefresh := MainGui.Add("Button", "xm y+12 w90", "Refresh")
    btnUp := MainGui.Add("Button", "x+8 yp w90", "Move Up")
    btnDown := MainGui.Add("Button", "x+8 yp w90", "Move Down")
    btnFirst := MainGui.Add("Button", "x+8 yp w90", "Send First")
    btnLast := MainGui.Add("Button", "x+8 yp w90", "Send Last")
    btnClose := MainGui.Add("Button", "x+8 yp w90", "Close")

    MainGui.Add("Text", "xm y+14 w105", "Cycle shortcut:")
    CycleShortcutText := MainGui.Add("Text", "x+8 yp w160", "")
    btnListen := MainGui.Add("Button", "x+8 yp-4 w90", "Listen...")
    btnResetHotkey := MainGui.Add("Button", "x+8 yp w90", "Reset to F21")

    HotkeyStatusText := MainGui.Add("Text", "xm y+8 w680", "")
    StatusText := MainGui.Add("Text", "xm y+8 w680", "")

    DebugCheckbox := MainGui.Add("CheckBox", "xm y+10 w120 Checked" (DebugEnabled ? "1" : "0"), "Debug Enabled")
    btnClearDebug := MainGui.Add("Button", "x+8 yp-4 w90", "Clear Debug")
    btnCopyDebug := MainGui.Add("Button", "x+8 yp w90", "Copy Debug")
    DebugEdit := MainGui.Add("Edit", "xm y+6 w680 h135 ReadOnly -Wrap")

    btnRefresh.OnEvent("Click", (*) => RefreshWindows(true, false))
    btnUp.OnEvent("Click", MoveSelectedUp)
    btnDown.OnEvent("Click", MoveSelectedDown)
    btnFirst.OnEvent("Click", SendSelectedFirst)
    btnLast.OnEvent("Click", SendSelectedLast)
    btnClose.OnEvent("Click", HideMainGui)
    btnListen.OnEvent("Click", StartHotkeyListen)
    btnResetHotkey.OnEvent("Click", ResetCycleHotkey)
    DebugCheckbox.OnEvent("Click", ToggleDebugFromUi)
    btnClearDebug.OnEvent("Click", ClearDebugLog)
    btnCopyDebug.OnEvent("Click", CopyDebugLog)
    MainGui.OnEvent("Close", HideMainGui)

    UpdateHotkeyUi()
    UpdateDebugUi()
}

HideMainGui(*) {
    global MainGui

    if MainGui
        MainGui.Hide()
}

RefreshFromTray(*) {
    RefreshWindows(true, false)
}

TogglePause(*) {
    global IsPaused

    IsPaused := !IsPaused
    SetCycleHotkeyEnabled(!IsPaused)
    if IsPaused {
        A_TrayMenu.Check("Pause Cycling")
        ShowTip("Cycling paused.")
    } else {
        A_TrayMenu.Uncheck("Pause Cycling")
        ShowTip("Cycling enabled.")
    }
    UpdateHotkeyUi()
}

ToggleDebug(*) {
    global DebugEnabled

    SetDebugEnabled(!DebugEnabled)
}

ToggleDebugFromUi(*) {
    global DebugCheckbox

    SetDebugEnabled(!!DebugCheckbox.Value)
}

SetDebugEnabled(enabled) {
    global DebugEnabled, DebugCheckbox

    DebugEnabled := !!enabled

    if DebugEnabled
        A_TrayMenu.Check("Debug Enabled")
    else
        A_TrayMenu.Uncheck("Debug Enabled")

    if DebugCheckbox
        DebugCheckbox.Value := DebugEnabled ? 1 : 0

    if DebugEnabled
        DebugLog("debug enabled")
    else
        UpdateDebugUi()
}

CycleWindows(*) {
    global IsPaused, IsCycling

    if IsPaused {
        DebugLog("cycle ignored: paused")
        return
    }

    if IsCycling {
        DebugLog("cycle ignored: already cycling")
        return
    }

    IsCycling := true
    try
        CycleWindowsCore()
    catch as err
        DebugLog("cycle exception: " err.Message)
    IsCycling := false
}

CycleWindowsCore(allowRefreshOnFailure := true) {
    global Windows, LastCycleIndex, LastCycleHwnd

    if (Windows.Length = 0) {
        RefreshWindows(false, false)
    }

    if (Windows.Length = 0) {
        DebugLog("cycle ignored: no Dofus windows")
        MaybeShowNoWindowTip()
        return
    }

    DebugLog("cycle begin windows=" Windows.Length " lastIndex=" LastCycleIndex " lastHwnd=" HwndHex(LastCycleHwnd))
    LogWindowOrder()

    activeHwnd := WinExist("A")
    activeIndex := FindWindowIndexByHwnd(activeHwnd)
    DebugLog("active " DescribeHwnd(activeHwnd) " activeIndex=" activeIndex)

    if (activeIndex = 0 && LastCycleHwnd)
        activeIndex := FindWindowIndexByHwnd(LastCycleHwnd)

    baseIndex := activeIndex ? activeIndex : LastCycleIndex
    if (baseIndex < 1 || baseIndex > Windows.Length)
        baseIndex := 0
    DebugLog("cycle baseIndex=" baseIndex)

    Loop Windows.Length {
        targetIndex := Mod(baseIndex + A_Index - 1, Windows.Length) + 1
        target := Windows[targetIndex]

        DebugLog("cycle try index=" targetIndex " " DescribeWindow(target))
        if ActivateWindow(target) {
            LastCycleIndex := targetIndex
            LastCycleHwnd := target["hwnd"]
            DebugLog("cycle success index=" targetIndex " activeNow=" DescribeHwnd(WinExist("A")))
            return
        }
        DebugLog("cycle failed index=" targetIndex)
    }

    DebugLog("cycle failed: no target activated")
    if allowRefreshOnFailure {
        DebugLog("cycle refresh after failed activation")
        RefreshWindows(false, false)
        if (Windows.Length > 0) {
            CycleWindowsCore(false)
            return
        }
    }
    ShowTip("Could not activate any Dofus window.")
}

LogWindowOrder() {
    global Windows

    for index, win in Windows
        DebugLog("order[" index "] " DescribeWindow(win))
}

FindWindowIndexByHwnd(hwnd) {
    global Windows

    if !hwnd
        return 0

    for index, win in Windows {
        if (win["hwnd"] = hwnd)
            return index
    }
    return 0
}

RefreshWindows(shouldNotify := false, saveIfAny := true) {
    global Windows, SavedOrder

    liveWindows := DiscoverDofusWindows()
    ordered := []
    added := Map()

    if (Windows.Length > 0) {
        DebugLog("refresh preserving live order oldCount=" Windows.Length " liveCount=" liveWindows.Length)
        hwndBuckets := BuildHwndBuckets(liveWindows)
        signatureBuckets := BuildSignatureBuckets(liveWindows)

        for _, oldWin in Windows {
            oldHwnd := oldWin["hwnd"]
            if (hwndBuckets.Has(oldHwnd) && hwndBuckets[oldHwnd].Length > 0) {
                win := hwndBuckets[oldHwnd].RemoveAt(1)
                ordered.Push(win)
                added[win["hwnd"]] := true
                continue
            }

            signature := oldWin["signature"]
            if (signatureBuckets.Has(signature) && signatureBuckets[signature].Length > 0) {
                win := signatureBuckets[signature].RemoveAt(1)
                if !added.Has(win["hwnd"]) {
                    ordered.Push(win)
                    added[win["hwnd"]] := true
                }
            }
        }
    } else {
        DebugLog("refresh building from saved signatures liveCount=" liveWindows.Length " savedCount=" SavedOrder.Length)
        buckets := BuildSignatureBuckets(liveWindows)

        for _, signature in SavedOrder {
            if (buckets.Has(signature) && buckets[signature].Length > 0) {
                win := buckets[signature].RemoveAt(1)
                ordered.Push(win)
                added[win["hwnd"]] := true
            }
        }
    }

    for _, win in liveWindows {
        if !added.Has(win["hwnd"])
            ordered.Push(win)
    }

    Windows := ordered

    if (saveIfAny && Windows.Length > 0)
        SaveOrder()

    UpdateListView()

    if shouldNotify {
        if (Windows.Length > 0)
            ShowTip(Windows.Length " Dofus window(s) detected.")
        else
            ShowTip("No Dofus windows detected.")
    }
}

BuildHwndBuckets(windowsToBucket) {
    buckets := Map()

    for _, win in windowsToBucket {
        hwnd := win["hwnd"]
        if !buckets.Has(hwnd)
            buckets[hwnd] := []
        buckets[hwnd].Push(win)
    }

    return buckets
}

DiscoverDofusWindows() {
    found := []

    for _, hwnd in WinGetList() {
        if !IsCandidateWindow(hwnd)
            continue

        title := Trim(WinGetTitle("ahk_id " hwnd))
        process := WinGetProcessName("ahk_id " hwnd)

        if !IsDofusWindow(title, process)
            continue

        pid := WinGetPID("ahk_id " hwnd)
        found.Push(Map(
            "hwnd", hwnd,
            "pid", pid,
            "process", process,
            "title", title,
            "signature", MakeSignature(process, title)
        ))
    }

    return found
}

IsCandidateWindow(hwnd) {
    if !DllCall("IsWindowVisible", "ptr", hwnd)
        return false

    title := Trim(WinGetTitle("ahk_id " hwnd))
    if (title = "")
        return false

    exStyle := WinGetExStyle("ahk_id " hwnd)
    if (exStyle & 0x80)
        return false

    return true
}

IsDofusWindow(title, process) {
    global APP_NAME

    processLower := StrLower(process)
    titleLower := StrLower(title)

    if (InStr(processLower, "autohotkey") || titleLower = StrLower(APP_NAME))
        return false

    if InStr(processLower, "dofus")
        return true

    return InStr(processLower, "ankama") && RegExMatch(titleLower, "(^|[^a-z])dofus([^a-z]|$)")
}

MakeSignature(process, title) {
    normalizedTitle := RegExReplace(Trim(title), "\s+", " ")
    return StrLower(process) "|" StrLower(normalizedTitle)
}

BuildSignatureBuckets(windowsToBucket) {
    buckets := Map()

    for _, win in windowsToBucket {
        signature := win["signature"]
        if !buckets.Has(signature)
            buckets[signature] := []
        buckets[signature].Push(win)
    }

    return buckets
}

ActivateWindow(win) {
    hwnd := win["hwnd"]

    if !WinExist("ahk_id " hwnd) {
        DebugLog("activate missing hwnd=" HwndHex(hwnd))
        return false
    }

    try {
        if WinActive("ahk_id " hwnd) {
            DebugLog("activate already active " DescribeWindow(win))
            return true
        }

        DebugLog("activate start " DescribeWindow(win))
        WinActivate "ahk_id " hwnd
        if WinWaitActive("ahk_id " hwnd,, 0.10) {
            DebugLog("activate winactivate ok hwnd=" HwndHex(hwnd))
            return true
        }

        WinShow "ahk_id " hwnd
        WinRestore "ahk_id " hwnd
        WinActivate "ahk_id " hwnd
        if WinWaitActive("ahk_id " hwnd,, 0.12) {
            DebugLog("activate restore ok hwnd=" HwndHex(hwnd))
            return true
        }

        result := DllCall("SetForegroundWindow", "ptr", hwnd)
        if WinWaitActive("ahk_id " hwnd,, 0.12) {
            DebugLog("activate setforeground ok result=" result " hwnd=" HwndHex(hwnd))
            return true
        }

        DebugLog("activate failed result=" result " activeNow=" DescribeHwnd(WinExist("A")))
        return false
    } catch as err {
        DebugLog("activate exception hwnd=" HwndHex(hwnd) " message=" err.Message)
        return false
    }
}

MoveSelectedUp(*) {
    global Windows

    row := GetSelectedRow()
    if (row <= 1)
        return

    temp := Windows[row - 1]
    Windows[row - 1] := Windows[row]
    Windows[row] := temp
    SaveOrder()
    UpdateListView()
    SelectRow(row - 1)
}

MoveSelectedDown(*) {
    global Windows

    row := GetSelectedRow()
    if (row = 0 || row >= Windows.Length)
        return

    temp := Windows[row + 1]
    Windows[row + 1] := Windows[row]
    Windows[row] := temp
    SaveOrder()
    UpdateListView()
    SelectRow(row + 1)
}

SendSelectedFirst(*) {
    global Windows

    row := GetSelectedRow()
    if (row <= 1)
        return

    win := Windows.RemoveAt(row)
    Windows.InsertAt(1, win)
    SaveOrder()
    UpdateListView()
    SelectRow(1)
}

SendSelectedLast(*) {
    global Windows

    row := GetSelectedRow()
    if (row = 0 || row >= Windows.Length)
        return

    win := Windows.RemoveAt(row)
    Windows.Push(win)
    SaveOrder()
    UpdateListView()
    SelectRow(Windows.Length)
}

GetSelectedRow() {
    global WindowListView

    if !WindowListView
        return 0

    return WindowListView.GetNext(0)
}

SelectRow(row) {
    global WindowListView, Windows

    if (WindowListView && row >= 1 && row <= Windows.Length)
        WindowListView.Modify(row, "Select Focus Vis")
}

UpdateListView() {
    global Windows, WindowListView, StatusText

    if !WindowListView
        return

    WindowListView.Delete()
    for index, win in Windows
        WindowListView.Add("", index, HwndHex(win["hwnd"]), win["pid"], win["process"], win["title"])

    WindowListView.ModifyCol(1, 42)
    WindowListView.ModifyCol(2, 92)
    WindowListView.ModifyCol(3, 70)
    WindowListView.ModifyCol(4, 100)
    WindowListView.ModifyCol(5, 360)

    if StatusText
        StatusText.Value := Windows.Length " Dofus window(s) detected."
}

LoadSavedOrder() {
    global SETTINGS_FILE

    order := []
    count := Integer(IniRead(SETTINGS_FILE, "Order", "Count", 0))

    Loop count {
        signature := IniRead(SETTINGS_FILE, "Order", "Item" A_Index, "")
        if (signature != "")
            order.Push(signature)
    }

    return order
}

SaveOrder() {
    global SETTINGS_DIR, SETTINGS_FILE, Windows, SavedOrder

    DirCreate SETTINGS_DIR
    SavedOrder := []
    for _, win in Windows
        SavedOrder.Push(win["signature"])

    try IniDelete SETTINGS_FILE, "Order"
    IniWrite SavedOrder.Length, SETTINGS_FILE, "Order", "Count"

    for index, signature in SavedOrder
        IniWrite signature, SETTINGS_FILE, "Order", "Item" index
}

MaybeShowNoWindowTip() {
    global LastNoWindowTipAt

    now := A_TickCount
    if (now - LastNoWindowTipAt > 3000) {
        ShowTip("No Dofus windows detected.")
        LastNoWindowTipAt := now
    }
}

ShowTip(message) {
    global APP_NAME

    try TrayTip(message, APP_NAME, 1)
}

*XButton1::
{
    MouseButtonDispatcher("XButton1")
}

*XButton2::
{
    MouseButtonDispatcher("XButton2")
}
