# Angular → Build via node, statisch via nginx
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
# Angular 17+: dist/<app>/browser — bei Bedarf Pfad anpassen
COPY --from=build /app/dist/*/browser /usr/share/nginx/html
EXPOSE 80
