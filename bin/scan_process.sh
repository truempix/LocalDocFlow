#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# LocalDocFlow - Dokumentverarbeitung
#
# Aufgaben:
#
#   1. Rohscan per OCR verarbeiten
#   2. PDF/A-2b erzeugen
#   3. Dokumentdatum erkennen
#   4. Absender erkennen
#   5. Titel / Betreff per KI bestimmen
#   6. Dokumenttyp / Kategorie bestimmen
#   7. sinnvollen Dateinamen erzeugen
#   8. gelernte Ablageregeln prüfen
#   9. normales Mapping prüfen
#  10. Dokument möglichst sinnvoll ablegen
#  11. Lerninformationen speichern
#
# Grundprinzip:
#
#   Gute Benennung ist wichtiger als maximale Ablagetiefe.
#
#   Gelernte Korrekturen haben Vorrang vor dem normalen
#   mapping.json.
#
#   Die KI darf niemals selbst Ordner erzeugen.
#
#   Der Inhalt des Originals unter Archiv/Rohscans bleibt
#   unangetastet. Nach erfolgreicher Analyse darf lediglich
#   der Dateiname aussagekräftig umbenannt werden.
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
# Benötigte Systemwerte prüfen
# ------------------------------------------------------------

: "${DOCUMENT_ROOT:?DOCUMENT_ROOT fehlt in system.conf}"
: "${OCR_DIR:?OCR_DIR fehlt in system.conf}"
: "${CABINET_DIR:?CABINET_DIR fehlt in system.conf}"
: "${OCR_LANGUAGES:?OCR_LANGUAGES fehlt in system.conf}"
: "${OLLAMA_URL:?OLLAMA_URL fehlt in system.conf}"
: "${OLLAMA_MODEL:?OLLAMA_MODEL fehlt in system.conf}"


# ------------------------------------------------------------
# Interne / fachliche Konfiguration
# ------------------------------------------------------------

BASE_DIR="$DOCUMENT_ROOT"

SENDERS_CONFIG="${CONFIG_DIR}/senders.json"
TYPES_CONFIG="${CONFIG_DIR}/document_types.json"
MAPPING_CONFIG="${CONFIG_DIR}/mapping.json"
LEARNING_CONFIG="${CONFIG_DIR}/learning_config.json"


# ============================================================
# Eingabe prüfen
# ============================================================

if [[ $# -ne 1 ]]; then
    echo "Verwendung:"
    echo "  $0 /pfad/zum/scan.pdf"
    exit 1
fi

INPUT="$1"

if [[ ! -f "$INPUT" ]]; then
    echo "Fehler: Eingabedatei existiert nicht:"
    echo "$INPUT"
    exit 1
fi

case "${INPUT,,}" in
    *.pdf)
        ;;
    *)
        echo "Fehler: Eingabedatei ist keine PDF-Datei."
        exit 1
        ;;
esac


# ============================================================
# Benötigte Programme prüfen
# ============================================================

for CMD in \
    ocrmypdf \
    pdfinfo \
    pdftotext \
    jq \
    curl \
    grep \
    sed \
    tr \
    date \
    sha256sum
do

    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "Fehler: '$CMD' wurde nicht gefunden."
        exit 1
    fi

done


# ============================================================
# Konfigurationsdateien prüfen
# ============================================================

for FILE in \
    "$SENDERS_CONFIG" \
    "$TYPES_CONFIG" \
    "$MAPPING_CONFIG" \
    "$LEARNING_CONFIG"
do

    if [[ ! -f "$FILE" ]]; then
        echo "Fehler: Konfigurationsdatei fehlt:"
        echo "$FILE"
        exit 1
    fi

    if ! jq empty "$FILE" >/dev/null 2>&1; then
        echo "Fehler: Ungültige JSON-Datei:"
        echo "$FILE"
        exit 1
    fi

done


# ============================================================
# Lernsystem-Pfade
#
# Rechnerabhängige Pfade kommen jetzt aus system.conf.
# learning_config.json enthält später nur noch fachliche
# Lernregeln.
# ============================================================

: "${LEARNING_ROOT:?LEARNING_ROOT fehlt in system.conf}"
: "${PENDING_LEARNING_FILE:?PENDING_LEARNING_FILE fehlt in system.conf}"
: "${LEARNING_RULES_FILE:?LEARNING_RULES_FILE fehlt in system.conf}"

PENDING_FILE="$PENDING_LEARNING_FILE"
LEARNING_FILE="$LEARNING_RULES_FILE"


if [[ ! -f "$PENDING_FILE" ]]; then
    echo "Fehler: pending_learning.json fehlt:"
    echo "$PENDING_FILE"
    exit 1
fi

if [[ ! -f "$LEARNING_FILE" ]]; then
    echo "Fehler: learning.json fehlt:"
    echo "$LEARNING_FILE"
    exit 1
fi


# ============================================================
# OCR-Verzeichnis prüfen
# ============================================================

if [[ ! -d "$OCR_DIR" ]]; then
    echo "Fehler: OCR-Verzeichnis existiert nicht:"
    echo "$OCR_DIR"
    exit 1
fi


# ============================================================
# Temporären OCR-Dateinamen erzeugen
# ============================================================

INPUT_NAME="$(basename "$INPUT")"
BASE_NAME="${INPUT_NAME%.pdf}"

OUTPUT="${OCR_DIR}/${BASE_NAME}_ocr.pdf"

if [[ -e "$OUTPUT" ]]; then

    COUNTER=1

    while true; do

        printf -v SUFFIX "%02d" "$COUNTER"

        OUTPUT="${OCR_DIR}/${BASE_NAME}_ocr_${SUFFIX}.pdf"

        [[ ! -e "$OUTPUT" ]] && break

        (( COUNTER += 1 ))

    done

fi


# ============================================================
# Arbeitsverzeichnis
# ============================================================

WORKDIR="$(mktemp -d /tmp/scan-process.XXXXXX)"

cleanup() {
    rm -rf "$WORKDIR"
}

trap cleanup EXIT

TEMP_OUTPUT="${WORKDIR}/ocr.pdf"

TEXT_FILE="${WORKDIR}/text.txt"
FIRST_PAGE_FILE="${WORKDIR}/first-page.txt"
HEADER_FILE="${WORKDIR}/header.txt"


# ============================================================
# OCR / PDF-A
# ============================================================

echo
echo "------------------------------------------------------------"
echo "OCR-Verarbeitung"
echo "------------------------------------------------------------"
echo
echo "Eingabe:"
echo "  $INPUT"
echo

ocrmypdf \
    --language "$OCR_LANGUAGES" \
    --rotate-pages \
    --deskew \
    --output-type pdfa-2 \
    --optimize 1 \
    "$INPUT" \
    "$TEMP_OUTPUT"

if [[ ! -s "$TEMP_OUTPUT" ]]; then

    echo "Fehler:"
    echo "OCRmyPDF hat keine gültige Datei erzeugt."

    exit 1
fi

mv "$TEMP_OUTPUT" "$OUTPUT"


# ============================================================
# OCR-Text extrahieren
# ============================================================

pdftotext -layout "$OUTPUT" "$TEXT_FILE"


# ------------------------------------------------------------
# Komplette erste Seite
# ------------------------------------------------------------

awk '
    /\f/ { exit }
    { print }
' "$TEXT_FILE" > "$FIRST_PAGE_FILE"


# ------------------------------------------------------------
# Oberer Dokumentbereich
#
# Wird als zweiter Suchbereich für Datumsangaben verwendet.
# ------------------------------------------------------------

head -n 25 "$FIRST_PAGE_FILE" > "$HEADER_FILE"


# ============================================================
# Datumsfunktionen
# ============================================================

month_number() {

    case "${1,,}" in

        januar)
            echo "01"
            ;;

        februar)
            echo "02"
            ;;

        märz|maerz)
            echo "03"
            ;;

        april)
            echo "04"
            ;;

        mai)
            echo "05"
            ;;

        juni)
            echo "06"
            ;;

        juli)
            echo "07"
            ;;

        august)
            echo "08"
            ;;

        september)
            echo "09"
            ;;

        oktober)
            echo "10"
            ;;

        november)
            echo "11"
            ;;

        dezember)
            echo "12"
            ;;

        *)
            return 1
            ;;

    esac
}


