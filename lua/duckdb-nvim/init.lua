local M = {}

-- Plugin state
local config = {
  default_format = 'table',
  result_window = 'vsplit',
  auto_close_result = false,
  default_page_size = 100,
  cache_ttl = 60000,  -- 60 seconds in milliseconds
  max_history = 50,   -- Maximum number of queries to keep in history
  keymaps = {
    execute = '<leader>de',
    refresh = '<leader>dr',
    toggle_format = '<leader>df',
  }
}

-- Query history
local query_history = {}

-- Validate configuration
local function validate_config(cfg)
  -- Validate format
  if cfg.default_format and cfg.default_format ~= 'table' and
     cfg.default_format ~= 'csv' and cfg.default_format ~= 'jsonl' then
    vim.notify('Invalid default_format: ' .. cfg.default_format .. '. Using "table".', vim.log.levels.WARN)
    cfg.default_format = 'table'
  end

  -- Validate result_window
  if cfg.result_window and cfg.result_window ~= 'split' and cfg.result_window ~= 'vsplit' then
    vim.notify('Invalid result_window: ' .. cfg.result_window .. '. Using "vsplit".', vim.log.levels.WARN)
    cfg.result_window = 'vsplit'
  end

  -- Validate numeric values
  if cfg.default_page_size and (type(cfg.default_page_size) ~= 'number' or cfg.default_page_size < 1) then
    vim.notify('Invalid default_page_size: must be a positive number. Using 100.', vim.log.levels.WARN)
    cfg.default_page_size = 100
  end

  if cfg.cache_ttl and (type(cfg.cache_ttl) ~= 'number' or cfg.cache_ttl < 0) then
    vim.notify('Invalid cache_ttl: must be a non-negative number. Using 60000.', vim.log.levels.WARN)
    cfg.cache_ttl = 60000
  end

  if cfg.max_history and (type(cfg.max_history) ~= 'number' or cfg.max_history < 1) then
    vim.notify('Invalid max_history: must be a positive number. Using 50.', vim.log.levels.WARN)
    cfg.max_history = 50
  end

  return cfg
end

-- Setup function for user configuration
function M.setup(opts)
  local user_config = opts or {}
  user_config = validate_config(user_config)

  config = vim.tbl_deep_extend('force', config, user_config)
  M.config = config  -- Expose config for access by other modules

  -- Register nvim-cmp source if available
  local ok, cmp = pcall(require, 'cmp')
  if ok then
    local source = require('duckdb-nvim.cmp_source')
    cmp.register_source('duckdb', source:new())
  end
end

-- Get current configuration
function M.get_config()
  return config
end

-- Load submodules
M.db = require('duckdb-nvim.db')
M.buffer = require('duckdb-nvim.buffer')
M.formatter = require('duckdb-nvim.formatter')
M.popup = require('duckdb-nvim.popup')

-- Add query to history
local function add_to_history(query)
  -- Remove duplicates
  for i = #query_history, 1, -1 do
    if query_history[i] == query then
      table.remove(query_history, i)
    end
  end

  -- Add to end
  table.insert(query_history, query)

  -- Trim if over max
  if #query_history > config.max_history then
    table.remove(query_history, 1)
  end
end

-- Execute SQL query
function M.execute(query, source_bufnr)
  local result, err = M.db.execute(query)
  if err then
    vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
    return
  end

  add_to_history(query)
  M.buffer.show_result(result, query, config.default_format, source_bufnr)
end

-- Load file into database
function M.load_file(filepath)
  local expanded_path = vim.fn.expand(filepath)
  local filename = vim.fn.fnamemodify(expanded_path, ':t:r')
  local table_name = filename:gsub('[^%w_]', '_')

  return M.load_file_as(expanded_path, table_name)
end

-- Load file with custom table name
function M.load_file_as(filepath, table_name)
  local expanded_path = vim.fn.expand(filepath)
  local ext = vim.fn.fnamemodify(expanded_path, ':e'):lower()

  local query
  if ext == 'csv' then
    query = string.format("CREATE OR REPLACE TABLE %s AS SELECT * FROM read_csv_auto('%s')",
                         table_name, expanded_path)
  elseif ext == 'parquet' then
    query = string.format("CREATE OR REPLACE TABLE %s AS SELECT * FROM read_parquet('%s')",
                         table_name, expanded_path)
  elseif ext == 'json' or ext == 'jsonl' then
    query = string.format("CREATE OR REPLACE TABLE %s AS SELECT * FROM read_json_auto('%s')",
                         table_name, expanded_path)
  else
    vim.notify('Unsupported file type: ' .. ext, vim.log.levels.ERROR)
    return
  end

  local _, err = M.db.execute(query)
  if err then
    vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format('Loaded %s into table "%s"', filepath, table_name), vim.log.levels.INFO)
end

-- Export table to file
function M.export(table_name, filepath)
  local expanded_path = vim.fn.expand(filepath)
  local ext = vim.fn.fnamemodify(expanded_path, ':e'):lower()

  local query
  if ext == 'csv' then
    query = string.format("COPY %s TO '%s' (HEADER, DELIMITER ',')", table_name, expanded_path)
  elseif ext == 'parquet' then
    query = string.format("COPY %s TO '%s' (FORMAT PARQUET)", table_name, expanded_path)
  elseif ext == 'json' then
    query = string.format("COPY %s TO '%s' (FORMAT JSON, ARRAY true)", table_name, expanded_path)
  elseif ext == 'jsonl' then
    query = string.format("COPY %s TO '%s' (FORMAT JSON)", table_name, expanded_path)
  else
    vim.notify('Unsupported export format: ' .. ext, vim.log.levels.ERROR)
    return
  end

  local _, err = M.db.execute(query)
  if err then
    vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format('Exported table "%s" to %s', table_name, filepath), vim.log.levels.INFO)
