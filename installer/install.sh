#!/usr/bin/env bash

set -Eeuo pipefail


# ============================================================
# LocalDocFlow - Installer
# ============================================================
#
# Universeller Installer für die Scan-Automation.
#
# Aktueller Stand:
#   - Betriebssystem erkennen
#   - Paketmanager erkennen
#   - Benutzerumgebung prüfen
#   - Desktop erkennen
#   - Installer-Dateien prüfen
#   - benötigte Programme prüfen
#   - fehlende Pakete ermitteln
#   - fehlende Pakete nach Rückfrage installieren
#   - Installation anschließend erneut prüfen
#
# Die eigentliche Scan-Automation und system.conf werden in
# späteren Schritten installiert bzw. erzeugt.
# ============================================================


# ------------------------------------------------------------
# Pfade des Installers
# Installer paths
# ------------------------------------------------------------

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

PROJECT_DIR="$(
    cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1
    pwd
)"

TEMPLATE_DIR="${SCRIPT_DIR}/templates"
DEFAULT_DIR="${SCRIPT_DIR}/defaults"


# ------------------------------------------------------------
# Globale Variablen
# Global variables
# ------------------------------------------------------------

OS_ID=""
OS_NAME=""
OS_VERSION=""

PACKAGE_MANAGER=""

INSTALL_USER=""
INSTALL_HOME=""

declare -a MISSING_PACKAGES=()


# ------------------------------------------------------------
# Ausgabe
# Output
# ------------------------------------------------------------

info() {
    printf '[INFO] %s\n' "$*"
}

ok() {
    printf '[ OK ] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

error() {
    printf '[FEHLER] %s\n' "$*" >&2
}


# ------------------------------------------------------------
# Betriebssystem erkennen
# Detect operating system
# ------------------------------------------------------------

detect_os() {
    if [[ ! -r /etc/os-release ]]; then
        error "/etc/os-release wurde nicht gefunden."
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-${NAME:-Unbekanntes Linux}}"
    OS_VERSION="${VERSION_ID:-unknown}"

    ok "Betriebssystem: ${OS_NAME}"
}


# ------------------------------------------------------------
# Paketmanager erkennen
# Detect package manager
# ------------------------------------------------------------

detect_package_manager() {
    PACKAGE_MANAGER=""

    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"

    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"

    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"

    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
    fi

    if [[ -n "$PACKAGE_MANAGER" ]]; then
        ok "Paketmanager: ${PACKAGE_MANAGER}"
    else
        warn "Kein unterstützter Paketmanager erkannt."
    fi
}


# ------------------------------------------------------------
# Benutzerumgebung prüfen
# Validate user environment
# ------------------------------------------------------------

check_user_environment() {
    if [[ "$EUID" -eq 0 ]]; then
        error "Der Installer soll nicht direkt als root gestartet werden."
        error "Bitte als normaler Benutzer starten."
        error "sudo wird vom Installer nur bei Bedarf verwendet."
        return 1
    fi

    INSTALL_USER="$USER"
    INSTALL_HOME="$HOME"

    ok "Benutzer: ${INSTALL_USER}"
    ok "Home-Verzeichnis: ${INSTALL_HOME}"

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user show-environment >/dev/null 2>&1; then
            ok "systemd-Benutzerdienste verfügbar"
        else
            warn "systemd --user ist vorhanden, aber die Benutzersitzung ist derzeit nicht erreichbar."
        fi
    else
        warn "systemctl wurde nicht gefunden."
    fi
}


# ------------------------------------------------------------
# Desktop-Umgebung erkennen
# Detect desktop environment
# ------------------------------------------------------------

detect_desktop() {
    local desktop="${XDG_CURRENT_DESKTOP:-unknown}"
    local session="${XDG_SESSION_DESKTOP:-unknown}"

    info "Desktop: ${desktop}"
    info "Sitzung: ${session}"
}


# ------------------------------------------------------------
# Projektstruktur prüfen
# Validate project structure
# ------------------------------------------------------------

