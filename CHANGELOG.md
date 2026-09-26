# Changelog

Alle wichtigen Änderungen an LocalDocFlow werden in dieser Datei dokumentiert.

## [0.1.3] - unveröffentlicht

### Geändert

- Projektname auf `LocalDocFlow` umgestellt.
- technische Kennung auf `localdocflow` umgestellt.
- Installationspfade für neue Installationen auf `~/.local/share/localdocflow/` und `~/.config/localdocflow/` umgestellt.
- systemd-Userdienste auf `localdocflow-watcher.service` und `localdocflow-learning-watcher.service` umbenannt.
- Desktop-Starter auf `localdocflow.desktop` umgestellt.
- RAM-Prüfung für das lokale Ollama-Modell ergänzt.
- Warnung bei weniger als 6 GiB RAM für `qwen3:4b`.
- 8 GiB RAM oder mehr werden für `qwen3:4b` empfohlen.
- Default-Konfigurationen für Veröffentlichung neutralisiert.
- persönliche Ablagestrukturen aus dem Installer entfernt.
- endgültige Dokumentenablage über `CABINET_DIR` frei konfigurierbar.

### Behoben

- GUI sucht Hilfsskripte relativ zu ihrem eigenen Installationsverzeichnis.
- Systemstatus und Protokoll funktionieren auch nach Installation unter `~/.local/share/...`.
- bestehende Scannerkonfiguration wird nicht mehr versehentlich geleert, wenn der Scanner während eines erneuten Installerlaufs ausgeschaltet ist.
- Scannerstatus behandelt einen nicht angeschlossenen Scanner als Warnung.
- doppelte Abschlussmeldung des Installers entfernt.
- feste Entwicklungs- und Benutzerpfade aus dem portablen Quellstand entfernt.

### Getestet

- Clean-Install unter Ubuntu 26.04.
- Installation unter Linux Lite auf Ubuntu-Basis.
- systemd-Userdienste.
- Scannererkennung mit SANE.
- realer Scan.
- OCR und PDF/A-Erzeugung.
- lokale Analyse mit `qwen3:4b`.
- Fallback in OCR-Zwischenablage.
- manuelle Ablagekorrektur.
- Erzeugung einer Lernregel.
- automatische Ablage eines späteren ähnlichen Dokuments über die Lernregel.

## [0.1.2] - Entwicklungsstand

- portable GUI-Pfade korrigiert.
- Installer-Ausgabe bereinigt.
- erfolgreicher Clean-Install-Test auf Ubuntu.

## [0.1.1] - Entwicklungsstand

- Installer und Pfade weiter portabilisiert.
- frei wählbare Dokumentenablage vorbereitet.
- Default-Lernkonfiguration neutralisiert.
- persönliche Pfade aus dem Paket entfernt.

## [0.1.0] - früher Teststand

- erster portabler Installer-Test in einer Linux-Lite-VM.
