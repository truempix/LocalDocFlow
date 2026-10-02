#!/usr/bin/env bash
set -u

# ============================================================
# LocalDocFlow - Protokollanzeige
# LocalDocFlow - Log viewer
#
# Zeigt die letzten relevanten Meldungen der Scan-Automation:
#
#   - Rohscan-Watcher / Dokumentverarbeitung
#   - Learning-Watcher
#
# Die Daten stammen direkt aus dem systemd-Journal.
# Es werden keinerlei Dateien verändert.
# ============================================================


RAW_SERVICE="localdocflow-watcher.service"
LEARNING_SERVICE="localdocflow-learning-watcher.service"

LINES="${1:-120}"


# ============================================================
# Kopf
# Header
# ============================================================

echo
echo "============================================================"
echo "LocalDocFlow - Protokoll"
echo "============================================================"
echo

echo "Zeitpunkt:"
echo "  $(date '+%d.%m.%Y %H:%M:%S')"
echo


# ============================================================
# Dienste
# Services
# ============================================================

echo "------------------------------------------------------------"
echo "Dienststatus"
echo "------------------------------------------------------------"
echo

RAW_STATE="$(
    systemctl --user is-active "$RAW_SERVICE" 2>/dev/null || true
)"

LEARNING_STATE="$(
    systemctl --user is-active "$LEARNING_SERVICE" 2>/dev/null || true
)"

echo "Rohscan-Watcher:"
echo "  ${RAW_STATE:-unbekannt}"
echo

echo "Learning-Watcher:"
echo "  ${LEARNING_STATE:-unbekannt}"
echo


# ============================================================
# Letzte Dokumentverarbeitung
# Latest document processing
# ============================================================

echo "------------------------------------------------------------"
echo "Letzte Dokumentverarbeitung"
echo "------------------------------------------------------------"
echo

LAST_PROCESSING="$(
    journalctl \
        --user \
        -u "$RAW_SERVICE" \
        --no-pager \
        -o cat \
        2>/dev/null \
    | grep -E \
        'Dokumentverarbeitung abgeschlossen|Endgültige OCR-Datei:|Automatische Verarbeitung erfolgreich abgeschlossen|FEHLER bei der automatischen Verarbeitung' \
    | tail -20
)"

if [[ -n "$LAST_PROCESSING" ]]; then

    printf '%s\n' "$LAST_PROCESSING"

else

    echo "Keine passende Verarbeitung im Journal gefunden."

fi

echo


# ============================================================
# Auffälligkeiten / Fehler
# Warnings / errors
# ============================================================

echo "------------------------------------------------------------"
echo "Letzte Warnungen und Fehler"
echo "------------------------------------------------------------"
echo

ERRORS="$(
    {
        journalctl \
            --user \
            -u "$RAW_SERVICE" \
            --no-pager \
            -o cat \
            2>/dev/null

        journalctl \
            --user \
            -u "$LEARNING_SERVICE" \
            --no-pager \
            -o cat \
            2>/dev/null
    } \
    | grep -Ei \
        'fehler|error|warnung|warning|failed|failure|abgebrochen' \
    | tail -40
)"

if [[ -n "$ERRORS" ]]; then

    printf '%s\n' "$ERRORS"

else

    echo "Keine Warnungen oder Fehler gefunden."

fi

echo


# ============================================================
# Rohscan-Watcher
# Raw-scan watcher
# ============================================================

echo "------------------------------------------------------------"
echo "Rohscan-Watcher - letzte ${LINES} Zeilen"
echo "------------------------------------------------------------"
echo

journalctl \
    --user \
    -u "$RAW_SERVICE" \
    -n "$LINES" \
    --no-pager \
    -o short-iso \
    2>/dev/null \
    || echo "Journal konnte nicht gelesen werden."

echo


# ============================================================
# Learning-Watcher
# Learning watcher
# ============================================================

echo "------------------------------------------------------------"
echo "Learning-Watcher - letzte ${LINES} Zeilen"
echo "------------------------------------------------------------"
echo

journalctl \
    --user \
    -u "$LEARNING_SERVICE" \
    -n "$LINES" \
    --no-pager \
    -o short-iso \
    2>/dev/null \
    || echo "Journal konnte nicht gelesen werden."

echo
echo "============================================================"
echo "Ende des Protokolls"
echo "============================================================"
echo
