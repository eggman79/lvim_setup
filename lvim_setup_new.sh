#!/usr/bin/env bash
set -Eeuo pipefail

# LunarVim 1.4 installer for Debian/Ubuntu.
#
# Stable defaults are intentionally pinned to the official
# LunarVim 1.4 / Neovim 0.9 branch.
#
# Override when needed, for example:
#   LV_BRANCH=master NVIM_VERSION=0.10.4 bash ./lvim_installer_fixed.sh

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

LV_BRANCH="${LV_BRANCH:-release-1.4/neovim-0.9}"
NVIM_VERSION="${NVIM_VERSION:-0.9.5}"
PYTHON_MINOR="${PYTHON_MINOR:-3.13}"
INSTALL_FONTS="${INSTALL_FONTS:-1}"

readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log() {
    printf '%b[%s]%b %s - %s\n' \
        "$1" \
        "$(date '+%F %T')" \
        "$NC" \
        "$2" \
        "$3"
}

info() {
    log "$BLUE" INFO "$1"
}

ok() {
    log "$GREEN" SUCCESS "$1"
}

warn() {
    log "$YELLOW" WARNING "$1"
}

fatal() {
    log "$RED" ERROR "$1" >&2
    exit 1
}

trap 'fatal "Błąd w linii $LINENO: $BASH_COMMAND"' ERR

if [[ "$(id -u)" -eq 0 ]]; then
    fatal "Uruchom skrypt jako zwykły użytkownik, nie jako root."
fi

if ! command -v sudo >/dev/null 2>&1; then
    fatal "Brak programu sudo."
fi

sudo -v

append_once() {
    local line="$1"
    local file="$2"

    grep -Fqx "$line" "$file" 2>/dev/null || {
        printf '%s\n' "$line" >> "$file"
    }
}

###############################################################################
# STEP 1: System dependencies
###############################################################################

info "Instalowanie zależności systemowych..."

sudo apt-get update -qq

sudo apt-get install -y -qq \
    build-essential \
    cmake \
    automake \
    autoconf \
    libtool \
    libtool-bin \
    pkg-config \
    gettext \
    unzip \
    curl \
    wget \
    git \
    tmux \
    ripgrep \
    fzf \
    xclip \
    fontconfig \
    zlib1g-dev \
    libssl-dev \
    libbz2-dev \
    libncurses-dev \
    libffi-dev \
    libreadline-dev \
    libsqlite3-dev \
    liblzma-dev \
    tk-dev \
    uuid-dev \
    ca-certificates \
    ruby-full \
    clang \
    lldb

ok "Zależności systemowe zainstalowane."

###############################################################################
# STEP 2: pyenv and Python provider
###############################################################################

export PYENV_ROOT="$HOME/.pyenv"

if [[ ! -x "$PYENV_ROOT/bin/pyenv" ]]; then
    info "Instalowanie pyenv..."

    curl -fsSL https://pyenv.run | bash
fi

export PATH="$PYENV_ROOT/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

eval "$(pyenv init - bash)"

append_once \
    'export PYENV_ROOT="$HOME/.pyenv"' \
    "$HOME/.bashrc"

append_once \
    '[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"' \
    "$HOME/.bashrc"

append_once \
    'eval "$(pyenv init - bash)"' \
    "$HOME/.bashrc"

append_once \
    'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' \
    "$HOME/.bashrc"

info "Wyszukiwanie najnowszego wydania Pythona ${PYTHON_MINOR}.x..."

PYTHON_VERSION="$(
    pyenv install --list |
        sed 's/^ *//' |
        grep -E "^${PYTHON_MINOR//./\\.}\\.[0-9]+$" |
        sort -V |
        tail -n1
)"

if [[ -z "$PYTHON_VERSION" ]]; then
    fatal "Nie znaleziono Pythona ${PYTHON_MINOR}.x."
fi

info "Instalowanie Pythona ${PYTHON_VERSION}..."

pyenv install --skip-existing "$PYTHON_VERSION"
pyenv global "$PYTHON_VERSION"

PYTHON_BIN="$PYENV_ROOT/versions/$PYTHON_VERSION/bin/python"

"$PYTHON_BIN" -m pip install --upgrade pip
"$PYTHON_BIN" -m pip install --upgrade pynvim

