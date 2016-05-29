# Package manipulation functions.

# Standardise the source and package name extensions.
PKGEXT='.pkg.tar.xz'
SRCEXT='.src.tar.gz'

pkgdirsrctar() {
    # Print the source tarball path for the given package dir.
    local configdir="$1"
    local pkgdir="$2"
    
    # Bail if there is no .SRCINFO
    srcinfo="${configdir}/src/${pkgdir}/.SRCINFO"
    if [ ! -f "${srcinfo}" ]; then
        exit 2
    fi
    # Extract the pkgbase/version/rel
    pkgbase="$(sed -n "${srcinfo}" -e '/^pkgbase = /p' | sed -e 's:.*= ::')"
    pkgver="$(sed -n "${srcinfo}" -e '/pkgver = /p' | sed -e 's:.*= ::')"
    pkgrel="$(sed -n "${srcinfo}" -e '/pkgrel = /p' | sed -e 's:.*= ::')"
    
    printf "%s-%s-%s%s" "${pkgbase}" "${pkgver}" "${pkgrel}" "${SRCEXT}"
}

pkgdirpackages() {
    # Print the resulting filenames of the given packages.
    # I did try using makepkg --packagelist, but it was *painfully* slow...
    # TODO: Figure out how to use makepkg --packagelist.
    local configdir="$1"
    local pkgdir="$2"

    # Bail if there is no .SRCINFO
    srcinfo="${configdir}/src/${pkgdir}/.SRCINFO"
    if [ ! -f "${srcinfo}" ]; then
        exit 2
    fi
    # Extract the pkgbase/version/rel/arch
    local pkgnames="$(sed -n "${srcinfo}" -e '/^pkgname = /p' | \
        sed -e 's:.*= ::')"
    local pkgver="$(sed -n "${srcinfo}" -e '/pkgver = /p' | sed -e 's:.*= ::')"
    local pkgrel="$(sed -n "${srcinfo}" -e '/pkgrel = /p' | sed -e 's:.*= ::')"
    local arch="$(sed -n "${srcinfo}" -e '/arch = /p' | sed -e 's:.*= ::')"

    # Set the CARCH variable to the current architecture.
    local CARCH="$(uname -m)"
    # Set some other expected variables from the config.
    . <(genmakepkgconf "${configdir}" "${pkgdir}") || \
        error 1 "Failed to generate a temporary config file!"

    if [ "${arch}" != "any" ]; then
        local carch="${CARCH}"
    else
        local carch="any"
    fi
    for pkgname in ${pkgnames}; do
        printf "%s-%s-%s-%s%s\n" "${pkgname}" "${pkgver}" "${pkgrel}" \
            "${carch}" "${PKGEXT}"
    done
}

localmakepkgconf() {
    # Write the current main makepkg.conf to stdout.

    cat /etc/makepkg.conf

    local localconf="${XDG_CONFIG_HOME:-$HOME/.config}/pacman/makepkg.conf"
    if [ -f "${localconf}" ]; then
        cat "${localconf}"
    fi

    if [ -f "${HOME}/.makepkg.conf" ]; then
        cat "${HOME}/.makepkg.conf"
    fi
}

genmakepkgconf() {
    # Write a temporary config script to stdout.
    local configdir="$1"
    local pkgdir="$2"

    # Extract PACKAGER and MAKEFLAGS from the local makepkg.conf.
    # TODO: Use something else?
    printf '# Local configs'
    localmakepkgconf | /usr/bin/grep -e '^PACKAGER='
    localmakepkgconf | /usr/bin/grep -e '^MAKEFLAGS="'

    # Print a 'config.sh' equivalent.
    # We also standardise PKGEXT and SRCEXT.
    printf '
# Standard config variables.
_target_arch="%s"
_target_arch_alias="%s"
_target_triplet="%s"
_local_triplet="${CHOST}"
_target_cflags="%s"
_target_ldflags="%s"

# Sysroot is hardcoded to /sysroot.
_sysroot=/sysroot
_toolroot="/opt/${_target_triplet}"

# We standardise PKGEXT.
PKGEXT="%s"
SRCEXT="%s"

# Set BUILDDIR to something sane (for building src tarballs).
BUILDDIR="/tmp/builder-%s"
' \
        "${config[arch]}" "${config[arch_alias]}" "${config[triplet]}" \
        "${config[cflags]}" "${config[ldflags]}" "${PKGEXT}" "${SRCEXT}" \
        "${config[id]}"

    # If a package config file exists, add it...
    local local_config="${configdir}/src/${pkgdir%%/*}/makepkg.conf"
    if [ -f "${local_config}" ]; then
        cat "${local_config}"
    fi
}

findpkgdir() {
    # Given a package name and dir, find all packages in that dir that provide
    # the given package name.
    local configdir="$1"
    local target_name="$2"
    local dir="$3"

    local pkg providers provdir provider
    while IFS=":" read pkg providers; do
        if [ "${pkg}" == "${target_name}" ]; then
            while IFS="\/ " read provdir provider; do
                if [ "${provdir}" == "${dir}" ]; then
                    printf "%s/%s\n" "${provdir}" "${provider}";
                fi
            done < <(printf "${providers}\n")
        fi
    done < "${configdir}/pkglist"
}

findpkgdeps() {
    # Evaluate the deps piped in on stdin to dirs.
    local configdir="$1"
    local prefix="$2"
    while IFS= read line; do
        local deptype="$(printf "${line}" | cut -d= -f1 | sed -e 's:[ \t]::g')"
        local dep="$(printf "${line}" | cut -d= -f2- | sed -e 's:[ \t]::g')"
        if [ -z "${dep}" ]; then
            continue
        fi
        if [ "${deptype}" == "hostdepends" ]; then
            # Find the providers; we ignore missing deps, and assume that
            # they will be installed from the host distro's repos.
            depdir="toolchain"
            skip_missing="true"
        elif [ "${prefix}" == "toolchain" ] && \
            [ "${deptype}" != "targetdepends" ]; then
            # Find the providers; we ignore missing deps, and assume that
            # they will be installed from the host distro's repos.
            depdir="toolchain"
            skip_missing="true"
        else
            # Find the providers; we assume that they will be cross-compiled.
            depdir="packages"
            skip_missing="false"
        fi
        local providers="$(findpkgdir "${configdir}" "${dep}" "${depdir}")" \
            || error 3 "Failed to get providers for '${dep}'!"
        if [ "${skip_missing}" == "false" ] && [ -z "${providers}" ]; then
            error 4 "Found no providers for '${dep}' of type '${deptype}'!"
        elif [ -n "${providers}" ]; then
            printf "%s\n" "${providers}"
        fi
    done < /dev/stdin
}
