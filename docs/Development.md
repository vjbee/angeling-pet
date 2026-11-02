# การพัฒนาและร่วมพัฒนา

## โครงสร้าง repo

| Path | คืออะไร |
|---|---|
| `src/main.swift` | ตัวแอปทั้งหมด |
| `hooks/angeling-hook.sh` | hook ของ Claude Code |
| `scripts/build.sh` | build `.app` |
| `scripts/fetch-assets.sh` | ดึง sprite และ emote |
| `install.sh`, `uninstall.sh` | ติดตั้งและถอนการติดตั้ง |
| `get.sh` | ตัวติดตั้งแบบคำสั่งเดียว (ดาวน์โหลด `Angeling.zip` จาก Release ล่าสุด) |
| `scripts/package.sh` | สร้างไฟล์สำหรับ Release |
| `docs/` | คู่มือนี้ |

## Build และรัน

```bash
./scripts/build.sh                   # → ~/Applications/Angeling.app
pkill -x Angeling; open ~/Applications/Angeling.app
```

แก้ hook แล้วต้องคัดลอกไปวางที่เดิม:

```bash
cp hooks/angeling-hook.sh ~/.claude/angeling-pet/hook.sh
```

## ทดสอบหน้าตาโดยไม่ต้องจับภาพจอ

```bash
ANGELING_SNAPSHOT=/tmp/a.png ~/Applications/Angeling.app/Contents/MacOS/Angeling
```

| ตัวแปร | ผล |
|---|---|
| `ANGELING_EXPANDED=1` | แบบขยาย (ไม่ใส่ = แบบย่อ ไม่ว่าจะเลือกอะไรไว้) |
| `ANGELING_LIMITS=62,40` | จำลอง limit สัปดาห์,5 ชม. (`71` = มีแค่สัปดาห์, `none` = บัญชีไม่มีข้อมูล, `wait` = ยังไม่มีข้อมูล) และเปิดการแสดง limit |
| `ANGELING_LIMIT_MODE=left` | แสดง limit เป็น % ที่เหลือ |
| `ANGELING_LIMIT_PLACE=both` | ที่แสดง limit (`auto`, `both`, `bar`) |
| `ANGELING_HIDE_ACTIVITY=1` | ซ่อนบับเบิล (เห็นป้ายตัวเลข) |
| `ANGELING_HOVER=1` | แสดงปุ่มซ่อนหรือแสดง |
| `ANGELING_EMOTE=lv` | บังคับให้แสดง emote |
| `ANGELING_LINE_UNREAD=5` | จำลองจำนวน LINE ที่ยังไม่อ่าน |
| `ANGELING_DISCORD_UNREAD=4` | จำลองจำนวน Discord ที่ยังไม่อ่าน |
| `ANGELING_FAKE_VERSION=1.0.0` | ทำเหมือนแอปเป็นเวอร์ชันนี้ (และเช็คอัปเดตทันทีตอน snapshot) |
| `ANGELING_LATEST_VERSION=9.9.9` | ทำเหมือน GitHub มีเวอร์ชันนี้ (ไม่ต่อเน็ต) |
| `ANGELING_UPDATE_NOW=1` | เริ่มอัปเดตทันทีที่เปิดแอป |
| `ANGELING_UPDATE_CMD="…"` | คำสั่งที่ใช้แทน `get.sh` ตอนอัปเดต |
| `ANGELING_REMINDERS=/path.json` | ใช้ไฟล์การเตือนจำลอง (snapshot จะไม่ส่งเสียง) |
| `ANGELING_FORM=1` | จับภาพหน้าต่างตั้งเตือนแทนตัว Angeling |
| `ANGELING_CHARACTER=thunder` | ใช้ตัวละครนี้ (`angeling`, `id` ของเพ็ตใน `pets/` หรือ `id` ใน `characters.json`) |
| `ANGELING_ANIM=failed` | เล่นท่านี้ (`idle`, `running`, `review`, `waiting`, `failed`, `waving`, `jumping`, `running-left`, `running-right`) |
| `ANGELING_THEME=dark` | ใช้ธีมนี้ (`classic`, `light`, `dark`, `glass`, `tokyo`, `ragnarok`, `auto`) |
| `ANGELING_STATE_DIR=/path` | อ่านไฟล์ session จำลองจากโฟลเดอร์นี้แทนของจริง |

