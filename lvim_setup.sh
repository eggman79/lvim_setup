#!/bin/bash

################################################################################
# LunarVim Installer Script with Enhanced Logging and Comments
# 
# This script installs LunarVim (a Neovim IDE layer) with all required dependencies:
# - Python (via pyenv)
# - Node.js (via nvm) 
# - Rust (via rustup)
# - Neovim
# - LunarVim
# - Nerd Fonts
#
# Author: Enhanced version with logging and comments
# Usage: bash lvim_installer.sh
# 
# NOTE: This script runs ALL installations without prompts (non-interactive mode)
#################################################################################

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive

# Disable prompts for all package installations
export APT_LISTCHANGES_FRONTEND=none

# Color codes for better log visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        log_success "$1"
    else
        log_error "$1 failed"
        exit 1
    fi
}

# Main installation starts here
log_info "Starting LunarVim installation process..."

#################################################################################
# STEP 1: System Package Installation
#################################################################################
log_info "Step 1: Updating system packages and installing dependencies..."

# Update package lists and upgrade existing packages (non-interactive)
log_info "Updating package repositories..."
apt update -qq
check_status "Package repository update"

log_info "Upgrading existing packages..."
apt upgrade -y -qq
check_status "Package upgrade"

# Install all required system dependencies for building Python, Node.js, and other tools (non-interactive)
log_info "Installing system dependencies..."
apt install -y -qq tmux git curl g++ cmake automake vim zlib1g-dev libssl-dev openssl bzip2 libbz2-dev libncurses5-dev libncursesw5-dev libffi-dev libreadline-dev sqlite3 libsqlite3-dev liblzma-dev ruby-full fontconfig sudo
check_status "System dependencies installation"

# Set C++ compiler environment variable (required for some Python packages)
log_info "Setting C++ compiler environment variable..."
export CXX=`which g++`
log_info "CXX compiler set to: $CXX"

#################################################################################
# STEP 2: Python Environment Setup (via pyenv)
#################################################################################
log_info "Step 2: Setting up Python environment with pyenv..."

# Remove any existing pyenv installation to ensure clean setup
log_info "Removing existing pyenv installation (if any)..."
rm -rf $HOME/.pyenv

# Install pyenv (Python version manager)
log_info "Installing pyenv..."
curl -fsSL https://pyenv.run | bash
check_status "pyenv installation"

# Configure shell environment for pyenv
log_info "Configuring shell environment for pyenv..."
bashrc="$HOME/.bashrc"

# Add pyenv configuration to .bashrc
cat >>$bashrc << 'EOL'
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
export PATH="$PATH:/opt/nvim-linux64/bin:$HOME/.local/bin:$HOME/.cargo/bin"
EOL

# Remove problematic PS1 check that can interfere with non-interactive shells
log_info "Cleaning up .bashrc configuration..."
sed -i.bak '/\-z "\$PS1"/d' "$bashrc"

# Reload shell configuration
log_info "Reloading shell configuration..."
source "$bashrc"

# Verify pyenv installation
pyenv --version
check_status "pyenv configuration verification"

# Find and install the latest stable Python version
log_info "Finding latest Python version..."
last_python_ver=`pyenv install --list|egrep '^\s*[0-9]'|grep -v [a-z]|tail -n1|sed 's/ //g'`

# Validate that we found a Python version
if [ "$last_python_ver" == "" ]; then
    log_error "Cannot find latest Python version"
    exit 1
fi

log_info "Latest Python version found: $last_python_ver"

# Install the latest Python version (non-interactive)
log_info "Installing Python $last_python_ver (this may take several minutes)..."
PYTHON_CONFIGURE_OPTS="--enable-optimizations" pyenv install "$last_python_ver" --skip-existing
check_status "Python $last_python_ver installation"

# Set the installed Python version as global default
log_info "Setting Python $last_python_ver as global default..."
pyenv global "$last_python_ver"
check_status "Python global version setting"

# Upgrade pip to latest version
log_info "Upgrading pip to latest version..."
pip install --upgrade pip
check_status "pip upgrade"

# Install Python Neovim provider
log_info "Installing Python Neovim provider..."
pip install neovim
check_status "Python Neovim provider installation"

#################################################################################
# STEP 3: Ruby Neovim Provider Setup
#################################################################################
log_info "Step 3: Setting up Ruby Neovim provider..."

# Install Ruby Neovim provider (non-interactive)
log_info "Installing Ruby Neovim provider..."
sudo gem install neovim --no-document
check_status "Ruby Neovim provider installation"

#################################################################################
# STEP 4: Node.js Environment Setup (via nvm)
#################################################################################
log_info "Step 4: Setting up Node.js environment with nvm..."

# Install nvm (Node Version Manager)
log_info "Installing nvm (Node Version Manager)..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
check_status "nvm installation"

# Load nvm into current shell session
log_info "Loading nvm into current session..."
\. "$HOME/.nvm/nvm.sh"

# Install Node.js version 22 (LTS) - non-interactive
log_info "Installing Node.js version 22..."
nvm install 22 --silent
check_status "Node.js 22 installation"

# Install Node.js Neovim provider globally (silent)
log_info "Installing Node.js Neovim provider..."
npm install -g neovim --silent
check_status "Node.js Neovim provider installation"

#################################################################################
# STEP 5: Rust Environment Setup
#################################################################################
log_info "Step 5: Setting up Rust environment..."

