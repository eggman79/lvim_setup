#!/usr/bin/env bash
# setup-nvim.sh
# Neovim 0.12.x + LunarVim + providery (Python/pyenv, Node/nvm, Ruby) + Rust
# Ubuntu 26.04 (x86_64 / aarch64)
#
# Użycie:
#   ./setup-nvim.sh                    instalacja / aktualizacja (idempotentna)
#   ./setup-nvim.sh --force-reinstall  backup starych configów i czysta instalacja
#   ./setup-nvim.sh --skip-apt         pomiń apt
#   ./setup-nvim.sh --no-rust          pomiń Rust
#   ./setup-nvim.sh --no-ruby          pomiń provider Ruby
#   ./setup-nvim.sh --no-ai            pomiń CodeCompanion + Groq
#
# Zmienne środowiskowe (opcjonalne):
#   NVIM_SERIES=0.12      seria Neovima; bierze najnowszy tag v0.12.x z GitHuba
#   NVIM_VERSION=v0.12.6  wymusza konkretny tag (nadpisuje NVIM_SERIES)
#   PY_SERIES=3.13        seria Pythona (najnowszy patch z pyenv)
#   PY_OPTIMIZE=0         1 = Python z --enable-optimizations --with-lto
#   NVM_VERSION=0.40.3    wersja instalatora nvm
#   LV_BRANCH=master      branch LunarVima
#   TS_COMPAT=1           0 = bez shimu/obejść nvim-treesitter w config.lua
#   GROQ_API_KEY=...      klucz Groq; czytany przez CodeCompanion z env w runtime
#                         (skrypt go NIE zapisuje — dodaj export do ~/.bashrc)

set -Eeuo pipefail

# ------------------------------------------------------------------ config
NVIM_SERIES="${NVIM_SERIES:-0.12}"
NVIM_VERSION="${NVIM_VERSION:-}"
PY_SERIES="${PY_SERIES:-3.13}"
PY_OPTIMIZE="${PY_OPTIMIZE:-0}"
NVM_VERSION="${NVM_VERSION:-0.40.3}"
LV_BRANCH="${LV_BRANCH:-master}"
TS_COMPAT="${TS_COMPAT:-1}"

FORCE=0
SKIP_APT=0
INSTALL_RUST=1
INSTALL_RUBY=1
INSTALL_AI=1

OPT_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"
VENV_DIR="$HOME/.local/share/nvim-python/venv"
LVIM_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lvim"
LVIM_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lunarvim"
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
TS="$(date +%Y%m%d%H%M%S)"

# ----------------------------------------------------------------- logging
_log()  { printf '[%s] %s - %s\n' "$(date '+%F %T')" "$1" "$2"; }
info()  { _log INFO "$*"; }
ok()    { _log SUCCESS "$*"; }
warn()  { _log WARN "$*" >&2; }
err()   { _log ERROR "$*" >&2; }
die()   { err "$*"; exit 1; }
trap 'err "Błąd w linii $LINENO (kod $?). Przerwano."' ERR

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

for arg in "$@"; do
  case "$arg" in
    --force-reinstall) FORCE=1 ;;
    --skip-apt)        SKIP_APT=1 ;;
    --no-rust)         INSTALL_RUST=0 ;;
    --no-ruby)         INSTALL_RUBY=0 ;;
    --no-ai)           INSTALL_AI=0 ;;
    -h|--help)         usage; exit 0 ;;
    *) die "Nieznana opcja: $arg (użyj --help)" ;;
  esac
done

# Wstawia/podmienia blok między znacznikami (idempotentnie).
# upsert_block <plik> <prefiks komentarza> <tag> <treść>
upsert_block() {
  local file="$1" cmt="$2" tag="$3" content="$4"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  sed -i "\|^${cmt} >>> ${tag} >>>\$|,\|^${cmt} <<< ${tag} <<<\$|d" "$file"
  {
    printf '%s >>> %s >>>\n' "$cmt" "$tag"
    printf '%s\n' "$content"
    printf '%s <<< %s <<<\n' "$cmt" "$tag"
  } >>"$file"
}

