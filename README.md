# sing-box 自用一键脚本

这是我维护的 `sing-box` 安装与管理脚本。仓库从
[233boy/sing-box](https://github.com/233boy/sing-box) fork 而来，感谢原项目提供的一键安装、协议生成、Caddy 自动 TLS 和日常管理的基础能力。

本 fork 面向我自己的服务器和自动化部署流程维护。后续文档、安装源、Release 和问题反馈都以
[lr00rl/sing-box](https://github.com/lr00rl/sing-box) 为准。

> 这不是 SagerNet/sing-box 官方项目。`sing-box` core 来自
> [SagerNet/sing-box](https://github.com/SagerNet/sing-box)，本仓库只维护安装和管理脚本。

## 主要改动

- 发布源切换到 `lr00rl/sing-box`，脚本更新从本仓库 Release 下载 `code.tar.gz`。
- 安装阶段支持 `--server-addr` / `--addr` 手动指定连接地址，避免自动获取公网 IP 失败或拿到错误地址。
- 支持 `-p` / `--proxy` 代理下载安装资源；公网 IP 探测会绕过代理直连，避免拿到代理出口 IP。
- 运行时支持 `sb --addr <ip|domain> ...` 临时覆盖连接地址，并为配置保存 `.addr` sidecar。
- 增加面向 Lattice / Probe-Dashboards 使用的 JSON 自动化接口，例如 `list`、`inspect`、`info --json`、`sub`、`provision`、`backup --json`。
- 增加配置备份：`sb backup` 会归档 `/etc/sing-box/config.json` 和 `/etc/sing-box/conf/` 到 `/opt/lattice/.archive_backup/`。
- 去掉脚本帮助、页脚、分享链接标签里的上游展示信息；只在 README 和 `about` 中保留 fork 来源与致谢。

## 功能范围

脚本会安装 `sing-box` core，并提供 `/usr/local/bin/sing-box` 和 `/usr/local/bin/sb` 两个命令入口。默认首次安装会创建一个 VLESS-REALITY 配置。

支持的常用协议包括：

- VLESS-REALITY / VLESS-HTTP2-REALITY
- AnyTLS
- TUIC
- Trojan
- Hysteria2
- Shadowsocks / Shadowsocks 2022
- VMess TCP / HTTP / QUIC / WS / H2 / HTTPUpgrade
- VMess / VLESS / Trojan 的 WS/H2/HTTPUpgrade + TLS
- Socks

支持的管理能力包括：

- 添加、修改、删除、查看节点配置
- 输出分享 URL 或二维码
- 自动配置 Caddy TLS
- 更新 `sing-box` core、脚本和 Caddy
- 启用 BBR
- DNS、日志、服务启停、配置修复
- JSON 输出，便于被控制面或自动化脚本调用

## 系统要求

- root 用户
- 64 位 Linux：`amd64/x86_64` 或 `arm64/aarch64`
- 包管理器：`apt-get`、`yum`、`zypper` 或 `apk`
- 服务管理：systemd 或 OpenRC
- 可访问 GitHub Release；网络受限时建议使用代理安装

## 快速安装

远程安装必须使用 raw 地址，不要使用 GitHub 的 `blob` 页面地址。

```bash
bash <(curl -fsSL https://github.com/lr00rl/sing-box/raw/main/install.sh)
```

如果自动获取服务器公网 IP 失败，或你希望客户端连接到指定 IP/域名：

```bash
bash <(curl -fsSL https://github.com/lr00rl/sing-box/raw/main/install.sh) --server-addr 1.2.3.4
bash <(curl -fsSL https://github.com/lr00rl/sing-box/raw/main/install.sh) --server-addr example.com
```

如果机器上已经安装过 233boy/sing-box 或本 fork 的旧版本，直接执行上面的安装命令会自动进入脚本层迁移模式：只替换 `/etc/sing-box/sh` 管理脚本和 `/usr/local/bin/sing-box`、`/usr/local/bin/sb` 链接，保留已有 core、`config.json`、`conf/`、日志和服务。

也可以指定 `sing-box` core 版本或本地 core 包：

```bash
bash <(curl -fsSL https://github.com/lr00rl/sing-box/raw/main/install.sh) --core-version v1.12.0
bash install.sh --core-file /root/sing-box-linux-amd64.tar.gz
```

## 代理安装

`install.sh` 的 `-p` / `--proxy` 只用于下载脚本包、core、jq 等资源。脚本探测服务器公网 IP 时会直连，避免把代理出口当成节点地址。

首次拉取安装脚本本身也需要走代理时，用下面的写法：

```bash
PROXY='socks5h://USER:PASS@HOST:PORT'

export http_proxy="$PROXY"
export https_proxy="$PROXY"
export all_proxy="$PROXY"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export ALL_PROXY="$PROXY"

bash <(curl -fsSL --proxy "$PROXY" \
  https://github.com/lr00rl/sing-box/raw/main/install.sh) \
  --proxy "$PROXY"
```

代理安装并同时指定连接地址：

```bash
bash <(curl -fsSL --proxy "$PROXY" \
  https://github.com/lr00rl/sing-box/raw/main/install.sh) \
  --proxy "$PROXY" --server-addr example.com
```

## 本地安装

如果 Release 中暂时没有 `code.tar.gz`，远程安装会在下载脚本包时失败。可以先下载源码，再使用本地模式安装：

```bash
git clone https://github.com/lr00rl/sing-box.git
cd sing-box
bash install.sh --local-install
```

本地模式也支持指定连接地址：

```bash
bash install.sh --local-install --server-addr example.com
```

只重装或迁移管理脚本：

```bash
bash <(curl -fsSL https://github.com/lr00rl/sing-box/raw/main/install.sh) --script-only
```

## 常用命令

安装完成后优先使用 `sb`，也可以使用完整命令 `sing-box`。

```bash
sb help
sb status
sb version
sb info
sb url
sb qr
```

添加配置：

```bash
sb add reality
sb add reality 40572
sb add reality 40572 auto www.microsoft.com
sb add anytls
sb add anytls 8443 auto example.com
sb add tuic
sb add trojan
sb add hy2
sb add ss
sb add socks
```

修改和删除配置：

```bash
sb change <name>
sb addr <name> example.com
sb port <name> 443
sb sni <name> www.microsoft.com
sb del <name>
```

`del` / `ddel` 会直接删除配置，不会再次确认，执行前确认参数。

运行管理：

```bash
sb status
sb start
sb stop
sb restart
sb log
sb test
```

更新：

```bash
sb update core
sb update sh
sb update caddy
sb update core v1.12.0
```

重装管理脚本：

```bash
sb reinstall
```

`sb reinstall` 只刷新 `/etc/sing-box/sh`，不会删除已有节点配置。如果需要完整卸载，使用 `sb uninstall`。

卸载：

```bash
sb uninstall
```

## 连接地址

脚本会自动探测服务器公网 IP。以下情况建议手动指定连接地址：

- 服务器只有内网 IP，但对外通过公网 IP、DDNS 或域名访问。
- 自动探测公网 IP 失败。
- 安装时使用代理，但客户端应该连接服务器本机地址而不是代理出口。
- 同一台机器上的不同配置需要展示不同连接地址。

安装阶段：

```bash
bash install.sh --server-addr 1.2.3.4
bash install.sh --server-addr example.com
```

运行阶段：

```bash
sb --addr 1.2.3.4 add reality 40572
sb --addr example.com add tuic
```

为单个配置修改连接地址：

```bash
sb addr <name> 1.2.3.4
sb addr <name> example.com
sb addr <name> auto
```

指定的地址会保存到对应配置的 `.addr` sidecar；使用 `auto` 会回到自动探测。

## JSON 自动化接口

这些命令用于控制面、脚本或自动化系统读取状态，输出结构化 JSON。

```bash
sb list
sb list reality
sb inspect --json
sb inspect <name> --json
sb --json info <name>
sb sub
sb provision
sb --json backup
```

添加、修改、删除也可以配合 `--json`：

```bash
sb --addr example.com --json add reality 40572
sb --json change <name> port 443
sb --json del <name>
```

常见返回：

- `list`：`{ok,count,nodes:[...]}`
- `inspect --json`：`{ok,count,lines:[...]}`
- `inspect <name> --json`：`{ok,line:{core,tag,type,listen_host,listen_port,users,outbound,domain,metadata}}`
- `info --json`：`{ok,node:{...}}`；当 sidecar 记录了节点身份时，附带 `lattice_node:{node_uuid,node_id,purity_percent,quality}`
- `sub`：`{ok,count,plain,base64}`
- `provision`：`{ok,installed,version,service_active}`
- `backup --json`：`{ok,archive,bytes,nodes}`

在 `--json` 模式下，如果命令需要交互输入但参数不完整，脚本会返回结构化错误，而不是进入 TTY 提问。

### 线路用户（`user`）

控制面通过这组命令增删、暂停和恢复某条线路上的单个用户。`<json>` 的字段按线路协议取用：
vless/vmess 取 `name`、`uuid`、`flow`，tuic 取 `name`、`uuid`、`password`，trojan/hysteria2/anytls
取 `name`、`password`，socks 取 `username`、`password`（socks 用户没有 `name` 字段，core 会拒绝它，
所以 `name` 会被当作 `username` 写入）。

```bash
sb --json user add <line> '{"name":"u_0123456789abcdef","uuid":"..."}'
sb --json user del <line> '{"name":"u_0123456789abcdef","uuid":"..."}'
sb --json user del <line> '{"name":"u_0123456789abcdef"}'
sb --json user park <line> '[{"name":"u_0123456789abcdef"},{"name":"u_fedcba9876543210"}]'
sb --json user unpark <line> '{"name":"u_0123456789abcdef"}'
sb --json user parked [line]
sb --json caps
```

- `add` 先替换所有与 payload 任一字段（name、uuid、username、password）相同的条目，再追加这个用户。
  带凭据的 `del` 删除所有这样的条目。两者都返回 `user_count_before`、`user_count_after` 和 `matched`
  （命中的条目数），`matched` 大于 1 说明这次调用动到了别人的条目。
  带凭据的 `del` 即使同时给了名字也这样匹配，因为它是撤销：与这个用户共用 uuid 或密码的条目用的是同一个凭据，
  留下它就等于没撤销。
- `del` 也可以只给用户名：只按名字匹配，名字对应多个条目时拒绝（`ambiguous_user`），不猜。
  线路上没有这个名字时什么也不改，也不重启。共用凭据的手工条目会留下，那个凭据也就仍能通过它连上；
  要保留这类条目时用它，要彻底撤销凭据时用带凭据的 `del`。
- `park` 把用户对象原样从 `conf/<line>` 移到 `lattice-parked/<line>`，凭据不丢；`unpark` 原样移回。
  有用户名时只按用户名匹配，否则按凭据匹配，每个选择器最多命中一个条目。一次可传一个数组，整批只重启一次。
  重复暂停或恢复不报错，结果里写明 `already_parked`、`already_active` 或 `absent`；什么都没变时不重启。
  暂停副本与线路上同名条目不一致时报 `conflict`，由人处理。
- 删除用户（按名字或按凭据）会一并删掉它的暂停副本，避免已撤销的用户被 `unpark` 带回来；
  `add` 会丢弃同名的暂停副本。暂停副本删不掉时（例如磁盘写满），`del` 照样先从线路上撤销并重启，
  但返回 `ok:false`、`error:"parked_stale"`、退出码 1，调用方应当重试，重试会补删暂停副本。
  `add` 遇到同样情况仍然成功，只带 `parked_stale:true`：留下的是这个用户的旧凭据，`unpark` 会以 `conflict` 拒绝它。
- socks、http、mixed 线路没有用户时，上游 sing-box 不做任何认证，谁都能用。`del` 和 `park`
  拒绝删掉或暂停这类线路的最后一个用户（`last_user_open_proxy`）。
- `user parked` 和 `list` 的线路 metadata（`parked_users`、`parked_names`，均为字符串）报告暂停中的用户。
  `user parked` 不带线路时列出所有有暂停用户的线路；带线路时总是返回那一条，没有暂停用户就报 0。
  只列出 Lattice 自己的 `u_<16 位十六进制>` 名字，其他用户只计数；凭据从不输出。
- `add`、`del`、`park`、`unpark` 在一台节点上一次只跑一个：先用 flock(1) 拿到
  `/etc/sing-box/lattice-user.lock`，最多等 20 秒，拿不到就报 `busy`（退出码 2），什么都不读也不改。
  只用 `flock -n` 轮询，所以 util-linux 和 busybox（Alpine）的 flock 都能用；busybox 的 flock 没有 `-w`。
  锁挂在打开的文件描述符上，调用退出或被杀时由内核释放，不会留下死锁；重启 core 时不把这个描述符交给子进程。
  节点上没有 flock 时照旧不加锁运行，`caps` 也不列出 `user-lock`，这时控制面要自己把对这台节点的调用错开。
- `caps` 返回 `{ok,script,caps:[...]}`。旧脚本没有这个命令，会以 `ok:false` 回答，即不具备这些能力。

### Lattice 身份元数据 sidecar

节点与线路身份（`node_uuid`、`node_id`、每条线路的 `line_id` 等）保存在
**`/etc/sing-box/lattice-metadata.json`** 这个 sidecar 文件里，**不再写入** `conf/*.json`
配置文件。原因：sing-box 会以 `DisallowUnknownFields` 严格解析 `config.json`（`-c`）
以及每个 `conf/*.json`（`-C`），任何未知字段（例如旧版的 `_lattice`）都会导致
`sing-box check` / 服务启动 **直接失败** 并使节点崩溃重启；因此身份数据必须放在
服务永远不会读取的 `conf/` 之外。

sidecar 结构：

```json
{
  "version": 1,
  "node": { "node_uuid": "...", "node_id": "...", "purity_percent": 98, "quality": "high" },
  "lines": { "<conf-filename>.json": { "line_id": "<uuid>" } }
}
```

`add` / `create` 时通过以下环境变量写入 sidecar（供 Lattice 自动化部署使用）：

- `LATTICE_IDENTITY_UUID`：节点身份 UUID，设置后才会写入 sidecar 元数据。
- `LATTICE_NODE_ID`：节点 ID。
- `LATTICE_LINE_ID`：手动指定线路 ID；默认自动生成，且在改端口/协议、重建配置等
  操作后 **保持不变**（`line_id` 跟随线路，按配置文件名迁移）。
- `LATTICE_NODE_PURITY`：节点纯净度，0-100 的整数；非法值只会告警并跳过，不会中断创建。
- `LATTICE_NODE_QUALITY`：节点质量等级（短字符串）。

`list` / `inspect` / `info --json` 的输出形态保持不变：读取路径优先取 sidecar，
并对仍携带旧版 `_lattice` 配置的节点自动回退读取以完成迁移，因此
`metadata.{line_id,node_uuid,node_id}` 等对外字段与之前完全一致。删除线路会同时清理
其 sidecar 条目；`sb backup` 也会一并归档 `lattice-metadata.json`。

## 文件位置

- 脚本目录：`/etc/sing-box/sh`
- core：`/etc/sing-box/bin/sing-box`
- 主配置：`/etc/sing-box/config.json`
- 节点配置：`/etc/sing-box/conf/*.json`
- 节点连接地址 sidecar：`/etc/sing-box/conf/*.addr`
- Lattice 身份元数据 sidecar：`/etc/sing-box/lattice-metadata.json`（在 `conf/` 之外，服务不解析）
- 暂停中的线路用户：`/etc/sing-box/lattice-parked/<line>.json`（在 `conf/` 之外；目录 0700，文件 0600；`sb backup` 一并归档）
- 线路用户锁：`/etc/sing-box/lattice-user.lock`（空文件，只供 flock 使用）
- 日志目录：`/var/log/sing-box`
- 命令入口：`/usr/local/bin/sing-box`、`/usr/local/bin/sb`
- 备份目录：`/opt/lattice/.archive_backup/`

出于兼容已安装节点的考虑，部分内部路径仍保留上游脚本的历史命名空间，例如 Caddy 配置目录可能继续使用旧路径。这个兼容细节不影响对外展示、安装源或使用方式。

## 发布与维护

- 脚本版本写在 `sing-box.sh` 的 `is_sh_ver`。
- GitHub Actions 会在 `main` 分支 push 后读取 `is_sh_ver`，但只接受明确的
  `alpha` / `beta` / `rc` 版本，并把 Release 标记为 prerelease、非 Latest。
- 稳定版本必须经过单独的人工发布决策；不能由普通 `main` 推送自动生成。
- Release 资产 `code.tar.gz` 是远程安装和 `sb update sh` 使用的脚本包。
- 如果修改脚本逻辑并希望已安装机器检测到更新，需要同步提升 `is_sh_ver`。
- 安装脚本里的 `is_sh_repo` 指向 `lr00rl/sing-box`。
- 远程安装脚本检测到已有安装时，会默认只替换管理脚本层，方便从上游脚本迁移到本 fork。

## 反馈

问题反馈到本仓库：

https://github.com/lr00rl/sing-box/issues

上游脚本来源：

https://github.com/233boy/sing-box
