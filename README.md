# Сгенерируйте конфиг Cloudflare WARP для AmneziaWG
Этот bash скрипт сгенерирует конфиг Cloudflare WARP для AmneziaWG.

Не стоит выполнять его локально, так как РКН заблокировал запросы для получения конфига. Вместо этого лучше выполнять на удалённых серверах.

## Вариант 1: Aeza Terminator
1. Заходим на https://terminator.aeza.net/en/
2. Выбираем **Debian**
3. Вставляем команду:
```bash
bash <(wget -qO- https://raw.githubusercontent.com/ImMALWARE/bash-warp-generator/main/warp_generator.sh)
```
4. После того, как конфиг сгенерируется, копируем его, либо скачиваем файлом по ссылке и импортируем в AmneziaWG!👍
## Вариант 2: Replit
1. Тыкаем сюда: [![Run on Repl.it](https://repl.it/badge/github/replit/upm)](https://replit.com/new/github/ImMALWARE/bash-warp-generator)
2. Создаём аккаунт
3. Нажимаем кнопку Run вверху
4. После того, как конфиг сгенерируется, копируем его, либо скачиваем файлом по ссылке и импортируем в AmneziaWG!👍
## Вариант 3: Windows
#### Имейте в виду, что запросы на получение конфига могут не выполниться из-за блокировки РКН
1. Открываем PowerShell
2. Вставляем команду:
```bash
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ImMALWARE/bash-warp-generator/main/warp_generator.ps1" -UseBasicParsing).Content)
```
3. Копируем конфиг, либо скачиваем файлом по ссылке и импортируем в AmneziaWG!👍


## Что-то не получается?
### После подключения в AmneziaWG ничего не работает, в строке **Передача**: получено 0 Б
К сожалению, AmneziaWG не удалось обойти блокировку WireGuard от вашего провайдера :( \
https://github.com/ImMALWARE/bash-warp-generator/issues/5

### Другой вопрос?
Напишите в чат: https://t.me/immalware_chat