backup_path() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    info "Backing up: $p -> $p.bak.$TS"
    mv "$p" "$p.bak.$TS"
  fi
}

# nvm nie lubi `set -eu`
nvm_do() { set +eu; nvm "$@"; local rc=$?; set -eu; return $rc; }
load_nvm() {
  [[ -s "$NVM_DIR/nvm.sh" ]] || return 1
  set +eu
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  set -eu
}

# --------------------------------------------------------------- 0. sanity
[[ $EUID -ne 0 ]] || die "Nie uruchamiaj jako root (skrypt sam użyje sudo do apt)."

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "26.04" ]]; then
    warn "Wykryto ${PRETTY_NAME:-nieznany system}; skrypt celuje w Ubuntu 26.04 — kontynuuję."
  fi
fi

case "$(uname -m)" in
  x86_64)  NVIM_ASSET="nvim-linux-x86_64.tar.gz"; NVIM_ARCH="x86_64" ;;
  aarch64) NVIM_ASSET="nvim-linux-arm64.tar.gz";  NVIM_ARCH="arm64"  ;;
  *) die "Nieobsługiwana architektura: $(uname -m)" ;;
esac

mkdir -p "$OPT_DIR" "$BIN_DIR"
export PATH="$BIN_DIR:$HOME/.cargo/bin:$PATH"

# ------------------------------------------------- 1. force: backup + clean
if [[ "$FORCE" == "1" ]]; then
  info "Force reinstall requested."
  for p in \
    "$HOME/.config/nvim" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim" \
    "$LVIM_CFG_DIR" "$LVIM_DATA_DIR" "$HOME/.cache/lvim"; do
    backup_path "$p"
  done
  rm -f "$BIN_DIR/lvim" "$BIN_DIR/nvim"
  rm -rf "$OPT_DIR"/nvim-*
  ok "Previous Neovim/LunarVim installation cleaned and backed up."
fi

# ------------------------------------------------------------------ 2. apt
if [[ "$SKIP_APT" != "1" ]]; then
  info "Installing system dependencies..."
  sudo apt-get update -qq
  # UWAGA: celowo bez cargo/rustc z apt (Rust idzie przez rustup — bez podwójnej instalacji)
  PKGS=(
    build-essential git curl wget ca-certificates unzip xz-utils pkg-config make gcc g++
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev
    tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev libzstd-dev uuid-dev
    libgdbm-dev libgdbm-compat-dev
    ripgrep fd-find xclip wl-clipboard
  )
  [[ "$INSTALL_RUBY" == "1" ]] && PKGS+=(ruby ruby-dev)
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}" >/dev/null
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" "$BIN_DIR/fd"
  fi
  ok "System dependencies installed."
else
  info "Skipping apt (--skip-apt)."
fi

# --------------------------------------------------------- 3. Python/pyenv
if [[ ! -d "$PYENV_ROOT" ]]; then
  info "Installing pyenv..."
  curl -fsSL https://pyenv.run | bash
elif [[ -d "$PYENV_ROOT/.git" ]]; then
  git -C "$PYENV_ROOT" pull --ff-only -q || warn "pyenv: pull nie powiódł się, lecę dalej."
fi
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"

info "Looking for the latest Python ${PY_SERIES}.x release..."
PY_FULL="$(pyenv latest -k "$PY_SERIES" 2>/dev/null || true)"
if [[ -z "$PY_FULL" ]]; then
  pyenv update >/dev/null 2>&1 || git -C "$PYENV_ROOT" pull --ff-only -q || true
  PY_FULL="$(pyenv latest -k "$PY_SERIES" 2>/dev/null || true)"
fi
[[ -n "$PY_FULL" ]] || die "Nie znalazłem Pythona ${PY_SERIES}.x w pyenv (pyenv install -l)."

if [[ "$PY_OPTIMIZE" == "1" ]]; then
  export PYTHON_CONFIGURE_OPTS="--enable-optimizations --with-lto ${PYTHON_CONFIGURE_OPTS:-}"
