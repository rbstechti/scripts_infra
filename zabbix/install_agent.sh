#!/bin/bash

if [ -z "$1" ]; then
  echo "Uso: $0 <API_TOKEN>"
  exit 1
fi

ZABBIX_SERVER="zbx.suporterbs.com.br"
ZABBIX_URL="https://zbx.suporterbs.com.br/api_jsonrpc.php"
ZABBIX_TOKEN="$1"

HOSTNAME=$(hostname)

echo "Hostname: $HOSTNAME"

apt update -y
apt install wget curl jq -y

wget -q https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest+debian12_all.deb -O /tmp/zabbix-release.deb
dpkg -i /tmp/zabbix-release.deb
apt update -y

apt install zabbix-agent -y

CONF_FILE="/etc/zabbix/zabbix_agentd.conf"

sed -i "s/^Server=.*/Server=${ZABBIX_SERVER}/" $CONF_FILE
sed -i "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER}/" $CONF_FILE
sed -i "s/^Hostname=.*/Hostname=${HOSTNAME}/" $CONF_FILE

sed -i "s/^# ListenIP=.*/ListenIP=0.0.0.0/" $CONF_FILE

systemctl restart zabbix-agent
systemctl enable zabbix-agent

echo "Agent configurado!"

# =========================
# GROUP ID
# =========================
GROUP_ID=$(curl -s -X POST -H 'Content-Type: application/json' \
-d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"hostgroup.get\",
    \"params\": {
        \"filter\": {\"name\": [\"Clientes/CLASSIFICAR"]}
    },
    \"auth\": \"$ZABBIX_TOKEN\",
    \"id\": 1
}" $ZABBIX_URL | jq -r '.result[0].groupid')

echo "Group ID: $GROUP_ID"

# =========================
# TEMPLATE ID
# =========================
TEMPLATE_ID=$(curl -s -X POST -H 'Content-Type: application/json' \
-d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"template.get\",
    \"params\": {
        \"filter\": {\"host\": [\"Linux by Zabbix agent active\"]}
    },
    \"auth\": \"$ZABBIX_TOKEN\",
    \"id\": 1
}" $ZABBIX_URL | jq -r '.result[0].templateid')

echo "Template ID: $TEMPLATE_ID"

echo "Criando host..."

curl -s -X POST -H 'Content-Type: application/json' \
-d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"host.create\",
    \"params\": {
        \"host\": \"$HOSTNAME\",
        \"groups\": [{\"groupid\": \"$GROUP_ID\"}],
        \"templates\": [{\"templateid\": \"$TEMPLATE_ID\"}],
        \"interfaces\": [{
            \"type\": 1,
            \"main\": 1,
            \"useip\": 1,
            \"ip\": \"127.0.0.1\",
            \"dns\": \"\",
            \"port\": \"10050\"
        }]
    },
    \"auth\": \"$ZABBIX_TOKEN\",
    \"id\": 1
}" $ZABBIX_URL

echo "Host criado no RBS Tech ZBX-SV-0001"
