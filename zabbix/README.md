# Zabbix Agent Auto Install

## Uso

```bash
wget https://raw.githubusercontent.com/rbstechti/scripts_infra/main/zabbix/install_agent.sh -O install_agent.sh
chmod +x install_agent.sh
./install_agent.sh TOKEN

```bash
Invoke-WebRequest "https://raw.githubusercontent.com/rbstechti/scripts_infra/main/zabbix/install_agent_windows" -OutFile install_agent.ps1
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install_agent.ps1 TOKEN
