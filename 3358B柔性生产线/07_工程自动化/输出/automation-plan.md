# 3358B 自动化执行计划

- 生成时间: 2026-04-17 21:38:01
- PlanOnly: False
- 检测到 TIA Openness: True
- 子网: PN_3358B
- 模板工程: C:\Users\韩明宇\Desktop\v17程序\335B柔性生产线\335B柔性生产线.ap17
- 目标工程: D:\TIAProjects\3358B\335B柔性生产线.ap17

## 站点网络

| 站点 | 设备名 | IP | PN 名称 |
|---|---|---|---|
| S01 | S7-1200 station_1 | 192.168.10.11 | plc-3358b-s01 |
| S02 | S7-1200 station_2 | 192.168.10.12 | plc-3358b-s02 |
| S03 | S7-1200 station_3 | 192.168.10.13 | plc-3358b-s03 |
| S04 | S7-1200 station_4 | 192.168.10.14 | plc-3358b-s04 |
| S05 | S7-1200 station_5 | 192.168.10.15 | plc-3358b-s05 |

## PUT/GET 链路

| 链路 | 连接 ID | 本地站 | 远端站 | 字段数 |
|---|---|---|---|---|
| S02 | 2 | S01 | S02 | 18 |
| S03 | 3 | S01 | S03 | 18 |
| S04 | 4 | S01 | S04 | 18 |
| S05 | 5 | S01 | S05 | 16 |

## 策略

- 当前采用: template-fixed-ids
- 说明: PUT/GET connection objects are pre-created in the TIA template project. Automation keeps device names stable and only stamps network parameters.
