<?php
/**
 * 系谷 · 统一客服中枢（多站点访客 / AI 起草与自动回复 / 双向翻译）
 * - 访客匿名（vid 标识，无需登录），可跨站点（cn/ipip/fy/sz）调用，已开 CORS。
 * - 管理员动作需 is_admin 会话（同域）。
 * - 表名/列名/站点白名单硬编码，不读取用户路径，避免注入。
 */
/* 仅管理员动作需要 session；访客高频动作（poll/beat/send 等）不启动 session，
   避免 PHP session 文件锁把并发请求串行化、累计等待直到被 fpm 超时强制终止。 */
const ADMIN_ACTIONS=['visitors','conversation','admin_send','admin_read','ai_draft','get_settings','set_setting','clear_messages','admin_typing','admin_ping','tracks_overview','user_tracks','user_stats','user_tracks_by_uid'];
function peekAction(){
    if(isset($_GET['action']) && $_GET['action']!=='') return (string)$_GET['action'];
    $d=json_decode(file_get_contents('php://input'),true);
    return is_array($d)?(string)($d['action']??''):'';
}
if(in_array(peekAction(),ADMIN_ACTIONS,true)){
    session_start();
}

/* ---------- 跨域（访客组件位于其它子域） ---------- */
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json; charset=utf-8');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') { http_response_code(204); exit; }

/* ===== 系谷授权锁：未在后台开通则拒绝服务 ===== */
require_once __DIR__ . '/license_client.php';
if (!xg_license_check('chat')) xg_license_deny_json();

const DB_HOST='YOUR_DB_HOST', DB_NAME='YOUR_DB_NAME', DB_USER='YOUR_DB_USER', DB_PASS='YOUR_DB_PASSWORD';
const ARK_KEY='YOUR_ARK_API_KEY';
const ARK_URL='https://ark.cn-beijing.volces.com/api/plan/v3/chat/completions';
const ARK_MODEL='doubao-seed-2-1-pro-260628';
const SITE_WHITELIST=['cn','ipip','fy','sz'];
const SITE_LABELS=['cn'=>'系谷主站','ipip'=>'IP工具站','fy'=>'翻译站','sz'=>'时钟站'];

function pdo(){
    static $p=null;
    if($p===null){
        $p=new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4",DB_USER,DB_PASS,[
            PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
        ]);
    }
    return $p;
}
function jout($a){ echo json_encode($a,JSON_UNESCAPED_UNICODE); exit; }
function isAdmin(){ return !empty($_SESSION['is_admin']); }
function body(){
    $d=json_decode(file_get_contents('php://input'),true);
    return is_array($d)?$d:[];
}
function normSite($s){ $s=(string)$s; return in_array($s,SITE_WHITELIST,true)?$s:'cn'; }
function normLang($l){
    $l=strtolower(substr(trim((string)$l),0,12));
    return preg_match('/^[a-z]{2,3}(-[a-z0-9]{2,8})?$/',$l)?$l:'';
}
function normTz($t){
    $t=trim((string)$t);
    if($t===''||strlen($t)>48) return '';
    return preg_match('#^[A-Za-z][A-Za-z0-9_/+\-]{0,46}(\.[A-Za-z0-9_/+\-]+)?$#',$t)?$t:'';
}

