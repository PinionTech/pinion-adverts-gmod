AddCSLuaFile("pinion.lua")

local Pinion = {}
if SERVER then
	Pinion.motd_url = CreateConVar("pinion_motd_url", "http://motd.pinion.gg/COMMUNITY/GAME/motd.html", FCVAR_ARCHIVE, "URL to to your MOTD")
	Pinion.motd_title = CreateConVar("pinion_motd_title", "A sponsored message from your server admin", FCVAR_ARCHIVE, "Title of your MOTD")
	Pinion.motd_required_minimum = CreateConVar("pinion_motd_min_time", "0", FCVAR_ARCHIVE, "Minimum required viewing time in seconds")
	Pinion.motd_immunity = CreateConVar("pinion_motd_immunity", "0", FCVAR_ARCHIVE, "Set to 1 to allow immunity based on user's group")
	Pinion.motd_immunity_group = CreateConVar("pinion_motd_immunity_group", "admin", FCVAR_ARCHIVE, "Set to the group you would like to give immunity to")
end

Pinion.MOTD = nil
Pinion.StartTime = nil
Pinion.MinimumTime = nil

Pinion.ConnectedThisMap = {}
Pinion.TRIGGER_CONNECT = 1
Pinion.TRIGGER_LEVELCHANGE = 2

local function pretty_print_ip(ip)
	return string.format("%u.%u.%u.%u", 
							bit.band(bit.rshift(ip, 24), 0xFF),
							bit.band(bit.rshift(ip, 16), 0xFF),
							bit.band(bit.rshift(ip, 8), 0xFF),
							bit.band(ip, 0xFF))
end

function Pinion:CreateMOTDPanel(title, url, minimum, ip, port, steamid, trigger_type)
	local ip = pretty_print_ip(ip)
	local query_string = string.format("?steamID=%s&ip=%s&port=%u&trigger=%u", steamid, ip, port, trigger_type)
	local url = url .. query_string
	
	local w, h = ScrW()*0.9, ScrH()*0.9
	self.MOTD = vgui.Create("DFrame")
	self.MOTD:ShowCloseButton(false)
	self.MOTD:SetScreenLock(true)
	self.MOTD:SetTitle(title)
	self.MOTD:SetSize(w, h)
	self.MOTD:Center()
	
	self.MOTD.HTML = vgui.Create("DHTML", self.MOTD)
	self.MOTD.HTML:SetPos(0, 25)
	self.MOTD.HTML:SetSize(w, h - 75)
	self.MOTD.HTML:OpenURL(url)
	
	self.MOTD.Accept = vgui.Create("DButton", self.MOTD)
	self.MOTD.Accept:SetSize(200, 50)
	self.MOTD.Accept:SetPos((w / 2) - (self.MOTD.Accept:GetWide() / 2), h - 50)
	self.MOTD.Accept:SetText("Continue")
	self.MOTD.Accept:SetDisabled(true)
	
	self.MOTD:MakePopup()
	
	self.MOTD.BaseThink = self.MOTD.Think
	function self.MOTD:Think()
		self:BaseThink()
		if RealTime() >= Pinion.MinimumTime then
			if IsValid(LocalPlayer()) then
				self.Accept:SetText("Continue")
				self.Accept:SetDisabled(false)
				self.Think = self.BaseThink
			end
		else
			local time_remaining = math.ceil(Pinion.MinimumTime - RealTime())
			self.Accept:SetText("Continue in " .. time_remaining .. "s")
		end
	end
	
	function self.MOTD:Close()
		self:Remove()
		Pinion:MOTDClosed()
		Pinion.MOTD = nil
	end
	
	function self.MOTD.Accept:DoClick()
		Pinion.MOTD:Close()
	end
	
	self.StartTime = RealTime()
	self.MinimumTime = RealTime() + minimum
end

function Pinion:AdjustDuration(duration)
	self.MinimumTime = self.StartTime + duration
end

function Pinion:MOTDClosed()
	local time_open = RealTime() - self.StartTime
	self.MOTD.HTML:RunJavascript("windowClosed()")
	
	net.Start("PinionClosedMOTD")
	net.SendToServer()
end

function Pinion:ShowMOTDToClient(ply)
	local trigger = self.TRIGGER_LEVELCHANGE
	
	if self.ConnectedThisMap[ply:IPAddress()] then
		trigger = self.TRIGGER_CONNECT
	end
	
	local hostip, hostport = GetConVar("hostip"):GetInt(), GetConVar("hostport"):GetInt()
	local steamid = ply:SteamID()
	
	net.Start("PinionShowMOTD")
	net.WriteString(self.motd_title:GetString())
	net.WriteString(self.motd_url:GetString())
	net.WriteInt(self.motd_required_minimum:GetInt(), 16)
	net.WriteInt(hostip, 32)
	net.WriteInt(hostport, 16)
	net.WriteString(steamid)
	net.WriteInt(trigger, 8)
	net.Send(ply)
	
	local min_ad_time = self.motd_required_minimum:GetInt()
	if min_ad_time > 0 then
		ply.FetchDurationTries = 1 --math.floor(min_ad_time / 3)
		self:FetchDurationAdjustment(ply)
	end
end

function Pinion:FetchDurationAdjustment(ply)
	http.Fetch("http://adback.pinion.gg/duration/" .. ply:SteamID(), function(body, len, headers, code)
		if code == 200 then
			local duration = tonumber(body)
			if duration then
					net.Start("PinionAdjustMOTD")
					net.WriteInt(duration, 16)
					net.Send(ply)
			end
		else
			if ply.FetchDurationTries > 0 then
				ply.FetchDurationTries = ply.FetchDurationTries - 1
				timer.Simple(3, function()
					self:FetchDurationAdjustment(ply)
				end)
			end
		end
	end)
end

if SERVER then
	util.AddNetworkString("PinionShowMOTD")
	util.AddNetworkString("PinionClosedMOTD")
	util.AddNetworkString("PinionAdjustMOTD")
	
	function Pinion.ClosedMOTD(len, ply)

	end
	net.Receive("PinionClosedMOTD", Pinion.ClosedMOTD)
else
	function Pinion.DisplayMOTD(len)
		local title, url = net.ReadString(), net.ReadString()
		local minimum = net.ReadInt(16)
		local ip, port = net.ReadInt(32), net.ReadInt(16)
		local steamid = net.ReadString()
		local trigger_type = net.ReadInt(8)

		Pinion:CreateMOTDPanel(title, url, minimum, ip, port, steamid, trigger_type)
	end
	net.Receive("PinionShowMOTD", Pinion.DisplayMOTD)
	
	function Pinion.AdjustMOTD(len)
		local duration = net.ReadInt(16)
		
		if Pinion.MOTD then
			Pinion:AdjustDuration(duration)
		end
	end
	net.Receive("PinionAdjustMOTD", Pinion.AdjustMOTD)
end

--[[
hook.Add("Initialize", "Pinion:ShowMOTD", function()
end)
]]--

hook.Add("PlayerConnect", "Pinion:PlayerConnect", function(name, address)
	Pinion.ConnectedThisMap[address] = true
end)

hook.Add("PlayerInitialSpawn", "Pinion:PlayerSpawnMOTD", function(ply)
	if Pinion.motd_immunity:GetBool() then
		local group = Pinion.motd_immunity_group:GetString()
		if IsValid(ply) and ply:IsUserGroup(group) then
			return
		end
	end
	
	Pinion:ShowMOTDToClient(ply)
end)