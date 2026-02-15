# ---------- Stage 1: Build React App ----------
FROM node:20-alpine AS build

WORKDIR /app

# Copy dependency files first (caching)
COPY package*.json ./
RUN npm ci

# Copy source code
COPY . .

# Build static files
RUN npm run build


# ---------- Stage 2: Production image ----------
FROM nginx:1.27-alpine

# Copy built files from stage 1
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
