#!/usr/bin/env python3

"""
LocalDocFlow - grafische Benutzeroberfläche

Die GUI steuert ausschließlich den Scanvorgang.

Nach erfolgreichem Scan übernimmt der bereits laufende
localdocflow-watcher.service automatisch:

    OCR / PDF-A
    Datumserkennung
    KI-Analyse
    Dateibenennung
    Learning / Mapping
    Ablage

Dadurch bleibt die GUI schlank und kann direkt für das nächste
Dokument verwendet werden.
"""

import os
import signal
import sys
from pathlib import Path

from PyQt6.QtCore import (
    QProcess,
    QProcessEnvironment,
    QSettings,
    QTimer,
)
from PyQt6.QtGui import QCloseEvent, QIcon, QTextCursor
from PyQt6.QtWidgets import (
    QApplication,
    QButtonGroup,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QRadioButton,
    QVBoxLayout,
    QWidget,
)


# ============================================================
# Konfiguration
# Configuration
# ============================================================

HOME = Path.home()

# Verzeichnis, in dem scan_gui.py selbst liegt.
# Dadurch funktionieren die Hilfsskripte unabhängig davon,
# ob die Anwendung aus dem Entwicklungsordner oder aus
# ~/.local/share/localdocflow/bin gestartet wird.
SCRIPT_DIR = Path(__file__).resolve().parent

CAPTURE_SCRIPT = SCRIPT_DIR / "scan_capture.sh"
STATUS_SCRIPT = SCRIPT_DIR / "scan_status.sh"
LOG_SCRIPT = SCRIPT_DIR / "scan_logs.sh"

SETSID = Path("/usr/bin/setsid")


# Profilnummern entsprechen scan_capture.sh:
#
#   1 = Simplex Color
#   2 = Simplex Gray
#   3 = Duplex Color
#   4 = Duplex Gray

PROFILES = [
    (1, "Simplex – Farbe", "Einseitig in Farbe"),
    (2, "Simplex – Graustufen", "Einseitig in Graustufen"),
    (3, "Duplex – Farbe", "Vorder- und Rückseite in Farbe"),
    (4, "Duplex – Graustufen", "Vorder- und Rückseite in Graustufen"),
]


# ============================================================
# Hauptfenster
# Main window
# ============================================================

