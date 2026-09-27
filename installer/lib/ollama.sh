#!/usr/bin/env bash


# ============================================================
# LocalDocFlow - Installer
# Ollama und lokales KI-Modell
# ============================================================


# ------------------------------------------------------------
# Ollama-URL aus der Konfiguration ermitteln
# ------------------------------------------------------------

get_configured_ollama_url() {
    local config_file
    local result

    config_file="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow/system.conf"

    if [[ -r "$config_file" ]]; then
        result="$(
            bash -c '
                source "$1" 2>/dev/null
                printf "%s" "${OLLAMA_URL:-}"
            ' _ "$config_file"
        )"

        if [[ -n "$result" ]]; then
            printf '%s\n' "$result"
            return 0
        fi
    fi

    printf '%s\n' "http://127.0.0.1:11434"
}


# ------------------------------------------------------------
# Prüfen, ob Ollama installiert ist
# ------------------------------------------------------------

check_ollama_installed() {
    command -v ollama >/dev/null 2>&1
}


# ------------------------------------------------------------
# Prüfen, ob eine systemd-Unit für Ollama vorhanden ist
# ------------------------------------------------------------

ollama_service_exists() {

    command -v systemctl >/dev/null 2>&1 || return 1

    systemctl list-unit-files \
        ollama.service \
        --no-legend \
        2>/dev/null |
        grep -q '^ollama\.service'
}


# ------------------------------------------------------------
# Prüfen, ob die Ollama-API bereits erreichbar ist
# ------------------------------------------------------------

ollama_api_reachable() {

    local ollama_url

    ollama_url="$(get_configured_ollama_url)"

    curl \
        -fsS \
        "${ollama_url}/api/version" \
        >/dev/null 2>&1
}


# ------------------------------------------------------------
# Offiziellen Ollama-Installer ausführen
# ------------------------------------------------------------

run_official_ollama_installer() {

    local installer_file

    if ! command -v curl >/dev/null 2>&1; then
        error "curl fehlt. Ollama kann nicht heruntergeladen werden."
        return 1
    fi

    installer_file="$(
        mktemp --tmpdir ollama-install.XXXXXX.sh
    )"

    info "Lade offiziellen Ollama-Installer ..."

    if ! curl \
        -fsSL \
        https://ollama.com/install.sh \
        -o "$installer_file"
    then

        rm -f "$installer_file"

        error "Ollama-Installer konnte nicht heruntergeladen werden."
        return 1
    fi

    chmod 700 "$installer_file"

    info "Starte offiziellen Ollama-Installer ..."

    if ! sh "$installer_file"; then

        rm -f "$installer_file"

        error "Ollama-Installation fehlgeschlagen."
        return 1
    fi

    rm -f "$installer_file"

    return 0
}


# ------------------------------------------------------------
# Ollama installieren
# ------------------------------------------------------------

install_ollama() {

    if check_ollama_installed; then

        ok "Ollama ist bereits installiert."
        return 0
    fi

    warn "Ollama ist noch nicht installiert."

    if ! ask_yes_no "Ollama jetzt installieren?"; then

        error "Ollama wird für die lokale KI-Verarbeitung benötigt."
        return 1
    fi

    if ! run_official_ollama_installer; then
        return 1
    fi

    if ! check_ollama_installed; then

        error "Ollama wurde nach der Installation nicht gefunden."
        return 1
    fi

    ok "Ollama wurde installiert."

    return 0
}


# ------------------------------------------------------------
# Ollama-Dienst aktivieren
# ------------------------------------------------------------

