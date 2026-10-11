#!/usr/bin/env bash
set -Eeuo pipefail

# LunarVim 1.4 installer for Debian/Ubuntu.
#
# Domyślnie instaluje Neovim 0.10.4 - najnowszą wersję, z którą LunarVim
# działa bez błędów (nvim-treesitter w LunarVim jest przypięty do starego
# commita, który nie działa z Neovim 0.11+).
#
# Przykłady:
#   bash ./lvim_setup_new.sh                        # Neovim 0.10.4 + LunarVim master
#   NVIM_VERSION=0.9.5 bash ./lvim_setup_new.sh     # oficjalnie wspierane przez LunarVim 1.4
#   NVIM_VERSION=latest bash ./lvim_setup_new.sh    # najnowszy Neovim (mogą być błędy pluginów!)
#   NVIM_VERSION=nightly bash ./lvim_setup_new.sh   # build nightly (jw.)
#
# LV_BRANCH (opcjonalnie): jeśli nie podano, wybierane automatycznie:
#   Neovim 0.9.x -> release-1.4/neovim-0.9, w pozostałych przypadkach -> master

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

LV_BRANCH="${LV_BRANCH:-}"
NVIM_VERSION="${NVIM_VERSION:-0.10.4}"
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
    wl-clipboard \
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
    lldb \
    rr \
    radare2
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

# nvm jest niezgodny z ustawieniami prefix/globalconfig w ~/.npmrc
# (poprzednie wersje tego skryptu ustawiały prefix, co psuje nvm).
if [[ -f "$HOME/.npmrc" ]]; then
    sed -i -E '/^[[:space:]]*(prefix|globalconfig)[[:space:]]*=/d' "$HOME/.npmrc"
fi

unset npm_config_prefix NPM_CONFIG_PREFIX

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

info "Instalowanie najnowszego wydania LTS Node.js..."

nvm install --lts >/dev/null
nvm alias default 'lts/*' >/dev/null

# Uwaga: nie ustawiamy "npm config set prefix" - nvm instaluje pakiety globalne
# w katalogu użytkownika, więc nie ma problemów z uprawnieniami.

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
        NVIM_ARCH="x86_64"
        ;;

    aarch64|arm64)
        NVIM_ARCH="arm64"
        ;;

    *)
        fatal "Nieobsługiwana architektura: $(uname -m)"
        ;;
esac

resolve_nvim_tag() {
    local requested="$1"
    local url

    case "$requested" in
        latest)
            # /releases/latest przekierowuje na tag najnowszego stabilnego wydania.
            url="$(
                curl -fsSL \
                    --retry 3 \
                    -o /dev/null \
                    -w '%{url_effective}' \
                    https://github.com/neovim/neovim/releases/latest
            )"
            printf '%s\n' "${url##*/}"
            ;;

        nightly)
            printf 'nightly\n'
            ;;

        *)
            printf 'v%s\n' "${requested#v}"
            ;;
    esac
}

info "Ustalanie wersji Neovim (${NVIM_VERSION})..."

NVIM_TAG="$(resolve_nvim_tag "$NVIM_VERSION")"

if [[ ! "$NVIM_TAG" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+|nightly)$ ]]; then
    fatal "Nieprawidłowa wersja Neovim: ${NVIM_TAG}"
fi

info "Instalowanie Neovim ${NVIM_TAG}..."

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# Nazwy archiwów zmieniały się między wydaniami:
#   nowe:   nvim-linux-x86_64.tar.gz / nvim-linux-arm64.tar.gz
#   starsze: nvim-linux64.tar.gz (tylko x86_64)
ARCHIVE_CANDIDATES=("nvim-linux-${NVIM_ARCH}.tar.gz")

if [[ "$NVIM_ARCH" == "x86_64" ]]; then
    ARCHIVE_CANDIDATES+=("nvim-linux64.tar.gz")
fi

NVIM_ARCHIVE=""

for candidate in "${ARCHIVE_CANDIDATES[@]}"; do
    if curl \
        -fL \
        --retry 3 \
        -o "$TMP_DIR/$candidate" \
        "https://github.com/neovim/neovim/releases/download/${NVIM_TAG}/${candidate}"; then
        NVIM_ARCHIVE="$candidate"
        break
    fi

    warn "Brak archiwum ${candidate} dla ${NVIM_TAG}, próbuję następny wariant..."
done

[[ -n "$NVIM_ARCHIVE" ]] ||
    fatal "Nie udało się pobrać Neovim ${NVIM_TAG} dla architektury $(uname -m)."

mkdir -p "$TMP_DIR/extract"

tar \
    -C "$TMP_DIR/extract" \
    -xzf "$TMP_DIR/$NVIM_ARCHIVE"

