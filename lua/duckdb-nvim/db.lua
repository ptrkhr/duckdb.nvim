local M = {}

-- Database state
local db_path = nil  -- nil means in-memory

-- Initialize database path
local function get_db_path()
  if not db_path then
    -- Create temp file for in-memory database
    db_path = vim.fn.tempname() .. '.duckdb'
  end
  return db_path
end

-- Execute SQL query and return results
function M.execute(query)
  local path = get_db_path()

  -- Use vim.system (Neovim 0.10+) or vim.fn.systemlist for better handling
  -- Pipe query directly to duckdb via stdin to avoid escaping issues
  local cmd = {'duckdb', path, '-json'}

  -- Use vim.system if available (Neovim 0.10+)
  if vim.system then
    local result = vim.system(cmd, {
      stdin = query,
      text = true,
    }):wait()

    if result.code ~= 0 then
      return nil, result.stderr or result.stdout
    end

    local output = result.stdout
    if output == '' or output == '[]' then
      return {}, nil
    end

    local ok, decoded = pcall(vim.fn.json_decode, output)
    if not ok then
      return nil, 'Failed to parse result: ' .. output
    end

    return decoded, nil
  else
    -- Fallback for older Neovim versions - use temp file
    local temp_query = vim.fn.tempname() .. '.sql'
    local query_file = io.open(temp_query, 'w')
    if not query_file then
      return nil, 'Failed to write query to temporary file'
    end
    query_file:write(query)
    query_file:close()

    local temp_out = vim.fn.tempname()
    local shell_cmd = string.format(
      "duckdb '%s' -json < '%s' > '%s' 2>&1",
      path,
      temp_query,
      temp_out
    )

    local exit_code = os.execute(shell_cmd)
    os.remove(temp_query)

    local file = io.open(temp_out, 'r')
    if not file then
      return nil, 'Failed to read query output'
    end

    local output = file:read('*all')
    file:close()
    os.remove(temp_out)

    if exit_code ~= 0 then
      return nil, output
    end

    if output == '' or output == '[]' then
      return {}, nil
    end

    local ok, decoded = pcall(vim.fn.json_decode, output)
    if not ok then
      return nil, 'Failed to parse result: ' .. output
    end

    return decoded, nil
  end
end

-- Reset database
function M.reset()
  if db_path and vim.fn.filereadable(db_path) == 1 then
    os.remove(db_path)
  end
  db_path = nil
end

-- Execute paginated query (with LIMIT and OFFSET)
function M.execute_paginated(query, page_size, page_number)
  page_size = page_size or 100
  page_number = page_number or 1

  local offset = (page_number - 1) * page_size

  -- Wrap query with pagination
  local paginated_query = string.format(
    "SELECT * FROM (%s) LIMIT %d OFFSET %d",
    query,
    page_size,
    offset
  )

  return M.execute(paginated_query)
end

-- Get total row count for a query
function M.get_count(query)
  local count_query = string.format("SELECT COUNT(*) as count FROM (%s)", query)
  local result, err = M.execute(count_query)

  if err then
    return nil, err
  end

  if result and #result > 0 and result[1].count then
    return result[1].count, nil
  end

  return 0, nil
end

-- Get current database path (for debugging)
function M.get_path()
  return get_db_path()
end

return M
