# GitHub quick start for LocalDocFlow

**Language:** [Deutsch](GITHUB_START.md) | English

This file is intended for the project maintainer and explains the basic terms and the first upload.

## Basic terms

- **Git**: version control on the local computer.
- **GitHub**: online platform that can host a Git repository.
- **Repository**: project directory including version history.
- **Commit**: saved project state with a description.
- **Push**: transfer local commits to GitHub.
- **Clone**: copy a repository to a computer.
- **Branch**: parallel line of development; the default is usually `main`.
- **Issue**: bug report, task, or suggestion.
- **Pull request**: proposed change that can be reviewed and merged.
- **Release**: published version such as 0.1.3, optionally with an archive file.

## Before the first commit

Check which identity Git would write into commits:

```bash
git config --global user.name
git config --global user.email
```

If you do not want to publish your private email address, GitHub provides a `noreply` address that can be configured in Git.

## Create the local repository

Inside the project directory:

```bash
cd ~/LocalDocFlow
git init -b main
git status
git add .
git status
git commit -m "Initial release preparation for LocalDocFlow 0.1.3"
```

Run the privacy check from `RELEASE.en.md` before `git add .`.

## Create the repository on GitHub

For an existing local project directory, create an **empty** GitHub repository named `LocalDocFlow`. Do not let GitHub create an additional README, `.gitignore`, or license because those files already exist locally.

The repository can initially remain **private**. It can later be changed to **public** after everything has been checked.

## Connect to GitHub

Two common approaches are:

1. GitHub CLI (`gh`) – often convenient for beginners because authentication can happen in a browser.
2. normal Git over HTTPS or SSH.

With GitHub CLI, an existing local repository can be created and pushed interactively:

```bash
gh auth login
gh repo create
```

Choose “Push an existing local repository to GitHub”.

## After the upload

Check on GitHub that:

- the README renders correctly
- the license is detected
- no private files are present
- `.github/ISSUE_TEMPLATE/` exists
- the version number is correct
- repository description and topics are set

Suggested short description:

> Local Linux document workflow: scan, OCR/PDF-A, local Ollama classification, rule-based filing and learning from manual corrections.

Suggested topics:

`linux`, `document-management`, `ocr`, `ollama`, `sane`, `tesseract`, `ocrmypdf`, `pdf-a`, `pyqt6`, `automation`, `document-scanner`
