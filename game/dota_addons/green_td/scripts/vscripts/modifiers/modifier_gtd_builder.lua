-- The builder (WC3 "Shadow"): flying, 522 speed, cannot attack or be hurt.
modifier_gtd_builder = class({})

function modifier_gtd_builder:IsHidden() return true end
function modifier_gtd_builder:IsPurgable() return false end
function modifier_gtd_builder:RemoveOnDeath() return false end

function modifier_gtd_builder:CheckState()
	return {
		[MODIFIER_STATE_FLYING] = true,
		[MODIFIER_STATE_INVULNERABLE] = true,
		[MODIFIER_STATE_NO_UNIT_COLLISION] = true,
		[MODIFIER_STATE_DISARMED] = true,
		[MODIFIER_STATE_NO_HEALTH_BAR] = true,
	}
end

function modifier_gtd_builder:DeclareFunctions()
	return { MODIFIER_PROPERTY_MOVESPEED_ABSOLUTE }
end

function modifier_gtd_builder:GetModifierMoveSpeed_Absolute()
	return 522
end
