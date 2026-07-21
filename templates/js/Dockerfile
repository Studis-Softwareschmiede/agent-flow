# Node-Service
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

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

EXPOSE 8080
CMD ["node", "server.js"]
