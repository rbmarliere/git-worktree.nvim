local Path = require('plenary.path')

local Git = require('git-worktree.git')
local Log = require('git-worktree.logger')
local Hooks = require('git-worktree.hooks')
local Config = require('git-worktree.config')

local function get_absolute_path(path)
    if Path:new(path):is_absolute() then
        return path
    else
        return Path:new(vim.loop.cwd(), path):absolute()
    end
end

local function change_dirs(path)
    Log.info('changing dirs:  %s ', path)
    local worktree_path = get_absolute_path(path)
    local previous_worktree = vim.loop.cwd()
    Config = require('git-worktree.config')

    -- vim.loop.chdir(worktree_path)
    if Path:new(worktree_path):exists() then
        local cmd = string.format('%s %s', Config.change_directory_command, worktree_path)
        Log.debug('Changing to directory  %s', worktree_path)
        vim.cmd(cmd)
    else
        Log.error('Could not chang to directory: %s', worktree_path)
    end

    if Config.clearjumps_on_change then
        Log.debug('Clearing jumps')
        vim.cmd('clearjumps')
    end

    return previous_worktree
end

local function failure(from, cmd, path, soft_error)
    return function(e)
        local error_message = string.format(
            '%s Failed: PATH %s CMD %s RES %s, ERR %s',
            from,
            path,
            vim.inspect(cmd),
            vim.inspect(e:result()),
            vim.inspect(e:stderr_result())
        )

        if soft_error then
            Log.error(error_message)
        else
            Log.error(error_message)
        end
    end
end

local M = {}

--- SWITCH ---

--Switch the current worktree
---@param path string
function M.switch(path)
    Git.has_worktree(path, function(found)
        Log.debug('test')
        if not found then
            Log.error('worktree does not exists, please create it first %s ', path)
        end
        Log.debug('has worktree')

        vim.schedule(function()
            local prev_path = change_dirs(path)
            Hooks.emit(Hooks.type.SWITCH, path, prev_path)
        end)
    end)
end

--- CREATE ---

--create a worktree
---@param path string
---@param branch string
---@param upstream? string
function M.create(path, branch, upstream)
    -- if upstream == nil then
    --     if Git.has_origin() then
    --         upstream = 'origin'
    --     end
    -- end

    -- M.setup_git_info()

    Git.has_worktree(path, function(found)
        if found then
            Log.error('worktree already exists')
            return
        end

        Git.has_branch(branch, function(found_branch)
            Config = require('git-worktree.config')
            local worktree_path
            if Path:new(path):is_absolute() then
                worktree_path = path
            else
                worktree_path = Path:new(vim.loop.cwd(), path):absolute()
            end

            -- create_worktree(path, branch, upstream, found_branch)
            local create_wt_job = Git.create_worktree_job(path, branch, found_branch)

            if upstream ~= nil then
                local fetch = Git.fetchall_job(path, branch, upstream)
                local set_branch = Git.setbranch_job(path, branch, upstream)
                local set_push = Git.setpush_job(path, branch, upstream)
                local rebase = Git.rebase_job(path)

                create_wt_job:and_then_on_success(fetch)
                fetch:and_then_on_success(set_branch)

                if Config.autopush then
                    -- These are "optional" operations.
                    -- We have to figure out how we want to handle these...
                    set_branch:and_then(set_push)
                    set_push:and_then(rebase)
                    set_push:after_failure(failure('create_worktree', set_branch.args, worktree_path, true))
                else
                    set_branch:and_then(rebase)
                end

                create_wt_job:after_failure(failure('create_worktree', create_wt_job.args, vim.loop.cwd()))
                fetch:after_failure(failure('create_worktree', fetch.args, worktree_path))

                set_branch:after_failure(failure('create_worktree', set_branch.args, worktree_path, true))

                rebase:after(function()
                    if rebase.code ~= 0 then
                        Log.debug("Rebase failed, but that's ok.")
                    end

                    vim.schedule(function()
                        Hooks.emit(Hooks.type.CREATE, path, branch, upstream)
                        M.switch(path)
                    end)
                end)
            else
                create_wt_job:after(function()
                    vim.schedule(function()
                        Hooks.emit(Hooks.type.CREATE, path, branch, upstream)
                        M.switch(path)
                    end)
                end)
            end
            create_wt_job:start()
        end)
    end)
end

--- DELETE ---

--Delete a worktree
---@param path string
---@param force boolean
---@param opts any
function M.delete(path, force, opts)
    if not opts then
        opts = {}
    end

    Git.has_worktree(path, function(found)
        Log.info('OMG here')
        if not found then
            Log.error('Worktree %s does not exist', path)
        else
            Log.info('Worktree %s does exist', path)
        end

        local delete = Git.delete_worktree_job(path, force)
        delete:after_success(vim.schedule_wrap(function()
            Log.info('delete after success')
            Hooks.emit(Hooks.type.DELETE, path)
            if opts.on_success then
                opts.on_success()
            end
        end))

        delete:after_failure(function(e)
            Log.info('delete after failure')
            -- callback has to be called before failure() because failure()
            -- halts code execution
            if opts.on_failure then
                opts.on_failure(e)
            end

            failure(delete.cmd, vim.loop.cwd())(e)
        end)
        Log.info('delete start job')
        delete:start()
    end)
end

return M
