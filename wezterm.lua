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
local current_style_lua = config_dir .. "\\current-style.lua"
local current_gpu_lua = config_dir .. "\\current-gpu.lua"

-- Per-profile state file support: if WEZTERM_PROFILE is set and not "default",
-- load profile-specific Lua state files (e.g. current-bg-work.lua)
local active_profile = os.getenv("WEZTERM_PROFILE") or "default"
if active_profile ~= "" and active_profile ~= "default" then
  local profile_bg = config_dir .. "\\current-bg-" .. active_profile .. ".lua"
  local profile_opacity = config_dir .. "\\current-opacity-" .. active_profile .. ".lua"
  local profile_style = config_dir .. "\\current-style-" .. active_profile .. ".lua"
  local profile_gpu = config_dir .. "\\current-gpu-" .. active_profile .. ".lua"
  if file_exists(profile_bg) then current_bg_lua = profile_bg end
  if file_exists(profile_opacity) then current_opacity_lua = profile_opacity end
  if file_exists(profile_style) then current_style_lua = profile_style end
  if file_exists(profile_gpu) then current_gpu_lua = profile_gpu end
end

local cursor_styles = {
  "SteadyBlock",
  "BlinkingBlock",
  "BlinkingBar",
  "BlinkingUnderline",
}

local cursor_style_labels = {
  SteadyBlock = "BLOCK",
  BlinkingBlock = "B-BLOCK",
  BlinkingBar = "B-BAR",
  BlinkingUnderline = "B-ULINE",
}

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

local function with_extension(path, ext)
  local stem = path:match("^(.*)%.[^%.]+$")
  if not stem then
    return path .. ext
  end
  return stem .. ext
end

local function resolve_optimized_background_path(path)
  if not path or path == "" then
    return nil
  end

  local avif_path = with_extension(path, ".avif")
  if avif_path ~= path and file_exists(avif_path) then
    return avif_path
  end

  local webp_path = with_extension(path, ".webp")
  if webp_path ~= path and file_exists(webp_path) then
    return webp_path
  end

  return path
end

local function clamp_number(value, min_value, max_value)
  return math.max(min_value, math.min(max_value, value))
end

local function load_opacity(default_value, adaptive_delta)
  local base_value = default_value
  if file_exists(current_opacity_lua) then
    local ok, value = pcall(dofile, current_opacity_lua)
    if ok and type(value) == "number" then
      base_value = value
    end
  end

  return clamp_number(base_value + (adaptive_delta or 0), 0, 1)
end

local function load_style_state()
  if not file_exists(current_style_lua) then
    return nil
  end

  local ok, value = pcall(dofile, current_style_lua)
  if not ok or type(value) ~= "table" then
    return nil
  end

  local result = {}
  if type(value.style) == "string" and value.style ~= "" then
    result.style = value.style
  end
  if type(value.scene) == "string" and value.scene ~= "" then
    result.scene = value.scene
  end
  if type(value.bg_hint) == "string" and value.bg_hint ~= "" then
    result.bg_hint = value.bg_hint
  end

  return result
end

local function load_gpu_state()
  local default_state = {
    min_percent = 10,
  }

  if not file_exists(current_gpu_lua) then
    return default_state
  end

  local ok, value = pcall(dofile, current_gpu_lua)
  if not ok or type(value) ~= "table" then
    return default_state
  end

  local result = {
    min_percent = default_state.min_percent,
  }

  if type(value.min_percent) == "number" then
    result.min_percent = clamp_number(value.min_percent, 0, 100)
  end

  return result
end

