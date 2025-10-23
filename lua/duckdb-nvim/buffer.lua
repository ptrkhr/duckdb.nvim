local M = {}

-- Track result buffers
local result_buffers = {}

-- Track buffer mappings (SQL buffer <-> Result buffer)
local sql_to_result = {}
local result_to_sql = {}

-- Set up buffer cleanup autocmd group
local augroup = vim.api.nvim_create_augroup('DuckDBBufferCleanup', { clear = true })

-- Clean up mappings when buffers are deleted
vim.api.nvim_create_autocmd('BufDelete', {
  group = augroup,
  callback = function(args)
    local bufnr = args.buf

    -- Clean up if this was a SQL buffer
    if sql_to_result[bufnr] then
      local result_buf = sql_to_result[bufnr]
      sql_to_result[bufnr] = nil
      result_to_sql[result_buf] = nil
    end

    -- Clean up if this was a result buffer
    if result_to_sql[bufnr] then
      local sql_buf = result_to_sql[bufnr]
      result_to_sql[bufnr] = nil
      sql_to_result[sql_buf] = nil
      result_buffers[bufnr] = nil
    end
  end,
})

-- Show query result in a buffer
function M.show_result(result, query, format, source_bufnr)
  local formatter = require('duckdb-nvim.formatter')
  local lines = formatter.format(result, format)

  -- Check if we should reuse an existing result buffer
  local bufnr
  local reusing = false

  if source_bufnr and sql_to_result[source_bufnr] then
    local existing_bufnr = sql_to_result[source_bufnr]
    -- Check if the buffer still exists and is valid
    if vim.api.nvim_buf_is_valid(existing_bufnr) then
      bufnr = existing_bufnr
      reusing = true
    else
      -- Buffer was deleted, clean up mapping
      sql_to_result[source_bufnr] = nil
      result_to_sql[existing_bufnr] = nil
    end
  end

  -- Create new buffer if not reusing
  if not bufnr then
    bufnr = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
    vim.api.nvim_buf_set_option(bufnr, 'filetype', 'duckdb-result')

    -- Disable word wrap for better table viewing
    vim.api.nvim_buf_set_option(bufnr, 'wrap', false)

    -- Set buffer name
    local buf_name
    if source_bufnr then
      local source_name = vim.api.nvim_buf_get_name(source_bufnr)
      local filename = vim.fn.fnamemodify(source_name, ':t')
      buf_name = string.format('[DuckDB: %s]', filename ~= '' and filename or 'query')
    else
      buf_name = string.format('[DuckDB Result %d]', bufnr)
    end
    vim.api.nvim_buf_set_name(bufnr, buf_name)

    -- Set up buffer mappings if source buffer provided
    if source_bufnr then
      sql_to_result[source_bufnr] = bufnr
      result_to_sql[bufnr] = source_bufnr
    end
  end

  -- Set content (for both new and reused buffers)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'modified', false)

  -- Store metadata
  result_buffers[bufnr] = {
    query = query,
    result = result,
    format = format,
    source_bufnr = source_bufnr,
  }

  -- Open in split or just switch to buffer if reusing
  if reusing then
    -- Find window showing this buffer, or open in split
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      local config = require('duckdb-nvim').setup and require('duckdb-nvim').config or {}
      local split_cmd = (config.result_window == 'vsplit') and 'vsplit' or 'split'
      vim.cmd(split_cmd)
      vim.api.nvim_set_current_buf(bufnr)
    end
  else
    -- New buffer, open in split
    local config = require('duckdb-nvim').setup and require('duckdb-nvim').config or {}
    local split_cmd = (config.result_window == 'vsplit') and 'vsplit' or 'split'
    vim.cmd(split_cmd)
    vim.api.nvim_set_current_buf(bufnr)
  end

  -- Set up buffer-local keymaps
  local opts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set('n', 'q', '<cmd>close<cr>', opts)
  vim.keymap.set('n', '<leader>dr', function()
    M.refresh_buffer(bufnr)
  end, opts)
  vim.keymap.set('n', '<leader>df', function()
    M.toggle_format(bufnr)
  end, opts)
  vim.keymap.set('n', '<leader>dq', function()
    M.edit_current_query()
  end, opts)
  vim.keymap.set('n', 'e', function()
    M.edit_current_query()
  end, opts)
end

