#!/bin/bash
# ============================================
# ECS-Studio — Bootstrap
# Erstellt ~/ECS-Studio und installiert Tools
# ============================================

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

ECS_HOME="$HOME/ECS-Studio"
TOOLS_DIR="$ECS_HOME/.tools"
GH_DIR="$TOOLS_DIR/gh"
GH_BIN="$GH_DIR/bin/gh"

# Plattform erkennen (Linux, macOS, WSL)
detect_platform() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

PLATFORM=$(detect_platform)

# ============================================
# Hilfsfunktionen
# ============================================

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}ECS-Studio — Setup${NC}                   ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

confirm() {
    local prompt="$1"
    local response
    echo -ne "${CYAN}?${NC} ${prompt} ${BOLD}[J/n]${NC}: "
    read -r response
    case "$response" in
        [nN]|[nN][eE][iI][nN]) return 1 ;;
        *) return 0 ;;
    esac
}

# ============================================
# Prüfungen
# ============================================

check_dependencies() {
    print_step "Prüfe Abhängigkeiten..."

    local missing=()

    # curl prüfen
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    # unzip prüfen (für GitHub CLI Installation)
    if ! command -v unzip &> /dev/null; then
        missing+=("unzip")
    fi

    # git prüfen
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Fehlende Abhängigkeiten: ${missing[*]}"
        echo ""
        echo "Bitte installiere die fehlenden Pakete:"
        echo ""

        case "$PLATFORM" in
            macos)
                echo -e "  ${CYAN}xcode-select --install${NC}   # für git"
                echo -e "  ${CYAN}brew install ${missing[*]}${NC}"
                ;;
            wsl|linux)
                echo -e "  ${CYAN}sudo apt install ${missing[*]}${NC}     # Debian/Ubuntu"
                echo -e "  ${CYAN}sudo dnf install ${missing[*]}${NC}     # Fedora/RHEL"
                echo -e "  ${CYAN}sudo pacman -S ${missing[*]}${NC}       # Arch Linux"
                ;;
            *)
                echo -e "  Installiere: ${missing[*]}"
                ;;
        esac

        echo ""
        exit 1
    fi

    print_success "Alle Abhängigkeiten vorhanden"
}

check_platform() {
    print_step "Prüfe Betriebssystem..."

    case "$PLATFORM" in
        macos)
            local macos_version
            macos_version=$(sw_vers -productVersion)
            local major_version
            major_version=$(echo "$macos_version" | cut -d. -f1)

            if [ "$major_version" -lt 12 ]; then
                print_error "macOS 12 (Monterey) oder neuer wird benötigt."
                exit 1
            fi
            print_success "macOS $macos_version"
            ;;
        linux)
            print_success "Linux ($(uname -r))"
            ;;
        wsl)
            print_success "Windows WSL ($(uname -r))"
            ;;
        *)
            print_warning "Unbekanntes System: $OSTYPE"
            print_warning "Das Script könnte trotzdem funktionieren."
            ;;
    esac
}

check_xcode_clt() {
    # Nur auf macOS relevant
    if [ "$PLATFORM" != "macos" ]; then
        return 0
    fi

    print_step "Prüfe Xcode Command Line Tools..."

    if ! xcode-select -p &>/dev/null; then
        print_warning "Xcode Command Line Tools werden benötigt."
        echo ""
        echo -e "${YELLOW}Wir müssen einige Tools von Apple installieren - etwa 1,5 GB.${NC}"
        echo -e "${YELLOW}Ein Popup-Fenster wird erscheinen. Finde es! Dann klicke 'Installieren'.${NC}"
        echo ""
        xcode-select --install

        echo ""
        while true; do
            echo -e "${YELLOW}Drücke ENTER nachdem die Installation abgeschlossen ist...${NC}"
            read -r

            if xcode-select -p &>/dev/null; then
                break
            fi

            print_warning "Installation noch nicht abgeschlossen. Bitte warten..."
            echo ""
        done
    fi

    print_success "Xcode Command Line Tools installiert"
}

# ============================================
# Installation
# ============================================

create_directories() {
    print_step "Erstelle ECS-Studio Verzeichnis..."

    mkdir -p "$TOOLS_DIR"
    mkdir -p "$GH_DIR"

    print_success "$ECS_HOME erstellt"
}

