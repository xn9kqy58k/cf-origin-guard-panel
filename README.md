# cf-origin-guard-panel

一个 Cloudflare 源站保护工具。安装后输入 `cf` 打开操作面板，可一键开启/关闭源站保护，并自动同步 Cloudflare 官方 IP。

适用于 aaPanel / 宝塔国际版 / 普通 Nginx 环境，例如 xiaov2board、v2board 或其他通过 Cloudflare 橙云访问的 Web 站点。

## 主要功能

- 只允许 Cloudflare IP 访问源站 `80/443`
- 自动同步 Cloudflare IPv4 / IPv6 IP 段
- 支持 IPv6 防护
- 支持额外白名单 IP
- 支持 DROP / REJECT 拦截模式
- 支持 Nginx 真实访客 IP `real_ip`
- 支持一键验证源站是否还能被直连

> 默认安装后不会立刻封锁端口。需要手动输入 `cf`，在面板中开启源站保护。

## 安装

```bash
git clone https://github.com/xn9kqy58k/cf-origin-guard-panel.git
cd cf-origin-guard-panel
bash install.sh
```

打开面板：

```bash
cf
```

## 使用步骤

### 1. 确认域名已开启 Cloudflare 橙云

Cloudflare DNS 中应为：

```text
panel.example.com  A/AAAA  源站IP  Proxied / 橙云
```

不要使用灰云，也不要让业务直连源站 IP。

### 2. 开启源站保护

输入：

```bash
cf
```

选择：

```text
1) 源站保护开关
```

开启后，源站 `80/443` 只允许 Cloudflare IP 和你添加的白名单 IP 访问。

### 3. 验证效果

在面板中选择：

```text
10) 验证站点
```

或执行：

```bash
cf verify panel.example.com 源站IP
```

正常结果：

```text
Cloudflare 域名访问：成功
源站 IP 直连访问：失败、超时或无响应
```

## 常用命令

```bash
cf                    # 打开操作面板
cf status             # 查看状态
cf apply              # 同步 CF IP 并应用规则
cf remove             # 删除防火墙规则，恢复直连
cf realip             # 开启/刷新 Nginx 真实 IP 配置
cf realip-off         # 关闭 Nginx 真实 IP 配置
cf verify 域名 源站IP  # 验证访问效果
```

## 配置文件

配置路径：

```bash
/etc/cf-origin-guard/cf-origin-guard.conf
```

主要配置：

```bash
ENABLE_GUARD="0"          # 源站保护开关
ENABLE_AUTO_SYNC="1"      # 自动同步 CF IP
WEB_PORTS="80,443"        # 保护端口
ENABLE_IPV6="auto"        # IPv6：auto / 1 / 0
DROP_ACTION="DROP"        # DROP 或 REJECT
MANAGE_NGINX_REALIP="0"   # Nginx real_ip 开关
EXTRA_ALLOWLIST_IPV4=""   # 额外 IPv4 白名单
EXTRA_ALLOWLIST_IPV6=""   # 额外 IPv6 白名单
```

这些配置也可以在 `cf` 面板里修改。

## Nginx 真实 IP

默认不开启，避免影响现有 Nginx。

需要让日志或后端程序显示真实访客 IP 时，在面板中选择：

```text
3) Nginx 真实 IP
```

工具会先执行 `nginx -t`，测试通过后才会 reload Nginx。

## 自动同步 Cloudflare IP

默认开启自动同步。

查看定时任务：

```bash
systemctl list-timers cf-origin-guard.timer
```

查看日志：

```bash
journalctl -u cf-origin-guard.service -n 100 --no-pager
```

手动同步：

```bash
cf apply
```

## 注意事项

开启源站保护后，`WEB_PORTS` 中的端口会只允许 Cloudflare IP 访问。

默认只保护：

```text
80,443
```

默认不会修改：

```text
SSH 端口
aaPanel 管理端口
Nginx 站点文件
xiaov2board 程序文件
节点后端端口
```

如果支付回调、监控服务或其他服务需要直连源站，请在面板中添加额外白名单。

## 卸载

保留配置卸载：

```bash
bash uninstall.sh
```

完全清理：

```bash
bash uninstall.sh --purge
```

紧急恢复 `80/443` 直连：

```bash
cf remove
```
