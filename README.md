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

### Usage

refactorex.nvim hooks into neovim's built in LSP system, and it's functions are
made availble with the following two functions:

1. `vim.lsp.buf.code_action()` - allows you to pick from any code actions
   provided by any language server connected to the current buffer, for the
   given context. For example, given the following code:

   ```elixir

   def ship(item_id, quantity) do
     items = Inventory.take!(item_id, quantity)

     ...
   end
   ```

   If you highlight the `items =` line and run `:lua
   vim.lsp.buf.code_action()`, you will see the option to "Introduce
   IO.inspect". If you choose it, it will change the line to `items =
   Inventory.take!(item_id, quantity) |> IO.inspect()`.

   There are lots of things you can do, but a lot of them are context specific.
   Check https://github.com/gp-pereira/refactorex for more information and
   examples.

2. `vim.lsp.buf.rename()` - allows you to rename a symbol

   If you have your cursor on a symbol, you can run `:lua
   vim.lsp.buf.rename()`, it will allow to rename that symbol (and  all of it's
   occurences). Note that for the time being, this only works with local
   symbols in the same file.

### Key Bindings

Running `:lua vim.lsp.buf.rename()` or `:lua vim.lsp.buf.code_action()` every
time you want to rename a symbol or refactor some code isn't very appealing, so
you may want to add some keybindings for these actions. Note that these are not
refactorex.nvim specific functions, they are part of Neovim's built in LSP
system, and work for any language server(s) connected to the buffer you are in.
If you are using a Neovim distribution (like LazyVim), keybindings like this
are may already be set up.

```lua
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(event)
    -- code actions keybinding, in normal and visual mode
    vim.keymap.set(
      "n",
      "ga",
      vim.lsp.buf.code_action,
      { buffer = true, desc = "Show code actions" }
    )
    vim.keymap.set(
      "v",
      "ga",
      vim.lsp.buf.code_action,
      { buffer = true, desc = "Show code actions" }
    )

    -- rename keybinding, in normal and visual mode
    vim.keymap.set(
      "n",
      "ga",
      vim.lsp.buf.rename,
      { buffer = true, desc = "Rename symbol" }
    )
    vim.keymap.set(
      "v",
      "ga",
      vim.lsp.buf.rename,
      { buffer = true, desc = "Rename symbol" }
    )

  end
})
```

This will run when any LSP server attaches to the buffer. The `buffer = true`
part of the keymap.set means that these keybindings are just for the current
buffer. If you want to set up keybindings for specific file types, you can
examine `vim.bo[event.buf].filetype`.

More information about setting up LSP can be found here:
https://neovim.io/doc/user/lsp.html
