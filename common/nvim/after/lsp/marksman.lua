-- Equal-priority markers (nested list) stop the upward search at the nearest one. The
-- default {'.marksman.toml', '.git'} walks to / for the first before trying the second,
-- which costs ~0.4 s on /mnt/c. `.obsidian` makes a vault the root, so wikilinks
-- resolve vault-wide.
return {
	root_markers = { { ".marksman.toml", ".obsidian", ".git" } },
}
