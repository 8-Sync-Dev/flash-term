-- keys.lua — WezTerm keybindings
-- Loaded by wezterm.lua via pcall(dofile, ...).
-- Returns the config.keys table (array of binding objects).
-- Leader: Ctrl+a (900ms timeout, set in wezterm.lua).

local wezterm = require("wezterm")
local act = wezterm.action

-- Session persistence plugin (cached by wezterm; same instance as wezterm.lua).
local resurrect_ok, resurrect =
  pcall(wezterm.plugin.require, "https://github.com/YedPool/resurrect.wezterm")

-- Type a command into the active pane + Enter (tmux-style prefix trigger).
local function send(cmd)
  return act.SendString(cmd .. "\r")
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- Smart paste (Ctrl+Alt+V): WezTerm has no native clipboard-image paste
-- (issue wezterm#7272, closed unmerged). If the clipboard holds an image,
-- save it as %TEMP%\ft-paste\img_<stamp>.png and type the file path into the
-- pane (the Claude Code / 8sync image workflow); otherwise paste text normally.
local paste_image_ps = [==[
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img) {
  $dir = Join-Path $env:TEMP 'ft-paste'
  $null = New-Item -ItemType Directory -Force -Path $dir
  $path = Join-Path $dir ('img_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.png')
  $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  [Console]::Out.Write($path)
}
]==]

local pwsh_shim = wezterm.home_dir .. "\\scoop\\shims\\pwsh.exe"
local paste_shell = file_exists(pwsh_shim) and pwsh_shim
  or "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"

