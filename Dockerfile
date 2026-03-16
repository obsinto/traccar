# Stage 1: Build backend (Java)
FROM gradle:8.14-jdk21 AS backend-builder
WORKDIR /app
COPY build.gradle settings.gradle gradlew ./
COPY gradle ./gradle
COPY src ./src
COPY schema ./schema
COPY templates ./templates
RUN gradle assemble --no-daemon

# Stage 2: Build frontend (React)
FROM node:22-alpine AS frontend-builder
RUN apk add --no-cache git
WORKDIR /app
ARG TRACCAR_WEB_REPO=https://github.com/obsinto/traccar-web.git
ARG TRACCAR_WEB_BRANCH=master
RUN git clone --depth 1 --branch ${TRACCAR_WEB_BRANCH} ${TRACCAR_WEB_REPO} .
RUN npm ci
RUN npm run build

# Stage 3: Create package
FROM alpine:3.22 AS packager
WORKDIR /package
RUN mkdir -p conf data lib logs web schema templates

COPY --from=backend-builder /app/target/tracker-server.jar ./
COPY --from=backend-builder /app/target/lib ./lib
COPY --from=backend-builder /app/schema ./schema
COPY --from=backend-builder /app/templates ./templates
COPY --from=frontend-builder /app/build ./web
COPY --from=frontend-builder /app/src/resources/l10n ./templates/translations

# Stage 4: Create minimal JRE
FROM eclipse-temurin:21-alpine AS jdk
RUN jlink --module-path $JAVA_HOME/jmods \
    --add-modules java.se,jdk.charsets,jdk.crypto.ec,jdk.unsupported \
    --strip-debug --no-header-files --no-man-pages --compress=2 --output /jre

# Stage 5: Final image
FROM alpine:3.22
LABEL maintainer="your-email@example.com"

RUN apk add --no-cache tzdata

COPY --from=packager /package /opt/traccar
COPY --from=jdk /jre /opt/traccar/jre

# Create default config that uses environment variables
RUN mkdir -p /opt/traccar/conf && \
    echo '<?xml version="1.0" encoding="UTF-8"?>' > /opt/traccar/conf/traccar.xml && \
    echo '<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">' >> /opt/traccar/conf/traccar.xml && \
    echo '<properties>' >> /opt/traccar/conf/traccar.xml && \
    echo '    <entry key="config.useEnvironmentVariables">true</entry>' >> /opt/traccar/conf/traccar.xml && \
    echo '</properties>' >> /opt/traccar/conf/traccar.xml

WORKDIR /opt/traccar

# Default ports
EXPOSE 8082 5000-5150

VOLUME ["/opt/traccar/logs", "/opt/traccar/data"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8082/api/health || exit 1

ENTRYPOINT ["/opt/traccar/jre/bin/java"]
CMD ["-jar", "tracker-server.jar", "conf/traccar.xml"]
