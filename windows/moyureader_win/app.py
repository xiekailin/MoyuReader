from __future__ import annotations

import sys
from pathlib import Path
from typing import Callable

from PySide6.QtCore import QEvent, QPoint, Qt, QTimer
from PySide6.QtGui import (
    QAction,
    QColor,
    QCursor,
    QFont,
    QIcon,
    QKeyEvent,
    QMouseEvent,
    QTextBlockFormat,
    QTextCharFormat,
    QTextCursor,
    QWheelEvent,
)
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
    QSystemTrayIcon,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from .epub import EpubParseError, EpubParser
from .chapter_navigation import ChapterDirection, chapter_destination
from .models import ReadingDocument
from .reader_formatting import line_height_percent
from .scrolling import MAXIMUM_FPS, animation_interval_ms, next_offset, progress_percent, smoothed_offset
from .settings import ReaderSettings
from .store import LibraryStore, ProgressStore, ReadingProgress
from .window_geometry import ResizeEdges, WindowGeometry, edge_at, resize_geometry


def resource_path(name: str) -> Path:
    bundle_root = getattr(sys, "_MEIPASS", None)
    if bundle_root:
        bundled = Path(bundle_root) / "Resources" / name
        if bundled.exists():
            return bundled

    return Path(__file__).resolve().parents[1] / name


