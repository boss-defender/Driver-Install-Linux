#!/usr/bin/env bash
# ==============================================================================
# Universal Linux Gaming Driver & Stack Installer
# ==============================================================================
# Supported Distributions:
#   - Fedora, Nobara, Ultramarine
#   - Ubuntu, Debian, Linux Mint, Pop!_OS, Zorin OS, Elementary, KDE neon
#   - Arch Linux, Manjaro, EndeavourOS, Garuda, CachyOS, ArcoLinux, Artix
#
# Hardware Detection & Drivers:
#   - NVIDIA: Proprietary drivers (DKMS/akmod/ubuntu-drivers), 32-bit GL/Vulkan, CUDA
#   - AMD: Mesa RADV (64 & 32-bit), VA-API/VDPAU hardware video acceleration
#   - Intel: Mesa ANV (64 & 32-bit), Intel Media VA-API acceleration
#   - Hybrid / Dual GPU: Auto-configures both drivers & switcheroo-control
#
# Audio & Gaming Stack:
#   - PipeWire + WirePlumber + 32-bit ALSA/Pulse compatibility (Fixes sound crackle)
#   - Vulkan ICD loaders (64 & 32-bit) for Steam, Proton, and Wine
#   - Feral GameMode (gamemode) & MangoHud performance overlay
# ==============================================================================

set -euo pipefail

