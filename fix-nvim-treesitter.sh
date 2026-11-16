#!/usr/bin/env bash
set -euo pipefail

TS_DIR="$HOME/.local/share/lunarvim/site/pack/lazy/opt/nvim-treesitter"
BACKUP_DIR="$HOME/lvim-treesitter-backup-$(date +%F-%H%M%S)"

log() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

die() {
  printf '\n\033[1;31mBŁĄD: %s\033[0m\n' "$*" >&2
  exit 1
}

command -v git >/dev/null || die "Brak git"
command -v lvim >/dev/null || die "Brak lvim w PATH"

[[ -d "$TS_DIR/.git" ]] || die "Nie znaleziono repozytorium nvim-treesitter w:\n$TS_DIR"

log "Kopia zapasowa aktualnego stanu nvim-treesitter"
mkdir -p "$BACKUP_DIR"
cp -a "$TS_DIR" "$BACKUP_DIR/nvim-treesitter"

log "Stan przed naprawą"
cd "$TS_DIR"
git status --short --branch || true
git log -1 --oneline || true
git remote -v || true

log "Pobieranie aktualnych referencji"
git fetch origin --prune

if git rev-parse --verify origin/main >/dev/null 2>&1; then
  log "Przełączanie nvim-treesitter na origin/main"
  if git show-ref --verify --quiet refs/heads/main; then
    git switch main
    git reset --hard origin/main
  else
    git switch -c main origin/main
  fi
else
  die "Zdalne repozytorium nie zawiera gałęzi origin/main"
fi

log "Aktualny commit nvim-treesitter"
git log -1 --oneline
git branch --show-current || true

log "Sprawdzanie, czy LunarVim gdzieś wymusza gałąź master"
grep -RIn --include='*.lua' -E 'nvim-treesitter/nvim-treesitter|branch *= *"master"' \
  "$HOME/.config/lvim" \
  "$HOME/.local/share/lunarvim/lvim/lua" 2>/dev/null || true

log "Aktualizacja pluginu przez lazy.nvim"
lvim --headless \
  "+Lazy! update nvim-treesitter" \
  "+qa" || true

log "Usuwanie parserów zbudowanych przez starą gałąź master"
lvim --headless \
  "+TSUninstall all" \
  "+qa" || true

log "Instalacja parserów: c, cpp, lua, vim, vimdoc"
lvim --headless \
  "+TSInstall c cpp lua vim vimdoc" \
  "+qa" || true

log "Aktualizacja parserów"
lvim --headless \
  "+TSUpdate" \
  "+qa" || true

log "Diagnostyka nvim-treesitter"
lvim --headless \
  "+checkhealth nvim-treesitter" \
  "+qa" || true

log "Gotowe"
cat <<EOF

Wykonano:
- kopia zapasowa: $BACKUP_DIR/nvim-treesitter
- nvim-treesitter przełączony na main
- aktualizacja przez lazy.nvim
- reinstall parserów: c, cpp, lua, vim, vimdoc

Teraz uruchom:
  lvim

Następnie otwórz plik C++ i sprawdź:
  :messages
  :checkhealth nvim-treesitter

Jeżeli błąd query_predicates.lua:139 nadal występuje, prześlij wynik:
  cd $TS_DIR && git branch --show-current && git log -1 --oneline
  grep -RIn --include='*.lua' -E 'nvim-treesitter|branch *= *"master"' \
    ~/.config/lvim ~/.local/share/lunarvim/lvim/lua
EOF
