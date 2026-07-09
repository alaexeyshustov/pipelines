#!/bin/bash
# Run as root inside the OrbStack isolated machine:
#   orb -m pipeline-sandbox -- sudo bash /work/sandbox/setup.sh
set -euo pipefail

# mise — system-wide binary
curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
echo 'eval "$(/usr/local/bin/mise activate zsh)"' >> /etc/zsh/zshrc
echo 'eval "$(/usr/local/bin/mise activate bash)"' >> /etc/bash.bashrc

# docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker

# gh cli
mkdir -p -m 755 /etc/apt/keyrings
wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
apt-get update && apt-get install -y gh

# Install tools and claude code for each user
for u in $(ls /home 2>/dev/null); do
  mkdir -p "/home/$u/.config/mise"
  cp /work/sandbox/mise.toml "/home/$u/.config/mise/config.toml"
  chown -R "$u:$u" "/home/$u/.config"
  sudo -u "$u" env HOME="/home/$u" /usr/local/bin/mise install
  git clone --depth 1 https://github.com/Shopify/rubydex.git "/home/$u/rubydex"
  chown -R "$u:$u" "/home/$u/rubydex"
  sudo -u "$u" env HOME="/home/$u" /usr/local/bin/mise exec -- \
    cargo install --path "/home/$u/rubydex/rust/rubydex-mcp"
  PNPM_HOME="/home/$u/.local/share/pnpm"
  sudo -u "$u" env HOME="/home/$u" PNPM_HOME="$PNPM_HOME" PATH="$PNPM_HOME:$PNPM_HOME/bin:$PATH" /usr/local/bin/mise exec -- pnpm add -g '@anthropic-ai/claude-code'
  usermod -aG docker "$u"
  chsh -s /usr/bin/zsh "$u" 2>/dev/null || true
  cat >> "/home/$u/.zshrc" << 'ZSHRC'
eval "$(/usr/local/bin/mise activate zsh)"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PNPM_HOME/bin:$PATH"
[ -f /work/.env.local ] && source /work/.env.local

# colors
export CLICOLOR=1
export LS_COLORS='di=1;34:ln=1;36:ex=1;32:*.rb=33:*.js=33:*.ts=33:*.json=36:*.yml=36:*.md=35'
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

PROMPT='%F{cyan}%n@%m%f %F{yellow}%~%f %(?..%F{red})%#%f '
RPROMPT='%F{240}%*%f'

HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS

cd /work 2>/dev/null || true
ZSHRC
  chown "$u:$u" "/home/$u/.zshrc"
done

echo "Sandbox setup complete. Connect with: orb -m pipeline-sandbox"