fi
if [[ "$FORCE" == "1" ]]; then
  info "Force reinstalling Python ${PY_FULL}..."
  pyenv uninstall -f "$PY_FULL" 2>/dev/null || true
fi
MAKEFLAGS="-j$(nproc)" pyenv install -s "$PY_FULL"

PY_BIN="$(pyenv prefix "$PY_FULL")/bin/python"
mkdir -p "$(dirname "$VENV_DIR")"
"$PY_BIN" -m venv --clear "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip wheel
"$VENV_DIR/bin/python" -m pip install --upgrade pynvim cmake-language-server
ln -sf "$VENV_DIR/bin/cmake-language-server" "$BIN_DIR/cmake-language-server"
ok "Python ${PY_FULL} and pynvim provider are ready ($VENV_DIR)."

# ---------------------------------------------------------------- 4. Ruby
RUBY_GEM_BIN=""
if [[ "$INSTALL_RUBY" == "1" ]]; then
  info "Installing Ruby provider..."
  if command -v gem >/dev/null 2>&1; then
    gem install --user-install --no-document neovim
    RUBY_GEM_BIN="$(ruby -e 'print Gem.user_dir')/bin"
    export PATH="$RUBY_GEM_BIN:$PATH"
    ok "Ruby provider installed."
  else
    warn "Brak 'gem' — pomijam provider Ruby."
  fi
fi

# ------------------------------------------------------- 5. Node (nvm) + CLI
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  info "Installing nvm v${NVM_VERSION}..."
  PROFILE=/dev/null bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh")"
fi
load_nvm || die "Nie mogę załadować nvm ($NVM_DIR/nvm.sh)."

info "Installing Node.js LTS..."
nvm_do install --lts
nvm_do alias default 'lts/*' >/dev/null
nvm_do use default >/dev/null

info "Installing Node provider and tree-sitter-cli..."
npm install -g --allow-scripts=tree-sitter-cli neovim tree-sitter-cli
if ! tree-sitter --version >/dev/null 2>&1; then
  warn "tree-sitter-cli nie działa po instalacji — próbuję uruchomić jego install.js."
  ( cd "$(npm root -g)/tree-sitter-cli" && node install.js ) || true
fi
tree-sitter --version >/dev/null 2>&1 \
  && ok "Node.js $(node --version), Node provider and tree-sitter-cli $(tree-sitter --version | awk '{print $2}') are ready." \
  || warn "tree-sitter-cli nadal nie działa (nvim-treesitter na master zadziała i bez niego)."

