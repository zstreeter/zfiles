-- Lean 4: language server (from the project's own toolchain via elan), the
-- infoview showing goals at the cursor, and \to-style unicode input.
-- Toolchain and Mathlib sandbox come from zfiles: see `lean-sandbox`.
return {
	"Julian/lean.nvim",
	event = { "BufReadPre *.lean", "BufNewFile *.lean" },
	opts = { mappings = true },
}
