# 用 GCP 免费层自建 Xray-REALITY 的踩坑记录（2026-11）

> 作者：张阳飞（[@Dfbab](https://github.com/Dfbab)）× 宇歌（AI 助手）
>
> 一篇写给后来者的实录：哪些坑是真的坑，哪些“教程”已经过期。

## 背景

想用免费云搭一条自己的翻墙线路：VLESS + REALITY，客户端 Clash Verge（mihomo 内核）。
平台选 Google Cloud 免费试用（$300 / 90 天，e2-micro 免费层）。

结论先说：**GCP 免费层不适合长期翻墙**，但整个流程和本文的坑对所有 VPS 都适用。

---

## 1. 注册：2026 年起要预付 HK$250

- Google Cloud 免费试用现在要求**一次性预付 HK$250**（约 230 人民币）才能激活，
  不是以前教程里的“$1 卡验证”。
- 预付的是**余额**，不是费用，用不完可以申请退款。
- 国家/地区列表里**没有中国大陆**，香港可用（中国大陆需走代理商，没有免费层）。
- 香港虚拟银行（如 ZA Bank）的 Visa 借记卡可以绑定成功。

## 2. 建机

- e2-micro（2 vCPU 共享 / 1GB），us-central1，Debian 13。
- 防火墙默认只开 22。需要手动加 `tcp:443` 入站规则（目标“网络中的所有实例”，来源 `0.0.0.0/0`）。
- **浏览器 SSH 里的 gcloud 权限不足**（`Request had insufficient authentication scopes`），
  防火墙规则只能在控制台加。

## 3. 核心坑：Xray 26.x 的 REALITY 与 mihomo 不兼容

### 现象

服务端配置 `Configuration OK`，TLS 握手正常（`openssl s_client` 能拿到目标站证书），
但 Clash（mihomo 1.19）连不上，debug 日志：

```
REALITY Authentication: false, AEAD: *gcm.GCM
```

客户端 `/proxies/<node>/delay` 返回 `503 Service Unavailable`。

### 排查过程

1. `xray x25519 -i <私钥>` 验证公钥——配对正确。
2. shortId、serverNames、SNI 全部一致。
3. 目标站 `www.microsoft.com` 确认支持 TLS 1.3。
4. `GODEBUG=tlsmlkem=0` 禁用 ML-KEM——无效（Go 1.27 不认这个开关）。

### 根因与解决

Xray 26.10 与 mihomo 1.19 在 REALITY 握手层存在兼容问题，且 `dest: www.microsoft.com`
在该组合下认证失败。解决组合：

1. 服务端降级到 **Xray 25.3.6**：
   ```bash
   curl -L -o /tmp/x.zip https://github.com/XTLS/Xray-core/releases/download/v25.3.6/Xray-linux-64.zip
   sudo unzip -o /tmp/x.zip -d /usr/local/bin xray
   sudo systemctl restart xray
   ```
   （注意：`install-release.sh` 的 `-v` 参数在 26.x 上不可用，直接下载 zip 覆盖二进制。）
2. 把 REALITY 的 `dest` / `serverNames` 换成 **www.cloudflare.com**。
3. 重启后 mihomo 延迟测试返回 1082–1821ms，**通了**。

## 4. “IP 被墙”的正确识别方式

台湾 asia-east1 实例：`ping` 通（197ms），但 **TCP 22/443 全部超时**。

这不是防火墙配错，是 **IP 被 GFW 封锁**（GCP 亚洲 IP 段常见）。

判别方法：先 ping，再测 TCP 端口。**ping 通 ≠ 能用**。

## 5. 浏览器 SSH 粘贴长命令会被折断

GCP 的浏览器 SSH 终端会在约 80 字符处**插入真实换行**，导致：

- 长命令被拆成多条执行；
- base64 / heredoc 直接失效；
- 写入的 JSON 字符串中间被插入换行，Xray 报 `invalid character '\n' in string`。

对策：

- 每条命令 **<70 字符**，分步粘贴；
- 写多行 JSON 用 `nano`，不要用长 heredoc；
- 用变量缩短长 URL，例如：
  ```bash
  B=https://github.com/XTLS/Xray-core/releases/download/
  V=v25.3.6/Xray-linux-64.zip
  curl -L -o /tmp/x.zip $B$V
  ```

## 6. 一键安装脚本

见本仓库 [`install_xray.sh`](install_xray.sh)。在服务器上执行：

```bash
sudo bash install_xray.sh
```

脚本会：安装 Xray → 降级 25.3.6 → 生成 UUID/密钥/shortId → 写 REALITY 配置（cloudflare dest）
→ 启动服务 → 输出一行 `vless://` 链接（直接导入 Clash）。

## 7. 结论

| 项目 | 实测 |
|---|---|
| GCP 免费层流量 | 1GB/月出站，翻墙不够用 |
| GCP 美国（us-central1） | 延迟 ~1.5s，下载 ~0.1MB/s |
| GCP 台湾（asia-east1） | IP 被墙，TCP 全超时 |
| 90 天后 | 需付费，否则服务暂停 |

**推荐做法**：免费云只适合练手。长期用，花 $10/年买台 RackNerd（支持支付宝），
IP 被封花 $3 自助换一个，流量 1–3TB/月，体验稳定得多。

---

*本文所有 IP、UUID、密钥均已脱敏。*
