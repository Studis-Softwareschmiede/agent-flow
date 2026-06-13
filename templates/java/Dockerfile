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
