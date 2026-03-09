Manual Completo — Ambiente de Monitoramento HA com Grafana + Zabbix + LDAP

Sobre o projeto
Este manual documenta a implantação de um ambiente completo de monitoramento corporativo em laboratório, cobrindo desde a criação do template Debian no Proxmox até a integração de ferramentas de observabilidade com autenticação centralizada via Active Directory.
Domínio AD: treinamento.local

Infraestrutura — Alta Disponibilidade (HA)
Cluster Proxmox HA
  ├── pve1 (nó principal)
  ├── pve2
  └── pve3
Redes do ambiente
  Rede          Subnet               Gateway                          Função 
CLUSTER1   192.168.110.0/24     192.168.110.10         Comunicação interna do cluster Proxmox 
CLUSTER2   192.168.120.0/24     192.168.120.10         Replicação e storage do cluster 
INTRANET   192.168.130.0/24     192.168.130.10         Rede interna de servidores
EXTRANET   192.168.140.0/24     192.168.140.10         Rede das VMs com acesso externo
LAN        192.168.1.0/24       192.168.1.200          Rede local — OPNsense 
LANWAN       DHCP               (10.0.2.x)—            Saída para internet via NAT VirtualBox

Topologia completa
PC Principal (192.168.1.11)
  └── VirtualBox
        ├── OPNsense (Firewall/Gateway central)
        │     ├── WAN  → NAT VirtualBox (10.0.2.x) → internet
        │     ├── LAN  → Bridge → 192.168.1.200
        │     ├── CLUSTER1 → 192.168.110.10
        │     ├── CLUSTER2 → 192.168.120.10
        │     ├── INTRANET → 192.168.130.10
        │     └── EXTRANET → 192.168.140.10
        │
        ├── Proxmox HA (pve1 + pve2 + pve3)
        │     ├── 101 — debian-12-template (template base)
        │     └── 102 — servidor-01 (VM de monitoramento)
        │           └── EXTRANET → 192.168.140.202
        │
        └── AD Windows Server 2022
              └── Bridge → 192.168.1.50

Arquitetura do projeto
PC Principal (192.168.1.11)
        ↓ SSH / Browser
VM Debian — servidor-01 (192.168.140.202)
        ├── UFW (firewall local)
        ├── Nginx (proxy reverso — atualizado automaticamente via systemd)
        │     ├── grafana.lab.local → porta 3000
        │     └── zabbix.lab.local  → porta 8080
        └── Docker (rede interna 172.18.0.x)
              ├── grafana:11.6.0
              ├── zabbix-web-nginx-mysql:alpine-7.0-latest
              ├── zabbix-server-mysql:alpine-7.0-latest
              └── mysql:8.0-debian

AD/LDAP — Windows Server 2022 (192.168.1.50)
        ├── Domínio: treinamento.local
        ├── Service Account: grafana-svc
        └── Autenticação centralizada para Grafana e Zabbix

Decisões de segurança e arquitetura
Princípio do Menor Privilégio — cada serviço roda com seu próprio usuário dedicado, sem shell e sem permissão de login direto.
Segmentação de rede — cada tipo de tráfego tem sua própria rede controlada pelo OPNsense.
Service Account dedicada no AD — usuário grafana-svc exclusivamente para autenticação LDAP, sem permissões administrativas, sem obrigatoriedade de troca de senha.
AD com acesso restrito — protegido por regras granulares no OPNsense e Windows Firewall.
Nginx com atualização automática — script systemd atualiza os IPs dos containers Docker automaticamente no boot, evitando 502 Bad Gateway.
ldap.toml via volume Docker — arquivo montado externamente ao container para garantir permissões corretas e persistência.
Nota sobre produção — em produção: AD em rede MANAGEMENT dedicada, acesso via Jump Server, LDAPS (porta 636 com TLS), rotação periódica de credenciais.

PARTE 0 — Criar o Template Debian 12 no Proxmox
Método Cloud Image — sem instalação manual
Este é o método profissional. Utiliza uma imagem oficial do Debian já pronta para virtualização, sem necessidade de instalar o SO manualmente.
Acesse pve1 → Shell e rode:
bash# Baixar a Cloud Image oficial do Debian 12
# O -c permite retomar o download caso seja interrompido
wget -c https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
Criar o template
bash# 1. Criar a VM base
qm create 101 --name debian-12-template --memory 2048 --cores 1 --net0 virtio,bridge=vmbr2

