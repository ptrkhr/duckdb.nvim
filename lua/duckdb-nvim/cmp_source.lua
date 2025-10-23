local source = {}

-- Try to load cmp, fallback to manual values if not available
local cmp_ok, cmp = pcall(require, 'cmp')
local CompletionItemKind = cmp_ok and cmp.lsp.CompletionItemKind or {
  Class = 7,  -- For tables
  Field = 5,  -- For columns
}

-- Cache for schema information
local schema_cache = {
  tables = {},      -- { table_name = { columns = { col1, col2, ...}, column_types = { col1 = 'INTEGER', ... } } }
  last_updated = 0,
  ttl = 60000,      -- Cache for 60 seconds
}

-- Get all tables and their columns from DuckDB
local function fetch_schema()
  local db = require('duckdb-nvim.db')

  local query = [[
    SELECT
      table_name,
      column_name,
      data_type
    FROM information_schema.columns
    WHERE table_schema = 'main'
    ORDER BY table_name, ordinal_position
  ]]

  local result, err = db.execute(query)
  if err or not result then
    return nil
  end

  -- Organize schema by table
  local tables = {}
  for _, row in ipairs(result) do
    local table_name = row.table_name
    if not tables[table_name] then
      tables[table_name] = {
        columns = {},
        column_types = {},
      }
    end
    table.insert(tables[table_name].columns, row.column_name)
    tables[table_name].column_types[row.column_name] = row.data_type
  end

  return tables
end

-- Get cached schema or fetch new
local function get_schema()
  local now = vim.loop.hrtime() / 1000000  -- Convert to milliseconds

  if now - schema_cache.last_updated > schema_cache.ttl or not next(schema_cache.tables) then
    local tables = fetch_schema()
    if tables then
      schema_cache.tables = tables
      schema_cache.last_updated = now
    end
  end

  return schema_cache.tables
end

-- Parse FROM clause to find referenced tables
local function get_referenced_tables(lines)
  local tables = {}
  local text = table.concat(lines, ' ')

  -- Simple regex to find FROM table_name
  -- TODO: Could be more sophisticated (handle JOINs, subqueries, etc.)
  for table_name in text:gmatch('[Ff][Rr][Oo][Mm]%s+([%w_]+)') do
    tables[table_name:lower()] = true
  end

  -- Also check for JOINs
  for table_name in text:gmatch('[Jj][Oo][Ii][Nn]%s+([%w_]+)') do
    tables[table_name:lower()] = true
  end

  return tables
end

-- Create nvim-cmp source
function source:new()
  local self = setmetatable({}, { __index = source })
  return self
end

function source:is_available()
  -- Only available in SQL buffers
  return vim.bo.filetype == 'sql'
end

function source:get_debug_name()
  return 'duckdb'
end

function source:complete(params, callback)
  local schema = get_schema()
  if not schema or not next(schema) then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local items = {}

  -- Get current buffer lines for context
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local referenced_tables = get_referenced_tables(lines)

  -- Add table name completions
  for table_name, _ in pairs(schema) do
    table.insert(items, {
      label = table_name,
      kind = require('cmp').lsp.CompletionItemKind.Class,
      detail = 'table',
      sortText = '1_' .. table_name,  -- Prioritize tables
    })
  end

  -- Add column completions
  for table_name, table_info in pairs(schema) do
    local is_referenced = referenced_tables[table_name:lower()]
    local priority = is_referenced and '2' or '3'  -- Referenced tables get higher priority

    for _, column_name in ipairs(table_info.columns) do
      local data_type = table_info.column_types[column_name]

      -- Unqualified column name
      table.insert(items, {
        label = column_name,
        kind = require('cmp').lsp.CompletionItemKind.Field,
        detail = string.format('%s (%s)', table_name, data_type),
        sortText = priority .. '_' .. column_name,
      })

      -- Qualified column name (table.column)
      table.insert(items, {
        label = table_name .. '.' .. column_name,
        kind = require('cmp').lsp.CompletionItemKind.Field,
        detail = data_type,
        sortText = priority .. '_' .. table_name .. '.' .. column_name,
      })
    end
  end

  callback({ items = items, isIncomplete = false })
end

-- Function to manually refresh schema cache
function source:refresh_schema()
  schema_cache.last_updated = 0
  get_schema()
end

return source
