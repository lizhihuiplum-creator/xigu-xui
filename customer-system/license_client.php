<?php
/**
 * 系谷 Xigu 软件授权客户端
 * 客户部署后默认锁定，需在中央后台（panel.php）按域名开通后才能使用。
 *
 * 用法：
 *   require_once __DIR__ . '/license_client.php';
 *   if (!xg_license_check('distribution')) xg_license_deny_json();
 *
 * 容错策略：
 *   - 正常结果缓存 10 分钟，避免每次请求都打授权服务器；
 *   - 授权服务器不可达时，若本机此前已授权，给予 7 天宽限（断网不锁死正常客户）；
 *   - 全新部署（无历史授权）一律 fail-closed，未授权即拒绝。
 */
if (!function_exists('xg_license_check')) {

    function xg_license_check($product, $opts = array()) {
        $licenseUrl = 'https://cn.jige.us/license.php';
        $ttl   = isset($opts['ttl'])   ? (int)$opts['ttl']   : 600;     // 正常缓存 10 分钟
        $grace = isset($opts['grace']) ? (int)$opts['grace'] : 604800;  // 断网宽限 7 天

        $domain = xg_license_domain();
        $cacheDir = function_exists('sys_get_temp_dir') ? sys_get_temp_dir() : __DIR__;
        $cacheFile = $cacheDir . '/xg_license_' . md5($domain . '|' . $product) . '.json';
        $now = time();

        $cached = null;
        if (is_file($cacheFile)) {
            $raw = @file_get_contents($cacheFile);
            $j = $raw ? json_decode($raw, true) : null;
            if (is_array($j) && isset($j['authorized'])) $cached = $j;
        }

        // 缓存仍新鲜，直接采用
        if ($cached && isset($cached['_fetched']) && ($now - (int)$cached['_fetched']) < $ttl) {
            return !empty($cached['authorized']);
        }

        // 向中央授权服务器实时校验
        $url = $licenseUrl . '?action=check&domain=' . rawurlencode($domain)
             . '&product=' . rawurlencode($product);
        $resp = xg_license_http_get($url);
        if ($resp !== null) {
            $data = json_decode($resp, true);
            if (is_array($data) && isset($data['authorized'])) {
                $data['_fetched'] = $now;
                @file_put_contents($cacheFile, json_encode($data), LOCK_EX);
                return !empty($data['authorized']);
            }
        }

        // 授权服务器不可达：有历史授权则宽限放行，否则拒绝
        if ($cached && !empty($cached['authorized'])
            && isset($cached['_fetched']) && ($now - (int)$cached['_fetched']) < $grace) {
            return true;
        }
        return false;
    }

    function xg_license_domain() {
        $host = !empty($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : '';
        $host = preg_replace('/:\d+$/', '', $host);   // 去掉端口
        return strtolower(trim($host));
    }

    function xg_license_http_get($url) {
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt_array($ch, array(
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT        => 6,
                CURLOPT_CONNECTTIMEOUT => 4,
                CURLOPT_SSL_VERIFYPEER => false,
                CURLOPT_SSL_VERIFYHOST => 0,
            ));
            $body = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($body !== false && (int)$code === 200) return $body;
            return null;
        }
        $ctx = stream_context_create(array(
            'http' => array('timeout' => 6),
            'ssl'  => array('verify_peer' => false, 'verify_peer_name' => false),
        ));
        $body = @file_get_contents($url, false, $ctx);
        return $body === false ? null : $body;
    }

    function xg_license_deny_json() {
        header('Content-Type: application/json; charset=utf-8');
        http_response_code(403);
        echo json_encode(array(
            'code'    => 403,
            'license' => 'locked',
            'msg'     => '软件未授权，请联系系谷开通后使用',
            'contact' => array(
                'qq'       => '1441673277',
                'telegram' => 'https://t.me/xigu_support_bot',
            ),
        ));
        exit;
    }
}
