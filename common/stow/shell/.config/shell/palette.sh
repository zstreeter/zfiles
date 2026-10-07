
ZF_PROMPT_BRACKET=1   # the enclosing [ ]
ZF_PROMPT_USER=3      # %n / the model id
ZF_PROMPT_AT=2        # the literal @
ZF_PROMPT_HOST=4      # %M / the provider
ZF_PROMPT_DIR=5       # %1d / the working directory

ZF_PROMPT_GROUP=5     # the ( ) and [ ] delimiters
ZF_PROMPT_JOIN=3      # the - joining one group to the next
ZF_PROMPT_VALUE=2     # br:main, gh:acct, ctx:87%
ZF_PROMPT_ALERT=1     # vcs action state (rebase/merge) and the svn/bzr : separator

ZF_PROMPT_ENV=6       # (conda-env) marker
ZF_PROMPT_ARROW=4     # the second-line ➜

ZF_PROMPT_CTX_OK=2
ZF_PROMPT_CTX_WARN=3
ZF_PROMPT_CTX_CRIT=1

# Host label for both prompts (sourced only by them, so this lookup never runs in scripts).
# The short name, plus the site label when the FQDN is deep enough to have one:
# login09.frontier.olcf.ornl.gov -> login09.frontier, but host.example.com -> host.
# Login nodes often set only the short hostname, so ask for the FQDN.
__zf_fq=$(hostname -f 2>/dev/null)
[ -n "$__zf_fq" ] || __zf_fq=${HOSTNAME:-${HOST:-}}
case $__zf_fq in
    *.*.*.*) __zf_rest=${__zf_fq#*.}; ZF_HOST=${__zf_fq%%.*}.${__zf_rest%%.*} ;;
    *)       ZF_HOST=${__zf_fq%%.*} ;;
esac
unset __zf_fq __zf_rest
