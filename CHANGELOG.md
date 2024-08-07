# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2024-07-18

### 🚀 Features

- V2 refactor
- Add ability to run luarocks non nix

### 🐛 Bug Fixes

- Add hook to update current buffer on switch

### 🚜 Refactor

- Stylua fixes and start to build from core
- Config
- Lost code
- Basic switch working
- Create worktree
- Delete worktree
- Delete worktree
- Add back in telescope
- To plenary test and other
- Final rework

### 📚 Documentation

- Initial readme update
- Update plugin help docs
- Update readme

### 🧪 Testing

- Add git ops tests

### ⚙️ Miscellaneous Tasks

- Mv test repo to spec dir
- Fix stylua
- Luachecks
- Add commit-lint workflow
- Switch to vusted for testing
- Add name to commit-lint
- Add plenary install
- Refactor tests to hopefully pass
- Add test for switching normal repo
- Add windows-latest test
- Add busted test to nix check
- Add bused tests
- Add type-check
- Add style check
- Add dependabot.yml
- Add convential commit checker
- Add luarocks release

## [1.0.0] - 2023-11-17

### 🚀 Features

- *(delete)* Allowed for deleting the buffer
- *(worktree-swap)* Better swapping and sane defaults
- *(create)* If rebase fails, we don't stop the creation process
- *(switch)* Clear jumps on switch.  Can be configured
- *(status)* Added a status line printer
- *(readme)* Effectively correct
- *(on_tree_change)* Better interfacing with on_tree_change
- *(set_push)* Push so I can push with Git push

### 🐛 Bug Fixes

- *(indenting)* Tree shitter to the rescue
- *(status)* Status was 8 / 7 at some point.
- *(create_worktree)* Allows for worktree to also create the branch.
- Pass opts to git_worktrees
- Always return absolute git dir
- Merge mistake to prevent errors
- :Telescope git_worktree

### ⚙️ Miscellaneous Tasks

- Renamed :w to wip.lua
- Removed file
- Nixify
- Add luarocks release uploader
- Create LICENSE

### Fix

- Typo in README.md

### Feta

- *(first-commit)* It "sorta" works.

<!-- generated by git-cliff -->
