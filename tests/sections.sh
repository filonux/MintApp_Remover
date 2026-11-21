# sections.sh - runs only some sections of a bash suite in tests/. It is loaded with BASH_ENV, never run by hand:
#   ONLY_SECTIONS="12 56-64" SECTIONS_SUITE=tests/test_clean.sh BASH_ENV=tests/sections.sh bash tests/test_clean.sh
# A section starts at each line that begins with: echo "-- ; the header (before the first one) always runs.
# In the sections that were not chosen only the assignments and declarations run, because they leave the state
# the next sections read (T1, H_SCRIPT...); every other top-level command is skipped. A command with a prefix
# assignment (VAR=x cmd) is a command, not an assignment. Functions, subshells and the program are not touched.
# The last command of a suite, "finish", always runs: the totals line ("  -- N passed, ...") and the exit status
# are those of a complete run, counting only the chosen sections. Without that line a run cannot be told from one
# that stopped halfway (tests/mutate.py reads it).
# Skipped sections run with errexit and nounset off (nothing may abort there); a chosen one turns them back on.
# A chosen section must create what it needs (folders, files): it cannot count on what a skipped one would make.
# SECTIONS_TRACE=file appends "section seconds" when each section starts.
if [ -n "${ONLY_SECTIONS:-}" ] && [ -z "${_SEC_ON:-}" ]; then
    _SEC_ON=1 _SEC_E=0 _SEC_U=0 _SEC_LAST=-1
    _SEC_STARTS=(0) _SEC_WANT=()
    while IFS=: read -r _n _; do _SEC_STARTS+=("$_n"); done \
        < <(grep -n '^echo "-- ' "${SECTIONS_SUITE:?SECTIONS_SUITE is not set}")
    for _w in $ONLY_SECTIONS; do
        case "$_w" in
            *-*) for ((_k = ${_w%-*}; _k <= ${_w#*-}; _k++)); do _SEC_WANT[_k]=1; done ;;
            *) _SEC_WANT[_w]=1 ;;
        esac
    done
    _sec_of() {  # section of line $1, in _SEC_K
        local i
        _SEC_K=0
        for ((i = 1; i < ${#_SEC_STARTS[@]}; i++)); do
            if [ "$1" -ge "${_SEC_STARTS[i]}" ]; then _SEC_K=$i; else break; fi
        done
    }
    _sec_assign_only() {  # $1 is only NAME=value assignments, with no command word after them
        local s=$1 c i n stack
        while [[ $s =~ ^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?= ]]; do
            s=${s#"${BASH_REMATCH[0]}"}
            [[ $s == *[[:space:]]* ]] || return 0  # no space at all: nothing can follow the value
            stack="" n=${#s}
            for ((i = 0; i < n; i++)); do  # the value is one word: it ends at a space outside quotes and $(...)
                c=${s:i:1}
                case "${stack: -1}" in
                    "'") [ "$c" != "'" ] || stack=${stack%?}; continue ;;
                    '`') case "$c" in \\) i=$((i + 1)) ;; '`') stack=${stack%?} ;; esac; continue ;;
                esac
                case "$c" in
                    \\) i=$((i + 1)) ;;
                    "'") [ "${stack: -1}" = '"' ] || stack+="'" ;;
                    '"') if [ "${stack: -1}" = '"' ]; then stack=${stack%?}; else stack+='"'; fi ;;
                    '`') stack+='`' ;;
                    '$') case "${s:i+1:1}" in '(') stack+=')' i=$((i + 1)) ;; '{') stack+='}' i=$((i + 1)) ;; esac ;;
                    '(') [ "${stack: -1}" != ')' ] && [ -n "$stack" ] && [ "${stack: -1}" != '"' ] || stack+=')' ;;
                    ')' | '}') [ "${stack: -1}" != "$c" ] || stack=${stack%?} ;;
                    [[:space:]]) [ -z "$stack" ] && break ;;
                esac
            done
            s=${s:i}
            s=${s#"${s%%[![:space:]]*}"}
            [ -n "$s" ] || return 0
        done
        return 1
    }
    _sec_dbg() {
        local ln=$1 cmd=$BASH_COMMAND depth=${#FUNCNAME[@]}
        # only the top-level commands of the suite (FUNCNAME ends with "main")
        if [ "${FUNCNAME[depth - 1]}" = main ]; then depth=$((depth - 1)); fi
        if ((BASH_SUBSHELL > 0 || depth > 1)); then return 0; fi
        _sec_of "$ln"
        if [ "$_SEC_K" != "$_SEC_LAST" ]; then
            _SEC_LAST=$_SEC_K
            if [ -n "${SECTIONS_TRACE:-}" ]; then printf '%s %s\n' "$_SEC_K" "$SECONDS" >> "$SECTIONS_TRACE"; fi
            if [ "$_SEC_K" = 0 ] || [ -n "${_SEC_WANT[_SEC_K]:-}" ]; then
                if [ "$_SEC_E" = 1 ]; then _SEC_E=0; set -e; fi
                if [ "$_SEC_U" = 1 ]; then _SEC_U=0; set -u; fi
            else
                if [[ $- == *e* ]]; then _SEC_E=1; set +e; fi
                if [[ $- == *u* ]]; then _SEC_U=1; set +u; fi
            fi
        fi
        if [ "$_SEC_K" = 0 ] || [ -n "${_SEC_WANT[_SEC_K]:-}" ]; then return 0; fi
        if [ "$cmd" = finish ]; then return 0; fi  # always: a run that ends prints its totals; one cut short does not
        if [[ "$cmd" =~ ^(declare|export|readonly|typeset)[[:space:]] ]]; then return 0; fi
        if _sec_assign_only "$cmd"; then return 0; fi
        return 1
    }
    # extdebug cannot be turned on here (bash would look for bashdb): it is turned on by the first command.
    _sec_boot() { shopt -s extdebug; trap '_sec_dbg $LINENO' DEBUG; }
    trap '_sec_boot' DEBUG
fi
