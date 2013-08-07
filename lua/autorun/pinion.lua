AddCSLuaFile("pinion.lua")

if not Pinion then
Pinion = {}

if SERVER then
	Pinion.motd_url = CreateConVar("pinion_motd_url", "http://motd.pinion.gg/COMMUNITY/GAME/motd.html", FCVAR_ARCHIVE, "URL to to your MOTD")
	Pinion.motd_title = CreateConVar("pinion_motd_title", "A sponsored message from your server admin", FCVAR_ARCHIVE, "Title of your MOTD")
	Pinion.motd_immunity = CreateConVar("pinion_motd_immunity", "0", FCVAR_ARCHIVE, "Set to 1 to allow immunity based on user's group")
	Pinion.motd_immunity_group = CreateConVar("pinion_motd_immunity_group", "admin", FCVAR_ARCHIVE, "Set to the group you would like to give immunity to")
	Pinion.motd_show_mode = CreateConVar("pinion_motd_show_mode", "1", FCVAR_ARCHIVE, "Set to 1 to show on player connect. Set to 2 to show at opportune gamemode times")
	Pinion.motd_cooldown_time = CreateConVar("pinion_motd_cooldown_time", "300", FCVAR_ARCHIVE, "Minimum time in seconds between ads being shown to users")
	
	local gamemode = engine.ActiveGamemode()
	if file.Exists("integration/" .. gamemode .. ".lua", "LUA") then
		include("integration/" .. gamemode .. ".lua")
	end
	
	game.ConsoleCommand(file.Read("cfg/pinion.cfg", "GAME") .. "\n")
end

Pinion.PluginVersion = "1.0.0"
Pinion.MOTD = nil
Pinion.StartTime = nil
Pinion.RequiredTime = nil

Pinion.ConnectedThisMap = {}
Pinion.TRIGGER_CONNECT = 1
Pinion.TRIGGER_LEVELCHANGE = 2

Pinion.GamemodesSupportingInterrupt = {'darkrp', 'terrortown', 'zombiesurvival'}
end

local function pretty_print_ip(ip)
	return string.format("%u.%u.%u.%u", 
							bit.band(bit.rshift(ip, 24), 0xFF),
							bit.band(bit.rshift(ip, 16), 0xFF),
							bit.band(bit.rshift(ip, 8), 0xFF),
							bit.band(ip, 0xFF))
end

function Pinion:CreateMOTDPanel(title, url, duration, ip, port, steamid, trigger_type)
	local ip = pretty_print_ip(ip)
	local query_string = string.format("?steamid=%s&ip=%s&port=%u&trigger=%u&plug_ver=%s", steamid, ip, port, trigger_type, self.PluginVersion)
	local url = url .. query_string
	
	self.StartTime = RealTime()
	self.RequiredTime = RealTime() + duration
	self.HasAdjustedDuration = false
	
	local w, h = ScrW()*0.9, ScrH()*0.9
	self.MOTD = self.MOTD or vgui.Create("DFrame")
	self.MOTD:ShowCloseButton(false)
	self.MOTD:SetScreenLock(true)
	self.MOTD:SetTitle(title)
	self.MOTD:SetSize(w, h)
	self.MOTD:Center()
	
	self.MOTD.HTML = self.MOTD.HTML or vgui.Create("DHTML", self.MOTD)
	self.MOTD.HTML:SetPos(0, 25)
	self.MOTD.HTML:SetSize(w, h - 75)
	self.MOTD.HTML:OpenURL(url)
	self.MOTD.HTML:AddFunction( "motd", "close", function( param )
		-- just to be safe, we'll give the browser time to finish
		timer.Simple(3, function()
			if self.MOTD then
				self.MOTD:Remove()
				self.MOTD = nil
			end
		end)
	end )
	
	self.MOTD.Accept = self.MOTD.Accept or vgui.Create("DButton", self.MOTD)
	self.MOTD.Accept:SetSize(200, 50)
	self.MOTD.Accept:SetPos((w / 2) - (self.MOTD.Accept:GetWide() / 2), h - 50)
	self.MOTD.Accept:SetText("Please Wait")
	self.MOTD.Accept:SetDisabled(true)
	
	self.MOTD:SetVisible(true)
	self.MOTD:MakePopup()

	self.MOTD.BaseThink = self.MOTD.Think
	function self.MOTD.Think(motdpanel)
		motdpanel:BaseThink()
		if RealTime() >= self.RequiredTime then
			if IsValid(LocalPlayer()) then
				motdpanel.Accept:SetText("Continue")
				motdpanel.Accept:SetDisabled(false)
				motdpanel.Think = motdpanel.BaseThink
			end
		elseif self.HasAdjustedDuration then
			local time_remaining = math.ceil(self.RequiredTime - RealTime())
			motdpanel.Accept:SetText("Continue in " .. time_remaining .. "s")
		end
	end
	
	function self.MOTD:Close()
		self:SetVisible(false)
		Pinion:MOTDClosed()
	end
	
	function self.MOTD.Accept.DoClick(btn)
		if self.MOTD then
			self.MOTD:Close()
		end
	end
end

function Pinion:AdjustDuration(duration)
	self.RequiredTime = self.StartTime + duration
	self.HasAdjustedDuration = true
end

