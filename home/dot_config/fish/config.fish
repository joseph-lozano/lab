set -gx EDITOR vim
set -gx PATH $HOME/.local/bin $PATH
if test -x $HOME/.local/bin/mise
    $HOME/.local/bin/mise activate fish | source
end
