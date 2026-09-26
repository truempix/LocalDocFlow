#!/usr/bin/env bash
set -u

# ============================================================
# LocalDocFlow - Systemstatus
#
# Prüft die wesentlichen Bestandteile der Installation:
#
#   - Verzeichnisse
#   - Programme
#   - Konfigurationsdateien
#   - systemd-Userdienste
#   - Ollama / KI-Modell
#   - Scanner
#   - OCR-Sprachen
#   - Python / PyQt6
#
# Das Skript verändert keinerlei Daten.
#
# Exit-Codes:
#
#   0 = alles Wesentliche in Ordnung
#   1 = mindestens ein kritischer Fehler
# ============================================================


# ============================================================
# Zentrale Systemkonfiguration
# ============================================================

CONFIG_DIR="$HOME/.config/localdocflow"
SYSTEM_CONFIG="${CONFIG_DIR}/system.conf"

if [[ ! -f "$SYSTEM_CONFIG" ]]; then

    echo "Fehler: Systemkonfiguration fehlt:"
    echo "  $SYSTEM_CONFIG"

    exit 1

fi

# shellcheck source=/dev/null
source "$SYSTEM_CONFIG"


# ------------------------------------------------------------
# Benötigte Werte prüfen
# ------------------------------------------------------------

: "${DOCUMENT_ROOT:?DOCUMENT_ROOT fehlt in system.conf}"
: "${RAW_DIR:?RAW_DIR fehlt in system.conf}"
: "${OCR_DIR:?OCR_DIR fehlt in system.conf}"
: "${CABINET_DIR:?CABINET_DIR fehlt in system.conf}"
    SCANNER_DEVICE="${SCANNER_DEVICE:-}"
: "${OCR_LANGUAGES:?OCR_LANGUAGES fehlt in system.conf}"
: "${OLLAMA_URL:?OLLAMA_URL fehlt in system.conf}"
: "${OLLAMA_MODEL:?OLLAMA_MODEL fehlt in system.conf}"


# ------------------------------------------------------------
# Projektpfade
# ------------------------------------------------------------

BASE_DIR="$DOCUMENT_ROOT"

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

PROJECT_DIR="$(
    cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1
    pwd
)"

BIN_DIR="${PROJECT_DIR}/bin"


# ------------------------------------------------------------
# Dienste
# ------------------------------------------------------------

RAW_SERVICE="localdocflow-watcher.service"
LEARNING_SERVICE="localdocflow-learning-watcher.service"


# ============================================================
# Zähler
# ============================================================

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0


# ============================================================
# Ausgabe-Funktionen
# ============================================================

ok() {

    printf '[ OK ] %s\n' "$1"
    OK_COUNT=$((OK_COUNT + 1))
}


