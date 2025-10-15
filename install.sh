#!/bin/bash

# Voicenote Automation Installer
# This script sets up the environment, dependencies, and services for the automation.

set -e # Exit immediately if a command fails

# --- Configuration ---
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CONFIG_DIR="$HOME/.config/voicenote-automation"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
LOG_DIR="$HOME/Automation/voicenotes/logs"


# --- Helper Functions ---
print_info() {
    echo -e "\033[34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
    exit 1
}

# --- Main Installation Logic ---

# Step 1: Install System Dependencies
print_info "Updating package database and installing dependencies (git, ffmpeg, pipx)..."
if command -v pamac &> /dev/null; then
    pamac install git ffmpeg --no-confirm
else
    sudo pacman -Syu git ffmpeg  --noconfirm
fi
print_success "System dependencies installed."

#python-pipx

# Step 2: Install whisper.cpp and download model
print_info "Installing whisper.cpp"
if command -v pamac &> /dev/null; then
    pamac whisper.cpp --no-confirm
else
    echo "Require pamac to install from aur"
    exit 1
fi
print_success "whisper.cpp installed..."

# Clone whisper.cpp repo in a temporary directory
print_info "Cloning whisper.cpp repository into temporary directory..."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT  # Ensure cleanup on exit

git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$TEMP_DIR/whisper.cpp"
print_success "Repository cloned to $TEMP_DIR/whisper.cpp"

# Download Whisper model using provided script
MODEL_SIZE="base"  # Options: tiny, base, small, medium, large
print_info "Downloading Whisper model: $MODEL_SIZE..."
cd "$TEMP_DIR/whisper.cpp/models"
bash download-ggml-model.sh "$MODEL_SIZE"
print_success "Model '$MODEL_SIZE' downloaded successfully."

# Move model to a permanent location
MODEL_DEST="$HOME/.local/share/whisper.cpp/models"
mkdir -p "$MODEL_DEST"
mv "ggml-${MODEL_SIZE}.bin" "$MODEL_DEST/"
print_success "Model moved to $MODEL_DEST/ggml-${MODEL_SIZE}.bin"


# Step 3: Create Application Directories from Config
print_info "Setting up configuration..."
mkdir -p "$CONFIG_DIR"
cp "$INSTALL_DIR/config/voicenote-automation.conf" "$CONFIG_DIR/config"
# Source the config to get directory paths
source "$CONFIG_DIR/config"
print_info "Creating required directories..."
mkdir -p "$VOICENOTES_IN_DIR" "$VOICENOTES_ARCHIVE_DIR" "$LOG_DIR"
print_success "Application directories created."
print_info "  - Input: $VOICENOTES_IN_DIR"
print_info "  - Archive: $VOICENOTES_ARCHIVE_DIR"
print_info "  - Logs: $LOG_DIR"


# Step 4: Make scripts executable
print_info "Making processing script executable..."
chmod +x "$INSTALL_DIR/bin/process-voicenote.sh"
print_success "Script is now executable."

# Step 5: Install systemd user services
print_info "Installing systemd user services..."
mkdir -p "$SYSTEMD_USER_DIR"
cp "$INSTALL_DIR/systemd/voicenote-processor.path" "$SYSTEMD_USER_DIR/"
cp "$INSTALL_DIR/systemd/voicenote-processor.service" "$SYSTEMD_USER_DIR/"
# Replace placeholder path in service file with the actual path
sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "$SYSTEMD_USER_DIR/voicenote-processor.service"
print_success "Systemd units installed."

# Step 6: Reload systemd and start services
print_info "Reloading systemd daemon and enabling the path watcher..."
systemctl --user daemon-reload
systemctl --user enable --now voicenote-processor.path
print_success "Path watcher is now enabled and active."


# --- Final Instructions ---
echo
print_success "Installation Complete!"
echo
print_warning "ACTION REQUIRED: Please edit the configuration file to match your setup:"
print_warning "  vim $CONFIG_DIR/config"
echo
print_info "To check the status of the watcher, run:"
print_info "  systemctl --user status voicenote-processor.path"
echo
print_info "To monitor the logs in real-time, run:"
print_info "  tail -f \"$LOG_DIR/automation.log\""
echo