activate_ollama_service() {

    local enabled_state=""
    local system_unit="/etc/systemd/system/ollama.service"
    local broken_mask=false


    if ! command -v systemctl >/dev/null 2>&1; then

        error "systemctl fehlt. Ollama-Dienst kann nicht verwaltet werden."
        return 1
    fi


    # --------------------------------------------------------
    # Status der Unit prüfen
    # --------------------------------------------------------

    enabled_state="$(
        systemctl is-enabled \
            ollama.service \
            2>/dev/null \
            || true
    )"


    # --------------------------------------------------------
    # Maskierte oder beschädigte Unit erkennen
    #
    # systemd behandelt unter anderem folgende Zustände als
    # maskiert:
    #
    #   /etc/systemd/system/ollama.service -> /dev/null
    #
    # oder eine leere Unit-Datei.
    #
    # Letzteres kann beispielsweise nach einer abgebrochenen
    # Installation zurückbleiben.
    # --------------------------------------------------------

    if [[ "$enabled_state" == "masked" ]]; then
        broken_mask=true
    fi


    if [[ -L "$system_unit" ]]; then

        if [[ "$(readlink -f "$system_unit" 2>/dev/null)" == "/dev/null" ]]; then
            broken_mask=true
        fi

    elif [[ -f "$system_unit" && ! -s "$system_unit" ]]; then

        broken_mask=true
    fi


    # --------------------------------------------------------
    # Maskierte / leere Unit reparieren
    # --------------------------------------------------------

    if [[ "$broken_mask" == true ]]; then

        warn "ollama.service ist maskiert oder beschädigt."

        if [[ -f "$system_unit" && ! -s "$system_unit" ]]; then

            warn "Leere systemd-Unit gefunden:"
            warn "  $system_unit"

        elif [[ -L "$system_unit" ]]; then

            warn "Maskierende systemd-Verknüpfung gefunden:"
            warn "  $system_unit"

        fi


        if ! ask_yes_no \
            "Beschädigte Ollama-Service-Konfiguration reparieren?"
        then

            error "Ollama-Dienst wurde nicht repariert."
            return 1
        fi


        # Nur eindeutig defekte bzw. maskierende Dateien
        # automatisch entfernen.
        #
        # Eine normale, nicht leere Unit-Datei wird hier niemals
        # ungefragt gelöscht.

        if [[ -f "$system_unit" && ! -s "$system_unit" ]]; then

            info "Entferne leere Ollama-Service-Datei ..."

            if ! sudo rm -f "$system_unit"; then

                error "Leere Ollama-Service-Datei konnte nicht entfernt werden."
                return 1
            fi

        elif [[ -L "$system_unit" ]] \
          && [[ "$(readlink -f "$system_unit" 2>/dev/null)" == "/dev/null" ]]
        then

            info "Entferne Maskierung des Ollama-Dienstes ..."

            if ! sudo rm -f "$system_unit"; then

                error "Maskierung konnte nicht entfernt werden."
                return 1
            fi

        else

            info "Versuche Ollama-Dienst zu entmaskieren ..."

            sudo systemctl unmask \
                ollama.service \
                >/dev/null 2>&1 \
                || true
        fi


        if ! sudo systemctl daemon-reload; then

            error "systemd-Konfiguration konnte nicht neu geladen werden."
            return 1
        fi


        info "Installiere Ollama-Service erneut ..."

        if ! run_official_ollama_installer; then

            error "Reparatur der Ollama-Installation fehlgeschlagen."
            return 1
        fi


        if ! sudo systemctl daemon-reload; then

            error "systemd-Konfiguration konnte nach der Reparatur nicht neu geladen werden."
            return 1
        fi


        enabled_state="$(
            systemctl is-enabled \
                ollama.service \
                2>/dev/null \
                || true
        )"


        if [[ "$enabled_state" == "masked" ]]; then

            error "ollama.service ist nach der Reparatur weiterhin maskiert."
            return 1
        fi


        if ! ollama_service_exists; then

            error "Nach der Reparatur wurde keine gültige ollama.service Unit gefunden."
            return 1
        fi


        ok "Beschädigte Ollama-Service-Konfiguration wurde repariert."
    fi


    # --------------------------------------------------------
    # Binary vorhanden, aber Service vollständig verschwunden
    # --------------------------------------------------------

    if ! ollama_service_exists; then

        warn "Ollama ist installiert, aber ollama.service fehlt."

        if ollama_api_reachable; then

            warn "Die Ollama-API läuft momentan trotzdem."
            warn "Für einen zuverlässigen Systemstart sollte der Dienst repariert werden."

        else

            warn "Die Ollama-API ist ebenfalls nicht erreichbar."
            warn "Die Ollama-Installation ist wahrscheinlich unvollständig."

        fi


        if ! ask_yes_no \
            "Ollama-Installation mit dem offiziellen Installer reparieren?"
        then

            error "Ollama-Dienst wurde nicht repariert."
            return 1
        fi


        info "Versuche Ollama-Installation zu reparieren ..."

        if ! run_official_ollama_installer; then

            error "Reparatur der Ollama-Installation fehlgeschlagen."
            return 1
        fi


        info "Lade systemd-Konfiguration neu ..."

        if ! sudo systemctl daemon-reload; then

            error "systemd-Konfiguration konnte nicht neu geladen werden."
            return 1
        fi


        if ! ollama_service_exists; then

            error "Nach der Reparatur wurde weiterhin keine ollama.service Unit gefunden."
            return 1
        fi


        ok "ollama.service wurde wiederhergestellt."
    fi


    # --------------------------------------------------------
    # Vollständig eingerichteter Dienst
    # --------------------------------------------------------

    if systemctl is-enabled \
            ollama.service >/dev/null 2>&1 &&
       systemctl is-active \
            ollama.service >/dev/null 2>&1
    then

        ok "Ollama-Dienst ist bereits aktiviert und läuft."
        return 0
    fi


    info "Aktiviere und starte Ollama-Dienst ..."

    if ! sudo systemctl enable --now ollama.service; then

        error "Ollama-Dienst konnte nicht aktiviert oder gestartet werden."
        return 1
    fi


    if systemctl is-active \
        ollama.service >/dev/null 2>&1
    then

        ok "Ollama-Dienst ist aktiviert und läuft."
        return 0
    fi


    error "Ollama-Dienst konnte nicht gestartet werden."

    return 1
}


