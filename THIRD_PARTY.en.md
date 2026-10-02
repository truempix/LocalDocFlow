# Third-party components

**Language:** [Deutsch](THIRD_PARTY.md) | English

LocalDocFlow uses or installs external open-source components. Those components remain subject to their respective licenses.

Important components include:

- PyQt6 – graphical user interface
- OCRmyPDF – OCR/PDF-A processing
- Tesseract – text recognition
- Ollama – local model execution
- SANE – scanner access
- ImageMagick – image processing
- inotify-tools – file-system monitoring
- Ghostscript – PDF processing
- Poppler tools such as `pdftotext` and `pdfinfo`

LocalDocFlow does not necessarily bundle these projects in its own source archive. It primarily uses installed system packages or separately installed runtime components.

Before distributing LocalDocFlow as a binary package in the future, the applicable license and redistribution terms should be reviewed again.
