# Binance Futures Screener — API

نسخه ۲.۵.۰ یک API عمومی، فقط-خواندنی (read-only) و بدون نیاز به کلید ارائه میکند تا هر کسی بتواند دادههای اسکرینر را در برنامه، اسکریپت یا داشبورد خود استفاده کند.

> **آدرس این نصب:** `http://SERVER:8080/api/v1` — درخواستها را دقیقاً به همین آدرس بزنید.
> **راهنمای تعاملی:** `http://SERVER:8080/api` — هر اندپوینت را با دکمه «اجرا» امتحان میکند.
>
> هنگام نصب، اسکریپت این دو آدرس را **بهطور خودکار** با دامنهای که وارد کردید (یا IP و پورت سرور) جایگزین میکند. پس نسخهای که روی سرور نصب میشود، همیشه آدرس درست همان سرور را نشان میدهد.

- **آدرس پایه:** `http://SERVER:8080/api/v1`
- **راهنمای تعاملی:** `http://SERVER:8080/api` — همان صفحهای که با دکمه «اجرا» درخواستها را امتحان میکند.
- **روشها:** فقط `GET` و `OPTIONS`
- **احراز هویت:** ندارد
- **CORS:** `Access-Control-Allow-Origin: *` — از مرورگر هم قابل فراخوانی است.
- **قالب:** JSON با فیلد ثابت `ok`.

> **نسخه ۲.۵ و بعد از آن:** روی سرور نصبشده صفحه اصلی از همان API سرور میخواند (`/api/v1/tickers`) و بروزرسانیها را از `/api/v1/stream` میگیرد؛ بنابراین صفحه و API همیشه همان snapshot را نشان میدهند. مسیر مستقیم بایننس فقط روی GitHub Pages استفاده میشود، جایی که سروری برای میزبانی API وجود ندارد.

---

## قالب پاسخ

همه پاسخها — موفق و ناموفق — یک ساختار دارند. `meta.generation` هر بار که دیتای سرور واقعاً تغییر کند زیاد میشود و `meta.last_update` زمان همان تغییر است:

```json
{
  "ok": true,
  "data": [ ... ],
  "meta": {
    "version": "2.6.0",
    "generated_at": "2026-11-19T13:05:00Z",
    "source": "binance-usdt-m-futures",
    "upstream": "https://www.binance.com/fapi/v1",
    "generation": 803,
    "last_update": 1795603892.88
  }
}
```

در خطا، بهجای `data` فیلد `error` میآید:

```json
{
  "ok": false,
  "error": {
    "code": "INVALID_PARAM",
    "message": "tf must be one of: h2, h6, h12, h24"
  }
}
```

---

## اندپوینتها

### `GET /api/v1/health`

سلامت سرویس و وضعیت کش. مناسب مانیتورینگ.

از نسخه ۲.۶ فیلد `upstream_health` هم اضافه شده است. `stale` وقتی `true` میشود که سرور نتوانسته در ۶۰ ثانیه اخیر به بایننس دسترسی پیدا کند؛ `consecutive_failures` تعداد دفعات شکست پیاپی و `last_error` آخرین پیام خطاست. همان فیلدها در `meta` تمام پاسخها هم موجودند.

```bash
curl -s http://localhost:8080/api/v1/health
```

پاسخ:
```json
{
  "ok": true,
  "data": {
    "status": "ok",
    "version": "2.6.0",
    "upstream": "https://www.binance.com/fapi/v1",
    "upstream_health": {
      "status": "ok",
      "stale": false,
      "last_success": 1795603892.88,
      "age_seconds": 3.2,
      "consecutive_failures": 0,
      "last_error": null
    },
    "cache": {
      "symbols": { "age_seconds": 12.4, "ttl_seconds": 600 },
      "tickers": { "age_seconds": 3.1, "ttl_seconds": 15 },
      "klines": { "symbols_cached": 522, "age_seconds": 22.7, "ttl_seconds": 180 },
      "rows": { "age_seconds": 1.2, "ttl_seconds": 5 }
    }
  },
  "meta": { ... }
}
```

---

### `GET /api/v1/meta`

نسخه، بازههای زمانی، فیلدهای مرتبسازی و محدودیتها.

```bash
curl -s http://localhost:8080/api/v1/meta
```

---

### `GET /api/v1/symbols`

لیست نمادهای پپچوال USDT-M فعال. سبکترین اندپوینت — بدون کندل و محاسبه.

```bash
curl -s http://localhost:8080/api/v1/symbols
```

```json
{
  "ok": true,
  "data": [
    { "symbol": "BTCUSDT", "base": "BTC" },
    { "symbol": "ETHUSDT", "base": "ETH" }
  ],
  "meta": { "count": 522, ... }
}
```

---

### `GET /api/v1/tickers`

اندپوینت اصلی: تمام کوینها با چهار بازه زمانی، قابل فیلتر، مرتبسازی و صفحهبندی.

