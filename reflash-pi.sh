#!/usr/bin/env bash
#
# reflash-pi.sh - Remote Raspberry Pi Reflash Tool
#
# Remotely reflash a Raspberry Pi's SD card over SSH using an initramfs hook.
# The hook runs from RAM during early boot, so it survives overwriting the SD card.
#
# Usage: ./reflash-pi.sh <PI_IP> <PASSWORD> [USERNAME]
#        DEBUG=1 ./reflash-pi.sh <PI_IP> <PASSWORD> [USERNAME]
#
# Version: 5.0
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
        printf "\r\033[K"
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

# SCP with progress bar (polls remote file size)
scp_with_progress() {
    local src="$1"
    local dst="$2"
    local desc="$3"

    local size
    size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null)
    local size_mb=$(( size / 1024 / 1024 ))

    log_info "$desc (${size_mb}MB)..."

    scp $SSH_OPTS -i "$TEMP_KEY_PATH" "$src" "$PI_USER@$PI_IP:$dst" &
    local scp_pid=$!

    while kill -0 "$scp_pid" 2>/dev/null; do
        local remote_size
        remote_size=$(ssh $SSH_OPTS -i "$TEMP_KEY_PATH" "$PI_USER@$PI_IP" \
            "stat -c%s '$dst' 2>/dev/null || echo 0" 2>/dev/null || echo 0)
        local percent=$(( remote_size * 100 / size ))
        [ "$percent" -gt 99 ] && percent=99
        progress_bar "$percent" 100 "$desc"
        sleep 1
    done

    wait "$scp_pid"
    progress_bar 100 100 "$desc"
    log_success "Upload complete (${size_mb}MB)"
}

# Format seconds as Xm Ys
format_elapsed() {
    local secs=$1
    if [ "$secs" -lt 60 ]; then
        echo "${secs}s"
    else
        echo "$((secs / 60))m $((secs % 60))s"
    fi
}

#=============================================================================
# Step 1: SSH Key Setup
#=============================================================================

