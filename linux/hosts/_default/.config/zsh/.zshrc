### General
setopt histignorealldups sharehistory
bindkey -e
HISTSIZE=1000
SAVEHIST=1000
HISTFILE="$Z_HIST_FILE"
fpath+=("$Z_COMPLETION_DIR" "$Z_PLUGIN_DIR/pure")

### RC
source "$PPL_DIR/ppl.zsh"
source "$Z_RC_DIR/aliase.zsh"

### Completion
autoload -Uz compinit && compinit -d "$Z_COMPDUMP_FILE"

### Prompt
# eval "$(starship init zsh)"
autoload -U promptinit && promptinit
PURE_CMD_MAX_EXEC_TIME=10
zstyle ':prompt:pure:prompt:*' color cyan
zstyle :prompt:pure:git:stash show yes
prompt pure

### Plugins
eval "$(zoxide init zsh)" # TODO: fzf
source "$Z_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$Z_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" # MUST BE LAST
