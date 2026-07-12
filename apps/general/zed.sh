# Zed — watches settings.json and restyles itself, so there's no reload step.

render() {
    generate zed/settings.json "$DOTFILES/general/config/zed/settings.json"
}
