"""paperctl -- one research-paper library for every agent and every machine.

Search arXiv, Crossref and OpenAlex; harvest papers out of an email thread
through whatever mail client the machine has; keep it all in ~/Library with
generated BibTeX that Quarto can cite.

A CLI rather than an agent skill because Claude Code, Codex, opencode and pi
all have to reach it, and a skill only serves one of them. The skill that ships
alongside (.agents/skills/paperctl/) documents this binary; it does not
reimplement it.
"""

__version__ = "1.0"
