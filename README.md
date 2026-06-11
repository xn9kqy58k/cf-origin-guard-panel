# cf-origin-guard-panel

`cf-origin-guard-panel` 是一个用于 aaPanel / 宝塔国际版 / 普通 Nginx 服务器的 Cloudflare 源站保护工具。

安装后，在 VPS 里输入：

```bash
cf
```

会打开一个终端可视化开关面板，用来控制：

- 源站保护开关：只允许 Cloudflare IP 访问 80/443；
- 自动同步 Cloudflare IP；
- Nginx `real_ip` 开关；
- IPv6 防护模式；
- 保护端口；
- DROP / REJECT 拦截方式；
- 额外直连白名单；
- 域名和源站 IP 验证。

> 默认安全策略：安装完成后不会立刻封锁 80/443。需要手动输入 `cf`，选择 `1) 源站保护开关` 后才会正式启用 Cloudflare-only 源站访问限制。

---

## 适合场景

适合 xiaov2board / v2board / 机场面板这类需要隐藏源站 IP 的 Web 面板。

典型目标：

```text
访客 / 节点 / 回调服务
        ↓
Cloudflare 橙云域名
        ↓
源站 VPS Nginx / xiaov2board
```

启用后，源站 VPS 的 `80,443` 默认只允许：

```text
Cloudflare 官方 IPv4 段
Cloudflare 官方 IPv6 段
你手动加入的额外白名单 IP
本机 loopback
```

非 Cloudflare 直连源站 IP 会被防火墙拦截。

---

## 安装

```bash
git clone https://github.com/你的用户名/cf-origin-guard-panel.git
cd cf-origin-guard-panel
bash install.sh
```

安装完成后打开面板：

```bash
cf
```

也可以直接查看状态：

```bash
cf status
```

---

## 面板菜单

输入 `cf` 后会显示：

```text
Cloudflare Origin Guard 可视化面板

  1) 源站保护开关          已关闭    实际防火墙: 未生效
  2) 自动同步 CF IP         已开启    每天同步 Cloudflare 官方 IP 段
  3) Nginx 真实 IP          已关闭    real_ip: 未生成
  4) IPv6 防护模式          auto      IPv6 防火墙: 未生效
  5) 保护端口               80,443
  6) 拦截方式               DROP
  7) 额外白名单             IPv4/IPv6 直连白名单
  8) 立即同步并应用         下载 CF IP + 刷新规则
  9) 查看详细状态           iptables / ipset / timer
 10) 验证站点               域名访问 + 源站直连测试
 11) 删除防火墙规则          关闭保护并恢复 80/443 直连
 12) 打开配置文件路径        显示配置位置和常用命令

  0) 退出
```

---

## 推荐上线顺序

### 1. 确认域名是 Cloudflare 橙云

Cloudflare DNS 里应该是：

```text
panel.example.com  A/AAAA  源站IP  Proxied / 橙云
```

不要是灰云 DNS-only。

### 2. 安装工具

```bash
git clone https://github.com/你的用户名/cf-origin-guard-panel.git
cd cf-origin-guard-panel
bash install.sh
```

### 3. 打开面板

```bash
cf
```

### 4. 开启源站保护

选择：

```text
1) 源站保护开关
```

确认后工具会：

```text
1. 下载 Cloudflare 官方 IPv4 / IPv6 IP 段
2. 写入 ipset
3. 创建 iptables / ip6tables 过滤链
4. 把 80/443 限制为只允许 Cloudflare IP 和额外白名单访问
```

### 5. 验证源站直连是否被挡

菜单选择：

```text
10) 验证站点
```

或命令行执行：

```bash
cf verify panel.example.com 源站IP
```

预期：

```text
正常域名访问：HTTP/2 200 或 302
源站直连访问：timeout / connection reset / no HTTP response
```

---

## 常用命令

```bash
cf                    # 打开可视化面板
cf status             # 查看状态
cf apply              # 同步 Cloudflare IP 并按配置应用
cf remove             # 删除防火墙规则并关闭源站保护
cf realip             # 重新生成 Nginx real_ip 配置
cf realip-off         # 删除生成的 Nginx real_ip 配置
cf verify 域名 源站IP  # 验证正常访问和直连拦截
```

高级命令名：

```bash
cf-origin-guard status
```

---

## 配置文件

配置文件路径：

```bash
/etc/cf-origin-guard/cf-origin-guard.conf
```

核心配置：

```bash
ENABLE_GUARD="0"
ENABLE_AUTO_SYNC="1"
WEB_PORTS="80,443"
ENABLE_IPV6="auto"
DROP_ACTION="DROP"
MANAGE_NGINX_REALIP="0"
EXTRA_ALLOWLIST_IPV4=""
EXTRA_ALLOWLIST_IPV6=""
```

说明：

| 配置 | 说明 |
|---|---|
| `ENABLE_GUARD` | 源站保护总开关，`1` 开启，`0` 关闭 |
| `ENABLE_AUTO_SYNC` | 自动同步开关 |
| `WEB_PORTS` | 要保护的 TCP 端口，默认 `80,443` |
| `ENABLE_IPV6` | `auto` / `1` / `0` |
| `DROP_ACTION` | `DROP` 更隐蔽，`REJECT` 更方便测试 |
| `MANAGE_NGINX_REALIP` | 是否生成 Nginx real_ip 配置 |
| `EXTRA_ALLOWLIST_IPV4` | 额外允许直连的 IPv4 CIDR |
| `EXTRA_ALLOWLIST_IPV6` | 额外允许直连的 IPv6 CIDR |

---

## Nginx real_ip

默认不开启，避免改变现有 Nginx 行为。

需要 xiaov2board / Nginx 日志显示真实访客 IP 时，在 `cf` 面板中选择：

```text
3) Nginx 真实 IP
```

开启后会生成：

```text
/www/server/panel/vhost/nginx/cf-origin-guard-realip.conf
```

或普通 Nginx：

```text
/etc/nginx/conf.d/cf-origin-guard-realip.conf
```

生成后工具会自动执行：

```bash
nginx -t
```

测试通过才会 reload Nginx。失败会自动回滚。

---

## 额外白名单

如果有支付回调、监控服务、上游反代、节点后端必须绕过 Cloudflare 直连源站，可以在面板里选择：

```text
7) 额外白名单
```

示例：

```text
203.0.113.10/32 198.51.100.0/24
```

修改后如果源站保护已开启，工具会自动重新应用规则。

---

## 自动同步 Cloudflare IP

安装后默认开启 systemd timer 或 cron fallback。

查看 timer：

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

关闭自动同步：

```bash
cf
# 选择 2) 自动同步 CF IP
```

---

## 卸载

保留配置：

```bash
bash uninstall.sh
```

完全清理：

```bash
bash uninstall.sh --purge
```

紧急恢复 80/443 直连：

```bash
cf remove
```

---

## 不会自动影响的内容

默认情况下：

| 项目 | 默认是否修改 |
|---|---|
| xiaov2board 站点文件 | 不修改 |
| Nginx vhost 文件 | 不修改 |
| Nginx real_ip | 不开启，需要手动开关 |
| 80/443 防火墙限制 | 不立即开启，需要手动开关 |
| SSH 端口 | 不修改 |
| aaPanel 管理端口 | 不修改 |
| 节点后端端口 | 不修改，除非你写进 `WEB_PORTS` |

开启源站保护后，所有跑在 `WEB_PORTS` 上且没有经过 Cloudflare 的直连访问都会被拦截。