check_installer_files() {
    local failed=0

    if [[ -d "$PROJECT_DIR/bin" ]]; then
        ok "Programmverzeichnis vorhanden"
    else
        error "Programmverzeichnis fehlt: ${PROJECT_DIR}/bin"
        failed=1
    fi

    if [[ -f "${TEMPLATE_DIR}/system.conf.template" ]]; then
        ok "system.conf-Vorlage vorhanden"
    else
        error "system.conf-Vorlage fehlt"
        failed=1
    fi

    if [[ -f "${DEFAULT_DIR}/pending_learning.json" ]]; then
        ok "pending_learning.json-Vorlage vorhanden"
    else
        error "pending_learning.json-Vorlage fehlt"
        failed=1
    fi

    if [[ -f "${DEFAULT_DIR}/learning.json" ]]; then
        ok "learning.json-Vorlage vorhanden"
    else
        error "learning.json-Vorlage fehlt"
        failed=1
    fi

    if [[ -f "${DEFAULT_DIR}/learning_config.json" ]]; then
        ok "learning_config.json-Vorlage vorhanden"
    else
        error "learning_config.json-Vorlage fehlt"
        failed=1
    fi

    return "$failed"
}


# ------------------------------------------------------------
# Bereits vorhandene Programme anzeigen
# Show already installed programs
# ------------------------------------------------------------

check_existing_components() {
    local commands=(
        scanimage
        tesseract
        ocrmypdf
        pdftotext
        pdfinfo
        jq
        inotifywait
        python3
        ollama
    )

    local cmd

    printf '\n'
    info "Vorhandene Komponenten:"

    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '  [vorhanden] %s\n' "$cmd"
        else
            printf '  [fehlt]    %s\n' "$cmd"
        fi
    done
}


# ------------------------------------------------------------
# Hilfsfunktion für Paketliste
# Helper for package list
# ------------------------------------------------------------

add_package() {
    local package="$1"

    if [[ " ${MISSING_PACKAGES[*]} " != *" ${package} "* ]]; then
        MISSING_PACKAGES+=("$package")
    fi
}


# ------------------------------------------------------------
# Fehlende Abhängigkeiten ermitteln
# Determine missing dependencies
# ------------------------------------------------------------

