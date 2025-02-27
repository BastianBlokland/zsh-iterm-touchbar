# GIT
GIT_UNCOMMITTED="${GIT_UNCOMMITTED:-+}"
GIT_UNSTAGED="${GIT_UNSTAGED:-!}"
GIT_UNTRACKED="${GIT_UNTRACKED:-?}"
GIT_STASHED="${GIT_STASHED:-$}"
GIT_UNPULLED="${GIT_UNPULLED:-⇣}"
GIT_UNPUSHED="${GIT_UNPUSHED:-⇡}"
TOUCHBAR_GIT_ENABLED=true

# https://unix.stackexchange.com/a/22215
find-up () {
  path=$PWD
  while [[ "$path" != "" && ! -e "$path/$1" ]]; do
    path=${path%/*}
  done
  echo "$path"
}

# Output name of current branch.
git_current_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # no git repo.
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

# Uncommitted changes.
# Check for uncommitted changes in the index.
git_uncomitted() {
  if ! $(git diff --quiet --ignore-submodules --cached); then
    echo -n "${GIT_UNCOMMITTED}"
  fi
}

# Unstaged changes.
# Check for unstaged changes.
git_unstaged() {
  if ! $(git diff-files --quiet --ignore-submodules --); then
    echo -n "${GIT_UNSTAGED}"
  fi
}

# Untracked files.
# Check for untracked files.
git_untracked() {
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo -n "${GIT_UNTRACKED}"
  fi
}

# Stashed changes.
# Check for stashed changes.
git_stashed() {
  if $(git rev-parse --verify refs/stash &>/dev/null); then
    echo -n "${GIT_STASHED}"
  fi
}

# Unpushed and unpulled commits.
# Get unpushed and unpulled commits from remote and draw arrows.
git_unpushed_unpulled() {
  # check if there is an upstream configured for this branch
  command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

  local count
  count="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"
  # exit if the command failed
  (( !$? )) || return

  # counters are tab-separated, split on tab and store as array
  count=(${(ps:\t:)count})
  local arrows left=${count[1]} right=${count[2]}

  (( ${right:-0} > 0 )) && arrows+="${GIT_UNPULLED}"
  (( ${left:-0} > 0 )) && arrows+="${GIT_UNPUSHED}"

  [ -n $arrows ] && echo -n "${arrows}"
}

pecho() {
  if [ -n "$TMUX" ]; then
    echo -ne "\ePtmux;\e$*\e\\"
  else
    echo -ne $*
  fi
}

# F1-12: https://github.com/vmalloc/zsh-config/blob/master/extras/function_keys.zsh
# F13-F20: just running read and pressing F13 through F20. F21-24 don't print escape sequences
fnKeys=('^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~' '^[[1;2P' '^[[1;2Q' '^[[1;2R' '^[[1;2S' '^[[15;2~' '^[[17;2~' '^[[18;2~' '^[[19;2~')
touchBarState=''
npmScripts=()
gitBranches=()
lastPackageJsonPath=''

function _clearTouchbar() {
  pecho "\033]1337;PopKeyLabels\a"
}

function _unbindTouchbar() {
  for fnKey in "$fnKeys[@]"; do
    bindkey -s "$fnKey" ''
  done
}

function setKey(){
  pecho "\033]1337;SetKeyLabel=F${1}=${2}\a"
  if [ "$4" != "-q" ]; then
    bindkey -s $fnKeys[$1] "$3 \n"
  else
    bindkey $fnKeys[$1] $3
  fi
}

function clearKey(){
  pecho "\033]1337;SetKeyLabel=F${1}=F${1}\a"
}

function _displayDefault() {
  if [[ $touchBarState != "" ]]; then
    _clearTouchbar
  fi
  _unbindTouchbar
  touchBarState=""

  # CURRENT_DIR
  # -----------
  setKey 1 "👉 $(echo $PWD | awk -F/ '{print $(NF-1)"/"$(NF)}')" _displayPath '-q'

  # GIT
  # ---
  # Check if the current directory is a git repository and not the .git directory
  if [[ "$TOUCHBAR_GIT_ENABLED" = true ]] &&
    git rev-parse --is-inside-work-tree &>/dev/null &&
    [[ "$(git rev-parse --is-inside-git-dir 2> /dev/null)" == 'false' ]]; then

    # Ensure the index is up to date.
    git update-index --really-refresh -q &>/dev/null

    # String of indicators
    local indicators=''

    indicators+="$(git_uncomitted)"
    indicators+="$(git_unstaged)"
    indicators+="$(git_untracked)"
    indicators+="$(git_stashed)"
    indicators+="$(git_unpushed_unpulled)"

    [ -n "${indicators}" ] && touchbarIndicators="🔥[${indicators}]" || touchbarIndicators="🙌";

    setKey 2 "🎋 `git_current_branch`" _displayBranches '-q'
    setKey 3 $touchbarIndicators "git status -sb"
    setKey 4 "🔼 push" "git push origin $(git_current_branch)"
    setKey 5 "🔽 pull" "git pull origin $(git_current_branch)"
    setKey 6 "📜 log" "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --all"
    setKey 7 "💣 reset" "git reset HEAD --hard & git clean -fd"
  else
    clearKey 2
    clearKey 3
    clearKey 4
    clearKey 5
    clearKey 6
    clearKey 7
  fi
}

function _displayBranches() {
  # List of branches for current repo
  gitBranches=($(node -e "console.log('$(echo $(git branch))'.split(/[ ,]+/).toString().split(',').join(' ').toString().replace('* ', ''))"))

  _clearTouchbar
  _unbindTouchbar

  # change to github state
  touchBarState='github'

  fnKeysIndex=1
  # for each branch name, bind it to a key
  for branch in "$gitBranches[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    setKey $fnKeysIndex $branch "git checkout $branch"
  done

  setKey 1 "👈 back" _displayDefault '-q'
}

function _displayPath() {
  _clearTouchbar
  _unbindTouchbar
  touchBarState='path'

  IFS="/" read -rA directories <<< "$PWD"
  fnKeysIndex=2
  for dir in "${directories[@]:1}"; do
    setKey $fnKeysIndex "$dir" "cd $(pwd | cut -d'/' -f-$fnKeysIndex)"
    fnKeysIndex=$((fnKeysIndex + 1))
  done

  setKey 1 "👈 back" _displayDefault '-q'
}

zle -N _displayDefault
zle -N _displayBranches
zle -N _displayPath

precmd_iterm_touchbar() {
  if [[ $touchBarState == 'github' ]]; then
    _displayBranches
  elif [[ $touchBarState == 'path' ]]; then
    _displayPath
  else
    _displayDefault
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd precmd_iterm_touchbar
