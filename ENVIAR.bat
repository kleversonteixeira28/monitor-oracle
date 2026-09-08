@echo off
setlocal
cd /d "%~dp0"

echo.
echo  ENVIAR PARA O GITHUB
echo  O servidor puxa esta mudanca em ate 5 minutos.
echo  ---------------------------------------------------------
echo.

git rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
  echo  Esta pasta ainda nao e um repositorio git.
  echo  Rode primeiro:  git init -b main
  echo.
  pause
  exit /b 1
)

git status --short
echo.

git diff --quiet
if errorlevel 1 goto TEMMUDANCA
git diff --cached --quiet
if errorlevel 1 goto TEMMUDANCA
git ls-files --others --exclude-standard >"%TEMP%\mo_novos.txt"
for %%A in ("%TEMP%\mo_novos.txt") do if %%~zA GTR 0 goto TEMMUDANCA
echo  Nada mudou. Nada a enviar.
echo.
pause
exit /b 0

:TEMMUDANCA
set "MSG="
set /p MSG=  Descreva a mudanca (enter usa um texto padrao):
if "%MSG%"=="" set "MSG=Ajuste na stack de monitoramento"

git add -A
if errorlevel 1 goto ERRO
git commit -m "%MSG%"
if errorlevel 1 goto ERRO
git push
if errorlevel 1 goto ERRO

echo.
echo  Enviado. O servidor se atualiza em ate 5 minutos.
echo  Para nao esperar:  ssh ubuntu@SEU-IP "sudo bash /opt/monitor/scripts/sincronizar.sh"
echo.
pause
exit /b 0

:ERRO
echo.
echo  Falhou. Leia a mensagem acima antes de tentar de novo.
echo.
pause
exit /b 1
