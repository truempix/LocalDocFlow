# Release checklist

**Language:** [Deutsch](RELEASE.md) | English

## 1. Syntax checks

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

## 2. Privacy check

```bash
grep -RInI \
  --exclude-dir='__pycache__' \
  --exclude-dir='.git' \
  -E "/home/${USER}/|/mnt/|192\.168\.|Ordner_SCHRANK|preferred_roots|scan-automation|Scan Automation" \
  .

grep -RInI \
  --exclude-dir='__pycache__' \
  --exclude-dir='.git' \
  -Ei 'password|passwd|kennwort|secret|token|api[_-]?key|authorization|bearer|private[_ -]?key|BEGIN .*PRIVATE KEY' \
  .
```

Every match must be reviewed individually.

Before publication, also search specifically for personal names, domains, host names, scanner serial numbers, and other private identifiers.

## 3. Check for unwanted files

```bash
find . \
  \( -name '*.bak*' \
     -o -name '*.swp' \
     -o -name '*~' \
     -o -name '*.pyc' \
     -o -name '__pycache__' \
     -o -name '*.log' \) \
  -print
```

## 4. Create the build directory

```bash
rm -rf ~/localdocflow-build
mkdir -p ~/localdocflow-build/LocalDocFlow-0.1.3

cp -a ~/LocalDocFlow/bin ~/localdocflow-build/LocalDocFlow-0.1.3/
cp -a ~/LocalDocFlow/installer ~/localdocflow-build/LocalDocFlow-0.1.3/

cp \
  ~/LocalDocFlow/README.md \
  ~/LocalDocFlow/README.en.md \
  ~/LocalDocFlow/INSTALL.md \
  ~/LocalDocFlow/INSTALL.en.md \
  ~/LocalDocFlow/CONTRIBUTING.md \
  ~/LocalDocFlow/CONTRIBUTING.en.md \
  ~/LocalDocFlow/SECURITY.md \
  ~/LocalDocFlow/SECURITY.en.md \
  ~/LocalDocFlow/THIRD_PARTY.md \
  ~/LocalDocFlow/THIRD_PARTY.en.md \
  ~/LocalDocFlow/CHANGELOG.md \
  ~/LocalDocFlow/LICENSE \
  ~/LocalDocFlow/.gitignore \
  ~/LocalDocFlow/RELEASE.md \
  ~/LocalDocFlow/RELEASE.en.md \
  ~/localdocflow-build/LocalDocFlow-0.1.3/
```

## 5. Clean the build and create the archive

```bash
find ~/localdocflow-build/LocalDocFlow-0.1.3 \
  -type f -name '*.bak*' -delete

find ~/localdocflow-build/LocalDocFlow-0.1.3 \
  -type d -name '__pycache__' -prune -exec rm -rf {} +

chmod +x ~/localdocflow-build/LocalDocFlow-0.1.3/installer/install.sh

tar -C ~/localdocflow-build \
  -czf ~/LocalDocFlow-0.1.3.tar.gz \
  LocalDocFlow-0.1.3
```

## 6. Inspect the archive

```bash
ls -lh ~/LocalDocFlow-0.1.3.tar.gz
tar -tzf ~/LocalDocFlow-0.1.3.tar.gz | head -100
```

## 7. Test in a fresh VM

Before publication, install the final archive once more in a fresh VM.
