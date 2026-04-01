# Build stage
FROM node:20-slim AS builder

WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci --production=false

COPY src/ src/
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# Runtime stage
FROM node:20-slim

# Install system tools needed by the agent
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    less \
    groff \
    net-tools \
    iproute2 \
    iputils-ping \
    traceroute \
    dnsutils \
    procps \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 (ARM64)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

WORKDIR /app
COPY --from=builder /app/dist/ dist/
COPY --from=builder /app/node_modules/ node_modules/
COPY --from=builder /app/package.json .
COPY skills/ skills/

ENV NODE_ENV=production
ENV SKILLS_DIR=/app/skills
ENV WORKSPACE_PATH=/mnt/workspace

EXPOSE 8080

CMD ["node", "dist/index.js"]
