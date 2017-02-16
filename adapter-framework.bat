@rem cls
@echo made by cunhuan and guojin
@echo made by cunhuan and guojin
@echo made by cunhuan and guojin
@echo made by cunhuan and guojin

set File=%~dp0
set ARM=%File%\arm
set ARM64=%File%\arm64
set FRAMEWORK=system/framework

adb remount
adb push %ARM% %FRAMEWORK% && adb push %ARM64% %FRAMEWORK%

@echo made by cunhuan and guojin
@echo made by cunhuan and guojin
@echo made by cunhuan and guojin
@echo made by cunhuan and guojin
pause