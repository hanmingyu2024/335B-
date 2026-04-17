# 3358B 整线 PUT/GET 实施清单

## 1. 当前代码前提

- `01站` 由 `FB_LineCtrl` 统一向 `DB_Link_S02..S05` 写命令、读状态。
- `DB_Link_S02..S05` 与各站 `DB_Comm` 当前是同结构影子块。
- 这套结构里同时混放了 `01 -> 各站` 命令位和 `各站 -> 01` 状态位。
- 因此不能做“整块 `PUT` / 整块 `GET`”或“整块镜像同步”，否则会互相覆盖。

结论：

- `PUT` 只下发 `01 -> 各站` 的命令字段集。
- `GET` 只回读 `各站 -> 01` 的状态字段集。
- `HeartbeatRxLast / HeartbeatWatchdog / HeartbeatLimit / PeerAlive` 只在本地维护，不上网。

## 2. 组态前先定死的规则

1. `01站` 作为唯一主动发起方，统一访问 `02/03/04/05站` 的 `DB_Comm`。
2. 每个远端站单独建 1 条 S7 连接，不混用、不广播。
3. 第一阶段只上传“最小可运行集”，保留位先不配。
4. 心跳必须交叉映射：`01.Tx -> 远端.Rx`，`远端.Tx -> 01.Rx`。
5. 远端站不新增额外通信逻辑块，先沿用现有 `FB_Comm + DB_Comm`。

## 3. 博途中必须补齐的基础信息

| 远端站 | CPU | 01站本地影子块 | 远端暴露块 | PROFINET 名称 | IP 地址 | S7 连接 ID | 建议周期 |
|---|---|---|---|---|---|---|---|
| `S02` | `CPU 1214C AC/DC/Rly` | `DB_Link_S02` | `DB_Comm` | 待填 | 待填 | 待填 | `50~100 ms` |
| `S03` | `CPU 1214C DC/DC/DC` | `DB_Link_S03` | `DB_Comm` | 待填 | 待填 | 待填 | `50~100 ms` |
| `S04` | `CPU 1214C AC/DC/Rly` | `DB_Link_S04` | `DB_Comm` | 待填 | 待填 | 待填 | `50~100 ms` |
| `S05` | `CPU 1214C AC/DC/Rly` | `DB_Link_S05` | `DB_Comm` | 待填 | 待填 | 待填 | `50~100 ms` |

## 4. DB 访问约束

- 当前 `DB_Link_S02..S05` 与各站 `DB_Comm` 都是 `S7_Optimized_Access := TRUE`。
- 若采用绝对地址式 `PUT/GET`，先把参与互访的通信 DB 改成非优化访问，并在地址冻结后再做连接组态。
- 若项目坚持保留优化访问，则不要按整块绝对地址互抄；改走同项目符号方式，或改成 `I-Device`。

## 5. 01站后续推荐调用位置

当第 2 阶段开始补真正传输块时，建议把 01站主循环收敛成下面这个顺序：

```text
FC_IMap
FB_StationCtrl
FB_Alarm
DB_Station.StationReady := NOT DB_Station.FaultActive
DB_Station.StationBusy := DB_Station.CycleActive
FC_Lights
FB_Comm
FB_LineCommGet
FB_LineCtrl
FB_LineCommPut
FC_QMap
```

说明：

- `FB_LineCommGet` 只负责把远端状态字段读回到本地 `DB_Link_Sxx`。
- `FB_LineCtrl` 只负责整线判定和写本地命令影子。
- `FB_LineCommPut` 只负责把本地命令字段写到远端 `DB_Comm`。

## 6. 每条链路的最小实施范围

### 6.1 `S02`

`01 -> 02` 必配：

- `CmdAuto`
- `CmdStart`
- `CmdStop`
- `CmdReset`
- `HeartbeatTx -> HeartbeatRx`
- `PlaceDone`
- `TakeDone`

`02 -> 01` 必配：

- `HeartbeatTx -> HeartbeatRx`
- `StsReady`
- `StsBusy`
- `StsDone`
- `StsFault`
- `StepNo`
- `AllowIn`
- `PartReceived`
- `ProcessDone`
- `ReqOut`
- `PartReady`

暂缓：

- `ReqIn`
- `AllowTake`

### 6.2 `S03`

`01 -> 03` 必配：

- `CmdAuto`
- `CmdStart`
- `CmdStop`
- `CmdReset`
- `HeartbeatTx -> HeartbeatRx`
- `TransferJob`
- `JobSource`
- `JobTarget`
- `PlaceRotateLeft`

`03 -> 01` 必配：

- `HeartbeatTx -> HeartbeatRx`
- `StsReady`
- `StsBusy`
- `StsDone`
- `StsFault`
- `StepNo`
- `ReadyForJob`
- `JobBusy`
- `JobDone`

暂缓：

- `JobAbort`
- `PickAtLeft`
- `PlaceAtLeft`

### 6.3 `S04`

`01 -> 04` 必配：

- `CmdAuto`
- `CmdStart`
- `CmdStop`
- `CmdReset`
- `HeartbeatTx -> HeartbeatRx`
- `PlaceDone`
- `TakeDone`

`04 -> 01` 必配：

- `HeartbeatTx -> HeartbeatRx`
- `StsReady`
- `StsBusy`
- `StsDone`
- `StsFault`
- `StepNo`
- `AllowIn`
- `PartReceived`
- `ProcessDone`
- `ReqOut`
- `PartReady`

暂缓：

- `ReqIn`
- `AllowTake`

### 6.4 `S05`

`01 -> 05` 必配：

- `CmdAuto`
- `CmdStart`
- `CmdStop`
- `CmdReset`
- `HeartbeatTx -> HeartbeatRx`
- `PlaceDone`
- `DoneAck`

`05 -> 01` 必配：

- `HeartbeatTx -> HeartbeatRx`
- `StsReady`
- `StsBusy`
- `StsDone`
- `StsFault`
- `StepNo`
- `AllowIn`
- `PartReceived`
- `ProcessDone`

暂缓：

- `ReqIn`

## 7. 调试顺序

1. 先补全 4 条 S7 连接的站名、IP、连接 ID。
2. 先打通 `S03` 的任务链路，再联动 `S02/S04/S05`。
3. 心跳先验收，再验收 `StsReady/StsFault`，最后再验收工艺握手。
4. 任一链路断开时，确认 `01站` 的 `PeerAlive` 能掉下去，整线故障码能切到对应通信故障。

## 8. 后续可选重构

如果后面希望简化传输块，优先考虑把 `DB_Link_Sxx` 拆成：

- `DB_Link_Sxx_Cmd`
- `DB_Link_Sxx_Sts`

拆完以后才适合做整块同步；在当前混合结构下，不建议这么做。