| پارامتر | پیشفرض | توضیح |
|---|---|---|
| `tf` | `h2` | بازه مرتبسازی: `h2`, `h6`, `h12`, `h24` |
| `sort` | `pct` | `pct`, `symbol`, `price`, `vol`, `base` |
| `dir` | `desc` | `asc` یا `desc` |
| `q` | — | جستجو در نماد یا ارز پایه (مثلاً `btc`) |
| `minVol` | `0` | حداقل حجم ۲۴ ساعته به USDT |
| `limit` | `100` | تعداد ردیف (۱–۵۰۰) |
| `offset` | `0` | شروع صفحهبندی |
| `spark` | `0` | `1` = اضافه کردن اسپارکلاین ۲۴ ساعته |
| `force` | `0` | `1` = نادیده گرفتن کش و گرفتن قیمتهای تازه از بایننس |

```bash
# ۱۰ کوین با بیشترین ریزش ۲ ساعته
curl -s 'http://localhost:8080/api/v1/tickers?tf=h2&sort=pct&dir=asc&limit=10'

# جستجوی بیتکوین با حجم بالای ۱۰ میلیون و اسپارکلاین
curl -s 'http://localhost:8080/api/v1/tickers?q=btc&minVol=10000000&spark=1'

# صفحه دوم، مرتب بر حجم
curl -s 'http://localhost:8080/api/v1/tickers?sort=vol&limit=100&offset=100'
```

پاسخ:
```json
{
  "ok": true,
  "data": [{
    "symbol": "BTCUSDT",
    "base": "BTC",
    "price": 67312.5,
    "change": -1.234,
    "pct": { "h2": -1.234, "h6": 0.82, "h12": 2.1, "h24": -0.45 },
    "vol": 1284567890.25,
    "spark": [67000, 67120, 66980]
  }],
  "meta": {
    "timeframe": "h2", "sort": "pct", "dir": "desc",
    "total": 522, "returned": 1, "limit": 100, "offset": 0,
    "filters": { "q": null, "minVol": null },
    "cache": { ... }
  }
}
```

`change` همان مقدار `pct[tf]` است و راحتتر استفاده میشود. `spark` فقط وقتی میآید که `spark=1` بدهید.

---

### `GET /api/v1/ticker/{symbol}`

تمام چهار بازه بهعلاوه اسپارکلاین. حروف بزرگ/کوچک فرقی ندارد.

```bash
curl -s http://localhost:8080/api/v1/ticker/BTCUSDT
curl -s http://localhost:8080/api/v1/ticker/btcusdt   # همان نتیجه
```

```json
{
  "ok": true,
  "data": {
    "symbol": "BTCUSDT",
    "base": "BTC",
    "quote": "USDT",
    "price": 67312.5,
    "pct": { "h2": -1.234, "h6": 0.82, "h12": 2.1, "h24": -0.45 },
    "vol": 1284567890.25,
    "spark": [67000, 67120, 66980]
  },
  "meta": { ... }
}
```

---

### `GET /api/v1/overview`

خلاصه بازار: تعداد صعودی/نزولی، میانگین تغییر، سهم بازار، حجم کل و بهترین/بدترین کوین. پارامتر اختیاری `tf`.

```bash
curl -s 'http://localhost:8080/api/v1/overview?tf=h6'
```

```json
{
  "ok": true,
  "data": {
    "timeframe": "h6",
    "total": 522,
    "with_change": 520,
    "up": 314,
    "down": 197,
    "flat": 9,
    "unchanged": 9,
    "breadth": 61.45,
    "average_change": 0.1233,
    "total_quote_volume": 128456789012.5,
    "top_gainer": { "symbol": "XYZUSDT", "base": "XYZ", "price": 0.12, "change": 28.4 },
    "top_loser": { "symbol": "ABCUSDT", "base": "ABC", "price": 0.04, "change": -31.2 }
  },
  "meta": { ... }
}
```

`breadth` درصد نمادهای صعودی از مجموع صعودی＋نزولی است (نمادهای بدون تغییر حذف میشوند).

---

### `GET /api/v1/stream`

جریان زنده Server-Sent Events. سرور دادهها را در پسزمینه تازه نگه میدارد و **همین لحظه که تغییر کنند**، همان snapshot را برای همه کلاینتهای متصل میفرستد — نیازی به polling نیست.

```bash
curl -N http://SERVER:8080/api/v1/stream
```

دو نوع رویداد:

```
event: snapshot          # بلافاصله بعد از اتصال، وضعیت فعلی
data: {"data":[...],"meta":{...}}

event: update            # هر بار که دیتای سرور عوض شود
data: {"data":[...],"meta":{...}}
```

پیام `: ping` هر ۱۵ ثانیه برای زنده نگه داشتن اتصال میآید. دقیقاً همان آرایهای که `/api/v1/tickers` برمیگرداند در `data` قرار دارد، پس نمایش صفحه و پاسخ API همیشه یکسانند.

