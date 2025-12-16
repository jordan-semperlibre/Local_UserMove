@echo off
wpeinit

:: optional: set bigger buffer for readability
mode con cols=120 lines=40

:: launch the menu
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File X:\Windows\System32\Menu\Menu.ps1

:: fall back to a shell if menu exits
cmd
