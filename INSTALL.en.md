# Installing LocalDocFlow

**Language:** [Deutsch](INSTALL.md) | English

This guide describes installation of the current development version.

> **Language note:** the English documentation does not yet imply a fully localized application. The interactive installer and application messages are currently primarily in German.

## Requirements

Recommended:

- Debian/Ubuntu-based Linux
- systemd with user services
- SANE-compatible scanner
- at least 6 GiB RAM for `qwen3:4b`
- 8 GiB RAM or more recommended
- Internet access for package and model downloads

The installer checks many of the required programs automatically.

## 1. Extract the archive

```bash
tar -xzf LocalDocFlow-0.1.3.tar.gz
cd LocalDocFlow-0.1.3
```

## 2. Start the installer

```bash
./installer/install.sh
```

The installer is interactive and asks for the most important settings.

## 3. Document root and filing directory

The installer first asks for the document root and then for the final filing directory.

For a fresh installation, a directory such as

```text
~/Documents/Dokumentenablage
```

is typically suggested.

LocalDocFlow does not create subject-specific subfolders inside it on its own.

## 4. Technical directories

The installer can create the required technical directories:

```text
Archiv/Rohscans
Scans/OCR
Dokumentenablage
```

These names currently reflect the project's existing directory conventions.

## 5. Scanner

If the scanner is powered on and reachable through SANE, the installer attempts to detect it.

Manual check:

```bash
scanimage -L
```

If no scanner is connected during installation, installation can still be completed. The scanner can be configured later by running the installer again.

## 6. Local AI / Ollama

The current default model is `qwen3:4b`.

The installer checks available RAM. A prominent warning is shown below 6 GiB. 8 GiB or more is recommended.

With very little RAM, the Linux OOM killer may terminate `llama-server` while the model is processing a document.

## 7. Installation locations

Program files:

```text
~/.local/share/localdocflow/
```

Configuration:

```text
~/.config/localdocflow/
```

Desktop launcher:

```text
~/.local/share/applications/localdocflow.desktop
```

systemd user services:

```text
localdocflow-watcher.service
localdocflow-learning-watcher.service
```

## 8. Check services

```bash
systemctl --user status \
  localdocflow-watcher.service \
  localdocflow-learning-watcher.service \
  --no-pager
```

## 9. System status

```bash
~/.local/share/localdocflow/bin/scan_status.sh
```

A scanner that is disconnected or not yet configured is reported as a warning rather than a complete installation failure.

## 10. Start the GUI

After a successful installation, LocalDocFlow should be available through the desktop launcher.

Alternatively:

```bash
~/.local/share/localdocflow/bin/scan_gui.py
```

## 11. First test scan

For the first test:

1. insert a single sheet,
2. select `Simplex – Graustufen`,
3. start the scan,
4. wait for background processing to finish,
5. check system status or logs.

The raw file should remain in the raw scan archive. The searchable PDF/A file is either filed directly into a suitable target folder or initially placed in the OCR holding area.

## 12. Test the learning system

If an unknown document is initially placed in `Scans/OCR`, move it manually into the correct subject-specific folder inside the filing directory.

Live view:

```bash
journalctl --user -u localdocflow-learning-watcher.service -f
```

A later similar document may then be handled automatically by the newly created learned rule.

## Logs

```bash
journalctl --user -u localdocflow-watcher.service
journalctl --user -u localdocflow-learning-watcher.service
```

Live:

```bash
journalctl --user -u localdocflow-watcher.service -f
```

## Known Ghostscript note

Some distributions ship Ghostscript versions for which OCRmyPDF reports a warning about possible JPEG encoding problems.

LocalDocFlow does not suppress this warning. If OCRmyPDF explicitly warns that the installed Ghostscript version may damage images, use a corrected version from the relevant distribution or upstream project when one becomes available.

## Other distributions

The installer already contains support for parts of several package-manager families. Practical testing currently focuses on Debian/Ubuntu-based systems.

Installations on other distributions should therefore initially be treated as tests.
