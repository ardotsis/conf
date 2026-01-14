# TODO: FIX THE LOAD ORDER
# TODO: FIX THE LOAD ORDER
# TODO: FIX THE LOAD ORDER
# TODO: FIX THE LOAD ORDER
export PATH="$PATH:/opt/nvim-linux-x86_64/bin"

autoload -Uz compinit
compinit

# TODO: history

# Other config
source "$Z_RC_DIR/aliase.zsh"

# Prompt framework
eval "$(starship init zsh)"

# Plugins
source "${Z_SHARE_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "${Z_SHARE_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" # Source at the end of the file
