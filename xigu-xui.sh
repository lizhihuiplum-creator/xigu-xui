#!/usr/bin/env bash
#====================================================================
# 系谷 Xigu Tech | Network — 3XUI 定制一键安装脚本
# 功能：
#   1. 自动安装官方 3x-ui 面板（支持 GitHub 直连 / 国内镜像）
#   2. 部署「系谷 Xigu Tech | Network」品牌标识，SSH 登录自动显示
#   3. 四个广告网站位（链接可点击 / 可复制）
#   4. Socks5 落地 IP 一键添加、入站一键绑定落地（住宅中转）
#   5. 全协议一键生成：VLESS+Reality / VLESS+WS+TLS(CDN) /
#      VMess+WS / Trojan / Hysteria2 / Shadowsocks-2022
#   6. 节点分享链接一键提取，写入 /root/xigu-links.txt
#   7. 时区一键切换
# 系统：Debian / Ubuntu / CentOS / AlmaLinux / Rocky（x86_64 / arm64）
# 用法：bash xigu-xui.sh
#====================================================================

set -euo pipefail

#======================= 品牌配置区（可直接改） =======================
XIGU_VERSION="1.0.0"
BRAND_CN="系谷"
BRAND_EN="Xigu Tech | Network"

SITE_CN_URL="https://cn.jige.us"
SITE_CN_NAME="家庭住宅顶级线路"
SITE_FY_URL="https://fy.jige.us"
SITE_FY_NAME="在线翻译"
SITE_SZ_URL="https://sz.jige.us"
SITE_SZ_NAME="全球在线时钟"
SITE_IP_URL="https://ipip.jige.us"
SITE_IP_NAME="IP 检查工具"

XUI_DIR="/usr/local/x-ui"
XUI_DB="/etc/x-ui/x-ui.db"
XIGU_BIN="/usr/local/bin/xigu"
XIGU_PROFILE="/etc/profile.d/xigu.sh"
XIGU_ETC="/etc/xigu"
LINK_FILE="/root/xigu-links.txt"

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; }

# root 检测
if [ "$(id -u)" -ne 0 ]; then
  error "请使用 root 用户运行本脚本（或 sudo bash xigu-xui.sh）"
  exit 1
fi

# 系统检测
OS_ID=""; OS_VER=""; PM=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="${ID:-}"
  OS_VER="${VERSION_ID:-}"
fi
if command -v apt-get >/dev/null 2>&1; then
  PM="apt"
elif command -v dnf >/dev/null 2>&1; then
  PM="dnf"
elif command -v yum >/dev/null 2>&1; then
  PM="yum"
else
  error "不支持的系统：未找到 apt-get / dnf / yum"
  exit 1
fi
ARCH="$(uname -m)"
info "系统：${OS_ID} ${OS_VER}，架构：${ARCH}，包管理器：${PM}"

#======================= 依赖安装 =======================
install_deps() {
  info "安装基础依赖..."
  if [ "$PM" = "apt" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl wget tar openssl jq sqlite3 ca-certificates iproute2 procps
  else
    yum install -y epel-release 2>/dev/null || dnf install -y epel-release 2>/dev/null || true
    if [ "$PM" = "dnf" ]; then
      dnf install -y curl wget tar openssl jq sqlite ca-certificates iproute procps-ng
    else
      yum install -y curl wget tar openssl jq sqlite ca-certificates iproute procps-ng
    fi
  fi
  command -v jq >/dev/null 2>&1 || { error "jq 安装失败，请检查软件源后重试"; exit 1; }
}

#======================= 3x-ui 安装 =======================
install_xui() {
  if [ -d "$XUI_DIR" ] && systemctl list-unit-files x-ui.service >/dev/null 2>&1; then
    info "检测到 3x-ui 已安装，跳过面板安装步骤（仅更新系谷定制文件）"
    return 0
  fi

  echo
  echo -e "${BOLD}请选择下载通道：${NC}"
  echo "  1) GitHub 直连（境外 VPS 推荐，默认）"
  echo "  2) gh-proxy 国内镜像（国内服务器用）"
  read -r -p "输入选项 [1/2]，默认 1： " CH
  CH="${CH:-1}"

  local raw_base rel_prefix
  if [ "$CH" = "2" ]; then
    raw_base="https://gh-proxy.com/https://raw.githubusercontent.com"
    rel_prefix="https://gh-proxy.com/https://github.com"
  else
    raw_base="https://raw.githubusercontent.com"
    rel_prefix="https://github.com"
  fi

  local tmp_sh="/tmp/xui-install.$$.sh"
  info "下载官方 3x-ui 安装脚本..."
  if ! curl -fsSL --max-time 60 "${raw_base}/MHSanaei/3x-ui/master/install.sh" -o "$tmp_sh"; then
    error "下载失败。若当前是国内服务器，请重跑脚本并选择通道 2"
    rm -f "$tmp_sh"
    exit 1
  fi
  # 镜像通道：把脚本内的 GitHub 下载地址也替换成镜像
  if [ "$CH" = "2" ]; then
    sed -i "s#https://github.com#${rel_prefix}#g" "$tmp_sh"
  fi

  info "开始安装 3x-ui（安装过程中如出现询问，直接回车用默认即可）..."
  bash "$tmp_sh" || {
    error "3x-ui 安装失败，请把上方报错截图发我"
    rm -f "$tmp_sh"
    exit 1
  }
  rm -f "$tmp_sh"

  systemctl daemon-reload 2>/dev/null || true
  systemctl enable x-ui >/dev/null 2>&1 || true
  systemctl restart x-ui
  info "3x-ui 安装完成"
}

#======================= 时区设置 =======================
choose_timezone() {
  echo
  echo -e "${BOLD}服务器时区设置：${NC}"
  echo "  1) Asia/Shanghai 北京时间（默认）"
  echo "  2) Asia/Singapore 新加坡"
  echo "  3) America/New_York 美东"
  echo "  4) America/Los_Angeles 美西"
  echo "  5) Europe/London 伦敦"
  echo "  6) America/Santiago 智利"
  echo "  7) 跳过，保持系统默认"
  read -r -p "输入选项 [1-7]，默认 1： " TZCH
  TZCH="${TZCH:-1}"
  local tz=""
  case "$TZCH" in
    1) tz="Asia/Shanghai" ;;
    2) tz="Asia/Singapore" ;;
    3) tz="America/New_York" ;;
    4) tz="America/Los_Angeles" ;;
    5) tz="Europe/London" ;;
    6) tz="America/Santiago" ;;
    7) info "跳过时区设置"; return 0 ;;
    *) tz="Asia/Shanghai" ;;
  esac
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone "$tz"
  else
    ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
  fi
  info "时区已设置为：$tz（以后随时输入 xigu 可再改）"
}

