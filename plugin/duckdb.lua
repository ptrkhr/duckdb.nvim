-- duckdb-nvim: DuckDB integration for Neovim
-- This is a pure Lua plugin

if vim.g.loaded_duckdb_nvim then
  return
end
vim.g.loaded_duckdb_nvim = 1

-- Create user commands
vim.api.nvim_create_user_command('DuckDB', function(opts)
  require('duckdb-nvim').execute(opts.args)
end, { nargs = '+', desc = 'Execute DuckDB query' })

vim.api.nvim_create_user_command('DuckDBLoad', function(opts)
  local args = vim.split(opts.args, '%s+', { trimempty = true })
  if #args == 0 then
    vim.notify('Usage: DuckDBLoad <file> [table_name]', vim.log.levels.ERROR)
    return
  end

  local filepath = args[1]
  local table_name = args[2]  -- nil if not provided

  if table_name then
    require('duckdb-nvim').load_file_as(filepath, table_name)
  else
    require('duckdb-nvim').load_file(filepath)
  end
end, { nargs = '+', complete = 'file', desc = 'Load file into DuckDB with optional table name' })

-- Keep DuckDBLoadAs as an alias for backward compatibility
vim.api.nvim_create_user_command('DuckDBLoadAs', function(opts)
  local args = vim.split(opts.args, '%s+')
  if #args < 2 then
    vim.notify('Usage: DuckDBLoadAs <file> <table_name>', vim.log.levels.ERROR)
    return
  end
  require('duckdb-nvim').load_file_as(args[1], args[2])
end, { nargs = '+', complete = 'file', desc = '[Deprecated] Use :DuckDBLoad <file> <table_name> instead' })

vim.api.nvim_create_user_command('DuckDBExport', function(opts)
  local args = vim.split(opts.args, '%s+')
  if #args < 2 then
    vim.notify('Usage: DuckDBExport <table> <file>', vim.log.levels.ERROR)
    return
  end
  require('duckdb-nvim').export(args[1], args[2])
end, { nargs = '+', complete = 'file', desc = 'Export DuckDB table to file' })

vim.api.nvim_create_user_command('DuckDBReset', function()
  require('duckdb-nvim').reset()
end, { nargs = 0, desc = 'Reset DuckDB database' })

vim.api.nvim_create_user_command('DuckDBSchema', function(opts)
  require('duckdb-nvim').show_schema(opts.args)
end, { nargs = '?', desc = 'Show DuckDB schema' })

vim.api.nvim_create_user_command('DuckDBExecute', function(opts)
  require('duckdb-nvim').execute_buffer(opts.args)
end, { nargs = '*', desc = 'Execute DuckDB query (from buffer/selection or as argument)' })

vim.api.nvim_create_user_command('DuckDBFormat', function(opts)
  require('duckdb-nvim').set_format(opts.args)
end, { nargs = 1, complete = function()
  return {'table', 'csv', 'jsonl'}
end, desc = 'Set result buffer format' })

vim.api.nvim_create_user_command('DuckDBRefresh', function()
  require('duckdb-nvim').refresh_result()
end, { nargs = 0, desc = 'Refresh result buffer' })

vim.api.nvim_create_user_command('DuckDBPaginate', function(opts)
  local args = vim.split(opts.args, '%s+', { trimempty = true })

  -- Extract page_size if provided (last argument is a number)
  local page_size = nil  -- Will use config default if not provided
  local query_parts = {}

  for i, arg in ipairs(args) do
    local num = tonumber(arg)
    if num and i == #args and #query_parts > 0 then
      -- Last arg is a number and we have query parts, treat as page_size
      page_size = num
    else
      table.insert(query_parts, arg)
    end
  end

  local query = table.concat(query_parts, ' ')
  if query == '' then
    vim.notify('Usage: DuckDBPaginate <query> [page_size]', vim.log.levels.ERROR)
    return
  end

  require('duckdb-nvim').execute_paginated(query, page_size)
end, { nargs = '+', desc = 'Execute DuckDB query with pagination' })

vim.api.nvim_create_user_command('DuckDBNextPage', function()
  require('duckdb-nvim').next_page()
end, { nargs = 0, desc = 'Go to next page in paginated result' })

vim.api.nvim_create_user_command('DuckDBPrevPage', function()
  require('duckdb-nvim').prev_page()
end, { nargs = 0, desc = 'Go to previous page in paginated result' })

vim.api.nvim_create_user_command('DuckDBGotoPage', function(opts)
  local page = tonumber(opts.args)
  if not page then
    vim.notify('Usage: DuckDBGotoPage <page_number>', vim.log.levels.ERROR)
    return
  end
  require('duckdb-nvim').goto_page(page)
end, { nargs = 1, desc = 'Go to specific page in paginated result' })

vim.api.nvim_create_user_command('DuckDBEditQuery', function()
  require('duckdb-nvim').edit_query()
end, { nargs = 0, desc = 'Edit query for current result buffer' })

vim.api.nvim_create_user_command('DuckDBBuffers', function()
  require('duckdb-nvim').list_sql_buffers()
end, { nargs = 0, desc = 'List all SQL buffers' })

vim.api.nvim_create_user_command('DuckDBHistory', function()
  require('duckdb-nvim').show_history()
end, { nargs = 0, desc = 'Show query history' })

vim.api.nvim_create_user_command('DuckDBClearHistory', function()
  require('duckdb-nvim').clear_history()
end, { nargs = 0, desc = 'Clear query history' })
