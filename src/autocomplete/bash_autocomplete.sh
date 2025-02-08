# SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
# SPDX-License-Identifier: EUPL-1.2
# This file is part of zarg project (https://github.com/d4c7/zarg)

__%{TARGET}%_debug() {
    if [[ -n ${BASH_COMP_DEBUG_FILE:-} ]]; then
        echo "$*" >>"${BASH_COMP_DEBUG_FILE}"
    fi
}

_%{TARGET}%_completions() {
    __%{TARGET}%_debug
    __%{TARGET}%_debug "========================"
    __%{TARGET}%_debug "COMP_LINE  = ${COMP_LINE}"
    __%{TARGET}%_debug "COMP_POINT = ${COMP_POINT}"
    
    while IFS=$'\t' read -r col1 col2; do
        COMPREPLY+=("$col1")
    done < <(%{AUTOCOMPLETER}% suggest --cursor-pos=${COMP_POINT} -- "${COMP_LINE}")

    if [[ ${#COMPREPLY[@]} -gt 0 ]]; then
        first_item="${COMPREPLY[0]}"
        if [[ "$first_item" == DIR:* ]]; then
            COMPREPLY=( $(compgen -d -- "${first_item#DIR:}") )
        elif [[ "$first_item" == FILE:* ]]; then
            COMPREPLY=( $(compgen -f -- "${first_item#FILE:}") )
        fi
    fi

    __%{TARGET}%_debug "COMPREPLY    = ${COMPREPLY[@]}"

}

complete -o nospace  -F _%{TARGET}%_completions %{TARGET}%
