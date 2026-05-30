@echo off
powershell -WindowStyle Hidden -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File', '%~dp0traffic_light.ps1' -WindowStyle Hidden"