/* ---------- 表结构（含旧表平滑加列） ---------- */
function ensureTables(){
    $p=pdo();
    $p->exec("CREATE TABLE IF NOT EXISTS proactive_visitors (
        id INT AUTO_INCREMENT PRIMARY KEY,
        vid VARCHAR(40) NOT NULL UNIQUE,
        site VARCHAR(16) NOT NULL DEFAULT 'cn',
        ip VARCHAR(45) NOT NULL DEFAULT '',
        country VARCHAR(64) NOT NULL DEFAULT '',
        city VARCHAR(64) NOT NULL DEFAULT '',
        lang VARCHAR(16) NOT NULL DEFAULT '',
        tz VARCHAR(48) NOT NULL DEFAULT '',
        visitor_typing DATETIME NULL,
        admin_typing DATETIME NULL,
        last_page VARCHAR(190) NOT NULL DEFAULT '',
        first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
        KEY idx_last_seen (last_seen),
        KEY idx_site (site)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $p->exec("CREATE TABLE IF NOT EXISTS proactive_messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        vid VARCHAR(40) NOT NULL,
        sender ENUM('admin','visitor') NOT NULL DEFAULT 'admin',
        body MEDIUMTEXT NOT NULL,
        is_read TINYINT NOT NULL DEFAULT 0,
        create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
        KEY idx_vid (vid),
        KEY idx_read (is_read)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $p->exec("CREATE TABLE IF NOT EXISTS chat_settings (
        k VARCHAR(64) PRIMARY KEY,
        v TEXT
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // 页面浏览轨迹（每次落地/路由变化写一条，含登录用户标识，用于后台回放“看了什么”）
    $p->exec("CREATE TABLE IF NOT EXISTS page_views (
        id INT AUTO_INCREMENT PRIMARY KEY,
        vid VARCHAR(40) NOT NULL,
        site VARCHAR(16) NOT NULL DEFAULT 'cn',
        user_id INT NULL,
        user_name VARCHAR(60) NOT NULL DEFAULT '',
        page VARCHAR(190) NOT NULL DEFAULT '',
        title VARCHAR(190) NOT NULL DEFAULT '',
        referer VARCHAR(255) NOT NULL DEFAULT '',
        ip VARCHAR(45) NOT NULL DEFAULT '',
        country VARCHAR(64) NOT NULL DEFAULT '',
        view_time DATETIME DEFAULT CURRENT_TIMESTAMP,
        KEY idx_vid (vid),
        KEY idx_site (site),
        KEY idx_user (user_id),
        KEY idx_view_time (view_time)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // 访问会话（连续在线归为一个会话，心跳累计活跃秒数，用于后台统计“在线多长时间”）
    $p->exec("CREATE TABLE IF NOT EXISTS visitor_sessions (
        id INT AUTO_INCREMENT PRIMARY KEY,
        vid VARCHAR(40) NOT NULL,
        site VARCHAR(16) NOT NULL DEFAULT 'cn',
        user_id INT NULL,
        user_name VARCHAR(60) NOT NULL DEFAULT '',
        ip VARCHAR(45) NOT NULL DEFAULT '',
        country VARCHAR(64) NOT NULL DEFAULT '',
        started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_beat_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        active_seconds INT NOT NULL DEFAULT 0,
        page_count INT NOT NULL DEFAULT 0,
        ended TINYINT(1) NOT NULL DEFAULT 0,
        KEY idx_vid (vid),
        KEY idx_site (site),
        KEY idx_user (user_id),
        KEY idx_last_beat (last_beat_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // 旧表补列（重复列会抛异常，忽略）
    foreach (['proactive_visitors'=>['site'=>"VARCHAR(16) NOT NULL DEFAULT 'cn'",
                                      'lang'=>"VARCHAR(16) NOT NULL DEFAULT ''",
                                      'tz'=>"VARCHAR(48) NOT NULL DEFAULT ''",
                                      'visitor_typing'=>"DATETIME NULL",
                                      'admin_typing'=>"DATETIME NULL",
                                      'user_id'=>"INT NULL",
                                      'user_name'=>"VARCHAR(60) NOT NULL DEFAULT ''"]] as $tbl=>$cols){
        foreach($cols as $col=>$ddl){
            try{ $p->exec("ALTER TABLE `$tbl` ADD COLUMN `$col` $ddl"); }catch(Throwable $e){}
        }
    }
}
function getSetting($k,$def=''){
    $st=pdo()->prepare("SELECT v FROM chat_settings WHERE k=?");$st->execute([$k]);
    $r=$st->fetchColumn(); return $r===false?$def:(string)$r;
}
function setSetting($k,$v){
    $st=pdo()->prepare("INSERT INTO chat_settings (k,v) VALUES (?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)");
    $st->execute([$k,(string)$v]);
}
function deleteSetting($k){
    $st=pdo()->prepare("DELETE FROM chat_settings WHERE k=?");
    $st->execute([$k]);
}
/* 真人是否正在值守：后台打开（心跳 30 秒内）或正在给该访客打字（10 秒内）即视为在场 */
function adminIsActive($vid=''){
    $pres=(int)getSetting('admin_presence','0');
    if($pres>0 && time()-$pres<=30) return true;
    if($vid!==''){
        $st=pdo()->prepare("SELECT admin_typing FROM proactive_visitors WHERE vid=?");$st->execute([$vid]);
        $t=$st->fetchColumn();
        if($t && strtotime($t)>=time()-10) return true;
    }
    return false;
}

/* ---------- Geo（本地 MMDB，离线） ---------- */
function resolveGeo($ip){
    $country='';$city='';
    if($ip && filter_var($ip,FILTER_VALIDATE_IP,FILTER_FLAG_NO_PRIV_RANGE|FILTER_FLAG_NO_RES_RANGE)){
        try{
            require_once __DIR__.'/geo_mmdb.php';
            $g=new GeoMmdb(__DIR__.'/geo/GeoLite2-City.mmdb');
            $r=$g->lookup($ip);
            if(is_array($r)&&isset($r['country'])&&is_array($r['country'])){
                $d=$r['country'];
                $country=(string)($d['country']??'');
                $city=(string)($d['city']??'');
                if($city===''&&!empty($d['province'])) $city=(string)$d['province'];
            }
        }catch(Throwable $e){}
    }
    return [$country,$city];
}

/* ---------- 火山 Ark（AI） ---------- */
function aiSystemPrompt(){
    return '你是系谷科技（Xigu）的“AI 真人客服”，面向跨境电商、企业出海、社媒直播等客户，提供住宅代理IP、静态IP、IP纯净度、防关联、网络加速等咨询。'.
           '【免费工具矩阵（无需登录，打开即用）】世界时钟/中外日历 https://sz.jige.us ；IP检测/纯净度查询 https://ipip.jige.us ；在线翻译 https://fy.jige.us ；中文主站 https://cn.jige.us 。'.
           '【商品卡独立链接规则】每个商品卡都有可单独发给客户的固定链接，格式为 https://cn.jige.us/?plan=标识 ，客户点开即定位并高亮该商品卡，可直接选地区、时长下单。涉及具体套餐或客户要“直接拍/单独链接”时，务必附上对应链接。'.
           '【商品卡完整知识库（价格、特点、适用场景均以卡片为准，逐卡说明）】'.
           '① day39 高速普通线路·一天体验，3.9 元/天，链接 https://cn.jige.us/?plan=day39 ：高速普通线路、稳定流畅；可注册 TikTok、抖音、快手、微信、YouTube、谷歌账号；AI 工具与全部平台兼容。适合低成本先试用、注册账号。'.
           '② day29 CN2 GIA顶级线路·一天体验，29 元/天，链接 https://cn.jige.us/?plan=day29 ：三网优化顶级线路、CN2 GIA 通道；顶级高速，兼容所有社交、媒体、金融软件；游戏、AI 全部适用。适合追求顶级速度、低延迟的短期体验。'.
           '③ p128 专业型，119.9 元/月（原价 128 元/月，新用户优惠），链接 https://cn.jige.us/?plan=p128 ：优选线路节点、更好的网络稳定性；独享 ISP、适合长期运营、支持更多设备连接；热门地区 10 个（美、日、英、新、韩、德、法、澳、加、荷）；售后优先响应。适合个人长期使用、基础专业月付。'.
           '④ p199 标准型·独享ISP，199 元/月，链接 https://cn.jige.us/?plan=p199 ：独享网络 IP、ISP 网络资源、稳定线路，常用海外地区 20+（含港澳台、东南亚）；支持电脑、手机等常用设备；基础技术支持。适合个人、海外社交媒体、跨境业务基础使用。'.
           '⑤ p298 专业型·独享ISP，298 元/月，链接 https://cn.jige.us/?plan=p298 ：独享 ISP IP、优化跨境线路、连接更稳定；适合 YouTube、Instagram、TikTok 等内容运营；支持多设备；优先技术支持。适合注重稳定与速度的内容运营。'.
           '⑥ p450 企业型·独享ISP，450 元/月，链接 https://cn.jige.us/?plan=p450 ：独享 ISP 网络环境、专属 IP 资源、优化国际线路、更高资源配置；支持多设备与长期业务、远程部署与环境调试；企业级技术支持。适合跨境电商、海外业务团队、内容创作者、长期运营。'.
           '⑦ p888 高端型·专属网络环境，888 元/月，链接 https://cn.jige.us/?plan=p888 ：专属网络 IP 资源、独立网络环境、高规格线路配置，可按业务选地区；支持多设备与业务环境部署；专属技术支持，可做针对性网络优化与测试。适合对 IP 独立性、稳定性和专属服务要求高的客户。'.
           '⑧ p3600 定制型·企业专属，3600 元/月，链接 https://cn.jige.us/?plan=p3600 ：企业级专属网络资源、多 IP/多节点配置（含 10 个 IP），可定制地区与网络架构、专属部署，支持多用户多设备；提供网络环境测试优化与专属技术支持；具体配置、IP 数量、地区、线路、设备数量按实际需求单独确认。适合企业、团队及有特殊网络资源需求的项目。'.
           '⑨ webdev 网站搭建开发，7990 元（原价 8000 元），链接 https://cn.jige.us/?plan=webdev ：一站式全球部署、从 0 到 1 上线；含域名、服务器与全套配置，专业团队开发、支持个性化需求。'.
           '【折扣规则】月付套餐（p128/p199/p298/p450/p888/p3600）选 3 个月（按季）9.5 折、选 12 个月（按年）8.5 折；具体合计以页面选择时长后显示为准。'.
           '【回答套餐区别的硬性要求】客户问“套餐/价格有什么区别、哪个适合我”时，必须按上面编号逐卡对照说明（价格、线路/IP 特点、适用场景、独立链接），先简短区分档位（单日体验→月付标准/专业/企业/高端/定制），再结合客户用途（如直播、电商、社媒、游戏、预算）推荐 1-2 个并附对应链接；信息只能引用本知识库，未列出的价格或配置不要编造，引导查看链接或转人工。'.
           '下单步骤：打开商品卡链接→在“地区”下拉选择国家/地区（如美国，显示有货数量）→选择使用时长→点击立即体验/立即购买并完成支付。客户问“怎么买/怎么拍/如何下单”时，按此步骤引导。'.
           '【如实可说】真实住宅IP、国内直连、国外走住宅、稳定不自动切换、15天内可退款。'.
           '【表达要求】用与客户相同的语言，简短、专业、热情，优先给出可执行建议与可点击链接；中文语境不得出现 VPN、翻墙、梯子等词，统一用“企业出海/住宅代理IP/网络加速/IP检测/防关联”等中性表述。';
}
function arkChat($messages,$maxTokens=2400){
    $payload=json_encode(['model'=>ARK_MODEL,'messages'=>$messages,'max_tokens'=>$maxTokens,
                          'temperature'=>0.4],JSON_UNESCAPED_UNICODE);
    $ch=curl_init(ARK_URL);
    curl_setopt_array($ch,[
        CURLOPT_RETURNTRANSFER=>true,CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>$payload,
        CURLOPT_TIMEOUT=>170,CURLOPT_CONNECTTIMEOUT=>15,
        CURLOPT_HTTPHEADER=>['Content-Type: application/json','Authorization: Bearer '.ARK_KEY],
    ]);
    $r=curl_exec($ch);$code=curl_getinfo($ch,CURLINFO_HTTP_CODE);
    $errno=curl_errno($ch);$err=curl_error($ch);curl_close($ch);
    if($r===false||$code<200||$code>=300){
        @file_put_contents('/tmp/ark_fail.log', date('Y-m-d H:i:s')." HTTP=$code ERRNO=$errno ERR=$err RESP=".substr((string)$r,0,300)."\n", FILE_APPEND);
        return null;
    }
    $d=json_decode($r,true);
    $c=$d['choices'][0]['message']['content']??'';
    $finish=$d['choices'][0]['finish_reason']??'';
    if($finish==='length'){
        @file_put_contents('/tmp/ark_fail.log', date('Y-m-d H:i:s')." FINISH=length (max_tokens reached, consider raising) LEN=".mb_strlen((string)$c)."\n", FILE_APPEND);
    }
    $c=trim((string)$c);
    if($c===''){
        @file_put_contents('/tmp/ark_fail.log', date('Y-m-d H:i:s')." EMPTY_CONTENT RESP=".substr((string)$r,0,300)."\n", FILE_APPEND);
        return null;
    }
    return $c;
}
function buildContext($vid,$limit=10){
    $st=pdo()->prepare("SELECT sender,body FROM proactive_messages WHERE vid=? ORDER BY id DESC LIMIT $limit");
    $st->execute([$vid]);$rows=array_reverse($st->fetchAll());
    $msgs=[['role'=>'system','content'=>aiSystemPrompt()]];
    foreach($rows as $r){
        $msgs[]=['role'=>$r['sender']==='admin'?'assistant':'user','content'=>(string)$r['body']];
    }
    return $msgs;
}

/* ---------- 翻译代理（Google gtx 主，MyMemory 备） ---------- */
function httpGet($url){
    if(function_exists('curl_init')){
        $ch=curl_init($url);
        curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>true,
            CURLOPT_TIMEOUT=>20,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_SSL_VERIFYPEER=>false,
            CURLOPT_SSL_VERIFYHOST=>0,CURLOPT_USERAGENT=>'Mozilla/5.0']);
        $r=curl_exec($ch);$code=curl_getinfo($ch,CURLINFO_HTTP_CODE);curl_close($ch);
        return ($r!==false&&$code>=200&&$code<300)?$r:null;
    }
    $ctx=stream_context_create(['http'=>['timeout'=>20],'ssl'=>['verify_peer'=>false,'verify_peer_name'=>false]]);
    $r=@file_get_contents($url,false,$ctx); return $r===false?null:$r;
}
/* 轻量语言检测：Google 失败且源语言为 auto 时，供 MyMemory 备用确定源语言 */
function detectLang($q){
    if(preg_match('/[\x{4e00}-\x{9fff}]/u',$q)) return 'zh-CN';            // 汉字
    if(preg_match('/[\x{3040}-\x{309f}\x{30a0}-\x{30ff}]/u',$q)) return 'ja'; // 日文假名
    if(preg_match('/[\x{ac00}-\x{d7af}]/u',$q)) return 'ko';               // 韩文音节
    if(preg_match('/[\x{0400}-\x{04ff}]/u',$q)) return 'ru';               // 西里尔
    if(preg_match('/[\x{0600}-\x{06ff}]/u',$q)) return 'ar';               // 阿拉伯
    if(preg_match('/[\x{0590}-\x{05ff}]/u',$q)) return 'he';               // 希伯来
    if(preg_match('/[\x{0e00}-\x{0e7f}]/u',$q)) return 'th';               // 泰文
    return 'en';
}
function translateText($q,$sl,$tl){
    if($q===''||$tl==='') return null;
    if($sl==='') $sl='auto';
    $g='https://translate.googleapis.com/translate_a/single?client=gtx&sl='.rawurlencode($sl)
       .'&tl='.rawurlencode($tl).'&dt=t&q='.rawurlencode($q);
    $r=httpGet($g);
    if($r!==null){
        $d=json_decode($r,true);
        if(is_array($d)&&isset($d[0])&&is_array($d[0])){
            $t='';foreach($d[0] as $seg){ if(isset($seg[0])) $t.=$seg[0]; }
            if($t!=='') return $t;
        }
    }
    // MyMemory 不支持 auto：auto 时用本地检测确定源语言
    $mmSl=($sl==='auto')?detectLang($q):$sl;
    // 源语言与目标语言相同（含中文变体）：直接返回原文，避免上游报错
    if($mmSl===$tl||(strpos($tl,'zh')===0&&strpos($mmSl,'zh')===0)) return $q;
    if($mmSl&&$mmSl!=='auto'){
        $mm='https://api.mymemory.translated.net/get?q='.rawurlencode($q).'&langpair='.rawurlencode($mmSl.'|'.$tl);
        $r=httpGet($mm);
        if($r!==null){
            $d=json_decode($r,true);
            $t=trim((string)($d['responseData']['translatedText']??''));
            if($t!==''&&strtoupper($t)!=='INVALID'&&stripos($t,'MYMEMORY WARNING')===false) return $t;
        }
    }
    return null;
}

$b=body();
$action=$b['action']??($_GET['action']??'');
try{ ensureTables(); }catch(Throwable $e){ jout(['code'=>500,'msg'=>'init failed']); }

/* ---------- 公共：翻译（访客与管理员都用） ---------- */
if($action==='translate'){
    $q=trim((string)($b['q']??''));
    $sl=normLang($b['sl']??'') ?: 'auto';
    $tl=normLang($b['tl']??'');
    if(strpos($tl,'zh')===0) $tl='zh-CN';
    $t=translateText($q,$sl,$tl);
    jout($t===null?['code'=>502,'msg'=>'翻译失败']:['code'=>200,'text'=>$t,'tl'=>$tl]);
}

/* ---------------- 管理员动作 ---------------- */
if(in_array($action,['visitors','conversation','admin_send','admin_read','ai_draft','get_settings','set_setting','clear_messages','admin_typing','admin_ping','tracks_overview','user_tracks','user_stats','user_tracks_by_uid'],true)){
    if(!isAdmin()) jout(['code'=>403,'msg'=>'forbidden']);
    $p=pdo();
    if($action==='admin_ping'){
        setSetting('admin_presence',(string)time());
        jout(['code'=>200]);
    }
    if($action==='visitors'){
        $rows=$p->query("SELECT v.*,
            (SELECT COUNT(*) FROM proactive_messages m WHERE m.vid=v.vid AND m.sender='visitor' AND m.is_read=0) unread_visitor,
            (SELECT COUNT(*) FROM proactive_messages m WHERE m.vid=v.vid) msg_count
            FROM proactive_visitors v ORDER BY v.last_seen DESC LIMIT 500")->fetchAll();
        foreach($rows as &$r){
            $r['online']=(strtotime($r['last_seen'])>=time()-60)?1:0;
            $r['site_label']=SITE_LABELS[$r['site']]??$r['site'];
        }
        jout(['code'=>200,'visitors'=>$rows]);
    }
    if($action==='conversation'){
        $vid=(string)($b['vid']??'');
        $st=$p->prepare("SELECT id,sender,body,is_read,create_time FROM proactive_messages WHERE vid=? ORDER BY id ASC");
        $st->execute([$vid]);
        $vi=$p->prepare("SELECT tz,visitor_typing FROM proactive_visitors WHERE vid=?");$vi->execute([$vid]);
        $vrow=$vi->fetch();
        $vt=$vrow['visitor_typing']??null;
        $visitorTyping=($vt&&strtotime($vt)>=time()-4)?1:0;
        jout(['code'=>200,'vid'=>$vid,'tz'=>(string)($vrow['tz']??''),
              'visitor_typing'=>$visitorTyping,'messages'=>$st->fetchAll()]);
    }
    if($action==='admin_typing'){
        $vid=(string)($b['vid']??'');
        $st=$p->prepare("UPDATE proactive_visitors SET admin_typing=NOW() WHERE vid=?");
        $st->execute([$vid]);
        jout(['code'=>200]);
    }
    if($action==='admin_send'){
        $vid=(string)($b['vid']??'');$msg=trim((string)($b['body']??''));
        if($vid===''||$msg==='') jout(['code'=>400,'msg'=>'内容为空']);
        if(mb_strlen($msg)>2000) jout(['code'=>400,'msg'=>'内容过长']);
        $st=$p->prepare("INSERT INTO proactive_messages (vid,sender,body,is_read) VALUES (?,?,?,0)");
        $st->execute([$vid,'admin',$msg]);
        jout(['code'=>200,'id'=>$p->lastInsertId()]);
    }
    if($action==='admin_read'){
        $vid=(string)($b['vid']??'');
        $st=$p->prepare("UPDATE proactive_messages SET is_read=1 WHERE vid=? AND sender='visitor'");
        $st->execute([$vid]);
        jout(['code'=>200]);
    }
    if($action==='clear_messages'){
        $vid=(string)($b['vid']??'');
        if($vid===''||!preg_match('/^[a-f0-9]{16,40}$/',$vid)) jout(['code'=>400,'msg'=>'访客无效']);
        $del=$p->prepare("DELETE FROM proactive_messages WHERE vid=?");
        $del->execute([$vid]);
        $cnt=$del->rowCount();
        // 记录清除标记，访客轮询到后清空本地聊天框
        setSetting('clear_'.$vid,date('Y-m-d H:i:s'));
        jout(['code'=>200,'deleted'=>$cnt]);
    }
    if($action==='get_settings'){
        jout(['code'=>200,'auto_reply'=>getSetting('auto_reply','0')]);
    }
    if($action==='set_setting'){
        $k=(string)($b['k']??'');
        if(!in_array($k,['auto_reply'],true)) jout(['code'=>400,'msg'=>'未知设置']);
        $v=((string)($b['v']??'')==='1')?'1':'0';
        setSetting($k,$v);
        jout(['code'=>200,$k=>$v]);
    }
    if($action==='ai_draft'){
        $vid=(string)($b['vid']??'');
        $chk=$p->prepare("SELECT id FROM proactive_visitors WHERE vid=?");$chk->execute([$vid]);
        if(!$chk->fetch()) jout(['code'=>404,'msg'=>'访客不存在']);
        $ctx=buildContext($vid);
        $draft=arkChat($ctx,2400);
        jout($draft===null?['code'=>502,'msg'=>'AI 暂不可用，请手动回复']:['code'=>200,'draft'=>$draft]);
    }
}

/* ---------------- 访客动作 ---------------- */
$ip=$_SERVER['REMOTE_ADDR']??'';
if($action==='beat'){
    $vid=(string)($b['vid']??'');
    if($vid===''||!preg_match('/^[a-f0-9]{16,40}$/',$vid)) $vid=bin2hex(random_bytes(16));
    $site=normSite($b['site']??'cn');
    $lang=normLang($b['lang']??'');
    $tz=normTz($b['tz']??'');
    $page=substr((string)($b['page']??''),0,190);
    $title=substr((string)($b['title']??''),0,190);
    $referer=substr((string)($b['referer']??''),0,255);
    $visible=!empty($b['visible'])?1:0;
    $rawDt=isset($b['dt'])?(int)$b['dt']:0;
    $dt=max(0,min(60,$rawDt)); // 距上次心跳秒数，封顶 60 防异常累计
    $uid=isset($b['uid'])?(int)$b['uid']:0; if($uid<=0) $uid=null;
    $uname=substr((string)($b['uname']??''),0,60);
    $p=pdo();
    $country='';
    $chk=$p->prepare("SELECT id,last_page,country FROM proactive_visitors WHERE vid=?");
    $chk->execute([$vid]);
    $vrow=$chk->fetch();
    if(!$vrow){
        list($country,$city)=resolveGeo($ip);
        $ins=$p->prepare("INSERT INTO proactive_visitors (vid,site,ip,country,city,lang,tz,last_page,user_id,user_name,first_seen,last_seen) VALUES (?,?,?,?,?,?,?,?,?,?,NOW(),NOW())");
        $ins->execute([$vid,$site,$ip,$country,$city,$lang,$tz,$page,$uid,$uname]);
    }else{
        $country=(string)$vrow['country'];
        $up=$p->prepare("UPDATE proactive_visitors SET ip=?,site=?,lang=?,tz=COALESCE(NULLIF(?, ''),tz),last_page=?,
            user_id=COALESCE(?,user_id),
            user_name=CASE WHEN ?<>'' THEN ? ELSE user_name END,
            last_seen=NOW() WHERE vid=?");
        $up->execute([$ip,$site,$lang,$tz,$page,$uid,$uname,$uname,$vid]);
    }
    // 会话：取当前未结束会话；不存在或中断超过 90 秒则新开一个
    $sess=$p->prepare("SELECT id,last_beat_at FROM visitor_sessions WHERE vid=? AND ended=0 ORDER BY id DESC LIMIT 1");
    $sess->execute([$vid]);
    $srow=$sess->fetch();
    $newSession=false;
    if(!$srow || (time()-strtotime($srow['last_beat_at']))>90){
        if($srow){ $p->prepare("UPDATE visitor_sessions SET ended=1 WHERE id=?")->execute([$srow['id']]); }
        $ins=$p->prepare("INSERT INTO visitor_sessions (vid,site,user_id,user_name,ip,country,started_at,last_beat_at,active_seconds,page_count) VALUES (?,?,?,?,?,?,NOW(),NOW(),0,0)");
        $ins->execute([$vid,$site,$uid,$uname,$ip,$country]);
        $newSession=true;
    }
    // 页面轨迹：新会话首条或页面变化时写一条
    $pageChanged=!$vrow || $vrow['last_page']!==$page;
    if($newSession || $pageChanged){
        $pv=$p->prepare("INSERT INTO page_views (vid,site,user_id,user_name,page,title,referer,ip,country,view_time) VALUES (?,?,?,?,?,?,?,?,?,NOW())");
        $pv->execute([$vid,$site,$uid,$uname,$page,$title,$referer,$ip,$country]);
    }
    // 更新当前会话：仅页面可见时累计活跃秒数
    $cur=$p->prepare("SELECT id FROM visitor_sessions WHERE vid=? AND ended=0 ORDER BY id DESC LIMIT 1");
    $cur->execute([$vid]); $sid=$cur->fetchColumn();
    $su=$p->prepare("UPDATE visitor_sessions SET last_beat_at=NOW(),
        user_id=COALESCE(?,user_id),
        user_name=CASE WHEN ?<>'' THEN ? ELSE user_name END,
        active_seconds=active_seconds+?,
        page_count=page_count+? WHERE id=?");
    $su->execute([$uid,$uname,$uname,($visible?$dt:0),($pageChanged?1:0),$sid]);
    jout(['code'=>200,'vid'=>$vid]);
}
if($action==='poll'){
    $vid=(string)($b['vid']??'');
    $after=(int)($b['after_id']??0);
    $st=pdo()->prepare("SELECT id,sender,body,is_read,create_time FROM proactive_messages WHERE vid=? AND id>? ORDER BY id ASC");
    $st->execute([$vid,$after]);
    $msgs=$st->fetchAll();
    $unread=pdo()->prepare("SELECT COUNT(*) FROM proactive_messages WHERE vid=? AND sender='admin' AND is_read=0");
    $unread->execute([$vid]);$uc=(int)$unread->fetchColumn();
    $ty=pdo()->prepare("SELECT admin_typing FROM proactive_visitors WHERE vid=?");$ty->execute([$vid]);
    $at=$ty->fetchColumn();
    $adminTyping=($at&&strtotime($at)>=time()-4)?1:0;
    // AI 离线自动回复正在生成（60 秒窗口内）也显示“客服正在输入”
    $aiTypingAt=(int)getSetting('ai_typing_'.$vid,'0');
    if($aiTypingAt>0 && time()-$aiTypingAt<=60) $adminTyping=1;
    jout(['code'=>200,'messages'=>$msgs,'unread_admin'=>$uc,'admin_typing'=>$adminTyping,
          'clear_token'=>getSetting('clear_'.$vid,'')]);
}
if($action==='send'){
    $vid=(string)($b['vid']??'');$msg=trim((string)($b['body']??''));
    if($vid===''||$msg==='') jout(['code'=>400,'msg'=>'内容为空']);
    if(mb_strlen($msg)>2000) jout(['code'=>400,'msg'=>'内容过长']);
    $p=pdo();
    $chk=$p->prepare("SELECT id,site,lang FROM proactive_visitors WHERE vid=?");$chk->execute([$vid]);
    $vrow=$chk->fetch();
    if(!$vrow){
        $site=normSite($b['site']??'cn');$lang=normLang($b['lang']??'');
        list($country,$city)=resolveGeo($ip);
        $ins=$p->prepare("INSERT INTO proactive_visitors (vid,site,ip,country,city,lang,last_page,first_seen,last_seen) VALUES (?,?,?,?,?,?,?,NOW(),NOW())");
        $ins->execute([$vid,$site,$ip,$country,$city,$lang,'']);
    }
    $st=$p->prepare("INSERT INTO proactive_messages (vid,sender,body,is_read) VALUES (?,?,?,0)");
    $st->execute([$vid,'visitor',$msg]);
    $newId=(int)$p->lastInsertId();
    $autoReply=null;
    // 离线自动回复：开关打开且真人未在后台值守（也没在打字）时，才由 AI 生成并以管理员身份入库
    if(getSetting('auto_reply','0')==='1' && !adminIsActive($vid)){
        setSetting('ai_typing_'.$vid,time()); // 让访客在 AI 生成期间看到“客服正在输入”
        $ctx=buildContext($vid);
        $ai=arkChat($ctx,2400);
        deleteSetting('ai_typing_'.$vid);
        if($ai!==null){
            $ast=$p->prepare("INSERT INTO proactive_messages (vid,sender,body,is_read) VALUES (?,?,?,0)");
            $ast->execute([$vid,'admin',$ai]);
            $autoReply=['id'=>(int)$p->lastInsertId(),'body'=>$ai];
        }
    }
    jout(['code'=>200,'id'=>$newId,'auto_reply'=>$autoReply]);
}
if($action==='read'){
    $vid=(string)($b['vid']??'');$to=(int)($b['id']??'0');
    $st=pdo()->prepare("UPDATE proactive_messages SET is_read=1 WHERE vid=? AND sender='admin' AND id<=?");
    $st->execute([$vid,$to]);
    jout(['code'=>200]);
}
if($action==='typing'){
    $vid=(string)($b['vid']??'');
    $st=pdo()->prepare("UPDATE proactive_visitors SET visitor_typing=NOW() WHERE vid=?");
    $st->execute([$vid]);
    jout(['code'=>200]);
}

/* ---------------- 用户行为监控（管理员） ---------------- */
function fmtDur($sec){
    $sec=(int)$sec;
    if($sec<60) return $sec.'秒';
    $h=intval($sec/3600); $m=intval(($sec%3600)/60); $s=$sec%60;
    return ($h>0?$h.'小时':'').($m>0?$m.'分':'').($h==0?$s.'秒':'');
}
// 行为总览：按访客聚合总时长/页面数/会话数，支持站点筛选
if($action==='tracks_overview'){
    $rawSite=(string)($b['site']??'all');
    $site=in_array($rawSite,SITE_WHITELIST,true)?$rawSite:'all';
    $where=''; $args=[];
    if($site!=='' && $site!=='all'){ $where='WHERE v.site=?'; $args[]=$site; }
    $q=$p->prepare("SELECT v.vid,v.site,v.ip,v.country,v.city,v.user_id,v.user_name,v.last_page,v.first_seen,v.last_seen,
        COALESCE((SELECT SUM(s.active_seconds) FROM visitor_sessions s WHERE s.vid=v.vid),0) total_seconds,
        COALESCE((SELECT COUNT(*) FROM page_views w WHERE w.vid=v.vid),0) view_count,
        COALESCE((SELECT COUNT(*) FROM visitor_sessions s WHERE s.vid=v.vid),0) session_count
        FROM proactive_visitors v $where ORDER BY v.last_seen DESC LIMIT 500");
    $q->execute($args);
    jout(['code'=>200,'rows'=>$q->fetchAll()]);
}
// 单个访客/用户的明细：会话列表 + 页面轨迹
if($action==='user_tracks'){
    $vid=(string)($b['vid']??'');
    if($vid===''||!preg_match('/^[a-f0-9]{16,40}$/',$vid)) jout(['code'=>400,'msg'=>'bad vid']);
    $sess=$p->prepare("SELECT id,site,user_id,user_name,ip,country,started_at,last_beat_at,active_seconds,page_count,ended
        FROM visitor_sessions WHERE vid=? ORDER BY id DESC LIMIT 200");
    $sess->execute([$vid]);
    $views=$p->prepare("SELECT id,site,user_id,user_name,page,title,referer,ip,country,view_time
        FROM page_views WHERE vid=? ORDER BY id DESC LIMIT 300");
    $views->execute([$vid]);
    $info=$p->prepare("SELECT vid,site,ip,country,city,user_id,user_name,last_page,first_seen,last_seen FROM proactive_visitors WHERE vid=?");
    $info->execute([$vid]);
    jout(['code'=>200,'info'=>$info->fetch(),'sessions'=>$sess->fetchAll(),'views'=>$views->fetchAll()]);
}
// 按登录用户聚合：同一 user_id 在各站点的总时长/页面数（跨站点识别同一注册用户）
if($action==='user_stats'){
    $q=$p->query("SELECT user_id, MAX(user_name) user_name,
        COUNT(DISTINCT vid) vid_count,
        COALESCE(SUM(active_seconds),0) total_seconds,
        COALESCE(SUM(page_count),0) total_pages,
        MIN(started_at) first_seen, MAX(last_beat_at) last_seen
        FROM visitor_sessions WHERE user_id IS NOT NULL
        GROUP BY user_id ORDER BY last_seen DESC LIMIT 300");
    jout(['code'=>200,'rows'=>$q->fetchAll()]);
}
// 单个注册用户的跨站点明细：该 user_id 在所有站点的会话与页面轨迹
if($action==='user_tracks_by_uid'){
    $uid=isset($b['uid'])?(int)$b['uid']:0;
    if($uid<=0) jout(['code'=>400,'msg'=>'bad uid']);
    $sess=$p->prepare("SELECT id,site,user_id,user_name,ip,country,started_at,last_beat_at,active_seconds,page_count,ended
        FROM visitor_sessions WHERE user_id=? ORDER BY id DESC LIMIT 300");
    $sess->execute([$uid]);
    $views=$p->prepare("SELECT id,site,user_id,user_name,page,title,referer,ip,country,view_time
        FROM page_views WHERE user_id=? ORDER BY id DESC LIMIT 400");
    $views->execute([$uid]);
    $info=$p->prepare("SELECT user_id, MAX(user_name) user_name, MAX(ip) ip, MAX(country) country,
        MIN(first_seen) first_seen, MAX(last_seen) last_seen
        FROM proactive_visitors WHERE user_id=? GROUP BY user_id");
    $info->execute([$uid]);
    jout(['code'=>200,'info'=>$info->fetch(),'sessions'=>$sess->fetchAll(),'views'=>$views->fetchAll()]);
}
jout(['code'=>400,'msg'=>'unknown action']);
