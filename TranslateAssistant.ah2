#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; 划词与多模态翻译助手 - TranslateAssistant (Windows 11)
; ==============================================================================

global ConfigFile := A_ScriptDir . "\config.ini"

; 用户配置项与默认值
global ActiveEngine := "Copilot"
global WindowMode := "Mini" ; Mini（快捷迷你窗口）或 Full（完整独立大窗口）
global TranslateHotkey := "!c"
global CopilotAppHotkey := "#c"
global GeminiAppHotkey := "!g"
global CopilotDelayMs := 600
global GeminiDelayMs := 600
global TextPromptTemplate := "请将以下内容准确翻译为简体中文，保持自然流畅：`n`n{text}"
global ImagePrompt := "请先完整提取图片中的文字内容（保留代码与排版），随后将其准确翻译为简体中文："
global FilePrompt := "请阅读所附文件，并将其内容准确翻译为简体中文，保持自然流畅。"

LoadConfig()
InitTrayMenu()
BindHotkeys()

TrayTip "翻译助手已就绪", "引擎: " . ActiveEngine . " [" . WindowMode . "] (快捷键: " . TranslateHotkey . ")", "Iconi"

; ==============================================================================
; 核心翻译分发逻辑
; 统一由 TranslateHotkey 触发当前 ActiveEngine
; ==============================================================================

ExecuteTranslate() {
    global ActiveEngine, TextPromptTemplate, ImagePrompt, FilePrompt

    ; 临时备份原始剪贴板
    savedClip := ClipboardAll()

    ; 尝试复制屏幕当前选区
    seqBefore := DllCall("GetClipboardSequenceNumber", "UInt")
    Send "^c"
    Sleep 120
    seqAfter := DllCall("GetClipboardSequenceNumber", "UInt")

    ; 优先级 1: 成功抓取新选区文本 -> 自动发送
    if (seqAfter != seqBefore && A_Clipboard != "") {
        selectedText := Trim(A_Clipboard)
        prompt := FormatTextPrompt(selectedText)
        DispatchToEngine(ActiveEngine, "text", prompt)
        return
    }

    ; 未抓取到新选区，恢复原有剪贴板，触发优先级 2 (剪贴板已有内容)
    A_Clipboard := savedClip
    Sleep 50

    isImage := DllCall("IsClipboardFormatAvailable", "UInt", 2)  ; CF_BITMAP = 2 (纯截图)
    isFile  := DllCall("IsClipboardFormatAvailable", "UInt", 15) ; CF_HDROP = 15 (复制的文件/文档)

    if (isImage) {
        DispatchToEngine(ActiveEngine, "image", ImagePrompt)
    } else if (isFile) {
        DispatchToEngine(ActiveEngine, "file", FilePrompt)
    } else if (A_Clipboard != "") {
        existingText := Trim(A_Clipboard)
        prompt := FormatTextPrompt(existingText)
        DispatchToEngine(ActiveEngine, "text", prompt)
    }
}

FormatTextPrompt(rawText) {
    global TextPromptTemplate
    if InStr(TextPromptTemplate, "{text}") {
        return StrReplace(TextPromptTemplate, "{text}", rawText)
    }
    return TextPromptTemplate . "`n`n" . rawText
}

PasteAndRestoreClipboard(payload) {
    clipBackup := ClipboardAll()
    A_Clipboard := payload
    Send "^v"
    Sleep 120
    A_Clipboard := clipBackup
}

PressEnterToSubmit() {
    Sleep 200
    SetKeyDelay 40, 40
    SendEvent "{Enter}"
}

; ==============================================================================
; 窗口指纹探测辅助函数
; ==============================================================================

GetGeminiMiniHwnd() {
    try {
        ids := WinGetList("ahk_exe chrome.exe")
        for this_id in ids {
            if !DllCall("IsWindowVisible", "Ptr", this_id)
                continue
            WinGetPos &x, &y, &w, &h, this_id
            if (w >= 300 && w <= 650) {
                title := WinGetTitle(this_id)
                if !InStr(title, " - Google Chrome")
                    return this_id
            }
        }
    }
    return 0
}

GetGeminiFullHwnd() {
    try {
        ids := WinGetList("ahk_exe chrome.exe")
        for this_id in ids {
            if !DllCall("IsWindowVisible", "Ptr", this_id)
                continue
            WinGetPos &x, &y, &w, &h, this_id
            if (w > 650) {
                title := WinGetTitle(this_id)
                if InStr(title, "Gemini")
                    return this_id
            }
        }
    }
    return 0
}

GetCopilotMiniHwnd() {
    SetTitleMatchMode 2
    if WinExist("ahk_exe copilotapphost.exe")
        return WinExist("ahk_exe copilotapphost.exe")
    if WinExist("Copilot ahk_class ApplicationFrameWindow")
        return WinExist("Copilot ahk_class ApplicationFrameWindow")

    try {
        ids := WinGetList("ahk_exe copilotapp.exe")
        for this_id in ids {
            if !DllCall("IsWindowVisible", "Ptr", this_id)
                continue
            WinGetPos &x, &y, &w, &h, this_id
            if (w > 0 && w <= 650)
                return this_id
        }
    }
    return 0
}