# ---------------------------------------------------------------- 6. Rust
if [[ "$INSTALL_RUST" == "1" ]]; then
  if command -v rustup >/dev/null 2>&1; then
    info "rustup już jest — aktualizuję toolchain stable (bez kasowania Rusta)."
    rustup update stable
  else
    info "Installing Rust (rustup)..."
    # systemowy rustc z apt nie ma tu przeszkadzać
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
      | RUSTUP_INIT_SKIP_PATH_CHECK=yes sh -s -- -y --no-modify-path
  fi
  # shellcheck disable=SC1091
  [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
  ok "Rust is ready ($(rustc --version 2>/dev/null || echo '?'))."
fi

# -------------------------------------------------------------- 7. Neovim
if [[ -z "$NVIM_VERSION" ]]; then
  info "Resolving latest Neovim v${NVIM_SERIES}.x tag..."
  NVIM_VERSION="$(git ls-remote --tags --refs https://github.com/neovim/neovim.git "v${NVIM_SERIES}.*" \
    | sed 's|.*/||' | grep -E "^v${NVIM_SERIES//./\\.}\.[0-9]+$" | sort -V | tail -n1 || true)"
  [[ -n "$NVIM_VERSION" ]] || die "Nie znalazłem tagu v${NVIM_SERIES}.x (ustaw NVIM_VERSION=vX.Y.Z)."
fi

NVIM_DEST="$OPT_DIR/nvim-${NVIM_VERSION}-${NVIM_ARCH}"
NVIM_REAL="$NVIM_DEST/bin/nvim"
if [[ -x "$NVIM_REAL" ]]; then
  info "Neovim ${NVIM_VERSION} już jest w $NVIM_DEST."
else
  info "Installing Neovim ${NVIM_VERSION}..."
  tmp="$(mktemp -d)"
  base="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}"
  curl -fL --retry 3 -o "$tmp/$NVIM_ASSET" "$base/$NVIM_ASSET"
  if curl -fsSL --retry 3 -o "$tmp/shasum.txt" "$base/shasum.txt"; then
    ( cd "$tmp" && grep " ${NVIM_ASSET}\$" shasum.txt | sha256sum -c - >/dev/null )
    info "SHA-256 OK."
  else
    warn "Brak shasum.txt dla ${NVIM_VERSION} — pomijam weryfikację sumy."
  fi
  rm -rf "$NVIM_DEST"
  mkdir -p "$NVIM_DEST"
  tar -xzf "$tmp/$NVIM_ASSET" --strip-components=1 -C "$NVIM_DEST"
  rm -rf "$tmp"
fi

# 1) wersja zainstalowanego pliku (nie z PATH!)
REAL_VER="$("$NVIM_REAL" --version | head -n1 | awk '{print $2}')"
[[ "$REAL_VER" == "$NVIM_VERSION" ]] \
  || die "Zainstalowany plik $NVIM_REAL to $REAL_VER, oczekiwano $NVIM_VERSION."

# 2) symlink w ~/.local/bin (zawsze podmieniany, żeby nie został stary)
ln -sfn "$NVIM_REAL" "$BIN_DIR/nvim"
hash -r

# 3) czy PATH rozwiązuje się do naszego pliku? (lvim woła `nvim` z PATH)
RESOLVED="$(command -v nvim || true)"
if [[ "$(readlink -f "$RESOLVED")" != "$(readlink -f "$NVIM_REAL")" ]]; then
  err "W PATH wygrywa inny nvim: ${RESOLVED:-brak}"
  type -a nvim >&2 || true
  die "Usuń/wyprzedź tamten plik albo ustaw ~/.local/bin na początku PATH."
fi
ok "Neovim ${NVIM_VERSION} ready ($RESOLVED)."

# ------------------------------------------------------------- 8. LunarVim
if [[ -d "$LVIM_DATA_DIR" && -x "$BIN_DIR/lvim" ]]; then
  info "LunarVim już zainstalowany — pomijam instalator (użyj --force-reinstall)."
else
  info "Installing LunarVim (branch: ${LV_BRANCH})..."
  export LV_BRANCH
  installer_url="https://raw.githubusercontent.com/LunarVim/LunarVim/${LV_BRANCH}/utils/installer/install.sh"
  bash <(curl -fsSL "$installer_url") --no-install-dependencies \
    || warn "Instalator LunarVima zwrócił błąd (na nvim 0.12 możliwe ostrzeżenia w bootstrapie) — sprawdzam stan."
fi
[[ -x "$BIN_DIR/lvim" ]] || die "Brak $BIN_DIR/lvim — instalacja LunarVima się nie powiodła."
ok "LunarVim installed."

# ------------------------------------------------------ 9. config.lua blocks
info "Configuring ${LVIM_CFG_DIR}/config.lua..."
mkdir -p "$LVIM_CFG_DIR"
touch "$LVIM_CFG_DIR/config.lua"
upsert_block "$LVIM_CFG_DIR/config.lua" "--" "setup-nvim providers" \
"vim.g.python3_host_prog = \"$VENV_DIR/bin/python\"
vim.g.loaded_perl_provider = 0"

if [[ "$TS_COMPAT" == "1" ]]; then
  TS_SHIM="$(cat <<'LUA'
-- nvim-treesitter (branch master, zamrożony) vs Neovim 0.12:
-- handlery predykatów/dyrektyw dostają match[id] jako listę węzłów zamiast
-- pojedynczego węzła => "attempt to call method 'type' (a nil value)".
-- Shim opakowuje TYLKO handlery zarejestrowane z plików nvim-treesitter:
-- najpierw woła je z "rozpakowanym" match (ostatni węzeł z listy),
-- a gdy to rzuci błędem, wraca do oryginalnego match.
do
  local q = vim.treesitter.query

  local function from_nts(fn)
    local info = debug.getinfo(fn, "S")
    return info ~= nil and info.source ~= nil
      and info.source:find("nvim%-treesitter") ~= nil
  end

  local function unwrap(match)
    return setmetatable({}, {
      __index = function(_, k)
        local v = match[k]
        if type(v) == "table" then
          return v[#v]
        end
        return v
      end,
    })
  end

  local function wrap(handler)
    return function(match, pattern, source, pred, metadata)
      local ok, res = pcall(handler, unwrap(match), pattern, source, pred, metadata)
      if ok then
        return res
      end
      return handler(match, pattern, source, pred, metadata)
    end
  end

  for _, name in ipairs({ "add_predicate", "add_directive" }) do
    local orig = q[name]
    if type(orig) == "function" then
      q[name] = function(pname, handler, opts)
        local wants_list = type(opts) == "table" and opts.all == true
        if type(handler) == "function" and not wants_list and from_nts(handler) then
          handler = wrap(handler)
        end
        return orig(pname, handler, opts)
      end
    end
  end
end

-- wcięcia z treesittera + indent-blankline(use_treesitter) wywalały się na 0.12
if lvim.builtin.treesitter then
  lvim.builtin.treesitter.indent = { enable = false }
end
if lvim.builtin.indentlines and lvim.builtin.indentlines.options then
  lvim.builtin.indentlines.options.use_treesitter = false
end
LUA
)"
  upsert_block "$LVIM_CFG_DIR/config.lua" "--" "setup-nvim ts-compat" "$TS_SHIM"
else
  sed -i "\|^-- >>> setup-nvim ts-compat >>>\$|,\|^-- <<< setup-nvim ts-compat <<<\$|d" \
    "$LVIM_CFG_DIR/config.lua"
fi

# ------------------------------------------ 9b. CodeCompanion + Groq
if [[ "$INSTALL_AI" == "1" ]]; then
  info "Configuring CodeCompanion (Groq)..."
  AI_BLOCK="$(cat <<'LUA'
-- CodeCompanion + Groq (adapter openai_compatible).
-- Wymaga zmiennej środowiskowej GROQ_API_KEY (ustaw ją w ~/.bashrc, nie w repo).
-- Model domyślny możesz zmienić w czacie klawiszem `ga` (lista modeli z API).
lvim.plugins = lvim.plugins or {}
table.insert(lvim.plugins, {
  "olimorris/codecompanion.nvim",
  version = "^19.0.0",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
  config = function()
    require("codecompanion").setup({
      adapters = {
        http = {
          groq = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
              name = "groq",
              formatted_name = "Groq",
              env = {
                url = "https://api.groq.com/openai",
                api_key = "GROQ_API_KEY",
              },
              schema = {
                model = { default = "llama-3.3-70b-versatile" },
              },
            })
          end,
        },
      },
      interactions = {
        chat = { adapter = "groq" },
        inline = { adapter = "groq" },
      },
    })
  end,
})

