# Mitwirken

**Sprache:** Deutsch | [English](CONTRIBUTING.en.md)

Beiträge zu LocalDocFlow sind willkommen.

## Fehler melden

Bitte möglichst angeben:

- LocalDocFlow-Version
- Linux-Distribution und Version
- Desktop-Umgebung
- Scanner-Modell, sofern relevant
- nachvollziehbare Schritte zum Fehler
- relevante, bereinigte Logzeilen

Bitte vorher persönliche Informationen entfernen.

Nicht veröffentlichen:

- echte Dokumente oder vollständige Dokumenttexte
- Passwörter, Tokens oder private Schlüssel
- private Adressen oder andere personenbezogene Daten
- produktive Lernregeln mit privaten Inhalten
- Scanner-Seriennummern, sofern sie nicht bewusst benötigt und freigegeben werden

## Änderungen am Code

Vor einem Pull Request:

```bash
for f in bin/*.sh installer/install.sh installer/lib/*.sh; do
    bash -n "$f" || exit 1
done

python3 -m py_compile bin/scan_gui.py

for f in installer/defaults/*.json; do
    jq empty "$f" || exit 1
done
```

Bitte Änderungen möglichst klein und nachvollziehbar halten.

## Grundprinzip der Ablage

LocalDocFlow soll keine fachlichen Zielordner eigenmächtig erfinden oder erzeugen. Die fachliche Ordnerstruktur wird vom Benutzer vorgegeben.

## Lizenz

Mit einem Beitrag bestätigst du, dass du den Beitrag unter der Projektlizenz GPL-3.0-or-later bereitstellen darfst.
