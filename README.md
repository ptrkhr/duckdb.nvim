# duckdb-nvim

DuckDB integration for Neovim - Query structured data with SQL directly in your editor.

## Features

- In-memory DuckDB database for fast data analysis
- Load CSV, Parquet, JSON/JSONL files
- Multiple result formats: ASCII tables, CSV, JSONL
- Execute queries from buffers or command line
- **Pagination support for large datasets**
- Export results to files
- SQL buffer support with keybindings

## Requirements

- Neovim >= 0.8.0
- DuckDB CLI installed and in PATH (`brew install duckdb` or https://duckdb.org/docs/installation/)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'ptrkhr/duckdb.nvim',
  config = function()
    require('duckdb-nvim').setup({
      default_format = 'table',  -- 'table', 'csv', 'jsonl'
      result_window = 'vsplit',  -- 'split', 'vsplit'
      keymaps = {
        execute = '<leader>de',
        refresh = '<leader>dr',
        toggle_format = '<leader>df',
      }
    })
  end
}
```

### nvim-cmp Integration (Optional)

For SQL autocompletion of table and column names:

```lua
{
  'ptrkhr/duckdb.nvim',
  config = function()
    require('duckdb-nvim').setup({
      default_format = 'table',
      result_window = 'vsplit',
    })
  end
}

-- In your nvim-cmp setup:
require('cmp').setup({
  sources = {
    { name = 'duckdb' },  -- Add DuckDB completion source
    { name = 'buffer' },
    { name = 'path' },
    -- ... other sources
  }
})
```

**Features:**
- Auto-completes table names
- Auto-completes column names (both `column` and `table.column`)
- Smart ranking: prioritizes columns from tables in your `FROM` clause
- Shows data types in completion details
- Cached for performance (60s TTL)

## Usage

### Loading Data

```vim
" Load a CSV file (table name auto-generated from filename)
:DuckDBLoad data/sales.csv

" Load with custom table name
:DuckDBLoad data/sales.csv my_sales

" Supported formats: CSV, Parquet, JSON, JSONL
:DuckDBLoad data/users.parquet
:DuckDBLoad data/events.jsonl customers

" Note: File basename is used as table name by default
" Example: sales-2024.csv → table name: sales_2024
```

### Executing Queries

```vim
" Execute SQL directly
:DuckDB SELECT * FROM my_sales WHERE amount > 1000

" In a .sql buffer, press <leader>de to execute
" Visual select SQL text and press <leader>de to execute selection
```

### Pagination (for Large Datasets)

When working with large datasets, use pagination to load results in manageable chunks:

```vim
" Execute query with pagination (default: 100 rows per page)
:DuckDBPaginate SELECT * FROM large_table

" Specify custom page size (e.g., 50 rows per page)
:DuckDBPaginate SELECT * FROM large_table WHERE status = 'active' 50

" In paginated result buffers:
" ]p or :DuckDBNextPage - Go to next page
" [p or :DuckDBPrevPage - Go to previous page
" :DuckDBGotoPage 5 - Jump to page 5
" <leader>dr - Refresh (stays on current page)
" <leader>df - Toggle format (table/csv/jsonl)
```

**Pagination Features:**
- Only loads one page at a time (memory efficient)
- Shows page info: `Page 3/10 (rows 201-300 of 1000)`
- Total row count displayed
- State persists across refreshes and format changes

**Example with large dataset:**
```vim
:DuckDBLoad huge_file.parquet
:DuckDBPaginate SELECT * FROM huge_file WHERE date >= '2024-01-01' ORDER BY timestamp 500

" Navigate: ]p to see next 500 rows, [p to go back
" Switch to JSONL for row-by-row editing: <leader>df
```

### Working with Results

Result buffers support:
- `q` - Close buffer
- `<leader>dr` - Refresh (re-run query)
- `<leader>df` - Toggle format (table → csv → jsonl)
- `<leader>dq` or `e` - Edit query in popup window

```vim
" Change format in result buffer
:DuckDBFormat jsonl
:DuckDBFormat csv
:DuckDBFormat table

" Refresh current result
:DuckDBRefresh

" Edit and re-execute query
:DuckDBEditQuery
" Or press 'e' in result buffer
```

### Editing Queries

Edit the query for any result buffer in a popup window:

```vim
" In a result buffer, press 'e' or <leader>dq
" Or use the command:
:DuckDBEditQuery
```

**Features:**
- Opens a centered popup with SQL syntax highlighting
- Shows the original query for editing
- Press `<CR>` or `<leader>w` to execute the modified query
- Press `q` or `<Esc>` to cancel
- **Pagination preserved**: If viewing page 5 of 10, stays on page 5 after edit
- Total count updated automatically for modified queries
- If current page becomes invalid (e.g., fewer results), adjusts to last valid page

**Example workflow:**
```vim
" Start with a query
:DuckDBPaginate SELECT * FROM sales WHERE amount > 1000 100

" Navigate to page 3
]p
]p

