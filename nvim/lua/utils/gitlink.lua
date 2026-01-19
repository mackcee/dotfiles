local M = {}

local function trim(s)
  return (s:gsub("%s+$", ""))
end

local function git_root_for_file(file_abs)
  local dir = vim.fn.fnamemodify(file_abs, ":h")
  local out = vim.fn.system("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")
  out = trim(out)
  if out == "" then
    return nil
  end
  return out
end

function M.copy_link(opts)
  opts = opts or {}

  local file_abs = vim.fn.expand "%:p"
  local root = git_root_for_file(file_abs)

  if not root then
    vim.notify("Not inside a git repo (from file dir)", vim.log.levels.ERROR)
    return
  end

  -- make repo-relative path
  local rel = file_abs:gsub("^" .. vim.pesc(root) .. "/", "")

  -- line(s)
  local s = vim.fn.line "v"
  local e = vim.fn.line "."
  if s > e then
    s, e = e, s
  end

  local link
  if s == e then
    link = string.format("%s#L%d", rel, s)
  else
    link = string.format("%s#L%d-L%d", rel, s, e)
  end

  if opts.markdown then
    link = string.format("[%s](%s)", link, link)
  end

  vim.fn.setreg("+", link)
  vim.notify("Copied: " .. link)
end

return M
