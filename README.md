# Radio-86RK FPGA replica on ReVerSE-U16 board

## Overview

Radio-86RK is a popular DIY personal computer designed in 1986 by soviet union engineers and based on i8080A microprocessor (KR580VM80A). More information here: <https://ru.wikipedia.org/wiki/Радио_86РК> 

This project is a **Radio-86RK** port of the original Altera DE1 fpga implementation by Dmitry Tselikov aka **b2m** on *ReVerSE-U16 board*.

All copyrights are going to Dmitry Tselikov <http://bashkiria-2m.narod.ru/>. 

Please see **LICENSE.TXT** for more information.

Discussion about this project (including Altera DE1 implementation) is located here: <http://zx-pk.ru/showthread.php?t=12985>

## Hardware part

This port is designed to run on ReVerSE-U16 board with Cyclone IV (EP4CE22E22C8).

## Software part

To compile the project, you need at least Quartus II v 13.0sp1 Web Edition <http://dl.altera.com/13.0sp1/?edition=web> with Cyclone IV support. 

To run confifuration automatially when board powering on, you need to perform the following steps:

1. Convert *sof*-firmware into *jic* using u16_rk86_jic.cof convertor config;
2. Upload it via JTAG to the on-board EPCS16 serial flash memory. 

### SD card usage

SD card should be formatted as _FAT16_ filesystem. Place _*.RK_ files in the root of the filesystem.

In the Radio-86RK **monitor** a special command "U" is exists. Type "U" then press "Enter" to load SD card interface. 
SD card interface is quiet simple, you just need to type "DIR" to get a list of files on SD card, then type a filename to run, then press "Enter". 

## Contribution

Please feel free to ask a questions as well as help and support to this project. Please send your bug-reports and pull-requests via github  

-._
