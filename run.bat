@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

REM =========================
REM Configuration
REM =========================

set "SOURCE_JSON_DIR=%~dp0"
set "TARGET_REPO_DIR=C:\IMDB_Top_250"

set "GITHUB_REPO_URL=https://github.com/Druidblack/IMDB_Top_250.git"
set "GITHUB_REPO_BRANCH=main"

set "GITHUB_USERNAME=Druidblack"
set "GITHUB_TOKEN=ghp_"

set "GIT_USER_NAME=IMDb Scraper Bot"
set "GIT_USER_EMAIL=imdb-scraper-bot@localhost"
set "GIT_COMMIT_MESSAGE=Update IMDb Top 250 JSON files"

set "UV_LOCAL_DIR=%~dp0tools\uv"
set "UV_EXE=%UV_LOCAL_DIR%\uv.exe"

REM =========================
REM Validation
REM =========================

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] git is not installed or not found in PATH.
    pause
    exit /b 1
)

if "%GITHUB_USERNAME%"=="YOUR_GITHUB_USERNAME" (
    echo [ERROR] Replace GITHUB_USERNAME in this .bat file.
    pause
    exit /b 1
)

if "%GITHUB_TOKEN%"=="YOUR_GITHUB_PAT" (
    echo [ERROR] Replace GITHUB_TOKEN in this .bat file.
    pause
    exit /b 1
)

if not exist "%TARGET_REPO_DIR%\.git" (
    echo [ERROR] TARGET_REPO_DIR is not a git repository:
    echo %TARGET_REPO_DIR%
    pause
    exit /b 1
)

if not exist "scraper.py" (
    echo [ERROR] scraper.py was not found in:
    echo %cd%
    pause
    exit /b 1
)

REM =========================
REM Resolve / install uv
REM =========================

where uv >nul 2>nul
if not errorlevel 1 (
    for /f "delims=" %%I in ('where uv') do (
        set "UV_EXE=%%I"
        goto :uv_found
    )
)

if exist "%UV_EXE%" goto :uv_found

echo.
echo uv not found in PATH. Installing local uv to:
echo %UV_LOCAL_DIR%
echo.

if not exist "%UV_LOCAL_DIR%" mkdir "%UV_LOCAL_DIR%"

powershell -ExecutionPolicy ByPass -Command ^
  "$env:UV_INSTALL_DIR='%UV_LOCAL_DIR%'; irm https://astral.sh/uv/install.ps1 | iex"

if errorlevel 1 (
    echo [ERROR] Failed to install uv.
    pause
    exit /b 1
)

if not exist "%UV_EXE%" (
    echo [ERROR] uv.exe was not found after installation:
    echo %UV_EXE%
    pause
    exit /b 1
)

:uv_found
echo.
echo Using uv:
echo %UV_EXE%
echo.

REM =========================
REM Install Playwright Chromium
REM =========================

"%UV_EXE%" tool run playwright install chromium
if errorlevel 1 (
    echo [ERROR] Failed to install Playwright Chromium.
    pause
    exit /b 1
)

REM =========================
REM Run generator
REM =========================

echo.
echo Running generator...
echo.

"%UV_EXE%" run scraper.py
set "RUN_EXITCODE=%ERRORLEVEL%"

if not "%RUN_EXITCODE%"=="0" (
    echo.
    echo [ERROR] Generator finished with code %RUN_EXITCODE%.
    pause
    exit /b %RUN_EXITCODE%
)

REM =========================
REM Copy JSON files to repo
REM =========================

echo.
echo Copying JSON files...
echo.

set "FOUND_JSON=0"
for %%F in ("%SOURCE_JSON_DIR%\*.json") do (
    if exist "%%~fF" (
        copy /Y "%%~fF" "%TARGET_REPO_DIR%\%%~nxF" >nul
        echo Copied: %%~nxF
        set "FOUND_JSON=1"
    )
)

if "!FOUND_JSON!"=="0" (
    echo [ERROR] No JSON files were found in:
    echo %SOURCE_JSON_DIR%
    pause
    exit /b 1
)

REM =========================
REM Commit and push
REM =========================

git -C "%TARGET_REPO_DIR%" config user.name "%GIT_USER_NAME%"
git -C "%TARGET_REPO_DIR%" config user.email "%GIT_USER_EMAIL%"
git -C "%TARGET_REPO_DIR%" remote set-url origin "%GITHUB_REPO_URL%" >nul 2>nul

git -C "%TARGET_REPO_DIR%" add *.json
if errorlevel 1 (
    echo [ERROR] Failed to add JSON files to git.
    pause
    exit /b 1
)

git -C "%TARGET_REPO_DIR%" diff --cached --quiet
if not errorlevel 1 (
    echo No JSON changes to commit.
    pause
    exit /b 0
)

git -C "%TARGET_REPO_DIR%" commit -m "%GIT_COMMIT_MESSAGE%"
if errorlevel 1 (
    echo [ERROR] Failed to create git commit.
    pause
    exit /b 1
)

set "AUTH_PUSH_URL=https://%GITHUB_USERNAME%:%GITHUB_TOKEN%@github.com/Druidblack/IMDB_Top_250.git"

git -C "%TARGET_REPO_DIR%" pull --rebase origin "%GITHUB_REPO_BRANCH%"
if errorlevel 1 (
    echo [ERROR] git pull --rebase failed.
    pause
    exit /b 1
)

git -C "%TARGET_REPO_DIR%" push "%AUTH_PUSH_URL%" "HEAD:%GITHUB_REPO_BRANCH%"
if errorlevel 1 (
    echo [ERROR] git push failed.
    pause
    exit /b 1
)

echo.
echo [OK] JSON files were pushed to GitHub successfully.
pause
exit /b 0
