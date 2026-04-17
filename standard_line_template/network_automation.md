# 网络自动化

这份模板现在已经把 `网络 / 子网 / IP / PROFINET 设备名` 纳入标准清单，并接入了 `TIA Openness V17` 构建链。

## 当前已自动化

- 按清单创建全局子网
- 将每个 PLC 的首个网络节点连接到子网
- 按站写入 `IP address`
- 按站写入 `PROFINET device name`
- 按站设置 `InterfaceOperatingMode`
- 写入 `SubnetMask`
- 按项目写入 `IpProtocolSelection`
- 按项目写入 `UseRouter / RouterAddress`

## 清单字段

项目级网络：

```json
"network": {
  "subnetName": "PN_LINE_1",
  "subnetTypeIdentifier": "System:Subnet.Ethernet",
  "subnetMask": "255.255.255.0",
  "useRouter": false,
  "routerAddress": "",
  "ipProtocolSelection": "Project"
}
```

站级网络：

```json
"network": {
  "ipAddress": "192.168.10.11",
  "pnDeviceName": "std-line-st01-plc",
  "interfaceOperatingMode": "IoController",
  "autoGeneratePnDeviceName": false
}
```

## 对应脚本

- 清单生成与校验：[new_standard_line_project.ps1](../tools/new_standard_line_project.ps1)
- TIA 构建与网络写入：[build_tia_project_from_manifest_v17.ps1](../tools/build_tia_project_from_manifest_v17.ps1)

## 对应 Openness 能力

本模板当前直接落到以下 Openness 入口：

- `project.Subnets.Create("System:Subnet.Ethernet", "PN_LINE_1")`
- `deviceItem.GetService<NetworkInterface>()`
- `itf.Nodes`
- `node.ConnectToSubnet(subnet)`
- `node.SetAttribute("Address", "...")`
- `node.SetAttribute("SubnetMask", "...")`
- `node.SetAttribute("PnDeviceName", "...")`
- `node.SetAttribute("PnDeviceNameAutoGeneration", false)`
- `node.SetAttribute("IpProtocolSelection", IpProtocolSelection.Project)`

## 当前约束

- 默认只处理每台 PLC 暴露出来的首个网络接口和首个节点。
- 这一步覆盖的是 `CPU PN/IE 接口`，还没有继续自动挂接 `ET200 / 扩展 IO 模块 / GSD 设备`。
- 现场下载和在线诊断仍然受当前 Windows 会话的 `Siemens TIA Openness` 权限影响。

## 下一个扩展点

最值得继续补的是两类：

1. 扩展模块自动挂接
2. IoSystem / 远程 IO / 第三方设备自动组态

这两块补完后，模板就会从“项目骨架自动化”推进到“硬件组态自动化”。
