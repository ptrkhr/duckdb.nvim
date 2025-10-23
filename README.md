# duckdb-nvim

DuckDB integration for Neovim - Query structured data with SQL directly in your editor.

## Features

- 🚀 In-memory DuckDB database for fast data analysis
- 📊 Load CSV, Parquet, JSON/JSONL files
- 🎨 Multiple result formats: ASCII tables, CSV, JSONL
- 📄 Pagination support for large datasets
- ✨ SQL autocompletion via nvim-cmp integration
- 📝 Query history and interactive query editing
- 💾 Export results to various formats

## Requirements

- Neovim >= 0.8.0
- DuckDB CLI installed and in PATH
  - macOS: `brew install duckdb`
  - Other platforms: https://duckdb.org/docs/installation/

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'ptrkhr/duckdb.nvim',
  config = function()
    require('duckdb-nvim').setup({
      default_format = 'table',      -- 'table', 'csv', 'jsonl'
      result_window = 'vsplit',      -- 'split', 'vsplit'
      default_page_size = 100,       -- Rows per page for pagination
      keymaps = {
        execute = '<leader>de',
        refresh = '<leader>dr',
        toggle_format = '<leader>df',
      }
    })
  end
}
```

### Optional: nvim-cmp Integration

For SQL autocompletion of table and column names:

```lua
-- In your nvim-cmp setup:
require('cmp').setup({
  sources = {
    { name = 'duckdb' },  -- Add DuckDB completion
    -- ... other sources
  }
})
```

Provides smart SQL completion with table/column names and type information.

## Quick Start

```vim
" 1. Load data
:DuckDBLoad ~/data/sales.csv

" 2. Query it
:DuckDB SELECT * FROM sales WHERE amount > 1000

" 3. Navigate results
" Press <leader>df to cycle formats (table → csv → jsonl)
" Press q to close
" Press <leader>dr to refresh

" 4. For large datasets, use pagination
:DuckDBPaginate SELECT * FROM sales ORDER BY date 100
" Use ]p and [p to navigate pages
```

## Key Features

### Query Execution

```vim
" Execute directly
:DuckDB SELECT COUNT(*) FROM my_table

" In a .sql file, press <leader>de to execute
" Visual select text and press <leader>de for partial execution
```

### Pagination for Large Datasets

```vim
:DuckDBPaginate SELECT * FROM large_table 50
]p  " Next page
[p  " Previous page
:DuckDBGotoPage 5  " Jump to page 5
```

Loads only one page at a time for memory efficiency.

### Interactive Query Editing

```vim
" In any result buffer, press 'e' to edit the query
" Modify and press <CR> to re-execute
" Pagination state is preserved!
```

### Query History

```vim
:DuckDBHistory        " Browse and re-execute previous queries
:DuckDBClearHistory   " Clear history
```

### Schema Inspection

```vim
:DuckDBSchema           " Show all tables
:DuckDBSchema my_table  " Show specific table schema
```

### Data Export

```vim
:DuckDBExport my_table output.parquet
:DuckDBExport results output.csv
```

### Result Formats

Toggle between three formats with `<leader>df`:

- **table** - ASCII tables with box drawing (default)
- **csv** - Comma-separated values
- **jsonl** - JSON Lines (one object per line)

## Working with SQL Buffers

Create `analysis.sql`:

```sql
SELECT
  category,
  COUNT(*) as count,
  AVG(price) as avg_price
FROM sales
WHERE date >= '2024-01-01'
GROUP BY category
ORDER BY count DESC;
```

Press `<leader>de` to execute. Results open in a split.

## Documentation

For comprehensive documentation, see:
```vim
:help duckdb-nvim
```

The help file includes:
- Complete command reference
- Configuration options
- Lua API documentation
- Advanced examples and workflows
- Troubleshooting guide

## DuckDB Features

DuckDB supports powerful features like CTEs, window functions, and reading files directly in queries. See the [DuckDB documentation](https://duckdb.org/docs/) for details.

```sql
-- Read files directly
SELECT * FROM read_csv_auto('data/*.csv');
SELECT * FROM read_parquet('data/*.parquet');

-- Window functions
SELECT *, ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) as rank
FROM products;
```

## Common Commands

| Command | Description |
|---------|-------------|
| `:DuckDB <query>` | Execute SQL query |
| `:DuckDBLoad <file> [table]` | Load file into database |
| `:DuckDBPaginate <query> [size]` | Execute with pagination |
| `:DuckDBSchema [table]` | Show schema |
| `:DuckDBHistory` | Browse query history |
| `:DuckDBExport <table> <file>` | Export table |
| `:DuckDBReset` | Clear database |

See `:help duckdb-nvim-commands` for the complete list.

## Keybindings

**In SQL buffers:**
- `<leader>de` - Execute buffer/selection

**In result buffers:**
- `q` - Close
- `e` - Edit query
- `<leader>dr` - Refresh
- `<leader>df` - Toggle format
- `]p` / `[p]` - Next/previous page (paginated results)

## License

MIT

---

For bug reports and feature requests, please visit the [GitHub repository](https://github.com/ptrkhr/duckdb.nvim).