local keys = {
  -- ── Pane splits ──────────────────────────────────────────────────────────
  { key = "|", mods = "CTRL|SHIFT", action = act.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
  { key = "_", mods = "CTRL|SHIFT", action = act.SplitPane({ direction = "Down",  size = { Percent = 34 } }) },
  { key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = false }) },
  { key = "z", mods = "CTRL|SHIFT", action = act.TogglePaneZoomState },

  -- Pane navigation (Ctrl+Shift+Arrow)
  { key = "LeftArrow",  mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left")  },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow",    mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up")    },
  { key = "DownArrow",  mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down")  },

  -- Pane resize (Alt+Shift+Arrow)
  { key = "LeftArrow",  mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Left",  5 }) },
  { key = "RightArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
  { key = "UpArrow",    mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Up",    2 }) },
  { key = "DownArrow",  mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Down",  2 }) },

  -- ── Tabs ─────────────────────────────────────────────────────────────────
  { key = "t",     mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "Tab",   mods = "CTRL",       action = act.ActivateTabRelative(1)  },
  { key = "Tab",   mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "Enter", mods = "ALT",        action = act.ToggleFullScreen },
  -- Alt+1..9 jumps to tab N; Alt+0 -> last tab
  { key = "1", mods = "ALT", action = act.ActivateTab(0) },
  { key = "2", mods = "ALT", action = act.ActivateTab(1) },
  { key = "3", mods = "ALT", action = act.ActivateTab(2) },
  { key = "4", mods = "ALT", action = act.ActivateTab(3) },
  { key = "5", mods = "ALT", action = act.ActivateTab(4) },
  { key = "6", mods = "ALT", action = act.ActivateTab(5) },
  { key = "7", mods = "ALT", action = act.ActivateTab(6) },
  { key = "8", mods = "ALT", action = act.ActivateTab(7) },
  { key = "9", mods = "ALT", action = act.ActivateTab(8) },
  { key = "0", mods = "ALT", action = act.ActivateTab(-1) },

  -- ── Font size ────────────────────────────────────────────────────────────
  { key = "=", mods = "CTRL", action = act.IncreaseFontSize },
  { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
  { key = "0", mods = "CTRL", action = act.ResetFontSize    },

  -- ── Clipboard ────────────────────────────────────────────────────────────
  { key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard")    },
  { key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
  { key = "v", mods = "CTRL",       action = act.PasteFrom("Clipboard") },
  -- Smart paste: image in clipboard -> save PNG + type its path; else text paste
  { key = "v", mods = "CTRL|ALT",   action = wezterm.action_callback(function(window, pane)
    local ok, stdout = wezterm.run_child_process({
      paste_shell, "-NoLogo", "-NoProfile", "-STA", "-Command", paste_image_ps,
    })
    if ok and stdout and stdout ~= "" then
      pane:send_text(stdout:gsub("[\r\n]+$", ""))
    else
      window:perform_action(act.PasteFrom("Clipboard"), pane)
    end
  end) },

  -- ── Search / palette / launcher / select ─────────────────────────────────
  { key = "f", mods = "CTRL|SHIFT", action = act.Search({ CaseInSensitiveString = "" }) },
  { key = "p", mods = "CTRL|SHIFT", action = act.ActivateCommandPalette },
  { key = "l", mods = "CTRL|SHIFT", action = act.ShowLauncher           },
  { key = "y", mods = "CTRL|SHIFT", action = act.QuickSelect            },

  -- ── Leader (Ctrl+a) — tmux-style prefix ──────────────────────────────────
  { key = "a", mods = "LEADER", action = act.SendKey({ key = "a", mods = "CTRL" }) },
  { key = "c", mods = "LEADER", action = act.ActivateCopyMode },
  { key = "x", mods = "LEADER", action = act.ActivateCommandPalette },
  { key = "s", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES|TABS|LAUNCH_MENU_ITEMS" }) },
  { key = "r", mods = "LEADER", action = act.ReloadConfiguration },

  -- ── Leader — AI (su-code `8sync`) + ft shortcuts ─────────────────────────
  -- Leader .   resume the latest omp session in this repo
  { key = ".", mods = "LEADER", action = send("8sync .") },
  -- Leader o   start typing an omp one-shot prompt (8sync ai <your prompt>)
  { key = "o", mods = "LEADER", action = act.SendString("8sync ai ") },
  -- Leader h   harness readiness (omp / skills / codegraph / MCP / memory)
  { key = "h", mods = "LEADER", action = send("8sync harness status") },
  -- Leader k   skill registry list
  { key = "k", mods = "LEADER", action = send("8sync skill list") },
  -- Leader u   update-all dry-run preview
  { key = "u", mods = "LEADER", action = send("ft up --check") },
  -- Leader b   background wallpaper picker
  { key = "b", mods = "LEADER", action = send("ft bg pick") },

  -- ── Leader — session save/restore (resurrect.wezterm) ────────────────────
}

if resurrect_ok then
  -- Leader S   save the whole workspace state now (also auto-saved every 2 min)
  table.insert(keys, {
    key = "S",
    mods = "LEADER",
    action = wezterm.action_callback(function(window, pane)
      resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
    end),
  })
  -- Leader R   fuzzy-pick a saved workspace/window/tab and restore it
  table.insert(keys, {
    key = "R",
    mods = "LEADER",
    action = wezterm.action_callback(function(window, pane)
      resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id, label)
        local type = string.match(id, "^([^/]+)")
        id = string.match(id, "([^/]+)$")
        id = string.match(id, "(.+)%..+$")
        local opts = {
          relative = true,
          restore_text = true,
          on_pane_restore = resurrect.tab_state.default_on_pane_restore,
        }
        if type == "workspace" then
          resurrect.workspace_state.restore_workspace(
            resurrect.state_manager.load_state(id, "workspace"), opts)
        elseif type == "window" then
          resurrect.window_state.restore_window(
            pane:window(), resurrect.state_manager.load_state(id, "window"), opts)
        elseif type == "tab" then
          resurrect.tab_state.restore_tab(
            pane:tab(), resurrect.state_manager.load_state(id, "tab"), opts)
        end
      end)
    end),
  })
end

return keys
