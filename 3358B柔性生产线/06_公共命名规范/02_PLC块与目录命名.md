# PLC块与目录命名

## 1. 目录命名

项目目录固定使用编号排序：

```text
00_项目说明
01_设备和网络
02_HMI
03_通信点表
04_IO点表
05_报警表
06_公共命名规范
```

单站内部固定使用：

```text
00_OB
10_IO
20_站控
30_通信
40_报警
50_设备
60_数据
70_类型
```

## 2. PLC站名命名

推荐格式：

```text
01站供料站 [CPU 1214C AC_DC_Rly]
02站加工站 [CPU 1214C AC_DC_Rly]
03站输送站 [CPU 1214C DC_DC_DC]
04站装配站 [CPU 1214C AC_DC_Rly]
05站分拣站 [CPU 1214C AC_DC_Rly]
```

## 3. OB命名

固定建议：

| 功能 | 命名 |
|---|---|
| 主循环 | `Main [OB1]` |
| 上电初始化 | `Startup [OB100]` 或 `启动初始化 [OB100]` |
| 系统保留块 | 保持系统生成，不拿来替代 `OB100` |

## 4. FC命名

推荐格式：

```text
FC_功能名
```

当前项目建议固定：

- `FC_IMap`
- `FC_QMap`
- `FC_ModeCtrl`
- `FC_AutoSeq`
- `FC_ManualCtrl`
- `FC_Reset`
- `FC_Lights`

## 5. FB命名

推荐格式：

```text
FB_对象名
```

当前项目建议固定：

- `FB_StationCtrl`
- `FB_Comm`
- `FB_Alarm`
- `FB_Cylinder`
- `FB_Motor`
- `FB_Conveyor`
- `FB_Sensor`

## 6. DB命名

### 主DB

- `DB_Station`
- `DB_Comm`
- `DB_Alarm`
- `DB_Parm`

### 设备实例DB

推荐格式：

```text
DB_设备类型_功能_序号
```

例如：

- `DB_Cyl_Stopper`
- `DB_Cyl_Pusher_1`
- `DB_Conv_Feed_1`
- `DB_Sensor_OutPos_1`
- `DB_Motor_Process_1`

## 7. UDT命名

统一用：

- `UDT_StationState`
- `UDT_CommCmd`
- `UDT_CommSts`
- `UDT_AlarmItem`
- `UDT_Parm`
