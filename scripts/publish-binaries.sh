#!/usr/bin/env bash
# 把私有源仓 MGO 的 Release 二进制搬运到公开门面仓 MGO-CLI。
#
# 用途：一次性回填存量版本（如 v0.9.2）。此后新版本由 MGO 的
# .github/workflows/release.yml 自动镜像，无需再跑本脚本。
#
# 依赖：gh CLI（已 gh auth login，账号需同时能读 MGO、写 MGO-CLI）
#       curl + sha256sum（用于跨仓一致性校验）
#
# 用法：
#   ./scripts/publish-binaries.sh v0.9.2
#   DRY_RUN=1 ./scripts/publish-binaries.sh v0.9.2      # 只下载校验，不上传
#   EXPECT_SHA=0 ./scripts/publish-binaries.sh v0.9.2   # 强制比对 MGOServer manifest 的 sha256
set -euo pipefail

TAG="${1:?用法: $0 <tag>  例如 $0 v0.9.2}"
SRC_REPO="${SRC_REPO:-Johnly1986/MGO}"
DST_REPO="${DST_REPO:-Johnly1986/MGO-CLI}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 从 $SRC_REPO 下载 $TAG 的产物"
gh release download "$TAG" -R "$SRC_REPO" --dir "$WORK" --pattern '*'

echo "==> 待发布文件："
ls -la "$WORK"

# ---------------------------------------------------------------- 完整性校验
# 与 MGOServer/package.json 的 mgoEngine.downloads[*].sha256 比对，
# 确保公开仓的字节与安装器预期一致（防止搬错版本/搬半截）。
MANIFEST_URL="https://raw.githubusercontent.com/Johnly1986/MGOServer/main/package.json"
verify_against_manifest() {
  command -v python3 >/dev/null || { echo "::warning::无 python3，跳过 sha256 比对"; return 0; }
  curl -fsSL "$MANIFEST_URL" -o "$WORK/manifest.json" || { echo "::warning::拉取 manifest 失败，跳过比对"; return 0; }
  python3 - "$WORK" <<'PY'
import hashlib, json, os, sys
work = sys.argv[1]
m = json.load(open(os.path.join(work, 'manifest.json')))['mgoEngine']['downloads']
ok = True
for key, spec in m.items():
    name = spec['url'].rsplit('/', 1)[-1]
    path = os.path.join(work, name)
    if not os.path.exists(path):
        print(f'  (skip) {key}: {name} 不在本次下载中'); continue
    h = hashlib.sha256(open(path, 'rb').read()).hexdigest()
    exp = spec.get('sha256')
    if exp and exp != h:
        print(f'  MISMATCH {key}: got {h} expected {exp}'); ok = False
    else:
        print(f'  OK {key}: {h[:16]}…')
sys.exit(0 if ok else 1)
PY
}
if [ "${EXPECT_SHA:-1}" = "1" ]; then
  echo "==> 校验 sha256（对齐 MGOServer manifest）"
  verify_against_manifest
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "==> DRY_RUN=1，不上传。文件在 $WORK（退出即删）"
  exit 0
fi

# ---------------------------------------------------------------- 发布
NOTES=$(cat <<EOF
MGO CLI \`${TAG}\` — 预编译二进制包（Linux x64 / Windows x64），自包含、解压即用。

本仓库仅发布构建产物，不含源码。第三方依赖许可见附件 \`THIRD_PARTY_LICENSES.txt\`。

问题反馈：https://github.com/Johnly1986/MGOServer/issues
EOF
)

PRERELEASE=()
case "$TAG" in *-*) PRERELEASE=(--prerelease);; esac

if gh release view "$TAG" -R "$DST_REPO" >/dev/null 2>&1; then
  echo "==> $DST_REPO 已存在 $TAG，追加上传缺失资产"
  gh release upload "$TAG" "$WORK"/* -R "$DST_REPO" --clobber
else
  echo "==> 在 $DST_REPO 创建 Release $TAG"
  gh release create "$TAG" "$WORK"/* -R "$DST_REPO" \
    --title "$TAG" --notes "$NOTES" "${PRERELEASE[@]}"
fi

echo "==> 完成：https://github.com/$DST_REPO/releases/tag/$TAG"
echo "提示：确认目标仓可见性为 public 后，外部才能匿名下载。"