# ============================================================
# Numerisches Datum validieren
#
# Ausgabe:
#
#   DD.MM.YY
# ============================================================

normalize_numeric_date() {

    local DAY="$1"
    local MONTH="$2"
    local YEAR="$3"

    local DAY_NUM
    local MONTH_NUM
    local YEAR_NUM


    # 10# verhindert Bash-Oktalprobleme bei 08 / 09.

    DAY_NUM=$((10#$DAY))
    MONTH_NUM=$((10#$MONTH))
    YEAR_NUM=$((10#$YEAR))


    if (( YEAR_NUM < 100 )); then

        if (( YEAR_NUM <= 69 )); then
            YEAR_NUM=$((2000 + YEAR_NUM))
        else
            YEAR_NUM=$((1900 + YEAR_NUM))
        fi

    fi


    if (( DAY_NUM < 1 || DAY_NUM > 31 )); then
        return 1
    fi

    if (( MONTH_NUM < 1 || MONTH_NUM > 12 )); then
        return 1
    fi


    date \
        -d "$(
            printf '%04d-%02d-%02d' \
                "$YEAR_NUM" \
                "$MONTH_NUM" \
                "$DAY_NUM"
        )" \
        '+%d.%m.%y' \
        2>/dev/null
}


# ============================================================
# Zeilen mit ungeeigneten Datumsarten ausschließen
# ============================================================

is_excluded_date_line() {

    local LINE="${1,,}"

    case "$LINE" in

        *geburtsdatum*|\
        *geboren*|\
        *geburt*|\
        *patient*|\
        *verfall*|\
        *gültig\ bis*|\
        *gueltig\ bis*|\
        *charge*|\
        *mindesthaltbar*|\
        *haltbar\ bis*|\
        *vertragsbeginn*|\
        *vertragsende*)
            return 0
            ;;

    esac

    return 1
}


# ============================================================
# Prüfen, ob eine Zeile ausdrücklich ein Dokumentdatum
# bezeichnet.
#
# Beispiele:
#
#   Datum:
#   Rechnungsdatum:
#   Belegdatum:
#   Ausstellungsdatum:
#   Briefdatum:
#   Schreibdatum:
#
# "Geburtsdatum" wird durch den Wortvergleich nicht als
# allgemeines "Datum" behandelt.
# ============================================================

is_explicit_date_line() {

    local LINE="$1"

    printf '%s\n' "$LINE" |
        grep -Eqi \
        '(^|[^[:alnum:]_])(Rechnungsdatum|Belegdatum|Ausstellungsdatum|Briefdatum|Schreibdatum|Datum)([^[:alnum:]_]|$)'
}


# ============================================================
# Beliebiges Datum aus EINER Zeile extrahieren
#
# Unterstützt:
#
#   31.07.2026
#   31-07-2026
#   31/07/2026
#
#   2026-07-31
#
#   31. Juli 2026
# ============================================================

extract_date_from_line() {

    local LINE="$1"
    local LINE_LOWER="${LINE,,}"

    local DAY
    local MONTH
    local YEAR

    local MONTH_WORD
    local NORMALIZED


    # --------------------------------------------------------
    # DD.MM.YYYY / DD-MM-YYYY / DD/MM/YYYY
    # --------------------------------------------------------

    if [[ "$LINE" =~ ([0-3]?[0-9])[./-]([01]?[0-9])[./-]([12][0-9]{3}|[0-9]{2}) ]]; then

        DAY="${BASH_REMATCH[1]}"
        MONTH="${BASH_REMATCH[2]}"
        YEAR="${BASH_REMATCH[3]}"

        if NORMALIZED="$(
            normalize_numeric_date \
                "$DAY" \
                "$MONTH" \
                "$YEAR"
        )"; then

            echo "$NORMALIZED"
            return 0
        fi

    fi


    # --------------------------------------------------------
    # YYYY-MM-DD
    # --------------------------------------------------------

    if [[ "$LINE" =~ ([12][0-9]{3})-([01][0-9])-([0-3][0-9]) ]]; then

        YEAR="${BASH_REMATCH[1]}"
        MONTH="${BASH_REMATCH[2]}"
        DAY="${BASH_REMATCH[3]}"

        if NORMALIZED="$(
            normalize_numeric_date \
                "$DAY" \
                "$MONTH" \
                "$YEAR"
        )"; then

            echo "$NORMALIZED"
            return 0
        fi

    fi


    # --------------------------------------------------------
    # 31. Juli 2026
    # --------------------------------------------------------

    if [[ "$LINE_LOWER" =~ ([0-3]?[0-9])[\.\ ]+[[:space:]]*(januar|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember)[[:space:]]+([12][0-9]{3}) ]]; then

        DAY="${BASH_REMATCH[1]}"
        MONTH_WORD="${BASH_REMATCH[2]}"
        YEAR="${BASH_REMATCH[3]}"

        if MONTH="$(
            month_number "$MONTH_WORD"
        )"; then

            if NORMALIZED="$(
                normalize_numeric_date \
                    "$DAY" \
                    "$MONTH" \
                    "$YEAR"
            )"; then

                echo "$NORMALIZED"
                return 0

            fi

        fi

    fi


    return 1
}

# ============================================================
# Monat/Jahr aus einer Zeile extrahieren
#
# Unterstützt beispielsweise:
#
#   August 2026
#   im August 2026
#   München, im August 2026
#   08.2026
#   08/2026
#
# Ausgabe:
#
#   MM.YYYY
#
# Wichtig:
# Enthält die Zeile bereits ein vollständiges Datum mit Tag,
# wird dieses hier NICHT als bloßes Monat/Jahr interpretiert.
# ============================================================

