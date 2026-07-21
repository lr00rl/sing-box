#!/bin/bash

protocol_list=(
    TUIC
    Trojan
    Hysteria2
    VMess-WS
    VMess-TCP
    VMess-HTTP
    VMess-QUIC
    Shadowsocks
    VMess-H2-TLS
    VMess-WS-TLS
    VLESS-H2-TLS
    VLESS-WS-TLS
    Trojan-H2-TLS
    Trojan-WS-TLS
    VMess-HTTPUpgrade-TLS
    VLESS-HTTPUpgrade-TLS
    Trojan-HTTPUpgrade-TLS
    VLESS-REALITY
    VLESS-HTTP2-REALITY
    AnyTLS
    # Direct
    Socks
)
ss_method_list=(
    aes-128-gcm
    aes-256-gcm
    chacha20-ietf-poly1305
    xchacha20-ietf-poly1305
    2022-blake3-aes-128-gcm
    2022-blake3-aes-256-gcm
    2022-blake3-chacha20-poly1305
)
mainmenu=(
    "添加配置"
    "更改配置"
    "查看配置"
    "删除配置"
    "运行管理"
    "更新"
    "卸载"
    "帮助"
    "其他"
    "关于"
)
info_list=(
    "协议 (protocol)"
    "地址 (address)"
    "端口 (port)"
    "用户ID (id)"
    "传输协议 (network)"
    "伪装类型 (type)"
    "伪装域名 (host)"
    "路径 (path)"
    "传输层安全 (TLS)"
    "应用层协议协商 (Alpn)"
    "密码 (password)"
    "加密方式 (encryption)"
    "链接 (URL)"
    "目标地址 (remote addr)"
    "目标端口 (remote port)"
    "流控 (flow)"
    "SNI (serverName)"
    "指纹 (Fingerprint)"
    "公钥 (Public key)"
    "用户名 (Username)"
    "跳过证书验证 (allowInsecure)"
    "拥塞控制算法 (congestion_control)"
)
change_list=(
    "更改协议"
    "更改端口"
    "更改域名"
    "更改路径"
    "更改密码"
    "更改 UUID"
    "更改加密方式"
    "更改目标地址"
    "更改目标端口"
    "更改密钥"
    "更改 SNI (serverName)"
    "更改伪装网站"
    "更改用户名 (Username)"
    "更改连接地址"
)
servername_list=(
    www.amazon.com
    www.ebay.com
    www.paypal.com
    www.cloudflare.com
    dash.cloudflare.com
    aws.amazon.com
)

# shuf fallback for systems without shuf (e.g., Alpine BusyBox)
if ! type -P shuf &>/dev/null; then
    shuf() {
        local min max n
        while [[ $# -gt 0 ]]; do
            case $1 in
            -i) IFS=- read min max <<<"$2"; shift 2 ;;
            -n) n=$2; shift 2 ;;
            esac
        done
        echo $(( RANDOM % (max - min + 1) + min ))
    }
fi

is_random_ss_method=${ss_method_list[$(shuf -i 4-6 -n1)]} # random only use ss2022
is_random_servername=${servername_list[$(shuf -i 0-${#servername_list[@]} -n1) - 1]}

msg() {
    [[ $is_json_out ]] && { echo -e "$@" >&2; return; }
    echo -e "$@"
}

msg_ul() {
    echo -e "\e[4m$@\e[0m"
}

# pause
pause() {
    [[ $is_json_out ]] && return 0
    echo
    echo -ne "按 $(_green Enter 回车键) 继续, 或按 $(_red Ctrl + C) 取消."
    read -rs -d $'\n'
    echo
}

get_uuid() {
    tmp_uuid=$(cat /proc/sys/kernel/random/uuid)
}

normalize_addr() {
    local addr=$1
    [[ $addr == \[*\] ]] && addr=${addr:1:${#addr}-2}
    echo "$addr"
}

is_valid_ipv4() {
    local addr=$1 octet
    [[ $addr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<<"$addr"
    for octet in "${octets[@]}"; do
        ((octet >= 0 && octet <= 255)) || return 1
    done
}

is_valid_ipv6() {
    local addr
    addr=$(normalize_addr "$1")
    [[ $addr == *:* && $addr =~ ^[0-9A-Fa-f:]+$ ]]
}

is_valid_domain() {
    [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

is_valid_addr() {
    local addr
    addr=$(normalize_addr "$1")
    is_valid_ipv4 "$addr" || is_valid_ipv6 "$addr" || is_valid_domain "$addr"
}

fetch_public_ip_direct() {
    local family=$1 url=$2

    (
        unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
        if [[ $(type -P curl) ]]; then
            curl -fsSL -"${family}" --noproxy '*' --connect-timeout 5 --max-time 10 "$url"
        else
            wget --no-check-certificate -"${family}" -T 5 -t 1 -qO- "$url"
        fi
    )
}

get_public_ip() {
    local family=$1 candidate url
    local -a urls
    case $family in
    4)
        urls=(
            https://api.ipify.org
            https://ipv4.icanhazip.com
            https://checkip.amazonaws.com
            https://ifconfig.me/ip
            https://ip.sb
        )
        ;;
    6)
        urls=(
            https://api64.ipify.org
            https://ipv6.icanhazip.com
            https://ifconfig.me/ip
            https://ip.sb
        )
        ;;
    *)
        return 1
        ;;
    esac
    for url in "${urls[@]}"; do
        candidate=$(fetch_public_ip_direct "$family" "$url" 2>/dev/null | tr -d '\r' | sed -n '1{s/[[:space:]]//g;p;q}')
        [[ ! $candidate ]] && continue
        if [[ $family == 4 ]]; then
            is_valid_ipv4 "$candidate" && {
                echo "$candidate"
                return 0
            }
        else
            is_valid_ipv6 "$candidate" && {
                echo "$candidate"
                return 0
            }
        fi
    done
    return 1
}

get_host_dns_result() {
    local dns_type=$1 result url
    local -a dns_urls=(
        "https://dns.google/resolve?name=$host&type=$dns_type"
        "https://cloudflare-dns.com/dns-query?name=$host&type=$dns_type"
        "https://dns.quad9.net/dns-query?name=$host&type=$dns_type"
    )
    if [[ $(type -P getent) ]]; then
        case $dns_type in
        a)
            result=$(getent hosts "$host" 2>/dev/null | awk '/^[0-9.]+[[:space:]]/{print $1}' | sort -u)
            ;;
        aaaa)
            result=$(getent hosts "$host" 2>/dev/null | awk '/:/{print $1}' | sort -u)
            ;;
        esac
        [[ $result ]] && {
            echo "$result"
            return 0
        }
    fi
    for url in "${dns_urls[@]}"; do
        if [[ $url == *"/dns-query"* ]]; then
            result=$(_wget -qO- --header="accept: application/dns-json" "$url" 2>/dev/null)
        else
            result=$(_wget -qO- "$url" 2>/dev/null)
        fi
        [[ $result ]] && {
            echo "$result"
            return 0
        }
    done
    return 1
}

config_addr_file() {
    local config_name=${1:-$is_config_name}
    echo "$is_conf_dir/${config_name%.json}.addr"
}

load_config_addr() {
    local addr_file
    unset is_custom_addr
    addr_file=$(config_addr_file "$1")
    [[ ! -f $addr_file ]] && return
    read -r is_custom_addr <"$addr_file"
    is_custom_addr=$(normalize_addr "$is_custom_addr")
    [[ $(is_test addr "$is_custom_addr") ]] || unset is_custom_addr
}

save_config_addr() {
    local addr_file
    addr_file=$(config_addr_file "$1")
    if [[ $is_custom_addr ]]; then
        is_custom_addr=$(normalize_addr "$is_custom_addr")
        [[ $(is_test addr "$is_custom_addr") ]] || err "连接地址 ($is_custom_addr) 无效."
        echo "$is_custom_addr" >"$addr_file"
    else
        rm -f "$addr_file"
    fi
}

ask_custom_addr() {
    ask string server_addr "自动获取失败, 请输入连接地址 (IP 或域名):"
    server_addr=$(normalize_addr "$server_addr")
    [[ $(is_test addr "$server_addr") ]] || err "请输入正确的 IP 或域名."
    ip=$server_addr
    is_custom_addr=$server_addr
}

detect_ip() {
    [[ $ip || $is_no_auto_tls || $is_gen || $is_dont_get_ip ]] && return
    if [[ $server_addr ]]; then
        server_addr=$(normalize_addr "$server_addr")
        [[ $(is_test addr "$server_addr") ]] || err "连接地址 ($server_addr) 无效."
        ip=$server_addr
        is_custom_addr=$server_addr
        return
    fi
    ip=$(get_public_ip 4)
    [[ ! $ip ]] && ip=$(get_public_ip 6)
    [[ $ip ]]
}

get_ip() {
    detect_ip && return
    [[ ! $ip ]] && {
        err "获取服务器 IP 失败.."
    }
}

get_port() {
    is_count=0
    while :; do
        ((is_count++))
        if [[ $is_count -ge 233 ]]; then
            err "自动获取可用端口失败次数达到 233 次, 请检查端口占用情况."
        fi
        tmp_port=$(shuf -i 445-65535 -n 1)
        [[ ! $(is_test port_used $tmp_port) && $tmp_port != $port ]] && break
    done
}

get_pbk() {
    is_tmp_pbk=($($is_core_bin generate reality-keypair | sed 's/.*://'))
    is_public_key=${is_tmp_pbk[1]}
    is_private_key=${is_tmp_pbk[0]}
}

show_list() {
    PS3=''
    COLUMNS=1
    select i in "$@"; do echo; done &
    wait
    # i=0
    # for v in "$@"; do
    #     ((i++))
    #     echo "$i) $v"
    # done
    # echo

}

is_test() {
    case $1 in
    number)
        echo $2 | grep -E '^[1-9][0-9]?+$'
        ;;
    port)
        if [[ $(is_test number $2) ]]; then
            [[ $2 -le 65535 ]] && echo ok
        fi
        ;;
    port_used)
        [[ $(is_port_used $2) && ! $is_cant_test_port ]] && echo ok
        ;;
    domain)
        is_valid_domain "$2" && echo ok
        ;;
    addr)
        is_valid_addr "$2" && echo ok
        ;;
    path)
        echo $2 | grep -E -i '^\/\w(\w|\-|\/)?+\w$'
        ;;
    uuid)
        echo $2 | grep -E -i '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        ;;
    esac

}

