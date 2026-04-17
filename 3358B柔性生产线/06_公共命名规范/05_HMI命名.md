# HMI命名

## 1. 画面命名

推荐文件名统一为 `Scr_` 前缀：

- `Scr_LineHome`
- `Scr_LineOverview`
- `Scr_S01_Monitor`
- `Scr_S01_Manual`
- `Scr_Alarm`
- `Scr_Param`
- `Scr_IODiag`
- `Scr_CommDiag`

## 2. 对象命名前缀

| 对象 | 前缀 |
|---|---|
| 按钮 | `Btn_` |
| 指示灯 | `Lamp_` |
| 文本 | `Txt_` |
| 数值显示 | `Num_` |
| 输入框 | `In_` |
| 趋势 | `Trend_` |
| 导航按钮 | `Nav_` |
| 图标 | `Icon_` |
| 组对象 | `Grp_` |

## 3. HMI对象示例

- `Btn_LineStart`
- `Btn_LineReset`
- `Btn_S01_ManPush`
- `Lamp_S03_Fault`
- `Num_S04_Step`
- `Nav_ToAlarm`

## 4. HMI变量组命名

推荐组名：

- `Line`
- `S01`
- `S02`
- `S03`
- `S04`
- `S05`
- `Alarm`
- `Comm`
- `Diag`

## 5. HMI变量命名示例

- `Line.CmdStart`
- `Line.StsFault`
- `S01.Sts.Step`
- `S02.IO.InHeadUp`
- `S03.Comm.TransferJob`
- `S05.Cmd.ManPusher1`

## 6. 颜色与状态命名

推荐状态文字统一：

- `Ready`
- `Busy`
- `Done`
- `Fault`
- `Auto`
- `Manual`

不要同一项目里同时出现：

- `Alarm` 和 `Fault` 混用表示同一状态
- `Run` 和 `Busy` 混用表示同一状态