## ทดสอบ hook

```bash
printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"test","cwd":"/tmp/demo","prompt":"ลองดู"}' \
  | bash hooks/angeling-hook.sh
cat ~/.claude/angeling-pet/state/test.json
rm ~/.claude/angeling-pet/state/test.json
```

## ออก Release

ผู้ใช้ทั่วไปติดตั้งจาก Release ล่าสุด จึงต้องออก Release ใหม่ทุกครั้งที่อยากให้คนอื่นได้ของใหม่

```bash
git switch main && git pull
./scripts/package.sh 1.2.3                       # → dist/
gh release create v1.2.3 dist/* --title "Angeling 1.2.3" --notes "…"
```

`dist/` มี:

| ไฟล์ | ใช้ทำอะไร |
|---|---|
| `Angeling.zip` | ชุดติดตั้งที่ `get.sh` ดาวน์โหลด: แอป universal (Apple silicon + Intel) ภาพ เสียง และสคริปต์ |
| `spritesheet.webp`, `emote-*.gif`, `levelup.mp3`, `characters.zip`, `pets.zip` | ภาพและเสียงแยกไฟล์ สำหรับคนที่ติดตั้งจาก git clone |

`package.sh` ต้องมี `assets/characters/` และ `assets/pets/` ก่อน ถ้ายังไม่มีให้สร้างจากไฟล์ต้นฉบับ:

```bash
python3 -I scripts/import-characters.py ~/Downloads/bomber-all-18-characters.zip
```

```bash
swift scripts/import-pet.swift ~/Downloads/huskey.png bee-husky "Bee Husky"
```

ทุก Release ต้องแนบไฟล์ครบทุกตัว เพราะ `get.sh` และ `fetch-assets.sh` ดึงจาก `releases/latest`

ทดสอบตัวติดตั้งกับไฟล์ในเครื่อง โดยไม่ยุ่งกับการติดตั้งจริง:

```bash
env -i HOME=/tmp/fakehome PATH=/usr/bin:/bin:/usr/sbin:/sbin ANGELING_NO_LAUNCH=1 \
  ANGELING_BUNDLE_URL="file://$PWD/dist/Angeling.zip" bash get.sh --no-login
```

(คำสั่งนี้จะปิด Angeling ตัวจริงที่เปิดอยู่ด้วย ทดสอบเสร็จแล้วต้องเปิดใหม่)

| ตัวแปร | ผล |
|---|---|
| `ANGELING_BUNDLE_URL` | ที่อยู่ของ `Angeling.zip` สำหรับ `get.sh` |
| `ANGELING_RELEASE_URL` | ที่อยู่ของไฟล์ภาพและเสียงสำหรับ `fetch-assets.sh` |
| `ANGELING_NO_LAUNCH=1` | ติดตั้งโดยไม่เปิดแอป |

## ร่วมพัฒนา

`main` ถูกป้องกันไว้ ต้องแก้ผ่าน Pull Request เท่านั้น

1. Fork repo (หรือสร้าง branch ถ้ามีสิทธิ์)
2. `git switch -c feat/<ชื่อ>`
3. แก้โค้ด แล้วทดสอบด้วย snapshot
4. เปิด PR เข้า `main` พร้อมบอกว่าทดสอบอะไรไปแล้ว

## แก้คู่มือ

คู่มืออยู่ใน `docs/` ให้แก้แล้วเปิด PR เหมือนโค้ด ลิงก์ระหว่างหน้าให้ใช้ชื่อไฟล์แบบมี `.md` เช่น `[การติดตั้ง](Installation.md)` และถ้าเพิ่มหน้าใหม่ ให้เพิ่มลิงก์ใน `docs/README.md` ด้วย

---
[← สารบัญคู่มือ](README.md)