is_port_used() {
    if [[ $(type -P netstat) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(netstat -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi
    if [[ $(type -P ss) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(ss -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi
    is_cant_test_port=1
    msg "$is_warn 无法检测端口是否可用."
    msg "请执行: $(_yellow "${cmd} update -y; ${cmd} install net-tools -y") 来修复此问题."
}

# ask input a string or pick a option for list.
ask() {
    [[ $is_json_out ]] && json_err "interactive_input_required" "operation needs interactive input ($1); in --json mode pass all required args (and --addr)" 2
    case $1 in
    set_ss_method)
        is_tmp_list=(${ss_method_list[@]})
        is_default_arg=$is_random_ss_method
        is_opt_msg="\n请选择加密方式:\n"
        is_opt_input_msg="(默认\e[92m $is_default_arg\e[0m):"
        is_ask_set=ss_method
        ;;
    set_protocol)
        is_tmp_list=(${protocol_list[@]})
        [[ $is_no_auto_tls ]] && {
            unset is_tmp_list
            for v in ${protocol_list[@]}; do
                [[ $(grep -i "\-tls$" <<<$v) ]] && is_tmp_list=(${is_tmp_list[@]} $v)
            done
        }
        is_opt_msg="\n请选择协议:\n"
        is_ask_set=is_new_protocol
        ;;
    set_change_list)
        is_tmp_list=()
        for v in ${is_can_change[@]}; do
            is_tmp_list+=("${change_list[$v]}")
        done
        is_opt_msg="\n请选择更改:\n"
        is_ask_set=is_change_str
        is_opt_input_msg=$3
        ;;
    string)
        is_ask_set=$2
        is_opt_input_msg=$3
        ;;
    list)
        is_ask_set=$2
        [[ ! $is_tmp_list ]] && is_tmp_list=($3)
        is_opt_msg=$4
        is_opt_input_msg=$5
        ;;
    get_config_file)
        is_tmp_list=("${is_all_json[@]}")
        is_opt_msg="\n请选择配置:\n"
        is_ask_set=is_config_file
        ;;
    mainmenu)
        is_tmp_list=("${mainmenu[@]}")
        is_ask_set=is_main_pick
        is_emtpy_exit=1
        ;;
    esac
    msg $is_opt_msg
    [[ ! $is_opt_input_msg ]] && is_opt_input_msg="请选择 [\e[91m1-${#is_tmp_list[@]}\e[0m]:"
    [[ $is_tmp_list ]] && show_list "${is_tmp_list[@]}"
    while :; do
        echo -ne $is_opt_input_msg
        read REPLY
        [[ ! $REPLY && $is_emtpy_exit ]] && exit
        [[ ! $REPLY && $is_default_arg ]] && export $is_ask_set=$is_default_arg && break
        [[ "$REPLY" == "${is_str}2${is_get}3${is_opt}3" && $is_ask_set == 'is_main_pick' ]] && {
            msg "\n${is_get}2${is_str}3${is_msg}3b${is_tmp}o${is_opt}y\n" && exit
        }
        if [[ ! $is_tmp_list ]]; then
            [[ $(grep port <<<$is_ask_set) ]] && {
                [[ ! $(is_test port "$REPLY") ]] && {
                    msg "$is_err 请输入正确的端口, 可选(1-65535)"
                    continue
                }
                if [[ $(is_test port_used $REPLY) && $is_ask_set != 'door_port' ]]; then
                    msg "$is_err 无法使用 ($REPLY) 端口."
                    continue
                fi
            }
            [[ $(grep path <<<$is_ask_set) && ! $(is_test path "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的路径, 例如: /$tmp_uuid"
                continue
            }
            [[ $(grep uuid <<<$is_ask_set) && ! $(is_test uuid "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的 UUID, 例如: $tmp_uuid"
                continue
            }
            [[ $(grep ^y$ <<<$is_ask_set) ]] && {
                [[ $(grep -i ^y$ <<<"$REPLY") ]] && break
                msg "请输入 (y)"
                continue
            }
            [[ $REPLY ]] && export $is_ask_set=$REPLY && msg "使用: ${!is_ask_set}" && break
        else
            [[ $(is_test number "$REPLY") ]] && is_ask_result=${is_tmp_list[$REPLY - 1]}
            [[ $is_ask_result ]] && export $is_ask_set="$is_ask_result" && msg "选择: ${!is_ask_set}" && break
        fi

        msg "输入${is_err}"
    done
    unset is_opt_msg is_opt_input_msg is_tmp_list is_ask_result is_default_arg is_emtpy_exit
}

# ------------- Lattice sidecar metadata (design-09 §E.2) -------------
# Upstream sing-box loads /etc/sing-box/config.json (-c) plus every
# /etc/sing-box/conf/*.json (-C) with DisallowUnknownFields at BOTH the top and
# inbound level, so it FATALs on any unknown key (e.g. `_lattice`). Node and line
# identity therefore live in a sidecar the service never parses: $is_lattice_meta
# (/etc/sing-box/lattice-metadata.json), OUTSIDE conf/. Shape:
#   {version, node:{node_uuid,node_id,purity_percent,quality},
#    lines:{"<conf>.json":{line_id}}}

# Atomically apply a jq program to the sidecar (create-if-absent). Mirrors the
# repo's backup->jq->mv pattern: jq writes a temp file and we only mv it into
# place on success, so the live sidecar is never left half-written.
lattice_meta_apply() {
    local filter=$1
    shift
    local tmp base='{"version":1,"node":{},"lines":{}}'
    [[ -s $is_lattice_meta ]] && base=$(jq -c . "$is_lattice_meta" 2>/dev/null)
    [[ $base ]] || base='{"version":1,"node":{},"lines":{}}'
    mkdir -p "$(dirname "$is_lattice_meta")" 2>/dev/null
    tmp=$(mktemp "${TMPDIR:-/tmp}/lattice-meta.XXXXXX") || return 1
    if jq "$@" "$filter" <<<"$base" >"$tmp" 2>/dev/null; then
        mv "$tmp" "$is_lattice_meta"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Record node-level identity from the environment. LATTICE_NODE_PURITY must be an
# integer 0-100 (else warn + skip, never fail create); LATTICE_NODE_QUALITY is a
# short free-form string. Fields absent from the env are preserved, not wiped.
lattice_meta_write_node() {
    local purity=$LATTICE_NODE_PURITY quality=$LATTICE_NODE_QUALITY purity_arg=
    if [[ $purity ]]; then
        if [[ $purity =~ ^[0-9]+$ ]] && [[ $purity -ge 0 && $purity -le 100 ]]; then
            purity_arg=$purity
        else
            warn "LATTICE_NODE_PURITY ($purity) 无效, 已忽略 (应为 0-100 的整数)."
        fi
    fi
    lattice_meta_apply '
        .node.node_uuid=$node_uuid
        | if $node_id != "" then .node.node_id=$node_id else . end
        | if $purity != "" then .node.purity_percent=($purity|tonumber) else . end
        | if $quality != "" then .node.quality=$quality else . end
    ' --arg node_uuid "$LATTICE_IDENTITY_UUID" \
        --arg node_id "$LATTICE_NODE_ID" \
        --arg purity "$purity_arg" \
        --arg quality "$quality"
}

# Look up a line's line_id from the sidecar (keyed by conf filename).
lattice_meta_line_id() {
    [[ -f $is_lattice_meta ]] || return 0
    jq -r --arg n "$1" '.lines[$n].line_id // empty' "$is_lattice_meta" 2>/dev/null
}

# Assign/preserve a line's line_id under its conf filename key.
lattice_meta_write_line() {
    lattice_meta_apply '.lines[$n].line_id=$line_id' --arg n "$1" --arg line_id "$2"
}

# Drop a line's sidecar entry (deletion, or the old key after a rename).
lattice_meta_del_line() {
    [[ -f $is_lattice_meta ]] || return 0
    lattice_meta_apply 'del(.lines[$n])' --arg n "$1"
}

# Flat {line_id,node_uuid,node_id} object for one conf filename, as the machine
# interface emits it. Sidecar wins; a legacy in-config _lattice block (pre-sidecar
# nodes) fills any gaps so migrated readers keep emitting the same shape.
lattice_meta_obj_for() {
    local name=$1 raw_file=$2 sidecar='{}' legacy='{}'
    [[ -f $is_lattice_meta ]] && sidecar=$(jq -c --arg n "$name" '
        (.lines[$n] // {}) as $line
        | (.node // {}) as $node
        | {line_id:($line.line_id // ""), node_uuid:($node.node_uuid // ""), node_id:($node.node_id // "")}
        | with_entries(select(.value != ""))' "$is_lattice_meta" 2>/dev/null)
    [[ $sidecar ]] || sidecar='{}'
    [[ $raw_file && -f $raw_file ]] && legacy=$(jq -c '(.inbounds[0]._lattice // {})
        | {line_id:(.line_id // ""), node_uuid:(.node_uuid // ""), node_id:(.node_id // "")}
        | with_entries(select(.value != ""))' "$raw_file" 2>/dev/null)
    [[ $legacy ]] || legacy='{}'
    jq -cn --argjson l "$legacy" --argjson s "$sidecar" '$l + $s'
}

# Node-level identity object for `info --json` (sidecar .node, legacy _lattice fallback).
lattice_meta_node_obj() {
    local raw_file=$1 node='{}' legacy='{}'
    [[ -f $is_lattice_meta ]] && node=$(jq -c '.node // {}' "$is_lattice_meta" 2>/dev/null)
    [[ $node ]] || node='{}'
    [[ $raw_file && -f $raw_file ]] && legacy=$(jq -c '(.inbounds[0]._lattice // {})
        | {node_uuid:(.node_uuid // ""), node_id:(.node_id // "")}
        | with_entries(select(.value != ""))' "$raw_file" 2>/dev/null)
    [[ $legacy ]] || legacy='{}'
    jq -cn --argjson l "$legacy" --argjson n "$node" '($l + $n) | with_entries(select(.value != "" and .value != null))'
}

# create file
create() {
    case $1 in
    server)
        is_tls=none
        get new
        # listen
        is_listen='listen: "::"'
        # file name
        if [[ $host ]]; then
            is_config_name=$2-${host}.json
            is_listen='listen: "127.0.0.1"'
        elif [[ $is_anytls_domain ]]; then
            is_config_name=$2-${is_anytls_domain}.json
        else
            is_config_name=$2-${port}.json
        fi
        is_json_file=$is_conf_dir/$is_config_name
        # get json
        [[ $is_change || ! $json_str ]] && get protocol $2
        [[ $net == "reality" ]] && is_add_public_key=",outbounds:[{type:\"direct\"},{tag:\"public_key_$is_public_key\",type:\"direct\"}]"
        is_new_json=$(jq "{inbounds:[{tag:\"$is_config_name\",type:\"$is_protocol\",$is_listen,listen_port:$port,$json_str}]$is_add_public_key}" <<<{})
        # design-09 §E.2: node/line identity goes to the sidecar, NOT the config,
        # so the strict-parsing service can still load conf/*.json. Skip on gen/
        # test flows since they never persist a config. Preserve line_id continuity:
        # explicit env -> new filename's sidecar entry -> old filename's entry (a
        # rename) -> legacy in-config _lattice (pre-sidecar migration) -> fresh uuid.
        if [[ $LATTICE_IDENTITY_UUID && ! $is_gen && ! $is_test_json ]]; then
            is_lattice_line_id=$LATTICE_LINE_ID
            [[ ! $is_lattice_line_id ]] && is_lattice_line_id=$(lattice_meta_line_id "$is_config_name")
            [[ ! $is_lattice_line_id && $is_config_file && $is_config_file != "$is_config_name" ]] && is_lattice_line_id=$(lattice_meta_line_id "$is_config_file")
            [[ ! $is_lattice_line_id && $is_config_file && -f $is_conf_dir/$is_config_file ]] && is_lattice_line_id=$(jq -r '.inbounds[0]._lattice.line_id // empty' "$is_conf_dir/$is_config_file" 2>/dev/null)
            [[ ! $is_lattice_line_id && -f $is_json_file ]] && is_lattice_line_id=$(jq -r '.inbounds[0]._lattice.line_id // empty' "$is_json_file" 2>/dev/null)
            [[ ! $is_lattice_line_id ]] && get_uuid && is_lattice_line_id=$tmp_uuid
            lattice_meta_write_node
            lattice_meta_write_line "$is_config_name" "$is_lattice_line_id"
            # rename: identity now lives under the new key; drop the stale old key.
            [[ $is_config_file && $is_config_file != "$is_config_name" ]] && lattice_meta_del_line "$is_config_file"
        fi
        [[ $is_test_json ]] && return # tmp test
        # only show json, dont save to file.
        [[ $is_gen ]] && {
            msg
            jq <<<$is_new_json
            msg
            return
        }
        # del old file
        [[ $is_config_file ]] && is_no_del_msg=1 && del $is_config_file
        # save json to file
        cat <<<$is_new_json >$is_json_file
        save_config_addr "$is_config_name"
        if [[ $is_new_install ]]; then
            # config.json
            create config.json
        fi
        # caddy auto tls
        [[ $is_caddy && $host && ! $is_no_auto_tls ]] && {
            create caddy $net
        }
        # restart core
        manage restart &
        ;;
    client)
        is_tls=tls
        is_client=1
        get info $2
        [[ ! $is_client_id_json ]] && err "($is_config_name) 不支持生成客户端配置."
        is_new_json=$(jq '{outbounds:[{tag:'\"$is_config_name\"',protocol:'\"$is_protocol\"','"$is_client_id_json"','"$is_stream"'}]}' <<<{})
        msg
        jq <<<$is_new_json
        msg
        ;;
    caddy)
        load caddy.sh
        [[ $is_install_caddy ]] && caddy_config new
        [[ ! $(grep "$is_caddy_conf" $is_caddyfile) ]] && {
            msg "import $is_caddy_conf/*.conf" >>$is_caddyfile
        }
        [[ ! -d $is_caddy_conf ]] && mkdir -p $is_caddy_conf
        caddy_config $2
        manage restart caddy &
        ;;
    config.json)
        is_log='log:{output:"/var/log/'$is_core'/access.log",level:"info","timestamp":true}'
        is_dns='dns:{}'
        is_ntp='ntp:{"enabled":true,"server":"time.apple.com"},'
        if [[ -f $is_config_json ]]; then
            [[ $(jq .ntp.enabled $is_config_json) != "true" ]] && is_ntp=
        else
            [[ ! $is_ntp_on ]] && is_ntp=
        fi
        is_outbounds='outbounds:[{tag:"direct",type:"direct"}]'
        is_server_config_json=$(jq "{$is_log,$is_dns,$is_ntp$is_outbounds}" <<<{})
        cat <<<$is_server_config_json >$is_config_json
        manage restart &
        ;;
    esac
}

# change config file
change() {
    is_change=1
    is_dont_show_info=1
    if [[ $2 ]]; then
        case ${2,,} in
        full)
            is_change_id=full
            ;;
        new)
            is_change_id=0
            ;;
        port)
            is_change_id=1
            ;;
        host)
            is_change_id=2
            ;;
        path)
            is_change_id=3
            ;;
        pass | passwd | password)
            is_change_id=4
            ;;
        id | uuid)
            is_change_id=5
            ;;
        ssm | method | ss-method | ss_method)
            is_change_id=6
            ;;
        dda | door-addr | door_addr)
            is_change_id=7
            ;;
        ddp | door-port | door_port)
            is_change_id=8
            ;;
        key | publickey | privatekey)
            is_change_id=9
            ;;
        sni | servername | servernames)
            is_change_id=10
            ;;
        web | proxy-site)
            is_change_id=11
            ;;
        addr | address)
            is_change_id=13
            ;;
        *)
            [[ $is_try_change ]] && return
            err "无法识别 ($2) 更改类型."
            ;;
        esac
    fi
    [[ $is_try_change ]] && return
    [[ $is_dont_auto_exit ]] && {
        get info $1
    } || {
        [[ $is_change_id ]] && {
            is_change_msg=${change_list[$is_change_id]}
            [[ $is_change_id == 'full' ]] && {
                [[ $3 ]] && is_change_msg="更改多个参数" || is_change_msg=
            }
            [[ $is_change_msg ]] && _green "\n快速执行: $is_change_msg"
        }
        info $1
        [[ $is_auto_get_config ]] && msg "\n自动选择: $is_config_file"
    }
    is_old_net=$net
    [[ $is_tcp_http ]] && net=http
    [[ $host ]] && net=$is_protocol-$net-tls
    [[ $is_reality && $net_type =~ 'http' ]] && net=rh2

    [[ $3 == 'auto' ]] && is_auto=1
    # if is_dont_show_info exist, cant show info.
    is_dont_show_info=
    # if not prefer args, show change list and then get change id.
    [[ ! $is_change_id ]] && {
        ask set_change_list
        is_change_id=${is_can_change[$REPLY - 1]}
    }
    case $is_change_id in
    full)
        add $net ${@:3}
        ;;
    0)
        # new protocol
        is_set_new_protocol=1
        add ${@:3}
        ;;
    1)
        # new port
        is_new_port=$3
        [[ $host && ! $is_caddy || $is_no_auto_tls ]] && err "($is_config_file) 不支持更改端口, 因为没啥意义."
        if [[ $is_new_port && ! $is_auto ]]; then
            [[ ! $(is_test port $is_new_port) ]] && err "请输入正确的端口, 可选(1-65535)"
            [[ $is_new_port != 443 && $(is_test port_used $is_new_port) ]] && err "无法使用 ($is_new_port) 端口"
        fi
        [[ $is_auto ]] && get_port && is_new_port=$tmp_port
        [[ ! $is_new_port ]] && ask string is_new_port "请输入新端口:"
        if [[ $is_caddy && $host ]]; then
            net=$is_old_net
            is_https_port=$is_new_port
            load caddy.sh
            caddy_config $net
            manage restart caddy &
            info
        else
            add $net $is_new_port
        fi
        ;;
    2)
        # new host
        is_new_host=$3
        [[ ! $host ]] && err "($is_config_file) 不支持更改域名."
        [[ ! $is_new_host ]] && ask string is_new_host "请输入新域名:"
        old_host=$host # del old host
        add $net $is_new_host
        ;;
    3)
        # new path
        is_new_path=$3
        [[ ! $path ]] && err "($is_config_file) 不支持更改路径."
        [[ $is_auto ]] && get_uuid && is_new_path=/$tmp_uuid
        [[ ! $is_new_path ]] && ask string is_new_path "请输入新路径:"
        add $net auto auto $is_new_path
        ;;
    4)
        # new password
        is_new_pass=$3
        if [[ $ss_password || $password ]]; then
            [[ $is_auto ]] && {
                get_uuid && is_new_pass=$tmp_uuid
                [[ $ss_password ]] && is_new_pass=$(get ss2022)
            }
        else
            err "($is_config_file) 不支持更改密码."
        fi
        [[ ! $is_new_pass ]] && ask string is_new_pass "请输入新密码:"
        password=$is_new_pass
        ss_password=$is_new_pass
        is_socks_pass=$is_new_pass
        add $net
        ;;
    5)
        # new uuid
        is_new_uuid=$3
        [[ ! $uuid ]] && err "($is_config_file) 不支持更改 UUID."
        [[ $is_auto ]] && get_uuid && is_new_uuid=$tmp_uuid
        [[ ! $is_new_uuid ]] && ask string is_new_uuid "请输入新 UUID:"
        add $net auto $is_new_uuid
        ;;
    6)
        # new method
        is_new_method=$3
        [[ $net != 'ss' ]] && err "($is_config_file) 不支持更改加密方式."
        [[ $is_auto ]] && is_new_method=$is_random_ss_method
        [[ ! $is_new_method ]] && {
            ask set_ss_method
            is_new_method=$ss_method
        }
        add $net auto auto $is_new_method
        ;;
    7)
        # new remote addr
        is_new_door_addr=$3
        [[ $net != 'direct' ]] && err "($is_config_file) 不支持更改目标地址."
        [[ ! $is_new_door_addr ]] && ask string is_new_door_addr "请输入新的目标地址:"
        door_addr=$is_new_door_addr
        add $net
        ;;
    8)
        # new remote port
        is_new_door_port=$3
        [[ $net != 'direct' ]] && err "($is_config_file) 不支持更改目标端口."
        [[ ! $is_new_door_port ]] && {
            ask string door_port "请输入新的目标端口:"
            is_new_door_port=$door_port
        }
        add $net auto auto $is_new_door_port
        ;;
    9)
        # new is_private_key is_public_key
        is_new_private_key=$3
        is_new_public_key=$4
        [[ ! $is_reality ]] && err "($is_config_file) 不支持更改密钥."
        if [[ $is_auto ]]; then
            get_pbk
            add $net
        else
            [[ $is_new_private_key && ! $is_new_public_key ]] && {
                err "无法找到 Public key."
            }
            [[ ! $is_new_private_key ]] && ask string is_new_private_key "请输入新 Private key:"
            [[ ! $is_new_public_key ]] && ask string is_new_public_key "请输入新 Public key:"
            if [[ $is_new_private_key == $is_new_public_key ]]; then
                err "Private key 和 Public key 不能一样."
            fi
            is_tmp_json=$is_conf_dir/$is_config_file-$uuid
            cp -f $is_conf_dir/$is_config_file $is_tmp_json
            sed -i s#$is_private_key #$is_new_private_key# $is_tmp_json
            $is_core_bin check -c $is_tmp_json &>/dev/null
            if [[ $? != 0 ]]; then
                is_key_err=1
                is_key_err_msg="Private key 无法通过测试."
            fi
            sed -i s#$is_new_private_key #$is_new_public_key# $is_tmp_json
            $is_core_bin check -c $is_tmp_json &>/dev/null
            if [[ $? != 0 ]]; then
                is_key_err=1
                is_key_err_msg+="Public key 无法通过测试."
            fi
            rm $is_tmp_json
            [[ $is_key_err ]] && err $is_key_err_msg
            is_private_key=$is_new_private_key
            is_public_key=$is_new_public_key
            is_test_json=
            add $net
        fi
        ;;
    10)
        # new serverName
        is_new_servername=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持更改 serverName."
        [[ $is_auto ]] && is_new_servername=$is_random_servername
        [[ ! $is_new_servername ]] && ask string is_new_servername "请输入新的 serverName:"
        is_servername=$is_new_servername
        add $net
        ;;
    11)
        # new proxy site
        is_new_proxy_site=$3
        [[ ! $is_caddy && ! $host ]] && {
            err "($is_config_file) 不支持更改伪装网站."
        }
        [[ ! -f $is_caddy_conf/${host}.conf.add ]] && err "无法配置伪装网站."
        [[ ! $is_new_proxy_site ]] && ask string is_new_proxy_site "请输入新的伪装网站 (例如 example.com):"
        proxy_site=$(sed 's#^.*//##;s#/$##' <<<$is_new_proxy_site)
        load caddy.sh
        caddy_config proxy
        manage restart caddy &
        msg "\n已更新伪装网站为: $(_green $proxy_site) \n"
        ;;
    12)
        # new socks user
        [[ ! $is_socks_user ]] && err "($is_config_file) 不支持更改用户名 (Username)."
        ask string is_socks_user "请输入新用户名 (Username):"
        add $net
        ;;
    13)
        # new connect addr
        is_new_addr=$3
        [[ $is_protocol == 'anytls' && $is_anytls_domain ]] && err "($is_config_file) 不支持更改连接地址."
        [[ $is_auto ]] && unset is_new_addr is_custom_addr
        if [[ ! $is_auto && ! $is_new_addr ]]; then
            ask string is_new_addr "请输入新的连接地址 (IP 或域名, auto 为自动获取):"
        fi
        [[ ${is_new_addr,,} == 'auto' ]] && is_auto=1 && unset is_new_addr is_custom_addr
        if [[ ! $is_auto ]]; then
            is_new_addr=$(normalize_addr "$is_new_addr")
            [[ $(is_test addr "$is_new_addr") ]] || err "请输入正确的 IP 或域名."
            is_custom_addr=$is_new_addr
        fi
        add $net
        ;;
    esac
}

