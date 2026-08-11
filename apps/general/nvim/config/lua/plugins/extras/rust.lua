-- rust_analyzer is enabled in lsp.lua; rustaceanvim is deliberately not
-- added here since it would spawn a second, conflicting rust-analyzer.
return {
  -- Crate versions, features and upgrades inline in Cargo.toml
  {
    'saecki/crates.nvim',
    event = { 'BufRead Cargo.toml' },
    opts = {
      completion = {
        crates = { enabled = true },
      },
      lsp = {
        enabled = true,
        actions = true,
        completion = true,
        hover = true,
      },
    },
  },
}
