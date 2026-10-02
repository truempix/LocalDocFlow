# Externe Komponenten

**Sprache:** Deutsch | [English](THIRD_PARTY.en.md)

LocalDocFlow nutzt bzw. installiert externe Open-Source-Komponenten. Diese bleiben unter ihren jeweiligen eigenen Lizenzen.

Wichtige Komponenten sind unter anderem:

- PyQt6 – grafische Oberfläche
- OCRmyPDF – OCR/PDF-A-Verarbeitung
- Tesseract – Texterkennung
- Ollama – lokale Modellausführung
- SANE – Scannerzugriff
- ImageMagick – Bildverarbeitung
- inotify-tools – Dateisystemüberwachung
- Ghostscript – PDF-Verarbeitung
- Poppler-Werkzeuge wie `pdftotext` und `pdfinfo`

LocalDocFlow bündelt diese Projekte nicht notwendigerweise im eigenen Quellarchiv, sondern verwendet überwiegend installierte Systempakete bzw. separat installierte Laufzeitkomponenten.

Vor einer späteren Distribution als Binärpaket sollten die jeweiligen Lizenz- und Weitergabebedingungen nochmals geprüft werden.
