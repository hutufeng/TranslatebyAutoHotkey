#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; 划词与多模态剪贴板翻译助手 - TranslateAssistant (Windows 11)
; ==============================================================================

global ConfigFile := A_ScriptDir . "\config.ini"
global CopilotHotkey := "!c"
global GeminiHotkey := "!v"
global CopilotDelayMs := 600
global GeminiDelayMs := 600
global TextPromptTemplate := "请将以下内容准确翻译为简体中文，保持自然流畅：`n`n{text}"
global ImagePrompt := "请提取并翻译图片中的内容为简体中文，保持自然流畅。"
global FilePrompt := "请阅读所附文件，并将其内容准确翻译为简体中文，保持自然流畅。"

LoadConfig()
InitTrayMenu()
BindHotkeys()

TrayTip "翻译助手已就绪", "Alt + C: Copilot | Alt + V: Gemini", "Iconi"

; ==============================================================================
; 核心分发逻辑
; 优先级 1：选中文字 -> 复制 -> 传递 -> 翻译 (自动发送)
; 优先级 2：没有选中 -> 剪贴板已有内容：
;           - 截图 (CF_BITMAP) -> 粘贴图片 -> 贴入 ImagePrompt -> 手动发送
;           - 文件 (CF_HDROP)  -> 粘贴文件 -> 贴入 FilePrompt  -> 手动发送
;           - 文本             -> 贴入文本 Prompt -> 自动发送
; ==============================================================================

ExecuteTranslate(targetEngine) {
    global TextPromptTemplate, ImagePrompt, FilePrompt

    ; 临时备份原始剪贴板
    savedClip := ClipboardAll()

    ; 尝试复制屏幕当前选区
    seqBefore := DllCall("GetClipboardSequenceNumber", "UInt")
    Send "^c"
    Sleep 120
    seqAfter := DllCall("GetClipboardSequenceNumber", "UInt")

    ; 判定是否成功抓取了新选区文本 (优先级 1)
    if (seqAfter != seqBefore && A_Clipboard != "") {
        selectedText := Trim(A_Clipboard)
        prompt := FormatTextPrompt(selectedText)
        DispatchToEngine(targetEngine, "text", prompt)
        return
    }

    ; 未抓取到新选区，恢复原有剪贴板，触发 (优先级 2: 剪贴板已有内容)
    A_Clipboard := savedClip
    Sleep 50

    ; 检查剪贴板格式
    isImage := DllCall("IsClipboardFormatAvailable", "UInt", 2)  ; CF_BITMAP = 2 (纯截图)
    isFile  := DllCall("IsClipboardFormatAvailable", "UInt", 15) ; CF_HDROP = 15 (复制的文件/文档)

    if (isImage) {
        ; 剪贴板是截图
        DispatchToEngine(targetEngine, "image", ImagePrompt)
    } else if (isFile) {
        ; 剪贴板是文件/文档（PDF/Word/代码/本地图片文件等）
        DispatchToEngine(targetEngine, "file", FilePrompt)
    } else if (A_Clipboard != "") {
        ; 剪贴板是纯文本
        existingText := Trim(A_Clipboard)
        prompt := FormatTextPrompt(existingText)
        DispatchToEngine(targetEngine, "text", prompt)
    }
}

FormatTextPrompt(rawText) {
    global TextPromptTemplate
    if InStr(TextPromptTemplate, "{text}") {
        return StrReplace(TextPromptTemplate, "{text}", rawText)
    }
    return TextPromptTemplate . "`n`n" . rawText
}

; 高性能提示词粘贴并秒级还原剪贴板（兼顾瞬时粘贴与原数据零污染）
PasteAndRestoreClipboard(payload) {
    ; 1. 完整备份剪贴板（包含图片/文件句柄等原始二进制）
    clipBackup := ClipboardAll()

    ; 2. 毫秒级借用剪贴板进行 Ctrl+V 粘贴（支持超长提示词瞬间完成）
    A_Clipboard := payload
    Send "^v"
    Sleep 120

    ; 3. 立即还原原剪贴板内容，图片/文件原样无损保全
    A_Clipboard := clipBackup
}

