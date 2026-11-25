# راهنمای نصب — قدم به قدم

این راهنما برای کسی نوشته شده که تازه یک سرور گرفته و می‌خواهد در چند دقیقه سایت را بالا بیاورد.
هیچ دانشی از لینوکس لازم نیست؛ فقط کافی است دستورها را به ترتیب کپی کنید.

**خلاصه:** یک دستور. فقط دامنه را می‌پرسد، و هیچ‌چیز از قلم نمی‌افتد.

---

## ۰) قبل از شروع — چک‌لیست ۳۰ ثانیه‌ای

| لازم است | توضیح |
|---|---|
| یک سرور لینوکس | Ubuntu 22.04 / 24.04 بهترین گزینه است. Debian، CentOS، Rocky، Alma، Fedora، Arch، Alpine و openSUSE هم پشتیبانی می‌شوند |
| دسترسی `root` یا `sudo` | اگر با کاربر عادی وصل می‌شوید، اسکریپت خودش `sudo` می‌زند |
| رم و دیسک | ۵۱۲ مگابایت رم و حدود ۵۰ مگابایت دیسک کافی است (برنامه یک فایل HTML و یک وب‌سرور پایتون است) |
| یک پورت آزاد | پیش‌فرض از `8080` شروع می‌کند و اگر اشغال بود، خودش پورت آزاد بعدی را برمی‌دارد |
| دامنه | **اختیاری**. بدون دامنه با IP هم کار می‌کند؛ با دامنه، HTTPS هم می‌گیرید |

> اگر سرورت پنل مدیریتی مثل cPanel/aaPanel دارد که پورت ۸۰ را گرفته، مشکلی نیست — نصب‌کننده پورت آزاد را خودش پیدا می‌کند.

---

## ۱) وصل شدن به سرور

از ترمینال ویندوز (PowerShell یا Git Bash)، مک یا لینوکس:

```bash
ssh root@SERVER_IP
```

`SERVER_IP` همان آدرسی است که پنل سرور به شما داده (مثلاً `185.12.34.56`).
بار اول می‌پرسد `Are you sure you want to continue connecting?` → `yes` و بعد رمز عبور.

---

## ۲) نصب — همین یک دستور

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | bash
```

همین. اول از شما **دامنه** را می‌پرسد:

```
[2/7] تنظیمات
  دامنه  اگر دامنه ندارید خالی بگذارید تا سایت با IP و پورت 8080 کار کند.
  با دامنه، nginx و گواهی رایگان HTTPS هم خودکار راه می‌افتند.
  دامنه:
```

- **دامنه دارید؟** بنویسید (مثل `screener.example.com`) — nginx و HTTPS خودکار می‌شوند و بعد ایمیل SSL را هم می‌پرسد (اختیاری، `Enter` = بدون ایمیل).
- **دامنه ندارید؟** فقط `Enter` بزنید — سایت با `http://IP:8080` بالا می‌آید.
- **هیچ سؤالی نمی‌خواهید؟** `--unattended` را اضافه کنید.

بعد از این مرحله، اسکریپت خودش:

- اگر root نباشید، با `sudo` دوباره اجرا می‌شود (پس نیازی نیست خودتان `sudo` بنویسید)
- `python3` و ابزار دانلود را بررسی و در صورت نبودن نصب می‌کند
- اولین پورت آزاد را انتخاب می‌کند
- فایل‌ها را می‌نشاند، کاربر بدون دسترسی می‌سازد، سرویس می‌سازد و بالا می‌آورد
- سالم بودن سرویس را واقعاً تست می‌کند و آدرس نهایی را چاپ می‌کند

### در حین نصب چه می‌بینید

اسکریپت هفت مرحله را با شماره نشان می‌دهد؛ هر خط یا `✔` (انجام شد) است یا `•` (اطلاع) یا `!` (هشدار غیرمرگبار):

| مرحله | چه کاری می‌کند |
|---|---|
| `[1/7] بررسی پیش‌نیازها` | سیستم‌عامل، init (systemd/OpenRC)، پایتون و ابزار دانلود |
| `[2/7] تنظیمات` | انتخاب پورت، مسیر نصب، حالت دسترسی (IP یا دامنه) |
| `[3/7] دریافت فایل‌های برنامه` | دانلود آخرین نسخه از گیت‌هاب (یا استفاده از فایل‌های کنار اسکریپت) |
| `[4/7] نصب فایل‌ها` | کپی در `/opt/binance-futures-screener`، ساخت کاربر سرویس، تنظیم دسترسی‌ها |
| `[5/7] راه‌اندازی سرویس` | ساخت یونیت systemd (یا اسکریپت OpenRC)، فعال‌سازی در بوت، استارت |
| `[6/7] بررسی سلامت` | درخواست به `/healthz` تا مطمئن شود سرویس واقعاً جواب می‌دهد |
| `[7/7] وب‌سرور و فایروال` | nginx و SSL (اگر دامنه داده باشید) و باز کردن پورت در ufw/firewalld |

