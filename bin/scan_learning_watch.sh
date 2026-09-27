#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# LocalDocFlow - Learning Watcher
#
# Aufgabe:
#
#   Bereits verarbeitete Dokumente werden anhand ihres
#   SHA256-Hashes wiedererkannt.
#
#   # Wird ein solches Dokument später innerhalb von
# LEARNING_ROOT aus system.conf verschoben, kann daraus
# eine Lernregel entstehen.
#
# WICHTIG:
#
# CABINET_DIR aus system.conf ist der bevorzugte Lernbereich,
# aber NICHT der einzige gültige Lernbereich.
#
# Andere fachliche Zielordner innerhalb von LEARNING_ROOT
# können ebenfalls als Lernziele verwendet werden.
# ============================================================


# ============================================================
# Grundkonfiguration
# ============================================================

CONFIG_DIR="$HOME/.config/localdocflow"

LEARNING_CONFIG="${CONFIG_DIR}/learning_config.json"

# Standardmäßig noch NICHT wirklich lernen.
#
# Zum späteren Aktivieren:
#
#   LEARNING_DRY_RUN=false scan_learning_watch.sh
#
DRY_RUN="${LEARNING_DRY_RUN:-true}"


# ============================================================
# Programme prüfen
# ============================================================

for CMD in \
    jq \
    inotifywait \
    sha256sum \
    dirname \
    basename \
    date
do

    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "Fehler: '$CMD' wurde nicht gefunden."
        exit 1
    fi

done


# ============================================================
# Konfiguration prüfen
# ============================================================

if [[ ! -f "$LEARNING_CONFIG" ]]; then
    echo "Fehler: learning_config.json fehlt:"
    echo "$LEARNING_CONFIG"
    exit 1
fi

if ! jq empty "$LEARNING_CONFIG" >/dev/null 2>&1; then
    echo "Fehler: learning_config.json ist ungültig."
    exit 1
fi


# ============================================================
# Zentrale Systemkonfiguration
# ============================================================

SYSTEM_CONFIG="$HOME/.config/localdocflow/system.conf"

if [[ ! -f "$SYSTEM_CONFIG" ]]; then

    echo "Fehler: Systemkonfiguration fehlt:"
    echo "  $SYSTEM_CONFIG"

    exit 1

fi

# shellcheck source=/dev/null
source "$SYSTEM_CONFIG"


# ------------------------------------------------------------
# Benötigte Lernsystem-Pfade prüfen
# ------------------------------------------------------------

: "${LEARNING_ROOT:?LEARNING_ROOT fehlt in system.conf}"
: "${CABINET_DIR:?CABINET_DIR fehlt in system.conf}"
: "${PENDING_LEARNING_FILE:?PENDING_LEARNING_FILE fehlt in system.conf}"
: "${LEARNING_RULES_FILE:?LEARNING_RULES_FILE fehlt in system.conf}"

PENDING_FILE="$PENDING_LEARNING_FILE"
LEARNING_FILE="$LEARNING_RULES_FILE"


# Bevorzugter Lernbereich kommt zentral aus system.conf.
PREFERRED_ROOTS=("$CABINET_DIR")

mapfile -t IGNORED_ROOTS < <(
    jq -r '.ignored_roots[]?' "$LEARNING_CONFIG"
)

mapfile -t IGNORED_NAMES < <(
    jq -r '.ignored_names[]?' "$LEARNING_CONFIG"
)
# ============================================================
# Relative ignorierte Lernpfade auflösen
#
# Der bevorzugte Lernbereich kommt direkt als absoluter Pfad
# aus CABINET_DIR in system.conf.
#
# Die ignorierten Bereiche aus learning_config.json werden
# dagegen relativ zu LEARNING_ROOT angegeben.
#
# Beispiel:
#
#   Archiv/Rohscans
#
# wird mit LEARNING_ROOT aus system.conf zu:
#
#   <LEARNING_ROOT>/Archiv/Rohscans
#
# Absolute Pfade werden aus Kompatibilitätsgründen weiterhin
# akzeptiert.
# ============================================================

