# Contributing

**Language:** [Deutsch](CONTRIBUTING.md) | English

Contributions to LocalDocFlow are welcome.

## Reporting bugs

Please include, where possible:

- LocalDocFlow version
- Linux distribution and version
- desktop environment
- scanner model, if relevant
- reproducible steps
- relevant sanitized log lines

Remove personal information first.

Do not publish:

- real documents or complete document text
- passwords, tokens, or private keys
- private addresses or other personal data
- production learning rules containing private information
- scanner serial numbers unless they are intentionally required and approved for publication

## Code changes

Before opening a pull request:

```bash
for f in bin/*.sh installer/install.sh installer/lib/*.sh; do
    bash -n "$f" || exit 1
done

python3 -m py_compile bin/scan_gui.py

for f in installer/defaults/*.json; do
    jq empty "$f" || exit 1
done
```

Keep changes as small and understandable as practical.

## Filing principle

LocalDocFlow must not invent or create subject-specific target folders on its own. The subject-specific folder structure is defined by the user.

## License

By contributing, you confirm that you may provide your contribution under the project's `GPL-3.0-or-later` license.
