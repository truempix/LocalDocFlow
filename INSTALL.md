# Installation von LocalDocFlow

Diese Anleitung beschreibt die Installation des aktuellen Entwicklungsstands.

## Voraussetzungen

Empfohlen:

- Debian-/Ubuntu-basiertes Linux
- systemd mit User-Diensten
- SANE-kompatibler Scanner
- mindestens 6 GiB RAM für `qwen3:4b`
- 8 GiB RAM oder mehr empfohlen
- Internetzugang für Paket- und Modelldownloads

Der Installer prüft einen großen Teil der benötigten Programme selbst.

## 1. Archiv entpacken

```bash
tar -xzf LocalDocFlow-0.1.3.tar.gz
cd LocalDocFlow-0.1.3
```

## 2. Installer starten

```bash
./installer/install.sh
```

Der Installer arbeitet interaktiv und fragt die wichtigsten Einstellungen ab.

## 3. Dokumentwurzel und Dokumentenablage

Der Installer fragt zuerst nach der Dokumentwurzel und anschließend nach dem endgültigen Ablagebereich.

Bei einer frischen Installation wird typischerweise ein Ordner wie

```text
~/Documents/Dokumentenablage
```

vorgeschlagen.

LocalDocFlow legt darin keine fachlichen Unterordner selbstständig an.

## 4. Technische Verzeichnisse

Der Installer kann die benötigten technischen Verzeichnisse anlegen:

```text
Archiv/Rohscans
Scans/OCR
Dokumentenablage
```

## 5. Scanner

Wenn der Scanner eingeschaltet und über SANE erreichbar ist, versucht der Installer ihn zu erkennen.

Manuelle Kontrolle:

```bash
scanimage -L
```

Ist während der Installation kein Scanner angeschlossen, kann die Installation trotzdem abgeschlossen werden. Der Scanner kann später durch einen erneuten Installerlauf konfiguriert werden.

## 6. Lokale KI / Ollama

Standardmäßig ist derzeit `qwen3:4b` vorgesehen.

Der Installer prüft den verfügbaren Arbeitsspeicher. Bei weniger als 6 GiB RAM erscheint eine deutliche Warnung. 8 GiB RAM oder mehr werden empfohlen.

Bei sehr wenig RAM kann der Linux-OOM-Killer den `llama-server` während der Modellverarbeitung beenden.

## 7. Installationsorte

Programmdateien:

```text
~/.local/share/localdocflow/
```

Konfiguration:

```text
~/.config/localdocflow/
```

Desktop-Starter:

```text
~/.local/share/applications/localdocflow.desktop
```

systemd-Userdienste:

```text
localdocflow-watcher.service
localdocflow-learning-watcher.service
```

## 8. Dienste prüfen

```bash
systemctl --user status   localdocflow-watcher.service   localdocflow-learning-watcher.service   --no-pager
```

## 9. Systemstatus

```bash
~/.local/share/localdocflow/bin/scan_status.sh
```

Ein nicht angeschlossener oder noch nicht konfigurierter Scanner wird als Warnung und nicht als vollständiger Installationsfehler behandelt.

## 10. GUI starten

Nach erfolgreicher Installation sollte LocalDocFlow über den Desktop-Starter startbar sein.

Alternativ:

```bash
~/.local/share/localdocflow/bin/scan_gui.py
```

## 11. Erster Testscan

Für den ersten Test empfiehlt sich:

1. ein einzelnes Blatt einlegen,
2. `Simplex – Graustufen` auswählen,
3. Scan starten,
4. Hintergrundverarbeitung abwarten,
5. Systemstatus oder Protokoll kontrollieren.

Die Rohdatei sollte im Rohscan-Archiv erhalten bleiben. Die durchsuchbare PDF/A-Datei landet entweder direkt in einem passenden Zielordner oder zunächst in der OCR-Zwischenablage.

## 12. Lernsystem testen

Liegt ein unbekanntes Dokument zunächst in `Scans/OCR`, kann es manuell in den fachlich richtigen Ordner innerhalb der Dokumentenablage verschoben werden.

Live-Anzeige:

```bash
journalctl --user -u localdocflow-learning-watcher.service -f
```

Bei einem späteren ähnlichen Dokument kann die erzeugte Lernregel automatisch greifen.

## Protokolle

```bash
journalctl --user -u localdocflow-watcher.service
journalctl --user -u localdocflow-learning-watcher.service
```

Live:

```bash
journalctl --user -u localdocflow-watcher.service -f
```

## Bekannter Hinweis zu Ghostscript

Einige Distributionen liefern Ghostscript-Versionen aus, bei denen OCRmyPDF eine Warnung zu möglichen JPEG-Encoding-Problemen ausgibt.

LocalDocFlow unterdrückt diese Warnung nicht. Wenn OCRmyPDF für die installierte Ghostscript-Version ausdrücklich vor möglicher Bildbeschädigung warnt, sollte eine korrigierte Version des jeweiligen Distributors bzw. Projekts verwendet werden, sobald sie verfügbar ist.

## Andere Distributionen

Der Installer enthält bereits Teile für verschiedene Paketmanager. Der Schwerpunkt der praktischen Tests liegt aktuell jedoch auf Debian-/Ubuntu-basierten Systemen.

Installationen auf anderen Distributionen sollten deshalb zunächst als Test betrachtet werden.
