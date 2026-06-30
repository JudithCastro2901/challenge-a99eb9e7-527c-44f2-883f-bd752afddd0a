# Documentación del Proceso - Gestión de Servidores Remotos

## Información del Reto

| Campo | Valor |
|-------|-------|
| **Tema** | Manejo de infraestructura |
| **Nivel** | junior-l2 |
| **Tipo** | practical |
| **Participante** | Judith Castro |
| **Fecha** | Junio 2025 |

---

## Fase 0: Configuración del Proyecto

El proyecto base fue obtenido y verificado sin errores de sintaxis usando `bash -n` en los 3 scripts.

---

## Fase 1: Configuración Inicial del Servidor

### 1.1 Creación de la infraestructura en AWS (CLI)

Se utilizó AWS CLI con el profile `pra_kappa_lab` para crear la infraestructura:

**Crear Key Pair:**
```bash
aws ec2 create-key-pair --key-name fintech-server-key --key-type rsa --query "KeyMaterial" --output text --profile pra_kappa_lab > fintech-server-key.pem
```

![Creación de Key Pair](keypair.png)

**Crear Security Group:**
```bash
aws ec2 create-security-group --group-name fintech-server-sg --description "Security Group para servidor fintech - SSH y HTTP/HTTPS" --vpc-id vpc-0a713448d7c37c8ae --profile pra_kappa_lab
```

**Configurar reglas de firewall:**
```bash
aws ec2 authorize-security-group-ingress --group-id sg-08ad8f32ab059ff6b --protocol tcp --port 22 --cidr 0.0.0.0/0 --profile pra_kappa_lab
aws ec2 authorize-security-group-ingress --group-id sg-08ad8f32ab059ff6b --protocol tcp --port 80 --cidr 0.0.0.0/0 --profile pra_kappa_lab
aws ec2 authorize-security-group-ingress --group-id sg-08ad8f32ab059ff6b --protocol tcp --port 443 --cidr 0.0.0.0/0 --profile pra_kappa_lab
```

**Lanzar instancia EC2 (Ubuntu 22.04):**
```bash
aws ec2 run-instances \
  --image-id ami-0d7405d05f836d0d4 \
  --instance-type t2.micro \
  --key-name fintech-server-key \
  --security-group-ids sg-08ad8f32ab059ff6b \
  --subnet-id subnet-035ef60e7f5c33e75 \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=fintech-server}]" \
  --profile pra_kappa_lab
```

### 1.2 Datos del servidor creado

| Campo | Valor |
|-------|-------|
| **Instance ID** | i-018c1c4ee3f89d726 |
| **IP Pública** | 44.201.227.98 |
| **IP Privada** | 10.25.1.9 |
| **Tipo** | t2.micro |
| **SO** | Ubuntu 22.04 LTS |
| **Región** | us-east-1a |
| **VPC** | vpc-cloudops |
| **Subnet** | sub-cloudops-public1 |

### 1.3 Conexión SSH al servidor

```bash
cd /c/Users/judith.castro_pragma/Documents/Ruta/challenge-a99eb9e7-527c-44f2-883f-bd752afddd0a
chmod 400 fintech-server-key.pem
ssh -i fintech-server-key.pem ubuntu@44.201.227.98
```

![Conexión SSH al servidor](conexionalservidor.png)

### 1.4 Configuración del servidor

Se ejecutaron los siguientes pasos dentro del servidor:

```bash
# Actualizar sistema operativo
sudo apt-get update -y && sudo apt-get upgrade -y

# Instalar paquetes esenciales
sudo apt-get install -y curl wget vim htop net-tools fail2ban ufw

# Configurar firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
echo "y" | sudo ufw enable
sudo ufw status

# Habilitar Fail2Ban (protección contra fuerza bruta)
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

**Resultado:** Firewall activo con puertos 22, 80 y 443 habilitados. Fail2Ban activo y protegiendo el servidor.

![Configuración del servidor](configuracion.png)

---

## Fase 2: Monitoreo de Recursos

### 2.1 Monitoreo local en el servidor

Se verificó el estado de los recursos directamente en la EC2:

```bash
# CPU
top -b -n 1 | head -5