class ReaderTextBrowser(QTextBrowser):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setOpenExternalLinks(False)
        self.setReadOnly(True)
        self.setFrameShape(QTextBrowser.Shape.NoFrame)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)

    def wheelEvent(self, event: QWheelEvent) -> None:
        reader = self.reader_window()
        if reader:
            reader.handle_wheel(event)
            return
        super().wheelEvent(event)

    def keyPressEvent(self, event: QKeyEvent) -> None:
        reader = self.reader_window()
        if reader and reader.handle_chapter_key(
            event, mouse_over_text=self.underMouse() or self.viewport().underMouse()
        ):
            return
        super().keyPressEvent(event)

    def reader_window(self) -> ReaderWindow | None:
        widget: QWidget | None = self
        while widget is not None:
            if isinstance(widget, ReaderWindow):
                return widget
            widget = widget.parentWidget()
        return None


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
        self._mouse_inside = False
        self._last_progress_label_text = ""
        self._drag_start_global: QPoint | None = None
        self._drag_start_position: QPoint | None = None
        self._resize_start_global: QPoint | None = None
        self._resize_start_geometry: WindowGeometry | None = None
        self._resize_edges = ResizeEdges.NONE
        self._resize_widgets: tuple[QWidget, ...] = ()
        self.progress_timer = QTimer(self)
        self.progress_timer.setSingleShot(True)
        self.progress_timer.timeout.connect(self.save_progress)

        self.scroll_timer = QTimer(self)
        self.scroll_timer.setTimerType(Qt.TimerType.PreciseTimer)
        self.scroll_timer.setInterval(animation_interval_ms(MAXIMUM_FPS))
        self.scroll_timer.timeout.connect(self.advance_smooth_scroll)

        self.geometry_timer = QTimer(self)
        self.geometry_timer.setSingleShot(True)
        self.geometry_timer.setInterval(250)
        self.geometry_timer.timeout.connect(self.settings.save)

        self.hover_leave_timer = QTimer(self)
        self.hover_leave_timer.setSingleShot(True)
        self.hover_leave_timer.setInterval(80)
        self.hover_leave_timer.timeout.connect(self._confirm_mouse_left)

        self.text = ReaderTextBrowser(self)
        self.chapter_box = QComboBox()
        self.previous_button = QPushButton("<")
        self.next_button = QPushButton(">")
        self.progress_label = QLabel("")
        self.tray_icon = QSystemTrayIcon(self)
        self.tray_toggle_action: QAction | None = None

        self._configure_window()
        self._configure_ui()
        self._configure_tray()
        self.apply_settings()

    def _configure_window(self) -> None:
        self.setWindowTitle("MoyuReader")
        self.resize(self.settings.width, self.settings.height)
        self.setMinimumSize(260, 100)
        flags = Qt.WindowType.FramelessWindowHint | Qt.WindowType.Tool
        if self.settings.keep_on_top:
            flags |= Qt.WindowType.WindowStaysOnTopHint
        self.setWindowFlags(flags)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setMouseTracking(True)
        self.installEventFilter(self)

    def _configure_ui(self) -> None:
        central = QWidget()
        central.setObjectName("readerCentral")
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

        self._resize_widgets = (
            self,
            central,
            self.text,
            self.text.viewport(),
            self.menuBar(),
            self.chapter_box,
            self.previous_button,
            self.next_button,
            self.progress_label,
        )
        for widget in self._resize_widgets:
            widget.setMouseTracking(True)
            widget.installEventFilter(self)

    def _configure_tray(self) -> None:
        icon = QIcon(str(resource_path("AppIcon.png")))
        if not icon.isNull():
            self.setWindowIcon(icon)
            self.tray_icon.setIcon(icon)

        self.tray_icon.setToolTip("MoyuReader")
        tray_menu = QMenu(self)
        self.tray_toggle_action = self._add_action(tray_menu, "隐藏窗口", self.toggle_window)
        self._add_action(tray_menu, "打开 EPUB...", self.open_file_dialog)
        self._add_action(tray_menu, "书库...", self.open_library)
        self._add_action(tray_menu, "设置...", self.open_settings)
        tray_menu.addSeparator()
        self._add_action(tray_menu, "退出", self.quit_application)
        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self._tray_activated)
        if QSystemTrayIcon.isSystemTrayAvailable():
            self.tray_icon.show()

    def _tray_activated(self, reason: QSystemTrayIcon.ActivationReason) -> None:
        if reason in {
            QSystemTrayIcon.ActivationReason.Trigger,
            QSystemTrayIcon.ActivationReason.DoubleClick,
        }:
            self.toggle_window()

    def toggle_window(self) -> None:
        if self.isVisible() and not self.isMinimized():
            self.hide()
            if self.tray_toggle_action:
                self.tray_toggle_action.setText("显示窗口")
            return

        self.showNormal()
        self.raise_()
        self.activateWindow()
        if self.tray_toggle_action:
            self.tray_toggle_action.setText("隐藏窗口")

    def quit_application(self) -> None:
        self.tray_icon.hide()
        QApplication.instance().quit()

    def _add_action(self, menu: QMenu, title: str, callback) -> QAction:
        action = QAction(title, self)
        action.triggered.connect(callback)
        menu.addAction(action)
        return action

    def apply_settings(self) -> None:
        font = self._reader_font()
        self.text.setFont(font)
        self._apply_document_format(font)
        background_alpha = int(self.settings.background_opacity * 255)
        self.setStyleSheet(
            f"""
            QMainWindow, QWidget#readerCentral {{
                background: transparent;
            }}
            QTextBrowser {{
                color: {self.settings.text_color};
                background: rgba(0, 0, 0, {background_alpha});
                border: none;
            }}
            QMenuBar {{
                color: {self.settings.text_color};
                background: transparent;
                border: none;
                padding: 0px 2px;
            }}
            QMenuBar::item {{
                background: transparent;
                padding: 2px 5px;
            }}
            QMenuBar::item:selected {{ background: rgba(0, 0, 0, 70); }}
            QComboBox {{
                color: {self.settings.text_color};
                background: rgba(0, 0, 0, 42);
                border: 1px solid rgba(255, 255, 255, 35);
                border-radius: 2px;
                padding: 1px 6px;
                min-height: 18px;
            }}
            QComboBox:hover {{
                background: rgba(0, 0, 0, 68);
                border-color: rgba(255, 255, 255, 80);
            }}
            QComboBox::drop-down {{ border: none; width: 18px; }}
            QComboBox QAbstractItemView {{
                color: {self.settings.text_color};
                background: rgba(22, 25, 30, 235);
                border: 1px solid rgba(255, 255, 255, 55);
            }}
            QPushButton {{
                color: {self.settings.text_color};
                background: rgba(0, 0, 0, 42);
                border: 1px solid rgba(255, 255, 255, 35);
                border-radius: 2px;
                min-width: 28px;
                padding: 1px 8px;
            }}
            QPushButton:hover {{
                background: rgba(0, 0, 0, 74);
                border-color: rgba(255, 255, 255, 90);
            }}
            QLabel {{ background: transparent; }}
            QScrollBar:vertical {{ width: 8px; background: transparent; }}
            QScrollBar::handle:vertical {{
                background: rgba(255, 255, 255, 55);
                min-height: 24px;
            }}
            """
        )
        self.progress_label.setStyleSheet(f"color: {self.settings.text_color};")
        self._apply_window_opacity()

    def _reader_font(self) -> QFont:
        font = QFont(self.settings.font_family)
        font.setPointSize(self.settings.font_size)
        return font

    def _apply_document_format(self, font: QFont) -> None:
        document = self.text.document()
        document.setDefaultFont(font)
        cursor = QTextCursor(document)
        cursor.select(QTextCursor.SelectionType.Document)

        character_format = QTextCharFormat()
        character_format.setFont(font)
        cursor.mergeCharFormat(character_format)

        block_format = QTextBlockFormat()
        block_format.setLineHeight(
            line_height_percent(self.settings.line_spacing),
            QTextBlockFormat.LineHeightTypes.ProportionalHeight.value,
        )
        cursor.mergeBlockFormat(block_format)

    def _apply_window_opacity(self) -> None:
        target = (
            self.settings.visible_opacity
            if self.preview_locked or self._mouse_inside
            else self.settings.hidden_opacity
        )
        if abs(self.windowOpacity() - target) > 0.001:
            self.setWindowOpacity(target)

    def _set_mouse_inside(self, inside: bool) -> None:
        if self._mouse_inside == inside:
            return
        self._mouse_inside = inside
        self._apply_window_opacity()

    def enterEvent(self, event) -> None:
        self.hover_leave_timer.stop()
        self._set_mouse_inside(True)
        self.progress_label.setVisible(True)
        self.update_progress_label()
        super().enterEvent(event)

    def leaveEvent(self, event) -> None:
        if self.preview_locked:
            super().leaveEvent(event)
            return
        self.hover_leave_timer.start()
        super().leaveEvent(event)

    def _confirm_mouse_left(self) -> None:
        if self.preview_locked:
            return
        if self.geometry().contains(QCursor.pos()):
            self._set_mouse_inside(True)
            return
        self.progress_label.setVisible(False)
        self._set_mouse_inside(False)

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

    def end_preview_appearance(self) -> None:
        self.preview_locked = False
        self._mouse_inside = self.geometry().contains(QCursor.pos())
        self.progress_label.setVisible(self._mouse_inside)
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
        self._apply_document_format(self._reader_font())
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

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if self.handle_chapter_key(event, mouse_over_text=self.text.viewport().underMouse()):
            return
        super().keyPressEvent(event)

    def handle_chapter_key(self, event: QKeyEvent, mouse_over_text: bool) -> bool:
        if not mouse_over_text or not self.document:
            return False

        modifiers = event.modifiers()
        blocked_modifiers = (
            Qt.KeyboardModifier.ShiftModifier
            | Qt.KeyboardModifier.ControlModifier
            | Qt.KeyboardModifier.AltModifier
            | Qt.KeyboardModifier.MetaModifier
        )
        if modifiers & blocked_modifiers:
            return False

        if event.key() == Qt.Key.Key_Left:
            direction = ChapterDirection.PREVIOUS
        elif event.key() == Qt.Key.Key_Right:
            direction = ChapterDirection.NEXT
        else:
            return False

        destination = chapter_destination(
            self.current_chapter_index,
            len(self.document.chapters),
            direction,
        )
        if destination is not None:
            self.show_chapter(destination, 0)
        event.accept()
        return True

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
        self.geometry_timer.start()
        self.update_progress_label()
        super().resizeEvent(event)

    def eventFilter(self, watched, event: QEvent) -> bool:
        if not self._is_resize_widget(watched):
            return super().eventFilter(watched, event)

        if event.type() == QEvent.Type.Enter:
            self.hover_leave_timer.stop()
            self._set_mouse_inside(True)
        elif event.type() == QEvent.Type.Leave and not self.preview_locked:
            self.hover_leave_timer.start()

        if event.type() == QEvent.Type.MouseButtonPress:
            mouse_event = event
            if isinstance(mouse_event, QMouseEvent) and mouse_event.button() == Qt.MouseButton.LeftButton:
                global_pos = mouse_event.globalPosition().toPoint()
                if self._resize_edges_at(global_pos) != ResizeEdges.NONE:
                    self._begin_window_interaction(global_pos)
                    return True
                if self._is_drag_surface(watched):
                    self._begin_window_interaction(global_pos)
                    return True

        if event.type() == QEvent.Type.MouseMove:
            mouse_event = event
            if isinstance(mouse_event, QMouseEvent):
                global_pos = mouse_event.globalPosition().toPoint()
                if self._drag_start_global is not None:
                    self._move_window(global_pos)
                    return True
                if self._resize_start_global is not None:
                    self._resize_window(global_pos)
                    return True
                self._update_resize_cursor(global_pos)

        if event.type() == QEvent.Type.MouseButtonRelease:
            mouse_event = event
            if (
                isinstance(mouse_event, QMouseEvent)
                and mouse_event.button() == Qt.MouseButton.LeftButton
                and (self._drag_start_global is not None or self._resize_start_global is not None)
            ):
                self._end_window_interaction()
                return True

        return super().eventFilter(watched, event)

    def _is_resize_widget(self, watched) -> bool:
        return watched in self._resize_widgets

    def _is_drag_surface(self, watched) -> bool:
        return watched in {self, self.centralWidget(), self.text, self.text.viewport()}

    def _begin_window_interaction(self, global_pos: QPoint) -> None:
        edges = self._resize_edges_at(global_pos)
        if edges != ResizeEdges.NONE:
            geometry = self.geometry()
            self._resize_edges = edges
            self._resize_start_global = global_pos
            self._resize_start_geometry = WindowGeometry(
                geometry.x(), geometry.y(), geometry.width(), geometry.height()
            )
            return

        self._drag_start_global = global_pos
        self._drag_start_position = self.pos()

    def _move_window(self, global_pos: QPoint) -> None:
        if self._drag_start_global is None or self._drag_start_position is None:
            return
        delta = global_pos - self._drag_start_global
        self.move(self._drag_start_position + delta)

    def _resize_window(self, global_pos: QPoint) -> None:
        if self._resize_start_global is None or self._resize_start_geometry is None:
            return
        delta = global_pos - self._resize_start_global
        resized = resize_geometry(
            self._resize_start_geometry,
            delta.x(),
            delta.y(),
            self._resize_edges,
        )
        self.setGeometry(resized.x, resized.y, resized.width, resized.height)

    def _end_window_interaction(self) -> None:
        self._drag_start_global = None
        self._drag_start_position = None
        self._resize_start_global = None
        self._resize_start_geometry = None
        self._resize_edges = ResizeEdges.NONE
        self.setCursor(Qt.CursorShape.ArrowCursor)

    def _update_resize_cursor(self, global_pos: QPoint) -> None:
        edges = self._resize_edges_at(global_pos)
        cursor_map = {
            ResizeEdges.TOP | ResizeEdges.LEFT: Qt.CursorShape.SizeFDiagCursor,
            ResizeEdges.BOTTOM | ResizeEdges.RIGHT: Qt.CursorShape.SizeFDiagCursor,
            ResizeEdges.TOP | ResizeEdges.RIGHT: Qt.CursorShape.SizeBDiagCursor,
            ResizeEdges.BOTTOM | ResizeEdges.LEFT: Qt.CursorShape.SizeBDiagCursor,
            ResizeEdges.LEFT: Qt.CursorShape.SizeHorCursor,
            ResizeEdges.RIGHT: Qt.CursorShape.SizeHorCursor,
            ResizeEdges.TOP: Qt.CursorShape.SizeVerCursor,
            ResizeEdges.BOTTOM: Qt.CursorShape.SizeVerCursor,
        }
        self.setCursor(cursor_map.get(edges, Qt.CursorShape.ArrowCursor))

    def _resize_edges_at(self, global_pos: QPoint) -> ResizeEdges:
        local_pos = self.mapFromGlobal(global_pos)
        return edge_at(local_pos.x(), local_pos.y(), self.width(), self.height())


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("MoyuReader")
    app.setWindowIcon(QIcon(str(resource_path("AppIcon.png"))))
    app.setQuitOnLastWindowClosed(True)
    window = ReaderWindow()
    if len(sys.argv) > 1:
        window.load_book(Path(sys.argv[1]))
    window.show()
    return app.exec()
