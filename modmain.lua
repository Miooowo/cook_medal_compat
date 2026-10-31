-- 烹饪勋章只认 IsNativeCookingProduct。该函数在 medal_globalfn.lua 导出到 GLOBAL，
-- functional_medal_defs.lua 的 HarvestFoodFn 每次直接查这个全局，没有 local 缓存。
-- 收获时 medal_hook 调用的是勋章实例上的 HarvestFoodFn（extrafn 在 prefab 构造里赋上，PostInit 之前）。

if not GLOBAL.KnownModIndex:IsModEnabled("workshop-1909182187") then
	return
end

local function CookRecipes()
	local cooking = require("cooking")
	return cooking and cooking.recipes or nil
end

local function PotRecipes(foodname)
	if type(foodname) ~= "string" then
		return nil, nil
	end
	local recipes = CookRecipes()
	if recipes == nil then
		return nil, nil
	end
	local pot = recipes.cookpot and recipes.cookpot[foodname] or nil
	local portable = recipes.portablecookpot and recipes.portablecookpot[foodname] or nil
	return pot, portable
end

-- 香料菜：预制体上的 spicedfood 标签来自配方的 spice 字段。收获回调拿到的是 prefab 名。
local function RecipeMarkedSpice(recipe)
	if recipe == nil then
		return false
	end
	if recipe.spice ~= nil then
		return true
	end
	local tags = recipe.tags
	if type(tags) == "table" then
		for k, v in pairs(tags) do
			if k == "spicedfood" or v == "spicedfood" then
				return true
			end
		end
	end
	return false
end

-- 任一非调味站的锅上有这份配方，且该份没有盘子、不是香料，就算烹饪锅成品。
local function CanRecord(foodname, cookpotname)
	if cookpotname == "portablespicer" or type(foodname) ~= "string" then
		return false
	end
	if string.find(foodname, "_spice_", 1, true) ~= nil then
		return false
	end
	local recipes = CookRecipes()
	if recipes == nil then
		return false
	end
	if RecipeMarkedSpice(recipes.portablespicer and recipes.portablespicer[foodname] or nil) then
		return false
	end
	for cooker, list in pairs(recipes) do
		if cooker ~= "portablespicer" and type(list) == "table" then
			local recipe = list[foodname]
			if recipe ~= nil and recipe.platetype == nil and not RecipeMarkedSpice(recipe) then
				return true
			end
		end
	end
	return false
end

local function Listed(inst, foodname)
	return inst.foodlist ~= nil and table.contains(inst.foodlist, foodname)
end

AddPrefabPostInit("cook_certificate", function(inst)
	if GLOBAL.TheWorld == nil or not GLOBAL.TheWorld.ismastersim then
		return
	end
	local oldfn = inst.HarvestFoodFn
	if oldfn == nil then
		return
	end

	inst.HarvestFoodFn = function(inst, foodname, harvester, cookpotname)
		local widen = CanRecord(foodname, cookpotname)
		local native = GLOBAL.IsNativeCookingProduct
		if widen and native ~= nil then
			GLOBAL.IsNativeCookingProduct = function(name, ismaster)
				-- 第二个参数为 true 是沃利倍率，也是大厨勋章的查询。必须走原函数。
				if ismaster ~= true and name ~= nil and name == foodname then
					return true
				end
				return native(name, ismaster)
			end
		end

		local had = Listed(inst, foodname)
		-- 模组环境里没有直接放 pcall / error，走 _G，保证原函数出错时也能把全局函数放回去。
		local ok, err = GLOBAL.pcall(oldfn, inst, foodname, harvester, cookpotname)
		if widen and native ~= nil then
			GLOBAL.IsNativeCookingProduct = native
		end
		if not ok then
			GLOBAL.error(err)
		end

		-- 原函数：
		-- fuelnum = TUNING_MEDAL.COOK_MEDAL.CONSUME * (IsNativeCookingProduct(foodname, true) and 2 or 1)
		-- CONSUME = 5 * (TUNING.IS_LOW_COST and 2 or 1)，上限 MAXUSES = 200。
		-- 模组菜不传 true 的查询被临时放宽，传 true 仍走原函数，所以原函数按普通菜扣 CONSUME。
		-- 只在 portablecookpot、cookpot 没有的模组菜，再补扣同样一份，合计为沃利档。
		-- foodlist、食谱同步、飘字、天道酬勤都只在原函数里发生一次。
		if not widen or native == nil or had or not Listed(inst, foodname) then
			return
		end
		local pot, portable = PotRecipes(foodname)
		if portable == nil or pot ~= nil then
			return
		end
		if native(foodname) == true or native(foodname, true) == true then
			return
		end
		local medal = GLOBAL.TUNING_MEDAL
		local consume = medal and medal.COOK_MEDAL and medal.COOK_MEDAL.CONSUME
		if consume == nil or not inst:IsValid() or inst.components.finiteuses == nil then
			return
		end
		inst.components.finiteuses:Use(consume)
	end
end)

-- 星璃自动电饭煲 stella_cookpot 用 stewer，但 StartAutoCook 调用 StartCooking() 时没有烹饪者。
-- 星璃在 doer 为空时走自己的 StartCooking，chef_id 写成 false。
-- 能力勋章只在 chef_id 等于收获者时才调用 HarvestFoodFn，所以这口锅的成品不会入账。
-- 这里包在组件包装之外（PrefabPostInit 晚于 AddComponent），chef_id 为空才补记，避免和勋章自己的收获各记一次。
local function EquippedGroupMedal(harvester, prefab)
	local inv = harvester.components and harvester.components.inventory or nil
	if inv == nil or inv.EquipMedalWithgroupTag == nil then
		return nil
	end
	local medal = inv:EquipMedalWithgroupTag("chefMedal")
	if medal ~= nil and medal.prefab == prefab and medal.HarvestFoodFn ~= nil then
		return medal
	end
	return nil
end

-- 与大厨勋章原函数一致：第二个参数为 true 时只认 preparedfoods_warly。
local function IsWarlyDish(foodname)
	local native = GLOBAL.IsNativeCookingProduct
	return native ~= nil and native(foodname, true) == true
end

AddPrefabPostInit("stella_cookpot", function(inst)
	if GLOBAL.TheWorld == nil or not GLOBAL.TheWorld.ismastersim then
		return
	end
	local stewer = inst.components and inst.components.stewer or nil
	if stewer == nil or stewer.Harvest == nil then
		return
	end
	local old_harvest = stewer.Harvest
	stewer.Harvest = function(self, harvester, ...)
		if self.done and not self.chef_id and harvester ~= nil and self.product ~= nil then
			-- 烹饪勋章：chef_id 为空时补记。戴着大厨勋章时这里拿不到 cook_certificate。
			if CanRecord(self.product, inst.prefab) then
				local cook_medal = EquippedGroupMedal(harvester, "cook_certificate")
				if cook_medal ~= nil then
					GLOBAL.pcall(cook_medal.HarvestFoodFn, cook_medal, self.product, harvester, inst.prefab)
				end
			end
			-- 大厨勋章亲手收获才扣沃利菜。chef_id 为空时勋章自己的 Harvest 不会调用，这里补一次。
			-- 锅名不是 portablespicer，原函数走 IsNativeCookingProduct(foodname, true) 那一支。
			if IsWarlyDish(self.product) then
				local chef_medal = EquippedGroupMedal(harvester, "chef_certificate")
				if chef_medal ~= nil then
					GLOBAL.pcall(chef_medal.HarvestFoodFn, chef_medal, self.product, harvester, inst.prefab)
				end
			end
		end
		return old_harvest(self, harvester, ...)
	end
end)
