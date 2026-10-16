#!/bin/zsh
# 編譯並包成 ~/Applications/Haiyaa.app，並把辨識服務裝到 ~/Library/Application Support/VoiceType/server。
# 用固定的開發者憑證簽章，重新編譯後「輔助使用」「輸入監控」權限才不會被系統重置。
set -euo pipefail
cd "$(dirname "$0")"

# 簽章身分：可用 VOICETYPE_SIGN_IDENTITY 指定；沒指定就用這台電腦上第一張 Apple Development 憑證。
# 固定用同一張憑證簽，重新編譯後「輔助使用」「輸入監控」權限才不會被系統重置。
IDENTITY="${VOICETYPE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$IDENTITY" ]]; then
  echo "找不到 Apple Development 憑證，改用臨時簽章（每次重新編譯都要重開系統權限）" >&2
  IDENTITY="-"
fi
# 對外名稱是 Haiyaa；bundle id 和資料夾維持 voicetype，系統權限才不用重開
APP="$HOME/Applications/Haiyaa.app"

swift build -c release
mkdir -p "$APP/Contents/MacOS"
cp .build/release/VoiceType "$APP/Contents/MacOS/VoiceType"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 辨識服務裝到 Application Support：專案在「文件」資料夾裡，由 App 啟動的程式讀那裡會卡在系統的資料夾權限詢問
SERVER_DIR="$HOME/Library/Application Support/VoiceType/server"
mkdir -p "$SERVER_DIR"
cp ../server/server.py "$SERVER_DIR/server.py"
if [[ ! -x "$SERVER_DIR/.venv/bin/python" ]]; then
  /opt/homebrew/opt/python@3.12/bin/python3.12 -m venv --system-site-packages "$SERVER_DIR/.venv"
  "$SERVER_DIR/.venv/bin/pip" install -q opencc-python-reimplemented
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>tw.mixxin.voicetype</string>
  <key>CFBundleName</key><string>Haiyaa</string>
  <key>CFBundleDisplayName</key><string>Haiyaa</string>
  <key>CFBundleExecutable</key><string>VoiceType</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>VoiceTypeServerDir</key><string>$SERVER_DIR</string>
  <key>NSMicrophoneUsageDescription</key><string>Haiyaa 需要麥克風來聽你說話並轉成文字。</string>
</dict>
</plist>
PLIST
codesign --force --sign "$IDENTITY" "$APP"
echo "已安裝：$APP"
