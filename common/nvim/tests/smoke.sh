#!/bin/sh
# Smoke test: config must boot headless with no errors and pass tests/smoke.lua.
set -e
cd "$(dirname "$0")/.."

out=$(nvim --headless "+lua dofile('tests/smoke.lua')" +qa 2>&1) || true
printf '%s\n' "$out"
printf '%s' "$out" | grep -q 'SMOKE-PASS' || { echo "smoke.lua failed"; exit 1; }
printf '%s' "$out" | grep -qi 'E5108\|stack traceback' && { echo "runtime errors during boot"; exit 1; }

# structural: exactly one copy of the kind glyph table (lua/config/icons.lua)
dups=$(grep -rln 'EnumMember = "' lua | grep -v 'lua/config/icons.lua' || true)
if [ -n "$dups" ]; then
	echo "duplicated kind table in: $dups"
	exit 1
fi

# structural: goto pickers live in snacks.lua only, not duplicated in lsp.lua
if grep -n 'Snacks.picker' lua/config/lsp.lua >/dev/null 2>&1; then
	echo "config/lsp.lua duplicates snacks picker keymaps"; exit 1
fi
# structural: which-key groups live in the registry only
if grep -n 'group = ' lua/plugins/which-key.lua lua/plugins/lang/quarto.lua >/dev/null 2>&1; then
	echo "group labels outside config/keys.lua"; exit 1
fi

# structural: after/lsp/*.lua are pure data — no plugin requires
if grep -rn 'require(' after/lsp/ >/dev/null 2>&1; then
	echo "after/lsp/ must stay pure data:"; grep -rn 'require(' after/lsp/
	exit 1
fi

# structural: interactive shells and TUIs belong in real Herdr panes
embedded=$(grep -Ern 'Snacks\.(terminal|lazygit)|termopen|vim\.cmd.*terminal' lua/ || true)
if [ -n "$embedded" ]; then
	echo "embedded terminal usage is forbidden; use config.herdr.open_pane:"; echo "$embedded"
	exit 1
fi

echo PASS