# Nazwa katalogu w archiwum zależy od wydania, więc wykrywamy ją automatycznie.
EXTRACTED=("$TMP_DIR"/extract/*/)
NVIM_DIR="$(basename "${EXTRACTED[0]}")"

[[ -d "$TMP_DIR/extract/$NVIM_DIR/bin" ]] ||
    fatal "Nieoczekiwana zawartość archiwum Neovim."

sudo rm -rf "/opt/$NVIM_DIR"
sudo mv "$TMP_DIR/extract/$NVIM_DIR" "/opt/$NVIM_DIR"

sudo ln -sfn \
    "/opt/$NVIM_DIR/bin/nvim" \
    /usr/local/bin/nvim

hash -r

if ! command -v nvim >/dev/null 2>&1; then
    fatal "Nie znaleziono polecenia nvim po instalacji."
fi

NVIM_VERSION_LINE="$(nvim --version | sed -n '1p')"

if [[ "$NVIM_TAG" != "nightly" && "$NVIM_VERSION_LINE" != *"${NVIM_TAG}"* ]]; then
    fatal "Nieprawidłowa wersja Neovim w PATH: ${NVIM_VERSION_LINE} (oczekiwano ${NVIM_TAG})."
fi

ok "Zainstalowano: ${NVIM_VERSION_LINE}"

# Wybór gałęzi LunarVim dopasowanej do Neovim.
if [[ -z "$LV_BRANCH" ]]; then
    case "$NVIM_TAG" in
        v0.9.*)
            LV_BRANCH="release-1.4/neovim-0.9"
            ;;
        *)
            LV_BRANCH="master"
            ;;
    esac
fi

case "$NVIM_TAG" in
    v0.9.*|v0.10.*)
        ;;
    *)
        warn "Neovim ${NVIM_TAG} jest nowszy niż 0.10 - LunarVim z nim nie działa poprawnie."
        warn "Typowy objaw: błędy nvim-treesitter (query_predicates.lua ... 'type' (a nil value))."
        warn "Jeśli je zobaczysz, uruchom ponownie z NVIM_VERSION=0.10.4."
        ;;
esac

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
# STEP 7b: Claude Code CLI
###############################################################################

info "Instalowanie Claude Code CLI..."

export PATH="$HOME/.local/bin:$PATH"

if command -v claude >/dev/null 2>&1; then
    ok "Claude Code jest już zainstalowany: $(claude --version 2>/dev/null || echo 'nieznana wersja')"
else
    # Natywny instalator (zalecany): nie wymaga Node.js, instaluje do ~/.local/bin/claude
    curl -fsSL https://claude.ai/install.sh | bash

    hash -r

    if ! command -v claude >/dev/null 2>&1; then
        fatal "Instalator nie utworzył polecenia claude (oczekiwano ~/.local/bin/claude)."
    fi

    ok "Claude Code zainstalowany: $(claude --version 2>/dev/null || echo 'nieznana wersja')"
fi

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

-- Python provider (interpreter installed by pyenv).
vim.g.python3_host_prog = "${PYTHON_PATH_LUA}"

-- Perl provider is not required.
vim.g.loaded_perl_provider = 0

-- Enable DAP.
lvim.builtin.dap.active = true

-- Install codelldb through Mason.
lvim.builtin.mason.ensure_installed = {
  "codelldb",
}

-- Configure C/C++ debugging after LunarVim has initialized DAP.
lvim.builtin.dap.on_config_done = function(dap)
  local registry = require("mason-registry")
  local package = registry.get_package("codelldb")

  if not package:is_installed() then
    vim.notify(
      "codelldb is not installed. Run :MasonInstall codelldb and retry.",
      vim.log.levels.ERROR
    )
    return
  end

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

  local cpp_config = {
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
  }

  dap.configurations.cpp = { cpp_config }
  dap.configurations.c = { cpp_config }
end

-- DAP key mappings.
lvim.keys.normal_mode["<F5>"] = "<cmd>lua require('dap').continue()<CR>"
lvim.keys.normal_mode["<F6>"] = "<cmd>lua require('dap').terminate()<CR>"
lvim.keys.normal_mode["<F10>"] = "<cmd>lua require('dap').step_over()<CR>"
lvim.keys.normal_mode["<F11>"] = "<cmd>lua require('dap').step_into()<CR>"
lvim.keys.normal_mode["<F12>"] = "<cmd>lua require('dap').step_out()<CR>"
lvim.keys.normal_mode["<leader>b"] = "<cmd>lua require('dap').toggle_breakpoint()<CR>"
lvim.keys.normal_mode["<leader>B"] = "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>"
lvim.keys.normal_mode["<leader>dh"] = "<cmd>lua require('dap.ui.widgets').hover()<CR>"

-- Claude Code integration (coder/claudecode.nvim)
-- Używa wbudowanego terminala Neovim ("native"), więc nie wymaga snacks.nvim.
local claude_bin = vim.fn.expand("~/.local/bin/claude")

lvim.plugins = vim.list_extend(lvim.plugins or {}, {
  {
    "coder/claudecode.nvim",
    cmd = {
      "ClaudeCode",
      "ClaudeCodeFocus",
      "ClaudeCodeSelectModel",
      "ClaudeCodeAdd",
      "ClaudeCodeSend",
      "ClaudeCodeTreeAdd",
      "ClaudeCodeStatus",
      "ClaudeCodeStart",
      "ClaudeCodeStop",
      "ClaudeCodeOpen",
      "ClaudeCodeClose",
      "ClaudeCodeDiffAccept",
      "ClaudeCodeDiffDeny",
      "ClaudeCodeCloseAllDiffs",
    },
    opts = {
      -- Pełna ścieżka, żeby działało także gdy PATH w lvim nie zawiera ~/.local/bin.
      terminal_cmd = vim.fn.executable(claude_bin) == 1 and claude_bin or nil,
      terminal = {
        provider = "native",
        split_side = "right",
        split_width_percentage = 0.35,
      },
    },
    config = true,
  },
})

-- Klawisze: <leader>a (Space a) = Claude Code
lvim.builtin.which_key.mappings["a"] = {
  name = "Claude Code",
  c = { "<cmd>ClaudeCode<cr>", "Toggle Claude" },
  f = { "<cmd>ClaudeCodeFocus<cr>", "Focus Claude" },
  r = { "<cmd>ClaudeCode --resume<cr>", "Resume session" },
  C = { "<cmd>ClaudeCode --continue<cr>", "Continue session" },
  m = { "<cmd>ClaudeCodeSelectModel<cr>", "Select model" },
  b = { "<cmd>ClaudeCodeAdd %<cr>", "Add current buffer" },
  a = { "<cmd>ClaudeCodeDiffAccept<cr>", "Accept diff" },
  d = { "<cmd>ClaudeCodeDiffDeny<cr>", "Deny diff" },
  s = { "<cmd>ClaudeCodeStatus<cr>", "Status" },
}

lvim.builtin.which_key.vmappings["a"] = {
  name = "Claude Code",
  s = { "<cmd>ClaudeCodeSend<cr>", "Send selection to Claude" },
}

-- Schowek systemowy.
-- Na maszynie bez środowiska graficznego (SSH, serwer, kontener) kopiowanie
-- działa przez sekwencję OSC 52, którą przekazuje terminal użytkownika.
-- Wymaga Neovim >= 0.10 oraz terminala obsługującego OSC 52
-- (Windows Terminal, kitty, WezTerm, iTerm2, Alacritty).
local function has_value(v)
  return v ~= nil and v ~= ""
end

local has_display = has_value(vim.env.DISPLAY) or has_value(vim.env.WAYLAND_DISPLAY)
local use_osc52 = (has_value(vim.env.SSH_TTY) or not has_display)
  and vim.fn.has("wsl") == 0
  and vim.fn.has("nvim-0.10") == 1

if use_osc52 then
  local osc52 = require("vim.ui.clipboard.osc52")

  local function paste_from_register()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end

  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    paste = {
      ["+"] = paste_from_register,
      ["*"] = paste_from_register,
    },
  }
end

-- END managed installer config
LUA

ok "Konfiguracja LunarVim zapisana w $CONFIG_FILE."

# tmux: przekazuj schowek (OSC 52) do terminala użytkownika.
append_once 'set -g set-clipboard on' "$HOME/.tmux.conf"

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

info "Instalowanie pluginów użytkownika (claudecode.nvim)..."

"$HOME/.local/bin/lvim" \
    --headless \
    '+Lazy! sync' \
    +qa ||
    warn "Nie udało się zsynchronizować pluginów użytkownika; uruchom :Lazy sync w lvim."

ok "Pluginy użytkownika zainstalowane."

###############################################################################
# Summary
###############################################################################

cat <<EOF

Instalacja zakończona.

  LunarVim: ${LV_BRANCH}
  Neovim:   ${NVIM_TAG}
  Python:   ${PYTHON_VERSION}

Uruchom nową sesję powłoki albo wykonaj:

  source ~/.bashrc

Następnie uruchom:

  lvim

Przydatne polecenia w LunarVim:

  :checkhealth
  :checkhealth provider
  :Mason

Claude Code w LunarVim:

  1. W terminalu uruchom raz:  claude   (zaloguj się kontem Claude lub kluczem API)
  2. W lvim:  :ClaudeCode  lub  <Space>ac
  3. Diagnostyka:  :checkhealth claudecode

  <Space>ac  przełącz Claude        <Space>af  fokus
  <Space>ar  wznów sesję            <Space>aC  kontynuuj sesję
  <Space>ab  dodaj bieżący bufor    <Space>as  (tryb visual) wyślij zaznaczenie
  <Space>aa  akceptuj diff          <Space>ad  odrzuć diff

Jeżeli codelldb nie zostanie zainstalowany automatycznie:

  :MasonInstall codelldb

EOF
