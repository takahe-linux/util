#!/usr/bin/bash
#
# Rebuild all outdated packages.
#
# Author:   Alastair Hughes
# Contact:  < hobbitalastair at yandex dot com >

# Initial setup.
VERSION="0.1"
USAGE="<config dir> [<target>]..."
source "$(dirname "$(realpath "$0")")/libmain.sh"
source "$(dirname "$(realpath "$0")")/libbuild.sh"

# Create a new dict of targets.
declare -A old

rebuild() {
    # Rebuild the given target, as needed.
    configdir="$1"
    shift
    local current_old=false

    # First, check whether any of the dependencies are marked as old.
    for dep in ${graph["$1"]}; do
        if [ -z "${old["${dep}"]}" ]; then
            error 1 "Encountered '$1' before it's dependency '${dep}'!"
        elif "${old["${dep}"]}"; then
            current_old=true
        fi
    done

    # Then check wether this is old.
    if old "${configdir}" "$1"; then
        current_old=true
    fi

    # Finally, rebuild and save the result.
    old["$1"]="${current_old}"
    if "${current_old}"; then
        message warn "$1 is out of date"
        run_action build "${configdir}" "$1"
        local ret="$?"
        if [ "${ret}" -ne 0 ]; then
            message error "Failed to build '$1'!"
        else
            mark "${configdir}" "$1" || \
                error $? "Invalid target '$1'!"
            old["$1"]=false
        fi
    else
        message info "$1 is up to date"
    fi
}

main() {
    # Print the current status.
    local configdir="$1"
    shift
    local target_list="$(get_target_list "${configdir}" $@)"
    generate_graph "${configdir}" ${target_list}
    generate_states "${configdir}"
    walk "${CONFIGDIR}" "rebuild" ${target_list}
}

# Parse the arguments.
CONFIGDIR="" # Set the initial config dir.
TARGETS="" # The set of targets to investigate.
parseargs $@ # Initial argument parse.
# Manual argument parse.
for arg in $@; do
    ignore_arg "${arg}" || \
    case "${arg}" in
        *) if [ "${CONFIGDIR}" == "" ]; then
            CONFIGDIR="${arg}"
        else
            TARGETS+=" ${arg}"
        fi;;
    esac
done
check_configdir "${CONFIGDIR}"

main "${CONFIGDIR}" ${TARGETS}