PressEnterToSubmit() {
    Sleep 200
    SetKeyDelay 40, 40
    SendEvent "{Enter}"
}

; ==============================================================================
; AI 引擎调用与投递（智能防误关 + 多模态分流）
; ==============================================================================

DispatchToEngine(targetEngine, contentType, payload) {
    if (StrLower(targetEngine) = "copilot") {
        SendToCopilot(contentType, payload)
    } else {
        SendToGemini(contentType, payload)
    }
}

SendToCopilot(contentType, payload) {
    global CopilotDelayMs

    SetTitleMatchMode 2
    copilotHwnd := WinExist("Copilot") || WinExist("ahk_exe msedgewebview2.exe")

    if (copilotHwnd) {
        ; 窗口已存在：直接激活置顶，绝不重复按 Win+C（防止被意外关闭）
        WinActivate(copilotHwnd)
        WinWaitActive(copilotHwnd, , 1.5)
        Sleep 250
    } else {
        ; 窗口未打开：发送 Win+C 呼出
        Send "#c"
        Sleep CopilotDelayMs
    }

    if (contentType = "text") {
        A_Clipboard := payload
        Send "^v"
        PressEnterToSubmit()
    } else if (contentType = "image" || contentType = "file") {
        ; 1. 粘贴截图或复制的文件
        Send "^v"
        Sleep 500
        ; 2. 毫秒级借用粘贴对应提示词，并立即恢复原剪贴板附件
        PasteAndRestoreClipboard(payload)
        ; 3. 多模态附件模式光标停在末尾，等待用户按回车手动发送
    }
}

SendToGemini(contentType, payload) {
    global GeminiDelayMs

    SetTitleMatchMode 2
    geminiHwnd := WinExist("Gemini ahk_exe chrome.exe") || WinExist("Gemini")

    if (geminiHwnd) {
        ; 窗口已存在：直接激活置顶，绝不重复按 Alt+G（防止被意外关闭）
        if (WinGetMinMax(geminiHwnd) == -1)
            WinRestore(geminiHwnd)
        WinActivate(geminiHwnd)
        WinWaitActive(geminiHwnd, , 1.5)
        Sleep 250
    } else {
        ; 窗口尚未打开：发送系统原生 Alt+G 呼出小浮窗
        Send "!g"
        Sleep GeminiDelayMs
    }

    if (contentType = "text") {
        A_Clipboard := payload
        Send "^v"
        PressEnterToSubmit()
    } else if (contentType = "image" || contentType = "file") {
        ; 1. 粘贴截图或复制的文件
        Send "^v"
        Sleep 500
        ; 2. 毫秒级借用粘贴对应提示词，并立即恢复原剪贴板附件
        PasteAndRestoreClipboard(payload)
        ; 3. 多模态附件模式光标停在末尾，等待用户按回车手动发送
    }
}

; ==============================================================================
; 纯 UTF-8 驱动配置读取
; ==============================================================================

LoadConfig() {
    global ConfigFile, CopilotHotkey, GeminiHotkey, CopilotDelayMs, GeminiDelayMs
    global TextPromptTemplate, ImagePrompt, FilePrompt

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
                    case "copilothotkey": CopilotHotkey := val
                    case "geminihotkey": GeminiHotkey := val
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
    global CopilotHotkey, GeminiHotkey

    if (CopilotHotkey != "") {
        try Hotkey CopilotHotkey, (*) => ExecuteTranslate("copilot"), "On"
    }
    if (GeminiHotkey != "") {
        try Hotkey GeminiHotkey, (*) => ExecuteTranslate("gemini"), "On"
    }
}

; ==============================================================================
; 托盘菜单与开机自启动
; ==============================================================================

InitTrayMenu() {
    tray := A_TrayMenu
    tray.Delete()

    tray.Add("划词翻译助手 (Alt+C: Copilot | Alt+V: Gemini)", (*) => OpenConfigFile())
    tray.Disable("1&")
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