end

-- Reset database
function M.reset()
  M.db.reset()
  vim.notify('DuckDB database reset', vim.log.levels.INFO)
end

-- Show schema
function M.show_schema(table_name)
  local query
  if table_name == '' or table_name == nil then
    query = "SELECT table_name, column_name, data_type FROM information_schema.columns ORDER BY table_name, ordinal_position"
  else
    query = string.format("DESCRIBE %s", table_name)
  end

  local result, err = M.db.execute(query)
  if err then
    vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
    return
  end

  M.buffer.show_result(result, query, 'table')
end

-- Execute current buffer, visual selection, or provided query
function M.execute_buffer(query_arg)
  local query
  local source_bufnr = nil

  -- If query argument provided, use it
  if query_arg and query_arg ~= '' then
    query = query_arg
  else
    -- No query argument, check for visual selection or use entire buffer
    local visual_mode = vim.fn.visualmode()

    if visual_mode ~= '' then
      -- We have a visual selection, use it
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local lines = vim.fn.getline(start_pos[2], end_pos[2])
      query = table.concat(lines, '\n')
    else
      -- No visual selection, use entire buffer
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      query = table.concat(lines, '\n')
    end

    -- Track source buffer if it's a SQL file
    local current_buf = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_get_option(current_buf, 'filetype') == 'sql' then
      source_bufnr = current_buf
    end
  end

  -- Validate query is not empty or just whitespace
  if not query or query:match("^%s*$") then
    vim.notify('No SQL query to execute', vim.log.levels.WARN)
    return
  end

  M.execute(query, source_bufnr)
end

-- Set result format
function M.set_format(format)
  M.buffer.set_current_format(format)
end

-- Refresh result buffer
function M.refresh_result()
  M.buffer.refresh_current()
end

-- Execute paginated SQL query
function M.execute_paginated(query, page_size)
  page_size = page_size or config.default_page_size

  -- Get total count first
  local total_count, err = M.db.get_count(query)
  if err then
    vim.notify('DuckDB Error (count): ' .. err, vim.log.levels.ERROR)
    return
  end

  -- Execute first page
  local result, err2 = M.db.execute_paginated(query, page_size, 1)
  if err2 then
    vim.notify('DuckDB Error: ' .. err2, vim.log.levels.ERROR)
    return
  end

  add_to_history(query)

  -- Show result with pagination metadata
  M.buffer.show_paginated_result(result, query, config.default_format, {
    page_size = page_size,
    current_page = 1,
    total_count = total_count
  })
end

-- Navigate to next page
function M.next_page()
  M.buffer.navigate_page(1)
end

-- Navigate to previous page
function M.prev_page()
  M.buffer.navigate_page(-1)
end

-- Go to specific page
function M.goto_page(page_number)
  M.buffer.goto_page(page_number)
end

-- Edit query for current result buffer
function M.edit_query()
  M.buffer.edit_current_query()
end

-- List all SQL buffers
function M.list_sql_buffers()
  local sql_buffers = {}
  local current_buf = vim.api.nvim_get_current_buf()

  -- Get all buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    -- Check if buffer is loaded and has SQL filetype
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')
      if ft == 'sql' then
        local name = vim.api.nvim_buf_get_name(bufnr)
        local modified = vim.api.nvim_buf_get_option(bufnr, 'modified')
        local is_current = (bufnr == current_buf)

        -- Get just the filename if it's a full path
        local display_name = name
        if name ~= '' then
          display_name = vim.fn.fnamemodify(name, ':t')
        else
          display_name = '[No Name]'
        end

        table.insert(sql_buffers, {
          bufnr = bufnr,
          name = display_name,
          full_path = name,
          modified = modified,
          is_current = is_current
        })
      end
    end
  end

  -- Sort by buffer number
  table.sort(sql_buffers, function(a, b) return a.bufnr < b.bufnr end)

  -- Format output
  if #sql_buffers == 0 then
    vim.notify('No SQL buffers open', vim.log.levels.INFO)
    return
  end

  local lines = {'SQL Buffers:', ''}
  for _, buf in ipairs(sql_buffers) do
    local indicator = buf.is_current and '* ' or '  '
    local modified = buf.modified and ' [+]' or ''
    local line = string.format('%s%3d  %s%s', indicator, buf.bufnr, buf.name, modified)
    table.insert(lines, line)
  end

  -- Show in notification or could show in a buffer
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

-- Get query history
function M.get_history()
  return vim.deepcopy(query_history)
end

-- Show query history and allow selection
function M.show_history()
  if #query_history == 0 then
    vim.notify('No query history available', vim.log.levels.INFO)
    return
  end

  -- Use vim.ui.select to show history
  local items = {}
  for i = #query_history, 1, -1 do  -- Reverse order (most recent first)
    local query = query_history[i]
    local preview = query:gsub('\n', ' '):sub(1, 80)
    if #query > 80 then
      preview = preview .. '...'
    end
    table.insert(items, {
      index = i,
      preview = preview,
      query = query
    })
  end

  vim.ui.select(items, {
    prompt = 'Query History:',
    format_item = function(item)
      return string.format('%2d. %s', item.index, item.preview)
    end,
  }, function(choice)
    if choice then
      M.execute(choice.query)
    end
  end)
end

-- Clear query history
function M.clear_history()
  query_history = {}
  vim.notify('Query history cleared', vim.log.levels.INFO)
end

return M
