#!/bin/zsh
# 啟動 Haiyaa。辨識服務由 App 自己管理（啟動、掛了重開、結束時一起關），這裡只是打開 App。
# 要重新編譯／更新辨識服務，跑 client/build.sh。
open "$HOME/Applications/Haiyaa.app"
