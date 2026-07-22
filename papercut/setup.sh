#!/bin/bash
#===============================================================================
# PaperCut NG Zabbix Monitoring — Setup Script
# Run this on the PaperCut server (Debian 12 Bookworm) as root
#
# Usage: sudo bash setup.sh
#===============================================================================

set -e

echo "=========================================="
echo " PaperCut NG Zabbix Monitoring Setup"
echo "=========================================="

# ─── Configuration ───────────────────────────────────────────────────────────
ZABBIX_SERVER="10.1.2.61"
HOSTNAME="Papercut"
SCRIPTS_DIR="/usr/local/bin"
AGENT_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
SCRIPT_SOURCE="./scripts"
AGENT_SOURCE="./agent"

# ─── Check we're running as root ─────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root: sudo bash setup.sh"
    exit 1
fi

# ─── Check we're in the right directory ──────────────────────────────────────
if [ ! -d "$SCRIPT_SOURCE" ] || [ ! -d "$AGENT_SOURCE" ]; then
    echo "ERROR: This script must be run from the papercut/ directory."
    echo "  cd /path/to/NOMMA-ZABBIX/papercut"
    echo "  sudo bash setup.sh"
    exit 1
fi

# ─── Step 1: Install Zabbix Agent 2 (if not present) ────────────────────────
echo ""
echo "[1/7] Checking Zabbix Agent 2..."
if ! command -v zabbix_agent2 &> /dev/null; then
    echo "  Zabbix Agent 2 not found. Installing..."
    wget -q https://repo.zabbix.com/zabbix/7.2/debian/pool/main/z/zabbix-release/zabbix-release_7.2-1+debian12_all.deb
    dpkg -i zabbix-release_7.2-1+debian12_all.deb
    apt update
    apt install -y zabbix-agent2
    rm -f zabbix-release_7.2-1+debian12_all.deb
    echo "  Zabbix Agent 2 installed."
else
    echo "  Zabbix Agent 2 already installed: $(zabbix_agent2 --version 2>&1 | head -1)"
fi

# ─── Step 2: Configure Zabbix Agent 2 ───────────────────────────────────────
echo ""
echo "[2/7] Configuring Zabbix Agent 2..."
AGENT_CONF="/etc/zabbix/zabbix_agent2.conf"
if [ -f "$AGENT_CONF" ]; then
    # Set Server
    if grep -q "^Server=" "$AGENT_CONF"; then
        sed -i "s/^Server=.*/Server=$ZABBIX_SERVER/" "$AGENT_CONF"
    else
        echo "Server=$ZABBIX_SERVER" >> "$AGENT_CONF"
    fi
    # Set ServerActive
    if grep -q "^ServerActive=" "$AGENT_CONF"; then
        sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER/" "$AGENT_CONF"
    else
        echo "ServerActive=$ZABBIX_SERVER" >> "$AGENT_CONF"
    fi
    # Set Hostname
    if grep -q "^Hostname=" "$AGENT_CONF"; then
        sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" "$AGENT_CONF"
    else
        echo "Hostname=$HOSTNAME" >> "$AGENT_CONF"
    fi
    echo "  Agent configured: Server=$ZABBIX_SERVER, Hostname=$HOSTNAME"
else
    echo "  WARNING: $AGENT_CONF not found. Creating minimal config..."
    cat > "$AGENT_CONF" <<EOCONF
