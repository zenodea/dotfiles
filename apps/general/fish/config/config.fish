set -g fish_greeting

fish_add_path --path \
    ~/.local/bin \
    ~/.local/lib/node_modules/.bin \
    ~/.npm-global/bin \
    ~/.cargo/bin \
    /opt/homebrew/opt/ruby@3.2/bin \
    /opt/homebrew/opt/ruby/bin \
    /opt/homebrew/bin \
    /opt/homebrew/sbin
fish_add_path --path --append ~/.filen-cli/bin

set -gx NVIM_LOG_FILE ~/.local/state/nvim/log
test "$TERM_PROGRAM" = rex; and set -gx FORCE_HYPERLINK 1

test -f ~/.config/fish/local.fish; and source ~/.config/fish/local.fish

if status is-interactive; and command -q nu
    function __handoff_to_nu --on-event fish_prompt
        functions --erase __handoff_to_nu
        set -l parent (ps -o comm= -p (ps -o ppid= -p $fish_pid | string trim) | path basename)
        string match -q -r '^-?nu$' -- $parent; and return
        status is-login; and exec nu --login
        exec nu
    end
end