GetCopilotFullHwnd() {
    try {
        ids := WinGetList("ahk_exe copilotapp.exe")
        for this_id in ids {
            if !DllCall("IsWindowVisible", "Ptr", this_id)
                continue
            WinGetPos &x, &y, &w, &h, this_id
            if (w > 650)
                return this_id
        }
    }
    return 0
}

; ==============================================================================
; 引擎调度（支持 Mini 与 Full 模式）
; ==============================================================================

DispatchToEngine(engineName, contentType, payload) {
    if (StrLower(engineName) = "gemini") {
        SendToGemini(contentType, payload)
    } else {
        SendToCopilot(contentType, payload)
    }
}

SendToCopilot(contentType, payload) {
    global WindowMode, CopilotAppHotkey, CopilotDelayMs

    if (StrLower(WindowMode) = "full") {
        ; --- 完整独立大窗口模式 (基于进程运行) ---
        fullHwnd := GetCopilotFullHwnd()
        if (fullHwnd != 0) {
            if (WinGetMinMax(fullHwnd) == -1)
                WinRestore(fullHwnd)
            WinActivate(fullHwnd)
            WinWaitActive(fullHwnd, , 1.5)
            Sleep 150
        } else {
            copilotExe := "C:\Program Files (x86)\Microsoft\Copilot\Application\copilotapp.exe"
            if FileExist(copilotExe) {
                Run '"' . copilotExe . '"'
            } else {
                try Run "copilot:"
            }
            Sleep CopilotDelayMs
        }
    } else {
        ; --- 快捷迷你窗口模式 (基于 Win+C 原生快捷指令) ---
        miniHwnd := GetCopilotMiniHwnd()
        if (miniHwnd != 0) {
            if (WinGetMinMax(miniHwnd) == -1)
                WinRestore(miniHwnd)
            WinActivate(miniHwnd)
            WinWaitActive(miniHwnd, , 1.5)
            Sleep 150
        } else {
            KeyWait "Alt", "T0.3"
            Send "{Alt up}{Ctrl up}{Shift up}"
            Sleep 50
            SetKeyDelay 40, 40
            SendEvent CopilotAppHotkey
            Sleep CopilotDelayMs
        }
    }

    if (contentType = "text") {
        A_Clipboard := payload
        Send "^v"
        PressEnterToSubmit()
    } else if (contentType = "image" || contentType = "file") {
        Send "^v"
        Sleep 500
        PasteAndRestoreClipboard(payload)
    }
}

SendToGemini(contentType, payload) {
    global WindowMode, GeminiAppHotkey, GeminiDelayMs

    if (StrLower(WindowMode) = "full") {
        ; --- 完整独立大窗口模式 (基于 Chrome PWA 应用进程) ---
        fullHwnd := GetGeminiFullHwnd()
        if (fullHwnd != 0) {
            if (WinGetMinMax(fullHwnd) == -1)
                WinRestore(fullHwnd)
            WinActivate(fullHwnd)
            WinWaitActive(fullHwnd, , 1.5)
            Sleep 150
        } else {
            try {
                Run 'chrome.exe --app="https://gemini.google.com"'
            } catch {
                Run "https://gemini.google.com"
            }
            Sleep 1500
        }
    } else {
        ; --- 快捷迷你小浮窗模式 (基于 Alt+G 原生快捷指令) ---
        miniHwnd := GetGeminiMiniHwnd()
        if (miniHwnd != 0) {
            if (WinGetMinMax(miniHwnd) == -1)
                WinRestore(miniHwnd)
            WinActivate(miniHwnd)
            WinWaitActive(miniHwnd, , 1.5)
            Sleep 150
        } else {
            KeyWait "Alt", "T0.3"
            Send "{Alt up}{Ctrl up}{Shift up}"
            Sleep 50
            SetKeyDelay 40, 40
            SendEvent GeminiAppHotkey
            Sleep GeminiDelayMs
        }
    }

    if (contentType = "text") {
        A_Clipboard := payload
        Send "^v"
        PressEnterToSubmit()
    } else if (contentType = "image" || contentType = "file") {
        Send "^v"
        Sleep 500
        PasteAndRestoreClipboard(payload)
    }
}

; ==============================================================================
; 纯 UTF-8 驱动配置读取与动态绑定
; ==============================================================================

