-- Compose/reply/forward/resume mail in a plain buffer, handed to the himalaya
-- v2 CLI on :write.
--
-- The buffer is a header block (From/To/Cc/Bcc/Subject/Attach, one blank line)
-- followed by the body. On :write you choose Send / Save draft / Cancel.
-- himalaya's own composer (`message compose`) builds the MIME — encoding,
-- attachments, Date, Message-ID — so this module never writes MIME itself; it
-- only adds the threading headers (In-Reply-To/References) the flag composer
-- has no option for, then pipes the result to `message send` / `message add`.
-- Everything goes through the CLI, so any backend himalaya supports works.
--
-- Threading data and draft ids live in b:mail_compose, not in the buffer text.
-- M.himalaya is the single CLI seam and is replaceable in tests.
local M = {}

-- Accounts whose SMTP server already files a copy in Sent (Gmail does);
-- `--save sent` there would duplicate every message.
M.skip_sent_copy = { gmail = true }

local HEADERS = { "From", "To", "Cc", "Bcc", "Subject" }
local compose_backend -- defined with the account helpers below

--- Run himalaya with args; stdin optional. cb(ok, stdout, stderr) on the main loop.
function M.himalaya(args, stdin, cb)
	-- text=false: MIME must reach us byte-exact. text=true rewrites CRLF and can
	-- leave mixed line endings, which corrupted header rewriting.
	vim.system(vim.list_extend({ "himalaya" }, args), { stdin = stdin, text = false }, function(r)
		vim.schedule(function()
			cb(r.code == 0, r.stdout or "", r.stderr or "")
		end)
	end)
end

local function acct_args(account, ...)
	local args = {}
	if account and account ~= "" then
		args = { "-a", account }
	end
	return vim.list_extend(args, { ... })
end

local function fail(what, err)
	vim.notify(what .. ": " .. vim.trim(err), vim.log.levels.ERROR, { title = "Mail" })
end

-- ── himalaya JSON (mail-parser shape) ──────────────────────────────────────

local function header(part, name)
	for _, h in ipairs(part.headers or {}) do
		local n = type(h.name) == "table" and h.name.other or h.name
		if type(n) == "string" and n:lower():gsub("_", "-") == name then
			return h.value
		end
	end
end

local function text(value)
	if type(value) ~= "table" then
		return nil
	end
	if value.Text then
		return value.Text
	end
	if value.TextList then
		return table.concat(value.TextList, " ")
	end
end

local function id_list(value)
	if type(value) ~= "table" then
		return {}
	end
	return value.TextList or (value.Text and vim.split(value.Text, "%s+", { trimempty = true })) or {}
end

local function addresses(value)
	local out = {}
	local addr = type(value) == "table" and value.Address
	if not addr then
		return out
	end
	local function add(a) -- JSON null (no display name) decodes to vim.NIL
		table.insert(out, { name = type(a.name) == "string" and a.name or "", address = type(a.address) == "string" and a.address or "" })
	end
	for _, a in ipairs(type(addr.List) == "table" and addr.List or {}) do
		add(a)
	end
	for _, g in ipairs(type(addr.Group) == "table" and addr.Group or {}) do
		for _, a in ipairs(type(g.addresses) == "table" and g.addresses or {}) do
			add(a)
		end
	end
	return out
end

local function fmt_addr(a)
	local name, email = a.name or "", a.address or ""
	if name == "" then
		return email
	end
	if name:find('[^%w%s%.%-\']') then
		name = '"' .. name:gsub('["\\]', "\\%0") .. '"'
	end
	return name .. " <" .. email .. ">"
end

local function fmt_list(list)
	return table.concat(vim.tbl_map(fmt_addr, list), ", ")
end

local function bare(addr)
	return (addr:match("<([^>]+)>") or addr):lower():gsub("%s", "")
end