extract_month_year_from_line() {

    local LINE="$1"
    local LINE_LOWER="${LINE,,}"

    local MONTH
    local MONTH_WORD
    local YEAR
    local YEAR_NUM


    # --------------------------------------------------------
    # Zeilen mit vollständigem Datum nicht als Monatsdatum
    # interpretieren.
    # --------------------------------------------------------

    if [[ "$LINE" =~ ([0-3]?[0-9])[./-]([01]?[0-9])[./-]([12][0-9]{3}|[0-9]{2}) ]]; then
        return 1
    fi


    if [[ "$LINE" =~ ([12][0-9]{3})-([01][0-9])-([0-3][0-9]) ]]; then
        return 1
    fi


    # --------------------------------------------------------
    # August 2026 / August 26
    # --------------------------------------------------------

    if [[ "$LINE_LOWER" =~ (januar|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember)[[:space:]]+([12][0-9]{3}|[0-9]{2}) ]]; then

        MONTH_WORD="${BASH_REMATCH[1]}"
        YEAR="${BASH_REMATCH[2]}"


        if ! MONTH="$(
            month_number "$MONTH_WORD"
        )"; then
            return 1
        fi


        YEAR_NUM=$((10#$YEAR))


        if (( YEAR_NUM < 100 )); then

            if (( YEAR_NUM <= 69 )); then
                YEAR_NUM=$((2000 + YEAR_NUM))
            else
                YEAR_NUM=$((1900 + YEAR_NUM))
            fi

        fi


        printf '%02d.%04d\n' \
            "$((10#$MONTH))" \
            "$YEAR_NUM"

        return 0
    fi


    # --------------------------------------------------------
    # 08.2026 / 08/2026 / 08-2026
    # --------------------------------------------------------

    if [[ "$LINE" =~ (^|[^0-9])([01]?[0-9])[./-]([12][0-9]{3}|[0-9]{2})([^0-9]|$) ]]; then

        MONTH="${BASH_REMATCH[2]}"
        YEAR="${BASH_REMATCH[3]}"

        MONTH=$((10#$MONTH))
        YEAR_NUM=$((10#$YEAR))


        if (( MONTH < 1 || MONTH > 12 )); then
            return 1
        fi


        if (( YEAR_NUM < 100 )); then

            if (( YEAR_NUM <= 69 )); then
                YEAR_NUM=$((2000 + YEAR_NUM))
            else
                YEAR_NUM=$((1900 + YEAR_NUM))
            fi

        fi


        printf '%02d.%04d\n' \
            "$MONTH" \
            "$YEAR_NUM"

        return 0
    fi


    return 1
}


# ============================================================
# Prüfen, ob eine Monatsangabe ausdrücklich als
# Dokumentdatierung erscheint.
#
# Beispiele:
#
#   Datum: August 2026
#   Rechnungsdatum: 08.2026
#   München, im August 2026
#
# "im August 2026" behandeln wir als typische Datierung
# eines Briefes, auch wenn kein Tag angegeben wurde.
# ============================================================

is_explicit_month_year_line() {

    local LINE="$1"


    # Normale Datumsbezeichnungen

    if is_explicit_date_line "$LINE"; then
        return 0
    fi


    # Typische Briefdatierung:
    # "München, im August 2026"

    printf '%s\n' "$LINE" |
        grep -Eqi \
        '(^|[^[:alnum:]_])im[[:space:]]+(Januar|Februar|März|Maerz|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)[[:space:]]+([12][0-9]{3}|[0-9]{2})([^[:alnum:]_]|$)'
}
# ============================================================
# Dokumentdatum erkennen
#
# PRIORITÄT:
#
#   1. Explizites vollständiges Dokumentdatum auf der
#      gesamten ersten Seite
#
#      Beispiel:
#          Datum: 31.07.2026
#
#   2. Explizite Datierung nur mit Monat/Jahr
#
#      Beispiele:
#          Datum: August 2026
#          München, im August 2026
#
#   3. Allgemeines vollständiges Datum im oberen Bereich
#
#   4. Allgemeines Monat/Jahr im oberen Bereich
#
#   5. Scan-Datum als späterer Fallback
#
# Ausgabe:
#
#   DATUM|QUELLE
#
# Beispiele:
#
#   31.07.26|Dokument
#   08.2026|Dokument (Monat)
# ============================================================

detect_document_date() {

    local LINE
    local NORMALIZED


    # --------------------------------------------------------
    # 1. Gesamte erste Seite:
    #    ausdrücklich bezeichnetes vollständiges Datum
    # --------------------------------------------------------

    while IFS= read -r LINE; do

        [[ -z "${LINE//[[:space:]]/}" ]] && continue


        if is_excluded_date_line "$LINE"; then
            continue
        fi


        if ! is_explicit_date_line "$LINE"; then
            continue
        fi


        if NORMALIZED="$(
            extract_date_from_line "$LINE"
        )"; then

            printf '%s|Dokument\n' "$NORMALIZED"
            return 0

        fi

    done < "$FIRST_PAGE_FILE"


    # --------------------------------------------------------
    # 2. Gesamte erste Seite:
    #    ausdrückliche Datierung nur mit Monat und Jahr
    #
    #    Dadurch wird z.B.
    #
    #      München, im August 2026
    #
    #    korrekt als Dokumentdatierung erkannt.
    # --------------------------------------------------------

    while IFS= read -r LINE; do

        [[ -z "${LINE//[[:space:]]/}" ]] && continue


        if is_excluded_date_line "$LINE"; then
            continue
        fi


        if ! is_explicit_month_year_line "$LINE"; then
            continue
        fi


        if NORMALIZED="$(
            extract_month_year_from_line "$LINE"
        )"; then

            printf '%s|Dokument (Monat)\n' "$NORMALIZED"
            return 0

        fi

    done < "$FIRST_PAGE_FILE"


    # --------------------------------------------------------
    # 3. Allgemeines vollständiges Datum nur im oberen
    #    Dokumentbereich
    # --------------------------------------------------------

    while IFS= read -r LINE; do

        [[ -z "${LINE//[[:space:]]/}" ]] && continue


        if is_excluded_date_line "$LINE"; then
            continue
        fi


        if NORMALIZED="$(
            extract_date_from_line "$LINE"
        )"; then

            printf '%s|Dokument\n' "$NORMALIZED"
            return 0

        fi

    done < "$HEADER_FILE"


    # --------------------------------------------------------
    # 4. Allgemeines Monat/Jahr nur im oberen Bereich
    #
    #    Das fängt beispielsweise einen Briefkopf ab, der nur
    #
    #      August 2026
    #
    #    enthält.
    # --------------------------------------------------------

    while IFS= read -r LINE; do

        [[ -z "${LINE//[[:space:]]/}" ]] && continue


        if is_excluded_date_line "$LINE"; then
            continue
        fi


        if NORMALIZED="$(
            extract_month_year_from_line "$LINE"
        )"; then

            printf '%s|Dokument (Monat)\n' "$NORMALIZED"
            return 0

        fi

    done < "$HEADER_FILE"


    return 1
}

# ============================================================
# Generische Regelerkennung aus JSON
# ============================================================

detect_from_config() {

    local CONFIG_FILE="$1"
    local ARRAY_NAME="$2"
    local SEARCH_FILE="$3"

    local ENTRY
    local NAME
    local PATTERN


    while IFS= read -r ENTRY; do

        NAME="$(
            jq -r '.name' <<< "$ENTRY"
        )"


        while IFS= read -r PATTERN; do

            [[ -z "$PATTERN" ]] && continue


            if grep \
                -Eqi \
                -- "$PATTERN" \
                "$SEARCH_FILE"
            then

                echo "$NAME"
                return 0

            fi

        done < <(
            jq -r '.patterns[]' <<< "$ENTRY"
        )


    done < <(
        jq \
            -c \
            --arg ARRAY "$ARRAY_NAME" \
            '.[$ARRAY][]' \
            "$CONFIG_FILE"
    )


    return 1
}


# ============================================================
# Bekannten Absender erkennen
# ============================================================

detect_sender() {

    local RESULT


    # Briefkopf bevorzugen

    if RESULT="$(
        detect_from_config \
            "$SENDERS_CONFIG" \
            "senders" \
            "$HEADER_FILE"
    )"; then

        echo "$RESULT"
        return 0

    fi


    # Danach gesamtes Dokument

    if RESULT="$(
        detect_from_config \
            "$SENDERS_CONFIG" \
            "senders" \
            "$TEXT_FILE"
    )"; then

        echo "$RESULT"
        return 0

    fi


    return 1
}


# ============================================================
# Bekannten Dokumenttyp erkennen
# ============================================================

detect_document_type() {

    detect_from_config \
        "$TYPES_CONFIG" \
        "document_types" \
        "$TEXT_FILE"
}


# ============================================================
# Ollama prüfen
# ============================================================

ollama_available() {

    curl \
        -fsS \
        --max-time 3 \
        "${OLLAMA_URL}/api/version" \
        >/dev/null 2>&1
}


# ============================================================
# Unbrauchbare KI-Werte erkennen
# ============================================================

