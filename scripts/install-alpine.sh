#!/bin/sh
#
# install-alpine.sh — Install s-ui on Alpine Linux from this repository
#
# Usage:
#   ./install-alpine.sh <repo_url> [OPTIONS]
#
# Arguments:
#   repo_url          Git repository URL containing s-ui binaries
#
# Options:
#   --arch <arch>     Force architecture (amd64|arm64). Auto-detected by default.
#   --install-dir <d> Installation directory. Default: /usr/local/s-ui
#   --branch <b>      Git branch to track. Default: main
#   --uninstall       Remove s-ui, OpenRC service, and data
#   -h, --help        Show this help
#
# Examples:
#   ./install-alpine.sh https://github.com/user/alpine-s-ui-light.git
#   ./install-alpine.sh https://github.com/user/alpine-s-ui-light.git --arch arm64
#   ./install-alpine.sh --uninstall

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info()  { printf "${GREEN}[INF]${NC} %s\n" "$*"; }
log_warn()  { printf "${YELLOW}[WRN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERR]${NC} %s\n" "$*"; }

# ── Defaults ──────────────────────────────────────────────────────────────────
INSTALL_DIR="/usr/local/s-ui"
DATA_DIR="/etc/s-ui"
LOG_FILE="/var/log/s-ui.log"
INIT_SCRIPT="/etc/init.d/s-ui"
REPO_DIR="/opt/alpine-s-ui-light"
BRANCH="main"
ARCH=""
REPO_URL=""
UNINSTALL=false

# ── Parse arguments ───────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            sed -n '3,/^$/s/^# \?//p' "$0"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [ -z "$REPO_URL" ]; then
                REPO_URL="$1"
            else
                log_error "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# ── OS check ──────────────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "alpine" ]; then
        log_warn "This script is designed for Alpine Linux. Detected: $ID"
    fi
else
    log_warn "Cannot detect OS. Proceeding anyway."
fi

# ── Detect architecture ───────────────────────────────────────────────────────
detect_arch() {
    if [ -n "$ARCH" ]; then
        case "$ARCH" in
            amd64|arm64) ;;
            *) log_error "Unsupported architecture: $ARCH (use amd64 or arm64)"; exit 1 ;;
        esac
        return
    fi

    MACHINE=$(uname -m)
    case "$MACHINE" in
        x86_64|amd64)   ARCH="amd64" ;;
        aarch64|arm64)  ARCH="arm64" ;;
        *)
            log_error "Unsupported architecture: $MACHINE"
            log_error "Use --arch amd64|arm64 to force"
            exit 1
            ;;
    esac
    log_info "Detected architecture: $ARCH ($MACHINE)"
}

# ── Check dependencies ────────────────────────────────────────────────────────
check_deps() {
    local missing=""
    for cmd in git rc-service rc-update; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        log_error "Missing required commands:$missing"
        log_info "Install with: apk add git openrc"
        exit 1
    fi
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
do_uninstall() {
    log_info "Uninstalling s-ui..."

    # Stop service
    if rc-service s-ui status >/dev/null 2>&1; then
        rc-service s-ui stop 2>/dev/null || true
    fi

    # Remove from boot
    rc-update del s-ui default 2>/dev/null || true

    # Remove init script
    rm -f "$INIT_SCRIPT"

    # Remove install dir
    rm -rf "$INSTALL_DIR"

    # Remove cloned repo
    rm -rf "$REPO_DIR"

    # Ask about data
    if [ -d "$DATA_DIR" ]; then
        printf "Remove data directory %s? [y/N]: " "$DATA_DIR"
        read -r ans
        case "$ans" in
            y|Y) rm -rf "$DATA_DIR"; log_info "Removed $DATA_DIR" ;;
            *)   log_info "Kept $DATA_DIR" ;;
        esac
    fi

    rm -f "$LOG_FILE"
    log_info "s-ui uninstalled successfully"
    exit 0
}

