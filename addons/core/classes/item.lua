--[[
	item.lua
		An item slot button
--]]

local ADDON, Addon = ...
local Item = Addon.Tipped:NewClass('Item', Addon.IsRetail and 'ItemButton' or 'Button', 'ContainerFrameItemButtonTemplate', true)
local C = LibStub('C_Everywhere').Container
local Search = LibStub('ItemSearch-1.3')

Item.BagFamilies = {
	[-3] = 'reagent',
	[0x00001] = 'quiver',
	[0x00002] = 'quiver',
	[0x00003] = 'soul',
	[0x00004] = 'soul',
	[0x00006] = 'herb',
	[0x00007] = 'enchant',
	[0x00008] = 'leather',
	[0x00009] = 'key',
	[0x00010] = 'inscribe',
	[0x00020] = 'herb',
	[0x00040] = 'enchant',
	[0x00080] = 'engineer',
	[0x00200] = 'gem',
	[0x00400] = 'mine',
 	[0x08000] = 'tackle',
 	[0x10000] = 'fridge'
}

Item.Backgrounds = {
	LAYOUT_STYLE_MODERN and 'item/weapon/1_null',
	'interface/paperdoll/ui-backpack-emptyslot'
}


--[[ Construct ]]--

function Item:New(parent, bag, slot)
	local b = self:Super(Item):New(parent)
	b:SetID(slot)
	b.bag = bag

	if b:IsVisible() then
		b:Update()
	else
		b:Show()
	end
	return b
end

function Item:Construct()
	local b = self:GetBlizzard() or self:Super(Item):Construct()
	local name = b:GetName()

	b.Flash = b:CreateAnimationGroup()
	b.IconGlow = b:CreateTexture(nil, 'OVERLAY', nil, -1)
	b.Cooldown, b.QuestBorder = _G[name .. 'Cooldown'], _G[name .. 'IconQuestTexture']
	b.UpdateTooltip = self.OnEnter

	b.newitemglowAnim:SetLooping('NONE')
	b.IconOverlay:SetAtlas('AzeriteIconFrame')
	b.QuestBorder:SetTexture(TEXTURE_ITEM_QUEST_BANG)
	b.IconGlow:SetTexture('Interface/Buttons/UI-ActionButton-Border')
	b.IconGlow:SetBlendMode('ADD')
	b.IconGlow:SetPoint('CENTER')
	b.IconGlow:SetSize(67, 67)

	for i = 1, 3 do
		local fade = b.Flash:CreateAnimation('Alpha')
		fade:SetOrder(i * 2)
		fade:SetDuration(.2)
		fade:SetFromAlpha(.8)
		fade:SetToAlpha(0)

		local fade = b.Flash:CreateAnimation('Alpha')
		fade:SetOrder(i * 2 + 1)
		fade:SetDuration(.3)
		fade:SetFromAlpha(0)
		fade:SetToAlpha(.8)
	end

	b:SetScript('OnEvent', nil)
	b:SetScript('OnShow', b.OnShow)
	b:SetScript('OnHide', b.OnHide)
	b:SetScript('OnEnter', b.OnEnter)
	b:SetScript('OnLeave', b.OnLeave)
	b:SetScript('PreClick', b.OnPreClick)
	b:HookScript('OnClick', b.OnPostClick)
	return b
end

function Item:GetBlizzard(id)
    if not Addon.sets.displayBlizzard and Addon.Frames:AreBasicsEnabled() then
		local id = self:NumFrames() + 1
		local bag = ceil(id / 36)
		local slot = (id-1) % 36 + 1
		local b = _G[format('ContainerFrame%dItem%d', bag, slot)]
		if b then
			b:ClearAllPoints()
			return self:Bind(b)
		end
    end
end

function Item:Bind(frame)
	for k in pairs(frame) do
		if self[k] then
			frame[k] = nil
		end
	end

	local class = self
	while class do
		for k,v in pairs(class) do
			frame[k] = frame[k] or v
		end

		class = class:GetSuper()
	end

	return frame
end


--[[ Interaction ]]--

function Item:OnShow()
	self:RegisterFrameSignal('FOCUS_BAG', 'UpdateFocus')
	self:RegisterSignal('SEARCH_CHANGED', 'UpdateSearch')
	self:RegisterSignal('SEARCH_TOGGLED', 'UpdateSearch')
	self:RegisterSignal('FLASH_ITEM', 'OnItemFlashed')
	self:Update()
end

function Item:OnHide()
	if self.hasStackSplit == 1 then
		StackSplitFrame:Hide()
	end

	self:MarkSeen()
	self:UnregisterAll()
end

