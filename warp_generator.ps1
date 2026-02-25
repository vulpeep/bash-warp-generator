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
    #$peer_endpoint = $response.result.config.peers[0].endpoint.host
    $client_ipv4   = $response.result.config.interface.addresses.v4
    $client_ipv6   = $response.result.config.interface.addresses.v6

    # Проверка, что необходимые данные получены
    if ([string]::IsNullOrEmpty($peer_pub) -or [string]::IsNullOrEmpty($client_ipv4) -or [string]::IsNullOrEmpty($client_ipv6)) {
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
MTU = 1280
I1 = <b 0xc2000000011419fa4bb3599f336777de79f81ca9a8d80d91eeec000044c635cef024a885dcb66d1420a91a8c427e87d6cf8e08b563932f449412cddf77d3e2594ea1c7a183c238a89e9adb7ffa57c133e55c59bec101634db90afb83f75b19fe703179e26a31902324c73f82d9354e1ed8da39af610afcb27e6590a44341a0828e5a3d2f0e0f7b0945d7bf3402feea0ee6332e19bdf48ffc387a97227aa97b205a485d282cd66d1c384bafd63dc42f822c4df2109db5b5646c458236ddcc01ae1c493482128bc0830c9e1233f0027a0d262f92b49d9d8abd9a9e0341f6e1214761043c021d7aa8c464b9d865f5fbe234e49626e00712031703a3e23ef82975f014ee1e1dc428521dc23ce7c6c13663b19906240b3efe403cf30559d798871557e4e60e86c29ea4504ed4d9bb8b549d0e8acd6c334c39bb8fb42ede68fb2aadf00cfc8bcc12df03602bbd4fe701d64a39f7ced112951a83b1dbbe6cd696dd3f15985c1b9fef72fa8d0319708b633cc4681910843ce753fac596ed9945d8b839aeff8d3bf0449197bd0bb22ab8efd5d63eb4a95db8d3ffc796ed5bcf2f4a136a8a36c7a0c65270d511aebac733e61d414050088a1c3d868fb52bc7e57d3d9fd132d78b740a6ecdc6c24936e92c28672dbe00928d89b891865f885aeb4c4996d50c2bbbb7a99ab5de02ac89b3308e57bcecf13f2da0333d1420e18b66b4c23d625d836b538fc0c221d6bd7f566a31fa292b85be96041d8e0bfe655d5dc1afed23eb8f2b3446561bbee7644325cc98d31cea38b865bdcc507e48c6ebdc7553be7bd6ab963d5a14615c4b81da7081c127c791224853e2d19bafdc0d9f3f3a6de898d14abb0e2bc849917e0a599ed4a541268ad0e60ea4d147dc33d17fa82f22aa505ccb53803a31d10a7ca2fea0b290a52ee92c7bf4aab7cea4e3c07b1989364eed87a3c6ba65188cd349d37ce4eefde9ec43bab4b4dc79e03469c2ad6b902e28e0bbbbf696781ad4edf424ffb35ce0236d373629008f142d04b5e08a124237e03e3149f4cdde92d7fae581a1ac332e26b2c9c1a6bdec5b3a9c7a2a870f7a0c25fc6ce245e029b686e346c6d862ad8df6d9b62474fbc31dbb914711f78074d4441f4e6e9edca3c52315a5c0653856e23f681558d669f4a4e6915bcf42b56ce36cb7dd3983b0b1d6fdf0f8efddb68e7ca0ae9dd4570fe6978fbb524109f6ec957ca61f1767ef74eb803b0f16abd0087cf2d01bc1db1c01d97ac81b3196c934586963fe7cf2d310e0739621e8bd00dc23fded18576d8c8f285d7bb5f43b547af3c76235de8b6f757f817683b2151600b11721219212bf27558edd439e73fce951f61d582320e5f4d6c315c71129b719277fc144bbe8ded25ab6d29b6e189c9bd9b16538faf60cc2aab3c3bb81fc2213657f2dd0ceb9b3b871e1423d8d3e8cc008721ef03b28e0ee7bb66b8f2a2ac01ef88df1f21ed49bf1ce435df31ac34485936172567488812429c269b49ee9e3d99652b51a7a614b7c460bf0d2d64d8349ded7345bedab1ea0a766a8470b1242f38d09f7855a32db39516c2bd4bcc538c52fa3a90c8714d4b006a15d9c7a7d04919a1cab48da7cce0d5de1f9e5f8936cffe469132991c6eb84c5191d1bcf69f70c58d9a7b66846440a9f0eef25ee6ab62715b50ca7bef0bc3013d4b62e1639b5028bdf757454356e9326a4c76dabfb497d451a3a1d2dbd46ec283d255799f72dfe878ae25892e25a2542d3ca9018394d8ca35b53ccd94947a8>
Address = $client_ipv4, $client_ipv6
DNS = 1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001

[Peer]
PublicKey = $peer_pub
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:500
"@

    # Генерация AWG_JSON для AmneziaVPN
    $AWG_JSON_OBJ = [ordered]@{
        H1 = "1"
        H2 = "2"
        H3 = "3"
        H4 = "4"
        I1 = ""
        Jc = "120"
        Jmax = "911"
        Jmin = "23"
        S1 = "0"
        S2 = "0"
        allowed_ips = @("0.0.0.0/0", "::/0")
        client_ip = "$client_ipv4, $client_ipv6"
        client_priv_key = $priv
        config = ($conf -replace "`r`n", "`n" -replace "`n", "`r`n")
        hostName = "162.159.192.1"
        mtu = 1280
        port = 500
        server_pub_key = $peer_pub
    }
    $AWG_JSON = $AWG_JSON_OBJ | ConvertTo-Json -Depth 10

    # Генерация AMNEZIA_JSON
    $AMNEZIA_JSON_OBJ = [ordered]@{
        containers = @(
            [ordered]@{
                container = "amnezia-awg"
                awg = [ordered]@{
                    isThirdPartyConfig = $true
                    last_config = $AWG_JSON
                    port = "500"
                    transport_proto = "udp"
                }
            }
        )
        defaultContainer = "amnezia-awg"
        description = "Cloudflare WARP"
        hostName = "162.159.192.1"
    }
    $AMNEZIA_JSON = $AMNEZIA_JSON_OBJ | ConvertTo-Json -Depth 10

    # Генерация VPN ключа
    $VPN_KEY = "vpn://" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($AMNEZIA_JSON))

} catch {
    Write-Host "Произошла ошибка: $_"
    Write-Host $_.ScriptStackTrace -Foreground "DarkGray"
    $ErrorOccurred = $true
}

if (-not $ErrorOccurred) {
    Clear-Host
    Write-Host "########## СТРОКА ДЛЯ AMNEZIAVPN ##########"
    Write-Host $VPN_KEY
    Write-Host "########### КОНЕЦ СТРОКИ ДЛЯ AMNEZIAVPN ###########"

    Write-Host "`n`n`n"
    Write-Host "########## НАЧАЛО КОНФИГА ##########"
    Write-Host $conf -ForegroundColor DarkGray
    Write-Host "########### КОНЕЦ КОНФИГА ###########"

    Write-Host "`n"
    $conf_base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($conf))
    Write-Host "Скачать конфиг файлом: https://immalware.vercel.app/download?filename=WARP.conf&content=$conf_base64"
    Write-Host "Импортируйте конфиг в приложение AmneziaVPN! Приложение AmneziaWG не поддерживает этот формат!"
    Write-Host "`n"
    Write-Host "Что-то не получилось? Есть вопросы? Пишите в чат: https://t.me/immalware_chat"
} else {
    Write-Host "Конфигурация не будет выведена из-за ошибок."
}