# ── Sync repository ───────────────────────────────────────────────────────────
sync_repo() {
    if [ -z "$REPO_URL" ]; then
        log_error "Repository URL is required"
        log_info "Usage: $0 <repo_url> [--arch amd64|arm64]"
        exit 1
    fi

    mkdir -p "$(dirname "$REPO_DIR")"

    if [ -d "$REPO_DIR/.git" ]; then
        log_info "Updating existing repository..."
        cd "$REPO_DIR"
        git fetch origin "$BRANCH"
        git reset --hard "origin/$BRANCH"
    else
        log_info "Cloning repository..."
        git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR"
    fi

    # Verify architecture directory exists
    if [ ! -d "$REPO_DIR/$ARCH" ]; then
        log_error "Architecture directory not found: $REPO_DIR/$ARCH"
        exit 1
    fi

    # Check version
    if [ -f "$REPO_DIR/$ARCH/version.txt" ]; then
        REMOTE_VER=$(cat "$REPO_DIR/$ARCH/version.txt")
        log_info "Remote version: $REMOTE_VER"
    fi
}

# ── Install binary ────────────────────────────────────────────────────────────
install_binary() {
    log_info "Installing s-ui ($ARCH) to $INSTALL_DIR..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR"

    # Copy files from repo to install dir
    cp -f "$REPO_DIR/$ARCH/sui" "$INSTALL_DIR/sui"
    chmod +x "$INSTALL_DIR/sui"

    # Copy version
    if [ -f "$REPO_DIR/$ARCH/version.txt" ]; then
        cp -f "$REPO_DIR/$ARCH/version.txt" "$INSTALL_DIR/version.txt"
    fi

    # Copy optional s-ui.sh (management script, can be used for admin commands)
    if [ -f "$REPO_DIR/$ARCH/s-ui.sh" ]; then
        cp -f "$REPO_DIR/$ARCH/s-ui.sh" "$INSTALL_DIR/s-ui.sh"
        chmod +x "$INSTALL_DIR/s-ui.sh"
    fi

    log_info "Binary installed to $INSTALL_DIR/sui"
}

# ── Create OpenRC service ─────────────────────────────────────────────────────
install_openrc_service() {
    log_info "Creating OpenRC service..."

    cat > "$INIT_SCRIPT" << 'INITEOF'
#!/sbin/openrc-run

supervisor=supervise-daemon

name="s-ui"
description="s-ui Panel (Sing-Box based)"
command="/usr/local/s-ui/sui"
directory="/usr/local/s-ui"

output_log="/var/log/s-ui.log"
error_log="/var/log/s-ui.log"

depend() {
    need net
    after firewall
}

start_pre() {
    if [ ! -d /etc/s-ui ]; then
        mkdir -p /etc/s-ui
    fi
}
INITEOF

    chmod +x "$INIT_SCRIPT"
    log_info "OpenRC service created at $INIT_SCRIPT"
}

# ── Enable and start ─────────────────────────────────────────────────────────
enable_and_start() {
    # Add to default runlevel (boot auto-start)
    rc-update add s-ui default 2>/dev/null || {
        log_warn "s-ui already in default runlevel or rc-update failed"
    }

    # Start the service
    log_info "Starting s-ui service..."
    rc-service s-ui start

    sleep 2

    # Check status
    if rc-service s-ui status; then
        log_info "s-ui is running!"
        LOCAL_VER=$(cat "$INSTALL_DIR/version.txt" 2>/dev/null || echo "unknown")
        log_info "Version: $LOCAL_VER"
        log_info "Data directory: $DATA_DIR"
        log_info "Log file: $LOG_FILE"
    else
        log_error "s-ui failed to start. Check logs: $LOG_FILE"
        exit 1
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    if $UNINSTALL; then
        do_uninstall
    fi

    log_info "=== s-ui Alpine Installer ==="

    detect_arch
    check_deps
    sync_repo
    install_binary
    install_openrc_service
    enable_and_start

    log_info "=== Installation complete ==="
    log_info "Service: rc-service s-ui {start|stop|restart|status}"
    log_info "Manage:  rc-update {add|del} s-ui default"
    log_info "Logs:    tail -f $LOG_FILE"
}

main