local style_presets = {
  neon_glass = {
    window = {
      background_opacity = 0.88,
      text_background_opacity = 0.88,
    },
    background = {
      brightness = 0.26,
      saturation = 0.88,
      overlay_color = "#0b1220",
      overlay_opacity_default = 0.72,
    },
    frame = {
      active_titlebar_bg = "#0b1220",
      inactive_titlebar_bg = "#09101c",
      active_titlebar_fg = "#bff9ff",
      inactive_titlebar_fg = "#6f829f",
      active_titlebar_border_bottom = "#22456b",
      inactive_titlebar_border_bottom = "#152a43",
      button_fg = "#bff9ff",
      button_bg = "#15253c",
      button_hover_fg = "#07111d",
      button_hover_bg = "#38e7ff",
      border_left_width = "3px",
      border_right_width = "3px",
      border_top_height = "3px",
      border_bottom_height = "3px",
      border_left_color = "#38e7ff",
      border_right_color = "#8b5cf6",
      border_top_color = "#38e7ff",
      border_bottom_color = "#8b5cf6",
    },
    tab = {
      active_fg = "#f2feff",
      active_bg = "#24496e",
      inactive_fg = "#9badc6",
      inactive_bg = "#121d31",
      hover_fg = "#e6f6ff",
      hover_bg = "#1a304d",
    },
    status = {
      base_bg = "#09101c",
      ws_fg = "#f8fcff",
      ws_bg = "#1e40af",
      cwd_fg = "#ecfeff",
      cwd_bg = "#0f766e",
      proc_fg = "#e2e8f0",
      proc_bg = "#364152",
      dim_fg = "#6f829f",
    },
  },
  ice_glass = {
    window = {
      background_opacity = 0.92,
      text_background_opacity = 0.92,
    },
    background = {
      brightness = 0.30,
      saturation = 0.86,
      overlay_color = "#0b1521",
      overlay_opacity_default = 0.66,
    },
    frame = {
      active_titlebar_bg = "#0d1b2a",
      inactive_titlebar_bg = "#0b1521",
      active_titlebar_fg = "#e0f2fe",
      inactive_titlebar_fg = "#7f93a8",
      active_titlebar_border_bottom = "#2a4f70",
      inactive_titlebar_border_bottom = "#1b3248",
      button_fg = "#e0f2fe",
      button_bg = "#1a2e43",
      button_hover_fg = "#0b1521",
      button_hover_bg = "#67e8f9",
      border_left_width = "3px",
      border_right_width = "3px",
      border_top_height = "3px",
      border_bottom_height = "3px",
      border_left_color = "#67e8f9",
      border_right_color = "#38bdf8",
      border_top_color = "#67e8f9",
      border_bottom_color = "#38bdf8",
    },
    tab = {
      active_fg = "#f0f9ff",
      active_bg = "#27445e",
      inactive_fg = "#8ba1b8",
      inactive_bg = "#152438",
      hover_fg = "#e0f2fe",
      hover_bg = "#1f334a",
    },
    status = {
      base_bg = "#0b1521",
      ws_fg = "#f0f9ff",
      ws_bg = "#0369a1",
      cwd_fg = "#ecfeff",
      cwd_bg = "#0f766e",
      proc_fg = "#e2e8f0",
      proc_bg = "#334155",
      dim_fg = "#64748b",
    },
  },
  mint_glass = {
    window = {
      background_opacity = 0.90,
      text_background_opacity = 0.90,
    },
    background = {
      brightness = 0.29,
      saturation = 0.90,
      overlay_color = "#0b1f1a",
      overlay_opacity_default = 0.67,
    },
    frame = {
      active_titlebar_bg = "#0f1f1a",
      inactive_titlebar_bg = "#0b1713",
      active_titlebar_fg = "#d1fae5",
      inactive_titlebar_fg = "#6b8f85",
      active_titlebar_border_bottom = "#215f54",
      inactive_titlebar_border_bottom = "#173f38",
      button_fg = "#d1fae5",
      button_bg = "#18352f",
      button_hover_fg = "#08110f",
      button_hover_bg = "#34d399",
      border_left_width = "3px",
      border_right_width = "3px",
      border_top_height = "3px",
      border_bottom_height = "3px",
      border_left_color = "#34d399",
      border_right_color = "#2dd4bf",
      border_top_color = "#34d399",
      border_bottom_color = "#2dd4bf",
    },
    tab = {
      active_fg = "#f0fdf4",
      active_bg = "#21544a",
      inactive_fg = "#95b8ae",
      inactive_bg = "#132a24",
      hover_fg = "#dcfce7",
      hover_bg = "#1a3b33",
    },
    status = {
      base_bg = "#0b1713",
      ws_fg = "#f0fdf4",
      ws_bg = "#0f766e",
      cwd_fg = "#ecfdf5",
      cwd_bg = "#047857",
      proc_fg = "#d1fae5",
      proc_bg = "#2f4f46",
      dim_fg = "#6b8f85",
    },
  },
}

local scene_presets = {
  focus = {
    window_background_opacity = 0.93,
    text_background_opacity = 0.90,
    overlay_opacity = 0.75,
    adaptive_overlay_strength = 0.10,
  },
  cinematic = {
    window_background_opacity = 0.89,
    text_background_opacity = 0.86,
    overlay_opacity = 0.69,
    adaptive_overlay_strength = 0.08,
  },
  showcase = {
    window_background_opacity = 0.84,
    text_background_opacity = 0.82,
    overlay_opacity = 0.61,
    adaptive_overlay_strength = 0.06,
  },
}