function Item:OnPreClick(button)
	if not IsModifiedClick() and button == 'RightButton' then
		if REAGENTBANK_CONTAINER and Addon:InBank() and IsReagentBankUnlocked() and C.GetContainerNumFreeSlots(REAGENTBANK_CONTAINER) > 0 then
			if not Addon:IsReagents(self:GetBag()) and select(17, GetItemInfo(self.info.id)) then
				for _, bag in ipairs {BANK_CONTAINER, 5, 6, 7, 8, 9, 10, 11} do
					for slot = 1, C.GetContainerNumSlots(bag) do
						if C.GetContainerItemID(bag, slot) == self.info.id then
							local free = self.info.stack - C.GetContainerItemInfo(bag, slot).stackCount
							if free > 0 then
								C.SplitContainerItem(self:GetBag(), self:GetID(), min(self.info.count, free))
								C.PickupContainerItem(bag, slot)
							end
						end
					end
				end

				C.UseContainerItem(self:GetBag(), self:GetID(), nil, true)
			end
		end
	end

	self.locked = self.info.locked
end

function Item:OnPostClick(button)
	if self:FlashFind(button) or IsModifiedClick() then
		return
	elseif button == 'RightButton' and Addon:InVault() and self.locked then
		for i = 10, 1, -1 do
			if GetVoidTransferDepositInfo(i) == self.info.id then
				ClickVoidTransferDepositSlot(i, true)
			end
		end
	end
end

function Item:OnEnter()
	if self.info.cached then
		self:AttachDummy()
	elseif self.hasItem then
		self:ShowTooltip()
		self:MarkSeen()
	end
end

function Item:OnLeave()
	self:Super(Item):OnLeave()
	ResetCursor()
end


--[[ Update ]]--

function Item:Update()
	self.info = self:GetInfo()
	self.hasItem = self.info.id and true -- for blizzard template
	self.readable = self.info.readable -- for blizzard template
	self:Delay(0.05, 'UpdateSecondary')
	self:UpdateSlotColor()
	self:UpdateCooldown()
	self:UpdateBorder()

	SetItemButtonTexture(self, self.info.icon or self.Backgrounds[Addon.sets.slotBackground])
	SetItemButtonCount(self, self.info.count)
end

function Item:UpdateSecondary()
	if self:GetFrame() then
		self:UpdateFocus()
		self:UpdateSearch()
		self:UpdateUpgradeIcon()
		self:UpdateNewItemAnimation()

		if self.hasItem and GameTooltip:IsOwned(self) then
			self:ShowTooltip()
		end
	end
end

function Item:UpdateLocked()
	self.info = self:GetInfo()
	self:SetLocked(self.info.locked)
end


--[[ Basic Appearance ]]--

function Item:UpdateBorder()
	local quality, id = self.info.quality, self.info.id
	local quest, bang = self:GetQuestInfo()
	local r,g,b

	SetItemButtonQuality(self, quality, self.info.link, false, self.info.isBound)

	if id then
		if Addon.sets.glowQuest and quest or bang then
			r,g,b = 1, .82, .2
		elseif Addon.sets.glowUnusable and Search:IsUnusable(id) then
			r,g,b = RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b
		elseif Addon.sets.glowSets and Search:BelongsToSet(id) then
	  		r,g,b = .2, 1, .8
		elseif Addon.sets.glowQuality and quality and quality > 1 then
			r,g,b = GetItemQualityColor(quality)
		end

		if r then
			self.IconGlow:SetVertexColor(r,g,b, Addon.sets.glowAlpha)
			self.IconBorder:SetVertexColor(r,g,b)
		end
	end

	self.IconGlow:SetShown(r)
	self.IconBorder:SetShown(r)
	self.QuestBorder:SetShown(bang)
	self.JunkIcon:SetShown(Addon.sets.glowPoor and quality == 0 and not self.info.worthless)
end

function Item:UpdateSlotColor()
	if not self.hasItem then
		local color = Addon.sets.colorSlots and Addon.sets[self:GetBagFamily() .. 'Color'] or {}
		local r,g,b = color[1] or 1, color[2] or 1, color[3] or 1

		SetItemButtonTextureVertexColor(self, r,g,b)
		self:GetNormalTexture():SetVertexColor(r,g,b)
	else
		self:GetNormalTexture():SetVertexColor(1,1,1)
	end
end

function Item:UpdateCooldown()
	if self.hasItem and not self.info.cached then
		local start, duration, enable = C.GetContainerItemCooldown(self:GetBag(), self:GetID())
		local fade = duration > 0 and 0.4 or 1

		CooldownFrame_Set(self.Cooldown, start, duration, enable)
		SetItemButtonTextureVertexColor(self, fade,fade,fade)
	else
		CooldownFrame_Set(self.Cooldown, 0,0,0)
		self.Cooldown:Hide()
	end
end

function Item:SetLocked(locked)
	SetItemButtonDesaturated(self, locked)
end


--[[ Secondary Highlights ]]--

function Item:UpdateSearch()
	local search = Addon.canSearch and Addon.search or ''
	local matches = search == '' or self.hasItem and Search:Matches(self:GetQuery(), search)

	self:SetAlpha(matches and 1 or 0.3)
	self:SetLocked(not matches or self.info.locked)
end

function Item:UpdateFocus()
	if self:GetBag() == self:GetFrame().focusedBag then
		self:LockHighlight()
	else
		self:UnlockHighlight()
	end
end