در پایان یک خلاصه‌ی کادردار چاپ می‌شود:

```
────────────────────────────────────────────────────────────
  ✔ نصب کامل شد  —  Binance Futures Screener
────────────────────────────────────────────────────────────
  آدرس          http://185.12.34.56:8080
  API           http://185.12.34.56:8080/api/v1  (راهنما: /api)
  پورت          8080  (0.0.0.0)
  مسیر نصب      /opt/binance-futures-screener
  سرویس         binance-screener  (systemd)
  فایروال       پورت 8080 در ufw باز شد
  SSL           غیرفعال
────────────────────────────────────────────────────────────
```

**همان «آدرس» را در مرورگر باز کنید.** تمام.

---

## ۳) اگر سایت باز نشد — به همین ترتیب چک کنید

این‌جا ۹۵٪ موارد حل می‌شود. به ترتیب بروید و اولی که جواب داد، همان است.

**۱. فایروال ابری (شایع‌ترین دلیل).** فایروال داخل سرور با پنل ابری فرق دارد. در پنل ارائه‌دهنده (AWS → Security Group، Hetzner → Firewall، Arvan/DigitalOcean → Firewall) باید پورت را باز کنید:

| حالت | پورت‌هایی که باید باز باشند |
|---|---|
| دسترسی با IP | همان پورت سرویس (مثلاً `8080/tcp`) |
| با دامنه و HTTPS | `80/tcp` و `443/tcp` |

**۲. خود سرویس سالم است؟** روی سرور:

```bash
curl -s localhost:8080/healthz
```

اگر `ok` برگرداند، برنامه سالم است و مشکل فقط مسیر شبکه/فایروال است.

**۳. فایروال داخل سرور:**

```bash
ufw status          # اوبونتو/دبیان
firewall-cmd --list-ports   # CentOS/Rocky
```

**۴. گزارش وضعیت کامل** (سیستم‌عامل، init، پایتون، فایروال، پورت، وضعیت سرویس — بدون تغییر چیزی):

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | bash -s -- --check
```

**۵. لاگ‌ها:**

```bash
tail -n 50 /var/log/binance-screener-install.log   # لاگ نصب
journalctl -u binance-screener -n 50 --no-pager    # لاگ سرویس
```

> **نکته‌ی مهم:** اگر سرور شما در ایران است، ممکن است صفحه باز شود ولی لیست کوین‌ها خالی بماند. این به خاطر محدودیت منطقه‌ای بایننس (خطای `451`) است، نه نصب. برنامه خودش چند دامنه‌ی جایگزین را امتحان می‌کند، ولی اگر همه بسته باشند، سرور باید خارج از ایران باشد. جزئیات در بخش «محدودیت منطقه‌ای» در `README.md`.

---

## ۴) نصب با دامنه و HTTPS (توصیه‌شده برای استفاده‌ی واقعی)

**اول DNS را درست کنید.** در پنل دامنه یک رکورد `A` بسازید:

```
نوع: A    نام: screener    مقدار: SERVER_IP    TTL: 300
```

بعد از چند دقیقه چک کنید که resolve شود:

```bash
ping screener.example.com
```

وقتی IP سرور را برگرداند، نصب را با دامنه اجرا کنید:

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh \
  | bash -s -- --domain screener.example.com --email you@example.com
```

این بار علاوه بر همه‌ی مراحل قبل: nginx نصب می‌شود، ریورس‌پروکسی روی دامنه ساخته می‌شود، گواهی رایگان Let's Encrypt گرفته می‌شود و HTTP به HTTPS ریدایرکت می‌شود. برنامه هم دیگر روی `0.0.0.0` باز نیست، فقط `127.0.0.1` — یعنی از بیرون کسی نمی‌تواند پورت داخلی را مستقیم صدا بزند.

