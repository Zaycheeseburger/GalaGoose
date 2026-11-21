# -*- coding: utf-8 -*-
"""
Generate professional PDF Game Manual for GALAGOOSE (Space Shooter on Nexys A7 FPGA)
"""
import os
import base64
import subprocess
import shutil

ROOT_DIR = r"D:\vivado_pj\Space_Shooter"
DOC_DIR = os.path.join(ROOT_DIR, "doc")
PLANS_DIR = os.path.join(ROOT_DIR, ".agents", "plans")
os.makedirs(DOC_DIR, exist_ok=True)
os.makedirs(PLANS_DIR, exist_ok=True)

def get_base64_img(rel_path):
    full_path = os.path.join(ROOT_DIR, rel_path)
    if os.path.exists(full_path):
        ext = os.path.splitext(rel_path)[1].lower()
        mime = "image/jpeg" if ext in [".jpg", ".jpeg"] else "image/png"
        with open(full_path, "rb") as f:
            data = base64.b64encode(f.read()).decode("utf-8")
            return f"data:{mime};base64,{data}"
    return ""

img_sprites = get_base64_img(r"mem\sprite_preview.png")
img_boss = get_base64_img(r"sim_work\boss_compare_new.png")
img_board = get_base64_img(r"Space_shooter_source\NexysA7.jpg")

