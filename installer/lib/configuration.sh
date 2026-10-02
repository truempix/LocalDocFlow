#!/usr/bin/env bash


# ============================================================
# LocalDocFlow - Installer
# Interaktive Konfiguration
# ============================================================


# ------------------------------------------------------------
# Vorhandenen DOCUMENT_ROOT als Vorschlag ermitteln
# Determine existing DOCUMENT_ROOT as suggestion
# ------------------------------------------------------------

get_default_document_root() {
    local existing_config
    local result

    existing_config="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow/system.conf"

    if [[ -r "$existing_config" ]]; then
        result="$(
            bash -c '
                source "$1" 2>/dev/null
                printf "%s" "${DOCUMENT_ROOT:-}"
            ' _ "$existing_config"
        )"

        if [[ -n "$result" ]]; then
            printf '%s\n' "$result"
            return 0
        fi
    fi

    if command -v xdg-user-dir >/dev/null 2>&1; then
        result="$(xdg-user-dir DOCUMENTS 2>/dev/null || true)"

        if [[ -n "$result" ]]; then
            printf '%s\n' "$result"
            return 0
        fi
    fi

    printf '%s\n' "$HOME/Documents"
}


# ------------------------------------------------------------
# Dokumentwurzel abfragen
# Ask for document root
# ------------------------------------------------------------