#======================= 部署系谷定制文件 =======================
deploy_xigu() {
  info "部署系谷管理命令 xigu ..."
  mkdir -p "$XIGU_ETC"
  chmod 700 "$XIGU_ETC"

  cat > "$XIGU_BIN" <<'XGEOF'
#!/usr/bin/env bash
#================================================================
# 系谷 Xigu Tech | Network — 3XUI 定制管理菜单
# 输入 xigu 即可随时打开本菜单
#================================================================

set -uo pipefail

XIGU_VERSION="1.0.0"
BRAND_CN="系谷"
BRAND_EN="Xigu Tech | Network"

SITE_CN_URL="https://cn.jige.us";  SITE_CN_NAME="家庭住宅顶级线路"
SITE_FY_URL="https://fy.jige.us";  SITE_FY_NAME="在线翻译"
SITE_SZ_URL="https://sz.jige.us";  SITE_SZ_NAME="全球在线时钟"
SITE_IP_URL="https://ipip.jige.us"; SITE_IP_NAME="IP 检查工具"

XUI_DIR="/usr/local/x-ui"
XUI_DB="/etc/x-ui/x-ui.db"
XIGU_ETC="/etc/xigu"
CONF="$XIGU_ETC/xigu.conf"
COOKIE="$XIGU_ETC/cookie.txt"
LINK_FILE="/root/xigu-links.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*" >&2; }

#==================== 品牌 banner ====================
show_banner() {
  echo
  echo -e "${CYAN}${BOLD}"
  cat <<'LOGO'
 ██╗  ██╗██╗ ██████╗ ██╗   ██╗
 ╚██╗██╔╝██║██╔════╝ ██║   ██║
  ╚██╔╝ ██║██║  ███╗ ██║   ██║
  ██╔╝  ██║██║   ██║ ██║   ██║
 ██╔╝   ██║╚██████╔╝ ╚██████╔╝
 ╚═╝    ╚═╝ ╚═════╝   ╚═════╝
LOGO
  echo -e "${YELLOW}  ${BRAND_CN} Xigu  ·  ${BRAND_EN}${NC}"
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo -e "  ${BOLD}[1]${NC} ${SITE_CN_NAME}  ${GREEN}${SITE_CN_URL}${NC}"
  echo -e "  ${BOLD}[2]${NC} ${SITE_FY_NAME}  ${GREEN}${SITE_FY_URL}${NC}"
  echo -e "  ${BOLD}[3]${NC} ${SITE_SZ_NAME}  ${GREEN}${SITE_SZ_URL}${NC}"
  echo -e "  ${BOLD}[4]${NC} ${SITE_IP_NAME}  ${GREEN}${SITE_IP_URL}${NC}"
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo -e "  ${YELLOW}终端内按住 Ctrl/Cmd 点击链接可直接打开，选中链接即可复制${NC}"
  echo
}

#==================== 工具函数 ====================
find_xray_bin() {
  local b
  b="$(ls "$XUI_DIR"/bin/xray-* 2>/dev/null | head -n1 || true)"
  echo "$b"
}
XRAY_BIN="$(find_xray_bin)"

random_port() {
  local p
  while :; do
    p=$((RANDOM % 50000 + 10000))
    if command -v ss >/dev/null 2>&1; then
      ss -tuln 2>/dev/null | grep -q ":$p " && continue
    fi
    echo "$p"
    return
  done
}