html_content = f"""<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="UTF-8">
<title>GALAGOOSE - Game Manual & Specification</title>
<style>
    @import url('https://fonts.googleapis.com/css2?family=Kanit:wght@400;600;700&family=Sarabun:ital,wght@0,300;0,400;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;700&display=swap');

    @page {{
        size: A4;
        margin: 12mm 12mm 12mm 12mm;
    }}

    * {{
        box-sizing: border-box;
        -webkit-print-color-adjust: exact !important;
        print-color-adjust: exact !important;
    }}

    body {{
        font-family: 'Sarabun', 'Segoe UI', Tahoma, sans-serif;
        font-size: 13.5px;
        line-height: 1.55;
        color: #1e293b;
        background: #ffffff;
        margin: 0;
        padding: 0;
    }}

    h1, h2, h3, h4 {{
        font-family: 'Kanit', sans-serif;
        color: #0f172a;
        margin-top: 0;
    }}

    .header-banner {{
        background: linear-gradient(135deg, #0b1120 0%, #1e1b4b 50%, #311042 100%);
        color: #ffffff;
        padding: 24px 28px;
        border-radius: 12px;
        margin-bottom: 20px;
        box-shadow: 0 4px 14px rgba(0,0,0,0.15);
        border: 1px solid #3730a3;
    }}

    .header-title {{
        font-size: 28px;
        font-weight: 700;
        letter-spacing: 1.5px;
        color: #facc15;
        margin-bottom: 4px;
        text-shadow: 0 2px 8px rgba(250, 204, 21, 0.4);
    }}

    .header-subtitle {{
        font-size: 15px;
        color: #cbd5e1;
        font-weight: 400;
    }}

    .header-meta {{
        margin-top: 12px;
        display: flex;
        gap: 12px;
        font-size: 11.5px;
    }}

    .badge {{
        display: inline-block;
        padding: 3px 10px;
        border-radius: 6px;
        font-weight: 600;
        font-size: 11.5px;
        letter-spacing: 0.5px;
    }}

    .badge-primary {{ background: #4338ca; color: #ffffff; }}
    .badge-gold {{ background: #b45309; color: #ffffff; }}
    .badge-cyan {{ background: #0891b2; color: #ffffff; }}
    .badge-green {{ background: #15803d; color: #ffffff; }}
    .badge-red {{ background: #b91c1c; color: #ffffff; }}

    .card {{
        background: #f8fafc;
        border: 1px solid #e2e8f0;
        border-radius: 10px;
        padding: 16px 18px;
        margin-bottom: 18px;
        page-break-inside: avoid;
    }}

    .card-title {{
        font-size: 17px;
        font-weight: 600;
        color: #1e3a8a;
        border-bottom: 2px solid #cbd5e1;
        padding-bottom: 6px;
        margin-bottom: 12px;
        display: flex;
        align-items: center;
        gap: 8px;
    }}

    table {{
        width: 100%;
        border-collapse: collapse;
        margin: 10px 0;
        font-size: 12.5px;
    }}

    th, td {{
        border: 1px solid #cbd5e1;
        padding: 7px 10px;
        text-align: left;
    }}

    th {{
        background: #f1f5f9;
        color: #0f172a;
        font-weight: 600;
        font-family: 'Kanit', sans-serif;
    }}

    tr:nth-child(even) {{
        background: #ffffff;
    }}

    tr:nth-child(odd) {{
        background: #f8fafc;
    }}

    .key {{
        display: inline-block;
        background: #0f172a;
        color: #38bdf8;
        font-family: 'JetBrains Mono', monospace;
        font-weight: 700;
        padding: 2px 7px;
        border-radius: 4px;
        font-size: 11.5px;
        border: 1px solid #334155;
    }}

    .sw {{
        display: inline-block;
        background: #374151;
        color: #facc15;
        font-family: 'JetBrains Mono', monospace;
        font-weight: 700;
        padding: 2px 7px;
        border-radius: 4px;
        font-size: 11.5px;
    }}

    .grid-2 {{
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 14px;
    }}

    .grid-3 {{
        display: grid;
        grid-template-columns: 1fr 1fr 1fr;
        gap: 12px;
    }}

    .callout {{
        border-left: 4px solid #3b82f6;
        background: #eff6ff;
        padding: 10px 14px;
        border-radius: 0 8px 8px 0;
        margin: 10px 0;
        font-size: 12.5px;
    }}

    .callout-warning {{
        border-left-color: #ef4444;
        background: #fef2f2;
    }}

    .callout-success {{
        border-left-color: #10b981;
        background: #ecfdf5;
    }}

    .img-box {{
        text-align: center;
        background: #0b1120;
        padding: 10px;
        border-radius: 8px;
        margin: 10px 0;
    }}

    .img-box img {{
        max-width: 100%;
        border-radius: 6px;
        display: block;
        margin: 0 auto;
    }}

    .caption {{
        font-size: 11px;
        color: #94a3b8;
        margin-top: 6px;
        text-align: center;
    }}

    .page-break {{
        page-break-before: always;
    }}

    .evolution-box {{
        background: #ffffff;
        border: 1px solid #cbd5e1;
        border-radius: 8px;
        padding: 10px;
        text-align: center;
    }}

    .evo-title {{
        font-family: 'Kanit', sans-serif;
        font-weight: 600;
        font-size: 13.5px;
        margin-bottom: 4px;
    }}
</style>
</head>
<body>

<!-- PAGE 1: OVERVIEW & CORE MECHANICS -->
<div class="header-banner">
    <div class="header-title">GALAGOOSE: FPGA SPACE SHOOTER</div>
    <div class="header-subtitle">คู่มือการเล่น สถาปัตยกรรมระบบควบคุมฮาร์ดแวร์ และกฎเกณฑ์กลไกเกมฉบับสมบูรณ์</div>
    <div class="header-meta">
        <span class="badge badge-primary">Hardware: Digilent Nexys A7-100T</span>
        <span class="badge badge-gold">Video: 640x480 @ 60Hz VGA (RGB444)</span>
        <span class="badge badge-cyan">Audio: PWM Mono Chiptune</span>
        <span class="badge badge-green">Version: 2.4 Final Release</span>
    </div>
</div>

<div class="card">
    <div class="card-title">1. กฎการเล่นและเป้าหมายของเกม (Game Rules & Objectives)</div>
    <p><b>GALAGOOSE</b> คือเกมยานยิงอวกาศสไตล์ Galaga Arcade สุดคลาสสิกที่ทำงานด้วยลอจิกฮาร์ดแวร์ Verilog/SystemVerilog 100% บน FPGA Xilinx Artix-7 โดยผู้เล่นจะบังคับยาน "ห่านอวกาศ" (Galagoose) ต่อสู้กับฝูงศัตรูในกาแล็กซีเพื่อปกป้องจักรวาล</p>
    <ul>
        <li><b>พลังชีวิต (Player Lives):</b> เริ่มต้นที่ <b>3 ชีวิต</b> (แสดงผลเป็นไอคอนหัวใจบนแถบ HUD ด้านบนขวา) เมื่อโดนกระสุนศัตรูหรือชนศัตรู ชีวิตจะลดลงครั้งละ 1 และมียานกะพริบอมตะชั่วคราว (Invulnerability) 1.5 วินาที</li>
        <li><b>การควบคุมขอบเขต:</b> ยานห่านสามารถเคลื่อนที่ได้ 4 ทิศทางอย่างอิสระภายในพิกัดฉาก <code>X: 16–592</code> และ <code>Y: 72–440</code></li>
        <li><b>เงื่อนไขชัยชนะ (VICTORY):</b> เคลียร์ศัตรู Wave 1 ถึง Wave 3 และพิชิต Last Boss (อาจารย์เจษฎา - AJV) ใน Wave 4 สำเร็จ เข้าสู่หน้าจอ Victory พร้อมเพลงสรรเสริญชัยชนะ</li>
        <li><b>เงื่อนไขพ่ายแพ้ (GAME OVER):</b> พลังชีวิตหมดลงเหลือ 0 หรือผู้เล่นสับสวิตช์ยอมแพ้ <span class="sw">SW[15]</span></li>
    </ul>

    <table>
        <thead>
            <tr>
                <th style="width: 15%;">ด่าน (Wave)</th>
                <th style="width: 25%;">ศัตรูที่เผชิญหน้า</th>
                <th style="width: 60%;">รูปแบบและยุทธวิธีของศัตรู</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td><b>Wave 1</b></td>
                <td>Pf (16 ตัว)</td>
                <td>บินจัดขบวนปีกนกด้านบน เคลื่อนที่แบบขบวนแกว่งไกว (Formation Sway) ยิงกระสุนเล็งต่ำเป็นระยะ</td>
            </tr>
            <tr>
                <td><b>Wave 2</b></td>
                <td>Ppuen (16 ตัว)</td>
                <td>ความเร็วการบินสูงขึ้น เริ่มมีศัตรูบินโฉบแบบดิ่งลงมา (Dive Attack) และยิงกระสุนสวนทิศทาง</td>
            </tr>
            <tr>
                <td><b>Wave 3</b></td>
                <td>Ppeem & Pping (16 ตัว)</td>
                <td>บินแยกขบวนและโฉบลงมาคู่ด้วยความเร็วสูง รัวกระสุนถี่และบีบให้ผู้เล่นต้องหลบตลอดเวลา</td>
            </tr>
            <tr>
                <td><b>Wave 4</b></td>
                <td><b>Last Boss (AJV)</b> + การ์ด 2 ตัว</td>
                <td>บอสใหญ่ประจำเกม มี 2 เฟสการต่อสู้ (ร่างปกติ และ ร่างคลั่ง Enraged AJV2 ตาเลเซอร์สีแดง)</td>
            </tr>
        </tbody>
    </table>
</div>

<div class="card">
    <div class="card-title">2. ระบบพัฒนาร่างห่าน 3 ขั้น (Goose Evolution Mechanics)</div>
    <p>ผู้เล่นสามารถเก็บลูกแก้ววิวัฒนาการที่ดรอปในฉากเพื่ออัปเกรดขีดความสามารถของยานห่านได้ 3 ขั้น:</p>
    
    <div class="grid-3">
        <div class="evolution-box" style="border-top: 4px solid #64748b;">
            <div class="evo-title" style="color: #334155;">ร่าง 1: ห่านขาว (White Goose)</div>
            <div style="font-size: 11.5px; color: #64748b; margin-bottom: 6px;">[Form 0 - ร่างพื้นฐาน]</div>
            <p style="margin: 0; font-size: 12px;">ยิงกระสุนปืนคู่ธรรมดา 1 นัด/ชุด<br>Cooldown: <b>12 เฟรม</b> (~5 นัด/วินาที)<br><i>เป็นร่างถาวร ไม่จำกัดเวลา</i></p>
        </div>
        <div class="evolution-box" style="border-top: 4px solid #0284c7;">
            <div class="evo-title" style="color: #0284c7;">ร่าง 2: ห่านฟ้า (Blue Goose)</div>
            <div style="font-size: 11.5px; color: #0284c7; margin-bottom: 6px;">[Form 1 - พลาสมาคู่ทรงพลัง]</div>
            <p style="margin: 0; font-size: 12px;">ยิงหอกพลาสมาคู่สีฟ้า พลังทำลายสูง<br>Cooldown: <b>8 เฟรม</b> (~7.5 นัด/วินาที)<br><i>ระยะเวลากลายร่าง: <b>9 วินาที</b></i></p>
        </div>
        <div class="evolution-box" style="border-top: 4px solid #d946ef;">
            <div class="evo-title" style="color: #a21caf;">ร่าง 3: ห่านรุ้ง (Rainbow Goose)</div>
            <div style="font-size: 11.5px; color: #a21caf; margin-bottom: 6px;">[Form 2 - อัลติเมต 8 ทิศทาง]</div>
            <p style="margin: 0; font-size: 12px;">ยิงกระจายรอบทิศ 8 แฉก 180° ครอบคลุมจอ<br>Cooldown: <b>5 เฟรม</b> (~12 นัด/วินาที)<br><i>ระยะเวลากลายร่าง: <b>9 วินาที</b></i></p>
        </div>
    </div>

    <div class="callout callout-success" style="margin-top: 12px;">
        <b>กลไกตัวจับเวลา 9 วินาที (Evolution Countdown):</b> เมื่ออยู่ในร่างห่านฟ้าหรือห่านรุ้ง จะมีเวลานับถอยหลัง <code>EVO TIME: 9S...1S</code> หากเวลาหมดจะลดระดับคืนกลับสู่ร่างก่อนหน้า แต่หากเก็บลูกแก้วขั้นถัดไปได้ทัน เวลาจะถูกรีเซ็ตเต็ม 9 วินาทีใหม่ทันที!
    </div>
</div>

<!-- PAGE 2: HARDWARE CONTROLS & ITEM RULES -->
<div class="page-break"></div>

<div class="card">
    <div class="card-title">3. การควบคุมด้วยส่วนประกอบบนบอร์ด Nexys A7 (Hardware Controls)</div>
    <p>ระบบเกมรองรับอินพุตหลายช่องทาง และมีระบบความปลอดภัยตัดสัญญาณรบกวนอัตโนมัติ:</p>

    <table>
        <thead>
            <tr>
                <th style="width: 25%;">ช่องทางควบคุม</th>
                <th style="width: 35%;">การเชื่อมต่อ / สวิตช์เปิดใช้งาน</th>
                <th style="width: 40%;">ฟังก์ชันการควบคุม</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td><b>Push Buttons<br>(ปุ่มกดบนบอร์ด)</b></td>
                <td>ใช้งานเมื่อ <span class="sw">SW[5] = OFF</span></td>
                <td>
                    <span class="key">BTNU</span> : บินขึ้น (Up)<br>
                    <span class="key">BTND</span> : บินลง (Down)<br>
                    <span class="key">BTNL</span> : เลี้ยวซ้าย (Left) / เลื่อนเลือกโหมดในเมนู<br>
                    <span class="key">BTNR</span> : เลี้ยวขวา (Right) / เลื่อนเลือกโหมดในเมนู<br>
                    <span class="key">BTNC</span> : ยิงกระสุน (Fire) / ยืนยันเริ่มเกม (Start Game)
                </td>
            </tr>
            <tr>
                <td><b>USB / PS/2 Keyboard<br>(คีย์บอร์ดภายนอก)</b></td>
                <td>สับสวิตช์ <span class="sw">SW[5] = ON</span><br>(Keyboard-Only Mode)</td>
                <td>
                    <span class="key">W</span> : บินขึ้น (Up)<br>
                    <span class="key">S</span> : บินลง (Down)<br>
                    <span class="key">A</span> : เลี้ยวซ้าย (Left) / เลื่อนเมนู<br>
                    <span class="key">D</span> : เลี้ยวขวา (Right) / เลื่อนเมนู<br>
                    <span class="key">Enter</span> / <span class="key">Space</span> : ยิงกระสุน / เริ่มเกม
                </td>
            </tr>
            <tr>
                <td><b>Tilt Accelerometer<br>(เซนเซอร์เอียง ADXL362)</b></td>
                <td>สับสวิตช์ <span class="sw">SW[2] = ON</span><br>(และ <span class="sw">SW[5] = OFF</span>)</td>
                <td>เอียงบอร์ด Nexys A7 ไปข้างหน้า/หลัง/ซ้าย/ขวา เพื่อควบคุมการบินลอยตามแรงโน้มถ่วงแบบอะนาล็อก</td>
            </tr>
            <tr>
                <td><b>Autofire Mode</b></td>
                <td>สับสวิตช์ <span class="sw">SW[0] = ON</span></td>
                <td>เปิดระบบยิงกระสุนรัวอัตโนมัติ ผู้เล่นเพียงแค่บังคับทิศทางโดยไม่ต้องกดปุ่มยิงย้ำๆ</td>
            </tr>
            <tr>
                <td><b>Surrender Switch</b></td>
                <td>สับสวิตช์ <span class="sw">SW[15] = ON</span></td>
                <td>ยอมแพ้และสิ้นสุดเกม เข้าสู่หน้าจอ Game Over ทันที</td>
            </tr>
        </tbody>
    </table>

    <div class="callout callout-warning">
        <b>ระบบ Keyboard-Only Exclusive Interlock:</b> ทันทีที่เปิดสวิตช์ <span class="sw">SW[5] = ON</span> วงจรฮาร์ดแวร์จะตัดสัญญาณปุ่มกด <code>BTNU, BTND, BTNL, BTNR, BTNC</code> และเซนเซอร์เอียงทั้งหมดออกจากการประมวลผลทันที เพื่อป้องกันการกดชนกันและการดริฟต์ของเซนเซอร์
    </div>

    <h4>การแสดงผลผ่าน LED Bar และ 7-Segment Display</h4>
    <ul>
        <li><b>16-LED Bar (LED[15:0]):</b>
            <ul>
                <li><i>ใน Wave 1–3:</i> แสดงตำแหน่งและสถานะของศัตรูแต่ละตัวที่ยังมีชีวิตอยู่ในขบวน</li>
                <li><i>ใน Wave 4 (Boss Fight):</i> แปลงเป็น <b>Boss HP Gauge 16 ขีด</b> แสดงแถบเลือดของบอสแบบเรียลไทม์ (หลอดไฟจะค่อยๆ ดับลงตาม HP บอส)</li>
            </ul>
        </li>
        <li><b>7-Segment Display:</b> แสดงผลคะแนนสะสม 6 หลัก (Decimal BCD) หรือแสดงรหัส Scan Code ในโหมด Debug คีย์บอร์ด</li>
    </ul>
</div>

<div class="card">
    <div class="card-title">4. กฎและจังหวะเวลาการปล่อยไอเทม (Item Drop Rules & Timing)</div>
    <div class="grid-2">
        <div>
            <h4 style="color: #0369a1; margin-bottom: 6px;">ก. กฎในด่านปกติ (Wave 1 – 3)</h4>
            <ul>
                <li>ดรอปตามลำดับขั้นบันไดของห่านอย่างเคร่งครัด:
                    <ul>
                        <li><b>ห่านขาว</b> $\rightarrow$ ดรอป <b>ลูกแก้วฟ้า (Type 0)</b></li>
                        <li><b>ห่านฟ้า</b> $\rightarrow$ ดรอป <b>ลูกแก้วรุ้ง (Type 1)</b></li>
                        <li><b>ห่านรุ้ง</b> $\rightarrow$ ดรอป <b>หัวใจฟื้นเลือด (Type 2)</b></li>
                    </ul>
                </li>
                <li><b>การันตีการดรอป:</b> ตัวที่ตายตัวที่ 2 ใน Wave 1 ปล่อยลูกแก้วฟ้า และตัวที่ 2 ใน Wave 2 ปล่อยลูกแก้วรุ้ง</li>
            </ul>
        </div>
        <div>
            <h4 style="color: #b91c1c; margin-bottom: 6px;">ข. กฎในด่าน Last Boss (Wave 4)</h4>
            <ul>
                <li><b>ใช้กฎขั้นบันไดเดียวกัน:</b> ห่านขาวได้ลูกแก้วฟ้า, ห่านฟ้าได้ลูกแก้วรุ้ง, ห่านรุ้งได้หัวใจ (ไม่มีการข้ามขั้น)</li>
                <li><b>การันตีปล่อยลูกแก้วรุ้งทันใน 9 วินาที:</b> เมื่อเก็บลูกแก้วฟ้า บอสจะถูกรีเซ็ตเวลาดรอปเหลือ <b>2.5 วินาที</b> เพื่อปล่อยลูกแก้วรุ้งตกลงมาทันที ทำให้มีเวลาเก็บอีกกว่า 4-5 วินาทีก่อนหมดเวลา 9 วินาที</li>
                <li><b>ความถี่การดรอป:</b> ห่านขาวดรอปทุก 4.0s, ห่านรุ้งดรอปหัวใจทุก 5.0s, และหากพลาดลูกแก้วรุ้งจะดรอปซ้ำทุก 3.0s</li>
                <li><b>Milestone Drops:</b> ดรอปหัวใจทันทีเมื่อบอส HP เหลือ 50% และ 25%</li>
            </ul>
        </div>
    </div>
</div>

<!-- PAGE 3: NORMAL VS HARD MODE & GRAPHICS -->
<div class="page-break"></div>

<div class="card">
    <div class="card-title">5. การเปรียบเทียบความแตกต่าง: โหมด Normal vs Hard</div>
    <p>ผู้เล่นสามารถเลือกโหมดความยากได้ที่หน้า Title Screen (กดปุ่มซ้าย/ขวา หรือ A/D บนคีย์บอร์ด) หรือสับสวิตช์ <span class="sw">SW[1] = ON</span> เพื่อบังคับเป็นโหมด Hard ทันที โดยมีความแตกต่างเชิงลึกดังตาราง:</p>

    <table>
        <thead>
            <tr>
                <th style="width: 25%;">พารามิเตอร์ของระบบ</th>
                <th style="width: 25%;">โหมดปกติ (NORMAL MODE)</th>
                <th style="width: 25%;">โหมดท้าทาย (HARD MODE)</th>
                <th style="width: 25%;">ผลกระทบต่อการเล่น</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td><b>Boss Max HP</b></td>
                <td><b style="color: #0284c7;">90 หน่วย</b></td>
                <td><b style="color: #b91c1c;">120 หน่วย (+33%)</b></td>
                <td>การต่อสู้ยาวนานขึ้น ต้องเน้นเก็บร่างรุ้งเพื่อทำดาเมจสูง</td>
            </tr>
            <tr>
                <td><b>ความเร็วการบินของบอส</b></td>
                <td>3 พิกเซล / เฟรม</td>
                <td><b>4 พิกเซล / เฟรม</b></td>
                <td>บอสบินโฉบซ้ายขวารวดเร็วขึ้น หลบวิถีกระสุนได้เก่งขึ้น</td>
            </tr>
            <tr>
                <td><b>การหลบหลีกฉับพลัน (Feint Weave)</b></td>
                <td>สุ่มเลี้ยวเมื่อ LFSR[8:0] == 9'h155 (ความถี่ต่ำ)</td>
                <td>สุ่มเลี้ยวเมื่อ LFSR[7:0] == 8'hA5 (ถี่ขึ้น 2 เท่า)</td>
                <td>ทิศทางการบินคาดเดายากขึ้น มีจังหวะหลอกล่อกะทันหัน</td>
            </tr>
            <tr>
                <td><b>อัตราการยิงบอส Phase 1<br>(ร่างปกติ ajv)</b></td>
                <td>หน่วงเวลา <b>60 เฟรม</b><br>(1.00 วินาที / ชุด)</td>
                <td>หน่วงเวลา <b>45 เฟรม</b><br>(0.75 วินาที / ชุด)</td>
                <td>กระสุนศัตรูในเฟสแรกมาถี่ขึ้น 25%</td>
            </tr>
            <tr>
                <td><b>อัตราการยิงบอส Phase 2<br>(ร่างคลั่ง ajv2 เลเซอร์)</b></td>
                <td>หน่วงเวลา <b>18 เฟรม</b><br>(0.30 วินาที / ชุด)</td>
                <td>หน่วงเวลา <b>14 เฟรม</b><br>(0.23 วินาที / ชุด)</td>
                <td>สภาพห่ากระสุน (Bullet Hell) หนาแน่นและรัวเร็วที่สุด</td>
            </tr>
            <tr>
                <td><b>จำนวนกระสุนบอสต่อชุด<br>(Salvo Bullet Count)</b></td>
                <td>Phase 1: 4 นัด<br>Phase 2: 7 นัด</td>
                <td>Phase 1: <b>5 นัด (+25%)</b><br>Phase 2: <b>8 นัด (+14%)</b></td>
                <td>มุมการกระจายของกระสุนกว้างขึ้น หลบยากขึ้นอย่างเห็นได้ชัด</td>
            </tr>
            <tr>
                <td><b>ความเร็วศัตรูทั่วไป (Wave 1–3)</b></td>
                <td>บินปกติ 3 พิกเซล/เฟรม</td>
                <td>ความเร็วโฉบและกระสุนเพิ่มขึ้น</td>
                <td>เพิ่มความตื่นเต้นตั้งแต่ต้นเกม</td>
            </tr>
            <tr>
                <td><b>สเกล LED Boss HP Gauge</b></td>
                <td>6 HP ต่อ 1 หลอด LED</td>
                <td>7.5 HP ต่อ 1 หลอด LED</td>
                <td>คำนวณและเกลี่ยลง 16 หลอด LED อัตโนมัติ</td>
            </tr>
        </tbody>
    </table>
</div>

<div class="card">
    <div class="card-title">6. สไปรต์กราฟิกของบอสสองเฟส (AJV Phase 1 & Phase 2)</div>
    <p>Last Boss ประจำ Wave 4 มีการเปลี่ยนร่างตามระดับพลังชีวิตอย่างชัดเจน:</p>
    
    <div class="grid-2">
        <div style="text-align: center; background: #0f172a; padding: 12px; border-radius: 8px;">
            <div style="color: #93c5fd; font-weight: 600; margin-bottom: 6px;">PHASE 1: ร่างปกติ (AJV)</div>
            <p style="color: #cbd5e1; font-size: 11.5px; margin: 0;">ใช้รูป <code>ajv</code> หน้าปกติ ยิงกระสุนจังหวะช้ากว่า (หน่วงเวลา 45-60 เฟรม) ให้ผู้เล่นมีโอกาสตั้งตัวและเก็บลูกแก้วพัฒนา</p>
        </div>
        <div style="text-align: center; background: #2a0808; padding: 12px; border-radius: 8px; border: 1px solid #dc2626;">
            <div style="color: #f87171; font-weight: 600; margin-bottom: 6px;">PHASE 2: ร่างคลั่ง (Enraged AJV2)</div>
            <p style="color: #fca5a5; font-size: 11.5px; margin: 0;">เมื่อ HP ≤ 50% จะสลับเป็นรูป <code>ajv2</code> ตาเลเซอร์สีแดง ขอบคมชัดไม่แหว่ง พร้อมกระหน่ำยิงรัวเร็วกระจายรอบทิศทาง</p>
        </div>
    </div>

    <div class="img-box" style="margin-top: 14px;">
        <img src="{img_sprites}" alt="Sprite Sheet Preview" style="max-height: 220px;">
        <div class="caption">ภาพจำลองสไปรต์ 4-bit VGA: ห่าน 3 ร่าง, ศัตรูทั่วไป 4 รุ่น, Last Boss AJV (Phase 1 & 2), และ Galaga FX</div>
    </div>
</div>

<div style="text-align: center; font-size: 11px; color: #64748b; margin-top: 16px;">
    เอกสารข้อกำหนดและการทำงานของระบบเกม GALAGOOSE — ภาควิชาวิศวกรรมคอมพิวเตอร์ คณะวิศวกรรมศาสตร์
</div>

</body>
</html>
"""

