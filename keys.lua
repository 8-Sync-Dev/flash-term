-- keys.lua — WezTerm keybindings
-- Loaded by wezterm.lua via pcall(dofile, ...).
-- Returns the config.keys table (array of binding objects).

local wezterm = require("wezterm")

return {
  -- Pane splits
  { key = "|", mods = "CTRL|SHIFT", action = wezterm.action.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
  { key = "_", mods = "CTRL|SHIFT", action = wezterm.action.SplitPane({ direction = "Down",  size = { Percent = 34 } }) },
  { key = "w", mods = "CTRL|SHIFT", action = wezterm.action.CloseCurrentPane({ confirm = false }) },
  { key = "z", mods = "CTRL|SHIFT", action = wezterm.action.TogglePaneZoomState },

  -- Pane navigation
  { key = "LeftArrow",  mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Left")  },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Right") },
  { key = "UpArrow",    mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Up")    },
  { key = "DownArrow",  mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Down")  },

  -- Pane resize
  { key = "LeftArrow",  mods = "ALT|SHIFT", action = wezterm.action.AdjustPaneSize({ "Left",  5 }) },
  { key = "RightArrow", mods = "ALT|SHIFT", action = wezterm.action.AdjustPaneSize({ "Right", 5 }) },
  { key = "UpArrow",    mods = "ALT|SHIFT", action = wezterm.action.AdjustPaneSize({ "Up",    2 }) },
  { key = "DownArrow",  mods = "ALT|SHIFT", action = wezterm.action.AdjustPaneSize({ "Down",  2 }) },

  -- Font size
  { key = "=", mods = "CTRL", action = wezterm.action.IncreaseFontSize },
  { key = "-", mods = "CTRL", action = wezterm.action.DecreaseFontSize },
  { key = "0", mods = "CTRL", action = wezterm.action.ResetFontSize    },

  -- Clipboard
  { key = "c", mods = "CTRL|SHIFT", action = wezterm.action.CopyTo("Clipboard")      },
  { key = "v", mods = "CTRL|SHIFT", action = wezterm.action.PasteFrom("Clipboard")   },
  { key = "v", mods = "CTRL",       action = wezterm.action.PasteFrom("Clipboard")   },

  -- Search / palette / launcher / select
  { key = "f", mods = "CTRL|SHIFT", action = wezterm.action.Search({ CaseInSensitiveString = "" }) },
  { key = "p", mods = "CTRL|SHIFT", action = wezterm.action.ActivateCommandPalette },
  { key = "l", mods = "CTRL|SHIFT", action = wezterm.action.ShowLauncher           },
  { key = "y", mods = "CTRL|SHIFT", action = wezterm.action.QuickSelect            },

  -- Tab management
  { key = "t",     mods = "CTRL|SHIFT", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
  { key = "Enter", mods = "ALT",        action = wezterm.action.ToggleFullScreen              },

  -- Leader (Ctrl+a, 900ms timeout — set in wezterm.lua)
  { key = "a", mods = "LEADER", action = wezterm.action.SendKey({ key = "a", mods = "CTRL" }) },
  { key = "c", mods = "LEADER", action = wezterm.action.ActivateCopyMode },
  { key = "x", mods = "LEADER", action = wezterm.action.ActivateCommandPalette },
  { key = "s", mods = "LEADER", action = wezterm.action.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES|TABS|LAUNCH_MENU_ITEMS" }) },
}