# 2. Importar o disco para o storage Ceph
qm importdisk 101 debian-12-generic-amd64.qcow2 CephcursoDC

# 3. Configurar hardware
qm set 101 --scsihw virtio-scsi-pci --scsi0 CephcursoDC:vm-101-disk-0
qm set 101 --ide2 CephcursoDC:cloudinit
qm set 101 --boot c --bootdisk scsi0
qm set 101 --serial0 socket --vga serial0
qm set 101 --agent enabled=1

# 4. Configurar usuário e senha padrão via Cloud-Init
qm set 101 --ciuser root --cipassword SuaSenhaAqui

# 5. Configurar IP base via Cloud-Init
qm set 101 --ipconfig0 ip=192.168.140.201/24,gw=192.168.140.255

# 6. Verificar configuração antes de converter
qm config 101

# 7. Converter para template — operação irreversível
qm template 101
```

Resultado esperado do `qm config 101`:
```
agent: 1
boot: c
bootdisk: scsi0
cipassword: **********
ciuser: root
cores: 1
ipconfig0: ip=192.168.140.201/24,gw=192.168.140.255
memory: 2048
net0: virtio,bridge=vmbr2
template: 1
Clonar o template para criar novas VMs
bash# 1. Clonar
qm clone 101 102 --name servidor-01 --full

# 2. Alterar IP — OBRIGATÓRIO para evitar conflito de IP
qm set 102 --ipconfig0 ip=192.168.140.202/24,gw=192.168.140.10

# 3. Configurar rede sem VLAN tag
# IMPORTANTE: nunca adicionar VLAN tag — impede comunicação com OPNsense
qm set 102 --net0 virtio,bridge=vmbr2,firewall=1

# 4. Iniciar
qm start 102

Atenção: Sempre altere o IP antes de iniciar o clone — o template tem IP fixo e causará conflito se duas VMs subirem com o mesmo endereço.


Atenção: qm template é irreversível. Sempre use qm clone para criar VMs a partir dele.

Comandos úteis qm
bashqm list                    # listar VMs
qm stop <VMID>             # parar VM
qm shutdown <VMID>         # desligar graciosamente
qm config <VMID>           # ver configuração
qm unlock <VMID>           # desbloquear VM travada
rm -f /var/lock/qemu-server/lock-<VMID>.conf  # forçar remoção de lock

# Gerenciar HA
ha-manager set vm:<VMID> --state stopped   # pausar HA temporariamente
ha-manager set vm:<VMID> --state started   # reativar HA

# Verificar storages
pvesm status

# Mover disco para outro storage se local-lvm estiver cheio
qm move-disk <VMID> scsi0 CephcursoDC --delete

PARTE 1 — Configurar rede permanente da VM
Acesse o console da VM pelo Proxmox. Primeiro ative a rede temporariamente para ter acesso SSH:
bash# Silenciar logs do kernel no terminal
dmesg -n 1

# Ativar rede temporariamente
ip addr add 192.168.140.202/24 dev eth0
ip link set eth0 up
ip route add default via 192.168.140.10
Agora configure de forma permanente via systemd-networkd:
bashmkdir -p /etc/systemd/network

cat > /etc/systemd/network/10-eth0.network << 'EOF'
[Match]
Name=eth0

[Network]
Address=192.168.140.202/24
Gateway=192.168.140.10
DNS=8.8.8.8
DNS=8.8.4.4
EOF

systemctl enable systemd-networkd
systemctl start systemd-networkd

Nota: O systemd-networkd é o método permanente recomendado — resiste a reboots e não depende do ifupdown. Se aparecer erro networking.service does not exist, ignore — significa que o Debian já usa o systemd-networkd por padrão.


Nota: Se após reboot a internet parar, acesse o OPNsense em Interfaces → WAN e desmarque Block private networks e Block bogon networks. O NAT do VirtualBox usa IP privado (10.0.2.x) e essas opções bloqueiam esse tráfego.

Teste:
bashping 8.8.8.8
ping 192.168.1.11
Alterar hostname
bashhostnamectl set-hostname servidor-01.lab.local
echo "192.168.140.202 servidor-01.lab.local" >> /etc/hosts

PARTE 2 — Preparar o sistema
bashapt update && apt upgrade -y
apt install -y curl git vim net-tools ufw nginx ldap-utils