# Memoria RAM
free -h

# Disco
df -h

# Red
ss -tun | head -10

# Uptime
uptime

# Servicios críticos
systemctl is-active sshd ufw fail2ban
```

### Resultados del monitoreo local

| Recurso | Estado | Valor |
|---------|--------|-------|
| **CPU** | ✅ Normal | 0% uso |
| **RAM** | ✅ Normal | 175Mi / 957Mi (18%) |
| **Disco** | ✅ Normal | 2.1G / 7.6G (28%) |
| **Red** | ✅ Normal | 1 conexión SSH activa |
| **sshd** | ✅ Activo | active |
| **ufw** | ✅ Activo | active |
| **fail2ban** | ✅ Activo | active |

![Monitoreo de recursos](monitoreo.png)

### 2.2 Monitoreo con Amazon CloudWatch

Se configuró CloudWatch como sistema de monitoreo en tiempo real. AWS envía métricas de la EC2 automáticamente (CPU, red, estado) sin necesidad de instalar agentes.

**Rol IAM creado para la EC2:**
```bash
# Crear rol con permisos de CloudWatch
aws iam create-role --role-name fintech-server-cloudwatch-role \
  --assume-role-policy-document file://trust-policy.json --profile pra_kappa_lab

# Asociar política de CloudWatch
aws iam attach-role-policy --role-name fintech-server-cloudwatch-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess --profile pra_kappa_lab

# Crear y asociar instance profile a la EC2
aws iam create-instance-profile --instance-profile-name fintech-server-profile --profile pra_kappa_lab
aws iam add-role-to-instance-profile --instance-profile-name fintech-server-profile \
  --role-name fintech-server-cloudwatch-role --profile pra_kappa_lab
aws ec2 associate-iam-instance-profile --instance-id i-018c1c4ee3f89d726 \
  --iam-instance-profile Name=fintech-server-profile --profile pra_kappa_lab
```

### 2.3 Alarmas de CloudWatch configuradas

Se crearon alarmas para alertas tempranas en caso de sobrecarga:

```bash
# Alarma de CPU alta (>80% por más de 10 minutos)
aws cloudwatch put-metric-alarm --alarm-name "fintech-server-cpu-alta" \
  --metric-name CPUUtilization --namespace AWS/EC2 \
  --statistic Average --period 300 --threshold 80 \
  --comparison-operator GreaterThanThreshold --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=i-018c1c4ee3f89d726 \
  --alarm-description "Alerta: CPU supera el 80%" --profile pra_kappa_lab

# Alarma de tráfico de red excesivo (>50MB en 5 min)
aws cloudwatch put-metric-alarm --alarm-name "fintech-server-network-in-alta" \
  --metric-name NetworkIn --namespace AWS/EC2 \
  --statistic Average --period 300 --threshold 50000000 \
  --comparison-operator GreaterThanThreshold --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=i-018c1c4ee3f89d726 \
  --alarm-description "Alerta: Trafico de red entrante excesivo" --profile pra_kappa_lab

# Alarma de status check (servidor caído)
aws cloudwatch put-metric-alarm --alarm-name "fintech-server-status-check" \
  --metric-name StatusCheckFailed --namespace AWS/EC2 \
  --statistic Maximum --period 60 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=i-018c1c4ee3f89d726 \
  --alarm-description "Alerta: El servidor fallo el status check" --profile pra_kappa_lab
