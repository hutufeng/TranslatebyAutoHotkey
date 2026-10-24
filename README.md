# TranslateAssistant (Windows 11 AI 划词与多模态翻译助手)

> **极轻量、免依赖、无黑框的 Windows 桌面级 AI 翻译助手。**  
> 一键无缝衔接系统级 **Microsoft Copilot** 与 **Google Gemini**，支持划词翻译、屏幕截图翻译与轻量文档附件翻译。

---

## 🌟 核心特色

* 🚀 **双引擎原生直达**：
  * **Copilot**：支持快捷抽屉栏与完整客户端双模，自带物理按键释放与防误关保护。
  * **Gemini**：支持纯净快速小浮窗与独立 PWA 大窗口双模，秒级激活置顶。
* 🎛️ **双窗口展示模式（随时自由切换）**：
  * **⚡ 快捷迷你窗口 (Mini - 默认)**：基于系统命令（Win+C / Alt+G），秒开、轻量、不占视线，极速翻译快查。
  * **🖥️ 完整独立窗口 (Full)**：基于官方应用进程，大屏幕视野、完整多轮会话树，适合长篇深度交互。
  * **右键托盘图标随时一键切换**，自动持久化保存。
* 🎯 **多模态智能三级分流**：
  * **划词短句/段落**：选中文本 ➔ 按快捷键 ➔ 自动组装提示词 ➔ **全自动回车发送**。
  * **屏幕截图 (Bitmap)**：任意截图工具截完图 ➔ 按快捷键 ➔ 自动贴图并填入专属图片提示词 ➔ **手动回车发送**（避免上传延迟被吞按键）。
  * **轻量文档/文件**：资源管理器中复制小文档 (TXT/MD/PDF等) ➔ 按快捷键 ➔ 自动贴入文件并切换为文档提示词。
* 🛡️ **剪贴板无损还原机制**：
  * 采用“毫秒级借用与立即还原”黑科技，输入长篇提示词仅耗时 0.01 秒，**原始剪贴板中的图片或文件原封不动保全**，连续翻译永不丢图。
* 🪶 **极度轻量与纯粹**：
  * 后台静默常驻，内存占用仅约 3MB，无控制台黑框打扰。
  * 托盘右键一键开启开机自启、免重启重载配置。
  * 支持编译为绿色单文件 `TranslateAssistant.exe`，彻底脱离任何运行环境。

---

## ⌨️ 极简按键交互设计

* **用户只需记一个快捷键**：默认 **`Alt + C`**（可在配置中任意修改）。
* **自动调用当前激活的引擎**：默认使用 **Microsoft Copilot**。
* **随时随地一键切换**：在右下角任务栏托盘右键，点击切换为 **Gemini**（自动写入配置文件保存，开机依然生效）。

---

## ⚙️ 配置文件说明 (`config.ini`)

所有设置均以纯 UTF-8 驱动，记事本打开直接编辑，修改后右键托盘图标点击 **“🔄 重新加载配置”** 即可秒级生效：

```ini
[General]
; 当前激活的翻译引擎：可填 Copilot 或 Gemini（默认 Copilot）
; 您可在右下角托盘图标中直接一键切换
ActiveEngine=Copilot

[UserHotkey]
; 您日常触发翻译的全局快捷键（只需记这一个键，触发当前 ActiveEngine）
; 快捷键格式：! 代表 Alt，^ 代表 Ctrl，+ 代表 Shift，# 代表 Win
TranslateHotkey=!c

[AppHotkeys]
; 目标 AI 软件自身在 Windows 系统中的唤出快捷键（若软件快捷键改变，在此修改即可）
; Copilot 系统呼出键（Win11 默认为 Win + C，即 #c）
CopilotAppHotkey=#c

; Gemini 浮窗系统呼出键（Chrome/扩展默认为 Alt + G，即 !g）
GeminiAppHotkey=!g

[Settings]
; 窗口呼出等待就绪毫秒数
CopilotDelayMs=600
GeminiDelayMs=600

; 纯文本翻译提示词模板（{text} 会自动替换为目标文本）
TextPromptTemplate=请将以下内容准确翻译为简体中文，保持自然流畅：`n`n{text}

; 截图翻译与 OCR 提示词（兼备文字提取与翻译）
ImagePrompt=请先完整提取图片中的文字内容（保留代码与排版），随后将其准确翻译为简体中文：

; 文档/文件翻译提示词（当复制了 PDF、Word、TXT、图片等文件时调用）
FilePrompt=请阅读所附文件，并将其内容准确翻译为简体中文，保持自然流畅。
```

---

## 🔨 自动生成独立 `.exe` (两种方式)

### 方式 1：GitHub Actions 云端自动构建与发布（推荐）

本项目已配置完善的 CI/CD 自动化流水线（`.github/workflows/build-release.yml`）：
* **发布新版本**：每次您在 GitHub 打一个 Git Tag（如 `v1.0.0`），GitHub Actions 会在 Windows 虚拟机上**自动编译出单文件 `TranslateAssistant.exe`，并自动发布到 GitHub Releases** 供直接下载绿色压缩包。
* **手动触发**：在 GitHub 仓库的 **Actions** 标签页中，选中 `Build and Release TranslateAssistant`，点击 **Run workflow** 即可随时自动打包生成 Artifact。

### 方式 2：本地一键生成独立 `.exe`

若需要在本地打包，直接在终端运行内置打包脚本：

```powershell
powershell -ExecutionPolicy Bypass -File "build.ps1"
```

构建脚本会自动生成 `dist/` 文件夹：
* `dist/TranslateAssistant.exe`：**绿色单文件，体积小，复制到任意未安装 AutoHotkey 的 Windows 11 电脑双击即用**。
* `dist/config.ini`：保持外置，方便随时修改配置。

---

## 🔄 开机自启动设置

提供了三种便捷管理方式：

1. **托盘一键开关（推荐）**：
   * 右键托盘绿色小图标 ➔ 点击 **“🚀 开机自启动”**，菜单前出现 `✓` 即代表生效。
   * 写入的是当前用户的 `HKCU` 注册表，**无需管理员提权，绝不弹 UAC 弹窗**。
2. **启动文件夹**：
   * 按 `Win + R` 输入 `shell:startup`，将程序的快捷方式拖入该目录。
3. **PowerShell 快速配置**：
   ```powershell
   Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "TranslateAssistant" -Value "`"$PWD\TranslateAssistant.exe`""
   ```

---

## 💡 设计哲学 (KISS 原则)

* **拒绝过度工程化**：长篇大文档翻译存在 Token 截断与摘要倾向，交给专业切片工具；本工具将 AI 最强悍的**划词秒翻**与**截图局部翻译**做到极致轻量。
* **尊重系统原生交互**：窗口已激活时不重复按键（防误关），提示词瞬时借用立即归还（防丢图），确保系统稳定与安全。
