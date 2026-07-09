from __future__ import annotations

import sys
from pathlib import Path
from typing import Callable

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QAction, QColor, QFont, QWheelEvent
from PySide6.QtWidgets import (
    QApplication,
    QColorDialog,
    QComboBox,
    QDialog,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMenu,
    QMessageBox,
    QPushButton,
    QSlider,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from .epub import EpubParseError, EpubParser
from .models import ReadingDocument
from .scrolling import MAXIMUM_FPS, animation_interval_ms, next_offset, progress_percent, smoothed_offset
from .settings import ReaderSettings
from .store import LibraryStore, ProgressStore, ReadingProgress


class ReaderTextBrowser(QTextBrowser):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setOpenExternalLinks(False)
        self.setReadOnly(True)
        self.setFrameShape(QTextBrowser.Shape.NoFrame)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)

    def wheelEvent(self, event: QWheelEvent) -> None:
        parent = self.parent()
        if isinstance(parent, ReaderWindow):
            parent.handle_wheel(event)
            return
        super().wheelEvent(event)


class SettingsDialog(QDialog):
    def __init__(
        self,
        settings: ReaderSettings,
        parent: QWidget | None = None,
        on_preview: Callable[[], None] | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("MoyuReader 设置")
        self.settings = settings
        self.on_preview = on_preview
        self._original_color = settings.text_color

        layout = QFormLayout(self)
        self.font_combo = QComboBox()
        for title, family in [
            ("微软雅黑", "Microsoft YaHei UI"),
            ("宋体", "SimSun"),
            ("楷体", "KaiTi"),
            ("等宽", "Consolas"),
        ]:
            self.font_combo.addItem(title, family)
            if family == settings.font_family:
                self.font_combo.setCurrentIndex(self.font_combo.count() - 1)
        self.font_slider = self._slider(9, 36, settings.font_size)
        self.spacing_slider = self._slider(0, 18, settings.line_spacing)
        self.visible_slider = self._slider(0, 100, int(settings.visible_opacity * 100))
        self.hidden_slider = self._slider(0, 100, int(settings.hidden_opacity * 100))
        self.background_slider = self._slider(0, 45, int(settings.background_opacity * 100))
        self.scroll_slider = self._slider(12, 72, settings.scroll_step)
        self.keep_on_top = QPushButton("保持置顶：开" if settings.keep_on_top else "保持置顶：关")
        self.color_button = QPushButton("选择文字颜色")

        layout.addRow("字体", self.font_combo)
        layout.addRow("字号", self.font_slider)
        layout.addRow("行距", self.spacing_slider)
        layout.addRow("显示透明度", self.visible_slider)
        layout.addRow("鼠标移出透明度", self.hidden_slider)
        layout.addRow("背景透明度", self.background_slider)
        layout.addRow("滚动速度", self.scroll_slider)
        layout.addRow("置顶", self.keep_on_top)
        layout.addRow("文字颜色", self.color_button)

        button_row = QHBoxLayout()
        self.ok_button = QPushButton("确定")
        self.cancel_button = QPushButton("取消")
        button_row.addStretch(1)
        button_row.addWidget(self.ok_button)
        button_row.addWidget(self.cancel_button)
        layout.addRow(button_row)

        self.keep_on_top.clicked.connect(self._toggle_top)
        self.color_button.clicked.connect(self._choose_color)
        self.ok_button.clicked.connect(self.accept)
        self.cancel_button.clicked.connect(self.reject)

    def apply_to_settings(self) -> ReaderSettings:
        self.settings.font_family = self.font_combo.currentData()
        self.settings.font_size = self.font_slider.value()
        self.settings.line_spacing = self.spacing_slider.value()
        self.settings.visible_opacity = self.visible_slider.value() / 100
        self.settings.hidden_opacity = self.hidden_slider.value() / 100
        self.settings.background_opacity = self.background_slider.value() / 100
        self.settings.scroll_step = self.scroll_slider.value()
        self.settings.clamp_values()
        return self.settings

    @staticmethod
    def _slider(minimum: int, maximum: int, value: int) -> QSlider:
        slider = QSlider(Qt.Orientation.Horizontal)
        slider.setRange(minimum, maximum)
        slider.setValue(value)
        return slider

    def _toggle_top(self) -> None:
        self.settings.keep_on_top = not self.settings.keep_on_top
        self.keep_on_top.setText("保持置顶：开" if self.settings.keep_on_top else "保持置顶：关")

    def _choose_color(self) -> None:
        if self.on_preview:
            self.on_preview()
        dialog = QColorDialog(QColor(self.settings.text_color), self)
        dialog.setWindowTitle("选择文字颜色")
        dialog.currentColorChanged.connect(self._preview_color)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            color = dialog.currentColor()
            if color.isValid():
                self.settings.text_color = color.name().upper()
        else:
            self.settings.text_color = self._original_color
            if self.on_preview:
                self.on_preview()

    def _preview_color(self, color: QColor) -> None:
        if color.isValid():
            self.settings.text_color = color.name().upper()
            if self.on_preview:
                self.on_preview()


class LibraryDialog(QDialog):
    def __init__(self, library: LibraryStore, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("书库")
        self.selected_path: str | None = None
        self.library = library
        layout = QVBoxLayout(self)
        layout.addWidget(QLabel("打开过的 EPUB"))

        self.combo = QComboBox()
        for entry in library.entries():
            self.combo.addItem(entry.title, entry.path)
        layout.addWidget(self.combo)

        row = QHBoxLayout()
        self.open_button = QPushButton("打开")
        self.cancel_button = QPushButton("取消")
        row.addStretch(1)
        row.addWidget(self.open_button)
        row.addWidget(self.cancel_button)
        layout.addLayout(row)

        self.open_button.clicked.connect(self._accept_path)
        self.cancel_button.clicked.connect(self.reject)

    def _accept_path(self) -> None:
        self.selected_path = self.combo.currentData()
        self.accept()


class ReaderWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.settings = ReaderSettings.load()
        self.progress_store = ProgressStore()
        self.library_store = LibraryStore()
        self.parser = EpubParser()
        self.document: ReadingDocument | None = None
        self.current_chapter_index = 0
        self.current_book_path: Path | None = None
        self.smooth_target: float | None = None
        self.preview_locked = False
        self._last_progress_label_text = ""
        self.progress_timer = QTimer(self)
        self.progress_timer.setSingleShot(True)
        self.progress_timer.timeout.connect(self.save_progress)

        self.scroll_timer = QTimer(self)
        self.scroll_timer.setTimerType(Qt.TimerType.PreciseTimer)
        self.scroll_timer.setInterval(animation_interval_ms(MAXIMUM_FPS))
        self.scroll_timer.timeout.connect(self.advance_smooth_scroll)

        self.text = ReaderTextBrowser(self)
        self.chapter_box = QComboBox()
        self.previous_button = QPushButton("<")
        self.next_button = QPushButton(">")
        self.progress_label = QLabel("")

        self._configure_window()
        self._configure_ui()
        self.apply_settings()

    def _configure_window(self) -> None:
        self.setWindowTitle("MoyuReader")
        self.resize(self.settings.width, self.settings.height)
        flags = Qt.WindowType.FramelessWindowHint | Qt.WindowType.Tool
        if self.settings.keep_on_top:
            flags |= Qt.WindowType.WindowStaysOnTopHint
        self.setWindowFlags(flags)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setMouseTracking(True)

    def _configure_ui(self) -> None:
        central = QWidget()
        layout = QVBoxLayout(central)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(4)

        self.chapter_box.currentIndexChanged.connect(self.select_chapter)
        self.text.verticalScrollBar().valueChanged.connect(lambda _: self.update_progress_label())
        layout.addWidget(self.chapter_box)
        layout.addWidget(self.text, 1)

        nav = QHBoxLayout()
        self.previous_button.clicked.connect(self.previous_chapter)
        self.next_button.clicked.connect(self.next_chapter)
        self.progress_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.progress_label.setVisible(False)
        nav.addWidget(self.previous_button)
        nav.addStretch(1)
        nav.addWidget(self.progress_label)
        nav.addStretch(1)
        nav.addWidget(self.next_button)
        layout.addLayout(nav)
        self.setCentralWidget(central)

        menu = self.menuBar()
        file_menu = menu.addMenu("文件")
        self._add_action(file_menu, "打开 EPUB...", self.open_file_dialog)
        self._add_action(file_menu, "书库...", self.open_library)
        self._add_action(file_menu, "设置...", self.open_settings)
        file_menu.addSeparator()
        self._add_action(file_menu, "退出", self.close)

    def _add_action(self, menu: QMenu, title: str, callback) -> QAction:
        action = QAction(title, self)
        action.triggered.connect(callback)
        menu.addAction(action)
        return action

    def apply_settings(self) -> None:
        font = QFont(self.settings.font_family)
        font.setPointSize(self.settings.font_size)
        self.text.setFont(font)
        background_alpha = int(self.settings.background_opacity * 255)
        self.text.setStyleSheet(
            f"""
            QTextBrowser {{
                color: {self.settings.text_color};
                background: rgba(0, 0, 0, {background_alpha});
                line-height: {self.settings.font_size + self.settings.line_spacing}px;
            }}
            QScrollBar:vertical {{ width: 8px; }}
            """
        )
        self.progress_label.setStyleSheet(f"color: {self.settings.text_color};")
        self.setWindowOpacity(
            self.settings.visible_opacity if self.preview_locked else self.settings.hidden_opacity
        )

    def enterEvent(self, event) -> None:
        self.progress_label.setVisible(True)
        self.update_progress_label()
        self.setWindowOpacity(self.settings.visible_opacity)
        super().enterEvent(event)

    def leaveEvent(self, event) -> None:
        if self.preview_locked:
            super().leaveEvent(event)
            return
        self.progress_label.setVisible(False)
        self.setWindowOpacity(self.settings.hidden_opacity)
        super().leaveEvent(event)

    def open_file_dialog(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "打开 EPUB", "", "EPUB 电子书 (*.epub)")
        if path:
            self.load_book(Path(path))

    def open_library(self) -> None:
        dialog = LibraryDialog(self.library_store, self)
        if dialog.exec() == QDialog.DialogCode.Accepted and dialog.selected_path:
            self.load_book(Path(dialog.selected_path))

    def open_settings(self) -> None:
        dialog = SettingsDialog(self.settings, self, on_preview=self.preview_appearance)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            self.settings = dialog.apply_to_settings()
            self.settings.save()
            self.apply_settings()
        self.end_preview_appearance()

    def preview_appearance(self) -> None:
        self.preview_locked = True
        self.apply_settings()
        self.progress_label.setVisible(True)
        self.update_progress_label()
        self.setWindowOpacity(self.settings.visible_opacity)

    def end_preview_appearance(self) -> None:
        self.preview_locked = False
        self.progress_label.setVisible(False)
        self.apply_settings()

    def load_book(self, path: Path) -> None:
        try:
            book = self.parser.parse(path)
        except (EpubParseError, OSError, ValueError) as error:
            QMessageBox.critical(self, "EPUB 打开失败", str(error))
            return

        self.document = ReadingDocument(book)
        self.current_book_path = path
        self.library_store.record(book.title, path)
        self.chapter_box.blockSignals(True)
        self.chapter_box.clear()
        total = len(self.document.chapters)
        for chapter in self.document.chapters:
            self.chapter_box.addItem(f"第 {chapter.index + 1}/{total} 章 · {chapter.title}")
        self.chapter_box.blockSignals(False)

        progress = self.progress_store.progress_for(path)
        self.show_chapter(progress.chapter_index, progress.offset)

    def select_chapter(self, index: int) -> None:
        if index >= 0:
            self.show_chapter(index, 0)

    def show_chapter(self, index: int, offset: int = 0) -> None:
        if not self.document or not self.document.chapters:
            return

        self.stop_smooth_scroll(clear_target=True)
        self.current_chapter_index = min(max(0, index), len(self.document.chapters) - 1)
        self.text.setPlainText(self.document.chapter_text(self.current_chapter_index))
        self.text.verticalScrollBar().setValue(max(0, offset))
        self.chapter_box.blockSignals(True)
        self.chapter_box.setCurrentIndex(self.current_chapter_index)
        self.chapter_box.blockSignals(False)
        self.update_navigation()
        self.update_progress_label()
        self.schedule_progress_save()

    def update_navigation(self) -> None:
        total = len(self.document.chapters) if self.document else 0
        self.previous_button.setVisible(self.current_chapter_index > 0)
        self.next_button.setVisible(self.current_chapter_index + 1 < total)
        self.update_progress_label()

    def update_progress_label(self) -> None:
        if not self.progress_label.isVisible():
            return

        total = len(self.document.chapters) if self.document else 0
        if total <= 0:
            if self._last_progress_label_text:
                self._last_progress_label_text = ""
                self.progress_label.setText("")
            return
        scroll_bar = self.text.verticalScrollBar()
        percent = progress_percent(scroll_bar.value(), scroll_bar.maximum())
        text = f"第 {self.current_chapter_index + 1}/{total} 章 · 当前章 {percent}%"
        if text == self._last_progress_label_text:
            return
        self._last_progress_label_text = text
        self.progress_label.setText(text)

    def previous_chapter(self) -> None:
        self.show_chapter(self.current_chapter_index - 1, 0)

    def next_chapter(self) -> None:
        self.show_chapter(self.current_chapter_index + 1, 0)

    def handle_wheel(self, event: QWheelEvent) -> None:
        scroll_bar = self.text.verticalScrollBar()
        delta = event.angleDelta().y() / 120
        max_offset = scroll_bar.maximum()
        target = next_offset(
            current=self.smooth_target if self.smooth_target is not None else scroll_bar.value(),
            wheel_delta_y=delta,
            max_offset=max_offset,
            precise=False,
            wheel_step=self.settings.scroll_step,
        )
        self.smooth_target = target
        if not self.scroll_timer.isActive():
            self.scroll_timer.start()
        event.accept()

    def advance_smooth_scroll(self) -> None:
        if self.smooth_target is None:
            self.stop_smooth_scroll(clear_target=True)
            return

        scroll_bar = self.text.verticalScrollBar()
        next_value = smoothed_offset(scroll_bar.value(), self.smooth_target)
        scroll_bar.setValue(round(next_value))
        if round(next_value) == round(self.smooth_target):
            self.stop_smooth_scroll(clear_target=True)
            self.schedule_progress_save()

    def stop_smooth_scroll(self, clear_target: bool) -> None:
        self.scroll_timer.stop()
        if clear_target:
            self.smooth_target = None

    def schedule_progress_save(self) -> None:
        self.progress_timer.start(120)

    def save_progress(self) -> None:
        if not self.current_book_path:
            return
        self.progress_store.save(
            self.current_book_path,
            ReadingProgress(
                chapter_index=self.current_chapter_index,
                offset=self.text.verticalScrollBar().value(),
            ),
        )

    def resizeEvent(self, event) -> None:
        self.settings.width = self.width()
        self.settings.height = self.height()
        self.settings.save()
        self.update_progress_label()
        super().resizeEvent(event)


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("MoyuReader")
    window = ReaderWindow()
    if len(sys.argv) > 1:
        window.load_book(Path(sys.argv[1]))
    window.show()
    return app.exec()
