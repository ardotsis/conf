export PATH="/opt/nvim-linux-x86_64/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# TODO: history size? ref default zshrc
fpath+=("$ZDOTDIR/completions")
autoload -Uz compinit
compinit

eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

# Configs
source "$Z_RC_DIR/aliase.zsh"

# Plugins
source "$Z_SHARE_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "$Z_SHARE_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" # MUST BE LAST
