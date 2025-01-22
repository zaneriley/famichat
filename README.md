# Famichat

This repository contains a minimal Docker setup for an Elixir/Phoenix backend
and a Flutter app to validate end-to-end functionality.

## Prerequisites

- Docker / Docker Compose
- Flutter SDK (latest)


## Getting Started

1. **Clone the repo**:
   ```bash
   git clone https://github.com/your-user/famichat.git
   cd famichat
   ```

2. **Run containers**:

   Install [Flutter](https://docs.flutter.dev/get-started/install) and [Docker](https://docs.docker.com/get-docker/) if you haven't already.

   ```bash
   docker-compose up --build
   ```
   This will:
   - Launch PostgreSQL on port `5432`.
   - Launch Phoenix on port `4000`.

3. **Test Backend**:
   Open your browser at [http://localhost:4000](http://localhost:4000).
   You should see a "Hello from Famichat!" message.

4. **Set Up Flutter Web Development**:
   
   Flutter web support needs to be explicitly enabled. Here's how to set it up:

   ```bash
   # Enable web support in Flutter
   flutter config --enable-web
   
   # Verify web device is available
   flutter devices
   ```
   
   You should see 'Chrome' or 'Web Server' in the device list.

5. **Run the Flutter App**:

   You can run the app either in a web browser or on a mobile device/emulator.

   ### Web Browser (Recommended for Quick Testing)
   ```bash
   # Navigate to the Flutter project
   cd flutter/famichat
   
   # Get dependencies
   flutter pub get
   
   # Run the app in Chrome
   flutter run -d chrome
   ```
   
   The app should open automatically in your default Chrome browser.
   
   ### Mobile Device/Emulator (Alternative)
   ```bash
   cd flutter/famichat
   flutter pub get
   flutter run
   ```

## Troubleshooting

### Web-Specific Issues

1. **CORS Errors**
   
   If you see network errors in the browser console, you may need to enable CORS in the Phoenix backend:

   ```elixir
   # In mix.exs, add:
   {:cors_plug, "~> 3.0"}
   
   # In endpoint.ex, add:
   plug CORSPlug, origin: ["http://localhost:3000"]
   ```

2. **SDK Version Issues**
   
   If you see SDK constraint errors, ensure your `pubspec.yaml` has the correct SDK version:

   ```yaml
   environment:
     sdk: '>=3.6.0 <4.0.0'
   ```

3. **Web Server Port Conflicts**
   
   If port 3000 is already in use:
   ```bash
   flutter run -d chrome --web-port=3001
   ```

### General Flutter Issues

1. **Missing Dependencies**
   ```bash
   flutter doctor
   ```
   Follow the recommendations to install any missing components.

2. **Network Connection**
   
   When testing locally:
   - Web app should use `localhost:4000` to connect to Phoenix
   - Mobile devices should use your machine's local IP (e.g., `192.168.1.100:4000`)
   - Android emulator should use `10.0.2.2:4000`

## Development Notes

- The web version runs in a browser sandbox, which may affect some features like file system access or bluetooth connectivity
- For production, you'll want to configure proper CORS settings and secure the communication between Flutter and Phoenix
- Web performance may differ from native mobile performance

You can adapt these steps for production or more advanced setups.
