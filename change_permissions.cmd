@echo off
for %%F in ("%CD%\*.pem") do (
    echo Changing permissions for: %%~nxF
    icacls "%%F" /inheritance:r /grant "%USERNAME%":F
)
