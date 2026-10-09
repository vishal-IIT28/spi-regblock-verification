# SPI-Controlled Register Block: Design Specification

**Author:** Vishal Kumar  
**Status:** v1.0 (pre-RTL)  
**Language / Tools:** Verilog, Vivado 2024.2 (xsim), Python 3

## 1. Overview

A small SPI slave that exposes a bank of 8-bit registers, plus an SPI master used to drive it.
This mirrors how real silicon is configured and read back during bring-up: a host writes and reads
a register map over a serial bus. The project is verified with a self-checking testbench and a
Python script that generates test vectors and checks simulation logs.

Blocks:

| Block | Description |
|---|---|
| `spi_slave` | Receives frames, decodes address, reads/writes the register file |
| `regfile` | 16 x 8-bit registers (may be inside `spi_slave`) |
| `spi_master` | Generates SCLK/CS_N/MOSI, shifts out a frame, captures MISO |
| `top` | Master connected to slave (loopback), used by the testbench |

## 2. Interface

### 2.1 SPI slave ports

| Signal | Dir | Description |
|---|---|---|
| `clk` | in | System clock (100 MHz assumed) |
| `rst_n` | in | Active-low asynchronous reset |
| `sclk` | in | SPI clock from master |
| `cs_n` | in | Chip select, active low |
| `mosi` | in | Master out, slave in |
| `miso` | out | Master in, slave out (driven 0 when `cs_n` is high; single slave, no shared bus) |

### 2.2 Clocking approach

SPI inputs (`sclk`, `cs_n`, `mosi`) are asynchronous to `clk`. The slave passes each through a
2-flop synchronizer into the `clk` domain and detects SCLK rising/falling edges there.
This keeps the design in a single clock domain. Requirement: **SCLK frequency <= clk / 4**.

## 3. SPI protocol

- **Mode 0:** CPOL = 0 (SCLK idles low), CPHA = 0.
  - Master and slave **sample** data on the SCLK **rising** edge.
  - Master and slave **change** data on the SCLK **falling** edge.
- **MSB first**, 16 SCLK cycles per frame, `cs_n` low for the whole frame.

### 3.1 Frame format

```
bit:   15     14 ......... 8   7 ......... 0
     +------+---------------+--------------+
     |  RW  |  ADDR[6:0]    |  DATA[7:0]   |
     +------+---------------+--------------+
RW = 1 : write      RW = 0 : read
```

### 3.2 Write frame (RW = 1)

- MOSI carries `RW`, `ADDR`, `DATA` in order.
- The register is updated **only after the 16th rising edge of SCLK** has been received.
- MISO output is don't-care (driven 0).

### 3.3 Read frame (RW = 0)

- MOSI carries `RW` and `ADDR`; `DATA` bits on MOSI are ignored.
- After the 8th rising edge (address fully received), the slave looks up the register.
- The slave places `DATA[7]` on MISO at the **8th falling edge** and shifts out the remaining bits on
  falling edges 9 to 15, so the master samples `DATA[7:0]` on rising edges 9 to 16.
- During bits 15:8 (RW and ADDR), MISO is 0.

## 4. Register map

| Addr | Name | Access | Reset | Description |
|---|---|---|---|---|
| 0x00 | `ID` | RO | 0xA5 | Fixed device ID |
| 0x01 | `CTRL` | RW | 0x00 | Control register (no hardware function in v1, readback only) |
| 0x02 | `STATUS` | RO | 0x00 | Count of completed write frames (wraps at 256) |
| 0x03 to 0x0F | `SCRATCH0..12` | RW | 0x00 | General purpose scratch registers |
| 0x10 to 0x7F | (unmapped) | n/a | n/a | Read returns 0x00, writes ignored |

## 5. Behavioural rules

1. **Write to a read-only register** (`ID`, `STATUS`) or an **unmapped address** is ignored; the register keeps its value.
2. **STATUS counter** increments once for every **completed** write frame (16 SCLK rising edges received with `cs_n` low throughout), **including** writes to read-only or unmapped addresses. Read frames do not change it.
3. **Aborted frame:** if `cs_n` goes high before 16 SCLK rising edges were received, the frame is discarded: no register changes, STATUS does not increment, the bit counter and shift register reset.
4. **Extra clocks:** a frame with more than 16 SCLK edges while `cs_n` is low is outside the spec. Behaviour in v1: edges after the 16th are ignored until `cs_n` returns high.
5. **Back-to-back frames:** a new frame may start after `cs_n` has been high for at least 2 `clk` cycles.
6. **Reset (`rst_n` low):** all registers return to their reset values, STATUS counter clears, any frame in progress is aborted. `miso` is 0 during reset.
7. **Read-after-write:** a read issued after a completed write to the same address returns the written value (for RW registers).

## 6. Verification plan (summary)

| ID | Test | Expected |
|---|---|---|
| T1 | Read `ID` after reset | 0xA5 |
| T2 | Write then read every RW register (0x01, 0x03 to 0x0F) | Read matches written value |
| T3 | Write to `ID` and `STATUS` | Value unchanged |
| T4 | Write to unmapped address, then read it | Reads 0x00 |
| T5 | N completed writes, then read `STATUS` | Equals N (mod 256) |
| T6 | Abort frame (raise `cs_n` after 10 clocks) | No register change, no STATUS increment |
| T7 | Reset in the middle of a frame | Registers reset, frame discarded |
| T8 | Back-to-back frames, minimum `cs_n` high gap | All frames succeed |
| T9 | Random write/read sequences (Python-generated vectors) | Scoreboard matches reference model |
| T10 | SCLK at slowest and fastest allowed rate | All tests still pass |

Checking approach: a self-checking SystemVerilog-free Verilog testbench with a reference model
(array of expected register values) compares every read; a Python script generates vectors,
parses the simulation log and reports PASS/FAIL with a summary.

## 7. Out of scope (v1)

- Multiple slaves, daisy chaining, SPI modes 1 to 3
- Burst / auto-increment transfers
- Interrupts or real hardware function behind `CTRL`
- FPGA board bring-up (simulation and synthesis/timing reports only)
