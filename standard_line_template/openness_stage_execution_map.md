# 七阶段执行映射

这份文档不是再罗列一遍 Openness 功能，而是把你的七个阶段直接映射到可执行动作。

本地帮助里已经能确认以下相关入口：

- `Functions for projects and project data`
- `Functions for accessing devices, networks and connections`
- `Functions for accessing the data of a PLC device`
- `Tags and Tag tables`
- `Creating PLC tag table`
- `Importing PLC tag table`
- `Functions for downloading data to PLC device`
- `Importing/exporting data of a PLC device`
- `Export/Import of PLC tags`

## 1. IO对点

目标：

- 从 Excel 收敛出结构化 I/O 数据
- 形成稳定的 ASCII 符号名
- 产出可编译映射骨架

当前落地：

- [generate_io_assets_from_workbook.py](../tools/generate_io_assets_from_workbook.py)
- `plc_tags_flat.csv`
- `StationXX_plc_tags.csv`
- `DB_IO.db`
- `FC_IMap.scl`
- `FC_QMap.scl`

下一步 Openness 接法：

- 直接创建 PLC Tag Table
- 直接写入 PLC Tag
- 不再依赖手工导入 CSV

## 2. 工艺流程

目标：

- 固化站间流向
- 固化握手信号
- 固化整线节拍

当前落地：

- `line_manifest.sample.json` 中的 `processFlow`
- `line_manifest.sample.json` 中的 `commSignals`
- `03_CommTable/station_comm_signals.md`

下一步 Openness 接法：

- 自动建立通讯对象
- 自动建立工艺相关 DB 或连接参数

## 3. 设备组态

目标：

- 根据清单自动创建 CPU 和设备对象
- 后续扩展网络、IP、模块参数

当前落地：

- [build_tia_project_from_manifest_v17.ps1](../tools/build_tia_project_from_manifest_v17.ps1)
- `cpuTypeIdentifier`
- `deviceName`
- `deviceItemName`

下一步 Openness 接法：

- 自动创建子网和设备名称
- 自动挂接扩展 IO 模块
- 自动写模块参数

## 4. 项目框架搭建

目标：

- 统一目录
- 统一块结构
- 统一数据块与 UDT

当前落地：

- [new_standard_line_project.ps1](../tools/new_standard_line_project.ps1)
- `tia_sources/manifest.json`
- `Types / DB / Blocks` 标准骨架

下一步 Openness 接法：

- 批量创建用户组
- 批量创建块目录或软件单元

## 5. 编程

目标：

- 先自动生成可编译骨架
- 再把专有工艺限制在少量块内

当前落地：

- `FB_StationCtrl`
- `FB_Comm`
- `FB_Alarm`
- `FB_LineCtrl`
- `FB_Cylinder`
- `FB_Motor`
- `FB_Conveyor`
- `FB_Sensor`

下一步 Openness 接法：

- 自动导入外部源
- 自动替换模板块
- 自动生成实例 DB

## 6. 调试

目标：

- 自动编译
- 自动输出日志
- 后续补下载和在线诊断

当前落地：

- 3358B 专用链：[build_tia_project_v17.ps1](../tools/build_tia_project_v17.ps1)
- 通用链：[build_tia_project_from_manifest_v17.ps1](../tools/build_tia_project_from_manifest_v17.ps1)
- `logs/StationXX_compile.txt`

下一步 Openness 接法：

- 下载到 PLC
- 上传现场程序
- 在线读取设备状态

## 7. 优化

目标：

- 所有变化回写模板
- 所有项目差异回写清单
- 不让工程经验散落在单个项目里

当前落地：

- 标准模板目录
- 通用脚手架
- Openness 能力矩阵
- I/O 自动化脚本

下一步 Openness 接法：

- 版本对比
- 工程差异追踪
- 多产线批量生成

## 当前最值得继续补的三项

1. `PLC Tag Table` 直接通过 Openness 创建，不再只产出 CSV。
2. `网络 / 子网 / IP / 扩展模块` 自动化，补齐设备组态链。
3. `下载 / 上传 / 在线诊断` 自动化，补齐现场调试链。
