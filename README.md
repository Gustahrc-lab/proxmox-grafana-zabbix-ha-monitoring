##    Proxmox + Grafana + Zabbix + HA Monitoring Stack  ##  


##   Stack completo de monitoramento corporativo implantado em ambiente de Alta Disponibilidade, simulando infraestrutura de produção real.  ##  


##  Arquitetura  ##  
```
Cluster Proxmox HA (pve1 + pve2 + pve3)
└── VM Debian 12 
      ├── Nginx (proxy reverso)
      └── Docker
            ├── Grafana 11.6.0
            ├── Zabbix Server 7.0
            ├── Zabbix Frontend 7.0
            └── MySQL 8.0

OPNsense (Firewall/Gateway)
└── Segmentação de redes CLUSTER1/CLUSTER2/INTRANET/EXTRANET

Active Directory (Windows Server 2022)
└── Autenticação LDAP centralizada
```

 Tecnologias

| Tecnologia | Função |
|---|---|
| Proxmox VE | Virtualização com cluster HA |
| OPNsense | Firewall e segmentação de redes |
| Debian 12 | SO base da VM de monitoramento |
| Docker + Compose | Containerização dos serviços |
| Grafana 11.6.0 | Visualização e dashboards |
| Zabbix 7.0 | Coleta e alertas de monitoramento |
| MySQL 8.0 | Banco de dados do Zabbix |
| Nginx | Proxy reverso com atualização automática |
| Active Directory | Autenticação centralizada via LDAP |
| systemd | Gerenciamento de serviços e automações |

##   Funcionalidades implementadas  ##  

- Cluster Proxmox HA com 3 nós — VMs reiniciam automaticamente em falha de nó
- Segmentação de redes por função (CLUSTER, INTRANET, EXTRANET)
- Stack de monitoramento 100% containerizada com Docker Compose
- Proxy reverso Nginx com script systemd que atualiza IPs automaticamente no boot
- Autenticação LDAP integrada ao Active Directory com service account dedicada
- Rede permanente via systemd-networkd resistente a reboots
- Firewall OPNsense com regras granulares por origem e destino

##  Estrutura do projeto  ##  
```
/opt/monitoring/
├── docker-compose.yml
└── grafana/
    └── config/
        └── ldap.toml


##  Como usar  ##  


```bash
git clone https://github.com/Gustahrc-lab/proxmox-grafana-zabbix-ha-monitoring.git
cd proxmox-grafana-zabbix-ha-monitoring
docker compose up -d
```

Acesse:
- Grafana: `http://<IP>:3000` → admin / admin123
- Zabbix: `http://<IP>:8080` → Admin / zabbix

##  Segurança aplicada  ##  

- Princípio do menor privilégio — usuário dedicado por serviço
- Service account no AD exclusiva para autenticação LDAP
- SSH sem login root, com UseDNS desabilitado
- UFW com regras por rede de origem
- Imagens Docker Alpine (menor superfície de ataque)
- ldap.toml montado via volume (sem exposição de credenciais no container)

##  Documentação completa ## 


A documentação completa com passo a passo de toda a implantação está disponível [aqui] (./docs/manual.md)

##  Autor  ##

**Gustavo Cunha** — Analista de Infraestrutura  
[LinkedIn](https://linkedin.com/in/gustahrc) • [GitHub](https://github.com/Gustahrc-lab)




