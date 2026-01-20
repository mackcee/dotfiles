return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre", -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "mg979/vim-visual-multi",
    branch = "master",
    lazy = false,
  },
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require "lint"

      lint.linters_by_ft = {
        markdown = { "markdownlint-cli2" },
      }

      vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter", "InsertLeave" }, {
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },

  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "<leader>s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash",
      },
      {
        "<leader>S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash Treesitter",
      },
    },
  },

  {
    "kylechui/nvim-surround",
    version = "^3.0.0", -- Use for stability; omit to use `main` branch for the latest features
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup {
        -- Configuration here, or leave empty to use defaults
      }
    end,
  },

  {
    "mikesmithgh/kitty-scrollback.nvim",
    enabled = true,
    lazy = true,
    cmd = {
      "KittyScrollbackGenerateKittens",
      "KittyScrollbackCheckHealth",
      "KittyScrollbackGenerateCommandLineEditing",
    },
    event = { "User KittyScrollbackLaunch" },
    -- version = '*', -- latest stable version, may have breaking changes if major version changed
    version = "^6.0.0", -- pin major version, include fixes and features that do not have breaking changes

    config = function()
      require("kitty-scrollback").setup()
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    opts = function(_, conf)
      local actions = require "telescope.actions"
      local action_state = require "telescope.actions.state"

      local function get_path(entry)
        return entry.path or entry.filename
      end

      conf.defaults.mappings.i = {
        ["<C-j>"] = actions.move_selection_next,
        ["<Esc>"] = actions.close,

        -- 📋 full absolute path
        ["<C-y>"] = function(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          local path = get_path(entry)
          vim.fn.setreg("+", path)
          vim.notify("Yanked full path:\n" .. path)
        end,

        -- 📎 relative path
        ["<C-r>"] = function(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          local path = vim.fn.fnamemodify(get_path(entry), ":.")
          vim.fn.setreg("+", path)
          vim.notify("Yanked relative path:\n" .. path)
        end,

        -- 📄 filename only
        ["<C-f>"] = function(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          local path = vim.fn.fnamemodify(get_path(entry), ":t")
          vim.fn.setreg("+", path)
          vim.notify("Yanked filename:\n" .. path)
        end,

        -- 📁 directory only
        ["<C-d>"] = function(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          local path = vim.fn.fnamemodify(get_path(entry), ":h")
          vim.fn.setreg("+", path)
          vim.notify("Yanked directory:\n" .. path)
        end,
      }

      return conf
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  -- {
  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },
}
