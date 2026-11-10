#!/usr/bin/env bash
#================================================================
# 系谷 Xigu Tech | Network
# 协议 / Protocol: VLESS + WebSocket + TLS（Cloudflare CDN 中转）
# 特点：需要域名，证书可自动申请；套 Cloudflare 小云朵隐藏源站
# EN: Requires a domain; works behind Cloudflare CDN to hide origin IP
# 用法 / Usage: bash xigu-vless-ws-tls.sh [mirror]
#================================================================
set -uo pipefail

BRAND_CN="系谷"
BRAND_EN="Xigu Tech | Network"
SITE_CN_URL="https://cn.jige.us";  SITE_CN_NAME="家庭住宅顶级线路 / Residential Proxies"
SITE_FY_URL="https://fy.jige.us";  SITE_FY_NAME="在线翻译 / Translator"
SITE_SZ_URL="https://sz.jige.us";  SITE_SZ_NAME="全球在线时钟 / World Clock"
SITE_IP_URL="https://ipip.jige.us"; SITE_IP_NAME="IP 检查工具 / IP Checker"
LINK_FILE="/root/xigu-links.txt"
CONF_DIR="/etc/xigu/conf"
CERT_DIR="/etc/xigu/certs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; }

show_banner() {
  echo
  echo -e "${CYAN}${BOLD}================================================================${NC}"
  echo -e "${CYAN}${BOLD}  ${BRAND_CN} Xigu  ·  ${BRAND_EN}${NC}"
  echo -e "${CYAN}${BOLD}================================================================${NC}"
  echo -e "  ${BOLD}本脚本 / This script: VLESS + WS + TLS（CDN）${NC}"
  echo -e "  中文：需要一个域名，脚本自动申请证书；域名接入 Cloudflare 开小云朵后源站 IP 被隐藏。"
  echo -e "  EN: A domain is required; put it behind Cloudflare orange cloud to hide the origin."
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo -e "  [1] ${SITE_CN_NAME}  ${GREEN}${SITE_CN_URL}${NC}"
  echo -e "  [2] ${SITE_FY_NAME}  ${GREEN}${SITE_FY_URL}${NC}"
  echo -e "  [3] ${SITE_SZ_NAME}  ${GREEN}${SITE_SZ_URL}${NC}"
  echo -e "  [4] ${SITE_IP_NAME}  ${GREEN}${SITE_IP_URL}${NC}"
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo -e "  ${YELLOW}Ctrl/Cmd+点击打开 / Click to open，选中即可复制 / select to copy${NC}"
  echo
}

[ "$(id -u)" -eq 0 ] || { error "请用 root 运行 / Please run as root"; exit 1; }

PM=""
if command -v apt-get >/dev/null 2>&1; then PM="apt"
elif command -v dnf >/dev/null 2>&1; then PM="dnf"
elif command -v yum >/dev/null 2>&1; then PM="yum"
else error "不支持的系统 / Unsupported OS"; exit 1; fi

install_deps() {
  info "安装依赖 / Installing dependencies..."
  if [ "$PM" = "apt" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl wget tar openssl jq ca-certificates iproute2 socat
  else
    yum install -y epel-release 2>/dev/null || dnf install -y epel-release 2>/dev/null || true
    if [ "$PM" = "dnf" ]; then dnf install -y curl wget tar openssl jq ca-certificates iproute socat
    else yum install -y curl wget tar openssl jq ca-certificates iproute socat; fi
  fi
}

install_xray() {
  if command -v xray >/dev/null 2>&1; then info "Xray 已安装 / Already installed"; return 0; fi
  local raw_base rel_prefix
  if [ "${1:-}" = "mirror" ]; then
    raw_base="https://gh-proxy.com/https://raw.githubusercontent.com"
    rel_prefix="https://gh-proxy.com/https://github.com"
  else
    raw_base="https://raw.githubusercontent.com"
    rel_prefix="https://github.com"
  fi
  local f="/tmp/xray-install.$$.sh"
  info "下载 Xray 安装器 / Downloading installer..."
  curl -fsSL --max-time 60 "${raw_base}/XTLS/Xray-install/main/install-release.sh" -o "$f" \
    || { error "下载失败，请加 mirror 参数重新执行一键命令 / Retry with mirror argument"; exit 1; }
  [ "${1:-}" = "mirror" ] && sed -i "s#https://github.com#${rel_prefix}#g" "$f"
  bash "$f" || { error "Xray 安装失败 / Install failed"; rm -f "$f"; exit 1; }
  rm -f "$f"
}

setup_confdir() {
  mkdir -p "$CONF_DIR" "$CERT_DIR"
  mkdir -p /etc/systemd/system/xray.service.d
  cat > /etc/systemd/system/xray.service.d/10-xigu.conf <<'INI'
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -confdir /etc/xigu/conf
INI
  systemctl daemon-reload
  systemctl enable xray >/dev/null 2>&1 || true
  [ -f "$CONF_DIR/00-base.json" ] || cat > "$CONF_DIR/00-base.json" <<'JSON'
{
  "log": {"loglevel": "warning"},
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIP"}},
    {"tag": "blocked", "protocol": "blackhole", "settings": {}}
  ]
}
JSON
}

