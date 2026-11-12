local terminal = "ghostty --gtk-single-instance=true"
local menu = "qs ipc call shell launcher apps"
local mainMod = "SUPER"

hl.monitor({ output = "DP-1", mode = "3840x2160@120", position = "0x0", scale = 1.67 })
hl.monitor({ output = "eDP-1", mode = "2880x1920@120", position = "auto-left", scale = 1.67 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.67 })

for i = 1, 9 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "DP-1", default = true })
end
hl.workspace_rule({ workspace = "10", monitor = "eDP-1", default = true })

hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -d")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprsunset")
    hl.exec_cmd("systemctl --user start plasma-polkit-agent")
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
    hl.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ true")
    hl.exec_cmd("awww img ~/.config/current-wallpaper")
    hl.exec_cmd("ghostty --gtk-single-instance=true --quit-after-last-window-closed=false --initial-window=false")
end)

local accent = { colors = { "rgb(${PURPLE})", "rgb(${BG_ALT})" }, angle = 90 }

hl.config({
    general = {
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0,
        layout = "dwindle",
        allow_tearing = false,
        col = {
            active_border = "rgb(${BORDER})",
            inactive_border = "rgb(${SURFACE})",
            nogroup_border = "rgba(${BG}dd)",
            nogroup_border_active = accent,
        },
    },

    group = {
        groupbar = {
            col = {
                active = accent,
                inactive = "rgba(${BG}dd)",
            },
        },
    },

    decoration = {
        rounding = 0,
        dim_inactive = true,
        dim_strength = 0.06,
        blur = {
            enabled = true,
            size = 3,
            passes = 3,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        force_default_wallpaper = -1,
        allow_session_lock_restore = true,
        background_color = "rgb(${BG})",
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },

    input = {
        kb_options = "ctrl:nocaps",
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
        },
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "easeOutQuint", style = "popin 92%" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = false })

hl.device({
    name = "epic-mouse-v1",
    sensitivity = -0.5,
})

hl.layer_rule({
    name = "rofi-blur",
    match = { namespace = "rofi" },
    blur = true,
    ignore_alpha = 0,
})

local function run(keys, cmd)
    hl.bind(keys, hl.dsp.exec_cmd(cmd))
end

run("XF86AudioRaiseVolume", "pactl set-sink-volume @DEFAULT_SINK@ +5%")
run("XF86AudioLowerVolume", "pactl set-sink-volume @DEFAULT_SINK@ -5%")
run("XF86AudioMute", "pactl set-sink-mute @DEFAULT_SINK@ toggle")
run("XF86MonBrightnessUp", "brightnessctl set +10%")
run("XF86MonBrightnessDown", "brightnessctl set 10%-")
run("XF86Display", "slurp | grim -g- | wl-copy")

run(mainMod .. " + Return", terminal)
run(mainMod .. " + Q", menu)
run(mainMod .. " + Space", menu)
run(mainMod .. " + R", menu)
run(mainMod .. " + SHIFT + P", "qs ipc call shell launcher session")
run(mainMod .. " + W", "qs ipc call shell launcher wallpapers")
run(mainMod .. " + T", "qs ipc call shell launcher themes")
run(mainMod .. " + F", "qs ipc call shell launcher fonts")
run(mainMod .. " + D", "qs ipc call shell drawer dashboard")
run(mainMod .. " + SHIFT + D", "qs ipc call shell drawer system")
run(mainMod .. " + C", "qs ipc call shell controls")
run(mainMod .. " + A", "qs ipc call shell agent")
run(mainMod .. " + SHIFT + V", "qs ipc call shell clipboard")
run(mainMod .. " + O", "qs ipc call shell lock")
run(mainMod .. " + SHIFT + L", "qs ipc call shell lock")
run(mainMod .. " + E", "ghostty -e yazi")
run(mainMod .. " + N", "$HOME/scripts/night-mode")
run(mainMod .. " + M", "spotify-launcher")
run(mainMod .. " + B", "firefox")
run(mainMod .. " + V", "mullvad-vpn")
run(mainMod .. " + Y", "firefox youtube.com")
run(mainMod .. " + P", "firefox mail.proton.me")

hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))

hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