-- Refresh a result buffer
function M.refresh_buffer(bufnr)
  local meta = result_buffers[bufnr]
  if not meta then
    vim.notify('Not a DuckDB result buffer', vim.log.levels.ERROR)
    return
  end

  local db = require('duckdb-nvim.db')
  local query = meta.query

  -- If linked to a source SQL buffer, read current content from it
  if meta.source_bufnr and vim.api.nvim_buf_is_valid(meta.source_bufnr) then
    local lines = vim.api.nvim_buf_get_lines(meta.source_bufnr, 0, -1, false)
    query = table.concat(lines, '\n')

    -- Validate query is not empty
    if not query or query:match("^%s*$") then
      vim.notify('Source buffer is empty', vim.log.levels.WARN)
      return
    end

    -- Update stored query
    meta.query = query
  end

  -- Check if this is a paginated result
  if meta.pagination then
    local result, err = db.execute_paginated(
      query,
      meta.pagination.page_size,
      meta.pagination.current_page
    )

    if err then
      vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
      return
    end

    meta.result = result
    M.update_buffer_content_paginated(bufnr, result, meta.format, meta.pagination)
    vim.notify('Result refreshed from source', vim.log.levels.INFO)
  else
    local result, err = db.execute(query)

    if err then
      vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
      return
    end

    meta.result = result
    M.update_buffer_content(bufnr, result, meta.format)
    vim.notify('Result refreshed from source', vim.log.levels.INFO)
  end
end

-- Refresh current buffer
function M.refresh_current()
  M.refresh_buffer(vim.api.nvim_get_current_buf())
end

-- Update buffer content
function M.update_buffer_content(bufnr, result, format)
  local formatter = require('duckdb-nvim.formatter')
  local lines = formatter.format(result, format)

  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'modified', false)
end

-- Toggle format for buffer
function M.toggle_format(bufnr)
  local meta = result_buffers[bufnr]
  if not meta then
    vim.notify('Not a DuckDB result buffer', vim.log.levels.ERROR)
    return
  end

  local formats = {'table', 'csv', 'jsonl'}
  local current_idx = 1
  for i, fmt in ipairs(formats) do
    if fmt == meta.format then
      current_idx = i
      break
    end
  end

  local next_idx = (current_idx % #formats) + 1
  meta.format = formats[next_idx]

  M.update_buffer_content(bufnr, meta.result, meta.format)
  vim.notify('Format: ' .. meta.format, vim.log.levels.INFO)
end

-- Set format for current buffer
function M.set_current_format(format)
  local bufnr = vim.api.nvim_get_current_buf()
  local meta = result_buffers[bufnr]

  if not meta then
    vim.notify('Not a DuckDB result buffer', vim.log.levels.ERROR)
    return
  end

  if format ~= 'table' and format ~= 'csv' and format ~= 'jsonl' then
    vim.notify('Invalid format: ' .. format, vim.log.levels.ERROR)
    return
  end

  meta.format = format
  if meta.pagination then
    M.update_buffer_content_paginated(bufnr, meta.result, format, meta.pagination)
  else
    M.update_buffer_content(bufnr, meta.result, format)
  end
  vim.notify('Format: ' .. format, vim.log.levels.INFO)
end

-- Show paginated query result in a buffer
function M.show_paginated_result(result, query, format, pagination)
  local formatter = require('duckdb-nvim.formatter')
  local lines = formatter.format(result, format)

  -- Add pagination footer
  local total_pages = math.ceil(pagination.total_count / pagination.page_size)
  local start_row = (pagination.current_page - 1) * pagination.page_size + 1
  local end_row = math.min(pagination.current_page * pagination.page_size, pagination.total_count)

  table.insert(lines, '')
  table.insert(lines, string.format('-- Page %d/%d (rows %d-%d of %d) --',
    pagination.current_page,
    total_pages,
    start_row,
    end_row,
    pagination.total_count
  ))
  table.insert(lines, '-- [p]rev | ]p next | [g]oto --')

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'duckdb-result')
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)

  -- Disable word wrap for better table viewing
  vim.api.nvim_buf_set_option(bufnr, 'wrap', false)

  -- Set buffer name
  local buf_name = string.format('[DuckDB Result %d (paginated)]', bufnr)
  vim.api.nvim_buf_set_name(bufnr, buf_name)

  -- Set content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'modified', false)

  -- Store metadata
  result_buffers[bufnr] = {
    query = query,
    result = result,
    format = format,
    pagination = pagination
  }

  -- Open in split
  local config = require('duckdb-nvim').setup and require('duckdb-nvim').config or {}
  local split_cmd = (config.result_window == 'vsplit') and 'vsplit' or 'split'
  vim.cmd(split_cmd)
  vim.api.nvim_set_current_buf(bufnr)

  -- Set up buffer-local keymaps
  local opts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set('n', 'q', '<cmd>close<cr>', opts)
  vim.keymap.set('n', '<leader>dr', function()
    M.refresh_buffer(bufnr)
  end, opts)
  vim.keymap.set('n', '<leader>df', function()
    M.toggle_format(bufnr)
  end, opts)
  vim.keymap.set('n', '<leader>dq', function()
    M.edit_current_query()
  end, opts)
  vim.keymap.set('n', 'e', function()
    M.edit_current_query()
  end, opts)
  vim.keymap.set('n', ']p', function()
    M.navigate_page_in_buffer(bufnr, 1)
  end, opts)
  vim.keymap.set('n', '[p', function()
    M.navigate_page_in_buffer(bufnr, -1)
  end, opts)
