### General
setopt histignorealldups sharehistory
bindkey -e
HISTSIZE=1000
SAVEHIST=1000
HISTFILE="$Z_HIST_FILE"
fpath+=("$Z_COMPLETION_DIR" "$Z_PLUGIN_DIR/pure")

### Run Commands
source "$Z_RC_DIR/aliase.zsh"
source "$Z_RC_DIR/ppl.zsh"

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
eval "$(zoxide init zsh)"
source "$Z_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$Z_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" # MUST BE LAST

### SSH Agent (https://grep.koditi.my/reuse-existing-ssh-agent)
# Function to find existing SSH agent
find_ssh_agent() {
	echo "Look for existing ssh-agent processes"
	AGENT_PID=$(pgrep -u $USER ssh-agent)
	if [ -n "$AGENT_PID" ]; then
		# Try to find socket in standard locations
		for SOCKET in /tmp/ssh-*/agent.*; do
			echo $SOCKET
			if [ -S "$SOCKET" ]; then # Check if it's a valid socket
				# Test the socket
				SSH_AUTH_SOCK=$SOCKET ssh-add -l >/dev/null 2>&1
				if [ $? -ne 2 ]; then # Exit code 2 means socket is invalid
					echo "Found socket $SOCKET"
					export SSH_AUTH_SOCK=$SOCKET
					export SSH_AGENT_PID=$AGENT_PID
					return 0
				fi
			fi
		done
	fi
	return 1
}

echo "Try to find existing agent first"
if ! find_ssh_agent; then
	echo "If no agent found, start a new one"
	eval "$(ssh-agent)" >/dev/null
fi

echo "Check if keys are already added"
ssh-add -l >/dev/null 2>&1
if [ $? -eq 1 ]; then
	echo "No identities found, add default keys"
	ssh-add
fi
