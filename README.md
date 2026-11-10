# 系谷 Xigu Tech | Network — 3XUI 定制一键管理脚本

单文件 Bash 脚本集合，在官方 [3x-ui](https://github.com/MHSanaei/3x-ui) 面板基础上，提供品牌化安装、多协议节点一键生成、Socks5 住宅落地中转与节点链接提取等能力。主脚本安装后输入 `xigu` 即可随时打开管理菜单；也可单独运行各协议脚本。

## 特性

- 一键安装官方 3x-ui，支持 GitHub 直连与国内 gh-proxy 镜像两条下载通道
- 自动部署「系谷 Xigu Tech | Network」品牌标识，每次 SSH 登录自动显示
- 全协议一键生成，密钥 / UUID / 端口自动生成，无需手工计算
- Socks5 落地 IP 一键添加，自动测试连通性并显示落地出口 IP
- 入站一键绑定落地，实现住宅中转，并可查看全部绑定关系
- 节点分享链接一键提取，统一写入 `/root/xigu-links.txt`
- 时区一键切换，支持 x86_64 与 arm64

## 脚本清单（共 9 个）

| 脚本 | 用途 | 是否需要域名 |
| --- | --- | --- |
| `xigu-xui.sh` | 3x-ui 面板全功能一键安装与管理菜单 | 否 |
| `xigu-vless-reality-vision.sh` | VLESS + Reality + XTLS-Vision | 否 |
| `xigu-vless-reality.sh` | VLESS + Reality（无 flow） | 否 |
| `xigu-vless-ws-tls.sh` | VLESS + WS + TLS（可走 CDN） | 是 |
| `xigu-vmess-ws-tls.sh` | VMess + WS + TLS（CDN 中转） | 是 |
| `xigu-trojan-tls.sh` | Trojan + TLS（可留空自签） | 是 |
| `xigu-hysteria2.sh` | Hysteria2 自签，高速 UDP | 否 |
| `xigu-shadowsocks2022.sh` | Shadowsocks-2022 | 否 |
| `xigu-cloudflare-worker.sh` | Cloudflare Worker 免费节点引导 | 否 |

## 支持系统

Debian、Ubuntu、CentOS、AlmaLinux、Rocky，x86_64 与 arm64 架构。

## 快速开始

以 root 用户运行主脚本：

```bash
bash xigu-xui.sh
```

安装完成后，随时输入以下命令打开管理菜单：

```bash
xigu
```

## 一键远程命令

把脚本托管后，客户无需上传文件，一条命令即可运行（以 GitHub 直链为例）：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/lizhihuiplum-creator/xigu-xui/main/xigu-xui.sh)
```

国内服务器直连 GitHub 较慢时，使用 gh-proxy 镜像：

```bash
bash <(curl -Ls https://gh-proxy.com/https://raw.githubusercontent.com/lizhihuiplum-creator/xigu-xui/main/xigu-xui.sh)
```

独立协议脚本需要强制镜像时，在命令末尾加 `mirror` 参数即可。

## 管理菜单

1. 官方网站入口
2. 面板原生管理（端口 / 用户名 / 密码）
3. 一键生成节点
4. 添加 Socks5 落地 IP
5. 节点绑定落地
6. 查看绑定关系
7. 提取全部节点链接
8. 时区设置
9. 重启面板

## 免责声明

本脚本仅用于学习与合法的服务器运维、网络管理场景，请遵守所在地区的法律法规。使用者需对自身行为负责，作者不对滥用承担责任。

---

系谷 Xigu Tech | Network
