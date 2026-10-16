# Haiyaa

自己做的 macOS 語音輸入工具，概念跟 Typeless 一樣：點一下左 Option 開始說話，再點一下，文字就自動潤飾好、貼到游標位置。辨識在本機跑，潤飾透過 Claude。

## 用法

| 操作 | 效果 |
|---|---|
| 點一下左 Option | 開始錄音（免持），再點一下送出 |
| 按住左 Option 超過 1 秒 | 按住說話，放開送出 |
| 錄音中按 Esc | 取消 |

點 Dock 圖示或選單列的「開啟 Haiyaa…」，可以看紀錄、編輯個人詞庫、調整設定。

## 架構

```
client/  Swift Dock App：快捷鍵、錄音、讀畫面上下文（Accessibility）、貼字、主視窗與提示條
server/  Python 本機辨識服務（127.0.0.1:5577），由 App 自動啟動和管理
```

流程：Whisper large-v3-turbo（mlx-whisper）辨識 → 依畫面上下文和個人詞庫，用 `claude -p`（Sonnet）潤飾 → 貼上。
精準模式會再加跑 Breeze ASR 25，兩份辨識結果交給 LLM 挑選。

## 安裝

需求：Apple Silicon Mac、Xcode、Homebrew 的 Python 3.12、已登入的 Claude Code CLI。

1. 安裝辨識套件：`/opt/homebrew/opt/python@3.12/bin/python3.12 -m pip install mlx-whisper`
2. （精準模式才需要）把 Breeze ASR 25 轉成 MLX 格式，放到 `~/.cache/breeze-asr-25/mlx-q8`
3. 在 `client/` 執行 `./build.sh`：會編譯、簽章、安裝成 `~/Applications/Haiyaa.app`，並把辨識服務安裝到 `~/Library/Application Support/VoiceType/server/`
   - 會自動使用這台 Mac 上的 Apple Development 憑證（Xcode 登入 Apple ID 就會有）；也可以用環境變數 `VOICETYPE_SIGN_IDENTITY` 指定
4. 打開 Haiyaa，依提示開啟三個權限：麥克風、輸入監控、輔助使用

## 資料

都放在 `~/Library/Application Support/VoiceType/`：

- `history.db`：每一筆的原始辨識、潤飾結果、上下文和耗時
- `recordings/`：錄音檔
- `dictionary.txt`：個人詞庫。一行一個詞；也可以寫「正確寫法：誤聽1、誤聽2」，辨識結果出現誤聽就直接換掉
- `server.log`、`client.log`

## 備註

- 內部的 bundle id（`tw.mixxin.voicetype`）、資料夾和 Swift 型別名稱沿用舊名 VoiceType；改掉的話，系統權限要重新授權。
- 「Haiyaa」取自華人常見的感嘆詞「哎呀」，這是個人使用的工具。