warn() {

    printf '[WARN] %s\n' "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}


fail() {

    printf '[FAIL] %s\n' "$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}


section() {

    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}


# ============================================================
# Programm prüfen
# ============================================================

check_command() {

    local COMMAND="$1"
    local DESCRIPTION="${2:-$1}"

    if command -v "$COMMAND" >/dev/null 2>&1; then

        ok "$DESCRIPTION vorhanden"

    else

        fail "$DESCRIPTION fehlt"

    fi
}


# ============================================================
# Verzeichnis prüfen
# ============================================================

check_directory() {

    local DIRECTORY="$1"
    local DESCRIPTION="$2"

    if [[ ! -d "$DIRECTORY" ]]; then

        fail "$DESCRIPTION fehlt: $DIRECTORY"
        return

    fi


    if [[ ! -r "$DIRECTORY" ]]; then

        fail "$DESCRIPTION ist nicht lesbar: $DIRECTORY"
        return

    fi


    if [[ ! -w "$DIRECTORY" ]]; then

        fail "$DESCRIPTION ist nicht beschreibbar: $DIRECTORY"
        return

    fi


    ok "$DESCRIPTION erreichbar"

}


# ============================================================
# JSON-Datei prüfen
# ============================================================

check_json() {

    local FILE="$1"
    local DESCRIPTION="$2"

    if [[ ! -f "$FILE" ]]; then

        fail "$DESCRIPTION fehlt"
        return

    fi


    if jq empty "$FILE" >/dev/null 2>&1; then

        ok "$DESCRIPTION gültig"

    else

        fail "$DESCRIPTION enthält ungültiges JSON"

    fi
}


# ============================================================
# Skript prüfen
# ============================================================

check_script() {

    local FILE="$1"
    local DESCRIPTION="$2"

    if [[ ! -f "$FILE" ]]; then

        fail "$DESCRIPTION fehlt"
        return

    fi


    if [[ ! -x "$FILE" ]]; then

        fail "$DESCRIPTION ist nicht ausführbar"
        return

    fi


    ok "$DESCRIPTION vorhanden und ausführbar"
}


# ============================================================
# systemd-Dienst prüfen
# ============================================================

check_service() {

    local SERVICE="$1"
    local DESCRIPTION="$2"

    local ACTIVE
    local ENABLED


    ACTIVE="$(
        systemctl --user is-active "$SERVICE" 2>/dev/null || true
    )"

    ENABLED="$(
        systemctl --user is-enabled "$SERVICE" 2>/dev/null || true
    )"


    if [[ "$ACTIVE" == "active" ]]; then

        ok "$DESCRIPTION läuft"

    else

        fail "$DESCRIPTION läuft nicht (${ACTIVE:-unbekannt})"

    fi


    if [[ "$ENABLED" == "enabled" ]]; then

        ok "$DESCRIPTION ist für den Benutzerstart aktiviert"

    else

        warn "$DESCRIPTION ist nicht aktiviert (${ENABLED:-unbekannt})"

    fi

}


# ============================================================
# Kopf
# ============================================================

echo
echo "============================================================"
echo "LocalDocFlow - Systemstatus"
echo "============================================================"
echo


# ============================================================
# Verzeichnisse
# ============================================================

section "Verzeichnisse"

check_directory \
    "$RAW_DIR" \
    "Rohscan-Archiv"

check_directory \
    "$OCR_DIR" \
    "OCR-Zwischenablage"

check_directory \
    "$CABINET_DIR" \
    "Dokumentenablage"


# Mountpoint anzeigen

if command -v findmnt >/dev/null 2>&1; then

    MOUNT_INFO="$(
        findmnt \
            -T "$BASE_DIR" \
            -no SOURCE,FSTYPE,TARGET \
            2>/dev/null \
            || true
    )"

    if [[ -n "$MOUNT_INFO" ]]; then
        ok "Dokumentenpfad liegt auf: $MOUNT_INFO"
    else
        warn "Mountinformationen für $BASE_DIR konnten nicht bestimmt werden"
    fi

fi


# ============================================================
# Projektdateien
# ============================================================

section "Scan-Automation"

check_script \
    "${BIN_DIR}/scan_capture.sh" \
    "scan_capture.sh"

check_script \
    "${BIN_DIR}/scan_process.sh" \
    "scan_process.sh"

check_script \
    "${BIN_DIR}/scan_watch.sh" \
    "scan_watch.sh"

check_script \
    "${BIN_DIR}/scan_learning_watch.sh" \
    "scan_learning_watch.sh"

check_script \
    "${BIN_DIR}/scan_gui.py" \
    "scan_gui.py"


# Bash-Syntax

for SCRIPT in \
    "${BIN_DIR}/scan_capture.sh" \
    "${BIN_DIR}/scan_process.sh" \
    "${BIN_DIR}/scan_watch.sh" \
    "${BIN_DIR}/scan_learning_watch.sh"
do

    if [[ -f "$SCRIPT" ]]; then

        if bash -n "$SCRIPT" >/dev/null 2>&1; then
            ok "Bash-Syntax: $(basename "$SCRIPT")"
        else
            fail "Bash-Syntaxfehler: $(basename "$SCRIPT")"
        fi

    fi

done


# Python-Syntax

if [[ -f "${BIN_DIR}/scan_gui.py" ]]; then

    if python3 \
        -m py_compile \
        "${BIN_DIR}/scan_gui.py" \
        >/dev/null 2>&1
    then

        ok "Python-Syntax: scan_gui.py"

    else

        fail "Python-Syntaxfehler: scan_gui.py"

    fi

fi