# ------------------------------------------------------------
# Auf Ollama-API warten
# ------------------------------------------------------------

wait_for_ollama() {
    local ollama_url
    local attempt

    ollama_url="$(get_configured_ollama_url)"

    info "Warte auf Ollama unter ${ollama_url} ..."

    for attempt in {1..30}; do

        if curl \
            -fsS \
            "${ollama_url}/api/version" \
            >/dev/null 2>&1
        then
            ok "Ollama-API ist erreichbar."
            return 0
        fi

        sleep 1
    done

    error "Ollama-API ist nach 30 Sekunden nicht erreichbar."
    return 1
}


# ------------------------------------------------------------
# Prüfen, ob Modell vorhanden ist
# ------------------------------------------------------------

ollama_model_installed() {
    local model="$1"

    ollama list 2>/dev/null |
        awk 'NR > 1 {print $1}' |
        grep -Fxq "$model"
}


# ------------------------------------------------------------
# KI-Modell installieren
# ------------------------------------------------------------

install_ollama_model() {
    local model="$1"

    if [[ -z "$model" ]]; then
        error "Kein Ollama-Modell angegeben."
        return 1
    fi

    if ollama_model_installed "$model"; then
        ok "Ollama-Modell bereits vorhanden: ${model}"
        return 0
    fi

    printf '\n'
    info "Benötigtes Ollama-Modell: ${model}"

    if ! ask_yes_no "KI-Modell jetzt herunterladen?"; then
        error "Das ausgewählte KI-Modell wurde nicht installiert."
        return 1
    fi

    info "Lade Modell ${model} ..."

    if ! ollama pull "$model"; then
        error "Modell konnte nicht heruntergeladen werden: ${model}"
        return 1
    fi

    if ! ollama_model_installed "$model"; then
        error "Modell wurde nach dem Download nicht gefunden: ${model}"
        return 1
    fi

    ok "Ollama-Modell installiert: ${model}"
}

# ------------------------------------------------------------
# Arbeitsspeicher für lokales KI-Modell prüfen
# ------------------------------------------------------------

check_ollama_memory() {
    local model="$1"
    local mem_kb
    local swap_kb
    local mem_mib
    local swap_mib

    mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    swap_kb="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"

    mem_mib=$((mem_kb / 1024))
    swap_mib=$((swap_kb / 1024))

    info "RAM verfügbar: ca. $((mem_mib / 1024)) GiB"
    info "Swap vorhanden: ca. $((swap_mib / 1024)) GiB"

    case "$model" in
        qwen3:4b)
            if (( mem_mib < 6144 )); then
                warn "Für qwen3:4b ist wenig Arbeitsspeicher vorhanden."
                warn "Bei der Modellverarbeitung kann Linux den Ollama-Prozess wegen Speichermangels beenden."
                warn "Mindestens 6 GiB nutzbarer RAM werden empfohlen; 8 GiB sind sinnvoll."

                if (( swap_mib == 0 )); then
                    warn "Zusätzlich ist kein Swap eingerichtet."
                fi

                if ! ask_yes_no "Ollama und qwen3:4b trotzdem einrichten?"; then
                    warn "Ollama-Konfiguration auf Wunsch abgebrochen."
                    return 1
                fi

            elif (( mem_mib < 7168 )); then
                warn "qwen3:4b sollte funktionieren, 8 GiB RAM bieten jedoch mehr Reserve."

            else
                ok "Arbeitsspeicher für qwen3:4b ausreichend."
            fi
            ;;

        *)
            info "Für das Modell '$model' ist keine spezielle RAM-Prüfung hinterlegt."
            ;;
    esac

    return 0
}

# ------------------------------------------------------------
# Vollständige Ollama-Vorbereitung
# ------------------------------------------------------------

prepare_ollama() {
    local model="$1"

    printf '\n'
    printf '============================================================\n'
    printf ' Lokale KI / Ollama\n'
    printf '============================================================\n'
    printf '\n'

     check_ollama_memory "$model" || return 1

    install_ollama || return 1
    activate_ollama_service || return 1
    wait_for_ollama || return 1
    install_ollama_model "$model" || return 1

    printf '\n'
    ok "Lokale KI ist einsatzbereit."
}
