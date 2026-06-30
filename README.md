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
- 增加面向 Lattice / Probe-Dashboards 使用的 JSON 自动化接口，例如 `list`、`info --json`、`sub`、`provision`、`backup --json`。
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
- `info --json`：`{ok,node:{...}}`
- `sub`：`{ok,count,plain,base64}`
- `provision`：`{ok,installed,version,service_active}`
- `backup --json`：`{ok,archive,bytes,nodes}`

在 `--json` 模式下，如果命令需要交互输入但参数不完整，脚本会返回结构化错误，而不是进入 TTY 提问。

## 文件位置

- 脚本目录：`/etc/sing-box/sh`
- core：`/etc/sing-box/bin/sing-box`
- 主配置：`/etc/sing-box/config.json`
- 节点配置：`/etc/sing-box/conf/*.json`
- 节点连接地址 sidecar：`/etc/sing-box/conf/*.addr`
- 日志目录：`/var/log/sing-box`
- 命令入口：`/usr/local/bin/sing-box`、`/usr/local/bin/sb`
- 备份目录：`/opt/lattice/.archive_backup/`

出于兼容已安装节点的考虑，部分内部路径仍保留上游脚本的历史命名空间，例如 Caddy 配置目录可能继续使用旧路径。这个兼容细节不影响对外展示、安装源或使用方式。

## 发布与维护

- 脚本版本写在 `sing-box.sh` 的 `is_sh_ver`。
- GitHub Actions 会在 `main` 分支 push 后读取 `is_sh_ver`，生成/更新同名 Release。
- Release 资产 `code.tar.gz` 是远程安装和 `sb update sh` 使用的脚本包。
- 如果修改脚本逻辑并希望已安装机器检测到更新，需要同步提升 `is_sh_ver`。
- 安装脚本里的 `is_sh_repo` 指向 `lr00rl/sing-box`。
- 远程安装脚本检测到已有安装时，会默认只替换管理脚本层，方便从上游脚本迁移到本 fork。

## 反馈

问题反馈到本仓库：

https://github.com/lr00rl/sing-box/issues

上游脚本来源：

https://github.com/233boy/sing-box
