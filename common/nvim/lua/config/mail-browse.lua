-- Mail browser in ordinary windows (no floats, so SUPER+hjkl works as
-- everywhere else), driven by the himalaya v2 CLI.
--
-- :Mail [account] lists a mailbox in the current window; <CR> reads the
-- message in a split below (reused per tab). Composing, replying, forwarding
-- and draft editing hand off to config.mail-compose. CLI calls go through
-- mail-compose's M.himalaya — the one seam, replaced in tests.
local M = {}

local function mc()
	return require("config.mail-compose")
end

local function cli(args, cb)
	mc().himalaya(args, nil, cb)
end

local function fail(what, err)
	vim.notify(what .. ": " .. vim.trim(err), vim.log.levels.ERROR, { title = "Mail" })
end

local function acct(account, ...)
	local args = account and account ~= "" and { "-a", account } or {}
	return vim.list_extend(args, { ... })
end

-- ── list rendering (pure) ──────────────────────────────────────────────────

local utc_offset = os.time() - os.time(os.date("!*t"))

-- "2026-10-04T22:17:06Z" / "...+02:00" → local "10-04 17:17"
-- himalaya emits JSON null for absent fields (a draft has no Date); null
-- decodes to vim.NIL, which is truthy — so `x or ""` is not enough.
local function str(v)
	return type(v) == "string" and v or ""
end

local function local_date(iso)
	iso = str(iso)
	local y, mo, d, h, mi, s, rest = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)(.*)$")
	if not y then
		return iso:sub(1, 11)
	end
	local sign, oh, om = rest:match("([+-])(%d%d):?(%d%d)")
	local off = sign and (sign == "-" and -1 or 1) * (tonumber(oh) * 3600 + tonumber(om) * 60) or 0
	local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s }) + utc_offset - off
	return os.date("%m-%d %H:%M", t)
end

local function has_flag(env, name)
	for _, f in ipairs(type(env.flags) == "table" and env.flags or {}) do
		if type(f) == "table" and f.iana == name then
			return true
		end
	end
	return false
end

local function pad(str, width)
	str = str:gsub("[\r\n]", " ")
	if vim.fn.strdisplaywidth(str) > width then
		str = vim.fn.strcharpart(str, 0, width - 1) .. "…"
	end
	return str .. string.rep(" ", width - vim.fn.strdisplaywidth(str))
end

--- One list line per envelope. Pure.
function M.render_line(env)
	local from = type(env.from) == "table" and type(env.from[1]) == "table" and env.from[1] or {}
	local who = str(from.name) ~= "" and from.name or str(from.email) ~= "" and from.email or "?"
	local mark = (has_flag(env, "seen") and " " or "●") .. (has_flag(env, "flagged") and "!" or " ") .. (env["has-attachment"] == true and "@" or " ")
	return string.format("%s %s  %s  %s", mark, local_date(env.date), pad(who, 22), (str(env.subject):gsub("[\r\n]", " ")))
end

-- ── list buffer ────────────────────────────────────────────────────────────

local function list_state(buf)
	return vim.b[buf or 0].mail_list
end

