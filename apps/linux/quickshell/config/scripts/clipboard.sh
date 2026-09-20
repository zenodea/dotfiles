#!/usr/bin/env bash

dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/clipboard"
entries="$dir/entries"
index="$dir/index"
limit=200

mkdir -p "$entries"
touch "$index"

drop_from_index() {
    local new
    new=$(mktemp "$dir/.index.XXXXXX")
    grep -v "^$1	" "$index" > "$new" 2> /dev/null
    mv -f "$new" "$index"
}

prune() {
    cut -f1 "$index" | sort -u > "$dir/.keep"
    local f
    for f in "$entries"/*; do
        [[ -f "$f" ]] || continue
        grep -qx "$(basename "$f")" "$dir/.keep" || rm -f "$f"
    done
    rm -f "$dir/.keep"
}

case "${1:-list}" in
    watch)
        wl-paste --type text --watch "$0" add text text/plain &
        wl-paste --type image/png --watch "$0" add image image/png &
        wl-paste --type image/jpeg --watch "$0" add image image/jpeg &
        wait
        ;;

    add)
        tmp=$(mktemp "$dir/.incoming.XXXXXX")
        cat > "$tmp"
        if [[ ! -s "$tmp" ]]; then
            rm -f "$tmp"
            exit 0
        fi

        kind=${2:-text}
        mime=${3:-text/plain}
        if [[ "$kind" == image ]]; then
            preview=${mime#image/}
        else
            preview=$(head -c 400 "$tmp" | tr -cd '[:print:]\n\t' | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ $//')
            if [[ -z "$preview" ]]; then
                rm -f "$tmp"
                exit 0
            fi
        fi

        id=$(sha1sum < "$tmp" | cut -c1-16)
        mv -f "$tmp" "$entries/$id"

        drop_from_index "$id"
        new=$(mktemp "$dir/.index.XXXXXX")
        printf '%s\t%s\t%s\t%s\n' "$id" "$kind" "$mime" "$preview" > "$new"
        head -n "$((limit - 1))" "$index" >> "$new"
        mv -f "$new" "$index"

        prune
        echo added
        ;;

    list) cat "$index" ;;

    path) printf '%s' "$entries/$2" ;;

    copy)
        line=$(grep -m1 "^$2	" "$index") || exit 0
        kind=$(cut -f2 <<< "$line")
        mime=$(cut -f3 <<< "$line")
        if [[ "$kind" == image ]]; then
            wl-copy --type "$mime" < "$entries/$2"
        else
            wl-copy < "$entries/$2"
        fi
        ;;

    delete)
        rm -f "$entries/$2"
        drop_from_index "$2"
        ;;

    wipe)
        rm -rf "$entries"
        : > "$index"
        mkdir -p "$entries"
        ;;
esac