> صفحه اصلی هم از همین مسیر میخواند: وقتی از سرور نصبشده سرو شود، ابتدا `/api/v1/meta` را امتحان میکند، سپس ردیفها را از `/api/v1/tickers` میگیرد و از `/api/v1/stream` بروزرسانی زنده دریافت میکند. روی GitHub Pages که APIای وجود ندارد، به مسیر مستقیم بایننس برمیگردد.

### پشت nginx

اگر از ریورسپروکسی nginx استفاده میکنید، مسیر استریم را حتماً بدون بافر تنظیم کنید وگرنه رویدادها با تأخیر میرسند:

```nginx
location /api/v1/stream {
    proxy_pass http://127.0.0.1:18080;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 3600s;
    add_header X-Accel-Buffering no;
}
```

---

## کدهای خطا

| کد | HTTP | علت |
|---|---|---|
| `INVALID_PARAM` | 400 | پارامتر نامعتبر یا خارج از محدوده |
| `INVALID_SYMBOL` | 400 | نام نماد بدفرمت |
| `SYMBOL_NOT_FOUND` | 404 | نماد وجود ندارد یا غیرفعال است |
| `NOT_FOUND` | 404 | آدرس API وجود ندارد |
| `UPSTREAM_ERROR` | 502 | بایننس در دسترس نیست یا منطقه مسدود است |
| `INTERNAL_ERROR` | 500 | خطای داخلی؛ جزئیات در لاگ سرویس (`journalctl -u binance-screener`) |

---

## نحوه محاسبه

- نمادها از `exchangeInfo` گرفته میشوند و فقط مواردی که `contractType=PERPETUAL`, `status=TRADING` و `quoteAsset=USDT` باشند نگه داشته میشوند.
- تغییرات ۲/۶/۱۲ ساعته از کندل بسته ۱۵ دقیقه متناظر محاسبه میشود:
  `idx = 97 - 1 - round(hours / 0.25)` و `pct = (price / close[idx] - 1) × 100`.
- تغییر ۲۴ ساعته مستقیماً از `priceChangePercent` بایننس است.
- حجم همان `quoteVolume` بایننس است.

---

## کش و تازگی

| داده | TTL |
|---|---|
| لیست نمادها | ۱۰ دقیقه |
| قیمت و حجم (`ticker/24hr`) | ۱۵ ثانیه |
| کندلهای ۱۵ دقیقه | ۳ دقیقه |
| ردیفهای آماده | ۵ ثانیه |

تمام کلاینتها از **یک snapshot مشترک** روی سرور استفاده میکنند. یعنی ۱۰۰ کاربر همزمان تنها **یک** اسکن از بایننس ایجاد میکند، نه ۱۰۰ اسکن. سرور از لحظه بالا آمدن در پسزمینه دادهها را تازه نگه میدارد و نیازی ندارد کسی صفحه را باز کند تا شروع به کار کند. هر تغییری بلافاصله از طریق `/api/v1/stream` به صفحههای باز هم میرسد.

TTL کندلها عمداً ۳ دقیقه است چون یک اسکن کامل ~۵۰۰ نماد ممکن است ۱–۲ دقیقه طول بکشد؛ اگر TTL کوتاهتر بود، قدیمیترین کندلها همان موقع تمام اسکن منقضی میشدند و هر درخواست اسکن تازهای را آغاز میکرد.

### مانیتورینگ ساده

برای مطمئن شدن اینکه سرویس زنده و داده تازه است، کافی است دو عدد را مقایسه کنید:

```bash
curl -s https://DOMAIN/api/v1/meta | python3 -c "import json,sys,time; m=json.load(sys.stdin)['meta']; print('generation=',m['generation'],'age_seconds=',round(time.time()-m['last_update']))"
```

`generation` باید هر چند ثانیه یک بار بالا برود و `age_seconds` معمولاً زیر ۱۰ ثانیه است. اگر generation ثابت ماند و age رشد کرد، لاگ سرویس را ببینید:

```bash
journalctl -u binance-screener -n 50 --no-pager
```

---

## تنظیمات سرور (اختیاری)

| متغیر محیطی | پیشفرض | توضیح |
|---|---|---|
| `BFS_BINANCE_BASE` | `https://www.binance.com/fapi/v1` | آدرس جایگزین upstream (برای شبکههای محدودشده) |
| `BFS_API_TIMEOUT` | `15` | timeout هر درخواست به بایننس (ثانیه) |
| `BFS_API_RETRIES` | `2` | تعداد تلاش مجدد برای خطاهای موقت شبکه و پاسخ ۵xx (۰ تا ۵) |
| `BFS_API_CONCURRENCY` | `20` | تعداد worker برای گرفتن کندلها (۱–۴۰) |

برای تنظیم، یونیت سرویس را ویرایش و `Environment=...` اضافه کنید، سپس:

```bash
systemctl daemon-reload && systemctl restart binance-screener
```
