-- Game Link: https://www.roblox.com/games/89327904149866/OTS [[ Test Game (not an actual one) ]]

local Main = {}
Main.__index = Main

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

-- // Player
local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

local CurrentCamera = workspace.CurrentCamera

local Remotes = ReplicatedStorage.GunSystem.Remotes

-- // Modules
local Utilites = require(script.Utilities)
local CameraShaker = require(script.CameraShaker)
local ShiftlockEnabler = require(script.ShiftlockEnabler)
local CharacterFramework = require(script.CharacterFramework)
local DynamicCrosshair = require(script.DynamicCrosshair)
local Config = require(ReplicatedStorage.GunSystem.Config.Config)

-- // Essentials
local FirerateCooldowns = {}

local HitsCounter = 0

-- // Functions

-- [[ Check if the key pressed matches a key inside the Keylist which has keys for most of the gaming devices ]]
local function IsInputMatched(Input: InputObject, KeyList: {EnumItem}): boolean
	for _, Key in ipairs(KeyList) do
		if Input.KeyCode == Key or Input.UserInputType == Key then
			return true
		end
	end
	
	return false
end

-- [[ Initializer ]]
function Main.New(Tool: Tool)
	local self = setmetatable({}, Main)
	local GetConfig = Utilites.GetConfig(Tool.Name)
	if GetConfig == nil then return end
	
	-- Gun Parts
	local Animations = Tool:FindFirstChild("Animations")
	local Sounds = Tool:FindFirstChild("Sounds")
	local GunParts = Tool:FindFirstChild("GunParts")
	
	self.Tool = Tool
	self.Ammo = Tool:FindFirstChild("AmmoValue")
	self.Config = GetConfig
	self.Sounds = Tool:FindFirstChild("Sounds")
	self.GunParts = GunParts
	self.UI = Player.PlayerGui.GunUIs.Frame
	
	self.OriginalCFrame = Tool.Grip
	
	if not GetConfig.SniperSight then
		self.Crosshair = DynamicCrosshair.New(nil, GetConfig.RecoilMinSpread, GetConfig.RecoilMaxSpread, GetConfig.RecoilDecreasePerSecond, GetConfig.RecoilIncreasePerSecond)
	end
	
	-- Essential booleans
	self.CanShoot = true
	self.NormalPosition = false
	self.Shooting = false
	self.Running = false
	self.FullAuto = GetConfig["FullAuto"]
	self.CanChangeModes = GetConfig["CanModeChange"]
	
	self.Humanoid = Player.Character:WaitForChild("Humanoid")
	
	-- If humanoid exists then load aniamtions
	if self.Humanoid then
		self.HandleAnimation = self.Humanoid.Animator:LoadAnimation(Animations.HandleAnimation)
		self.ShootAnimation = self.Humanoid.Animator:LoadAnimation(Animations.ShootAnimation)
		self.AimAnimation = self.Humanoid.Animator:LoadAnimation(Animations.AimAnimation)
	end
	
	return self
end

