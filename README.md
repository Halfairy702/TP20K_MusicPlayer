# TP20K 音乐播放器 · Tang Primer 20K

基于 Sipeed Tang Primer 20K（GW2A-LV18PG256C8/I7）+ Dock 的纯 FPGA 音乐播放器。
没有 CPU、没有软件——乐曲调度、DDS 合成、PT8211 串行发送全部是硬件逻辑。

板载 **PT8211 DAC → LPA4809 功放 → 3.5mm 耳机口 J10**，插上耳机就能听，不需要额外买任何模块。

---

## 1. 当前功能

| 功能 | 说明 |
|------|------|
| 两首曲子 | 小星星 / 欢乐颂，循环播放 |
| 合成方式 | 24 位相位累加器 DDS + 256×16 正弦波表 |
| 输出 | PT8211，BCK 1.5 MHz，采样率 **46875 Hz** |
| 按键 | S2 切歌，S3 播放/暂停 |
| 指示灯 | LED4 播放时慢闪，暂停时常亮 |

---

## 2. 操作

| 按键 | 位置 | 功能 |
|------|------|------|
| **S1** | 板上 | 复位（低有效，兼 FPGA_RST） |
| **S2** | 板上 | 下一首 |
| **S3** | 板上 | 播放 / 暂停 |
| **LED4** | 板上 | 播放中闪烁 |

> ⚠️ **SW1 拨码必须保持在 ON**：它接 RECONFIG_N，拉低会导致无法配置。
> 开机时 S1 会被复位监控芯片拉低，这是正常的。

---

## 3. 音频链路参数

```
27 MHz (H11)
   │
   ├─ ÷18 ──────────► BCK  = 1.5 MHz   (N15)
   │                    │
   │                    └─ ÷32 ──► WS = 46875 Hz 帧率 (P16)
   │
   └─ DDS 24 bit ──► 正弦波表 ──► 16 bit ──► DIN (P15)
                                              PA_EN (R16) = 常高
```

采样率 = 27,000,000 ÷ 18 ÷ 32 = **46,875 Hz**

> 官方 demo 用 rPLL 把 27 MHz 倍到 6 MHz 再 ÷4 得到 1.536 MHz。
> 本工程直接从 27 MHz 整数分频，省掉 PLL，采样率 46.875 kHz 对 PT8211 完全够用。

**PT8211 是 16 位 LSB-justified（"日本格式"），不是标准 I2S。**
数据在 BCK 上升沿更新、MSB 先行、WS 边沿偏移 3 个 BCK——与厂商已验证的驱动保持一致。

---

## 4. 引脚

| 信号 | 管脚 | 电压域 |
|------|------|--------|
| clk (27 MHz) | H11 | 3.3 V |
| rst_n (S1) | T10 | 3.3 V |
| key_next (S2) | T3 | **1.5 V** |
| key_play (S3) | T2 | **1.5 V** |
| hp_bck | N15 | 3.3 V |
| hp_ws | P16 | 3.3 V |
| hp_din | P15 | 3.3 V |
| pa_en | R16 | 3.3 V |
| led (LED4) | L14 | 3.3 V |

> S2–S5 在 1.5 V 的 Bank 4 上，约束必须写 `LVCMOS15`，写错会导致输入失效。

---

## 5. 编译

工程必须放在**纯英文路径**下。Gowin 命令行不认中文路径，会报
`Corrupted project file: C:/Users/???/...`。

```powershell
cd C:\gowin_work\TP20K_MusicPlayer
& "C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe" build.tcl
```

产物：`impl\pnr\top.fs`

GUI 方式：双击 `TP20K_MusicPlayer.gprj` 用 Gowin IDE 打开，直接 Run All。

---

## 6. 烧录

**下载到 SRAM（断电丢失，调试用）**

```powershell
& "C:\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe" `
  -d GW2A-18C --run 2 --fsFile "C:\gowin_work\TP20K_MusicPlayer\impl\pnr\top.fs"
```

**写入 Flash（掉电保存，比赛演示用）**

把 `--run 2` 改成 `--run 36`。

GUI 方式：打开 Programmer → 选 GW2A-18C → 添加 `top.fs` → Program/Configure。

---

## 7. 验证

`sim\verify.py` 是位级模型，做两件事：

1. 逐周期模拟 `pt8211_tx.v`，把串行流反解回 16 位字，确认 DAC 收到的就是 `sample_l/sample_r`
2. 模拟乐谱 + DDS，输出 `twinkle.wav` / `ode.wav` 试听

```powershell
cd sim
python verify.py
```

当前结果：

```
frame 0: L=0xA55A R=0x3CC3  OK
frame 1: L=0xA55A R=0x3CC3  OK
frames produced: 3, BCK period = 18 clk, frame = 32 BCK, Fs = 46875.00 Hz
RESULT: PASS
```

> 这个模型在开发中抓到过一个真 bug：`bit_cnt` 误写成 6 位导致每帧 64 个 BCK、
> 采样率掉一半。改成 5 位后修复。

---

## 8. 资源占用

| 资源 | 用量 | 占比 |
|------|------|------|
| Logic (LUT/ALU) | 294 / 20736 | **2%** |
| Register | 149 / 15552 | <1% |
| BSRAM | 1 / 46 | 3% |

余量极大，后续加 8 声部 Karplus-Strong 引擎绰绰有余。

---

## 9. 下一步

- [ ] 加入 Karplus-Strong 物理建模拨弦（钢琴/古筝音色）
- [ ] 多声部并行（8 voice）
- [ ] ADSR 包络
- [ ] 电容触摸 / 压力传感器交互
- [ ] 音色切换

---

## 10. 目录

```
TP20K_MusicPlayer/
├── src/
│   ├── top.v          主控：乐谱 ROM + DDS + 按键
│   ├── pt8211_tx.v    PT8211 串行发送器
│   ├── sine_rom.v     256×16 正弦波表
│   ├── top.cst        引脚约束
│   └── top.sdc        时钟约束
├── sim/
│   ├── verify.py      位级验证 + WAV 渲染
│   ├── twinkle.wav
│   └── ode.wav
├── build.tcl          命令行构建脚本
└── TP20K_MusicPlayer.gprj
```
