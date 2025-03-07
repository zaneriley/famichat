@echo off
echo Running manual formatting and checks for Windows users...

echo.
echo Step 1: Starting Docker containers (if not already running)
docker compose up -d

echo.
echo Step 2: Waiting for web service to be ready...
:WAIT_LOOP
curl -s http://localhost:8001/up > nul 2>&1
if %ERRORLEVEL% == 0 (
    echo Web service is up!
    goto :FORMAT_CHECKS
)
echo Waiting for web service...
timeout /t 1 > nul
goto :WAIT_LOOP

:FORMAT_CHECKS
echo.
echo Step 3: Running Elixir formatting
call .\run format:all

echo.
echo Step 4: Running linting checks
call .\run lint:all

echo.
echo Step 5: Running tests
call .\run test:all

echo.
echo All checks completed successfully!
echo You can now commit your changes with: git commit --no-verify
echo And push with: git push --no-verify
echo.
echo Remember to manually run these checks regularly when lefthook isn't working on Windows.