local function body_text(msg)
	local chunks = {}
	for _, i in ipairs(msg.text_body or {}) do
		table.insert(chunks, text(msg.parts[i + 1].body) or "")
	end
	if #chunks == 0 then
		-- ponytail: crude tag strip for HTML-only mail; pipe through a real renderer if it reads badly
		for _, i in ipairs(msg.html_body or {}) do
			local html = text(msg.parts[i + 1].body) or ""
			table.insert(chunks, (html:gsub("<br%s*/?>", "\n"):gsub("</p>", "\n\n"):gsub("<[^>]+>", "")))
		end
	end
	local s = table.concat(chunks, "\n"):gsub("\r\n", "\n"):gsub("\r", "")
	-- Newsletter preheaders pad with zero-width/format chars (ZWNJ, soft hyphen,
	-- CGJ, BOM…); nvim and the terminal disagree on their width, so text spills
	-- past the window and leaves stale cells. Drop them (and the space each pads).
	s = s:gsub(" ?\226\128[\139-\143\170-\174]", "") -- U+200B-200F, U+202A-202E
		:gsub("\226\129[\160-\175]", "") -- U+2060-206F
		:gsub("\194\173", "") -- U+00AD soft hyphen
		:gsub("\205\143", "") -- U+034F CGJ
		:gsub("\239\187\191", "") -- U+FEFF BOM
	return s
end

local function fmt_date(v)
	local d = type(v) == "table" and v.DateTime
	if not d then
		return "?"
	end
	local sign = d.tz_before_gmt and "-" or "+"
	return string.format("%04d-%02d-%02d %02d:%02d %s%02d:%02d", d.year, d.month, d.day, d.hour, d.minute, sign, d.tz_hour, d.tz_minute)
end

local function prefixed(subject, prefix)
	if subject:lower():find("^" .. prefix:lower() .. ":") then
		return subject
	end
	return prefix .. ": " .. subject
end

--- Reply fields from a `message read --json` result. Pure.
function M.reply_fields(msg, self_addr, all)
	local top = msg.parts[1]
	local from = addresses(header(top, "from"))
	local reply_to = addresses(header(top, "reply-to"))
	local to = #reply_to > 0 and reply_to or from

	local seen = { [bare(self_addr or "")] = true }
	for _, a in ipairs(to) do
		seen[a.address:lower()] = true
	end
	local cc = {}
	if all then
		local others = vim.list_extend(addresses(header(top, "to")), addresses(header(top, "cc")))
		for _, a in ipairs(others) do
			local key = (a.address or ""):lower()
			if key ~= "" and not seen[key] then
				seen[key] = true
				table.insert(cc, a)
			end
		end
	end

	local mid = text(header(top, "message-id"))
	local refs = vim.tbl_map(function(r)
		return "<" .. r:gsub("^<", ""):gsub(">$", "") .. ">"
	end, id_list(header(top, "references")))
	if mid then
		table.insert(refs, "<" .. mid .. ">")
	end

	local quoted = vim.tbl_map(function(l)
		return l == "" and ">" or "> " .. l
	end, vim.split(body_text(msg), "\n"))
	local headline = string.format("On %s, %s wrote:", fmt_date(header(top, "date")), from[1] and (from[1].name ~= "" and from[1].name or from[1].address) or "?")

	return {
		to = fmt_list(to),
		cc = fmt_list(cc),
		subject = prefixed(text(header(top, "subject")) or "", "Re"),
		body = "\n\n" .. headline .. "\n" .. table.concat(quoted, "\n"),
		in_reply_to = mid and ("<" .. mid .. ">") or nil,
		references = #refs > 0 and table.concat(refs, " ") or nil,
	}
end

-- ── buffer format ──────────────────────────────────────────────────────────

--- Parse buffer lines into { headers = {From=...}, attach = {paths}, body = string }. Pure.
function M.parse(lines)
	local headers, attach, i = {}, {}, 1
	-- Only the known header names count; any other line (e.g. "Note: ...")
	-- starts the body, so a missing blank separator never swallows text.
	while i <= #lines do
		local name, value = lines[i]:match("^([%w-]+):%s*(.-)%s*$")
		local known = name and (name:lower() == "attach" and "Attach" or nil)
		for _, h in ipairs(HEADERS) do
			if name and h:lower() == name:lower() then
				known = h
			end
		end
		if not known then
			break
		end
		if known == "Attach" then
			if value ~= "" then
				table.insert(attach, vim.fn.expand(value))
			end
		else
			headers[known] = value
		end
		i = i + 1
	end
	if lines[i] == "" then
		i = i + 1 -- the separator line itself
	end
	return { headers = headers, attach = attach, body = table.concat(vim.list_slice(lines, i), "\n") }