# Install Rust programming language via rustup (non-interactive)
log_info "Installing Rust via rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
check_status "Rust installation"

#################################################################################
# STEP 6: Neovim Installation
#################################################################################
log_info "Step 6: Installing Neovim..."

# Define Neovim package filename
nvim_zip=nvim-linux64.tar.gz

# Download Neovim stable release
log_info "Downloading Neovim v0.9.5..."
curl -LO https://github.com/neovim/neovim/releases/download/v0.9.5/$nvim_zip
check_status "Neovim download"

# Remove any existing Neovim installation
log_info "Removing existing Neovim installation..."
rm -rf /opt/nvim

# Extract Neovim to /opt directory
log_info "Extracting Neovim to /opt..."
sudo tar -C /opt -xzf $nvim_zip
check_status "Neovim extraction"

#################################################################################
# STEP 7: LunarVim Installation
#################################################################################
log_info "Step 7: Installing LunarVim..."

# Install LunarVim using the official installer script
# Using specific branch for Neovim 0.9 compatibility
log_info "Running LunarVim installer..."
LV_BRANCH='release-1.4/neovim-0.9' bash <(curl -s https://raw.githubusercontent.com/LunarVim/LunarVim/release-1.4/neovim-0.9/utils/installer/install.sh) -y
check_status "LunarVim installation"

#################################################################################
# STEP 8: LunarVim Configuration
#################################################################################
log_info "Step 8: Configuring LunarVim..."

# Create LunarVim configuration directory if it doesn't exist
mkdir -p $HOME/.config/lvim

# Add Python provider configuration to LunarVim config
log_info "Adding Python provider configuration..."
cat >> $HOME/.config/lvim/config.lua << EOL
-- Python provider configuration
vim.g.python3_host_prog = '$HOME/.pyenv/versions/$last_python_ver/bin/python3'
-- Disable Perl provider (not needed)
vim.g.loaded_perl_provider = 0

lvim.builtin.dap.active = true

local dap = require("dap")
-- Function key mappings for DAP
lvim.keys.normal_mode["<F5>"] = "<cmd>lua require'dap'.continue()<CR>"
lvim.keys.normal_mode["<F6>"] = "<cmd>lua require'dap'.step_over()<CR>"
lvim.keys.normal_mode["<F7>"] = "<cmd>lua require'dap'.step_into()<CR>"
lvim.keys.normal_mode["<F8>"] = "<cmd>lua require'dap'.step_out()<CR>"
lvim.keys.normal_mode["<F9>"] = "<cmd>lua require'dap'.toggle_breakpoint()<CR>"
lvim.keys.normal_mode["<F10>"] = "<cmd>lua require'dap'.set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>"
lvim.keys.normal_mode["<F12>"] = "<cmd>lua require'dap.ui.widgets'.hover()<CR>"

-- Additional useful mappings

lvim.keys.normal_mode["<F4>"] = "<cmd>lua require'dap'.terminate()<CR>"
-- Setup DAP after it loads

lvim.builtin.dap.on_config_done = function(dap)
  local mason_registry = require("mason-registry")
  local codelldb = mason_registry.get_package("codelldb")
  local extension_path = codelldb:get_install_path() .. "/extension/"
  local codelldb_path = extension_path .. "adapter/codelldb"
  
  dap.adapters.codelldb = {
    type = 'server',
    port = "${port}",
    executable = {
      command = codelldb_path,
      args = {"--port", "${port}"},
    }
  }
  
  dap.configurations.cpp = {
    {
      name = "Launch file",
      type = "codelldb",
      request = "launch",
      program = function()
        return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
      end,
      cwd = '${workspaceFolder}',
      stopOnEntry = false,
    },
  }
  
  dap.configurations.c = dap.configurations.cpp
end
EOL

log_success "LunarVim configuration updated"

#################################################################################
# STEP 9: Nerd Fonts Installation
#################################################################################
log_info "Step 9: Installing Nerd Fonts..."

# Install Nerd Fonts for better terminal experience (non-interactive)
log_info "Installing Nerd Fonts..."
curl -fsSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh | bash -s -- 
check_status "Nerd Fonts installation"

# Refresh font cache
log_info "Refreshing font cache..."
fc-cache
check_status "Font cache refresh"

#################################################################################
# STEP 10: Final Setup and Plugin Sync
#################################################################################
log_info "Step 10: Finalizing LunarVim setup..."

# Update LunarVim and sync core plugins (headless mode)
log_info "Updating LunarVim and syncing core plugins..."
lvim --headless +LvimUpdate +LvimSyncCorePlugins +q
check_status "LunarVim update and plugin sync"

#################################################################################
# Installation Complete
#################################################################################
log_success "LunarVim installation completed successfully!"
echo
log_info "Installation Summary:"
log_info "- Python $last_python_ver installed via pyenv"
log_info "- Node.js 22 installed via nvm"
log_info "- Rust installed via rustup"
log_info "- Neovim v0.9.5 installed to /opt/nvim-linux64"
log_info "- LunarVim installed and configured"
log_info "- Nerd Fonts installed"
echo
log_info "Next steps:"
log_info "1. Restart your terminal or run: source ~/.bashrc"
log_info "2. Start LunarVim with: lvim"
log_info "3. Check providers with: :checkhealth provider"
echo
log_success "Happy coding with LunarVim! 🚀"
