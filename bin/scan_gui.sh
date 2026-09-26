#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

CAPTURE_SCRIPT="${SCRIPT_DIR}/scan_capture.sh"

if [[ ! -x "$CAPTURE_SCRIPT" ]]; then
    zenity \
        --error \
        --title="LocalDocFlow" \
        --width=500 \
        --text="Capture-Skript wurde nicht gefunden:

$CAPTURE_SCRIPT"

    exit 1
fi

while true; do

    # --------------------------------------------------------
    # Scanprofil auswählen
    # --------------------------------------------------------

    PROFILE="$(
        zenity \
            --list \
            --radiolist \
            --title="Dokument scannen" \
            --text="Scanprofil auswählen:" \
            --column="Auswahl" \
            --column="Profil" \
            TRUE  "Simplex Color" \
            FALSE "Simplex Gray" \
            FALSE "Duplex Color" \
            FALSE "Duplex Gray" \
            --width=520 \
            --height=420
    )" || exit 0

    case "$PROFILE" in

        "Simplex Color")
            PROFILE_NUMBER=1
            ;;

        "Simplex Gray")
            PROFILE_NUMBER=2
            ;;

        "Duplex Color")
            PROFILE_NUMBER=3
            ;;

        "Duplex Gray")
            PROFILE_NUMBER=4
            ;;

        *)
            zenity \
                --error \
                --title="LocalDocFlow" \
                --width=450 \
                --text="Ungültiges Scanprofil."

            continue
            ;;

    esac

    # --------------------------------------------------------
    # Scan in Konsole starten
    #
    # Nach erfolgreichem oder abgebrochenem Durchlauf:
    # - Enter drücken
    # - Konsole schließt sich
    # - GUI erscheint erneut
    # --------------------------------------------------------

    konsole \
        -e bash -c '
            "'"$CAPTURE_SCRIPT"'" "'"$PROFILE_NUMBER"'"
            STATUS=$?

            echo
            echo
            read -r -p "Enter drücken zum Schließen ..."

            exit "$STATUS"
        '

done
