local M = {}

local function get_md_target_on_line(line)
  -- First markdown link target on the line: [text](target)
  return line:match "%b[]%(([^)]+)%)"
end

local function parse_target(target)
  -- target may be: path#L22 or path#L22-L29
  local path, frag = target:match "^(.-)#(.*)$"
  path = path or target

  local l1 = nil
  if frag then
    l1 = frag:match "^L(%d+)"
  end

  return path, l1
end

function M.follow_with_line()
  local line = vim.api.nvim_get_current_line()

  local target = get_md_target_on_line(line)
  if not target then
    -- fallback: bare filepath or filepath#Lxx under cursor
    target = vim.fn.expand "<cfile>"
    if not target or target == "" then
      vim.notify("No link/file under cursor", vim.log.levels.WARN)
      return
    end
  end

  local path, l1 = parse_target(target)

  -- Resolve relative to the current markdown file's directory
  local base = vim.fn.expand "%:p:h"
  local full = vim.fn.fnamemodify(base .. "/" .. path, ":p")

  vim.cmd("edit " .. vim.fn.fnameescape(full))

  if l1 then
    vim.api.nvim_win_set_cursor(0, { tonumber(l1), 0 })
  end
end

return M
