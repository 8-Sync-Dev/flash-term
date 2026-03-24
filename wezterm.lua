local wezterm = require("wezterm")
local config = wezterm.config_builder()

local function file_exists(path)
  local ok, _, code = os.rename(path, path)
  return ok or code == 13
end

local home = wezterm.home_dir
local config_dir = wezterm.config_dir or (home .. "\\.config\\wezterm")
local fallback_bg_path = config_dir .. "\\bg\\your-name-couple-3840x2160-25439.jpg"
local current_bg_lua = config_dir .. "\\current-bg.lua"
local bootstrap_path = config_dir .. "\\wezterm-bootstrap.ps1"
local current_opacity_lua = config_dir .. "\\current-opacity.lua"

local default_shell = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
local pwsh_path = home .. "\\scoop\\shims\\pwsh.exe"
if file_exists(pwsh_path) then
  default_shell = pwsh_path
end

local function load_background_path()
  if file_exists(current_bg_lua) then
    local ok, value = pcall(dofile, current_bg_lua)
    if ok and type(value) == "string" and value ~= "" and file_exists(value) then
      return value
    end
  end

  if file_exists(fallback_bg_path) then
    return fallback_bg_path
  end

  return nil
end

local function load_opacity()
  if file_exists(current_opacity_lua) then
    local ok, value = pcall(dofile, current_opacity_lua)
    if ok and type(value) == "number" then
      return math.max(0, math.min(1, value))
    end
  end
  return 0.72
end

local function pane_cwd(pane)
  local cwd_uri = pane:get_current_working_dir()
  if not cwd_uri then
    return ""
  end

  if type(cwd_uri) == "table" and cwd_uri.file_path then
    return cwd_uri.file_path
  end

  local text = tostring(cwd_uri)
  text = text:gsub("^file:///", "")
  text = text:gsub("%%20", " ")
  text = text:gsub("/", "\\")
  return text
end

local function basename(path)
  path = path:gsub("[/\\]+$", "")
  return path:match("([^/\\]+)$") or path
end

local function truncate_text(text, max_len)
  if max_len <= 0 then
    return ""
  end
  if #text <= max_len then
    return text
  end
  if max_len <= 2 then
    return text:sub(1, max_len)
  end
  return text:sub(1, max_len - 2) .. ".."
end

local neon_colors = {
  { l = "#00e5ff", r = "#7c3aed" },
  { l = "#7c3aed", r = "#ff00c8" },
  { l = "#ff00c8", r = "#00e5ff" },
  { l = "#00ff99", r = "#00e5ff" },
}
local neon_idx = 1
local neon_last = 0

wezterm.on("update-status", function(window, pane)
  local now = wezterm.time.now()
  if now - neon_last >= 2.5 then
    neon_last = now
    neon_idx = (neon_idx % #neon_colors) + 1
    local c = neon_colors[neon_idx]
    window:set_config_overrides({
      window_frame = {
        active_titlebar_bg         = "#0b1220",
        inactive_titlebar_bg       = "#0a0f1a",
        active_titlebar_fg         = "#8ffbff",
        inactive_titlebar_fg       = "#5c6b86",
        active_titlebar_border_bottom   = "#1d3b5f",
        inactive_titlebar_border_bottom = "#111b2e",
        button_fg       = "#8ffbff",
        button_bg       = "#101c2f",
        button_hover_fg = "#0b1220",
        button_hover_bg = "#00e5ff",
        border_left_width    = "2px",
        border_right_width   = "2px",
        border_top_height    = "2px",
        border_bottom_height = "2px",
        border_left_color    = c.l,
        border_right_color   = c.r,
        border_top_color     = c.l,
        border_bottom_color  = c.r,
      },
    })
  end

  local cwd     = pane_cwd(pane)
  local process = basename(pane:get_foreground_process_name() or "")
  local ws      = truncate_text(window:active_workspace(), 12)
  local cwd_lbl = truncate_text(cwd ~= "" and basename(cwd) or "~", 18)
  local proc_lbl = truncate_text(process, 16)

  window:set_right_status(wezterm.format({
    { Foreground = { Color = "#a6adc8" } },
    { Text = "  " .. ws .. "  " },
    { Foreground = { Color = "#89b4fa" } },
    { Text = cwd_lbl },
    { Foreground = { Color = "#6c7086" } },
    { Text = "  " .. proc_lbl .. "  " },
  }))
end)

wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
  local title = tab.active_pane.title or ""
  if title == "" then
    title = basename(tab.active_pane.foreground_process_name or "shell")
  end
  local max_chars = math.max(6, max_width - 6)
  return " " .. truncate_text(title, max_chars) .. " "
end)

wezterm.on("format-window-title", function(tab, pane)
  local cwd = pane_cwd(pane)
  local process = basename(pane:get_foreground_process_name() or "")
  local cwd_label = truncate_text(cwd ~= "" and basename(cwd) or "~", 20)
  local process_label = truncate_text(process, 14)
  if tab.is_active then
    return cwd_label .. "  " .. process_label
  end
  return cwd_label
end)