```

### Resumen de alarmas

| Alarma | Métrica | Umbral | Descripción |
|--------|---------|--------|-------------|
| `fintech-server-cpu-alta` | CPUUtilization | > 80% por 10 min | Alerta temprana de sobrecarga |
| `fintech-server-network-in-alta` | NetworkIn | > 50MB en 5 min | Posible ataque DDoS o tráfico anómalo |
| `fintech-server-status-check` | StatusCheckFailed | ≥ 1 por 2 min | Servidor caído o inaccesible |

![Alarmas en CloudWatch](alarmas_cloudwatch.png)

### Métricas monitoreadas en CloudWatch (automáticas)

| Métrica | Descripción | Frecuencia |
|---------|-------------|------------|
| CPUUtilization | Uso de CPU del servidor | Cada 5 min |
| NetworkIn | Bytes de tráfico entrante | Cada 5 min |
| NetworkOut | Bytes de tráfico saliente | Cada 5 min |
| StatusCheckFailed | Estado de salud de la instancia | Cada 1 min |
| DiskReadOps | Operaciones de lectura en disco | Cada 5 min |
| DiskWriteOps | Operaciones de escritura en disco | Cada 5 min |

---

## Fase 3: Aplicación de Parches de Seguridad

Se implementó un proceso automatizado de parcheo usando **AWS Systems Manager Patch Manager**.

### 3.1 Configuración de SSM en la instancia

Se asoció el rol `ssm-ec2rol` a la EC2 para permitir comunicación con Systems Manager:

```bash
# Asociar rol SSM a la instancia
aws ec2 associate-iam-instance-profile --instance-id i-018c1c4ee3f89d726 \
  --iam-instance-profile Name=ssm-ec2rol --profile pra_kappa_lab
```

Se verificó que la instancia aparece como **Online** en SSM:
```bash
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-018c1c4ee3f89d726" --profile pra_kappa_lab
```

### 3.2 Creación de Patch Baseline

Se creó una política de parches que solo aprueba parches de prioridad Required e Important, con aprobación automática a los 3 días:

```bash
aws ssm create-patch-baseline \
  --name "fintech-security-patch-baseline" \
  --description "Patch baseline para servidores fintech - solo parches de seguridad" \
  --operating-system UBUNTU \
  --approval-rules "PatchRules=[{PatchFilterGroup={PatchFilters=[{Key=PRIORITY,Values=[Required,Important]},{Key=SECTION,Values=[All]}]},ApproveAfterDays=3,ComplianceLevel=HIGH}]" \
  --approved-patches-compliance-level HIGH \
  --profile pra_kappa_lab
```

**Baseline ID:** `pb-0fcf6d215d77dee5d`

### 3.3 Registro de Patch Group

Se etiquetó la instancia con un Patch Group y se asoció a la baseline:

```bash
# Etiquetar la instancia
aws ec2 create-tags --resources i-018c1c4ee3f89d726 \
  --tags "Key=Patch Group,Value=fintech-servers" --profile pra_kappa_lab

# Registrar baseline con el patch group
aws ssm register-patch-baseline-for-patch-group \
  --baseline-id pb-0fcf6d215d77dee5d \
  --patch-group "fintech-servers" --profile pra_kappa_lab
```

### 3.4 Maintenance Window (Ventana de Mantenimiento)

Se creó una ventana de mantenimiento programada para ejecutar el parcheo automáticamente cada domingo a las 3AM UTC:

```bash
# Crear ventana de mantenimiento
aws ssm create-maintenance-window \
  --name "fintech-patch-window" \
  --description "Ventana de mantenimiento para parches - Domingos 3AM UTC" \
  --schedule "cron(0 3 ? * SUN *)" \
  --duration 2 --cutoff 1 \
  --allow-unassociated-targets --profile pra_kappa_lab

# Registrar target (instancias del patch group)
aws ssm register-target-with-maintenance-window \
  --window-id mw-05de16f63197e1e7a \
  --resource-type INSTANCE \
  --targets "Key=tag:Patch Group,Values=fintech-servers" --profile pra_kappa_lab

# Registrar tarea de parcheo
aws ssm register-task-with-maintenance-window \
  --window-id mw-05de16f63197e1e7a \
  --task-type RUN_COMMAND \
  --targets "Key=WindowTargetIds,Values=7073f61a-f6eb-4cfe-a499-26b234042815" \
  --task-arn "AWS-RunPatchBaseline" \
  --task-invocation-parameters '{"RunCommand":{"Parameters":{"Operation":["Install"]}}}' \
  --max-concurrency "1" --max-errors "0" --priority 1 --profile pra_kappa_lab