-- [[ Eqiup which is the main function ]]
function Main:Equip()
	-- Utilites as well as CharacterFramework to move arms & head with the mouse position
	CharacterFramework.Setup()
	Utilites.EnableUI(true, self.Tool.Name)
	
	-- If the gun has a sniper sight then the ZoomDistance is different
	if self.Crosshair then
		Player.CameraMinZoomDistance = 3
	else
		Player.CameraMinZoomDistance = 0
	end
	
	self.HandleAnimation:Play()
	
	self.NormalPosition = true
	
	self.UI.Ammo.Text = self.Ammo.Value
	self.UI.GunName.Text = self.Tool.Name
	
	if self.FullAuto then
		self.UI.Mode.Text = "AUTO"
	else
		self.UI.Mode.Text = "SEMI"
	end
	
	self.Tool.Grip = self.OriginalCFrame
	
	self.Sounds.EquippedSound:Play()
	
	self.InputBeganConnection = UserInputService.InputBegan:Connect(function(Input, Processed)
		if Processed then return end
		
		if IsInputMatched(Input, Config.AimKeyCodes) then
			self:Aim(true)
		end
		
		if IsInputMatched(Input, Config.ShootKeyCodes) then
			if self.NormalPosition then return end
			
			local LastFired = FirerateCooldowns[self.Tool.Name] or 0
			if tick() - LastFired < self.Config.Firerate then return end
			FirerateCooldowns[self.Tool.Name] = tick()

			self.Shooting = true

			while self.Shooting and self.CanShoot and not self.NormalPosition and self.Humanoid.Health > 0 and not self.Running do
				if self.Ammo.Value > 0 then
					self.Ammo.Value -= 1
					self.UI.Ammo.Text = tostring(self.Ammo.Value)

					Remotes.SoundHandler:FireServer(self.Sounds.Sound)
					self:Shoot()
				else
					Remotes.SoundHandler:FireServer(self.Sounds.Out)
				end

				if not self.FullAuto then
					self.Shooting = false
				end

				task.wait(self.Config.Firerate)
			end
		end
		
		if IsInputMatched(Input, Config.ReloadKeyCodes) then
			self:Reload()
		end
		
		if Input.KeyCode == Enum.KeyCode.L then
			if not self.Config["HasLaser"] then return end
			
			task.spawn(function()
				Utilites.Laser(self.GunParts.Barrel, true)
			end)
		end
		
		if Input.KeyCode == Enum.KeyCode.F then
			if not self.Config["HasFlashlight"] then return end
			
			Utilites.Flashlight(self.GunParts.Barrel, true)
		end
		
		if Input.KeyCode == Enum.KeyCode.LeftShift then
			self:Run()
		end
		
		if Input.KeyCode == Enum.KeyCode.V then
			if not self.CanChangeModes then return end
			
			self.FullAuto = not self.FullAuto
			
			if self.FullAuto then
				self.UI.Mode.Text = "AUTO"
			else
				self.UI.Mode.Text = "SEMI"
			end
		end
		
		if Input.KeyCode == Enum.KeyCode.T then
			if self.NormalPosition then return end
			
			ShiftlockEnabler.SwitchSide()
		end
	end)
	
	self.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input, Processed)
		if Processed then return end
		
		if Input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:Aim(false)
		end
		
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.Shooting = false
		end
	end)
end

-- [[ Aim Function that makes the gun be able to shoot ]]
function Main:Aim(Boolean)
	if Boolean == true and self.CanShoot then
		if self.Running then
			self:Run()
		end
		
		-- NormalPosition means if the person is aiming or not
		self.NormalPosition = false
		
		-- If the person is aiming then we want to make the crosshair not visible
		if self.Crosshair then
			Player.CameraMaxZoomDistance = 15
			
			self.Crosshair:Enable()
			ShiftlockEnabler.SetShiftLock(true)
			self.Crosshair:FollowMouse(true)
			CharacterFramework.Framework(true)
		else
			self.UI.Parent.ImageLabel.Visible = true
			
			Player.CameraMaxZoomDistance = 0
			CurrentCamera.FieldOfView = 20
			 
			task.spawn(function()
				Utilites.CameraSightRecoil(true)
			end)
			
			UserInputService.MouseDeltaSensitivity = 0.3
			
			for _, Part in pairs(self.Tool:GetDescendants()) do
				if Part:IsA("BasePart") then
					Part.Transparency = 1
				end
			end
		end

		self.HandleAnimation:Stop()
		self.AimAnimation:Play()

		self.Tool.Grip = self.Config.AimCFrame
	else
		self.NormalPosition = true
		
		Player.CameraMaxZoomDistance = 30

		if self.Crosshair then	
			self.Crosshair:Disable()
			ShiftlockEnabler.SetShiftLock(false)
			CharacterFramework.Framework(false)
		else
			self.UI.Parent.ImageLabel.Visible = false
			
			CurrentCamera.FieldOfView = 70
			UserInputService.MouseDeltaSensitivity = 1
			Utilites.CameraSightRecoil(false)
			
			for _, Part in pairs(self.Tool:GetDescendants()) do
				if Part:IsA("BasePart") then
					Part.Transparency = 0
				end
			end
		end
		
		self.HandleAnimation:Play()
		self.AimAnimation:Stop()
		
		-- Disable Laser/Flashlight if were turned on 
		Utilites.Laser(self.GunParts.Barrel, false)
		Utilites.Flashlight(self.GunParts.Barrel, false)

		self.Tool.Grip = self.OriginalCFrame
	end
end

