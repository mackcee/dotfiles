-- Colorscheme: Omarchy's active theme when this machine runs Omarchy,
-- Tokyo Night everywhere else.
--
-- Omarchy ships this file as a relative symlink into ~/.local/state/omarchy.
-- That link breaks once the nvim folder lives in ~/dotfiles, so this loader
-- reads the same file instead. Omarchy's hot-reload plugin re-requires this
-- module on theme change, so live theme switching keeps working.
local omarchy_theme = vim.fn.expand("~/.local/state/omarchy/current/theme/neovim.lua")

if vim.uv.fs_stat(omarchy_theme) then
  local ok, spec = pcall(dofile, omarchy_theme)
  if ok and type(spec) == "table" then
    return spec
  end
end

return {
  { "folke/tokyonight.nvim", priority = 1000 },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight-night" } },
}
