-- SQL filetype plugin for DuckDB integration
-- This adds keybindings for .sql files to execute queries

local opts = { noremap = true, silent = true, buffer = true }

-- Execute buffer or visual selection
vim.keymap.set('n', '<leader>de', function()
  require('duckdb-nvim').execute_buffer()
end, vim.tbl_extend('force', opts, { desc = 'Execute DuckDB query' }))

vim.keymap.set('v', '<leader>de', function()
  require('duckdb-nvim').execute_buffer()
end, vim.tbl_extend('force', opts, { desc = 'Execute DuckDB query' }))

-- Pagination navigation (works when in paginated result buffer)
vim.keymap.set('n', ']p', function()
  require('duckdb-nvim').next_page()
end, vim.tbl_extend('force', opts, { desc = 'Next page (DuckDB)' }))

vim.keymap.set('n', '[p', function()
  require('duckdb-nvim').prev_page()
end, vim.tbl_extend('force', opts, { desc = 'Previous page (DuckDB)' }))
