local M = {
  "aserowy/tmux.nvim",
}

function M.config()
  return require("tmux").setup()
end

return M
