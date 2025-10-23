local M = {}

-- Create a centered floating window
local function create_centered_float(width_ratio, height_ratio)
  local width_ratio_val = width_ratio or 0.8
  local height_ratio_val = height_ratio or 0.6

  local width = math.floor(vim.o.columns * width_ratio_val)
  local height = math.floor(vim.o.lines * height_ratio_val)

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Edit Query ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  return buf, win
end

-- Show query editor popup
function M.edit_query(query, on_save)
  local bufnr, winnr = create_centered_float(0.8, 0.6)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'acwrite')
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'sql')
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')

  -- Set query content
  local lines = vim.split(query, '\n')
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Add footer with instructions
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, {
    '',
    '-- Press <CR> to execute | :q to cancel | <leader>w to save & execute',
  })

  -- Mark footer as non-editable (visual indicator)
  local ns_id = vim.api.nvim_create_namespace('duckdb_popup_footer')
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, #lines + 1, 0, {
    virt_text = {{'━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'Comment'}},
    virt_text_pos = 'overlay',
  })

  -- Function to execute the query
  local function execute_query()
    -- Get all lines except footer
    local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local query_lines = {}

    for i, line in ipairs(all_lines) do
      -- Stop at the empty line before footer
      if line == '' and i == #all_lines - 1 then
        break
      end
      table.insert(query_lines, line)
    end

    local new_query = table.concat(query_lines, '\n')

    -- Close popup
    vim.api.nvim_win_close(winnr, true)

    -- Execute callback with new query
    if on_save then
      on_save(new_query)
    end
  end

  -- Set up keymaps
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- Execute on <CR> in normal mode
  vim.keymap.set('n', '<CR>', execute_query, opts)

  -- Execute on <leader>w
  vim.keymap.set('n', '<leader>w', execute_query, opts)

  -- Close on q or Escape
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(winnr, true)
  end, opts)

  vim.keymap.set('n', '<Esc>', function()
    vim.api.nvim_win_close(winnr, true)
  end, opts)

  -- Set cursor to first line
  vim.api.nvim_win_set_cursor(winnr, {1, 0})

  -- Enter insert mode at end of first line
  vim.cmd('startinsert!')
end

return M
