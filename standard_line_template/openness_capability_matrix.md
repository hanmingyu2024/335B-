# Openness 能力矩阵

这份矩阵综合了两个本地来源：

- `D:\西门子 TIA Openness API 全功能汇总表(版本TIA Portal V17).csv`
- `_tia_docs_v17/Toc/Default.xml`

本地帮助目录能确认的主要总览入口包括：

- `Functions for projects and project data`
- `Functions for Connections`
- `Functions for accessing devices, networks and connections`
- `Functions for accessing the data of a PLC device`
- `Functions for downloading data to PLC device`
- `Functions for accessing PLC service`
- `Functions for accessing the data of an HMI device`
- `Functions for Version Control Interface`
- `Importing/exporting data of a PLC device`
- `Importing/exporting hardware data`

## 和标准模板直接相关的能力

### 1. 工程与项目管理

模板用途：

- 创建项目
- 保存和归档项目
- 标准目录生成
- 多项目复用

当前落地：

- `tools/build_tia_project_from_manifest_v17.ps1`
- 现有 `tools/build_tia_project_v17.ps1`

### 2. 硬件组态自动化

模板用途：

- 根据清单自动创建设备
- 按 CPU 订货号生成站点
- 后续可扩展 ET200、HMI、驱动器

当前落地：

- 已实现 CPU 创建设备
- 网络和模块参数仍需下一步增强

### 3. 通讯组态自动化

模板用途：

- 固化握手字段
- 统一站间 DB 结构
- 为后续 PUT/GET、OPC UA、Modbus 扩展留接口

当前落地：

- 已实现统一 `DB_Comm`
- 连接对象的自动创建还未接入脚本

### 4. 程序与代码自动化

模板用途：

- 创建 OB/FB/FC/DB/UDT
- 自动生成主循环调用链
- 统一设备模板和站控模板

当前落地：

- 已实现标准块骨架生成
- 已实现外部源文件导入并生成块

### 5. 编译与验证自动化

模板用途：

- 自动编译
- 自动写出日志
- 自动阻断错误工程

当前落地：

- 已实现每站编译日志输出
- 已实现编译失败自动中止

### 6. 下载、上传与调试

模板用途：

- 现场下载
- 在线诊断
- 变量监控

当前落地：

- 本地帮助可确认 Openness 支持下载与上传
- 当前仓库还没有把在线下载和调试自动化接进脚本

### 7. 批量与扩展能力

模板用途：

- 用清单批量生成多站项目
- 为 Excel / CSV / MES 数据接口预留入口
- 固化成你自己的工程生成器

当前落地：

- `tools/new_standard_line_project.ps1`
- `tools/invoke_standard_line_pipeline.ps1`

## 对你最有价值的结论

如果目标是“下一个项目直接复用”，Openness 最应该优先用在下面四件事上：

1. 基于清单自动创建设备和工程结构。
2. 基于模板自动导入 OB/FB/FC/DB/UDT。
3. 自动编译并输出日志。
4. 统一归档和交付。

而这四件事，正是这次模板和脚本已经开始固定下来的主链路。
