-- keys.lua — WezTerm keybindings
-- Loaded by wezterm.lua via pcall(dofile, ...).
-- Returns the config.keys table (array of binding objects).
-- Leader: Ctrl+a (900ms timeout, set in wezterm.lua).

local wezterm = require("wezterm")
local act = wezterm.action

-- Type a command into the active pane + Enter (tmux-style prefix trigger).
local function send(cmd)
  return act.SendString(cmd .. "\r")
end

return {
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
}
