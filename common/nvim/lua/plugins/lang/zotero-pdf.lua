local zotero_dir = vim.fn.expand("~/Zotero/Zotero-Library")

local function open_in_sioyek(path)
	if not path or path == "" then
		return
	end
	vim.fn.jobstart({ "sioyek", path }, { detach = true })
end

local function pick_pdf()
	if vim.fn.isdirectory(zotero_dir) == 0 then
		vim.notify("Zotero library not found: " .. zotero_dir, vim.log.levels.WARN)
		return
	end
	Snacks.picker.files({
		cwd = zotero_dir,
		ft = "pdf",
		hidden = false,
		follow = true,
		ignored = false,
		title = "Zotero PDFs",
		confirm = function(picker, item)
			picker:close()
			if not item then
				return
			end
			local path = item._path or vim.fs.joinpath(item.cwd or zotero_dir, item.file or item.text)
			open_in_sioyek(path)
		end,
	})
end

return {
	"folke/snacks.nvim",
	optional = true,
	-- init (not module scope): module scope runs during lazy's spec import,
	-- before startup finishes; init is the sanctioned startup hook.
	init = function()
		vim.api.nvim_create_user_command(
			"ZoteroPdf",
			pick_pdf,
			{ desc = "Fuzzy find Zotero PDFs and open in sioyek" }
		)
	end,
	keys = {
		{ "<leader>fz", pick_pdf, desc = "Find Zotero PDF (sioyek)" },
	},
}
