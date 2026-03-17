


# Famichat

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Alpha](https://img.shields.io/badge/Status-Alpha-orange.svg)](#status)

Famichat is a self-hosted messaging server for a closed, trusted group of people—your family or inner circle. You run the backend, generate the invite links, and keep the data on your own hardware. 

It currently handles real-time text messaging, passkey authentication, and invite-based onboarding through a web interface. 

## Status: Alpha

This is early software, currently run by one developer to validate the core mechanics. 

**Important note for operators:** Famichat is not yet end-to-end encrypted. Right now, the server decrypts messages to render the interface. This means whoever controls the server and database can read the message content. 

The immediate roadmap focuses entirely on fixing this by moving decryption to the client. The next release will introduce a Svelte single-page application where the OpenMLS library compiles to WebAssembly. This allows the browser to encrypt and decrypt messages locally. Once that ships, the server will become a blind relay that only stores and forwards encrypted blobs.

Until that milestone is finished, you should only invite people who explicitly trust you as the server operator.



## What this is not

There is no cloud service or mandatory central account. While we might explore deployment templates or other hosting conveniences later, running the server on your own infrastructure will always be a fully supported, first-class option. 

The application does not include public friend discovery, algorithmic feeds, engagement tracking, or default telemetry back to a central server. It is built strictly for closed, invite-only communication.

## Features and access

Right now, users access Famichat through a web browser or by installing it to their home screen as a Progressive Web App (PWA). Dedicated mobile and desktop applications are planned for later development phases.

### Messaging and authentication
Text messaging happens in real time. Accounts are secured entirely by passkeys—Touch ID, Face ID, Windows Hello, or hardware keys. Because there are no passwords, you do not have to worry about securing a password database or handling reset emails for now. Other options are planned in the future, but this is the most convenient. Onboarding happens strictly through single-use invite links that expire after 72 hours.

### Governance and customization
The permissions and customization options are split into three tiers so you can tailor the space to your specific group.

As the community admin running the server, you control the deployment and the branding. You can rename the application entirely using the `WEBAUTHN_RP_NAME` environment variable and the `backend/bin/rename-project` script. This ensures your family members see a name they recognize when their browser prompts them for a passkey. 

Family admins manage their specific household space. They issue the invite links and approve new devices for younger members. 

Individual users control their own display preferences, accessibility features, and notification settings.

### Internationalization
The interface supports multiple languages out of the box, currently shipping with English and Japanese. The layout is structured to support both left-to-right and right-to-left languages naturally. Adding a new language to your deployment only requires adding the corresponding translation file.




## Prerequisites

To run Famichat, you need a Linux host with at least 1 vCPU and 1 GB of RAM. The software runs as a Docker Compose stack, which includes the backend application and a PostgreSQL 16 database.

You must have a registered domain name and a reverse proxy (such as Caddy, Nginx, or Cloudflare Tunnel) configured to handle HTTPS traffic. Passkey authentication relies on the WebAuthn API, which browsers strictly block on unencrypted HTTP connections.

By default, the application binds to `127.0.0.1:8001`. You will need to route your reverse proxy to this port.

## Deploy

1. Clone the repository and navigate to the backend directory:
   ```bash
   git clone https://github.com/zaneriley/famichat.git
   cd famichat/backend
   ```

2. Copy the production environment template and secure the file:
   ```bash
   cp .env.production.example .env.production
   chmod 0600 .env.production
   ```

3. Generate your cryptographic secrets. Run the following commands and paste each output into the corresponding variables in your `.env.production` file:
   ```bash
   openssl rand -base64 64   # SECRET_KEY_BASE
   openssl rand -base64 32   # UNIQUE_CONVERSATION_KEY_SALT
   openssl rand -base64 32   # MLS_SNAPSHOT_HMAC_KEY
   openssl rand -base64 32   # FAMICHAT_VAULT_KEY
   openssl rand -base64 32   # POSTGRES_PASSWORD
   ```

4. Configure your domain variables. Passkeys are cryptographically bound to the origin they are registered on. `URL_HOST`, `WEBAUTHN_ORIGIN`, and `WEBAUTHN_RP_ID` must all match your domain exactly. If you change your domain later, all existing passkeys will fail.
   ```
   URL_HOST=chat.yourfamily.net
   WEBAUTHN_ORIGIN=https://chat.yourfamily.net
   WEBAUTHN_RP_ID=chat.yourfamily.net
   ```

5. Start the Docker Compose stack in the background:
   ```bash
   docker compose -f docker-compose.production.yml up -d
   ```

6. Verify the server and database are healthy:
   ```bash
   curl -fsS http://localhost:8001/up/databases
   ```

7. Open `https://your-domain/setup` in your browser. This route will guide you through creating the community admin account and registering your first passkey.




## Prerequisites

To run Famichat, you need a Linux host with at least 1 vCPU and 1 GB of RAM. The software runs as a Docker Compose stack, which includes the backend application and a PostgreSQL 16 database.


To use the web app outside your network, you'll need to have a registered domain name and a reverse proxy (such as Caddy, Nginx, or Cloudflare Tunnel) configured to handle HTTPS traffic. Passkey authentication relies on the WebAuthn API, which browsers strictly block on unencrypted HTTP connections.

By default, the application binds to `127.0.0.1:8001`. You will need to route your reverse proxy to this port.

## Deploy

1. Clone the repository and navigate to the backend directory:
   ```bash
   git clone https://github.com/zaneriley/famichat.git
   cd famichat/backend
   ```

2. Copy the production environment template and secure the file:
   ```bash
   cp .env.production.example .env.production
   chmod 0600 .env.production
   ```

3. Generate your cryptographic secrets. Run the following commands and paste each output into the corresponding variables in your `.env.production` file:
   ```bash
   openssl rand -base64 64   # SECRET_KEY_BASE
   openssl rand -base64 32   # UNIQUE_CONVERSATION_KEY_SALT
   openssl rand -base64 32   # MLS_SNAPSHOT_HMAC_KEY
   openssl rand -base64 32   # FAMICHAT_VAULT_KEY
   openssl rand -base64 32   # POSTGRES_PASSWORD
   ```

4. Configure your domain variables. Passkeys are cryptographically bound to the origin they are registered on. `URL_HOST`, `WEBAUTHN_ORIGIN`, and `WEBAUTHN_RP_ID` must all match your domain exactly. If you change your domain later, all existing passkeys will fail.
   ```
   URL_HOST=chat.yourfamily.net
   WEBAUTHN_ORIGIN=https://chat.yourfamily.net
   WEBAUTHN_RP_ID=chat.yourfamily.net
   ```

5. Start the Docker Compose stack in the background:
   ```bash
   docker compose -f docker-compose.production.yml up -d
   ```

6. Verify the server and database are healthy:
   ```bash
   curl -fsS http://localhost:8001/up/databases
   ```

7. Open `https://your-domain/setup` in your browser. This route will guide you through creating the community admin account and registering your first passkey.