LoadConfig() {
    global ConfigFile, ActiveEngine, WindowMode, TranslateHotkey, CopilotAppHotkey, GeminiAppHotkey
    global CopilotDelayMs, GeminiDelayMs, TextPromptTemplate, ImagePrompt, FilePrompt

    if !FileExist(ConfigFile)
        return

    try {
        fileContent := FileRead(ConfigFile, "UTF-8")
        for line in StrSplit(fileContent, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "[")
                continue

            eqPos := InStr(line, "=")
            if (eqPos > 0) {
                key := Trim(SubStr(line, 1, eqPos - 1))
                val := Trim(SubStr(line, eqPos + 1))
                val := StrReplace(val, "``n", "`n")

                switch StrLower(key) {
                    case "activeengine": ActiveEngine := val
                    case "windowmode": WindowMode := val
                    case "translatehotkey": TranslateHotkey := val
                    case "copilotapphotkey": CopilotAppHotkey := val
                    case "geminiapphotkey": GeminiAppHotkey := val
                    case "copilotdelayms": CopilotDelayMs := Integer(val)
                    case "geminidelayms": GeminiDelayMs := Integer(val)
                    case "textprompttemplate": TextPromptTemplate := val
                    case "imageprompt": ImagePrompt := val
                    case "fileprompt": FilePrompt := val
                }
            }
        }
    }
}

BindHotkeys() {
    global TranslateHotkey
    if (TranslateHotkey != "") {
        try Hotkey TranslateHotkey, (*) => ExecuteTranslate(), "On"
    }
}

; ==============================================================================
; 托盘菜单与开机自启动
; ==============================================================================

InitTrayMenu() {
    global ActiveEngine, WindowMode, TranslateHotkey
    tray := A_TrayMenu
    tray.Delete()

    modeText := (StrLower(WindowMode) = "full") ? "完整大窗口" : "快捷迷你"
    tray.Add("划词翻译助手 (" . TranslateHotkey . " -> " . ActiveEngine . " [" . modeText . "])", (*) => OpenConfigFile())
    tray.Disable("1&")
    tray.Add()

    ; 1. 引擎单选切换
    tray.Add("引擎: Microsoft Copilot", (*) => SwitchEngine("Copilot"))
    tray.Add("引擎: Google Gemini", (*) => SwitchEngine("Gemini"))
    if (StrLower(ActiveEngine) = "gemini") {
        tray.Check("引擎: Google Gemini")
    } else {
        tray.Check("引擎: Microsoft Copilot")
    }
    tray.Add()

    ; 2. 窗口模式切换 (Mini vs Full)
    tray.Add("⚡ 窗口模式: 快捷迷你窗口 (默认/秒开)", (*) => SwitchWindowMode("Mini"))
    tray.Add("🖥️ 窗口模式: 完整独立大窗口 (多轮深聊)", (*) => SwitchWindowMode("Full"))
    if (StrLower(WindowMode) = "full") {
        tray.Check("🖥️ 窗口模式: 完整独立大窗口 (多轮深聊)")
    } else {
        tray.Check("⚡ 窗口模式: 快捷迷你窗口 (默认/秒开)")
    }
    tray.Add()

    tray.Add("📝 打开配置文件 (config.ini)", (*) => OpenConfigFile())
    tray.Add("🔄 重新加载配置", (*) => Reload())

    isAutoStart := CheckAutoStart()
    tray.Add("🚀 开机自启动", (*) => ToggleAutoStart())
    if (isAutoStart)
        tray.Check("🚀 开机自启动")

    tray.Add()
    tray.Add("❌ 退出程序", (*) => ExitApp())
}

SwitchEngine(newEngine) {
    global ConfigFile, ActiveEngine
    ActiveEngine := newEngine

    if FileExist(ConfigFile) {
        try {
            content := FileRead(ConfigFile, "UTF-8")
            newContent := RegExReplace(content, "i)ActiveEngine\s*=\s*.*", "ActiveEngine=" . newEngine)
            FileDelete(ConfigFile)
            FileAppend(newContent, ConfigFile, "UTF-8")
        }
    }

    TrayTip "引擎已切换", "当前翻译引擎已切换为: " . newEngine, "Iconi"
    InitTrayMenu()
}

SwitchWindowMode(newMode) {
    global ConfigFile, WindowMode
    WindowMode := newMode

    if FileExist(ConfigFile) {
        try {
            content := FileRead(ConfigFile, "UTF-8")
            newContent := RegExReplace(content, "i)WindowMode\s*=\s*.*", "WindowMode=" . newMode)
            FileDelete(ConfigFile)
            FileAppend(newContent, ConfigFile, "UTF-8")
        }
    }

    desc := (StrLower(newMode) = "full") ? "🖥️ 完整独立大窗口" : "⚡ 快捷迷你窗口"
    TrayTip "模式已切换", "当前窗口模式已切换为: " . desc, "Iconi"
    InitTrayMenu()
}

OpenConfigFile() {
    global ConfigFile
    Run "notepad.exe " . ConfigFile
}

CheckAutoStart() {
    try {
        val := RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run", "TranslateAssistant")
        return (val != "")
    } catch {
        return false
    }
}

ToggleAutoStart() {
    regKey := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"
    if CheckAutoStart() {
        try RegDelete(regKey, "TranslateAssistant")
        TrayTip "开机自启", "已关闭开机自启动", "Iconi"
    } else {
        execPath := '"' . A_AhkPath . '" "' . A_ScriptFullPath . '"'
        try RegWrite(execPath, "REG_SZ", regKey, "TranslateAssistant")
        TrayTip "开机自启", "已开启开机自启动", "Iconi"
    }
    InitTrayMenu()
}
