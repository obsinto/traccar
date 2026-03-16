# Guia Completo do Traccar

Este guia cobre todos os conceitos, funcionalidades e configurações do Traccar para você aproveitar 100% da plataforma.

## Índice

1. [Conceitos Fundamentais](#1-conceitos-fundamentais)
2. [Devices (Dispositivos)](#2-devices-dispositivos)
3. [Atributos](#3-atributos)
4. [Groups (Grupos)](#4-groups-grupos)
5. [Users (Usuários)](#5-users-usuários)
6. [Geofences (Cercas Virtuais)](#6-geofences-cercas-virtuais)
7. [Drivers (Motoristas)](#7-drivers-motoristas)
8. [Notifications (Notificações)](#8-notifications-notificações)
9. [Commands (Comandos)](#9-commands-comandos)
10. [Reports (Relatórios)](#10-reports-relatórios)
11. [Calendars (Calendários)](#11-calendars-calendários)
12. [Maintenance (Manutenção)](#12-maintenance-manutenção)
13. [Computed Attributes](#13-computed-attributes)
14. [API REST](#14-api-rest)
15. [WebSocket](#15-websocket)
16. [Configurações do Servidor](#16-configurações-do-servidor)
17. [Protocolos de Rastreadores](#17-protocolos-de-rastreadores)
18. [Sensores](#18-sensores)
19. [Integrações](#19-integrações)
20. [Dicas e Boas Práticas](#20-dicas-e-boas-práticas)

---

## 1. Conceitos Fundamentais

### Arquitetura de Dados

```
┌─────────────────────────────────────────────────────────────────┐
│                           TRACCAR                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │  Users   │───▶│  Groups  │───▶│ Devices  │───▶│Positions │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       │              │               │               │          │
│       │              │               │               ▼          │
│       │              │               │         ┌──────────┐     │
│       │              │               └────────▶│  Events  │     │
│       │              │                         └──────────┘     │
│       │              │                                          │
│       ▼              ▼                                          │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐     │
│  │Geofences │   │ Drivers  │   │ Commands │   │  Reports │     │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Fluxo de Dados

```
Rastreador GPS          Traccar Server              Cliente
     │                        │                        │
     │  Posição (lat, lon)    │                        │
     │───────────────────────▶│                        │
     │                        │                        │
     │                        │  Processa e salva      │
     │                        │  (tc_positions)        │
     │                        │                        │
     │                        │  Verifica eventos      │
     │                        │  (geofence, velocidade)│
     │                        │                        │
     │                        │  WebSocket/API         │
     │                        │───────────────────────▶│
     │                        │                        │
```

### Entidades Principais

| Entidade | Tabela | Descrição |
|----------|--------|-----------|
| User | tc_users | Usuários do sistema |
| Device | tc_devices | Rastreadores/Veículos |
| Group | tc_groups | Agrupamento de devices |
| Position | tc_positions | Posições GPS (histórico) |
| Event | tc_events | Eventos gerados (alertas) |
| Geofence | tc_geofences | Cercas virtuais |
| Driver | tc_drivers | Motoristas |
| Command | tc_commands | Comandos salvos |
| Notification | tc_notifications | Regras de notificação |
| Calendar | tc_calendars | Calendários (horários) |
| Maintenance | tc_maintenances | Manutenções programadas |
| Report | tc_reports | Relatórios salvos |
| Attribute | tc_attributes | Computed attributes |

---

## 2. Devices (Dispositivos)

### O que é um Device?

Device representa um rastreador GPS instalado em um veículo. É a entidade central do sistema.

### Campos do Device

```json
{
  "id": 1,
  "name": "Ambulância 01",
  "uniqueId": "123456789012345",
  "status": "online",
  "disabled": false,
  "lastUpdate": "2024-01-15T10:30:00Z",
  "positionId": 12345,
  "groupId": 5,
  "phone": "+5511999999999",
  "model": "GT06N",
  "contact": "João Silva",
  "category": "car",
  "attributes": {}
}
```

### Campos Importantes

| Campo | Descrição |
|-------|-----------|
| `uniqueId` | **IMEI** do rastreador (identificador único) |
| `status` | `online`, `offline`, `unknown` |
| `lastUpdate` | Última comunicação |
| `positionId` | ID da última posição |
| `groupId` | Grupo ao qual pertence |
| `category` | Ícone no mapa (car, truck, bus, motorcycle, etc) |
| `disabled` | Se true, ignora dados recebidos |

### Categorias de Ícones

```
car         - Carro
truck       - Caminhão
bus         - Ônibus
motorcycle  - Moto
bicycle     - Bicicleta
boat        - Barco
train       - Trem
tram        - Bonde
trolleybus  - Trólebus
person      - Pessoa
animal      - Animal
scooter     - Patinete
helicopter  - Helicóptero
ship        - Navio
plane       - Avião
default     - Padrão (ponto)
```

### Status do Device

```
┌─────────────────────────────────────────────────────────────┐
│                    CICLO DE STATUS                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────┐      Recebe      ┌─────────┐                   │
│  │ unknown │ ─────posição────▶│ online  │                   │
│  └─────────┘                  └─────────┘                   │
│       ▲                            │                        │
│       │                            │ Timeout                │
│       │         ┌─────────┐        │ (deviceTimeout)        │
│       └─────────│ offline │◀───────┘                        │
│                 └─────────┘                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### API - Devices

```bash
# Listar todos
GET /api/devices

# Criar device
POST /api/devices
{
  "name": "Veículo 01",
  "uniqueId": "123456789012345"
}

# Atualizar
PUT /api/devices/{id}

# Deletar
DELETE /api/devices/{id}
```

---

## 3. Atributos

### O que são Atributos?

Atributos são dados extras enviados pelo rastreador ou calculados pelo servidor. Ficam no campo `attributes` de Devices e Positions.

### Tipos de Atributos

#### 1. Atributos de Position (enviados pelo rastreador)

```json
{
  "id": 12345,
  "deviceId": 1,
  "latitude": -23.550520,
  "longitude": -46.633308,
  "altitude": 760,
  "speed": 45.5,
  "course": 180,
  "accuracy": 10,
  "valid": true,
  "fixTime": "2024-01-15T10:30:00Z",
  "deviceTime": "2024-01-15T10:30:00Z",
  "serverTime": "2024-01-15T10:30:01Z",
  "attributes": {
    "ignition": true,
    "motion": true,
    "fuel": 75.5,
    "battery": 12.4,
    "odometer": 125430.5,
    "hours": 3600000,
    "sat": 12,
    "rssi": -65,
    "io1": true,
    "adc1": 4.2,
    "temp1": 25.5,
    "driverUniqueId": "ABC123"
  }
}
```

#### 2. Atributos de Device (configurações)

```json
{
  "id": 1,
  "name": "Ambulância 01",
  "attributes": {
    "speedLimit": 80,
    "fuelCapacity": 60,
    "devicePassword": "123456",
    "decoder.timezone": "America/Sao_Paulo"
  }
}
```

### Atributos Comuns de Position

| Atributo | Tipo | Descrição |
|----------|------|-----------|
| `ignition` | boolean | Ignição ligada/desligada |
| `motion` | boolean | Veículo em movimento |
| `fuel` | number | Nível de combustível (litros ou %) |
| `fuelConsumption` | number | Consumo de combustível |
| `battery` | number | Voltagem da bateria do veículo |
| `batteryLevel` | number | Nível bateria interna do rastreador (%) |
| `odometer` | number | Hodômetro (metros) |
| `hours` | number | Horímetro (milissegundos) |
| `distance` | number | Distância desde última posição |
| `totalDistance` | number | Distância total |
| `rpm` | number | Rotações por minuto |
| `throttle` | number | Posição do acelerador (%) |
| `coolantTemp` | number | Temperatura do motor |
| `sat` | number | Quantidade de satélites |
| `rssi` | number | Intensidade sinal GSM |
| `event` | string | Tipo de evento (alarm, sos, etc) |
| `alarm` | string | Tipo de alarme |
| `driverUniqueId` | string | ID do motorista (iButton/RFID) |
| `temp1..N` | number | Sensores de temperatura |
| `adc1..N` | number | Entradas analógicas |
| `io1..N` | boolean | Entradas/saídas digitais |

### Atributos de Device (Configuração)

| Atributo | Tipo | Descrição |
|----------|------|-----------|
| `speedLimit` | number | Limite de velocidade (km/h) |
| `fuelCapacity` | number | Capacidade do tanque |
| `fuelDropThreshold` | number | Limite para detectar drenagem |
| `fuelIncreaseThreshold` | number | Limite para detectar abastecimento |
| `devicePassword` | string | Senha para enviar comandos |
| `deviceInactivityStart` | number | Início inatividade (ms desde meia-noite) |
| `deviceInactivityPeriod` | number | Período de inatividade (ms) |
| `processing.copyAttributes` | string | Copiar atributos do device para position |

### Usando Atributos no Frontend

```javascript
// Verificar ignição
if (position.attributes.ignition === true) {
  console.log("Veículo ligado");
}

// Verificar nível de combustível
const fuel = position.attributes.fuel || 0;
console.log(`Combustível: ${fuel}%`);

// Verificar odômetro (converter de metros para km)
const odometer = (position.attributes.odometer || 0) / 1000;
console.log(`Odômetro: ${odometer.toFixed(1)} km`);
```

---

## 4. Groups (Grupos)

### O que são Groups?

Grupos organizam dispositivos em hierarquias. Útil para separar por departamento, região, tipo de veículo, etc.

### Estrutura Hierárquica

```
Prefeitura (id: 1, groupId: null)
├── Secretaria de Saúde (id: 2, groupId: 1)
│   ├── Ambulâncias (id: 5, groupId: 2)
│   └── Veículos Administrativos (id: 6, groupId: 2)
├── Secretaria de Obras (id: 3, groupId: 1)
│   ├── Caminhões (id: 7, groupId: 3)
│   └── Máquinas (id: 8, groupId: 3)
└── Secretaria de Educação (id: 4, groupId: 1)
    └── Ônibus Escolares (id: 9, groupId: 4)
```

### Campos do Group

```json
{
  "id": 2,
  "name": "Secretaria de Saúde",
  "groupId": 1,
  "attributes": {
    "speedLimit": 80,
    "fuelCapacity": 60
  }
}
```

### Herança de Atributos

Atributos são herdados do grupo pai:

```
Prefeitura (speedLimit: 100)
└── Sec. Saúde (speedLimit: 80)        ← sobrescreve
    └── Ambulâncias (não definido)      ← herda 80
        └── Ambulância 01 (speedLimit: 120) ← sobrescreve
```

### API - Groups

```bash
# Listar
GET /api/groups

# Criar
POST /api/groups
{
  "name": "Novo Grupo",
  "groupId": 1
}

# Associar device ao grupo
PUT /api/devices/{id}
{
  "groupId": 5
}
```

---

## 5. Users (Usuários)

### Tipos de Usuários

```
┌─────────────────────────────────────────────────────────────┐
│                      HIERARQUIA                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐                                        │
│  │  Administrator  │  administrator = true                  │
│  │  Acesso total   │  Pode tudo                            │
│  └────────┬────────┘                                        │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────┐                                        │
│  │     Manager     │  userLimit > 0                        │
│  │  Gestor/Gerente │  Pode criar sub-usuários              │
│  └────────┬────────┘                                        │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────┐                                        │
│  │   User Normal   │  userLimit = 0                        │
│  │  Operador/Base  │  Apenas visualiza o que tem permissão │
│  └────────┬────────┘                                        │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────┐                                        │
│  │   Readonly      │  readonly = true                      │
│  │  Somente leitura│  Não pode editar nada                 │
│  └─────────────────┘                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Campos do User

```json
{
  "id": 1,
  "name": "João Silva",
  "email": "joao@prefeitura.gov.br",
  "login": "joao.silva",
  "phone": "+5511999999999",
  "administrator": false,
  "readonly": false,
  "disabled": false,
  "deviceLimit": 10,
  "userLimit": 5,
  "deviceReadonly": false,
  "limitCommands": false,
  "disableReports": false,
  "fixedEmail": false,
  "expirationTime": "2025-12-31T23:59:59Z",
  "attributes": {
    "notificationTokens": "firebase_token_here"
  }
}
```

### Permissões Detalhadas

| Campo | Descrição | Valor |
|-------|-----------|-------|
| `administrator` | Acesso total | true/false |
| `userLimit` | Quantos usuários pode criar (0 = nenhum, -1 = ilimitado) | number |
| `deviceLimit` | Quantos devices pode ter (0 = nenhum, -1 = ilimitado) | number |
| `readonly` | Somente visualização | true/false |
| `deviceReadonly` | Não pode editar devices | true/false |
| `limitCommands` | Não pode enviar comandos | true/false |
| `disableReports` | Não pode gerar relatórios | true/false |
| `disabled` | Conta desativada | true/false |
| `expirationTime` | Data de expiração da conta | datetime |

### Tabelas de Permissão

```sql
-- Usuário tem acesso a device
tc_user_device (userId, deviceId)

-- Usuário tem acesso a grupo (e todos devices do grupo)
tc_user_group (userId, groupId)

-- Usuário gerencia outro usuário
tc_user_user (userId, managedUserId)

-- Usuário tem acesso a geofence
tc_user_geofence (userId, geofenceId)

-- Usuário tem acesso a driver
tc_user_driver (userId, driverId)

-- etc...
```

### API - Users

```bash
# Listar
GET /api/users

# Criar
POST /api/users
{
  "name": "Maria Santos",
  "email": "maria@prefeitura.gov.br",
  "password": "senhaSegura123"
}

# Dar permissão de device ao usuário
POST /api/permissions
{
  "userId": 5,
  "deviceId": 10
}

# Remover permissão
DELETE /api/permissions
{
  "userId": 5,
  "deviceId": 10
}
```

---

## 6. Geofences (Cercas Virtuais)

### O que são Geofences?

Áreas geográficas que geram eventos quando um veículo entra ou sai.

### Tipos de Geofence

```
┌─────────────────────────────────────────────────────────────┐
│                    TIPOS DE GEOFENCE                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Círculo   │  │  Polígono   │  │   Linha     │         │
│  │  (radius)   │  │  (polygon)  │  │(polyline)   │         │
│  │     ●       │  │    ⬡       │  │    ╱        │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Formato WKT (Well-Known Text)

```
# Círculo (ponto central + raio)
CIRCLE (-46.633308 -23.550520, 500)

# Polígono
POLYGON ((-46.63 -23.55, -46.64 -23.55, -46.64 -23.56, -46.63 -23.56, -46.63 -23.55))

# Linha (corredor)
LINESTRING (-46.63 -23.55, -46.64 -23.56, -46.65 -23.57)
```

### Campos do Geofence

```json
{
  "id": 1,
  "name": "Garagem Central",
  "description": "Garagem da prefeitura",
  "area": "CIRCLE (-46.633308 -23.550520, 100)",
  "calendarId": 1,
  "attributes": {
    "color": "#FF0000",
    "speedLimit": 20
  }
}
```

### Usos de Geofences

| Uso | Descrição |
|-----|-----------|
| **Controle de área** | Veículo saiu da região permitida |
| **Ponto de interesse** | Chegou no cliente/destino |
| **Garagem** | Detectar entrada/saída da garagem |
| **Área de risco** | Alertar quando entrar em área perigosa |
| **Limite de velocidade** | Velocidade diferente por área |
| **Rota** | Verificar se está na rota (polyline) |

### Eventos de Geofence

```json
{
  "type": "geofenceEnter",  // ou "geofenceExit"
  "deviceId": 1,
  "geofenceId": 5,
  "positionId": 12345
}
```

### API - Geofences

```bash
# Criar círculo
POST /api/geofences
{
  "name": "Garagem",
  "area": "CIRCLE (-46.633308 -23.550520, 100)"
}

# Associar geofence ao device
POST /api/permissions
{
  "deviceId": 1,
  "geofenceId": 5
}
```

---

## 7. Drivers (Motoristas)

### O que são Drivers?

Motoristas que podem ser associados a dispositivos. Identificados por iButton, RFID, ou digitação.

### Identificação do Motorista

```
┌─────────────────────────────────────────────────────────────┐
│                FORMAS DE IDENTIFICAÇÃO                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   iButton   │  │    RFID     │  │   Manual    │         │
│  │  (Dallas)   │  │   (NFC)     │  │  (teclado)  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│        │               │                │                   │
│        └───────────────┴────────────────┘                   │
│                        │                                    │
│                        ▼                                    │
│              ┌─────────────────┐                            │
│              │ driverUniqueId  │                            │
│              │ no Position     │                            │
│              └─────────────────┘                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Campos do Driver

```json
{
  "id": 1,
  "name": "Carlos Oliveira",
  "uniqueId": "ABC123456",
  "attributes": {
    "phone": "+5511999999999",
    "license": "12345678900",
    "licenseExpire": "2025-06-15"
  }
}
```

### Como Funciona

1. Motorista aproxima iButton/RFID no leitor do rastreador
2. Rastreador envia `driverUniqueId` na posição
3. Traccar associa o `driverUniqueId` ao Driver cadastrado
4. Relatórios mostram qual motorista estava dirigindo

### API - Drivers

```bash
# Criar
POST /api/drivers
{
  "name": "Carlos Oliveira",
  "uniqueId": "ABC123456"
}

# Associar ao usuário
POST /api/permissions
{
  "userId": 5,
  "driverId": 1
}
```

---

## 8. Notifications (Notificações)

### O que são Notifications?

Regras que disparam alertas quando eventos ocorrem.

### Tipos de Eventos

| Tipo | Descrição |
|------|-----------|
| `deviceOnline` | Device ficou online |
| `deviceOffline` | Device ficou offline |
| `deviceUnknown` | Device status desconhecido |
| `deviceInactive` | Device inativo (não moveu) |
| `deviceMoving` | Device começou a mover |
| `deviceStopped` | Device parou |
| `deviceOverspeed` | Excedeu velocidade |
| `deviceFuelDrop` | Queda de combustível |
| `deviceFuelIncrease` | Aumento de combustível |
| `geofenceEnter` | Entrou em geofence |
| `geofenceExit` | Saiu de geofence |
| `alarm` | Alarme do rastreador |
| `ignitionOn` | Ignição ligada |
| `ignitionOff` | Ignição desligada |
| `maintenance` | Manutenção necessária |
| `driverChanged` | Motorista mudou |
| `commandResult` | Resultado de comando |
| `textMessage` | Mensagem de texto |

### Canais de Notificação

| Canal | Descrição |
|-------|-----------|
| `web` | Popup no navegador |
| `mail` | Email |
| `sms` | SMS |
| `firebase` | Push notification (app) |
| `telegram` | Mensagem no Telegram |
| `pushover` | Pushover app |

### Campos do Notification

```json
{
  "id": 1,
  "type": "deviceOverspeed",
  "always": false,
  "notificators": "web,mail",
  "calendarId": null,
  "commandId": null,
  "attributes": {
    "speedLimit": 80
  }
}
```

### Configuração de Email

```properties
# No traccar.xml ou variáveis de ambiente
MAIL_SMTP_HOST=smtp.gmail.com
MAIL_SMTP_PORT=587
MAIL_SMTP_STARTTLS_ENABLE=true
MAIL_SMTP_FROM=traccar@suaprefeitura.gov.br
MAIL_SMTP_USERNAME=usuario
MAIL_SMTP_PASSWORD=senha
```

### API - Notifications

```bash
# Criar
POST /api/notifications
{
  "type": "deviceOverspeed",
  "notificators": "web,mail"
}

# Associar ao device
POST /api/permissions
{
  "deviceId": 1,
  "notificationId": 5
}
```

---

## 9. Commands (Comandos)

### O que são Commands?

Comandos que podem ser enviados do servidor para o rastreador.

### Tipos de Comando

| Comando | Descrição |
|---------|-----------|
| `positionPeriodic` | Alterar intervalo de posições |
| `positionStop` | Parar de enviar posições |
| `engineStop` | Bloquear motor |
| `engineResume` | Desbloquear motor |
| `alarmArm` | Armar alarme |
| `alarmDisarm` | Desarmar alarme |
| `setTimezone` | Definir timezone |
| `requestPhoto` | Solicitar foto |
| `rebootDevice` | Reiniciar rastreador |
| `sendSms` | Enviar SMS |
| `sendUssd` | Enviar USSD |
| `sosNumber` | Configurar número SOS |
| `silenceTime` | Período de silêncio |
| `setIndicator` | Configurar indicador |
| `custom` | Comando customizado |

### Campos do Command

```json
{
  "id": 1,
  "deviceId": 5,
  "type": "engineStop",
  "description": "Bloquear veículo",
  "attributes": {}
}
```

### Comando Customizado

```json
{
  "type": "custom",
  "attributes": {
    "data": "COMANDO_RAW_AQUI"
  }
}
```

### API - Commands

```bash
# Enviar comando imediatamente
POST /api/commands/send
{
  "deviceId": 5,
  "type": "engineStop"
}

# Salvar comando para uso futuro
POST /api/commands
{
  "type": "engineStop",
  "description": "Bloquear emergência"
}

# Listar comandos suportados pelo device
GET /api/commands/types?deviceId=5
```

---

## 10. Reports (Relatórios)

### Tipos de Relatórios

| Relatório | Descrição |
|-----------|-----------|
| `route` | Rota percorrida |
| `events` | Lista de eventos |
| `trips` | Viagens (início → fim) |
| `stops` | Paradas |
| `summary` | Resumo por período |
| `combined` | Viagens + Paradas combinados |

### Relatório de Summary

```json
{
  "deviceId": 1,
  "deviceName": "Ambulância 01",
  "distance": 125.5,        // km
  "averageSpeed": 45.2,     // km/h
  "maxSpeed": 95.0,         // km/h
  "spentFuel": 15.5,        // litros
  "engineHours": 28800000,  // ms (8 horas)
  "startTime": "2024-01-15T08:00:00Z",
  "endTime": "2024-01-15T18:00:00Z"
}
```

### Relatório de Trips

```json
{
  "deviceId": 1,
  "deviceName": "Ambulância 01",
  "startTime": "2024-01-15T08:00:00Z",
  "startAddress": "Rua A, 123",
  "startLat": -23.550520,
  "startLon": -46.633308,
  "endTime": "2024-01-15T08:45:00Z",
  "endAddress": "Rua B, 456",
  "endLat": -23.560000,
  "endLon": -46.640000,
  "distance": 15.5,
  "averageSpeed": 35.0,
  "maxSpeed": 60.0,
  "duration": 2700000,
  "driverUniqueId": "ABC123",
  "driverName": "Carlos Oliveira"
}
```

### API - Reports

```bash
# Relatório de rotas
GET /api/reports/route?deviceId=1&from=2024-01-15T00:00:00Z&to=2024-01-15T23:59:59Z

# Relatório de viagens
GET /api/reports/trips?deviceId=1&from=2024-01-15T00:00:00Z&to=2024-01-15T23:59:59Z

# Relatório de summary
GET /api/reports/summary?deviceId=1&from=2024-01-15T00:00:00Z&to=2024-01-15T23:59:59Z

# Exportar em Excel
GET /api/reports/route?deviceId=1&from=...&to=...
Accept: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
```

---

## 11. Calendars (Calendários)

### O que são Calendars?

Definem períodos de tempo para aplicar regras (notificações, geofences).

### Formato iCalendar

```ical
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Traccar//NONSGML Traccar//EN
BEGIN:VEVENT
DTSTART:20240101T080000
DTEND:20240101T180000
RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
SUMMARY:Horário comercial
END:VEVENT
END:VCALENDAR
```

### Uso de Calendars

```json
{
  "id": 1,
  "name": "Horário Comercial",
  "data": "BEGIN:VCALENDAR...",
  "attributes": {}
}
```

### Aplicações

- **Geofence + Calendar**: Cerca só ativa em horário comercial
- **Notification + Calendar**: Alertas só durante expediente
- **Device + Calendar**: Inatividade só fora do expediente

---

## 12. Maintenance (Manutenção)

### O que é Maintenance?

Alertas de manutenção preventiva baseados em odômetro ou tempo.

### Tipos de Manutenção

| Tipo | Baseado em | Exemplo |
|------|------------|---------|
| `odometer` | Quilometragem | Trocar óleo a cada 10.000 km |
| `hours` | Horímetro | Revisar a cada 500 horas |
| `date` | Data | Vistoria anual |

### Campos do Maintenance

```json
{
  "id": 1,
  "name": "Troca de óleo",
  "type": "odometer",
  "start": 0,
  "period": 10000000,  // metros (10.000 km)
  "attributes": {}
}
```

### API - Maintenance

```bash
# Criar
POST /api/maintenance
{
  "name": "Troca de óleo",
  "type": "odometer",
  "start": 0,
  "period": 10000000
}

# Associar ao device
POST /api/permissions
{
  "deviceId": 1,
  "maintenanceId": 5
}
```

---

## 13. Computed Attributes

### O que são?

Atributos calculados automaticamente com base em outros atributos.

### Exemplo: Calcular consumo

```json
{
  "id": 1,
  "description": "Consumo km/L",
  "attribute": "fuelConsumption",
  "expression": "distance / (fuel * 0.01 * 60)",
  "type": "number"
}
```

### Sintaxe de Expressões

```javascript
// Operadores
+ - * / %

// Condicionais
speed > 80 ? 'alta' : 'normal'

// Atributos disponíveis
speed           // velocidade atual
distance        // distância desde última posição
totalDistance   // distância total
fuel            // nível de combustível
batteryLevel    // nível de bateria
ignition        // ignição
motion          // em movimento

// Atributos do device
deviceAttribute('speedLimit')
```

### API - Computed Attributes

```bash
POST /api/attributes/computed
{
  "description": "Velocidade em mph",
  "attribute": "speedMph",
  "expression": "speed * 0.621371",
  "type": "number"
}
```

---

## 14. API REST

### Autenticação

```bash
# Basic Auth
curl -u email:password https://traccar.example.com/api/devices

# Ou com token de sessão
POST /api/session
{
  "email": "user@example.com",
  "password": "senha"
}
# Retorna cookie JSESSIONID
```

### Endpoints Principais

```
/api/session          - Autenticação
/api/devices          - Dispositivos
/api/groups           - Grupos
/api/users            - Usuários
/api/positions        - Posições
/api/events           - Eventos
/api/geofences        - Cercas virtuais
/api/drivers          - Motoristas
/api/notifications    - Notificações
/api/commands         - Comandos
/api/reports/*        - Relatórios
/api/permissions      - Permissões
/api/server           - Configurações do servidor
/api/statistics       - Estatísticas
```

### Paginação

```bash
# Sem paginação (retorna todos)
GET /api/devices

# Com filtro
GET /api/positions?deviceId=1&from=2024-01-01T00:00:00Z&to=2024-01-31T23:59:59Z
```

### Exemplos Práticos

```bash
# Última posição de todos os devices
GET /api/positions

# Posições de um device específico
GET /api/positions?deviceId=1

# Histórico de posições
GET /api/positions?deviceId=1&from=2024-01-15T00:00:00Z&to=2024-01-15T23:59:59Z

# Criar device
POST /api/devices
Content-Type: application/json
{
  "name": "Veículo Novo",
  "uniqueId": "123456789012345"
}

# Atualizar device
PUT /api/devices/1
Content-Type: application/json
{
  "name": "Veículo Renomeado"
}

# Deletar device
DELETE /api/devices/1
```

---

## 15. WebSocket

### Conexão

```javascript
const socket = new WebSocket('wss://traccar.example.com/api/socket');

socket.onopen = () => {
  console.log('Conectado');
};

socket.onmessage = (event) => {
  const data = JSON.parse(event.data);

  if (data.positions) {
    // Novas posições
    data.positions.forEach(pos => {
      console.log(`Device ${pos.deviceId}: ${pos.latitude}, ${pos.longitude}`);
    });
  }

  if (data.devices) {
    // Atualização de status do device
    data.devices.forEach(dev => {
      console.log(`Device ${dev.id} status: ${dev.status}`);
    });
  }

  if (data.events) {
    // Novos eventos
    data.events.forEach(evt => {
      console.log(`Evento: ${evt.type} no device ${evt.deviceId}`);
    });
  }
};
```

### Tipos de Mensagens

```json
// Posições
{
  "positions": [{
    "id": 12345,
    "deviceId": 1,
    "latitude": -23.550520,
    "longitude": -46.633308,
    "speed": 45.5,
    ...
  }]
}

// Devices (atualização de status)
{
  "devices": [{
    "id": 1,
    "status": "online",
    "lastUpdate": "2024-01-15T10:30:00Z",
    ...
  }]
}

// Eventos
{
  "events": [{
    "id": 100,
    "type": "deviceOverspeed",
    "deviceId": 1,
    "positionId": 12345,
    ...
  }]
}
```

---

## 16. Configurações do Servidor

### Variáveis de Ambiente

```bash
# Banco de dados
DATABASE_DRIVER=org.postgresql.Driver
DATABASE_URL=jdbc:postgresql://localhost:5432/traccar
DATABASE_USER=traccar
DATABASE_PASSWORD=senha

# Web
WEB_PORT=8082
WEB_ADDRESS=0.0.0.0

# Geocodificação reversa
GEOCODER_ENABLE=true
GEOCODER_TYPE=nominatim
GEOCODER_URL=https://nominatim.openstreetmap.org/reverse

# Email
MAIL_SMTP_HOST=smtp.gmail.com
MAIL_SMTP_PORT=587
MAIL_SMTP_STARTTLS_ENABLE=true
MAIL_SMTP_FROM=traccar@example.com
MAIL_SMTP_USERNAME=usuario
MAIL_SMTP_PASSWORD=senha

# Device
DEVICE_TIMEOUT=300

# Logger
LOGGER_ENABLE=true
LOGGER_FILE=/opt/traccar/logs/tracker-server.log
```

### Timeouts

| Configuração | Descrição | Padrão |
|--------------|-----------|--------|
| `deviceTimeout` | Tempo para considerar offline (segundos) | 300 |
| `server.timeout` | Timeout de conexão TCP | 180000 |

### Processamento

| Configuração | Descrição |
|--------------|-----------|
| `filter.enable` | Ativar filtros de posição |
| `filter.invalid` | Filtrar posições inválidas |
| `filter.zero` | Filtrar coordenadas (0,0) |
| `filter.duplicate` | Filtrar posições duplicadas |
| `filter.distance` | Distância mínima entre posições |
| `filter.maxSpeed` | Velocidade máxima permitida |
| `filter.minPeriod` | Período mínimo entre posições |

---

## 17. Protocolos de Rastreadores

### Lista de Protocolos e Portas

| Porta | Protocolo | Marcas/Modelos |
|-------|-----------|----------------|
| 5001 | gps103 | TK103, GPS103 |
| 5002 | tk103 | Coban TK103 |
| 5003 | gl100 | Queclink GL100 |
| 5004 | gl200 | Queclink GL200/300 |
| 5005 | t55 | T55, Totem |
| 5006 | xexun | Xexun |
| 5007 | totem | Totem |
| 5008 | enfora | Enfora |
| 5009 | meiligao | Meiligao |
| 5010 | trv | TRV |
| 5011 | suntech | Suntech |
| 5012 | progress | Progress |
| 5013 | h02 | H02, TX-2, Sinotrack |
| 5014 | jt600 | JT600 |
| 5015 | huabao | Huabao |
| 5016 | v680 | V680 |
| 5017 | pt502 | PT502 |
| 5018 | tr20 | TR20 |
| 5019 | navis | Navis |
| 5020 | meitrack | Meitrack |
| 5021 | skypatrol | Skypatrol |
| 5022 | gt02 | GT02 |
| 5023 | gt06 | GT06, Concox |
| 5024 | megastek | Megastek |
| 5025 | navigil | Navigil |
| 5026 | gpsgate | GPSGate |
| 5027 | teltonika | Teltonika FMB/FMC |
| 5028 | mta6 | MTA6 |
| 5029 | tzone | Tzone |
| 5030 | tlt2h | TLT2H |
| 5031 | taip | TAIP |
| 5032 | wondex | Wondex |
| 5033 | cellocator | Cellocator |
| 5034 | galileo | Galileo |
| 5035 | ywt | YWT |
| 5036 | tk102 | TK102 |
| 5037 | intellitrac | Intellitrac |
| 5038 | gpsmta | GPSMTA |
| 5039 | wialon | Wialon |
| 5040 | carscop | Carscop |
| 5041 | apel | Apel |
| 5042 | manpower | Manpower |
| 5043 | globalsat | GlobalSat |
| 5044 | atrack | Atrack |
| 5045 | pt3000 | PT3000 |
| 5046 | ruptela | Ruptela |
| 5047 | ulbotech | Ulbotech |
| 5048 | tramigo | Tramigo |
| 5049 | tr900 | TR900 |
| 5050 | ardi01 | Ardi01 |
| 5051 | xt013 | XT013 |
| 5052 | autofon | Autofon |
| 5053 | gosafe | GoSafe |
| 5054 | tt8850 | TT8850 |
| 5055 | osmand | OsmAnd App |
| 5056 | easytrack | EasyTrack |
| ... | ... | ... |

### Configurar Protocolo

```bash
# Habilitar protocolo específico
GT06_PORT=5023
GT06_ENABLE=true

# Desabilitar protocolo não usado
GPS103_ENABLE=false
```

---

## 18. Sensores

### Tipos de Sensores

```
┌─────────────────────────────────────────────────────────────┐
│                    TIPOS DE SENSORES                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Combustível │  │ Temperatura │  │  Digitais   │         │
│  │    (FLS)    │  │   (temp1)   │  │  (io1..N)   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Analógicos │  │   iButton   │  │    OBD-II   │         │
│  │  (adc1..N)  │  │   (RFID)    │  │  (rpm, etc) │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Sensor de Combustível

```json
{
  "attributes": {
    "fuel": 75.5,          // % ou litros (depende do sensor)
    "fuelUsed": 125.5      // combustível usado
  }
}
```

**Configuração no device:**

```json
{
  "attributes": {
    "fuelCapacity": 60,           // capacidade do tanque em litros
    "fuelDropThreshold": 3,       // % queda para alertar drenagem
    "fuelIncreaseThreshold": 5    // % aumento para alertar abastecimento
  }
}
```

### Sensor de Temperatura

```json
{
  "attributes": {
    "temp1": 25.5,    // sensor 1
    "temp2": -18.0,   // sensor 2 (frigorífico)
    "temp3": 4.5      // sensor 3
  }
}
```

### Entradas Digitais

```json
{
  "attributes": {
    "io1": true,    // porta 1 aberta
    "io2": false,   // porta 2 fechada
    "io3": true,    // sirene acionada
    "door": true,   // alias para porta
    "panic": false  // botão de pânico
  }
}
```

### OBD-II (Diagnóstico Veicular)

```json
{
  "attributes": {
    "rpm": 2500,
    "throttle": 45.5,
    "coolantTemp": 90,
    "engineLoad": 35.0,
    "fuelLevel": 65.0,
    "obdSpeed": 60,
    "dtcs": "P0300,P0420"
  }
}
```

---

## 19. Integrações

### Webhook (Forward)

Enviar posições para outro servidor:

```bash
FORWARD_ENABLE=true
FORWARD_URL=http://seu-servidor.com/api/positions
FORWARD_JSON=true
```

### MQTT

```bash
MQTT_ENABLE=true
MQTT_BROKER=tcp://broker.example.com:1883
MQTT_TOPIC=traccar/positions
```

### Redis

```bash
REDIS_ENABLE=true
REDIS_URL=redis://localhost:6379
```

### Kafka

```bash
KAFKA_ENABLE=true
KAFKA_BROKERS=localhost:9092
KAFKA_TOPIC=traccar-positions
```

### Firebase (Push Notifications)

```bash
NOTIFICATOR_FIREBASE_ENABLE=true
NOTIFICATOR_FIREBASE_KEY_FILE=/opt/traccar/firebase-key.json
```

### Telegram

```bash
NOTIFICATOR_TELEGRAM_ENABLE=true
NOTIFICATOR_TELEGRAM_BOT_TOKEN=123456:ABC-DEF
NOTIFICATOR_TELEGRAM_CHAT_ID=-123456789
```

---

## 20. Dicas e Boas Práticas

### Performance

1. **Filtrar posições duplicadas**
   ```bash
   FILTER_ENABLE=true
   FILTER_DUPLICATE=true
   ```

2. **Indexar banco de dados**
   ```sql
   CREATE INDEX idx_positions_deviceid_time
   ON tc_positions (deviceid, fixtime);
   ```

3. **Limpar posições antigas**
   ```sql
   DELETE FROM tc_positions
   WHERE fixtime < NOW() - INTERVAL '90 days';
   ```

### Segurança

1. **Usar HTTPS**
   ```bash
   WEB_SECURE=true
   WEB_KEYSTORE=/opt/traccar/keystore.jks
   WEB_KEYSTORE_PASSWORD=senha
   ```

2. **Limitar tentativas de login**
   ```bash
   LOGIN_RETRY_DELAY=30000  # ms
   LOGIN_RETRY_COUNT=5
   ```

3. **Desabilitar registro público**
   ```bash
   SERVER_REGISTRATION=false
   ```

### Monitoramento

1. **Verificar saúde**
   ```bash
   curl http://localhost:8082/api/server
   ```

2. **Estatísticas**
   ```bash
   GET /api/statistics?from=2024-01-01T00:00:00Z&to=2024-01-31T23:59:59Z
   ```

### Backup

```bash
# PostgreSQL
pg_dump -U traccar traccar > backup.sql

# Volumes Docker
docker run --rm -v traccar-data:/data -v $(pwd):/backup \
  alpine tar cvf /backup/traccar-data.tar /data
```

---

## Referências

- [Documentação Oficial](https://www.traccar.org/documentation/)
- [API Reference](https://www.traccar.org/api-reference/)
- [Protocolos Suportados](https://www.traccar.org/protocols/)
- [Configurações](https://www.traccar.org/configuration-file/)
- [Fórum](https://www.traccar.org/forums/)
- [GitHub](https://github.com/traccar/traccar)