end

--- Lines with an attachment added: fills an empty "Attach:" or adds one after
--- the last header line. Pure.
function M.add_attachment(lines, path)
	local out, last_header, done = vim.deepcopy(lines), 0, false
	for i, line in ipairs(out) do
		if line == "" then
			break
		end
		last_header = i
		if not done and line:match("^Attach:%s*$") then
			out[i], done = "Attach: " .. path, true
		end
	end
	if not done then
		table.insert(out, last_header + 1, "Attach: " .. path)
	end
	return out
end

--- Split an address list on commas outside quotes and angle brackets. Pure.
function M.split_addrs(str)
	local out, cur, quoted, angle = {}, {}, false, false
	for ch in (str or ""):gmatch(".") do
		if ch == '"' then
			quoted = not quoted
		elseif ch == "<" and not quoted then
			angle = true
		elseif ch == ">" and not quoted then
			angle = false
		end
		if ch == "," and not quoted and not angle then
			table.insert(out, vim.trim(table.concat(cur)))
			cur = {}
		else
			table.insert(cur, ch)
		end
	end
	table.insert(out, vim.trim(table.concat(cur)))
	return vim.tbl_map(function(a)
		local name, addr = a:match('^(.-)%s*<([^>]+)>$')
		name = (name or ""):gsub('^"(.*)"$', "%1"):gsub('\\(.)', "%1")
		return { name = name, address = vim.trim(addr or a) }
	end, vim.tbl_filter(function(a)
		return a ~= ""
	end, out))
end

-- Header-safe "Name <addr>" list: RFC 2047 for non-ASCII names, quotes for specials.
local function header_addrs(list)
	return table.concat(vim.tbl_map(function(a)
		if a.name ~= "" and a.name:find("[\128-\255]") then
			return "=?UTF-8?B?" .. vim.base64.encode(a.name) .. "?= <" .. a.address .. ">"
		end
		return fmt_addr(a)
	end, list), ", ")
end

--- Set header fields on a MIME message: an existing field (with its folded
--- continuation lines) is replaced, a missing one is added before the body. Pure.
function M.set_headers(mime, fields)
	-- the header block ends at the first empty line, whatever the line endings
	local stop = mime:match("()\r?\n\r?\n")
	local head = stop and mime:sub(1, stop - 1) or mime
	local rest = stop and mime:sub(stop) or ""
	local out, skipping, pending = {}, false, vim.deepcopy(fields)
	for _, line in ipairs(vim.split(head, "\r?\n")) do
		local name = line:match("^([%w-]+)%s*:")
		if name then
			skipping = false
			for k, v in pairs(fields) do
				if k:lower() == name:lower() then
					skipping = true
					if pending[k] then
						table.insert(out, k .. ": " .. v)
						pending[k] = nil
					end
				end
			end
			if not skipping then
				table.insert(out, line)
			end
		elseif not skipping then
			table.insert(out, line)
		end
	end
	for _, k in ipairs({ "From", "To", "Cc", "Bcc", "In-Reply-To", "References" }) do
		if pending[k] then
			table.insert(out, k .. ": " .. pending[k])
		end
	end
	return table.concat(out, "\r\n") .. rest
end