setup_ssh_key() {
    log_step "${WRENCH} STEP 1/7: SSH Authentication"

    spinner_start "Generating temporary SSH key..."
    ssh-keygen -t ed25519 -f "$TEMP_KEY_PATH" -N "" -C "reflash-$(date +%s)" >/dev/null 2>&1
    spinner_stop
    log_success "SSH key generated"

    log_warning "Password required (only THIS once!):"
    echo -e "${DIM}Connecting to $PI_USER@$PI_IP...${NC}"

    local pubkey=$(cat "${TEMP_KEY_PATH}.pub")
    local result=$(ssh $SSH_OPTS_INITIAL "$PI_USER@$PI_IP" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo SUCCESS" 2>&1)

    if echo "$result" | grep -q "SUCCESS"; then
        log_success "SSH key installed"
    else
        log_error "SSH key installation failed"
        log_debug "Output: $result"
        exit 1
    fi

    # Verify key works
    if ssh -o BatchMode=yes $SSH_OPTS -i "$TEMP_KEY_PATH" "$PI_USER@$PI_IP" "echo OK" 2>/dev/null | grep -q "OK"; then
        log_success "${GREEN}${BOLD}${CHECK} No more password prompts from here!${NC}"
    else
        log_error "Key authentication failed"
        exit 1
    fi
}

#=============================================================================
# Step 2: Download Raspberry Pi OS
#=============================================================================

download_raspios() {
    log_step "${PACKAGE} STEP 2/7: Raspberry Pi OS Image"

    mkdir -p "$IMAGE_DIR"

    if [ -f "$IMAGE_PATH" ] && [ -s "$IMAGE_PATH" ]; then
        local size=$(du -h "$IMAGE_PATH" | awk '{print $1}')
        log_success "Image already present: $size"

        if xz -t "$IMAGE_PATH" 2>/dev/null; then
            return 0
        else
            log_warning "Image appears corrupt, re-downloading..."
            rm -f "$IMAGE_PATH"
        fi
    fi

    log_info "Looking up latest Raspberry Pi OS version..."

    local download_page="https://downloads.raspberrypi.org/raspios_lite_arm64/images/"
    local latest_dir=$(curl -s "$download_page" | \
        grep -o 'href="raspios_lite_arm64-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/"' | \
        sed 's/href="//;s/"//' | sort -V | tail -1)

    if [ -z "$latest_dir" ]; then
        log_error "Could not find latest version"
        exit 1
    fi

    local image_url="${download_page}${latest_dir}"
    local image_file=$(curl -s "$image_url" | \
        grep -o '[^"]*\.img\.xz' | \
        grep -v torrent | grep -v sha | head -1)

    if [ -z "$image_file" ]; then
        log_error "Could not find image file"
        exit 1
    fi

    local full_url="${image_url}${image_file}"
    log_info "Version: ${latest_dir}"
    log_info "Downloading from: $full_url"

    if curl -L -o "$IMAGE_PATH" --progress-bar "$full_url"; then
        local size=$(du -h "$IMAGE_PATH" | awk '{print $1}')
        log_success "Download complete: $size"

        if ! xz -t "$IMAGE_PATH" 2>/dev/null; then
            log_error "Download is corrupt!"
            rm -f "$IMAGE_PATH"
            exit 1
        fi
    else
        log_error "Download failed"
        exit 1
    fi
}

#=============================================================================
# Step 3: System Analysis
#=============================================================================

check_system() {
    log_step "${WRENCH} STEP 3/7: System Analysis"

    local uname=$(ssh_cmd "uname -a" | tail -1)
    log_info "System: $uname"

    local mem_total=$(ssh_cmd "free -h | grep Mem: | awk '{print \$2}'")
    local mem_free=$(ssh_cmd "free -h | grep Mem: | awk '{print \$7}'")
    log_info "RAM: $mem_total total, $mem_free available"

    log_info "Flash method: ${CYAN}initramfs hook${NC} (survives SD card overwrite)"
}

#=============================================================================
# Step 4: Password Hash
#=============================================================================

generate_password_hash() {
    log_step "${WRENCH} STEP 4/7: Password Hash"

    spinner_start "Generating SHA-512 hash..."
    PASSWORD_HASH=$(openssl passwd -6 "$PI_PASSWORD")
    spinner_stop

    log_success "Hash generated"
    log_debug "Hash: ${PASSWORD_HASH:0:30}..."
}

#=============================================================================
# Step 5: Upload Image to Pi
#=============================================================================

upload_image_to_pi() {
    log_step "${PACKAGE} STEP 5/7: Upload to Pi"

    ssh_cmd "mkdir -p /home/$PI_USER/reflash && rm -rf /home/$PI_USER/reflash/*"

    scp_with_progress "$IMAGE_PATH" "/home/$PI_USER/reflash/image.img.xz" "Raspberry Pi OS Image"
}

#=============================================================================
# Step 6: Prepare Initramfs Flash Hook
#=============================================================================

prepare_initramfs_flash() {
    log_step "${WRENCH} STEP 6/7: Prepare Flash"

    log_info "Creating initramfs hook for flash on next boot..."

    # The initramfs hook runs during early boot from RAM.
    # After dd overwrites the SD card, we re-read the partition table,
    # mount the boot partition, enable SSH, copy user config, then force reboot.
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

# Only run if reflash was requested
if [ ! -f /run/do_reflash ]; then
    exit 0
fi

echo "============================================"
echo "  Raspberry Pi Reflash Service"
echo "============================================"
echo ""
echo "Flashing SD card with new image..."
echo "DO NOT POWER OFF!"
echo ""

if [ -f /root/reflash/image.img.xz ]; then
    # Flash the SD card
    xzcat /root/reflash/image.img.xz | dd of=/dev/mmcblk0 bs=4M conv=fsync status=progress
    sync

    echo ""
    echo "Flash complete. Configuring boot partition..."

    # Re-read partition table (critical: kernel must see new partitions after dd)
    blockdev --rereadpt /dev/mmcblk0
    sleep 2

    # Mount boot partition and configure SSH + user
    mkdir -p /mnt/boot
    mount /dev/mmcblk0p1 /mnt/boot

    # Enable SSH (try both legacy and Bookworm+ paths)
    touch /mnt/boot/ssh 2>/dev/null
    cp /root/reflash/userconf.txt /mnt/boot/ 2>/dev/null

    # Bookworm+ uses /boot/firmware/
    mkdir -p /mnt/boot/firmware 2>/dev/null
    touch /mnt/boot/firmware/ssh 2>/dev/null
    cp /root/reflash/userconf.txt /mnt/boot/firmware/ 2>/dev/null

    sync
    umount /mnt/boot

    echo ""
    echo "Done! Rebooting into fresh system..."
    sleep 2

    # Force reboot — do NOT let initramfs continue into the now-destroyed rootfs
    reboot -f
fi
INITRAMFS_SCRIPT

    ssh_cmd "sudo chmod +x /usr/share/initramfs-tools/scripts/init-top/reflash"

    # Copy image to /root (persists across reboot, loaded into initramfs env)
    ssh_cmd "sudo mkdir -p /root/reflash"
    spinner_start "Copying image to /root (survives reboot)..."
    ssh_cmd "sudo cp /home/$PI_USER/reflash/image.img.xz /root/reflash/"
    spinner_stop
    log_success "Image copied to /root"

    # Create user config file
    ssh_cmd "echo '$PI_USER:$PASSWORD_HASH' | sudo tee /root/reflash/userconf.txt" >/dev/null

    # Rebuild initramfs with the flash hook included
    spinner_start "Rebuilding initramfs with flash hook..."
    ssh_cmd "sudo update-initramfs -u" >/dev/null 2>&1
    spinner_stop

    log_success "Initramfs updated"

    # Set the trigger flag
    ssh_cmd "sudo touch /run/do_reflash"

    log_success "Flash hook ready"
    log_info "SD card will be flashed on next boot!"
}

#=============================================================================
# Step 7: Reboot, Flash & Verify
#=============================================================================

reboot_flash_and_verify() {
    log_step "${ROCKET} STEP 7/7: Reboot, Flash & Verify"

    log_warning ""
    log_warning "╔════════════════════════════════════════════════════════╗"
    log_warning "║  WARNING: Pi will now reboot and flash the SD card    ║"
    log_warning "║  This takes ~5-10 minutes. DO NOT POWER OFF!         ║"
    log_warning "╚════════════════════════════════════════════════════════╝"
    log_warning ""

    read -p "Ready to reboot? [ENTER] "

    log_info "Sending reboot command..."
    ssh_cmd "sudo reboot" >/dev/null 2>&1 || true

    log_success "Reboot sent"
    echo ""

    # Wait for Pi to go down, flash, and come back up
    local start_time=$(date +%s)
    local max_wait=900  # 15 minutes max
    local phase="rebooting"
    local ping_lost=0

    while true; do
        local elapsed=$(( $(date +%s) - start_time ))

        if [ "$elapsed" -ge "$max_wait" ]; then
            printf "\r\033[K"
            log_error "Timeout after $(format_elapsed $elapsed)"
            log_info "The flash may still be running. Check manually:"
            log_info "  ping $PI_IP"
            log_info "  ssh $PI_USER@$PI_IP"
            exit 1
        fi

        local elapsed_fmt=$(format_elapsed $elapsed)

        # Phase logic
        case "$phase" in
            rebooting)
                printf "\r\033[K${CYAN}${SPINNER[$(( elapsed % 10 ))]}${NC} Rebooting... ($elapsed_fmt)"
                if ! ping -c 1 -W 1 "$PI_IP" &>/dev/null; then
                    ping_lost=1
                    phase="flashing"
                fi
                ;;
            flashing)
                printf "\r\033[K${CYAN}${SPINNER[$(( elapsed % 10 ))]}${NC} Flashing SD card (no ping response)... ($elapsed_fmt)"
                if ping -c 1 -W 1 "$PI_IP" &>/dev/null; then
                    phase="booting"
                fi
                ;;
            booting)
                printf "\r\033[K${CYAN}${SPINNER[$(( elapsed % 10 ))]}${NC} Booting new system... ($elapsed_fmt)"
                # Try SSH with sshpass (password auth, since old key is gone)
                if sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS_INITIAL -o BatchMode=no \
                    "$PI_USER@$PI_IP" "echo ONLINE" 2>/dev/null | grep -q "ONLINE"; then
                    phase="online"
                    break
                fi
                ;;
        esac

        sleep 3
    done

    local total_elapsed=$(( $(date +%s) - start_time ))
    printf "\r\033[K"
    log_success "Pi is online! (took $(format_elapsed $total_elapsed))"
    echo ""

    # Re-install SSH key on fresh system (no more password prompts)
    log_info "Installing SSH key on fresh system..."
    local pubkey=$(cat "${TEMP_KEY_PATH}.pub")
    sshpass -p "$PI_PASSWORD" ssh $SSH_OPTS_INITIAL -o BatchMode=no "$PI_USER@$PI_IP" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null
    log_success "SSH key installed on new system"

    # Verify the new system
    log_info "Verifying new system..."
    local new_kernel=$(ssh_cmd "uname -r" 2>/dev/null || echo "unknown")
    local new_os=$(ssh_cmd "cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2" 2>/dev/null || echo "unknown")

    log_success "Kernel: $new_kernel"
    log_success "OS: $new_os"

    show_success_banner
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
║          ✓✓✓  REFLASH SUCCESSFUL!  ✓✓✓                   ║
║                                                           ║
║     Your Raspberry Pi is running a fresh system!          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ Connect:                                                 ║${NC}"
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

    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🚀  RASPBERRY PI REMOTE REFLASH TOOL  🚀              ║
