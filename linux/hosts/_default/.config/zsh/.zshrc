export PATH="/opt/nvim-linux-x86_64/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

fpath+=("$Z_COMPLETION_DIR" "$Z_PLUGIN_DIR/pure")
# Pure prompt
autoload -U promptinit
promptinit
PURE_CMD_MAX_EXEC_TIME=10
# zstyle :prompt:pure:path color white
zstyle ':prompt:pure:prompt:*' color cyan
zstyle :prompt:pure:git:stash show yes
prompt pure

setopt histignorealldups sharehistory
bindkey -e

HISTSIZE=1000
SAVEHIST=1000
HISTFILE="$Z_HIST_FILE"

autoload -Uz compinit
compinit -d "$Z_COMPDUMP_FILE" # TODO: broken. they dont output anything

# eval "$(starship init zsh)" # https://github.com/starship/starship/issues/6519
eval "$(zoxide init zsh)" # TODO: fzf

# Configs
source "$Z_RC_DIR/aliase.zsh"

# Plugins (TODO: copy and paste to under .config)
source "$Z_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$Z_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" # MUST BE LAST
