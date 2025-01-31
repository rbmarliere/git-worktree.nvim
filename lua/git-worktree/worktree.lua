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
        Log.error('Could not change to directory: %s', worktree_path)
    end

    if Config.clearjumps_on_change then
        Log.debug('Clearing jumps')
        vim.cmd('clearjumps')
    end

    print(string.format('Switched to %s', path))
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
---@param path string?
function M.switch(path)
    if path == vim.loop.cwd() then
        return
    end
    Git.has_worktree(path, nil, function(found)
        if not found then
            Log.error('Worktree does not exists, please create it first %s ', path)
            return
        end

        vim.defer_fn(function()
            local prev_path = change_dirs(path)
            Hooks.emit(Hooks.type.SWITCH, path, prev_path)
        end, 500)
    end)
end

--- CREATE ---

--create a worktree
---@param path string
---@param branch string
---@param upstream? string
function M.create(path, branch, upstream)
    local schedule = function(cb, _path, _branch, _found_branch, _upstream, _found_upstream)
        vim.print('Creating worktree')
        local create_wt_job = Git.create_worktree_job(_path, _branch, _found_branch, _upstream, _found_upstream)
        create_wt_job:after_failure(vim.schedule_wrap(function()
            Log.error('Unable to create worktree')
        end))
        create_wt_job:after_success(vim.schedule_wrap(function()
            vim.print('Worktree was created')
            Hooks.emit(Hooks.type.CREATE, path, branch, upstream)
            if cb then
                cb()
            end
            M.switch(path)
        end))
        create_wt_job:start()
    end

    Git.has_worktree(path, branch, function(found)
        if found then
            Log.error('Path "%s" or branch "%s" already in use.', path, branch)
            return
        end

        if branch == '' then
            -- detached head
            schedule(nil, path, nil, false, nil, false)
            return
        end

        if upstream == nil then
            Git.has_branch(branch, nil, function(found_branch)
                schedule(nil, path, branch, found_branch, nil, false)
            end)
            return
        end

        Git.has_branch(upstream, { '--all' }, function(found_upstream)
            if found_upstream and branch == upstream then
                -- if a remote branch, default to `basename $branch` like git does
                branch = branch:match('([^/]+)$')
            end
            Git.has_branch(branch, nil, function(found_branch)
                local cb = nil
                if found_upstream and found_branch then
                    -- if upstream was selected for an existing branch,
                    -- overwrite the current one by scheduling a `git branch -u` later
                    local setbranch_job = Git.setbranch_job(path, branch, upstream)
                    cb = function()
                        setbranch_job:start()
                    end
                end
                schedule(cb, path, branch, found_branch, upstream, found_upstream)
            end)
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

    local branch = Git.current_branch(path)

    Git.has_worktree(path, nil, function(found)
        if not found then
            Log.error('Worktree %s does not exist', path)
            return
        end

        local delete = Git.delete_worktree_job(path, force)
        delete:after_success(vim.schedule_wrap(function()
            vim.print('Worktree was deleted')
            Hooks.emit(Hooks.type.DELETE, path)
            if opts.on_success then
                opts.on_success { branch = branch }
            end
        end))

        delete:after_failure(function(e)
            Log.error('Unable to delete worktree')
            -- callback has to be called before failure() because failure()
            -- halts code execution
            if opts.on_failure then
                opts.on_failure(e)
            end

            failure(delete.command, vim.loop.cwd())(e)
        end)
        Log.info('delete start job')
        delete:start()
    end)
end

--- MOVE ---

--Move a worktree
---@param path string
---@param new_path string
---@param opts any
function M.move(path, new_path, opts)
    if Path:new(new_path):exists() then
        Log.error('The destination dir %s already exists', new_path)
        return
    end

    local branch = Git.current_branch(path)

    -- `git worktree move` only works if there are no submodules...
    local ret, err = os.rename(path, new_path)
    if not ret then
        Log.error('Error renaming dir: %s', err)
        return
    end

    local reinit_submodules = Git.init_submodules_job(new_path)
    reinit_submodules:after_success(vim.schedule_wrap(function()
        local repair = Git.repair_worktree_job(new_path)
        repair:after_success(vim.schedule_wrap(function()
            vim.print('Worktree was moved')
            Hooks.emit(Hooks.type.MOVE, path)
            if opts.on_success then
                opts.on_success { branch = branch, new_path = new_path }
            end
        end))
        repair:after_failure(function(e)
            Log.error('Unable to repair worktree')
            if opts.on_failure then
                opts.on_failure(e)
            end

            failure(repair.command, vim.loop.cwd())(e)
        end)
        repair:start()
    end))
    reinit_submodules:after_failure(function(e)
        Log.error('Unable to init submodules')
        if opts.on_failure then
            opts.on_failure(e)
        end

        failure(reinit_submodules.command, vim.loop.cwd())(e)
    end)
    reinit_submodules:start()
end

return M
