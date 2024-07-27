---@toc git-worktree.contents

---@mod intro Introduction
---@brief [[
--- A plugin  that helps to use git worktree operations, create, switch, and delete in neovim.
---@brief ]]
---
---@mod git-worktree

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

return M
