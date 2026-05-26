get_latest_version_from_redirect() {
    local repo=$1 latest_url final
    latest_url="https://github.com/${repo}/releases/latest"

    if [[ $(type -P curl) ]]; then
        local curl_args=(-fsSLI -o /dev/null -w '%{url_effective}')
        [[ $proxy ]] && curl_args+=(--proxy "$proxy")
        final=$(curl "${curl_args[@]}" "$latest_url" 2>/dev/null)
    else
        final=$(_wget -T 8 -t 1 --spider -S "$latest_url" 2>&1 | awk '/^[[:space:]]*Location: /{loc=$2} END{print loc}')
    fi

    echo "$final" | sed -n 's#.*/releases/tag/\(v[0-9][0-9A-Za-z._-]*\).*#\1#p' | head -n 1
}

get_latest_version() {
    case $1 in
    core)
        name=$is_core_name
        repo=$is_core_repo
        url="https://api.github.com/repos/${is_core_repo}/releases/latest?v=$RANDOM"
        ;;
    sh)
        name="$is_core_name 脚本"
        repo=$is_sh_repo
        url="https://api.github.com/repos/$is_sh_repo/releases/latest?v=$RANDOM"
        ;;
    caddy)
        name="Caddy"
        repo=$is_caddy_repo
        url="https://api.github.com/repos/$is_caddy_repo/releases/latest?v=$RANDOM"
        ;;
    esac
    latest_ver=$(_wget -qO- $url | grep tag_name | grep -E -o 'v[0-9][0-9A-Za-z._-]*')
    [[ $latest_ver ]] || latest_ver=$(get_latest_version_from_redirect "$repo")
    [[ ! $latest_ver ]] && {
        err "获取 ${name} 最新版本失败."
    }
    unset name url repo
}
download() {
    latest_ver=$2
    [[ ! $latest_ver ]] && get_latest_version $1
    # tmp dir
    tmpdir=$(mktemp -u)
    [[ ! $tmpdir ]] && {
        tmpdir=/tmp/tmp-$RANDOM
    }
    mkdir -p $tmpdir
    case $1 in
    core)
        name=$is_core_name
        tmpfile=$tmpdir/$is_core.tar.gz
        link="https://github.com/${is_core_repo}/releases/download/${latest_ver}/${is_core}-${latest_ver:1}-linux-${is_arch}.tar.gz"
        download_file
        tar zxf $tmpfile --strip-components 1 -C $is_core_dir/bin
        chmod +x $is_core_bin
        ;;
    sh)
        name="$is_core_name 脚本"
        tmpfile=$tmpdir/sh.tar.gz
        link="https://github.com/${is_sh_repo}/releases/download/${latest_ver}/code.tar.gz"
        download_file
        tar zxf $tmpfile -C $is_sh_dir
        chmod +x $is_sh_bin ${is_sh_bin/$is_core/sb}
        ;;
    caddy)
        name="Caddy"
        tmpfile=$tmpdir/caddy.tar.gz
        # https://github.com/caddyserver/caddy/releases/download/v2.6.4/caddy_2.6.4_linux_amd64.tar.gz
        link="https://github.com/${is_caddy_repo}/releases/download/${latest_ver}/caddy_${latest_ver:1}_linux_${is_arch}.tar.gz"
        download_file
        tar zxf $tmpfile -C $tmpdir
        cp -f $tmpdir/caddy $is_caddy_bin
        chmod +x $is_caddy_bin
        ;;
    esac
    rm -rf $tmpdir
    unset latest_ver
}
download_file() {
    if ! _wget -t 5 -c $link -O $tmpfile; then
        rm -rf $tmpdir
        err "\n下载 ${name} 失败.\n"
    fi
}