-- parsery potrzebne do czatu (markdown w buforze czatu)
local ts = lvim.builtin.treesitter
if type(ts.ensure_installed) == "table" then
  vim.list_extend(ts.ensure_installed, { "markdown", "markdown_inline", "yaml" })
end

-- <leader>a...
lvim.builtin.which_key.mappings["a"] = {
  name = "AI (CodeCompanion)",
  c = { "<cmd>CodeCompanionChat Toggle<cr>", "Chat (toggle)" },
  a = { "<cmd>CodeCompanionActions<cr>", "Actions" },
  i = { "<cmd>CodeCompanion<cr>", "Inline prompt" },
}
lvim.builtin.which_key.vmappings["a"] = {
  name = "AI (CodeCompanion)",
  a = { "<cmd>CodeCompanionActions<cr>", "Actions" },
  i = { ":CodeCompanion<cr>", "Inline prompt (selection)" },
  c = { "<cmd>CodeCompanionChat Add<cr>", "Add selection to chat" },
}
LUA
)"
  upsert_block "$LVIM_CFG_DIR/config.lua" "--" "setup-nvim codecompanion" "$AI_BLOCK"
  ok "CodeCompanion block written (plugin pobierze lazy.nvim przy pierwszym starcie lvim)."
  [[ -n "${GROQ_API_KEY:-}" ]] \
    || warn "GROQ_API_KEY nie jest ustawiony w tej powłoce — dodaj export do ~/.bashrc."
