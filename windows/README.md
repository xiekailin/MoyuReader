# MoyuReader Windows

Windows 版摸鱼 EPUB 阅读器。

## 功能

- 透明悬浮阅读窗
- 鼠标移入显示文字，移出降低透明度
- EPUB 打开和书库
- 单章阅读模式：滚到章节底部不会自动进入下一章
- 底部 `<` / `>` 切换上一章和下一章
- 中文设置：字号、行距、透明度、文字颜色、置顶
- 鼠标滚动使用最高 240FPS 目标的精确定时器

## 开发运行

```powershell
cd windows
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m moyureader_win
```

打开指定 EPUB：

```powershell
.\.venv\Scripts\python.exe -m moyureader_win "D:\Books\demo.epub"
```

## 打包 exe

在 Windows CMD 中运行：

```bat
cd windows
build_windows.bat
```

也可以在 PowerShell 中运行：

```powershell
cd windows
.\build_windows.ps1
```

脚本会自动检测 Python 3.12。没有 Python 3.12 时，会优先用 `winget` 自动安装；没有 `winget` 时，会从 python.org 下载 Python 3.12.10 当前用户安装包并静默安装。

这个目录是自包含的，直接把 `windows` 文件夹压缩到 Windows 电脑即可。

输出文件：

```text
windows\dist\MoyuReader.exe
```

这是包含 Python 和 PySide6 运行环境的单文件 EXE，目标电脑不需要安装 Python。

如果想重新干净打包：

```bat
build_windows.bat -Clean
```
