#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "启动 gcli2api（兼容补丁模式，不强制更新代码）..."

patch_sqlite_unixepoch() {
  python - <<'PY'
from pathlib import Path

path = Path('src/storage/sqlite_manager.py')
if not path.exists():
    raise SystemExit('未找到 src/storage/sqlite_manager.py，无法打 SQLite 兼容补丁')

text = path.read_text(encoding='utf-8')
original = text
replacement = "CAST(strftime('%s','now') AS INTEGER)"

# 兼容 SQLite < 3.38：unixepoch() 在 3.38.0 才加入。
# 使用 CAST(strftime('%s','now') AS INTEGER) 保持与 unixepoch() 接近的整数时间戳行为。
text = text.replace('unixepoch()', replacement)

if text != original:
    path.write_text(text, encoding='utf-8')
    print('已应用 SQLite unixepoch() 兼容补丁')
else:
    print('SQLite unixepoch() 兼容补丁已存在，无需重复修改')
PY
}

ensure_venv() {
  if [ ! -d ".venv" ]; then
    echo "未发现 .venv，正在创建虚拟环境..."
    if command -v python3.13 >/dev/null 2>&1; then
      python3.13 -m venv .venv
    elif command -v python3.12 >/dev/null 2>&1; then
      python3.12 -m venv .venv
    elif command -v python3 >/dev/null 2>&1; then
      python3 -m venv .venv
    else
      echo "错误：未找到 python3.13、python3.12 或 python3" >&2
      exit 1
    fi
  fi
}

install_dependencies() {
  # shellcheck disable=SC1091
  source .venv/bin/activate

  if ! python - <<'PY'
import importlib.util
required = ['fastapi', 'hypercorn', 'aiosqlite', 'jwt']
missing = [name for name in required if importlib.util.find_spec(name) is None]
raise SystemExit(1 if missing else 0)
PY
  then
    echo "依赖不完整，正在安装 requirements.txt..."
    python -m pip install -U pip setuptools wheel
    python -m pip install -r requirements.txt
  else
    echo "依赖检查通过"
  fi
}

show_sqlite_version() {
  python - <<'PY'
import sqlite3
print(f"Python SQLite 版本: {sqlite3.sqlite_version}")
try:
    print("unixepoch() 测试:", sqlite3.connect(':memory:').execute('select unixepoch()').fetchone())
except Exception as exc:
    print(f"unixepoch() 不可用，已依赖代码兼容补丁: {exc}")
PY
}

patch_sqlite_unixepoch
ensure_venv
install_dependencies
show_sqlite_version

echo "正在启动 web.py..."
exec python web.py