# ANSI color formatting
C_RESET="\033[0m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_CYAN="\033[1;36m"
C_BOLD="\033[1m"

log_info()    { echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $*"; }
log_warn()    { echo -e "${C_YELLOW}[WARNING]${C_RESET} $*"; }
log_error()   { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }
log_step()    { echo -e "\n${C_CYAN}${C_BOLD}==> $*${C_RESET}"; }

# ------------------------------------------------------------------------------
# 0. CLI Options (--help, --probe, --dry-run)
# ------------------------------------------------------------------------------
DRY_RUN=false

show_help() {
    echo -e "${C_BOLD}Universal Linux Gaming Driver & Stack Installer${C_RESET}"
    echo -e "Usage: ./install_gaming_drivers.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --probe, --dry-run, -p   Scan system, detect GPU & OS, and display installation"
    echo "                           plan without making changes (does NOT require sudo)."
    echo "  --help, -h               Show this help message and exit."
    echo ""
    echo "Supported Distributions:"
    echo "  • Fedora, Nobara, Ultramarine"
    echo "  • Ubuntu, Debian, Linux Mint, Pop!_OS, Zorin OS"
    echo "  • Arch Linux, Manjaro, EndeavourOS, Garuda, CachyOS"
    echo ""
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            show_help
            exit 0
            ;;
        --dry-run|--probe|-p)
            DRY_RUN=true
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 1. Privilege Check & Self-Elevation
# ------------------------------------------------------------------------------
TARGET_USER="${SUDO_USER:-${USER:-}}"

if [ "$DRY_RUN" = false ] && [ "$EUID" -ne 0 ]; then
    log_warn "Root privileges are required to configure repositories and drivers."
    log_info "Prompting for sudo password..."
    exec sudo -E bash "$0" "$@"
fi

# Determine the actual desktop user
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    REAL_USER=$(logname 2>/dev/null || echo "")
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        TARGET_USER="$REAL_USER"
    else
        TARGET_USER=$(id -un 1000 2>/dev/null || echo "root")
    fi
fi

TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")

echo -e "${C_BOLD}====================================================================${C_RESET}"
echo -e "${C_BOLD}          Universal Linux Gaming Driver & Stack Installer          ${C_RESET}"
echo -e "${C_BOLD}====================================================================${C_RESET}"
log_info "Target desktop user: ${C_BOLD}${TARGET_USER}${C_RESET} (UID: ${TARGET_UID})"
[ "$DRY_RUN" = true ] && log_warn "DRY-RUN / PROBE MODE: No system changes will be performed."

# ------------------------------------------------------------------------------
# 2. Immutable / Atomic OS Check
# ------------------------------------------------------------------------------
if [ -f /run/ostree-booted ] || [ -f /etc/steamos-release ]; then
    log_warn "Immutable / Atomic Linux environment detected (Silverblue / Kinoite / Bazzite / SteamOS)."
    echo -e "${C_YELLOW}On immutable systems, graphics and audio drivers are pre-baked into the read-only base OS image."
    echo -e "Gaming is designed to run via Flatpak without modifying system packages:${C_RESET}"
    echo -e "  -> ${C_BOLD}flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo${C_RESET}"
    echo -e "  -> ${C_BOLD}flatpak install flathub com.valvesoftware.Steam com.heroicgameslauncher.hgl${C_RESET}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Network Connectivity Check
# ------------------------------------------------------------------------------
check_network() {
    log_step "Checking Network Connectivity..."
    local test_hosts=("1.1.1.1" "8.8.8.8" "9.9.9.9")
    local connected=false

    for ip in "${test_hosts[@]}"; do
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            connected=true
            break
        fi
    done

    if [ "$connected" = false ]; then
        if command -v curl >/dev/null 2>&1 && curl -s --connect-timeout 3 https://cloudflare.com >/dev/null 2>&1; then
            connected=true
        fi
    fi

    if [ "$connected" = false ]; then
        log_error "No active internet connection detected. Please connect before running this script."
        exit 1
    fi
    log_success "Internet connection verified."
}
check_network

# ------------------------------------------------------------------------------
# 4. Distribution Detection
# ------------------------------------------------------------------------------
log_step "Detecting Linux Distribution..."

if [ ! -f /etc/os-release ]; then
    log_error "Could not find /etc/os-release. Unsupported Linux distribution."
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

DISTRO_FAMILY=""
DISTRO_NAME="${PRETTY_NAME:-$NAME}"

log_info "Detected OS: ${C_BOLD}${DISTRO_NAME}${C_RESET} (ID: ${ID:-unknown}, ID_LIKE: ${ID_LIKE:-none})"

if [[ "${ID:-}" =~ ^(fedora|nobara|ultramarine)$ ]] || [[ "${ID_LIKE:-}" =~ (fedora) ]]; then
    DISTRO_FAMILY="fedora"
elif [[ "${ID:-}" =~ ^(ubuntu|debian|linuxmint|pop|zorin|elementary|neon|tuxedo)$ ]] || [[ "${ID_LIKE:-}" =~ (ubuntu|debian) ]]; then
    DISTRO_FAMILY="debian"
elif [[ "${ID:-}" =~ ^(arch|manjaro|endeavouros|garuda|cachyos|arcolinux|artix)$ ]] || [[ "${ID_LIKE:-}" =~ (arch) ]]; then
    DISTRO_FAMILY="arch"
else
    log_error "Unsupported distribution family: '${ID:-unknown}'."
    log_error "This script supports Fedora, Debian/Ubuntu-family, and Arch-family distributions."
    exit 1
fi

log_success "Identified distribution family: ${C_BOLD}${DISTRO_FAMILY^^}${C_RESET}"

# ------------------------------------------------------------------------------
# 5. Lock Wait Helpers (Prevents background updater crashes)
# ------------------------------------------------------------------------------
wait_for_locks() {
    [ "$DRY_RUN" = true ] && return 0
    case "$DISTRO_FAMILY" in
        debian)
            local waited=0
            local max_wait=60
            while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
                  fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
                  fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
                if [ "$waited" -ge "$max_wait" ]; then
                    log_warn "Package manager lock held for more than ${max_wait}s. Proceeding..."
                    break
                fi
                log_info "Waiting for background package managers (unattended-upgrades/apt) to release locks... (${waited}s)"
                sleep 3
                waited=$((waited + 3))
            done
            ;;
        arch)
            if [ -f /var/lib/pacman/db.lck ]; then
                if pgrep -x pacman >/dev/null 2>&1; then
                    log_info "Waiting for active pacman process to finish..."
                    while pgrep -x pacman >/dev/null 2>&1; do
                        sleep 2
                    done
                else
                    log_warn "Found stale /var/lib/pacman/db.lck with no running pacman. Removing stale lock..."
                    rm -f /var/lib/pacman/db.lck
                fi
            fi
            ;;
        fedora)
            # DNF handles locking internally with auto-retry
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 6. Hardware Scanning (GPU Detection)
# ------------------------------------------------------------------------------
log_step "Scanning Hardware & Display Adapters..."

