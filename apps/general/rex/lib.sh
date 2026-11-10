# Where the rex command is: on PATH (a Linux package, or a Mac with the CLI
# installed), or inside the Mac app. Sourced by every app.sh that talks to Rex.
rex_bin() {
    if have rex; then
        command -v rex
        return
    fi
    local app
    for app in "/Applications/Rex.app" "/Applications/Rex Beta.app"; do
        [[ -x "$app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex" ]] || continue
        printf '%s' "$app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
        return
    done
    return 1
}