install_gh() {
    print_step "Installiere GitHub CLI..."

    # Prüfen ob bereits installiert
    if [ -x "$GH_BIN" ]; then
        print_success "GitHub CLI bereits installiert"
        return 0
    fi

    local gh_version="2.65.0"
    local arch
    local os_name
    local archive_ext
    local extract_cmd

    # Architektur ermitteln
    case "$(uname -m)" in
        arm64|aarch64) arch="arm64" ;;
        x86_64) arch="amd64" ;;
        i386|i686) arch="386" ;;
        *)
            print_error "Unbekannte Architektur: $(uname -m)"
            exit 1
            ;;
    esac

    # Betriebssystem und Archiv-Format ermitteln
    case "$PLATFORM" in
        macos)
            os_name="macOS"
            archive_ext="zip"
            ;;
        linux|wsl)
            os_name="linux"
            archive_ext="tar.gz"
            ;;
        *)
            print_error "Unbekanntes Betriebssystem: $PLATFORM"
            exit 1
            ;;
    esac

    local gh_archive="gh_${gh_version}_${os_name}_${arch}.${archive_ext}"
    local gh_url="https://github.com/cli/cli/releases/download/v${gh_version}/${gh_archive}"
    local tmp_dir="/tmp/gh-install-$$"

    mkdir -p "$tmp_dir"

    print_step "Lade gh v${gh_version} herunter..."

    if curl -fsSL "$gh_url" -o "$tmp_dir/$gh_archive"; then
        # Entpacken je nach Format
        if [ "$archive_ext" = "zip" ]; then
            unzip -q "$tmp_dir/$gh_archive" -d "$tmp_dir"
        else
            tar -xzf "$tmp_dir/$gh_archive" -C "$tmp_dir"
        fi

        cp -r "$tmp_dir/gh_${gh_version}_${os_name}_${arch}/"* "$GH_DIR/"
        chmod +x "$GH_BIN"
        rm -rf "$tmp_dir"
        print_success "GitHub CLI installiert"
    else
        print_error "Download fehlgeschlagen"
        rm -rf "$tmp_dir"
        exit 1
    fi
}

download_setup_script() {
    print_step "Lade Setup-Script herunter..."

    local setup_url="https://raw.githubusercontent.com/gameplanXXL/ecs-setup/main/setup.sh"

    if curl -fsSL "$setup_url" -o "$TOOLS_DIR/setup.sh"; then
        chmod +x "$TOOLS_DIR/setup.sh"
        print_success "Setup-Script installiert"
    else
        print_error "Download fehlgeschlagen"
        exit 1
    fi

    # Symlink erstellen
    ln -sf ".tools/setup.sh" "$ECS_HOME/setup"
    print_success "Shortcut erstellt: ~/ECS-Studio/setup"
}

github_login() {
    print_step "GitHub Anmeldung..."

    # Prüfen ob bereits eingeloggt
    if "$GH_BIN" auth status &>/dev/null; then
        print_success "Bereits bei GitHub angemeldet"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}Ein Browser-Fenster wird sich öffnen.${NC}"
    echo -e "${YELLOW}Bitte melde dich bei GitHub an und autorisiere den Zugriff.${NC}"
    echo -e "${YELLOW}Drücke jetzt ENTER.${NC}"
    read -r

    if "$GH_BIN" auth login --web --git-protocol https; then
        print_success "GitHub Login erfolgreich"
    else
        print_error "GitHub Login fehlgeschlagen"
        echo ""
        echo "Du kannst es später erneut versuchen mit:"
        echo "  $GH_BIN auth login"
        echo ""
    fi
}

# ============================================
# Hauptprogramm
# ============================================

main() {
    print_header

    echo "Dieses Setup erstellt:"
    echo "  • ~/ECS-Studio/ — darunter später je Projekt ein Verzeichnis"
    echo "  • GitHub CLI"
    if [ "$PLATFORM" = "macos" ]; then
        echo "  • Xcode CLI Tools von Apple (falls nötig)"
    fi
    echo "  • Setup-Script für neue Projekte"
    echo ""

    if ! confirm "Möchtest du fortfahren?"; then
        echo "Abgebrochen."
        exit 0
    fi

    echo ""

    check_dependencies
    check_platform
    check_xcode_clt
    create_directories
    install_gh
    download_setup_script
    github_login

    # Abschluss
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Fertig! Dein ECS-Studio ist bereit.${NC}"
    echo ""
    echo "  Nächster Schritt — Erstelle dein erstes Projekt:"
    echo ""
    echo -e "    ${CYAN}cd ~/ECS-Studio${NC}"
    echo -e "    ${CYAN}./setup${NC}"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
