-- Monitor declarations are generated into monitors.lua by the installer.
require("monitors")

hl.config({
    cursor = { no_warps = true },
    input = { kb_layout = "us" },
    binds = { drag_center_window = false },
})

hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + A", hl.dsp.exec_cmd("wofi --show drun"))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.float({action = "toggle"}))
for workspace = 1, 10 do
    local key = workspace % 10
    hl.bind("SUPER + " .. key, hl.dsp.focus({workspace = workspace}))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({workspace = workspace}))
end

local switcher = "$HOME/.local/share/desktop-switcher/switch.sh"
hl.bind("SUPER + F1", hl.dsp.exec_cmd(switcher .. " --animate serpantinum"))
hl.bind("SUPER + F2", hl.dsp.exec_cmd(switcher .. " --animate leyzs"))
hl.bind("SUPER + F3", hl.dsp.exec_cmd(switcher .. " --animate win11"))

hl.window_rule({
    match = { title = "^Cinematic Desktop Transition$" },
    no_anim = true,
})
hl.layer_rule({
    match = { namespace = "^serpantinum-cinematic$" },
    no_anim = true,
    order = -1000,
})
hl.window_rule({ match = { class = ".*" }, float = true })

hl.on("hyprland.start", function()
    hl.exec_cmd(switcher .. " --login leyzs")
end)
