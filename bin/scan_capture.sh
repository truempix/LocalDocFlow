#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# Sauberer manueller Abbruch
#
# Ctrl+C beendet nur den aktuellen Scanvorgang.
# Bereits vorhandene Rohscans und Hintergrunddienste
# bleiben unangetastet.
# ============================================================

handle_abort() {

    echo
    echo "------------------------------------------------------------"
    echo "Scan abgebrochen."
    echo "------------------------------------------------------------"
    echo

    exit 130
}

trap handle_abort INT TERM
# ------------------------------------------------------------
# LocalDocFlow - Capture Script
#
# Aufgabe:
#   - Dokumente über den ADF scannen
#   - Simplex / Duplex
#   - Farbe / Graustufen
#   - mehrere Scan-Durchläufe zu EINEM Dokument zusammenfassen
#   - erster Scan startet sofort
#   - bei Scanfehler kann erneut versucht werden
#   - DIN A4 bei 300 dpi
#   - unveränderten Rohscan im Nextcloud-Archiv speichern
#
# Aufruf:
#
#   scan_capture.sh
#
# oder mit Profil:
#
#   scan_capture.sh 1
#
# Profile:
#   1 = Simplex Color
#   2 = Simplex Gray
#   3 = Duplex Color
#   4 = Duplex Gray
# ------------------------------------------------------------

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
#
# Ein fehlender Wert soll einen verständlichen Fehler erzeugen,
# statt später irgendwo während des Scannens zu scheitern.
# ------------------------------------------------------------

: "${DOCUMENT_ROOT:?DOCUMENT_ROOT fehlt in system.conf}"
: "${RAW_DIR:?RAW_DIR fehlt in system.conf}"
: "${SCANNER_DEVICE:?SCANNER_DEVICE fehlt in system.conf}"
: "${SCAN_RESOLUTION:?SCAN_RESOLUTION fehlt in system.conf}"
: "${SCAN_PAGE_WIDTH:?SCAN_PAGE_WIDTH fehlt in system.conf}"
: "${SCAN_PAGE_HEIGHT:?SCAN_PAGE_HEIGHT fehlt in system.conf}"


# ------------------------------------------------------------
# Interne Namen
#
# Die bisherigen Variablennamen bleiben vorerst bestehen.
# Dadurch müssen wir den restlichen funktionierenden
# Capture-Code nicht unnötig umbauen.
# ------------------------------------------------------------

BASE_DIR="$DOCUMENT_ROOT"
RAW_BASE="$RAW_DIR"

RESOLUTION="$SCAN_RESOLUTION"

PAGE_WIDTH="$SCAN_PAGE_WIDTH"
PAGE_HEIGHT="$SCAN_PAGE_HEIGHT"

WORKDIR="$(mktemp -d /tmp/scan-capture.XXXXXX)"

cleanup() {
    rm -rf "$WORKDIR"
}

trap cleanup EXIT

# ------------------------------------------------------------
# Manueller Abbruch
#
# Ctrl+C beendet ausschließlich den aktuellen Scanvorgang.
# Das temporäre Arbeitsverzeichnis wird anschließend durch
# den bereits vorhandenen EXIT-Trap aufgeräumt.
# ------------------------------------------------------------

handle_abort() {

    echo
    echo "------------------------------------------------------------"
    echo "Scanvorgang abgebrochen."
    echo "------------------------------------------------------------"
    echo

    exit 130
}

trap handle_abort INT TERM

# ------------------------------------------------------------
# Programme prüfen
# ------------------------------------------------------------

for CMD in scanimage magick tiffcp tiff2pdf; do

    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "Fehler: '$CMD' wurde nicht gefunden."
        exit 1
    fi

done

# ------------------------------------------------------------
# Ziel prüfen
# ------------------------------------------------------------

if [[ ! -d "$RAW_BASE" ]]; then
    echo "Fehler: Zielverzeichnis existiert nicht:"
    echo "$RAW_BASE"
    exit 1
fi

# ------------------------------------------------------------
# Profil bestimmen
# ------------------------------------------------------------

if [[ $# -ge 1 ]]; then

    PROFILE="$1"

else

    echo
    echo "Scanprofil auswählen:"
    echo
    echo "1) Simplex Color"
    echo "2) Simplex Gray"
    echo "3) Duplex Color"
    echo "4) Duplex Gray"
    echo

    read -r -p "Auswahl [1-4]: " PROFILE

fi

case "$PROFILE" in

    1)
        SOURCE="ADF Front"
        MODE="Color"
        PROFILE_NAME="Simplex Color"
        ;;

    2)
        SOURCE="ADF Front"
        MODE="Gray"
        PROFILE_NAME="Simplex Gray"
        ;;

    3)
        SOURCE="ADF Duplex"
        MODE="Color"
        PROFILE_NAME="Duplex Color"
        ;;

    4)
        SOURCE="ADF Duplex"
        MODE="Gray"
        PROFILE_NAME="Duplex Gray"
        ;;

    *)
        echo "Ungültiges Scanprofil: $PROFILE"
        exit 1
        ;;

esac

