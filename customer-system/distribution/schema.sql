-- 系谷分销模块建表示例（在你自己的数据库中执行）
-- 字符集 utf8mb4

CREATE TABLE IF NOT EXISTS dist_users (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT NOT NULL DEFAULT 0,
  username VARCHAR(100) NOT NULL DEFAULT '',
  phone VARCHAR(50) NOT NULL DEFAULT '',
  join_time INT NOT NULL DEFAULT 0,
  balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  total_commission DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  total_orders INT NOT NULL DEFAULT 0,
  total_team INT NOT NULL DEFAULT 0,
  level1_team INT NOT NULL DEFAULT 0,
  level2_team INT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dist_products (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  status TINYINT NOT NULL DEFAULT 1,
  commission1 DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  commission2 DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  commission3 DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 默认一条启用中的佣金配置（佣金比例可按需修改）
INSERT INTO dist_products (status, commission1, commission2, commission3)
SELECT 1, 0.00, 0.00, 0.00
WHERE NOT EXISTS (SELECT 1 FROM dist_products);
