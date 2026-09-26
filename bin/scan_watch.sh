#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# LocalDocFlow - Rohscan Watcher
#
# Überwacht:
#
# Das in system.conf konfigurierte Rohscan-Verzeichnis
#
# Sobald dort eine neue PDF vollständig angekommen ist,
# wird sie an scan_process.sh übergeben.
#
# Die Verarbeitung erfolgt bewusst nacheinander.
# Dadurch laufen nicht mehrere OCR-/Ollama-Prozesse
# gleichzeitig auf dem Rechner.
# ============================================================


# ============================================================
# Konfiguration
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

: "${RAW_DIR:?RAW_DIR fehlt in system.conf}"


# ------------------------------------------------------------
# Interne Pfade
# ------------------------------------------------------------

RAW_ROOT="$RAW_DIR"

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

PROCESSOR="${SCRIPT_DIR}/scan_process.sh"



# ============================================================
# Programme prüfen
# ============================================================

for CMD in \
    inotifywait \
    pdfinfo \
    sha256sum \
    jq \
    stat \
    date
do

    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "Fehler: '$CMD' wurde nicht gefunden."
        exit 1
    fi

done


# ============================================================
# Verzeichnisse / Dateien prüfen
# ============================================================

if [[ ! -d "$RAW_ROOT" ]]; then

    echo "Fehler: Rohscan-Verzeichnis existiert nicht:"
    echo "  $RAW_ROOT"

    exit 1

fi


if [[ ! -x "$PROCESSOR" ]]; then

    echo "Fehler: Processor fehlt oder ist nicht ausführbar:"
    echo "  $PROCESSOR"

    exit 1

fi




: "${PENDING_LEARNING_FILE:?PENDING_LEARNING_FILE fehlt in system.conf}"

PENDING_FILE="$PENDING_LEARNING_FILE"


if [[ ! -f "$PENDING_FILE" ]]; then

    echo "Fehler: pending_learning.json fehlt:"
    echo "  $PENDING_FILE"

    exit 1

fi


# ============================================================
# Doppelte Events innerhalb derselben Watcher-Sitzung
# verhindern.
#
# inotify kann für eine Datei unter Umständen mehr als ein
# interessantes Event liefern.
# ============================================================

declare -A SEEN_EVENTS


# ============================================================
# Prüfen, ob dieser Rohscan bereits verarbeitet wurde.
#
# scan_process.sh speichert den SHA256-Hash des Rohscans als
# source_hash in pending_learning.json.
#
# Dadurch verhindern wir auch nach einem Neustart des Watchers
# weitgehend eine erneute Verarbeitung derselben Rohdatei.
# ============================================================

already_processed() {

    local FILE="$1"
    local HASH

    HASH="$(
        sha256sum "$FILE" |
        awk '{print $1}'
    )"


    jq -e \
        --arg HASH "$HASH" \
        '
        any(
            .documents[]?;
            .source_hash == $HASH
        )
        ' \
        "$PENDING_FILE" \
        >/dev/null 2>&1
}


# ============================================================
# Prüfen, ob die PDF wirklich fertig geschrieben und lesbar
# ist.
#
# close_write bzw. moved_to sind bereits gute Signale.
# Zusätzlich prüfen wir Größe und pdfinfo.
# ============================================================

wait_until_ready() {

    local FILE="$1"

    local SIZE_1
    local SIZE_2

    local TRY


    for TRY in {1..20}; do

        [[ -f "$FILE" ]] || return 1


        SIZE_1="$(
            stat -c '%s' "$FILE" 2>/dev/null || echo 0
        )"


        if (( SIZE_1 == 0 )); then

            sleep 1
            continue

        fi


        sleep 1


        [[ -f "$FILE" ]] || return 1


        SIZE_2="$(
            stat -c '%s' "$FILE" 2>/dev/null || echo 0
        )"


        # Dateigröße stabil und PDF lesbar
        if [[ "$SIZE_1" == "$SIZE_2" ]] \
           && pdfinfo "$FILE" >/dev/null 2>&1
        then

            return 0

        fi

    done


    return 1
}


