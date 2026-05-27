FROM node:22-alpine AS build
WORKDIR /app
COPY package.json ./
# Lockfile is intentionally not committed — small project, deterministic deps
# come from explicit version pins in package.json. Run `npm install` here so
# the install resolves on first build.
RUN npm install
COPY tsconfig.json drizzle.config.ts ./
COPY src ./src
RUN npx tsc

FROM node:22-alpine
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./
ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "dist/server.js"]