function Item:UpdateUpgradeIcon()
	local isUpgrade = self:IsUpgrade()
	if isUpgrade == nil then
		self:Delay(0.5, 'UpdateUpgradeIcon')
	else
		self.UpgradeIcon:SetShown(isUpgrade)
	end
end

function Item:UpdateNewItemAnimation()
	local new = Addon.sets.glowNew and self:IsNew()

	self.BattlepayItemTexture:SetShown(new and self:IsPaid())
	self.NewItemTexture:SetShown(new)

	if new then
		self.NewItemTexture:SetAtlas(quality and NEW_ITEM_ATLAS_BY_QUALITY[quality] or 'bags-glow-white')
		self.newitemglowAnim:Play()
		self.flashAnim:Play()
	end
end

function Item:MarkSeen()
	if self.NewItemTexture:IsShown() then
		C_NewItems.RemoveNewItem(self:GetBag(), self:GetID())
		self:UpdateNewItemAnimation()
	end
end

function Item:FlashFind(mouse)
	if IsAltKeyDown() and mouse == 'LeftButton' and Addon.sets.flashFind and self.info.id then
		self:SendSignal('FLASH_ITEM', self.info.id)
		return true
	end
end

function Item:OnItemFlashed(_, itemID)
	self.Flash:Stop()
	if self.info.id == itemID then
		self.Flash:Play()
	end
end


--[[ Tooltip ]]--

function Item:ShowTooltip()
	(self:GetInventorySlot() and BankFrameItemButton_OnEnter or
		ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnUpdate or ContainerFrameItemButton_OnEnter)(self)
end

function Item:AttachDummy()
	if not Item.Dummy then
		local function updateTip(slot)
			local parent = slot:GetParent()
			local link = parent.info.link
			if link then
				GameTooltip:SetOwner(parent:GetTipAnchor())
				parent:LockHighlight()
				CursorUpdate(parent)

				if link:find('battlepet:') then
					local _, specie, level, quality, health, power, speed = strsplit(':', link)
					local name = link:match('%[(.-)%]')

					BattlePetToolTip_Show(tonumber(specie), level, tonumber(quality), health, power, speed, name)
				else
					GameTooltip:SetHyperlink(link)
					GameTooltip:Show()
				end
			end
		end

		Item.Dummy = CreateFrame('Button')
		Item.Dummy:SetScript('OnEnter', updateTip)
		Item.Dummy:SetScript('OnShow', updateTip)
		Item.Dummy:RegisterForClicks('anyUp')
		Item.Dummy:SetToplevel(true)

		Item.Dummy:SetScript('OnClick', function(dummy, button)
			local parent = dummy:GetParent()
			if not HandleModifiedItemClick(parent.info.link) then
				parent:FlashFind(button)
			end
		end)

		Item.Dummy:SetScript('OnLeave', function(dummy)
			dummy:GetParent():UnlockHighlight()
			dummy:GetParent():OnLeave()
			dummy:Hide()
		end)
	end

	Item.Dummy:SetParent(self)
	Item.Dummy:SetAllPoints()
	Item.Dummy:Show()
end


--[[ Proprieties ]]--

function Item:GetBag()
	return self.bag
end

function Item:GetBagFamily()
	local bag = self:GetFrame():GetBagInfo(self:GetBag())
	return self.BagFamilies[bag.family] or 'normal'
end

function Item:GetInventorySlot()
	local bag = self:GetBag()
	local api = Addon:IsBank(bag) and BankButtonIDToInvSlotID or
							Addon:IsKeyring(bag) and KeyRingButtonIDToInvSlotID or
							Addon:IsReagents(bag) and ReagentBankButtonIDToInvSlotID
	return api and api(self:GetID())
end

function Item:GetQuery()
	return {bagID = self:GetBag(), slotIndex = self:GetID()}
end

function Item:GetInfo()
	return self:GetFrame():GetItemInfo(self:GetBag(), self:GetID())
end

function Item:GetQuestInfo()
	if self.hasItem then
		if not self.info.cached and C.GetContainerItemQuestInfo then
			local info = C.GetContainerItemQuestInfo(self:GetBag(), self:GetID())
			if info then
				return info.isQuestItem, (info.questID and not info.isActive)
			end
		else
			return Search:IsQuestItem(self.info.id)
		end
	end
end

function Item:IsSlot(bag, slot)
	return self:GetBag() == bag and self:GetID() == slot
end

function Item:IsNew()
	return self:GetBag() and C_NewItems.IsNewItem(self:GetBag(), self:GetID())
end

function Item:IsPaid()
	return C_Container.IsBattlePayItem(self:GetBag(), self:GetID())
end

function Item:IsUpgrade()
	if self.hasItem then
		if PawnShouldItemLinkHaveUpgradeArrow then
			return PawnShouldItemLinkHaveUpgradeArrow(self:GetItem()) or false
		elseif IsContainerItemAnUpgrade then
			return not self.info.cached and IsContainerItemAnUpgrade(self:GetBag(), self:GetID())
		end
	end
	return false
end