collect_missing_dependencies() {
    MISSING_PACKAGES=()

    case "$PACKAGE_MANAGER" in

        apt)
            command -v scanimage >/dev/null 2>&1 \
                || add_package "sane-utils"

            command -v tesseract >/dev/null 2>&1 \
                || add_package "tesseract-ocr"

            command -v ocrmypdf >/dev/null 2>&1 \
                || add_package "ocrmypdf"

            command -v pdftotext >/dev/null 2>&1 \
                || add_package "poppler-utils"

            command -v pdfinfo >/dev/null 2>&1 \
                || add_package "poppler-utils"

            command -v jq >/dev/null 2>&1 \
                || add_package "jq"

            command -v inotifywait >/dev/null 2>&1 \
                || add_package "inotify-tools"

            command -v python3 >/dev/null 2>&1 \
                || add_package "python3"

            if ! command -v convert >/dev/null 2>&1 &&
               ! command -v magick >/dev/null 2>&1; then
                add_package "imagemagick"
            fi

            command -v tiffcp >/dev/null 2>&1 \
                || add_package "libtiff-tools"

            command -v tiff2pdf >/dev/null 2>&1 \
                || add_package "libtiff-tools"

            command -v setsid >/dev/null 2>&1 \
                || add_package "util-linux"

            command -v curl >/dev/null 2>&1 \
                || add_package "curl"

            python3 -c 'import PyQt6' >/dev/null 2>&1 \
                || add_package "python3-pyqt6"

            if ! tesseract --list-langs 2>/dev/null |
                 grep -qx 'deu'; then
                add_package "tesseract-ocr-deu"
            fi

            if ! tesseract --list-langs 2>/dev/null |
                 grep -qx 'eng'; then
                add_package "tesseract-ocr-eng"
            fi
            ;;


        dnf)
            command -v scanimage >/dev/null 2>&1 \
                || add_package "sane-backends"

            command -v tesseract >/dev/null 2>&1 \
                || add_package "tesseract"

            command -v ocrmypdf >/dev/null 2>&1 \
                || add_package "ocrmypdf"

            command -v pdftotext >/dev/null 2>&1 \
                || add_package "poppler-utils"

            command -v pdfinfo >/dev/null 2>&1 \
                || add_package "poppler-utils"

            command -v jq >/dev/null 2>&1 \
                || add_package "jq"

            command -v inotifywait >/dev/null 2>&1 \
                || add_package "inotify-tools"

            command -v python3 >/dev/null 2>&1 \
                || add_package "python3"

            if ! command -v convert >/dev/null 2>&1 &&
               ! command -v magick >/dev/null 2>&1; then
                add_package "ImageMagick"
            fi

            command -v tiffcp >/dev/null 2>&1 \
                || add_package "libtiff-tools"

            command -v tiff2pdf >/dev/null 2>&1 \
                || add_package "libtiff-tools"

            command -v setsid >/dev/null 2>&1 \
                || add_package "util-linux"

            command -v curl >/dev/null 2>&1 \
                || add_package "curl"

            python3 -c 'import PyQt6' >/dev/null 2>&1 \
                || add_package "python3-qt6"

            if ! tesseract --list-langs 2>/dev/null |
                 grep -qx 'deu'; then
                add_package "tesseract-langpack-deu"
            fi

            if ! tesseract --list-langs 2>/dev/null |
                 grep -qx 'eng'; then
                add_package "tesseract-langpack-eng"
            fi
            ;;


        pacman)
            command -v scanimage >/dev/null 2>&1 \
                || add_package "sane"

            command -v tesseract >/dev/null 2>&1 \
                || add_package "tesseract"

            command -v ocrmypdf >/dev/null 2>&1 \
                || add_package "ocrmypdf"

            command -v pdftotext >/dev/null 2>&1 \
                || add_package "poppler"

            command -v pdfinfo >/dev/null 2>&1 \
                || add_package "poppler"

            command -v jq >/dev/null 2>&1 \
                || add_package "jq"

            command -v inotifywait >/dev/null 2>&1 \
                || add_package "inotify-tools"

            command -v python3 >/dev/null 2>&1 \
                || add_package "python"

            if ! command -v convert >/dev/null 2>&1 &&
               ! command -v magick >/dev/null 2>&1; then
                add_package "imagemagick"
            fi

            command -v tiffcp >/dev/null 2>&1 \
                || add_package "libtiff"

            command -v tiff2pdf >/dev/null 2>&1 \
                || add_package "libtiff"

            command -v setsid >/dev/null 2>&1 \
                || add_package "util-linux"

            command -v curl >/dev/null 2>&1 \
                || add_package "curl"

            python3 -c 'import PyQt6' >/dev/null 2>&1 \
                || add_package "python-pyqt6"

            if ! tesseract --list-langs 2>/dev/null |
                 grep -qx 'deu'; then
                add_package "tesseract-data-deu"
            fi

            if ! tesseract --list-langs 2>/dev/null |
                 grep -qx 'eng'; then
                add_package "tesseract-data-eng"
            fi
            ;;


        zypper)
            warn "Automatische Paketzuordnung für zypper ist noch nicht aktiviert."
            return 0
            ;;


        *)
            warn "Keine automatische Paketzuordnung möglich."
            return 0
            ;;
    esac
}


# ------------------------------------------------------------
# Fehlende Pakete anzeigen
# Show missing packages
# ------------------------------------------------------------

show_missing_dependencies() {
    printf '\n'
    info "Benötigte Paketinstallation:"

    if (( ${#MISSING_PACKAGES[@]} == 0 )); then
        ok "Alle derzeit geprüften Abhängigkeiten sind vorhanden."
        return 0
    fi

    local package

    for package in "${MISSING_PACKAGES[@]}"; do
        printf '  [installieren] %s\n' "$package"
    done

    printf '\n'

    case "$PACKAGE_MANAGER" in
        apt)
            info "Vorgesehener Installationsbefehl:"
            printf '  sudo apt-get install'
            ;;

        dnf)
            info "Vorgesehener Installationsbefehl:"
            printf '  sudo dnf install'
            ;;

        pacman)
            info "Vorgesehener Installationsbefehl:"
            printf '  sudo pacman -S --needed'
            ;;

        *)
            return 0
            ;;
    esac

    printf ' %q' "${MISSING_PACKAGES[@]}"
    printf '\n'
}


# ------------------------------------------------------------
# Ja/Nein-Rückfrage
# Yes/no prompt
# ------------------------------------------------------------

