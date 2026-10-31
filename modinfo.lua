name = "烹饪勋章料理兼容"
description = "使烹饪勋章和大厨勋章可以记录其他模组加进烹饪锅或便携锅的料理。\n同时使得其他模组的烹饪锅能被烹饪勋章或大厨勋章识别。"
author = "ClockCycas"
version = "1.0.0"

api_version = 10

dst_compatible = true
all_clients_require_mod = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

-- 高于能力勋章的 -10001，保证本模组的 AddPrefabPostInit 在其注册 prefab 之前挂上。
-- 不需要压过 -10001：收获逻辑挂在实例函数上，不依赖比它更晚加载。
priority = -1