> اگر DNS هنوز آماده نباشد، نصب **نمی‌شکند**: با HTTP بالا می‌آید و در پایان دستور اصلاح را چاپ می‌کند. کافی است بعد از درست شدن DNS همان دستور را دوباره بزنید.

---

## ۴.۱) سرورهای دارای پنل مدیریتی (CyberPanel / cPanel / aaPanel)

اگر روی سرور شما از قبل nginx دیگری در حال سرویسدهی است، قبل از نصب ببینید کدام پوشه را میخواند:

```bash
sudo nginx -T | grep -E "include.*(sites-enabled|conf\.d|http\.d)"
```

اگر خروجی `sites-enabled` نشان دهد، فایلی که نصبکننده بهطور پیشفرض در `conf.d` مینویسد **بارگذاری نمیشود**. سرویس پایتون را نصب کنید و ریورسپروکسی را خودتان در کنار سایتهای موجود بسازید:

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh \
  | bash -s -- --port 18080 --bind 127.0.0.1 --domain screener.example.com --no-nginx --no-firewall
```

### مرحله ۱ — vhost موقت برای گرفتن گواهی

وقتی گواهی هنوز وجود ندارد، nginx نمیتواند فایلی را که به آن اشاره میکند بارگذاری کند. اول فقط یک سرور HTTP بسازید:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name screener.example.com;
    location ^~ /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { proxy_pass http://127.0.0.1:18080; }
}
```

ذخیره کنید در `/etc/nginx/sites-enabled/screener.example.com.conf`، سپس:

```bash
sudo mkdir -p /var/www/certbot
sudo nginx -t && sudo systemctl reload nginx
sudo certbot certonly --webroot -w /var/www/certbot -d screener.example.com \
  --agree-tos --no-eff-email -m you@example.com
sudo certbot reconfigure --cert-name screener.example.com \
  --deploy-hook "systemctl reload nginx"
```

### مرحله ۲ — vhost نهایی HTTPS

همان فایل را با این محتوا جایگزین کنید. مسیر `/api/v1/stream` حتماً بدون بافر پراکسی میشود:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name screener.example.com;
    location ^~ /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://screener.example.com$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name screener.example.com;

    ssl_certificate     /etc/letsencrypt/live/screener.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/screener.example.com/privkey.pem;

    location = /healthz {
        proxy_pass http://127.0.0.1:18080/healthz;
        access_log off;
    }

    location /api/v1/stream {
        proxy_pass http://127.0.0.1:18080;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        add_header X-Accel-Buffering no;
    }

    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### چک نهایی

```bash
curl -I http://screener.example.com          # باید 301 به https بدهد
curl -s https://screener.example.com/api/v1/health
curl -N --max-time 10 https://screener.example.com/api/v1/stream  # رویداد snapshot میآید
```

> **نکته درباره منو:** گزینه تغییر دامنه در `binance-screener` از همان نصبکننده استفاده میکند و فایل را در `conf.d` مینویسد. روی این سرورها بعد از تغییر دامنه از منو، حتماً vhost دستی بالا را هم با دامنه تازه هماهنگ کنید و دوباره `nginx -t && systemctl reload nginx` بزنید. سرویس پایتون و تمام سایتهای دیگر دستنخورده میمانند.

## ۵) حالت تعاملی — اگر می‌خواهید خودتان انتخاب کنید

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | bash -s -- --interactive
```

به ترتیب می‌پرسد: پورت، دامنه، nginx، SSL، ایمیل، فایروال. هر سؤال یک مقدار پیش‌فرض در `[]` دارد؛ `Enter` بزنید یعنی «همان». اگر ترمینال تعاملی نباشد (مثلاً از داخل پنل وب اجرا کنید) خودش به حالت خودکار برمی‌گردد و نصب را ادامه می‌دهد.

---

## ۶) منوی مدیریت — تنظیمات بعد از نصب

بعد از نصب یک دستور اضافه می‌شود که همه‌ی تنظیمات را در یک منو نشان می‌دهد:

```bash
binance-screener        # یا کوتاه‌تر: bfs
```

```
  Binance Futures Screener // منوی مدیریت
────────────────────────────────────────────────────────────
  وضعیت   فعال
  آدرس    https://screener.example.com
  پورت    8080    دامنه  screener.example.com    SSL  فعال
────────────────────────────────────────────────────────────
   1   نمایش وضعیت و سلامت سرویس
   2   تغییر پورت
   3   تنظیم یا تغییر دامنه   (HTTPS خودکار)
   4   حذف دامنه و برگشت به دسترسی با IP
   5   ری‌استارت سرویس
   6   دیدن لاگ سرویس
   7   به‌روزرسانی به آخرین نسخه
   8   حذف کامل نصب
   0   بستن منو
