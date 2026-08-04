#!/usr/bin/env bash
set -Eeuo pipefail

# Instalador do Zabbix Proxy 7.0 LTS para Debian 13 (Trixie)
# Uso:
#   sudo bash install-zabbix-proxy.sh CAL-CT-0002
#   sudo bash install-zabbix-proxy.sh CAL-CT-0002 zbx.suporterbs.com.br
#
# Variáveis opcionais:
#   ZABBIX_SERVER, SERVER_PORT, DB_PATH
#   TIMEOUT, CACHE_SIZE, HISTORY_CACHE_SIZE, HISTORY_INDEX_CACHE_SIZE
#   START_POLLERS, START_UNREACHABLE, START_SNMP_POLLERS
#   START_PINGERS, START_DISCOVERERS
#   CONFIG_FREQUENCY, DATA_SENDER_FREQUENCY, LOG_SLOW_QUERIES

PROXY_HOSTNAME="${1:-}"
ZABBIX_SERVER="${2:-${ZABBIX_SERVER:-zbx.suporterbs.com.br}}"

SERVER_PORT="${SERVER_PORT:-10051}"
DB_PATH="${DB_PATH:-/var/lib/zabbix/zabbix_proxy.db}"
CONF_FILE="/etc/zabbix/zabbix_proxy.conf"
SCHEMA_FILE="/usr/share/zabbix-sql-scripts/sqlite3/proxy.sql"
REPO_DEB="/tmp/zabbix-release_latest_7.0+debian13_all.deb"
REPO_URL="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian13_all.deb"

TIMEOUT="${TIMEOUT:-20}"
CACHE_SIZE="${CACHE_SIZE:-128M}"
HISTORY_CACHE_SIZE="${HISTORY_CACHE_SIZE:-64M}"
HISTORY_INDEX_CACHE_SIZE="${HISTORY_INDEX_CACHE_SIZE:-32M}"
START_POLLERS="${START_POLLERS:-20}"
START_UNREACHABLE="${START_UNREACHABLE:-5}"
START_SNMP_POLLERS="${START_SNMP_POLLERS:-10}"
START_PINGERS="${START_PINGERS:-10}"
START_DISCOVERERS="${START_DISCOVERERS:-3}"
CONFIG_FREQUENCY="${CONFIG_FREQUENCY:-60}"
DATA_SENDER_FREQUENCY="${DATA_SENDER_FREQUENCY:-5}"
LOG_SLOW_QUERIES="${LOG_SLOW_QUERIES:-3000}"

