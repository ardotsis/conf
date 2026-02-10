### General
setopt histignorealldups sharehistory
bindkey -e
HISTSIZE=1000
SAVEHIST=1000
HISTFILE="$Z_HIST_FILE"
fpath+=("$Z_COMPLETION_DIR" "$Z_PLUGIN_DIR/pure")

### RC
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

# <3
ppl() {
	printf "kamakura amane\n"
	printf "muranaka mimori\n"
	printf "arimura ruka\n"
	printf "fujinami mizuki\n"
	printf "yoshida mitsuki\n"
	printf "\n"
	printf "hurry up. u have no time to study.\n"
}

### Plugins
eval "$(zoxide init zsh)"
source "$Z_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$Z_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" # MUST BE LAST
