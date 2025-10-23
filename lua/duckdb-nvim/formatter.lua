local M = {}

-- Format result as ASCII table
function M.format_table(result)
  if not result or #result == 0 then
    return {'-- No results --'}
  end

  -- Get column names from first row
  local columns = {}
  for col, _ in pairs(result[1]) do
    table.insert(columns, col)
  end
  table.sort(columns)

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

  -- Header separator
  local header_parts = {}
  for _, col in ipairs(columns) do
    table.insert(header_parts, string.rep('─', widths[col] + 2))
  end
  local separator = '┌' .. table.concat(header_parts, '┬') .. '┐'
  table.insert(lines, separator)

  -- Header row
  local header_vals = {}
  for _, col in ipairs(columns) do
    local padded = col .. string.rep(' ', widths[col] - #col)
    table.insert(header_vals, ' ' .. padded .. ' ')
  end
  table.insert(lines, '│' .. table.concat(header_vals, '│') .. '│')

  -- Header bottom separator
  local mid_parts = {}
  for _, col in ipairs(columns) do
    table.insert(mid_parts, string.rep('─', widths[col] + 2))
  end
  local mid_separator = '├' .. table.concat(mid_parts, '┼') .. '┤'
  table.insert(lines, mid_separator)

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
  local bottom_parts = {}
  for _, col in ipairs(columns) do
    table.insert(bottom_parts, string.rep('─', widths[col] + 2))
  end
  local bottom = '└' .. table.concat(bottom_parts, '┴') .. '┘'
  table.insert(lines, bottom)

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

  -- Get column names
  local columns = {}
  for col, _ in pairs(result[1]) do
    table.insert(columns, col)
  end
  table.sort(columns)

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
