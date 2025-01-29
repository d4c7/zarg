# SPDX-FileCopyrightText: 2023-2025 David Castañon Belloso <d4c7@proton.me>
# SPDX-License-Identifier: EUPL-1.2
# This file is part of zarg project (https://github.com/d4c7/zarg)

#COMP_WORDS	Un array que contiene todas las palabras ingresadas en la línea de comandos.
#COMP_CWORD	El índice en COMP_WORDS de la palabra que se está autocompletando.
#COMP_LINE	La línea completa de comando ingresada por el usuario.
#COMP_POINT	La posición actual del cursor dentro de COMP_LINE.
#COMPREPLY	Un array donde se deben colocar las sugerencias de autocompletado.
#COMP_KEY	Indica qué tecla activó la autocompletación (?, <Tab>, etc.).


__sample_autocomplete_debug() {
    if [[ -n ${BASH_COMP_DEBUG_FILE:-} ]]; then
        echo "$*" >>"${BASH_COMP_DEBUG_FILE}"
    fi
}

_sample_autocomplete_completions() {
    local cursor_pos_in_word
    cursor_pos_in_word=$(( COMP_POINT - ${#COMP_LINE%%${COMP_WORDS[COMP_CWORD]}*} ))

    __sample_autocomplete_debug
    __sample_autocomplete_debug "========= starting completion logic =========="
    __sample_autocomplete_debug "COMP_LINE  = ${COMP_LINE}"
    __sample_autocomplete_debug "COMP_POINT = ${COMP_POINT}"
    __sample_autocomplete_debug "${COMP_WORDS[@]} --complete ${COMP_POINT}"
    __sample_autocomplete_debug "cursor_pos_in_word = ${cursor_pos_in_word}"
    
    #__sample_autocomplete_debug "result  is ${res}"


    COMPREPLY+=(${COMP_LINE} --complete ${COMP_POINT})

}

complete -F _sample_autocomplete_completions zig-out/bin/sample_autocomplete
