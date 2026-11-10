<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

// ===== 系谷授权锁：未在后台开通则拒绝服务 =====
require_once __DIR__ . '/license_client.php';
if (!xg_license_check('distribution')) xg_license_deny_json();

$host = 'YOUR_DB_HOST';
$dbname = 'YOUR_DB_NAME';
$username = 'YOUR_DB_USER';
$password = 'YOUR_DB_PASSWORD';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8mb4", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch(PDOException $e) {
    die(json_encode(['code' => 500, 'msg' => '数据库连接失败']));
}

$action = $_GET['action'] ?? '';
if ($action == 'getUserData') {
    $userId = (int)($_GET['user_id'] ?? 0);
    $username = substr((string)($_GET['username'] ?? ''), 0, 100);
    $phone = substr((string)($_GET['phone'] ?? ''), 0, 50);
    $stmt = $pdo->prepare("SELECT * FROM dist_users WHERE user_id = ?");
    $stmt->execute([$userId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        $stmt = $pdo->prepare("INSERT INTO dist_users (user_id, username, phone, join_time) VALUES (?, ?, ?, ?)");
        $stmt->execute([$userId, $username, $phone, time()]);
        $newId = (int)$pdo->lastInsertId();
        $user = [
            'id' => $newId,
            'balance' => 0.00,
            'total_commission' => 0.00,
            'total_orders' => 0,
            'total_team' => 0,
            'level1_team' => 0,
            'level2_team' => 0
        ];
    }
    
    $stmt = $pdo->prepare("SELECT commission1, commission2, commission3 FROM dist_products WHERE status = 1 LIMIT 1");
    $stmt->execute();
    $rates = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$rates) $rates = ['commission1' => '0.00', 'commission2' => '0.00', 'commission3' => '0.00'];
    
    echo json_encode([
        'code' => 200,
        'data' => [
            'balance' => $user['balance'],
            'total_commission' => $user['total_commission'],
            'total_orders' => $user['total_orders'],
            'total_team' => $user['total_team'],
            'promo_link' => 'https://www.666clouds.com/?ref=' . $user['id'],
            'rates' => [
                'level1' => $rates['commission1'],
                'level2' => $rates['commission2'],
                'level3' => $rates['commission3']
            ]
        ]
    ]);
}
?>