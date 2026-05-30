@echo off
title 键盘红绿灯 - 久坐提醒
echo 正在启动键盘红绿灯...
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0traffic_light.ps1"
