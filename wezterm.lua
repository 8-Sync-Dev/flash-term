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
  return path:match("([^\\]+)$") or path
end

wezterm.on("update-status", function(window, pane)
  local cwd = pane_cwd(pane)
  local process = basename(pane:get_foreground_process_name() or "")
  local workspace = window:active_workspace()

  window:set_right_status(wezterm.format({
    { Foreground = { Color = "#a6adc8" } },
    { Text = "  " .. workspace .. "  " },
    { Foreground = { Color = "#89b4fa" } },
    { Text = cwd ~= "" and basename(cwd) or "~" },
    { Foreground = { Color = "#6c7086" } },
    { Text = "  " .. process .. "  " },
  }))
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
config.font_size = 12.5
config.line_height = 1.08
config.freetype_load_target = "Light"
config.freetype_render_target = "HorizontalLcd"

config.window_decorations = "TITLE | RESIZE"
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
config.webgpu_power_preference = "HighPerformance"

config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.show_new_tab_button_in_tab_bar = false
config.scrollback_lines = 12000
config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 650
config.animation_fps = 60
config.max_fps = 120
config.enable_scroll_bar = false
config.audible_bell = "Disabled"
config.check_for_updates = false
config.enable_kitty_keyboard = false
config.enable_csi_u_key_encoding = false

config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 900 }

config.launch_menu = {
  { label = "PowerShell (WezTerm bootstrap)", args = config.default_prog },
  { label = "Windows PowerShell", args = { "powershell.exe", "-NoLogo", "-NoProfile" } },
  { label = "Command Prompt", args = { "cmd.exe" } },
}

local keys_ok, keys_table = pcall(dofile, config_dir .. "\\keys.lua")
config.keys = (keys_ok and type(keys_table) == "table") and keys_table or {}

return config