config.default_prog = {
  default_shell,
  "-NoLogo",
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-NoExit",
  "-Command",
  ". '" .. bootstrap_path .. "'",
}

config.default_cwd = home
config.exit_behavior = "CloseOnCleanExit"
config.automatically_reload_config = true
config.window_close_confirmation = "NeverPrompt"

config.font = wezterm.font_with_fallback({
  { family = "JetBrainsMono NF", weight = "Regular" },
  { family = "JetBrainsMono NFM", weight = "Regular" },
  { family = "Consolas" },
})
config.font_size = 14
config.line_height = 1.08
config.freetype_load_target = "Normal"
config.freetype_render_target = "HorizontalLcd"

config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.win32_system_backdrop = "Acrylic"
config.window_padding = { left = 10, right = 10, top = 8, bottom = 8 }
config.initial_cols = 150
config.initial_rows = 42
config.adjust_window_size_when_changing_font_size = false

config.color_scheme = "Catppuccin Mocha"
config.window_background_opacity = 0.0
config.text_background_opacity = 1.0

local active_bg_path = load_background_path()
if active_bg_path then
  config.background = {
    {
      source = { File = active_bg_path },
      width = "100%",
      height = "100%",
      hsb = {
        brightness = 0.32,
        saturation = 0.95,
      },
    },
    {
      source = { Color = "#11111b" },
      width = "100%",
      height = "100%",
      opacity = load_opacity(),
    },
  }
end

config.front_end = "WebGpu"

-- Auto-select GPU: discrete when available, else integrated
local ok_gpus, gpus = pcall(wezterm.gui.enumerate_gpus)
if ok_gpus and gpus and #gpus > 0 then
  local preferred = nil
  for _, gpu in ipairs(gpus) do
    if gpu.device_type == "DiscreteGpu" then
      preferred = gpu
      break
    end
  end
  if not preferred then
    for _, gpu in ipairs(gpus) do
      if gpu.device_type == "IntegratedGpu" then
        preferred = gpu
        break
      end
    end
  end
  if preferred then
    config.webgpu_preferred_adapter = preferred
  end
else
  config.webgpu_power_preference = "HighPerformance"
end
config.webgpu_power_preference = "HighPerformance"

config.window_frame = {
  active_titlebar_bg = "#0b1220",
  inactive_titlebar_bg = "#0a0f1a",
  active_titlebar_fg = "#8ffbff",
  inactive_titlebar_fg = "#5c6b86",
  active_titlebar_border_bottom = "#1d3b5f",
  inactive_titlebar_border_bottom = "#111b2e",
  button_fg = "#8ffbff",
  button_bg = "#101c2f",
  button_hover_fg = "#0b1220",
  button_hover_bg = "#00e5ff",
  border_left_width    = "2px",
  border_right_width   = "2px",
  border_top_height    = "2px",
  border_bottom_height = "2px",
  border_left_color    = "#00e5ff",
  border_right_color   = "#7c3aed",
  border_top_color     = "#00e5ff",
  border_bottom_color  = "#7c3aed",
}

config.integrated_title_buttons = { "Hide", "Maximize", "Close" }
config.integrated_title_button_style = "Windows"
config.integrated_title_button_alignment = "Right"
config.integrated_title_button_color = "#00e5ff"

config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = true
config.show_new_tab_button_in_tab_bar = false
config.scrollback_lines = 12000
config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 650
config.animation_fps = 1
config.max_fps = 120
config.status_update_interval = 1000
config.enable_scroll_bar = false
config.audible_bell = "Disabled"
config.check_for_updates = false
config.enable_kitty_keyboard = false
config.enable_csi_u_key_encoding = false

config.bypass_mouse_reporting_modifiers = "SHIFT"

config.mouse_bindings = {
  {
    event   = { Down = { streak = 1, button = "Left" } },
    mods    = "SHIFT",
    action  = wezterm.action.SelectTextAtMouseCursor("Cell"),
  },
  {
    event   = { Drag = { streak = 1, button = "Left" } },
    mods    = "SHIFT",
    action  = wezterm.action.ExtendSelectionToMouseCursor("Cell"),
  },
  {
    event   = { Up = { streak = 1, button = "Left" } },
    mods    = "SHIFT",
    action  = wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor("Clipboard"),
  },
}

config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 900 }

config.launch_menu = {
  { label = "PowerShell (WezTerm bootstrap)", args = config.default_prog },
  { label = "Windows PowerShell", args = { "powershell.exe", "-NoLogo", "-NoProfile" } },
  { label = "Command Prompt", args = { "cmd.exe" } },
}

local keys_ok, keys_table = pcall(dofile, config_dir .. "\\keys.lua")
config.keys = (keys_ok and type(keys_table) == "table") and keys_table or {}

return config
