-- Masks values in .env* buffers so secrets don't leak while screensharing
-- or pairing; :CloakToggle reveals them when actually editing.
return {
  {
    'laytan/cloak.nvim',
    event = 'BufReadPre',
    opts = {},
  },
}
