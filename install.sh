#!/usr/bin/env bash
set -Eeuo pipefail

# LazyVim + CodeCompanion installer dla Debian/Ubuntu.
#
# Instaluje:
#   - Neovim 0.12.6
#   - LazyVim starter
#   - codecompanion.nvim z adapterem Groq
#   - Python/Node/Ruby provider, Rust, narzędzia C/C++
#   - Hack Nerd Font
#
# Uruchomienie:
#   GROQ_API_KEY="gsk_..." bash ./install.sh
#
# Zmiana modelu:
#   GROQ_MODEL="openai/gpt-oss-20b" bash ./install.sh

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

NVIM_VERSION="${NVIM_VERSION:-0.12.6}"
PYTHON_MINOR="${PYTHON_MINOR:-3.13}"
INSTALL_FONTS="${INSTALL_FONTS:-1}"
GROQ_MODEL="${GROQ_MODEL:-openai/gpt-oss-120b}"

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

info() { log "$BLUE" INFO "$1"; }
ok() { log "$GREEN" SUCCESS "$1"; }
warn() { log "$YELLOW" WARNING "$1"; }

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
  radare2 \
  nasm

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
"$PYTHON_BIN" -m pip install cmake-language-server

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
if [[ -f "$HOME/.npmrc" ]]; then
  sed -i -E '/^[[:space:]]*(prefix|globalconfig)[[:space:]]*=/d' "$HOME/.npmrc"
fi

unset npm_config_prefix NPM_CONFIG_PREFIX

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

info "Instalowanie najnowszego wydania LTS Node.js..."
nvm install --lts >/dev/null
nvm alias default 'lts/*' >/dev/null

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
# STEP 6: Neovim 0.12
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

NVIM_TAG="v${NVIM_VERSION#v}"

if [[ ! "$NVIM_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fatal "Nieprawidłowa wersja Neovim: $NVIM_TAG"
fi

info "Instalowanie Neovim $NVIM_TAG..."

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ARCHIVE="nvim-linux-${NVIM_ARCH}.tar.gz"

curl -fL \
  --retry 3 \
  -o "$TMP_DIR/$ARCHIVE" \
  "https://github.com/neovim/neovim/releases/download/${NVIM_TAG}/${ARCHIVE}"

mkdir -p "$TMP_DIR/extract"
tar -C "$TMP_DIR/extract" -xzf "$TMP_DIR/$ARCHIVE"

EXTRACTED_DIR="$(find "$TMP_DIR/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)"

[[ -d "$EXTRACTED_DIR/bin" ]] ||
  fatal "Nieoczekiwana zawartość archiwum Neovim."

sudo rm -rf "/opt/nvim-0.12"
sudo mv "$EXTRACTED_DIR" "/opt/nvim-0.12"
sudo ln -sfn "/opt/nvim-0.12/bin/nvim" "/usr/local/bin/nvim"

hash -r

if ! command -v nvim >/dev/null 2>&1; then
  fatal "Nie znaleziono polecenia nvim po instalacji."
fi

NVIM_VERSION_LINE="$(nvim --version | sed -n '1p')"

if [[ "$NVIM_VERSION_LINE" != *"$NVIM_TAG"* ]]; then
  fatal "Nieprawidłowa wersja Neovim w PATH: $NVIM_VERSION_LINE (oczekiwano $NVIM_TAG)"
fi

ok "Zainstalowano: $NVIM_VERSION_LINE"

###############################################################################
# STEP 7: LazyVim
###############################################################################

STAMP="$(date +%Y%m%d%H%M%S)"

if [[ -d "$HOME/.config/nvim" ]]; then
  BACKUP="$HOME/.config/nvim.bak.$STAMP"
  info "Backup istniejącej konfiguracji Neovim: $BACKUP"
  mv "$HOME/.config/nvim" "$BACKUP"
fi

for dir in \
  "$HOME/.local/share/nvim" \
  "$HOME/.local/state/nvim" \
  "$HOME/.cache/nvim"; do
  if [[ -d "$dir" ]]; then
    mv "$dir" "${dir}.bak.$STAMP"
  fi
done

info "Instalowanie LazyVim starter..."

git clone --depth 1 \
  https://github.com/LazyVim/starter "$HOME/.config/nvim"

rm -rf "$HOME/.config/nvim/.git"

ok "LazyVim starter zainstalowany."

###############################################################################
# STEP 8: CodeCompanion + Groq
###############################################################################

PLUGIN_DIR="$HOME/.config/nvim/lua/plugins"
mkdir -p "$PLUGIN_DIR"

cat > "$PLUGIN_DIR/codecompanion.lua" <<LUA
return {
  {
    "olimorris/codecompanion.nvim",
    version = "^19.0.0",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = {
      "CodeCompanion",
      "CodeCompanionChat",
      "CodeCompanionActions",
      "CodeCompanionCmd",
    },
    opts = {
      adapters = {
        groq = function()
          return require("codecompanion.adapters").extend("openai_compatible", {
            name = "groq",
            formatted_name = "Groq",
            env = {
              api_key = "GROQ_API_KEY",
            },
            url = "https://api.groq.com/openai",
            chat_url = "/v1/chat/completions",
            schema = {
              model = {
                default = "${GROQ_MODEL}",
              },
            },
          })
        end,
      },

      interactions = {
        chat = {
          adapter = "groq",
        },
        inline = {
          adapter = "groq",
        },
        agent = {
          adapter = "groq",
        },
      },
    },
  },
}
LUA

ok "Konfiguracja CodeCompanion zapisana w $PLUGIN_DIR/codecompanion.lua."

###############################################################################
# STEP 9: C/C++ DAP - codelldb
###############################################################################

cat > "$PLUGIN_DIR/dap-codelldb.lua" <<'LUA'
return {
  {
    "mfussenegger/nvim-dap",
    event = "VeryLazy",
    config = function()
      local dap = require("dap")

      local ok_mason, registry = pcall(require, "mason-registry")
      if not ok_mason then
        vim.notify("Mason nie jest dostępny.", vim.log.levels.WARN)
        return
      end

      local ok_package, package = pcall(registry.get_package, "codelldb")
      if not ok_package or not package:is_installed() then
        vim.notify(
          "codelldb nie jest zainstalowany. Uruchom :MasonInstall codelldb",
          vim.log.levels.WARN
        )
        return
      end

      local extension = package:get_install_path() .. "/extension/"
      local adapter = extension .. "adapter/codelldb"

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = adapter,
          args = {
            "--port",
            "${port}",
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
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      }

      dap.configurations.cpp = { cpp_config }
      dap.configurations.c = { cpp_config }
    end,
  },
}
LUA

ok "Konfiguracja C/C++ DAP zapisana."

###############################################################################
# STEP 10: NASM and clipboard
###############################################################################

cat > "$PLUGIN_DIR/editor.lua" <<'LUA'
return {
  {
    "LazyVim/LazyVim",
    opts = {
      options = {
        g = {
          asmsyntax = "nasm",
        },
      },
    },
  },

  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>a", group = "AI (Groq)" },
        { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle chat" },
        { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "Actions" },
        { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "Inline prompt" },
      },
    },
  },
}
LUA

