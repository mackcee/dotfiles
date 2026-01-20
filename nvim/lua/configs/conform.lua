local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    solidity = { "forge_fmt" },

    -- ✅ markdown
    markdown = { "prettier" },
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

    -- ✅ prettier formatter (Conform usually has this built-in,
    -- but adding explicitly makes it unambiguous)
    prettier = {
      command = "prettier",
      args = { "--stdin-filepath", "$FILENAME" },
      stdin = true,
    },
  },
}

return options