else
  sed -i "\|^-- >>> setup-nvim codecompanion >>>\$|,\|^-- <<< setup-nvim codecompanion <<<\$|d" \
    "$LVIM_CFG_DIR/config.lua"
fi

# ------------------------------------------------------ 10. shell rc blocks
info "Updating shell rc files..."
RC_BLOCK="export PATH=\"\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH\""
[[ -n "$RUBY_GEM_BIN" ]] && RC_BLOCK+=$'\n'"export PATH=\"$RUBY_GEM_BIN:\$PATH\""
PYENV_BLOCK='export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - SHELLNAME)"'
NVM_BLOCK='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ "$rc" == "$HOME/.zshrc" && ! -f "$rc" ]] && continue
  sh_name="bash"; [[ "$rc" == *zshrc ]] && sh_name="zsh"
  upsert_block "$rc" "#" "setup-nvim path"  "$RC_BLOCK"
  upsert_block "$rc" "#" "setup-nvim pyenv" "${PYENV_BLOCK//SHELLNAME/$sh_name}"
  upsert_block "$rc" "#" "setup-nvim nvm"   "$NVM_BLOCK"
done
ok "Shell rc files updated."

# --------------------------------------------------------- 11. weryfikacja
info "Verification:"
printf '  nvim    : %s (%s)\n' "$(nvim --version | head -n1)" "$(command -v nvim)"
printf '  python  : %s (pyenv %s)\n' "$("$VENV_DIR/bin/python" --version)" "$PY_FULL"
printf '  pynvim  : %s\n' "$("$VENV_DIR/bin/python" -c 'import pynvim; print(pynvim.__version__)')"
printf '  node    : %s / npm %s\n' "$(node --version)" "$(npm --version)"
printf '  ts-cli  : %s\n' "$(tree-sitter --version 2>/dev/null || echo brak)"
printf '  rust    : %s\n' "$(rustc --version 2>/dev/null || echo brak)"
printf '  ruby    : %s\n' "$(ruby --version 2>/dev/null || echo brak)"
printf '  rg / fd : %s / %s\n' "$(command -v rg || echo brak)" "$(command -v fd || echo brak)"
printf '  lvim    : %s\n' "$(command -v lvim)"
printf '  groq key: %s\n' "$([[ -n "${GROQ_API_KEY:-}" ]] && echo ustawiony || echo 'brak (export GROQ_API_KEY=...)')"

lvim --headless "+lua io.write('  python3_host_prog = ' .. tostring(vim.g.python3_host_prog) .. '\n')" +qa 2>&1 \
  || warn "lvim --headless zwrócił błąd — odpal 'lvim' ręcznie i zobacz :messages / :checkhealth."

ok "Done."
cat <<EOF

Dalsze kroki:
  1. Otwórz nowy terminal (lub: source ~/.bashrc).
  2. Uruchom:  lvim   → poczekaj aż lazy.nvim doinstaluje pluginy.
  3. Sprawdź:  :checkhealth provider   :Lazy sync   :LvimInfo
  4. Przy błędzie treesittera wklej cały stack trace.

Gdyby LunarVim nie dał rady na 0.12:
  NVIM_SERIES=0.11 ./$(basename "$0") --force-reinstall
EOF
