require "nvchad.mappings"
local gitlink = require "utils.gitlink"
local mdlink = require "utils.mdlink"

--madd yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

map("n", "gl", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<A-j>", ":m .+1<CR>==", { desc = "Move line down" })
map("n", "<A-k>", ":m .-2<CR>==", { desc = "Move line up" })
map("n", "<A-n>", ":NvimTreeToggle<CR>", { desc = "Toggle tree view" })
map("n", "<leader>a", "ggVG", { desc = "Select all text" })
-- Terminal escape
map("t", "<A-e>", [[<C-\><C-n>]], {
  desc = "Exit terminal mode",
  noremap = true,
  silent = true,
})

--remap redo to U
map("n", "U", "<C-r>", { desc = "Redo" })

--remove standard mapping for ctrl-n (treeviewer)
map("n", "<C-n>", "<Plug>(VM-Find-Under)", { desc = "VM Find Under" })
map("x", "<C-n>", "<Plug>(VM-Find-Under)", { desc = "VM Find Under" })

-- Terminal window navigation
map("t", "<C-h>", [[<C-\><C-n><C-w>h]], { silent = true })
map("t", "<C-j>", [[<C-\><C-n><C-w>j]], { silent = true })
map("t", "<C-k>", [[<C-\><C-n><C-w>k]], { silent = true })
map("t", "<C-l>", [[<C-\><C-n><C-w>l]], { silent = true })

-- plain link
map({ "n", "v" }, "<leader>yl", function()
  gitlink.copy_link()
end, { desc = "Copy file:line link" })

-- markdown link
map({ "n", "v" }, "<leader>yL", function()
  gitlink.copy_link { markdown = true }
end, { desc = "Copy markdown file:line link" })

map("n", "gF", mdlink.follow_with_line, { desc = "Follow file link with line number" })

map("n", "<leader>rm", function()
  -- clear cached modules
  package.loaded["mappings"] = nil
  package.loaded["utils.gitlink"] = nil
  package.loaded["utils.mdlink"] = nil

  -- re-require mappings
  require "mappings"

  vim.notify "Mappings reloaded"
end, { desc = "Reload mappings" })

-- Insert blank line(s) below without leaving normal mode
map("n", "<leader>o", function()
  local n = vim.v.count1
  -- put n empty lines below
  vim.cmd("put =repeat([''], " .. n .. ")")
end, { desc = "Insert blank line(s) below" })

-- Insert blank line(s) above without leaving normal mode
map("n", "<leader>O", function()
  local n = vim.v.count1
  -- put n empty lines above
  vim.cmd("put! =repeat([''], " .. n .. ")")
end, { desc = "Insert blank line(s) above" })