is_bad_ai_value() {

    local VALUE="$1"
    local VALUE_LOWER="${VALUE,,}"

    local ALNUM


    case "$VALUE_LOWER" in

        ""|\
        null|\
        unbekannt|\
        unknown|\
        dokument|\
        dokumenttyp|\
        titel|\
        betreff|\
        absender|\
        sender|\
        kategorie|\
        unterkategorie|\
        n/a|\
        "nicht erkannt"|\
        "...")
            return 0
            ;;

    esac


    ALNUM="$(
        printf '%s' "$VALUE" |
        tr -cd '[:alnum:]ÄÖÜäöüß'
    )"


    if (( ${#ALNUM} < 2 )); then
        return 0
    fi


    return 1
}


# ============================================================
# Allgemeine KI-Dokumentanalyse
# ============================================================

analyse_with_ai() {

    local KNOWN_SENDER="$1"
    local KNOWN_TYPE="$2"
    local ATTEMPT="${3:-1}"

    local DOCUMENT_TEXT
    local PROMPT
    local REQUEST
    local RESPONSE
    local CONTENT


    if [[ "$ATTEMPT" == "1" ]]; then

        DOCUMENT_TEXT="$(
            head -c 14000 "$TEXT_FILE"
        )"

    else

        DOCUMENT_TEXT="$(
            head -c 22000 "$TEXT_FILE"
        )"

    fi


    PROMPT=$(cat <<EOF
Analysiere den OCR-Text eines gescannten Dokuments.

Bereits erkannter Absender:
$KNOWN_SENDER

Bereits erkannter Dokumenttyp:
$KNOWN_TYPE

Aufgabe:

1. Ermittle den tatsächlichen Absender.
2. Erzeuge einen kurzen, aussagekräftigen Titel bzw. Betreff.
3. Ermittle den konkreten Dokumenttyp.
4. Ermittle eine grobe Kategorie.
5. Ermittle eine sinnvolle Unterkategorie.
6. Ermittle die Versicherungsnummer, falls sie ausdrücklich im Dokument steht.
   Sonst verwende für insurance_number eine leere Zeichenfolge.

Der Titel ist besonders wichtig, weil daraus der Dateiname erzeugt wird.

Gute Titel sind zum Beispiel:

Kreditantrag Modernisierung
Rechnung August
Jahresabrechnung Strom
Kontoauszug Girokonto
Beitragsbescheid Krankenversicherung
Tierärztliche Behandlung
Versicherungsschreiben Mazda 5

Regeln:

- Der Titel soll ca. 2 bis 6 Wörter lang sein.
- Keine vollständigen Sätze.
- Datum nicht in den Titel schreiben.
- Absender nicht unnötig im Titel wiederholen.
- Keine Platzhalter wie Dokument, Dokumenttyp, Titel, Betreff oder "...".
- Bereits sicher bekannte Werte möglichst beibehalten.
- Nichts erfinden, was im Dokument nicht erkennbar ist.
- confidence muss high, medium oder low sein.

Mögliche grobe Kategorien sind zum Beispiel:

Bank
Versicherung
Gesundheit
Arbeit
Steuer
Haus
Telekommunikation
Fahrzeug
Schule
Einkauf
Sonstiges

Antworte ausschließlich als gültiges JSON.

OCR-TEXT:

$DOCUMENT_TEXT
EOF
)


    if [[ "$ATTEMPT" == "2" ]]; then

        PROMPT="${PROMPT}

Dies ist ein zweiter Analyseversuch.
Prüfe besonders Überschrift, Betreff, Formularbezeichnung
und den oberen Bereich des Dokuments."

    fi


    REQUEST="$(
        jq -n \
            --arg MODEL "$OLLAMA_MODEL" \
            --arg PROMPT "$PROMPT" \
            '{
                model: $MODEL,
                stream: false,
                think: false,
                format: "json",
                options: {
                    temperature: 0
                },
                messages: [
                    {
                        role: "system",
                        content: "Analysiere das Dokument. Liefere die Felder sender, title, document_type, category, subcategory, insurance_number und confidence als gültiges JSON."
                    },
                    {
                        role: "user",
                        content: $PROMPT
                    }
                ]
            }'
    )"


    RESPONSE="$(
        curl \
            -fsS \
            --max-time 240 \
            "${OLLAMA_URL}/api/chat" \
            -H 'Content-Type: application/json' \
            -d "$REQUEST"
    )" || return 1


    CONTENT="$(
        jq -er '.message.content' <<< "$RESPONSE"
    )" || return 1


    jq empty \
        <<< "$CONTENT" \
        >/dev/null 2>&1 \
        || return 1


    printf '%s\n' "$CONTENT"
}


# ============================================================
# KI-Analyse mit Retry
# ============================================================

analyse_with_ai_retry() {

    local KNOWN_SENDER="$1"
    local KNOWN_TYPE="$2"

    local RESULT


    if RESULT="$(
        analyse_with_ai \
            "$KNOWN_SENDER" \
            "$KNOWN_TYPE" \
            1
    )"; then

        echo "$RESULT"
        return 0

    fi


    echo \
        "Erster KI-Versuch nicht verwertbar." \
        >&2

    echo \
        "Starte zweiten Versuch ..." \
        >&2


    if RESULT="$(
        analyse_with_ai \
            "$KNOWN_SENDER" \
            "$KNOWN_TYPE" \
            2
    )"; then

        echo "$RESULT"
        return 0

    fi


    return 1
}


# ============================================================
# Gezielte Titel-Erkennung
# ============================================================

detect_title_with_ai() {

    local DOCUMENT_TEXT
    local PROMPT
    local REQUEST
    local RESPONSE
    local CONTENT

    local DETECTED_TITLE
    local DETECTED_CONFIDENCE


    DOCUMENT_TEXT="$(
        head -c 18000 "$TEXT_FILE"
    )"


    PROMPT=$(cat <<EOF
Ermittle ausschließlich einen kurzen und aussagekräftigen Titel
für dieses Dokument.

Bekannter Absender:
$SENDER

Bereits erkannter Dokumenttyp:
$DOCUMENT_TYPE

Der Titel wird direkt für einen Dateinamen verwendet.

Beispiele:

Kreditantrag Modernisierung
Rechnung August
Jahresabrechnung Strom
Kontoauszug Girokonto
Beitragsbescheid Krankenversicherung
Versicherung Mazda 5
Tierärztliche Behandlung

Regeln:

- 2 bis ungefähr 6 Wörter
- keine vollständigen Sätze
- kein Datum
- Absender nicht unnötig wiederholen
- keine Platzhalter
- benutze nur Informationen aus dem OCR-Text

Liefere ausschließlich gültiges JSON mit:

title
confidence

OCR-TEXT:

$DOCUMENT_TEXT
EOF
)


    REQUEST="$(
        jq -n \
            --arg MODEL "$OLLAMA_MODEL" \
            --arg PROMPT "$PROMPT" \
            '{
                model: $MODEL,
                stream: false,
                think: false,
                format: "json",
                options: {
                    temperature: 0
                },
                messages: [
                    {
                        role: "system",
                        content: "Extrahiere einen kurzen Dokumenttitel. Liefere title und confidence als JSON."
                    },
                    {
                        role: "user",
                        content: $PROMPT
                    }
                ]
            }'
    )"


    RESPONSE="$(
        curl \
            -fsS \
            --max-time 240 \
            "${OLLAMA_URL}/api/chat" \
            -H 'Content-Type: application/json' \
            -d "$REQUEST"
    )" || return 1


    CONTENT="$(
        jq -er '.message.content' <<< "$RESPONSE"
    )" || return 1


    jq empty \
        <<< "$CONTENT" \
        >/dev/null 2>&1 \
        || return 1


    DETECTED_TITLE="$(
        jq -r \
            '.title // empty' \
            <<< "$CONTENT"
    )"


    DETECTED_CONFIDENCE="$(
        jq -r \
            '.confidence // "low"' \
            <<< "$CONTENT" |
        tr \
            '[:upper:]' \
            '[:lower:]'
    )"


    if is_bad_ai_value "$DETECTED_TITLE"; then
        return 1
    fi


    case "$DETECTED_CONFIDENCE" in

        high|medium|low)
            ;;

        *)
            DETECTED_CONFIDENCE="low"
            ;;

    esac


    printf '%s|%s\n' \
        "$DETECTED_TITLE" \
        "$DETECTED_CONFIDENCE"
}


# ============================================================
# Dateinamensbestandteile bereinigen
# ============================================================

sanitize_filename_part() {

    local VALUE="$1"

    printf '%s' "$VALUE" |
        sed 's/[[:space:]]\+/_/g' |
        sed 's#[/\\:*?"<>|]#_#g' |
        sed 's/__*/_/g' |
        sed 's/^_//' |
        sed 's/_$//'
}


# ============================================================
# Kollisionsfreien Dateinamen bestimmen
# ============================================================

unique_destination() {

    local DIRECTORY="$1"
    local FILENAME="$2"

    local STEM="${FILENAME%.pdf}"
    local DEST="${DIRECTORY}/${FILENAME}"

    local COUNTER=1
    local SUFFIX


    if [[ ! -e "$DEST" ]]; then

        echo "$DEST"
        return 0

    fi


    while true; do

        printf -v SUFFIX \
            "%02d" \
            "$COUNTER"

        DEST="${DIRECTORY}/${STEM}_${SUFFIX}.pdf"


        if [[ ! -e "$DEST" ]]; then

            echo "$DEST"
            return 0

        fi


        (( COUNTER += 1 ))

    done
}


