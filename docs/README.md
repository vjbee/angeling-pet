# คู่มือ Angeling Pet

**Angeling** คือเพ็ตลอยบนเดสก์ท็อป macOS ที่:
- **ช่วยตั้งเตือน:** บันทึกลงปฏิทิน และเตือนด้วยเสียง Level Up ของ Ragnarok เมื่อถึงเวลา
- **บอกจำนวนข้อความ LINE** ที่ยังไม่อ่าน
- **บอกจำนวนข้อความ Discord** ที่ยังไม่อ่าน (DM และ @mention)
- **บอก limit การใช้งาน Claude** รายสัปดาห์และ 5 ชั่วโมง (เปิดในเมนู)
- **รายงานงานของ Claude Code** ว่าแต่ละ session กำลังทำอะไร อันไหนรอคุณ อันไหนเสร็จแล้ว คลิกเพื่อไปที่ session นั้นได้ (ไม่มี Claude Code ก็ใช้ฟีเจอร์อื่นได้)

ติดตั้งด้วยคำสั่งเดียว (วางใน Terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/mobbenxd/angeling-pet/main/get.sh | bash
```

> **ติดตั้งครั้งแรก?** ดู[การติดตั้ง](Installation.md) ใช้เวลาไม่ถึง 1 นาที

## สารบัญ

### เริ่มต้น
| หน้า | อ่านเมื่อ |
|---|---|
| [ความต้องการของระบบ](Requirements.md) | ก่อนติดตั้ง: เช็คว่าเครื่องพร้อม |
| [การติดตั้ง](Installation.md) | ติดตั้งทีละขั้น พร้อมวิธีเช็คว่าสำเร็จ |
| [เริ่มใช้งานครั้งแรก](First-Run.md) | ติดตั้งเสร็จแล้ว ลองให้ Angeling รายงานงานแรก |

### ใช้งาน
| หน้า | อ่านเมื่อ |
|---|---|
| [วิธีใช้งาน](Usage.md) | คลิก ลาก ซ่อน เมนู และคีย์ลัด |
| [บับเบิลกิจกรรมและสถานะ](Activity-Bubble.md) | อยากรู้ว่าแต่ละแถว สี และไอคอนหมายถึงอะไร |
| [ตั้งเตือน](Reminders.md) | อยากให้ Angeling เตือนนัดหรืองาน พร้อมบันทึกลงปฏิทิน |
| [แจ้งเตือน Discord](Discord-Notifications.md) | อยากรู้ว่ามี DM ใน Discord ที่ยังไม่อ่านกี่ข้อความ |
| [แจ้งเตือน LINE](LINE-Notifications.md) | อยากให้แสดงข้อความ LINE ที่ยังไม่อ่าน |
| [Limit การใช้งาน Claude](Usage-Limits.md) | อยากรู้ว่าใช้ limit สัปดาห์และ 5 ชั่วโมงไปเท่าไร |
| [Emote และท่าทาง](Emotes-and-Animations.md) | อยากรู้ว่า Angeling ทำท่าไหนเมื่อไร |
| [เปลี่ยนเป็นเพ็ตตัวอื่น](Custom-Pet.md) | อยากใช้ sprite ของเพ็ต Codex ตัวอื่น |

### ดูแลรักษา
| หน้า | อ่านเมื่อ |
|---|---|
| [แก้ปัญหา](Troubleshooting.md) | Angeling ไม่ขึ้น งานค้าง คลิกแล้วไม่ไป ฯลฯ |
| [อัปเดตและถอนการติดตั้ง](Updating-and-Uninstalling.md) | ดึงเวอร์ชันใหม่ หรือเอาออกจากเครื่อง |

### สำหรับนักพัฒนา
| หน้า | อ่านเมื่อ |
|---|---|
| [หลักการทำงาน](How-It-Works.md) | อยากรู้ว่า hook, ไฟล์ state และแอปคุยกันอย่างไร |
| [การพัฒนาและร่วมพัฒนา](Development.md) | build เอง ทดสอบ และเปิด PR |

## ลิงก์
- Repository: <https://github.com/mobbenxd/angeling-pet>
- แจ้งปัญหา: <https://github.com/mobbenxd/angeling-pet/issues>

---
คู่มือนี้อยู่ใน `docs/` ของ repo แก้ไขผ่าน Pull Request · โค้ดใช้ MIT License · ภาพ Angeling © Gravity Co., Ltd. ไม่ได้รวมอยู่ใน repo
