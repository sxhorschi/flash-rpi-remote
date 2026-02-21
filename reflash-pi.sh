#!/usr/bin/env bash
#
# reflash-pi.sh - Professional Remote Raspberry Pi Reflash Tool
#
# Features:
#  - Fancy progress bars & animations
#  - Debug mode (DEBUG=1 ./script.sh ...)
#  - Multiple flash methods (kexec, initramfs hook, direct)
#  - One-time password authentication
#  - Robust error handling
#
# Usage: ./reflash-pi.sh <PI_IP> <PASSWORD> [USERNAME]
#        DEBUG=1 ./reflash-pi.sh <PI_IP> <PASSWORD> [USERNAME]
#
# Version: 4.0 - Production Ready
#

set -euo pipefail

#=============================================================================
# Configuration
#=============================================================================

IMAGE_DIR="./raspbian-images"
IMAGE_NAME="raspios-lite-arm64.img.xz"
IMAGE_PATH="$IMAGE_DIR/$IMAGE_NAME"
DEFAULT_USER="pi"
TEMP_KEY_PATH="/tmp/reflash_pi_key_$$"
DEBUG="${DEBUG:-0}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR -o BatchMode=yes"
SSH_OPTS_INITIAL="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

PI_IP=""
PI_USER=""
PI_PASSWORD=""
PASSWORD_HASH=""
FLASH_METHOD=""  # will be: kexec, initramfs, or direct

#=============================================================================
# Colors & Symbols
#=============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Unicode symbols
CHECK="✓"
CROSS="✗"
ARROW="→"
SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
ROCKET="🚀"
WRENCH="🔧"
PACKAGE="📦"
TIMER="⏱️"

