
local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    solidity = { "forge_fmt" },
  },

  format_on_save = {
    timeout_ms = 5000,
    lsp_fallback = false,
  },

  formatters = {
    forge_fmt = {
      command = "forge",
      args = { "fmt", "--raw", "-" },
      stdin = true,
    },
  },
}

return options
