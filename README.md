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

    First, check if Lefthook is already installed by running:
    ```bash
    lefthook version
    ```
    If it's not installed, please refer to the [official Lefthook documentation](https://github.com/evilmartians/lefthook/blob/master/docs/installation.md) for the latest installation instructions.

    Once Lefthook is installed, initialize it in the repository:
    ```bash
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

### Development with VS Code DevContainers

For a consistent and pre-configured development environment for the Elixir backend, this project supports VS Code DevContainers.

**Benefits:**

*   **Consistent Environment:** Ensures all developers use the same environment, tools, and dependencies, matching the Docker setup.
*   **Pre-configured Tools:** Comes with recommended VS Code extensions for Elixir development, linting, and Git.
*   **Simplified Setup:** Reduces the need for manual local setup of Elixir and related tooling.

**Getting Started:**

1.  **Install Prerequisite:**
    *   Ensure you have [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.
    *   Install the [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) in VS Code.

2.  **Open in DevContainer:**
    *   Clone this repository to your local machine.
    *   Open the cloned repository folder in VS Code.
    *   VS Code should automatically detect the `.devcontainer/devcontainer.json` configuration and show a notification asking if you want to "Reopen in Container". Click it.
    *   Alternatively, you can open the Command Palette (Ctrl+Shift+P or Cmd+Shift+P) and type/select "Remote-Containers: Reopen in Container".

3.  **Backend Development:**
    *   Once the DevContainer is built and started, VS Code will be connected to the `backend` service defined in `docker-compose.yml`.
    *   The workspace will be automatically set to `/workspace/backend`.
    *   You can use the integrated terminal in VS Code to run Elixir commands (e.g., `mix deps.get`, `mix ecto.setup`, `mix phx.server`).
    *   The Phoenix server port (4000) is forwarded, so you can access the running application from your local browser.

**Note on Frontend Development:**

This DevContainer setup is primarily focused on **backend (Elixir/Phoenix) development**. Flutter development for the client application can continue on your local machine as usual. A separate DevContainer configuration for Flutter could be a future enhancement.

### Git Hooks with Lefthook

Famichat uses [Lefthook](https://github.com/evilmartians/lefthook) to manage Git hooks, which automate checks and tasks before commits and pushes. This helps maintain code quality and prevent issues from being committed or pushed.

*   **Pre-commit Hook:** Runs automatically before each commit and:
    *   Starts Docker containers
    *   Waits for the web service to be available
    *   Formats Elixir and JavaScript files that are staged for commit

*   **Pre-push Hook:** Runs automatically before each push and:
    *   Runs a series of checks including format verification, linting, and tests
    *   Provides feedback if any checks fail, but allows the push to proceed (Note: this behavior will be updated as per current subtask).

*   **Installation:**
    *   Refer to the [official Lefthook documentation](https://github.com/evilmartians/lefthook/blob/master/docs/installation.md) for the most up-to-date installation methods.
    *   After installation, navigate to the project root and run `lefthook install` to initialize the Git hooks for this repository.

*   **Configuration:** The hooks are configured in `.lefthook.yml` files in the root and backend directories.

### Backend (Phoenix/Elixir)

*   **Directory:** `backend/`
    *   Most backend commands can be run using `./run <mix_task>` from the `backend/` directory or via npm/yarn scripts from the `backend/assets/` directory (e.g., `npm run be:migrate` or `yarn be:migrate`).
*   **Running Migrations:**
    *   `cd backend && ./run mix ecto.migrate`
    *   or `cd backend/assets && npm run be:migrate`
*   **Rollback Migrations:**
    *   `cd backend && ./run mix ecto.rollback`
    *   or `cd backend/assets && npm run be:rollback`
*   **Running Tests:**
    *   `cd backend && ./run mix test`
    *   or `cd backend/assets && npm run be:test`
*   **Running IEx Console:**
    *   `cd backend && ./run iex -S mix`
    *   or `cd backend/assets && npm run be:iex`
*   **Code Formatting (Elixir):**
    *   `cd backend && ./run mix format`
    *   or `cd backend/assets && npm run be:format`
*   **Code Analysis (Credo):**
    *   `cd backend && ./run mix credo`
    *   or `cd backend/assets && npm run be:credo`

### Frontend (Flutter)

*   **Directory:** `flutter/famichat/`
*   **Get Dependencies:** `flutter pub get`
*   **Run in Web Browser (Chrome):** `flutter run -d chrome`
*   **Run on Device/Emulator:** `flutter run`
*   **Run Tests:** `flutter test`
*   **Code Formatting:** Flutter uses automatic formatting. Configure your IDE to format on save.

## IDE Setup Recommendations

While Famichat can be developed using a variety of text editors and IDEs, we recommend the following for an optimal experience, especially for newcomers.

### General

*   **VS Code:** A highly popular choice for both Elixir (backend) and Flutter (frontend) development due to its extensive extension marketplace and features.
*   **Android Studio:** Primarily recommended for Flutter development if you prefer a more integrated Java/Kotlin-like environment or are focusing heavily on Android-specific aspects.

### VS Code

*   **Recommended Extensions:**
    *   **For Elixir (Backend):**
        *   `jakebecker.elixir-ls`: Provides Elixir language support, code completion, debugging, and Credo integration. (This is already included in the DevContainer setup).
    *   **For Flutter (Frontend):**
        *   `Dart-Code.flutter`: The official Flutter extension, providing comprehensive support for Flutter development, including debugging, hot reload, and device management.
    *   **General Development:**
        *   `EditorConfig.EditorConfig`: Helps maintain consistent coding styles across different editors.
        *   `eamodio.gitlens`: Enhances Git capabilities within VS Code.
        *   `ms-azuretools.vscode-docker`: Useful for managing Docker containers if not using the DevContainer exclusively.

*   **Formatting on Save:**
    *   **Elixir:** To enable automatic formatting on save for Elixir files using ElixirLS, add the following to your VS Code `settings.json` (User or Workspace settings):
        ```json
        "[elixir]": {
            "editor.defaultFormatter": "jakebecker.elixir-ls",
            "editor.formatOnSave": true
        }
        ```
    *   **Dart/Flutter:** The Flutter extension typically handles formatting well. Ensure `editor.formatOnSave` is enabled for Dart files:
        ```json
        "[dart]": {
            "editor.formatOnSave": true,
            "editor.defaultFormatter": "Dart-Code.flutter"
        }
        ```
        You can also trigger formatting manually via the command palette (`Format Document`).

*   **Linting:**
    *   **Elixir (Credo):**
        *   The `ElixirLS` extension usually integrates Credo findings, displaying them in the "Problems" panel of VS Code.
        *   For manual checks from the terminal:
            *   Navigate to `backend/assets/` and run `npm run be:credo` (or `yarn be:credo`).
            *   Alternatively, from `backend/`, run `./run mix credo`.
    *   **Flutter:**
        *   The Dart/Flutter extension integrates `flutter analyze` directly into the IDE, showing issues in the "Problems" panel.
        *   You can also run `flutter analyze` manually in the `flutter/famichat` directory.

### Android Studio (Primarily for Flutter)

*   **Plugin:** Install the **Flutter plugin** from the JetBrains plugin marketplace. This will also install the required Dart plugin.
*   **Features:** The Flutter plugin provides a rich, integrated development experience:
    *   Code completion, navigation, and refactoring.
    *   Integrated Flutter DevTools.
    *   Visual debugging tools.
    *   Device management and emulators.
*   **Official Documentation:** For detailed setup and usage instructions for Android Studio (and other editors like IntelliJ), refer to the [official Flutter editor setup page](https://docs.flutter.dev/tools/editors).

## Debugging

### Backend (Elixir/Phoenix)

*   **Using `IEx.pry`**:
    *   You can insert `require IEx; IEx.pry` into your Elixir code where you want to start a debugging session.
    *   Run the backend in an IEx session: `cd backend/assets && npm run be:iex` (or `yarn be:iex`).
    *   When the code execution reaches `IEx.pry`, the IEx session will become interactive, allowing you to inspect variables, execute code, and use `respawn/0` to re-enter the pry session after code changes, or `continue/0` to resume execution.
*   **Viewing Logs**:
    *   To view real-time logs from the backend container: `docker-compose logs -f backend`
*   **VS Code Debugger (with DevContainer)**:
    *   If you are using the VS Code DevContainer setup, the ElixirLS extension provides debugging capabilities.
    *   You can set breakpoints directly in VS Code and launch a debugging session. Refer to the [ElixirLS documentation](https://elixir-lsp.github.io/elixir-ls/debugging.html) for detailed setup and usage.

### Frontend (Flutter)

*   **Official Documentation**: The most comprehensive guide is the [official Flutter debugging documentation](https://docs.flutter.dev/testing/debugging).
*   **Flutter DevTools**: A suite of performance tools for Flutter. You can use it to inspect layouts, diagnose performance issues, and more. It can usually be launched from your IDE when a Flutter app is running or via the `flutter devtools` command.
*   **Flutter Inspector**: Available in IDEs like Android Studio/IntelliJ and VS Code, it helps visualize and explore the Flutter widget tree.

## Project Documentation

This `README.md` provides a general overview and setup instructions. For more detailed project information, including architecture decisions, sprint plans, specific technical guides, and team processes, please refer to the documents within the `project-docs/` directory.

Key documents include:

*   **[`project-docs/guide.md`](project-docs/guide.md):** The comprehensive project guide covering architecture, development workflows, and more. This is a good starting point for a deeper understanding of the project.
*   **[`project-docs/telemetry.md`](project-docs/telemetry.md):** Information about the project's telemetry and data collection (if any).
*   **[`project-docs/onboarding.md`](project-docs/onboarding.md):** Guide for new developers joining the project.

Please consult these documents for more in-depth information.
