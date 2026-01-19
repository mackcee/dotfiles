# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"


# --- helpers for portability ---
is_macos() { [[ "$OSTYPE" == darwin* ]]; }
is_linux() { [[ "$OSTYPE" == linux* ]]; }

# Source a file only if it exists
source_if_exists() {
  [[ -f "$1" ]] && source "$1"
}

# Prefer Homebrew prefix if available (macOS)
brew_prefix() {
  command -v brew >/dev/null 2>&1 && brew --prefix
}

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

bindkey -v

alias cat='bat'
alias ls='eza --icons'
alias ll='eza -lah --icons -h'
alias lt='eza -lah --icons -h --sort=modified'
alias pbc='xclip -selection clipboard'
alias pbp='xclip -selection clipboard -o'

zstyle :compinstall filename "$HOME/.zshrc"

fpath=(~/.zsh/completions $fpath)

autoload -Uz compinit
compinit


# fzf keybindings / completion (portable)
if command -v fzf >/dev/null 2>&1; then
  # preferred: ask fzf to generate correct init for this platform
  eval "$(fzf --zsh 2>/dev/null)" || true

  # fallback paths (Arch / Homebrew)
  source_if_exists "/usr/share/fzf/key-bindings.zsh"
  source_if_exists "/usr/share/fzf/completion.zsh"

  local bp="$(brew_prefix)"
  if [[ -n "$bp" ]]; then
    source_if_exists "$bp/opt/fzf/shell/key-bindings.zsh"
    source_if_exists "$bp/opt/fzf/shell/completion.zsh"
  fi
fi


 
# RPC URLS
sepolia_rpc_url=https://eth-sepolia.g.alchemy.com/v2/7moGyB4OM8Ert3cRTG3bO4mI4ZSu3TOz
mainnet_rpc_url=https://eth-mainnet.g.alchemy.com/v2/7moGyB4OM8Ert3cRTG3bO4mI4ZSu3TOz

# zsh-autosuggestions
source_if_exists "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
source_if_exists "/usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
local bp="$(brew_prefix)"
[[ -n "$bp" ]] && source_if_exists "$bp/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# zsh-syntax-highlighting (must be last among zsh plugins)
source_if_exists "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
source_if_exists "/usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -n "$bp" ]] && source_if_exists "$bp/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

source /usr/share/nvm/init-nvm.sh

# Kitty shell integration (portable)
# Kitty sets KITTY_INSTALLATION_DIR when launched from Kitty
if [[ -n "$KITTY_INSTALLATION_DIR" ]]; then
  source_if_exists "$KITTY_INSTALLATION_DIR/shell-integration/zsh/kitty.zsh"
else
  # fallback common paths
  source_if_exists "/usr/lib/kitty/shell-integration/zsh/kitty.zsh"
  local bp="$(brew_prefix)"
  [[ -n "$bp" ]] && source_if_exists "$bp/opt/kitty/share/kitty/shell-integration/zsh/kitty.zsh"
fi

export PATH="$HOME/.local/bin:$PATH"
export PATH="/usr/lib/docker/cli-plugins:$PATH"

unset ARGV0 # fix for terminal issues with rust 

eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
eval "$(thefuck --alias)"

