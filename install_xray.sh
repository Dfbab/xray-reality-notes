#!/bin/bash
# Xray VLESS-REALITY 一键安装脚本
# 2026-11-05 在 GCP Debian 12/13 上验证通过
#
# 用法：把本文件上传到服务器（或复制内容到服务器），然后执行：
#   sudo bash install_xray.sh
#
# 安装完最后会输出一行 vless:// 链接，复制到 Clash Verge 导入即可。
# 注意：运行前确保云服务器安全组/防火墙已放行 TCP 443。

set -e

# 1. 安装 Xray 官方包（创建 systemd 服务）
curl -Ls -o /tmp/xray-install.sh https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh
sudo bash /tmp/xray-install.sh install

# 2. 降级到 25.3.6（26.x 的 REALITY 与 Clash/mihomo 不兼容）
curl -L -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/v25.3.6/Xray-linux-64.zip
sudo unzip -o /tmp/xray.zip -d /usr/local/bin xray

# 3. 生成 UUID / 密钥 / shortId
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$(sudo /usr/local/bin/xray x25519)
PRIV=$(echo "$KEYS" | grep -i "private" | awk '{print $NF}')
PUB=$(echo "$KEYS" | grep -i "public" | awk '{print $NF}')
SHORT=$(openssl rand -hex 8)

# 4. 写配置（dest 必须用 www.cloudflare.com；用 microsoft 会导致 REALITY 认证失败）
sudo tee /usr/local/etc/xray/config.json >/dev/null <<EOF
{
"inbounds":[{"port":443,"protocol":"vless","settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"www.cloudflare.com:443","serverNames":["www.cloudflare.com"],"privateKey":"$PRIV","shortIds":["$SHORT"]}}}],
"outbounds":[{"protocol":"freedom"}]
}
EOF

# 5. 重启服务
sudo systemctl restart xray
sleep 1

# 6. 输出导入链接
IP=$(curl -s4 ifconfig.me)
echo ""
echo "================== 复制下面这行到 Clash =================="
echo "vless://${UUID}@${IP}:443?encryption=none&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=${PUB}&sid=${SHORT}&type=tcp#Xray-Reality"
echo "=========================================================="
echo ""
echo "参数备份："
echo "  UUID=$UUID"
echo "  私钥=$PRIV"
echo "  公钥=$PUB"
echo "  shortId=$SHORT"