# ------------------------------------------------------------
# Einzelnen Scan-Durchlauf ausführen
# ------------------------------------------------------------

scan_batch() {

    local BATCH_DIR="$1"

    rm -rf "$BATCH_DIR"
    mkdir -p "$BATCH_DIR"

    echo
    echo "Scanne mit:"
    echo
    echo "  Quelle:      $SOURCE"
    echo "  Modus:       $MODE"
    echo "  Auflösung:   ${RESOLUTION} dpi"
    echo "  Seitengröße: DIN A4 (${PAGE_WIDTH} x ${PAGE_HEIGHT} mm)"
    echo

    set +e

    (
        cd "$BATCH_DIR"

        scanimage \
            --device-name "$SCANNER_DEVICE" \
            --source "$SOURCE" \
            --mode "$MODE" \
            --resolution "$RESOLUTION" \
            --page-width "$PAGE_WIDTH" \
            --page-height "$PAGE_HEIGHT" \
            -x "$PAGE_WIDTH" \
            -y "$PAGE_HEIGHT" \
            --batch='page-%03d.pnm'
    )

    SCAN_EXIT=$?

    set -e

    shopt -s nullglob
    BATCH_PAGES=( "$BATCH_DIR"/page-*.pnm )
    shopt -u nullglob

    # Wenn mindestens eine Seite vorhanden ist, gilt der Scan
    # als erfolgreich. scanimage kann beim leeren ADF am Ende
    # eine Meldung ausgeben, obwohl vorher korrekt gescannt wurde.
    if (( ${#BATCH_PAGES[@]} > 0 )); then
        return 0
    fi

    echo
    echo "Es wurde keine Seite erfasst."

    if (( SCAN_EXIT != 0 )); then
        echo "scanimage meldete Fehlercode: $SCAN_EXIT"
    fi

    return 1
}

# ------------------------------------------------------------
# Scan durchführen
# ------------------------------------------------------------

PAGE_COUNTER=1
FIRST_SCAN=true

echo
echo "Gewähltes Scanprofil:"
echo "  $PROFILE_NAME"
echo

while true; do

    BATCH_DIR="${WORKDIR}/batch"

    # --------------------------------------------------------
    # Erster Scan startet sofort.
    # Weitere Durchläufe erst nach der "weitere Seiten"-Abfrage.
    # --------------------------------------------------------

    if [[ "$FIRST_SCAN" == true ]]; then

    echo "Starte ersten Scan ..."

else

    # --------------------------------------------------------
    # Weitere Seiten einlegen
    #
    # Im GUI-Modus wird nur ein eindeutiges Signal ausgegeben.
    # scan_gui.py zeigt anschließend den grafischen Dialog.
    #
    # Im Terminal-Modus bleibt die bisherige Bedienung erhalten.
    # --------------------------------------------------------

    if [[ "${SCAN_GUI_MODE:-0}" == "1" ]]; then

        echo "__SCAN_PROMPT_CONTINUE__"
        read -r CONTINUE_INPUT

    else

        echo
        echo "Weitere Seiten können jetzt eingelegt werden."
        echo

        read -r -p \
            "Enter drücken, um den nächsten Scan zu starten ..." \
            CONTINUE_INPUT

    fi

fi

    # --------------------------------------------------------
    # Scanversuch mit Wiederholungs-/Abbruchmöglichkeit
    #
    # Ein Scanfehler darf das Programm nicht festsetzen.
    #
    # Mögliche Ursachen sind beispielsweise:
    #
    #   - Scanner ausgeschaltet
    #   - Scanner nicht erreichbar
    #   - kein Papier im ADF
    #   - Papierstau
    #
    # Der Benutzer kann anschließend entweder den Scan erneut
    # versuchen oder den gesamten Vorgang sauber abbrechen.
    # --------------------------------------------------------

    while true; do

        if scan_batch "$BATCH_DIR"; then
            break
        fi

        echo
        echo "------------------------------------------------------------"
        echo "Scan konnte nicht durchgeführt werden."
        echo "------------------------------------------------------------"
        echo
        echo "Bitte Scanner und Papierzufuhr prüfen."
        echo
        echo "  [W] Wiederholen"
        echo "  [A] Abbrechen"
        echo

                while true; do

            if [[ "${SCAN_GUI_MODE:-0}" == "1" ]]; then

                echo "__SCAN_PROMPT_RETRY__"
                read -r RETRY

            else

                read -r -p "Auswahl [W/a]: " RETRY

            fi

            case "${RETRY,,}" in

                ""|w|weiter|wiederholen|j|ja|y|yes)

                    echo
                    echo "Starte neuen Scanversuch ..."
                    echo

                    # Innere Auswahl-Schleife verlassen.
                    # Danach beginnt die äußere Scan-Schleife
                    # erneut mit scan_batch().
                    break
                    ;;


                a|abbrechen|n|nein|no)

                    echo
                    echo "------------------------------------------------------------"
                    echo "Scanvorgang abgebrochen."
                    echo "------------------------------------------------------------"
                    echo

                    # 130 kennzeichnet einen bewussten
                    # Benutzerabbruch und kann später von der
                    # grafischen Oberfläche unterschieden
                    # werden.
                    exit 130
                    ;;


                *)

                    echo
                    echo "Ungültige Eingabe."
                    echo "Bitte W für Wiederholen oder A für Abbrechen eingeben."
                    echo
                    ;;

            esac

        done

    done

    # --------------------------------------------------------
    # Seiten dieses Durchlaufs übernehmen
    # --------------------------------------------------------

    shopt -s nullglob
    PAGES=( "$BATCH_DIR"/page-*.pnm )
    shopt -u nullglob

    for PAGE in "${PAGES[@]}"; do

        printf -v DEST "%s/page-%04d.pnm" \
            "$WORKDIR" \
            "$PAGE_COUNTER"

        mv "$PAGE" "$DEST"

        (( PAGE_COUNTER += 1 ))

    done

    echo
    echo "$((PAGE_COUNTER - 1)) Seite(n) insgesamt erfasst."
    echo

    FIRST_SCAN=false

