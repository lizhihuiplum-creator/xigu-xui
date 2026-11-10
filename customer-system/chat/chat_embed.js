/* 系谷 · 统一客服访客组件（全站通用，自包含，无外部依赖）
   页面加载前可配置：
   window.__XG_SITE = 'cn'|'ipip'|'fy'|'sz'   来源站点（默认 cn）
   window.__XG_HUB  = 'https://cn.jige.us'      中枢地址
   window.__XG_POS  = 'right'|'left'           悬浮位置（默认 right）
   登录用户标识（由各站点登录逻辑同步，用于后台按用户统计）：
   window.__XG_UID  = 注册用户 id（数字）
   window.__XG_UNAME = 注册用户名（字符串）
*/
(function () {
  'use strict';
  if (window.__XG_CHAT_LOADED) return;
  window.__XG_CHAT_LOADED = true;

  var SITE = (window.__XG_SITE || 'cn');
  var HUB = (window.__XG_HUB || 'https://cn.jige.us').replace(/\/+$/, '');
  var POS = (window.__XG_POS === 'left') ? 'left' : 'right';
  var BOTTOM = /^\d{1,4}px$/.test(window.__XG_BOTTOM) ? window.__XG_BOTTOM : '24px';
  var MYLANG = (navigator.language || 'en').toLowerCase();
  var MYLANG_SHORT = MYLANG.split('-')[0];
  var isZh = MYLANG_SHORT === 'zh';
  var MYTZ = '';
  try { MYTZ = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (e) {}
  function zHM(tz) {
    try {
      return new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date());
    } catch (e) { return '--:--'; }
  }
  function zFull(tz) {
    try {
      return new Intl.DateTimeFormat(MYLANG, { timeZone: tz, month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date());
    } catch (e) { return ''; }
  }
  function tzCityEn(tz) {
    if (!tz) return '';
    if (/^Etc\/|^UTC$/.test(tz)) return tz.replace('Etc/', '');
    var seg = tz.split('/').pop().replace(/_/g, ' ');
    return seg;
  }
  var localLabelCache = null;
  function refreshLocalLabels() {
    var en = tzCityEn(MYTZ);
    var zhEl = document.getElementById('xgLocalZh');
    var enEl = document.getElementById('xgLocalEn');
    if (!en) { zhEl.textContent = isZh ? '本地' : 'Local'; enEl.textContent = 'Local'; return; }
    if (localLabelCache && localLabelCache.tz === MYTZ) { zhEl.textContent = localLabelCache.zh; enEl.textContent = localLabelCache.en; return; }
    post({ action: 'translate', q: en, sl: 'en', tl: 'zh-CN' }).then(function (j) {
      var zh = (j && j.code === 200 && j.text) ? j.text : en;
      localLabelCache = { tz: MYTZ, zh: zh, en: en };
      zhEl.textContent = zh; enEl.textContent = en;
    });
  }

  /* ---------- vid（先读旧 cookie，再 localStorage，否则生成） ---------- */
  function readCookie(n) {
    var m = document.cookie.match(new RegExp('(?:^|; )' + n + '=([^;]*)'));
    return m ? decodeURIComponent(m[1]) : '';
  }
  function genVid() {
    var s = '';
    for (var i = 0; i < 32; i++) s += '0123456789abcdef'.charAt(Math.floor(Math.random() * 16));
    return s;
  }
  var vid = readCookie('xg_vid') || '';
  if (!/^[a-f0-9]{16,40}$/.test(vid)) {
    try { vid = localStorage.getItem('xg_vid') || ''; } catch (e) { vid = ''; }
  }
  if (!/^[a-f0-9]{16,40}$/.test(vid)) { vid = genVid(); }
  try { localStorage.setItem('xg_vid', vid); } catch (e) {}
  document.cookie = 'xg_vid=' + vid + '; path=/; max-age=31536000; SameSite=Lax';

  /* ---------- 登录用户标识（动态读取，登录/退出后下一次心跳自动生效） ---------- */
  function curUid() {
    var u = window.__XG_UID;
    if (u === undefined || u === null || u === '' || isNaN(Number(u)) || Number(u) <= 0) return 0;
    return Number(u);
  }
  function curUname() {
    var n = window.__XG_UNAME;
    return (n === undefined || n === null) ? '' : String(n).slice(0, 60);
  }
  var lastBeatAt = 0; // 上次心跳时间戳，用于计算 dt

  var lastId = 0, panelOpen = false, titleTimer = null, origTitle = document.title, clearToken = '', firstPoll = true;
  var pendingSends = []; // 发送中（等待 send 返回）的乐观气泡，用于 poll 提前拉回时收敛去重
  function findPending(body) {
    for (var i = 0; i < pendingSends.length; i++) { if (pendingSends[i].body === body) return pendingSends[i]; }
    return null;
  }
  function removePending(body) {
    for (var i = 0; i < pendingSends.length; i++) { if (pendingSends[i].body === body) { pendingSends.splice(i, 1); return; } }
  }

  /* ---------- 注入样式 ---------- */
  var css = document.createElement('style');
  css.textContent = [
    '.xg-fab{position:fixed;bottom:24px;z-index:2147483000;display:flex;align-items:center;gap:8px;',
    'background:linear-gradient(135deg,#2563eb,#1d4ed8);color:#fff;border:none;border-radius:24px;',
    'padding:11px 18px;font-size:14px;font-weight:600;cursor:pointer;box-shadow:0 6px 18px rgba(37,99,235,.4);font-family:inherit;}',
    '.xg-fab .xg-badge{background:#ef4444;color:#fff;border-radius:10px;font-size:11px;padding:1px 7px;}',
    '.xg-panel{position:fixed;bottom:24px;z-index:2147483001;width:340px;max-width:calc(100vw - 24px);height:460px;max-height:calc(100vh - 40px);',
    'background:#fff;color:#0f172a;border-radius:14px;display:flex;flex-direction:column;overflow:hidden;',
    'box-shadow:0 12px 40px rgba(2,6,23,.28);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;}',
    '.xg-panel[hidden],.xg-fab[hidden]{display:none !important;}',
    '.xg-min{min-width:40px;min-height:40px;display:flex;align-items:center;justify-content:center;font-size:22px !important;}',
'.xg-panel.xg-alert{border:2px solid #ffcf3f;animation:xgPulse 1s ease-in-out 3;}',
    '@keyframes xgPulse{0%,100%{box-shadow:0 0 0 rgba(255,207,63,0);}50%{box-shadow:0 0 26px rgba(255,207,63,.95);}}',
    // 未对话时悬浮入口的呼吸引导，让客户一进来就注意到
    '.xg-fab.xg-fab-pulse{animation:xgFabPulse 2.2s ease-in-out infinite;}',
    '@keyframes xgFabPulse{0%,100%{box-shadow:0 6px 18px rgba(37,99,235,.4);transform:scale(1);}50%{box-shadow:0 8px 28px rgba(37,99,235,.9);transform:scale(1.05);}}',
    // 悬浮入口旁的引导小气泡
    '.xg-hint{position:fixed;z-index:2147483000;background:#fff;color:#1d4ed8;font-size:12px;font-weight:600;padding:8px 12px;border-radius:10px;box-shadow:0 6px 20px rgba(2,6,23,.18);max-width:200px;}',
    '.xg-hint:after{content:"";position:absolute;bottom:-6px;' + (POS === 'left' ? 'left:24px;border-left:6px solid transparent;border-right:6px solid transparent;border-top:7px solid #fff;' : 'right:24px;border-left:6px solid transparent;border-right:6px solid transparent;border-top:7px solid #fff;') + '}',
    '.xg-hint b{display:block;margin-top:2px;cursor:pointer;}',
    '.xg-hint .xg-hint-x{position:absolute;top:2px;right:6px;color:#94a3b8;cursor:pointer;font-size:14px;}',
    '.xg-head{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;}',
    '.xg-head b{font-size:14px;}.xg-head button{background:transparent;border:none;color:#fff;font-size:18px;cursor:pointer;line-height:1;padding:0 4px;}',
    '.xg-msgs{flex:1;overflow-y:auto;padding:14px;background:#f8fafc;display:flex;flex-direction:column;gap:10px;}',
    '.xg-row{display:flex;flex-direction:column;max-width:86%;}',
    '.xg-row.admin{align-self:flex-end;align-items:flex-end;}.xg-row.visitor{align-self:flex-start;align-items:flex-start;}',
    '.xg-bubble{border-radius:12px;padding:8px 11px;font-size:13px;line-height:1.5;white-space:pre-wrap;word-break:break-word;}',
    '.xg-row.admin .xg-bubble{background:#2563eb;color:#fff;border-bottom-right-radius:3px;}',
    '.xg-row.visitor .xg-bubble{background:#e2e8f0;color:#0f172a;border-bottom-left-radius:3px;}',
    '.xg-meta{font-size:10px;color:#94a3b8;margin-top:3px;display:flex;gap:6px;align-items:center;}',
    '.xg-tr{background:none;border:none;color:#2563eb;font-size:10px;cursor:pointer;padding:0;}',
    '.xg-tr:disabled{color:#94a3b8;}',
    '.xg-tr-out{margin-top:4px;font-size:12px;color:#047857;background:#ecfdf5;border-radius:8px;padding:5px 8px;}',
    '.xg-input{display:flex;gap:6px;padding:10px;border-top:1px solid #e2e8f0;background:#fff;}',
    '.xg-input input{flex:1;border:1px solid #cbd5e1;border-radius:8px;padding:9px 10px;font-size:13px;min-width:0;}',
    '.xg-input button{background:#2563eb;color:#fff;border:none;border-radius:8px;padding:0 14px;font-size:13px;cursor:pointer;}',
    // 系谷品牌条（正常聊天界面底部）
    '.xg-brandbar{display:flex;align-items:center;gap:8px;padding:8px 12px;background:#f8fafc;border-top:1px solid #e2e8f0;text-decoration:none;}',
    '.xg-brandbar .xg-bb-logo{width:24px;height:24px;border-radius:7px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:11px;flex:none;}',
    '.xg-brandbar .xg-bb-txt{flex:1;min-width:0;}',
    '.xg-brandbar .xg-bb-name{font-size:11.5px;font-weight:700;color:#1e293b;line-height:1.2;}',
    '.xg-brandbar .xg-bb-desc{font-size:10px;color:#64748b;line-height:1.2;margin-top:1px;}',
    '.xg-brandbar .xg-bb-go{font-size:11px;color:#2563eb;font-weight:600;flex:none;}',
    // 品牌欢迎弹窗
    '.xg-welcome{position:fixed;inset:0;z-index:2147483003;background:rgba(2,6,23,.5);display:flex;align-items:center;justify-content:center;padding:20px;}',
    '.xg-welcome[hidden]{display:none !important;}',
    '.xg-welcome .xg-wc-card{width:330px;max-width:100%;background:#fff;border-radius:16px;overflow:hidden;text-align:center;}',
    '.xg-welcome .xg-wc-head{padding:24px 18px 18px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;}',
    '.xg-welcome .xg-wc-logo{width:56px;height:56px;border-radius:15px;background:rgba(255,255,255,.18);margin:0 auto 12px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:22px;}',
    '.xg-welcome .xg-wc-name{font-size:18px;font-weight:700;}',
    '.xg-welcome .xg-wc-sub{font-size:11.5px;opacity:.88;margin-top:3px;}',
    '.xg-welcome .xg-wc-body{padding:18px;}',
    '.xg-welcome .xg-wc-tip{font-size:13px;line-height:1.6;color:#334155;margin-bottom:16px;}',
    '.xg-welcome .xg-wc-btn{width:100%;border:none;background:#0e7a43;color:#fff;font-size:14px;font-weight:600;border-radius:10px;padding:12px;cursor:pointer;}',
    '.xg-welcome .xg-wc-contact{display:flex;gap:8px;margin-top:10px;}',
    '.xg-welcome .xg-wc-contact a{flex:1;text-align:center;font-size:12px;font-weight:600;text-decoration:none;border-radius:8px;padding:9px 6px;border:1px solid #cbd5e1;color:#1d4ed8;}',
    '.xg-empty{color:#94a3b8;font-size:12px;text-align:center;margin:auto;}',
    '.xg-clockstrip{display:flex;justify-content:space-between;gap:8px;background:#eef2ff;font-size:11px;color:#3730a3;padding:8px 12px;}',
    '.xg-cs{display:flex;flex-direction:column;align-items:center;gap:1px;line-height:1.2;}',
    '.xg-cs .xg-cs-zh{font-weight:700;font-size:12px;}',
    '.xg-cs .xg-cs-en{font-size:10px;color:#6366f1;}',
    '.xg-cs b{font-weight:600;font-size:13px;margin-top:2px;}',
    '.xg-typing{align-self:flex-start;background:#e2e8f0;color:#475569;border-radius:12px;padding:8px 12px;font-size:12px;display:none;align-items:center;gap:4px;}',
    '.xg-typing.on{display:flex;}',
    '.xg-typing i{width:6px;height:6px;border-radius:50%;background:#64748b;animation:xgBlink 1s infinite;}',
    '.xg-typing i:nth-child(2){animation-delay:.2s;}.xg-typing i:nth-child(3){animation-delay:.4s;}',
    '@keyframes xgBlink{0%,100%{opacity:.25;}50%{opacity:1;}}',
    '.xg-status{font-size:10px;color:#16a34a;}',
    '.xg-auto{margin-top:4px;font-size:12px;color:#075985;background:#f0f9ff;border:1px solid #bae6fd;border-radius:8px;padding:5px 8px;}',
    '@media (max-width:420px){.xg-panel{width:calc(100vw - 20px);height:70vh;left:10px !important;right:10px !important;bottom:10px !important;}',
    '.xg-fab{padding:9px 14px;font-size:13px;max-width:calc(100vw - 24px);white-space:nowrap;}}',
    // 授权锁定界面
    '.xg-lock{position:fixed;bottom:24px;z-index:2147483002;width:340px;max-width:calc(100vw - 24px);background:#fff;color:#0f172a;',
    'border-radius:14px;overflow:hidden;box-shadow:0 12px 40px rgba(2,6,23,.28);',
    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;}',
    '.xg-lock .xg-lock-head{padding:18px 16px 14px;background:linear-gradient(135deg,#1d4ed8,#2563eb);color:#fff;text-align:center;}',
    '.xg-lock .xg-lock-brand{font-size:17px;font-weight:700;letter-spacing:.5px;}',
    '.xg-lock .xg-lock-sub{font-size:11px;opacity:.85;margin-top:3px;}',
    '.xg-lock .xg-lock-body{padding:16px;}',
    '.xg-lock .xg-lock-tip{font-size:13px;line-height:1.6;color:#334155;text-align:center;margin:0 0 14px;}',
    '.xg-lock .xg-lock-ico{width:46px;height:46px;margin:0 auto 10px;border-radius:50%;background:#fef3c7;color:#b45309;display:flex;align-items:center;justify-content:center;font-size:24px;}',
    '.xg-lock .xg-apply{width:100%;border:none;background:#0e7a43;color:#fff;font-size:14px;font-weight:600;border-radius:9px;padding:11px;cursor:pointer;}',
    '.xg-lock .xg-apply:disabled{opacity:.7;cursor:default;}',
    '.xg-lock .xg-contact{display:flex;gap:8px;margin-top:12px;}',
    '.xg-lock .xg-contact a{flex:1;text-align:center;font-size:12px;font-weight:600;text-decoration:none;border-radius:8px;padding:9px 6px;border:1px solid #cbd5e1;color:#1d4ed8;}',
    '.xg-lock .xg-lock-msg{font-size:12px;color:#0e7a43;text-align:center;margin-top:10px;min-height:14px;}',
    '@media (max-width:420px){.xg-lock{left:10px !important;right:10px !important;width:auto;bottom:10px !important;}}'
  ].join('');
  document.head.appendChild(css);

  /* ---------- 构建 DOM ---------- */
  var launcher = document.createElement('button');
  launcher.type = 'button';
  launcher.className = 'xg-fab';
  launcher.style[POS] = '12px';
  launcher.style.bottom = BOTTOM;
  launcher.innerHTML = '<span aria-hidden="true">💬</span><span>' + (isZh ? 'AI 真人客服' : 'AI Live Agent') + '</span><span class="xg-badge" hidden>0</span>';
  // 管理员完全控制模式：访客侧入口默认隐藏，访客无法主动打开，仅在收到管理员消息时才弹出
  launcher.hidden = true;

  var panel = document.createElement('div');
  panel.className = 'xg-panel';
  panel.style[POS] = '12px';
  panel.hidden = true;
  panel.innerHTML =
    '<div class="xg-head"><b>' + (isZh ? 'AI 真人客服' : 'AI Live Agent') + '</b><button type="button" class="xg-min" aria-label="关闭">&times;</button></div>' +
    '<div class="xg-clockstrip"><span class="xg-cs"><span class="xg-cs-zh">北京</span><span class="xg-cs-en">Beijing</span><b id="xgTzCn">--:--</b></span><span class="xg-cs"><span class="xg-cs-zh" id="xgLocalZh">本地</span><span class="xg-cs-en" id="xgLocalEn">Local</span><b id="xgTzLocal">--:--</b></span></div>' +
    '<div class="xg-msgs"></div>' +
    '<div class="xg-typing" id="xgTyping"><i></i><i></i><i></i><span>' + (isZh ? '客服正在输入…' : 'Support is typing…') + '</span></div>' +
    '<div class="xg-input"><input class="xg-text" placeholder="' + (isZh ? '输入消息，回车发送' : 'Type a message…') + '" autocomplete="off"><button type="button" class="xg-send">' + (isZh ? '发送' : 'Send') + '</button></div>' +
    '<a class="xg-brandbar" href="https://cn.jige.us" target="_blank" rel="noopener">' +
    '<span class="xg-bb-logo">XG</span><span class="xg-bb-txt">' +
    '<span class="xg-bb-name">系谷 Xigu Tech | Network</span>' +
    '<span class="xg-bb-desc">' + (isZh ? '全球网络服务 · 软件定制' : 'Global network services · Custom software') + '</span></span>' +
    '<span class="xg-bb-go">' + (isZh ? '访问官网' : 'Visit') + ' →</span></a>';

  // 悬浮入口旁的引导气泡（首次进入引导客户点击）
  var hint = document.createElement('div');
  hint.className = 'xg-hint';
  hint.hidden = true;
  hint.innerHTML = '<span class="xg-hint-x" aria-hidden="true">&times;</span>' +
    (isZh ? '<div>有问题随时问我～</div><b>点击咨询 AI 真人客服</b>' : '<div>Need help?</div><b>Chat with our AI agent</b>');

  // 授权锁定界面（未在后台开通时展示）
  var lockEl = document.createElement('div');
  lockEl.className = 'xg-lock';
  lockEl.style[POS] = '12px';
  lockEl.hidden = true;
  lockEl.innerHTML =
    '<div class="xg-lock-head"><div class="xg-lock-brand">系谷 Xigu Tech</div>' +
    '<div class="xg-lock-sub">Xigu Tech | Network</div></div>' +
    '<div class="xg-lock-body"><div class="xg-lock-ico">🔒</div>' +
    '<p class="xg-lock-tip">' + (isZh ? '本系统尚未在当前域名开通授权，点击申请后我们会收到通知，审核通过即可使用。' : 'This system is not licensed on this domain yet. Click Apply and we will be notified; it works once approved.') + '</p>' +
    '<button type="button" class="xg-apply">' + (isZh ? '申请使用' : 'Request Access') + '</button>' +
    '<div class="xg-contact"><a href="https://t.me/xigu_support_bot" target="_blank" rel="noopener">Telegram</a>' +
    '<a href="http://wpa.qq.com/msgrd?v=3&uin=1441673277&site=qq&menu=yes" target="_blank" rel="noopener">QQ 1441673277</a></div>' +
    '<p class="xg-lock-msg"></p></div>';

  // 品牌欢迎弹窗（首次加载/安装完成展示一次）
  var welcomeEl = document.createElement('div');
  welcomeEl.className = 'xg-welcome';
  welcomeEl.hidden = true;
  welcomeEl.innerHTML =
    '<div class="xg-wc-card"><div class="xg-wc-head"><div class="xg-wc-logo">XG</div>' +
    '<div class="xg-wc-name">系谷 Xigu Tech</div>' +
    '<div class="xg-wc-sub">Xigu Tech | Network</div></div>' +
    '<div class="xg-wc-body"><p class="xg-wc-tip">' +
    (isZh ? '感谢使用系谷客服系统。本系统由系谷科技提供技术支持，如需开通授权、定制功能或咨询网络服务，请联系我们。'
           : 'Thanks for using the Xigu support system. For licensing, custom features or network services, please contact us.') +
    '</p><button type="button" class="xg-wc-btn">' + (isZh ? '我知道了，开始使用' : 'Got it') + '</button>' +
    '<div class="xg-wc-contact"><a href="https://t.me/xigu_support_bot" target="_blank" rel="noopener">Telegram</a>' +
    '<a href="http://wpa.qq.com/msgrd?v=3&uin=1441673277&site=qq&menu=yes" target="_blank" rel="noopener">QQ 1441673277</a></div>' +
    '</div></div>';

  function attach() {
    document.body.appendChild(launcher);
    document.body.appendChild(panel);
    document.body.appendChild(hint);
    document.body.appendChild(lockEl);
    document.body.appendChild(welcomeEl);
  }
  if (document.body) attach();
  else document.addEventListener('DOMContentLoaded', attach);

  function positionHint() {
    if (hint.hidden) return;
    var fr = launcher.getBoundingClientRect();
    hint.style.bottom = (window.innerHeight - fr.top + 10) + 'px';
    if (POS === 'left') { hint.style.left = '12px'; hint.style.right = 'auto'; }
    else { hint.style.right = '12px'; hint.style.left = 'auto'; }
  }
  function hideHint() { hint.hidden = true; launcher.classList.remove('xg-fab-pulse'); }
  hint.querySelector('.xg-hint-x').addEventListener('click', function (e) { e.stopPropagation(); hideHint(); try { localStorage.setItem('xg_hint_closed', '1'); } catch (err) {} });
  hint.addEventListener('click', function () { openPanel(false); });
  window.addEventListener('resize', positionHint);

  var msgsEl = panel.querySelector('.xg-msgs');
  var textEl = panel.querySelector('.xg-text');
  var badgeEl = launcher.querySelector('.xg-badge');
  var typingEl = panel.querySelector('#xgTyping');
  var tzCnEl = panel.querySelector('#xgTzCn');
  var tzLocalEl = panel.querySelector('#xgTzLocal');
  setInterval(function () {
    tzCnEl.textContent = zHM('Asia/Shanghai');
    tzLocalEl.textContent = MYTZ ? zHM(MYTZ) : zHM('Asia/Shanghai');
  }, 1000);
  refreshLocalLabels();

  /* ---------- 网络 ---------- */
  var xgLocked = false;
  function post(d) {
    return fetch(HUB + '/proactive.php', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(d)
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.license === 'locked') handleLock(j);
      return j;
    }).catch(function () { return null; });
  }

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function nowHM() {
    var d = new Date();
    function p(x) { return (x < 10 ? '0' : '') + x; }
    return p(d.getHours()) + ':' + p(d.getMinutes());
  }

  /* ---------- 渲染消息 ---------- */
  function rowEl(m) {
    var wrap = document.createElement('div');
    wrap.className = 'xg-row ' + (m.sender === 'admin' ? 'admin' : 'visitor');
    if (m.id) wrap.setAttribute('data-mid', m.id);
    var who = m.sender === 'admin' ? (isZh ? '客服' : 'Support') : (isZh ? '我' : 'Me');
    var status = '';
    if (m.sender === 'visitor') {
      status = '<span class="xg-status">' + (m.is_read ? (isZh ? '已读' : 'Read') : (isZh ? '已发送' : 'Sent')) + '</span>';
    }
    wrap.innerHTML =
      '<div class="xg-bubble">' + esc(m.body) + '</div>' +
      '<div class="xg-meta"><span>' + who + ' · ' + esc((m.create_time ? m.create_time.slice(11, 16) : nowHM())) + '</span>' +
      status +
      '<button type="button" class="xg-tr">' + (isZh ? '翻译' : 'Translate') + '</button></div>';
    var btn = wrap.querySelector('.xg-tr');
    btn.addEventListener('click', function () {
      btn.disabled = true; btn.textContent = isZh ? '翻译中…' : '…';
      post({ action: 'translate', q: m.body, sl: 'auto', tl: MYLANG }).then(function (j) {
        var out = wrap.querySelector('.xg-tr-out');
        if (!out) { out = document.createElement('div'); out.className = 'xg-tr-out'; wrap.appendChild(out); }
        if (j && j.code === 200) { out.textContent = j.text; }
        else { out.textContent = isZh ? '翻译暂不可用' : 'Translation unavailable'; }
        btn.disabled = false; btn.textContent = isZh ? '翻译' : 'Translate';
      });
    });
    // 管理员消息：自动翻译成访客语言（双语展示，同语言则不显示）
    if (m.sender === 'admin') {
      post({ action: 'translate', q: m.body, sl: 'auto', tl: MYLANG }).then(function (j) {
        if (j && j.code === 200 && j.text && j.text !== m.body && !wrap.querySelector('.xg-auto')) {
          var a = document.createElement('div'); a.className = 'xg-auto';
          a.textContent = (isZh ? '译文：' : 'Translation: ') + j.text;
          wrap.appendChild(a);
        }
      });
    }
    return wrap;
  }
  function renderAll(list) {
    msgsEl.innerHTML = '';
    if (!list.length) {
      var e = document.createElement('div');
      e.className = 'xg-empty'; e.textContent = isZh ? '还没有对话，发送第一条消息吧' : 'No messages yet';
      msgsEl.appendChild(e);
    } else {
      list.forEach(function (m) { msgsEl.appendChild(rowEl(m)); });
      msgsEl.scrollTop = msgsEl.scrollHeight;
    }
  }
  var history = [];
  function appendMsg(m) {
    var empty = msgsEl.querySelector('.xg-empty'); if (empty) empty.remove();
    var el = rowEl(m);
    msgsEl.appendChild(el); msgsEl.scrollTop = msgsEl.scrollHeight;
    history.push(m);
    return el;
  }

  /* ---------- 提示（声音/标题/徽标） ---------- */
  function beep() {
    try {
      var AC = window.AudioContext || window.webkitAudioContext;
      var ac = new AC(); var o = ac.createOscillator(); var g = ac.createGain();
      o.frequency.value = 880; o.connect(g); g.connect(ac.destination);
      g.gain.setValueAtTime(0.0001, ac.currentTime);
      g.gain.exponentialRampToValueAtTime(0.12, ac.currentTime + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + 0.4);
      o.start(); o.stop(ac.currentTime + 0.42);
      o.onended = function () { ac.close(); };
    } catch (e) {}
  }
  function flashTitle() {
    if (titleTimer) clearInterval(titleTimer);
    var toggle = false;
    titleTimer = setInterval(function () {
      document.title = toggle ? origTitle : (isZh ? '【新消息】系谷客服' : '【New Message】Xigu');
      toggle = !toggle;
    }, 900);
    setTimeout(function () { clearInterval(titleTimer); titleTimer = null; document.title = origTitle; }, 12000);
  }
  function setBadge(n) {
    if (n > 0) { badgeEl.hidden = false; badgeEl.textContent = n; }
    else { badgeEl.hidden = true; }
  }

  function openPanel(alert) {
    panel.hidden = false; panelOpen = true; launcher.hidden = true;
    hideHint();
    if (alert) {
      panel.classList.add('xg-alert');
      setTimeout(function () { panel.classList.remove('xg-alert'); }, 3200);
      beep(); flashTitle();
    }
    setTimeout(function () { textEl.focus(); }, 50);
  }
  function closePanel() {
    panel.hidden = true; panelOpen = false;
    // 管理员完全控制：访客关闭后不显示入口，访客无法自行找回，只能等管理员再次发消息
    launcher.hidden = true;
  }
  launcher.addEventListener('click', function () { openPanel(false); });
  panel.querySelector('.xg-min').addEventListener('click', closePanel);

  /* ---------- 发送 ---------- */
  function doSend() {
    var v = textEl.value.trim();
    if (!v) return;
    textEl.value = '';
    var local = { sender: 'visitor', body: v, create_time: '' };
    var bubbleEl = appendMsg(local); // 乐观气泡
    pendingSends.push({ body: v, el: bubbleEl });
    post({ action: 'send', vid: vid, body: v, site: SITE, lang: MYLANG }).then(function (j) {
      if (j && j.code === 200) {
        if (j.id > lastId) lastId = j.id; // 用真实消息 id 推进游标，避免 poll 重复拉取
        // 若 poll 尚未提前收敛，补绑真实 id，保证乐观气泡带上 data-mid
        var pi = findPending(v);
        if (pi && !pi.el.getAttribute('data-mid')) { pi.el.setAttribute('data-mid', j.id); removePending(v); }
        if (j.auto_reply && j.auto_reply.body) {
          appendMsg({ id: j.auto_reply.id, sender: 'admin', body: j.auto_reply.body, create_time: '' });
          if (j.auto_reply.id > lastId) lastId = j.auto_reply.id;
          if (!panelOpen) { /* 面板已开，无需弹窗 */ }
        }
      }
    });
  }
  panel.querySelector('.xg-send').addEventListener('click', doSend);
  textEl.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); doSend(); } });
  var lastTyping = 0;
  textEl.addEventListener('input', function () {
    var t = Date.now();
    if (t - lastTyping > 2000) { lastTyping = t; post({ action: 'typing', vid: vid }); }
  });

  /* ---------- 心跳 / 轮询 ---------- */
  function beat() {
    var now = Date.now();
    var dt = lastBeatAt ? Math.round((now - lastBeatAt) / 1000) : 0;
    lastBeatAt = now;
    var ref = '';
    try { ref = document.referrer || ''; } catch (e) {}
    post({
      action: 'beat', vid: vid, site: SITE, lang: MYLANG, tz: MYTZ,
      page: location.pathname + location.search,
      title: document.title || '',
      referer: ref,
      visible: document.visibilityState === 'visible' ? 1 : 0,
      dt: dt,
      uid: curUid(),
      uname: curUname()
    });
  }
  function poll() {
    post({ action: 'poll', vid: vid, after_id: lastId }).then(function (j) {
      if (!j || j.code !== 200) return;
      // 管理员清除了对话：同步清空本地聊天框并重置游标
      if (j.clear_token && j.clear_token !== clearToken) {
        clearToken = j.clear_token; lastId = 0; history = [];
        renderAll([]); setBadge(0);
      }
      var gotAdmin = false;
      (j.messages || []).forEach(function (m) {
        if (m.id > lastId) lastId = m.id;
        if (m.id && msgsEl.querySelector('[data-mid="' + m.id + '"]')) return; // 已渲染则跳过，防重复
        // 乐观气泡收敛：这是自己刚发、send 尚未返回就被 poll 拉回的访客消息，绑定真实 id 而非新增
        if (m.sender === 'visitor') {
          var pi = findPending(m.body);
          if (pi) { pi.el.setAttribute('data-mid', m.id); removePending(m.body); return; }
        }
        appendMsg(m);
        if (m.sender === 'admin') gotAdmin = true;
      });
      setBadge(j.unread_admin || 0);
      if (j.admin_typing) { typingEl.classList.add('on'); }
      else { typingEl.classList.remove('on'); }
      // 首次加载只渲染历史并显示未读角标，不自动弹窗；之后收到“实时新消息”才弹出提醒
      if (gotAdmin && !panelOpen && !firstPoll) { openPanel(true); }
      if (panelOpen && j.unread_admin > 0) {
        post({ action: 'read', vid: vid, id: lastId });
      }
      firstPoll = false;
    });
  }
  /* ---------- 授权锁定处理 ---------- */
  function handleLock(j) {
    if (xgLocked) return;
    xgLocked = true;
    launcher.hidden = true;
    panel.hidden = true;
    hint.hidden = true;
    lockEl.hidden = false;
  }
  function applyLicense() {
    var btn = lockEl.querySelector('.xg-apply');
    var msg = lockEl.querySelector('.xg-lock-msg');
    btn.disabled = true;
    fetch(HUB + '/license.php', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'request', domain: location.hostname, product: 'chat',
        contact: (isZh ? '来自客服组件申请' : 'Apply from chat widget')
      })
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (j && j.code === 200) {
        msg.textContent = isZh ? '申请已提交，请通过 QQ/Telegram 联系我们尽快开通' : 'Request sent. Contact us via QQ/Telegram to speed it up.';
      } else {
        btn.disabled = false;
        msg.textContent = isZh ? '提交失败，请直接通过 QQ/Telegram 联系' : 'Failed; please contact us via QQ/Telegram.';
      }
    }).catch(function () {
      btn.disabled = false;
      msg.textContent = isZh ? '网络异常，请直接通过 QQ/Telegram 联系' : 'Network error; please contact us via QQ/Telegram.';
    });
  }
  lockEl.querySelector('.xg-apply').addEventListener('click', applyLicense);

  function maybeShowWelcome() {
    var seen = null;
    try { seen = localStorage.getItem('xg_welcome_seen'); } catch (e) {}
    if (seen) return;
    welcomeEl.hidden = false;
  }
  function closeWelcome() {
    welcomeEl.hidden = true;
    try { localStorage.setItem('xg_welcome_seen', '1'); } catch (e) {}
  }
  welcomeEl.querySelector('.xg-wc-btn').addEventListener('click', closeWelcome);
  welcomeEl.addEventListener('click', function (e) { if (e.target === welcomeEl) closeWelcome(); });

  function start() {
    // 启动先做一次授权探测；未授权会由 post 内部切换到锁定界面
    post({
      action: 'beat', vid: vid, site: SITE, lang: MYLANG, tz: MYTZ,
      page: location.pathname + location.search, title: document.title || '',
      visible: document.visibilityState === 'visible' ? 1 : 0, uid: curUid(), uname: curUname()
    }).then(function (j) {
      if (xgLocked) return;
      maybeShowWelcome();
      poll();
      setInterval(function () { if (!xgLocked) beat(); }, 25000);
      setInterval(function () { if (!xgLocked) poll(); }, 5000);
    });
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden && !xgLocked) { beat(); poll(); }
    });
    // 单页应用路由变化：拦截 history 方法，URL 改变立即上报新页面
    function wrapHistory(fn) {
      var orig = history[fn];
      history[fn] = function () {
        var ret = orig.apply(this, arguments);
        window.dispatchEvent(new Event('xg_locationchange'));
        return ret;
      };
    }
    if (window.history && history.pushState) {
      wrapHistory('pushState');
      wrapHistory('replaceState');
      window.addEventListener('popstate', function () {
        window.dispatchEvent(new Event('xg_locationchange'));
      });
    }
    var lastUrl = location.pathname + location.search;
    window.addEventListener('xg_locationchange', function () {
      var u = location.pathname + location.search;
      if (u !== lastUrl) { lastUrl = u; beat(); }
    });
    // 兼容 hash 路由
    window.addEventListener('hashchange', function () {
      var u = location.pathname + location.search;
      if (u !== lastUrl) { lastUrl = u; beat(); }
    });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
