local Job = require('plenary.job')
local Path = require('plenary.path')
local Log = require('git-worktree.logger')

---@class GitWorktreeGitOps
local M = {}

-- A lot of this could be cleaned up if there was better job -> job -> function
-- communication.  That should be doable here in the near future
---
---@param path_str string path to the worktree to check. if relative, then path from the git root dir
---@param cb any
function M.has_worktree(path_str, cb)
    local found = false
    local path = Path:new(path_str)

    if path_str == '.' then
        path_str = vim.loop.cwd()
        path = Path:new(path_str)
    end

    local job = Job:new {
        command = 'git',
        args = { 'worktree', 'list' },
        on_stdout = function(_, data)
            local list_data = {}
            for section in data:gmatch('%S+') do
                table.insert(list_data, section)
            end

            data = list_data[1]

            local start
            if path:is_absolute() then
                start = data == path_str
            else
                local worktree_path = Path:new(string.format('%s' .. Path.path.sep .. '%s', vim.loop.cwd(), path_str))
                worktree_path = worktree_path:absolute()
                start = data == worktree_path
            end

            -- TODO: This is clearly a hack (do not think we need this anymore?)
            --local start_with_head = string.find(data, string.format('[heads/%s]', path), 1, true)
            found = found or start
            Log.debug('found: %s', found)
        end,
        cwd = vim.loop.cwd(),
    }

    job:after(function()
        Log.debug('calling after')
        cb(found)
    end)

    Log.debug('Checking for worktree %s', path)
    job:start()
end

--- @return string|nil
function M.gitroot_dir()
    local job = Job:new {
        command = 'git',
        args = { 'rev-parse', '--path-format=absolute', '--git-common-dir' },
        cwd = vim.loop.cwd(),
        on_stderr = function(_, data)
            Log.error('ERROR: ' .. data)
        end,
    }

    local stdout, code = job:sync()
    if code ~= 0 then
        Log.error(
            'Error in determining the git root dir: code:'
                .. tostring(code)
                .. ' out: '
                .. table.concat(stdout, '')
                .. '.'
        )
        return nil
    end

    return table.concat(stdout, '')
end

--- @return string|nil
function M.toplevel_dir()
    local job = Job:new {
        command = 'git',
        args = { 'rev-parse', '--path-format=absolute', '--show-toplevel' },
        cwd = vim.loop.cwd(),
        on_stderr = function(_, data)
            Log.error('ERROR: ' .. data)
        end,
    }

    local stdout, code = job:sync()
    if code ~= 0 then
        Log.error(
            'Error in determining the git root dir: code:'
                .. tostring(code)
                .. ' out: '
                .. table.concat(stdout, '')
                .. '.'
        )
        return nil
    end

    return table.concat(stdout, '')
end

function M.has_branch(branch, remotes, cb)
    local found = false

    local args = { 'branch' }
    if remotes then
        table.insert(args, '--remotes')
    end

    local job = Job:new {
        command = 'git',
        args = args,
        on_stdout = function(_, data)
            -- remove  markere on current branch
            data = data:gsub('*', '')
            data = vim.trim(data)
            found = found or data == branch
        end,
        cwd = vim.loop.cwd(),
    }

    -- TODO: I really don't want status's spread everywhere... seems bad
    job:after(function()
        cb(found)
    end):start()
end

--- @param path string
--- @param branch string
--- @param found_branch boolean
--- @param upstream string
--- @param found_upstream boolean
--- @return Job
function M.create_worktree_job(path, branch, found_branch, upstream, found_upstream)
    local worktree_add_cmd = 'git'
    local worktree_add_args = { 'worktree', 'add' }

    if not found_branch then
        table.insert(worktree_add_args, '-b')
        table.insert(worktree_add_args, branch)
        table.insert(worktree_add_args, path)
    else
        table.insert(worktree_add_args, path)
        table.insert(worktree_add_args, branch)
    end

    if found_upstream then
        table.insert(worktree_add_args, '--track')
        table.insert(worktree_add_args, upstream)
    end

    return Job:new {
        command = worktree_add_cmd,
        args = worktree_add_args,
        cwd = vim.loop.cwd(),
        on_start = function()
            Log.debug(worktree_add_cmd .. ' ' .. table.concat(worktree_add_args, ' '))
        end,
    }
end

--- @param path string
--- @param force boolean
--- @return Job
function M.delete_worktree_job(path, force)
    local worktree_del_cmd = 'git'
    local worktree_del_args = { 'worktree', 'remove', path }

    if force then
        table.insert(worktree_del_args, '--force')
    end

    return Job:new {
        command = worktree_del_cmd,
        args = worktree_del_args,
        cwd = vim.loop.cwd(),
        on_start = function()
            Log.debug(worktree_del_cmd .. ' ' .. table.concat(worktree_del_args, ' '))
        end,
    }
end

--- @param path string
--- @return Job
function M.fetchall_job(path)
    return Job:new {
        command = 'git',
        args = { 'fetch', '--all' },
        cwd = path,
        on_start = function()
            Log.debug('git fetch --all (This may take a moment)')
        end,
    }
end

--- @param path string
--- @param branch string
--- @param upstream string
--- @return Job
function M.setbranch_job(path, branch, upstream)
    local set_branch_cmd = 'git'
    local set_branch_args = { 'branch', branch, string.format('--set-upstream-to=%s', upstream) }
    return Job:new {
        command = set_branch_cmd,
        args = set_branch_args,
        cwd = path,
        on_start = function()
            Log.debug(set_branch_cmd .. ' ' .. table.concat(set_branch_args, ' '))
        end,
    }
end

--- @param path string
--- @param branch string
--- @param upstream string
--- @return Job
function M.setpush_job(path, branch, upstream)
    -- TODO: How to configure origin???  Should upstream ever be the push
    -- destination?
    local set_push_cmd = 'git'
    local set_push_args = { 'push', '--set-upstream', upstream, branch, path }
    return Job:new {
        command = set_push_cmd,
        args = set_push_args,
        cwd = path,
        on_start = function()
            Log.debug(set_push_cmd .. ' ' .. table.concat(set_push_args, ' '))
        end,
    }
end

--- @param path string
--- @return Job
function M.rebase_job(path)
    return Job:new {
        command = 'git',
        args = { 'rebase' },
        cwd = path,
        on_start = function()
            Log.debug('git rebase')
        end,
    }
end

return M