```

**Window ID:** `mw-05de16f63197e1e7a`

### 3.5 Resumen de la estrategia de parches

| Componente | Configuración |
|------------|---------------|
| **Patch Baseline** | Solo prioridad Required e Important |
| **Aprobación** | Automática después de 3 días |
| **Ventana de mantenimiento** | Domingos 3:00 AM UTC |
| **Duración máxima** | 2 horas |
| **Concurrencia** | 1 instancia a la vez |
| **Tolerancia a errores** | 0 (se detiene si falla) |
| **Compliance** | HIGH |

### 3.6 Aplicación manual de parches (ejecutada en Fase 1)

Adicionalmente se ejecutó un parcheo manual durante la configuración inicial:

```bash
sudo apt-get update -y && sudo apt-get upgrade -y
```

**Resultado:** 15 paquetes actualizados, 0 parches pendientes, todos los servicios activos.

![Aplicación de parches](parches.png)

---

---

## Respuestas a Dimensiones Evaluadas

### ¿Qué es un servidor remoto y por qué es importante en una empresa fintech?
Un servidor remoto es una máquina física o virtual ubicada en un centro de datos (como AWS) que se administra a distancia mediante SSH. En una fintech es crítico porque aloja los servicios que procesan transacciones financieras, datos sensibles de clientes y debe garantizar alta disponibilidad 24/7.

### ¿Para qué sirve el monitoreo de recursos en un servidor?
Sirve para detectar problemas antes de que afecten a los usuarios: sobrecarga de CPU, memoria llena, disco agotado o conexiones anómalas. Permite tomar decisiones proactivas como escalar recursos o investigar posibles ataques.

### ¿Cómo se usa un sistema de monitoreo para mejorar la eficiencia del servidor?
Se definen umbrales de alerta (CPU>80%, RAM>85%, Disco>90%) y se revisan periódicamente. Si un recurso se acerca al umbral, se optimiza la aplicación o se escala la infraestructura antes de que haya degradación del servicio.

### ¿Cuáles son los errores comunes al aplicar parches de seguridad?
- Aplicar parches directamente en producción sin probar
- No hacer backup antes de aplicar
- No verificar que los servicios siguen funcionando después del parche
- Ignorar parches pendientes por mucho tiempo
- No tener un plan de rollback en caso de fallo

### ¿Qué decisiones implica la automatización de la aplicación de parches?
- Definir ventanas de mantenimiento para minimizar impacto
- Decidir si aplicar solo parches de seguridad o todos
- Establecer un proceso de backup obligatorio antes de cada parche
- Implementar verificación automática post-parche
- Definir criterios de rollback automático si algo falla
- Decidir si se requiere reinicio del servidor y cómo manejarlo

---

---

## Fase 4: Cierre y Documentación Final

### Resumen Ejecutivo

Se implementó exitosamente un sistema completo de gestión de infraestructura para una empresa fintech, cubriendo:

| Fase | Objetivo | Herramientas | Estado |
|------|----------|--------------|--------|
| Fase 1 | Configuración del servidor | AWS EC2, UFW, Fail2Ban, SSH | ✅ Completada |
| Fase 2 | Monitoreo de recursos | CloudWatch, Alarmas, Dashboard | ✅ Completada |
| Fase 3 | Automatización de parches | SSM Patch Manager, Maintenance Window | ✅ Completada |
| Fase 4 | Documentación y cierre | Markdown, Git | ✅ Completada |

### Logros alcanzados

- Servidor Ubuntu 22.04 desplegado y hardened en AWS
- Firewall configurado con principio de mínimo privilegio (solo puertos 22, 80, 443)
- Protección contra fuerza bruta con Fail2Ban
- Monitoreo en tiempo real con CloudWatch (dashboard + alarmas)
- Parcheo automatizado semanal con SSM Patch Manager
- Toda la infraestructura creada y gestionada vía CLI (reproducible)

---

### Guía de Operaciones

#### Cómo monitorear el servidor

1. **Dashboard en tiempo real:** https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards/dashboard/fintech-server-monitoring
2. **Alarmas activas:** https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:
3. **Monitoreo manual por SSH:**
   ```bash
   ssh -i fintech-server-key.pem ubuntu@44.201.227.98
   htop                          # CPU y RAM en tiempo real
   df -h                         # Uso de disco
   sudo ufw status               # Estado del firewall
   sudo fail2ban-client status   # IPs bloqueadas
   ```

#### Cómo aplicar parches manualmente

```bash
# Conectar al servidor
ssh -i fintech-server-key.pem ubuntu@44.201.227.98