# ============================================================
# Konfiguration
# ============================================================

section "Konfiguration"

check_json \
    "${CONFIG_DIR}/senders.json" \
    "senders.json"

check_json \
    "${CONFIG_DIR}/document_types.json" \
    "document_types.json"

check_json \
    "${CONFIG_DIR}/mapping.json" \
    "mapping.json"

check_json \
    "${CONFIG_DIR}/learning_config.json" \
    "learning_config.json"

check_json \
    "${CONFIG_DIR}/pending_learning.json" \
    "pending_learning.json"

check_json \
    "${CONFIG_DIR}/learning.json" \
    "learning.json"


# ============================================================
# Hintergrunddienste
# ============================================================

section "Hintergrunddienste"

check_service \
    "$RAW_SERVICE" \
    "Rohscan-Watcher"

check_service \
    "$LEARNING_SERVICE" \
    "Learning-Watcher"


# ============================================================
# Programme
# ============================================================

section "Programme"

check_command scanimage "SANE / scanimage"
check_command ocrmypdf "OCRmyPDF"
check_command tesseract "Tesseract"
check_command pdftotext "pdftotext"
check_command pdfinfo "pdfinfo"
check_command magick "ImageMagick"
check_command tiffcp "tiffcp"
check_command tiff2pdf "tiff2pdf"
check_command inotifywait "inotify-tools"
check_command jq "jq"
check_command curl "curl"
check_command sha256sum "sha256sum"
check_command python3 "Python 3"


# ============================================================
# PyQt6
# ============================================================

section "Grafische Oberfläche"

if python3 -c \
    'from PyQt6.QtWidgets import QApplication' \
    >/dev/null 2>&1
then

    ok "PyQt6 verfügbar"

else

    fail "PyQt6 fehlt"

fi


DESKTOP_FILE="$HOME/.local/share/applications/localdocflow.desktop"

if [[ -f "$DESKTOP_FILE" ]]; then

    ok "KDE-Starter vorhanden"

    if grep -Fq \
        "Exec=${PROJECT_DIR}/bin/scan_gui.py" \
        "$DESKTOP_FILE"
    then

        ok "KDE-Starter verwendet die Qt-GUI"

    else

        warn "KDE-Starter zeigt nicht auf scan_gui.py"

    fi

else

    fail "KDE-Starter fehlt"

fi


# ============================================================
# OCR-Sprachen
# ============================================================

section "OCR-Sprachen"

if command -v tesseract >/dev/null 2>&1; then

    TESS_LANGS="$(
        tesseract --list-langs 2>/dev/null || true
    )"


    if grep -qx "deu" <<< "$TESS_LANGS"; then
        ok "Tesseract Deutsch (deu)"
    else
        fail "Tesseract Deutsch (deu) fehlt"
    fi


    if grep -qx "eng" <<< "$TESS_LANGS"; then
        ok "Tesseract Englisch (eng)"
    else
        fail "Tesseract Englisch (eng) fehlt"
    fi


    if grep -qx "osd" <<< "$TESS_LANGS"; then
        ok "Tesseract Orientation Detection (osd)"
    else
        warn "Tesseract Orientation Detection (osd) fehlt"
    fi

fi


# ============================================================
# Ollama
# ============================================================

section "Lokale KI"

if ! command -v ollama >/dev/null 2>&1; then

    fail "Ollama fehlt"

else

    ok "Ollama installiert"


    OLLAMA_VERSION="$(
        curl \
            -fsS \
            --max-time 3 \
            "${OLLAMA_URL}/api/version" \
            2>/dev/null \
            | jq -r '.version // empty' \
            2>/dev/null \
            || true
    )"


    if [[ -n "$OLLAMA_VERSION" ]]; then

        ok "Ollama erreichbar (Version $OLLAMA_VERSION)"

    else

        fail "Ollama-API nicht erreichbar"

    fi


    if ollama list 2>/dev/null \
        | awk 'NR > 1 {print $1}' \
        | grep -Fxq "$OLLAMA_MODEL"
    then

        ok "KI-Modell $OLLAMA_MODEL vorhanden"

    else

        fail "KI-Modell $OLLAMA_MODEL fehlt"

    fi

