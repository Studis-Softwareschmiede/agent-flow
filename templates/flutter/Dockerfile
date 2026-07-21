# Flutter Web → statisch via nginx
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM nginx:alpine

# Build-Versionierung (docs/specs/build-version-stamping.md AC4/AC6): dieselbe Version
# wird zur Build-Zeit als version.json ins served-dir geschrieben, und index.html wird
# via nginx.conf mit no-cache ausgeliefert — damit die GUI-Version nach jedem Deploy
# sofort mitzieht statt in einem Edge-/Browser-Cache einzufrieren (flashrescue-Vorfall
# 2026-07-19). Gleiche ARG-Namen/Label-Keys wie die Service-Dockerfiles (S-090).
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ARG BUILD_CREATED=""

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN echo "{\"version\":\"$APP_VERSION\",\"revision\":\"$GIT_SHA\"}" > /usr/share/nginx/html/version.json

LABEL org.opencontainers.image.version="$APP_VERSION" \
      org.opencontainers.image.revision="$GIT_SHA" \
      org.opencontainers.image.created="$BUILD_CREATED"

EXPOSE 80
