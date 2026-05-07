# User template override for mako — extends the built-in
# default/themed/mako.ini.tpl by adding zfiles' email category rules.
# Omarchy's template engine processes user templates first, so this wins
# over the built-in version.

include=~/.local/share/omarchy/default/mako/core.ini

text-color={{ foreground }}
border-color={{ accent }}
background-color={{ background }}

[category=email.personal]
border-color=#5599ff

[category=email.work]
border-color=#ff9900
