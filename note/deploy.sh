#!/usr/bin/env bash
# 在 web-agent 项目根目录执行：
#   chmod +x note/deploy.sh && bash note/deploy.sh
#
# Windows：可用 Git Bash
#
# 功能：
#   1. 自动递增 package.json 的 patch 版本号
#   2. npm run dist 打包
#   3. SCP 上传更新文件到服务器
#   4. 同步更新 main.js 中的 UPDATE_FEED_URL
#
# 安全：脚本含服务器密钥路径，请勿 push 到公开仓库。
set -uo pipefail

die() { echo "❌ 错误: $*" >&2; exit 1; }

# ======== 配置区 ========
REMOTE_USER="alice"
REMOTE_HOST="154.8.213.134"
REMOTE_DIR="/opt/qq-bot/updates"
UPDATE_URL="http://154.8.213.134:8080/updates"

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
SCP_OPTS="${SCP_OPTS:--o StrictHostKeyChecking=no}"
if [[ -f "${SSH_KEY}" ]]; then
  SCP_OPTS="${SCP_OPTS} -i ${SSH_KEY}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || die "无法定位脚本目录"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)" || die "无法定位项目根目录"
cd "${ROOT_DIR}" || die "无法进入项目根目录: ${ROOT_DIR}"

echo "工作目录: ${ROOT_DIR}"

# ======== 1. 递增版本号 ========
echo "==> [1/5] 自动递增版本号（patch +1）"

[[ -f ./package.json ]] || die "未找到 package.json，请在项目根目录执行本脚本"

CUR_VERSION="$(node -e "console.log(require('./package.json').version)" 2>&1)" || die "读取当前版本号失败: ${CUR_VERSION}"
echo "    当前版本: ${CUR_VERSION}"

NEXT_VERSION="$(node -e "
const v = '${CUR_VERSION}'.split('.');
if (v.length < 3) throw new Error('版本号格式需为 x.y.z，当前: ${CUR_VERSION}');
v[2] = String(Number(v[2]) + 1);
if (isNaN(Number(v[2]))) throw new Error('版本号 patch 位非数字: ${CUR_VERSION}');
console.log(v.join('.'));
" 2>&1)" || die "计算下一版本号失败: ${NEXT_VERSION}"

echo "    目标版本: ${CUR_VERSION} -> ${NEXT_VERSION}"

node -e "
const pkg = require('./package.json');
pkg.version = '${NEXT_VERSION}';
pkg.build = pkg.build || {};
pkg.build.publish = pkg.build.publish || {};
pkg.build.publish.provider = 'generic';
pkg.build.publish.url = '${UPDATE_URL}';
require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');
" 2>&1 || die "写入 package.json 失败"

echo "    package.json 已更新"

# ======== 2. 同步 main.js 中的 UPDATE_FEED_URL ========
echo "==> [2/5] 同步 main.js 更新地址"

node -e "
const fs = require('fs');
let main = fs.readFileSync('./main.js', 'utf8');
const old = main.match(/const UPDATE_FEED_URL = '.*'/);
if (!old) throw new Error('未找到 UPDATE_FEED_URL 声明');
main = main.replace(/const UPDATE_FEED_URL = '.*'/, \"const UPDATE_FEED_URL = '${UPDATE_URL}'\");
fs.writeFileSync('./main.js', main);
console.log('已替换: ' + old[0]);
" 2>&1 || die "同步 main.js 失败"

# ======== 3. 打包 ========
echo "==> [3/5] electron-builder 打包（请耐心等待）"

npm run dist || die "electron-builder 打包失败"

[[ -d ./release ]] || die "release 目录不存在，打包可能未完成"

# ======== 4. 确保远程目录存在 ========
echo "==> [4/5] 确保远程目录存在"

ssh ${SCP_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_DIR}" || die "SSH 连接失败，请检查网络和密钥"

# ======== 5. 上传 ========
echo "==> [5/5] 上传更新文件"
cd "${ROOT_DIR}/release" || die "无法进入 release 目录"

[[ -f latest.yml ]] || die "未找到 latest.yml"
echo "    上传 latest.yml ..."
scp ${SCP_OPTS} latest.yml "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" || die "上传 latest.yml 失败"

EXE_FILE="AI小说创作台 Setup ${NEXT_VERSION}.exe"
[[ -f "${EXE_FILE}" ]] || die "未找到 ${EXE_FILE}"
echo "    上传 ${EXE_FILE} ..."
scp ${SCP_OPTS} "${EXE_FILE}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" || die "上传 ${EXE_FILE} 失败"

BLOCKMAP_FILE="AI小说创作台 Setup ${NEXT_VERSION}.exe.blockmap"
[[ -f "${BLOCKMAP_FILE}" ]] || die "未找到 ${BLOCKMAP_FILE}"
echo "    上传 ${BLOCKMAP_FILE} ..."
scp ${SCP_OPTS} "${BLOCKMAP_FILE}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" || die "上传 ${BLOCKMAP_FILE} 失败"

echo ""
echo "=============================================="
echo "  发布完成！"
echo "  版本: ${NEXT_VERSION}"
echo "  更新地址: ${UPDATE_URL}"
echo "  安装包: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${EXE_FILE}"
echo "=============================================="
echo ""
echo "  用户下次启动应用时将自动检测到此更新。"