function Pinion:MOTDClosed()
	local time_open = RealTime() - self.StartTime
	self.MOTD.HTML:RunJavascript("windowClosed(); motd.close()")

	net.Start("PinionClosedMOTD")
	net.SendToServer()
end

function Pinion:ShowMOTD(ply)
	-- check for group based immunity
	if self.motd_immunity:GetBool() then
		local group = self.motd_immunity_group:GetString()
		if ply:IsUserGroup(group) then
			return
		end
	end
	
	-- if we've already shown an ad recently, don't show another yet
	if ply._ViewingStartTime and RealTime() < ply._ViewingStartTime + self.motd_cooldown_time:GetInt() then
		return
	end

	-- start with a duration of 4 while we fetch the adback duration
	local duration = 40
	
	self:SendMOTDToClient(ply, duration)
	
	if duration > 0 then
		timer.Simple(1, function()
			if not IsValid(ply) then return end
			
			ply._FetchDurationTries = 10
			self:GetUserAdDuration(ply, duration, self.SendMOTDAdjustment)
		end)
	end
	
	ply._LastAdDuration = duration
	ply._ViewingStartTime = RealTime()
	ply._ViewingMOTD = true
end

function Pinion:ClosedMOTD(ply)
	if not ply._ViewingMOTD then return end
	ply._ViewingMOTD = false
	
	local duration_viewed = RealTime() - (ply._ViewingStartTime)
	local completed = ply._LastAdDuration > 0 and duration_viewed > ply._LastAdDuration

	hook.Call("Pinion:PlayerViewedAd", GAMEMODE, ply, completed)
end

function Pinion:SendMOTDToClient(ply, duration)
	local trigger = self.TRIGGER_LEVELCHANGE
	
	if self.ConnectedThisMap[ply:IPAddress()] then
		trigger = self.TRIGGER_CONNECT
	end
	
	local hostip, hostport = GetConVar("hostip"):GetInt(), GetConVar("hostport"):GetInt()
	local steamid = ply:SteamID()
	
	net.Start("PinionShowMOTD")
	net.WriteString(self.motd_title:GetString())
	net.WriteString(self.motd_url:GetString())
	net.WriteInt(duration, 16)
	net.WriteInt(hostip, 32)
	net.WriteInt(hostport, 16)
	net.WriteString(steamid)
	net.WriteInt(trigger, 8)
	net.Send(ply)
end

function Pinion:SendMOTDAdjustment(ply, duration)
	net.Start("PinionAdjustMOTD")
	net.WriteInt(duration, 16)
	net.Send(ply)
end

function Pinion:GetUserAdDuration(ply, duration_sent, callback_adjust)
	if not IsValid(ply) then return end

	http.Fetch("http://adback.pinion.gg/duration/" .. ply:SteamID(), function(body, len, headers, code)
		if not IsValid(ply) then return end
		
		if code == 200 then
			local duration = tonumber(body)
			ply._LastAdDuration = duration
			if duration then
				callback_adjust(self, ply, duration)
			end
		else
			if ply._FetchDurationTries > 0 then
				ply._FetchDurationTries = ply._FetchDurationTries - 1
				timer.Simple(3, function()
					self:GetUserAdDuration(ply, duration_sent, callback_adjust)
				end)
			end
		end
	end)
end

Pinion.Net = {}
if SERVER then
	util.AddNetworkString("PinionShowMOTD")
	util.AddNetworkString("PinionClosedMOTD")
	util.AddNetworkString("PinionAdjustMOTD")
	
	function Pinion.Net.ClosedMOTD(len, ply)
		Pinion:ClosedMOTD(ply)
	end
	net.Receive("PinionClosedMOTD", Pinion.Net.ClosedMOTD)
else
	function Pinion.Net.DisplayMOTD(len)
		local title, url = net.ReadString(), net.ReadString()
		local duration = net.ReadInt(16)
		local ip, port = net.ReadInt(32), net.ReadInt(16)
		local steamid = net.ReadString()
		local trigger_type = net.ReadInt(8)

		Pinion:CreateMOTDPanel(title, url, duration, ip, port, steamid, trigger_type)
	end
	net.Receive("PinionShowMOTD", Pinion.Net.DisplayMOTD)
	
	function Pinion.Net.AdjustMOTD(len)
		local duration = net.ReadInt(16)
		
		if Pinion.MOTD then
			Pinion:AdjustDuration(duration)
		end
	end
	net.Receive("PinionAdjustMOTD", Pinion.Net.AdjustMOTD)
end

hook.Add("PlayerConnect", "Pinion:PlayerConnect", function(name, address)
	Pinion.ConnectedThisMap[address] = true
end)

hook.Add("PlayerInitialSpawn", "Pinion:PlayerSpawnMOTD", function(ply)
	if not IsValid(ply) then return end
	
	Pinion:ShowMOTD(ply)
end)

hook.Add("PlayerDeath", "Pinion:ShowAdOnDeath", function(ply)
	local gamemode = engine.ActiveGamemode()
	if not table.HasValue(Pinion.GamemodesSupportingInterrupt, gamemode) then return end
	if Pinion.motd_show_mode:GetInt() <= 1 then return end
	
	timer.Simple(2, function() 
		if not IsValid(ply) then return end
		Pinion:ShowMOTD(ply)
	end)
end)