ask_yes_no() {
    local prompt="$1"
    local answer

    while true; do
        read -r -p "${prompt} [j/N]: " answer

        case "${answer,,}" in
            j|ja|y|yes)
                return 0
                ;;

            ""|n|nein|no)
                return 1
                ;;

            *)
                warn "Bitte mit j oder n antworten."
                ;;
        esac
    done
}


# ------------------------------------------------------------
# Fehlende Pakete installieren
# Install missing packages
# ------------------------------------------------------------

install_missing_dependencies() {
    if (( ${#MISSING_PACKAGES[@]} == 0 )); then
        return 0
    fi

    if [[ -z "$PACKAGE_MANAGER" ]]; then
        error "Kein unterstützter Paketmanager vorhanden."
        return 1
    fi

    printf '\n'

    if ! ask_yes_no "Fehlende Systempakete jetzt installieren?"; then
        warn "Paketinstallation übersprungen."
        return 0
    fi

    info "Installiere fehlende Systempakete ..."

    case "$PACKAGE_MANAGER" in

        apt)
            sudo apt-get update
            sudo apt-get install -y "${MISSING_PACKAGES[@]}"
            ;;

        dnf)
            sudo dnf install -y "${MISSING_PACKAGES[@]}"
            ;;

        pacman)
            sudo pacman -S --needed --noconfirm \
                "${MISSING_PACKAGES[@]}"
            ;;

        zypper)
            error "Automatische Installation über zypper ist noch nicht konfiguriert."
            return 1
            ;;

        *)
            error "Nicht unterstützter Paketmanager: ${PACKAGE_MANAGER}"
            return 1
            ;;
    esac

    ok "Paketinstallation abgeschlossen."
}


# ------------------------------------------------------------
# Abhängigkeiten nach Installation erneut prüfen
# Re-check dependencies after installation
# ------------------------------------------------------------

verify_dependencies() {
    collect_missing_dependencies

    if (( ${#MISSING_PACKAGES[@]} == 0 )); then
        ok "Abhängigkeitsprüfung erfolgreich."
        return 0
    fi

    error "Es fehlen weiterhin benötigte Pakete:"

    local package

    for package in "${MISSING_PACKAGES[@]}"; do
        printf '  %s\n' "$package" >&2
    done

    return 1
}


# ------------------------------------------------------------
# Hauptprogramm
# Main program
# ------------------------------------------------------------

main() {
    printf '\n'
    printf '============================================================\n'
    printf ' LocalDocFlow - Installer\n'
    printf '============================================================\n'
    printf '\n'

    info "Installer-Verzeichnis: ${SCRIPT_DIR}"
    info "Projekt-Verzeichnis:   ${PROJECT_DIR}"

    printf '\n'

    detect_os
    detect_package_manager
    check_user_environment
    detect_desktop

    printf '\n'

    check_installer_files

    check_existing_components
    collect_missing_dependencies
    show_missing_dependencies
    install_missing_dependencies
    verify_dependencies

# Interaktive Systemkonfiguration laden
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/configuration.sh"

configure_installation

ACTIVE_SYSTEM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/localdocflow/system.conf"

if [[ ! -f "$ACTIVE_SYSTEM_CONFIG" ]]; then
    error "Keine system.conf vorhanden."
    error "Ohne Systemkonfiguration kann die Installation nicht fortgesetzt werden."
    exit 1
fi

# Ollama und lokales KI-Modell vorbereiten
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/ollama.sh"

prepare_ollama "$OLLAMA_MODEL_SELECTION"

# Programmdateien und Desktop-/systemd-Integration laden
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/lib/install_files.sh"

determine_install_paths

printf '\n'
info "Geplanter Programm-Installationsort:"
printf '  %s\n' "$INSTALL_DIR"
printf '\n'

if ask_yes_no "Programmdateien und Integration jetzt installieren?"; then
    install_program_files
    install_systemd_units
    install_desktop_launcher

    activate_systemd_units

    final_installation_check
else
    warn "Installation der Programmdateien wurde übersprungen."
fi

    printf '\n'
    printf '============================================================\n'
    printf ' Installer-Durchlauf abgeschlossen\n'
    printf '============================================================\n'
    printf '\n'

    info "Grundlegende Systemabhängigkeiten sind geprüft."
    }


main "$@"
