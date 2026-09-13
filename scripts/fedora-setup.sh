#!/usr/bin/env bash
# Sets up a fresh Fedora container the way spirit uses it. Run it INSIDE the container:
#
#   proot-distro install fedora
#   proot-distro login fedora
#   curl -fsSL https://raw.githubusercontent.com/beqa-beridze/spirit/main/scripts/fedora-setup.sh | bash
#
# It installs the base tools, starship, and Claude Code, and writes the prompt config.
# It does not log Claude in, that part needs a browser and you do it yourself afterwards.
# Safe to re-run: every step checks first.
set -euo pipefail

say() { printf '\n== %s\n' "$*"; }

[ -f /etc/fedora-release ] || { echo "this is meant to run inside the Fedora container"; exit 1; }

say "base packages"
PKGS="zsh tmux git curl python3 nodejs npm fastfetch openssh-clients unzip"
MISSING=""
for p in $PKGS; do rpm -q "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"; done
if [ -n "$MISSING" ]; then dnf -y install $MISSING; else echo "already there"; fi

say "starship"
if ! command -v starship >/dev/null 2>&1; then
  curl -fsSL https://starship.rs/install.sh | sh -s -- -y
else
  echo "already there"
fi

say "claude code"
if [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
else
  echo "already there"
fi

say "prompt"
mkdir -p "$HOME/.config"
if [ ! -f "$HOME/.config/starship.toml" ]; then
  cat > "$HOME/.config/starship.toml" <<'TOML'
add_newline = true
format = "[spirit ](bold #a07be0)$directory$git_branch$git_status$python$nodejs$cmd_duration$line_break$character"

[character]
success_symbol = "[❯](bold #f0b429)"
error_symbol = "[❯](bold #e25822)"

[directory]
style = "bold #6db8e8"
truncation_length = 3
truncation_symbol = "…/"

[git_branch]
style = "bold #a8c878"
TOML
fi

# proot-distro login reads the login shell out of the container's /etc/passwd,
# so chsh is the right way to do this and it sticks.
if command -v zsh >/dev/null 2>&1 && [ "$(getent passwd root | cut -d: -f7)" != "$(command -v zsh)" ]; then
  chsh -s "$(command -v zsh)" root || true
fi
grep -q 'HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
grep -q 'starship init zsh' "$HOME/.zshrc" 2>/dev/null || cat >> "$HOME/.zshrc" <<'RC'
export PATH="$HOME/.local/bin:$PATH"
eval "$(starship init zsh)"
RC

say "done"
echo "claude:   $("$HOME/.local/bin/claude" --version 2>/dev/null || echo 'not installed')"
echo "starship: $(starship --version 2>/dev/null | head -1 || echo 'not installed')"
echo
echo "Next: run 'claude', open the URL it prints on the phone, paste the code back."
