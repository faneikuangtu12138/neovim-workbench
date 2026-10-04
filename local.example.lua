-- Copy this file to local.lua in your Neovim configuration directory.
-- local.lua is personal configuration and must not be committed.
return {
  -- Standard Nerd Font Mono by default. Enable only after installing all four
  -- ForgeMono Geometry 6 NF styles and matching your terminal's cell height.
  round_tabs = false,

  -- Optional startup default for the geometry glyphs. A :UiLineHeight cache
  -- takes priority, so querying/changing the terminal height survives restart.
  -- This setting does not change any terminal application's font or line height.
  -- line_height = 1.42,

  terminal_ui = {
    enabled = true,
    -- :UiLineHeight operates only from WSL inside Windows Terminal.
    -- Set the name of your WSL profile. If names repeat, specify its GUID.
    profile = "Fedora",
    -- guid = "{YOUR-WINDOWS-TERMINAL-PROFILE-GUID}",
    -- Use a WSL path for Preview/unpackaged Terminal or custom settings files.
    -- settings = "/mnt/c/path/to/WindowsTerminal/settings.json",
    python = "python3",
    -- state = "/path/to/workbench-ui.json",
    -- backup_dir = "/path/to/terminal-ui-backups",
  },
}
