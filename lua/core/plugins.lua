vim.pack.add({
  -- Language tooling and editor features; managed directly by Neovim.
  { src = "https://github.com/neovim/nvim-lspconfig" },
  { src = "https://github.com/mason-org/mason.nvim" },
  { src = "https://github.com/Saghen/blink.cmp", version = "v1.10.2" },
  { src = "https://github.com/rafamadriz/friendly-snippets" },
  { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
  { src = "https://github.com/stevearc/conform.nvim" },
  { src = "https://github.com/nvim-mini/mini.nvim" },
  { src = "https://github.com/akinsho/bufferline.nvim" },
  -------------------------------------------------------
  -- Theme
  -------------------------------------------------------

  {
    src = "https://github.com/catppuccin/nvim",
    name = "catppuccin",
  },

  -------------------------------------------------------
  -- Common Dependencies
  -------------------------------------------------------

  {
    src = "https://github.com/nvim-lua/plenary.nvim",
  },

  {
    src = "https://github.com/MunifTanjim/nui.nvim",
  },

  {
    src = "https://github.com/nvim-tree/nvim-web-devicons",
  },

  -------------------------------------------------------
  -- Explorer
  -------------------------------------------------------

  {
    src = "https://github.com/nvim-neo-tree/neo-tree.nvim",
    version = "v3.x",
  },

  -------------------------------------------------------
  -- Search
  -------------------------------------------------------

  {
    src = "https://github.com/nvim-telescope/telescope.nvim",
  },

  -------------------------------------------------------
  -- UI
  -------------------------------------------------------

  {
    src = "https://github.com/nvim-lualine/lualine.nvim",
  },

  {
    src = "https://github.com/folke/noice.nvim",
  },

  {
    src = "https://github.com/rcarriga/nvim-notify",
  },

  {
    src = "https://github.com/folke/which-key.nvim",
  },

  -------------------------------------------------------
  -- Key Display
  -------------------------------------------------------

  {
    src = "https://github.com/NStefan002/screenkey.nvim",
  },

  -------------------------------------------------------
  -- Git
  -------------------------------------------------------

  {
    src = "https://github.com/lewis6991/gitsigns.nvim",
  },
}, {
  confirm = false,
  load = true,
})
