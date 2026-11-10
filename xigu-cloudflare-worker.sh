#!/usr/bin/env bash
#================================================================
# 系谷 Xigu Tech | Network
# 主题：Cloudflare Workers 免费节点（VLESS over WebSocket）
# 本脚本不改动服务器，只生成可直接粘贴的 worker.js 和节点链接，
# 并给出 Cloudflare 全流程中英文操作说明
# EN: Generates a ready-to-paste Worker script and full bilingual setup guide
# 用法 / Usage: bash xigu-cloudflare-worker.sh
#================================================================
set -uo pipefail

BRAND_CN="系谷"
BRAND_EN="Xigu Tech | Network"
SITE_CN_URL="https://cn.jige.us";  SITE_CN_NAME="家庭住宅顶级线路 / Residential Proxies"
SITE_FY_URL="https://fy.jige.us";  SITE_FY_NAME="在线翻译 / Translator"
SITE_SZ_URL="https://sz.jige.us";  SITE_SZ_NAME="全球在线时钟 / World Clock"
SITE_IP_URL="https://ipip.jige.us"; SITE_IP_NAME="IP 检查工具 / IP Checker"
LINK_FILE="/root/xigu-links.txt"
WORKER_FILE="/root/xigu-worker.js"

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
  echo -e "  ${BOLD}本脚本 / This script: Cloudflare Workers 免费节点${NC}"
  echo -e "  中文：利用 Cloudflare Workers 免费额度搭建 VLESS 节点，零服务器成本，隐藏真实 IP。"
  echo -e "  EN: Build a free VLESS node on Cloudflare Workers; zero server cost, hides your real IP."
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo -e "  [1] ${SITE_CN_NAME}  ${GREEN}${SITE_CN_URL}${NC}"
  echo -e "  [2] ${SITE_FY_NAME}  ${GREEN}${SITE_FY_URL}${NC}"
  echo -e "  [3] ${SITE_SZ_NAME}  ${GREEN}${SITE_SZ_URL}${NC}"
  echo -e "  [4] ${SITE_IP_NAME}  ${GREEN}${SITE_IP_URL}${NC}"
  echo -e "${CYAN}----------------------------------------------------------------${NC}"
  echo
}

[ "$(id -u)" -eq 0 ] || { error "请用 root 运行 / Please run as root"; exit 1; }
show_banner

#==================== 生成 UUID ====================
read -r -p "设置客户端 UUID（回车自动生成 / Enter for random）： " UUID
UUID="${UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "")}"
[ -z "$UUID" ] && { error "无法生成 UUID，请手动输入"; exit 1; }
info "UUID: ${GREEN}${UUID}${NC}"

#==================== 生成 worker.js ====================
cat > "$WORKER_FILE" <<'WKEOF'
// ============================================================
// 系谷 Xigu Tech | Network — VLESS over WebSocket for Cloudflare Workers
// 部署方式：粘贴到 Cloudflare Worker 后保存部署即可
// ============================================================
import { connect } from 'cloudflare:sockets';

const USER_ID = '__XIGU_UUID__';

export default {
  async fetch(request) {
    const upgrade = (request.headers.get('Upgrade') || '').toLowerCase();
    if (upgrade !== 'websocket') {
      return new Response('Xigu VLESS Worker is running. Connect with a VLESS client.', { status: 200 });
    }
    const pair = new WebSocketPair();
    pair[1].accept();
    handleVless(pair[1], USER_ID).catch(() => pair[1].close());
    return new Response(null, { status: 101, webSocket: pair[0] });
  },
};

async function handleVless(ws, userId) {
  let remote = null;
  let first = true;

  ws.addEventListener('message', async (event) => {
    const data = new Uint8Array(await event.data.arrayBuffer());
    if (first) {
      first = false;
      let at = 1; // 跳过 VLESS 版本字节 / skip version
      const port = ((data[at] & 0x1f) << 8) | data[at + 1];
      at += 2;
      const atype = data[at++];
      let address = '';
      if (atype === 1) {
        address = data.slice(at, at + 4).join('.');
        at += 4;
      } else if (atype === 2) {
        const len = data[at++];
        address = new TextDecoder().decode(data.slice(at, at + len));
        at += len;
      } else if (atype === 3) {
        address = [...data.slice(at, at + 16)]
          .map((b) => b.toString(16).padStart(2, '0')).join(':');
        at += 16;
      }
      // VLESS 请求附加选项 / option blocks until terminator
      for (;;) {
        const b = data[at];
        const length = b & 0x0f;
        if ((b >> 4) === 0) { at += 1; break; }
        at += 1 + length;
      }
      remote = connect(`${address}:${port}`);
      pumpRemote(remote, ws);
      if (data.length > at) remote.write(data.slice(at));
    } else if (remote) {
      remote.write(data);
    }
  });

  ws.addEventListener('close', () => { if (remote) remote.close(); });
}

