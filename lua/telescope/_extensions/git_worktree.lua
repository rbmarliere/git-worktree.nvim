local strings = require('plenary.strings')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local actions = require('telescope.actions')
local utils = require('telescope.utils')
local action_set = require('telescope.actions.set')
local action_state = require('telescope.actions.state')
local conf = require('telescope.config').values
local git_worktree = require('git-worktree')
local Config = require('git-worktree.config')
local Git = require('git-worktree.git')
local Log = require('git-worktree.logger')

local force_next_deletion = false

-- Get the path of the selected worktree
-- @param prompt_bufnr number: the prompt buffer number
-- @return string?: the path of the selected worktree
local get_worktree_path = function(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    if selection == nil then
        vim.print('No worktree selected')
        return
    end
    return selection.path
end

-- Switch to the selected worktree
-- @param prompt_bufnr number: the prompt buffer number
-- @return nil
local switch_worktree = function(prompt_bufnr)
    local worktree_path = get_worktree_path(prompt_bufnr)
    if worktree_path == nil then
        return
    end
    actions.close(prompt_bufnr)
    git_worktree.switch_worktree(worktree_path)
end

-- Toggle the forced deletion of the next worktree
-- @return nil
local toggle_forced_deletion = function()
    -- redraw otherwise the message is not displayed when in insert mode
    if force_next_deletion then
        vim.print('The next deletion will not be forced')
        vim.fn.execute('redraw')
    else
        vim.print('The next deletion will be forced')
        vim.fn.execute('redraw')
        force_next_deletion = true
    end
end

-- Confirm the deletion of a worktree
-- @param forcing boolean: whether the deletion is forced
-- @return boolean: whether the deletion is confirmed
local confirm_worktree_deletion = function(forcing)
    if not Config.confirm_telescope_deletions then
        return true
    end

    local confirmed
    if forcing then
        confirmed = vim.fn.input('Force deletion of worktree? [y/n]: ')
    else
        confirmed = vim.fn.input('Delete worktree? [y/n]: ')
    end

    if string.sub(string.lower(confirmed), 0, 1) == 'y' then
        return true
    end

    vim.print("Didn't delete worktree")
    return false
end

-- Ask user for confirmation
-- @return boolean: whether the deletion is confirmed
local confirm = function(label)
    local confirmed = vim.fn.input(string.format('%s [y|N]: ', label))

    if string.sub(string.lower(confirmed), 0, 1) == 'y' then
        return true
    end

    return false
end

-- Handler for successful deletion
-- @return nil
local delete_success_handler = function(opts)
    opts = opts or {}
    force_next_deletion = false
    if opts.branch ~= nil and opts.branch ~= 'HEAD' and confirm('Force deletion of branch?') then
        Log.debug('deleting ' .. opts.branch)
        local delete_branch_job = Git.delete_branch_job(opts.branch)
        if delete_branch_job ~= nil then
            delete_branch_job:after_success(vim.schedule_wrap(function()
                vim.print('Branch was deleted')
            end))
            delete_branch_job:after_failure(vim.schedule_wrap(function()
                Log.error('Unable to delete branch')
            end))
            delete_branch_job:start()
        end
    end
end

-- Handler for failed deletion
-- @return nil
local delete_failure_handler = function()
    vim.print('Deletion failed, use <C-f> to force the next deletion')
end

-- Delete the selected worktree
-- @param prompt_bufnr number: the prompt buffer number
-- @return nil
local delete_worktree = function(prompt_bufnr)
    -- TODO: confirm_deletion(forcing)
    local selected = get_worktree_path(prompt_bufnr)
    if selected == nil then
        return
    end

    if not confirm_worktree_deletion() then
        return
    end

    actions.close(prompt_bufnr)

    if selected ~= nil then
        local current = vim.loop.cwd()
        if current == selected then
            git_worktree.switch_worktree(Git.gitroot_dir())
        end
        git_worktree.delete_worktree(selected, force_next_deletion, {
            on_failure = delete_failure_handler,
            on_success = delete_success_handler,
        })
    end
end

local move_success_handler = function(opts)
    opts = opts or {}
    if confirm('Worktree moved, now rename branch?') then
        local new_branch = vim.fn.input('New branch name > ', opts.branch)
        if new_branch == '' or new_branch == opts.branch then
            Log.error('No branch name provided')
            return
        end

        local rename_branch_job = Git.rename_branch_job(opts.branch, new_branch)
        rename_branch_job:after_success(vim.schedule_wrap(function()
            vim.print('Branch was renamed')
        end))
        rename_branch_job:after_failure(function()
            Log.error('Unable to rename branch')
        end)
        rename_branch_job:start()
    end
end

-- Move the selected worktree
-- @param prompt_bufnr number: the prompt buffer number
-- @return nil
local move_worktree = function(prompt_bufnr)
    local selected = get_worktree_path(prompt_bufnr)
    if selected == nil then
        return
    end
    actions.close(prompt_bufnr)

    local current = vim.loop.cwd()
    if current == selected then
        git_worktree.switch_worktree(Git.gitroot_dir())
    end

    local new_path = vim.fn.input('Path to subtree > ', selected)
    if new_path == '' or new_path == selected then
        Log.error('No worktree path provided')
        return
    end

    if selected ~= new_path then
        git_worktree.move_worktree(selected, new_path, {
            -- on_failure = ?
            on_success = move_success_handler,
        })
    end
end

-- Create a prompt to get the path of the new worktree
-- @param cb function: the callback to call with the path
-- @return nil
local create_input_prompt = function(opts, cb)
    opts = opts or {}
    opts.pattern = nil -- show all branches that can be tracked

    local path = vim.fn.input('Path to subtree > ', Git.gitroot_dir() .. '/' .. opts.branch)
    if path == '' then
        Log.error('No worktree path provided')
        return
    end

    if opts.branch == '' then
        cb(path, nil)
        return
    end

    local branches = vim.fn.systemlist('git branch --all')
    if #branches == 0 then
        cb(path, nil)
        return
    end

    local re = string.format('git branch --remotes --list %s', opts.branch)
    local branch = vim.fn.systemlist(re)
    if #branch == 1 then
        cb(path, opts.branch)
        return
    end

    if not confirm('Track an upstream?') then
        cb(path, nil)
        return
    end

    re = string.format('git branch --list %s', opts.branch)
    branch = vim.fn.systemlist(re)
    if #branch == 1 then
        if not confirm('Overwrite upstream of existing branch?') then
            cb(path, nil)
            return
        end
    end

    opts.attach_mappings = function()
        actions.select_default:replace(function(prompt_bufnr, _)
            local selected_entry = action_state.get_selected_entry()
            local current_line = action_state.get_current_line()
            actions.close(prompt_bufnr)
            local upstream = selected_entry ~= nil and selected_entry.value or current_line
            cb(path, upstream)
        end)
        return true
    end
    require('telescope.builtin').git_branches(opts)
end

-- Create a worktree
-- @param opts table: the options for the telescope picker (optional)
-- @return nil
local telescope_create_worktree = function(opts)
    opts = opts or {}

    local create_branch = function(prompt_bufnr, _)
        -- if current_line is still not enough to filter everything but user
        -- still wants to use it as the new branch name, without selecting anything
        local branch = action_state.get_current_line()
        -- if branch == "" then
        --     TODO:detached head should list tags
        -- end
        actions.close(prompt_bufnr)
        opts.branch = branch
        create_input_prompt(opts, function(path, upstream)
            git_worktree.create_worktree(path, branch, upstream)
        end)
    end

    local select_or_create_branch = function(prompt_bufnr, _)
        local selected_entry = action_state.get_selected_entry()
        local current_line = action_state.get_current_line()
        actions.close(prompt_bufnr)
        -- selected_entry can be null if current_line filters everything
        -- and there's no branch shown
        local branch = selected_entry ~= nil and selected_entry.value or current_line
        if branch == nil or branch == '' then
            Log.error('No branch selected')
            return
        end
        opts.branch = branch
        create_input_prompt(opts, function(path, upstream)
            git_worktree.create_worktree(path, branch, upstream)
        end)
    end

    opts.attach_mappings = function(_, map)
        map({ 'i', 'n' }, '<tab>', create_branch)
        actions.select_default:replace(select_or_create_branch)
        return true
    end

    -- TODO: A corner case here is that of a new bare repo which has no branch nor tree,
    -- but user may want to create one using this picker when creating the first worktree.
    -- Perhaps telescope git_branches should only be used for selecting the upstream to track.
    require('telescope.builtin').git_branches(opts)
end

-- List the git worktrees
-- @param opts table: the options for the telescope picker (optional)
-- @return nil
local telescope_git_worktree = function(opts)
    opts = opts or {}
    opts.path_display = { 'smart' }
    local output = utils.get_os_command_output { 'git', 'worktree', 'list', '--porcelain' }
    local results = {}
    local widths = {
        path = 0,
        branch = 0,
        sha = 0,
    }

    -- if within a worktree, the base repo dir is seen
    -- as the main worktree with a sha but should not be shown
    local root = Git.gitroot_dir()
    local current = vim.loop.cwd()

    local entry = {}
    local index = 1
    for _, line in ipairs(output) do
        if line == '' and entry.sha ~= nil then
            if entry.path ~= root then
                for key, val in pairs(widths) do
                    if key == 'path' then
                        local path, _ = utils.transform_path(opts, entry.path)
                        local path_len = strings.strdisplaywidth(path or '')
                        widths[key] = math.max(val, path_len)
                    else
                        widths[key] = math.max(val, strings.strdisplaywidth(entry[key] or ''))
                    end
                end
                table.insert(results, index, entry)
                index = index + 1
            end
            entry = {}
        else
            local path = string.match(line, '^worktree%s+(.+)$')
            if path then
                entry.path = path
            end
            local sha = string.match(line, '^HEAD%s+(.+)$')
            if sha then
                entry.sha = sha:sub(0, 12)
            end
            local branch = string.match(line, '^branch refs/heads/(.+)$')
            if branch then
                entry.branch = string.format('[%s]', branch)
            elseif string.find(line, '^detached$') then
                entry.branch = '(detached HEAD)'
            end
        end
    end

    -- if #results == 0 then
    --     return
    -- end

    local displayer = require('telescope.pickers.entry_display').create {
        separator = ' ',
        items = {
            { width = widths.path },
            { width = widths.sha },
            { width = widths.branch },
        },
    }

    local make_display = function(entry)
        local path, _ = utils.transform_path(opts, entry.path)
        if entry.path == current then
            path = '.'
        end
        return displayer {
            { path, 'TelescopeResultsIdentifier' },
            { entry.sha },
            { entry.branch },
        }
    end

    pickers
        .new(opts or {}, {
            prompt_title = 'Git Worktrees',
            finder = finders.new_table {
                results = results,
                entry_maker = function(entry)
                    entry.value = entry.branch
                    entry.ordinal = entry.path
                    entry.display = make_display
                    return entry
                end,
            },
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(_, map)
                action_set.select:replace(switch_worktree)

                map('i', '<m-c>', function()
                    telescope_create_worktree {}
                end)
                map('n', '<m-c>', function()
                    telescope_create_worktree {}
                end)
                map('i', '<m-r>', move_worktree)
                map('n', '<m-r>', move_worktree)
                map('i', '<m-d>', delete_worktree)
                map('n', '<m-d>', delete_worktree)
                map('i', '<c-f>', toggle_forced_deletion)
                map('n', '<c-f>', toggle_forced_deletion)

                return true
            end,
        })
        :find()
end

-- Register the extension
-- @return table: the extension
return require('telescope').register_extension {
    exports = {
        git_worktree = telescope_git_worktree,
        create_git_worktree = telescope_create_worktree,
    },
}
