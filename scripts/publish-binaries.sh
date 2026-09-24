#!/usr/bin/env bash
# 把私有源仓 MGO 的 Release 二进制搬运到公开门面仓 MGO-CLI。
#
# 用途：一次性回填存量版本（如 v0.9.2）。此后新版本由 MGO 的
# .github/workflows/release.yml 自动镜像，无需再跑本脚本。
#
# 两种模式：
#   1) 默认 —— 只下载 + 校验 sha256，产物留在工作目录并打印上传命令。
#      适合 MGO 尚未转私有、本机没有 API 凭据时先把包备好。
#   2) --upload —— 下载 + 校验 + 直接建 Release 并上传。
#      需要 gh CLI（已登录）或 GH_TOKEN；SSH key 不能调 REST API。
#
# 用法：
#   ./scripts/publish-binaries.sh v0.9.2                       # 下载+校验
#   ./scripts/publish-binaries.sh v0.9.2 --upload              # 有 gh 登录态
#   GH_TOKEN=github_pat_xxx ./scripts/publish-binaries.sh v0.9.2 --upload
#   KEEP=1 ./scripts/publish-binaries.sh v0.9.2                # 保留下载目录
set -euo pipefail

TAG="${1:?用法: $0 <tag> [--upload]}"
MODE="${2:-}"
SRC_REPO="${SRC_REPO:-Johnly1986/MGO}"
DST_REPO="${DST_REPO:-Johnly1986/MGO-CLI}"
API="https://api.github.com"
WORK="${WORK:-/tmp/mgo-mirror-$TAG}"
MANIFEST_URL="${MANIFEST_URL:-https://raw.githubusercontent.com/Johnly1986/MGOServer/main/package.json}"

rm -rf "$WORK"; mkdir -p "$WORK"

# ---------------------------------------------------------------- 解析资产清单
echo "==> 解析 $SRC_REPO 的 $TAG 资产清单"
AUTH_HDR=""
if [ -n "${GH_TOKEN:-}" ]; then AUTH_HDR="Authorization: Bearer $GH_TOKEN"; fi
python3 - "$API/repos/$SRC_REPO/releases/tags/$TAG" "$AUTH_HDR" >"$WORK/assets.tsv" <<'PY'
import json, sys, urllib.request
url, auth = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
if auth: req.add_header(*auth.split(" ", 1))
d = json.load(urllib.request.urlopen(req))
if not d.get("assets"):
    sys.exit(f"release {url} has no assets")
for a in d["assets"]:
    print("\t".join([a["name"], str(a["size"]), a.get("digest") or "", a["browser_download_url"]]))
PY
awk -F'\t' '{printf "  %-34s %12s bytes\n", $1, $2}' "$WORK/assets.tsv"

# ---------------------------------------------------------------- 下载
echo "==> 下载到 $WORK"
while IFS=$'\t' read -r name size digest url; do
  f="$WORK/$name"
  for i in 1 2 3 4 5; do
    curl -fL -C - --retry 4 --retry-delay 3 -o "$f" "$url" >/dev/null 2>&1 && break
    sleep 5
  done
  got=$(stat -c%s "$f" 2>/dev/null || echo 0)
  [ "$got" = "$size" ] || { echo "!! $name 大小不符: got=$got want=$size"; exit 1; }
  echo "  ok $name"
done < "$WORK/assets.tsv"

# ---------------------------------------------------------------- 完整性校验
# 与 MGOServer/package.json 的 mgoEngine.downloads[*].sha256 比对，
# 确保公开仓的字节与安装器预期一致（防止搬错版本 / 搬半截）。
echo "==> 校验 sha256（对齐 MGOServer manifest）"
python3 - "$WORK" "$MANIFEST_URL" <<'PY'
import hashlib, json, os, sys, urllib.request
work, murl = sys.argv[1], sys.argv[2]
m = json.load(urllib.request.urlopen(murl))["mgoEngine"]["downloads"]
lines = []
for fname in sorted(os.listdir(work)):
    p = os.path.join(work, fname)
    if not os.path.isfile(p) or fname in ("assets.tsv", "SHA256SUMS"): continue
    lines.append(f"{hashlib.sha256(open(p,'rb').read()).hexdigest()}  {fname}")
open(os.path.join(work, "SHA256SUMS"), "w").write("\n".join(lines) + "\n")
by_name = {l.split("  ", 1)[1]: l.split(" ", 1)[0] for l in lines}
ok = True
for key, spec in m.items():
    name = spec["url"].rsplit("/", 1)[-1]
    got = by_name.get(name)
    if got is None:
        print(f"  (skip) {key}: {name} 不在本次产物中"); continue
    match = (got == spec.get("sha256")); ok &= match
    print(f"  {'OK      ' if match else 'MISMATCH'} {key}: {got}")
