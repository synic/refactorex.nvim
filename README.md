# refactorex.nvim

A Neovim plugin for [RefactorEx - Elixir refactoring tool](https://github.com/gp-pereira/refactorex)

## Prerequisites

- Neovim 0.8.0 or higher
- Elixir/Mix installed on your system
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

### With lazy.nvim

```lua
{
  "synic/refactorex.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  ft = "elixir",  -- only if you want to lazy load
  config = true,
}
```
### Without lazy.nvim (manual installation)

1. Install the plugin using your preferred package manager
2. Install plenary.nvim

Example using [packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use {
  'synic/refactorex.nvim',
  requires = { 'nvim-lua/plenary.nvim' },
}
```