gen_uuid() {
  if [ -f /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    "$XRAY_BIN" uuid
  fi
}

x25519_keys() {
  local out priv pub
  if [ -z "$XRAY_BIN" ]; then error "未找到 xray 程序，面板可能未正确安装"; return 1; fi
  out="$("$XRAY_BIN" x25519 2>&1)"
  priv="$(echo "$out" | grep -iE 'private key|password' | head -1 | awk -F': ' '{print $2}' | tr -d '[:space:]')"
  pub="$(echo "$out" | grep -iE 'public key' | head -1 | awk -F': ' '{print $2}' | tr -d '[:space:]')"
  if [ -z "$priv" ] || [ -z "$pub" ]; then
    error "x25519 密钥生成失败：$out"
    return 1
  fi
  echo "$priv $pub"
}

public_ip() {
  local ip
  for u in "https://api.ip.sb/ip" "https://ipinfo.io/ip" "https://ifconfig.me/ip"; do
    ip="$(curl -4 -s --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]' || true)"
    if [ -n "${ip:-}" ]; then echo "$ip"; return 0; fi
  done
  echo ""
}

#==================== 面板 API 登录 ====================
init_conf() {
  mkdir -p "$XIGU_ETC"; chmod 700 "$XIGU_ETC"
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
    return 0
  fi

  local db_port="" db_user=""
  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$XUI_DB" ]; then
    db_port="$(sqlite3 "$XUI_DB" "select value from settings where key='webPort';" 2>/dev/null || true)"
    db_user="$(sqlite3 "$XUI_DB" "select value from settings where key='username';" 2>/dev/null || true)"
  fi
  db_port="${db_port:-2053}"
  db_user="${db_user:-admin}"

  echo
  warn "首次使用需要连接本机 3x-ui 面板（信息仅保存在 ${CONF}，权限 600）"
  local base user pass
  read -r -p "面板地址，默认 https://127.0.0.1:${db_port}： " base
  base="${base:-https://127.0.0.1:${db_port}}"
  base="${base%/}"
  read -r -p "面板用户名，默认 ${db_user}： " user
  user="${user:-$db_user}"
  read -r -s -p "面板密码： " pass; echo
  if [ -z "$pass" ]; then error "密码不能为空"; return 1; fi

  cat > "$CONF" <<CFG
BASE="$base"
XU="$user"
XP="$pass"
CFG
  chmod 600 "$CONF"
  # shellcheck disable=SC1090
  . "$CONF"
}

api_login() {
  init_conf || return 1
  rm -f "$COOKIE"
  local resp
  resp="$(curl -sk -c "$COOKIE" -X POST "${BASE}/login" \
    --data-urlencode "username=$XU" --data-urlencode "password=$XP" 2>/dev/null || true)"
  if echo "$resp" | jq -e '.success==true' >/dev/null 2>&1; then
    chmod 600 "$COOKIE"
    return 0
  fi
  error "面板登录失败，请检查地址/用户名/密码"
  echo -e "  接口返回：${YELLOW}${resp}${NC}"
  read -r -p "重新填写连接信息？(y/n)，默认 y： " r
  r="${r:-y}"
  if [ "$r" = "y" ]; then
    rm -f "$CONF"
    init_conf || return 1
    api_login
    return $?
  fi
  return 1
}

api_get() { curl -sk -b "$COOKIE" "$1"; }
api_post_json() { curl -sk -b "$COOKIE" -X POST "$1" -H 'Content-Type: application/json' -d "$2"; }

# 读取 xray 配置（兼容 obj 为对象或字符串两种返回）
get_xray_cfg() {
  local raw
  raw="$(api_get "${BASE}/panel/setting/xray")"
  if echo "$raw" | jq -e '.obj | type=="string"' >/dev/null 2>&1; then
    echo "$raw" | jq -r '.obj' | jq '.'
  else
    echo "$raw" | jq '.obj'
  fi
}

update_xray_cfg() {
  local cfg="$1" resp
  resp="$(curl -sk -b "$COOKIE" -X POST "${BASE}/panel/setting/xray" \
    --data-urlencode "xrayConfig=$cfg" 2>/dev/null || true)"
  echo "$resp" | jq -e '.success==true' >/dev/null 2>&1
}

list_inbounds_raw() { api_get "${BASE}/panel/api/inbounds/list"; }

add_inbound_api() {
  api_post_json "${BASE}/panel/api/inbounds/add" "$1"
}

# 列出入站供选择，输出选中的 tag
pick_inbound() {
  local data
  data="$(list_inbounds_raw)"
  local n
  n="$(echo "$data" | jq '.obj | length')"
  if [ "$n" -eq 0 ]; then warn "当前面板还没有任何入站，请先生成节点"; return 1; fi
  echo
  echo -e "${BOLD}现有入站：${NC}"
  echo "$data" | jq -r '.obj | to_entries[] | "  \(.key+1)) [\(.value.protocol)] \(.value.remark)  端口=\(.value.port)  tag=\(.value.tag)"'
  local pick
  read -r -p "选择序号 [1-${n}]： " pick
  echo "$pick" | grep -qE '^[0-9]+$' || { error "必须输入数字"; return 1; }
  [ "$pick" -lt 1 ] || [ "$pick" -gt "$n" ] && { error "序号超出范围"; return 1; }
  echo "$data" | jq -r ".obj[$((pick-1))].tag"
}

#==================== Socks5 落地管理 ====================
add_landing() {
  api_login || return 1
  echo
  echo -e "${BOLD}添加 Socks5 落地 IP（支持 IPRoyal/Oxylabs/Bright Data/Decodo 等所有住宅代理）${NC}"
  local name host port luser lpass
  read -r -p "落地名称（英文数字，如 iproyal-us）： " name
  name="$(echo "$name" | tr -cd 'A-Za-z0-9_-')"
  [ -z "$name" ] && { error "名称不合法"; return 1; }
  local tag="landing-${name}"
  read -r -p "落地 IP 或域名： " host
  [ -z "$host" ] && { error "地址不能为空"; return 1; }
  read -r -p "落地端口： " port
  echo "$port" | grep -qE '^[0-9]+$' || { error "端口必须是数字"; return 1; }
  read -r -p "用户名（无认证直接回车）： " luser
  read -r -s -p "密码（无认证直接回车）： " lpass; echo

  # 先测试落地连通性
  info "测试落地连通性（请求 ipinfo.io）..."
  local test_ip=""
  if [ -n "$luser" ]; then
    test_ip="$(curl -s --max-time 15 --socks5-hostname "${luser}:${lpass}@${host}:${port}" https://ipinfo.io/ip 2>/dev/null || true)"
  else
    test_ip="$(curl -s --max-time 15 --socks5-hostname "${host}:${port}" https://ipinfo.io/ip 2>/dev/null || true)"
  fi
  if [ -n "$test_ip" ]; then
    info "落地连通正常，落地出口 IP：${GREEN}${test_ip}${NC}"
  else
    warn "落地测试未通过，仍可继续保存（部分落地限制探测站点）"
    read -r -p "仍然保存？(y/n)，默认 n： " go
    [ "${go:-n}" = "y" ] || return 1
  fi

  local ob cfg
  if [ -n "$luser" ]; then
    ob="$(jq -nc --arg tag "$tag" --arg addr "$host" --argjson port "$port" \
      --arg u "$luser" --arg p "$lpass" \
      '{tag:$tag, protocol:"socks", settings:{servers:[{address:$addr, port:$port, users:[{user:$u, pass:$p}]}]}}')"
  else
    ob="$(jq -nc --arg tag "$tag" --arg addr "$host" --argjson port "$port" \
      '{tag:$tag, protocol:"socks", settings:{servers:[{address:$addr, port:$port}]}}')"
  fi

  cfg="$(get_xray_cfg)"
  if echo "$cfg" | jq -e --arg t "$tag" '(.outbounds // [])[] | select(.tag==$t)' >/dev/null 2>&1; then
    error "已存在同名落地：$tag"
    return 1
  fi
  cfg="$(echo "$cfg" | jq --argjson ob "$ob" '.outbounds = ((.outbounds // []) + [$ob])')"

  # 询问是否立即绑定入站
  read -r -p "是否立即把某个入站绑定到该落地？(y/n)，默认 y： " bd
  bd="${bd:-y}"
  if [ "$bd" = "y" ]; then
    local itag
    itag="$(pick_inbound)" || return 1
    [ -z "$itag" ] && return 1
    local rule
    rule="$(jq -nc --arg itag "$itag" --arg otag "$tag" \
      '{type:"field", inboundTag:[$itag], outboundTag:$otag}')"
    cfg="$(echo "$cfg" | jq --argjson r "$rule" \
      '.routing.rules = (if (.routing.rules // null) != null then [$r] + .routing.rules else [$r] end)')"
    info "入站 ${itag} 的流量将全部走该落地"
  fi

  if update_xray_cfg "$cfg"; then
    info "落地 ${tag} 保存成功，Xray 已自动应用"
  else
    error "保存失败，请检查面板状态"
  fi
}

bind_landing() {
  api_login || return 1
  local cfg
  cfg="$(get_xray_cfg)"
  local n
  n="$(echo "$cfg" | jq '(.outbounds // []) | map(select(.protocol=="socks")) | length')"
  if [ "$n" -eq 0 ]; then warn "还没有任何 Socks5 落地，请先添加"; return 1; fi
  echo
  echo -e "${BOLD}现有落地：${NC}"
  echo "$cfg" | jq -r '(.outbounds // []) | map(select(.protocol=="socks")) | to_entries[] | "  \(.key+1)) \(.value.tag) -> \(.value.settings.servers[0].address):\(.value.settings.servers[0].port)"'
  read -r -p "选择落地序号： " lp
  echo "$lp" | grep -qE '^[0-9]+$' || { error "必须输入数字"; return 1; }
  [ "$lp" -lt 1 ] || [ "$lp" -gt "$n" ] && { error "序号超出范围"; return 1; }
  local otag
  otag="$(echo "$cfg" | jq -r "(.outbounds // []) | map(select(.protocol==\"socks\")) | .[$((lp-1))].tag")"
  local itag
  itag="$(pick_inbound)" || return 1
  local rule
  rule="$(jq -nc --arg itag "$itag" --arg otag "$otag" \
    '{type:"field", inboundTag:[$itag], outboundTag:$otag}')"
  cfg="$(echo "$cfg" | jq --argjson r "$rule" \
    '.routing.rules = (if (.routing.rules // null) != null then [$r] + .routing.rules else [$r] end)')"
  if update_xray_cfg "$cfg"; then
    info "绑定成功：${itag} -> ${otag}"
  else
    error "绑定失败"
  fi
}

show_bindings() {
  api_login || return 1
  local cfg
  cfg="$(get_xray_cfg)"
  echo
  echo -e "${BOLD}当前中转绑定关系（inbound -> 落地）：${NC}"
  echo "$cfg" | jq -r '(.routing.rules // [])[] | select(.outboundTag? | startswith("landing-")) | "  \(.inboundTag[0])  ->  \(.outboundTag)"'
  echo
  echo -e "${BOLD}全部落地：${NC}"
  echo "$cfg" | jq -r '(.outbounds // [])[] | select(.protocol=="socks") | "  \(.tag) -> \(.settings.servers[0].address):\(.settings.servers[0].port)"'
}

#==================== 入站构造通用函数 ====================
build_and_add() {
  local tag="$1" port="$2" proto="$3" remark="$4" settings="$5" stream="$6"
  local sniff allocate ib resp
  sniff='{"enabled":true,"destOverride":["http","tls","quic"],"metadataOnly":false,"routeOnly":false}'
  allocate='{"strategy":"always","refresh":5,"concurrency":3}'
  ib="$(jq -nc --arg tag "$tag" --argjson port "$port" --arg p "$proto" --arg r "$remark" \
    --arg s "$settings" --arg st "$stream" --arg sn "$sniff" --arg al "$allocate" \
    '{up:0, down:0, total:0, remark:$r, enable:true, expiryTime:0, listen:"",
      port:$port, protocol:$p, settings:$s, streamSettings:$st,
      sniffing:$sn, allocate:$al, tag:$tag}')"
  resp="$(add_inbound_api "$ib")"
  if echo "$resp" | jq -e '.success==true' >/dev/null 2>&1; then
    info "入站创建成功：${remark}，端口 ${port}"
  else
    error "入站创建失败：$resp"
    return 1
  fi
}

ask_common() {
  # 输出：REMARK PORT，通过全局变量返回
  read -r -p "节点备注（客户看到的名字，默认 xigu-node）： " REMARK
  REMARK="${REMARK:-xigu-node}"
  read -r -p "监听端口（回车随机分配）： " PORT
  PORT="${PORT:-$(random_port)}"
}

# 证书检查（TLS/CDN 类协议用）
check_cert() {
  local cert_data cnt
  cert_data="$(api_get "${BASE}/panel/cert/list")"
  cnt="$(echo "$cert_data" | jq '(.obj // []) | length' 2>/dev/null || echo 0)"
  if [ "$cnt" -eq 0 ]; then
    warn "面板中还没有任何域名证书"
    echo -e "  请先在面板 ${BOLD}证书管理${NC} 中为域名申请证书（域名已解析到本机后可一键申请）"
    read -r -p "申请完成后按回车继续，输入 q 取消： " done
    [ "${done:-}" = "q" ] && return 1
    check_cert
    return $?
  fi
  info "检测到面板已有 ${cnt} 个证书，入站将自动匹配"
}

gen_vless_reality() {
  api_login || return 1
  local REMARK PORT; ask_common
  local uuid keys priv pub sid sub tag email dest sname
  uuid="$(gen_uuid)"
  keys="$(x25519_keys)" || return 1
  priv="${keys%% *}"; pub="${keys##* }"
  sid="$(openssl rand -hex 8)"
  sub="$(openssl rand -hex 8)"
  tag="vless-reality-$(openssl rand -hex 3)"
  email="${REMARK}-$(openssl rand -hex 2)"

  # 随机选一个大厂伪装目标
  local dests=("www.microsoft.com:443" "www.apple.com:443" "www.amazon.com:443" "dl.google.com:443" "www.cloudflare.com:443")
  dest="${dests[RANDOM % ${#dests[@]}]}"
  sname="${dest%%:*}"

  local settings stream
  settings="$(jq -nc --arg uuid "$uuid" --arg email "$email" --arg sub "$sub" \
    '{clients:[{id:$uuid, email:$email, flow:"xtls-rprx-vision", limitIp:0, totalGB:0,
      expiryTime:0, enable:true, tgId:"", subId:$sub, reset:0}],
      decryption:"none", fallbacks:[]}')"
  stream="$(jq -nc --arg priv "$priv" --arg pub "$pub" --arg sid "$sid" \
    --arg dest "$dest" --arg sn "$sname" \
    '{network:"tcp", security:"reality",
      realitySettings:{show:false, xver:0, dest:$dest, serverNames:[$sn],
        privateKey:$priv, minClient:"", maxClient:"", maxTimediff:0,
        shortIds:[$sid], settings:{publicKey:$pub, fingerprint:"chrome"},
        fingerprint:"chrome"}}')"
  build_and_add "$tag" "$PORT" vless "$REMARK" "$settings" "$stream"
}