sys.exit(0 if ok else 1)
PY

NOTES_FILE="$WORK/NOTES.md"
cat > "$NOTES_FILE" <<EOF
MGO CLI \`$TAG\` — 预编译二进制包（Linux x64 / Windows x64），自包含、解压即用。

本仓库仅发布构建产物，不含源码。第三方依赖许可见附件 \`THIRD_PARTY_LICENSES.txt\`。

问题反馈：https://github.com/Johnly1986/MGOServer/issues
EOF

if [ "$MODE" != "--upload" ]; then
  cat <<EOF

==> 已就绪（未上传）。$WORK：
$(sed 's|^|    |' "$WORK/SHA256SUMS")
    （NOTES.md 为 Release 正文草稿）

下一步二选一：
  A) 已装 gh 并登录：  gh release create $TAG $WORK/MGO-* $WORK/THIRD_PARTY_LICENSES.txt \\
                         -R $DST_REPO --title "$TAG" --notes-file $WORK/NOTES.md
  B) 只有 Fine-grained PAT：
       GH_TOKEN=<pat> WORK=$WORK KEEP=1 $0 $TAG --upload
     （设 KEEP=1 复用已下载的包，跳过重复下载需配合 WORK 指向同一目录）
EOF
  exit 0
fi

# ---------------------------------------------------------------- 发布
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  PRERELEASE=(); case "$TAG" in *-*) PRERELEASE=(--prerelease);; esac
  if gh release view "$TAG" -R "$DST_REPO" >/dev/null 2>&1; then
    echo "==> $DST_REPO 已存在 $TAG，追加/覆盖资产"
    gh release upload "$TAG" "$WORK"/MGO-* "$WORK"/THIRD_PARTY_LICENSES.txt -R "$DST_REPO" --clobber
  else
    echo "==> 在 $DST_REPO 创建 Release $TAG"
    gh release create "$TAG" "$WORK"/MGO-* "$WORK"/THIRD_PARTY_LICENSES.txt \
      -R "$DST_REPO" --title "$TAG" --notes-file "$NOTES_FILE" "${PRERELEASE[@]}"
  fi
else
  [ -n "${GH_TOKEN:-}" ] || { echo "!! 无 gh 登录态时必须提供 GH_TOKEN（Fine-grained PAT，对 $DST_REPO 有 Contents: Read and write）"; exit 1; }
  command -v node >/dev/null || { echo "!! 无 gh 也无 node"; exit 1; }
  echo "==> 通过 REST API 在 $DST_REPO 发布 $TAG"
  GH_TOKEN="$GH_TOKEN" DST_REPO="$DST_REPO" TAG="$TAG" WORK="$WORK" NOTES_FILE="$NOTES_FILE" node <<'JS'
const fs = require('fs'), path = require('path');
const { DST_REPO: repo, TAG: tag, WORK: work, NOTES_FILE: notesFile } = process.env;
const H = { Authorization: `Bearer ${process.env.GH_TOKEN}`, Accept: 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28' };
const files = fs.readdirSync(work).filter(f => /^(MGO-.*\.(tar\.gz|zip)|THIRD_PARTY_LICENSES\.txt)$/.test(f));
(async () => {
  let r = await fetch(`https://api.github.com/repos/${repo}/releases`, {
    method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ tag_name: tag, name: tag, body: fs.readFileSync(notesFile, 'utf8'),
                           prerelease: /-/.test(tag), draft: false }) });
  if (r.status === 422) { console.log('  release 已存在，复用'); r = await fetch(`https://api.github.com/repos/${repo}/releases/tags/${tag}`, { headers: H }); }
  if (!r.ok) throw new Error(`create release failed ${r.status}: ${await r.text()}`);
  const rel = await r.json();
  for (const f of files) {
    const data = fs.readFileSync(path.join(work, f));
    const ar = await fetch(`https://uploads.github.com/repos/${repo}/releases/${rel.id}/assets?name=${encodeURIComponent(f)}`,
      { method: 'POST', headers: { ...H, 'Content-Type': 'application/octet-stream' }, body: data });
    if (!ar.ok) throw new Error(`upload ${f} failed ${ar.status}: ${await ar.text()}`);
    console.log(`  uploaded ${f} (${data.length} bytes)`);
  }
  console.log(`==> ${rel.html_url}`);
})().catch(e => { console.error(e.message); process.exit(1); });
JS
fi

[ "${KEEP:-0}" = "1" ] || rm -rf "$WORK"
echo "==> 完成。确认 $DST_REPO 可见性为 public 后外部才能匿名下载。"
