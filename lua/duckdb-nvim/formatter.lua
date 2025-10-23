local M = {}

-- Helper: Get sorted column names from result
local function get_sorted_columns(result)
  if not result or #result == 0 then
    return {}
  end

  local columns = {}
  for col, _ in pairs(result[1]) do
    table.insert(columns, col)
  end
  table.sort(columns)
  return columns
end

-- Helper: Build table separator line
local function build_separator(columns, widths, left, mid, right)
  local parts = {}
  for _, col in ipairs(columns) do
    table.insert(parts, string.rep('─', widths[col] + 2))
  end
  return left .. table.concat(parts, mid) .. right
end

-- Format result as ASCII table
function M.format_table(result)
  if not result or #result == 0 then
    return {'-- No results --'}
  end

  local columns = get_sorted_columns(result)

  -- Calculate column widths
  local widths = {}
  for _, col in ipairs(columns) do
    widths[col] = #col
  end

  for _, row in ipairs(result) do
    for _, col in ipairs(columns) do
      local val = tostring(row[col] or 'NULL')
      widths[col] = math.max(widths[col], #val)
    end
  end

  -- Build table
  local lines = {}

  -- Top separator
  table.insert(lines, build_separator(columns, widths, '┌', '┬', '┐'))

  -- Header row
  local header_vals = {}
  for _, col in ipairs(columns) do
    local padded = col .. string.rep(' ', widths[col] - #col)
    table.insert(header_vals, ' ' .. padded .. ' ')
  end
  table.insert(lines, '│' .. table.concat(header_vals, '│') .. '│')

  -- Middle separator
  table.insert(lines, build_separator(columns, widths, '├', '┼', '┤'))

  -- Data rows
  for _, row in ipairs(result) do
    local row_vals = {}
    for _, col in ipairs(columns) do
      local val = tostring(row[col] or 'NULL')
      local padded = val .. string.rep(' ', widths[col] - #val)
      table.insert(row_vals, ' ' .. padded .. ' ')
    end
    table.insert(lines, '│' .. table.concat(row_vals, '│') .. '│')
  end

  -- Bottom separator
  table.insert(lines, build_separator(columns, widths, '└', '┴', '┘'))

  -- Add row count
  table.insert(lines, '')
  table.insert(lines, string.format('-- %d row%s --', #result, #result == 1 and '' or 's'))

  return lines
end

-- Format result as CSV
function M.format_csv(result)
  if not result or #result == 0 then
    return {'-- No results --'}
  end

  local lines = {}
  local columns = get_sorted_columns(result)

  -- Header
  table.insert(lines, table.concat(columns, ','))

  -- Data rows
  for _, row in ipairs(result) do
    local vals = {}
    for _, col in ipairs(columns) do
      local val = row[col]
      if val == nil then
        table.insert(vals, '')
      elseif type(val) == 'string' and (val:find(',') or val:find('"') or val:find('\n')) then
        -- Escape CSV special characters
        table.insert(vals, '"' .. val:gsub('"', '""') .. '"')
      else
        table.insert(vals, tostring(val))
      end
    end
    table.insert(lines, table.concat(vals, ','))
  end

  return lines
end

-- Format result as JSONL (one JSON object per line)
function M.format_jsonl(result)
  if not result or #result == 0 then
    return {'-- No results --'}
  end

  local lines = {}

  for _, row in ipairs(result) do
    local json_str = vim.fn.json_encode(row)
    table.insert(lines, json_str)
  end

  return lines
end

-- Main format dispatcher
function M.format(result, format_type)
  if format_type == 'csv' then
    return M.format_csv(result)
  elseif format_type == 'jsonl' then
    return M.format_jsonl(result)
  else
    return M.format_table(result)
  end
end

return M
