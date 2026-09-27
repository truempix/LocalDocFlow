# LocalDocFlow

LocalDocFlow ist eine lokale Linux-Anwendung zur automatisierten Digitalisierung, Texterkennung, Analyse und Ablage von Papierdokumenten.

Das Projekt verbindet einen SANE-kompatiblen Dokumentenscanner mit OCRmyPDF, Tesseract und einer lokal betriebenen KI über Ollama. Ziel ist ein möglichst einfacher Ablauf:

1. Dokument in den Scanner einlegen.
2. Scanprofil auswählen.
3. Scan starten.
4. Die weitere Verarbeitung im Hintergrund erledigen lassen.

Die Rohscans bleiben dauerhaft erhalten. Zusätzlich erzeugt LocalDocFlow eine durchsuchbare PDF/A-Datei, analysiert den Dokumentinhalt und kann Dokumente anhand vorhandener Regeln automatisch in eine bestehende Ordnerstruktur ablegen.

## Hauptfunktionen

- Scannen über SANE
- Simplex- und Duplex-Profile
- Farb- und Graustufenprofile
- dauerhafte Archivierung der Rohscans
- OCR mit OCRmyPDF und Tesseract
- Ausgabe als PDF/A
- Erkennung des Dokumentdatums
- lokale Dokumentanalyse mit Ollama
- Erkennung bzw. Ableitung von Titel/Betreff, Dokumenttyp, Kategorie und Unterkategorie
- Erkennung ausdrücklich im Dokument enthaltener Versicherungsnummern
- aussagekräftige Dateinamen, bei Versicherungen optional mit erkannter Versicherungsnummer
- regelbasierte automatische Ablage
- sichere OCR-Zwischenablage, wenn noch keine passende Regel existiert
- lernfähige Ablageregeln
- Erkennung manueller Ablagekorrekturen
- grafische Oberfläche mit PyQt6
- Hintergrundverarbeitung über systemd-Userdienste
- Systemstatus und Protokollanzeige
- Installer für Abhängigkeiten, Konfiguration und Dienste

## Lokale Verarbeitung

Die Dokumentanalyse läuft lokal auf dem eigenen Rechner. Für die KI-Auswertung wird Ollama verwendet. Standardmäßig ist derzeit `qwen3:4b` vorgesehen.

Dokumentinhalte müssen für die Analyse nicht an einen externen Cloud-KI-Dienst übertragen werden. Für die Erstinstallation, Paketdownloads und den Download des Ollama-Modells wird jedoch eine Internetverbindung benötigt.

## Lernsystem

Kann ein Dokument noch nicht sicher automatisch abgelegt werden, verbleibt es zunächst in der OCR-Zwischenablage.

Wird dieses Dokument anschließend manuell in den gewünschten fachlichen Ordner verschoben, erkennt der Learning-Watcher diese Korrektur. Daraus kann eine Ablageregel entstehen, die bei späteren ähnlichen Dokumenten automatisch angewendet wird.

Bei Versicherungsdokumenten kann eine erkannte Versicherungsnummer zusätzlich als Vertragsmerkmal verwendet werden. Gelernte Versicherungsregeln werden nur automatisch angewendet, wenn die normalisierten Versicherungsnummern übereinstimmen. Ältere Versicherungsregeln ohne gespeicherte Nummer werden dadurch nicht für eine automatische Vertragszuordnung verwendet.

LocalDocFlow erstellt keine fachliche Ordnerstruktur eigenmächtig. Die gewünschten Zielordner werden vom Benutzer vorgegeben.

## Verzeichnisprinzip

Bei der Installation werden nur die für LocalDocFlow notwendigen Bereiche eingerichtet:

- Rohscan-Archiv
- OCR-Zwischenablage
- vom Benutzer gewählte Dokumentenablage

Die fachliche Unterstruktur innerhalb der Dokumentenablage bleibt vollständig unter Kontrolle des Benutzers.

## Hardware

Benötigt werden:

- Linux-PC
- SANE-kompatibler Scanner
- ausreichend freier Speicherplatz
- ausreichend Arbeitsspeicher für das gewählte Ollama-Modell

Für `qwen3:4b` warnt der Installer bei weniger als 6 GiB RAM. Für einen zuverlässigen Betrieb werden 8 GiB RAM oder mehr empfohlen.

## Getesteter Stand

Der bisherige Entwicklungsstand wurde unter anderem auf folgenden Systemen getestet:

- Ubuntu 26.04
- Kubuntu 26.04
- Linux Lite auf Ubuntu-Basis

Ubuntu/Kubuntu bzw. andere Debian-/Ubuntu-basierte Systeme sind derzeit der Schwerpunkt der Tests. Unterstützung für andere Distributionen sollte vor einer produktiven Nutzung separat geprüft werden.

## Beispielhafter Ablauf

```text
Scanner
   ↓
Rohscan-Archiv
   ↓
OCR / PDF-A
   ↓
lokale KI-Analyse
   ↓
Dateiname + Klassifikation
   ↓
Mapping- oder Lernregel vorhanden?
   ├─ ja  → automatische Ablage
   └─ nein → OCR-Zwischenablage
                ↓
          manuelle Korrektur
                ↓
             Lernregel
```

## Datenschutz

LocalDocFlow ist für lokale Verarbeitung ausgelegt. Vor einer Veröffentlichung oder Weitergabe eigener Konfigurationsdateien sollte trotzdem geprüft werden, dass keine persönlichen Pfade, Absenderregeln, Lernregeln, Dokumentnamen, Scanner-Seriennummern oder andere private Daten enthalten sind.

Die im Projekt mitgelieferten Default-Konfigurationen sind dafür bewusst neutral gehalten.

## Projektstatus

LocalDocFlow befindet sich noch in Entwicklung. Der grundlegende Ablauf

`Scan → OCR/PDF-A → KI-Analyse → Klassifikation → Ablage → Lernen`

ist bereits funktionsfähig.

Vor einem produktiven Einsatz sollten Backups der Dokumente und der Konfigurationsdateien vorhanden sein.

## Installation

Siehe [INSTALL.md](INSTALL.md).

## Lizenz

LocalDocFlow wird unter der GNU General Public License v3 oder später (`GPL-3.0-or-later`) veröffentlicht. Siehe [LICENSE](LICENSE).

## Mitwirken

Fehlerberichte, Tests auf weiteren Linux-Distributionen und nachvollziehbare Verbesserungen sind willkommen. Vor einer öffentlichen Veröffentlichung sollten Beiträge keine persönlichen Dokumente oder produktiven Konfigurationsdaten enthalten.

## Entwicklung und GitHub

Für eine öffentliche Veröffentlichung ist dieses Projekt so vorbereitet, dass Quellcode, Dokumentation, Issue-Vorlagen und Release-Dateien gemeinsam in einem Repository gepflegt werden können.

Vor jedem öffentlichen Push sollte der Privacy-Check aus `RELEASE.md` ausgeführt werden.

## Ollama-Reparatur

Der Installer erkennt unvollständige Ollama-Installationen, bei denen das Programm bereits vorhanden ist, der systemd-Dienst jedoch fehlt oder beschädigt beziehungsweise maskiert ist. In diesem Fall kann die Ollama-Installation nach Bestätigung erneut ausgeführt und der Dienst wiederhergestellt werden.
