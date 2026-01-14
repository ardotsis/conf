export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

# TODO: in zprfile??

# XDG
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

# ZSH's environment variables
export ZDOTDIR="$HOME/.config/zsh"
# Custom ZSH environment variables
export Z_SHARE_DIR="$HOME/.local/share/zsh"
export Z_RC_DIR="$ZDOTDIR/rc"