local function infer_bg_hint_from_path(path)
  if not path or path == "" then
    return "neutral"
  end

  local lowered = string.lower(path)
  if lowered:find("bright", 1, true)
      or lowered:find("light", 1, true)
      or lowered:find("snow", 1, true)
      or lowered:find("day", 1, true)
      or lowered:find("white", 1, true)
      or lowered:find("sun", 1, true) then
    return "bright"
  end

  if lowered:find("dark", 1, true)
      or lowered:find("night", 1, true)
      or lowered:find("moon", 1, true)
      or lowered:find("space", 1, true)
      or lowered:find("black", 1, true)
      or lowered:find("neon", 1, true) then
    return "dark"
  end

  return "neutral"
end

local function overlay_delta_from_hint(bg_hint, strength)
  if bg_hint == "bright" then
    return strength
  end
  if bg_hint == "dark" then
    return -strength
  end
  return 0
end

local style_state = load_style_state() or {}
local env_style_name = os.getenv("WEZTERM_GLASS_STYLE")
local env_scene_name = os.getenv("WEZTERM_GLASS_SCENE")

local active_style_name = "neon_glass"
if env_style_name and style_presets[env_style_name] then
  active_style_name = env_style_name
elseif style_state.style and style_presets[style_state.style] then
  active_style_name = style_state.style
end

local active_scene_name = "focus"
if env_scene_name and scene_presets[env_scene_name] then
  active_scene_name = env_scene_name
elseif style_state.scene and scene_presets[style_state.scene] then
  active_scene_name = style_state.scene
end

local active_style = style_presets[active_style_name] or style_presets.neon_glass
local active_scene = scene_presets[active_scene_name] or scene_presets.focus

local active_bg_path = load_background_path()
local optimized_bg_path = resolve_optimized_background_path(active_bg_path)
local bg_hint = style_state.bg_hint or infer_bg_hint_from_path(active_bg_path)
local adaptive_overlay_delta = overlay_delta_from_hint(bg_hint, active_scene.adaptive_overlay_strength)
local gpu_state = load_gpu_state()

wezterm.GLOBAL.bg_mode = wezterm.GLOBAL.bg_mode or (optimized_bg_path and "legacy" or "solid")
wezterm.GLOBAL.cursor_style_index = wezterm.GLOBAL.cursor_style_index or 2

local function build_background(mode)
  if mode == "legacy" and optimized_bg_path then
    return {
      {
        source = { File = optimized_bg_path },
        width = "100%",
        height = "100%",
        hsb = {
          brightness = active_style.background.brightness,
          saturation = active_style.background.saturation,
        },
      },
      {
        source = { Color = active_style.background.overlay_color },
        width = "100%",
        height = "100%",
        opacity = load_opacity(active_scene.overlay_opacity or active_style.background.overlay_opacity_default, adaptive_overlay_delta),
      },
    }
  end

  return {
    {
      source = {
        Gradient = {
          orientation = { Linear = { angle = 28.0 } },
          colors = { "#070b10", "#081018", "#0a0d17", "#070b10" },
        },
      },
      width = "100%",
      height = "100%",
      opacity = 1.0,
    },
  }
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
  return text:sub(1, max_len - 1) .. "…"
end

local status_line_cache = wezterm.GLOBAL.status_line_cache
if not status_line_cache then
  status_line_cache = {
    { Background = { Color = "#09101c" } },
    { Foreground = { Color = "#6f829f" } },
    { Text = " " },
    { Background = { Color = "#1e40af" } },
    { Foreground = { Color = "#f8fcff" } },
    { Text = " WS " },
    { Background = { Color = "#09101c" } },
    { Text = " " },
    { Background = { Color = "#0f766e" } },
    { Foreground = { Color = "#ecfeff" } },
    { Text = " CWD " },
    { Background = { Color = "#09101c" } },
    { Text = " " },
    { Background = { Color = "#364152" } },
    { Foreground = { Color = "#e2e8f0" } },
    { Text = " PROC " },
    { Background = { Color = "#09101c" } },
    { Text = " " },
    { Background = { Color = "#14532d" } },
    { Foreground = { Color = "#ecfdf5" } },
    { Text = " CUR " },
    { Background = { Color = "#09101c" } },
    { Text = " " },
  }
  wezterm.GLOBAL.status_line_cache = status_line_cache
end

