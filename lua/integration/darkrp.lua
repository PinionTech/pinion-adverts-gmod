local darkrp_completion = CreateConVar("pinion_darkrp_completion_amount", "0", FCVAR_ARCHIVE, "Amount of money to grant a player for completing an ad")

hook.Add("Pinion:PlayerViewedAd", "Pinion:DarkRP:AdViewReward", function(ply, completed)
	local amount = darkrp_completion:GetInt()
	if amount <= 0 then return end
	
	if completed then
		ply:AddMoney(amount)
	end
end)