log()  { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'die "Falha na linha $LINENO. Verifique a saída acima."' ERR

[[ $EUID -eq 0 ]] || die "Execute como root."
[[ -n "$PROXY_HOSTNAME" ]] || die "Informe o hostname do proxy. Ex.: $0 CAL-CT-0002"

source /etc/os-release
[[ "${ID:-}" == "debian" ]] || die "Este script foi criado para Debian."
[[ "${VERSION_ID:-}" == "13" ]] || die "Versão detectada: ${VERSION_ID:-desconhecida}. É necessário Debian 13."

set_param() {
    local key="$1"
    local value="$2"

    if grep -Eq "^[[:space:]]*${key}=" "$CONF_FILE"; then
        sed -Ei "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$CONF_FILE"
    elif grep -Eq "^[[:space:]]*#?[[:space:]]*${key}=" "$CONF_FILE"; then
        sed -Ei "0,/^[[:space:]]*#?[[:space:]]*${key}=.*/s||${key}=${value}|" "$CONF_FILE"
    else
        printf '\n%s=%s\n' "$key" "$value" >> "$CONF_FILE"
    fi
}

log "Atualizando o Debian 13..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "Instalando dependências básicas..."
DEBIAN_FRONTEND=noninteractive apt-get install -y wget ca-certificates gnupg

log "Configurando o repositório oficial do Zabbix 7.0..."
wget -qO "$REPO_DEB" "$REPO_URL"
dpkg -i "$REPO_DEB"
apt-get update

log "Instalando Zabbix Proxy SQLite e ferramentas..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    zabbix-proxy-sqlite3 \
    zabbix-sql-scripts \
    sqlite3 \
    snmp \
    curl \
    netcat-openbsd

[[ -f "$CONF_FILE" ]] || die "Arquivo não encontrado: $CONF_FILE"
[[ -f "$SCHEMA_FILE" ]] || die "Schema não encontrado: $SCHEMA_FILE"

log "Preparando o banco SQLite..."
install -d -o zabbix -g zabbix -m 0755 "$(dirname "$DB_PATH")"

if [[ ! -s "$DB_PATH" ]]; then
    rm -f "$DB_PATH"
    sqlite3 "$DB_PATH" < "$SCHEMA_FILE"
    ok "Banco SQLite criado e schema importado."
else
    ok "Banco existente encontrado; importação ignorada."
fi

chown zabbix:zabbix "$DB_PATH"
chmod 0640 "$DB_PATH"

log "Criando backup da configuração..."
BACKUP_FILE="${CONF_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$CONF_FILE" "$BACKUP_FILE"
ok "Backup salvo em: $BACKUP_FILE"

log "Aplicando configuração do proxy..."
set_param "ProxyMode" "0"
set_param "Server" "$ZABBIX_SERVER"
set_param "ServerPort" "$SERVER_PORT"
set_param "Hostname" "$PROXY_HOSTNAME"
set_param "DBName" "$DB_PATH"

set_param "ConfigFrequency" "$CONFIG_FREQUENCY"
set_param "DataSenderFrequency" "$DATA_SENDER_FREQUENCY"
set_param "Timeout" "$TIMEOUT"

set_param "CacheSize" "$CACHE_SIZE"
set_param "HistoryCacheSize" "$HISTORY_CACHE_SIZE"
set_param "HistoryIndexCacheSize" "$HISTORY_INDEX_CACHE_SIZE"

set_param "StartPollers" "$START_POLLERS"
set_param "StartPollersUnreachable" "$START_UNREACHABLE"
set_param "StartSNMPPollers" "$START_SNMP_POLLERS"
set_param "StartPingers" "$START_PINGERS"
set_param "StartDiscoverers" "$START_DISCOVERERS"

set_param "LogSlowQueries" "$LOG_SLOW_QUERIES"

log "Garantindo a criação persistente de /run/zabbix..."
cat > /etc/tmpfiles.d/zabbix.conf <<'EOF'
d /run/zabbix 0755 zabbix zabbix -
EOF
systemd-tmpfiles --create /etc/tmpfiles.d/zabbix.conf

log "Validando a configuração..."
zabbix_proxy -c "$CONF_FILE" -T

log "Habilitando e iniciando o serviço..."
systemctl enable zabbix-proxy
systemctl restart zabbix-proxy

if systemctl is-active --quiet zabbix-proxy; then
    ok "Zabbix Proxy está ativo."
else
    systemctl status zabbix-proxy --no-pager -l || true
    journalctl -u zabbix-proxy -n 50 --no-pager || true
    die "O serviço não iniciou."
fi

cat <<EOF

============================================================
 INSTALAÇÃO CONCLUÍDA
============================================================
Hostname do Proxy : $PROXY_HOSTNAME
Servidor Zabbix   : $ZABBIX_SERVER:$SERVER_PORT
Banco SQLite      : $DB_PATH
Configuração      : $CONF_FILE

Próximo passo no frontend:
  Administration -> Proxies -> Create proxy
  Name: $PROXY_HOSTNAME
  Mode: Active

Comandos úteis:
  systemctl status zabbix-proxy
  tail -f /var/log/zabbix/zabbix_proxy.log
  nc -zv $ZABBIX_SERVER $SERVER_PORT
============================================================
EOF