select_document_root() {
    local default_root
    local answer

    default_root="$(get_default_document_root)"

    printf '\n'
    info "Dokumentablage"
    printf '\n'

    printf 'Dokumentwurzel [%s]: ' "$default_root"
    read -r answer

    if [[ -z "$answer" ]]; then
        answer="$default_root"
    fi

    # ~ am Anfang auflösen
    if [[ "$answer" == "~" ]]; then
        answer="$HOME"
    elif [[ "$answer" == "~/"* ]]; then
        answer="$HOME/${answer#~/}"
    fi

    # relativer Pfad ist für diese Konfiguration nicht sinnvoll
    if [[ "$answer" != /* ]]; then
        error "DOCUMENT_ROOT muss ein absoluter Pfad sein."
        return 1
    fi

    DOCUMENT_ROOT_SELECTION="${answer%/}"

    ok "Dokumentwurzel: ${DOCUMENT_ROOT_SELECTION}"

    if [[ -d "$DOCUMENT_ROOT_SELECTION" ]]; then
        ok "Dokumentwurzel existiert"
    else
        warn "Dokumentwurzel existiert derzeit noch nicht:"
        warn "  ${DOCUMENT_ROOT_SELECTION}"
        warn "Der Installer wird später vor dem Anlegen noch einmal nachfragen."
    fi
}

# ------------------------------------------------------------
# Vorhandenen Ablageordner als Vorschlag ermitteln
# Determine existing filing directory as suggestion
# ------------------------------------------------------------

get_default_cabinet_dir() {
    local existing_config
    local result

    existing_config="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow/system.conf"

    if [[ -r "$existing_config" ]]; then
        result="$(
            bash -c '
                source "$1" 2>/dev/null
                printf "%s" "${CABINET_DIR:-}"
            ' _ "$existing_config"
        )"

        if [[ -n "$result" ]]; then
            printf '%s\n' "$result"
            return 0
        fi
    fi

    printf '%s\n' "${DOCUMENT_ROOT_SELECTION}/Dokumentenablage"
}


# ------------------------------------------------------------
# Endgültigen Ablageordner auswählen
# Select final filing directory
# ------------------------------------------------------------

select_cabinet_dir() {
    local default_dir
    local answer

    default_dir="$(get_default_cabinet_dir)"

    printf '\n'
    info "Endgültige Dokumentablage"
    printf '\n'

    printf 'Ablageordner [%s]: ' "$default_dir"
    read -r answer

    if [[ -z "$answer" ]]; then
        answer="$default_dir"
    fi

    if [[ "$answer" == "~" ]]; then
        answer="$HOME"
    elif [[ "$answer" == "~/"* ]]; then
        answer="$HOME/${answer#~/}"
    fi

    if [[ "$answer" != /* ]]; then
        error "Der Ablageordner muss ein absoluter Pfad sein."
        return 1
    fi

    CABINET_DIR_SELECTION="${answer%/}"

    ok "Ablageordner: ${CABINET_DIR_SELECTION}"

    if [[ -d "$CABINET_DIR_SELECTION" ]]; then
        ok "Ablageordner existiert"
    else
        warn "Ablageordner existiert derzeit noch nicht."
    fi
}

# ------------------------------------------------------------
# Technische Dokumentstruktur vorbereiten
# Prepare technical document structure
# ------------------------------------------------------------

prepare_document_structure() {
    local raw_dir
    local ocr_dir
    local missing=0

    raw_dir="${DOCUMENT_ROOT_SELECTION}/Archiv/Rohscans"
    ocr_dir="${DOCUMENT_ROOT_SELECTION}/Scans/OCR"

    printf '\n'
    info "Technische Dokumentstruktur"

    for directory in \
        "$DOCUMENT_ROOT_SELECTION" \
        "$raw_dir" \
        "$ocr_dir" \
        "$CABINET_DIR_SELECTION"
    do
        if [[ -d "$directory" ]]; then
            ok "Vorhanden: ${directory}"
        else
            printf '  [fehlt] %s\n' "$directory"
            missing=1
        fi
    done

    if (( missing == 0 )); then
        return 0
    fi

    printf '\n'

    if ! ask_yes_no "Fehlende technische Verzeichnisse jetzt anlegen?"; then
        error "Die benötigte Dokumentstruktur ist unvollständig."
        return 1
    fi

    mkdir -p \
        "$raw_dir" \
        "$ocr_dir" \
        "$CABINET_DIR_SELECTION"

    ok "Technische Dokumentstruktur wurde angelegt."
}

# ------------------------------------------------------------
# Scanner suchen
# Detect scanners
# ------------------------------------------------------------

detect_scanners() {
    DETECTED_SCANNERS=()

    if ! command -v scanimage >/dev/null 2>&1; then
        warn "scanimage ist nicht verfügbar."
        return 0
    fi

    local device

    while IFS= read -r device; do
        [[ -n "$device" ]] || continue
        DETECTED_SCANNERS+=("$device")
    done < <(
        scanimage -f '%d|' 2>/dev/null |
        tr '|' '\n' ||
        true
    )
}

# ------------------------------------------------------------
# Bereits konfigurierten Scanner ermitteln
# Determine previously configured scanner
# ------------------------------------------------------------

get_existing_scanner_device() {
    local existing_config
    local result

    existing_config="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow/system.conf"

    if [[ ! -r "$existing_config" ]]; then
        return 0
    fi

    result="$(
        bash -c '
            source "$1" 2>/dev/null
            printf "%s" "${SCANNER_DEVICE:-}"
        ' _ "$existing_config"
    )"

    if [[ -n "$result" ]]; then
        printf '%s\n' "$result"
    fi
}

# ------------------------------------------------------------
# Scanner auswählen
# Select scanner
# ------------------------------------------------------------

select_scanner() {
    local count
    local index
    local choice
    local existing_scanner

    printf '\n'
    info "Scanner"
    printf '\n'

    detect_scanners

    count="${#DETECTED_SCANNERS[@]}"
    existing_scanner="$(get_existing_scanner_device)"

    # --------------------------------------------------------
    # Kein Scanner aktuell erkannt
    # --------------------------------------------------------

    if (( count == 0 )); then
        warn "Derzeit wurde kein Scanner erkannt."

        if [[ -n "$existing_scanner" ]]; then
            info "Bereits konfigurierter Scanner:"
            printf '  %s\n' "$existing_scanner"
            printf '\n'

            printf 'Scanner-Gerätename [%s]: ' "$existing_scanner"
            read -r choice

            SCANNER_DEVICE_SELECTION="${choice:-$existing_scanner}"

            ok "Scanner-Konfiguration: ${SCANNER_DEVICE_SELECTION}"
            return 0
        fi

        printf 'Scanner-Gerätename manuell eingeben'
        printf ' (leer = später konfigurieren): '

        read -r choice

        SCANNER_DEVICE_SELECTION="$choice"

        if [[ -z "$SCANNER_DEVICE_SELECTION" ]]; then
            warn "Noch kein Scanner festgelegt."
        else
            ok "Scanner: ${SCANNER_DEVICE_SELECTION}"
        fi

        return 0
    fi

    # --------------------------------------------------------
    # Genau ein Scanner erkannt
    # --------------------------------------------------------

    if (( count == 1 )); then
        SCANNER_DEVICE_SELECTION="${DETECTED_SCANNERS[0]}"
        ok "Scanner erkannt: ${SCANNER_DEVICE_SELECTION}"
        return 0
    fi

    # --------------------------------------------------------
    # Mehrere Scanner erkannt
    # --------------------------------------------------------

    info "Mehrere Scanner wurden gefunden:"

    for index in "${!DETECTED_SCANNERS[@]}"; do
        printf '  %d) %s\n' \
            "$((index + 1))" \
            "${DETECTED_SCANNERS[$index]}"
    done

    while true; do
        printf 'Scanner auswählen [1-%d]: ' "$count"
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           (( choice >= 1 && choice <= count )); then

            index=$((choice - 1))
            SCANNER_DEVICE_SELECTION="${DETECTED_SCANNERS[$index]}"
            break
        fi

        warn "Ungültige Auswahl."
    done

    ok "Scanner: ${SCANNER_DEVICE_SELECTION}"
}

# ------------------------------------------------------------
# Ollama-Modell auswählen
# Select Ollama model
# ------------------------------------------------------------

select_ollama_model() {
    local default_model="qwen3:4b"
    local answer

    printf '\n'
    info "KI-Konfiguration"
    printf '\n'

    printf 'Ollama-Modell [%s]: ' "$default_model"
    read -r answer

    OLLAMA_MODEL_SELECTION="${answer:-$default_model}"

    ok "Gewähltes KI-Modell: ${OLLAMA_MODEL_SELECTION}"
}


# ------------------------------------------------------------
# Vorschau für system.conf erzeugen
# Create system.conf preview
# ------------------------------------------------------------

create_system_config_preview() {
    local template
    local content

    template="${TEMPLATE_DIR}/system.conf.template"

    if [[ ! -r "$template" ]]; then
        error "system.conf-Vorlage nicht gefunden:"
        error "  ${template}"
        return 1
    fi

    SYSTEM_CONFIG_PREVIEW="$(
        mktemp --tmpdir localdocflow-system.conf.XXXXXX
    )"

    content="$(<"$template")"

    content="${content//__DOCUMENT_ROOT__/$DOCUMENT_ROOT_SELECTION}"
    content="${content//__CABINET_DIR__/$CABINET_DIR_SELECTION}"
    content="${content//__SCANNER_DEVICE__/$SCANNER_DEVICE_SELECTION}"
    content="${content//__OLLAMA_MODEL__/$OLLAMA_MODEL_SELECTION}"

    printf '%s\n' "$content" > "$SYSTEM_CONFIG_PREVIEW"

    ok "Konfigurationsvorschau erstellt."
}


# ------------------------------------------------------------
# Konfiguration anzeigen
# Show configuration
# ------------------------------------------------------------

show_system_config_preview() {
    printf '\n'
    printf '============================================================\n'
    printf ' Vorgesehene Systemkonfiguration\n'
    printf '============================================================\n'
    printf '\n'

    cat "$SYSTEM_CONFIG_PREVIEW"

    printf '\n'
    printf '============================================================\n'
}

# ------------------------------------------------------------
# system.conf schreiben
# Write system.conf
# ------------------------------------------------------------

write_system_config() {
    local config_dir
    local destination
    local backup

    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow"
    destination="${config_dir}/system.conf"

    mkdir -p "$config_dir"

    if [[ -f "$destination" ]]; then
        backup="${destination}.bak.$(date '+%Y%m%d-%H%M%S')"

        cp -a "$destination" "$backup"

        ok "Vorhandene system.conf gesichert:"
        printf '  %s\n' "$backup"
    fi

    install \
        -m 600 \
        "$SYSTEM_CONFIG_PREVIEW" \
        "$destination"

    ok "system.conf gespeichert:"
    printf '  %s\n' "$destination"
}


# ------------------------------------------------------------
# Laufzeitdateien einer Neuinstallation vorbereiten
# Prepare runtime files for a fresh installation
# ------------------------------------------------------------

initialize_runtime_config() {
    local config_dir
    local filename

    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow"

    mkdir -p "$config_dir"

    for filename in \
        pending_learning.json \
        learning.json \
        learning_config.json \
        senders.json \
        document_types.json \
        mapping.json
    do
        if [[ -e "${config_dir}/${filename}" ]]; then
            info "${filename} bereits vorhanden – bleibt unverändert."
            continue
        fi

        install \
            -m 600 \
            "${DEFAULT_DIR}/${filename}" \
            "${config_dir}/${filename}"

        ok "${filename} angelegt."
    done
}
# ------------------------------------------------------------
# Gesamte interaktive Konfiguration
# Complete interactive configuration
# ------------------------------------------------------------

configure_installation() {
    DOCUMENT_ROOT_SELECTION=""
    CABINET_DIR_SELECTION=""
    SCANNER_DEVICE_SELECTION=""
    OLLAMA_MODEL_SELECTION=""
    SYSTEM_CONFIG_PREVIEW=""

    select_document_root
    select_cabinet_dir
    prepare_document_structure
    select_scanner
    select_ollama_model

    create_system_config_preview
    show_system_config_preview

    printf '\n'

    if ask_yes_no "Diese Systemkonfiguration übernehmen?"; then
        write_system_config
        initialize_runtime_config
    else
        warn "Systemkonfiguration wurde nicht gespeichert."
    fi

    if [[ -n "$SYSTEM_CONFIG_PREVIEW" &&
          -f "$SYSTEM_CONFIG_PREVIEW" ]]; then
        rm -f "$SYSTEM_CONFIG_PREVIEW"
    fi
}
