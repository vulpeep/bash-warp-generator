# Очистка экрана
Clear-Host

# Переменная для отслеживания ошибок
$ErrorOccurred = $false

try {
    # Сохраняем wg.exe во временную директорию
    $wgTempPath = "$env:TEMP\wg.exe"
    if (-not (Test-Path $wgTempPath)) {
        Write-Host "wg.exe не найден. Автоматическая загрузка и извлечение wg.exe..."

        # URL для загрузки MSI-установщика WireGuard
        $msiUrl = "https://download.wireguard.com/windows-client/wireguard-x86-0.5.3.msi"

        # Путь для сохранения MSI-установщика
        $msiPath = "$env:TEMP\wireguard-installer.msi"

        # Скачиваем MSI-установщик
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

        # Проверяем, что MSI-установщик был успешно загружен
        if (-not (Test-Path $msiPath)) {
            throw "Не удалось загрузить MSI-установщик WireGuard."
        }

        # Используем Windows Installer COM Object для извлечения wg.exe из MSI без установки
        Write-Host "Извлечение wg.exe из MSI-установщика..."

        # Создаём временную папку для извлечения
        $tempExtractPath = "$env:TEMP\wg_msi_extract"
        New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null

        # Используем msiexec для распаковки MSI во временную папку
        $msiexecArgs = "/a `"$msiPath`" /qn TARGETDIR=`"$tempExtractPath`""
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "msiexec.exe"
        $processInfo.Arguments = $msiexecArgs
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($processInfo)
        $process.WaitForExit()

        # Проверяем, что wg.exe был успешно извлечён
        $extractedWgPath = Join-Path $tempExtractPath "WireGuard\wg.exe"
        if (-not (Test-Path $extractedWgPath)) {
            throw "Не удалось извлечь wg.exe из MSI-установщика."
        }

        # Копируем wg.exe во временную директорию
        Copy-Item $extractedWgPath $wgTempPath -Force

        # Удаляем временную папку и MSI-установщик, но сохраняем wg.exe
        Remove-Item $tempExtractPath -Recurse -Force
        Remove-Item $msiPath -Force
    }

    # Используем временную директорию для wg.exe
    $wgPath = $wgTempPath

    # Получение приватного и публичного ключей
    $priv = if ($args[0]) { $args[0] } else { (& "$wgPath" genkey).Trim() }

    if ($args[1]) {
        $pub = $args[1]
    } else {
        $pub = ($priv | & "$wgPath" pubkey).Trim()
    }

    # Проверка, что ключи не пустые
    if ([string]::IsNullOrEmpty($priv) -or [string]::IsNullOrEmpty($pub)) {
        throw "Не удалось сгенерировать ключи."
    }

    # API Cloudflare WARP
    $api = "https://api.cloudflareclient.com/v0i1909051800"

    # Подготовка данных для запроса
    $tos = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")
    $data = @{
        install_id = ""
        tos        = $tos
        key        = $pub
        fcm_token  = ""
        type       = "ios"
        locale     = "en_US"
    } | ConvertTo-Json

    # Отправка POST запроса
    $response = Invoke-RestMethod -Uri "$api/reg" -Method Post -Headers @{ 'user-agent' = 'okhttp/3.12.1'; 'content-type' = 'application/json' } -Body $data

    # Проверка ответа
    if (-not $response.result) {
        throw "Ошибка при регистрации устройства."
    }

    $id    = $response.result.id
    $token = $response.result.token

    # Обновление регистрации
    $headers = @{
        'user-agent'    = 'okhttp/3.12.1'
        'content-type'  = 'application/json'
        'authorization' = "Bearer $token"
    }
    $patchData = @{ warp_enabled = $true } | ConvertTo-Json
    $response  = Invoke-RestMethod -Uri "$api/reg/$id" -Method Patch -Headers $headers -Body $patchData

    # Проверка ответа
    if (-not $response.result) {
        throw "Ошибка при обновлении регистрации."
    }

    # Извлечение информации для конфигурации
    $peer_pub      = $response.result.config.peers[0].public_key
    $peer_endpoint = $response.result.config.peers[0].endpoint.host
    $client_ipv4   = $response.result.config.interface.addresses.v4
    $client_ipv6   = $response.result.config.interface.addresses.v6

    # Проверка, что необходимые данные получены
    if ([string]::IsNullOrEmpty($peer_pub) -or [string]::IsNullOrEmpty($peer_endpoint) -or [string]::IsNullOrEmpty($client_ipv4) -or [string]::IsNullOrEmpty($client_ipv6)) {
        throw "Не удалось получить данные для конфигурации."
    }

    # Создание конфигурационного файла
    $conf = @"
[Interface]
PrivateKey = $priv
S1 = 0
S2 = 0
Jc = 120
Jmin = 23
Jmax = 911
H1 = 1
H2 = 2
H3 = 3
H4 = 4
Address = $client_ipv4, $client_ipv6
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001

[Peer]
PublicKey = $peer_pub
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $peer_endpoint
"@

} catch {
    Write-Host "Произошла ошибка: $_"
    Write-Host $_.ScriptStackTrace -Foreground "DarkGray"
    $ErrorOccurred = $true
}

if (-not $ErrorOccurred) {
    # Вывод конфигурации
    Clear-Host
    Write-Host "`n`n`n"
    Write-Host "########## НАЧАЛО КОНФИГА ##########"
    Write-Host $conf -ForegroundColor DarkGray
    Write-Host "########### КОНЕЦ КОНФИГА ###########"

    # Кодирование конфигурации в Base64
    $conf_base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($conf))

    # Вывод ссылки для скачивания
    Write-Host "Скачать конфиг файлом: "
    Write-Host "https://immalware.github.io/downloader.html?filename=WARP.conf&content=$conf_base64" -ForegroundColor Blue
    Write-Host "`nЧто-то не получилось? Есть вопросы? Пишите в чат: https://t.me/immalware_chat"
} else {
    Write-Host "Конфигурация не будет выведена из-за ошибок."
}