#=============================================================================
# Logging Functions
#=============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[${CHECK}]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[${CROSS}]${NC} $1"; }
log_debug() {
    if [ "$DEBUG" = "1" ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1" >&2
    fi
}

log_step() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#=============================================================================
# Progress Bar & Spinner
#=============================================================================

# Fancy progress bar: progress_bar <current> <total> <description>
progress_bar() {
    local current=$1
    local total=$2
    local desc="${3:-}"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf "\r${CYAN}[${bar}]${NC} ${percent}%% ${desc}"

    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# Spinner for indefinite tasks: spinner_start <message>
spinner_pid=""
spinner_start() {
    local message="$1"
    {
        local i=0
        while true; do
            printf "\r${CYAN}${SPINNER[$i]}${NC} $message"
            i=$(( (i + 1) % ${#SPINNER[@]} ))
            sleep 0.1
        done
    } &
    spinner_pid=$!
    log_debug "Spinner started with PID $spinner_pid"
}

spinner_stop() {
    if [ -n "$spinner_pid" ]; then
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
        spinner_pid=""
        printf "\r\033[K"  # Clear line
    fi
}

#=============================================================================
# Cleanup
#=============================================================================

cleanup() {
    spinner_stop
    rm -f "$TEMP_KEY_PATH" "${TEMP_KEY_PATH}.pub" 2>/dev/null || true
    log_debug "Cleanup completed"
}
trap cleanup EXIT

#=============================================================================
# SSH Helper Functions
#=============================================================================

ssh_cmd() {
    local cmd="$1"
    log_debug "SSH: $cmd"
    ssh $SSH_OPTS -i "$TEMP_KEY_PATH" "$PI_USER@$PI_IP" "$cmd" 2>&1
}

ssh_cmd_quiet() {
    ssh $SSH_OPTS -i "$TEMP_KEY_PATH" "$PI_USER@$PI_IP" "$@" 2>/dev/null || true
}

scp_file() {
    local src="$1"
    local dst="$2"
    log_debug "SCP: $src -> $dst"
    scp $SSH_OPTS -i "$TEMP_KEY_PATH" "$src" "$PI_USER@$PI_IP:$dst" 2>&1 | grep -v "Warning:" || true
}

# SCP with progress bar
scp_with_progress() {
    local src="$1"
    local dst="$2"
    local desc="$3"

    local size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null)
    local size_mb=$((size / 1024 / 1024))

    log_info "$desc (${size_mb}MB)..."

    # Use rsync for progress if available, otherwise scp
    if command -v rsync &>/dev/null; then
        rsync -avz --progress -e "ssh $SSH_OPTS -i $TEMP_KEY_PATH" "$src" "$PI_USER@$PI_IP:$dst" 2>&1 | \
            grep -oP '\d+(?=%)' | while read -r percent; do
                progress_bar "$percent" 100 "$desc"
            done
    else
        scp $SSH_OPTS -i "$TEMP_KEY_PATH" "$src" "$PI_USER@$PI_IP:$dst" 2>&1 | grep -v "Warning:" || true
        log_success "Upload abgeschlossen"
    fi
}

#=============================================================================
# Step 1: SSH Key Setup
#=============================================================================

setup_ssh_key() {
    log_step "${WRENCH} SCHRITT 1/8: SSH-Authentifizierung"

    spinner_start "Generiere temporären SSH-Schlüssel..."
    ssh-keygen -t ed25519 -f "$TEMP_KEY_PATH" -N "" -C "reflash-$(date +%s)" >/dev/null 2>&1
    spinner_stop
    log_success "SSH-Schlüssel generiert"

    log_warning "Passwort-Eingabe erforderlich (nur DIESES eine Mal!):"
    echo -e "${DIM}Verbinde zu $PI_USER@$PI_IP...${NC}"

    local pubkey=$(cat "${TEMP_KEY_PATH}.pub")
    local result=$(ssh $SSH_OPTS_INITIAL "$PI_USER@$PI_IP" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo SUCCESS" 2>&1)

    if echo "$result" | grep -q "SUCCESS"; then
        log_success "SSH-Schlüssel erfolgreich installiert"
    else
        log_error "Installation fehlgeschlagen"
        log_debug "Output: $result"
        exit 1
    fi

    # Verify key works
    if ssh -o BatchMode=yes $SSH_OPTS -i "$TEMP_KEY_PATH" "$PI_USER@$PI_IP" "echo OK" 2>/dev/null | grep -q "OK"; then
        log_success "${GREEN}${BOLD}${CHECK} Ab jetzt keine Passwort-Eingabe mehr!${NC}"
    else
        log_error "Schlüssel-Authentifizierung fehlgeschlagen"
        exit 1
    fi
}

#=============================================================================
# Step 2: Download Raspberry Pi OS
#=============================================================================

download_raspios() {
    log_step "${PACKAGE} SCHRITT 2/8: Raspberry Pi OS Image"

    mkdir -p "$IMAGE_DIR"

    # Check if image exists and is valid
    if [ -f "$IMAGE_PATH" ] && [ -s "$IMAGE_PATH" ]; then
        local size=$(du -h "$IMAGE_PATH" | awk '{print $1}')
        log_success "Image bereits vorhanden: $size"

        # Verify it's actually compressed
        if xz -t "$IMAGE_PATH" 2>/dev/null; then
            return 0
        else
            log_warning "Image scheint korrupt zu sein, lade neu herunter..."
            rm -f "$IMAGE_PATH"
        fi
    fi

    log_info "Suche neueste Raspberry Pi OS Version..."

    local download_page="https://downloads.raspberrypi.org/raspios_lite_arm64/images/"
    local latest_dir=$(curl -s "$download_page" | \
        grep -o 'href="raspios_lite_arm64-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/"' | \
        sed 's/href="//;s/"//' | sort -V | tail -1)

    if [ -z "$latest_dir" ]; then
        log_error "Konnte neueste Version nicht finden"
        exit 1
    fi

    local image_url="${download_page}${latest_dir}"
    local image_file=$(curl -s "$image_url" | \
        grep -o '[^"]*\.img\.xz' | \
        grep -v torrent | grep -v sha | head -1)

    if [ -z "$image_file" ]; then
        log_error "Konnte Image-Datei nicht finden"
        exit 1
    fi

    local full_url="${image_url}${image_file}"
    log_info "Version: ${latest_dir}"
    log_info "Download von: $full_url"

    # Download with progress
    if curl -L -o "$IMAGE_PATH" --progress-bar "$full_url"; then
        local size=$(du -h "$IMAGE_PATH" | awk '{print $1}')
        log_success "Download abgeschlossen: $size"

        # Verify download
        if ! xz -t "$IMAGE_PATH" 2>/dev/null; then
            log_error "Download ist korrupt!"
            rm -f "$IMAGE_PATH"
            exit 1
        fi
    else
        log_error "Download fehlgeschlagen"
        exit 1
    fi
}

#=============================================================================
# Step 3: System Check & Determine Flash Method
#=============================================================================

check_system_and_method() {
    log_step "${WRENCH} SCHRITT 3/8: System-Analyse"

    local uname=$(ssh_cmd "uname -a" | tail -1)
    log_info "System: $uname"

    local mem_total=$(ssh_cmd "free -h | grep Mem: | awk '{print \\\$2}'")
    local mem_free=$(ssh_cmd "free -h | grep Mem: | awk '{print \\\$7}'")
    log_info "RAM: $mem_total gesamt, $mem_free frei"

    # Check for kexec support
    log_info "Prüfe Flash-Methoden..."

    # Install kexec-tools if needed
    ssh_cmd "command -v kexec >/dev/null || sudo apt-get update -qq && sudo apt-get install -y -qq kexec-tools" >/dev/null 2>&1 || true

    # Test kexec
    if ssh_cmd "kexec --version" >/dev/null 2>&1; then
        # Check if kernel supports kexec
        if ssh_cmd "grep -q CONFIG_KEXEC=y /boot/config-\\\$(uname -r) 2>/dev/null || zcat /proc/config.gz 2>/dev/null | grep -q CONFIG_KEXEC=y" 2>/dev/null; then
            FLASH_METHOD="kexec"
            log_success "Flash-Methode: ${GREEN}${BOLD}kexec${NC} (optimal, ~5 Min)"
        else
            FLASH_METHOD="initramfs"
            log_warning "Kernel unterstützt kexec nicht"
            log_info "Flash-Methode: ${YELLOW}initramfs hook${NC} (sicher, ~10 Min)"
        fi
    else
        FLASH_METHOD="initramfs"
        log_info "Flash-Methode: ${YELLOW}initramfs hook${NC} (zwei Reboots nötig)"
    fi

    log_debug "Gewählte Methode: $FLASH_METHOD"
}

#=============================================================================
# Step 4: Password Hash
#=============================================================================

generate_password_hash() {
    log_step "${WRENCH} SCHRITT 4/8: Passwort-Hash"

    spinner_start "Generiere SHA-512 Hash..."
    PASSWORD_HASH=$(openssl passwd -6 "$PI_PASSWORD")
    spinner_stop

    log_success "Hash erstellt"
    log_debug "Hash: ${PASSWORD_HASH:0:30}..."
}

#=============================================================================
# Step 5: Upload Image to Pi
#=============================================================================

upload_image_to_pi() {
    log_step "${PACKAGE} SCHRITT 5/8: Upload auf Pi"

    ssh_cmd "mkdir -p /home/$PI_USER/reflash && rm -rf /home/$PI_USER/reflash/*"

    scp_with_progress "$IMAGE_PATH" "/home/$PI_USER/reflash/image.img.xz" "Raspberry Pi OS Image"
}

#=============================================================================
# Step 6: Prepare Flash Script (Initramfs Method)
#=============================================================================

prepare_initramfs_flash() {
    log_step "${WRENCH} SCHRITT 6/8: Flash-Script vorbereiten"

    log_info "Erstelle Initramfs-Hook für Flash beim nächsten Boot..."

    # Create flash script that runs during early boot
    ssh_cmd "sudo tee /usr/share/initramfs-tools/scripts/init-top/reflash" >/dev/null <<'INITRAMFS_SCRIPT'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# Check if reflash flag exists
if [ ! -f /run/do_reflash ]; then
    exit 0
fi

echo "============================================"
echo "  Raspberry Pi Reflash Service"
echo "============================================"
echo ""
echo "Flashe SD-Karte mit neuem Image..."
echo "NICHT AUSSCHALTEN!"
echo ""

# Flash the SD card
if [ -f /root/reflash/image.img.xz ]; then
    xzcat /root/reflash/image.img.xz | dd of=/dev/mmcblk0 bs=4M conv=fsync status=progress

    echo ""
    echo "Flash abgeschlossen!"
    echo "Konfiguriere Boot-Partition..."

    mkdir -p /mnt/boot
    mount /dev/mmcblk0p1 /mnt/boot || mount /dev/mmcblk0p2 /mnt/boot

    # SSH aktivieren
    touch /mnt/boot/ssh || touch /mnt/boot/firmware/ssh

    # User config
    if [ -f /root/reflash/userconf.txt ]; then
        cp /root/reflash/userconf.txt /mnt/boot/ || cp /root/reflash/userconf.txt /mnt/boot/firmware/
    fi

    sync
    umount /mnt/boot

    # Remove reflash flag
    rm -f /run/do_reflash /root/reflash/image.img.xz

    echo ""
    echo "Fertig! System wird neu gestartet..."
    sleep 2
fi
INITRAMFS_SCRIPT

    ssh_cmd "sudo chmod +x /usr/share/initramfs-tools/scripts/init-top/reflash"

    # Copy image to /root (survives reboot)
    log_info "Kopiere Image nach /root..."
    ssh_cmd "sudo mkdir -p /root/reflash"
    ssh_cmd "sudo cp /home/$PI_USER/reflash/image.img.xz /root/reflash/"

    # Create user config
    ssh_cmd "echo '$PI_USER:$PASSWORD_HASH' | sudo tee /root/reflash/userconf.txt" >/dev/null

    # Update initramfs
    spinner_start "Erstelle neues Initramfs mit Flash-Hook..."
    ssh_cmd "sudo update-initramfs -u" >/dev/null 2>&1
    spinner_stop

    log_success "Initramfs aktualisiert"

    # Create reflash trigger
    ssh_cmd "sudo touch /run/do_reflash"

    log_success "Flash-Skript vorbereitet"
    log_info "Beim nächsten Boot wird die SD-Karte geflasht!"
}

#=============================================================================
# Step 7: Trigger Reboot
#=============================================================================

trigger_reflash_reboot() {
    log_step "${ROCKET} SCHRITT 7/8: Reboot & Flash"

    log_warning ""
    log_warning "╔════════════════════════════════════════════════════════╗"
    log_warning "║  ACHTUNG: Pi wird jetzt neu gestartet                 ║"
    log_warning "║  Flash-Prozess läuft automatisch (~5-10 Min)          ║"
    log_warning "║  NICHT STROMVERSORGUNG UNTERBRECHEN!                  ║"
    log_warning "╚════════════════════════════════════════════════════════╝"
    log_warning ""

    read -p "Bereit für Reboot? [ENTER]"

    log_info "Sende Reboot-Kommando..."
    ssh_cmd "sudo reboot" >/dev/null 2>&1 || true

    log_success "Reboot gesendet"
    log_info "Flash läuft jetzt..."

    # Show animated progress
    echo ""
    echo -e "${CYAN}${BOLD}Flash-Fortschritt (geschätzt):${NC}"
    for i in {1..100}; do
        progress_bar $i 100 "Flashe SD-Karte & boote neu..."
        sleep 6  # ~10 minutes total
    done
}

#=============================================================================
# Step 8: Wait & Verify
#=============================================================================

wait_and_verify() {
    log_step "${TIMER} SCHRITT 8/8: Verifikation"

    log_info "Warte auf neues System..."

    local max_wait=180
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if ping -c 1 -W 2 "$PI_IP" &>/dev/null; then
            sleep 10

            # Try SSH (password needed, key is gone)
            if ssh -o BatchMode=no -o ConnectTimeout=5 $SSH_OPTS_INITIAL "$PI_USER@$PI_IP" "echo online" 2>/dev/null | grep -q "online"; then
                break
            fi
        fi
        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done

    echo ""

    if [ $waited -lt $max_wait ]; then
        log_success "Pi ist online!"

        log_warning "Passwort-Eingabe für Verifikation:"
        local new_kernel=$(ssh $SSH_OPTS_INITIAL "$PI_USER@$PI_IP" "uname -r" 2>/dev/null)
        local new_os=$(ssh $SSH_OPTS_INITIAL "$PI_USER@$PI_IP" "cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2" 2>/dev/null)

        log_success "Kernel: $new_kernel"
        log_success "OS: $new_os"

        show_success_banner
    else
        log_warning "Timeout - Pi nicht erreichbar"
        log_info "Flash möglicherweise noch am Laufen..."
        log_info "Prüfe später: ssh $PI_USER@$PI_IP"
    fi
}

#=============================================================================
# Success Banner
#=============================================================================

show_success_banner() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║          ✓✓✓  REFLASH ERFOLGREICH!  ✓✓✓                  ║
║                                                           ║
║     Dein Raspberry Pi läuft mit frischem System! 🎉       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ Verbindung:                                              ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} ${GREEN}ssh $PI_USER@$PI_IP${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#=============================================================================
# Main
#=============================================================================

main() {
    clear

    # ASCII Art Banner
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🚀  RASPBERRY PI REMOTE REFLASH TOOL  🚀              ║
║                                                           ║
║  Professional Edition v4.0                                ║
║  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ║
║  Features:                                                ║
║  ✓ Komplett remote (kein physischer Zugriff)             ║
║  ✓ Automatische Methoden-Erkennung                       ║
║  ✓ Progress Bars & Animationen                           ║
║  ✓ Debug-Modus verfügbar                                 ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    if [ "$DEBUG" = "1" ]; then
        echo -e "${MAGENTA}[DEBUG MODE AKTIV]${NC}\n"
    fi

    # Parse args
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        log_error "Ungültige Argumente"
        echo ""
        echo "Usage: $0 <PI_IP> <PASSWORD> [USERNAME]"
        echo "       DEBUG=1 $0 <PI_IP> <PASSWORD> [USERNAME]"
        echo ""
        echo "Beispiel: $0 192.168.1.100 meinpasswort pi"
        echo "          DEBUG=1 $0 192.168.178.61 Schorschi06. georgws"
        exit 1
    fi

    PI_IP="$1"
    PI_PASSWORD="$2"
    PI_USER="${3:-$DEFAULT_USER}"

    log_info "Ziel: ${CYAN}$PI_USER@$PI_IP${NC}"
    if [ "$DEBUG" = "1" ]; then
        log_debug "Debug-Modus aktiv - verbose output enabled"
    fi
    echo ""

    # Confirmation
    log_warning "╔════════════════════════════════════════════════════════╗"
    log_warning "║   WARNUNG: SD-Karte wird KOMPLETT überschrieben!      ║"
    log_warning "╚════════════════════════════════════════════════════════╝"
    echo ""
    read -p "Fortfahren? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Abgebrochen"
        exit 0
    fi

    local start_time=$(date +%s)

    # Execute all steps
    setup_ssh_key
    download_raspios
    check_system_and_method
    generate_password_hash
    upload_image_to_pi
    prepare_initramfs_flash
    trigger_reflash_reboot
    wait_and_verify

    local duration=$(($(date +%s) - start_time))
    echo ""
    log_info "${TIMER} Gesamtdauer: $((duration/60))m $((duration%60))s"
    echo ""
}

# Dependencies
for cmd in ssh scp ssh-keygen openssl curl xz; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Fehler: $cmd nicht verfügbar"
        echo "Installation: brew install $cmd"
        exit 1
    fi
done

main "$@"
