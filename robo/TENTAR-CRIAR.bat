@echo off
setlocal
cd /d "%~dp0"

echo.
echo  ROBO DE TENTATIVA - instancia ARM na Oracle
echo  Fica pedindo ate a Oracle ter capacidade. Pode demorar horas ou dias.
echo  Deixe esta janela aberta e o PC ligado. Ctrl+C para parar.
echo.

where oci >nul 2>&1
if errorlevel 1 goto SEMOCI

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Robo-Tentativa.ps1" %*
set CODIGO=%ERRORLEVEL%

echo.
if "%CODIGO%"=="0" goto FIM
echo  O robo parou. Leia a mensagem acima antes de rodar de novo.
echo.

:FIM
pause
exit /b %CODIGO%

:SEMOCI
echo  O OCI CLI nao esta instalado.
echo.
echo  1) Abra o PowerShell e rode a linha de instalacao que esta no
echo     README-ROBO.md (secao "Instalar o OCI CLI").
echo  2) Feche e reabra o PowerShell.
echo  3) Rode:  oci setup config
echo  4) Volte aqui.
echo.
pause
exit /b 1
