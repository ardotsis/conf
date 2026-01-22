-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.clipboard = "unnamedplus"
vim.opt.number = true
vim.opt.relativenumber = true
vim.keymap.set("x", "p", "P")
vim.keymap.set("x", "P", "p")
vim.keymap.set("i", "jj", "<ESC>")
