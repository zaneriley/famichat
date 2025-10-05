# Famichat
Secure, Self-Hosted Family Communication Platform

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Project Status: Alpha](https://img.shields.io/badge/Project%20Status-Alpha-orange)](https://en.wikipedia.org/wiki/Software_release_life_cycle#Alpha)


**A self-hosted, white-label video and chat application designed to create a secure and intimate digital space for families.**

## Overview

We're trying to build a private video and chat app meant for a single household. Our goal is that you can customize it and white-label (e.g. your design) to fit your family's needs. The goal is for a non-capitalist app that's a bit more Animal Crossing than social media – relaxed and more about connection than constant updates.

For now, this repo is mainly a playground to test out:

*   A basic backend in Elixir/Phoenix.
*   A Phoenix LiveView web UI (for dogfooding Layers 0-3).
```
+---------------------+      WebSocket/Phoenix Channels     +---------------------+
| Phoenix LiveView UI | <-----------------------------------> | Phoenix Backend     |
| (Web Browser)       |                                     +---------------------+
+---------------------+                                          |
      |                                                         | Controllers, Channels,
      | LiveView Hooks                                          | Services, Telemetry
      | WebSocket events                                        |
      v                                                         v
                                                         +---------------------+
                                                         | PostgreSQL Database |
                                                         +---------------------+
                                                                 ^
                                                                 | (Metadata, Text, Media Refs)
                                                                 |
                                                         +---------------------+
                                                         | Object Storage      |
                                                         | AWS S3, MinIO, etc. |
                                                         +---------------------+
                                                                 ^
                                                                 | (Rich Media - future)

```

## Prerequisites

*   [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/)
*   [Lefthook](https://github.com/evilmartians/lefthook) for Git hooks management

## Getting Started

1.  **Clone the repository:**

    ```bash
    git clone [https://github.com/your-user/famichat.git](https://github.com/your-user/famichat.git)  # Replace with your repo URL
    cd famichat
    ```

2.  **Set up Lefthook for Git hooks:**

    ```bash
    # Download the Lefthook binary for your platform
    # For Windows:
    curl -L -o ~/bin/lefthook.exe https://github.com/evilmartians/lefthook/releases/download/v1.11.2/lefthook_1.11.2_Windows_x86_64.exe
    # For macOS:
    # curl -L -o ~/bin/lefthook https://github.com/evilmartians/lefthook/releases/download/v1.11.2/lefthook_1.11.2_MacOS_x86_64
    # For Linux:
    # curl -L -o ~/bin/lefthook https://github.com/evilmartians/lefthook/releases/download/v1.11.2/lefthook_1.11.2_Linux_x86_64
    
    # Make it executable (not needed for Windows)
    # chmod +x ~/bin/lefthook
    
    # Ensure ~/bin is in your PATH
    # export PATH="$HOME/bin:$PATH"
    
    # Initialize Lefthook in the repository
    ~/bin/lefthook install
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

5.  **Access the LiveView UI:**

    Open your browser and navigate to [http://localhost:8001](http://localhost:8001) to view the Phoenix LiveView UI.

    **Note**: Native mobile app (Flutter/iOS/Android) deferred until Layer 4. Current focus is dogfooding with LiveView for Layers 0-3.

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
    *   Direct binary download (recommended):
        * Download the appropriate binary for your platform from [GitHub Releases](https://github.com/evilmartians/lefthook/releases)
        * Place it in a directory that's in your PATH (e.g., ~/bin)
        * Make it executable (chmod +x) on Unix-based systems
    *   After installation: Run `lefthook install` to initialize the Git hooks

*   **Configuration:** The hooks are configured in `.lefthook.yml` files in the root and backend directories.

### Backend (Phoenix/Elixir)

*   **Directory:** `backend/`
*   **Running Tests:** `cd backend && ./run mix test`
*   **Running IEx Console:** `cd backend && ./run iex -S mix`
*   **Code Formatting:** `cd backend && ./run mix format`
*   **Code Analysis (Credo):** `cd backend && ./run mix credo`
*   **Running Migrations:** `cd backend && ./run mix ecto.migrate`
*   **Rollback Migrations:** `cd backend && ./run mix ecto.rollback`

### Frontend (Phoenix LiveView)

*   **Directory:** `backend/lib/famichat_web/live/`
*   **Access UI:** Open [http://localhost:8001](http://localhost:8001) in your browser
*   **LiveView Documentation:** [Phoenix LiveView Guides](https://hexdocs.pm/phoenix_live_view/)
*   **Note:** Native mobile app (Flutter/iOS/Android) deferred until Layer 4. Current focus is LiveView for dogfooding.
