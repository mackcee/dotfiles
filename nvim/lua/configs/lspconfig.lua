require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "rust_analyzer", "solidity_ls", "marksman" }
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers
