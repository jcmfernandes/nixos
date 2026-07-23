# Emacs-related zsh integration. Auto-sourced by oh-my-zsh as a $ZSH_CUSTOM
# file (~/.config/omz/*.zsh), after plugins load, so the emacs/git plugin
# aliases (e, gst) already exist when this runs.
#
# Ghostel shell integration (https://github.com/dakra/ghostel#shell-integration):
# directory tracking and prompt navigation work out of the box; these functions
# let terminal commands drive the running Emacs instead of spawning new processes.
# `ghostel_cmd` is provided by Ghostel; each target must be whitelisted in
# `ghostel-eval-cmds` on the Emacs side. The `function` keyword + `unalias` are
# required (not the `e() { }` form) because the omz emacs/git plugins define `e`
# and `gst` as aliases, which would otherwise cause a parse error.
if [[ "$INSIDE_EMACS" = 'ghostel' ]]; then
    unalias e dow gst 2>/dev/null
    function e   { ghostel_cmd find-file-other-window "$@"; }        # open file(s) in Emacs
    function dow { ghostel_cmd dired-other-window "$@"; }            # dired in another window
    function gst { ghostel_cmd magit-status-setup-buffer "$(pwd)"; } # magit for the current dir
fi
