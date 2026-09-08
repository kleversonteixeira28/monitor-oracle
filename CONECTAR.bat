@echo off
setlocal
cd /d "%~dp0"

if exist "servidor.txt" goto TEMIP

echo.
echo  Qual o IP publico do servidor na Oracle?
set "IPNOVO="
set /p IPNOVO=  IP:
if "%IPNOVO%"=="" exit /b 1
>servidor.txt echo %IPNOVO%

:TEMIP
set /p IP=<servidor.txt

echo.
echo  Conectando em %IP% ...
echo  Dentro do servidor, os comandos uteis sao:
echo    sudo bash /opt/monitor/scripts/raio-x.sh
echo    sudo bash /opt/monitor/scripts/senhas.sh
echo    sudo bash /opt/monitor/scripts/sincronizar.sh
echo.
echo  Para trocar o IP, apague o arquivo servidor.txt.
echo.

ssh ubuntu@%IP%
if errorlevel 1 goto FALHOU
exit /b 0

:FALHOU
echo.
echo  Nao conectou. Verifique:
echo   - o IP em servidor.txt esta certo?
echo   - a porta 22 esta liberada na Security List da VCN?
echo   - a chave em %USERPROFILE%\.ssh\id_ed25519 e a mesma que voce colou na Oracle?
echo.
pause
exit /b 1