# ============================================================
# Dokumentdatum bestimmen
#
# detect_document_date liefert sowohl den Wert als auch die
# Genauigkeit/Quelle:
#
#   31.07.26|Dokument
#
# oder:
#
#   08.2026|Dokument (Monat)
# ============================================================

if DATE_RESULT="$(
    detect_document_date
)"; then

    DOCUMENT_DATE="${DATE_RESULT%%|*}"
    DATE_SOURCE="${DATE_RESULT#*|}"

else

    DOCUMENT_DATE="$(
        date +%d.%m.%y
    )"

    DATE_SOURCE="Scan-Datum (Fallback)"

fi


# ============================================================
# Dokumentjahr bestimmen
#
# Unterstützt:
#
#   DD.MM.YY
#   MM.YYYY
#
# Das Jahr wird unter anderem benötigt, um einen bereits
# existierenden Jahresunterordner zu verwenden.
# ============================================================

if [[ "$DOCUMENT_DATE" =~ ^[0-9]{2}\.[0-9]{2}\.([0-9]{2})$ ]]; then

    DATE_YEAR="${BASH_REMATCH[1]}"


    if (( 10#$DATE_YEAR <= 69 )); then
        DOCUMENT_YEAR="20${DATE_YEAR}"
    else
        DOCUMENT_YEAR="19${DATE_YEAR}"
    fi


elif [[ "$DOCUMENT_DATE" =~ ^[0-9]{2}\.([0-9]{4})$ ]]; then

    DOCUMENT_YEAR="${BASH_REMATCH[1]}"


else

    DOCUMENT_YEAR="$(
        date +%Y
    )"

fi


# ============================================================
# Regelbasierte Voranalyse
# ============================================================

if SENDER="$(
    detect_sender
)"; then

    SENDER_SOURCE="Regeldatei"

else

    SENDER="Unbekannt"
    SENDER_SOURCE="nicht erkannt"

fi


if DOCUMENT_TYPE="$(
    detect_document_type
)"; then

    TYPE_SOURCE="Regeldatei"

else

    DOCUMENT_TYPE="Dokument"
    TYPE_SOURCE="nicht erkannt"

fi


TITLE=""
CATEGORY=""
SUBCATEGORY=""
INSURANCE_NUMBER=""

AI_CONFIDENCE=""
TITLE_CONFIDENCE=""
AI_USED=false


# ============================================================
# Allgemeine KI-Analyse
# ============================================================

echo
echo "Analysiere Dokumentinhalt mit $OLLAMA_MODEL ..."


if ollama_available; then

    if AI_RESULT="$(
        analyse_with_ai_retry \
            "$SENDER" \
            "$DOCUMENT_TYPE"
    )"; then


        AI_SENDER="$(
            jq -r \
                '.sender // empty' \
                <<< "$AI_RESULT"
        )"


        AI_TITLE="$(
            jq -r \
                '.title // empty' \
                <<< "$AI_RESULT"
        )"


        AI_TYPE="$(
            jq -r \
                '.document_type // empty' \
                <<< "$AI_RESULT"
        )"


        AI_CATEGORY="$(
            jq -r \
                '.category // empty' \
                <<< "$AI_RESULT"
        )"


        AI_SUBCATEGORY="$(
            jq -r \
                '.subcategory // empty' \
                <<< "$AI_RESULT"
        )"

        AI_INSURANCE_NUMBER="$(
            jq -r '.insurance_number // empty | strings' <<< "$AI_RESULT"
        )"

        # Nur eine im OCR-Text tatsächlich vorkommende Nummer übernehmen.
        # Trennzeichen dürfen variieren; Ziffern und Buchstaben müssen gleich sein.
        if [[ -n "$AI_INSURANCE_NUMBER" ]]; then
            NUMBER_NORMALIZED="$(printf '%s' "$AI_INSURANCE_NUMBER" | tr -cd '[:alnum:]' | tr '[:lower:]' '[:upper:]')"
            TEXT_NORMALIZED="$(tr -cd '[:alnum:]' < "$TEXT_FILE" | tr '[:lower:]' '[:upper:]')"
            if (( ${#NUMBER_NORMALIZED} >= 7 )) && [[ "$TEXT_NORMALIZED" == *"$NUMBER_NORMALIZED"* ]]; then
                INSURANCE_NUMBER="$AI_INSURANCE_NUMBER"
            fi
        fi


        AI_CONFIDENCE="$(
            jq -r \
                '.confidence // "low"' \
                <<< "$AI_RESULT" |
            tr \
                '[:upper:]' \
                '[:lower:]'
        )"


        case "$AI_CONFIDENCE" in

            high|medium|low)
                ;;

            *)
                AI_CONFIDENCE="low"
                ;;

        esac


        # ----------------------------------------------------
        # Absender ergänzen
        # ----------------------------------------------------

        if [[ "$SENDER" == "Unbekannt" ]] \
           && ! is_bad_ai_value "$AI_SENDER"
        then

            SENDER="$AI_SENDER"
            SENDER_SOURCE="Ollama"

        fi


        # ----------------------------------------------------
        # Dokumenttyp ergänzen
        # ----------------------------------------------------

        if [[ "$DOCUMENT_TYPE" == "Dokument" ]] \
           && ! is_bad_ai_value "$AI_TYPE"
        then

            DOCUMENT_TYPE="$AI_TYPE"
            TYPE_SOURCE="Ollama"

        fi


        # ----------------------------------------------------
        # Titel
        # ----------------------------------------------------

        if ! is_bad_ai_value "$AI_TITLE"; then

            TITLE="$AI_TITLE"
            TITLE_CONFIDENCE="$AI_CONFIDENCE"

        fi


        # ----------------------------------------------------
        # Kategorie
        # ----------------------------------------------------

        if ! is_bad_ai_value "$AI_CATEGORY"; then
            CATEGORY="$AI_CATEGORY"
        fi


        # ----------------------------------------------------
        # Unterkategorie
        # ----------------------------------------------------

        if ! is_bad_ai_value "$AI_SUBCATEGORY"; then
            SUBCATEGORY="$AI_SUBCATEGORY"
        fi


        AI_USED=true

    else

        echo
        echo "WARNUNG:"
        echo "Allgemeine KI-Analyse lieferte kein verwertbares Ergebnis."

    fi

else

    echo
    echo "WARNUNG: Ollama ist nicht erreichbar."

fi


# ============================================================
# Titel absichern
# ============================================================

if [[ -z "$TITLE" ]]; then

    echo
    echo "Kein brauchbarer Titel aus der ersten Analyse."
    echo "Versuche gezielte Titel-Erkennung ..."


    if ollama_available; then

        if TITLE_RESULT="$(
            detect_title_with_ai
        )"; then

            TITLE="${TITLE_RESULT%%|*}"
            TITLE_CONFIDENCE="${TITLE_RESULT#*|}"

            echo "Titel erkannt: $TITLE"

        else

            echo \
                "WARNUNG: Auch die gezielte Titel-Erkennung ist fehlgeschlagen."

        fi

    fi

fi


# ============================================================
# Titel-Fallback auf Dokumenttyp
# ============================================================

if [[ -z "$TITLE" ]]; then

    if [[ "$DOCUMENT_TYPE" != "Dokument" ]] \
       && ! is_bad_ai_value "$DOCUMENT_TYPE"
    then

        TITLE="$DOCUMENT_TYPE"
        TITLE_CONFIDENCE="fallback"

    fi

fi


# ============================================================
# Sinnvollen Dateinamen erzeugen
# ============================================================

PROPOSED_FILENAME=""

# Versicherungsnummer nur dann in den Dateinamen aufnehmen,
# wenn sie zuvor sicher im Dokument erkannt wurde.
INSURANCE_FILENAME_PART=""

if [[ -n "$INSURANCE_NUMBER" ]]; then

    SAFE_INSURANCE_NUMBER="$(
        sanitize_filename_part "$INSURANCE_NUMBER"
    )"

    if [[ -n "$SAFE_INSURANCE_NUMBER" ]]; then
        INSURANCE_FILENAME_PART="_${SAFE_INSURANCE_NUMBER}"
    fi