PARTE 3 — Usuários e segurança
Criar usuário admin pessoal
bashuseradd -m -s /bin/bash seunome
passwd seunome
usermod -aG sudo seunome
Criar usuário dedicado para os serviços
bash# Sem shell e sem login — apenas para rodar a aplicação
useradd -r -s /sbin/nologin -d /opt/monitoring monitoring

# Verificar
cat /etc/passwd | grep monitoring
Restringir SSH
bashsed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
echo "AllowUsers seunome" >> /etc/ssh/sshd_config

# Desabilitar resolução DNS no SSH — evita lentidão na conexão
echo "UseDNS no" >> /etc/ssh/sshd_config

systemctl restart sshd
Configurar UFW
bashufw enable

ufw allow from 192.168.1.0/24 to any port 22
ufw allow from 192.168.140.0/24 to any port 22
ufw allow from 192.168.1.0/24 to any port 3000
ufw allow from 192.168.1.0/24 to any port 8080
ufw allow from 192.168.140.0/24 to any port 10051
ufw allow 80/tcp
ufw allow 443/tcp

ufw status verbose

PARTE 4 — Instalar Docker
bashapt install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

docker --version
docker compose version

# Adicionar usuários ao grupo docker após a instalação
usermod -aG docker monitoring
usermod -aG docker seunome

PARTE 5 — Estrutura do projeto no Git
bashgit config --global user.name "gustahrc-lab"
git config --global user.email "GUSTAVO@TREINAMENTO.COM"

mkdir -p /opt/monitoring
cd /opt/monitoring
git init

# Se aparecer erro de "dubious ownership"
git config --global --add safe.directory /opt/monitoring

mkdir -p grafana/provisioning/{datasources,dashboards}
mkdir -p grafana/config
mkdir -p systemd
mkdir -p nginx

chown -R monitoring:monitoring /opt/monitoring
chmod -R 750 /opt/monitoring
```

Estrutura:
```
/opt/monitoring/
├── docker-compose.yml
├── grafana/
│   ├── config/
│   │   └── ldap.toml
│   └── provisioning/
│       ├── datasources/
│       └── dashboards/
├── systemd/
│   ├── monitoring.service
│   └── nginx-proxy-update.service
└── nginx/
    ├── monitoring.conf
    └── update-nginx-proxy.sh

PARTE 6 — Criar arquivo ldap.toml

Boa prática: Crie uma service account dedicada no AD exclusivamente para autenticação LDAP. No AD foi criado o usuário grafana-svc com senha forte, sem permissões administrativas, com Password never expires marcado e User must change password desmarcado.


Atenção crítica: Contas desabilitadas no AD (userAccountControl: 546) causam erro de autenticação mesmo com senha correta. Sempre verifique se a conta está habilitada em Active Directory Users and Computers → clique direito → Enable Account.

bashcat > /opt/monitoring/grafana/config/ldap.toml << 'EOF'
[[servers]]
host = "192.168.1.50"
port = 389
use_ssl = false
bind_dn = "CN=grafana-svc,OU=Contas de Service,OU=Usuarios,DC=treinamento,DC=local"
bind_password = "XXXXXXXXXXX"
search_base_dns = ["DC=treinamento,DC=local"]
search_filter = "(sAMAccountName=%s)"

[servers.attributes]
name = "givenName"
surname = "sn"
username = "sAMAccountName"
member_of = "memberOf"
email = "mail"

[[servers.group_mappings]]
group_dn = "CN=GrafanaAdmins,OU=Groups,DC=treinamento,DC=local"
org_role = "Admin"

[[servers.group_mappings]]
group_dn = "*"
org_role = "Viewer"
EOF
Testar conectividade LDAP antes de subir os containers:
bashldapsearch -x -H ldap://192.168.1.50 \
  -D "CN=grafana-svc,OU=Contas de Service,OU=Usuarios,DC=treinamento,DC=local" \
  -w "XXXXXXXXXXXXX" \
  -b "DC=treinamento,DC=local" \
  "(sAMAccountName=grafana-svc)"
Deve retornar result: 0 Success e userAccountControl: 66048 (conta habilitada).

PARTE 7 — docker-compose.yml

Importantes:

Use imagens Alpine — muito mais leves que as genéricas
O campo version foi removido pois está obsoleto nas versões atuais do Docker
Grafana 11.6.0 é obrigatório para compatibilidade com o plugin Zabbix — versões anteriores (ex: 10.4.0) são incompatíveis
O ldap.toml é montado via volume para garantir permissões corretas — tentar criar o arquivo dentro do container retorna Permission denied
O DNS 8.8.8.8 no container do Grafana é necessário para download do plugin


