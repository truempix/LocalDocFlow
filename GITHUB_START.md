# GitHub-Schnellstart für LocalDocFlow

**Sprache:** Deutsch | [English](GITHUB_START.en.md)

Diese Datei richtet sich an den Projektbetreuer und erklärt die wichtigsten Begriffe und den ersten Upload.

## Grundbegriffe

- **Git**: Versionsverwaltung auf dem eigenen Rechner.
- **GitHub**: Online-Plattform, auf der ein Git-Repository gehostet werden kann.
- **Repository**: Projektordner inklusive Versionsgeschichte.
- **Commit**: gespeicherter Zwischenstand mit Beschreibung.
- **Push**: lokale Commits zu GitHub übertragen.
- **Clone**: ein Repository auf einen Rechner kopieren.
- **Branch**: parallele Entwicklungslinie; Standard ist meist `main`.
- **Issue**: Fehlerbericht, Aufgabe oder Vorschlag.
- **Pull Request**: vorgeschlagene Änderung, die geprüft und übernommen werden kann.
- **Release**: veröffentlichter Versionsstand, z. B. 0.1.3, optional mit Archivdatei.

## Vor dem ersten Commit

Prüfen, welche Identität Git in Commits eintragen würde:

```bash
git config --global user.name
git config --global user.email
```

Wer die private E-Mail-Adresse nicht veröffentlichen möchte, kann in GitHub eine `noreply`-Adresse verwenden und diese für Git konfigurieren.

## Lokales Repository anlegen

Im Projektordner:

```bash
cd ~/LocalDocFlow
git init -b main
git status
git add .
git status
git commit -m "Initial release preparation for LocalDocFlow 0.1.3"
```

Vor `git add .` sollte der Privacy-Check aus `RELEASE.md` durchgeführt worden sein.

## Repository auf GitHub anlegen

Für einen vorhandenen lokalen Projektordner auf GitHub ein **leeres** Repository `LocalDocFlow` anlegen. Auf GitHub dabei nicht zusätzlich README, `.gitignore` oder Lizenz erzeugen, weil diese Dateien lokal bereits existieren.

Zum Einstieg kann das Repository zunächst **private** bleiben. Wenn alles korrekt aussieht, lässt es sich später auf **public** umstellen.

## Verbindung zu GitHub

Zwei übliche Wege:

1. GitHub CLI (`gh`) – für Einsteiger oft angenehm, weil die Anmeldung im Browser erfolgen kann.
2. normales Git über HTTPS oder SSH.

Mit GitHub CLI kann ein vorhandenes lokales Repository interaktiv erstellt und übertragen werden:

```bash
gh auth login
gh repo create
```

Dort „Push an existing local repository to GitHub“ auswählen.

## Nach dem Upload

Auf GitHub prüfen:

- README wird korrekt angezeigt
- Lizenz wird erkannt
- keine privaten Dateien vorhanden
- `.github/ISSUE_TEMPLATE/` ist vorhanden
- Versionsnummer stimmt
- Repository-Beschreibung und Topics setzen

Vorschlag für die Kurzbeschreibung:

> Local Linux document workflow: scan, OCR/PDF-A, local Ollama classification, rule-based filing and learning from manual corrections.

Vorschläge für Topics:

`linux`, `document-management`, `ocr`, `ollama`, `sane`, `tesseract`, `ocrmypdf`, `pdf-a`, `pyqt6`, `automation`, `document-scanner`