Server=$ZABBIX_SERVER
ServerActive=$ZABBIX_SERVER
Hostname=$HOSTNAME
Include=/etc/zabbix/zabbix_agent2.d/*.conf
EOCONF
fi

# ─── Step 3: Deploy custom scripts ──────────────────────────────────────────
echo ""
echo "[3/7] Deploying health check scripts..."
install -m 755 "$SCRIPT_SOURCE/papercut_health.sh" "$SCRIPTS_DIR/papercut_health.sh"
install -m 755 "$SCRIPT_SOURCE/papercut_printers.sh" "$SCRIPTS_DIR/papercut_printers.sh"
install -m 755 "$SCRIPT_SOURCE/papercut_activity.sh" "$SCRIPTS_DIR/papercut_activity.sh"
echo "  Scripts installed to $SCRIPTS_DIR"

# ─── Step 4: Deploy Zabbix Agent 2 config ───────────────────────────────────
echo ""
echo "[4/7] Deploying Zabbix Agent 2 UserParameter config..."
mkdir -p "$AGENT_CONF_DIR"
install -m 644 "$AGENT_SOURCE/papercut.conf" "$AGENT_CONF_DIR/papercut.conf"
echo "  Config installed to $AGENT_CONF_DIR/papercut.conf"

# ─── Step 5: Configure sudo for Zabbix user ─────────────────────────────────
echo ""
echo "[5/7] Configuring sudo access for zabbix user..."
SUDOERS_FILE="/etc/sudoers.d/zabbix-papercut"
if [ ! -f "$SUDOERS_FILE" ]; then
    cat > "$SUDOERS_FILE" <<EOSUDO
# Allow zabbix user to run PaperCut health checks without password
zabbix ALL=(ALL) NOPASSWD: /usr/local/bin/papercut_health.sh
zabbix ALL=(ALL) NOPASSWD: /usr/local/bin/papercut_printers.sh
zabbix ALL=(ALL) NOPASSWD: /usr/local/bin/papercut_activity.sh
EOSUDO
    chmod 440 "$SUDOERS_FILE"
    echo "  Sudoers entry created at $SUDOERS_FILE"
else
    echo "  Sudoers entry already exists."
fi

# ─── Step 6: Verify PaperCut server-command is accessible ────────────────────
echo ""
echo "[6/7] Verifying PaperCut server-command..."
SERVER_CMD="/home/papercut/server/bin/linux/server-command"
if [ -x "$SERVER_CMD" ]; then
    echo "  server-command found: $SERVER_CMD"
    # Test basic connectivity
    if $SERVER_CMD health-check &>/dev/null; then
        echo "  PaperCut health check: OK"
    else
        echo "  WARNING: server-command exists but health check failed."
        echo "  Is PaperCut Application Server running?"
    fi
else
    echo "  WARNING: server-command not found at $SERVER_CMD"
    echo "  Is PaperCut NG installed at /home/papercut/server?"
    echo "  The scripts will fall back to API checks, but some features may be limited."
fi

# ─── Step 7: Restart Zabbix Agent 2 ─────────────────────────────────────────
echo ""
echo "[7/7] Restarting Zabbix Agent 2..."
systemctl restart zabbix-agent2
systemctl enable zabbix-agent2
if systemctl is-active --quiet zabbix-agent2; then
    echo "  Zabbix Agent 2 is running."
else
    echo "  ERROR: Zabbix Agent 2 failed to start. Check: journalctl -u zabbix-agent2"
    exit 1
fi

# ─── Test ─────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " Testing custom checks..."
echo "=========================================="
for check in appserver db_connection db_pool license; do
    result=$(sudo -u zabbix "$SCRIPTS_DIR/papercut_health.sh" "$check" 2>/dev/null)
    echo "  papercut_health.sh $check → $result"
done

for check in total online offline; do
    result=$(sudo -u zabbix "$SCRIPTS_DIR/papercut_printers.sh" "$check" 2>/dev/null)
    echo "  papercut_printers.sh $check → $result"
done

result=$(sudo -u zabbix "$SCRIPTS_DIR/papercut_activity.sh" minutes_since 2>/dev/null)
echo "  papercut_activity.sh minutes_since → $result"

echo ""
echo "=========================================="
echo " Testing Zabbix Agent 2 responses..."
echo "=========================================="
zabbix_agent2 -t papercut.appserver.status
zabbix_agent2 -t papercut.db.connection
zabbix_agent2 -t papercut.printers.total
zabbix_agent2 -t papercut.activity.minutes_since

echo ""
echo "=========================================="
echo " SETUP COMPLETE"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Import the template into Zabbix:"
echo "     - Go to Configuration → Templates → Import"
echo "     - Select: papercut/templates/papercut_template.yaml"
echo ""
echo "  2. Link the template to the 'Papercut' host:"
echo "     - Configuration → Hosts → Papercut → Templates"
echo "     - Add 'PaperCut NG by Zabbix Agent 2'"
echo ""
echo "  3. View monitoring at:"
echo "     http://$ZABBIX_SERVER/zabbix"
echo "     Monitoring → Latest Data → Host: Papercut"
echo "=========================================="