gen_ws_tls() {
  # $1 = vless / vmess
  local proto="$1"
  api_login || return 1
  check_cert || return 1
  local REMARK PORT; ask_common
  local domain path tag email
  read -r -p "CDN 域名（如 cdn.example.com，已接入 Cloudflare 并开启小云朵）： " domain
  [ -z "$domain" ] && { error "域名不能为空"; return 1; }
  path="/xigu-$(openssl rand -hex 4)"
  tag="${proto}-ws-$(openssl rand -hex 3)"
  email="${REMARK}-$(openssl rand -hex 2)"

  local settings stream
  if [ "$proto" = "vless" ]; then
    local uuid; uuid="$(gen_uuid)"
    settings="$(jq -nc --arg uuid "$uuid" --arg email "$email" \
      '{clients:[{id:$uuid, email:$email, flow:"", limitIp:0, totalGB:0,
        expiryTime:0, enable:true, tgId:"", subId:"", reset:0}],
        decryption:"none", fallbacks:[]}')"
  else
    local uuid; uuid="$(gen_uuid)"
    settings="$(jq -nc --arg uuid "$uuid" --arg email "$email" \
      '{clients:[{id:$uuid, security:"auto", email:$email}],
        disableInsecureEncryption:false}')"
  fi
  stream="$(jq -nc --arg domain "$domain" --arg path "$path" \
    '{network:"ws", security:"tls",
      tlsSettings:{serverName:$domain, minVersion:"1.2", maxVersion:"1.3",
        certificates:[], alpn:["h2","http/1.1"]},
      wsSettings:{path:$path, host:$domain, headers:{}}}')"
  build_and_add "$tag" "$PORT" "$proto" "$REMARK" "$settings" "$stream"
  echo -e "  ${YELLOW}CDN 提示：Cloudflare  SSL/TLS 模式设为 Full（严格），WebSocket 无需额外规则${NC}"
}