local function set_lines(buf, lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
end

local function render(buf)
	local s = list_state(buf)
	local lines = vim.tbl_map(M.render_line, s.envelopes)
	if #lines == 0 then
		lines = { "  (no messages)" }
	end
	set_lines(buf, lines)
	local title = string.format("%s · %s · page %d%s", s.account, s.mailbox, s.page, s.query and ("  /" .. s.query) or "")
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.wo[win].winbar = " " .. title:gsub("%%", "%%%%")
	end
end

local generation = {} -- buf → id of the newest load; older responses are dropped

local function load(buf)
	local s = list_state(buf)
	generation[buf] = (generation[buf] or 0) + 1
	local gen = generation[buf]
	-- clear rows first: keys pressed while loading must not hit stale messages
	s.envelopes = {}
	vim.b[buf].mail_list = s
	local win = vim.fn.bufwinid(buf)
	local size = math.max(10, (win ~= -1 and vim.api.nvim_win_get_height(win) or 30) - 1)
	local args = acct(s.account, "envelope", s.query and "search" or "list", "-m", s.mailbox, "-p", tostring(s.page), "-s", tostring(size), "--json")
	if s.query then
		vim.list_extend(args, vim.split(s.query, "%s+", { trimempty = true }))
	end
	set_lines(buf, { "  loading…" })
	cli(args, function(ok, out, err)
		if not vim.api.nvim_buf_is_valid(buf) or generation[buf] ~= gen then
			return
		end
		local okj, data = pcall(vim.json.decode, ok and out or "")
		if not ok or not okj or type(data) ~= "table" or type(data.envelopes) ~= "table" then
			set_lines(buf, { "  failed to load: " .. vim.trim(err ~= "" and err or "unexpected himalaya JSON"):gsub("\n", " ") })
			return
		end
		local current = list_state(buf) -- re-read: never write back a stale snapshot
		current.envelopes = data.envelopes
		vim.b[buf].mail_list = current
		render(buf)
	end)
end

local function update(buf, changes)
	vim.b[buf].mail_list = vim.tbl_extend("force", list_state(buf), changes)
	load(buf)
end

local function selected(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local s = list_state(buf)
	if s then
		local env = s.envelopes[vim.api.nvim_win_get_cursor(0)[1]]
		return env and { account = s.account, mailbox = s.mailbox, id = tostring(env.id) }, env
	end
	local m = vim.b[buf].mail_msg -- inside a reader
	return m and { account = m.account, mailbox = m.mailbox, id = m.id }
end

local function pick_mailbox(account, prompt, cb)
	cli(acct(account, "mailbox", "list", "--json"), function(ok, out, err)
		if not ok then
			return fail("Mailboxes", err)
		end
		local names = vim.tbl_map(function(m)
			return m.name
		end, (vim.json.decode(out) or {}).mailboxes or {})
		vim.ui.select(names, { prompt = prompt }, function(choice)
			if choice then
				cb(choice)
			end
		end)
	end)
end

local function human_size(n)
	if not n then
		return "?"
	end
	for _, unit in ipairs({ "B", "KB", "MB" }) do
		if n < 1024 or unit == "MB" then
			return (unit == "B" and "%d %s" or "%.1f %s"):format(n, unit)
		end
		n = n / 1024
	end
end

--- Reader lines for a mail-compose summary. Pure.
function M.render_message(sm)
	local lines = { "Date: " .. sm.date, "From: " .. sm.from, "To: " .. sm.to }
	if sm.cc ~= "" then
		table.insert(lines, "Cc: " .. sm.cc)
	end
	table.insert(lines, "Subject: " .. sm.subject)
	local files = vim.tbl_filter(function(a)
		return not a.inline
	end, sm.attachments)
	for _, a in ipairs(files) do
		table.insert(lines, ("Attachment: %s (%s)  — ga saves to ~/Downloads"):format(a.name, human_size(a.size)))
	end
	table.insert(lines, "")
	vim.list_extend(lines, vim.split(sm.body, "\n", { plain = true }))
	return lines
end

-- ── reader ─────────────────────────────────────────────────────────────────

local function reader_win()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.b[vim.api.nvim_win_get_buf(win)].mail_msg then
			return win
		end
	end
end

local function read(list_buf)
	local opts, env = selected(list_buf)
	if not opts then
		return
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "mail"
	vim.b[buf].mail_msg = opts
	pcall(vim.api.nvim_buf_set_name, buf, string.format("himalaya://%s/%s/%s", opts.account, opts.mailbox, opts.id))
	set_lines(buf, { "loading…" })
	M.attach_keys(buf)

	local win = reader_win()
	if win then
		vim.api.nvim_win_set_buf(win, buf)
		vim.api.nvim_set_current_win(win)
	else
		vim.cmd("belowright split")
		vim.api.nvim_win_set_buf(0, buf)
	end
	vim.wo.wrap, vim.wo.linebreak = true, true

	mc().fetch(vim.tbl_extend("force", opts, { seen = true }), function(msg)
		if vim.api.nvim_buf_is_valid(buf) then
			set_lines(buf, M.render_message(mc().summary(msg)))
		end
		if env and not has_flag(env, "seen") and vim.api.nvim_buf_is_valid(list_buf) then
			local s = list_state(list_buf)
			for _, e in ipairs(s.envelopes) do
				if tostring(e.id) == opts.id then
					table.insert(e.flags, { iana = "seen", raw = "\\Seen" })
				end
			end
			vim.b[list_buf].mail_list = s
			render(list_buf)
		end
	end)
end

-- After a delete/move, refresh whichever list shows that mailbox.
local function refresh_lists(account, mailbox)
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		local s = vim.api.nvim_buf_is_valid(b) and list_state(b)
		if s and s.account == account and s.mailbox == mailbox then
			load(b)
		end
	end
end

local function remove(opts, args, done_msg)
	cli(acct(opts.account, unpack(args)), function(ok, _, err)
		if not ok then
			return fail(done_msg, err)
		end
		vim.notify(done_msg, vim.log.levels.INFO, { title = "Mail" })
		mc().forget(opts)
		local win = reader_win()
		local rbuf = win and vim.api.nvim_win_get_buf(win)
		if rbuf and vim.b[rbuf].mail_msg.id == opts.id then
			vim.api.nvim_buf_delete(rbuf, { force = true }) -- safe even as the last window
		end
		refresh_lists(opts.account, opts.mailbox)
	end)
end

-- ── keys ───────────────────────────────────────────────────────────────────

local function with_selected(fn)
	return function()
		local opts, env = selected()
		if opts then
			fn(opts, env)
		end
	end
end

-- "Deleted: <subject>" so a stray keystroke is obvious (and undoable from Trash)
local function what(env, opts)
	local subject = env and type(env.subject) == "string" and env.subject or nil
	if not subject and vim.b.mail_msg then
		subject = vim.fn.getline(vim.fn.search("^Subject: ", "nw")):gsub("^Subject: ", "")
	end
	subject = (subject and subject ~= "") and subject or ("message " .. opts.id)
	return vim.fn.strcharpart(subject, 0, 60)
end

local shared = {
	{ "r", with_selected(function(o) mc().reply(o) end), "Reply", "r" },
	{ "gR", with_selected(function(o) mc().reply(vim.tbl_extend("force", o, { all = true })) end), "Reply all", "R" },
	{ "gf", with_selected(function(o) mc().forward(o) end), "Forward", "f" },
	{ "e", with_selected(function(o) mc().resume(o) end), "Edit as draft", "e" },
	{ "c", function() mc().compose({ account = (list_state() or vim.b.mail_msg or {}).account }) end, "Compose", "c" },
	{ "d", with_selected(function(o, env) remove(o, { "message", "delete", "-m", o.mailbox, o.id }, "Deleted: " .. what(env, o)) end), "Delete", "D" },
	{
		"gm",
		with_selected(function(o, env)
			local label = what(env, o)
			pick_mailbox(o.account, "Move to:", function(to)
				-- `message move` names the source --from (not -m like the other commands)
				remove(o, { "message", "move", "--from", o.mailbox, "--to", to, o.id }, ("Moved to %s: %s"):format(to, label))
			end)
		end),
		"Move",
		"m",
	},
	{
		"ga",
		with_selected(function(o)
			local dir = vim.fn.expand("~/Downloads")
			cli(acct(o.account, "attachment", "download", "-m", o.mailbox, "--dir", dir, o.id), function(ok, _, err)
				if not ok then
					return fail("Attachments", err)
				end
				vim.notify("Attachments saved to " .. dir, vim.log.levels.INFO, { title = "Mail" })
			end)
		end),
		"Download attachments",
		"a",
	},
}

-- The list these keys act on: this buffer, or the list shown in this tab
-- (so they also work from the reader pane).
local function L()
	if list_state() then
		return vim.api.nvim_get_current_buf()
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local b = vim.api.nvim_win_get_buf(win)
		if list_state(b) then
			return b
		end
	end
	vim.notify("No mail list in this tab (:Mail)", vim.log.levels.WARN, { title = "Mail" })
end

local function on_list(fn)
	return function()
		local b = L()
		if b then
			fn(b, list_state(b))
		end
	end
end

local list_only = {
	{ "<CR>", function() read(vim.api.nvim_get_current_buf()) end, "Read", "<CR>" },
	{ "R", on_list(function(b) load(b) end), "Reload", "l" },
	{ "]]", on_list(function(b, st) update(b, { page = st.page + 1 }) end), "Next page", "n" },
	{ "[[", on_list(function(b, st) update(b, { page = math.max(1, st.page - 1) }) end), "Previous page", "p" },
	{
		"gF",
		on_list(function(b, st)
			pick_mailbox(st.account, "Mailbox:", function(name)
				update(b, { mailbox = name, page = 1, query = false })
			end)
		end),
		"Switch mailbox",
		"F",
	},
	{
		"gA",
		on_list(function(b)
			cli({ "account", "list", "--json" }, function(ok, out, err)
				if not ok then
					return fail("Accounts", err)
				end
				local names = vim.tbl_map(function(a)
					return a.name
				end, (vim.json.decode(out) or {}).accounts or {})
				vim.ui.select(names, { prompt = "Account:" }, function(name)
					if name then
						update(b, { account = name, mailbox = "inbox", page = 1, query = false })
						mc().warm(name)
					end
				end)
			end)
		end),
		"Switch account",
		"A",
	},
	{
		"/",
		on_list(function(b)
			vim.ui.input({ prompt = "Search (e.g. from ann and subject plan): " }, function(q)
				if q then
					update(b, { query = q ~= "" and q or false, page = 1 })
				end
			end)
		end),
		"Search",
		"/",
	},
	{ "q", "<cmd>bwipeout<cr>", "Close mail", "q" },
}

function M.attach_keys(buf)
	local keys = vim.deepcopy(shared)
	for _, k in ipairs(list_only) do
		if list_state(buf) or (k[1] ~= "<CR>" and k[1] ~= "q") then
			table.insert(keys, k)
		end
	end
	if not list_state(buf) then
		table.insert(keys, { "q", "<cmd>bwipeout<cr>", "Close message", "q" })
	end
	for _, k in ipairs(keys) do
		vim.keymap.set("n", k[1], k[2], { buffer = buf, nowait = true, desc = "Mail: " .. k[3] })
		-- same action under <leader>m so which-key lists what this buffer can do
		vim.keymap.set("n", "<leader>m" .. k[4], k[2], { buffer = buf, desc = k[3] .. "  (" .. k[1] .. ")" })
	end
end

-- ── entry points ───────────────────────────────────────────────────────────

--- Open a mailbox listing in the current window. opts: { account?, mailbox? }
function M.open(opts)
	opts = opts or {}
	local function show(account)
		local name = string.format("himalaya://%s", account)
		local existing = vim.fn.bufnr(name)
		if existing ~= -1 then
			vim.api.nvim_set_current_buf(existing)
			return load(existing)
		end
		local buf = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_set_name(buf, name)
		vim.bo[buf].filetype = "himalaya-list"
		vim.b[buf].mail_list = { account = account, mailbox = opts.mailbox or "inbox", page = 1, envelopes = {} }
		vim.api.nvim_set_current_buf(buf)
		vim.wo.wrap, vim.wo.cursorline, vim.wo.number, vim.wo.relativenumber = false, true, false, false
		M.attach_keys(buf)
		load(buf)
		mc().warm(account) -- first reply shouldn't wait on sender lookup
	end
	if opts.account and opts.account ~= "" then
		return show(opts.account)
	end
	cli({ "account", "list", "--json" }, function(ok, out, err)
		if not ok then
			return fail("Accounts", err)
		end
		for _, a in ipairs((vim.json.decode(out) or {}).accounts or {}) do
			if a.default then
				return show(a.name)
			end
		end
		fail("Accounts", "no default account in himalaya config")
	end)
end

function M.setup()
	vim.api.nvim_create_user_command("Mail", function(o)
		M.open({ account = o.args })
	end, {
		nargs = "?",
		desc = "Open mail (himalaya)",
		complete = function()
			local r = vim.system({ "himalaya", "account", "list", "--json" }, { text = false }):wait(2000)
			local okj, data = pcall(vim.json.decode, r.stdout or "")
			return okj and vim.tbl_map(function(a)
				return a.name
			end, data.accounts or {}) or {}
		end,
	})

	local map = function(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { desc = desc })
	end
	map("<leader>mo", "<cmd>Mail<cr>", "Open inbox (default)")
	map("<leader>mO", ":Mail ", "Open account...")
	map("<leader>mg", "<cmd>Mail gmail<cr>", "Gmail inbox")
	map("<leader>mw", "<cmd>Mail work<cr>", "Work inbox")
	map("<leader>mc", function()
		mc().compose({})
	end, "Compose new")
end

return M
