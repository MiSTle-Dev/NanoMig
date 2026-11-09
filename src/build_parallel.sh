#!/bin/bash
# Build several variants in parallel (one gw_sh process each).
#   ./build_par.sh 020 lcd tc60k   variants = suffix of scripts/build_<variant>.tcl
#   ./build_par.sh default         scripts/build.tcl
#   ./build_par.sh all             every scripts/build*.tcl
#   JOBS=8 ./build_par.sh all      limit parallel jobs (default: nproc)
#
# Every variant builds in its own copy of the tree (.par/<variant>) because
# gw_sh writes ./impl and update_xml.tcl writes misc/amiga_xml.hex, which
# would collide between concurrent runs. The .bin files (all named differently) end up in buildall/.
# gw_sh output goes to .par/<variant>/build.log; with a single variant it is
# also shown on the terminal.

[ $# -eq 0 ] && { sed -n '2,8p' "$0"; exit 1; }

SRC=$(cd "$(dirname "$0")" && pwd)
JOBS=${JOBS:-$(nproc)}

# gw_sh is Qt based; "minimal" needs neither X nor OpenGL (override: QT_QPA_PLATFORM=xcb ...)
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-minimal}

# logo (skipped if the file is not next to this script)
cat "$SRC/scripts/mistle_logo_ansi.txt" 2>/dev/null

if [ "$*" = all ]; then
    set -- $(cd "$SRC/scripts" && ls build*.tcl | sed 's/^build_\?//; s/\.tcl$//; s/^$/default/')
fi

[ $# -eq 1 ] && [ "$1" != all ] && export SINGLE=1

build() {
    v=$1; w=$SRC/.par/$v; ext=_$v
    [ "$v" = default ] && ext=
    printf '\e[1;33mbuilding %s ...\e[0m\n' "$v"
    rm -rf "$w"; mkdir -p "$w" "$SRC/buildall"
    (cd "$SRC" && tar -cf - --exclude=./.par --exclude=./buildall --exclude=./impl --exclude=./.git .) | tar -xf - -C "$w"
    if [ -n "$SINGLE" ]; then
        (cd "$w" && gw_sh scripts/build$ext.tcl) 2>&1 | tee "$w/build.log"
    else
        (cd "$w" && gw_sh scripts/build$ext.tcl) > "$w/build.log" 2>&1
    fi
    # gw_sh's exit code is unreliable, so judge by the .bin file
    if cp "$w"/impl/pnr/*.bin "$SRC/buildall/" 2>/dev/null; then
        printf '\e[1;34mOK    %s\e[0m\n' "$v"
    else
        printf '\e[1;31mFAIL  %s  (no .bin, see .par/%s/build.log)\e[0m\n' "$v" "$v"
    fi
}
export -f build
export SRC

printf '%s\n' "$@" | xargs -P "$JOBS" -I{} bash -c 'build {}'
printf '\e[1;34mDone!\e[0m\n'