# Verificar parches disponibles
sudo apt list --upgradable

# Crear backup antes de parchear
dpkg --get-selections > /tmp/packages_backup_$(date +%Y%m%d).txt

# Aplicar parches
sudo apt-get update -y && sudo apt-get upgrade -y

# Verificar servicios post-parche
systemctl is-active sshd ufw fail2ban
```

#### Cómo escalar el servidor

```bash
# Detener la instancia
aws ec2 stop-instances --instance-ids i-018c1c4ee3f89d726 --profile pra_kappa_lab

# Cambiar tipo de instancia (ej: t2.micro -> t2.small)
aws ec2 modify-instance-attribute --instance-id i-018c1c4ee3f89d726 \
  --instance-type "{\"Value\": \"t2.small\"}" --profile pra_kappa_lab

# Iniciar la instancia
aws ec2 start-instances --instance-ids i-018c1c4ee3f89d726 --profile pra_kappa_lab
```

#### Cómo responder a una alarma

| Alarma | Acción recomendada |
|--------|--------------------|
| CPU > 80% | Verificar procesos con `htop`, considerar escalar instancia |
| Network > 50MB | Revisar conexiones con `ss -tun`, posible ataque DDoS |
| Status Check Failed | Verificar logs en consola AWS, reiniciar si es necesario |

---

### Estrategia de Seguridad Implementada

| Capa | Medida | Descripción |
|------|--------|-------------|
| **Red** | Security Group | Solo puertos 22, 80, 443 abiertos |
| **Red** | UFW Firewall | Deny all incoming por defecto |
| **Acceso** | SSH Key Only | Sin password authentication |
| **Acceso** | Fail2Ban | Bloqueo tras 3 intentos fallidos |
| **Parches** | SSM Patch Manager | Actualizaciones automáticas semanales |
| **Monitoreo** | CloudWatch Alarms | Alertas proactivas de anomalías |
| **Monitoreo** | Dashboard | Visibilidad en tiempo real |

---

### Diagrama de Arquitectura Completo

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud (us-east-1)                        │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    VPC: vpc-cloudops                           │  │
│  │                    CIDR: 10.25.0.0/16                         │  │
│  │                                                               │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  Subnet: sub-cloudops-public1 (10.25.1.0/28)            │  │  │
│  │  │                                                         │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │  EC2: fintech-server (t2.micro)                    │  │  │  │
│  │  │  │  OS: Ubuntu 22.04 LTS                              │  │  │  │
│  │  │  │  IP Pública: 44.201.227.98                          │  │  │  │
│  │  │  │  IP Privada: 10.25.1.9                              │  │  │  │
│  │  │  │  Rol: ssm-ec2rol                                    │  │  │  │
│  │  │  │                                                     │  │  │  │
│  │  │  │  Servicios internos:                                │  │  │  │
│  │  │  │  • SSH (puerto 22)                                  │  │  │  │
│  │  │  │  • UFW Firewall                                    │  │  │  │
│  │  │  │  • Fail2Ban                                        │  │  │  │
│  │  │  │  • SSM Agent                                       │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐  │
│  │  CloudWatch                    │  │  Systems Manager             │  │
│  │  • Dashboard                   │  │  • Patch Baseline             │  │
│  │  • Alarmas (CPU, Red, Status)  │  │  • Maintenance Window         │  │
│  │  • Métricas automáticas        │  │  • RunPatchBaseline (Install) │  │
│  └─────────────────────────────┘  └─────────────────────────────┘  │
│                                                                     │
│  Security Group: fintech-server-sg                                  │
│  Inbound: 22/tcp, 80/tcp, 443/tcp | Outbound: All                   │
└─────────────────────────────────────────────────────────────────┘
```

