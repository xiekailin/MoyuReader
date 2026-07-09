# MoyuReader

透明悬浮 EPUB 阅读器。当前仓库包含 macOS 原生版和 Windows 版。

## 功能

- 悬浮透明阅读窗，鼠标移入显示，移出降低透明度。
- EPUB 解析、书库、中文设置。
- 目录下拉、当前章进度、当前书章节进度。
- 单章阅读模式：滚到底不会自动进入下一章。
- 底部 `<` / `>` 切换上一章和下一章。
- 字号、行距、字体、文字颜色、背景透明度、鼠标移出透明度可设置。
- macOS 支持根据背后应用明暗自动调整文字颜色。
- macOS 使用显示同步滚动；Windows 版使用最高 240FPS 目标的精确定时滚动。

## macOS 开发运行

```bash
swift run MoyuReader
```

通过菜单栏 `Moyu` 或 Dock 菜单打开 `.epub`。

自动文字颜色需要读取阅读窗背后的屏幕区域。macOS 第一次启用时可能会要求“屏幕录制”权限；拒绝后会回退到手动字体颜色。

## macOS 打包

```bash
./Scripts/build_app.sh
open build/MoyuReader.app
```

生成 DMG：

```bash
./Scripts/build_dmg.sh
open build/MoyuReader-mac.dmg
```

## Windows 版

Windows 版在 `windows/` 目录，使用 Python + PySide6 实现。

```powershell
cd windows
.\build_windows.ps1
```

输出：

```text
windows\dist\MoyuReader\MoyuReader.exe
```

## 测试

```bash
swift test --enable-code-coverage
pipx run pytest windows/tests
```

## 协议

MIT