html_path = os.path.join(DOC_DIR, "Galagoose_Game_Manual.html")
with open(html_path, "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"Generated HTML manual at: {html_path}")

# Generate PDF using headless Chrome
chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
pdf_target_doc = os.path.join(DOC_DIR, "Galagoose_Game_Manual.pdf")
pdf_target_plans = os.path.join(PLANS_DIR, "Galagoose_Game_Manual.pdf")

file_url = f"file:///{html_path.replace(os.sep, '/')}"
cmd = [
    chrome_path,
    "--headless=new",
    "--disable-gpu",
    f"--print-to-pdf={pdf_target_doc}",
    file_url
]

print("Running Chrome to generate PDF...")
proc = subprocess.run(cmd, capture_output=True, text=True)
if os.path.exists(pdf_target_doc):
    size = os.path.getsize(pdf_target_doc)
    print(f"Successfully generated PDF: {pdf_target_doc} (Size: {size} bytes)")
    # Copy to plans directory as well
    shutil.copyfile(pdf_target_doc, pdf_target_plans)
    print(f"Copied to plans directory: {pdf_target_plans}")
else:
    print(f"Failed to generate PDF. Return code: {proc.returncode}")
    print(f"Stdout: {proc.stdout}")
    print(f"Stderr: {proc.stderr}")