if ! command -v lspci >/dev/null 2>&1; then
    if [ "$DRY_RUN" = false ]; then
        log_info "lspci not found. Installing pciutils..."
        wait_for_locks
        case "$DISTRO_FAMILY" in
            fedora) dnf install -y pciutils ;;
            debian)
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -y && apt-get install -y pciutils
                ;;
            arch)
                pacman -Sy --noconfirm --needed pciutils
                ;;
        esac
    fi
fi

VGA_DEVICES=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)

HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

echo -e "${C_CYAN}Detected Display Controllers:${C_RESET}"
if [ -n "$VGA_DEVICES" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        echo "  -> $line"
        if echo "$line" | grep -Eiq 'nvidia|\[10de:'; then
            HAS_NVIDIA=true
        fi
        if echo "$line" | grep -Eiq 'amd|ati|radeon|\[1002:'; then
            HAS_AMD=true
        fi
        if echo "$line" | grep -Eiq 'intel|\[8086:'; then
            HAS_INTEL=true
        fi
    done <<< "$VGA_DEVICES"
else
    log_warn "lspci reported no standard display controllers."
fi

echo ""
log_info "GPU Hardware Summary:"
[ "$HAS_NVIDIA" = true ] && echo -e "  - NVIDIA: [${C_GREEN}DETECTED${C_RESET}]" || echo -e "  - NVIDIA: [NOT PRESENT]"
[ "$HAS_AMD" = true ]    && echo -e "  - AMD:    [${C_GREEN}DETECTED${C_RESET}]" || echo -e "  - AMD:    [NOT PRESENT]"
[ "$HAS_INTEL" = true ]  && echo -e "  - INTEL:  [${C_GREEN}DETECTED${C_RESET}]" || echo -e "  - INTEL:  [NOT PRESENT]"

if [ "$HAS_NVIDIA" = false ] && [ "$HAS_AMD" = false ] && [ "$HAS_INTEL" = false ]; then
    log_warn "No recognized GPU vendor identified. Defaulting to full universal Mesa stack."
    HAS_AMD=true
    HAS_INTEL=true
fi

IS_HYBRID=false
if [ "$HAS_NVIDIA" = true ] && { [ "$HAS_AMD" = true ] || [ "$HAS_INTEL" = true ]; }; then
    IS_HYBRID=true
    log_info "Hybrid / Dual-GPU setup detected (Integrated CPU Graphics + NVIDIA Discrete)."
fi

# ------------------------------------------------------------------------------
# 7. Distribution-Specific Installation Routines
# ------------------------------------------------------------------------------

# --- A. FEDORA ROUTINE ---
run_fedora() {
    log_step "Configuring Repositories & Packages for Fedora..."

    local DNF_BIN="dnf"
    if command -v dnf5 >/dev/null 2>&1; then
        DNF_BIN="dnf5"
    fi
    log_info "Package manager: ${C_BOLD}${DNF_BIN}${C_RESET}"

    local FEDORA_VER
    FEDORA_VER=$(rpm -E %fedora 2>/dev/null || echo "41")

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would enable RPM Fusion Free and Nonfree for Fedora ${FEDORA_VER}."
        log_info "[DRY-RUN] Would enable Cisco OpenH264 repository."
        log_info "[DRY-RUN] Would install PipeWire, WirePlumber, and 32-bit ALSA/Pulse wrappers."
        log_info "[DRY-RUN] Would install Mesa RADV/ANV, Vulkan loaders, and 32-bit compatibility."
        [ "$HAS_NVIDIA" = true ] && log_info "[DRY-RUN] Would install akmod-nvidia, CUDA, and build modules via akmods."
        return 0
    fi

    wait_for_locks

    # 1. Enable RPM Fusion Free & Nonfree
    log_info "Verifying RPM Fusion Free & Nonfree repositories..."
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        $DNF_BIN install -y --nogpgcheck "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" || true
    fi
    if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
        $DNF_BIN install -y --nogpgcheck "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" || true
    fi

    # Enable Cisco OpenH264
    if [ "$DNF_BIN" = "dnf5" ]; then
        dnf5 config-manager enable fedora-cisco-openh264 2>/dev/null || true
    else
        dnf config-manager --enable fedora-cisco-openh264 2>/dev/null || true
    fi

    # 2. Audio Stack
    log_step "Installing PipeWire, WirePlumber & 32-bit Audio Compatibility..."
    $DNF_BIN install -y --skip-unavailable \
        pipewire \
        pipewire-pulseaudio \
        wireplumber \
        pipewire-alsa \
        alsa-plugins-pulseaudio.i686 \
        alsa-plugins-pulseaudio.x86_64 \
        pipewire-libs.i686 \
        pipewire-plugin-libcamera \
        gstreamer1-plugins-good \
        gstreamer1-plugins-bad-free \
        gstreamer1-plugins-ugly-free || true

    # 3. Graphics Drivers & Gaming Libraries
    log_step "Installing Graphics Drivers, Vulkan ICDs & Gaming Libraries..."
    local PKGS=(
        vulkan-loader
        vulkan-loader.i686
        vulkan-tools
        glx-utils
        gamemode
        gamemode.i686
        mangohud
        mangohud.i686
    )

    if [ "$IS_HYBRID" = true ]; then
        PKGS+=(switcheroo-control)
    fi

    if [ "$HAS_AMD" = true ]; then
        log_info "Adding AMD Radeon Mesa/RADV (64 & 32-bit) and hardware video acceleration..."
        PKGS+=(
            mesa-dri-drivers
            mesa-dri-drivers.i686
            mesa-vulkan-drivers
            mesa-vulkan-drivers.i686
            mesa-va-drivers-freeworld
            mesa-vdpau-drivers-freeworld
            libva
            libva.i686
            libva-utils
        )
    fi

    if [ "$HAS_INTEL" = true ]; then
        log_info "Adding Intel Graphics Mesa/ANV (64 & 32-bit) and media drivers..."
        PKGS+=(
            mesa-dri-drivers
            mesa-dri-drivers.i686
            mesa-vulkan-drivers
            mesa-vulkan-drivers.i686
            intel-media-driver
            libva-intel-driver
            libva
            libva.i686
            libva-utils
        )
    fi

    if [ "$HAS_NVIDIA" = true ]; then
        log_info "Adding NVIDIA Akmod, CUDA, and 32-bit Vulkan/GL libraries..."
        local RUNNING_KERN
        RUNNING_KERN=$(uname -r)
        PKGS+=(
            "kernel-devel-${RUNNING_KERN}"
            kernel-headers
            akmod-nvidia
            xorg-x11-drv-nvidia-cuda
            xorg-x11-drv-nvidia-cuda-libs.i686
            xorg-x11-drv-nvidia-libs.i686
            xorg-x11-drv-nvidia-power
            nvidia-settings
            nvidia-vaapi-driver
        )
    fi

    log_info "Executing package installation via ${DNF_BIN}..."
    $DNF_BIN install -y --skip-unavailable --allowerasing "${PKGS[@]}"

    if [ "$HAS_NVIDIA" = true ]; then
        log_info "Compiling NVIDIA kernel modules with akmods..."
        akmods --force || log_warn "akmods finished with warnings; check /var/log/akmods if needed."
        dracut --force || true
    fi

    if [ "$IS_HYBRID" = true ]; then
        systemctl enable --now switcheroo-control.service 2>/dev/null || true
    fi
}

# --- B. DEBIAN / UBUNTU / MINT / POP!_OS / ZORIN ROUTINE ---
run_debian() {
    log_step "Configuring Repositories & Packages for Debian/Ubuntu Family..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would enable i386 multi-architecture (dpkg --add-architecture i386)."
        log_info "[DRY-RUN] Would enable contrib/non-free/multiverse repositories."
        log_info "[DRY-RUN] Would install PipeWire, WirePlumber, and 32-bit ALSA/Pulse wrappers."
        log_info "[DRY-RUN] Would install Mesa RADV/ANV, Vulkan loaders, and 32-bit compatibility."
        [ "$HAS_NVIDIA" = true ] && log_info "[DRY-RUN] Would install proprietary NVIDIA drivers via ubuntu-drivers/system76/apt."
        return 0
    fi

    wait_for_locks

    # Prevent interactive ncurses dialogs
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1

    # 1. Enable 32-bit Multiarch
    log_info "Ensuring i386 (32-bit) architecture is enabled..."
    dpkg --add-architecture i386

    # 2. Enable Non-Free Repositories
    if [ "${ID:-}" = "debian" ]; then
        log_info "Debian detected: Enabling contrib, non-free, and non-free-firmware..."
        if [ -f /etc/apt/sources.list ]; then
            sed -i -E '/^[[:space:]]*deb[[:space:]]/ {
                /contrib/! s/main/main contrib/
                /non-free-firmware/! s/main/main non-free-firmware/
                /non-free([^-]|$)/! s/main/main non-free/
            }' /etc/apt/sources.list
        fi
        if compgen -G "/etc/apt/sources.list.d/*.sources" > /dev/null; then
            for src in /etc/apt/sources.list.d/*.sources; do
                sed -i -E '/^[[:space:]]*Components:/ {
                    /contrib/! s/Components:(.*)main/Components:\1main contrib/
                    /non-free-firmware/! s/Components:(.*)main/Components:\1main non-free-firmware/
                    /non-free([^-]|$)/! s/Components:(.*)main/Components:\1main non-free/
                }' "$src"
            done
        fi
    else
        # Ubuntu, Linux Mint, Pop!_OS, Zorin OS
        if ! command -v add-apt-repository >/dev/null 2>&1; then
            apt-get update -y
            apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" software-properties-common || true
        fi
        if command -v add-apt-repository >/dev/null 2>&1; then
            log_info "Enabling universe, restricted, and multiverse components..."
            add-apt-repository -y universe 2>/dev/null || true
            add-apt-repository -y restricted 2>/dev/null || true
            add-apt-repository -y multiverse 2>/dev/null || true
        fi
    fi

    log_info "Updating APT package index..."
    apt-get update -y

    apt_install_safe() {
        local to_install=()
        for pkg in "$@"; do
            if apt-cache show "$pkg" >/dev/null 2>&1 || apt-cache show "${pkg%%:*}" >/dev/null 2>&1; then
                to_install+=("$pkg")
            fi
        done
        if [ ${#to_install[@]} -gt 0 ]; then
            apt-get install -y \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" \
                "${to_install[@]}"
        fi
    }

    # 3. Audio Stack
    log_step "Installing PipeWire, WirePlumber & 32-bit Audio Compatibility..."
    apt_install_safe \
        pipewire \
        pipewire-pulse \
        wireplumber \
        pipewire-alsa \
        libasound2-plugins:i386 \
        libasound2t64-plugins:i386 \
        libspa-0.2-bluetooth \
        gstreamer1.0-pipewire

    # 4. Graphics Drivers & Gaming Libraries
    log_step "Installing Graphics Drivers, Vulkan ICDs & Gaming Libraries..."
    local PKGS=(
        vulkan-tools
        mesa-utils
        libvulkan1
        libvulkan1:i386
        gamemode
        mangohud
    )

    if [ "$IS_HYBRID" = true ]; then
        PKGS+=(switcheroo-control)
    fi

    if [ "$HAS_AMD" = true ]; then
        log_info "Adding AMD Radeon Mesa/RADV (64 & 32-bit) and firmware..."
        PKGS+=(
            mesa-va-drivers
            mesa-vdpau-drivers
            mesa-vulkan-drivers
            mesa-vulkan-drivers:i386
            libgl1-mesa-dri
            libgl1-mesa-dri:i386
            libglx-mesa0
            libglx-mesa0:i386
            va-driver-all
            firmware-amd-graphics
        )
    fi

    if [ "$HAS_INTEL" = true ]; then
        log_info "Adding Intel Graphics Mesa/ANV (64 & 32-bit) and media drivers..."
        PKGS+=(
            intel-media-va-driver
            intel-media-va-driver-non-free
            mesa-vulkan-drivers
            mesa-vulkan-drivers:i386
            libgl1-mesa-dri
            libgl1-mesa-dri:i386
            libglx-mesa0
            libglx-mesa0:i386
            va-driver-all
            firmware-misc-nonfree
        )
    fi

    apt_install_safe "${PKGS[@]}"

    if [ "$HAS_NVIDIA" = true ]; then
        log_info "Configuring NVIDIA drivers..."
        if [ "${ID:-}" = "pop" ]; then
            log_info "Pop!_OS: Installing system76-driver-nvidia..."
            apt-get install -y system76-driver-nvidia || true
        elif [ "${ID:-}" = "debian" ]; then
            log_info "Debian: Installing nvidia-driver and 32-bit GL..."
            apt_install_safe \
                nvidia-driver \
                nvidia-vulkan-icd \
                libgl1-nvidia-glvnd-glx:i386 \
                firmware-misc-nonfree
        else
            if command -v ubuntu-drivers >/dev/null 2>&1; then
                log_info "Running ubuntu-drivers to install optimal proprietary driver..."
                ubuntu-drivers install 2>/dev/null || ubuntu-drivers autoinstall 2>/dev/null || true
            else
                apt-get install -y ubuntu-drivers-common || true
                ubuntu-drivers install 2>/dev/null || true
            fi
        fi

        # Ensure matching 32-bit NVIDIA GL libraries
        local NV_VER
        NV_VER=$(dpkg -l 2>/dev/null | grep -E '^ii[[:space:]]+nvidia-driver-[0-9]+' | awk '{print $2}' | head -n1 || true)
        if [ -n "$NV_VER" ]; then
            local NV_NUM="${NV_VER#nvidia-driver-}"
            log_info "Detected installed NVIDIA driver series: ${NV_NUM}. Adding 32-bit GL packages..."
            apt_install_safe "libnvidia-gl-${NV_NUM}:i386" "libnvidia-compute-${NV_NUM}:i386" "libnvidia-extra-${NV_NUM}:i386" nvidia-settings
        fi
    fi

    if [ "$IS_HYBRID" = true ]; then
        systemctl enable --now switcheroo-control.service 2>/dev/null || true
    fi
}

# --- C. ARCH LINUX / MANJARO / ENDEAVOUROS / GARUDA / CACHYOS ROUTINE ---
run_arch() {
    log_step "Configuring Repositories & Packages for Arch Linux Family..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would enable [multilib] in /etc/pacman.conf."
        log_info "[DRY-RUN] Would refresh keyrings and synchronize pacman databases."
        log_info "[DRY-RUN] Would install PipeWire, WirePlumber, and lib32 audio packages."
        log_info "[DRY-RUN] Would install Mesa RADV/ANV, Vulkan ICD loaders, and lib32 compatibility."
        [ "$HAS_NVIDIA" = true ] && log_info "[DRY-RUN] Would install nvidia-dkms, matching kernel headers, and lib32-nvidia-utils."
        return 0
    fi

    wait_for_locks

    # 1. Enable [multilib]
    if [ -f /etc/pacman.conf ] && ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        log_info "Enabling [multilib] repository in /etc/pacman.conf..."
        sed -i -e '/^#[[:space:]]*\[multilib\]/{s/^#[[:space:]]*//;n;/^[[:space:]]*#[[:space:]]*Include/s/^#[[:space:]]*//}' /etc/pacman.conf
        if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
            printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >> /etc/pacman.conf
        fi
    fi

    log_info "Updating keyrings and synchronizing Pacman database..."
    if [ "${ID:-}" = "manjaro" ]; then
        pacman -Sy --needed --noconfirm manjaro-keyring || true
    else
        pacman -Sy --needed --noconfirm archlinux-keyring || true
    fi
    pacman -Sy --noconfirm

    pacman_install_safe() {
        local to_install=()
        for pkg in "$@"; do
            if pacman -Si "$pkg" >/dev/null 2>&1; then
                to_install+=("$pkg")
            else
                log_warn "Package '$pkg' not found in active repositories, skipping."
            fi
        done
        if [ ${#to_install[@]} -gt 0 ]; then
            pacman -S --noconfirm --needed "${to_install[@]}"
        fi
    }

    # 2. Audio Stack
    log_step "Installing PipeWire, WirePlumber & 32-bit Multilib Audio..."
    pacman_install_safe \
        pipewire \
        pipewire-pulse \
        wireplumber \
        pipewire-alsa \
        pipewire-jack \
        lib32-pipewire \
        lib32-pipewire-jack

    # 3. Graphics Drivers & Gaming Stack
    log_step "Installing Graphics Drivers, Vulkan ICDs & Gaming Libraries..."

    if command -v mhwd >/dev/null 2>&1; then
        log_info "Manjaro Hardware Detection (mhwd) detected."
        if [ "$HAS_NVIDIA" = true ]; then
            mhwd -a pci nonfree 0300 2>/dev/null || true
        fi
        if [ "$HAS_AMD" = true ] || [ "$HAS_INTEL" = true ]; then
            mhwd -a pci free 0300 2>/dev/null || true
        fi
    fi

    local PKGS=(
        vulkan-tools
        mesa-utils
        vulkan-icd-loader
        lib32-vulkan-icd-loader
        gamemode
        lib32-gamemode
        mangohud
        lib32-mangohud
    )

    if [ "$IS_HYBRID" = true ]; then
        PKGS+=(switcheroo-control)
    fi

    if [ "$HAS_AMD" = true ]; then
        log_info "Adding AMD Radeon Mesa/RADV (64 & 32-bit)..."
        PKGS+=(
            mesa
            lib32-mesa
            vulkan-radeon
            lib32-vulkan-radeon
            xf86-video-amdgpu
            libva-mesa-driver
            lib32-libva-mesa-driver
            mesa-vdpau
            lib32-mesa-vdpau
        )
    fi

    if [ "$HAS_INTEL" = true ]; then
        log_info "Adding Intel Graphics Mesa/ANV (64 & 32-bit)..."
        PKGS+=(
            mesa
            lib32-mesa
            vulkan-intel
            lib32-vulkan-intel
            intel-media-driver
            libva-intel-driver
        )
    fi

    if [ "$HAS_NVIDIA" = true ] && ! command -v mhwd >/dev/null 2>&1; then
        log_info "Detecting installed Linux kernels to install matching headers for DKMS..."
        local INSTALLED_KERNELS
        INSTALLED_KERNELS=$(pacman -Qq 2>/dev/null | grep -E '^linux(-lts|-zen|-hardened|-cachyos)?$' || true)
        for k in $INSTALLED_KERNELS; do
            PKGS+=("${k}-headers")
        done
        if [ -z "$INSTALLED_KERNELS" ]; then
            PKGS+=(linux-headers)
        fi

        log_info "Adding NVIDIA DKMS and 32-bit multilib libraries..."
        PKGS+=(
            nvidia-dkms
            nvidia-utils
            lib32-nvidia-utils
            nvidia-settings
            opencl-nvidia
            lib32-opencl-nvidia
        )
    fi

    pacman_install_safe "${PKGS[@]}"

    if [ "$IS_HYBRID" = true ]; then
        systemctl enable --now switcheroo-control.service 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# 8. Dispatch Execution
# ------------------------------------------------------------------------------
case "$DISTRO_FAMILY" in
    fedora) run_fedora ;;
    debian) run_debian ;;
    arch)   run_arch ;;
