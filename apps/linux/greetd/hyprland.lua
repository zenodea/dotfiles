hl.config({
    misc = {
        background_color = "rgb(@BG@)",
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c 'qs -p /etc/greetd/quickshell/greeter.qml; hyprctl dispatch exit'")
end)
