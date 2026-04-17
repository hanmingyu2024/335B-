# 3358B 工程自动化

## 1. 目标

这套目录用于把 `3358B` 产线的工程侧动作尽量收敛成自动化：

- 自动校验 5 站网络拓扑配置
- 自动生成站间 `PUT/GET` 最小集执行计划
- 自动克隆 TIA 模板工程
- 自动挂接 PROFINET 子网
- 自动写入站点 IP、子网掩码、网关、PROFINET 名称
- 可选自动做一次 PC 到 PLC 的上线验证

## 2. 当前策略

当前采用 `template-fixed-ids` 策略：

- `PUT/GET` 的 PLC 通信连接对象预先固化在 TIA 模板工程里
- 自动化脚本不再手工点设备组态和网络页
- 脚本只负责复制模板、保持设备名稳定、下发地址和节点信息

这样做的原因是：

- 当前项目代码已经稳定依赖 `DB_Link_S02..S05`
- 官方 Openness 文档里我已经确认了网络、子网、地址、上线接口
- 但这轮没有在官方文档里确认到可直接创建 PLC-PLC `PUT/GET` 连接对象的通用接口

所以落地方案是：

1. 先做一份带固定 `PUT/GET` 连接 ID 的母版工程
2. 后续所有项目实例都由脚本自动克隆和改网参

## 3. 目录

```text
07_工程自动化
├─ README.md
├─ 配置
│  └─ line-topology.json
├─ 脚本
│  └─ Invoke-TiaAutoConfig.ps1
└─ 输出
```

## 4. 前置条件

在真正执行 TIA 自动化的工程机上，需要满足：

- 安装 TIA Portal，并可用 `TIA Portal Openness`
- 能找到 `Siemens.Engineering.dll`
- 有一份模板工程，模板内已经预建好 `01 -> 02/03/04/05` 的固定 `PUT/GET` 连接对象
- 模板内 5 台 PLC 的设备名和本配置文件一致

本仓库当前机器不满足这些条件：

- 未发现 TIA Portal 本体
- 仅发现 `PLCSIM`
- 仅安装了 `.NET Runtime`，未安装 `.NET SDK`

因此本轮提供的是：

- 可运行的 `PowerShell` 脚本
- 可直接修改的配置文件
- 已执行过的 `PlanOnly` 计划输出

## 5. 使用方法

### 5.1 只生成计划，不连 TIA

```powershell
PowerShell -ExecutionPolicy Bypass -File .\07_工程自动化\脚本\Invoke-TiaAutoConfig.ps1 -PlanOnly
```

输出：

- `07_工程自动化\输出\automation-plan.json`
- `07_工程自动化\输出\automation-plan.md`

### 5.2 在工程机上执行 TIA 自动化

```powershell
PowerShell -ExecutionPolicy Bypass -File .\07_工程自动化\脚本\Invoke-TiaAutoConfig.ps1
```

默认流程：

1. 读取 `line-topology.json`
2. 校验 `03_通信点表\PUT_GET最小集.csv`
3. 克隆模板工程到目标工程
4. 打开 TIA
5. 查找或创建 PROFINET 子网
6. 对 5 站逐一写入地址和节点信息
7. 保存工程
8. 输出本次执行计划

## 6. 配置约束

`line-topology.json` 里必须保持以下字段和模板工程一致：

- `stations[].deviceName`
- `stations[].deviceNameCandidates`
- `putGetConnections[].connectionId`
- `putGetConnections[].localShadowDb`
- `putGetConnections[].remoteCommDb`

推荐固定连接 ID：

- `S02 -> ID 2`
- `S03 -> ID 3`
- `S04 -> ID 4`
- `S05 -> ID 5`

## 7. 后续扩展

如果后面拿到一台已安装 TIA 的工程机，并确认了对应版本的 Openness 连接对象接口，可以直接在 `Invoke-TiaAutoConfig.ps1` 里补 `Apply-TiaConnectionObjects`，把模板策略替换成真正的连接对象创建策略。