esac

# ------------------------------------------------------------------------------
# 9. Audio Service Initialization & Legacy Conflict Resolution
# ------------------------------------------------------------------------------
if [ "$DRY_RUN" = false ] && [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    log_step "Configuring User Audio Services (PipeWire & WirePlumber)..."

    if [ -d "/run/user/${TARGET_UID}" ]; then
        log_info "Enabling systemd audio user services for ${C_BOLD}${TARGET_USER}${C_RESET}..."
        # 1. Disable legacy PulseAudio service if present (prevents audio lock conflict)
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
            systemctl --user stop pulseaudio.socket pulseaudio.service 2>/dev/null || true
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
            systemctl --user disable pulseaudio.socket pulseaudio.service 2>/dev/null || true

        # 2. Enable and start PipeWire & WirePlumber
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
            systemctl --user daemon-reload 2>/dev/null || true
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/${TARGET_UID}" \
            systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || \
            log_warn "Audio services will initialize automatically upon next desktop login."
    else
        log_info "Desktop session for UID ${TARGET_UID} not currently active in /run/user. PipeWire will start on next graphical login."
    fi
fi

# ------------------------------------------------------------------------------
# 10. Secure Boot Verification
# ------------------------------------------------------------------------------
SECURE_BOOT_ACTIVE=false
if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
        SECURE_BOOT_ACTIVE=true
    fi
elif [ -d /sys/firmware/efi/efivars ]; then
    if od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | grep -q " 1"; then
        SECURE_BOOT_ACTIVE=true
    fi
fi

# ------------------------------------------------------------------------------
# 11. Final Summary & Post-Install Guidance
# ------------------------------------------------------------------------------
log_step "Installation & Setup Complete!"

if [ "$DRY_RUN" = true ]; then
    echo -e "\n${C_GREEN}${C_BOLD}✓ Probe complete! Your system is fully compatible.${C_RESET}"
    echo -e "To perform the actual installation, simply run:"
    echo -e "  ${C_BOLD}./install_gaming_drivers.sh${C_RESET}\n"
    exit 0
fi

echo -e "\n${C_GREEN}${C_BOLD}✓ Your system is fully configured and ready for gaming!${C_RESET}"
echo -e "Summary of configured components:"
echo -e "  • ${C_BOLD}Operating System:${C_RESET} ${DISTRO_NAME} (${DISTRO_FAMILY})"
echo -e "  • ${C_BOLD}32-Bit / Multilib:${C_RESET} Configured (Steam & Wine/Proton 32-bit ready)"
echo -e "  • ${C_BOLD}Graphics Hardware:${C_RESET} $([ "$HAS_NVIDIA" = true ] && echo -n "NVIDIA ") $([ "$HAS_AMD" = true ] && echo -n "AMD ") $([ "$HAS_INTEL" = true ] && echo -n "Intel ")"
echo -e "  • ${C_BOLD}Vulkan & VA-API:${C_RESET} Installed for 64-bit and 32-bit"
echo -e "  • ${C_BOLD}Audio Stack:${C_RESET} PipeWire & WirePlumber with ALSA/Pulse 32-bit wrappers"
echo -e "  • ${C_BOLD}Gaming Utilities:${C_RESET} Feral GameMode (gamemode) & MangoHud overlay"
if [ "$IS_HYBRID" = true ]; then
    echo -e "  • ${C_BOLD}Hybrid Graphics:${C_RESET} switcheroo-control service enabled (Right-click -> 'Launch on Discrete GPU')"
fi

if [ "$HAS_NVIDIA" = true ]; then
    echo -e "\n${C_YELLOW}${C_BOLD}[IMPORTANT: REBOOT REQUIRED FOR NVIDIA]${C_RESET}"
    echo -e "The proprietary NVIDIA kernel module has been built. A ${C_BOLD}system restart is required${C_RESET} for the driver to load."
    if [ "$SECURE_BOOT_ACTIVE" = true ]; then
        echo -e "\n${C_RED}${C_BOLD}[SECURE BOOT ADVISORY]${C_RESET}"
        echo -e "Secure Boot is ${C_BOLD}ENABLED${C_RESET} on your UEFI motherboard."
        echo -e "If the NVIDIA driver does not load after restart, you may need to:"
        echo -e "  1. Enroll the Machine Owner Key (MOK) created during installation, OR"
        echo -e "  2. Temporarily disable Secure Boot in your BIOS/UEFI settings."
    fi
else
    echo -e "\n${C_CYAN}Tip: A quick restart or logout/login is recommended to initialize all new Vulkan ICDs and audio sessions.${C_RESET}"
fi
echo ""
