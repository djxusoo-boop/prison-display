@echo off
setlocal
title PRISON DISPLAY - Comprobacion de Windows
echo Esta comprobacion solo lee Windows, grafica y red local.
echo No instala aplicaciones ni cambia ajustes.
powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; $os=Get-CimInstance Win32_OperatingSystem; $gpu=Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion; $net=@(Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway} | ForEach-Object {[ordered]@{Adaptador=$_.InterfaceAlias;IPv4=@($_.IPv4Address | ForEach-Object {$_.IPAddress})}}); $ssh=Get-Service sshd -ErrorAction SilentlyContinue; $report=[ordered]@{Aplicacion='PRISON DISPLAY - diagnostico de solo lectura';Version='0.1.0-dev';Windows=$os.Caption;VersionWindows=$os.Version;Build=$os.BuildNumber;Arquitectura=$os.OSArchitecture;Equipo=[Environment]::MachineName;Graficas=@($gpu);Red=$net;SSH=if($ssh){[string]$ssh.Status}else{'No instalado'}}; $out=Join-Path ([Environment]::GetFolderPath('Desktop')) 'PRISON-DISPLAY-DIAGNOSTICO.txt'; [IO.File]::WriteAllText($out,($report | ConvertTo-Json -Depth 6),[Text.Encoding]::UTF8); Write-Host 'Informe guardado en el Escritorio: PRISON-DISPLAY-DIAGNOSTICO.txt'; Write-Host 'No se ha instalado ni activado ningun servicio.'"
if errorlevel 1 echo No se pudo completar. Copia el error para revisarlo.
pause