║                                                           ║
║  v5.0                                                     ║
║  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ║
║  Features:                                                ║
║  ✓ Fully remote (no physical access needed)              ║
║  ✓ Real progress tracking                                ║
║  ✓ Initramfs hook (flash from RAM)                       ║
║  ✓ Debug mode available                                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    if [ "$DEBUG" = "1" ]; then
        echo -e "${MAGENTA}[DEBUG MODE ACTIVE]${NC}\n"
    fi

    # Parse args
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
        log_error "Invalid arguments"
        echo ""
        echo "Usage: $0 <PI_IP> <PASSWORD> [USERNAME]"
        echo "       DEBUG=1 $0 <PI_IP> <PASSWORD> [USERNAME]"
        echo ""
        echo "Example: $0 192.168.1.100 mypassword pi"
        exit 1
    fi

    PI_IP="$1"
    PI_PASSWORD="$2"
    PI_USER="${3:-$DEFAULT_USER}"

    log_info "Target: ${CYAN}$PI_USER@$PI_IP${NC}"
    if [ "$DEBUG" = "1" ]; then
        log_debug "Debug mode active - verbose output enabled"
    fi
    echo ""

    # Confirmation
    log_warning "╔════════════════════════════════════════════════════════╗"
    log_warning "║   WARNING: SD card will be COMPLETELY overwritten!    ║"
    log_warning "╚════════════════════════════════════════════════════════╝"
    echo ""
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        exit 0
    fi

    local start_time=$(date +%s)

    # Execute all steps
    setup_ssh_key
    download_raspios
    check_system
    generate_password_hash
    upload_image_to_pi
    prepare_initramfs_flash
    reboot_flash_and_verify

    local duration=$(($(date +%s) - start_time))
    echo ""
    log_info "${TIMER} Total time: $(format_elapsed $duration)"
    echo ""
}

# Check dependencies
for cmd in ssh scp ssh-keygen openssl curl xz sshpass; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found"
        echo "Install: brew install $cmd"
        exit 1
    fi
done

main "$@"