# ============================================================
# Einzelnen Rohscan verarbeiten
# ============================================================

handle_pdf() {

    local FILE="$1"

    local SIGNATURE
    local EVENT_KEY


    # --------------------------------------------------------
    # Existiert noch?
    # --------------------------------------------------------

    [[ -f "$FILE" ]] || return 0


    # --------------------------------------------------------
    # Nur PDF
    # --------------------------------------------------------

    case "${FILE,,}" in

        *.pdf)
            ;;

        *)
            return 0
            ;;

    esac


    # --------------------------------------------------------
    # Versteckte Dateien ignorieren
    # --------------------------------------------------------

    if [[ "$(basename "$FILE")" == .* ]]; then
        return 0
    fi


    # --------------------------------------------------------
    # Event-Signatur bestimmen
    # --------------------------------------------------------

    SIGNATURE="$(
        stat -c '%Y:%s' "$FILE" 2>/dev/null || echo "unknown"
    )"

    EVENT_KEY="${FILE}|${SIGNATURE}"


    if [[ -n "${SEEN_EVENTS[$EVENT_KEY]:-}" ]]; then
        return 0
    fi


    SEEN_EVENTS["$EVENT_KEY"]=1


    echo
    echo "============================================================"
    echo "Neuer Rohscan erkannt"
    echo "============================================================"
    echo
    echo "Datei:"
    echo "  $FILE"
    echo


    # --------------------------------------------------------
    # Warten bis PDF vollständig ist
    # --------------------------------------------------------

    echo "Prüfe, ob PDF vollständig geschrieben wurde ..."


    if ! wait_until_ready "$FILE"; then

        echo
        echo "WARNUNG:"
        echo "PDF wurde nicht rechtzeitig lesbar."
        echo "Keine automatische Verarbeitung:"
        echo "  $FILE"

        return 0

    fi


    # --------------------------------------------------------
    # Schon verarbeitet?
    # --------------------------------------------------------

    if already_processed "$FILE"; then

        echo
        echo "Rohscan wurde bereits verarbeitet."
        echo "Überspringe:"
        echo "  $FILE"

        return 0

    fi


    # --------------------------------------------------------
    # Verarbeitung
    # --------------------------------------------------------

    echo
    echo "Starte Dokumentverarbeitung ..."
    echo


    if "$PROCESSOR" "$FILE"; then

        echo
        echo "------------------------------------------------------------"
        echo "Automatische Verarbeitung erfolgreich abgeschlossen"
        echo "------------------------------------------------------------"
        echo

    else

        RESULT=$?

        echo
        echo "------------------------------------------------------------"
        echo "FEHLER bei der automatischen Verarbeitung"
        echo "------------------------------------------------------------"
        echo
        echo "Exit-Code:"
        echo "  $RESULT"
        echo
        echo "Der Rohscan bleibt erhalten:"
        echo "  $FILE"
        echo
        echo "Manueller Wiederholungsbefehl:"
        echo "  $PROCESSOR \"$FILE\""
        echo

    fi
}


# ============================================================
# Start
# ============================================================

echo
echo "============================================================"
echo "LocalDocFlow - Rohscan Watcher"
echo "============================================================"
echo
echo "Überwache:"
echo "  $RAW_ROOT"
echo
echo "Processor:"
echo "  $PROCESSOR"
echo
echo "Warte auf neue Rohscans ..."
echo


# ============================================================
# Verzeichnis rekursiv überwachen
#
# close_write:
#   Datei wurde direkt im Zielverzeichnis geschrieben.
#
# moved_to:
#   Fertige Datei wurde in das Zielverzeichnis verschoben.
#
# Wir verwenden absichtlich NICHT create, weil eine Datei
# zu diesem Zeitpunkt noch unvollständig sein kann.
# ============================================================

inotifywait \
    -m \
    -r \
    -e close_write \
    -e moved_to \
    --format '%e|%w%f' \
    "$RAW_ROOT" |
while IFS='|' read -r EVENT FILE; do

    handle_pdf "$FILE"

done