end

-- Update buffer content with pagination
function M.update_buffer_content_paginated(bufnr, result, format, pagination)
  local formatter = require('duckdb-nvim.formatter')
  local lines = formatter.format(result, format)

  -- Add pagination footer
  local total_pages = math.ceil(pagination.total_count / pagination.page_size)
  local start_row = (pagination.current_page - 1) * pagination.page_size + 1
  local end_row = math.min(pagination.current_page * pagination.page_size, pagination.total_count)

  table.insert(lines, '')
  table.insert(lines, string.format('-- Page %d/%d (rows %d-%d of %d) --',
    pagination.current_page,
    total_pages,
    start_row,
    end_row,
    pagination.total_count
  ))
  table.insert(lines, '-- [p]rev | ]p next | [g]oto --')

  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(bufnr, 'modified', false)
end

-- Navigate to relative page (delta = 1 for next, -1 for previous)
function M.navigate_page_in_buffer(bufnr, delta)
  local meta = result_buffers[bufnr]
  if not meta or not meta.pagination then
    vim.notify('Not a paginated result buffer', vim.log.levels.ERROR)
    return
  end

  local total_pages = math.ceil(meta.pagination.total_count / meta.pagination.page_size)
  local new_page = meta.pagination.current_page + delta

  if new_page < 1 or new_page > total_pages then
    vim.notify('Already at ' .. (delta > 0 and 'last' or 'first') .. ' page', vim.log.levels.WARN)
    return
  end

  meta.pagination.current_page = new_page

  local db = require('duckdb-nvim.db')
  local result, err = db.execute_paginated(
    meta.query,
    meta.pagination.page_size,
    new_page
  )

  if err then
    vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
    return
  end

  meta.result = result
  M.update_buffer_content_paginated(bufnr, result, meta.format, meta.pagination)
end

-- Navigate to relative page in current buffer
function M.navigate_page(delta)
  M.navigate_page_in_buffer(vim.api.nvim_get_current_buf(), delta)
end

-- Go to specific page
function M.goto_page(page_number)
  local bufnr = vim.api.nvim_get_current_buf()
  local meta = result_buffers[bufnr]

  if not meta or not meta.pagination then
    vim.notify('Not a paginated result buffer', vim.log.levels.ERROR)
    return
  end

  local total_pages = math.ceil(meta.pagination.total_count / meta.pagination.page_size)

  if page_number < 1 or page_number > total_pages then
    vim.notify(string.format('Invalid page number. Must be between 1 and %d', total_pages), vim.log.levels.ERROR)
    return
  end

  meta.pagination.current_page = page_number

  local db = require('duckdb-nvim.db')
  local result, err = db.execute_paginated(
    meta.query,
    meta.pagination.page_size,
    page_number
  )

  if err then
    vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
    return
  end

  meta.result = result
  M.update_buffer_content_paginated(bufnr, result, meta.format, meta.pagination)
end

-- Edit query for current result buffer
function M.edit_current_query()
  local bufnr = vim.api.nvim_get_current_buf()
  local meta = result_buffers[bufnr]

  if not meta then
    vim.notify('Not a DuckDB result buffer', vim.log.levels.ERROR)
    return
  end

  local popup = require('duckdb-nvim.popup')

  -- Show popup editor with current query
  popup.edit_query(meta.query, function(new_query)
    if new_query == '' or new_query == meta.query then
      return
    end

    -- Update query in metadata
    meta.query = new_query

    local db = require('duckdb-nvim.db')

    -- Re-execute with pagination state preserved
    if meta.pagination then
      -- Get new total count
      local total_count, err = db.get_count(new_query)
      if err then
        vim.notify('DuckDB Error (count): ' .. err, vim.log.levels.ERROR)
        return
      end

      -- Update total count
      meta.pagination.total_count = total_count

      -- Check if current page is still valid
      local total_pages = math.ceil(total_count / meta.pagination.page_size)
      if meta.pagination.current_page > total_pages then
        meta.pagination.current_page = math.max(1, total_pages)
      end

      -- Execute at current (or adjusted) page
      local result, err2 = db.execute_paginated(
        new_query,
        meta.pagination.page_size,
        meta.pagination.current_page
      )

      if err2 then
        vim.notify('DuckDB Error: ' .. err2, vim.log.levels.ERROR)
        return
      end

      meta.result = result
      M.update_buffer_content_paginated(bufnr, result, meta.format, meta.pagination)
      vim.notify('Query updated and executed', vim.log.levels.INFO)
    else
      -- Non-paginated result
      local result, err = db.execute(new_query)

      if err then
        vim.notify('DuckDB Error: ' .. err, vim.log.levels.ERROR)
        return
      end

      meta.result = result
      M.update_buffer_content(bufnr, result, meta.format)
      vim.notify('Query updated and executed', vim.log.levels.INFO)
    end
  end)
end

return M