bashcat > /opt/monitoring/docker-compose.yml << 'EOF'
networks:
  monitoring:
    driver: bridge

volumes:
  mysql_data:
  grafana_data:
  zabbix_data:

services:

  mysql:
    image: mysql:8.0-debian
    container_name: zabbix-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbixpassword
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - monitoring

  zabbix-server:
    image: zabbix/zabbix-server-mysql:alpine-7.0-latest
    container_name: zabbix-server
    restart: always
    ports:
      - "10051:10051"
    environment:
      DB_SERVER_HOST: mysql
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbixpassword
      MYSQL_ROOT_PASSWORD: rootpassword
    depends_on:
      - mysql
    networks:
      - monitoring

  zabbix-frontend:
    image: zabbix/zabbix-web-nginx-mysql:alpine-7.0-latest
    container_name: zabbix-frontend
    restart: always
    ports:
      - "8080:8080"
    environment:
      DB_SERVER_HOST: mysql
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbixpassword
      ZBX_SERVER_HOST: zabbix-server
      PHP_TZ: America/Sao_Paulo
    depends_on:
      - mysql
      - zabbix-server
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:11.6.0
    container_name: grafana
    restart: always
    dns:
      - 8.8.8.8
      - 8.8.4.4
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin123
      GF_INSTALL_PLUGINS: alexanderzobnin-zabbix-app
      GF_AUTH_LDAP_ENABLED: "true"
      GF_AUTH_LDAP_CONFIG_FILE: /etc/grafana/ldap.toml
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/config/ldap.toml:/etc/grafana/ldap.toml:ro
    depends_on:
      - zabbix-server
    networks:
      - monitoring

EOF
Subir os containers
bashcd /opt/monitoring
docker compose up -d

# Verificar status
docker compose ps

# Ver logs se algum falhar
docker compose logs --tail=50

# Se houver erro de container com nome já existente
docker compose down
docker compose up -d --force-recreate
Configurar systemd para a stack
bashcat > /opt/monitoring/systemd/monitoring.service << 'EOF'
[Unit]
Description=Monitoring Stack (Grafana + Zabbix)
After=docker.service
Requires=docker.service

[Service]
User=monitoring
Group=monitoring
WorkingDirectory=/opt/monitoring
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Copiar e ativar
cp /opt/monitoring/systemd/monitoring.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable monitoring
systemctl start monitoring
systemctl status monitoring

PARTE 8 — Nginx com atualização automática

Problema identificado: O Nginx instalado no host não consegue resolver nomes de containers Docker (host not found in upstream "grafana:3000"). Os IPs dos containers mudam a cada restart. A solução é um script systemd que atualiza o Nginx automaticamente no boot com os IPs corretos.

Script de atualização automática
bashcat > /opt/monitoring/nginx/update-nginx-proxy.sh << 'EOF'
#!/bin/bash

# Aguarda containers subirem completamente
sleep 15

GRAFANA_IP=$(docker inspect grafana | grep '"IPAddress"' | tail -1 | tr -d ' ",' | cut -d: -f2)
ZABBIX_IP=$(docker inspect zabbix-frontend | grep '"IPAddress"' | tail -1 | tr -d ' ",' | cut -d: -f2)