gen_trojan() {
  api_login || return 1
  check_cert || return 1
  local REMARK PORT; ask_common
  local domain pw tag email
  read -r -p "域名（面板已申请该域名证书，直接回车用服务器 IP 自签）： " domain
  domain="${domain:-}"
  pw="$(openssl rand -hex 12)"
  tag="trojan-$(openssl rand -hex 3)"
  email="${REMARK}-$(openssl rand -hex 2)"
  local settings stream
  settings="$(jq -nc --arg pw "$pw" --arg email "$email" \
    '{clients:[{password:$pw, email:$email, flow:"", limitIp:0, totalGB:0,
      expiryTime:0, enable:true, tgId:"", subId:"", reset:0}], fallbacks:[]}')"
  stream="$(jq -nc --arg domain "$domain" \
    '{network:"tcp", security:"tls",
      tlsSettings:{serverName:$domain, minVersion:"1.2", maxVersion:"1.3",
        certificates:[], alpn:["h2","http/1.1"]}}')"
  build_and_add "$tag" "$PORT" trojan "$REMARK" "$settings" "$stream"
}

gen_hysteria2() {
  api_login || return 1
  local REMARK PORT; ask_common
  local pw tag email
  pw="$(openssl rand -hex 12)"
  tag="hy2-$(openssl rand -hex 3)"
  email="${REMARK}-$(openssl rand -hex 2)"
  local settings stream
  settings="$(jq -nc --arg pw "$pw" --arg email "$email" \
    '{clients:[{password:$pw, email:$email}], masquerade:""}')"
  stream="$(jq -nc \
    '{security:"tls",
      tlsSettings:{serverName:"", minVersion:"1.2", maxVersion:"1.3",
        certificates:[], alpn:["h3"]}}')"
  build_and_add "$tag" "$PORT" hysteria2 "$REMARK" "$settings" "$stream"
}

