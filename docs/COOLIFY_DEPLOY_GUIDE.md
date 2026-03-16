# Guia de Deploy do Traccar no Coolify

Este guia documenta como configuramos o Traccar para deploy no Coolify, incluindo a arquitetura do projeto, processo de build e configurações necessárias.

## Índice

1. [Arquitetura do Projeto](#arquitetura-do-projeto)
2. [Estrutura de Arquivos](#estrutura-de-arquivos)
3. [Como Funciona o Build](#como-funciona-o-build)
4. [Docker Compose](#docker-compose)
5. [Configuração no Coolify](#configuração-no-coolify)
6. [Variáveis de Ambiente](#variáveis-de-ambiente)
7. [Portas e Protocolos](#portas-e-protocolos)
8. [Troubleshooting](#troubleshooting)

---

## Arquitetura do Projeto

O Traccar é composto por dois componentes principais:

```
┌─────────────────────────────────────────────────────────┐
│                    Container Traccar                     │
│  ┌─────────────────────┐  ┌─────────────────────────┐   │
│  │   Backend (Java)    │  │   Frontend (React)      │   │
│  │   - API REST        │  │   - Interface Web       │   │
│  │   - WebSocket       │  │   - Arquivos estáticos  │   │
│  │   - Protocolos GPS  │  │   - PWA                 │   │
│  │   - Jetty Server    │  │                         │   │
│  └─────────────────────┘  └─────────────────────────┘   │
│                              ↓                           │
│                    /opt/traccar/web/                     │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│                  Container PostgreSQL                    │
│                    Banco de Dados                        │
└─────────────────────────────────────────────────────────┘
```

### Componentes

| Componente | Tecnologia | Descrição |
|------------|------------|-----------|
| Backend | Java 21 + Jetty | API REST, WebSocket, protocolos de rastreadores |
| Frontend | React + Vite | Interface web (SPA) servida pelo backend |
| Banco | PostgreSQL 16 | Armazenamento de dados |

**Importante:** O frontend não roda em um container separado. Os arquivos estáticos são compilados e copiados para `/opt/traccar/web/`, onde o servidor Jetty os serve.

---

## Estrutura de Arquivos

```
traccar/
├── Dockerfile                    # Build multi-stage
├── docker-compose.yaml           # Compose principal
├── .dockerignore                 # Arquivos ignorados no build
├── coolify/
│   ├── docker-compose.coolify.yaml
│   └── .env.example
├── src/                          # Código Java do backend
├── build.gradle                  # Configuração do Gradle
├── schema/                       # Migrations do banco (Liquibase)
├── templates/                    # Templates de relatórios
└── traccar-web/                  # Submodule do frontend (React)
    ├── src/
    ├── package.json
    └── vite.config.js
```

### Sobre o Submodule

O `traccar-web` é um **Git submodule**, ou seja, um repositório separado vinculado ao repositório principal. Isso causa problemas no Coolify porque ele não clona submodules automaticamente.

**Solução:** O Dockerfile clona o repositório do frontend diretamente durante o build.

---

## Como Funciona o Build

O Dockerfile usa **multi-stage build** com 5 estágios:

### Stage 1: Build do Backend (Java)

```dockerfile
FROM gradle:8.14-jdk21 AS backend-builder
WORKDIR /app
COPY build.gradle settings.gradle gradlew ./
COPY gradle ./gradle
COPY src ./src
COPY schema ./schema
COPY templates ./templates
RUN gradle assemble --no-daemon
```

**O que faz:**
- Usa imagem com Gradle + JDK 21
- Copia código fonte Java
- Compila com `gradle assemble`
- Gera `target/tracker-server.jar` + dependências em `target/lib/`

### Stage 2: Build do Frontend (React)

```dockerfile
FROM node:22-alpine AS frontend-builder
RUN apk add --no-cache git
WORKDIR /app
ARG TRACCAR_WEB_REPO=https://github.com/obsinto/traccar-web.git
ARG TRACCAR_WEB_BRANCH=master
RUN git clone --depth 1 --branch ${TRACCAR_WEB_BRANCH} ${TRACCAR_WEB_REPO} .
RUN npm ci
RUN npm run build
```

**O que faz:**
- Usa imagem Node.js 22
- Clona o repositório do frontend (não usa submodule)
- Instala dependências com `npm ci`
- Compila com Vite, gera arquivos em `build/`

**Por que clonar ao invés de copiar?**
O Coolify não inicializa submodules. Clonar durante o build garante que o código esteja disponível.

### Stage 3: Empacotamento

```dockerfile
FROM alpine:3.22 AS packager
WORKDIR /package
RUN mkdir -p conf data lib logs web schema templates

COPY --from=backend-builder /app/target/tracker-server.jar ./
COPY --from=backend-builder /app/target/lib ./lib
COPY --from=backend-builder /app/schema ./schema
COPY --from=backend-builder /app/templates ./templates
COPY --from=frontend-builder /app/build ./web
COPY --from=frontend-builder /app/src/resources/l10n ./templates/translations
```

**O que faz:**
- Cria estrutura de diretórios
- Copia artefatos do backend e frontend
- Organiza tudo em `/package/`

### Stage 4: JRE Mínimo

```dockerfile
FROM eclipse-temurin:21-alpine AS jdk
RUN jlink --module-path $JAVA_HOME/jmods \
    --add-modules java.se,jdk.charsets,jdk.crypto.ec,jdk.unsupported \
    --strip-debug --no-header-files --no-man-pages --compress=2 --output /jre
```

**O que faz:**
- Usa `jlink` para criar JRE customizado
- Inclui apenas módulos necessários
- Reduz tamanho da imagem (~150MB vs ~400MB)

### Stage 5: Imagem Final

```dockerfile
FROM alpine:3.22
RUN apk add --no-cache tzdata

COPY --from=packager /package /opt/traccar
COPY --from=jdk /jre /opt/traccar/jre

RUN mkdir -p /opt/traccar/conf && \
    echo '<?xml version="1.0" encoding="UTF-8"?>' > /opt/traccar/conf/traccar.xml && \
    echo '<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">' >> /opt/traccar/conf/traccar.xml && \
    echo '<properties>' >> /opt/traccar/conf/traccar.xml && \
    echo '    <entry key="config.useEnvironmentVariables">true</entry>' >> /opt/traccar/conf/traccar.xml && \
    echo '</properties>' >> /opt/traccar/conf/traccar.xml

WORKDIR /opt/traccar
EXPOSE 8082 5000-5150
VOLUME ["/opt/traccar/logs", "/opt/traccar/data"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8082/api/health || exit 1

ENTRYPOINT ["/opt/traccar/jre/bin/java"]
CMD ["-jar", "tracker-server.jar", "conf/traccar.xml"]
```

**O que faz:**
- Imagem base Alpine (mínima)
- Copia aplicação e JRE
- Cria `traccar.xml` que habilita variáveis de ambiente
- Expõe portas
- Configura healthcheck
- Define comando de inicialização

---

## Docker Compose

### docker-compose.yaml

```yaml
services:
  traccar:
    build:
      context: .
      dockerfile: Dockerfile
    restart: unless-stopped
    ports:
      - '8082:8082'                    # Interface Web + API
      - '5000-5150:5000-5150/tcp'      # Protocolos GPS (TCP)
      - '5000-5150:5000-5150/udp'      # Protocolos GPS (UDP)
    environment:
      - SERVICE_URL_TRACCAR_8082       # Coolify: gera URL pública
      - 'CONFIG_USE_ENVIRONMENT_VARIABLES=true'
      - 'DATABASE_DRIVER=org.postgresql.Driver'
      - 'DATABASE_URL=jdbc:postgresql://postgres:5432/${POSTGRESQL_DATABASE:-traccar}?sslmode=disable'
      - 'DATABASE_USER=${SERVICE_USER_POSTGRES}'
      - 'DATABASE_PASSWORD=${SERVICE_PASSWORD_POSTGRES}'
    volumes:
      - 'traccar-logs:/opt/traccar/logs'
      - 'traccar-data:/opt/traccar/data'
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:8082"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s

  postgres:
    image: 'postgres:16-alpine'
    restart: unless-stopped
    environment:
      - 'POSTGRES_USER=${SERVICE_USER_POSTGRES}'
      - 'POSTGRES_PASSWORD=${SERVICE_PASSWORD_POSTGRES}'
      - 'POSTGRES_DB=${POSTGRESQL_DATABASE:-traccar}'
    volumes:
      - 'traccar-postgresql-data:/var/lib/postgresql/data'
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 20s
      retries: 10

volumes:
  traccar-logs:
  traccar-data:
  traccar-postgresql-data:
```

### Explicação das Configurações

#### depends_on com condition

```yaml
depends_on:
  postgres:
    condition: service_healthy
```

O Traccar só inicia **após** o PostgreSQL estar healthy (healthcheck passou).

#### Healthcheck

```yaml
healthcheck:
  test: ["CMD", "wget", "--spider", "http://127.0.0.1:8082"]
  start_period: 120s  # 2 minutos para inicializar
```

- `start_period`: tempo de graça antes de considerar unhealthy
- Importante porque o Java demora para iniciar

#### Volumes Nomeados

```yaml
volumes:
  traccar-logs:
  traccar-data:
  traccar-postgresql-data:
```

Persistem dados entre restarts/deploys:
- `traccar-logs`: logs da aplicação
- `traccar-data`: dados internos
- `traccar-postgresql-data`: banco de dados

---

## Configuração no Coolify

### Passo 1: Criar o Serviço

1. **New Resource** → **Docker Compose**
2. Selecione o repositório Git
3. Branch: `master`
4. Compose file: `docker-compose.yaml`

### Passo 2: Configurar Domínio

1. Vá em **Configuration** ou **Network**
2. Em **Domains**, adicione: `https://seu-dominio.com`
3. **Não** coloque porta no domínio (errado: `https://dominio.com:8082`)

### Passo 3: Mapear Porta

O Coolify deve detectar automaticamente via `SERVICE_URL_TRACCAR_8082`.

Se não detectar, configure manualmente em **Network → Ports Mappings**:

| Container Port | Domain |
|----------------|--------|
| 8082 | seu-dominio.com |

### Passo 4: Variáveis (Opcional)

O Coolify auto-gera:
- `SERVICE_USER_POSTGRES`
- `SERVICE_PASSWORD_POSTGRES`

Você pode adicionar outras em **Environment Variables**.

### Passo 5: Deploy

Clique em **Deploy**. O primeiro build demora ~5-10 minutos.

---

## Variáveis de Ambiente

### Geradas pelo Coolify

| Variável | Descrição |
|----------|-----------|
| `SERVICE_USER_POSTGRES` | Usuário do PostgreSQL (gerado) |
| `SERVICE_PASSWORD_POSTGRES` | Senha do PostgreSQL (gerado) |
| `SERVICE_URL_TRACCAR_8082` | URL pública do serviço |

### Configuração do Traccar

O Traccar usa o padrão: `CATEGORIA_CHAVE=valor`

Exemplos:

| Variável | Descrição |
|----------|-----------|
| `DATABASE_DRIVER` | Driver JDBC |
| `DATABASE_URL` | String de conexão |
| `DATABASE_USER` | Usuário do banco |
| `DATABASE_PASSWORD` | Senha do banco |
| `SERVER_FORWARD` | Aceitar X-Forwarded headers |
| `GEOCODER_ENABLE` | Habilitar geocodificação |
| `GEOCODER_TYPE` | Tipo (nominatim, google, etc) |
| `MAIL_SMTP_HOST` | Servidor SMTP |

Documentação completa: https://www.traccar.org/configuration-file/

---

## Portas e Protocolos

### Porta 8082 - Web/API

- Interface web
- API REST (`/api/*`)
- WebSocket (`/api/socket`)

### Portas 5000-5150 - Rastreadores GPS

Cada protocolo de rastreador usa uma porta específica:

| Porta | Protocolo | Dispositivos |
|-------|-----------|--------------|
| 5001 | GPS103 | TK103, GPS103 |
| 5002 | TK103 | Coban TK103 |
| 5006 | GL200 | Queclink GL200/300 |
| 5007 | GL100 | Queclink GL100 |
| 5013 | Teltonika | FMB/FMC series |
| 5023 | GT06 | Concox GT06N |
| 5027 | Syrus | DCT Syrus |
| 5055 | OsmAnd | App OsmAnd |
| 5093 | Suntech | Suntech ST300/ST340 |

Lista completa: https://www.traccar.org/protocols/

**Importante:** Para rastreadores funcionarem, as portas devem estar abertas no firewall e no Cloudflare (se usar).

---

## Troubleshooting

### Erro 502 Bad Gateway

**Causa:** Proxy não consegue conectar ao container.

**Soluções:**
1. Verifique se o container está Running + Healthy
2. No Coolify, configure manualmente a porta 8082 → domínio
3. No Cloudflare, SSL mode deve ser "Full" ou "Full (Strict)"

### Container reiniciando (Restarting)

**Causa:** Erro na inicialização.

**Soluções:**
1. Verifique os logs: `docker logs <container_id>`
2. Comum: PostgreSQL não está pronto
3. Aumente `start_period` do healthcheck

### Erro "npm ci" no build

**Causa:** Submodule traccar-web não está disponível.

**Solução:** O Dockerfile já clona o repositório. Verifique se a URL está correta:
```dockerfile
ARG TRACCAR_WEB_REPO=https://github.com/SEU_USUARIO/traccar-web.git
```

### Database connection refused

**Causa:** Traccar tentou conectar antes do PostgreSQL estar pronto.

**Solução:** Já configurado com `depends_on: condition: service_healthy`

### Acesso direto por IP funciona, por domínio não

**Causa:** Configuração do proxy/Cloudflare.

**Soluções:**
1. Verifique mapeamento porta → domínio no Coolify
2. No Cloudflare: SSL mode = Full
3. Verifique se DNS aponta para IP correto

---

## Comandos Úteis

### Ver logs do container

```bash
docker logs -f <container_id>
```

### Acessar shell do container

```bash
docker exec -it <container_id> sh
```

### Verificar se porta está ouvindo

```bash
docker exec <container_id> wget -qO- http://127.0.0.1:8082/api/health
```

### Rebuild forçado (sem cache)

No Coolify: **Redeploy** com opção "Force rebuild"

---

## Referências

- [Traccar Documentation](https://www.traccar.org/documentation/)
- [Traccar Configuration](https://www.traccar.org/configuration-file/)
- [Traccar Protocols](https://www.traccar.org/protocols/)
- [Coolify Documentation](https://coolify.io/docs)
- [Docker Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)