for INDEX in "${!IGNORED_ROOTS[@]}"; do

    VALUE="${IGNORED_ROOTS[$INDEX]}"

    if [[ "$VALUE" != /* ]]; then
        IGNORED_ROOTS[$INDEX]="${LEARNING_ROOT%/}/${VALUE#/}"
    fi

done

# ============================================================
# Dateien prüfen
# ============================================================

if [[ ! -d "$LEARNING_ROOT" ]]; then
    echo "Fehler: Lernbereich existiert nicht:"
    echo "$LEARNING_ROOT"
    exit 1
fi

for FILE in "$PENDING_FILE" "$LEARNING_FILE"; do

    if [[ ! -f "$FILE" ]]; then
        echo "Fehler: Datei fehlt:"
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
# Hilfsfunktion:
# Liegt PATH innerhalb von ROOT?
# ============================================================

path_is_under() {

    local PATH_VALUE="$1"
    local ROOT_VALUE="$2"

    [[ "$PATH_VALUE" == "$ROOT_VALUE" \
       || "$PATH_VALUE" == "$ROOT_VALUE/"* ]]
}


# ============================================================
# Ignorierten Bereich erkennen
# ============================================================

is_ignored_path() {

    local PATH_VALUE="$1"
    local ROOT
    local NAME
    local PREFIX

    for ROOT in "${IGNORED_ROOTS[@]}"; do

        if path_is_under "$PATH_VALUE" "$ROOT"; then
            return 0
        fi

    done


    NAME="$(basename "$PATH_VALUE")"


    for PREFIX in "${IGNORED_NAMES[@]}"; do

        if [[ "$NAME" == "$PREFIX"* ]]; then
            return 0
        fi

    done


    return 1
}


# ============================================================
# Bevorzugten Lernbereich erkennen
# ============================================================

is_preferred_path() {

    local PATH_VALUE="$1"
    local ROOT

    for ROOT in "${PREFERRED_ROOTS[@]}"; do

        if path_is_under "$PATH_VALUE" "$ROOT"; then
            return 0
        fi

    done

    return 1
}


# ============================================================
# pending_learning.json atomar aktualisieren
# ============================================================

update_pending_path() {

    local INDEX="$1"
    local NEW_PATH="$2"

    local TMP

    TMP="$(
        mktemp "${CONFIG_DIR}/pending_learning.XXXXXX"
    )"


    jq \
        --argjson INDEX "$INDEX" \
        --arg PATH "$NEW_PATH" \
        '
        .documents[$INDEX].current_path = $PATH
        ' \
        "$PENDING_FILE" \
        > "$TMP"


    mv "$TMP" "$PENDING_FILE"
}


# ============================================================
# Lernregel erzeugen
# ============================================================

store_learning_rule() {

    local INDEX="$1"
    local NEW_PATH="$2"
    local FILE_HASH="$3"

    local NEW_DIR
    local TARGET_REL
    local PRIORITY
    local LEARNED_AT
    local RULE_ID

    local SENDER
    local TITLE
    local DOCUMENT_TYPE
    local CATEGORY
    local SUBCATEGORY
    local INSURANCE_NUMBER

    local TMP_PENDING
    local TMP_LEARNING


    NEW_DIR="$(dirname "$NEW_PATH")"


    # Ziel relativ zum gesamten Dokumentbereich speichern.
    if [[ "$NEW_DIR" == "$LEARNING_ROOT" ]]; then
        TARGET_REL="."
    else
        TARGET_REL="${NEW_DIR#"$LEARNING_ROOT"/}"
    fi


    if is_preferred_path "$NEW_DIR"; then
        PRIORITY="preferred"
    else
        PRIORITY="normal"
    fi


    LEARNED_AT="$(date --iso-8601=seconds)"

    RULE_ID="learned_${FILE_HASH:0:12}_$(date +%s)"


    SENDER="$(
        jq -r \
            --argjson INDEX "$INDEX" \
            '.documents[$INDEX].sender // ""' \
            "$PENDING_FILE"
    )"

    TITLE="$(
        jq -r \
            --argjson INDEX "$INDEX" \
            '.documents[$INDEX].title // ""' \
            "$PENDING_FILE"
    )"

    DOCUMENT_TYPE="$(
        jq -r \
            --argjson INDEX "$INDEX" \
            '.documents[$INDEX].document_type // ""' \
            "$PENDING_FILE"
    )"

    CATEGORY="$(
        jq -r \
            --argjson INDEX "$INDEX" \
            '.documents[$INDEX].category // ""' \
            "$PENDING_FILE"
    )"

    SUBCATEGORY="$(
        jq -r \
            --argjson INDEX "$INDEX" \
            '.documents[$INDEX].subcategory // ""' \
            "$PENDING_FILE"
    )"

    INSURANCE_NUMBER="$(jq -r --argjson INDEX "$INDEX" '.documents[$INDEX].insurance_number // ""' "$PENDING_FILE")"


    # --------------------------------------------------------
    # Lernregel hinzufügen
    # --------------------------------------------------------

    TMP_LEARNING="$(
        mktemp "${CONFIG_DIR}/learning.XXXXXX"
    )"


    jq \
        --arg ID "$RULE_ID" \
        --arg HASH "$FILE_HASH" \
        --arg SENDER "$SENDER" \
        --arg TITLE "$TITLE" \
        --arg TYPE "$DOCUMENT_TYPE" \
        --arg CATEGORY "$CATEGORY" \
        --arg SUBCATEGORY "$SUBCATEGORY" \
        --arg INSURANCE_NUMBER "$INSURANCE_NUMBER" \
        --arg TARGET "$TARGET_REL" \
        --arg PRIORITY "$PRIORITY" \
        --arg LEARNED "$LEARNED_AT" \
        '
        .rules += [
          {
            id: $ID,
            file_hash: $HASH,
            sender: $SENDER,
            title: $TITLE,
            document_type: $TYPE,
            category: $CATEGORY,
            subcategory: $SUBCATEGORY,
            insurance_number: $INSURANCE_NUMBER,
            target: $TARGET,
            priority: $PRIORITY,
            learned_at: $LEARNED,
            occurrences: 1
          }
        ]
        ' \
        "$LEARNING_FILE" \
        > "$TMP_LEARNING"


    mv "$TMP_LEARNING" "$LEARNING_FILE"


    # --------------------------------------------------------
    # Pending-Datensatz als gelernt markieren
    # --------------------------------------------------------

    TMP_PENDING="$(
        mktemp "${CONFIG_DIR}/pending_learning.XXXXXX"
    )"


    jq \
        --argjson INDEX "$INDEX" \
        --arg PATH "$NEW_PATH" \
        --arg TARGET "$TARGET_REL" \
        --arg LEARNED "$LEARNED_AT" \
        '
        .documents[$INDEX].current_path = $PATH |
        .documents[$INDEX].status = "learned" |
        .documents[$INDEX].learned_target = $TARGET |
        .documents[$INDEX].learned_at = $LEARNED
        ' \
        "$PENDING_FILE" \
        > "$TMP_PENDING"


    mv "$TMP_PENDING" "$PENDING_FILE"
}


# ============================================================
# Eine neu aufgetauchte PDF prüfen
# ============================================================

handle_pdf() {

    local FILE="$1"

    local HASH
    local INDEX
    local OLD_PATH
    local OLD_DIR
    local NEW_DIR


    # Datei muss existieren.
    [[ -f "$FILE" ]] || return 0


    # Nur PDFs.
    case "${FILE,,}" in
        *.pdf)
            ;;
        *)
            return 0
            ;;
    esac


    # Nur innerhalb des gewünschten Dokumentbereiches.
    if ! path_is_under "$FILE" "$LEARNING_ROOT"; then
        return 0
    fi


    # Kurz warten, bis Kopier-/Sync-Vorgänge beendet sind.
    sleep 1


    [[ -f "$FILE" ]] || return 0


    HASH="$(
        sha256sum "$FILE" |
        awk '{print $1}'
    )"


    # Letzten noch offenen Datensatz mit diesem Hash suchen.
    INDEX="$(
        jq -r \
            --arg HASH "$HASH" \
            '
            .documents
            | to_entries[]
            | select(
                .value.file_hash == $HASH
                and .value.status == "pending"
              )
            | .key
            ' \
            "$PENDING_FILE" |
        tail -n 1
    )"


    # Datei gehört zu keinem beobachteten Scan.
    if [[ -z "$INDEX" ]]; then
        return 0
    fi


    OLD_PATH="$(
        jq -r \
            --argjson INDEX "$INDEX" \
            '.documents[$INDEX].current_path' \
            "$PENDING_FILE"
    )"


    # Keine Veränderung.
    if [[ "$OLD_PATH" == "$FILE" ]]; then
        return 0
    fi


    OLD_DIR="$(dirname "$OLD_PATH")"
    NEW_DIR="$(dirname "$FILE")"


    echo
    echo "------------------------------------------------------------"
    echo "Bekanntes Dokument wiedergefunden"
    echo "------------------------------------------------------------"
    echo
    echo "Alt:"
    echo "  $OLD_PATH"
    echo
    echo "Neu:"
    echo "  $FILE"
    echo


    # --------------------------------------------------------
    # Nur umbenannt, aber nicht in einen anderen Ordner
    # --------------------------------------------------------

    if [[ "$OLD_DIR" == "$NEW_DIR" ]]; then

        echo "Datei wurde nur umbenannt."
        echo "Kein neues Ablageziel zu lernen."

        if [[ "$DRY_RUN" != "true" ]]; then
            update_pending_path "$INDEX" "$FILE"
        fi

        return 0
    fi


    # --------------------------------------------------------
    # Verschiebung in technischen/ignorierten Bereich
    # --------------------------------------------------------

    if is_ignored_path "$FILE"; then

        echo "Neuer Ort liegt in einem ignorierten Bereich."
        echo "Daraus wird keine Lernregel erzeugt."

        if [[ "$DRY_RUN" != "true" ]]; then
            update_pending_path "$INDEX" "$FILE"
        fi

        return 0
    fi


    # --------------------------------------------------------
    # Tatsächliche manuelle Korrektur
    # --------------------------------------------------------

    echo "Neues fachliches Ablageziel erkannt:"
    echo "  $NEW_DIR"


    if is_preferred_path "$NEW_DIR"; then
        echo "Priorität: bevorzugter Lernbereich"
    else
        echo "Priorität: normal"
    fi


    if [[ "$DRY_RUN" == "true" ]]; then

        echo
        echo "DRY-RUN:"
        echo "Diese Verschiebung würde als Lernregel gespeichert."
        echo "Es wurde noch nichts verändert."

    else

        store_learning_rule \
            "$INDEX" \
            "$FILE" \
            "$HASH"

        echo
        echo "Lernregel gespeichert."

    fi
}


# ============================================================
# Start
# ============================================================

echo
echo "============================================================"
echo "LocalDocFlow - Learning Watcher"
echo "============================================================"
echo
echo "Überwache:"
echo "  $LEARNING_ROOT"
echo
echo "Dry-Run:"
echo "  $DRY_RUN"
echo
echo "Bevorzugte Lernbereiche:"

for ROOT in "${PREFERRED_ROOTS[@]}"; do
    echo "  $ROOT"
done

echo
echo "Ignorierte Bereiche:"

for ROOT in "${IGNORED_ROOTS[@]}"; do
    echo "  $ROOT"
done

echo
echo "Warte auf Dateiänderungen ..."
echo


# ============================================================
# Gesamten Dokumentbaum beobachten
#
# moved_to:
#   normale Verschiebung innerhalb des Dateisystems
#
# close_write / create:
#   wichtig für Nextcloud-Synchronisation oder Kopiervorgänge
# ============================================================

inotifywait \
    -m \
    -r \
    -e moved_to \
    -e close_write \
    -e create \
    --format '%w%f' \
    "$LEARNING_ROOT" |
while IFS= read -r FILE; do

    handle_pdf "$FILE"

done
