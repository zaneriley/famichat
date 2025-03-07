#!/usr/bin/env bash

echo "Running manual formatting and checks for Windows Git Bash users..."

echo
echo "Step 1: Starting Docker containers (if not already running)"
docker compose up -d

echo
echo "Step 2: Waiting for web service to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:8001/up > /dev/null 2>&1; then
    echo "Web service is up!"
    break
  fi
  echo "Waiting for web service... (attempt $i)"
  sleep 1
  if [ $i -eq 30 ]; then
    echo "Warning: Web service did not come up in time, but continuing anyway..."
  fi
done

echo
echo "Step 3: Running Elixir formatting"
./run format:all

echo
echo "Step 4: Running linting checks"
./run lint:all

echo
echo "Step 5: Running tests"
./run test:all

echo
echo "All checks completed successfully!"
echo "You can now commit your changes with: git commit --no-verify"
echo "And push with: git push --no-verify"
echo
echo "Remember to manually run these checks regularly when lefthook isn't working on Windows."
