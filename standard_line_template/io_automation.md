# IO 自动化

这一步把 `IO表 -> PLC 标签/映射骨架/标准数据` 固化成脚本。

当前脚本：

- [generate_io_assets_from_workbook.py](../tools/generate_io_assets_from_workbook.py)

输入：

- 按 3358B 当前格式整理的 Excel I/O 总表
- 标准工作区里的 `config/line_manifest.json`

输出：

- `04_IOList/plc_tags_flat.csv`
- `04_IOList/StationXX_plc_tags.csv`
- `04_IOList/StationXX_io_points.md`
- `config/io_points.generated.json`
- `tia_sources/StationXX/DB/DB_IO.db`
- `tia_sources/StationXX/Blocks/10_IO/FC_IMap.scl`
- `tia_sources/StationXX/Blocks/10_IO/FC_QMap.scl`

当前策略：

- 信号描述保留中文
- 变量名统一转成稳定的 ASCII 符号
- 布尔量使用 `DI/DO`
- 字量使用 `AI/AQ`
- 地址直接映射到 `DB_IO`

示例：

- `Station01_DI_001`
- `Station03_DO_004`
- `Station05_AQ_001`

这样做的目的不是追求一次性把语义命名做满，而是先把“Excel 到可编译映射骨架”自动化打通。

和 Openness 的衔接点：

- 本地帮助里已经能确认 PLC 标签能力入口，包括：
  - `Functions for accessing the data of a PLC device`
  - `Tags and Tag tables`
  - `Creating PLC tag table`
  - `Exporting PLC tag tables`
  - `Importing PLC tag table`
  - `Export/Import of PLC tags`

下一步可继续做：

1. 用 Openness 直接创建 PLC Tag Table，而不是只导出 CSV。
2. 从 IO 描述里识别按钮、气缸、灯、传感器语义，自动回写更好的变量名。
3. 让 `DB_IO` 之外的 `DB_Station` 字段也自动绑定到语义化点位。
