@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"

REM =========================
REM Configuration
REM =========================

REM 1) Command that generates JSON files
set "RUN_COMMAND=uv run scraper.py"

REM 2) Directory where JSON files are created.
REM Usually this is the folder where this .bat file and scraper.py are located.
set "SOURCE_JSON_DIR=%~dp0"

REM 3) Local path to cloned target repository
set "TARGET_REPO_DIR=A:\imdbscraper2"

REM 4) GitHub target repository and branch
set "GITHUB_REPO_URL=https://github.com/Druidblack/IMDB_Top_250.git"
set "GITHUB_REPO_BRANCH=main"

REM 5) GitHub credentials for push
set "GITHUB_USERNAME=Druidblack"
set "GITHUB_TOKEN=you_token"

REM 6) Git commit metadata
set "GIT_USER_NAME=IMDb Scraper Bot"
set "GIT_USER_EMAIL=imdb-scraper-bot@localhost"
set "GIT_COMMIT_MESSAGE=Update IMDb Top 250 JSON files"

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

REM =========================
REM Run your existing generator
REM =========================

echo.
echo Running generator...
echo %RUN_COMMAND%
echo.

call %RUN_COMMAND%
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
echo Copying JSON files from:
echo %SOURCE_JSON_DIR%
echo to:
echo %TARGET_REPO_DIR%
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
REM Commit and push to GitHub
REM =========================

echo.
echo Preparing git commit...
echo.

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

echo.
echo Pushing to GitHub...
echo.

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