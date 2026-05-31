# dns-mirror-helper

ابزاری مبتنی بر Bash برای سیستم‌های Ubuntu که مدیریت DNS و انتخاب مخزن‌های APT را از طریق یک منوی تعاملی ساده فراهم می‌کند.

---

## قابلیت‌ها

### مدیریت DNS

* **حالت نت آزاد (FREE)** — هدایت درخواست‌های DNS از طریق dnscrypt-proxy و DoH (DNS over HTTPS) برای عبور از محدودیت‌های DNS محلی
* **حالت نت ملی (MELLI)** — تست خودکار فهرست DNSهای داخلی و انتخاب سریع‌ترین DNS در دسترس
* **حالت Auto** — ابتدا FREE را امتحان می‌کند و در صورت عدم دسترسی به اینترنت بین‌الملل، به‌صورت خودکار به MELLI تغییر می‌کند
* **ورود دستی DNS** — امکان وارد کردن DNSهای دلخواه به‌صورت لیست جداشده با کاما همراه با اعتبارسنجی آدرس‌ها
* **بازنشانی ایمن DNS** — راه‌اندازی مجدد سرویس‌های DNS و پاک‌سازی کش
* **تست اتصال** — بررسی عملکرد DNS و دسترسی HTTPS

### مدیریت Mirror

* تست سرعت و تأخیر (Latency) مخازن Ubuntu داخل ایران و خارج از ایران
* نمایش نتایج رتبه‌بندی‌شده و امکان انتخاب دستی در مدت ۱۰ ثانیه
* انتخاب خودکار بهترین Mirror در صورت عدم انتخاب کاربر
* پشتیبانی از هر دو فرمت:

  * `sources.list`
  * `ubuntu.sources` (DEB822)
* تهیه نسخه پشتیبان قبل از هرگونه تغییر
* مدیریت نسخه‌های پشتیبان و امکان بازگردانی آن‌ها

---

## پیش‌نیازها

* Ubuntu (تست‌شده روی نسخه‌های 20.04، 22.04 و 24.04)
* Bash نسخه 4.3 یا بالاتر
* ابزارهای:

  * curl
  * dig (بسته dnsutils)
  * systemd-resolved
* دسترسی Root یا sudo
* dnscrypt-proxy (در صورت نیاز به‌صورت خودکار نصب می‌شود)

---

## نصب

### اجرای مستقیم

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alighaffari3000/DNS-Mirror-Helper/main/dns-mirror-helper.sh)
```

### دانلود و اجرای دستی

```bash
curl -fsSL https://raw.githubusercontent.com/alighaffari3000/DNS-Mirror-Helper/main/dns-mirror-helper.sh -o dns-mirror-helper.sh
chmod +x dns-mirror-helper.sh
sudo ./dns-mirror-helper.sh
```

---

## نحوه استفاده

اسکریپت را با دسترسی sudo اجرا کنید:

```bash
sudo ./dns-mirror-helper.sh
```

منوی اصلی:

```text
  DNS & Mirror Helper
=====================================
  1) DNS Manager
  2) Mirror Manager
  0) Exit
```

---

## بخش DNS Manager

```text
  1) Switch to FREE mode (DoH)
  2) Switch to MELLI mode (Auto DNS select)
  3) Auto-select best mode
  4) Manual DNS entry
  5) Safe reset DNS services
  6) Run connectivity tests
  0) Back
```

### مثال ورود دستی DNS

```text
DNS addresses: 1.1.1.1, 8.8.8.8, 9.9.9.9
[VALID] 1.1.1.1
[VALID] 8.8.8.8
[VALID] 9.9.9.9
```

---

## بخش Mirror Manager

```text
  1) Iran mirrors only
  2) International mirrors only
  3) Iran + International
  4) Manage backups
  0) Back
```

پس از تست مخازن، نتایج به‌ترتیب بهترین عملکرد نمایش داده می‌شوند:

```text
Results (sorted by speed/latency):
  1) https://mirror.arvancloud.ir/ubuntu
     Latency: 11ms | Speed: 9200 KB/s | Score: 17
```

کاربر می‌تواند:

* شماره Mirror موردنظر را وارد کند.
* کلید Enter را برای انتخاب خودکار فشار دهد.
* یا ۱۰ ثانیه صبر کند تا بهترین گزینه به‌صورت خودکار انتخاب شود.

---

## توضیح حالت‌های DNS

| حالت   | روش                                       | مناسب برای                                |
| ------ | ----------------------------------------- | ----------------------------------------- |
| FREE   | استفاده از DoH از طریق dnscrypt-proxy     | زمانی که دسترسی بین‌الملل برقرار است      |
| MELLI  | استفاده مستقیم از DNSهای از پیش تعریف‌شده | زمانی که DoH مسدود یا غیرقابل استفاده است |
| Manual | DNSهای دلخواه کاربر                       | زمانی که DNS مشخصی مدنظر دارید            |
| Auto   | انتخاب خودکار بهترین حالت                 | زمانی که از وضعیت شبکه مطمئن نیستید       |

---

## شخصی‌سازی

### تغییر DNSهای حالت MELLI

آرایه `IR_DNS_LIST` را در ابتدای اسکریپت ویرایش کنید.

### تغییر Mirrorها

آرایه‌های زیر را ویرایش کنید:

```bash
IR_MIRRORS
GLOBAL_MIRRORS
```

خطوطی که با `#` شروع شوند به‌عنوان توضیح در نظر گرفته شده و نادیده گرفته می‌شوند.

### تنظیمات dnscrypt-proxy

فایل زیر توسط اسکریپت تولید می‌شود:

```text
/etc/dnscrypt-proxy/dnscrypt-proxy.toml
```

به‌صورت پیش‌فرض از Resolverهای Cloudflare، Google و Quad9 استفاده می‌شود.

برای تغییر این رفتار، تابع `write_default_config()` را در اسکریپت ویرایش کنید.

---

## بازگردانی نسخه پشتیبان

نمونه بازگردانی دستی:

```bash
sudo cp /etc/apt/sources.list.bak.2024-01-15-143022 /etc/apt/sources.list
sudo apt update
```

همچنین می‌توانید از مسیر زیر استفاده کنید:

```text
Mirror Manager → Manage backups
```

---

## فایل‌های تغییر داده شده

| مسیر                                                  | توضیح                             |
| ----------------------------------------------------- | --------------------------------- |
| `/etc/systemd/resolved.conf.d/dns-mirror-helper.conf` | تنظیمات DNS برای systemd-resolved |
| `/etc/resolv.conf`                                    | لینک به فایل مناسب resolved       |
| `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`             | تنظیمات dnscrypt-proxy            |
| `/etc/apt/sources.list`                               | تنظیمات Mirror در سیستم‌های قدیمی |
| `/etc/apt/sources.list.d/ubuntu.sources`              | تنظیمات Mirror در سیستم‌های جدید  |
| `/etc/apt/sources.list.bak.*`                         | نسخه‌های پشتیبان خودکار           |

---

## مجوز

MIT
