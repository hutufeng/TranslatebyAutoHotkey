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

; 智能剥离所有历史残留的重复提示词，彻底根除“俄罗斯套娃堆叠”
CleanPromptFromText(rawText) {
    global TextPromptTemplate
    prefix := StrReplace(TextPromptTemplate, "{text}", "")
    prefix := Trim(prefix)

    cleanText := rawText
    loop 25 {
        cleanText := Trim(cleanText)
        if (prefix != "" && InStr(cleanText, prefix) = 1) {
            cleanText := SubStr(cleanText, StrLen(prefix) + 1)
        } else {
            break
        }
    }
    return Trim(cleanText)
}

FormatTextPrompt(rawText) {
    global TextPromptTemplate
    pureText := CleanPromptFromText(rawText)
    if InStr(TextPromptTemplate, "{text}") {
        return StrReplace(TextPromptTemplate, "{text}", pureText)
    }
    return TextPromptTemplate . "`n`n" . pureText
}

; 毫秒级借用并在 120ms 内立即还原剪贴板（彻底防止提示词污染系统剪贴板）
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

; 统一内容投递器（消除重复代码）
DeliverPayload(contentType, payload) {
    if (contentType = "text") {
        PasteAndRestoreClipboard(payload)
        PressEnterToSubmit()
    } else if (contentType = "image" || contentType = "file") {
        Send "^v"
        Sleep 500
        PasteAndRestoreClipboard(payload)
    }
}

; ==============================================================================
; 纯进程与窗口直接前置激活（不依赖任何屏幕坐标与大小，彻底杜绝 Toggle 误关闭）
; ==============================================================================

ActivateCopilotDirect() {
    try {
        ids := WinGetList("ahk_exe copilotapp.exe")
        for id in ids {
            if DllCall("IsWindowVisible", "Ptr", id) {
                WinGetPos &x, &y, &w, &h, id
                if (w > 100 && h > 100) {
                    if (WinGetMinMax(id) == -1)
                        WinRestore(id)
                    WinActivate(id)
                    WinWaitActive(id, , 1.5)
                    return true
                }
            }
        }
    }

    SetTitleMatchMode 2
    if WinExist("Copilot") {
        hwnd := WinExist("Copilot")
        if DllCall("IsWindowVisible", "Ptr", hwnd) {
            WinGetPos &x, &y, &w, &h, hwnd
            if (w > 100 && h > 100) {
                if (WinGetMinMax(hwnd) == -1)
                    WinRestore(hwnd)
                WinActivate(hwnd)
                WinWaitActive(hwnd, , 1.5)
                return true
            }
        }
    }
    return false
}

ActivateGeminiDirect() {
    try {
        ids := WinGetList("ahk_exe chrome.exe")
        for id in ids {
            if DllCall("IsWindowVisible", "Ptr", id) {
                title := WinGetTitle(id)
                if !InStr(title, " - Google Chrome") {
                    WinGetPos &x, &y, &w, &h, id
                    if (w > 100 && h > 100) {
                        if (WinGetMinMax(id) == -1)
                            WinRestore(id)
                        WinActivate(id)
                        WinWaitActive(id, , 1.5)
                        return true
                    }
                }
            }
        }
    }
    return false
}

ActivateGeminiFullDirect() {
    try {
        ids := WinGetList("ahk_exe chrome.exe")
        for id in ids {
            if DllCall("IsWindowVisible", "Ptr", id) {
                title := WinGetTitle(id)
                if InStr(title, "Gemini") {
                    if (WinGetMinMax(id) == -1)
                        WinRestore(id)
                    WinActivate(id)
                    WinWaitActive(id, , 1.5)
                    return true
                }
            }
        }
    }
    return false
}

; ==============================================================================
; 引擎调度
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

    if (!ActivateCopilotDirect()) {
        if (StrLower(WindowMode) = "full") {
            copilotExe := "C:\Program Files (x86)\Microsoft\Copilot\Application\copilotapp.exe"
            if FileExist(copilotExe) {
                Run '"' . copilotExe . '"'
            } else {
                try Run "copilot:"
            }
        } else {
            KeyWait "Alt", "T0.3"
            Send "{Alt up}{Ctrl up}{Shift up}"
            Sleep 50
            SetKeyDelay 40, 40
            SendEvent CopilotAppHotkey
        }
        Sleep CopilotDelayMs
    } else {
        Sleep 150
    }

    DeliverPayload(contentType, payload)
}

SendToGemini(contentType, payload) {
    global WindowMode, GeminiAppHotkey, GeminiDelayMs

    isActivated := false

    if (StrLower(WindowMode) = "full") {
        isActivated := ActivateGeminiFullDirect()
        if (!isActivated) {
            try {
                Run 'chrome.exe --app="https://gemini.google.com"'
            } catch {
                Run "https://gemini.google.com"
            }
            Sleep 1500
        }
    } else {
        isActivated := ActivateGeminiDirect()
        if (!isActivated) {
            KeyWait "Alt", "T0.3"
            Send "{Alt up}{Ctrl up}{Shift up}"
            Sleep 50
            SetKeyDelay 40, 40
            SendEvent GeminiAppHotkey
            Sleep GeminiDelayMs
        }
    }

    if (isActivated)
        Sleep 150

    DeliverPayload(contentType, payload)
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

; 安全回写配置项
UpdateIniKey(keyName, keyValue) {
    global ConfigFile
    if FileExist(ConfigFile) {
        try {
            content := FileRead(ConfigFile, "UTF-8")
            pattern := "i)" . keyName . "\s*=\s*.*"
            replacement := keyName . "=" . keyValue
            newContent := RegExReplace(content, pattern, replacement)
            FileDelete(ConfigFile)
            FileAppend(newContent, ConfigFile, "UTF-8")
        }
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
    global ActiveEngine
    ActiveEngine := newEngine
    UpdateIniKey("ActiveEngine", newEngine)
    TrayTip "引擎已切换", "当前翻译引擎已切换为: " . newEngine, "Iconi"
    InitTrayMenu()
}

SwitchWindowMode(newMode) {
    global WindowMode
    WindowMode := newMode
    UpdateIniKey("WindowMode", newMode)
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