---

### Inventario de Recursos AWS Creados

| Recurso | Tipo | ID/Nombre |
|---------|------|-----------|
| EC2 Instance | Instancia | `i-018c1c4ee3f89d726` |
| Key Pair | Clave SSH | `fintech-server-key` |
| Security Group | SG | `sg-08ad8f32ab059ff6b` |
| CloudWatch Alarm | Alarma | `fintech-server-cpu-alta` |
| CloudWatch Alarm | Alarma | `fintech-server-network-in-alta` |
| CloudWatch Alarm | Alarma | `fintech-server-status-check` |
| CloudWatch Dashboard | Dashboard | `fintech-server-monitoring` |
| SSM Patch Baseline | Baseline | `pb-0fcf6d215d77dee5d` |
| SSM Maintenance Window | Window | `mw-05de16f63197e1e7a` |
| IAM Role (existente) | Rol | `ssm-ec2rol` |

---

### Comandos de Referencia Rápida

| Acción | Comando |
|--------|---------|
| Conectar al servidor | `ssh -i fintech-server-key.pem ubuntu@44.201.227.98` |
| Ver estado firewall | `sudo ufw status` |
| Ver uso de recursos | `htop` |
| Ver parches pendientes | `apt list --upgradable` |
| Ver logs de fail2ban | `sudo fail2ban-client status sshd` |
| Reiniciar servicio | `sudo systemctl restart <servicio>` |
| Ver alarmas CloudWatch | `aws cloudwatch describe-alarms --alarm-name-prefix fintech-server --profile pra_kappa_lab` |
| Ver estado SSM | `aws ssm describe-instance-information --profile pra_kappa_lab` |
| Ejecutar scan de parches | `aws ssm send-command --document-name AWS-RunPatchBaseline --targets Key=tag:Patch\ Group,Values=fintech-servers --parameters Operation=Scan --profile pra_kappa_lab` |

---

### Script de Limpieza de Recursos

```bash
# Eliminar alarmas CloudWatch
aws cloudwatch delete-alarms --alarm-names fintech-server-cpu-alta fintech-server-network-in-alta fintech-server-status-check --profile pra_kappa_lab

# Eliminar dashboard
aws cloudwatch delete-dashboards --dashboard-names fintech-server-monitoring --profile pra_kappa_lab

# Eliminar maintenance window
aws ssm delete-maintenance-window --window-id mw-05de16f63197e1e7a --profile pra_kappa_lab

# Deregistrar patch baseline del patch group
aws ssm deregister-patch-baseline-for-patch-group --baseline-id pb-0fcf6d215d77dee5d --patch-group fintech-servers --profile pra_kappa_lab

# Eliminar patch baseline
aws ssm delete-patch-baseline --baseline-id pb-0fcf6d215d77dee5d --profile pra_kappa_lab

# Desasociar instance profile
aws ec2 disassociate-iam-instance-profile --association-id iip-assoc-0925fc5ee0432392f --profile pra_kappa_lab

# Terminar instancia EC2
aws ec2 terminate-instances --instance-ids i-018c1c4ee3f89d726 --profile pra_kappa_lab

# Esperar a que termine
aws ec2 wait instance-terminated --instance-ids i-018c1c4ee3f89d726 --profile pra_kappa_lab

# Eliminar security group
aws ec2 delete-security-group --group-id sg-08ad8f32ab059ff6b --profile pra_kappa_lab

# Eliminar key pair
aws ec2 delete-key-pair --key-name fintech-server-key --profile pra_kappa_lab
```