-- [[Uneqiup which disables the whole gun and does a cleanup ]]
function Main:UnEquip()
	Utilites.EnableUI(false, self.Tool.Name)
	
	self:Aim(false)
	self.HandleAnimation:Stop()
	self.AimAnimation:Stop()
	
	if self.Crosshair then
		self.Crosshair:Destroy()
	else
		self.UI.Parent.ImageLabel.Visible = false
	end
	
	Player.CameraMinZoomDistance = 0
	
	if self.InputBeganConnection then
		self.InputBeganConnection:Disconnect()
	end
	
	if self.InputEndedConnection then
		self.InputEndedConnection:Disconnect()
	end
end

-- [[ Main Reload ]]
function Main:Reload()
	if not self.CanShoot then return end
	
	self.AimAnimation:Stop()
	self.HandleAnimation:Play()
	
	Remotes.SoundHandler:FireServer(self.Sounds, "Reload", self.Config.ReloadTime)
	
	self:Aim(false)
	self.CanShoot = false
	
	self.UI.Ammo.Text = "..."
	self.Ammo.Value = 0
	
	task.wait(self.Config["ReloadTime"])
	
	self.CanShoot = true

	self.Ammo.Value = self.Config["Ammo"]
	self.UI.Ammo.Text = self.Ammo.Value
end


-- [[ Main Shoot Function ]]
function Main:Shoot()
	local HumanoidRootPart: Part = Player.Character:FindFirstChild("HumanoidRootPart")
	
	Utilites.ArmsAnimation(1)
	Utilites.Recoil(self.Tool.Name, self.Crosshair)
	
	if not self.Config.ShotgunRounds then
		local RaycastInstance, Position, Normal, Origin, Direction
		if self.Crosshair then
			RaycastInstance, Position, Normal, Origin, Direction = self.Crosshair:Raycast()
		else
			RaycastInstance, Position, Normal, Origin, Direction = Utilites.MouseRaycast(self.Tool)
		end

		local EndPosition

		if RaycastInstance then
			EndPosition = Position

			Remotes.GunRemote:FireServer(false, 
				self.GunParts.Barrel.MuzzleFlash,
				self.GunParts.Barrel.MuzzleLight,
				RaycastInstance, 
				self.Config["HeadDamage"], 
				self.Config["BodyDamage"], 
				Normal, 
				Position
			)

			if RaycastInstance.Parent:FindFirstChildWhichIsA("Humanoid") then
				task.spawn(Utilites.HitCounter)
			end
		else
			EndPosition = Origin + (Direction.Unit * 500) 

			Remotes.GunRemote:FireServer(true, self.GunParts.Barrel.MuzzleFlash, self.GunParts.Barrel.MuzzleLight)
		end
		
		task.spawn(function()
			Utilites.CreateBullet(self.GunParts.Barrel.Position, EndPosition)
		end)
	else
		-- Shotgun does a burst of shots
		
		for i = 1, self.Config.ShotgunRoundsAmount, 1 do
			local RaycastInstance, Position, Normal, Origin, Direction = self.Crosshair:Raycast()

			local EndPosition

			if RaycastInstance then
				EndPosition = Position

				Remotes.GunRemote:FireServer(false, 
					self.GunParts.Barrel.MuzzleFlash,
					self.GunParts.Barrel.MuzzleLight,
					RaycastInstance, 
					self.Config["HeadDamage"], 
					self.Config["BodyDamage"], 
					Normal, 
					Position
				)

				if RaycastInstance.Parent:FindFirstChildWhichIsA("Humanoid") then
					task.spawn(Utilites.HitCounter)
				end
			else
				EndPosition = Origin + (Direction.Unit * 500) 

				Remotes.GunRemote:FireServer(true, self.GunParts.Barrel.MuzzleFlash, self.GunParts.Barrel.MuzzleLight)
			end
			
			task.spawn(function()
				Utilites.CreateBullet(self.GunParts.Barrel.Position, EndPosition)
			end)
		end
	end
end

-- [[Run Function done via server]]
function Main:Run()
	self.Running = not self.Running
	self.Shooting = false
	
	if not self.NormalPosition then
		self:Aim()
	end
	
	Remotes.RunRemote:FireServer(self.Running, self.Config["RunSpeed"])
end

return Main
