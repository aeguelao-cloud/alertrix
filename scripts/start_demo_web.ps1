$ErrorActionPreference = "SilentlyContinue"
$project = "F:\403\demo"
$flutter = "D:\flutter\bin\flutter.bat"
$port = 18093

# stop old listener on the same port
Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }

$out = "F:\403\demo\tmp_logs\demo_webserver.out.log"
$err = "F:\403\demo\tmp_logs\demo_webserver.err.log"
New-Item -ItemType Directory -Force -Path "F:\403\demo\tmp_logs" | Out-Null
Remove-Item $out,$err -Force -ErrorAction SilentlyContinue

Start-Process -FilePath $flutter -ArgumentList "run -d web-server --web-port $port --web-hostname 127.0.0.1" -WorkingDirectory $project -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden

Start-Sleep -Seconds 8
Start-Process "http://127.0.0.1:$port"