fi


if [[ -n "$TITLE" \
   && "$SENDER" != "Unbekannt" ]]
then

    SAFE_SENDER="$(
        sanitize_filename_part "$SENDER"
    )"

    SAFE_TITLE="$(
        sanitize_filename_part "$TITLE"
    )"

    PROPOSED_FILENAME="${DOCUMENT_DATE}_${SAFE_SENDER}${INSURANCE_FILENAME_PART}_${SAFE_TITLE}.pdf"


elif [[ -n "$TITLE" ]]; then

    SAFE_TITLE="$(
        sanitize_filename_part "$TITLE"
    )"

    PROPOSED_FILENAME="${DOCUMENT_DATE}${INSURANCE_FILENAME_PART}_${SAFE_TITLE}.pdf"


elif [[ "$SENDER" != "Unbekannt" ]]; then

    SAFE_SENDER="$(
        sanitize_filename_part "$SENDER"
    )"

    PROPOSED_FILENAME="${DOCUMENT_DATE}_${SAFE_SENDER}${INSURANCE_FILENAME_PART}_Unklar.pdf"

fi


# ============================================================
# Gelernte Ablageregeln
#
# Punkte:
#
#   Absender exakt             +4
#   Titel exakt                +7
#   Titel ähnlich >= 2 Wörter  +5
#   Titel ähnlich 1 Wort       +2
#   Dokumenttyp exakt          +2
#   Kategorie exakt            +2
#   Unterkategorie exakt       +3
#   bevorzugtes Lernziel       +1
#
# Mindestwert: 8
# ============================================================

LEARNING_MIN_SCORE=8


# ============================================================
# Text normalisieren
# ============================================================

normalize_match_text() {

    local VALUE="$1"

    printf '%s' "$VALUE" |
        tr \
            '[:upper:]' \
            '[:lower:]' |
        sed \
            -e 's/ä/ae/g' \
            -e 's/ö/oe/g' \
            -e 's/ü/ue/g' \
            -e 's/ß/ss/g' \
            -e 's/[^[:alnum:]]\+/ /g' \
            -e 's/^[[:space:]]*//' \
            -e 's/[[:space:]]*$//' \
            -e 's/[[:space:]]\+/ /g'
}


# ============================================================
# Lernwert validieren
# ============================================================

learning_value_valid() {

    local VALUE="${1,,}"

    case "$VALUE" in

        ""|\
        null|\
        unbekannt|\
        unknown|\
        dokument|\
        "nicht erkannt"|\
        "...")
            return 1
            ;;

    esac

    return 0
}


# ============================================================
# Exakten Lernwert vergleichen
# ============================================================

learning_exact_match() {

    local CURRENT="$1"
    local LEARNED="$2"

    local CURRENT_NORMALIZED
    local LEARNED_NORMALIZED


    learning_value_valid "$CURRENT" || return 1
    learning_value_valid "$LEARNED" || return 1


    CURRENT_NORMALIZED="$(
        normalize_match_text "$CURRENT"
    )"

    LEARNED_NORMALIZED="$(
        normalize_match_text "$LEARNED"
    )"


    [[ -n "$CURRENT_NORMALIZED" \
       && "$CURRENT_NORMALIZED" == "$LEARNED_NORMALIZED" ]]
}

normalize_insurance_number() {
    printf '%s' "$1" | tr -cd '[:alnum:]' | tr '[:lower:]' '[:upper:]'
}


# ============================================================
# Titelähnlichkeit
# ============================================================

