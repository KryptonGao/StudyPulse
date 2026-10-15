#!/bin/bash
# 字体规范检查:禁止 `.font(.system(size:))`(不随 Dynamic Type 缩放)。
# 请用 DesignToken.Font / 系统 text style / `.scaledFont(size:)`。
# 确需固定字号(如几何驱动的计时器数字)时,在该行末尾加 `// fixed-size-ok: <原因>`。
# Font policy check: raw `.font(.system(size:))` doesn't scale with Dynamic Type.
# Use DesignToken.Font / text styles / `.scaledFont(size:)`; annotate genuine exceptions with `// fixed-size-ok: <reason>`.
cd "$(dirname "$0")/.." || exit 1
hits=$(grep -rn --include='*.swift' 'system(size:' StudyPulse \
  | grep -v 'Extensions/ScaledFont.swift' \
  | grep -v 'fixed-size-ok')
if [ -n "$hits" ]; then
  echo "❌ 发现不随 Dynamic Type 缩放的固定字号 / Fixed-size fonts found:"
  echo "$hits"
  exit 1
fi
echo "✅ Font policy OK"
