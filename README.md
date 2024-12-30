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
  ft = "elixir",  -- only if you want to lazy load
  config = true,
}
```
### Without lazy.nvim (manual installation)

Install the plugin using your preferred package manager

Example using [packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use {
  "synic/refactorex.nvim",
  config = function()
    require("refactorex").setup()
  end,
}
```
