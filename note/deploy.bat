@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM 在 web-agent 项目根目录双击运行，或从终端执行 deploy.bat
REM 功能：自动递增版本号 -> 打包 -> SCP 上传

set REMOTE_USER=alice
set REMOTE_HOST=154.8.213.134
set REMOTE_DIR=/opt/qq-bot/updates
set UPDATE_URL=http://154.8.213.134:8080/updates

cd /d "%~dp0.."

echo 工作目录: %cd%
echo.

REM ======== 1. 递增版本号 ========
echo ==> [1/5] 自动递增版本号（patch +1）

for /f "delims=" %%i in ('node -e "console.log(require('./package.json').version)" 2^>^&1') do set CUR_VERSION=%%i
if "%CUR_VERSION%"=="" (echo ❌ 读取版本号失败 & pause & exit /b 1)
echo     当前版本: %CUR_VERSION%

for /f "delims=" %%i in ('node -e "const v='%CUR_VERSION%'.split('.');v[2]=String(Number(v[2])+1);console.log(v.join('.'))" 2^>^&1') do set NEXT_VERSION=%%i
if "%NEXT_VERSION%"=="" (echo ❌ 计算下一版本号失败 & pause & exit /b 1)
echo     目标版本: %CUR_VERSION% -^> %NEXT_VERSION%

node -e "const pkg=require('./package.json');pkg.version='%NEXT_VERSION%';pkg.build=pkg.build||{};pkg.build.publish=pkg.build.publish||{};pkg.build.publish.provider='generic';pkg.build.publish.url='%UPDATE_URL%';require('fs').writeFileSync('./package.json',JSON.stringify(pkg,null,2)+'\n')" 2>&1
if %errorlevel% neq 0 (echo ❌ 写入 package.json 失败 & pause & exit /b 1)
echo     package.json 已更新
echo.

REM ======== 2. 同步 main.js ========
echo ==> [2/5] 同步 main.js 更新地址

node -e "const fs=require('fs');let m=fs.readFileSync('./main.js','utf8');m=m.replace(/const UPDATE_FEED_URL = '.*'/,\"const UPDATE_FEED_URL = '%UPDATE_URL%'\");fs.writeFileSync('./main.js',m)" 2>&1
if %errorlevel% neq 0 (echo ❌ 同步 main.js 失败 & pause & exit /b 1)
echo.

REM ======== 3. 打包 ========
echo ==> [3/5] electron-builder 打包（请耐心等待）

call npm run dist
if %errorlevel% neq 0 (echo ❌ 打包失败 & pause & exit /b 1)
echo.

REM ======== 4. 确保远程目录存在 ========
echo ==> [4/5] 确保远程目录存在

ssh -o StrictHostKeyChecking=no %REMOTE_USER%@%REMOTE_HOST% "mkdir -p %REMOTE_DIR%"
if %errorlevel% neq 0 (echo ❌ SSH 连接失败，请检查网络 & pause & exit /b 1)
echo.

REM ======== 5. 上传 ========
echo ==> [5/5] 上传更新文件

cd release
if not exist latest.yml (echo ❌ 未找到 latest.yml & pause & exit /b 1)
echo     上传 latest.yml ...
scp -o StrictHostKeyChecking=no latest.yml %REMOTE_USER%@%REMOTE_HOST%:%REMOTE_DIR%/
if %errorlevel% neq 0 (echo ❌ 上传 latest.yml 失败 & pause & exit /b 1)

set EXE_FILE=AI小说创作台 Setup %NEXT_VERSION%.exe
if not exist "%EXE_FILE%" (echo ❌ 未找到 %EXE_FILE% & pause & exit /b 1)
echo     上传 %EXE_FILE% ...
scp -o StrictHostKeyChecking=no "%EXE_FILE%" %REMOTE_USER%@%REMOTE_HOST%:%REMOTE_DIR%/
if %errorlevel% neq 0 (echo ❌ 上传 %EXE_FILE% 失败 & pause & exit /b 1)

set BLOCKMAP_FILE=AI小说创作台 Setup %NEXT_VERSION%.exe.blockmap
if not exist "%BLOCKMAP_FILE%" (echo ❌ 未找到 %BLOCKMAP_FILE% & pause & exit /b 1)
echo     上传 %BLOCKMAP_FILE% ...
scp -o StrictHostKeyChecking=no "%BLOCKMAP_FILE%" %REMOTE_USER%@%REMOTE_HOST%:%REMOTE_DIR%/
if %errorlevel% neq 0 (echo ❌ 上传 %BLOCKMAP_FILE% 失败 & pause & exit /b 1)

echo.
echo ==============================================
echo   发布完成！
echo   版本: %NEXT_VERSION%
echo   更新地址: %UPDATE_URL%
echo   安装包: %REMOTE_USER%@%REMOTE_HOST%:%REMOTE_DIR%/%EXE_FILE%
echo ==============================================
echo.
echo   用户下次启动应用时将自动检测到此更新。
pause