fi

# ============================================================
# Scanner
#
# scanimage -L gibt auch bei fehlendem Scanner einen
# erklärenden Text aus. Deshalb reicht eine nichtleere
# Ausgabe nicht aus.
#
# Eine tatsächlich erkannte SANE-Hardware wird von
# scanimage mit einer Zeile beginnend mit "device "
# ausgegeben.
# ============================================================

section "Scanner"

if command -v scanimage >/dev/null 2>&1; then

    SCANNER_OUTPUT="$(
        scanimage -L 2>&1 || true
    )"

    SCANNER_DEVICES="$(
        printf '%s\n' "$SCANNER_OUTPUT" |
        grep '^device ' ||
        true
    )"

    # --------------------------------------------------------
    # Noch kein Scanner konfiguriert
    # --------------------------------------------------------

    if [[ -z "$SCANNER_DEVICE" ]]; then

        if [[ -z "$SCANNER_DEVICES" ]]; then
            warn "Kein Scanner konfiguriert und aktuell keiner erkannt"
        else
            warn "Noch kein Scanner konfiguriert"

            echo
            printf '%s\n' "$SCANNER_DEVICES" |
                sed 's/^/      /'
        fi

    # --------------------------------------------------------
    # Scanner konfiguriert, aber aktuell keiner erkannt
    # --------------------------------------------------------

    elif [[ -z "$SCANNER_DEVICES" ]]; then

        warn "Konfigurierter Scanner derzeit nicht erkannt: $SCANNER_DEVICE"
        warn "Scanner möglicherweise ausgeschaltet oder nicht verbunden"

    # --------------------------------------------------------
    # Mindestens ein Scanner erkannt
    # --------------------------------------------------------

    else

        ok "Scanner erkannt"

        echo
        printf '%s\n' "$SCANNER_DEVICES" |
            sed 's/^/      /'

        if grep -Fq \
            "$SCANNER_DEVICE" \
            <<< "$SCANNER_DEVICES"
        then
            ok "Konfigurierter Scanner erkannt: $SCANNER_DEVICE"
        else
            warn "Konfigurierter Scanner nicht gefunden: $SCANNER_DEVICE"
        fi

    fi

else
    warn "Scannerprüfung nicht möglich – scanimage fehlt"
fi


# ============================================================
# Lernsystem
# ============================================================

section "Lernsystem"

if [[ -f "${CONFIG_DIR}/learning.json" ]] \
   && jq empty \
        "${CONFIG_DIR}/learning.json" \
        >/dev/null 2>&1
then

    RULE_COUNT="$(
        jq \
            '.rules | length' \
            "${CONFIG_DIR}/learning.json"
    )"

    ok "$RULE_COUNT gelernte Regel(n) vorhanden"

fi


if [[ -f "${CONFIG_DIR}/pending_learning.json" ]] \
   && jq empty \
        "${CONFIG_DIR}/pending_learning.json" \
        >/dev/null 2>&1
then

    PENDING_COUNT="$(
        jq \
            '[.documents[]? | select(.status == "pending")] | length' \
            "${CONFIG_DIR}/pending_learning.json"
    )"

    ok "$PENDING_COUNT Dokument(e) warten derzeit auf mögliche Lernkorrekturen"

fi


# ============================================================
# Zusammenfassung
# ============================================================

echo
echo "============================================================"
echo "Zusammenfassung"
echo "============================================================"
echo

printf 'OK:        %d\n' "$OK_COUNT"
printf 'Warnungen: %d\n' "$WARN_COUNT"
printf 'Fehler:    %d\n' "$FAIL_COUNT"

echo


if (( FAIL_COUNT > 0 )); then

    echo "Gesamtstatus: FEHLER"
    echo
    echo "Mindestens eine notwendige Komponente ist nicht einsatzbereit."

    exit 1

elif (( WARN_COUNT > 0 )); then

    echo "Gesamtstatus: OK MIT WARNUNGEN"
    echo
    echo "Die Scan-Automation ist grundsätzlich einsatzbereit."

    exit 0

else

    echo "Gesamtstatus: OK"
    echo
    echo "Die Scan-Automation ist einsatzbereit."

    exit 0

fi