local left_status_cache = wezterm.GLOBAL.left_status_cache
if not left_status_cache then
  left_status_cache = {
    { Background = { Color = "#070d16" } },
    { Foreground = { Color = "#1ef2ff" } },
    { Text = "  " },
    { Background = { Color = "#0d1b32" } },
    { Foreground = { Color = "#78f3ff" } },
    { Text = " 󰖭 " },
    { Background = { Color = "#132744" } },
    { Foreground = { Color = "#a4f7ff" } },
    { Text = " 󰖯 " },
    { Background = { Color = "#183359" } },
    { Foreground = { Color = "#d6faff" } },
    { Text = " 󰅖 " },
    { Background = { Color = "#070d16" } },
    { Foreground = { Color = "#1ef2ff" } },
    { Text = "  " },
  }
  wezterm.GLOBAL.left_status_cache = left_status_cache
end

wezterm.on("update-status", function(window, pane)
  local cwd     = pane_cwd(pane)
  local process = basename(pane:get_foreground_process_name() or "")
  local ws      = truncate_text(window:active_workspace(), 12)
  local cwd_lbl = truncate_text(cwd ~= "" and basename(cwd) or "~", 18)
  local proc_lbl = truncate_text(process, 16)
  local cursor_style = cursor_styles[wezterm.GLOBAL.cursor_style_index or 2] or "BlinkingBlock"
  local cursor_lbl = cursor_style_labels[cursor_style] or cursor_style
  local status_colors = active_style.status
  local tab_colors = active_style.tab

  local items = status_line_cache
  items[1].Background.Color = status_colors.base_bg
  items[2].Foreground.Color = status_colors.dim_fg
  items[4].Background.Color = status_colors.ws_bg
  items[5].Foreground.Color = status_colors.ws_fg
  items[6].Text = " " .. ws .. " "
  items[7].Background.Color = status_colors.base_bg
  items[9].Background.Color = status_colors.cwd_bg
  items[10].Foreground.Color = status_colors.cwd_fg
  items[11].Text = " " .. cwd_lbl .. " "
  items[12].Background.Color = status_colors.base_bg
  items[14].Background.Color = status_colors.proc_bg
  items[15].Foreground.Color = status_colors.proc_fg
  items[16].Text = " " .. proc_lbl .. " "
  items[17].Background.Color = status_colors.base_bg
  items[19].Background.Color = tab_colors.active_bg
  items[20].Foreground.Color = tab_colors.active_fg
  items[21].Text = " " .. cursor_lbl .. " "
  items[22].Background.Color = status_colors.base_bg

  local left_items = left_status_cache
  left_items[2].Foreground.Color = tab_colors.active_bg
  left_items[4].Background.Color = status_colors.base_bg
  left_items[7].Background.Color = tab_colors.inactive_bg
  left_items[10].Background.Color = tab_colors.hover_bg
  left_items[13].Foreground.Color = tab_colors.active_bg

  window:set_left_status(wezterm.format(left_items))
  window:set_right_status(wezterm.format(items))
end)

wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
  local cwd = pane_cwd(tab.active_pane)
  local process = basename(tab.active_pane.foreground_process_name or "shell")
  local cwd_label = truncate_text(cwd ~= "" and basename(cwd) or "~", 14)
  local process_label = truncate_text(process ~= "" and process or "shell", 12)
  local label = cwd_label

  if process_label ~= "" and process_label ~= cwd_label then
    label = cwd_label .. " · " .. process_label
  end

  local max_chars = math.max(6, max_width - 8)
  label = truncate_text(label, max_chars)
  local tab_colors = active_style.tab
  local fg = tab.is_active and tab_colors.active_fg or tab_colors.inactive_fg
  local bg = tab.is_active and tab_colors.active_bg or tab_colors.inactive_bg
  local prefix = tab.is_active and "󰮔 " or ""

  if hover and not tab.is_active then
    fg = tab_colors.hover_fg
    bg = tab_colors.hover_bg
  end

  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Attribute = { Intensity = tab.is_active and "Bold" or "Normal" } },
    { Attribute = { Italic = tab.is_active } },
    { Text = "  " .. prefix .. label .. "  " },
  }
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

wezterm.on("toggle-bg-mode", function(window, pane)
  wezterm.GLOBAL.bg_mode = wezterm.GLOBAL.bg_mode == "legacy" and "solid" or "legacy"
  local overrides = window:get_config_overrides() or {}
  overrides.background = build_background(wezterm.GLOBAL.bg_mode)
  window:set_config_overrides(overrides)
end)

