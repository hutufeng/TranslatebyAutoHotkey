#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; 划词与多模态翻译助手 - TranslateAssistant (Windows 11)
; ==============================================================================

global ConfigFile := A_ScriptDir . "\config.ini"

; 用户配置项与默认值
global ActiveEngine := "Copilot"
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

TrayTip "翻译助手已就绪", "当前引擎: " . ActiveEngine . " (快捷键: " . TranslateHotkey . ")", "Iconi"

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

; 毫秒级借用并立即还原剪贴板
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
; AI 引擎调用（使用 config.ini 中可配的 AppHotkeys）
; ==============================================================================

DispatchToEngine(engineName, contentType, payload) {
    if (StrLower(engineName) = "gemini") {
        SendToGemini(contentType, payload)
    } else {
        SendToCopilot(contentType, payload)
    }
}

SendToCopilot(contentType, payload) {
    global CopilotAppHotkey, CopilotDelayMs

    SetTitleMatchMode 2
    copilotHwnd := WinExist("Copilot") || WinExist("ahk_exe msedgewebview2.exe")

    if (copilotHwnd) {
        ; 窗口已存在：直接激活置顶，绝不重复发送唤起按键（防止被 Toggle 误关闭）
        WinActivate(copilotHwnd)
        WinWaitActive(copilotHwnd, , 1.5)
        Sleep 250
    } else {
        ; 窗口未打开：发送配置文件中指定的 Copilot 唤起快捷键
        Send CopilotAppHotkey
        Sleep CopilotDelayMs
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
    global GeminiAppHotkey, GeminiDelayMs

    SetTitleMatchMode 2
    geminiHwnd := WinExist("Gemini ahk_exe chrome.exe") || WinExist("Gemini")

    if (geminiHwnd) {
        ; 窗口已存在：直接激活置顶，绝不重复发送唤起按键（防止被 Toggle 误关闭）
        if (WinGetMinMax(geminiHwnd) == -1)
            WinRestore(geminiHwnd)
        WinActivate(geminiHwnd)
        WinWaitActive(geminiHwnd, , 1.5)
        Sleep 250
    } else {
        ; 窗口未打开：发送配置文件中指定的 Gemini 唤起快捷键
        Send GeminiAppHotkey
        Sleep GeminiDelayMs
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
    global ConfigFile, ActiveEngine, TranslateHotkey, CopilotAppHotkey, GeminiAppHotkey
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
    global ActiveEngine, TranslateHotkey
    tray := A_TrayMenu
    tray.Delete()

    tray.Add("划词翻译助手 (" . TranslateHotkey . " -> " . ActiveEngine . ")", (*) => OpenConfigFile())
    tray.Disable("1&")
    tray.Add()

    ; 单选引擎切换
    tray.Add("切换默认引擎为: Copilot", (*) => SwitchEngine("Copilot"))
    tray.Add("切换默认引擎为: Gemini", (*) => SwitchEngine("Gemini"))
    if (StrLower(ActiveEngine) = "gemini") {
        tray.Check("切换默认引擎为: Gemini")
    } else {
        tray.Check("切换默认引擎为: Copilot")
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

    ; 更新配置文件中的 ActiveEngine 行
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