ok "Python $PYTHON_VERSION i provider pynvim gotowe."

###############################################################################
# STEP 3: Ruby provider
###############################################################################

info "Instalowanie providera Ruby..."

sudo gem install --no-document neovim

ok "Provider Ruby zainstalowany."

###############################################################################
# STEP 4: Node.js, npm and Node provider
###############################################################################

export NVM_DIR="$HOME/.nvm"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    info "Instalowanie nvm..."

    curl -fsSL \
        https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh |
        bash
fi

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

info "Instalowanie najnowszego wydania LTS Node.js..."

nvm install --lts >/dev/null
nvm alias default 'lts/*' >/dev/null

# Avoid permission problems with global npm packages.
npm config set prefix "$HOME/.local"

npm install --global neovim
npm install --global tree-sitter-cli

ok "Node.js, provider Node i tree-sitter-cli gotowe."

###############################################################################
# STEP 5: Rust
###############################################################################

if [[ ! -x "$HOME/.cargo/bin/rustc" ]]; then
    info "Instalowanie Rust..."

    curl \
        --proto '=https' \
        --tlsv1.2 \
        -sSf \
        https://sh.rustup.rs |
        sh -s -- -y
fi

# shellcheck source=/dev/null
source "$HOME/.cargo/env"

ok "Rust zainstalowany."

###############################################################################
# STEP 6: Neovim
###############################################################################

case "$(uname -m)" in
    x86_64)
        NVIM_ARCHIVE="nvim-linux64.tar.gz"
        NVIM_DIR="nvim-linux64"
        ;;

    aarch64|arm64)
        NVIM_ARCHIVE="nvim-linux-arm64.tar.gz"
        NVIM_DIR="nvim-linux-arm64"
        ;;

    *)
        fatal "Nieobsługiwana architektura: $(uname -m)"
        ;;
esac

info "Instalowanie Neovim v${NVIM_VERSION}..."

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

curl \
    -fL \
    --retry 3 \
    -o "$TMP_DIR/$NVIM_ARCHIVE" \
    "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/${NVIM_ARCHIVE}"

tar \
    -C "$TMP_DIR" \
    -xzf "$TMP_DIR/$NVIM_ARCHIVE"

sudo rm -rf "/opt/$NVIM_DIR"
sudo mv "$TMP_DIR/$NVIM_DIR" "/opt/$NVIM_DIR"

sudo ln -sfn \
    "/opt/$NVIM_DIR/bin/nvim" \
    /usr/local/bin/nvim

if ! command -v nvim >/dev/null 2>&1; then
    fatal "Nie znaleziono polecenia nvim po instalacji."
fi

if [[ "$(nvim --version | head -n1)" != *"v${NVIM_VERSION}"* ]]; then
    fatal "Nieprawidłowa wersja Neovim w PATH."
fi

ok "Neovim v${NVIM_VERSION} zainstalowany."

###############################################################################
# STEP 7: LunarVim
###############################################################################

info "Instalowanie LunarVim z gałęzi ${LV_BRANCH}..."

curl -fsSL \
    "https://raw.githubusercontent.com/LunarVim/LunarVim/${LV_BRANCH}/utils/installer/install.sh" |
    LV_BRANCH="$LV_BRANCH" bash -s -- -y

export PATH="$HOME/.local/bin:$PATH"

if ! command -v lvim >/dev/null 2>&1; then
    fatal "Instalator nie utworzył polecenia lvim."
fi

ok "LunarVim zainstalowany."

###############################################################################
# STEP 8: LunarVim configuration
###############################################################################

CONFIG_DIR="$HOME/.config/lvim"
CONFIG_FILE="$CONFIG_DIR/config.lua"

mkdir -p "$CONFIG_DIR"

if [[ -s "$CONFIG_FILE" ]] &&
   ! grep -q 'BEGIN managed installer config' "$CONFIG_FILE"; then

    BACKUP_FILE="${CONFIG_FILE}.before-lvim-installer.$(date +%Y%m%d%H%M%S)"

    cp -a "$CONFIG_FILE" "$BACKUP_FILE"

    warn "Istniejąca konfiguracja została zapisana jako:"
    warn "$BACKUP_FILE"
