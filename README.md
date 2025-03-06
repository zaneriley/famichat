# Famichat
Secure, Self-Hosted Family Communication Platform

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Project Status: Alpha](https://img.shields.io/badge/Project%20Status-Alpha-orange)](https://en.wikipedia.org/wiki/Software_release_life_cycle#Alpha)


**A self-hosted, white-label video and chat application designed to create a secure and intimate digital space for families.**

## Overview

We're trying to build a private video and chat app meant for a single household. Our goal is that you can customize it and white-label (e.g. your design) to fit your family's needs. The goal is for a non-capitalist app that's a bit more Animal Crossing than social media – relaxed and more about connection than constant updates.

For now, this repo is mainly a playground to test out:

*   A basic backend in Elixir/Phoenix.
*   A simple Flutter app that can talk to it.
```
+---------------------+      WebSocket/Phoenix Channels     +---------------------+
| Flutter Client App  | <-----------------------------------> | Phoenix Backend     |
+---------------------+                                     +---------------------+
      |                                                         |
      | UI, State Mgmt, WebRTC                                  | Controllers, Channels, Bots/Agents,       
      | WebRTC Signaling, DB Access                             |
      v                                                         v
+---------------------+                                     +---------------------+
| Rich Media (Local  |                                      | PostgreSQL Database |
| Caching, Playback) |                                      +---------------------+
+---------------------+                                          ^
                                                                 | (Metadata, Text, Media Refs)
                                                                 |
                                                         +---------------------+
                                                         | Object Storage      |
                                                         | AWS S3, MinIO, etc. |
                                                         +---------------------+
                                                                 ^
                                                                 | (Rich Media)
                                                                 |
                                                         +---------------------+
                                                         | TURN/STUN Servers   |
                                                         | (for WebRTC)        |
                                                         +---------------------+

```

## Prerequisites

*   [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/)
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable version)
*   [Lefthook](https://github.com/evilmartians/lefthook) for Git hooks management

## Getting Started

1.  **Clone the repository:**

    ```bash
    git clone [https://github.com/your-user/famichat.git](https://github.com/your-user/famichat.git)  # Replace with your repo URL
    cd famichat
    ```

2.  **Set up Lefthook for Git hooks:**

    ```bash
    # Install Lefthook globally (if not already installed)
    npm install -g lefthook

    # Initialize Lefthook in the repository
    lefthook install
    ```

3.  **Start the Docker containers:**

    ```bash
    docker-compose up --build
    ```

    This command will:
    *   Build and launch a PostgreSQL database container on port `5432`.
    *   Build and launch the Phoenix backend container, accessible on port `4000`.

4.  **Verify the Backend:**

    Open your web browser and navigate to [http://localhost:4000](http://localhost:4000). You should see the default Phoenix "Welcome to Phoenix!" page or a "Hello from Famichat!" message if you've customized the root route.

5.  **Set up Flutter Web Development (if needed):**

    If you want to run the Flutter web client, ensure web support is enabled in your Flutter installation:

    ```bash
    flutter config --enable-web
    flutter devices # Verify 'Chrome' or 'Web Server' is listed
    ```

6.  **Run the Flutter App:**

    Navigate to the Flutter project directory:

    ```bash
    cd flutter/famichat
    ```

    Get Flutter dependencies:

    ```bash
    flutter pub get
    ```

    **Run in a web browser (for development):**

    ```bash
    flutter run -d chrome
    ```

    This will launch the Flutter web app in your default Chrome browser, connecting to the Phoenix backend running in Docker.

    **Run on a mobile device or emulator:**

    Ensure you have a connected device or emulator configured for Flutter development. Then run:

    ```bash
    flutter run
    ```

    Flutter will attempt to build and run the app on your connected device/emulator.

## Development

### Git Hooks with Lefthook

Famichat uses [Lefthook](https://github.com/evilmartians/lefthook) to manage Git hooks, which automate checks and tasks before commits and pushes. This helps maintain code quality and prevent issues from being committed or pushed.

*   **Pre-commit Hook:** Runs automatically before each commit and:
    *   Starts Docker containers
    *   Waits for the web service to be available
    *   Formats Elixir and JavaScript files that are staged for commit

*   **Pre-push Hook:** Runs automatically before each push and:
    *   Runs a series of checks including format verification, linting, and tests
    *   Provides feedback if any checks fail, but allows the push to proceed

*   **Installation:**
    *   Global: `npm install -g lefthook`
    *   Local (alternative): Add to package.json and install with npm/yarn
    *   After installation: `lefthook install` to initialize the Git hooks

*   **Configuration:** The hooks are configured in `.lefthook.yml` files in the root and backend directories.

### Backend (Phoenix/Elixir)

*   **Directory:** `backend/`
*   **Running Tests:** `cd backend && ./run mix test`
*   **Running IEx Console:** `cd backend && ./run iex -S mix`
*   **Code Formatting:** `cd backend && ./run mix format`
*   **Code Analysis (Credo):** `cd backend && ./run mix credo`
*   **Running Migrations:** `cd backend && ./run mix ecto.migrate`
*   **Rollback Migrations:** `cd backend && ./run mix ecto.rollback`

### Frontend (Flutter)

*   **Directory:** `flutter/famichat/`
*   **Get Dependencies:** `flutter pub get`
*   **Run in Web Browser (Chrome):** `flutter run -d chrome`
*   **Run on Device/Emulator:** `flutter run`
*   **Run Tests:** `flutter test`
*   **Code Formatting:** Flutter uses automatic formatting. Configure your IDE to format on save.