wezterm.on("cycle-cursor-style", function(window, pane)
  local next_index = (wezterm.GLOBAL.cursor_style_index or 1) + 1
  if next_index > #cursor_styles then
    next_index = 1
  end
  wezterm.GLOBAL.cursor_style_index = next_index
  local overrides = window:get_config_overrides() or {}
  overrides.default_cursor_style = cursor_styles[next_index]
  window:set_config_overrides(overrides)
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
  { family = "CaskaydiaCove Nerd Font Mono", weight = "Regular" },
  { family = "GeistMono Nerd Font", weight = "Regular" },
  { family = "Consolas" },
})
config.font_size = 13
config.line_height = 1.08
config.harfbuzz_features = { "calt", "clig", "liga", "ss01", "ss02" }
config.freetype_load_target = "Normal"
config.freetype_render_target = "HorizontalLcd"

config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.win32_system_backdrop = "Mica"
config.window_padding = { left = 12, right = 12, top = 9, bottom = 9 }
config.initial_cols = 150
config.initial_rows = 42
config.adjust_window_size_when_changing_font_size = false

config.color_scheme = "Catppuccin Mocha"
config.window_background_opacity = active_scene.window_background_opacity
config.text_background_opacity = active_scene.text_background_opacity
config.background = build_background(wezterm.GLOBAL.bg_mode)

local gpu_bias_high = gpu_state.min_percent >= 10
local ok_gpus, gpus = pcall(wezterm.gui.enumerate_gpus)
if ok_gpus and gpus and #gpus > 0 then
  config.front_end = "WebGpu"
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
  config.webgpu_power_preference = gpu_bias_high and "HighPerformance" or "LowPower"
else
  config.front_end = "OpenGL"
end

config.colors = {
  split = "#14c8ff",
  tab_bar = {
    background = "#050a14",
    inactive_tab_edge = active_style.tab.hover_bg,
    active_tab = {
      bg_color = "#0f2d57",
      fg_color = "#e6fbff",
      intensity = "Bold",
      italic = true,
    },
    inactive_tab = {
      bg_color = "#091426",
      fg_color = "#8da7c4",
    },
    inactive_tab_hover = {
      bg_color = "#17365e",
      fg_color = "#ddf9ff",
      italic = true,
    },
    new_tab = {
      bg_color = "#0a1324",
      fg_color = "#73e7ff",
    },
    new_tab_hover = {
      bg_color = "#194066",
      fg_color = "#effdff",
      italic = true,
    },
  },
}
config.inactive_pane_hsb = {
  saturation = 0.90,
  brightness = 0.92,
}

-- Keep background tabs alive: prevent Windows from throttling unfocused panes.
-- WezTerm always reads PTY for all panes, but Windows may throttle timer resolution
-- for background windows, causing long-running processes to appear stalled.
-- The real fix is in wezterm-bootstrap.ps1 (process priority + timer keepalive).

config.window_frame = {
  font = active_style.frame.font,
  font_size = active_style.frame.font_size,
  active_titlebar_bg = "#050a14",
  inactive_titlebar_bg = "#050914",
  active_titlebar_fg = "#e8fbff",
  inactive_titlebar_fg = "#93a5bf",
  border_left_width = "4px",
  border_right_width = "4px",
  border_bottom_height = "4px",
  border_top_height = "4px",
  border_left_color = "#14c8ff",
  border_right_color = "#14c8ff",
  border_bottom_color = "#14c8ff",
  border_top_color = "#14c8ff",
  button_fg = "#f3feff",
  button_bg = "#0e2748",
  button_hover_fg = "#f4ffff",
  button_hover_bg = "#1f4b76",
}

config.integrated_title_buttons = { "Hide", "Maximize", "Close" }
config.integrated_title_button_style = "Gnome"
config.integrated_title_button_alignment = "Right"
config.integrated_title_button_color = "#d9f9ff"

config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = true
config.show_new_tab_button_in_tab_bar = false
config.tab_max_width = 32
config.scrollback_lines = 12000
config.default_cursor_style = cursor_styles[wezterm.GLOBAL.cursor_style_index or 2]
config.cursor_blink_rate = 420
config.cursor_blink_ease_in = "EaseOut"
config.cursor_blink_ease_out = "EaseOut"
if gpu_bias_high then
  config.animation_fps = 30
  config.max_fps = 165
else
  config.animation_fps = 24
  config.max_fps = 120
end
config.status_update_interval = 1500
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
table.insert(config.keys, {
  key = "b",
  mods = "CTRL|SHIFT",
  action = wezterm.action.EmitEvent("toggle-bg-mode"),
})
table.insert(config.keys, {
  key = "o",
  mods = "CTRL|SHIFT",
  action = wezterm.action.EmitEvent("cycle-cursor-style"),
})

return config