--- Is a built message safe to hand to send/add? Pure.
function M.well_formed(final, built, subject)
	local stop = final:match("()\r?\n\r?\n")
	if not stop then
		return false, "no header/body separator"
	end
	local head = "\n" .. final:sub(1, stop - 1)
	if not head:find("\nDate: ") then
		return false, "no Date header"
	end
	if subject and subject ~= "" and not head:find("\nSubject: ") then
		return false, "Subject header lost"
	end
	-- we only replace/add a few header lines; a big shrink means content was eaten
	if built and #final + 4096 < #built then
		return false, ("message shrank from %d to %d bytes"):format(#built, #final)
	end
	return true
end

local version_ok -- nil = unknown yet

-- himalaya < 2.2.1 transmits the Bcc header to every recipient (pimalaya/himalaya#747).
local function bcc_safe(cb)
	if version_ok ~= nil then
		return cb(version_ok)
	end
	M.himalaya({ "--version" }, nil, function(_, out)
		local maj, min, patch = out:match("v?(%d+)%.(%d+)%.(%d+)")
		local v = { tonumber(maj) or 0, tonumber(min) or 0, tonumber(patch) or 0 }
		version_ok = v[1] > 2 or (v[1] == 2 and (v[2] > 2 or (v[2] == 2 and v[3] >= 1)))
		cb(version_ok)
	end)
end

-- ── accounts ───────────────────────────────────────────────────────────────

local accounts -- name → { default, backends }, from `account list` (local, ~10 ms)

-- cb(name, info) for the given account, or the default one when none given.
local function account_info(account, cb)
	local function pick()
		if account and account ~= "" then
			return cb(account, accounts[account] or {})
		end
		for name, info in pairs(accounts) do
			if info.default then
				return cb(name, info)
			end
		end
		fail("Could not resolve account", "no default account in himalaya config")
	end
	if accounts then
		return pick()
	end
	M.himalaya({ "account", "list", "--json" }, nil, function(ok, out, err)
		if not ok then
			return fail("Could not list accounts", err)
		end
		local okj, data = pcall(vim.json.decode, out)
		accounts = {}
		for _, a in ipairs(okj and type(data) == "table" and data.accounts or {}) do
			accounts[a.name] = { default = a.default, backends = a.backends or {} }
		end
		pick()
	end)
end

-- `message compose` is offline work, but under the IMAP backend himalaya
-- still opens an IMAP session first (~1.1 s). The SMTP backend skips that.
compose_backend = function(account)
	local info = accounts and accounts[account] or {}
	local args = acct_args(account)
	if vim.tbl_contains(info.backends or {}, "smtp") then
		vim.list_extend(args, { "-b", "smtp" })
	end
	return args
end

-- ── sending ────────────────────────────────────────────────────────────────

-- The message is out (or saved): close the buffer now, then run best-effort
-- follow-ups in the background so the UI never waits on them.
local function finish(buf, meta, action)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.bo[buf].modified = false
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	if action == "send" and meta.reply_id then
		M.himalaya(acct_args(meta.account, "flag", "add", "-m", meta.mailbox, "-f", "answered", meta.reply_id), nil, function(ok, _, err)
			if not ok then
				vim.notify("Sent, but marking the original answered failed: " .. vim.trim(err), vim.log.levels.WARN, { title = "Mail" })
			end
		end)
	end
	if meta.draft_id then
		M.himalaya(acct_args(meta.account, "message", "delete", "-m", meta.draft_mailbox or "drafts", meta.draft_id), nil, function(ok, _, err)
			if not ok then
				vim.notify("Old draft not removed: " .. vim.trim(err), vim.log.levels.WARN, { title = "Mail" })
			end
		end)
	end
end

--- Unique misspelled words in the user's own text (quoted "> " lines skipped).
function M.misspelled(body)
	local seen, out = {}, {}
	for _, line in ipairs(vim.split(body, "\n")) do
		if not line:match("^%s*>") then
			for _, hit in ipairs(vim.spell.check(line)) do
				if hit[2] == "bad" and not seen[hit[1]] then
					seen[hit[1]] = true
					table.insert(out, hit[1])
				end
			end
		end
	end
	return out
end

--- Build with himalaya's composer, then send or save. action: "send" | "draft".
function M.submit(buf, action)
	local meta = vim.b[buf].mail_compose
	if vim.b[buf].mail_busy then
		return vim.notify("Already sending…", vim.log.levels.WARN, { title = "Mail" })
	end
	local msg = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	local h = msg.headers
	local addrs = {}
	for _, name in ipairs({ "From", "To", "Cc", "Bcc" }) do
		addrs[name] = M.split_addrs(h[name])
	end

	if action == "send" and #addrs.To + #addrs.Cc + #addrs.Bcc == 0 then
		return fail("Not sent", "no recipients")
	end
	for _, path in ipairs(msg.attach) do
		if vim.fn.filereadable(path) == 0 then
			return fail("Not sent", "attachment not readable: " .. path)
		end
	end

	local function go()
		vim.b[buf].mail_busy = true -- one submit at a time; cleared on failure
		vim.notify(action == "send" and "Sending…" or "Saving draft…", vim.log.levels.INFO, { title = "Mail" })
		local body_file = vim.fn.tempname()
		vim.fn.writefile(vim.split(msg.body, "\n"), body_file)
		local args = vim.list_extend(compose_backend(meta.account), { "message", "compose", "--body-file", body_file })
		if (h.Subject or "") ~= "" then
			vim.list_extend(args, { "--subject", h.Subject })
		end
		-- the flag composer only takes bare addresses (it splits on every comma);
		-- display names are restored by set_headers below
		for flag, name in pairs({ ["--from"] = "From", ["--to"] = "To", ["--cc"] = "Cc", ["--bcc"] = "Bcc" }) do
			for _, a in ipairs(addrs[name]) do
				vim.list_extend(args, { flag, a.address })
			end
		end
		for _, path in ipairs(msg.attach) do
			vim.list_extend(args, { "--attach", path })
		end

		M.himalaya(args, nil, function(ok, mime, err)
			os.remove(body_file)
			-- never save/send a malformed build: it must carry a header block
			-- (with Date) and a body separator, or the user's text is lost
			if ok and not (mime:find("\r?\n\r?\n") and mime:find("\nDate: ") and mime:find("^From: ")) then
				ok, err = false, ("himalaya returned no usable message (%d bytes); nothing was saved or sent"):format(#mime)
			end
			if not ok then
				if vim.api.nvim_buf_is_valid(buf) then
					vim.b[buf].mail_busy = false
				end
				return fail("Compose failed", err)
			end
			local fields = { ["In-Reply-To"] = meta.in_reply_to, References = meta.references }
			for _, name in ipairs({ "From", "To", "Cc", "Bcc" }) do
				if #addrs[name] > 0 then
					fields[name] = header_addrs(addrs[name])
				end
			end
			local final = M.set_headers(mime, fields)
			local good, why = M.well_formed(final, mime, h.Subject)
			if not good then
				if vim.api.nvim_buf_is_valid(buf) then
					vim.b[buf].mail_busy = false
				end
				return fail("Not saved or sent", "built message is malformed (" .. why .. "); your text is still here")
			end
			mime = final
			local out
			if action == "send" then
				out = acct_args(meta.account, "message", "send")
				if not M.skip_sent_copy[meta.account or ""] then
					vim.list_extend(out, { "--save", "sent" })
				end
			else
				out = acct_args(meta.account, "message", "add", "-m", "drafts", "-f", "draft", "-f", "seen")
			end
			M.himalaya(out, mime, function(sent, _, send_err)
				if not sent then
					if vim.api.nvim_buf_is_valid(buf) then
						vim.b[buf].mail_busy = false
					end
					return fail(action == "send" and "Send failed" or "Draft save failed", send_err)
				end
				vim.notify(action == "send" and "Sent" or "Draft saved", vim.log.levels.INFO, { title = "Mail" })
				finish(buf, meta, action)
			end)
		end)
	end

	if action == "send" and not vim.b[buf].mail_spell_ok then
		local typos = M.misspelled(msg.body)
		if #typos > 0 then
			return vim.ui.select({ "Keep editing", "Send anyway" }, {
				prompt = "Misspelled: " .. table.concat(typos, ", "),
			}, function(choice)
				if choice == "Send anyway" then
					vim.b[buf].mail_spell_ok = true
					M.submit(buf, action)
					vim.b[buf].mail_spell_ok = nil
				end
			end)
		end
	end

	account_info(meta.account, function()
		if action == "send" and #addrs.Bcc > 0 then
			return bcc_safe(function(safe)
				if not safe then
					return fail("Not sent", "this himalaya (< 2.2.1) would show Bcc to every recipient; upgrade or remove Bcc")
				end
				go()
			end)
		end
		go()
	end)
end

-- ── buffers ────────────────────────────────────────────────────────────────

local counter = 0

local function open(meta, fields)
	counter = counter + 1
	vim.cmd("tabnew")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(buf, string.format("himalaya://%s/%d", meta.kind, counter))
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].filetype = "mail"
	vim.wo.spell = true -- compose only; the reader shares ft=mail
	vim.b[buf].mail_compose = meta

	local lines = {
		"From: " .. (fields.from or ""),
		"To: " .. (fields.to or ""),
		"Cc: " .. (fields.cc or ""),
		"Bcc: " .. (fields.bcc or ""),
		"Subject: " .. (fields.subject or ""),
	}
	for _, path in ipairs(fields.attach or {}) do
		table.insert(lines, "Attach: " .. path)
	end
	if #(fields.attach or {}) == 0 then
		table.insert(lines, "Attach: ")
	end
	table.insert(lines, "")
	vim.list_extend(lines, vim.split(fields.body or "", "\n"))
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modified = false

	local function map(lhs, fn, desc)
		vim.keymap.set("n", "<leader>m" .. lhs, fn, { buffer = buf, desc = desc })
	end
	map("s", function()
		M.submit(buf, "send")
	end, "Send")
	map("d", function()
		M.submit(buf, "draft")
	end, "Save draft")
	map("a", function()
		vim.ui.input({ prompt = "Attach file: ", default = vim.fn.getcwd() .. "/", completion = "file" }, function(path)
			if path and path ~= "" then
				path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
				if vim.fn.filereadable(path) == 0 then
					return fail("Not attached", "not a readable file: " .. path)
				end
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.add_attachment(vim.api.nvim_buf_get_lines(buf, 0, -1, false), path))
			end
		end)
	end, "Attach file")
	map("x", function()
		vim.ui.select({ "Discard", "Keep editing" }, { prompt = "Discard this message?" }, function(choice)
			if choice == "Discard" then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end)
	end, "Discard")

	-- One menu for :w and ZZ. Scheduled so it opens after the triggering
	-- command finishes; opened inside BufWriteCmd, nvim yanks focus back to
	-- the buffer and the picker loses the cursor.
	local function ask(choices)
		vim.schedule(function()
			vim.ui.select(choices, { prompt = "Mail:" }, function(choice)
				if choice == "Send" then
					M.submit(buf, "send")
				elseif choice == "Save draft" then
					M.submit(buf, "draft")
				elseif choice == "Discard" then
					vim.api.nvim_buf_delete(buf, { force = true })
				end
			end)
		end)
	end
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			ask({ "Send", "Save draft", "Cancel" })
		end,
	})
	vim.keymap.set("n", "ZZ", function()
		ask({ "Send", "Save draft", "Discard", "Cancel" })
	end, { buffer = buf, desc = "Mail: send / save draft / discard" })
	vim.api.nvim_win_set_cursor(0, { fields.to == "" and 2 or #lines - #vim.split(fields.body or "", "\n") + 1, 0 })
end

local sender_cache = {}

-- The account's resolved name and From, as himalaya's own composer fills it
-- (no TOML parsing here). cb(account, from)
local function sender(account, cb)
	account_info(account, function(name)
		if sender_cache[name] then
			return cb(name, sender_cache[name])
		end
		M.himalaya(vim.list_extend(compose_backend(name), { "message", "compose", "--to", "probe@invalid", "--body", "x" }), nil, function(ok, out, err)
			if not ok then
				return fail("Could not resolve sender", err)
			end
			local from = (out:match("^From: ([^\r\n]+)") or out:match("\nFrom: ([^\r\n]+)") or ""):gsub("^<(.*)>$", "%1")
			if from == "" then
				-- reply-all would Cc yourself and the server may reject the message
				vim.notify("himalaya left From empty for account '" .. name .. "' (needs `from` in its config)", vim.log.levels.WARN, { title = "Mail" })
			else
				sender_cache[name] = from
			end
			cb(name, from)
		end)
	end)
end

--- Resolve account and sender ahead of time so the first reply doesn't wait.
function M.warm(account)
	sender(account, function() end)
end

-- ── message cache ──────────────────────────────────────────────────────────
-- Every message is fetched once (`message read --json`, ~2 s over IMAP) and
-- kept decoded; the reader, reply, forward and draft resume all share it.
-- Attachment bytes are dropped after decoding — only names/sizes are kept.

local cache, cache_order, CACHE_MAX = {}, {}, 30
local inflight = {} -- key → callbacks waiting on the same fetch

local function cache_key(o)
	return table.concat({ o.account or "", o.mailbox or "inbox", tostring(o.id) }, "\0")
end

local function strip_binary(msg)
	for _, part in ipairs(msg.parts or {}) do
		if type(part.body) == "table" and part.body.Binary then
			part.body = { Size = #part.body.Binary }
		end
	end
	return msg
end

--- Fetch a message (cached). opts: { account, mailbox?, id, seen? }. cb(msg) on success only.
function M.fetch(opts, cb)
	local key = cache_key(opts)
	if cache[key] then
		return cb(cache[key])
	end
	if inflight[key] then
		return table.insert(inflight[key], cb)
	end
	inflight[key] = { cb }
	local args = acct_args(opts.account, "message", "read", "-m", opts.mailbox or "inbox", "--json")
	if opts.seen then
		table.insert(args, "--seen")
	end
	table.insert(args, tostring(opts.id))
	M.himalaya(args, nil, function(ok, out, err)
		local waiting = inflight[key]
		inflight[key] = nil
		if not ok then
			return fail("Read failed", err)
		end
		local okj, msg = pcall(vim.json.decode, out)
		if not okj or type(msg) ~= "table" or not msg.parts then
			return fail("Read failed", "unexpected himalaya JSON")
		end
		cache[key] = strip_binary(msg)
		table.insert(cache_order, key)
		if #cache_order > CACHE_MAX then
			cache[table.remove(cache_order, 1)] = nil
		end
		for _, waiter in ipairs(waiting) do
			waiter(msg)
		end
	end)
end

--- Drop cached copies (after delete/move the ids no longer point there).
function M.forget(opts)
	cache[cache_key(opts)] = nil
end

local function attachment_name(part)
	for _, hname in ipairs({ "content-disposition", "content-type" }) do
		local v = header(part, hname)
		for _, a in ipairs(type(v) == "table" and v.ContentType and v.ContentType.attributes or {}) do
			if a.name == "filename" or a.name == "name" then
				return a.value
			end
		end
	end
	return "unnamed"
end

--- Display-ready view of a fetched message. Pure.
function M.summary(msg)
	local top = msg.parts[1]
	local atts = {}
	for _, i in ipairs(msg.attachments or {}) do
		local part = msg.parts[i + 1]
		local disp = header(part, "content-disposition")
		local inline = type(disp) == "table" and disp.ContentType and disp.ContentType.c_type == "inline"
		table.insert(atts, { name = attachment_name(part), size = type(part.body) == "table" and part.body.Size or nil, inline = inline })
	end
	return {
		date = fmt_date(header(top, "date")),
		from = fmt_list(addresses(header(top, "from"))),
		to = fmt_list(addresses(header(top, "to"))),
		cc = fmt_list(addresses(header(top, "cc"))),
		subject = text(header(top, "subject")) or "",
		body = body_text(msg),
		attachments = atts,
	}
end

-- Run fns in parallel; done(results...) once all have called back.
local function all(fns, done)
	local results, left = {}, #fns
	for i, fn in ipairs(fns) do
		fn(function(...)
			results[i] = { ... }
			left = left - 1
			if left == 0 then
				done(results)
			end
		end)
	end
end

-- Download a message's attachments into a fresh temp dir; cb(list of paths).
local function fetch_attachments(opts, cb)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	M.himalaya(acct_args(opts.account, "attachment", "download", "-m", opts.mailbox or "inbox", "--dir", dir, opts.id), nil, function(ok, _, err)
		if not ok then
			vim.notify("Attachments not copied: " .. vim.trim(err), vim.log.levels.WARN, { title = "Mail" })
		end
		cb(vim.fn.glob(dir .. "/*", false, true))
	end)
end

local function progress(opts)
	if not cache[cache_key(opts)] then
		vim.notify("Fetching message…", vim.log.levels.INFO, { title = "Mail" })
	end
end

--- opts: { account? }
function M.compose(opts)
	opts = opts or {}
	sender(opts.account, function(account, from)
		open({ kind = "compose", account = account }, { from = from, to = "", body = "" })
	end)
end

--- opts: { account?, mailbox?, id, all? }
function M.reply(opts)
	account_info(opts.account, function(account)
		opts = vim.tbl_extend("force", opts, { account = account })
		progress(opts)
		all({
			function(k)
				sender(account, k)
			end,
			function(k)
				M.fetch(opts, k)
			end,
		}, function(r)
			local from, msg = r[1][2], r[2][1]
			local f = M.reply_fields(msg, from, opts.all)
			f.from = from
			open({
				kind = opts.all and "reply-all" or "reply",
				account = account,
				mailbox = opts.mailbox or "inbox",
				reply_id = tostring(opts.id),
				in_reply_to = f.in_reply_to,
				references = f.references,
			}, f)
		end)
	end)
end

--- opts: { account?, mailbox?, id }
function M.forward(opts)
	account_info(opts.account, function(account)
		opts = vim.tbl_extend("force", opts, { account = account })
		progress(opts)
		all({
			function(k)
				sender(account, k)
			end,
			function(k)
				M.fetch(opts, k)
			end,
			function(k)
				fetch_attachments(opts, k)
			end,
		}, function(r)
			local from, msg, paths = r[1][2], r[2][1], r[3][1]
			local top = msg.parts[1]
			local body = table.concat({
				"",
				"",
				"---------- Forwarded message ----------",
				"From: " .. fmt_list(addresses(header(top, "from"))),
				"Date: " .. fmt_date(header(top, "date")),
				"Subject: " .. (text(header(top, "subject")) or ""),
				"To: " .. fmt_list(addresses(header(top, "to"))),
				"",
				body_text(msg),
			}, "\n")
			open({ kind = "forward", account = account }, {
				from = from,
				to = "",
				subject = prefixed(text(header(top, "subject")) or "", "Fwd"),
				attach = paths,
				body = body,
			})
		end)
	end)
end

local function angle(id)
	return "<" .. id:gsub("^<", ""):gsub(">$", "") .. ">"
end

--- Reopen a message as an editable draft. opts: { account?, mailbox?, id }.
--- Saving or sending deletes the original only when it lives in a drafts mailbox.
function M.resume(opts)
	account_info(opts.account, function(account)
		local o = vim.tbl_extend("force", opts, { account = account, mailbox = opts.mailbox or "drafts" })
		progress(o)
		all({
			function(k)
				M.fetch(o, k)
			end,
			function(k)
				fetch_attachments(o, k)
			end,
		}, function(r)
			local msg, paths = r[1][1], r[2][1]
			local top = msg.parts[1]
			local refs = id_list(header(top, "references"))
			local irt = text(header(top, "in-reply-to"))
			-- ponytail: "is a drafts mailbox" by name; himalaya exposes no alias reverse-lookup
			local is_draft = o.mailbox:lower():find("draft") ~= nil
			open({
				kind = "draft",
				account = account,
				draft_id = is_draft and tostring(o.id) or nil,
				draft_mailbox = is_draft and o.mailbox or nil,
				in_reply_to = irt and angle(irt) or nil,
				references = #refs > 0 and table.concat(vim.tbl_map(angle, refs), " ") or nil,
			}, {
				from = fmt_list(addresses(header(top, "from"))),
				to = fmt_list(addresses(header(top, "to"))),
				cc = fmt_list(addresses(header(top, "cc"))),
				bcc = fmt_list(addresses(header(top, "bcc"))),
				subject = text(header(top, "subject")) or "",
				attach = paths,
				body = body_text(msg),
			})
		end)
	end)
end

return M
