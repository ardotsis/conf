export PATH="$PATH:/opt/nvim-linux-x86_64/bin"

# Other config
source "$ZRCDIR/aliase.zsh"

# Prompt framework
eval "$(starship init zsh)"

# Plugins
source "${ZPLUGINDIR}/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "${ZPLUGINDIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" # Source at the end of the file
