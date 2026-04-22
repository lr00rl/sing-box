# 介绍

最好用的 sing-box 一键安装脚本 & 管理脚本

# 特点

- 快速安装
- 无敌好用
- 零学习成本
- 自动化 TLS
- 简化所有流程
- 兼容 sing-box 命令
- 强大的快捷参数
- 支持所有常用协议
- 一键添加 VLESS-REALITY (默认)
- 一键添加 TUIC
- 一键添加 Trojan
- 一键添加 Hysteria2
- 一键添加 AnyTLS
- 一键添加 Shadowsocks 2022
- 一键添加 VMess-(TCP/HTTP/QUIC)
- 一键添加 VMess-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 VLESS-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 Trojan-(WS/H2/HTTPUpgrade)-TLS
- 一键启用 BBR
- 一键更改伪装网站
- 一键更改 (端口/UUID/密码/域名/路径/加密方式/SNI/等...)
- 还有更多...

# 设计理念

设计理念为：**高效率，超快速，极易用**

脚本基于作者的自身使用需求，以 **多配置同时运行** 为核心设计

并且专门优化了，添加、更改、查看、删除、这四项常用功能

你只需要一条命令即可完成 添加、更改、查看、删除、等操作

例如，添加一个配置仅需不到 1 秒！瞬间完成添加！其他操作亦是如此！

脚本的参数非常高效率并且超级易用，请掌握参数的使用

# 文档

安装及使用：https://233boy.com/sing-box/sing-box-script/

本项目基于 [xykt/IPQuality](https://github.com/xykt/IPQuality) 进行了调整，主要解决部分机器在安装阶段无法正常获取 IP 的问题，并支持传入自定义 IP 或域名作为连接地址。

远程安装请使用 raw 地址，不要使用 GitHub 的 `blob` 页面地址。

标准安装命令：

- `bash <(curl -fsSL https://raw.githubusercontent.com/lr00rl/sing-box/main/install.sh)`
- `bash <(curl -fsSL https://raw.githubusercontent.com/lr00rl/sing-box/main/install.sh) --server-addr 1.2.3.4`
- `bash <(curl -fsSL https://raw.githubusercontent.com/lr00rl/sing-box/main/install.sh) --server-addr example.com`

如果仓库 Release 中不存在 `code.tar.gz`，远程安装会在下载脚本包时失败；这种情况下可先下载源码后使用本地模式安装：`bash install.sh -l`

安装时如果自动获取 IP 失败，或你希望直接指定连接地址，可执行：

- `bash install.sh --server-addr 1.2.3.4`
- `bash install.sh --server-addr example.com`

脚本运行时也支持临时指定连接地址，例如：

- `sb --addr 1.2.3.4 add reality 40572`
- `sb --addr example.com`

如果在交互式添加配置时自动获取 IP 失败，脚本现在也会提示手动输入连接地址继续创建。

发布说明：

- 仓库发布源使用 `lr00rl/sing-box`
- GitHub Actions 会在 `main` 分支 push 后自动刷新当前版本号对应的 Release，并更新 `code.tar.gz`
- 如果希望已安装机器通过 `sb update sh` 检测到新版本，请同步更新 `sing-box.sh` 中的 `is_sh_ver`

# 帮助

使用：`sing-box help`

```
sing-box script v1.0 by 233boy
Usage: sing-box [options]... [args]...

基本:
   v, version                                      显示当前版本
   ip                                              返回当前主机的 IP
   pbk                                             同等于 sing-box generate reality-keypair
   get-port                                        返回一个可用的端口
   ss2022                                          返回一个可用于 Shadowsocks 2022 的密码

一般:
   a, add [protocol] [args... | auto]              添加配置
   c, change [name] [option] [args... | auto]      更改配置
   d, del [name]                                   删除配置**
   i, info [name]                                  查看配置
   qr [name]                                       二维码信息
   url [name]                                      URL 信息
   log                                             查看日志
更改:
   full [name] [...]                               更改多个参数
   addr [name] [ip | domain | auto]                更改连接地址
   id [name] [uuid | auto]                         更改 UUID
   host [name] [domain]                            更改域名
   port [name] [port | auto]                       更改端口
   path [name] [path | auto]                       更改路径
   passwd [name] [password | auto]                 更改密码
   key [name] [Private key | atuo] [Public key]    更改密钥
   method [name] [method | auto]                   更改加密方式
   sni [name] [ ip | domain]                       更改 serverName
   new [name] [...]                                更改协议
   web [name] [domain]                             更改伪装网站

进阶:
   dns [...]                                       设置 DNS
   dd, ddel [name...]                              删除多个配置**
   fix [name]                                      修复一个配置
   fix-all                                         修复全部配置
   fix-caddyfile                                   修复 Caddyfile
   fix-config.json                                 修复 config.json
   import                                          导入 sing-box/v2ray 脚本配置

管理:
   un, uninstall                                   卸载
   u, update [core | sh | caddy] [ver]             更新
   U, update.sh                                    更新脚本
   s, status                                       运行状态
   start, stop, restart [caddy]                    启动, 停止, 重启
   t, test                                         测试运行
   reinstall                                       重装脚本

测试:
   debug [name]                                    显示一些 debug 信息, 仅供参考
   gen [...]                                       同等于 add, 但只显示 JSON 内容, 不创建文件, 测试使用
   no-auto-tls [...]                               同等于 add, 但禁止自动配置 TLS, 可用于 *TLS 相关协议
其他:
   bbr                                             启用 BBR, 如果支持
   bin [...]                                       运行 sing-box 命令, 例如: sing-box bin help
   [...] [...]                                     兼容绝大多数的 sing-box 命令, 例如: sing-box generate uuid
   h, help                                         显示此帮助界面

谨慎使用 del, ddel, 此选项会直接删除配置; 无需确认
反馈问题) https://github.com/lr00rl/sing-box/issues
文档(doc) https://233boy.com/sing-box/sing-box-script/
```