fi

PYTHON_PATH_LUA="${PYTHON_BIN//\\/\\\\}"

cat > "$CONFIG_FILE" <<LUA
-- BEGIN managed installer config

vim.g.python3_host_prog = "$PYTHON_PATH_LUA"

-- Perl provider is not required.
vim.g.loaded_perl_provider = 0

-- Enable DAP.
lvim.builtin.dap.active = true

-- Install codelldb through Mason.
lvim.builtin.mason.ensure_installed = {
  "codelldb",
}

-- Configure C/C++ debugging.
lvim.builtin.dap.on_config_done = function(dap)
  local registry = require("mason-registry")
  local package = registry.get_package("codelldb")
  local extension = package:get_install_path() .. "/extension/"
  local adapter = extension .. "adapter/codelldb"

  dap.adapters.codelldb = {
    type = "server",
    port = "\${port}",
    executable = {
      command = adapter,
      args = {
        "--port",
        "\${port}",
      },
    },
  }

  dap.configurations.cpp = {
    {
      name = "Launch file",
      type = "codelldb",
      request = "launch",

      program = function()
        return vim.fn.input(
          "Path to executable: ",
          vim.fn.getcwd() .. "/",
          "file"
        )
      end,

      cwd = "\${workspaceFolder}",
      stopOnEntry = false,
    },
  }

  dap.configurations.c = dap.configurations.cpp
end

-- DAP key mappings.
lvim.keys.normal_mode["<F4>"] =
  "<cmd>lua require('dap').terminate()<CR>"

lvim.keys.normal_mode["<F5>"] =
  "<cmd>lua require('dap').continue()<CR>"

lvim.keys.normal_mode["<F6>"] =
  "<cmd>lua require('dap').step_over()<CR>"

lvim.keys.normal_mode["<F7>"] =
  "<cmd>lua require('dap').step_into()<CR>"

lvim.keys.normal_mode["<F8>"] =
  "<cmd>lua require('dap').step_out()<CR>"

lvim.keys.normal_mode["<F9>"] =
  "<cmd>lua require('dap').toggle_breakpoint()<CR>"

lvim.keys.normal_mode["<F10>"] =
  "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>"

lvim.keys.normal_mode["<F12>"] =
  "<cmd>lua require('dap.ui.widgets').hover()<CR>"

-- END managed installer config
LUA

ok "Konfiguracja LunarVim zapisana w $CONFIG_FILE."

###############################################################################
# STEP 9: Nerd Font
###############################################################################

if [[ "$INSTALL_FONTS" == "1" ]]; then
    info "Instalowanie Hack Nerd Font..."

    if ! command -v getnf >/dev/null 2>&1; then
        curl -fsSL \
            https://raw.githubusercontent.com/getnf/getnf/main/install.sh |
            bash -s -- --silent
    fi

    export PATH="$HOME/.local/bin:$PATH"

    if command -v getnf >/dev/null 2>&1; then
        if ! getnf -i Hack; then
            warn "Nie udało się zainstalować Hack Nerd Font."
        fi
    else
        warn "Polecenie getnf nie jest dostępne; pomijam instalację fontu."
    fi

    fc-cache -f

    ok "Konfiguracja fontów zakończona."
else
    info "Instalację fontów pominięto przez INSTALL_FONTS=$INSTALL_FONTS."
fi

###############################################################################
# STEP 10: Initial plugin synchronization
###############################################################################

info "Pierwsza synchronizacja pluginów LunarVim..."

"$HOME/.local/bin/lvim" \
    --headless \
    '+LvimSyncCorePlugins' \
    +q

ok "Synchronizacja pluginów zakończona."

###############################################################################
# Summary
###############################################################################

cat <<EOF

Instalacja zakończona.

  LunarVim: ${LV_BRANCH}
  Neovim:   ${NVIM_VERSION}
  Python:   ${PYTHON_VERSION}

Uruchom nową sesję powłoki albo wykonaj:

  source ~/.bashrc

Następnie uruchom:

  lvim

Przydatne polecenia w LunarVim:

  :checkhealth
  :checkhealth provider
  :Mason

Jeżeli codelldb nie zostanie zainstalowany automatycznie:

  :MasonInstall codelldb

EOF