────────────────────────────────────────────────────────────
  شماره گزینه (0 = بستن منو):
```

- عدد گزینه را بزنید و `Enter`. برای برگشتن به منو دوباره `Enter`.
- **`0` منو را می‌بندد** (یا `q` / `Ctrl+C`).
- منو خودش root لازم ندارد؛ فقط وقتی تغییری اعمال می‌کنید رمز `sudo` می‌پرسد.
- هر تغییر از همان مسیر نصب رد می‌شود: بکاپ نسخه‌ی قبلی، بررسی `/healthz`، و بازگشت خودکار در صورت خطا.
- گزینه‌ی ۳ (دامنه) اگر DNS آماده نباشد نصب را نمی‌شکند؛ با HTTP بالا می‌آید و راهنمای اصلاح را چاپ می‌کند.

> اگر دستور `binance-screener` پیدا نشد، یعنی نصب قدیمی است: یک بار دستور نصب را دوباره اجرا کنید تا منو نصب شود.

## ۷) دستورهای روزمره

```bash
systemctl status binance-screener      # وضعیت
systemctl restart binance-screener     # ری‌استارت
systemctl stop binance-screener        # توقف
journalctl -u binance-screener -f      # لاگ زنده
curl -s localhost:8080/healthz         # تست سلامت
```

### API عمومی

همان سرور یک API فقط-خواندنی هم ارائه میدهد. نیازی به کلید یا ثبتنام نیست و از هر زبانی قابل فراخوانی است:

```bash
curl -s localhost:8080/api/v1/health
curl -s 'localhost:8080/api/v1/tickers?tf=h2&limit=10'
curl -s localhost:8080/api/v1/ticker/BTCUSDT
curl -s 'localhost:8080/api/v1/overview?tf=h6'
```

- **راهنمای تعاملی:** آدرس اصلی را بگیرید و `/api` به آن اضافه کنید (مثلاً `http://IP:8080/api`). در آن صفحه هر درخواست را با دکمه «اجرا» امتحان میکنید.
- **مرجع کامل و مثالها:** فایل `docs/API.md` کنار برنامه یا [همین فایل در ریپازیتوری](docs/API.md).
- اندپوینتها: `/health`، `/meta`، `/symbols`، `/tickers`، `/ticker/{symbol}`، `/overview` (زیر `/api/v1`).
- سرور از لحظه بالا آمدن در پسزمینه دادهها را تازه نگه میدارد و تمام کاربران از **یک snapshot مشترک** میخوانند: قیمت ۱۵ ثانیه، کندل ۳ دقیقه. با دامنه و nginx، آدرس API همان دامنه شماست (`https://domain/api/v1`).
- صفحه اصلی وقتی از همین سرور سرو شود، از API محلی میخواند و از طریق `/api/v1/stream` بصورت زنده بروز میشود؛ نیازی به رفرش دستی نیست. nginx برای جریان زنده بدون بافر تنظیم میشود.

روی Alpine به‌جای `systemctl` از `rc-service binance-screener status|restart` استفاده کنید.

---

## ۸) به‌روزرسانی

**همان دستور نصب را دوباره بزنید.** تنظیمات فعلی (پورت، دامنه، مسیر) از `/etc/binance-screener.install` خوانده می‌شود:

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | bash
```

قبل از جایگزینی، از نسخه‌ی فعلی در `$DIR/.previous` بکاپ گرفته می‌شود و **اگر نسخه‌ی جدید بالا نیاید، نسخه‌ی قبلی خودکار برمی‌گردد**. یعنی به‌روزرسانی نمی‌تواند سایت را زمین بزند.

---

## ۹) حذف کامل

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | bash -s -- --uninstall
```

سرویس، فایل‌ها، کاربر سرویس و کانفیگ nginx پاک می‌شوند. گواهی SSL در certbot می‌ماند و دستور حذفش چاپ می‌شود.

---

## ۱۰) روی سرور چه ساخته می‌شود

