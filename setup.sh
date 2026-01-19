#!/bin/bash
# ============================================
# ECS-Studio — Neues Projekt erstellen
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
CACHE_DIR="$ECS_HOME/.cache"
CACHE_AUTHOR="$CACHE_DIR/author_name"
GH_BIN="$TOOLS_DIR/gh/bin/gh"

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

# Plattformunabhängiges sed -i
sed_inplace() {
    if [ "$PLATFORM" = "macos" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ============================================
# Hilfsfunktionen
# ============================================

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}ECS-Studio — Neues Projekt${NC}             ${CYAN}║${NC}"
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

ask_question() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        echo -ne "${CYAN}?${NC} ${prompt} ${BOLD}[${default}]${NC}: " >&2
        read -r result
        echo "${result:-$default}"
    else
        echo -ne "${CYAN}?${NC} ${prompt}: " >&2
        read -r result
        echo "$result"
    fi
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

# Andere Projekte im ECS_HOME finden (außer dem aktuellen)
get_other_projects() {
    local current_project="$1"
    local projects=()

    # Alle Unterverzeichnisse in ECS_HOME durchsuchen
    for dir in "$ECS_HOME"/*/; do
        # Verzeichnisname extrahieren
        local name=$(basename "$dir")

        # Versteckte Ordner und aktuelles Projekt überspringen
        [[ "$name" == .* ]] && continue
        [[ "$name" == "$current_project" ]] && continue

        # Prüfen ob es ein ECS-Projekt ist (hat _bmad/ecs Ordner)
        if [ -d "$dir/_bmad/ecs" ]; then
            projects+=("$name")
        fi
    done

    # Projekte zurückgeben (eines pro Zeile)
    printf '%s\n' "${projects[@]}"
}

# ============================================
# Prüfungen
# ============================================

check_setup() {
    # Prüfen ob gh installiert ist
    if [ ! -x "$GH_BIN" ]; then
        print_error "GitHub CLI nicht gefunden."
        echo ""
        echo "Bitte führe zuerst das Bootstrap-Script aus:"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gameplanXXL/ecs-setup/main/bootstrap.sh)"'
        echo ""
        exit 1
    fi

    # Prüfen ob eingeloggt
    if ! "$GH_BIN" auth status &>/dev/null; then
        print_warning "Du bist nicht bei GitHub angemeldet."
        echo ""

        if confirm "Jetzt anmelden?"; then
            "$GH_BIN" auth login --web --git-protocol https
        else
            print_error "GitHub-Anmeldung erforderlich."
            exit 1
        fi
    fi

    # GitHub-Username holen
    GH_USER=$("$GH_BIN" api user --jq '.login' 2>/dev/null)
    if [ -z "$GH_USER" ]; then
        print_error "Konnte GitHub-Benutzernamen nicht ermitteln."
        exit 1
    fi
}

check_access() {
    print_step "Prüfe Zugang zu ECS-Studio..."

    if ! "$GH_BIN" repo view gameplanXXL/ecs-studio &>/dev/null; then
        print_error "Du hast keinen Zugang zum ECS-Studio Repository."
        echo ""
        echo "Bitte kontaktiere den Administrator und teile deinen"
        echo "GitHub-Benutzernamen mit, um Zugang zu erhalten."
        echo ""
        echo "Dein GitHub-Benutzername: $GH_USER"
        echo ""
        exit 1
    fi

    print_success "Zugang bestätigt"
}

# ============================================
# Projekt erstellen
# ============================================

choose_project_name() {
    while true; do
        echo ""
        PROJECT_NAME=$(ask_question "Wie soll dein Projekt heißen?" "MeinBuch")

        # Leerzeichen und Sonderzeichen entfernen
        PROJECT_NAME=$(echo "$PROJECT_NAME" | tr -cd '[:alnum:]-_')

        if [ -z "$PROJECT_NAME" ]; then
            PROJECT_NAME="MeinBuch"
        fi

        PROJECT_DIR="$ECS_HOME/$PROJECT_NAME"
        REPO_NAME="$GH_USER/$PROJECT_NAME"

        # Prüfen ob lokal bereits existiert
        if [ -d "$PROJECT_DIR" ]; then
            print_warning "Projekt '$PROJECT_NAME' existiert bereits lokal."
            echo ""
            echo "  1) Anderen Namen wählen"
            echo "  2) Bestehendes Projekt öffnen"
            echo "  3) ECS-System aktualisieren (von GitHub)"

            # Prüfen ob andere Projekte existieren
            local other_projects
            other_projects=$(get_other_projects "$PROJECT_NAME")
            local has_other_projects=false
            if [ -n "$other_projects" ]; then
                has_other_projects=true
                echo "  4) ECS-System von anderem Projekt kopieren"
            fi

            echo ""
            local choice
            choice=$(ask_question "Was möchtest du tun?" "1")

            case "$choice" in
                2)
                    USE_EXISTING_LOCAL=true
                    return 0
                    ;;
                3)
                    UPDATE_ECS=true
                    return 0
                    ;;
                4)
                    if [ "$has_other_projects" = true ]; then
                        # Andere Projekte auflisten
                        echo ""
                        echo "  Verfügbare Projekte:"
                        local i=1
                        local project_array=()
                        while IFS= read -r proj; do
                            echo "    $i) $proj"
                            project_array+=("$proj")
                            ((i++))
                        done <<< "$other_projects"
                        echo ""

                        local proj_choice
                        proj_choice=$(ask_question "Von welchem Projekt kopieren?" "1")

                        # Validieren und Projekt auswählen
                        if [[ "$proj_choice" =~ ^[0-9]+$ ]] && [ "$proj_choice" -ge 1 ] && [ "$proj_choice" -le "${#project_array[@]}" ]; then
                            COPY_ECS=true
                            COPY_SOURCE_PROJECT="${project_array[$((proj_choice-1))]}"
                            return 0
                        else
                            print_warning "Ungültige Auswahl."
                            continue
                        fi
                    else
                        continue
                    fi
                    ;;
                *)
                    continue
                    ;;
            esac
        fi

        # Prüfen ob GitHub-Repo bereits existiert
        if "$GH_BIN" repo view "$REPO_NAME" &>/dev/null; then
            print_warning "Repository '$REPO_NAME' existiert bereits auf GitHub."
            echo ""
            echo "  1) Anderen Namen wählen"
            echo "  2) Bestehendes Repo klonen und weiterarbeiten"
            echo ""
            local choice
            choice=$(ask_question "Was möchtest du tun?" "1")

            if [ "$choice" = "2" ]; then
                USE_EXISTING_REMOTE=true
                return 0
            fi
            continue
        fi

        # Name ist frei
        USE_EXISTING_LOCAL=false
        USE_EXISTING_REMOTE=false
        return 0
    done
}

clone_existing_repo() {
    print_step "Klone bestehendes Repository..."

    "$GH_BIN" repo clone "$REPO_NAME" "$PROJECT_DIR"

    print_success "Repository geklont"
}

update_ecs_system() {
    local project_dir="$1"

    # Warnung anzeigen
    echo ""
    print_warning "Das ECS-System wird aktualisiert."
    echo ""
    echo "  Folgende Ordner werden überschrieben:"
    echo "    - _bmad/ecs/"
    echo "    - .claude/commands/ecs/"
    echo "    - docs/"
    echo ""
    echo -e "  ${YELLOW}Achtung:${NC} Eigene Änderungen an ECS-Agenten und"
    echo "           ECS-Workflows gehen dabei verloren!"
    echo ""
    echo "  Deine Daten bleiben erhalten:"
    echo "    - _bmad/_memory/"
    echo "    - inbox/, content/, output/"
    echo ""

    if ! confirm "Fortfahren?"; then
        echo "Abgebrochen."
        return 1
    fi

    # Temporäres Verzeichnis
    local tmp_dir=$(mktemp -d)

    print_step "Lade neueste ECS-Version..."
    "$GH_BIN" repo clone gameplanXXL/ecs-studio "$tmp_dir" -- --depth 1 2>/dev/null

    print_step "Aktualisiere ECS-System..."

    # Alte Verzeichnisse entfernen
    rm -rf "$project_dir/_bmad/ecs"
    rm -rf "$project_dir/.claude/commands/ecs"
    rm -rf "$project_dir/docs"

    # Neue Verzeichnisse kopieren
    cp -r "$tmp_dir/_bmad/ecs" "$project_dir/_bmad/"
    mkdir -p "$project_dir/.claude/commands"
    cp -r "$tmp_dir/.claude/commands/ecs" "$project_dir/.claude/commands/"
    cp -r "$tmp_dir/docs" "$project_dir/"

    # Aufräumen
    rm -rf "$tmp_dir"

    print_success "ECS-System aktualisiert"

    # Git-Commit
    print_step "Committe Änderungen..."
    cd "$project_dir"
    git add -A
    git commit -m "[ECS] System: Update auf neueste Version

Co-Authored-By: Claude <noreply@anthropic.com>" 2>/dev/null || print_warning "Keine Änderungen zum Committen"

    print_success "Fertig!"
}

copy_ecs_system() {
    local target_dir="$1"
    local source_project="$2"
    local source_dir="$ECS_HOME/$source_project"

    # Warnung anzeigen
    echo ""
    print_warning "Das ECS-System wird von '$source_project' kopiert."
    echo ""
    echo "  Folgende Ordner werden überschrieben:"
    echo "    - _bmad/ecs/"
    echo "    - .claude/commands/ecs/"
    echo "    - docs/"
    echo ""
    echo -e "  ${YELLOW}Achtung:${NC} Eigene Änderungen an ECS-Agenten und"
    echo "           ECS-Workflows gehen dabei verloren!"
    echo ""
    echo "  Deine Daten bleiben erhalten:"
    echo "    - _bmad/_memory/"
    echo "    - inbox/, content/, output/"
    echo ""

    if ! confirm "Fortfahren?"; then
        echo "Abgebrochen."
        return 1
    fi

    print_step "Kopiere ECS-System von '$source_project'..."

    # Alte Verzeichnisse entfernen (saubere Kopie)
    rm -rf "$target_dir/_bmad/ecs"
    rm -rf "$target_dir/.claude/commands/ecs"
    rm -rf "$target_dir/docs"

    # Neue Verzeichnisse kopieren
    cp -r "$source_dir/_bmad/ecs" "$target_dir/_bmad/"
    mkdir -p "$target_dir/.claude/commands"
    if [ -d "$source_dir/.claude/commands/ecs" ]; then
        cp -r "$source_dir/.claude/commands/ecs" "$target_dir/.claude/commands/"
    fi
    if [ -d "$source_dir/docs" ]; then
        cp -r "$source_dir/docs" "$target_dir/"
    fi

    print_success "ECS-System kopiert"

    # Git-Commit
    print_step "Committe Änderungen..."
    cd "$target_dir"
    git add -A
    git commit -m "[ECS] System: Kopiert von Projekt '$source_project'

Co-Authored-By: Claude <noreply@anthropic.com>" 2>/dev/null || print_warning "Keine Änderungen zum Committen"

    print_success "Fertig!"
}

create_new_project() {
    # Gecachten Autor-Namen laden (falls vorhanden)
    local cached_author=""
    if [ -f "$CACHE_AUTHOR" ]; then
        cached_author=$(cat "$CACHE_AUTHOR" 2>/dev/null)
    fi

    # Autor-Name abfragen (mit Cache als Default)
    echo ""
    AUTHOR_NAME=$(ask_question "Wie heißt du? (für deine Bücher)" "$cached_author")

    while [ -z "$AUTHOR_NAME" ]; do
        print_warning "Bitte gib deinen Namen ein."
        AUTHOR_NAME=$(ask_question "Wie heißt du?" "$cached_author")
    done

    # Autor-Namen cachen
    mkdir -p "$CACHE_DIR"
    echo "$AUTHOR_NAME" > "$CACHE_AUTHOR"

    # Zusammenfassung
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Zusammenfassung:${NC}"
    echo ""
    echo "  Projekt:       $PROJECT_NAME"
    echo "  Autor:         $AUTHOR_NAME"
    echo "  Ordner:        $PROJECT_DIR"
    echo "  GitHub-Repo:   $REPO_NAME"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
    echo ""

    if ! confirm "Projekt erstellen?"; then
        echo "Abgebrochen."
        exit 0
    fi

    echo ""

    # ECS-Studio klonen
    print_step "Lade ECS-Studio Vorlage..."

    "$GH_BIN" repo clone gameplanXXL/ecs-studio "$PROJECT_DIR" -- --depth 1 2>/dev/null

    # .git entfernen (User bekommt eigenes Repo)
    rm -rf "$PROJECT_DIR/.git"

    print_success "Vorlage geladen"

    # Content-Ordner erstellen
    print_step "Erstelle Content-Ordner..."

    mkdir -p "$PROJECT_DIR/inbox"
    mkdir -p "$PROJECT_DIR/content/tone-of-voice/buch"
    mkdir -p "$PROJECT_DIR/content/tone-of-voice/kurs"
    mkdir -p "$PROJECT_DIR/content/tone-of-voice/reel"
    mkdir -p "$PROJECT_DIR/content/anekdoten"
    mkdir -p "$PROJECT_DIR/content/wissen"
    mkdir -p "$PROJECT_DIR/output/mini-buecher"
    mkdir -p "$PROJECT_DIR/output/ebooks"
    mkdir -p "$PROJECT_DIR/output/buecher"
    mkdir -p "$PROJECT_DIR/output/kurse"
    mkdir -p "$PROJECT_DIR/output/reels"

    # .gitkeep für leere Ordner
    for dir in inbox content/tone-of-voice/buch content/tone-of-voice/kurs content/tone-of-voice/reel \
               content/anekdoten content/wissen output/mini-buecher output/ebooks output/buecher \
               output/kurse output/reels; do
        touch "$PROJECT_DIR/$dir/.gitkeep"
    done

    # README in inbox erstellen
    cat > "$PROJECT_DIR/inbox/README.md" << 'INBOX_README'
# ECS Inbox

Lege hier deinen Content ab — er wird automatisch sortiert.

## Unterstützte Formate

- Dokumente (.pdf, .docx, .txt, .md)
- Transkripte
- Notizen

## Nächster Schritt

Starte `/ecs:content-inbox` um die Dateien zu verarbeiten.
INBOX_README

    print_success "Content-Ordner erstellt"

    # Konfiguration anpassen
    print_step "Konfiguriere Projekt..."

    # CLAUDE.md mit Autor-Namen aktualisieren
    if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
        sed_inplace "s/{{AUTHOR_NAME}}/$AUTHOR_NAME/g" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null || true
    fi

    # BMAD config.yaml mit Autor-Namen aktualisieren
    if [ -f "$PROJECT_DIR/_bmad/core/config.yaml" ]; then
        sed_inplace "s/{{AUTHOR_NAME}}/$AUTHOR_NAME/g" "$PROJECT_DIR/_bmad/core/config.yaml" 2>/dev/null || true
    fi

    # config.yaml erstellen
    local config_dir="$PROJECT_DIR/_bmad/ecs"
    if [ -d "$config_dir" ]; then
        cat > "$config_dir/config.yaml" << EOF
# ECS Konfiguration
# Erstellt am: $(date '+%Y-%m-%d')

author_name: "$AUTHOR_NAME"
project_name: "$PROJECT_NAME"

# Sprache
communication_language: "Deutsch"
document_output_language: "Deutsch"

# Content-Ordner (einfache Pfade im Projekt-Root)
content_inbox: "inbox"
content_storage: "content"
content_output: "output"
EOF
    fi

    print_success "Projekt konfiguriert"

    # Git initialisieren
    print_step "Initialisiere Git..."

    cd "$PROJECT_DIR"
    git init -q
    git add -A
    git commit -q -m "Projekt '$PROJECT_NAME' erstellt

Autor: $AUTHOR_NAME

Co-Authored-By: Claude <noreply@anthropic.com>"

    print_success "Git initialisiert"

    # GitHub-Repo erstellen
    print_step "Erstelle GitHub-Repository..."

    "$GH_BIN" repo create "$PROJECT_NAME" --private --source=. --remote=origin --push

    print_success "GitHub-Repository erstellt: $REPO_NAME"
}

# ============================================
# Hauptprogramm
# ============================================

main() {
    print_header

    check_setup
    check_access
    choose_project_name

    if [ "$UPDATE_ECS" = true ]; then
        update_ecs_system "$PROJECT_DIR"
    elif [ "$COPY_ECS" = true ]; then
        copy_ecs_system "$PROJECT_DIR" "$COPY_SOURCE_PROJECT"
    elif [ "$USE_EXISTING_LOCAL" = true ]; then
        echo ""
        print_success "Nutze bestehendes Projekt: $PROJECT_DIR"
    elif [ "$USE_EXISTING_REMOTE" = true ]; then
        clone_existing_repo
    else
        create_new_project
    fi

    # Abschluss
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Fertig! Dein Projekt ist bereit.${NC}"
    echo ""
    echo "  Starte dein Projekt:"
    echo ""
    echo -e "    ${CYAN}cd \"$PROJECT_DIR\"${NC}"
    echo -e "    ${CYAN}claude${NC}"
    echo ""
    echo "  Verfügbare Workflows:"
    echo "    /ecs:helper              — Heinz fragen (Hilfe)"
    echo "    /ecs:content-inbox       — Inhalte verarbeiten"
    echo "    /ecs:mini-buch-erstellen — Mini-Buch schreiben"
    echo "    /ecs:themenfindung       — Themen finden"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo "  Um Claude Code zu starten, führe aus:"
    echo ""
    echo -e "    ${CYAN}cd $PROJECT_NAME${NC}"
    echo -e "    ${CYAN}claude${NC}"
    echo ""
}

main "$@"
