#!/usr/bin/env bash


# ============================================================
# LocalDocFlow - Installer
# Programmdateien und Desktop-/systemd-Integration
# ============================================================


# ------------------------------------------------------------
# Installationspfade bestimmen
# Determine installation paths
# ------------------------------------------------------------

determine_install_paths() {
    INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/localdocflow"

    USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

    USER_APPLICATION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

    ok "Installationsverzeichnis: ${INSTALL_DIR}"
}


# ------------------------------------------------------------
# Programmdateien installieren
# Install program files
# ------------------------------------------------------------

install_program_files() {
    local source_bin="${PROJECT_DIR}/bin"
    local target_bin="${INSTALL_DIR}/bin"

    local files=(
        scan_capture.sh
        scan_gui.sh
        scan_gui.py
        scan_learning_watch.sh
        scan_logs.sh
        scan_process.sh
        scan_status.sh
        scan_watch.sh
    )

    local filename

    mkdir -p "$target_bin"

    for filename in "${files[@]}"; do
        if [[ ! -f "${source_bin}/${filename}" ]]; then
            error "Programmdatei fehlt:"
            error "  ${source_bin}/${filename}"
            return 1
        fi
    done

    for filename in "${files[@]}"; do
        install \
            -m 755 \
            "${source_bin}/${filename}" \
            "${target_bin}/${filename}"

        ok "Installiert: ${filename}"
    done
}


# ------------------------------------------------------------
# Template mit Installationspfad erzeugen
# Render template with installation path
# ------------------------------------------------------------

render_install_template() {
    local source="$1"
    local destination="$2"

    if [[ ! -f "$source" ]]; then
        error "Template fehlt:"
        error "  ${source}"
        return 1
    fi

    python3 - \
        "$source" \
        "$destination" \
        "$INSTALL_DIR" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
install_dir = sys.argv[3]

content = source.read_text(encoding="utf-8")
content = content.replace("__INSTALL_DIR__", install_dir)

destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(content, encoding="utf-8")
PY
}

# ------------------------------------------------------------
# Vorhandene Integrationsdatei sichern
# Back up existing integration file
# ------------------------------------------------------------

backup_existing_file() {
    local file="$1"
    local backup

    if [[ ! -e "$file" ]]; then
        return 0
    fi

    backup="${file}.bak.$(date '+%Y%m%d-%H%M%S')"

    cp -a "$file" "$backup"

    ok "Vorhandene Datei gesichert:"
    printf '  %s\n' "$backup"
}

# ------------------------------------------------------------
# systemd-Userdienste erzeugen
# Create systemd user services
# ------------------------------------------------------------

install_systemd_units() {
    mkdir -p "$USER_SYSTEMD_DIR"

    backup_existing_file \
        "${USER_SYSTEMD_DIR}/localdocflow-watcher.service"

    backup_existing_file \
        "${USER_SYSTEMD_DIR}/localdocflow-learning-watcher.service"

    render_install_template \
        "${TEMPLATE_DIR}/localdocflow-watcher.service.template" \
        "${USER_SYSTEMD_DIR}/localdocflow-watcher.service"

    render_install_template \
        "${TEMPLATE_DIR}/localdocflow-learning-watcher.service.template" \
        "${USER_SYSTEMD_DIR}/localdocflow-learning-watcher.service"

    chmod 644 \
        "${USER_SYSTEMD_DIR}/localdocflow-watcher.service" \
        "${USER_SYSTEMD_DIR}/localdocflow-learning-watcher.service"

    ok "systemd-Userdienste installiert."
}

# ------------------------------------------------------------
# systemd-Userdienste aktivieren und starten
# Enable and start systemd user services
# ------------------------------------------------------------

activate_systemd_units() {
    if ! command -v systemctl >/dev/null 2>&1; then
        error "systemctl wurde nicht gefunden."
        return 1
    fi

    info "Lade systemd-Benutzerkonfiguration neu ..."

    systemctl --user daemon-reload

    info "Aktiviere Scan-Dienste für den Benutzerstart ..."

    systemctl --user enable \
        localdocflow-watcher.service \
        localdocflow-learning-watcher.service

    info "Starte Scan-Dienste neu ..."

    systemctl --user restart \
        localdocflow-watcher.service \
        localdocflow-learning-watcher.service

    ok "systemd-Userdienste aktiviert und gestartet."
}


# ------------------------------------------------------------
# systemd-Userdienste prüfen
# Check systemd user services
# ------------------------------------------------------------

