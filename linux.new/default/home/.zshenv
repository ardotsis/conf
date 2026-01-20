### System
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

### XDG
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

### ZSH
export ZDOTDIR="$HOME/.config/zsh"

### ZSH (Custom)
# Config
export Z_CONFIG_DIR="$XDG_CONFIG_HOME/zsh"
export Z_RC_DIR="$Z_CONFIG_DIR/rc"
export Z_COMPLETION_DIR="$Z_CONFIG_DIR/completions"
# Cache
export Z_CACHE_DIR="$XDG_CACHE_HOME/zsh"
export Z_COMPDUMP_FILE="$Z_CACHE_DIR/compdump"
# Data
export Z_DATA_DIR="$XDG_DATA_HOME/zsh"
export Z_PLUGIN_DIR="$Z_DATA_DIR/plugins"
export Z_HIST_FILE="$Z_DATA_DIR/history"

### ppl
export PPL_DIR="$HOME/.ppl"

### Paths
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/nvim-linux-x86_64/bin:$PATH"