" Realize you want to change the filter
e                    " Opens popup editor

" Modify query: WHERE amount > 5000
" Press <CR>

" Result: Query re-executed, still on page 3 (if valid)
```

### Schema Inspection

```vim
" Show all tables and columns
:DuckDBSchema

" Describe specific table
:DuckDBSchema my_sales
```

### Exporting Data

```vim
" Export table to file
:DuckDBExport my_sales output.csv
:DuckDBExport my_sales output.parquet
:DuckDBExport my_sales output.jsonl
```

### Database Management

```vim
" Reset database (clear all tables)
:DuckDBReset
```

## Example Workflow

```vim
" Load some data
:DuckDBLoad ~/data/sales.csv
:DuckDBLoad ~/data/customers.parquet

" Check what's loaded
:DuckDBSchema

" Query the data
:DuckDB SELECT c.name, SUM(s.amount) as total FROM customers c JOIN sales s ON c.id = s.customer_id GROUP BY c.name ORDER BY total DESC LIMIT 10

" In result buffer:
" - Press <leader>df to switch to JSONL format
" - Press <leader>dr to refresh
" - Press q to close

" Export results
:DuckDBExport sales filtered_sales.parquet
```

## SQL Buffer Workflow

Create a file `analysis.sql`:

```sql
-- Load some data first with :DuckDBLoad

SELECT
  category,
  COUNT(*) as count,
  AVG(price) as avg_price,
  SUM(quantity) as total_qty
FROM sales
WHERE date >= '2024-01-01'
GROUP BY category
ORDER BY total_qty DESC;
```

Press `<leader>de` in normal mode to execute the entire buffer, or visually select specific queries and press `<leader>de`.

## Result Formats

### Table (default)
```
┌────────────┬───────┬───────────┐
│ category   │ count │ avg_price │
├────────────┼───────┼───────────┤
│ Electronics│   150 │    299.99 │
│ Books      │   423 │     15.99 │
└────────────┴───────┴───────────┘
-- 2 rows --
```

### CSV
```
category,count,avg_price
Electronics,150,299.99
Books,423,15.99
```

### JSONL (one object per line)
```
{"category":"Electronics","count":150,"avg_price":299.99}
{"category":"Books","count":423,"avg_price":15.99}
```

## Advanced DuckDB Features

DuckDB supports many advanced features:

```sql
-- Read files directly in queries
SELECT * FROM read_csv_auto('data/*.csv');
SELECT * FROM read_parquet('s3://bucket/data/*.parquet');

-- JSON operations
SELECT data->>'$.name' as name FROM json_table;

-- Window functions
SELECT *, ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) as rank FROM products;

-- CTEs
WITH top_customers AS (
  SELECT customer_id, SUM(amount) as total
  FROM sales GROUP BY customer_id
  ORDER BY total DESC LIMIT 10
)
SELECT * FROM top_customers;
```

## API Reference

### Commands

| Command | Description |
|---------|-------------|
| `:DuckDB <query>` | Execute SQL query |
| `:DuckDBPaginate <query> [page_size]` | Execute query with pagination |
| `:DuckDBLoad <file> [table_name]` | Load file into table (optional custom name) |
| `:DuckDBExport <table> <file>` | Export table to file |
| `:DuckDBSchema [table]` | Show schema (all tables or specific) |
| `:DuckDBExecute` | Execute current buffer/selection |
| `:DuckDBFormat <format>` | Set format (table/csv/jsonl) |
| `:DuckDBRefresh` | Refresh current result buffer |
| `:DuckDBEditQuery` | Edit query in popup (preserves pagination) |
| `:DuckDBNextPage` | Go to next page (paginated only) |
| `:DuckDBPrevPage` | Go to previous page (paginated only) |
| `:DuckDBGotoPage <n>` | Jump to specific page |
| `:DuckDBReset` | Clear database |

### Keybindings

#### SQL Buffers (.sql files)
- `<leader>de` - Execute buffer/visual selection
- `]p` - Next page (in result buffer)
- `[p` - Previous page (in result buffer)

#### Result Buffers
- `q` - Close buffer
- `e` or `<leader>dq` - Edit query in popup
- `<leader>dr` - Refresh results
- `<leader>df` - Toggle format
- `]p` - Next page (paginated only)
- `[p` - Previous page (paginated only)

### Lua API

```lua
local duckdb = require('duckdb-nvim')

-- Execute queries
duckdb.execute("SELECT * FROM my_table")
duckdb.execute_paginated("SELECT * FROM large_table", 100)

-- Navigate pages
duckdb.next_page()
duckdb.prev_page()
duckdb.goto_page(5)

-- Data management
duckdb.load_file("data.csv")
duckdb.load_file_as("data.csv", "my_table")
duckdb.export("my_table", "output.parquet")

-- Result buffer control
duckdb.set_format("jsonl")
duckdb.refresh_result()
duckdb.edit_query()  -- Edit query in popup
```

## License

MIT
