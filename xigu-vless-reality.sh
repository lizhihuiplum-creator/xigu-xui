#!/usr/bin/env bash
#================================================================
# 系谷 Xigu Tech | Network
# 协议 / Protocol: VLESS + Reality（无 Vision，兼容老客户端）
# 特点：无需域名、无需证书，一键生成
# EN: No domain/cert needed; no Vision flow, maximum client compatibility
# 用法 / Usage: bash xigu-vless-reality.sh [mirror]
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
  echo -e "  ${BOLD}本脚本 / This script: VLESS + Reality（无 Vision）${NC}"
  echo -e "  中文：无需域名和证书，不带 Vision 流控，兼容不支持 flow 的老客户端。"
  echo -e "  EN: No Vision flow; use this if your client does not support xtls-rprx-vision."
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo -e "  [1] ${SITE_CN_NAME}  ${GREEN}${SITE_CN_URL}${NC}"
  echo -e "  [2] ${SITE_FY_NAME}  ${GREEN}${SITE_FY_URL}${NC}"
  echo -e "  [3] ${SITE_SZ_NAME}  ${GREEN}${SITE_SZ_URL}${NC}"
  echo -e "  [4] ${SITE_IP_NAME}  ${GREEN}${SITE_IP_URL}${NC}"
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo -e "  ${YELLOW}Ctrl/Cmd+点击链接直接打开 / Click to open，选中即可复制 / select to copy${NC}"
  echo
}

if [ "$(id -u)" -ne 0 ]; then error "请用 root 运行 / Please run as root"; exit 1; fi

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
    apt-get install -y curl wget tar openssl jq ca-certificates iproute2
  else
    yum install -y epel-release 2>/dev/null || dnf install -y epel-release 2>/dev/null || true
    if [ "$PM" = "dnf" ]; then dnf install -y curl wget tar openssl jq ca-certificates iproute
    else yum install -y curl wget tar openssl jq ca-certificates iproute; fi
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
  info "下载 Xray 官方安装器 / Downloading installer..."
  if ! curl -fsSL --max-time 60 "${raw_base}/XTLS/Xray-install/main/install-release.sh" -o "$f"; then
    error "下载失败，请加 mirror 参数重新执行一键命令 / Retry with mirror argument"; exit 1
  fi
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
x25519_keys() {
  local out priv pub
  out="$(xray x25519 2>&1)"
  priv="$(echo "$out" | grep -iE 'private key|password' | head -1 | awk -F': ' '{print $2}' | tr -d '[:space:]')"
  pub="$(echo "$out" | grep -iE 'public key' | head -1 | awk -F': ' '{print $2}' | tr -d '[:space:]')"
  echo "$priv $pub"
}

show_banner
install_deps
install_xray "${1:-}"
setup_confdir

UUID="$(cat /proc/sys/kernel/random/uuid)"
KEYS="$(x25519_keys)"; PRIV="${KEYS%% *}"; PUB="${KEYS##* }"
SID="$(openssl rand -hex 8)"
PORT="$(random_port)"
TAG="vless-r-$(openssl rand -hex 3)"
REMARK="xigu-reality-novision-$(openssl rand -hex 2)"
DESTS=("www.microsoft.com:443" "www.apple.com:443" "www.amazon.com:443" "dl.google.com:443" "www.cloudflare.com:443")
DEST="${DESTS[RANDOM % ${#DESTS[@]}]}"
SNAME="${DEST%%:*}"

info "生成 VLESS+Reality（无 Vision）节点 / Generating node..."
jq -nc --arg uuid "$UUID" --arg priv "$PRIV" --arg sid "$SID" --arg dest "$DEST" --arg sn "$SNAME" \
'{inbounds:[{
   tag:("in-"+$sn), listen:"0.0.0.0", port:0, protocol:"vless",
   settings:{clients:[{id:$uuid, flow:""}], decryption:"none", fallbacks:[]},
   streamSettings:{network:"tcp", security:"reality",
     realitySettings:{dest:$dest, serverNames:[$sn], privateKey:$priv, shortIds:[$sid],
       fingerprint:"chrome", settings:{fingerprint:"chrome"}}},
   sniffing:{enabled:true, destOverride:["http","tls","quic"]}
 }]}' > /tmp/.xigu-tmp.json
jq --argjson port "$PORT" --arg tag "$TAG" '.inbounds[0].port=$port | .inbounds[0].tag=$tag' /tmp/.xigu-tmp.json \
  > "$CONF_DIR/10-$TAG.json"
rm -f /tmp/.xigu-tmp.json

systemctl restart xray
sleep 1
systemctl is-active --quiet xray || { error "Xray 启动失败 / Check: journalctl -u xray -n 30"; exit 1; }

HOST="$(public_ip)"
ENC="$(jq -rn --arg x "$REMARK" '$x|@uri')"
LINK="vless://${UUID}@${HOST}:${PORT}?encryption=none&security=reality&sni=${SNAME}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp#${ENC}"

{
  echo "# ${REMARK} / VLESS Reality no-Vision / $(date '+%F %T')"
  echo "$LINK"; echo
} >> "$LINK_FILE"

info "节点生成成功 / Node created"
echo -e "${CYAN}================================================================${NC}"
echo -e "  服务器 / Server: ${HOST}:${PORT}"
echo -e "  伪装目标 / SNI: ${SNAME}   短ID / shortId: ${SID}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"
echo -e "  ${GREEN}${LINK}${NC}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"
echo -e "  链接已追加到 / Saved to: ${BOLD}${LINK_FILE}${NC}"
echo