# delete config.
del() {
    # dont get ip
    is_dont_get_ip=1
    [[ $is_conf_dir_empty ]] && return # not found any json file.
    # get a config file
    [[ ! $is_config_file ]] && get info $1
    if [[ $is_config_file ]]; then
        if [[ $is_main_start && ! $is_no_del_msg ]]; then
            msg "\n是否删除配置文件?: $is_config_file"
            pause
        fi
        rm -rf $is_conf_dir/"$is_config_file"
        rm -f "$(config_addr_file "$is_config_file")"
        # drop the Lattice sidecar entry only on a standalone delete; create()'s
        # internal rewrite (is_new_json set) handles rename cleanup itself.
        [[ ! $is_new_json ]] && lattice_meta_del_line "$is_config_file"
        [[ ! $is_new_json ]] && manage restart &
        [[ ! $is_no_del_msg ]] && _green "\n已删除: $is_config_file\n"

        [[ $is_caddy ]] && {
            is_del_host=$host
            [[ $is_change ]] && {
                [[ ! $old_host ]] && return # no host exist or not set new host;
                is_del_host=$old_host
            }
            [[ $is_del_host && $host != $old_host && -f $is_caddy_conf/$is_del_host.conf ]] && {
                rm -rf $is_caddy_conf/$is_del_host.conf $is_caddy_conf/$is_del_host.conf.add
                [[ ! $is_new_json ]] && manage restart caddy &
            }
        }
    fi
    if [[ ! $(ls $is_conf_dir | grep .json) && ! $is_change ]]; then
        warn "当前配置目录为空! 因为你刚刚删除了最后一个配置文件."
        is_conf_dir_empty=1
    fi
    unset is_dont_get_ip
    [[ $is_dont_auto_exit ]] && unset is_config_file
}

# uninstall
uninstall() {
    if [[ $is_caddy ]]; then
        is_tmp_list=("卸载 $is_core_name" "卸载 ${is_core_name} & Caddy")
        ask list is_do_uninstall
    else
        ask string y "是否卸载 ${is_core_name}? [y]:"
    fi
    manage stop &>/dev/null
    manage disable &>/dev/null
    rm -rf $is_core_dir $is_log_dir $is_sh_bin ${is_sh_bin/$is_core/sb}
    if [[ $is_systemd ]]; then
        rm -f /lib/systemd/system/$is_core.service
    elif [[ $is_openrc ]]; then
        rm -f /etc/init.d/$is_core
    fi
    sed -i "/$is_core/d" /root/.bashrc
    # uninstall caddy; 2 is ask result
    if [[ $REPLY == '2' ]]; then
        manage stop caddy &>/dev/null
        manage disable caddy &>/dev/null
        if [[ $is_systemd ]]; then
            rm -rf $is_caddy_dir $is_caddy_bin /lib/systemd/system/caddy.service
        elif [[ $is_openrc ]]; then
            rm -rf $is_caddy_dir $is_caddy_bin /etc/init.d/caddy
        fi
    fi
    _green "\n卸载完成!"
    msg "脚本哪里需要完善? 请反馈"
    msg "反馈问题) $(msg_ul https://github.com/${is_sh_repo}/issues)\n"
}

# manage run status
manage() {
    [[ $is_dont_auto_exit ]] && return
    case $1 in
    1 | start)
        is_do=start
        is_do_msg=启动
        is_test_run=1
        ;;
    2 | stop)
        is_do=stop
        is_do_msg=停止
        ;;
    3 | r | restart)
        is_do=restart
        is_do_msg=重启
        is_test_run=1
        ;;
    *)
        is_do=$1
        is_do_msg=$1
        ;;
    esac
    case $2 in
    caddy)
        is_do_name=$2
        is_run_bin=$is_caddy_bin
        is_do_name_msg=Caddy
        ;;
    *)
        is_do_name=$is_core
        is_run_bin=$is_core_bin
        is_do_name_msg=$is_core_name
        ;;
    esac
    if [[ $is_systemd ]]; then
        systemctl $is_do $is_do_name 2>/dev/null
    elif [[ $is_openrc ]]; then
        case $is_do in
        enable)
            rc-update add $is_do_name default 2>/dev/null
            ;;
        disable)
            rc-update del $is_do_name default 2>/dev/null
            ;;
        *)
            rc-service $is_do_name $is_do 2>/dev/null
            ;;
        esac
    fi
    [[ $is_test_run && ! $is_new_install ]] && {
        sleep 2
        if [[ ! $(pgrep -f $is_run_bin) ]]; then
            is_run_fail=${is_do_name_msg,,}
            [[ ! $is_no_manage_msg ]] && {
                msg
                warn "($is_do_msg) $is_do_name_msg 失败"
                _yellow "检测到运行失败, 自动执行测试运行."
                get test-run
                _yellow "测试结束, 请按 Enter 退出."
            }
        fi
    }
}