ok "Konfiguracja NASM i skrótów AI zapisana."

###############################################################################
# STEP 11: Nerd Font
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
# STEP 12: First LazyVim sync
###############################################################################

info "Pierwsze uruchomienie LazyVim i synchronizacja pluginów..."

nvim --headless "+Lazy! sync" +qa ||
  warn "Nie udało się zsynchronizować pluginów; uruchom :Lazy sync w nvim."

ok "Pluginy LazyVim zainstalowane."

###############################################################################
# STEP 13: Summary
###############################################################################

if [[ -z "${GROQ_API_KEY:-}" ]]; then
  warn "Zmienna GROQ_API_KEY nie jest ustawiona - integracja Groq nie zadziała."
  warn 'Dodaj do ~/.bashrc: export GROQ_API_KEY="gsk_..."'
fi

cat <<EOF

Instalacja zakończona.

  Neovim:   $NVIM_VERSION_LINE
  Edytor:   LazyVim
  AI:       CodeCompanion + Groq
  Model:    $GROQ_MODEL

Uruchom nową sesję powłoki albo wykonaj:

  source ~/.bashrc

Następnie uruchom:

  nvim

Po pierwszym uruchomieniu zainstaluj debugger C/C++:

  :MasonInstall codelldb

Poczekaj na zakończenie instalacji, a następnie sprawdź:

  :checkhealth
  :checkhealth codecompanion

Przydatne polecenia:

  :Lazy
  :Mason

Groq w CodeCompanion:

  1. Utwórz klucz na https://console.groq.com/keys
  2. Dodaj do ~/.bashrc:
       export GROQ_API_KEY="gsk_..."
  3. W Neovim:
       :CodeCompanionChat

Skróty:

  <Space>ac  przełącz czat
  <Space>aa  akcje
  <Space>ai  prompt inline
  <Space>as  (tryb visual) wyślij zaznaczenie

Model zmienisz przez:

  GROQ_MODEL="openai/gpt-oss-20b" bash ./install.sh
EOF