cat > /etc/nginx/conf.d/monitoring.conf << NGINX
server {
    listen 80;
    server_name grafana.lab.local;

    location / {
        proxy_pass http://$GRAFANA_IP:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name zabbix.lab.local;

    location / {
        proxy_pass http://$ZABBIX_IP:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX

nginx -t && systemctl restart nginx
EOF

chmod +x /opt/monitoring/nginx/update-nginx-proxy.sh
cp /opt/monitoring/nginx/update-nginx-proxy.sh /usr/local/bin/update-nginx-proxy.sh
chmod +x /usr/local/bin/update-nginx-proxy.sh
Serviço systemd para execução automática no boot
bashcat > /opt/monitoring/systemd/nginx-proxy-update.service << 'EOF'
[Unit]
Description=Update Nginx proxy with Docker container IPs
After=docker.service monitoring.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-nginx-proxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cp /opt/monitoring/systemd/nginx-proxy-update.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable nginx-proxy-update
systemctl start nginx-proxy-update
```

### Arquivo hosts no PC Windows

Edite `C:\Windows\System32\drivers\etc\hosts` como Administrador:
```
192.168.140.202 grafana.lab.local
192.168.140.202 zabbix.lab.local
```

Acesse no browser:
```
http://grafana.lab.local   → admin / admin123
http://zabbix.lab.local    → Admin / zabbix
```

---

## PARTE 9 — Integração Grafana + Zabbix

Acesse `http://grafana.lab.local` → login `admin / admin123`

Vá em **Configuration → Plugins → Zabbix → Enable**

Depois em **Configuration → Data Sources → Add → Zabbix**:
```
URL: http://zabbix-frontend:8080/api_jsonrpc.php
Username: Admin
Password: zabbix

Nota: Se retornar Could not connect, aguarde alguns minutos — o Zabbix frontend pode ainda estar inicializando o banco. Se a senha padrão não funcionar, redefina via MySQL:

bashdocker exec -it zabbix-mysql mysql -u zabbix -pzabbixpassword zabbix \
  -e "UPDATE users SET passwd=md5('zabbix') WHERE alias='Admin';"
```

Clique em **Save & Test** — deve aparecer **Data source connected**.

> **Nota:** O Grafana usa o nome do container `zabbix-frontend` para resolver internamente via rede Docker — não use IP aqui.

---

## PARTE 10 — Preparar Active Directory para LDAP

### Rede do AD no VirtualBox

Com a VM **desligada** → **Configurações → Rede → Adaptador 1**:
```
Modo: Placa em modo Bridge
Placa: Intel(R) Ethernet Connection (14) I219-V
```

### IP fixo no Windows Server

**Painel de Controle → Central de Rede → Adaptador → IPv4**:
```
IP: 192.168.1.50
Máscara: 255.255.255.0
Gateway: 192.168.1.1
DNS: 127.0.0.1
```

### Criar service account no AD

No **Active Directory Users and Computers** crie o usuário dedicado para LDAP:
```
Nome: grafana-svc
OU: Contas de Service
Senha: senha forte
Opções:
  ✅ Password never expires
  ❌ User must change password at next logon
  ✅ Account is enabled   ← CRÍTICO: conta desabilitada causa erro de autenticação
Rota estática no AD
Sem essa rota o AD não sabe responder para a rede EXTRANET — o pacote chega mas a resposta vai para o roteador (192.168.1.1) que não conhece a rede 192.168.140.0/24:
cmdroute add 192.168.140.0 mask 255.255.255.0 192.168.1.200 -p
Firewall do Windows Server
cmdnetsh advfirewall set allprofiles state on
netsh advfirewall firewall add rule name="Allow ICMP" protocol=icmpv4 dir=in action=allow
netsh advfirewall firewall add rule name="Allow LDAP" protocol=TCP dir=in localport=389 action=allow
netsh advfirewall firewall add rule name="Allow RDP admin" protocol=TCP dir=in localport=3389 remoteip=192.168.1.11 action=allow
```

### Regras OPNsense — Firewall → Rules → LAN

Adicione nessa ordem exata (a ordem importa no OPNsense):
```
1. Pass — TCP  — 192.168.1.11    → 192.168.1.50 : 3389 — RDP admin → AD
2. Pass — TCP  — 192.168.140.202 → 192.168.1.50 : 389  — LDAP Monitoring → AD
3. Pass — ICMP — 192.168.140.202 → 192.168.1.50        — ICMP Monitoring → AD
4. Block — Any — Any             → 192.168.1.50        — Bloquear acesso não autorizado
Teste após aplicar:
bash# Na VM
ping 192.168.1.50

# Teste LDAP completo
ldapsearch -x -H ldap://192.168.1.50 \
  -D "CN=grafana-svc,OU=Contas de Service,OU=Usuarios,DC=treinamento,DC=local" \
  -w "XXXXXXXXXX" \
  -b "DC=treinamento,DC=local" \
  "(sAMAccountName=grafana-svc)"
```

Deve retornar `result: 0 Success`.

---

## PARTE 11 — Configurar LDAP no Zabbix

Acesse `http://zabbix.lab.local` → login `Admin / zabbix`

Vá em **Administration → Authentication → LDAP**:
```
Enable LDAP: marcado
LDAP Host: 192.168.1.50
Port: 389
Base DN: DC=treinamento,DC=local
Search attribute: sAMAccountName
Bind DN: CN=grafana-svc,OU=Contas de Service,OU=Usuarios,DC=treinamento,DC=local
Bind password: XXXXXXXXXX

Clique em Test authentication antes de salvar.