title_match_score() {

    local CURRENT="$1"
    local LEARNED="$2"

    local CURRENT_NORMALIZED
    local LEARNED_NORMALIZED

    local WORD
    local MATCHES=0


    learning_value_valid "$CURRENT" || {
        echo 0
        return
    }


    learning_value_valid "$LEARNED" || {
        echo 0
        return
    }


    CURRENT_NORMALIZED="$(
        normalize_match_text "$CURRENT"
    )"

    LEARNED_NORMALIZED="$(
        normalize_match_text "$LEARNED"
    )"


    if [[ "$CURRENT_NORMALIZED" == "$LEARNED_NORMALIZED" ]]; then

        echo 7
        return

    fi


    CURRENT_NORMALIZED=" ${CURRENT_NORMALIZED} "


    for WORD in $LEARNED_NORMALIZED; do

        # kurze Wörter ignorieren

        if (( ${#WORD} < 4 )); then
            continue
        fi


        if [[ "$CURRENT_NORMALIZED" == *" $WORD "* ]]; then
            (( MATCHES += 1 ))
        fi

    done


    if (( MATCHES >= 2 )); then

        echo 5

    elif (( MATCHES == 1 )); then

        echo 2

    else

        echo 0

    fi
}


# ============================================================
# Bestes gelerntes Ziel bestimmen
# ============================================================

detect_learned_target() {

    local RULE

    local RULE_ID
    local RULE_SENDER
    local RULE_TITLE
    local RULE_TYPE
    local RULE_CATEGORY
    local RULE_SUBCATEGORY
    local RULE_INSURANCE_NUMBER
    local RULE_TARGET
    local RULE_PRIORITY

    local SCORE
    local TITLE_SCORE

    local FULL_TARGET

    local BEST_SCORE=0
    local BEST_ID=""
    local BEST_TARGET=""
    local BEST_PRIORITY=""


    while IFS= read -r RULE; do


        RULE_ID="$(
            jq -r \
                '.id // ""' \
                <<< "$RULE"
        )"


        RULE_SENDER="$(
            jq -r \
                '.sender // ""' \
                <<< "$RULE"
        )"


        RULE_TITLE="$(
            jq -r \
                '.title // ""' \
                <<< "$RULE"
        )"


        RULE_TYPE="$(
            jq -r \
                '.document_type // ""' \
                <<< "$RULE"
        )"


        RULE_CATEGORY="$(
            jq -r \
                '.category // ""' \
                <<< "$RULE"
        )"


        RULE_SUBCATEGORY="$(
            jq -r \
                '.subcategory // ""' \
                <<< "$RULE"
        )"

        RULE_INSURANCE_NUMBER="$(jq -r '.insurance_number // ""' <<< "$RULE")"

        # Bei Versicherungen ist ein allgemeiner Treffer keine sichere
        # Vertragszuordnung. Auch ältere Regeln ohne Nummer bleiben inaktiv.
        if [[ "${CATEGORY,,}" == versicherung || "${RULE_CATEGORY,,}" == versicherung ]]; then
            CURRENT_NUMBER="$(normalize_insurance_number "$INSURANCE_NUMBER")"
            RULE_NUMBER="$(normalize_insurance_number "$RULE_INSURANCE_NUMBER")"
            if (( ${#CURRENT_NUMBER} < 7 || ${#RULE_NUMBER} < 7 )) \
                || [[ "$CURRENT_NUMBER" != "$RULE_NUMBER" ]]; then
                continue
            fi
        fi


        RULE_TARGET="$(
            jq -r \
                '.target // ""' \
                <<< "$RULE"
        )"


        RULE_PRIORITY="$(
            jq -r \
                '.priority // "normal"' \
                <<< "$RULE"
        )"


        [[ -z "$RULE_TARGET" ]] && continue


        # ----------------------------------------------------
        # Zielpfad auflösen
        # ----------------------------------------------------

        if [[ "$RULE_TARGET" == "." ]]; then

            FULL_TARGET="$LEARNING_ROOT"

        else

            FULL_TARGET="${LEARNING_ROOT}/${RULE_TARGET}"

        fi


        [[ -d "$FULL_TARGET" ]] || continue


        # Ziel muss innerhalb Dokumente bleiben

        case "$FULL_TARGET" in

            "$LEARNING_ROOT"|"$LEARNING_ROOT"/*)
                ;;

            *)
                continue
                ;;

        esac


        SCORE=0


        # ----------------------------------------------------
        # Absender
        # ----------------------------------------------------

        if learning_exact_match \
            "$SENDER" \
            "$RULE_SENDER"
        then

            (( SCORE += 4 ))

        fi


        # ----------------------------------------------------
        # Titel
        # ----------------------------------------------------

        TITLE_SCORE="$(
            title_match_score \
                "$TITLE" \
                "$RULE_TITLE"
        )"

        (( SCORE += TITLE_SCORE ))


        # ----------------------------------------------------
        # Dokumenttyp
        # ----------------------------------------------------

        if learning_exact_match \
            "$DOCUMENT_TYPE" \
            "$RULE_TYPE"
        then

            (( SCORE += 2 ))

        fi


        # ----------------------------------------------------
        # Kategorie
        # ----------------------------------------------------

        if learning_exact_match \
            "$CATEGORY" \
            "$RULE_CATEGORY"
        then

            (( SCORE += 2 ))

        fi


        # ----------------------------------------------------
        # Unterkategorie
        # ----------------------------------------------------

        if learning_exact_match \
            "$SUBCATEGORY" \
            "$RULE_SUBCATEGORY"
        then

            (( SCORE += 3 ))

        fi


        # ----------------------------------------------------
        # bevorzugtes Ziel
        # ----------------------------------------------------

        if [[ "$RULE_PRIORITY" == "preferred" ]]; then

            (( SCORE += 1 ))

        fi


        # ----------------------------------------------------
        # besten Treffer merken
        # ----------------------------------------------------

        if (( SCORE > BEST_SCORE )); then

            BEST_SCORE="$SCORE"
            BEST_ID="$RULE_ID"
            BEST_TARGET="$FULL_TARGET"
            BEST_PRIORITY="$RULE_PRIORITY"

        fi


    done < <(
        jq -c \
            '.rules[]?' \
            "$LEARNING_FILE"
    )


    if (( BEST_SCORE < LEARNING_MIN_SCORE )); then
        return 1
    fi


    printf '%s|%s|%s|%s\n' \
        "$BEST_ID" \
        "$BEST_TARGET" \
        "$BEST_SCORE" \
        "$BEST_PRIORITY"
}


# ============================================================
# Normales Mapping
# ============================================================

detect_target_folder() {

    local RULE
    local RULE_ID
    local TARGET_REL
    local USE_YEAR

    local MATCH
    local ROOT
    local FULL_TARGET
    local YEAR_TARGET


# Mapping-Zielwurzel kommt zentral aus system.conf.
    ROOT="$CABINET_DIR"


    while IFS= read -r RULE; do


        RULE_ID="$(
            jq -r \
                '.id' \
                <<< "$RULE"
        )"


        TARGET_REL="$(
            jq -r \
                '.target' \
                <<< "$RULE"
        )"


        USE_YEAR="$(
            jq -r \
                '.use_year_subfolder // false' \
                <<< "$RULE"
        )"


        MATCH=true


        # ----------------------------------------------------
        # Absender
        # ----------------------------------------------------

        if jq -e \
            'has("sender")' \
            <<< "$RULE" \
            >/dev/null
        then

            if ! jq -e \
                --arg VALUE "$SENDER" \
                '.sender | index($VALUE) != null' \
                <<< "$RULE" \
                >/dev/null
            then

                MATCH=false

            fi

        fi


        # ----------------------------------------------------
        # Dokumenttyp
        # ----------------------------------------------------

        if jq -e \
            'has("document_type")' \
            <<< "$RULE" \
            >/dev/null
        then

            if ! jq -e \
                --arg VALUE "$DOCUMENT_TYPE" \
                '.document_type | index($VALUE) != null' \
                <<< "$RULE" \
                >/dev/null
            then

                MATCH=false

            fi

        fi


        # ----------------------------------------------------
        # Kategorie
        # ----------------------------------------------------

        if jq -e \
            'has("category")' \
            <<< "$RULE" \
            >/dev/null
        then

            if ! jq -e \
                --arg VALUE "$CATEGORY" \
                '.category | index($VALUE) != null' \
                <<< "$RULE" \
                >/dev/null
            then

                MATCH=false

            fi

        fi


        # ----------------------------------------------------
        # Unterkategorie
        # ----------------------------------------------------

        if jq -e \
            'has("subcategory")' \
            <<< "$RULE" \
            >/dev/null
        then

            if ! jq -e \
                --arg VALUE "$SUBCATEGORY" \
                '.subcategory | index($VALUE) != null' \
                <<< "$RULE" \
                >/dev/null
            then

                MATCH=false

            fi

        fi


        # ----------------------------------------------------
        # Regel passt
        # ----------------------------------------------------

        if [[ "$MATCH" == true ]]; then


            FULL_TARGET="${ROOT}/${TARGET_REL}"


            [[ -d "$FULL_TARGET" ]] || continue


            # Jahresordner nur verwenden,
            # wenn er bereits existiert.

            if [[ "$USE_YEAR" == "true" ]]; then

                YEAR_TARGET="${FULL_TARGET}/${DOCUMENT_YEAR}"


                if [[ -d "$YEAR_TARGET" ]]; then
                    FULL_TARGET="$YEAR_TARGET"
                fi

            fi


            printf '%s|%s\n' \
                "$RULE_ID" \
                "$FULL_TARGET"


            return 0

        fi


    done < <(
        jq -c \
            '.rules[]' \
            "$MAPPING_CONFIG"
    )


    return 1
}


# ============================================================
# Ziel bestimmen
#
# Reihenfolge:
#
#   1. Gelernte Regeln
#   2. Normales Mapping
#   3. Scans/OCR
# ============================================================

TARGET_RULE="keine"

TARGET_FOLDER="$OCR_DIR"

TARGET_SOURCE="Fallback"

MAPPING_FOUND=false
LEARNING_FOUND=false

LEARNING_SCORE=0
LEARNING_PRIORITY=""


# ------------------------------------------------------------
# 1. Gelernte Regeln
# ------------------------------------------------------------

if LEARNED_RESULT="$(
    detect_learned_target
)"; then


    IFS='|' read -r \
        TARGET_RULE \
        TARGET_FOLDER \
        LEARNING_SCORE \
        LEARNING_PRIORITY \
        <<< "$LEARNED_RESULT"


    TARGET_SOURCE="Learning"
    LEARNING_FOUND=true
    MAPPING_FOUND=true

fi


# ------------------------------------------------------------
# 2. Normales Mapping
# ------------------------------------------------------------

if [[ "$LEARNING_FOUND" != true ]]; then


    if TARGET_RESULT="$(
        detect_target_folder
    )"; then


        TARGET_RULE="${TARGET_RESULT%%|*}"
        TARGET_FOLDER="${TARGET_RESULT#*|}"

        TARGET_SOURCE="Mapping"
        MAPPING_FOUND=true

    fi

fi


# ============================================================
# Sinnvollen Dateinamen bereits in Scans/OCR vergeben
# ============================================================

CURRENT_FILE="$OUTPUT"


if [[ -n "$PROPOSED_FILENAME" ]]; then


    RENAMED_FILE="$(
        unique_destination \
            "$OCR_DIR" \
            "$PROPOSED_FILENAME"
    )"


    if [[ "$RENAMED_FILE" != "$CURRENT_FILE" ]]; then

        mv \
            "$CURRENT_FILE" \
            "$RENAMED_FILE"

        CURRENT_FILE="$RENAMED_FILE"

    fi

fi


# ============================================================
# Automatische Ablage
# ============================================================

AUTO_FILE=false
AUTO_REASON=""


if [[ "$MAPPING_FOUND" != true ]]; then

    AUTO_REASON="Keine passende Mapping- oder Lernregel"


elif [[ ! -d "$TARGET_FOLDER" ]]; then

    AUTO_REASON="Zielordner existiert nicht"


elif [[ "$AI_USED" == true \
     && "$AI_CONFIDENCE" == "low" ]]
then

    AUTO_REASON="KI-Konfidenz zu niedrig"


else

    AUTO_FILE=true
    AUTO_REASON="Vorhandene Ablageregel ausreichend sicher"

fi


# ============================================================
# Gegebenenfalls verschieben
# ============================================================

FINAL_FILE="$CURRENT_FILE"


if [[ "$AUTO_FILE" == true ]]; then


    FINAL_NAME="$(
        basename "$CURRENT_FILE"
    )"


    DESTINATION="$(
        unique_destination \
            "$TARGET_FOLDER" \
            "$FINAL_NAME"
    )"


    echo
    echo "Passende Ablageregel gefunden."
    echo "Lege Dokument automatisch ab ..."
    echo


    mv \
        "$CURRENT_FILE" \
        "$DESTINATION"


    FINAL_FILE="$DESTINATION"

fi

# ============================================================
# Rohscan aussagekräftig umbenennen
#
# Der Inhalt der ursprünglichen PDF wird NICHT verändert.
# Es wird ausschließlich der Dateiname angepasst.
#
# Beispiel:
#
#   06.09.26_scan_original_01.pdf
#
# wird zu:
#
#   31.07.26_Dr._med._vet._Matthias_Herzberg_
#   Tierärztliche_Rechnung_original.pdf
#
# Für den Rohscan wird derselbe erkannte Informationskern
# verwendet wie für die OCR-Datei:
#
#   Dokumentdatum + Absender + Titel
#
# Falls keine sinnvolle Benennung ermittelt werden konnte,
# bleibt der bisherige neutrale Rohscanname erhalten.
#
# Bei Namenskollisionen verwendet unique_destination()
# automatisch _01, _02 usw.
# ============================================================

RAW_FILE="$INPUT"
RAW_RENAMED=false


if [[ -n "$PROPOSED_FILENAME" ]]; then

    RAW_DIRECTORY="$(
        dirname "$RAW_FILE"
    )"

    RAW_STEM="${PROPOSED_FILENAME%.pdf}"

    RAW_FILENAME="${RAW_STEM}_original.pdf"


    RAW_DESTINATION="$(
        unique_destination \
            "$RAW_DIRECTORY" \
            "$RAW_FILENAME"
    )"


    if [[ "$RAW_DESTINATION" != "$RAW_FILE" ]]; then

        if mv \
            -- \
            "$RAW_FILE" \
            "$RAW_DESTINATION"
        then

            # Ab diesem Punkt muss auch der restliche
            # Verarbeitungsablauf den neuen Rohscanpfad kennen.
            INPUT="$RAW_DESTINATION"
            RAW_FILE="$RAW_DESTINATION"
            RAW_RENAMED=true

        else

            echo
            echo "WARNUNG:"
            echo "Rohscan konnte nicht umbenannt werden."
            echo "Der bisherige Name bleibt erhalten:"
            echo "  $RAW_FILE"

        fi

    fi

fi
# ============================================================
# Fingerprints für späteres Lernen
# ============================================================

SOURCE_HASH="$(
    sha256sum "$INPUT" |
    awk '{print $1}'
)"


FILE_HASH="$(
    sha256sum "$FINAL_FILE" |
    awk '{print $1}'
)"


# ============================================================
# Lern-Datensatz speichern
# ============================================================

PROCESSED_AT="$(
    date --iso-8601=seconds
)"

PENDING_TMP="${WORKDIR}/pending_learning.json"


jq \
    --arg SOURCE_HASH "$SOURCE_HASH" \
    --arg FILE_HASH "$FILE_HASH" \
    --arg SOURCE_PATH "$INPUT" \
    --arg CURRENT_PATH "$FINAL_FILE" \
    --arg DATE "$DOCUMENT_DATE" \
    --arg SENDER "$SENDER" \
    --arg TITLE "$TITLE" \
    --arg TYPE "$DOCUMENT_TYPE" \
    --arg CATEGORY "$CATEGORY" \
    --arg SUBCATEGORY "$SUBCATEGORY" \
    --arg INSURANCE_NUMBER "$INSURANCE_NUMBER" \
    --arg CONFIDENCE "${AI_CONFIDENCE:-}" \
    --arg TITLE_CONFIDENCE "${TITLE_CONFIDENCE:-}" \
    --arg MAPPING "$TARGET_RULE" \
    --arg TARGET_SOURCE "$TARGET_SOURCE" \
    --arg PROCESSED "$PROCESSED_AT" \
    '
    .documents += [
      {
        source_hash: $SOURCE_HASH,
        file_hash: $FILE_HASH,
        source_path: $SOURCE_PATH,
        current_path: $CURRENT_PATH,
        document_date: $DATE,
        sender: $SENDER,
        title: $TITLE,
        document_type: $TYPE,
        category: $CATEGORY,
        subcategory: $SUBCATEGORY,
        insurance_number: $INSURANCE_NUMBER,
        confidence: $CONFIDENCE,
        title_confidence: $TITLE_CONFIDENCE,
        initial_mapping: $MAPPING,
        target_source: $TARGET_SOURCE,
        processed_at: $PROCESSED,
        status: "pending"
      }
    ]
    ' \
    "$PENDING_FILE" \
    > "$PENDING_TMP"


mv \
    "$PENDING_TMP" \
    "$PENDING_FILE"


# ============================================================
# PDF-Informationen
# ============================================================

PAGES="$(
    pdfinfo \
        "$FINAL_FILE" \
        2>/dev/null |
    awk '/^Pages:/ {print $2}'
)"


PAGE_SIZE="$(
    pdfinfo \
        "$FINAL_FILE" \
        2>/dev/null |
    awk \
        -F': +' \
        '/^Page size:/ {print $2}'
)"


TEXT_CHARS="$(
    tr \
        -d '[:space:]' \
        < "$TEXT_FILE" |
    wc -c
)"


# ============================================================
# Ergebnis
# ============================================================

echo
echo "------------------------------------------------------------"
echo "Dokumentverarbeitung abgeschlossen"
echo "------------------------------------------------------------"


echo
echo "Dokumentdatum:"
echo "  $DOCUMENT_DATE"
echo "  Quelle: $DATE_SOURCE"


echo
echo "Absender:"
echo "  $SENDER"
echo "  Quelle: $SENDER_SOURCE"


echo
echo "Titel / Betreff:"
echo "  ${TITLE:-nicht erkannt}"
echo "  Konfidenz: ${TITLE_CONFIDENCE:-nicht verfügbar}"


echo
echo "Dokumenttyp:"
echo "  $DOCUMENT_TYPE"
echo "  Quelle: $TYPE_SOURCE"


echo
echo "Kategorie:"
echo "  ${CATEGORY:-nicht erkannt}"


echo
echo "Unterkategorie:"
echo "  ${SUBCATEGORY:-nicht erkannt}"


echo
echo "KI-Konfidenz:"
echo "  ${AI_CONFIDENCE:-nicht verfügbar}"


if [[ -n "$PROPOSED_FILENAME" ]]; then

    echo
    echo "Dateiname:"
    echo "  $PROPOSED_FILENAME"

else

    echo
    echo "Kein ausreichender Inhalt für einen sinnvollen Dateinamen."
    echo "Neutrale OCR-Benennung wurde beibehalten."

fi


echo
echo "Zielquelle:"
echo "  $TARGET_SOURCE"


echo
echo "Regel:"
echo "  $TARGET_RULE"


if [[ "$TARGET_SOURCE" == "Learning" ]]; then

    echo
    echo "Lern-Score:"
    echo "  $LEARNING_SCORE / mindestens $LEARNING_MIN_SCORE"

    echo "Lern-Priorität:"
    echo "  $LEARNING_PRIORITY"

fi


echo
echo "Zielordner:"
echo "  $TARGET_FOLDER"


echo
echo "Automatische Ablage:"
echo "  $AUTO_FILE"


echo "Grund:"
echo "  $AUTO_REASON"


echo
echo "Seiten:"
echo "  ${PAGES:-unbekannt}"


echo
echo "Seitengröße:"
echo "  ${PAGE_SIZE:-unbekannt}"


echo
echo "OCR-Zeichen:"
echo "  ${TEXT_CHARS}"


echo
echo "Endgültige OCR-Datei:"
echo "  $FINAL_FILE"


echo
echo "Rohscan bleibt erhalten:"
echo "  $INPUT"


echo
echo "Lern-Datensatz:"
echo "  $PENDING_FILE"


echo
