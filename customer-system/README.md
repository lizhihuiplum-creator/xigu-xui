# 系谷 Xigu 客服与分销系统（含授权锁）

由 **系谷 Xigu Tech | Network** 提供的可独立部署 PHP 系统，包含两个模块：

- `chat/`：多站点在线客服（访客匿名、AI 起草与自动回复、双向翻译），前端 `chat_embed.js` 可嵌入任意页面。
- `distribution/`：分销中心（佣金、团队、推广链接），移动端单页。

所有模块默认带 **授权锁**：部署后在未授权域名上无法使用，需向系谷申请并由后台按域名开通。

## 目录结构

```
customer-system/
├─ license_client.php                # 授权客户端（两个模块都依赖，必须保留）
├─ chat/
│  ├─ proactive.php                  # 客服后端（需配置数据库与 AI Key）
│  └─ chat_embed.js                  # 客服前端组件
└─ distribution/
   ├─ distribution.php               # 分销后端（需配置数据库）
   └─ distribution.html              # 分销前端页面
```

## 环境要求

- PHP 8.0+（需 cURL 扩展；无 cURL 时自动回退 file_get_contents）
- MySQL 5.7+ / MariaDB 10.3+
- 服务器需能访问公网（用于向系谷授权服务器校验）

## 安装步骤

1. 将本目录上传到站点，例如 `customer-system/`。
2. 打开后端文件，把占位符替换为你自己的数据库信息：
   - `chat/proactive.php`：
     - `YOUR_DB_HOST` / `YOUR_DB_NAME` / `YOUR_DB_USER` / `YOUR_DB_PASSWORD`
     - `YOUR_ARK_API_KEY`：用于 AI 起草与自动回复的模型密钥（如不使用 AI 功能可留空占位）。
   - `distribution/distribution.php`：
     - `YOUR_DB_HOST` / `YOUR_DB_NAME` / `YOUR_DB_USER` / `YOUR_DB_PASSWORD`
3. 按所用模块在数据库中创建对应数据表（客服表由 `proactive.php` 自动创建；分销表需手动建立 `dist_users`、`dist_products`）。
4. 在需要客服的页面引入前端组件：

```html
<script src="https://你的域名/customer-system/chat/chat_embed.js" async></script>
```

## 授权机制

- 后端每次请求会通过 `license_client.php` 按当前域名向系谷授权服务器校验。
- 校验结果本地缓存 10 分钟；授权服务器短暂不可用时，已授权站点有 7 天宽限，不会被误锁。
- 未授权时后端返回 `403`，前端自动显示锁定界面，可点击「申请使用」或通过下面的联系方式联系我们开通。
- 开通后无需改动代码，缓存到期自动生效。

## 联系方式（开通授权 / 定制 / 售后）

- QQ：**1441673277**
- Telegram：**https://t.me/xigu_support_bot**
- 官方网站：**https://cn.jige.us**

## 免责声明

本软件按现状提供，使用者需自行确保所在地区的法律法规合规。系谷保留对授权开通与停用的最终解释权。
