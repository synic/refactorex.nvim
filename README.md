# refactorex.nvim

A Neovim plugin for [RefactorEx - Elixir refactoring tool](https://github.com/gp-pereira/refactorex)

## Prerequisites

- Neovim 0.8.0 or higher
- Elixir/Mix installed on your system

## Installation

### With lazy.nvim

```lua
{
  "synic/refactorex.nvim",
  ft = "elixir",
  ---@module "refactorex.nvim"
  ---@type refactorex.Config
  opts = {
    auto_update = true,
    pin_version = nil,
  }
}
```
### Without lazy.nvim (manual installation)

Install the plugin using your preferred package manager

Example using [packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use {
  "synic/refactorex.nvim",
  config = function()
    require("refactorex").setup({ auto_update = true, pin_version = nil })
  end,
}
```

### Available Options

- `auto_update` (boolean): When true, automatically checks for updates when the
  plugin loads.
- `pin_version` (string): When set, forces the plugin to use this specific
  version (e.g., "0.1.30"). This overrides auto_update.

## Commands

- `:RefactorExDownload`: Downloads and installs the latest version of
  RefactorEx, restarting the LSP server if it's running