| مسیر | چیست |
|---|---|
| `/opt/binance-futures-screener/` | برنامه (`index.html` + `server.py` + `api.py` + `api.html`) |
| `/opt/binance-futures-screener/docs/API.md` | مرجع کامل API |
| `/etc/systemd/system/binance-screener.service` | یونیت سرویس (روی Alpine: `/etc/init.d/binance-screener`) |
| `/etc/binance-screener.install` | تنظیمات نصب، برای به‌روزرسانی بعدی |
| `/etc/nginx/conf.d/binance-screener.conf` | فقط وقتی دامنه بدهید؛ روی Alpine `http.d` و روی سرورهای پنلداری مثل CyberPanel طبق بخش ۴.۱ دستی در `sites-enabled` |
| `/var/log/binance-screener-install.log` | لاگ کامل نصب |
| `/usr/local/bin/binance-screener` | دستور منو (لینک `bfs` هم ساخته می‌شود) |
| `/usr/local/lib/binance-screener/install.sh` | کپی نصب‌کننده که منو اجرا می‌کند |

سرویس با کاربر بدون دسترسی (`bfscreener`) اجرا می‌شود و سخت‌سازی systemd دارد: `NoNewPrivileges`، `ProtectSystem=strict`، `PrivateTmp`، محدودیت syscall و فقط اجازه‌ی bind به پورت‌های پایین.

---

## ۱۱) عیب‌یابی سریع

| نشانه | علت | راه‌حل |
|---|---|---|
| `command not found: curl` | سیستم حداقلی | `apt install -y curl` یا `apk add curl` |
| `Permission denied` | root نیستید و sudo هم نیست | با `root` وارد شوید یا `sudo` را نصب کنید |
| صفحه باز نمی‌شود | فایروال ابری | پورت را در Security Group باز کنید |
| `502 Bad Gateway` (با nginx) | سرویس بالا نیست | `systemctl status binance-screener` |
| لیست کوین‌ها خالی است | محدودیت منطقه‌ای بایننس (`451`) | سرور را از منطقه‌ی دیگر بگیرید |
| گواهی SSL گرفته نشد | DNS آماده نیست یا پورت ۸۰ بسته است | DNS و پورت ۸۰ را چک کنید و دوباره اجرا کنید |
| سایت با دامنه بالا نمیآید ولی سرویس سالم است | nginx پنل فقط `sites-enabled` را میخواند | طبق بخش ۴.۱ vhost دستی بسازید |
| صفحه باز است ولی بروزرسانی زنده نمیشود | `/api/v1/stream` توسط nginx بافر شده | `proxy_buffering off` و `X-Accel-Buffering` را طبق بخش ۴.۱ اضافه کنید |
| پورت اشغال است | سرویس دیگر روی ۸۰۸۰ | `--port 9000` بدهید یا خودکار انتخاب می‌شود |
| `binance-screener: command not found` | نصب قدیمی، قبل از نسخه‌ی منو | یک بار دستور نصب را دوباره اجرا کنید |

برای دیدن اینکه اسکریپت **قرار است** چه کاری بکند، بدون اینکه چیزی را تغییر دهد:

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | bash -s -- --dry-run
```

---

## ۱۲) نسخه‌ی Docker (اگر Docker را ترجیح می‌دهید)

```bash
git clone https://github.com/NigaByte031/binance-futures-screener.git
cd binance-futures-screener
docker compose up -d
```

سایت روی `http://SERVER_IP:8080` بالا می‌آید. برای تغییر پورت، `docker-compose.yml` را ویرایش کنید.

---

## ۱۳) چک‌لیست نهایی

- [ ] دستور نصب را زدید و پیام «✔ نصب کامل شد» را دیدید
- [ ] آدرسی که چاپ شد در مرورگر باز می‌شود و لیست کوین‌ها پر است
- [ ] پورت لازم در فایروال ابری (Security Group) باز است
- [ ] سرویس در بوت فعال است (`systemctl is-enabled binance-screener` → `enabled`)
- [ ] `curl -s localhost:8080/api/v1/meta` پاسخ `ok: true` میدهد
- [ ] `binance-screener` منو را باز می‌کند و گزینه‌ی `0` آن را می‌بندد
- [ ] (اختیاری) دامنه وصل است و HTTPS کار می‌کند
- [ ] (اختیاری) `/healthz` جواب `ok` می‌دهد
- [ ] (اختیاری) `curl -N https://DOMAIN/api/v1/stream` رویداد `event: snapshot` نشان میدهد
- [ ] (اختیاری) روی سرور پنلداری، vhost در `sites-enabled` است نه فقط `conf.d`

اگر همه‌ی موارد بالا تیک خورد، نصب کامل و تمیز است.
