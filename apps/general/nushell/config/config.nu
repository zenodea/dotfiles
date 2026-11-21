$env.config.show_banner = false
$env.config.error_style = "nested"
$env.config.render_right_prompt_on_last_line = true
$env.config.highlight_resolved_externals = true
$env.config.history.path = ($nu.data-dir | path join history.txt)
$env.config.buffer_editor = "nvim"
$env.config.edit_mode = "vi"
$env.config.cursor_shape.vi_insert = "line"
$env.config.cursor_shape.vi_normal = "block"

$env.config.color_config = ($env.config.color_config | merge {
    shape_internalcall: blue
    shape_external_resolved: blue
    shape_external: red
    shape_externalarg: default
    shape_garbage: red
    shape_string: green_italic
    shape_raw_string: green_italic
    shape_string_interpolation: cyan_italic
    shape_flag: yellow
    shape_pipe: dark_gray
    shape_redirection: dark_gray
    hints: dark_gray_italic
})

const link_pattern = r#'(https?://(?:[^\s<>"'`|\\^{}()\x00-\x1f\x7f]|\([^\s<>"'`|\\^{}()\x00-\x1f\x7f]*\))*(?:[^\s<>"'`|\\^{}()\x00-\x1f\x7f.,;:!?\]*_]|\([^\s<>"'`|\\^{}()\x00-\x1f\x7f]*\)))'#

def mark-link []: string -> string {
    let text = $in
    if ("://" not-in $text) or ("\e" in $text) or ("\n" in $text) { return $text }
    let found = $text | parse --regex $link_pattern
    if ($found | length) != 1 { return $text }
    let url = $found.0.capture0
    if ($text | str length) - ($url | str length) > 40 { return $text }
    $"\e]8;;($url)\e\\($text)\e]8;;\e\\"
}

def mark-links []: any -> any {
    let value = $in
    let kind = $value | describe
    if $kind == "string" {
        $value | mark-link
    } else if ($kind | str starts-with "record") {
        $value | columns | reduce --fold $value {|column, row| $row | update $column { mark-links } }
    } else if $kind =~ '^(list|table)' {
        $value | each --keep-empty { mark-links }
    } else {
        $value
    }
}

$env.config.hooks.display_output = {||
    metadata access {|meta|
        let value = $in
        let marked = if ($value | describe) == "string" or not $env.config.shell_integration.osc8 {
            $value
        } else {
            try { $value | mark-links } catch { $value }
        }
        $marked | metadata set --path-columns ($meta.path_columns? | default []) --table-width-priority-columns ($meta.table_width_priority_columns? | default [])
    } | if (term size).columns >= 100 { table -e } else { table }
}

let over_ssh = ("SSH_CLIENT" in $env) or ("SSH2_CLIENT" in $env)
let prompt_host = if $over_ssh {
    $"(ansi red)((sys host).hostname)"
} else {
    $"(ansi green)((sys host).hostname | split row '.' | first)"
}

def prompt-git-ref [] {
    for args in [[symbolic-ref --short HEAD] [describe --tags --exact-match HEAD] [rev-parse --short HEAD]] {
        let found = ^git ...$args | complete
        if $found.exit_code == 0 { return ($found.stdout | str trim) }
    }
    ""
}

def prompt-git [] {
    let ref = prompt-git-ref
    if ($ref | is-empty) { return "" }
    let status = with-env {GIT_OPTIONAL_LOCKS: "0"} {
        ^git status --porcelain --ignore-submodules=dirty | complete
    }
    let dirty = if ($status.stdout | is-empty) { "" } else { "*" }
    $"(ansi yellow)‹($ref)($dirty)› (ansi reset)"
}

def prompt-dir [] {
    let home = $nu.home-dir
    if $env.PWD == $home {
        "~"
    } else if ($env.PWD | str starts-with $"($home)/") {
        $env.PWD | str replace $home "~"
    } else {
        $env.PWD
    }
}

$env.PROMPT_COMMAND = {||
    let accent = if (is-admin) { ansi red } else { ansi green }
    let arrow = if (is-admin) { ansi red } else { ansi reset }
    [
        $"(ansi reset)╭─($accent)($env.USER)(ansi cyan)@($prompt_host)(ansi reset)"
        $" (ansi blue_bold)(prompt-dir)(ansi reset)  (prompt-git)\n"
        $"╰─($arrow)➤(ansi reset)  "
    ] | str join
}

$env.PROMPT_COMMAND_RIGHT = {||
    if $env.LAST_EXIT_CODE == 0 { "" } else { $"(ansi red)($env.LAST_EXIT_CODE) ↵(ansi reset)" }
}

$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ""
$env.PROMPT_INDICATOR_VI_NORMAL = ""
