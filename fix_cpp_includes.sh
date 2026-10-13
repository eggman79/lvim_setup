#!/bin/bash

CONFIG_DIR="$HOME/.config/lvim"
CONFIG_FILE="$CONFIG_DIR/config.lua"

cat >> "$CONFIG_FILE" << LUA
vim.list_extend(
  lvim.lsp.automatic_configuration.skipped_servers,
  { "clangd" }
)

require("lvim.lsp.manager").setup("clangd", {
  cmd = {
    vim.fn.expand("~/.local/share/lvim/mason/bin/clangd"),
    "--background-index",
    "--query-driver=/usr/bin/c++,/usr/bin/g++,/usr/bin/g++-*",
  },
})
LUA