async function pumpRemote(remote, ws) {
  try {
    for await (const chunk of remote.readable) ws.send(chunk);
    ws.close();
  } catch (e) {
    ws.close();
  }
}
WKEOF

sed -i "s#__XIGU_UUID__#${UUID}#g" "$WORKER_FILE"
info "Worker 代码已生成 / Saved: ${BOLD}${WORKER_FILE}${NC}"

#==================== 中英文操作说明 ====================
echo
echo -e "${CYAN}${BOLD}================  中文操作步骤  ================${NC}"
cat <<'CNGUIDE'
  1. 打开 https://dash.cloudflare.com 注册并登录（免费账号即可）。
  2. 左侧菜单进入「Workers 和 Pages」→ 点「创建」→ 选「创建 Worker」→ 起个名字 → 点「部署」。
  3. 部署后点「编辑代码」，把 /root/xigu-worker.js 的全部内容粘贴进去，覆盖默认代码，点「部署」。
  4. 绑定入口（二选一）：
     a. 直接用 workers.dev 免费子域名（创建时分配，形如 你的名字.账号.workers.dev）；
     b. 自定义域名：在该 Worker 点「设置 → 域和路由 → 添加自定义域」，填自己的域名（如 vless.example.com），
        域名托管在 Cloudflare 时会自动解析，无需小云朵设置。
  5. 客户端用本脚本末尾生成的 VLESS 链接导入即可，端口 443，TLS+WebSocket。
  6. 优选（可选）：客户端可把连接地址换成 Cloudflare 优选 IP/优选域名，
     SNI 与 Host 保持 Worker 域名不变；搜索「Cloudflare 优选IP」可获取最新地址。
CNGUIDE

echo
echo -e "${CYAN}${BOLD}================  English Steps  ================${NC}"
cat <<'ENGUIDE'
  1. Go to https://dash.cloudflare.com and sign up (free plan is enough).
  2. Open "Workers & Pages" -> "Create" -> "Create Worker" -> name it -> "Deploy".
  3. Click "Edit code", paste everything from /root/xigu-worker.js to replace the default, then "Deploy".
  4. Pick an entry point:
     a. Use the free workers.dev subdomain (assigned automatically, e.g. name.account.workers.dev);
     b. Or add a custom domain: Worker -> Settings -> Domains & Routes -> Add Custom Domain
        (automatic DNS when the domain is managed on Cloudflare).
  5. Import the VLESS link printed below into your client; port 443, TLS + WebSocket.
  6. Optional optimization: replace the connect address with a Cloudflare preferred IP,
     keeping SNI/Host as the Worker domain; search "Cloudflare preferred IP" for current lists.
ENGUIDE

#==================== 生成链接 ====================
echo
read -r -p "输入你的 Worker 访问域名（workers.dev 子域名或自定义域名）： " WDOMAIN
[ -z "$WDOMAIN" ] && { warn "未输入域名，链接稍后可自行拼接"; WDOMAIN="你的Worker域名"; }
REMARK="xigu-cf-worker-$(openssl rand -hex 2 2>/dev/null || echo 0000)"
ENC="$(jq -rn --arg x "$REMARK" '$x|@uri' 2>/dev/null || echo "$REMARK")"
LINK="vless://${UUID}@${WDOMAIN}:443?encryption=none&security=tls&type=ws&sni=${WDOMAIN}&host=${WDOMAIN}&path=%2F&fp=chrome#${ENC}"

{
  echo "# ${REMARK} / Cloudflare Worker VLESS / $(date '+%F %T')"
  echo "$LINK"; echo
} >> "$LINK_FILE"

echo
echo -e "${CYAN}================================================================${NC}"
echo -e "  Worker 文件 / File: ${WORKER_FILE}"
echo -e "  UUID: ${UUID}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"
echo -e "  ${GREEN}${LINK}${NC}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"
echo -e "  链接已保存到 / Saved: ${BOLD}${LINK_FILE}${NC}"
echo -e "  支持客户端 / Clients: v2rayNG, NekoBox, Shadowrocket, Streisand, Clash Meta"
echo
