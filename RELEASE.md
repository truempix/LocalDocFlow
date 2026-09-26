# Release-Checkliste

## 1. Syntax prüfen

```bash
cd ~/LocalDocFlow || exit 1

for f in bin/*.sh installer/install.sh installer/lib/*.sh; do
    bash -n "$f" || exit 1
done

python3 -m py_compile bin/scan_gui.py

for f in installer/defaults/*.json; do
    jq empty "$f" || exit 1
done

find . -type d -name '__pycache__' -prune -exec rm -rf {} +
```

## 2. Privacy-Check

grep -RInI \
  --exclude-dir='__pycache__' \
  --exclude-dir='.git' \
  -E "/home/${USER}/|/mnt/|192\.168\.|Ordner_SCHRANK|preferred_roots|scan-automation|Scan Automation" \
  .

```bash
grep -RInI   --exclude-dir='__pycache__'   --exclude-dir='.git'   -Ei 'password|passwd|kennwort|secret|token|api[_-]?key|authorization|bearer|private[_ -]?key|BEGIN .*PRIVATE KEY'   .
```

Treffer müssen einzeln bewertet werden.
Zusätzlich sollte vor einer Veröffentlichung gezielt nach eigenen Namen,
Domains, Rechnernamen, Scanner-Seriennummern und anderen persönlichen
Kennungen gesucht werden.

## 3. Unerwünschte Dateien prüfen

```bash
find .   \( -name '*.bak*'      -o -name '*.swp'      -o -name '*~'      -o -name '*.pyc'      -o -name '__pycache__'      -o -name '*.log' \)   -print
```

## 4. Build-Verzeichnis erzeugen

```bash
rm -rf ~/localdocflow-build
mkdir -p ~/localdocflow-build/LocalDocFlow-0.1.3

cp -a ~/LocalDocFlow/bin ~/localdocflow-build/LocalDocFlow-0.1.3/
cp -a ~/LocalDocFlow/installer ~/localdocflow-build/LocalDocFlow-0.1.3/

cp ~/LocalDocFlow/README.md    ~/LocalDocFlow/INSTALL.md    ~/LocalDocFlow/CHANGELOG.md    ~/LocalDocFlow/LICENSE    ~/LocalDocFlow/.gitignore    ~/LocalDocFlow/RELEASE.md    ~/localdocflow-build/LocalDocFlow-0.1.3/
```

## 5. Build bereinigen und Archiv erzeugen

```bash
find ~/localdocflow-build/LocalDocFlow-0.1.3   -type f -name '*.bak*' -delete

find ~/localdocflow-build/LocalDocFlow-0.1.3   -type d -name '__pycache__' -prune -exec rm -rf {} +

chmod +x ~/localdocflow-build/LocalDocFlow-0.1.3/installer/install.sh

tar -C ~/localdocflow-build   -czf ~/LocalDocFlow-0.1.3.tar.gz   LocalDocFlow-0.1.3
```

## 6. Archiv kontrollieren

```bash
ls -lh ~/LocalDocFlow-0.1.3.tar.gz
tar -tzf ~/LocalDocFlow-0.1.3.tar.gz | head -100
```

## 7. Frische VM testen

Vor Veröffentlichung sollte das fertige Archiv nochmals in einer frischen VM installiert werden.
