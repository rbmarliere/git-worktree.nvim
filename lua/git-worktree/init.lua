---@toc git-worktree.contents

---@mod intro Introduction
---@brief [[
--- A plugin that helps to use git worktree operations, create, switch, delete and move in neovim.
---@brief ]]
---
---@mod git-worktree

---@mod git-worktree.telescope
---@brief [[
--- To get telescope-file-browser loaded and working with telescope,
--- you need to call load_extension, somewhere after setup function:
--- <code>
--- require("telescope").load_extension("git_worktree")
---@brief ]]

---@brief [[
---@brief ]]

local M = {}

local Worktree = require('git-worktree.worktree')

--Switch the current worktree
---@param path string?
function M.switch_worktree(path)
    Worktree.switch(path)
end

--Create a worktree
---@param path string
---@param branch string
---@param upstream? string
function M.create_worktree(path, branch, upstream)
    Worktree.create(path, branch, upstream)
end

--Delete a worktree
---@param path string
---@param force boolean
---@param opts any
function M.delete_worktree(path, force, opts)
    Worktree.delete(path, force, opts)
end

--Move a worktree
---@param path string
---@param new_path string
---@param opts any
function M.move_worktree(path, new_path, opts)
    Worktree.move(path, new_path, opts)
end

return M