gen_ss2022() {
  api_login || return 1
  local REMARK PORT; ask_common
  local key tag method
  key="$(openssl rand -base64 32)"
  tag="ss-$(openssl rand -hex 3)"
  method="2022-blake3-aes-256-gcm"
  local settings stream
  settings="$(jq -nc --arg key "$key" --arg m "$method" \
    '{clients:null, method:$m, password:$key, network:"tcp,udp", ivCheck:false}')"
  stream='{"network":"tcp","security":"none"}'
  build_and_add "$tag" "$PORT" shadowsocks "$REMARK" "$settings" "$stream"
}

#==================== 节点链接提取 ====================
dump_links() {
  api_login || return 1
  local host; host="$(public_ip)"
  [ -z "$host" ] && { error "无法获取服务器公网 IP"; return 1; }
  local data; data="$(list_inbounds_raw)"
  : > "$LINK_FILE"

  echo "$data" | jq -c '.obj[]' | while read -r ib; do
    local proto port remark settings stream enc links
    proto="$(echo "$ib" | jq -r '.protocol')"
    port="$(echo "$ib" | jq -r '.port')"
    remark="$(echo "$ib" | jq -r '.remark')"
    settings="$(echo "$ib" | jq -r '.settings')"
    stream="$(echo "$ib" | jq -r '.streamSettings')"
    enc="$(jq -rn --arg x "$remark" '$x|@uri')"
    links=""

    case "$proto" in
      vless)
        local id sec
        id="$(echo "$settings" | jq -r '.clients[0].id')"
        sec="$(echo "$stream" | jq -r '.security')"
        if [ "$sec" = "reality" ]; then
          local pbk sni sid fp flow
          pbk="$(echo "$stream" | jq -r '.realitySettings.settings.publicKey')"
          sni="$(echo "$stream" | jq -r '.realitySettings.serverNames[0]')"
          sid="$(echo "$stream" | jq -r '.realitySettings.shortIds[0]')"
          fp="$(echo "$stream" | jq -r '.realitySettings.fingerprint')"
          flow="$(echo "$settings" | jq -r '.clients[0].flow // ""')"
          links="vless://${id}@${host}:${port}?encryption=none&flow=${flow}&security=reality&sni=${sni}&fp=${fp}&pbk=${pbk}&sid=${sid}&type=tcp#${enc}"
        else
          local sni wpath whost
          sni="$(echo "$stream" | jq -r '.tlsSettings.serverName')"
          wpath="$(echo "$stream" | jq -r '.wsSettings.path | @uri')"
          whost="$(echo "$stream" | jq -r '.wsSettings.host')"
          links="vless://${id}@${host}:${port}?encryption=none&security=tls&sni=${sni}&type=ws&path=${wpath}&host=${whost}#${enc}"
        fi
        ;;
      vmess)
        local id sni wpath whost vjson
        id="$(echo "$settings" | jq -r '.clients[0].id')"
        sni="$(echo "$stream" | jq -r '.tlsSettings.serverName')"
        wpath="$(echo "$stream" | jq -r '.wsSettings.path')"
        whost="$(echo "$stream" | jq -r '.wsSettings.host')"
        vjson="$(jq -nc --arg add "$host" --arg port "$port" --arg id "$id" \
          --arg ps "$remark" --arg net "ws" --arg host "$whost" --arg path "$wpath" --arg sni "$sni" \
          '{v:"2", ps:$ps, add:$add, port:$port, id:$id, aid:"0", scy:"auto",
            net:$net, type:"none", host:$host, path:$path, tls:"tls", sni:$sni}')"
        links="vmess://$(printf '%s' "$vjson" | base64 -w0)"
        ;;
      trojan)
        local pw sni
        pw="$(echo "$settings" | jq -r '.clients[0].password')"
        sni="$(echo "$stream" | jq -r '.tlsSettings.serverName // ""')"
        [ -z "$sni" ] && sni="$host"
        links="trojan://${pw}@${host}:${port}?security=tls&sni=${sni}&fp=chrome#${enc}"
        ;;
      hysteria2)
        local pw sni
        pw="$(echo "$settings" | jq -r '.clients[0].password')"
        sni="$(echo "$stream" | jq -r '.tlsSettings.serverName // ""')"
        links="hy2://${pw}@${host}:${port}?security=tls&sni=${sni}&insecure=1#${enc}"
        ;;
      shadowsocks)
        local m pw ui
        m="$(echo "$settings" | jq -r '.method')"
        pw="$(echo "$settings" | jq -r '.password')"
        ui="$(jq -rn --arg m "$m" --arg p "$pw" '($m+":"+$p) | @base64')"
        links="ss://${ui}@${host}:${port}#${enc}"
        ;;
    esac
    if [ -n "$links" ]; then
      echo "# ${remark} (${proto})" >> "$LINK_FILE"
      echo "$links" >> "$LINK_FILE"
      echo >> "$LINK_FILE"
    fi
  done

  echo
  info "节点链接如下（已同步保存到 ${LINK_FILE}，随时可 cat 查看复制）："
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  cat "$LINK_FILE"
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
}

