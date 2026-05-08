-- Registers all nvim-side state Veil depends on for one connection lifetime:
-- the VeilApp augroup (BufEnter/TabEnter notifications), the VeilAppDebug
-- and VeilAppVersion user commands, and, in remote mode only, a g:clipboard
-- provider that routes yank/paste through Veil's RPC channel back to the
-- local Mac pasteboard. Local nvim does not need this: the system's
-- pbcopy/pbpaste provider already talks to the Mac pasteboard directly.
--
-- Varargs from Swift:
--   chan_id   (number)  Veil's RPC channel id; baked into every
--                       rpcnotify / rpcrequest closure below.
--   is_remote (boolean) gates the clipboard provider injection.
--
-- chan_id MUST be passed in by Swift. Do not "simplify" by resolving it here
-- via `nvim_get_chan_info(0)`: the "0 = current channel" shorthand only works
-- for direct RPC calls. Inside this nested nvim_exec_lua context the API
-- treats Lua as an internal caller, so 0 yields nil. The failure surfaces
-- not at setup time but later at autocmd or user-command fire time, with a
-- "bad argument #1 to 'rpcnotify' (number expected, got nil)" stack trace
-- that does not obviously point back here.

local chan_id, is_remote = ...

local group = vim.api.nvim_create_augroup('VeilApp', { clear = true })
vim.api.nvim_create_autocmd({ 'BufEnter', 'TabEnter' }, {
  group = group,
  callback = function()
    vim.rpcnotify(chan_id, 'VeilAppBufChanged')
  end,
})

vim.api.nvim_create_user_command('VeilAppDebugToggle', function()
  vim.rpcnotify(chan_id, 'VeilAppDebugToggle')
end, {})

vim.api.nvim_create_user_command('VeilAppDebugCopy', function()
  vim.rpcnotify(chan_id, 'VeilAppDebugCopy')
end, {})

vim.api.nvim_create_user_command('VeilAppVersion', function(opts)
  vim.rpcnotify(chan_id, 'VeilAppVersion', opts.bang and '!' or '')
end, { bang = true })

if is_remote then
  -- If g:clipboard exists but g:VeilAppClipboardInjected is absent, the user
  -- configured their own provider and we leave it alone. Otherwise (no
  -- provider, or one we injected previously) install ours so rpcrequest
  -- targets the current channel.
  local has_user_provider = vim.g.clipboard ~= nil and vim.g.VeilAppClipboardInjected ~= true
  if not has_user_provider then
    vim.g.VeilAppClipboardInjected = true
    vim.g.clipboard = {
      name = 'VeilClipboard',
      copy = {
        ['+'] = function(lines, regtype)
          vim.rpcrequest(chan_id, 'VeilAppClipboardSet', lines, regtype)
        end,
        ['*'] = function(lines, regtype)
          vim.rpcrequest(chan_id, 'VeilAppClipboardSet', lines, regtype)
        end,
      },
      paste = {
        ['+'] = function()
          return vim.rpcrequest(chan_id, 'VeilAppClipboardGet')
        end,
        ['*'] = function()
          return vim.rpcrequest(chan_id, 'VeilAppClipboardGet')
        end,
      },
    }
    -- Force reload clipboard provider so it picks up the new g:clipboard
    package.loaded['vim.provider.clipboard'] = nil
    vim.g.loaded_clipboard_provider = nil
    vim.cmd('runtime autoload/provider/clipboard.vim')
  end
end