class ScanWindow(QMainWindow):

    def __init__(self):
        super().__init__()

        self.process = None
        self.status_process = None
        self.status_dialog = None
        self.status_output = None
        self.system_status_label = None
        self.log_process = None
        self.log_dialog = None
        self.log_output = None

        self.prompt_buffer = ""
        self.dialog_active = False

        self.user_cancelled = False
        self.close_when_finished = False

        self.settings = QSettings(
            "localdocflow",
            "scan-gui"
        )

        self.build_ui()
        self.restore_settings()


    # ========================================================
    # Oberfläche
    # User interface
    # ========================================================

    def build_ui(self):

        self.setWindowTitle("Dokument scannen")

        icon = QIcon.fromTheme("scanner")

        if not icon.isNull():
            self.setWindowIcon(icon)

        self.resize(580, 500)


        central = QWidget()
        self.setCentralWidget(central)

        layout = QVBoxLayout(central)

        layout.setContentsMargins(
            24,
            20,
            24,
            20
        )

        layout.setSpacing(14)


        # ----------------------------------------------------
        # Überschrift
        # Heading
        # ----------------------------------------------------

        title = QLabel("Dokument scannen")

        font = title.font()
        font.setPointSize(
            font.pointSize() + 5
        )
        font.setBold(True)

        title.setFont(font)

        layout.addWidget(title)


        description = QLabel(
            "Scanprofil auswählen und Dokument scannen. "
            "Die weitere Verarbeitung erfolgt anschließend "
            "automatisch im Hintergrund."
        )

        description.setWordWrap(True)

        layout.addWidget(description)


        # ----------------------------------------------------
        # Trennlinie
        # ----------------------------------------------------

        line = QFrame()

        line.setFrameShape(
            QFrame.Shape.HLine
        )

        line.setFrameShadow(
            QFrame.Shadow.Sunken
        )

        layout.addWidget(line)


        # ----------------------------------------------------
        # Scanprofil
        # Scan profile
        # ----------------------------------------------------

        profile_title = QLabel("Scanprofil")

        font = profile_title.font()
        font.setBold(True)

        profile_title.setFont(font)

        layout.addWidget(profile_title)


        self.profile_group = QButtonGroup(self)
        self.profile_buttons = {}


        for profile_id, name, tooltip in PROFILES:

            radio = QRadioButton(name)

            radio.setToolTip(tooltip)

            self.profile_group.addButton(
                radio,
                profile_id
            )

            self.profile_buttons[
                profile_id
            ] = radio

            layout.addWidget(radio)


        # ----------------------------------------------------
        # Status
        # ----------------------------------------------------

        layout.addSpacing(8)


        status_title = QLabel("Status")

        font = status_title.font()
        font.setBold(True)

        status_title.setFont(font)

        layout.addWidget(status_title)


        self.status_label = QLabel(
            "Bereit zum Scannen."
        )

        self.status_label.setWordWrap(True)

        layout.addWidget(
            self.status_label
        )


        # ----------------------------------------------------
        # Buttons
        # ----------------------------------------------------

        layout.addSpacing(8)

        buttons = QHBoxLayout()


        self.scan_button = QPushButton(
            "Scan starten"
        )

        icon = QIcon.fromTheme(
            "document-scan"
        )

        if icon.isNull():
            icon = QIcon.fromTheme("scanner")

        if not icon.isNull():
            self.scan_button.setIcon(icon)

        self.scan_button.clicked.connect(
            self.start_scan
        )


        self.cancel_button = QPushButton(
            "Scan abbrechen"
        )

        self.cancel_button.setEnabled(False)

        cancel_icon = QIcon.fromTheme(
            "process-stop"
        )

        if not cancel_icon.isNull():
            self.cancel_button.setIcon(
                cancel_icon
            )

        self.cancel_button.clicked.connect(
            self.cancel_scan
        )
        self.status_button = QPushButton(
            "Systemstatus"
        )

        status_icon = QIcon.fromTheme(
            "utilities-system-monitor"
        )

        if not status_icon.isNull():
            self.status_button.setIcon(
                status_icon
            )

        self.status_button.clicked.connect(
            self.show_system_status
        )
        self.log_button = QPushButton(
            "Protokoll"
        )

        log_icon = QIcon.fromTheme(
            "view-list-text"
        )

        if not log_icon.isNull():
            self.log_button.setIcon(
                log_icon
            )

        self.log_button.clicked.connect(
            self.show_logs
        )

        self.details_button = QPushButton(
            "Details anzeigen"
        )

        self.details_button.setCheckable(True)

        self.details_button.toggled.connect(
            self.toggle_details
        )


        buttons.addWidget(
            self.scan_button
        )

        buttons.addWidget(
            self.cancel_button
        )

        buttons.addStretch()

        buttons.addWidget(
            self.status_button
        )
        buttons.addWidget(
        self.log_button
        )

        buttons.addWidget(
            self.details_button
        )

        layout.addLayout(
            buttons
        )


        # ----------------------------------------------------
        # Technische Ausgabe
        # Technical output
        # ----------------------------------------------------

        self.details = QPlainTextEdit()

        self.details.setReadOnly(True)

        self.details.setPlaceholderText(
            "Technische Scan-Ausgabe"
        )

        self.details.setVisible(False)

        layout.addWidget(
            self.details,
            1
        )


    # ========================================================
    # Einstellungen wiederherstellen
    # Restore settings
    # ========================================================

    def restore_settings(self):

        profile_id = self.settings.value(
            "last_profile",
            4,
            type=int
        )

        if profile_id not in self.profile_buttons:
            profile_id = 4

        self.profile_buttons[
            profile_id
        ].setChecked(True)


    # ========================================================
    # Profilwahl sperren/freigeben
    # Lock/unlock profile selection
    # ========================================================

    def set_profile_controls_enabled(
        self,
        enabled
    ):

        for button in self.profile_buttons.values():
            button.setEnabled(enabled)


    # ========================================================
    # Scan starten
    # Start scan
    # ========================================================

    def start_scan(self):

        if self.process is not None:
            return


        if not CAPTURE_SCRIPT.is_file():

            QMessageBox.critical(
                self,
                "LocalDocFlow",
                "Das Scan-Skript wurde nicht gefunden:\n\n"
                f"{CAPTURE_SCRIPT}"
            )

            return


        if not SETSID.is_file():

            QMessageBox.critical(
                self,
                "LocalDocFlow",
                "/usr/bin/setsid wurde nicht gefunden."
            )

            return


        profile_id = (
            self.profile_group.checkedId()
        )


        if profile_id < 1:

            QMessageBox.warning(
                self,
                "LocalDocFlow",
                "Bitte ein Scanprofil auswählen."
            )

            return


        self.settings.setValue(
            "last_profile",
            profile_id
        )


        self.details.clear()

        self.prompt_buffer = ""
        self.dialog_active = False

        self.user_cancelled = False
        self.close_when_finished = False


        self.status_label.setText(
            "Scanner wird gestartet …"
        )


        self.scan_button.setEnabled(False)
        self.cancel_button.setEnabled(True)

        self.set_profile_controls_enabled(
            False
        )


        # ----------------------------------------------------
        # setsid startet scan_capture.sh in einer eigenen
        # Prozessgruppe.
        #
        # Dadurch kann die GUI bei "Scan abbrechen" sowohl das
        # Bash-Skript als auch ein gerade laufendes scanimage
        # sauber per Signal beenden.
        # ----------------------------------------------------

        self.process = QProcess(self)

        self.process.setProgram(
            str(SETSID)
        )

        self.process.setArguments([
            str(CAPTURE_SCRIPT),
            str(profile_id)
        ])


        self.process.setProcessChannelMode(
            QProcess.ProcessChannelMode.MergedChannels
        )
        # --------------------------------------------------------
        # Capture-Skript in den GUI-Modus versetzen.
        #
        # Dadurch verwendet scan_capture.sh eindeutige Signale
        # statt unsichtbarer Terminal-Prompts.
        # --------------------------------------------------------

        environment = QProcessEnvironment.systemEnvironment()

        environment.insert(
            "SCAN_GUI_MODE",
            "1"
        )

        self.process.setProcessEnvironment(
            environment
        )


        self.process.readyReadStandardOutput.connect(
            self.read_process_output
        )

        self.process.finished.connect(
            self.scan_finished
        )

        self.process.errorOccurred.connect(
            self.process_error
        )


        self.process.start()


        if not self.process.waitForStarted(3000):

            QMessageBox.critical(
                self,
                "LocalDocFlow",
                "Der Scanprozess konnte nicht gestartet werden."
            )

            self.cleanup_process()
            return


        self.status_label.setText(
            "Dokument wird gescannt …"
        )


    # ========================================================
    # Prozessausgabe
    # Process output
    # ========================================================

    def read_process_output(self):

        if self.process is None:
            return


        raw = (
            self.process
            .readAllStandardOutput()
        )

        text = bytes(raw).decode(
            "utf-8",
            errors="replace"
        )


        if not text:
            return


        self.details.moveCursor(
            QTextCursor.MoveOperation.End
        )

        self.details.insertPlainText(text)

        self.details.ensureCursorVisible()


        self.prompt_buffer += text


        if len(self.prompt_buffer) > 6000:
            self.prompt_buffer = (
                self.prompt_buffer[-6000:]
            )


        self.check_for_prompt()


    # ========================================================
    # Bash-Eingabeaufforderungen erkennen
    # Detect Bash prompts
    # ========================================================

        # ========================================================
    # Signale von scan_capture.sh erkennen
    # Detect signals from scan_capture.sh
    # ========================================================

    def check_for_prompt(self):

        if self.dialog_active:
            return

        text = self.prompt_buffer.lower()


        # ----------------------------------------------------
        # Scannerfehler:
        # Wiederholen oder Abbrechen
        # ----------------------------------------------------

        if "__scan_prompt_retry__" in text:

            self.prompt_buffer = ""
            self.dialog_active = True

            QTimer.singleShot(
                0,
                self.ask_retry
            )

            return


        # ----------------------------------------------------
        # Weitere Seiten zu diesem Dokument?
        # ----------------------------------------------------

        if "__scan_prompt_more__" in text:

            self.prompt_buffer = ""
            self.dialog_active = True

            QTimer.singleShot(
                0,
                self.ask_for_more_pages
            )

            return


        # ----------------------------------------------------
        # Weitere Seiten wurden gewählt:
        # Papier einlegen und nächsten Scan starten
        # ----------------------------------------------------

        if "__scan_prompt_continue__" in text:

            self.prompt_buffer = ""
            self.dialog_active = True

            QTimer.singleShot(
                0,
                self.ask_to_load_more_pages
            )

            return


    # ========================================================
    # Scannerfehler
    # Scanner error
    # ========================================================

    def ask_retry(self):

        if self.process is None:
            self.dialog_active = False
            return


        answer = QMessageBox.question(
            self,
            "Scannerfehler",
            "Der Scan konnte nicht durchgeführt werden.\n\n"
            "Bitte Scanner und Papierzufuhr prüfen.\n\n"
            "Soll der Scan erneut versucht werden?",
            QMessageBox.StandardButton.Retry
            | QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Retry
        )


        if answer == QMessageBox.StandardButton.Retry:

            self.process.write(
                b"w\n"
            )

            self.status_label.setText(
                "Scan wird erneut versucht …"
            )

        else:

            self.user_cancelled = True

            self.process.write(
                b"a\n"
            )

            self.status_label.setText(
                "Scan wird abgebrochen …"
            )


        self.dialog_active = False


    # ========================================================
    # Weitere Seiten?
    # Additional pages?
    # ========================================================

    def ask_for_more_pages(self):

        if self.process is None:
            self.dialog_active = False
            return


        answer = QMessageBox.question(
            self,
            "Weitere Seiten",
            "Gehören noch weitere Seiten zu diesem Dokument?",
            QMessageBox.StandardButton.Yes
            | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )


        if answer == QMessageBox.StandardButton.Yes:

            self.process.write(
                b"j\n"
            )

            self.status_label.setText(
                "Weitere Seiten vorbereiten …"
            )

        else:

            self.process.write(
                b"n\n"
            )

            self.status_label.setText(
                "Scan wird abgeschlossen …"
            )


        self.dialog_active = False


    # ========================================================
    # Weitere Seiten einlegen
    # Insert additional pages
    # ========================================================

    def ask_to_load_more_pages(self):

        if self.process is None:
            self.dialog_active = False
            return


        QMessageBox.information(
            self,
            "Weitere Seiten",
            "Weitere Seiten jetzt in den Dokumenteneinzug legen.\n\n"
            "Mit OK startet die nächste Scanrunde."
        )


        self.process.write(
            b"\n"
        )


        self.status_label.setText(
            "Weitere Seiten werden gescannt …"
        )

        self.dialog_active = False


    # ========================================================
    # Scan jederzeit abbrechen
    # Cancel scan at any time
    # ========================================================

    def cancel_scan(
        self,
        confirmed=False
    ):

        if self.process is None:
            return


        if not confirmed:

            answer = QMessageBox.question(
                self,
                "Scan abbrechen",
                "Soll der aktuelle Scanvorgang wirklich "
                "abgebrochen werden?",
                QMessageBox.StandardButton.Yes
                | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No
            )

            if answer != QMessageBox.StandardButton.Yes:
                return


        self.user_cancelled = True

        self.status_label.setText(
            "Scan wird abgebrochen …"
        )

        self.cancel_button.setEnabled(False)


        # ----------------------------------------------------
        # SIGINT an die komplette Prozessgruppe schicken.
        #
        # Das entspricht ungefähr Ctrl+C im Terminal.
        # scan_capture.sh besitzt dafür bereits unseren
        # handle_abort()-Trap.
        # ----------------------------------------------------

        pid = int(
            self.process.processId()
        )


        if pid > 0:

            try:

                os.killpg(
                    pid,
                    signal.SIGINT
                )

            except ProcessLookupError:
                pass

            except PermissionError:

                self.process.terminate()


        # Falls irgendein Treiber/Prozess nicht reagiert,
        # nach drei Sekunden hart beenden.

        QTimer.singleShot(
            3000,
            self.force_kill_if_needed
        )


    # ========================================================
    # Notfall-Abbruch
    # Emergency termination
    # ========================================================

    def force_kill_if_needed(self):

        if self.process is None:
            return


        if (
            self.process.state()
            == QProcess.ProcessState.NotRunning
        ):
            return


        pid = int(
            self.process.processId()
        )


        if pid > 0:

            try:

                os.killpg(
                    pid,
                    signal.SIGKILL
                )

            except ProcessLookupError:
                pass

            except PermissionError:
                self.process.kill()


    # ========================================================
    # Scan beendet
    # Scan finished
    # ========================================================

    def scan_finished(
        self,
        exit_code,
        exit_status
    ):

        if (
            exit_code == 0
            and not self.user_cancelled
        ):

            self.status_label.setText(
                "Scan abgeschlossen – "
                "Verarbeitung läuft im Hintergrund."
            )


        elif (
            exit_code == 130
            or self.user_cancelled
        ):

            self.status_label.setText(
                "Scan abgebrochen."
            )


        else:

            self.status_label.setText(
                "Scan konnte nicht erfolgreich abgeschlossen werden."
            )

            self.details.setVisible(True)
            self.details_button.setChecked(True)

            QMessageBox.warning(
                self,
                "LocalDocFlow",
                "Der Scan wurde mit einem Fehler beendet.\n\n"
                "Die technische Ausgabe wurde eingeblendet."
            )


        close_afterwards = (
            self.close_when_finished
        )

        self.cleanup_process()


        if close_afterwards:

            QTimer.singleShot(
                0,
                self.close
            )


    # ========================================================
    # QProcess-Fehler
    # QProcess error
    # ========================================================

    def process_error(self, error):

        if not self.user_cancelled:

            self.status_label.setText(
                "Fehler beim Starten oder Ausführen des Scanprozesses."
            )


    # ========================================================
    # Prozess aufräumen
    # Clean up process
    # ========================================================

    def cleanup_process(self):

        if self.process is not None:

            self.process.deleteLater()
            self.process = None


        self.scan_button.setEnabled(True)
        self.cancel_button.setEnabled(False)

        self.set_profile_controls_enabled(
            True
        )

    # ========================================================
    # Systemstatus anzeigen
    # Show system status
    # ========================================================

    def show_system_status(self):

        if self.status_process is not None:

            if self.status_dialog is not None:
                self.status_dialog.show()
                self.status_dialog.raise_()
                self.status_dialog.activateWindow()

            return


        if not STATUS_SCRIPT.is_file():

            QMessageBox.critical(
                self,
                "LocalDocFlow",
                "Das Status-Skript wurde nicht gefunden:\n\n"
                f"{STATUS_SCRIPT}"
            )

            return


        # ----------------------------------------------------
        # Eigenes Fenster für die Diagnoseausgabe
        # ----------------------------------------------------

        self.status_dialog = QDialog(self)

        self.status_dialog.setWindowTitle(
            "LocalDocFlow – Systemstatus"
        )

        self.status_dialog.resize(
            760,
            620
        )


        layout = QVBoxLayout(
            self.status_dialog
        )


        self.system_status_label = QLabel(
            "Systemprüfung läuft …"
        )

        layout.addWidget(
            self.system_status_label
        )


        self.status_output = QPlainTextEdit()

        self.status_output.setReadOnly(True)

        self.status_output.setPlainText(
            "Prüfung wird gestartet …\n"
        )

        layout.addWidget(
            self.status_output,
            1
        )


        close_button = QPushButton(
            "Schließen"
        )

        close_button.clicked.connect(
            self.status_dialog.close
        )

        layout.addWidget(
            close_button
        )


        # ----------------------------------------------------
        # scan_status.sh im Hintergrund starten
        #
        # Dadurch friert die eigentliche Scan-GUI während
        # der Systemprüfung nicht ein.
        # ----------------------------------------------------

        self.status_process = QProcess(self)

        self.status_process.setProgram(
            str(STATUS_SCRIPT)
        )

        self.status_process.setProcessChannelMode(
            QProcess.ProcessChannelMode.MergedChannels
        )

        self.status_process.readyReadStandardOutput.connect(
            self.read_system_status_output
        )

        self.status_process.finished.connect(
            self.system_status_finished
        )


        self.status_button.setEnabled(False)

        self.status_dialog.show()

        self.status_process.start()


    # ========================================================
    # Ausgabe des Statusskripts lesen
    # Read status script output
    # ========================================================

    def read_system_status_output(self):

        if self.status_process is None:
            return


        raw = (
            self.status_process
            .readAllStandardOutput()
        )

        text = bytes(raw).decode(
            "utf-8",
            errors="replace"
        )


        if not text:
            return


        if self.status_output is not None:

            # Den anfänglichen Hinweis beim ersten echten
            # Ausgabeblock entfernen.

            current = self.status_output.toPlainText()

            if current == "Prüfung wird gestartet …\n":
                self.status_output.clear()


            self.status_output.moveCursor(
                QTextCursor.MoveOperation.End
            )

            self.status_output.insertPlainText(
                text
            )

            self.status_output.ensureCursorVisible()


    # ========================================================
    # Systemprüfung abgeschlossen
    # System check completed
    # ========================================================

    def system_status_finished(
        self,
        exit_code,
        exit_status
    ):

        # eventuell noch gepufferte Ausgabe übernehmen

        self.read_system_status_output()


        if self.system_status_label is not None:

            if exit_code == 0:

                self.system_status_label.setText(
                    "Systemprüfung abgeschlossen."
                )

            else:

                self.system_status_label.setText(
                    "Systemprüfung abgeschlossen – "
                    "mindestens ein Fehler wurde erkannt."
                )


        if self.status_process is not None:

            self.status_process.deleteLater()
            self.status_process = None


        self.status_button.setEnabled(True)

        # ========================================================
    # Protokoll anzeigen
    # Show log
    # ========================================================

    def show_logs(self):

        if self.log_process is not None:

            if self.log_dialog is not None:
                self.log_dialog.show()
                self.log_dialog.raise_()
                self.log_dialog.activateWindow()

            return


        if not LOG_SCRIPT.is_file():

            QMessageBox.critical(
                self,
                "LocalDocFlow",
                "Das Protokoll-Skript wurde nicht gefunden:\n\n"
                f"{LOG_SCRIPT}"
            )

            return


        self.log_dialog = QDialog(self)

        self.log_dialog.setWindowTitle(
            "LocalDocFlow – Protokoll"
        )

        self.log_dialog.resize(
            900,
            700
        )


        layout = QVBoxLayout(
            self.log_dialog
        )


        info = QLabel(
            "Letzte Meldungen der Scan- und Lernverarbeitung"
        )

        layout.addWidget(info)


        self.log_output = QPlainTextEdit()

        self.log_output.setReadOnly(True)

        self.log_output.setPlainText(
            "Protokoll wird geladen …\n"
        )

        layout.addWidget(
            self.log_output,
            1
        )


        close_button = QPushButton(
            "Schließen"
        )

        close_button.clicked.connect(
            self.log_dialog.close
        )

        layout.addWidget(
            close_button
        )


        # ----------------------------------------------------
        # Logskript im Hintergrund starten
        # ----------------------------------------------------

        self.log_process = QProcess(self)

        self.log_process.setProgram(
            str(LOG_SCRIPT)
        )

        self.log_process.setProcessChannelMode(
            QProcess.ProcessChannelMode.MergedChannels
        )

        self.log_process.readyReadStandardOutput.connect(
            self.read_log_output
        )

        self.log_process.finished.connect(
            self.logs_finished
        )


        self.log_button.setEnabled(False)

        self.log_dialog.show()

        self.log_process.start()


    # ========================================================
    # Protokollausgabe lesen
    # Read log output
    # ========================================================

    def read_log_output(self):

        if self.log_process is None:
            return


        raw = (
            self.log_process
            .readAllStandardOutput()
        )

        text = bytes(raw).decode(
            "utf-8",
            errors="replace"
        )


        if not text:
            return


        if self.log_output is not None:

            current = self.log_output.toPlainText()

            if current == "Protokoll wird geladen …\n":
                self.log_output.clear()


            self.log_output.moveCursor(
                QTextCursor.MoveOperation.End
            )

            self.log_output.insertPlainText(
                text
            )

            self.log_output.ensureCursorVisible()


    # ========================================================
    # Protokoll fertig geladen
    # Log loading completed
    # ========================================================

    def logs_finished(
        self,
        exit_code,
        exit_status
    ):

        self.read_log_output()


        if self.log_process is not None:

            self.log_process.deleteLater()
            self.log_process = None


        self.log_button.setEnabled(True)

    # ========================================================
    # Details ein-/ausblenden
    # Show/hide details
    # ========================================================

    def toggle_details(
        self,
        visible
    ):

        self.details.setVisible(
            visible
        )


        if visible:

            self.details_button.setText(
                "Details ausblenden"
            )

            self.resize(
                max(self.width(), 580),
                max(self.height(), 650)
            )

        else:

            self.details_button.setText(
                "Details anzeigen"
            )


    # ========================================================
    # Fenster schließen
    # Close window
    # ========================================================

    def closeEvent(
        self,
        event: QCloseEvent
    ):

        if self.process is None:

            event.accept()
            return


        answer = QMessageBox.question(
            self,
            "Scan läuft",
            "Es läuft noch ein Scanvorgang.\n\n"
            "Scan abbrechen und Fenster schließen?",
            QMessageBox.StandardButton.Yes
            | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )


        if answer == QMessageBox.StandardButton.Yes:

            self.close_when_finished = True

            self.cancel_scan(
                confirmed=True
            )

            event.ignore()

        else:

            event.ignore()


# ============================================================
# Programmstart
# Program start
# ============================================================

def main():

    app = QApplication(sys.argv)

    app.setApplicationName(
        "LocalDocFlow"
    )

    window = ScanWindow()

    window.show()

    sys.exit(
        app.exec()
    )


if __name__ == "__main__":
    main()