#==================== 时区 ====================
set_timezone() {
  echo
  echo "  1) Asia/Shanghai 北京时间"
  echo "  2) Asia/Singapore 新加坡"
  echo "  3) America/New_York 美东"
  echo "  4) America/Los_Angeles 美西"
  echo "  5) Europe/London 伦敦"
  echo "  6) America/Santiago 智利"
  read -r -p "选择 [1-6]： " tzch
  local tz
  case "$tzch" in
    1) tz="Asia/Shanghai" ;; 2) tz="Asia/Singapore" ;;
    3) tz="America/New_York" ;; 4) tz="America/Los_Angeles" ;;
    5) tz="Europe/London" ;; 6) tz="America/Santiago" ;;
    *) error "无效选项"; return 1 ;;
  esac
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone "$tz"
  else
    ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
  fi
  info "时区已切换为：$tz，当前时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
}

#==================== 广告子菜单 ====================
ad_menu() {
  while :; do
    echo
    echo -e "${BOLD}系谷官方网站（链接单独成行，方便复制）：${NC}"
    echo
    echo -e "  ${SITE_CN_NAME}："
    echo -e "  ${GREEN}${SITE_CN_URL}${NC}"
    echo
    echo -e "  ${SITE_FY_NAME}："
    echo -e "  ${GREEN}${SITE_FY_URL}${NC}"
    echo
    echo -e "  ${SITE_SZ_NAME}："
    echo -e "  ${GREEN}${SITE_SZ_URL}${NC}"
    echo
    echo -e "  ${SITE_IP_NAME}："
    echo -e "  ${GREEN}${SITE_IP_URL}${NC}"
    echo
    read -r -p "按回车返回主菜单： " _
    return
  done
}

