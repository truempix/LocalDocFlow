# LocalDocFlow

**Language:** [Deutsch](README.md) | English

LocalDocFlow is a local Linux application for automated document scanning, OCR, analysis, and filing of paper documents.

The project combines a SANE-compatible document scanner with OCRmyPDF, Tesseract, and a locally running AI model through Ollama. The goal is a straightforward workflow:

1. Place the document in the scanner.
2. Select a scan profile.
3. Start the scan.
4. Let the remaining processing run in the background.

Raw scans are kept permanently. LocalDocFlow also creates a searchable PDF/A file, analyzes the document content, and can automatically file documents into an existing folder structure when a suitable rule is available.

## Main features

- scanning through SANE
- simplex and duplex profiles
- color and grayscale profiles
- permanent archival of raw scans
- OCR with OCRmyPDF and Tesseract
- PDF/A output
- document date detection
- local document analysis with Ollama
- detection or derivation of title/subject, document type, category, and subcategory
- detection of insurance numbers explicitly contained in a document
- meaningful file names, optionally including a detected insurance number for insurance documents
- rule-based automatic filing
- safe OCR holding area when no suitable rule exists yet
- learnable filing rules
- detection of manual filing corrections
- graphical interface based on PyQt6
- background processing through systemd user services
- system status and log display
- installer for dependencies, configuration, and services

## Local processing

Document analysis runs locally on the user's own computer. Ollama is used for AI-based analysis. The current default model is `qwen3:4b`.

Document contents do not need to be sent to an external cloud AI service for analysis. An Internet connection is still required for the initial installation, package downloads, and downloading the Ollama model.

## Learning system

If a document cannot yet be filed automatically with sufficient confidence, it remains in the OCR holding area.

When the user later moves that document manually to the desired subject-specific folder, the learning watcher detects the correction. It can create a filing rule that may be applied automatically to similar documents in the future.

For insurance documents, a detected insurance number can additionally be used as a contract-specific attribute. Learned insurance rules are applied automatically only when the normalized insurance numbers match. Older insurance rules without a stored number are therefore not used for automatic contract assignment.

LocalDocFlow does not invent a subject-specific folder structure on its own. Target folders are defined by the user.

## Directory concept

The installer creates only the areas required by LocalDocFlow:

- raw scan archive
- OCR holding area
- user-selected document filing directory

The subject-specific substructure inside the filing directory remains entirely under the user's control.

## Hardware

Required:

- Linux PC
- SANE-compatible scanner
- sufficient free storage
- sufficient RAM for the selected Ollama model

For `qwen3:4b`, the installer warns when less than 6 GiB of RAM is available. 8 GiB or more is recommended for reliable operation.

## Tested environments

The current development version has been tested on, among others:

- Ubuntu 26.04
- Kubuntu 26.04
- Linux Lite based on Ubuntu

Ubuntu/Kubuntu and other Debian/Ubuntu-based systems are currently the main testing focus. Support for other distributions should be verified separately before production use.

## Example workflow

```text
Scanner
   ↓
Raw scan archive
   ↓
OCR / PDF-A
   ↓
local AI analysis
   ↓
file name + classification
   ↓
Mapping or learned rule available?
   ├─ yes → automatic filing
   └─ no  → OCR holding area
                ↓
          manual correction
                ↓
             learned rule
```

## Privacy

LocalDocFlow is designed for local processing. Before publishing or sharing personal configuration files, users should still verify that they do not contain personal paths, sender rules, learned rules, document names, scanner serial numbers, or other private information.

The default configuration files included in the project are intentionally kept neutral for this reason.

## Project status

LocalDocFlow is still under development. The basic workflow

`Scan → OCR/PDF-A → AI analysis → classification → filing → learning`

is already functional.

The English files currently provide documentation and contribution guidance. The application UI, installer prompts, and many runtime messages are still primarily in German; runtime localization is a separate future step.

Backups of documents and configuration files should be available before production use.

## Installation

See [INSTALL.en.md](INSTALL.en.md).

## License

LocalDocFlow is released under the GNU General Public License v3 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE).

## Contributing

Bug reports, tests on additional Linux distributions, and reproducible improvements are welcome. Contributions intended for public use must not include personal documents or production configuration data.

See [CONTRIBUTING.en.md](CONTRIBUTING.en.md).

## Development and GitHub

The project is prepared for public development with source code, documentation, issue templates, and release files maintained in the same repository.

Run the privacy check from [RELEASE.en.md](RELEASE.en.md) before every public push.

## Ollama repair

The installer detects incomplete Ollama installations where the executable already exists but the systemd service is missing, damaged, or masked. After confirmation, the installer can rerun the Ollama installation and restore the service.
