-- Headless smoke tests. Run via tests/smoke.sh (or:
--   nvim --headless "+lua dofile('tests/smoke.lua')" +qa )
-- Each phase of the architecture work adds checks here; all must pass.

local failures = {}
local function check(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		table.insert(failures, name .. ": " .. tostring(err))
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

-- ── icons module ────────────────────────────────────────────────────────
check("icons: module shape", function()
	local i = require("config.icons")
	assert(type(i.kind) == "table", "kind missing")
	assert(i.kind.Function and i.kind.Variable and i.kind.Module, "kind entries missing")
	assert(i.diagnostics.Error and i.diagnostics.Warn and i.diagnostics.Hint and i.diagnostics.Info)
end)

check("icons: diagnostic signs use the shared table", function()
	local i = require("config.icons")
	local signs = vim.diagnostic.config().signs
	assert(type(signs) == "table" and type(signs.text) == "table", "signs.text not configured")
	assert(signs.text[vim.diagnostic.severity.ERROR] == i.diagnostics.Error, "sign column drifted from icons module")
end)

check("icons: blink kind icons come from the shared table", function()
	require("lazy").load({ plugins = { "blink.cmp" } })
	local kinds = require("blink.cmp.config").appearance.kind_icons
	assert(kinds.Function == require("config.icons").kind.Function, "blink kind_icons drifted from icons module")
end)

check("icons: breadcrumbs/navic boots against the shared table", function()
	require("lazy").load({ plugins = { "breadcrumbs.nvim" } })
	assert(package.loaded["nvim-navic"], "navic did not load")
end)

-- ── LSP module ──────────────────────────────────────────────────────────
check("lsp: every enabled server resolves a config", function()
	local servers = require("config.servers")
	for _, name in ipairs(servers.lsp_servers) do
		local cfg = vim.lsp.config[name]
		assert(type(cfg) == "table", name .. " has no resolvable config")
		assert(cfg.cmd, name .. " config has no cmd")
	end
end)

check("lsp: blink capabilities applied via the '*' default", function()
	local cfg = vim.lsp.config.ts_ls
	local snip = vim.tbl_get(cfg, "capabilities", "textDocument", "completion", "completionItem", "snippetSupport")
	assert(snip == true, "blink capabilities not merged into resolved server config")
end)

-- ── keymap registry ─────────────────────────────────────────────────────
check("keys: registry loads, has groups, rejects duplicates", function()
	local keys = require("config.keys")
	assert(#keys.groups >= 12, "expected >=12 group entries, got " .. #keys.groups)
	local prefixes = {}
	for _, g in ipairs(keys.groups) do
		assert(not prefixes[g[1]], "duplicate prefix " .. g[1])
		prefixes[g[1]] = true
	end
	assert(prefixes["<leader>q"] and prefixes["<leader>Q"], "quickfix/quarto groups missing")
	assert(not prefixes["<leader>r"], "phantom rename/restart group is back")
end)

check("keys: every <leader>xy mapping belongs to a registered group", function()
	local groups = {}
	for _, g in ipairs(require("config.keys").groups) do
		groups[g[1]:gsub("^<leader>", "")] = true
	end
	local leader = vim.g.mapleader
	local strays = {}
	for _, mode in ipairs({ "n", "x" }) do
		for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
			local rest = m.lhs:sub(1, #leader) == leader and m.lhs:sub(#leader + 1) or nil
			if rest and #rest >= 2 and not groups[rest:sub(1, 1)] then
				strays[#strays + 1] = mode .. " <leader>" .. rest
			end
		end
	end
	assert(#strays == 0, "no registered group for: " .. table.concat(strays, ", "))
end)

check("keys: which-key consumes the registry", function()
	require("lazy").load({ plugins = { "which-key.nvim" } })
	assert(package.loaded["config.keys"], "which-key did not require config.keys")
end)

check("keys: timeoutlen is 300 and stated in options.lua", function()
	assert(vim.o.timeoutlen == 300, "timeoutlen is " .. vim.o.timeoutlen)
end)

check("clipboard: Herdr sessions use the remote clipboard provider", function()
	local pane = vim.env.HERDR_PANE_ID
	local clipboard = vim.g.clipboard
	vim.env.HERDR_PANE_ID = "test"
	vim.g.clipboard = nil
	require("config.remote_clipboard").setup()
	assert(vim.g.clipboard.name == "OmarchyRemoteClipboard", "remote clipboard provider was not configured")
	assert(type(vim.g.clipboard.copy["+"]) == "function", "remote clipboard copy handler is missing")
	assert(type(vim.g.clipboard.paste["+"]) == "function", "remote clipboard paste handler is missing")
	vim.env.HERDR_PANE_ID = pane
	vim.g.clipboard = clipboard
end)

check("keys: <leader>/ is the built-in gc toggle", function()
	local rhs
	for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
		if m.lhs == " /" then
			rhs = m.rhs
		end
	end
	assert(rhs == "gcc", "<leader>/ rhs is " .. tostring(rhs) .. ", expected gcc")
	assert(package.loaded["Comment"] == nil, "Comment.nvim loaded — should be deleted")
end)

check("keys: built-in gt (next tab) is not shadowed", function()
	assert(vim.fn.maparg("gt", "n") == "", "gt is mapped: " .. vim.fn.maparg("gt", "n"))
end)

check("keys: <C-j>/<C-k> owned by neoscroll alone", function()
	local cj = vim.fn.maparg("<C-j>", "n")
	assert(cj:find("scroll") or cj:find("neoscroll"), "<C-j> not a neoscroll map: " .. cj)
	assert(cj ~= "<C-D>", "raw <C-D> nnoremap is back")
end)

-- ── omarchy theme seam ──────────────────────────────────────────────────
check("theme: Quattro link resolves and active colorscheme applied", function()
	local name = require("config.omarchy").get_colorscheme()
	assert(name == nil or type(name) == "string", "adapter returned " .. type(name))
	assert(vim.g.colors_name and #vim.g.colors_name > 0, "no colorscheme applied")

	local active = vim.fn.expand("~/.local/state/omarchy/current/theme/neovim.lua")
	if vim.fn.filereadable(active) == 1 then
		local link = vim.fn.stdpath("config") .. "/lua/plugins/theme.lua"
		assert(vim.uv.fs_lstat(link) and vim.uv.fs_lstat(link).type == "link", "Quattro theme link is missing")
		assert(vim.uv.fs_realpath(link) == vim.uv.fs_realpath(active), "Quattro theme link has the wrong target")
		assert(name, "Quattro theme exists but adapter returned nil")

		local theme_plugin
		for _, spec in ipairs(require("plugins.theme")) do
			if spec[1] and spec[1] ~= "LazyVim/LazyVim" then
				theme_plugin = spec
				break
			end
		end
		local registered = false
		for _, plugin in pairs(require("lazy.core.config").plugins) do
			if plugin[1] == theme_plugin[1] then
				local meta = getmetatable(plugin)
				while meta do
					local fragment = rawget(meta, "__index")
					registered = registered or vim.deep_equal(fragment, theme_plugin)
					meta = type(fragment) == "table" and getmetatable(fragment) or nil
				end
			end
		end
		assert(registered, "Quattro theme plugin was not registered by lazy.nvim")
	end

	if name then
		assert(vim.tbl_contains(vim.fn.getcompletion("", "color"), name), name .. " is not an available colorscheme")
		local applied = vim.g.colors_name
		if name == "catppuccin" then
			assert(vim.startswith(applied, "catppuccin"), "catppuccin alias applied " .. applied)
		else
			assert(applied == name, ("omarchy says %s but %s is active"):format(name, applied))
		end
	else
		assert(vim.startswith(vim.g.colors_name, "catppuccin"), "fallback should be catppuccin, got " .. vim.g.colors_name)
	end
end)

check("theme: adapter permits non-Omarchy fallback", function()
	local loaded = package.loaded["plugins.theme"]
	local preload = package.preload["plugins.theme"]
	package.loaded["plugins.theme"] = nil
	package.preload["plugins.theme"] = function()
		error("simulated non-Omarchy host")
	end
	local name = require("config.omarchy").get_colorscheme()
	package.preload["plugins.theme"] = preload
	package.loaded["plugins.theme"] = loaded
	assert(name == nil, "adapter should return nil without an Omarchy theme")

	local adapter = require("config.omarchy")
	local get_colorscheme = adapter.get_colorscheme
	local colorscheme_module = package.loaded["config.colorscheme"]
	local active = vim.g.colors_name
	adapter.get_colorscheme = function()
		return nil
	end
	package.loaded["config.colorscheme"] = nil
	vim.cmd.colorscheme("default")
	require("config.colorscheme")
	assert(vim.startswith(vim.g.colors_name, "catppuccin"), "non-Omarchy fallback was not applied")
	adapter.get_colorscheme = get_colorscheme
	package.loaded["config.colorscheme"] = colorscheme_module
	vim.cmd.colorscheme(active)
end)

check("theme: lualine namespace shadow is gone and lualine boots", function()
	assert(vim.fn.isdirectory(vim.fn.stdpath("config") .. "/lua/lualine") == 0, "lua/lualine/ shadow dir exists")
	require("lazy").load({ plugins = { "lualine.nvim" } })
	assert(package.loaded["lualine"], "lualine did not load")
	-- the config no longer injects a theme into lualine's namespace
	local origin = vim.api.nvim_get_runtime_file("lua/lualine/themes/default.lua", true)
	for _, path in ipairs(origin) do
		assert(not path:find(vim.fn.stdpath("config"), 1, true), "config still shadows lualine.themes.default")
	end
end)

check("mail: send guard flags typos in own text, not quoted lines", function()
	local typos = require("config.mail-compose").misspelled("Unfortunatley here\n> recieve\nfine text")
	assert(vim.deep_equal(typos, { "Unfortunatley" }), vim.inspect(typos))
end)

-- ── mail poller ─────────────────────────────────────────────────────────
local function envelopes_json(unseen, seen)
	local envs = {}
	for _ = 1, unseen do
		table.insert(envs, { flags = {} })
	end
	for _ = 1, seen do
		table.insert(envs, { flags = { { iana = "seen" } } })
	end
	return vim.json.encode({ envelopes = envs })
end

check("mail: notifies on unread increase, stop() halts polling", function()
	local mail = require("config.mail-notify")
	local sequence = { envelopes_json(1, 2), envelopes_json(3, 2), envelopes_json(3, 2) }
	local calls, notifications = 0, {}
	local orig_notify = vim.notify
	vim.notify = function(msg)
		table.insert(notifications, msg)
	end
	mail.start({
		accounts = { "testacct" },
		initial_delay_ms = 10,
		interval_ms = 40,
		runner = function(_, on_done)
			calls = calls + 1
			on_done(sequence[math.min(calls, #sequence)])
		end,
	})
	vim.wait(1000, function()
		return calls >= 2
	end)
	mail.stop()
	vim.notify = orig_notify
	assert(calls >= 2, "poller ticked " .. calls .. " times")
	local found
	for _, msg in ipairs(notifications) do
		if msg:find("new email") then
			found = msg
		end
	end
	assert(found, "no new-mail notification fired")
	assert(found:find("2 new emails in testacct", 1, true), "unexpected notification: " .. found)
	local settled = calls
	vim.wait(150)
	assert(calls == settled, "runner still polling after stop()")
end)

check("mail: schema drift warns loudly instead of reporting zero", function()
	local mail = require("config.mail-notify")
	local warned
	local orig_notify = vim.notify
	vim.notify = function(msg)
		if msg:find("schema") then
			warned = true
		end
	end
	mail.start({
		accounts = { "testacct" },
		initial_delay_ms = 10,
		interval_ms = 5000,
		runner = function(_, on_done)
			on_done('{"not_envelopes": []}')
		end,
	})
	vim.wait(1000, function()
		return warned
	end)
	mail.stop()
	vim.notify = orig_notify
	assert(warned, "schema drift was silent")
end)

-- ── herdr adapter ───────────────────────────────────────────────────────
check("herdr: pane list maps to sessions, non-agent panes ignored", function()
	require("lazy").load({ plugins = { "sidekick.nvim" } })
	local herdr = require("config.herdr")
	local sessions = herdr.sessions({
		{ pane_id = "w1:p1", cwd = "/tmp/a", workspace_id = "w1" }, -- plain shell
		{ pane_id = "w1:p3", cwd = "/tmp/b", foreground_cwd = "/tmp/c", agent = "pi", workspace_id = "w1" },
		{ pane_id = "w1:p4", cwd = "/tmp/d", agent = "not-a-sidekick-tool", workspace_id = "w1" },
	})
	assert(#sessions == 1, ("expected 1 session, got %d"):format(#sessions))
	assert(sessions[1].id == "herdr w1:p3", "session id is not keyed on the pane id")
	assert(sessions[1].herdr_pane_id == "w1:p3", "pane id not carried onto the session")
	assert(sessions[1].cwd == "/tmp/c", "foreground_cwd should win over the pane's start cwd")
	assert(sessions[1].tool.name == "pi", "agent label did not resolve to the sidekick tool")
end)

check("herdr: setup is a no-op outside a herdr pane", function()
	local Config = require("sidekick.config")
	local before = Config.cli.mux.backend
	local orig = vim.env.HERDR_ENV
	vim.env.HERDR_ENV = nil
	require("config.herdr").setup()
	vim.env.HERDR_ENV = orig
	assert(Config.cli.mux.backend == before, "backend was hijacked while outside herdr")
end)

-- ── pane and window navigation ──────────────────────────────────────────
check("herdr: shell and TUI shortcuts open real panes", function()
	local herdr = require("config.herdr")
	local Util = require("sidekick.util")
	local available, exec = herdr.available, Util.exec
	local calls = {}
	herdr.available = function()
		return true
	end
	Util.exec = function(cmd)
		calls[#calls + 1] = cmd
		if cmd[3] == "split" then
			return nil, vim.json.encode({ result = { pane = { pane_id = "test-pane" } } })
		end
	end
	local shell = vim.fn.maparg("<c-/>", "n", false, true).callback
	local lazygit = vim.fn.maparg("<leader>gg", "n", false, true).callback
	assert(type(shell) == "function" and type(lazygit) == "function", "herdr pane shortcuts are missing")
	shell()
	lazygit()
	herdr.available, Util.exec = available, exec

	local split = {
		"herdr",
		"pane",
		"split",
		"--current",
		"--direction",
		"right",
		"--ratio",
		"0.45",
		"--cwd",
		vim.fn.getcwd(),
		"--focus",
	}
	assert(vim.deep_equal(calls[1], split), "shell shortcut did not split a focused herdr pane")
	assert(vim.deep_equal(calls[2], split), "lazygit shortcut did not split a focused herdr pane")
	assert(
		vim.deep_equal(calls[3], { "herdr", "pane", "run", "test-pane", "lazygit" }),
		"lazygit was not run in the new pane"
	)
	for _, dir in ipairs({ "h", "j", "k", "l" }) do
		assert(vim.fn.maparg("<m-" .. dir .. ">", "n") == "", "local window navigation bypasses SUPER+hjkl")
		assert(vim.fn.maparg("<m-" .. dir .. ">", "t") == "", "terminal navigation bypasses SUPER+hjkl")
	end
end)

check("mail: IMAP STATUS counts, unread()/accounts(), MailUnread fires on change only", function()
	local mail = require("config.mail-notify")
	local seq = { '{"unseen":25,"messages":238}', '{"unseen":25,"messages":238}', '{"unseen":27,"messages":240}' }
	local calls, events = 0, 0
	local au = vim.api.nvim_create_autocmd("User", { pattern = "MailUnread", callback = function() events = events + 1 end })
	local orig_notify = vim.notify
	vim.notify = function() end
	mail.start({
		accounts = { "a1" },
		initial_delay_ms = 5,
		interval_ms = 30,
		runner = function(_, on_done)
			calls = calls + 1
			on_done(seq[math.min(calls, #seq)])
		end,
	})
	vim.wait(1000, function() return calls >= 3 end)
	mail.stop()
	vim.notify = orig_notify
	vim.api.nvim_del_autocmd(au)
	assert(mail.unread("a1") == 27, "unread(): " .. tostring(mail.unread("a1")))
	assert(vim.deep_equal(mail.accounts(), { "a1" }), "accounts()")
	assert(events == 2, "MailUnread must fire on first count and on change only, fired " .. events)
end)

check("dashboard: one mail row per account with key and unread count", function()
	package.loaded["plugins.snacks"] = nil
	local spec = require("plugins.snacks")
	local gen
	for _, sec in ipairs(spec.opts.dashboard.sections) do
		if type(sec) == "function" then gen = sec end
	end
	assert(gen, "no dynamic mail section")
	local mail = require("config.mail-notify")
	local orig_notify = vim.notify
	vim.notify = function() end
	mail.start({ accounts = { "gmail", "work" }, initial_delay_ms = 5, interval_ms = 100000, runner = function(acct, on_done)
		on_done(acct == "gmail" and '{"unseen":42}' or '{"unseen":0}')
	end })
	vim.wait(500, function() return mail.unread("work") ~= nil end)
	mail.stop()
	vim.notify = orig_notify
	local items = gen()
	assert(#items == 2, vim.inspect(items))
	assert(items[1].key == "g" and items[1].desc:find("gmail") and items[1].desc:find("42 unread") and items[1].action == ":Mail gmail", vim.inspect(items[1]))
	assert(items[2].key == "w" and items[2].desc:find("no unread") and items[2].action == ":Mail work", vim.inspect(items[2]))
end)

-- ── mail compose ────────────────────────────────────────────────────────
-- Synthetic message in himalaya v2's `message read --json` (mail-parser) shape.
local function addr_list(...)
	return { Address = { List = { ... } } }
end
local fixture = {
	text_body = { 1 },
	html_body = {},
	attachments = {},
	parts = {
		{
			headers = {
				{ name = "from", value = addr_list({ name = "Ann Sender", address = "ann@example.com" }) },
				{ name = "to", value = addr_list({ name = "Me (me@example.com)", address = "me@example.com" }, { name = vim.NIL, address = "bob@example.com" }) },
				{ name = "cc", value = addr_list({ name = "Carl", address = "carl@example.com" }, { name = "", address = "ANN@example.com" }) },
				{ name = "subject", value = { Text = "RE: plan" } },
				{ name = "message_id", value = { Text = "m2@example.com" } },
				{ name = "references", value = { Text = "m1@example.com" } },
				{ name = "date", value = { DateTime = { year = 2026, month = 10, day = 2, hour = 21, minute = 6, second = 0, tz_before_gmt = false, tz_hour = 0, tz_minute = 0 } } },
			},
		},
		{ headers = {}, body = { Text = "line one\r\n\r\nline two" } },
	},
}

check("mail-compose: reply-all fields, threading, quoting", function()
	local mc = require("config.mail-compose")
	local f = mc.reply_fields(fixture, "Me <me@example.com>", true)
	assert(f.to == "Ann Sender <ann@example.com>", "to: " .. f.to)
	assert(f.cc == "bob@example.com, Carl <carl@example.com>", "cc must drop self and the replied-to sender: " .. f.cc)
	assert(f.subject == "RE: plan", "existing Re: prefix doubled: " .. f.subject)
	assert(f.in_reply_to == "<m2@example.com>")
	assert(f.references == "<m1@example.com> <m2@example.com>", "references: " .. f.references)
	assert(f.body:find("> line one\n>\n> line two", 1, true), "quote: " .. f.body)
	assert(mc.reply_fields(fixture, "me@example.com", false).cc == "", "plain reply must not Cc")
end)

check("mail-compose: body drops zero-width preheader padding", function()
	local f = vim.deepcopy(fixture)
	f.parts[2].body = { Text = "Sale.\226\128\140 \226\128\140 \226\128\140\194\173 Hi\239\187\191 there" }
	local body = require("config.mail-compose").summary(f).body
	assert(body == "Sale. Hi there", "zero-width chars must not reach the reader: " .. vim.inspect(body))
end)

check("mail-compose: buffer parse and header injection", function()
	local mc = require("config.mail-compose")
	local m = mc.parse({ "From: me@example.com", "To: a@example.com", "Subject: hi: there", "Attach: /tmp/x.pdf", "Attach: ", "", "body", "", "To: not a header" })
	assert(m.headers.To == "a@example.com" and m.headers.Subject == "hi: there")
	assert(#m.attach == 1 and m.attach[1] == "/tmp/x.pdf", "attach parse")
	assert(m.body == "body\n\nTo: not a header", "body: " .. m.body)
	local tight = mc.parse({ "To: a@example.com", "Cc: <c@example.com>", "Attach: ", "Note: first line", "second" })
	assert(tight.body == "Note: first line\nsecond", "no blank separator must not lose body: " .. tight.body)
	assert(mc.split_addrs(tight.headers.Cc)[1].address == "c@example.com", "angle-only address")
	local mime = "From: a\r\nTo: <x@y>,\r\n\t<z@y>\r\nSubject: s\r\n\r\nbody\r\n"
	local out = mc.set_headers(mime, { To = "Ann <x@y>", ["In-Reply-To"] = "<x@y>" })
	assert(out == "From: a\r\nTo: Ann <x@y>\r\nSubject: s\r\nIn-Reply-To: <x@y>\r\n\r\nbody\r\n", "set_headers: " .. out)
	assert(mc.set_headers(mime, {}) == mime)
	local a = mc.split_addrs('"Doe, J (z@x.io)" <z@x.io>, Kim <m@x.io>,  bare@x.io')
	assert(#a == 3, "split on quoted comma: " .. vim.inspect(a))
	assert(a[1].name == "Doe, J (z@x.io)" and a[1].address == "z@x.io")
	assert(a[3].name == "" and a[3].address == "bare@x.io")
end)

check("mail-compose: attaching fills the empty Attach line, else adds one", function()
	local mc = require("config.mail-compose")
	local base = { "To: a@example.com", "Subject: s", "Attach: ", "", "Attach: body text" }
	local one = mc.add_attachment(base, "/tmp/a.pdf")
	assert(one[3] == "Attach: /tmp/a.pdf" and #one == 5, vim.inspect(one))
	local two = mc.add_attachment(one, "/tmp/b.pdf")
	assert(two[4] == "Attach: /tmp/b.pdf" and two[5] == "" and two[6] == "Attach: body text", vim.inspect(two))
	assert(#mc.parse(two).attach == 2, "both attachments must parse")
end)

check("mail-compose: send pipeline composes, threads, sends, flags", function()
	local mc = require("config.mail-compose")
	local real, calls = mc.himalaya, {}
	local accounts_json = vim.json.encode({ accounts = { { name = "work", default = false, backends = { "imap", "smtp" } }, { name = "gmail", default = true, backends = { "imap", "smtp" } } } })
	mc.himalaya = function(args, stdin, cb)
		table.insert(calls, { args = args, stdin = stdin })
		if args[1] == "account" then
			return cb(true, accounts_json, "")
		end
		cb(true, vim.tbl_contains(args, "compose") and "From: me\r\nSubject: s\r\nDate: Wed, 7 Oct 2026 00:00:00 +0000\r\n\r\nhello\r\n" or "", "")
	end
	local function find(c, word)
		for _, call in ipairs(c) do
			if vim.tbl_contains(call.args, word) then
				return call
			end
		end
	end
	local function run(account)
		calls = {}
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "From: me@example.com", "To: José <a@example.com>, \"B, C\" <b@example.com>", "Subject: s", "", "hello" })
		vim.b[buf].mail_compose = { kind = "reply", account = account, mailbox = "inbox", reply_id = "7", in_reply_to = "<m@x>", references = "<m@x>" }
		local ok, err = pcall(mc.submit, buf, "send")
		local kept = vim.api.nvim_buf_is_valid(buf)
		if kept then -- a modified leftover buffer would block the suite's +qa
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		assert(ok, err)
		assert(not kept, "buffer kept after successful send")
		return calls
	end
	local ok, c = pcall(run, "work")
	if not ok then
		mc.himalaya = real
		error(c)
	end
	local compose, send, flag = find(c, "compose"), find(c, "send"), find(c, "answered")
	assert(compose and send and flag, "expected compose, send, flag: " .. vim.inspect(c))
	assert(vim.tbl_contains(compose.args, "-b") and vim.tbl_contains(compose.args, "smtp"), "compose must use the offline smtp backend")
	assert(vim.deep_equal({ send.args[1], send.args[2], send.args[3], send.args[4] }, { "-a", "work", "message", "send" }))
	assert(send.args[6] == "sent", "work must save a Sent copy")
	assert(send.stdin:find("In-Reply-To: <m@x>\r\n", 1, true), "threading header not injected")
	assert(send.stdin:find('To: =?UTF-8?B?Sm9zw6k=?= <a@example.com>, "B, C" <b@example.com>', 1, true), "display names not restored: " .. send.stdin)
	local to_flags = 0
	for i, v in ipairs(compose.args) do
		if v == "--to" then
			to_flags = to_flags + 1
			assert(not compose.args[i + 1]:find("[<,]"), "composer must get bare addresses")
		end
	end
	assert(to_flags == 2, "one --to per address")
	assert(flag.args[#flag.args] == "7", "replied message not flagged")
	ok, c = pcall(run, "gmail")
	mc.himalaya = real
	assert(ok, c)
	assert(not vim.tbl_contains(find(c, "send").args, "--save"), "gmail files Sent itself; --save would duplicate")
end)

check("mail-compose: :w and ZZ open the menu after the command; ZZ can discard", function()
	package.loaded["config.mail-compose"] = nil
	local mc = require("config.mail-compose")
	mc.himalaya = function(args, _, cb)
		cb(true, vim.tbl_contains(args, "compose") and "From: <me@example.com>\r\n\r\n" or "", "")
	end
	local orig_select, seen = vim.ui.select, {}
	vim.ui.select = function(items, _, on_choice)
		table.insert(seen, items)
		on_choice(items[#seen == 2 and 3 or #items]) -- :w → Cancel, ZZ → Discard
	end
	local ok, err = pcall(function()
		mc.compose({ account = "testacct" })
		local buf = vim.api.nvim_get_current_buf()
		assert(vim.api.nvim_buf_get_name(buf):find("himalaya://compose"), "compose buffer not opened")
		vim.cmd("write")
		assert(#seen == 0, "menu must not open inside BufWriteCmd (steals focus)")
		vim.wait(500, function() return #seen == 1 end)
		assert(vim.deep_equal(seen[1], { "Send", "Save draft", "Cancel" }), vim.inspect(seen[1]))
		assert(vim.api.nvim_buf_is_valid(buf), "Cancel must keep the buffer")
		vim.api.nvim_feedkeys("ZZ", "x", false)
		vim.wait(500, function() return #seen == 2 end)
		assert(vim.deep_equal(seen[2], { "Send", "Save draft", "Discard", "Cancel" }), vim.inspect(seen[2]))
		assert(not vim.api.nvim_buf_is_valid(buf), "ZZ → Discard must close the message")
	end)
	vim.ui.select = orig_select
	package.loaded["config.mail-compose"] = nil
	assert(ok, err)
end)

check("mail-browse: envelopes with JSON-null fields render (drafts have no Date)", function()
	local mb = require("config.mail-browse")
	local line = mb.render_line({ id = "4", flags = vim.NIL, subject = vim.NIL, from = vim.NIL, date = vim.NIL, ["has-attachment"] = vim.NIL })
	assert(type(line) == "string" and line:find("?", 1, true), "all-null envelope: " .. tostring(line))
	local line2 = mb.render_line({ id = "5", flags = { vim.NIL }, subject = "s", from = { { name = vim.NIL, email = vim.NIL } }, date = "garbage" })
	assert(line2:find("s$"), "partial-null envelope: " .. line2)
end)

check("mail-browse: move uses --from; delete/move name the message", function()
	local mb = require("config.mail-browse")
	local mc = require("config.mail-compose")
	local real, calls, notes = mc.himalaya, {}, {}
	local orig_notify, orig_select = vim.notify, vim.ui.select
	vim.notify = function(m) table.insert(notes, m) end
	vim.ui.select = function(items, _, cb) cb(items[2]) end
	mc.himalaya = function(args, _, cb)
		table.insert(calls, args)
		if args[1] == "account" then
			return cb(true, vim.json.encode({ accounts = { { name = "t", default = true, backends = {} } } }), "")
		elseif vim.tbl_contains(args, "mailbox") then
			return cb(true, vim.json.encode({ mailboxes = { { name = "Inbox" }, { name = "Archive" } } }), "")
		elseif vim.tbl_contains(args, "envelope") then
			return cb(true, vim.json.encode({ envelopes = { { id = "5", flags = {}, subject = "Quarterly plan", from = { { email = "a@example.com" } }, date = "2026-01-01T00:00:00Z" } } }), "")
		end
		cb(true, "From: <me@example.com>\r\n\r\n", "")
	end
	local ok, err = pcall(function()
		vim.cmd("tabnew")
		mb.open({ account = "t", mailbox = "Inbox" })
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_feedkeys("gm", "x", false)
		local mv
		for _, a in ipairs(calls) do
			if vim.tbl_contains(a, "move") then mv = a end
		end
		assert(mv, "no move call")
		assert(vim.tbl_contains(mv, "--from") and not vim.tbl_contains(mv, "-m"), "move must name source with --from: " .. vim.inspect(mv))
		assert(mv[vim.fn.index(mv, "--to") + 2] == "Archive" and mv[#mv] == "5", vim.inspect(mv))
		assert(vim.tbl_contains(notes, "Moved to Archive: Quarterly plan"), vim.inspect(notes))
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_feedkeys("d", "x", false)
		assert(vim.tbl_contains(notes, "Deleted: Quarterly plan"), vim.inspect(notes))
		vim.cmd("tabclose")
	end)
	mc.himalaya, vim.notify, vim.ui.select = real, orig_notify, orig_select
	assert(ok, err)
end)

check("mail-browse: out-of-order loads never resurrect a stale list", function()
	local mb = require("config.mail-browse")
	local mc = require("config.mail-compose")
	local real, pending = mc.himalaya, {}
	mc.himalaya = function(args, _, cb)
		if args[1] == "account" then
			return cb(true, vim.json.encode({ accounts = { { name = "t", default = true, backends = {} } } }), "")
		end
		if vim.tbl_contains(args, "envelope") then
			local box = args[vim.fn.index(args, "-m") + 2]
			return table.insert(pending, function()
				cb(true, vim.json.encode({ envelopes = { { id = box, flags = {}, subject = "from " .. box, from = { { email = "x@example.com" } }, date = "2026-01-01T00:00:00Z" } } }), "")
			end)
		end
		cb(true, "From: <me@example.com>\r\n\r\n", "")
	end
	local ok, err = pcall(function()
		vim.cmd("tabnew")
		mb.open({ account = "t", mailbox = "A" })
		local buf = vim.api.nvim_get_current_buf()
		assert(#vim.b[buf].mail_list.envelopes == 0, "rows must be empty while loading")
		vim.b[buf].mail_list = vim.tbl_extend("force", vim.b[buf].mail_list, { mailbox = "B" })
		vim.api.nvim_feedkeys("R", "x", false) -- reload as B while A is in flight
		pending[2]() -- B answers first
		pending[1]() -- then the stale A response
		local s = vim.b[buf].mail_list
		assert(s.mailbox == "B" and s.envelopes[1].id == "B", "stale response won: " .. vim.inspect(s))
		vim.cmd("tabclose")
	end)
	mc.himalaya = real
	assert(ok, err)
end)

check("mail-compose: mixed line endings never eat headers or body (draft-corruption regression)", function()
	local mc = require("config.mail-compose")
	-- LF headers, a stray CRLF inside the body: the old code split headers on CRLF
	-- and collapsed the whole block into one "From:" line
	local mixed = "From: <me@x.io>\nTo: <a@x.io>\nSubject: keep me\nDate: Wed, 7 Oct 2026 00:00:00 +0000\nMIME-Version: 1.0\n\nline one\r\nline two\n"
	local out = mc.set_headers(mixed, { From = "Me <me@x.io>", To = "Ann <a@x.io>" })
	assert(out:find("Subject: keep me", 1, true) and out:find("Date: Wed", 1, true), "headers eaten: " .. out)
	assert(out:find("line one\r\nline two", 1, true), "body eaten: " .. out)
	assert(out:find("^From: Me <me@x%.io>\r\nTo: Ann <a@x%.io>\r\nSubject"), "rewrite/ordering: " .. out)
	assert(mc.well_formed(out, mixed, "keep me"), "well-formed message rejected")
	-- the exact corrupted shape seen live must be rejected
	local bad = "From: me@x.io\r\nTo: me@x.io"
	assert(not mc.well_formed(bad, mixed, "keep me"), "corrupted build accepted")
	assert(not mc.well_formed("From: a\r\nDate: x\r\n\r\nb", nil, "subject given"), "lost Subject accepted")
	assert(not mc.well_formed("From: a\r\nDate: x\r\n\r\nb", string.rep("x", 20000), nil), "big shrink accepted")
end)

check("mail-compose: a malformed build is refused, buffer and text kept", function()
	package.loaded["config.mail-compose"] = nil
	local mc = require("config.mail-compose")
	local calls, errors = {}, {}
	local orig_notify = vim.notify
	vim.notify = function(m, lvl)
		if lvl == vim.log.levels.ERROR then
			table.insert(errors, m)
		end
	end
	mc.himalaya = function(args, _, cb)
		table.insert(calls, args)
		cb(true, args[1] == "account" and vim.json.encode({ accounts = {} }) or "", "") -- compose "succeeds" with empty output
	end
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "To: a@example.com", "", "precious text" })
	vim.b[buf].mail_compose = { kind = "compose", account = "w" }
	local ok, err = pcall(mc.submit, buf, "draft")
	vim.notify = orig_notify
	local kept = vim.api.nvim_buf_is_valid(buf)
	local text = kept and vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1]
	if kept then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	package.loaded["config.mail-compose"] = nil
	assert(ok, err)
	for _, a in ipairs(calls) do
		assert(not vim.tbl_contains(a, "add") and not vim.tbl_contains(a, "send"), "malformed build was saved/sent")
	end
	assert(kept and text == "precious text", "buffer/text lost on failed build")
	assert(errors[1] and errors[1]:find("no usable message"), "failure not surfaced: " .. vim.inspect(errors))
end)

check("mail-compose: refuses Bcc send on himalaya < 2.2.1 (leaks Bcc, #747)", function()
	package.loaded["config.mail-compose"] = nil -- fresh version cache
	local mc = require("config.mail-compose")
	local calls, errors = {}, {}
	local orig_notify = vim.notify
	vim.notify = function(m, lvl)
		if lvl == vim.log.levels.ERROR then
			table.insert(errors, m)
		end
	end
	mc.himalaya = function(args, _, cb)
		table.insert(calls, args)
		cb(true, args[1] == "--version" and "himalaya v2.1.0 +imap" or "", "")
	end
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "To: a@example.com", "Bcc: hidden@example.com", "", "x" })
	vim.b[buf].mail_compose = { kind = "compose", account = "work" }
	local ok, err = pcall(mc.submit, buf, "send")
	vim.notify = orig_notify
	vim.api.nvim_buf_delete(buf, { force = true })
	package.loaded["config.mail-compose"] = nil
	assert(ok, err)
	for _, a in ipairs(calls) do
		assert(not vim.tbl_contains(a, "compose") and not vim.tbl_contains(a, "send"), "must stop before composing/sending; calls: " .. vim.inspect(calls))
	end
	assert(vim.tbl_contains(vim.tbl_map(function(a) return a[1] end, calls), "--version"), "version never checked")
	assert(errors[1] and errors[1]:find("Bcc"), "no Bcc refusal surfaced")
end)

check("mail-browse: list renders, <CR> reads in a normal split and marks seen", function()
	local mb = require("config.mail-browse")
	local mc = require("config.mail-compose")
	local real, calls = mc.himalaya, {}
	local envelopes = {
		{ id = "9", flags = {}, subject = "Plan", from = { { name = "Ann", email = "ann@example.com" } }, date = "2026-10-04T22:17:06Z", ["has-attachment"] = true },
		{ id = "8", flags = { { iana = "seen" } }, subject = "Old", from = { { name = vim.NIL, email = "bob@example.com" } }, date = "2026-10-03T08:00:00Z", ["has-attachment"] = vim.NIL },
	}
	mc.himalaya = function(args, _, cb)
		table.insert(calls, args)
		if vim.tbl_contains(args, "envelope") then
			cb(true, vim.json.encode({ envelopes = envelopes }), "")
		elseif args[1] == "account" then
			cb(true, vim.json.encode({ accounts = { { name = "testacct", default = true, backends = { "smtp" } } } }), "")
		elseif vim.tbl_contains(args, "read") then
			cb(true, vim.json.encode({
				text_body = { 1 }, html_body = {}, attachments = { 2 },
				parts = {
					{ headers = {
						{ name = "from", value = { Address = { List = { { name = "Ann", address = "ann@example.com" } } } } },
						{ name = "subject", value = { Text = "Plan" } },
					} },
					{ headers = {}, body = { Text = "hello" } },
					{ headers = { { name = "content_disposition", value = { ContentType = { c_type = "attachment", attributes = { { name = "filename", value = "spec.pdf" } } } } } }, body = { Binary = { 37, 80, 68, 70 } } },
				},
			}), "")
		else
			cb(true, "From: <me@example.com>\r\n\r\n", "")
		end
	end
	local ok, err = pcall(function()
		vim.cmd("tabnew")
		mb.open({ account = "testacct" })
		local list = vim.api.nvim_get_current_buf()
		local lines = vim.api.nvim_buf_get_lines(list, 0, -1, false)
		assert(#lines == 2, "list lines: " .. vim.inspect(lines))
		assert(lines[1]:find("^●") and lines[1]:find("@") and lines[1]:find("Ann") and lines[1]:find("Plan"), "unread row: " .. lines[1])
		assert(lines[2]:find("bob@example.com", 1, true), "null name must fall back to address: " .. lines[2])
		assert(lines[2]:sub(1, 3) == "   ", "JSON null has-attachment must not show @: " .. lines[2])
		assert(vim.fn.win_gettype() == "", "list must be a normal window, not a float")
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
		local reader = vim.api.nvim_get_current_buf()
		assert(reader ~= list and vim.b[reader].mail_msg.id == "9", "reader not focused")
		assert(vim.fn.win_gettype() == "" and #vim.api.nvim_tabpage_list_wins(0) == 2, "reader must be a normal split")
		local shown = vim.api.nvim_buf_get_lines(reader, 0, -1, false)
		assert(shown[#shown] == "hello", "body not shown: " .. vim.inspect(shown))
		assert(table.concat(shown, "\n"):find("Attachment: spec.pdf (4 B)", 1, true), "attachment not listed: " .. vim.inspect(shown))
		local gF = vim.fn.maparg("gF", "n", false, true)
		assert(gF.buffer == 1 and gF.desc == "Mail: Switch mailbox", "gF must work from the reader pane")
		assert(vim.tbl_contains(calls[#calls], "--seen"), "read must mark seen")
		assert(vim.api.nvim_buf_get_lines(list, 0, 1, false)[1]:find("^ "), "row still unread after reading")
		vim.cmd("tabclose")
	end)
	mc.himalaya = real
	assert(ok, err)
end)

-- ── editor behaviour ────────────────────────────────────────────────────
check("autocmd: VimResized equalizes splits without leaving the current tab", function()
	vim.cmd("tabnew")
	vim.cmd("tabnew")
	vim.cmd("tabprevious")
	local before = vim.fn.tabpagenr()
	vim.api.nvim_exec_autocmds("VimResized", {})
	assert(vim.fn.tabpagenr() == before, "VimResized moved to tab " .. vim.fn.tabpagenr())
	vim.cmd("tabonly")
end)

check("lualine: LSP diagnostics are counted once", function()
	local src = require("lualine").get_config().sections.lualine_b[3].sources
	assert(not vim.tbl_contains(src, "nvim_lsp"), "nvim_lsp duplicates nvim_diagnostic")
end)

check("save: prose is left alone, code is trimmed", function()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	local function saved(name, line)
		vim.cmd("edit " .. dir .. "/" .. name)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
		vim.cmd("write")
		return vim.fn.readfile(dir .. "/" .. name)[1]
	end
	assert(saved("a.md", "hard break  ") == "hard break  ", "markdown trailing spaces stripped on save")
	assert(saved("b.sh", "echo hi   ") == "echo hi", "code not trimmed on save")
	vim.cmd("%bwipeout!")
	vim.fn.delete(dir, "rf")
end)

check("clingo: .lp is clingo, % comments, potassco grammar registered", function()
	vim.cmd("edit " .. vim.fn.tempname() .. ".lp")
	assert(vim.bo.filetype == "clingo", ".lp detected as " .. vim.bo.filetype)
	assert(vim.bo.commentstring == "% %s", "commentstring " .. vim.bo.commentstring)
	require("lazy").load({ plugins = { "nvim-treesitter" } })
	vim.api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
	local info = require("nvim-treesitter.parsers").clingo
	assert(info and info.install_info.url:find("potassco/tree-sitter-clingo", 1, true), "clingo parser not registered")
	vim.cmd("bwipeout!")
end)

-- ── LSP overrides / obsidian gating ─────────────────────────────────────
check("lsp: after/lsp overrides win over nvim-lspconfig's bundled configs", function()
	local tw = vim.lsp.config.tailwindcss
	assert(not vim.tbl_contains(tw.filetypes, "markdown"), "tailwindcss override lost: attaches to markdown")
	local mk = vim.lsp.config.marksman.root_markers
	assert(type(mk[1]) == "table" and vim.tbl_contains(mk[1], ".obsidian"), "marksman override lost")
end)

check("obsidian: loads only for files inside a vault (.obsidian ancestor)", function()
	local loaded = function()
		return require("lazy.core.config").plugins["obsidian.nvim"]._.loaded ~= nil
	end
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/plain", "p")
	vim.fn.mkdir(root .. "/vault/.obsidian", "p")
	vim.fn.mkdir(root .. "/vault/notes", "p")
	vim.cmd("edit " .. root .. "/plain/a.md")
	assert(not loaded(), "obsidian.nvim loaded for markdown outside a vault")
	vim.cmd("edit " .. root .. "/vault/notes/b.md")
	assert(loaded(), "obsidian.nvim did not load inside a vault")
	local ws = require("obsidian").get_client().current_workspace.root.filename
	assert(ws == root .. "/vault", "workspace should be the vault root, got " .. tostring(ws))
	vim.cmd("%bwipeout!")
	vim.fn.delete(root, "rf")
end)

check("lean: lean.nvim stays unloaded until a .lean file is opened", function()
	local lean = require("lazy.core.config").plugins["lean.nvim"]
	assert(lean, "lean.nvim spec missing")
	assert(lean._.loaded == nil, "lean.nvim loaded at startup")
end)

-- ── result ──────────────────────────────────────────────────────────────
if #failures == 0 then
	print("SMOKE-PASS")
else
	print(("SMOKE-FAIL (%d)"):format(#failures))
end