# add a config
add() {
    is_lower=${1,,}
    if [[ $is_lower ]]; then
        case $is_lower in
        ws | tcp | quic | http)
            is_new_protocol=VMess-${is_lower^^}
            ;;
        wss | h2 | hu | vws | vh2 | vhu | tws | th2 | thu)
            is_new_protocol=$(sed -E "s/^V/VLESS-/;s/^T/Trojan-/;/^(W|H)/{s/^/VMess-/};s/WSS/WS/;s/HU/HTTPUpgrade/" <<<${is_lower^^})-TLS
            ;;
        r | reality)
            is_new_protocol=VLESS-REALITY
            ;;
        rh2)
            is_new_protocol=VLESS-HTTP2-REALITY
            ;;
        ss)
            is_new_protocol=Shadowsocks
            ;;
        door | direct)
            is_new_protocol=Direct
            ;;
        tuic)
            is_new_protocol=TUIC
            ;;
        hy | hy2 | hysteria*)
            is_new_protocol=Hysteria2
            ;;
        trojan)
            is_new_protocol=Trojan
            ;;
        anytls)
            is_new_protocol=AnyTLS
            ;;
        socks)
            is_new_protocol=Socks
            ;;
        *)
            for v in ${protocol_list[@]}; do
                [[ $(grep -E -i "^$is_lower$" <<<$v) ]] && is_new_protocol=$v && break
            done

            [[ ! $is_new_protocol ]] && err "无法识别 ($1), 请使用: $is_core add [protocol] [args... | auto]"
            ;;
        esac
    fi

    # no prefer protocol
    [[ ! $is_new_protocol ]] && ask set_protocol

    if [[ ${is_new_protocol,,} == 'anytls' ]]; then
        is_core_major=$(echo "$is_core_ver" | cut -d. -f1)
        is_core_minor=$(echo "$is_core_ver" | cut -d. -f2)
        if [[ ${is_core_major:-0} -lt 1 || ${is_core_major:-0} -eq 1 && ${is_core_minor:-0} -lt 12 ]]; then
            err "当前 sing-box 版本 ($is_core_ver) 不支持 AnyTLS，请先升级 sing-box core 到 1.12.0 或更高版本。"
        fi
    fi

    case ${is_new_protocol,,} in
    *-tls)
        is_use_tls=1
        is_use_host=$2
        is_use_uuid=$3
        is_use_path=$4
        is_add_opts="[host] [uuid] [/path]"
        ;;
    vmess* | tuic*)
        is_use_port=$2
        is_use_uuid=$3
        is_add_opts="[port] [uuid]"
        ;;
    trojan* | hysteria*)
        is_use_port=$2
        is_use_pass=$3
        is_add_opts="[port] [password]"
        ;;
    *reality*)
        is_reality=1
        is_use_port=$2
        is_use_uuid=$3
        is_use_servername=$4
        is_add_opts="[port] [uuid] [sni]"
        ;;
    shadowsocks)
        is_use_port=$2
        is_use_pass=$3
        is_use_method=$4
        is_add_opts="[port] [password] [method]"
        ;;
    direct)
        is_use_port=$2
        is_use_door_addr=$3
        is_use_door_port=$4
        is_add_opts="[port] [remote_addr] [remote_port]"
        ;;
    anytls*)
        is_use_port=$2
        is_use_pass=$3
        [[ $4 ]] && is_anytls_domain=$4
        is_add_opts="[port] [password] [domain]"
        ;;
    socks)
        is_socks=1
        is_use_port=$2
        is_use_socks_user=$3
        is_use_socks_pass=$4
        is_add_opts="[port] [username] [password]"
        ;;
    esac

    [[ $1 && ! $is_change ]] && {
        msg "\n使用协议: $is_new_protocol"
        # err msg tips
        is_err_tips="\n\n请使用: $(_green $is_core add $1 $is_add_opts) 来添加 $is_new_protocol 配置"
    }

    # remove old protocol args
    if [[ $is_set_new_protocol ]]; then
        case $is_old_net in
        h2 | ws | httpupgrade)
            old_host=$host
            [[ ! $is_use_tls ]] && unset host is_no_auto_tls
            ;;
        reality)
            net_type=
            [[ ! $(grep -i reality <<<$is_new_protocol) ]] && is_reality=
            ;;
        ss)
            [[ $(is_test uuid $ss_password) ]] && uuid=$ss_password
            ;;
        esac
        [[ ! $(is_test uuid $uuid) ]] && uuid=
        [[ $(is_test uuid $password) ]] && uuid=$password
    fi

    # no-auto-tls only use h2,ws,grpc
    if [[ $is_no_auto_tls && ! $is_use_tls ]]; then
        err "$is_new_protocol 不支持手动配置 tls."
    fi

    # prefer args.
    if [[ $2 ]]; then
        for v in is_use_port is_use_uuid is_use_host is_use_path is_use_pass is_use_method is_use_door_addr is_use_door_port; do
            [[ ${!v} == 'auto' ]] && unset $v
        done

        if [[ $is_use_port ]]; then
            [[ ! $(is_test port ${is_use_port}) ]] && {
                err "($is_use_port) 不是一个有效的端口. $is_err_tips"
            }
            [[ $(is_test port_used $is_use_port) && ! $is_gen ]] && {
                err "无法使用 ($is_use_port) 端口. $is_err_tips"
            }
            port=$is_use_port
        fi
        if [[ $is_use_door_port ]]; then
            [[ ! $(is_test port ${is_use_door_port}) ]] && {
                err "(${is_use_door_port}) 不是一个有效的目标端口. $is_err_tips"
            }
            door_port=$is_use_door_port
        fi
        if [[ $is_use_uuid ]]; then
            [[ ! $(is_test uuid $is_use_uuid) ]] && {
                err "($is_use_uuid) 不是一个有效的 UUID. $is_err_tips"
            }
            uuid=$is_use_uuid
        fi
        if [[ $is_use_path ]]; then
            [[ ! $(is_test path $is_use_path) ]] && {
                err "($is_use_path) 不是有效的路径. $is_err_tips"
            }
            path=$is_use_path
        fi
        if [[ $is_use_method ]]; then
            is_tmp_use_name=加密方式
            is_tmp_list=${ss_method_list[@]}
            for v in ${is_tmp_list[@]}; do
                [[ $(grep -E -i "^${is_use_method}$" <<<$v) ]] && is_tmp_use_type=$v && break
            done
            [[ ! ${is_tmp_use_type} ]] && {
                warn "(${is_use_method}) 不是一个可用的${is_tmp_use_name}."
                msg "${is_tmp_use_name}可用如下: "
                for v in ${is_tmp_list[@]}; do
                    msg "\t\t$v"
                done
                msg "$is_err_tips\n"
                exit 1
            }
            ss_method=$is_tmp_use_type
        fi
        [[ $is_use_pass ]] && ss_password=$is_use_pass && password=$is_use_pass
        [[ $is_use_host ]] && host=$is_use_host
        [[ $is_use_door_addr ]] && door_addr=$is_use_door_addr
        [[ $is_use_servername ]] && is_servername=$is_use_servername
        [[ $is_use_socks_user ]] && is_socks_user=$is_use_socks_user
        [[ $is_use_socks_pass ]] && is_socks_pass=$is_use_socks_pass
    fi

    # anytls with domain (ACME TLS)
    if [[ $is_anytls_domain && ! $is_change && ! $is_gen ]]; then
        get_ip
        host=$is_anytls_domain
        get host-test
        host=
    fi

    if [[ $is_use_tls ]]; then
        if [[ ! $is_no_auto_tls && ! $is_caddy && ! $is_gen && ! $is_dont_test_host ]]; then
            # test auto tls
            [[ $(is_test port_used 80) || $(is_test port_used 443) ]] && {
                get_port
                is_http_port=$tmp_port
                get_port
                is_https_port=$tmp_port
                warn "端口 (80 或 443) 已经被占用, 你也可以考虑使用 no-auto-tls"
                msg "\e[41m no-auto-tls 帮助(help)\e[0m: $(msg_ul $is_no_auto_tls_doc_url)\n"
                msg "\n Caddy 将使用非标准端口实现自动配置 TLS, HTTP:$is_http_port HTTPS:$is_https_port\n"
                msg "请确定是否继续???"
                pause
            }
            is_install_caddy=1
        fi
        # set host
        [[ ! $host ]] && ask string host "请输入域名:"
        # test host dns
        get host-test
    else
        # for main menu start, dont auto create args
        if [[ $is_main_start ]]; then

            # set port
            [[ ! $port ]] && ask string port "请输入端口:"

            case ${is_new_protocol,,} in
            socks)
                # set user
                [[ ! $is_socks_user ]] && ask string is_socks_user "请设置用户名:"
                # set password
                [[ ! $is_socks_pass ]] && ask string is_socks_pass "请设置密码:"
                ;;
            shadowsocks)
                # set method
                [[ ! $ss_method ]] && ask set_ss_method
                # set password
                [[ ! $ss_password ]] && ask string ss_password "请设置密码:"
                ;;
            esac

        fi
    fi

    # Dokodemo-Door
    if [[ $is_new_protocol == 'Direct' ]]; then
        # set remote addr
        [[ ! $door_addr ]] && ask string door_addr "请输入目标地址:"
        # set remote port
        [[ ! $door_port ]] && ask string door_port "请输入目标端口:"
    fi

    # Shadowsocks 2022
    if [[ $(grep 2022 <<<$ss_method) ]]; then
        # test ss2022 password
        [[ $ss_password ]] && {
            is_test_json=1
            create server Shadowsocks
            [[ ! $tmp_uuid ]] && get_uuid
            is_test_json_save=$is_conf_dir/tmp-test-$tmp_uuid
            cat <<<"$is_new_json" >$is_test_json_save
            $is_core_bin check -c $is_test_json_save &>/dev/null
            if [[ $? != 0 ]]; then
                warn "Shadowsocks 协议 ($ss_method) 不支持使用密码 ($(_red_bg $ss_password))\n\n你可以使用命令: $(_green $is_core ss2022) 生成支持的密码.\n\n脚本将自动创建可用密码:)"
                ss_password=
                # create new json.
                json_str=
            fi
            is_test_json=
            rm -f $is_test_json_save
        }

    fi

    # install caddy
    if [[ $is_install_caddy ]]; then
        get install-caddy
    fi

    # create json
    create server $is_new_protocol

    # show config info.
    info
}

# get config info
# or somes required args
get() {
    case $1 in
    addr)
        is_addr=$is_custom_addr
        [[ ! $is_addr ]] && is_addr=$host
        [[ ! $is_addr ]] && {
            get_ip
            is_addr=$ip
            is_valid_ipv6 "$ip" && is_addr="[$ip]"
        }
        ;;
    new)
        [[ ! $host ]] && {
            detect_ip || {
                [[ -t 0 ]] && ask_custom_addr || err "获取服务器 IP 失败.."
            }
        }
        [[ ! $port ]] && get_port && port=$tmp_port
        [[ ! $uuid ]] && get_uuid && uuid=$tmp_uuid
        ;;
    file)
        is_file_str=$2
        [[ ! $is_file_str ]] && is_file_str='.json$'
        # is_all_json=("$(ls $is_conf_dir | grep -E $is_file_str)")
        readarray -t is_all_json <<<"$(ls $is_conf_dir | grep -E -i "$is_file_str" | sed '/dynamic-port-.*-link/d' | head -233)" # limit max 233 lines for show.
        [[ ! $is_all_json ]] && err "无法找到相关的配置文件: $2"
        [[ ${#is_all_json[@]} -eq 1 ]] && is_config_file=$is_all_json && is_auto_get_config=1
        [[ ! $is_config_file ]] && {
            [[ $is_dont_auto_exit ]] && return
            ask get_config_file
        }
        ;;
    info)
        get file $2
        if [[ $is_config_file ]]; then
            is_json_str=$(cat $is_conf_dir/"$is_config_file" | sed s#//.*##)
            is_json_data=$(jq '(.inbounds[0]|.type,.listen_port,(.users[0]|.uuid,.password,.username),.method,.password,.override_port,.override_address,(.transport|.type,.path,.headers.host),(.tls|.server_name,.reality.private_key)),(.outbounds[1].tag)' <<<$is_json_str)
            [[ $? != 0 ]] && err "无法读取此文件: $is_config_file"
            is_up_var_set=(null is_protocol port uuid password username ss_method ss_password door_port door_addr net_type path host is_servername is_private_key is_public_key)
            [[ $is_debug ]] && msg "\n------------- debug: $is_config_file -------------"
            i=0
            for v in $(sed 's/""/null/g;s/"//g' <<<"$is_json_data"); do
                ((i++))
                [[ $is_debug ]] && msg "$i-${is_up_var_set[$i]}: $v"
                export ${is_up_var_set[$i]}="${v}"
            done
            for v in ${is_up_var_set[@]}; do
                [[ ${!v} == 'null' ]] && unset $v
            done

            if [[ $is_private_key ]]; then
                is_reality=1
                net_type+=reality
                is_public_key=${is_public_key/public_key_/}
            fi
            load_config_addr "$is_config_file"
            is_socks_user=$username
            is_socks_pass=$password

            # extract anytls ACME domain
            [[ $is_protocol == 'anytls' ]] && {
                is_anytls_domain=$(jq -r '(.inbounds[0].tls.certificate_provider.domain[0] // .inbounds[0].tls.acme.domain[0]) // empty' <<<$is_json_str 2>/dev/null)
            }

            is_config_name=$is_config_file

            if [[ $is_caddy && $host && -f $is_caddy_conf/$host.conf ]]; then
                is_tmp_https_port=$(grep -E -o "$host:[1-9][0-9]?+" $is_caddy_conf/$host.conf | sed s/.*://)
            fi
            if [[ $host && ! -f $is_caddy_conf/$host.conf ]]; then
                is_no_auto_tls=1
            fi
            [[ $is_tmp_https_port ]] && is_https_port=$is_tmp_https_port
            [[ $is_client && $host ]] && port=$is_https_port
            get protocol $is_protocol-$net_type
        fi
        ;;
    protocol)
        get addr # get host or server ip
        is_lower=${2,,}
        net=
        is_users="users:[{uuid:\"$uuid\"}]"
        is_tls_json='tls:{enabled:true,alpn:["h3"],key_path:"'$is_tls_key'",certificate_path:"'$is_tls_cer'"}'
        case $is_lower in
        vmess*)
            is_protocol=vmess
            [[ $is_lower =~ "tcp" || ! $net_type && $is_up_var_set ]] && net=tcp && json_str=$is_users
            ;;
        vless*)
            is_protocol=vless
            ;;
        tuic*)
            net=tuic
            is_protocol=$net
            [[ ! $password ]] && password=$uuid
            is_users="users:[{uuid:\"$uuid\",password:\"$password\"}]"
            json_str="$is_users,congestion_control:\"bbr\",$is_tls_json"
            ;;
        trojan*)
            is_protocol=trojan
            [[ ! $password ]] && password=$uuid
            is_users="users:[{password:\"$password\"}]"
            [[ ! $host ]] && {
                net=trojan
                json_str="$is_users,${is_tls_json/alpn\:\[\"h3\"\],/}"
            }
            ;;
        hysteria2*)
            net=hysteria2
            is_protocol=$net
            [[ ! $password ]] && password=$uuid
            json_str="users:[{password:\"$password\"}],$is_tls_json"
            ;;
        shadowsocks*)
            net=ss
            is_protocol=shadowsocks
            [[ ! $ss_method ]] && ss_method=$is_random_ss_method
            [[ ! $ss_password ]] && {
                ss_password=$uuid
                [[ $(grep 2022 <<<$ss_method) ]] && ss_password=$(get ss2022)
            }
            json_str="method:\"$ss_method\",password:\"$ss_password\""
            ;;
        direct*)
            net=direct
            is_protocol=$net
            json_str="override_port:$door_port,override_address:\"$door_addr\""
            ;;
        anytls*)
            net=anytls
            is_protocol=$net
            [[ ! $password ]] && password=$uuid
            is_users="users:[{password:\"$password\"}]"
            if [[ $is_anytls_domain ]]; then
                # sing-box >= 1.14.0 uses certificate_provider; older uses acme
                is_core_minor=$(echo "$is_core_ver" | cut -d. -f2)
                if [[ ${is_core_minor:-0} -ge 14 ]]; then
                    is_anytls_tls="tls:{enabled:true,certificate_provider:{type:\"acme\",domain:[\"$is_anytls_domain\"]}}"
                else
                    is_anytls_tls="tls:{enabled:true,acme:{domain:[\"$is_anytls_domain\"]}}"
                fi
            else
                is_anytls_tls="${is_tls_json/alpn\:\[\"h3\"\],/}"
            fi
            json_str="$is_users,$is_anytls_tls"
            ;;
        socks*)
            net=socks
            is_protocol=$net
            [[ ! $is_socks_user ]] && is_socks_user=${display_author:-lr00rl}
            [[ ! $is_socks_pass ]] && is_socks_pass=$uuid
            json_str="users:[{username: \"$is_socks_user\", password: \"$is_socks_pass\"}]"
            ;;
        *)
            err "无法识别协议: $is_config_file"
            ;;
        esac
        [[ $net ]] && return # if net exist, dont need more json args
        [[ $host && $is_lower =~ "tls" ]] && {
            [[ ! $path ]] && path="/$uuid"
            is_path_host_json=",path:\"$path\",headers:{host:\"$host\"}"
        }
        case $is_lower in
        *quic*)
            net=quic
            is_json_add="$is_tls_json,transport:{type:\"$net\"}"
            ;;
        *ws*)
            net=ws
            is_json_add="transport:{type:\"$net\"$is_path_host_json,early_data_header_name:\"Sec-WebSocket-Protocol\"}"
            ;;
        *reality*)
            net=reality
            [[ ! $is_servername ]] && is_servername=$is_random_servername
            [[ ! $is_private_key ]] && get_pbk
            is_json_add="tls:{enabled:true,server_name:\"$is_servername\",reality:{enabled:true,handshake:{server:\"$is_servername\",server_port:443},private_key:\"$is_private_key\",short_id:[\"\"]}}"
            [[ $is_lower =~ "http" ]] && {
                is_json_add="$is_json_add,transport:{type:\"http\"}"
            } || {
                is_users=${is_users/uuid/flow:\"xtls-rprx-vision\",uuid}
            }
            ;;
        *http* | *h2*)
            net=http
            [[ $is_lower =~ "up" ]] && net=httpupgrade
            is_json_add="transport:{type:\"$net\"$is_path_host_json}"
            [[ $is_lower =~ "h2" || ! $is_lower =~ "httpupgrade" && $host ]] && {
                net=h2
                is_json_add="${is_tls_json/alpn\:\[\"h3\"\],/},$is_json_add"
            }
            ;;
        *)
            err "无法识别传输协议: $is_config_file"
            ;;
        esac
        json_str="$is_users,$is_json_add"
        ;;
    host-test) # test host dns record; for auto *tls required.
        [[ $is_no_auto_tls || $is_gen || $is_dont_test_host ]] && return
        get_ip
        get ping
        if ! grep -F "$ip" <<<$is_host_dns &>/dev/null; then
            msg "\n请将 ($(_red_bg $host)) 解析到 ($(_red_bg $ip))"
            msg "\n如果使用 Cloudflare, 在 DNS 那; 关闭 (Proxy status / 代理状态), 即是 (DNS only / 仅限 DNS)"
            ask string y "我已经确定解析 [y]:"
            get ping
            if ! grep -F "$ip" <<<$is_host_dns &>/dev/null; then
                _cyan "\n测试结果: $is_host_dns"
                err "域名 ($host) 没有解析到 ($ip)"
            fi
        fi
        ;;
    ssss | ss2022)
        if [[ $(grep 128 <<<$ss_method) ]]; then
            $is_core_bin generate rand 16 --base64
        else
            $is_core_bin generate rand 32 --base64
        fi
        ;;
    ping)
        # is_ip_type="-4"
        # [[ $(grep ":" <<<$ip) ]] && is_ip_type="-6"
        # is_host_dns=$(ping $host $is_ip_type -c 1 -W 2 | head -1)
        is_dns_type="a"
        is_valid_ipv6 "$ip" && is_dns_type="aaaa"
        is_host_dns=$(get_host_dns_result "$is_dns_type")
        ;;
    install-caddy)
        _green "\n安装 Caddy 实现自动配置 TLS.\n"
        load download.sh
        download caddy
        load systemd.sh
        install_service caddy &>/dev/null
        is_caddy=1
        _green "安装 Caddy 成功.\n"
        ;;
    reinstall)
        bash "$is_sh_dir/install.sh" --script-only
        ;;
    test-run)
        if [[ $is_systemd ]]; then
            systemctl list-units --full -all &>/dev/null
            [[ $? != 0 ]] && {
                _yellow "\n无法执行测试, 请检查 systemctl 状态.\n"
                return
            }
        fi
        is_no_manage_msg=1
        if [[ ! $(pgrep -f $is_core_bin) ]]; then
            _yellow "\n测试运行 $is_core_name ..\n"
            manage start &>/dev/null
            if [[ $is_run_fail == $is_core ]]; then
                _red "$is_core_name 运行失败信息:"
                $is_core_bin run -c $is_config_json -C $is_conf_dir
            else
                _green "\n测试通过, 已启动 $is_core_name ..\n"
            fi
        else
            _green "\n$is_core_name 正在运行, 跳过测试\n"
        fi
        if [[ $is_caddy ]]; then
            if [[ ! $(pgrep -f $is_caddy_bin) ]]; then
                _yellow "\n测试运行 Caddy ..\n"
                manage start caddy &>/dev/null
                if [[ $is_run_fail == 'caddy' ]]; then
                    _red "Caddy 运行失败信息:"
                    $is_caddy_bin run --config $is_caddyfile
                else
                    _green "\n测试通过, 已启动 Caddy ..\n"
                fi
            else
                _green "\nCaddy 正在运行, 跳过测试\n"
            fi
        fi
        ;;
    esac
}

