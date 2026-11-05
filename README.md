# اسکرینر فیوچرز بایننس

صفحه‌ی وب سبک برای دیدن **همه‌ی کوین‌های فیوچرز USDT-M بایننس**، مرتب‌شده از بیشترین ریزش تا بیشترین رشد، در بازه‌های **۲ / ۶ / ۱۲ / ۲۴ ساعته**.

![پیش‌نمایش](docs/preview.png)

---

## نصب با یک دستور

روی سرور (Ubuntu / Debian / CentOS / Rocky / Alma / Fedora / Arch / Alpine) فقط همین یک خط را بزنید:

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | sudo bash
```

اسکریپت موقع نصب این‌ها را می‌پرسد:

| پرسش | پیش‌فرض | توضیح |
|---|---|---|
| پورت سرویس | `8080` | پورتی که برنامه روی آن اجرا می‌شود |
| دامنه | خالی | اگر خالی بمانید، با `http://IP:PORT` باز می‌شود |
| نصب nginx | بله (اگر دامنه بدهید) | ریورس‌پروکسی روی پورت ۸۰ |
| گواهی SSL | بله (اگر دامنه بدهید) | Let's Encrypt رایگان + ریدایرکت به https |
| باز کردن فایروال | بله (اگر ufw/firewalld فعال باشد) | پورت‌های لازم باز می‌شوند |

بعد از نصب، سرویس به‌صورت خودکار بالا می‌آید، در بوت ثبت می‌شود و آدرس نهایی در ترمینال چاپ می‌شود.

### نصب بدون پرسش (غیرتعاملی)

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh \
  | sudo bash -s -- --port 9000 --domain screener.example.com --ssl --email you@example.com --yes
```

### گزینه‌های اسکریپت

```text
--port <n>        پورت سرویس (پیش‌فرض 8080)
--domain <d>      دامنه، مثلاً screener.example.com
--dir <path>      مسیر نصب (پیش‌فرض /opt/binance-futures-screener)
--nginx / --no-nginx
--ssl / --no-ssl
--email <mail>    ایمیل برای Let's Encrypt
--yes, -y         بدون پرسش
--uninstall       حذف کامل نصب
-h, --help        راهنما
```

### حذف

```bash
curl -fsSL https://raw.githubusercontent.com/NigaByte031/binance-futures-screener/main/install.sh | sudo bash -s -- --uninstall
```

---

## نصب با Docker

```bash
git clone https://github.com/NigaByte031/binance-futures-screener.git
cd binance-futures-screener

# پورت را در docker-compose.yml عوض کنید
docker compose up -d
```

یا بدون compose:

```bash
docker build -t binance-screener .
docker run -d --name binance-screener -p 8080:8080 --restart unless-stopped binance-screener
```

---

## اجرای دستی (بدون نصب)

فقط `python3` لازم است:

```bash
git clone https://github.com/NigaByte031/binance-futures-screener.git
cd binance-futures-screener
python3 server.py --port 8080
```

یا حتی ساده‌تر: فایل `index.html` را مستقیم در مرورگر باز کنید — به هیچ سروری نیاز ندارد.

---

## امکانات صفحه

- **چهار تب**: ۲ / ۶ / ۱۲ / ۲۴ ساعته — با کلیک روی هدر هر ستون ترتیب برعکس می‌شود
- **مرتب‌سازی پیش‌فرض**: از بیشترین ریزش تا بیشترین رشد
- هر ردیف هم‌زمان هر چهار بازه را نشان می‌دهد و ستون فعال هایلایت می‌شود
- کارت‌های خلاصه: تعداد نماد، تعداد صعودی/نزولی، بیشترین ریزش و بیشترین رشد
- جستجوی نماد + فیلتر حداقل حجم ۲۴ ساعته (برای حذف کوین‌های کم‌عمق)
- اسپارک‌لاین ۲۴ ساعته برای هر نماد
- کلیک روی هر ردیف → صفحه‌ی فیوچرز همان کوین در بایننس
- به‌روزرسانی خودکار: قیمت هر ۱۵ ثانیه، کندل‌ها هر ۵ دقیقه
- تنظیمات: آدرس API، رنگ‌بندی (سبز=رشد یا قرمز=رشد)، تعداد درخواست همزمان
- فونت وزیرمتن، راست‌به‌چپ، تم تیره، ریسپانسیو

---

## داده‌ها از کجا می‌آید

همه‌چیز مستقیم از API فیوچرز بایننس و از داخل مرورگر گرفته می‌شود:

| کار | اندپوینت |
|---|---|
| لیست قراردادها | `GET /fapi/v1/exchangeInfo` (فیلتر `PERPETUAL` + `TRADING` + `USDT`) |
| قیمت و حجم ۲۴س | `GET /fapi/v1/ticker/24hr` |
| کندل‌ها | `GET /fapi/v1/klines?interval=15m&limit=97` برای هر نماد |

تغییر ۲/۶/۱۲ ساعته از قیمت مرجع همان لحظه (کندل ۱۵ دقیقه‌ای) حساب می‌شود و تغییر ۲۴ ساعته از خود API خوانده می‌شود.

### نکته‌ی مهم درباره‌ی محدودیت منطقه‌ای

آدرس رسمی `fapi.binance.com` در بعضی کشورها (از جمله ایران) کد **۴۵۱** برمی‌گرداند. به همین دلیل برنامه اول سراغ `www.binance.com/fapi/v1` می‌رود که همان API است و هدر `Access-Control-Allow-Origin: *` هم دارد، و اگر آن هم جواب نداد به‌ترتیب `fapi`، `fapi1`، `fapi2` و `fapi3` را امتحان می‌کند. آدرس سالم در `localStorage` ذخیره می‌شود.

اگر سرورتان پشت پروکسی است، از **تنظیمات** صفحه می‌توانید آدرس API دلخواه وارد کنید.

---

## ساختار پروژه

```text
.
├── index.html      # کل برنامه (HTML + CSS + JS، بدون وابستگی)
├── server.py       # وب‌سرور استاتیک کوچک، فقط با کتابخانه‌ی استاندارد پایتون
├── install.sh      # نصب‌کننده‌ی تعاملی (systemd + nginx + SSL)
├── Dockerfile
├── docker-compose.yml
└── docs/preview.png
```

---

## مدیریت سرویس (نصب با اسکریپت)

```bash
systemctl status binance-screener     # وضعیت
systemctl restart binance-screener    # ری‌استارت
journalctl -u binance-screener -f     # لاگ زنده
curl -s localhost:8080/healthz        # هلث‌چک
```

---

## هشدار

این ابزار فقط داده‌ی عمومی بازار را نمایش می‌دهد و **توصیه‌ی مالی یا معاملاتی نیست**. هیچ کلید API یا اطلاعات حساب لازم ندارد و هیچ سفارشی ارسال نمی‌کند.

## لایسنس

MIT — فایل [LICENSE](LICENSE) را ببینید.