# --------------------------------------------------------
# Weitere Seiten?
#
# Im GUI-Modus wird nur ein eindeutiges Signal ausgegeben.
# Die eigentliche Frage zeigt scan_gui.py an.
#
# Im Terminal-Modus bleibt die bisherige Abfrage erhalten.
# --------------------------------------------------------

if [[ "${SCAN_GUI_MODE:-0}" == "1" ]]; then

    echo "__SCAN_PROMPT_MORE__"
    read -r MORE

else

    read -r -p \
        "Weitere Seiten zu diesem Dokument hinzufügen? [j/N]: " \
        MORE

fi


case "${MORE,,}" in

    j|ja|y|yes)
        ;;

    *)
        break
        ;;

esac

done

# ------------------------------------------------------------
# Scan-Seiten erfassen
# ------------------------------------------------------------

shopt -s nullglob
SCAN_PAGES=( "$WORKDIR"/page-*.pnm )
shopt -u nullglob

if (( ${#SCAN_PAGES[@]} == 0 )); then
    echo "Keine Seiten vorhanden."
    exit 1
fi

# ------------------------------------------------------------
# Zielverzeichnis
# ------------------------------------------------------------

YEAR="$(date +%Y)"
RAW_DIR="${RAW_BASE}/${YEAR}"

mkdir -p "$RAW_DIR"

# ------------------------------------------------------------
# Dateiname
# ------------------------------------------------------------

SCAN_DATE="$(date +%d.%m.%y)"
BASENAME="${SCAN_DATE}_scan_original"

OUTPUT="${RAW_DIR}/${BASENAME}.pdf"

if [[ -e "$OUTPUT" ]]; then

    COUNTER=1

    while true; do

        printf -v SUFFIX "%02d" "$COUNTER"

        OUTPUT="${RAW_DIR}/${BASENAME}_${SUFFIX}.pdf"

        if [[ ! -e "$OUTPUT" ]]; then
            break
        fi

        (( COUNTER += 1 ))

    done

fi

# ------------------------------------------------------------
# PNM -> TIFF
# ------------------------------------------------------------

echo
echo "Bereite PDF vor ..."

TIFF_DIR="${WORKDIR}/tiff"

mkdir -p "$TIFF_DIR"

for PAGE in "${SCAN_PAGES[@]}"; do

    NAME="$(basename "$PAGE" .pnm)"

    magick "$PAGE" \
        -units PixelsPerInch \
        -density "$RESOLUTION" \
        -compress LZW \
        "${TIFF_DIR}/${NAME}.tif"

done

# ------------------------------------------------------------
# TIFF-Dateien erfassen
# ------------------------------------------------------------

shopt -s nullglob
TIFF_PAGES=( "$TIFF_DIR"/page-*.tif )
shopt -u nullglob

if (( ${#TIFF_PAGES[@]} == 0 )); then
    echo "Fehler: Es wurden keine TIFF-Seiten erzeugt."
    exit 1
fi

# ------------------------------------------------------------
# Mehrseitiges TIFF
# ------------------------------------------------------------

MULTIPAGE_TIFF="${WORKDIR}/document.tif"

echo
echo "Fasse TIFF-Seiten zusammen ..."

tiffcp \
    "${TIFF_PAGES[@]}" \
    "$MULTIPAGE_TIFF"

# ------------------------------------------------------------
# PDF erzeugen
# ------------------------------------------------------------

echo
echo "Erzeuge Roh-PDF ..."

tiff2pdf \
    -z \
    -p A4 \
    -o "$OUTPUT" \
    "$MULTIPAGE_TIFF"

# ------------------------------------------------------------
# Ergebnis prüfen
# ------------------------------------------------------------

if [[ ! -s "$OUTPUT" ]]; then

    echo
    echo "Fehler: PDF wurde nicht korrekt erzeugt."
    exit 1

fi

# ------------------------------------------------------------
# Ergebnis
# ------------------------------------------------------------

echo
echo "------------------------------------------------------------"
echo "Scan abgeschlossen."
echo "------------------------------------------------------------"
echo
echo "Gespeichert unter:"
echo
echo "$OUTPUT"
echo
echo "Seiten: ${#SCAN_PAGES[@]}"
echo
