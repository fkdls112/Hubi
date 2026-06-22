#!/usr/bin/env bash
# 每次 xcodegen generate 后跑一次，确保 Hubi.xcscheme 引用 .storekit
set -e
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

xcodegen generate

SCHEME="Hubi.xcodeproj/xcshareddata/xcschemes/Hubi.xcscheme"
if [ -f "$SCHEME" ] && ! grep -q "StoreKitConfigurationFileReference" "$SCHEME"; then
    python3 - <<PY
path = "$SCHEME"
with open(path) as f: s = f.read()
insert = """      <StoreKitConfigurationFileReference
         identifier = "../../../Hubi/Resources/Configuration.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>"""
s = s.replace("</LaunchAction>", insert, 1)
with open(path, "w") as f: f.write(s)
print("✅ .storekit binding patched into scheme")
PY
fi
echo "Done."