random_port() {
  local p
  while :; do
    p=$((RANDOM % 50000 + 10000))
    if command -v ss >/dev/null 2>&1; then ss -tuln 2>/dev/null | grep -q ":$p " && continue; fi
    echo "$p"; return
  done
}
public_ip() {
  local ip
  for u in "https://api.ip.sb/ip" "https://ipinfo.io/ip" "https://ifconfig.me/ip"; do
    ip="$(curl -4 -s --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]' || true)"
    [ -n "${ip:-}" ] && { echo "$ip"; return 0; }
  done
}

#==================== 交互：域名 + 证书 ====================
show_banner
install_deps
install_xray "${1:-}"
setup_confdir

echo
warn "本协议需要域名 / A domain is required"
echo -e "  先把域名 A 记录解析到本机公网 IP：${GREEN}$(public_ip)${NC}"
read -r -p "请输入域名（如 cdn.example.com）： " DOMAIN
[ -z "$DOMAIN" ] && { error "域名不能为空"; exit 1; }

echo
echo "选择证书方式 / Choose certificate:"
echo "  1) acme 自动申请 Let's Encrypt（域名已解析、80 端口空闲，推荐）"
echo "  2) 已有证书，手动输入 crt/key 路径"
echo "  3) 自签证书（仅测试，客户端需允许不安全）"
read -r -p "输入 [1-3]，默认 1： " CCH; CCH="${CCH:-1}"

CERT=""; KEY=""; INSECURE=0
case "$CCH" in
  1)
    info "安装 acme.sh 并申请证书 / Issuing certificate..."
    curl -fsSL https://get.acme.sh | sh -s email=admin@${DOMAIN}
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 || {
      error "申请失败，请确认域名已解析、80 端口未被占用，或改用选项 2/3"; exit 1; }
    CERT="$CERT_DIR/$DOMAIN.crt"; KEY="$CERT_DIR/$DOMAIN.key"
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
      --key-file "$KEY" --fullchain-file "$CERT"
    ;;
  2)
    read -r -p "证书 crt/pem 完整路径： " CERT
    read -r -p "私钥 key 完整路径： " KEY
    [ -f "$CERT" ] && [ -f "$KEY" ] || { error "证书文件不存在"; exit 1; }
    ;;
  3)
    CERT="$CERT_DIR/self-$DOMAIN.crt"; KEY="$CERT_DIR/self-$DOMAIN.key"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout "$KEY" -out "$CERT" -days 3650 -nodes -subj "/CN=$DOMAIN" >/dev/null 2>&1
    INSECURE=1
    ;;
esac

UUID="$(cat /proc/sys/kernel/random/uuid)"
PORT="$(random_port)"
TAG="vless-ws-$(openssl rand -hex 3)"
REMARK="xigu-ws-$(openssl rand -hex 2)"
WSPATH="/xigu-$(openssl rand -hex 4)"

info "生成 VLESS+WS+TLS 节点 / Generating node..."
jq -nc --arg uuid "$UUID" --arg domain "$DOMAIN" --arg path "$WSPATH" \
  --arg cert "$CERT" --arg key "$KEY" \
'{inbounds:[{
   tag:"ws-in", listen:"0.0.0.0", port:0, protocol:"vless",
   settings:{clients:[{id:$uuid, flow:""}], decryption:"none", fallbacks:[]},
   streamSettings:{network:"ws", security:"tls",
     tlsSettings:{serverName:$domain, minVersion:"1.2",
       certificates:[{certificateFile:$cert, keyFile:$key}], alpn:["h2","http/1.1"]},
     wsSettings:{path:$path, host:$domain, headers:{}}},
   sniffing:{enabled:true, destOverride:["http","tls","quic"]}
 }]}' > /tmp/.xigu-tmp.json
jq --argjson port "$PORT" --arg tag "$TAG" '.inbounds[0].port=$port | .inbounds[0].tag=$tag' /tmp/.xigu-tmp.json \
  > "$CONF_DIR/10-$TAG.json"
rm -f /tmp/.xigu-tmp.json

systemctl restart xray
sleep 1
systemctl is-active --quiet xray || { error "Xray 启动失败 / Check: journalctl -u xray -n 30"; exit 1; }

ENC="$(jq -rn --arg x "$REMARK" '$x|@uri')"
EPATH="$(jq -rn --arg x "$WSPATH" '$x|@uri')"
LINK="vless://${UUID}@${DOMAIN}:${PORT}?encryption=none&security=tls&sni=${DOMAIN}&type=ws&path=${EPATH}&host=${DOMAIN}#${ENC}"

{
  echo "# ${REMARK} / VLESS WS TLS / $(date '+%F %T')"
  echo "$LINK"; echo
} >> "$LINK_FILE"

info "节点生成成功 / Node created"
echo -e "${CYAN}================================================================${NC}"
echo -e "  域名 / Domain: ${DOMAIN}   端口 / Port: ${PORT}   路径 / Path: ${WSPATH}"
echo -e "${YELLOW}  Cloudflare 设置 / Setup: 小云朵开启 → SSL/TLS 选 Full（严格）→ WebSocket 无需额外规则${NC}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"
echo -e "  ${GREEN}${LINK}${NC}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"
echo -e "  链接已追加到 / Saved to: ${BOLD}${LINK_FILE}${NC}"
[ "$INSECURE" -eq 1 ] && warn "自签证书：客户端需允许不安全 / self-signed: allow insecure in client"
echo