#==================== 主菜单 ====================
main_menu() {
  while :; do
    show_banner
    echo -e "${BOLD}请选择功能：${NC}"
    echo "  1. 系谷官方网站（广告链接）"
    echo "  2. 3XUI 面板原生管理（改端口/用户名/密码）"
    echo "  3. 一键生成节点"
    echo "  4. 添加落地 IP（Socks5 住宅代理）"
    echo "  5. 节点绑定落地"
    echo "  6. 查看绑定关系"
    echo "  7. 查看全部节点链接（复制/导入）"
    echo "  8. 时区设置"
    echo "  9. 重启面板"
    echo "  0. 退出"
    read -r -p "输入选项 [0-9]： " op
    case "$op" in
      1) ad_menu ;;
      2)
        if command -v x-ui >/dev/null 2>&1; then x-ui; else error "未找到 x-ui 命令"; fi
        ;;
      3)
        echo
        echo -e "${BOLD}选择要生成的协议：${NC}"
        echo "  1) VLESS + Reality（直连抗封锁，推荐）"
        echo "  2) VLESS + WS + TLS（Cloudflare CDN 中转）"
        echo "  3) VMess + WS + TLS（CDN 中转）"
        echo "  4) Trojan + TLS"
        echo "  5) Hysteria2（高速 UDP）"
        echo "  6) Shadowsocks-2022"
        read -r -p "输入 [1-6]： " pp
        case "$pp" in
          1) gen_vless_reality ;;
          2) gen_ws_tls vless ;;
          3) gen_ws_tls vmess ;;
          4) gen_trojan ;;
          5) gen_hysteria2 ;;
          6) gen_ss2022 ;;
          *) warn "无效选项" ;;
        esac
        ;;
      4) add_landing ;;
      5) bind_landing ;;
      6) show_bindings ;;
      7) dump_links ;;
      8) set_timezone ;;
      9) systemctl restart x-ui && info "面板已重启" ;;
      0) echo "再见"; exit 0 ;;
      *) warn "无效选项，请重新输入" ;;
    esac
    echo
    read -r -p "按回车返回主菜单..." _
  done
}

# 入口：--banner 只显示标识（MOTD 用），无参数进交互菜单
if [ "${1:-}" = "--banner" ]; then
  show_banner
else
  main_menu
fi
XGEOF

  chmod +x "$XIGU_BIN"

  # SSH 登录自动显示 banner
  cat > "$XIGU_PROFILE" <<'PROFEOF'
# 系谷 Xigu Tech | Network 登录标识
if [ -x /usr/local/bin/xigu ] && [ -n "${SSH_CONNECTION:-}" ]; then
  /usr/local/bin/xigu --banner
fi
PROFEOF
  chmod 644 "$XIGU_PROFILE"
  info "系谷定制文件部署完成"
}

#======================= 主流程 =======================
echo
echo -e "${CYAN}${BOLD}================================================================${NC}"
echo -e "${CYAN}${BOLD}  系谷 Xigu · Xigu Tech | Network  3XUI 定制安装脚本 v${XIGU_VERSION}${NC}"
echo -e "${CYAN}${BOLD}================================================================${NC}"
echo

install_deps
install_xui
choose_timezone
deploy_xigu

# 读取面板信息用于结尾展示
PUB_IP="$(curl -4 -s --max-time 8 https://api.ip.sb/ip 2>/dev/null \
  || curl -4 -s --max-time 8 https://ipinfo.io/ip 2>/dev/null || echo "")"
PUB_IP="$(echo "$PUB_IP" | tr -d '[:space:]')"
WEB_PORT=""; WEB_USER=""
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$XUI_DB" ]; then
  WEB_PORT="$(sqlite3 "$XUI_DB" "select value from settings where key='webPort';" 2>/dev/null || true)"
  WEB_USER="$(sqlite3 "$XUI_DB" "select value from settings where key='username';" 2>/dev/null || true)"
fi

echo
"$XIGU_BIN" --banner
info "全部安装完成"
echo
echo -e "  面板地址：${BOLD}https://${PUB_IP:-服务器公网IP}:${WEB_PORT:-面板端口}${NC}"
echo -e "  面板用户名：${WEB_USER:-admin}（密码在安装 3x-ui 时已提示，忘记可在 x-ui 菜单重置）"
echo -e "  面板语言：登录后在页面右上角选择 ${BOLD}简体中文${NC}"
echo -e "  节点链接文件：${BOLD}${LINK_FILE}${NC}"
echo
echo -e "  ${YELLOW}以后在服务器上随时输入 ${BOLD}xigu${NC} ${YELLOW}即可打开管理菜单：${NC}"
echo -e "  ${YELLOW}一键生成协议 / 添加落地 IP / 绑定中转 / 复制节点链接 / 改时区${NC}"
echo
