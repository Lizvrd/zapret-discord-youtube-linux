<div align="center">

# <img src="https://cdn-icons-png.flaticon.com/128/5968/5968756.png" height=28 /> <a href="https://github.com">Lizvrd</a><a href="https://github.comzapret-discord-youtube-for-linux">/zapret-discord-youtube-for-linux</a> <img src="https://cdn-icons-png.flaticon.com/128/1384/1384060.png" height=28 />

**Linux-порт** стратегий из [zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube): `nfqws` + NFQUEUE вместо `winws.exe` + WinDivert

Основано на оригинальном проекте от **Flowseal** — <https://github.com/Flowseal/zapret-discord-youtube>  
Также вы можете материально поддержать оригинального разработчика zapret [тут](https://github.com/bol-van/zapret?tab=readme-ov-file#%D0%BF%D0%BE%D0%B4%D0%B4%D0%B5%D1%80%D0%B6%D0%B0%D1%82%D1%8C-%D1%80%D0%B0%D0%B7%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D1%87%D0%B8%D0%BA%D0%B0)
</div>

> [!CAUTION]
>
> ### ФЕЙКИ
>
> Я не веду никакие другие страницы/группы в телеграм/ютуб каналы  
> Если вы наткнулись на что-то вне этой страницы гитхаба, что распространяется от моего лица - **ФЕЙК**.

> [!IMPORTANT]
> Все `.bin`-фейки в папке [`bin`](./bin) взяты из [zapret-win-bundle/zapret-winws](https://github.com/bol-van/zapret-win-bundle/tree/master/zapret-winws) и [zapret/releases](https://github.com/bol-van/zapret/releases). Вы можете это проверить с помощью хэшей/контрольных сумм.
>
> Сам обход на Linux выполняет `nfqws` из [zapret/releases](https://github.com/bol-van/zapret/releases). Скачать его в `bin/nfqws` можно командой `./zapret.sh --install-nfqws` (с проверкой sha256).
>
> #### Проверяйте, что запускаете, используя сборки из интернета, и не используйте Яндекс Поиск! Он часто предлагает вредоносы по первым ссылкам, а настоящий репозиторий скрыт  

> [!WARNING]
>
> ### ROOT И FIREWALL
>
> Обход работает через NFQUEUE, поэтому нужны права root (`sudo`) и `iptables` или `nftables`.
>
> `zapret` добавляет правила в firewall и убирает их при остановке (`sudo ./zapret.sh stop`).
> Убедитесь, что на NFQUEUE `200` не запущен другой zapret - иначе они будут мешать друг другу.
>
> Посмотреть, что именно будет сделано, можно без запуска: `./general.sh --dry-run` и `sudo ./general.sh check`.

## ⚙️Использование

1. Включите Безопасный DNS (Secure DNS)
    * В Chrome - "Использовать безопасный DNS", и выбрать поставщика услуг DNS (выбрать вариант, отличный от варианта "Поставщик по умолчанию")
    * В Firefox - "DNS через HTTPS", выбрать режим "Персональный", затем "Выбрать провайдера/поставщика" и вписать URL поставщика вручную. Например, можно использовать `https://dns.google/dns-query` (т.к. поставщик Cloudflare может быть заблокирован)
    * Если у вас роутер Keenetic, включите в настройках роутера опцию "Транзит запросов". Отключение этой опции может привести к проблемам при настройке и использовании Secure DNS на компьютере

2. Скачайте репозиторий (git clone или архив со [страницы последнего релиза](https://github.com/Lizvrd/zapret-discord-youtube-linux/releases/latest))

3. Распакуйте в путь без кириллицы и спец. символов и перейдите в папку:

    ```bash
    cd zapret-discord-youtube-linux
    ```

4. Скачайте `nfqws`:

    ```bash
    ./zapret.sh --install-nfqws
    ```

5. Запустите нужную стратегию (нужен root):

    ```bash
    sudo ./general.sh
    ```

6. Узнать рабочую стратегию: `sudo ./zapret-test.sh` (аналог `Run Tests` -> `Standard tests` -> `All configs`)

7. Поставить на автозапуск: `sudo ./service.sh install general`

### 🐧 Linux

На каждую стратегию есть отдельный файл: `general.sh`, `alt.sh`, `alt2.sh` ... - их можно запускать напрямую, как `general*.bat` в оригинальном проекте.

```bash
./zapret.sh --install-nfqws          # скачать nfqws из последнего релиза zapret
./zapret.sh list                     # список стратегий (general, alt, alt2 ...)

sudo ./general.sh                    # запустить нужную стратегию напрямую
sudo ./zapret.sh general             # то же самое через CLI
sudo ./zapret.sh status              # проверить, что запущено
sudo ./zapret.sh stop                # остановить и убрать правила firewall
```

* общий движок лежит в `lib/zapret-lib.sh`, а файлы стратегий (`general.sh`, `alt.sh` ...) только описывают их параметры
* `./general.sh --dry-run` - проверить параметры стратегии без запуска
* `sudo ./general.sh run` - запуск в переднем плане (Ctrl+C - выход)
* `sudo ./general.sh check` - диагностика: root, правила firewall, параметры `nfqws`
* `sudo ./service.sh install general` / `sudo ./service.sh uninstall` - автозапуск через systemd (`zapret-linux.service`)
* `./service.sh status`, `sudo ./service.sh restart` - управление службой
* `sudo ./zapret-test.sh` - прогоняет все стратегии по целям из `utils/targets.txt` и показывает лучшую
* `.bin`-фейки, `lists/` и `utils/` - общие для всех стратегий

## ℹ️Краткие описания файлов

* [**`general.sh`, `alt.sh`, ...**](./general.sh) - 🐧 отдельный файл на каждую стратегию

  Запуск вручную можно использовать для проверки работоспособности стратегий. Работоспособность той или иной стратегии зависит от многих факторов. **Пробуйте разные стратегии (ALT, FAKE и другие), пока не найдёте рабочее для вас решение**

* [**`zapret.sh`**](./zapret.sh) - 🐧 CLI: `start`, `stop`, `status`, `list`, `check`, `--dry-run`, `--install-nfqws`

* [**`service.sh`**](./service.sh) - 🐧 автозапуск через systemd: `install` / `uninstall` / `status` / `restart`

* [**`lib/zapret-lib.sh`**](./lib/zapret-lib.sh) - 🐧 общий движок: firewall, списки, game filter, запуск `nfqws`

* [**`zapret-test.sh`**](./zapret-test.sh) - 🐧 проверка стратегий по сайтам из `utils/targets.txt`

* **`bin/`** - фейки `.bin` и `nfqws`
  * `nfqws` скачивается командой `./zapret.sh --install-nfqws`
  * `.bin`-фейки используются стратегиями и заменяются вручную

* **`lists/`** - списки доменов и IP:
  * `list-general.txt`, `list-exclude.txt`, `list-google.txt` - основные списки
  * `*-user.txt` - ваши дополнения (создаются автоматически при первом запуске)
  * `ipset-all.txt` - IP и подсети для ipset-фильтра

* **`utils/`**
  * `targets.txt` - сайты для `zapret-test.sh`
  * `game_filter.enabled` - режим Game Filter (необязательный файл)

## ☑️Распространенные вопросы и проблемы

### После запуска стратегии ничего не происходит

* Проверьте, что стратегия запущена: `./zapret.sh status`
* Посмотрите лог: `tail -n 50 /var/log/zapret-linux.log`
* Выполните диагностику: `sudo ./general.sh check`

### Ни одна стратегия не подходит

* Убедитесь, что скрипт запускается от root (`sudo`)
* Выполните `sudo ./zapret.sh check general` - команда проверит firewall и параметры `nfqws`
* Убедитесь, что нет другого zapret на NFQUEUE `200`: `pgrep -a nfqws`
* Попробуйте `sudo ./zapret-test.sh` и посмотрите, какие стратегии дают больше успешных проверок
* Перезагрузите компьютер и повторите запуск

### Обход не работает / перестал работать

> [!IMPORTANT]
> **Стратегии со временем могут переставать работать.**
> Определенная стратегия может работать какое-то время, но со временем она может переставать работать из-за обнаружения.
> В репозитории представлены множество различных стратегий для обхода. Если ни одна из них вам не помогает, то вам необходимо создать новую, взяв за основу одну из представленных здесь и изменив её параметры.
> Информацию про параметры стратегий вы можете найти [тут](https://github.com/bol-van/zapret/blob/master/docs/readme.md#nfqws).

* Проверьте, что обход запущен: `./zapret.sh status`

* Убедитесь, что адрес ресурса записан в списках доменов или IP

* Проверьте другие стратегии (**`ALT`**/**`FAKE`** и другие)

* Попробуйте полную переустановку (см. раздел ниже)

### Как переустановить/обновить полностью?

* Сохраните ресурсы/данные, которые вы сами добавляли (`lists/*-user.txt`)
* Остановите обход и службу: `sudo ./service.sh uninstall`, затем `sudo ./zapret.sh stop`
* Удалите папку с zapret
* Скачайте последнюю версию [со страницы релизов](https://github.com/Lizvrd/zapret-discord-youtube-linux/releases) или обновите `git pull`
* Заново скачайте `nfqws`: `./zapret.sh --install-nfqws`
* Пробуйте запускать различные стратегии (`sudo ./general.sh`, `sudo ./alt.sh` ...) и проверяйте доступность ресурсов
* Как найдёте рабочую стратегию, поставьте её на автозапуск: `sudo ./service.sh install <стратегия>`

### Не работает игра/приложение с включённым запретом

* В Linux game filter включается файлом `utils/game_filter.enabled` (`mode=disabled|all|tcp|udp`, `tcp=...`, `udp=...`), а фильтр по IP задаётся содержимым `lists/ipset-all.txt`
* После изменения `utils/game_filter.enabled` перезапустите стратегию

### 🐧 Linux: запустил, но обхода нет

* Выполните `sudo ./zapret.sh check general` - команда проверит root, правила firewall и параметры `nfqws`
* Посмотрите лог: `tail -n 50 /var/log/zapret-linux.log`, для службы - `journalctl -u zapret-linux.service -n 50`
* Убедитесь, что на NFQUEUE `200` не сидит другой zapret (`ss -f netlink` или `pgrep -a nfqws`)
* Проверьте, что в `lists/ipset-all.txt` не осталась заглушка `203.0.113.113/32` (так ipset-фильтр выключен)

### Служба осталась после удаления

* Удалите её командой `sudo ./service.sh uninstall`
* Если юнит остался вручную: `sudo systemctl disable --now zapret-linux.service` и `sudo rm /etc/systemd/system/zapret-linux.service`, затем `sudo systemctl daemon-reload`

### Не работает <img src="https://cdn-icons-png.flaticon.com/128/1384/1384060.png" height=18 /> YouTube

* Убедитесь что вы настроили [Secure DNS](#%EF%B8%8Fиспользование). Без этого сайт ютуба может писать "нет интернета", или вовсе не будет работать
* Вместо видео отображается надпись "Этот контент недоступен. Повторите попытку позже" - отключите блокировщик рекламы
* Сайт открывается, но загрузка видео сильно тормозит, либо видео не грузится совсем - работа российских серверов ютуба нарушена, прочтите [этот комментарий](https://github.com/Flowseal/zapret-discord-youtube/discussions/251#discussioncomment-19621478)
* Вы заблокировали у себя российские серверы YouTube, но это не помогло - измените стратегию обхода, проверьте что запрет запущен
* См. также [#251](https://github.com/Flowseal/zapret-discord-youtube/discussions/251)

### Не работает <img src="https://cdn-icons-png.flaticon.com/128/5968/5968756.png" height=18 /> Discord

* Убедитесь что вы настроили [Secure DNS](#%EF%B8%8Fиспользование)
* Желательно сначала узнать, на какой стратегии открывается сайт YouTube. Запустите эту стратегию.
* Очистите кэш Discord (в приложении или удалив каталог кэша) и перезапустите его
* Проверьте Discord в браузере: <https://discord.com/app>. В браузере работает? Если работает, то можете пользоваться в нём.
* Если Discord и в браузере не работает, то пробуйте ещё раз все стратегии. Бывает такое, что на одной стратегии YouTube работает, а Discord нет.
* См. также [#252](https://github.com/Flowseal/zapret-discord-youtube/discussions/252)

### Не работает <img src="https://cdn-icons-png.flaticon.com/128/5968/5968804.png" height=18 /> Telegram

* Используйте программу [tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy)
* Или используйте бесплатные MTProto прокси из интернета

### Не работает <img src="https://cdn-icons-png.flaticon.com/128/174/174872.png" height=18 /> Spotify

* С помощью zapret нельзя починить Spotify, он сам заблокировал российских пользователей. В Discussions можно найти другие способы починки Spotify, но к zapret они не имеют никакого отношения, и помощь по ним в issues не предоставляется.

### Не работают игры

Есть много разных игр. Исследовать и чинить каждую из них нет возможности.

Наиболее универсальный рецепт такой:

* включите Game Filter через `utils/game_filter.enabled` (`mode=all`)
* если это не поможет, то попробуйте также заполнить `lists/ipset-all.txt` и включить ipset-фильтр

Но помните, что при широком ipset-фильтре появятся проблемы с открытием многих сайтов. Чтобы этого избежать, не используйте его на постоянной основе. Вместо этого нужно выяснить все IP-адреса и домены, которые используются игрой, и добавить их в `lists/ipset-all.txt` и в `lists/list-general-user.txt` соответственно.

Игра работает, но большой пинг? Выясните всё то же самое, но вместо этого добавьте IP-адреса в `lists/ipset-exclude-user.txt`, а домены в `lists/list-exclude-user.txt`

Если и это не помогло, создайте ветку обсуждений в разделе [Discussions](https://github.com/Flowseal/zapret-discord-youtube/discussions) (не в issues) и ждите помощи от других игроков.

### Не нашли своей проблемы

* Создайте её [тут](https://github.com/Flowseal/zapret-discord-youtube/issues)

## 🗒️Добавление адресов прочих ресурсов

Список адресов для обхода можно расширить, добавляя их в:

* **`list-general-user.txt`** для доменов (поддомены автоматически учитываются)
* **`list-exclude-user.txt`** для исключения доменов (например, если айпи сети указан в `ipset-all.txt`, но конкретный домен из этой сети не надо фильтровать)
* **`ipset-all.txt`** для IP и подсетей
* **`ipset-exclude-user.txt`** для исключения IP и подсетей
  * Файлы **`*-user.txt`** автоматически создадутся при первом запуске любой стратегии

## ⭐Поддержка проекта

Вы можете поддержать проект, поставив :star: этому репозиторию (сверху справа этой страницы)

Также вы можете материально поддержать оригинального разработчика zapret [тут](https://github.com/bol-van/zapret?tab=readme-ov-file#%D0%BF%D0%BE%D0%B4%D0%B4%D0%B5%D1%80%D0%B6%D0%B0%D1%82%D1%8C-%D1%80%D0%B0%D0%B7%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D1%87%D0%B8%D0%BA%D0%B0)

## ⚖️Лицензирование

Проект распространяется на условиях лицензии [MIT](https://github.com/Lizvrd/zapret-discord-youtube-linux/blob/develop/LICENSE.txt)

## 🩷Благодарность участникам проекта

[![Contributors](https://contrib.rocks/image?repo=Flowseal/zapret-discord-youtube)](https://github.com/Flowseal/zapret-discord-youtube/graphs/contributors)

💖 Отдельная благодарность разработчику [zapret](https://github.com/bol-van/zapret) - [bol-van](https://github.com/bol-van)