# show info
info() {
    [[ ! $is_share_name_prefix ]] && is_share_name_prefix=lr00rl
    if [[ ! $is_protocol ]]; then
        get info $1
    fi
    # is_color=$(shuf -i 41-45 -n1)
    is_color=44
    case $net in
    ws | tcp | h2 | quic | http*)
        if [[ $host ]]; then
            is_color=45
            is_can_change=(0 1 2 3 5 13)
            is_info_show=(0 1 2 3 4 6 7 8)
            [[ $is_protocol == 'vmess' ]] && {
                is_vmess_url=$(jq -c '{v:2,ps:'\"$is_share_name_prefix-$net-$host\"',add:'\"$is_addr\"',port:'\"$is_https_port\"',id:'\"$uuid\"',aid:"0",net:'\"$net\"',host:'\"$host\"',path:'\"$path\"',tls:'\"tls\"'}' <<<{})
                is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
            } || {
                [[ $is_protocol == "trojan" ]] && {
                    uuid=$password
                    # is_info_str=($is_protocol $is_addr $is_https_port $password $net $host $path 'tls')
                    is_can_change=(0 1 2 3 4 13)
                    is_info_show=(0 1 2 10 4 6 7 8)
                }
                is_url="$is_protocol://$uuid@$is_addr:$is_https_port?encryption=none&security=tls&type=$net&host=$host&path=$path#$is_share_name_prefix-$net-$host"
            }
            [[ $is_caddy ]] && is_can_change+=(11)
            is_info_str=($is_protocol $is_addr $is_https_port $uuid $net $host $path 'tls')
        else
            is_type=none
            is_can_change=(0 1 5 13)
            is_info_show=(0 1 2 3 4)
            is_info_str=($is_protocol $is_addr $port $uuid $net)
            [[ $net == "http" ]] && {
                net=tcp
                is_type=http
                is_tcp_http=1
                is_info_show+=(5)
                is_info_str=(${is_info_str[@]/http/tcp http})
            }
            [[ $net == "quic" ]] && {
                is_insecure=1
                is_info_show+=(8 9 20)
                is_info_str+=(tls h3 true)
                is_quic_add=",tls:\"tls\",alpn:\"h3\"" # cant add allowInsecure
            }
            is_vmess_url=$(jq -c "{v:2,ps:\"$is_share_name_prefix-${net}-$is_addr\",add:\"$is_addr\",port:\"$port\",id:\"$uuid\",aid:\"0\",net:\"$net\",type:\"$is_type\"$is_quic_add}" <<<{})
            is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
        fi
        ;;
    ss)
        is_can_change=(0 1 4 6 13)
        is_info_show=(0 1 2 10 11)
        is_url="ss://$(echo -n ${ss_method}:${ss_password} | base64 -w 0)@${is_addr}:${port}#$is_share_name_prefix-$net-${is_addr}"
        is_info_str=($is_protocol $is_addr $port $ss_password $ss_method)
        ;;
    trojan)
        is_insecure=1
        is_can_change=(0 1 4 13)
        is_info_show=(0 1 2 10 4 8 20)
        is_url="$is_protocol://$password@$is_addr:$port?type=tcp&security=tls&insecure=1&allowInsecure=1#$is_share_name_prefix-$net-$is_addr"
        is_info_str=($is_protocol $is_addr $port $password tcp tls true)
        ;;
    hy*)
        is_can_change=(0 1 4 13)
        is_info_show=(0 1 2 10 8 9 20)
        # fix xray core for client use.
        is_sha256=$(openssl x509 -noout -fingerprint -sha256 -in $is_core_dir/bin/tls.cer | sed 's/.*=//;s/://g')
        is_url="$is_protocol://$password@$is_addr:$port?alpn=h3&insecure=1&allowInsecure=1&pinSHA256=$is_sha256#$is_share_name_prefix-$net-$is_addr"
        is_info_str=($is_protocol $is_addr $port $password tls h3 "true (设置, 固定证书>证书指纹(SHA-256): $is_sha256)")
        ;;
    tuic)
        is_insecure=1
        is_can_change=(0 1 4 5 13)
        is_info_show=(0 1 2 3 10 8 9 20 21)
        is_url="$is_protocol://$uuid:$password@$is_addr:$port?alpn=h3&insecure=1&allowInsecure=1&congestion_control=bbr#$is_share_name_prefix-$net-$is_addr"
        is_info_str=($is_protocol $is_addr $port $uuid $password tls h3 true bbr)
        ;;
    reality)
        is_color=41
        is_can_change=(0 1 5 9 10 13)
        is_info_show=(0 1 2 3 15 4 8 16 17 18)
        is_flow=xtls-rprx-vision
        is_net_type=tcp
        [[ $net_type =~ "http" || ${is_new_protocol,,} =~ "http" ]] && {
            is_flow=
            is_net_type=h2
            is_info_show=(${is_info_show[@]/15/})
        }
        is_info_str=($is_protocol $is_addr $port $uuid $is_flow $is_net_type reality $is_servername chrome $is_public_key)
        is_url="$is_protocol://$uuid@$is_addr:$port?encryption=none&security=reality&flow=$is_flow&type=$is_net_type&sni=$is_servername&pbk=$is_public_key&fp=chrome#$is_share_name_prefix-$net-$is_addr"
        ;;
    anytls)
        is_can_change=(0 1 4)
        if [[ $is_anytls_domain ]]; then
            is_info_show=(0 1 2 10 8)
            is_info_str=($is_protocol $is_anytls_domain $port $password tls)
            is_url="anytls://$password@$is_anytls_domain:$port#$is_share_name_prefix-$net-$is_anytls_domain"
        else
            is_insecure=1
            is_can_change+=(13)
            is_info_show=(0 1 2 10 8 20)
            is_info_str=($is_protocol $is_addr $port $password tls true)
            is_url="anytls://$password@$is_addr:$port?insecure=1&allowInsecure=1#$is_share_name_prefix-$net-$is_addr"
        fi
        ;;
    direct)
        is_can_change=(0 1 7 8 13)
        is_info_show=(0 1 2 13 14)
        is_info_str=($is_protocol $is_addr $port $door_addr $door_port)
        ;;
    socks)
        is_can_change=(0 1 12 4 13)
        is_info_show=(0 1 2 19 10)
        is_info_str=($is_protocol $is_addr $port $is_socks_user $is_socks_pass)
        is_url="socks://$(echo -n ${is_socks_user}:${is_socks_pass} | base64 -w 0)@${is_addr}:${port}#$is_share_name_prefix-$net-${is_addr}"
        ;;
    esac
    [[ $is_dont_show_info || $is_gen || $is_dont_auto_exit ]] && return # dont show info
    msg "-------------- $is_config_name -------------"
    for ((i = 0; i < ${#is_info_show[@]}; i++)); do
        a=${info_list[${is_info_show[$i]}]}
        if [[ ${#a} -eq 11 || ${#a} -ge 13 ]]; then
            tt='\t'
        else
            tt='\t\t'
        fi
        msg "$a $tt= \e[${is_color}m${is_info_str[$i]}\e[0m"
    done
    if [[ $is_new_install ]]; then
        warn "首次安装请查看脚本帮助文档: $(msg_ul $is_doc_url)"
    fi
    if [[ $is_url ]]; then
        msg "------------- ${info_list[12]} -------------"
        msg "\e[4;${is_color}m${is_url}\e[0m"
        [[ $is_insecure ]] && {
            warn "某些客户端如(V2rayN 等)导入URL需手动将: 跳过证书验证(allowInsecure) 设置为 true, 或打开: 允许不安全的连接"
        }
    fi
    if [[ $is_no_auto_tls ]]; then
        msg "------------- no-auto-tls INFO -------------"
        msg "端口(port): $port"
        msg "路径(path): $path"
        msg "\e[41m帮助(help)\e[0m: $(msg_ul $is_no_auto_tls_doc_url)"
    fi
    footer_msg
}

# footer msg
footer_msg() {
    [[ $is_core_stop && ! $is_new_json ]] && warn "$is_core_name 当前处于停止状态."
    [[ $is_caddy_stop && $host ]] && warn "Caddy 当前处于停止状态."
    msg "------------- END -------------"
    msg "文档(doc): $(msg_ul $is_doc_url)"
    msg "反馈(issue): $(msg_ul https://github.com/${is_sh_repo}/issues)\n"
}

# URL or qrcode
url_qr() {
    is_dont_show_info=1
    info $2
    if [[ $is_url ]]; then
        [[ $1 == 'url' ]] && {
            msg "\n------------- $is_config_name & URL 链接 -------------"
            msg "\n\e[${is_color}m${is_url}\e[0m\n"
            footer_msg
        } || {
            msg "\n------------- $is_config_name & QR code 二维码 -------------"
            msg "\n\e[${is_color}m${is_url}\e[0m\n"
            msg
            if [[ $(type -P qrencode) ]]; then
                qrencode -t ANSI "${is_url}"
            else
                msg "请安装 qrencode: $(_green "$cmd update -y; $cmd install qrencode -y")"
            fi
            msg
            msg "如果无法正常显示或识别, 请复制上面的 URL 到客户端或本地二维码工具生成."
            footer_msg
        }
    else
        [[ $1 == 'url' ]] && {
            err "($is_config_name) 无法生成 URL 链接."
        } || {
            err "($is_config_name) 无法生成 QR code 二维码."
        }
    fi
}

# ------------- Lattice JSON machine interface (design-09 §E.2) -------------
# All emitters reuse the existing `is_dont_show_info=1; info <file>` pipeline,
# which populates every field var (and is_url) WITHOUT printing, then return
# structured JSON on stdout. Human chrome is routed to stderr by msg()/warn()
# and any TTY prompt becomes a json_err via the ask()/pause() guards.

# Emit one node object from the vars populated by `is_dont_show_info=1; info <file>`.
json_node_obj() {
    local eff_port=$port
    [[ $host && $is_https_port ]] && eff_port=$is_https_port
    local pass=$password
    [[ ! $pass && $ss_password ]] && pass=$ss_password
    local raw_file=$is_conf_dir/$is_config_name
    local enrich='{}'
    # design-09 §E.2: identity comes from the sidecar (legacy _lattice as fallback),
    # not from the config; emitted shape stays identical for machine consumers.
    local lattice_obj
    lattice_obj=$(lattice_meta_obj_for "$is_config_name" "$raw_file")
    if [[ -f $raw_file ]]; then
        enrich=$(jq -c --arg tag "$is_config_name" --argjson lat "$lattice_obj" '
            def compact_obj:
                with_entries(select(.value != "" and .value != null and .value != [] and .value != {}));
            .inbounds[0] as $in
            | ($lat // {}) as $lattice
            | (($lattice // {}) | with_entries(select((.value | type) == "string" and .value != ""))) as $metadata
            | ({
                line_id:($lattice.line_id // ""),
                node_identity_uuid:($lattice.node_uuid // ""),
                listen_host:($in.listen // ""),
                outbound_ref:([(.route.rules // [])[]? | select(((.inbound // []) | index($tag)) != null) | .outbound][0] // "")
            } | compact_obj)
            + (if (($in.users? | type) == "array") then {user_count:($in.users | length), user_known:true} else {} end)
            + (if ($metadata | length) > 0 then {metadata:$metadata} else {} end)
        ' "$raw_file" 2>/dev/null || printf '{}')
    fi
    jq -nc \
        --arg name "$is_config_name" \
        --arg protocol "$is_protocol" \
        --arg network "$net" \
        --arg address "$is_addr" \
        --arg port "$eff_port" \
        --arg uuid "$uuid" \
        --arg password "$pass" \
        --arg method "$ss_method" \
        --arg sni "$is_servername" \
        --arg public_key "$is_public_key" \
        --arg host "$host" \
        --arg path "$path" \
        --arg share_url "$is_url" \
        --argjson enrich "$enrich" \
        '({name:$name,protocol:$protocol,network:$network,address:$address,port:$port,uuid:$uuid,password:$password,method:$method,sni:$sni,public_key:$public_key,host:$host,path:$path,share_url:$share_url} + $enrich)
         | with_entries(select(.value != "" and .value != null))'
}

line_json_obj() {
    local raw_file=$is_conf_dir/$is_config_name
    local node_json custom_addr domain
    [[ -f $raw_file ]] || json_err "not_found" "config file not found: $is_config_name" 2

    node_json=$(json_node_obj)
    custom_addr=$is_custom_addr
    domain=$host
    [[ ! $domain ]] && domain=$is_anytls_domain
    [[ ! $domain ]] && domain=$custom_addr
    [[ ! $domain ]] && domain=$is_servername

    local lattice_obj
    lattice_obj=$(lattice_meta_obj_for "$is_config_name" "$raw_file")

    jq -c \
        --arg core "$is_core" \
        --arg tag "$is_config_name" \
        --arg domain "$domain" \
        --arg custom_addr "$custom_addr" \
        --argjson lat "$lattice_obj" \
        --argjson node "$node_json" '
        def compact_obj:
            with_entries(select(.value != "" and .value != null and .value != []));
        def users_for($in):
            if (($in.users // []) | length) > 0 then
                ($in.users | map({
                    name:(.name // .username // .uuid // ""),
                    uuid:(.uuid // ""),
                    username:(.username // ""),
                    password:(.password // ""),
                    method:($in.method // .method // "")
                } | compact_obj))
            elif (($in.password // "") != "" or ($in.method // "") != "") then
                [{password:($in.password // ""),method:($in.method // "")} | compact_obj]
            else
                []
            end;
        .inbounds[0] as $in
        | {
            core:$core,
            tag:($in.tag // $tag),
            type:($in.type // $node.protocol // ""),
            listen_host:($in.listen // ""),
            listen_port:($in.listen_port // null),
            users:users_for($in),
            outbound:{
                tag:(.outbounds[1].tag // .outbounds[0].tag // "direct"),
                protocol:(.outbounds[1].type // .outbounds[0].type // "direct")
            },
            domain:$domain,
            metadata:({
                config_file:$tag,
                address:($node.address // ""),
                custom_addr:$custom_addr,
                network:($node.network // ""),
                share_url:($node.share_url // ""),
                method:($node.method // ""),
                sni:($node.sni // ""),
                public_key:($node.public_key // ""),
                host:($node.host // ""),
                path:($node.path // ""),
                line_id:($lat.line_id // ""),
                node_uuid:($lat.node_uuid // ""),
                node_id:($lat.node_id // "")
            } | compact_obj)
        } | compact_obj' "$raw_file"
}

# list/ls [filter] -> {ok,count,nodes:[...]}  (pass --addr so addresses resolve without network)
cmd_json_list() {
    is_json_out=1
    local filter="$1"
    [[ ! $filter ]] && filter='\.json$'
    local files=() nodes=() f out
    [[ -d $is_conf_dir ]] && readarray -t files <<<"$(ls "$is_conf_dir" 2>/dev/null | grep -E -i "$filter" | sed '/dynamic-port-.*-link/d')"
    for f in "${files[@]}"; do
        [[ ! $f ]] && continue
        # isolate each node in a subshell so per-file var pollution can't leak
        out="$(
            is_dont_show_info=1
            is_dont_test_host=1
            info "$f" >/dev/null 2>&1
            json_node_obj
        )"
        [[ $out ]] && nodes+=("$out")
    done
    if [[ ${#nodes[@]} -eq 0 ]]; then
        printf '{"ok":true,"count":0,"nodes":[]}\n'
    else
        printf '%s\n' "${nodes[@]}" | jq -s '{ok:true,count:length,nodes:.}'
    fi
    exit 0
}

# inspect [name] --json -> Line shape. With no name, returns all lines.
cmd_json_inspect() {
    is_json_out=1
    local name="$1"
    local files=() matches=() cleaned=() lines=() f out
    if [[ $name ]]; then
        if [[ -f $is_conf_dir/$name ]]; then
            matches=("$name")
        elif [[ -f $is_conf_dir/$name.json ]]; then
            matches=("$name.json")
        elif [[ -d $is_conf_dir ]]; then
            readarray -t matches <<<"$(ls "$is_conf_dir" 2>/dev/null | grep -F -i -- "$name" | sed '/dynamic-port-.*-link/d')"
        fi
        for f in "${matches[@]}"; do
            [[ $f && $f =~ \.json$ ]] && cleaned+=("$f")
        done
        [[ ${#cleaned[@]} -eq 0 ]] && json_err "not_found" "no line matches: $name" 2
        [[ ${#cleaned[@]} -gt 1 ]] && json_err "ambiguous" "multiple lines match: $name" 2
        is_config_file="${cleaned[0]}"
        is_dont_show_info=1
        is_dont_test_host=1
        info "$is_config_file" >/dev/null 2>&1
        printf '{"ok":true,"line":%s}\n' "$(line_json_obj)"
    else
        [[ -d $is_conf_dir ]] && readarray -t files <<<"$(ls "$is_conf_dir" 2>/dev/null | grep -E -i '\.json$' | sed '/dynamic-port-.*-link/d')"
        for f in "${files[@]}"; do
            [[ ! $f ]] && continue
            out="$(
                is_config_file="$f"
                is_dont_show_info=1
                is_dont_test_host=1
                info "$f" >/dev/null 2>&1
                line_json_obj
            )"
            [[ $out ]] && lines+=("$out")
        done
        if [[ ${#lines[@]} -eq 0 ]]; then
            printf '{"ok":true,"count":0,"lines":[]}\n'
        else
            printf '%s\n' "${lines[@]}" | jq -s '{ok:true,count:length,lines:.}'
        fi
    fi
    exit 0
}

# info <name> --json -> {ok,node:{...}}  (exact single match; 0/>1 -> structured error)
cmd_json_info() {
    is_json_out=1
    local name="$1"
    [[ ! $name ]] && json_err "missing_name" "info --json requires a node name" 2
    local matches=() cleaned=() m
    [[ -d $is_conf_dir ]] && readarray -t matches <<<"$(ls "$is_conf_dir" 2>/dev/null | grep -E -i "$name" | sed '/dynamic-port-.*-link/d')"
    for m in "${matches[@]}"; do [[ $m ]] && cleaned+=("$m"); done
    [[ ${#cleaned[@]} -eq 0 ]] && json_err "not_found" "no node matches: $name" 2
    [[ ${#cleaned[@]} -gt 1 ]] && json_err "ambiguous" "multiple nodes match: $name" 2
    is_dont_show_info=1
    is_dont_test_host=1
    info "${cleaned[0]}" 2>/dev/null
    # design-09 §E.2: also surface the Lattice node object (node_uuid/node_id plus
    # purity_percent/quality when recorded) from the sidecar, keeping `node` as-is.
    local node_obj lattice_node
    node_obj=$(json_node_obj)
    lattice_node=$(lattice_meta_node_obj "$is_conf_dir/$is_config_name")
    if [[ $lattice_node && $lattice_node != "{}" ]]; then
        printf '{"ok":true,"node":%s,"lattice_node":%s}\n' "$node_obj" "$lattice_node"
    else
        printf '{"ok":true,"node":%s}\n' "$node_obj"
    fi
    exit 0
}

json_resolve_config_file() {
    local name="$1"
    local matches=() cleaned=() f
    [[ ! $name ]] && json_err "missing_name" "line name is required" 2
    if [[ -f $is_conf_dir/$name ]]; then
        matches=("$name")
    elif [[ -f $is_conf_dir/$name.json ]]; then
        matches=("$name.json")
    elif [[ -d $is_conf_dir ]]; then
        readarray -t matches <<<"$(ls "$is_conf_dir" 2>/dev/null | grep -F -i -- "$name" | sed '/dynamic-port-.*-link/d')"
    fi
    for f in "${matches[@]}"; do
        [[ $f && $f =~ \.json$ ]] && cleaned+=("$f")
    done
    [[ ${#cleaned[@]} -eq 0 ]] && json_err "not_found" "no line matches: $name" 2
    [[ ${#cleaned[@]} -gt 1 ]] && json_err "ambiguous" "multiple lines match: $name" 2
    printf '%s' "${cleaned[0]}"
}

json_line_user_obj() {
    local raw_file="$1" payload="$2"
    jq -nc --slurpfile cfg "$raw_file" --argjson p "$payload" '
        def compact_obj:
            with_entries(select(.value != "" and .value != null and .value != [] and .value != {}));
        ($cfg[0].inbounds[0].type // "") as $type
        | if ($type == "vless" or $type == "vmess") then
            {name:($p.name // ""), uuid:($p.uuid // ""), flow:($p.flow // "")} | compact_obj
          elif ($type == "tuic") then
            {name:($p.name // ""), uuid:($p.uuid // ""), password:($p.password // "")} | compact_obj
          elif ($type == "trojan" or $type == "hysteria2" or $type == "anytls") then
            {name:($p.name // ""), password:($p.password // "")} | compact_obj
          elif ($type == "socks") then
            {name:($p.name // ""), username:($p.username // $p.email // $p.user_id // ""), password:($p.password // "")} | compact_obj
          else
            null
          end
    '
}

json_line_user_valid() {
    local user_json="$1"
    jq -e '
        type == "object" and (
            ((.uuid // "") != "") or
            ((.password // "") != "") or
            (((.username // "") != "") and ((.password // "") != ""))
        )
    ' >/dev/null <<<"$user_json"
}

json_line_user_matches_filter='
    def same_nonempty($a; $b): (($a // "") != "" and ($a // "") == ($b // ""));
    (same_nonempty(.name; $user.name)
     or same_nonempty(.uuid; $user.uuid)
     or same_nonempty(.username; $user.username)
     or same_nonempty(.password; $user.password))
'

json_write_config_atomically() {
    local raw_file="$1" filter="$2" user_json="$3"
    local tmp backup errf
    tmp=$(mktemp "${TMPDIR:-/tmp}/lattice-sb-user.XXXXXX") || json_err "tmp_failed" "cannot create temp file" 2
    backup="$raw_file.backup-$(date -u +%Y%m%d-%H%M%S)"
    errf=$(mktemp "${TMPDIR:-/tmp}/lattice-sb-check.XXXXXX") || { rm -f "$tmp"; json_err "tmp_failed" "cannot create temp file" 2; }
    cp -p "$raw_file" "$backup" || { rm -f "$tmp" "$errf"; json_err "backup_failed" "cannot backup $raw_file" 2; }
    if ! jq --argjson user "$user_json" "$filter" "$raw_file" >"$tmp"; then
        rm -f "$tmp" "$errf"
        json_err "jq_failed" "failed to update $raw_file" 2
    fi
    mv "$tmp" "$raw_file" || { rm -f "$tmp" "$errf"; json_err "write_failed" "failed to replace $raw_file" 2; }
    if ! "$is_core_bin" check -c "$raw_file" >"$errf" 2>&1; then
        mv "$backup" "$raw_file" 2>/dev/null || true
        local check_error
        check_error=$(tail -n 20 "$errf" 2>/dev/null)
        rm -f "$errf"
        jq -nc --arg error "config_invalid" --arg message "sing-box rejected updated config; rolled back" --arg detail "$check_error" \
            '{ok:false,error:$error,message:$message,detail:$detail}'
        exit 1
    fi
    rm -f "$errf"
}

# user add|del <line> <payload-json> -> mutate one inbound's user list.
cmd_json_user() {
    is_json_out=1
    local op="$1" name="$2" payload="$3"
    [[ $op == "add" || $op == "del" ]] || json_err "invalid_action" "user action must be add or del" 2
    [[ $payload ]] || json_err "missing_payload" "user payload json is required" 2
    jq -e . >/dev/null <<<"$payload" || json_err "invalid_payload" "user payload must be valid json" 2

    local config_file resolve_out resolve_rc raw_file user_json filter count_before count_after
    resolve_out=$(json_resolve_config_file "$name")
    resolve_rc=$?
    if [[ $resolve_rc != 0 ]]; then
        printf '%s\n' "$resolve_out"
        exit "$resolve_rc"
    fi
    config_file="$resolve_out"
    raw_file="$is_conf_dir/$config_file"
    [[ -f $raw_file ]] || json_err "not_found" "config file not found: $config_file" 2
    user_json=$(json_line_user_obj "$raw_file" "$payload") || json_err "payload_failed" "failed to derive sing-box user object" 2
    [[ $user_json != "null" && $user_json ]] || json_err "unsupported_protocol" "this line protocol does not support dashboard user mutation" 2
    json_line_user_valid "$user_json" || json_err "invalid_user" "payload does not contain the credential required by this line" 2

    count_before=$(jq '(.inbounds[0].users // []) | length' "$raw_file" 2>/dev/null)
    [[ $count_before =~ ^[0-9]+$ ]] || count_before=0
    if [[ $op == "add" ]]; then
        filter='
            .inbounds[0].users = (((.inbounds[0].users // []) | map(select(('"$json_line_user_matches_filter"') | not))) + [$user])
        '
    else
        filter='
            .inbounds[0].users = ((.inbounds[0].users // []) | map(select(('"$json_line_user_matches_filter"') | not)))
        '
    fi
    json_write_config_atomically "$raw_file" "$filter" "$user_json"
    count_after=$(jq '(.inbounds[0].users // []) | length' "$raw_file" 2>/dev/null)
    [[ $count_after =~ ^[0-9]+$ ]] || count_after=0
    manage restart "$is_core" >/dev/null 2>&1 || true
    jq -nc --arg action "$op" --arg line "$config_file" --argjson before "$count_before" --argjson after "$count_after" \
        '{ok:true,action:$action,line:$line,user_count_before:$before,user_count_after:$after}'
    exit 0
}

# meta --json -> regenerate the Lattice sidecar in design-15 v2 shape from on-box
# state, print it, and exit. Identity continuity: an existing v2 inbounds[].line_uuid
# or a v1 lines{}.line_id is preserved per conf file; only lines with no identity
# anywhere get a fresh uuid. The v1 keys (.node/.lines) are kept alongside the v2
# shape so pre-v2 readers (create/del/inspect) keep working unchanged. The server
# remains the authoritative writer; this is the on-box fallback/repair path.
cmd_json_meta() {
    is_json_out=1
    [[ -d $is_conf_dir ]] || json_err "not_found" "conf dir not found: $is_conf_dir" 2
    local old='{}' now tmp doc node_uuid node_id
    [[ -s $is_lattice_meta ]] && old=$(jq -c . "$is_lattice_meta" 2>/dev/null)
    [[ $old ]] || old='{}'
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    node_uuid=${LATTICE_IDENTITY_UUID:-$(jq -r '.node_uuid // .node.node_uuid // empty' <<<"$old" 2>/dev/null)}
    node_id=${LATTICE_NODE_ID:-$(jq -r '.node_id // .node.node_id // empty' <<<"$old" 2>/dev/null)}
    [[ $node_id ]] || json_err "missing_node_id" "node id unknown; set LATTICE_NODE_ID (or keep the existing sidecar)" 2

    local f tag uuid chain inbounds='[]'
    for f in "$is_conf_dir"/*.json; do
        [[ -f $f ]] || continue
        tag=$(basename "$f")
        uuid=$(jq -r --arg t "$tag" '(.inbounds // []) | map(select(.tag == $t)) | .[0].line_uuid // empty' <<<"$old" 2>/dev/null)
        [[ ! $uuid ]] && uuid=$(jq -r --arg t "$tag" '.lines[$t].line_id // empty' <<<"$old" 2>/dev/null)
        [[ ! $uuid ]] && { get_uuid; uuid=$tmp_uuid; }
        chain=$(jq -c --arg t "$tag" '(.inbounds // []) | map(select(.tag == $t)) | .[0].chain // empty' <<<"$old" 2>/dev/null)
        if [[ $chain ]]; then
            inbounds=$(jq -c --arg t "$tag" --arg u "$uuid" --argjson c "$chain" '. + [{tag:$t, line_uuid:$u, chain:$c}]' <<<"$inbounds")
        else
            inbounds=$(jq -c --arg t "$tag" --arg u "$uuid" '. + [{tag:$t, line_uuid:$u}]' <<<"$inbounds")
        fi
    done

    doc=$(jq -n \
        --arg now "$now" --arg node_uuid "$node_uuid" --arg node_id "$node_id" --argjson inbounds "$inbounds" '
        ($inbounds | map({key:.tag, value:{line_id:.line_uuid}}) | from_entries) as $v1lines
        | {
            schema:"lattice.singbox-metadata.v2",
            node_id:$node_id, updated_at:$now, writer:"sb",
            inbounds:$inbounds,
            node:{node_uuid:$node_uuid, node_id:$node_id} | with_entries(select(.value != "")),
            lines:$v1lines,
            reserved:{in_config_key:"_lattice",
              fields:{line_uuid:"string",node_uuid:"string",line_hash_id:"string"}}
          }
        | if $node_uuid != "" then .node_uuid=$node_uuid else . end')
    tmp=$(mktemp "${TMPDIR:-/tmp}/lattice-meta-v2.XXXXXX") || json_err "tmp_failed" "cannot create temp file" 2
    mkdir -p "$(dirname "$is_lattice_meta")" 2>/dev/null
    jq . <<<"$doc" >"$tmp" || { rm -f "$tmp"; json_err "jq_failed" "failed to render v2 metadata" 2; }
    mv "$tmp" "$is_lattice_meta"
    cat "$is_lattice_meta"
    exit 0
}

# Generic atomic jq edit of a sing-box config file: backup -> jq with caller
# args -> mv -> `sing-box check` with automatic rollback on rejection. Mirrors
# json_write_config_atomically but takes arbitrary jq --arg/--argjson pairs.
json_edit_config_atomically() {
    local raw_file="$1" filter="$2"
    shift 2
    local tmp backup errf
    tmp=$(mktemp "${TMPDIR:-/tmp}/lattice-sb-edit.XXXXXX") || json_err "tmp_failed" "cannot create temp file" 2
    backup="$raw_file.backup-$(date -u +%Y%m%d-%H%M%S)"
    errf=$(mktemp "${TMPDIR:-/tmp}/lattice-sb-check.XXXXXX") || { rm -f "$tmp"; json_err "tmp_failed" "cannot create temp file" 2; }
    cp -p "$raw_file" "$backup" || { rm -f "$tmp" "$errf"; json_err "backup_failed" "cannot backup $raw_file" 2; }
    if ! jq "$@" "$filter" "$raw_file" >"$tmp"; then
        rm -f "$tmp" "$errf"
        json_err "jq_failed" "failed to update $raw_file" 2
    fi
    mv "$tmp" "$raw_file" || { rm -f "$tmp" "$errf"; json_err "write_failed" "failed to replace $raw_file" 2; }
    if ! "$is_core_bin" check -c "$raw_file" >"$errf" 2>&1; then
        mv "$backup" "$raw_file" 2>/dev/null || true
        local check_error
        check_error=$(tail -n 20 "$errf" 2>/dev/null)
        rm -f "$errf"
        jq -nc --arg error "config_invalid" --arg message "sing-box rejected updated config; rolled back" --arg detail "$check_error" \
            '{ok:false,error:$error,message:$message,detail:$detail}'
        exit 1
    fi
    rm -f "$errf"
}

# stats on|off [listen] -> toggle the experimental V2Ray stats API in config.json
# (design-15 §8 / ADR-004). Loopback listens only: a stats API must never bind a
# routable address.
cmd_json_stats() {
    is_json_out=1
    local op="$1" listen="${2:-127.0.0.1:8080}"
    [[ $op == "on" || $op == "off" ]] || json_err "invalid_action" "stats action must be on or off" 2
    [[ -f $is_config_json ]] || json_err "not_found" "config.json not found: $is_config_json" 2
    if [[ $op == "on" ]]; then
        case "$listen" in
            127.* | localhost:* | \[::1\]:*) ;;
            *) json_err "invalid_listen" "stats listen must be loopback (e.g. 127.0.0.1:8080)" 2 ;;
        esac
        local port="${listen##*:}"
        [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]] || json_err "invalid_listen" "stats listen port is invalid" 2
        json_edit_config_atomically "$is_config_json" \
            '.experimental.v2ray_api = {listen:$l, stats:{enabled:true}}' --arg l "$listen"
    else
        json_edit_config_atomically "$is_config_json" \
            'del(.experimental.v2ray_api) | if (.experimental // {} | length) == 0 then del(.experimental) else . end'
    fi
    manage restart "$is_core" >/dev/null 2>&1 || true
    jq -nc --arg action "$op" --arg listen "$listen" '{ok:true,stats:$action,listen:(if $action=="on" then $listen else "" end)}'
    exit 0
}

conncheck_now_ms() {
    local now
    now=$(date +%s%3N 2>/dev/null)
    [[ $now =~ ^[0-9]+$ ]] || now=$(($(date +%s) * 1000))
    printf '%s' "$now"
}

conncheck_tail_file() {
    local file=$1
    [[ -s $file ]] || return 0
    tail -n 20 "$file" 2>/dev/null
}

conncheck_outbound_json() {
    local raw_file=$1 server=$2 server_port=$3
    jq -c --arg server "$server" --argjson server_port "$server_port" '
        def compact_obj:
            with_entries(select(.value != "" and .value != null and .value != [] and .value != {}));
        def compact_deep:
            walk(if type == "object" then compact_obj else . end);
        .inbounds[0] as $in
        | ($in.type // "") as $type
        | ([.outbounds[]? | (.tag // "") | select(startswith("public_key_")) | sub("^public_key_"; "")][0] // "") as $reality_public_key
        | ($in.tls.server_name // $in.tls.reality.handshake.server // $server) as $server_name
        | if $type == "vless" then
            if (($in.tls.reality.enabled // false) and $reality_public_key == "") then null else {
                type:"vless",
                tag:"line-check",
                server:$server,
                server_port:$server_port,
                uuid:($in.users[0].uuid // ""),
                flow:($in.users[0].flow // ""),
                tls:(if ($in.tls.enabled // false) then ({
                    enabled:true,
                    server_name:$server_name,
                    insecure:true,
                    reality:(if ($in.tls.reality.enabled // false) then {
                        enabled:true,
                        public_key:$reality_public_key,
                        short_id:(($in.tls.reality.short_id // [""])[0] // "")
                    } else null end),
                    utls:(if ($in.tls.reality.enabled // false) then {enabled:true,fingerprint:"chrome"} else null end)
                } | compact_deep) else null end)
            } | compact_deep end
        elif $type == "trojan" then {
            type:"trojan",
            tag:"line-check",
            server:$server,
            server_port:$server_port,
            password:($in.users[0].password // $in.password // ""),
            tls:(if ($in.tls.enabled // false) then {enabled:true,server_name:$server_name,insecure:true} else null end)
        } | compact_deep
        elif $type == "hysteria2" then {
            type:"hysteria2",
            tag:"line-check",
            server:$server,
            server_port:$server_port,
            password:($in.users[0].password // $in.password // ""),
            tls:{enabled:true,server_name:$server_name,insecure:true,alpn:["h3"]}
        } | compact_deep
        elif $type == "shadowsocks" then {
            type:"shadowsocks",
            tag:"line-check",
            server:$server,
            server_port:$server_port,
            method:($in.method // ""),
            password:($in.password // "")
        } | compact_deep
        elif $type == "anytls" then {
            type:"anytls",
            tag:"line-check",
            server:$server,
            server_port:$server_port,
            password:($in.users[0].password // $in.password // ""),
            tls:{enabled:true,server_name:$server_name,insecure:true}
        } | compact_deep
        elif $type == "socks" then {
            type:"socks",
            tag:"line-check",
            server:$server,
            server_port:$server_port,
            username:($in.users[0].username // ""),
            password:($in.users[0].password // "")
        } | compact_deep
        else null end
    ' "$raw_file"
}

# conncheck <name> [url] [timeout_sec] -> run a temporary local sing-box client
# for one line and curl the URL through it. The temporary config is deleted and
# never printed because it contains credential material derived from the line.
cmd_json_conncheck() {
    is_json_out=1
    local name="$1" url="$2" timeout_sec="$3"
    [[ ! $name ]] && json_err "missing_name" "conncheck --json requires a line name" 2
    [[ ! $url ]] && url="https://www.cloudflare.com/cdn-cgi/trace"
    [[ ${#url} -le 2048 && $url != *[[:space:]]* && ( $url == http://* || $url == https://* ) ]] || json_err "invalid_url" "conncheck url must be http(s)" 2
    [[ $timeout_sec ]] || timeout_sec=10
    [[ $timeout_sec =~ ^[0-9]+$ && $timeout_sec -ge 2 && $timeout_sec -le 60 ]] || json_err "invalid_timeout" "timeout_sec must be 2-60" 2

    local matches=() cleaned=() f
    if [[ -f $is_conf_dir/$name ]]; then
        matches=("$name")
    elif [[ -f $is_conf_dir/$name.json ]]; then
        matches=("$name.json")
    elif [[ -d $is_conf_dir ]]; then
        readarray -t matches <<<"$(ls "$is_conf_dir" 2>/dev/null | grep -F -i -- "$name" | sed '/dynamic-port-.*-link/d')"
    fi
    for f in "${matches[@]}"; do
        [[ $f && $f =~ \.json$ ]] && cleaned+=("$f")
    done
    [[ ${#cleaned[@]} -eq 0 ]] && json_err "not_found" "no line matches: $name" 2
    [[ ${#cleaned[@]} -gt 1 ]] && json_err "ambiguous" "multiple lines match: $name" 2

    is_config_file="${cleaned[0]}"
    is_dont_show_info=1
    is_dont_test_host=1
    info "$is_config_file" >/dev/null 2>&1

    local raw_file=$is_conf_dir/$is_config_file
    [[ -f $raw_file ]] || json_err "not_found" "config file not found: $is_config_file" 2
    local server=$is_addr
    [[ $host ]] && server=$host
    [[ $is_anytls_domain ]] && server=$is_anytls_domain
    [[ $server ]] || json_err "missing_server" "cannot determine server address for $is_config_file" 2
    local server_port=$port
    [[ $host && $is_https_port ]] && server_port=$is_https_port
    [[ $server_port =~ ^[0-9]+$ && $server_port -ge 1 && $server_port -le 65535 ]] || json_err "invalid_port" "cannot determine server port for $is_config_file" 2

    local outbound
    outbound=$(conncheck_outbound_json "$raw_file" "$server" "$server_port") || json_err "outbound_build_failed" "failed to build conncheck outbound" 2
    [[ $outbound != "null" && $outbound != "" ]] || json_err "unsupported_protocol" "conncheck does not support this line protocol yet" 2

    local old_port=$port
    port=$server_port
    get_port
    local listen_port=$tmp_port
    port=$old_port

    local tmpdir config core_log curl_err body http_code start_ms end_ms latency_ms pid ok=false
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/lattice-conncheck.XXXXXX") || json_err "tmpdir_failed" "cannot create temporary directory" 2
    config=$tmpdir/config.json
    core_log=$tmpdir/sing-box.log
    curl_err=$tmpdir/curl.err
    body=$tmpdir/body.out
    jq -n --argjson listen_port "$listen_port" --argjson outbound "$outbound" '{
        log:{level:"error"},
        inbounds:[{type:"mixed",tag:"probe-in",listen:"127.0.0.1",listen_port:$listen_port}],
        outbounds:[$outbound]
    }' >"$config" || { rm -rf "$tmpdir"; json_err "config_failed" "failed to write temporary conncheck config" 2; }

    "$is_core_bin" run -c "$config" >"$core_log" 2>&1 &
    pid=$!
    trap 'kill "$pid" 2>/dev/null || true; rm -rf "$tmpdir"' EXIT

    start_ms=$(conncheck_now_ms)
    local attempt
    for attempt in $(seq 1 30); do
        if http_code=$(curl -fsS --proxy "socks5h://127.0.0.1:$listen_port" --connect-timeout 3 --max-time "$timeout_sec" -o "$body" -w '%{http_code}' "$url" 2>"$curl_err"); then
            ok=true
            break
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.2
    done
    end_ms=$(conncheck_now_ms)
    latency_ms=$((end_ms - start_ms))
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    trap - EXIT

    if [[ $ok == true ]]; then
        jq -nc \
            --arg line "$is_config_file" \
            --arg url "$url" \
            --arg server "$server" \
            --argjson server_port "$server_port" \
            --argjson listen_port "$listen_port" \
            --arg http_code "$http_code" \
            --argjson latency_ms "$latency_ms" \
            '{ok:true,line:$line,url:$url,server:$server,server_port:$server_port,local_proxy_port:$listen_port,http_code:$http_code,latency_ms:$latency_ms}'
        rm -rf "$tmpdir"
        exit 0
    fi

    local curl_message core_tail
    curl_message=$(cat "$curl_err" 2>/dev/null)
    core_tail=$(conncheck_tail_file "$core_log")
    jq -nc \
        --arg line "$is_config_file" \
        --arg url "$url" \
        --arg server "$server" \
        --argjson server_port "$server_port" \
        --argjson listen_port "$listen_port" \
        --argjson latency_ms "$latency_ms" \
        --arg curl_error "$curl_message" \
        --arg core_log_tail "$core_tail" \
        '{ok:false,error:"conncheck_failed",line:$line,url:$url,server:$server,server_port:$server_port,local_proxy_port:$listen_port,latency_ms:$latency_ms,curl_error:$curl_error,core_log_tail:$core_log_tail}'
    rm -rf "$tmpdir"
    exit 1
}

# sub -> {ok,count,plain,base64}  aggregate every node's share link (the missing aggregator)
cmd_json_sub() {
    is_json_out=1
    local files=() urls=() f u
    [[ -d $is_conf_dir ]] && readarray -t files <<<"$(ls "$is_conf_dir" 2>/dev/null | grep -E -i '\.json$' | sed '/dynamic-port-.*-link/d')"
    for f in "${files[@]}"; do
        [[ ! $f ]] && continue
        u="$(is_dont_show_info=1; is_dont_test_host=1; info "$f" >/dev/null 2>&1; printf '%s' "$is_url")"
        [[ $u ]] && urls+=("$u")
    done
    local plain="" b64=""
    if [[ ${#urls[@]} -gt 0 ]]; then
        plain="$(printf '%s\n' "${urls[@]}")"
        b64="$(printf '%s\n' "${urls[@]}" | base64 | tr -d '\n')"
    fi
    jq -nc --arg plain "$plain" --arg b64 "$b64" --argjson count "${#urls[@]}" \
        '{ok:true,count:$count,plain:$plain,base64:$b64}'
    exit 0
}

# provision --json -> {ok,installed,version,service_active}  (status probe; fresh install = install.sh)
cmd_json_provision() {
    is_json_out=1
    local installed=false version="" active=false
    [[ -x $is_core_bin ]] && {
        installed=true
        version="$($is_core_bin version 2>/dev/null | head -1 | awk '{print $NF}')"
    }
    if [[ $is_systemd ]]; then
        systemctl is-active --quiet "$is_core" 2>/dev/null && active=true
    elif [[ $is_openrc ]]; then
        rc-service "$is_core" status &>/dev/null && active=true
    fi
    jq -nc --argjson installed "$installed" --arg version "$version" --argjson active "$active" \
        '{ok:true,installed:$installed,version:$version,service_active:$active}'
    exit 0
}

# backup [--json] -> archive the sing-box config DATA (config.json + conf/, incl.
# per-node .json and .addr sidecars, plus the Lattice lattice-metadata.json
# identity sidecar) to /opt/lattice/.archive_backup/ as a
# timestamped tarball. Works on any install — including nodes deployed by hand or
# by the interactive script flow — because it archives whatever is on disk.
cmd_backup() {
    local dir=/opt/lattice/.archive_backup
    local items=()
    [[ -f $is_config_json ]] && items+=(config.json)
    [[ -d $is_conf_dir ]] && items+=(conf)
    # Lattice node/line identity sidecar (design-09 §E.2), if present.
    [[ -f $is_lattice_meta ]] && items+=(lattice-metadata.json)
    if [[ ${#items[@]} -eq 0 ]]; then
        [[ $is_json_out ]] && json_err "nothing_to_backup" "no sing-box config data under $is_core_dir" 2
        err "没有可备份的 $is_core_name 数据 ($is_core_dir)"
    fi
    mkdir -p "$dir" 2>/dev/null || {
        [[ $is_json_out ]] && json_err "backup_dir" "cannot create $dir" 2
        err "无法创建备份目录: $dir"
    }
    local ts archive
    ts=$(date -u +%Y%m%d-%H%M%S)
    archive="$dir/sing-box-$ts.tar.gz"
    if ! tar -C "$is_core_dir" -czf "$archive" "${items[@]}" 2>/dev/null; then
        [[ $is_json_out ]] && json_err "backup_failed" "tar failed writing $archive" 2
        err "备份失败: $archive"
    fi
    local n bytes
    n=$(ls "$is_conf_dir" 2>/dev/null | grep -E -ic '\.json$')
    bytes=$(wc -c <"$archive" 2>/dev/null | tr -d ' ')
    [[ $bytes ]] || bytes=0
    if [[ $is_json_out ]]; then
        jq -nc --arg archive "$archive" --argjson bytes "$bytes" --argjson nodes "${n:-0}" \
            '{ok:true,archive:$archive,bytes:$bytes,nodes:$nodes}'
    else
        _green "\n备份完成: $archive ($bytes bytes, $n 个节点)\n"
    fi
    exit 0
}

# update core, sh, caddy
update() {
    case $1 in
    1 | core | $is_core)
        is_update_name=core
        is_show_name=$is_core_name
        is_run_ver=v${is_core_ver##* }
        is_update_repo=$is_core_repo
        ;;
    2 | sh)
        is_update_name=sh
        is_show_name="$is_core_name 脚本"
        is_run_ver=$is_sh_ver
        is_update_repo=$is_sh_repo
        ;;
    3 | caddy)
        [[ ! $is_caddy ]] && err "不支持更新 Caddy."
        is_update_name=caddy
        is_show_name="Caddy"
        is_run_ver=$is_caddy_ver
        is_update_repo=$is_caddy_repo
        ;;
    *)
        err "无法识别 ($1), 请使用: $is_core update [core | sh | caddy] [ver]"
        ;;
    esac
    [[ $2 ]] && is_new_ver=v${2#v}
    [[ $is_run_ver == $is_new_ver ]] && {
        msg "\n自定义版本和当前 $is_show_name 版本一样, 无需更新.\n"
        exit
    }
    load download.sh
    if [[ $is_new_ver ]]; then
        msg "\n使用自定义版本更新 $is_show_name: $(_green $is_new_ver)\n"
    else
        get_latest_version $is_update_name
        [[ $is_run_ver == $latest_ver ]] && {
            msg "\n$is_show_name 当前已经是最新版本了.\n"
            exit
        }
        msg "\n发现 $is_show_name 新版本: $(_green $latest_ver)\n"
        is_new_ver=$latest_ver
    fi
    download $is_update_name $is_new_ver
    msg "更新成功, 当前 $is_show_name 版本: $(_green $is_new_ver)\n"
    msg "$(_green 请查看更新说明: https://github.com/$is_update_repo/releases/tag/$is_new_ver)\n"
    [[ $is_update_name != 'sh' ]] && manage restart $is_update_name &
}

pass_args() {
    is_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
        -A | --server-addr | --addr)
            [[ -z $2 ]] && {
                err "($1) 缺少必需参数, 正确使用示例: [$is_core --addr 1.2.3.4 add reality or $is_core --addr example.com]"
            }
            server_addr=$(normalize_addr "$2")
            [[ $(is_test addr "$server_addr") ]] || err "($server_addr) 不是一个有效的 IP 或域名."
            is_custom_addr=$server_addr
            shift 2
            ;;
        --json)
            is_json_out=1
            shift
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                is_args+=("$1")
                shift
            done
            ;;
        *)
            is_args+=("$1")
            shift
            ;;
        esac
    done
}

# main menu; if no prefer args.
is_main_menu() {
    msg "\n------------- $is_core_name script $is_sh_ver by ${display_author:-$author} -------------"
    msg "$is_core_name $is_core_ver: $is_core_status"
    msg "项目(Project): $(msg_ul ${is_project_url:-https://github.com/${is_sh_repo}})"
    is_main_start=1
    ask mainmenu
    case $REPLY in
    1)
        add
        ;;
    2)
        change
        ;;
    3)
        info
        ;;
    4)
        del
        ;;
    5)
        ask list is_do_manage "启动 停止 重启"
        manage $REPLY &
        msg "\n管理状态执行: $(_green $is_do_manage)\n"
        ;;
    6)
        is_tmp_list=("更新$is_core_name" "更新脚本")
        [[ $is_caddy ]] && is_tmp_list+=("更新Caddy")
        ask list is_do_update null "\n请选择更新:\n"
        update $REPLY
        ;;
    7)
        uninstall
        ;;
    8)
        msg
        load help.sh
        show_help
        ;;
    9)
        ask list is_do_other "启用BBR 查看日志 测试运行 重装脚本 设置DNS"
        case $REPLY in
        1)
            load bbr.sh
            _try_enable_bbr
            ;;
        2)
            load log.sh
            log_set
            ;;
        3)
            get test-run
            ;;
        4)
            get reinstall
            ;;
        5)
            load dns.sh
            dns_set
            ;;
        esac
        ;;
    10)
        load help.sh
        about
        ;;
    esac
}

# check prefer args, if not exist prefer args and show main menu
main() {
    [[ $# -gt 0 ]] && {
        pass_args "$@"
        set -- "${is_args[@]}"
    }
    [[ ! $1 ]] && set -- main
    case $1 in
    list | ls)
        cmd_json_list "$2"
        ;;
    sub)
        cmd_json_sub
        ;;
    provision)
        cmd_json_provision
        ;;
    backup)
        cmd_backup
        ;;
    inspect)
        cmd_json_inspect "$2"
        ;;
    conncheck)
        cmd_json_conncheck "$2" "$3" "$4"
        ;;
    user)
        cmd_json_user "$2" "$3" "$4"
        ;;
    meta)
        cmd_json_meta
        ;;
    stats)
        cmd_json_stats "$2" "$3"
        ;;
    a | add | gen | no-auto-tls)
        [[ $1 == 'gen' ]] && is_gen=1
        [[ $1 == 'no-auto-tls' ]] && is_no_auto_tls=1
        [[ $is_json_out && ! $is_gen ]] && { is_dont_show_info=1; is_dont_test_host=1; }
        add ${@:2}
        [[ $is_json_out && ! $is_gen ]] && { wait 2>/dev/null; printf '{"ok":true,"node":%s}\n' "$(json_node_obj)"; exit 0; }
        ;;
    bin | pbk | check | completion | format | generate | geoip | geosite | merge | rule-set | run | tools)
        is_run_command=$1
        if [[ $1 == 'bin' ]]; then
            $is_core_bin ${@:2}
        else
            [[ $is_run_command == 'pbk' ]] && is_run_command="generate reality-keypair"
            $is_core_bin $is_run_command ${@:2}
        fi
        ;;
    bbr)
        load bbr.sh
        _try_enable_bbr
        ;;
    c | config | change)
        [[ $is_json_out ]] && { is_dont_show_info=1; is_dont_test_host=1; }
        change ${@:2}
        [[ $is_json_out ]] && { wait 2>/dev/null; printf '{"ok":true,"node":%s}\n' "$(json_node_obj)"; exit 0; }
        ;;
    # client | genc)
    #     create client $2
    #     ;;
    d | del | rm)
        [[ $is_json_out ]] && {
            is_no_del_msg=1
            del $2
            wait 2>/dev/null
            printf '{"ok":true,"deleted":"%s"}\n' "$is_config_file"
            exit 0
        }
        del $2
        ;;
    dd | ddel | fix | fix-all)
        case $1 in
        fix)
            [[ $2 ]] && {
                change $2 full
            } || {
                is_change_id=full && change
            }
            return
            ;;
        fix-all)
            is_dont_auto_exit=1
            msg
            for v in $(ls $is_conf_dir | grep .json$ | sed '/dynamic-port-.*-link/d'); do
                msg "fix: $v"
                change $v full
            done
            _green "\nfix 完成.\n"
            ;;
        *)
            is_dont_auto_exit=1
            [[ ! $2 ]] && {
                err "无法找到需要删除的参数"
            } || {
                for v in ${@:2}; do
                    del $v
                done
            }
            ;;
        esac
        is_dont_auto_exit=
        manage restart &
        [[ $is_del_host ]] && manage restart caddy &
        ;;
    dns)
        load dns.sh
        dns_set ${@:2}
        ;;
    debug)
        is_debug=1
        get info $2
        warn "如果需要复制; 请把 *uuid, *password, *host, *key 的值改写, 以避免泄露."
        ;;
    fix-config.json)
        create config.json
        ;;
    fix-caddyfile)
        if [[ $is_caddy ]]; then
            load caddy.sh
            caddy_config new
            manage restart caddy &
            _green "\nfix 完成.\n"
        else
            err "无法执行此操作"
        fi
        ;;
    i | info)
        [[ $is_json_out ]] && cmd_json_info "$2"
        info $2
        ;;
    ip)
        get_ip
        msg $ip
        ;;
    in | import)
        load import.sh
        ;;
    log)
        load log.sh
        log_set $2
        ;;
    url | qr)
        url_qr $@
        ;;
    un | uninstall)
        uninstall
        ;;
    u | up | update | U | update.sh)
        is_update_name=$2
        is_update_ver=$3
        [[ ! $is_update_name ]] && is_update_name=core
        [[ $1 == 'U' || $1 == 'update.sh' ]] && {
            is_update_name=sh
            is_update_ver=
        }
        update $is_update_name $is_update_ver
        ;;
    ssss | ss2022)
        get $@
        ;;
    s | status)
        msg "\n$is_core_name $is_core_ver: $is_core_status\n"
        [[ $is_caddy ]] && msg "Caddy $is_caddy_ver: $is_caddy_status\n"
        ;;
    start | stop | r | restart)
        [[ $2 && $2 != 'caddy' ]] && err "无法识别 ($2), 请使用: $is_core $1 [caddy]"
        manage $1 $2 &
        ;;
    t | test)
        get test-run
        ;;
    reinstall)
        get $1
        ;;
    get-port)
        get_port
        msg $tmp_port
        ;;
    main)
        is_main_menu
        ;;
    v | ver | version)
        [[ $is_caddy_ver ]] && is_caddy_ver="/ $(_blue Caddy $is_caddy_ver)"
        msg "\n$(_green $is_core_name $is_core_ver) / $(_cyan $is_core_name script $is_sh_ver) $is_caddy_ver\n"
        ;;
    h | help | --help)
        load help.sh
        show_help ${@:2}
        ;;
    *)
        is_try_change=1
        change test $1
        if [[ $is_change_id ]]; then
            unset is_try_change
            [[ $2 ]] && {
                change $2 $1 ${@:3}
            } || {
                change
            }
        else
            err "无法识别 ($1), 获取帮助请使用: $is_core help"
        fi
        ;;
    esac
}
