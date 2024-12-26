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
  "gp-pereira/refactorex.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  build = "./build.sh",
  cmd = "RefactorExDownload",
  config = true,
}
```

### Without lazy.nvim (manual installation)

1. Install the plugin using your preferred package manager
2. Install plenary.nvim
3. Download and setup RefactorEx by running this command in Neovim:
```vim
:lua require('refactorex').ensure_refactorex()
```

Example using [packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use {
  'gp-pereira/refactorex.nvim',
  requires = { 'nvim-lua/plenary.nvim' },
  run = './build.sh'
}
```
