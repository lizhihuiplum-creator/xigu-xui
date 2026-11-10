# 系谷 Xigu Tech | Network — 3XUI 定制一键管理脚本

单文件 Bash 脚本，在官方 [3x-ui](https://github.com/MHSanaei/3x-ui) 面板基础上，提供品牌化安装、多协议节点一键生成、Socks5 住宅落地中转与节点链接提取等能力。安装后输入 `xigu` 即可随时打开管理菜单。

## 特性

- 一键安装官方 3x-ui，支持 GitHub 直连与国内 gh-proxy 镜像两条下载通道
- 自动部署「系谷 Xigu Tech | Network」品牌标识，每次 SSH 登录自动显示
- 全协议一键生成，密钥 / UUID / 端口自动生成，无需手工计算
- Socks5 落地 IP 一键添加，自动测试连通性并显示落地出口 IP
- 入站一键绑定落地，实现住宅中转，并可查看全部绑定关系
- 节点分享链接一键提取，统一写入 `/root/xigu-links.txt`
- 时区一键切换，支持 x86_64 与 arm64

## 支持的协议

| 协议 | 传输 / 安全 | 说明 |
| --- | --- | --- |
| VLESS | TCP + Reality | 直连模式，内置大厂伪装目标 |
| VLESS | WS + TLS | Cloudflare CDN 中转，附带配置提示 |
| VMess | WS + TLS | Cloudflare CDN 中转 |
| Trojan | TCP + TLS | 自动生成密码 |
| Hysteria2 | TLS / QUIC | 高速 UDP |
| Shadowsocks | 2022-blake3-aes-256-gcm | SS-2022 |

## 支持系统

Debian、Ubuntu、CentOS、AlmaLinux、Rocky，x86_64 与 arm64 架构。

## 快速开始

以 root 用户运行：

```bash
bash xigu-xui.sh
```

安装过程中可选择下载通道（境外服务器选 1 直连，国内服务器选 2 镜像）与时区。安装完成后，随时输入以下命令打开管理菜单：

```bash
xigu
```

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

## 目录说明

```
xigu-xui.sh        主安装脚本（单文件）
```

## 免责声明

本脚本仅用于学习与合法的服务器运维、网络管理场景，请遵守所在地区的法律法规。使用者需对自身行为负责，作者不对滥用承担责任。

---

系谷 Xigu Tech | Network
