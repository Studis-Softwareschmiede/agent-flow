# Java (Maven) → Build + schlankes JRE-Runtime-Image
FROM maven:3-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -q -DskipTests dependency:go-offline
COPY . .
RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

# Build-Versionierung (docs/specs/build-version-stamping.md AC2/AC4): Version wird
# beim Build INS Image gebrannt (Datei), nicht nur in ENV — ENV wird bei einem
# Container-Recreate vom Alt-Container übernommen und friert die Anzeige ein, die
# gebrannte Datei nicht (flashrescue-Vorfall 2026-07-19). Labels aus denselben ARGs.
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ARG BUILD_CREATED=""
RUN echo "$APP_VERSION" > /app/VERSION

LABEL org.opencontainers.image.version="$APP_VERSION" \
      org.opencontainers.image.revision="$GIT_SHA" \
      org.opencontainers.image.created="$BUILD_CREATED"

# Non-root-Runtime (Security-Floor). WICHTIG: ein non-root-Container kann NICHT in
# root-owned Pfade schreiben. Jeder zur Laufzeit beschriebene Pfad (Datei-/Batch-/IO-
# Output, Temp-Downloads, FTP-Ziele) braucht ein EXPLIZIT writable Data-Dir — sonst
# AccessDeniedException erst zur Laufzeit (Unit-Tests sehen das strukturell nicht;
# vgl. upgrade-subsystem §16). App-Schreibpfade (z.B. via Property/Env) hierher legen.
RUN groupadd -r app && useradd -r -g app app \
    && mkdir -p /app/data \
    && chown -R app:app /app/data
USER app

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