verify_systemd_units() {
    local failed=0
    local service

    for service in \
        localdocflow-watcher.service \
        localdocflow-learning-watcher.service
    do
        if systemctl --user is-enabled \
            "$service" >/dev/null 2>&1; then

            ok "${service} ist aktiviert"
        else
            error "${service} ist nicht aktiviert"
            failed=1
        fi

        if systemctl --user is-active \
            "$service" >/dev/null 2>&1; then

            ok "${service} läuft"
        else
            error "${service} läuft nicht"
            failed=1

            journalctl --user \
                -u "$service" \
                -n 15 \
                --no-pager \
                >&2 || true
        fi
    done

    return "$failed"
}

# ------------------------------------------------------------
# Desktop-Starter erzeugen
# Create desktop launcher
# ------------------------------------------------------------

install_desktop_launcher() {
    mkdir -p "$USER_APPLICATION_DIR"

    backup_existing_file \
        "${USER_APPLICATION_DIR}/localdocflow.desktop"

    render_install_template \
        "${TEMPLATE_DIR}/localdocflow.desktop.template" \
        "${USER_APPLICATION_DIR}/localdocflow.desktop"

    chmod 644 \
        "${USER_APPLICATION_DIR}/localdocflow.desktop"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database \
            "$USER_APPLICATION_DIR" \
            >/dev/null 2>&1 || true
    fi

    ok "Desktop-Starter installiert."
}


# ------------------------------------------------------------
# Installierte Dateien prüfen
# Validate installed files
# ------------------------------------------------------------

verify_installed_files() {
    local failed=0

    local files=(
        "${INSTALL_DIR}/bin/scan_capture.sh"
        "${INSTALL_DIR}/bin/scan_gui.sh"
        "${INSTALL_DIR}/bin/scan_gui.py"
        "${INSTALL_DIR}/bin/scan_learning_watch.sh"
        "${INSTALL_DIR}/bin/scan_logs.sh"
        "${INSTALL_DIR}/bin/scan_process.sh"
        "${INSTALL_DIR}/bin/scan_status.sh"
        "${INSTALL_DIR}/bin/scan_watch.sh"
        "${USER_SYSTEMD_DIR}/localdocflow-watcher.service"
        "${USER_SYSTEMD_DIR}/localdocflow-learning-watcher.service"
        "${USER_APPLICATION_DIR}/localdocflow.desktop"
    )

    local file

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            ok "Vorhanden: ${file}"
        else
            error "Fehlt: ${file}"
            failed=1
        fi
    done

    return "$failed"
}

# ------------------------------------------------------------
# Abschließende Installationsprüfung
# Final installation check
# ------------------------------------------------------------

final_installation_check() {
    local status_script="${INSTALL_DIR}/bin/scan_status.sh"
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow"
    local failed=0

    printf '\n'
    printf '============================================================\n'
    printf ' Abschlussprüfung der Installation\n'
    printf '============================================================\n'
    printf '\n'

    # Zentrale Systemkonfiguration
    # Central system configuration
    if [[ -f "${config_dir}/system.conf" ]]; then
        ok "system.conf vorhanden"
    else
        error "system.conf fehlt"
        failed=1
    fi

    # Fachliche Konfigurationsdateien
    local config_file

    for config_file in \
        senders.json \
        document_types.json \
        mapping.json \
        learning_config.json \
        learning.json \
        pending_learning.json
    do
        if [[ -f "${config_dir}/${config_file}" ]]; then
            ok "${config_file} vorhanden"
        else
            error "${config_file} fehlt"
            failed=1
        fi
    done

    # Installierte Dateien
    if ! verify_installed_files; then
        failed=1
    fi

    # Dienste
    # Services
    if ! verify_systemd_units; then
        failed=1
    fi

    # Vollständiger Systemstatus
    if [[ -x "$status_script" ]]; then
        printf '\n'
        info "Führe vollständigen Systemstatus aus ..."
        printf '\n'

        if ! "$status_script"; then
            error "Systemstatus meldet mindestens einen kritischen Fehler."
            failed=1
        fi
    else
        error "scan_status.sh ist nicht ausführbar."
        failed=1
    fi

    printf '\n'
    printf '============================================================\n'

    if (( failed == 0 )); then
        printf ' Installation erfolgreich abgeschlossen\n'
        printf '============================================================\n'
        return 0
    fi

    printf ' Installation mit Fehlern abgeschlossen\n'
    printf '============================================================\n'
    return 1
}
