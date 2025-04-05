# To use this Dockerfile, you have to set `output: 'standalone'` in your next.config.mjs file.
# From https://github.com/vercel/next.js/blob/canary/examples/with-docker/Dockerfile

FROM node:22.12.0-alpine AS base

# Install latest corepack
RUN npm install -g corepack@0.32.0 && corepack enable

# Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; \
  fi


# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Next.js collects completely anonymous telemetry data about general usage.
# Learn more here: https://nextjs.org/telemetry
# Uncomment the following line in case you want to disable telemetry during the build.
ENV NEXT_TELEMETRY_DISABLED 1

# Run the build command first
RUN \
  if [ -f yarn.lock ]; then yarn run build; \
  elif [ -f package-lock.json ]; then npm run build; \
  elif [ -f pnpm-lock.yaml ]; then pnpm run build; \
  else echo "Lockfile not found." && exit 1; \
  fi

# Then run the migrate command
# Note: You might need your DATABASE_URI available at build time for migrations.
# If migrations fail here, consider running them as an entrypoint command
# or a separate step after the build but before starting the app in production.
# RUN \
#  if [ -f yarn.lock ]; then yarn run migrate; \
#  elif [ -f package-lock.json ]; then npm run migrate; \
#  elif [ -f pnpm-lock.yaml ]; then pnpm run migrate; \
#  else echo "Lockfile not found." && exit 1; \
#  fi


# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
# Uncomment the following line in case you want to disable telemetry during runtime.
ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy the *entire* application directory from the builder stage
# This includes the source, the build output (.next), and the full node_modules
COPY --from=builder --chown=nextjs:nodejs /app /app

# Ensure correct permissions on the copied .next directory
# (Optional but good practice if Next.js needs to write cache files etc.)
RUN chown -R nextjs:nodejs /app/.next

USER nextjs

EXPOSE 3000

ENV PORT 3000

# The start command needs to execute the server.js file
# which is located inside the .next/standalone directory relative to /app
CMD HOSTNAME="0.0.0.0" node .next/standalone/server.js
