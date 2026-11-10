--[[ ═════════════════════════════════════════════════════════
  TNThud v10.0 — Blox Fruits (Auto Farm State Machine + Bay hết snap back)
  • Bay: BodyVelocity + BodyGyro (ổn định mobile), KHÔNG ChangeState(11) — hết snap back
    fade mượt 0.25s khi tắt, character giữ nguyên vị trí
  • Auto Click: module độc lập, ~12 click/sec, subscriber pattern
    khi bật Auto Farm/Boss/Raid/KillAura → auto subscribe, tắt → auto unsubscribe
    KHÔNG cần chạm màn hình thủ công nữa
  • Auto Farm State Machine: CHECK_LEVEL → SELECT_QUEST → ACCEPT → VERIFY →
    FIND_TARGET → FARMING → CHECK_PROGRESS → QUEST_DONE → next
    parse "X/Y" từ quest title, chỉ đánh đúng số quái cần thiết
  • Bring Mob: chỉ kéo N mob gần nhất (N = quest còn lại),
    MaxForce chỉ trục X/Z (mob KHÔNG bay lên trời), hitbox 25 (không quá to)
  • Mobile: 1 vòng quét MobCache duy nhất, giới hạn ESP, AutoClick rate-controlled
═════════════════════════════════════════════════════════ ]]
local Players=game:GetService("Players") local RS=game:GetService("RunService")
local UIS=game:GetService("UserInputService") local TS=game:GetService("TweenService")
local ReSto=game:GetService("ReplicatedStorage") local WS=game:GetService("Workspace")
local Light=game:GetService("Lighting") local HS=game:GetService("HttpService")
local SG=game:GetService("StarterGui") local VU=game:GetService("VirtualUser")
local TPS=game:GetService("TeleportService")
local LP=Players.LocalPlayer local Cam=WS.CurrentCamera
local IS_MOB=UIS.TouchEnabled and not UIS.KeyboardEnabled

-- ===== SEA theo PlaceId (cả PlaceId mới) =====
local SEA=0
if game.PlaceId==2753915549 or game.PlaceId==85211729168715 then SEA=1
elseif game.PlaceId==4442272183 or game.PlaceId==79091703265657 then SEA=2
elseif game.PlaceId==7449423635 or game.PlaceId==100117331123089 then SEA=3 end

-- ===== UTIL =====
local function notify(t,x,d) pcall(function() SG:SetCore("SendNotification",{Title=t,Text=x,Duration=d or 3}) end) end
local function getGui() if gethui then return gethui() end local ok,g=pcall(function() if not RS:IsStudio() then return game:GetService("CoreGui") end end) return (ok and g) or LP:WaitForChild("PlayerGui") end
local function make(c,p) local i=Instance.new(c) if p then for k,v in pairs(p) do i[k]=v end end return i end
local function corner(p,r) make("UICorner",{CornerRadius=UDim.new(0,r or 8),Parent=p}) end
local function stroke(p,c) make("UIStroke",{Color=c or Color3.fromRGB(96,60,160),Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Parent=p}) end
local function grad(p,c1,c2,r) make("UIGradient",{Color=ColorSequence.new(c1,c2),Rotation=r or 90,Parent=p}) end
local function tw(o,pr,t) TS:Create(o,TweenInfo.new(t or .2),pr):Play() end
local function chr() return LP.Character end
local function hrp() local c=chr() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c=chr() return c and c:FindFirstChildOfClass("Humanoid") end

-- ===== FRUIT NAME PARSER (tên thật của trái ác quỷ) =====
local FRUIT_EMOJI={
    ["Rocket"]="🚀",["Spin"]="🌀",["Chop"]="💥",["Spring"]="🌱",["Bomb"]="💣",["Smoke"]="💨",
    ["Spike"]="🌵",["Flame"]="🔥",["Falcon"]="🦅",["Ice"]="❄️",["Sand"]="⏳",["Dark"]="🌑",
    ["Diamond"]="💎",["Light"]="💡",["Rubber"]="🟡",["Barrier"]="🛡️",["Magma"]="🌋",["Door"]="🚪",
    ["Leopard"]="🐆",["Dough"]="🍩",["Venom"]="🐍",["Shadow"]="👤",["Control"]="🎮",["Spirit"]="👻",
    ["Gravity"]="🌍",["Paw"]="🐾",["Phoenix"]="🦅",["Rumble"]="⚡",["Buddha"]="🧘",["Spider"]="🕷️",
    ["Sound"]="🎵",["Dragon"]="🐉",["Kitsune"]="🦊",["T-Rex"]="🦖",["Gas"]="☁️",["Blizzard"]="🌨️",
    ["Yeti"]="🦍",["Quake"]="🌋",["String"]="🧵",["Human: Buddha"]="🧘"
}
-- "Rocket- Fruit" → "Rocket","🚀"  ;  "Spider Fruit" → "Spider","🕷️"
local function parseFruit(rawName)
    if not rawName then return "?","🍎" end
    local short=rawName:gsub("%s*%-?%s*Fruit%s*$","")
    short=short:gsub("%s*%([^)]*%)%s*$","")
    short=short:match("^%s*(.-)%s*$") or short
    return short,FRUIT_EMOJI[short] or "🍎"
end

-- ===== REMOTE CommF_ (an toàn, cache) =====
local Rem=nil
local function getRem() if Rem and Rem.Parent then return Rem end Rem=ReSto:FindFirstChild("Remotes") return Rem end
local function INV(...) -- CommF_:InvokeServer bọc pcall
    local r=getRem() if not r then return end
    local f=r:FindFirstChild("CommF_") if not f then return end
    local a={...}
    local ok,res=pcall(function() return f:InvokeServer(unpack(a)) end)
    if ok then return res end
end

-- ===== DI CHUYỂN TWEEN (chống spam tạo tween) =====
local curTween=nil local lastTgt=nil
local gui  -- forward declare (ScreenGui chính, set ở phần UI)
local sgui -- forward declare (ScreenGui Status Bar, set ở phần UI — luôn hiện)
local function toTarget(cf,spd)
    local h=hrp() if not h then return end
    spd=spd or 300
    local dist=(cf.Position-h.Position).Magnitude
    if dist<4 then return end
    if lastTgt and curTween and curTween.TweenState==Enum.TweenState.Playing and (cf.Position-lastTgt.Position).Magnitude<3 then return end
    lastTgt=cf
    if curTween then curTween:Cancel() end
    curTween=TS:Create(h,TweenInfo.new(math.max(dist/spd,0.08),Enum.EasingStyle.Linear),{CFrame=cf})
    curTween:Play()
end
local function stopMove() if curTween then curTween:Cancel() curTween=nil end lastTgt=nil end

-- ===== FLY MƯỢT (LinearVelocity smooth + AlignOrientation + Mobile joystick) =====
-- Fly v10: BodyVelocity + BodyGyro (ổn định mobile, hết snap back)
-- LV/AO cũ gây "quay về vị trí cũ" vì ChangeState(11) trigger reset physics
local Fly={On=false,Speed=100,BV=nil,BG=nil,Conn=nil,CurrVel=Vector3.zero,
          Joy={X=0,Y=0,Up=false,Down=false},JoyUI=nil,JoyConn={},FadeConn=nil,Stopping=false,Goto=nil}
local function buildJoyUI()
    if Fly.JoyUI or not IS_MOB or not sgui then return end
    local j=make("Frame",{Size=UDim2.new(0,150,0,150),Position=UDim2.new(0,18,1,-170),
        BackgroundColor3=C.Bg2,BackgroundTransparency=.25,BorderSizePixel=0,Visible=false,Parent=sgui})
    corner(j,75) stroke(j,C.Primary)
    make("TextLabel",{Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,0,-18),BackgroundTransparency=1,
        Text="✈ Joystick Bay",Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Accent,Parent=j})
    local knob=make("Frame",{Size=UDim2.new(0,42,0,42),Position=UDim2.new(0.5,-21,0.5,-21),
        BackgroundColor3=C.Primary,BorderSizePixel=0,Parent=j}) corner(knob,21)
    local up=make("TextButton",{Size=UDim2.new(0,46,0,46),Position=UDim2.new(1,8,0,8),BackgroundColor3=C.Bg3,Text="▲",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=C.Text,AutoButtonColor=false,BorderSizePixel=0,Parent=j}) corner(up,8)
    local dn=make("TextButton",{Size=UDim2.new(0,46,0,46),Position=UDim2.new(1,8,0,62),BackgroundColor3=C.Bg3,Text="▼",Font=Enum.Font.GothamBold,TextSize=18,TextColor3=C.Text,AutoButtonColor=false,BorderSizePixel=0,Parent=j}) corner(dn,8)
    local dragging=false
    local c1=j.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true end
    end)
    local c2=UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then
            local cp=j.AbsolutePosition local sz=j.AbsoluteSize
            local dx=math.clamp((i.Position.X-(cp.X+sz.X/2))/math.max(1,sz.X/2-12),-1,1)
            local dy=math.clamp((i.Position.Y-(cp.Y+sz.Y/2))/math.max(1,sz.Y/2-12),-1,1)
            Fly.Joy.X=dx Fly.Joy.Y=dy
            knob.Position=UDim2.new(0.5,-21+dx*(sz.X/2-21),0.5,-21+dy*(sz.Y/2-21))
        end
    end)
    local c3=UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
            if dragging then dragging=false Fly.Joy.X=0 Fly.Joy.Y=0 tw(knob,{Position=UDim2.new(0.5,-21,0.5,-21)},0.15) end
        end
    end)
    local function bind(btn,field)
        btn.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then Fly.Joy[field]=true end end)
        btn.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then Fly.Joy[field]=false end end)
    end
    bind(up,"Up") bind(dn,"Down")
    Fly.JoyConn={c1,c2,c3}
    Fly.JoyUI=j
end
function Fly:DestroyInternal()
    if self.Conn then self.Conn:Disconnect() self.Conn=nil end
    if self.FadeConn then self.FadeConn:Disconnect() self.FadeConn=nil end
    if self.BV then self.BV:Destroy() self.BV=nil end
    if self.BG then self.BG:Destroy() self.BG=nil end
    -- QUAN TRỌNG: KHÔNG gọi ChangeState(11) — đó là nguyên nhân "snap back"
    -- Server thấy humanoid reset state → "sửa" character về vị trí cuối nó biết
    -- Chỉ tắt PlatformStand cho humanoid tự kiểm soát lại
    local h=hum() if h then pcall(function() h.PlatformStand=false end) end
    self.CurrVel=Vector3.zero
    self.Stopping=false
    if self.JoyUI then self.JoyUI.Visible=false end
end
function Fly:Stop()
    if self.Stopping then return end
    self.Stopping=true
    self.Goto=nil
    if self.Conn then self.Conn:Disconnect() self.Conn=nil end
    if self.JoyUI then self.JoyUI.Visible=false end
    self.Joy.X=0 self.Joy.Y=0 self.Joy.Up=false self.Joy.Down=false
    -- Fade mượt 0.25s: set velocity=0 NGAY (không lerp dài), giữ BV 1 frame cho server sync
    -- rồi mới destroy — tránh bị "snap back" do PlatformStand tắt khi còn momentum
    if self.BV and self.BV.Parent then
        self.BV.Velocity=Vector3.zero
        if self.BG and self.BG.Parent then
            -- ngừng giữ orientation để humanoid tự đứng lại
            self.BG.MaxTorque=Vector3.new(0,0,0)
        end
        if self.FadeConn then self.FadeConn:Disconnect() end
        local fadeStart=tick()
        self.FadeConn=RS.Heartbeat:Connect(function()
            if not self.BV or not self.BV.Parent or tick()-fadeStart>0.25 then
                if self.FadeConn then self.FadeConn:Disconnect() self.FadeConn=nil end
                self:DestroyInternal()
            end
        end)
    else
        self:DestroyInternal()
    end
end
function Fly:Start()
    if self.FadeConn then self.FadeConn:Disconnect() self.FadeConn=nil end
    self.Stopping=false
    self:DestroyInternal() local h=hrp() if not h then return end
    buildJoyUI()
    -- BodyVelocity: ổn định trên mobile, không bị "snap back" khi destroy
    -- (LinearVelocity + AlignOrientation cũ có vấn đề với network ownership)
    self.BV=Instance.new("BodyVelocity")
    self.BV.MaxForce=Vector3.new(math.huge,math.huge,math.huge)
    self.BV.Velocity=Vector3.zero
    self.BV.Parent=h
    -- BodyGyro: giữ orientation mượt (P=5000 D=100 = smooth, không snap)
    self.BG=Instance.new("BodyGyro")
    self.BG.MaxTorque=Vector3.new(math.huge,math.huge,math.huge)
    self.BG.D=100
    self.BG.P=5000
    self.BG.CFrame=h.CFrame
    self.BG.Parent=h
    local hm=hum() if hm then hm.PlatformStand=true end
    self.CurrVel=Vector3.zero
    if self.JoyUI then self.JoyUI.Visible=true end
    -- Heartbeat = đồng bộ physics, mượt hơn RenderStepped
    self.Conn=RS.Heartbeat:Connect(function()
        if not self.On then return end
        local h2=hrp() if not h2 then return end
        local cc=Cam.CFrame
        -- Auto-bay tới target (vd trái ác quỷ)
        if self.Goto then
            local tgtPos=self.Goto
            local dir=tgtPos-h2.Position
            local dist=dir.Magnitude
            if dist<8 then
                self.Goto=nil
                notify("Bay","✅ Đã tới nơi!",2)
            else
                local sp=dist<60 and self.Speed*0.6 or self.Speed
                self.CurrVel=self.CurrVel:Lerp(dir.Unit*sp,0.10)
                self.BG.CFrame=CFrame.new(h2.Position,tgtPos)
                self.BV.Velocity=self.CurrVel
                return
            end
        end
        local m=Vector3.zero
        self.BG.CFrame=CFrame.new(h2.Position,h2.Position+cc.LookVector)
        if IS_MOB then
            -- joystick: Y âm (lên trên) = forward, dương (xuống dưới) = back
            m=cc.LookVector*(-self.Joy.Y)+cc.RightVector*self.Joy.X
            if self.Joy.Up then m=m+Vector3.new(0,1,0) end
            if self.Joy.Down then m=m-Vector3.new(0,1,0) end
        else
            if UIS:IsKeyDown(Enum.KeyCode.W) then m=m+cc.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then m=m-cc.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then m=m-cc.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then m=m+cc.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then m=m+Vector3.new(0,1,0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then m=m-Vector3.new(0,1,0) end
        end
        local tgt
        if m.Magnitude>0.01 then
            tgt=m.Unit*self.Speed
            -- lerp alpha 0.10 = tăng tốc mượt, không bị dựt
            self.CurrVel=self.CurrVel:Lerp(tgt,0.10)
        else
            -- không input → giảm velocity mượt về 0
            self.CurrVel=self.CurrVel:Lerp(Vector3.zero,0.15)
        end
        self.BV.Velocity=self.CurrVel
    end)
end
-- Bay tự động tới vị trí (dùng cho nút "Bay tới Ác Quỷ")
function Fly:GotoTarget(pos)
    if not pos then return end
    self.Goto=pos
    if not self.On then
        self.On=true
        self:Start()
    end
end
function Fly:Toggle(v) self.On=v if v then self:Start() else self:Stop() end end
LP.CharacterAdded:Connect(function() task.wait(1) if Fly.On then Fly:Stop() task.wait(.3) Fly:Start() end end)

-- ===== AUTO CLICK CONTROLLER (thay thế Auto Attack cũ) =====
-- Tự chạm/nhấn liên tục, không cần chạm màn hình thủ công
-- Subscriber pattern: nhiều module dùng chung 1 loop duy nhất (không chồng chéo)
local AutoClick={Loop=nil,Subs=0,LastClick=0}
function AutoClick:Subscribe()
    self.Subs=self.Subs+1
    self:Update()
end
function AutoClick:Unsubscribe()
    self.Subs=math.max(0,self.Subs-1)
    self:Update()
end
function AutoClick:Update()
    if self.Subs>0 and not self.Loop then
        self:Start()
    elseif self.Subs==0 and self.Loop then
        self:Stop()
    end
end
function AutoClick:Start()
    if self.Loop then return end
    self.Loop=task.spawn(function()
        while self.Subs>0 do
            pcall(function()
                -- Method 1: VirtualUser click (universal - mobile + PC)
                pcall(function()
                    VU:CaptureController()
                    VU:Button1Down(Vector2.new(1280,672))
                    task.wait()
                    VU:Button1Up(Vector2.new(1280,672))
                end)
                -- Method 2: Activate equipped tool
                pcall(function()
                    local c=chr() if c then
                        local t=c:FindFirstChildOfClass("Tool")
                        if t then
                            t:Activate()
                            -- Method 3: Blox Fruits LeftClickRemote (direct)
                            if t:FindFirstChild("LeftClickRemote") then
                                t.LeftClickRemote:FireServer(Vector3.new(0,-1,0),1)
                            end
                        end
                    end
                end)
            end)
            task.wait(0.08)  -- ~12 click/sec - đủ nhanh, không spam gây lag
        end
        self.Loop=nil
    end)
end
function AutoClick:Stop()
    if self.Loop then task.cancel(self.Loop) self.Loop=nil end
    self.Subs=0  -- reset khi tắt hoàn toàn
end
function AutoClick:IsRunning() return self.Subs>0 end

-- ===== DATA 83 QUEST (tọa độ thật) =====
local Q={
{lv=1,hx=9,ms="Bandit [Lv. 5]",q="BanditQuest1",n=1,m="Bandit",cq=CFrame.new(1061.66699,16.5166187,1544.52905),cm=CFrame.new(1199.31287,52.2717781,1536.91516)},
{lv=10,hx=14,ms="Monkey [Lv. 14]",q="JungleQuest",n=1,m="Monkey",cq=CFrame.new(-1604.12012,36.8521118,154.23732),cm=CFrame.new(-1772.4093,60.860641,54.872589)},
{lv=15,hx=29,ms="Gorilla [Lv. 20]",q="JungleQuest",n=2,m="Gorilla",cq=CFrame.new(-1604.12012,36.8521118,154.23732),cm=CFrame.new(-1223.52808,6.279364,-502.292664)},
{lv=30,hx=39,ms="Pirate [Lv. 35]",q="BuggyQuest1",n=1,m="Pirate",cq=CFrame.new(-1139.59717,4.752052,3825.16211),cm=CFrame.new(-1219.32324,4.752052,3915.63452)},
{lv=40,hx=59,ms="Brute [Lv. 45]",q="BuggyQuest1",n=2,m="Brute",cq=CFrame.new(-1139.59717,4.752052,3825.16211),cm=CFrame.new(-1146.49646,96.093681,4312.1333)},
{lv=60,hx=74,ms="Desert Bandit [Lv. 60]",q="DesertQuest",n=1,m="Desert Bandit",cq=CFrame.new(897.031128,6.438464,4388.9716),cm=CFrame.new(932.788818,6.450375,4488.24609)},
{lv=75,hx=89,ms="Desert Officer [Lv. 70]",q="DesertQuest",n=2,m="Desert Officer",cq=CFrame.new(897.031128,6.438464,4388.9716),cm=CFrame.new(1580.03198,4.613758,4366.86426)},
{lv=90,hx=99,ms="Snow Bandit [Lv. 90]",q="SnowQuest",n=1,m="Snow Bandit",cq=CFrame.new(1384.14001,87.272789,-1297.06482),cm=CFrame.new(1370.24316,102.403511,-1411.52905)},
{lv=100,hx=119,ms="Snowman [Lv. 100]",q="SnowQuest",n=2,m="Snowman",cq=CFrame.new(1384.14001,87.272789,-1297.06482),cm=CFrame.new(1370.24316,102.403511,-1411.52905)},
{lv=120,hx=149,ms="Chief Petty Officer [Lv. 120]",q="MarineQuest2",n=1,m="Chief Petty Officer",cq=CFrame.new(-5035.0835,28.652039,4325.29443),cm=CFrame.new(-4882.8623,22.652039,4255.53516)},
{lv=150,hx=174,ms="Sky Bandit [Lv. 150]",q="SkyQuest",n=1,m="Sky Bandit",cq=CFrame.new(-4841.83447,717.669617,-2623.96436),cm=CFrame.new(-4970.74219,294.544342,-2890.11353)},
{lv=175,hx=224,ms="Dark Master [Lv. 175]",q="SkyQuest",n=2,m="Dark Master",cq=CFrame.new(-4841.83447,717.669617,-2623.96436),cm=CFrame.new(-5220.58594,430.693298,-2278.17456)},
{lv=225,hx=274,ms="Toga Warrior [Lv. 225]",q="ColosseumQuest",n=1,m="Toga Warrior",cq=CFrame.new(-1576.11743,7.389339,-2983.30762),cm=CFrame.new(-1779.97583,44.60775,-2736.35474)},
{lv=275,hx=299,ms="Gladiator [Lv. 275]",q="ColosseumQuest",n=2,m="Gladiator",cq=CFrame.new(-1576.11743,7.389339,-2983.30762),cm=CFrame.new(-1274.75903,58.189594,-3188.16309)},
{lv=300,hx=329,ms="Military Soldier [Lv. 300]",q="MagmaQuest",n=1,m="Military Soldier",cq=CFrame.new(-5316.55859,12.237062,8517.2998),cm=CFrame.new(-5363.01123,41.505688,8548.47266)},
{lv=330,hx=374,ms="Military Spy [Lv. 330]",q="MagmaQuest",n=2,m="Military Spy",cq=CFrame.new(-5316.55859,12.237062,8517.2998),cm=CFrame.new(-5787.99023,120.864456,8762.25293)},
{lv=375,hx=399,ms="Fishman Warrior [Lv. 375]",q="FishmanQuest",n=1,m="Fishman Warrior",cq=CFrame.new(61122.5625,18.47164,1568.16504),cm=CFrame.new(61163.85156,5.307304,1819.78418)},
{lv=400,hx=449,ms="Fishman Commando [Lv. 400]",q="FishmanQuest",n=2,m="Fishman Commando",cq=CFrame.new(61122.5625,18.47164,1568.16504),cm=CFrame.new(61163.85156,5.307304,1819.78418)},
{lv=450,hx=474,ms="God's Guard [Lv. 450]",q="SkyExp1Quest",n=1,m="God's Guard",cq=CFrame.new(-4721.71436,845.277161,-1954.20105),cm=CFrame.new(-4716.95703,853.089722,-1933.92543)},
{lv=475,hx=524,ms="Shanda [Lv. 475]",q="SkyExp1Quest",n=2,m="Shanda",cq=CFrame.new(-4721.71436,845.277161,-1954.20105),cm=CFrame.new(-7685.12354,5601.05127,-443.171509)},
{lv=525,hx=549,ms="Royal Squad [Lv. 525]",q="SkyExp2Quest",n=1,m="Royal Squad",cq=CFrame.new(-7902.66895,5635.96387,-1411.71802),cm=CFrame.new(-7685.02051,5606.87842,-1442.729)},
{lv=550,hx=624,ms="Royal Soldier [Lv. 550]",q="SkyExp2Quest",n=2,m="Royal Soldier",cq=CFrame.new(-7902.66895,5635.96387,-1411.71802),cm=CFrame.new(-7864.44775,5661.94092,-1708.22351)},
{lv=625,hx=649,ms="Galley Pirate [Lv. 625]",q="FountainQuest",n=1,m="Galley Pirate",cq=CFrame.new(5254.60156,38.501141,4049.69678),cm=CFrame.new(5595.06982,41.50137,3961.47095)},
{lv=650,hx=699,ms="Galley Captain [Lv. 650]",q="FountainQuest",n=2,m="Galley Captain",cq=CFrame.new(5254.60156,38.501141,4049.69678),cm=CFrame.new(5658.5752,38.536179,4928.93506)},
{lv=700,hx=724,ms="Raider [Lv. 700]",q="Area1Quest",n=1,m="Raider",cq=CFrame.new(-424.080078,73.005585,1836.91589),cm=CFrame.new(-737.026123,39.174835,2392.57959)},
{lv=725,hx=774,ms="Mercenary [Lv. 725]",q="Area1Quest",n=2,m="Mercenary",cq=CFrame.new(-424.080078,73.005585,1836.91589),cm=CFrame.new(-973.731995,95.873322,1836.46936)},
{lv=775,hx=874,ms="Swan Pirate [Lv. 775]",q="Area2Quest",n=1,m="Swan Pirate",cq=CFrame.new(632.698608,73.105591,918.666321),cm=CFrame.new(970.369446,142.653198,1217.3667)},
{lv=875,hx=899,ms="Marine Lieutenant [Lv. 875]",q="MarineQuest3",n=1,m="Marine Lieutenant",cq=CFrame.new(-2442.65015,73.051148,-3219.11523),cm=CFrame.new(-2913.26367,73.001183,-3321.66333)},
{lv=900,hx=949,ms="Marine Captain [Lv. 900]",q="MarineQuest3",n=2,m="Marine Captain",cq=CFrame.new(-2442.65015,73.051148,-3219.11523),cm=CFrame.new(-1868.67688,73.001183,-3321.66333)},
{lv=950,hx=974,ms="Zombie [Lv. 950]",q="ZombieQuest",n=1,m="Zombie",cq=CFrame.new(-5492.79395,48.515167,-793.710571),cm=CFrame.new(-5634.83838,126.067039,-697.665039)},
{lv=975,hx=999,ms="Vampire [Lv. 975]",q="ZombieQuest",n=2,m="Vampire",cq=CFrame.new(-5492.79395,48.515167,-793.710571),cm=CFrame.new(-6030.32031,6.437741,-1313.5564)},
{lv=1000,hx=1049,ms="Snow Trooper [Lv. 1000]",q="SnowMountainQuest",n=1,m="Snow Trooper",cq=CFrame.new(604.964966,401.457062,-5371.69287),cm=CFrame.new(535.893433,401.457062,-5329.6958)},
{lv=1050,hx=1099,ms="Winter Warrior [Lv. 1050]",q="SnowMountainQuest",n=2,m="Winter Warrior",cq=CFrame.new(604.964966,401.457062,-5371.69287),cm=CFrame.new(1223.7417,454.575226,-5170.02148)},
{lv=1100,hx=1124,ms="Lab Subordinate [Lv. 1100]",q="IceSideQuest",n=1,m="Lab Subordinate",cq=CFrame.new(-6060.10693,15.986802,-4904.7876),cm=CFrame.new(-5769.2041,37.928829,-4468.38721)},
{lv=1125,hx=1174,ms="Horned Warrior [Lv. 1125]",q="IceSideQuest",n=2,m="Horned Warrior",cq=CFrame.new(-6060.10693,15.986802,-4904.7876),cm=CFrame.new(-6400.85889,24.764515,-5818.63574)},
{lv=1175,hx=1199,ms="Magma Ninja [Lv. 1175]",q="FireSideQuest",n=1,m="Magma Ninja",cq=CFrame.new(-5431.09473,15.986802,-5296.53223),cm=CFrame.new(-5496.65576,58.689041,-5929.76855)},
{lv=1200,hx=1349,ms="Lava Pirate [Lv. 1200]",q="FireSideQuest",n=2,m="Lava Pirate",cq=CFrame.new(-5431.09473,15.986802,-5296.53223),cm=CFrame.new(-5169.71729,34.123478,-4669.73633)},
{lv=1350,hx=1374,ms="Arctic Warrior [Lv. 1350]",q="FrostQuest",n=1,m="Arctic Warrior",cq=CFrame.new(5669.43506,28.211779,-6482.60107),cm=CFrame.new(5995.07471,57.318848,-6183.47314)},
{lv=1375,hx=1424,ms="Snow Lurker [Lv. 1375]",q="FrostQuest",n=2,m="Snow Lurker",cq=CFrame.new(5669.43506,28.211779,-6482.60107),cm=CFrame.new(5518.00684,60.555973,-6828.80518)},
{lv=1425,hx=1449,ms="Sea Soldier [Lv. 1425]",q="ForgottenQuest",n=1,m="Sea Soldier",cq=CFrame.new(-3052.99097,236.881363,-10148.1943),cm=CFrame.new(-3030.36963,191.134644,-9859.7958)},
{lv=1450,hx=1499,ms="Water Fighter [Lv. 1450]",q="ForgottenQuest",n=2,m="Water Fighter",cq=CFrame.new(-3052.99097,236.881363,-10148.1943),cm=CFrame.new(-3436.77271,290.521912,-10503.438)},
{lv=1500,hx=1524,ms="Pirate Millionaire [Lv. 1500]",q="PiratePortQuest",n=1,m="Pirate Millionaire",cq=CFrame.new(-290.074677,42.903465,5581.58984),cm=CFrame.new(81.164993,43.755737,5724.702148)},
{lv=1525,hx=1574,ms="Pistol Billionaire [Lv. 1525]",q="PiratePortQuest",n=2,m="Pistol Billionaire",cq=CFrame.new(-290.074677,42.903465,5581.58984),cm=CFrame.new(81.164993,43.755737,5724.702148)},
{lv=1575,hx=1599,ms="Dragon Crew Warrior [Lv. 1575]",q="AmazonQuest",n=1,m="Dragon Crew Warrior",cq=CFrame.new(5832.83594,51.680611,-1101.51563),cm=CFrame.new(6241.995117,51.522083,-1243.97717)},
{lv=1600,hx=1624,ms="Dragon Crew Archer [Lv. 1600]",q="AmazonQuest",n=2,m="Dragon Crew Archer",cq=CFrame.new(5832.83594,51.680611,-1101.51563),cm=CFrame.new(6488.915527,383.383759,-110.66246)},
{lv=1625,hx=1649,ms="Female Islander [Lv. 1625]",q="AmazonQuest2",n=1,m="Female Islander",cq=CFrame.new(5448.86133,601.516174,751.130676),cm=CFrame.new(5825.224121,682.892456,704.57959)},
{lv=1650,hx=1699,ms="Giant Islander [Lv. 1650]",q="AmazonQuest2",n=2,m="Giant Islander",cq=CFrame.new(5448.86133,601.516174,751.130676),cm=CFrame.new(4530.354004,656.756958,-131.609527)},
{lv=1700,hx=1724,ms="Marine Commodore [Lv. 1700]",q="MarineTreeIsland",n=1,m="Marine Commodore",cq=CFrame.new(2180.54126,27.815681,-6741.5498),cm=CFrame.new(2490.084473,190.423264,-7160.050292)},
{lv=1725,hx=1774,ms="Marine Rear Admiral [Lv. 1725]",q="MarineTreeIsland",n=2,m="Marine Rear Admiral",cq=CFrame.new(2180.54126,27.815681,-6741.5498),cm=CFrame.new(3951.390381,229.115494,-6912.8164)},
{lv=1775,hx=1799,ms="Fishman Raider [Lv. 1775]",q="DeepForestIsland3",n=1,m="Fishman Raider",cq=CFrame.new(-10581.6563,330.872955,-8761.18652),cm=CFrame.new(-10322.400391,390.944733,-8580.0908)},
{lv=1800,hx=1824,ms="Fishman Captain [Lv. 1800]",q="DeepForestIsland3",n=2,m="Fishman Captain",cq=CFrame.new(-10581.6563,330.872955,-8761.18652),cm=CFrame.new(-11194.541992,442.027954,-8608.8066)},
{lv=1825,hx=1849,ms="Forest Pirate [Lv. 1825]",q="DeepForestIsland",n=1,m="Forest Pirate",cq=CFrame.new(-13234.04,331.488495,-7625.40137),cm=CFrame.new(-13225.80957,428.193878,-7753.1245)},
{lv=1850,hx=1899,ms="Mythological Pirate [Lv. 1850]",q="DeepForestIsland",n=2,m="Mythological Pirate",cq=CFrame.new(-13234.04,331.488495,-7625.40137),cm=CFrame.new(-13869.172852,564.952515,-7084.4135)},
{lv=1900,hx=1924,ms="Jungle Pirate [Lv. 1900]",q="DeepForestIsland2",n=1,m="Jungle Pirate",cq=CFrame.new(-12680.3818,389.971039,-9902.01953),cm=CFrame.new(-11982.22168,376.325226,-10451.415)},
{lv=1925,hx=1974,ms="Musketeer Pirate [Lv. 1925]",q="DeepForestIsland2",n=2,m="Musketeer Pirate",cq=CFrame.new(-12680.3818,389.971039,-9902.01953),cm=CFrame.new(-13282.304688,496.236847,-9565.15039)},
{lv=1975,hx=1999,ms="Reborn Skeleton [Lv. 1975]",q="HauntedQuest1",n=1,m="Reborn Skeleton",cq=CFrame.new(-9480.827148,142.130661,5566.07128),cm=CFrame.new(-8817.880859,191.167618,6298.655762)},
{lv=2000,hx=2024,ms="Living Zombie [Lv. 2000]",q="HauntedQuest1",n=2,m="Living Zombie",cq=CFrame.new(-9480.827148,142.130661,5566.07128),cm=CFrame.new(-10125.234375,183.947052,6242.013672)},
{lv=2025,hx=2049,ms="Demonic Soul [Lv. 2025]",q="HauntedQuest2",n=1,m="Demonic Soul",cq=CFrame.new(-9516.993164,178.006516,6078.46533),cm=CFrame.new(-9712.03125,204.695892,6193.322266)},
{lv=2050,hx=2074,ms="Posessed Mummy [Lv. 2050]",q="HauntedQuest2",n=2,m="Posessed Mummy",cq=CFrame.new(-9516.993164,178.006516,6078.46533),cm=CFrame.new(-9545.776367,69.619896,6339.56152)},
-- Sea of Treats / Tiki / Submerged (route Update mới)
{lv=2075,hx=2099,ms="Peanut Scout [Lv. 2075]",q="PeanutQuest1",n=1,m="Peanut Scout",cq=CFrame.new(-2202.74,15.14,-12354.08),cm=CFrame.new(-2202.74,15.14,-12354.08)},
{lv=2100,hx=2124,ms="Peanut President [Lv. 2100]",q="PeanutQuest2",n=2,m="Peanut President",cq=CFrame.new(-2202.74,15.14,-12354.08),cm=CFrame.new(-2202.74,15.14,-12354.08)},
{lv=2125,hx=2149,ms="Ice Cream Chef [Lv. 2125]",q="IceCreamQuest1",n=1,m="Ice Cream Chef",cq=CFrame.new(-730.54,38.35,-12629.5),cm=CFrame.new(-730.54,38.35,-12629.5)},
{lv=2150,hx=2174,ms="Ice Cream Commander [Lv. 2150]",q="IceCreamQuest2",n=2,m="Ice Cream Commander",cq=CFrame.new(-730.54,38.35,-12629.5),cm=CFrame.new(-730.54,38.35,-12629.5)},
{lv=2200,hx=2224,ms="Cookie Crafter [Lv. 2200]",q="CakeQuest1",n=1,m="Cookie Crafter",cq=CFrame.new(-383.28,79.44,-12611.5),cm=CFrame.new(-383.28,79.44,-12611.5)},
{lv=2225,hx=2249,ms="Cake Guard [Lv. 2225]",q="CakeQuest2",n=2,m="Cake Guard",cq=CFrame.new(-383.28,79.44,-12611.5),cm=CFrame.new(-383.28,79.44,-12611.5)},
{lv=2250,hx=2274,ms="Baking Staff [Lv. 2250]",q="CakeQuest3",n=1,m="Baking Staff",cq=CFrame.new(-383.28,79.44,-12611.5),cm=CFrame.new(-383.28,79.44,-12611.5)},
{lv=2275,hx=2299,ms="Head Baker [Lv. 2275]",q="CakeQuest4",n=2,m="Head Baker",cq=CFrame.new(-383.28,79.44,-12611.5),cm=CFrame.new(-383.28,79.44,-12611.5)},
{lv=2300,hx=2324,ms="Cocoa Warrior [Lv. 2300]",q="ChocolateQuest1",n=1,m="Cocoa Warrior",cq=CFrame.new(1000.15,55.19,-12498.6),cm=CFrame.new(1000.15,55.19,-12498.6)},
{lv=2325,hx=2349,ms="Chocolate Bar Battler [Lv. 2325]",q="ChocolateQuest2",n=2,m="Chocolate Bar Battler",cq=CFrame.new(1000.15,55.19,-12498.6),cm=CFrame.new(1000.15,55.19,-12498.6)},
{lv=2350,hx=2374,ms="Sweet Thief [Lv. 2350]",q="ChocolateQuest3",n=1,m="Sweet Thief",cq=CFrame.new(1000.15,55.19,-12498.6),cm=CFrame.new(1000.15,55.19,-12498.6)},
{lv=2375,hx=2399,ms="Candy Rebel [Lv. 2375]",q="ChocolateQuest4",n=2,m="Candy Rebel",cq=CFrame.new(1000.15,55.19,-12498.6),cm=CFrame.new(1000.15,55.19,-12498.6)},
{lv=2400,hx=2424,ms="Candy Pirate [Lv. 2400]",q="CandyQuest1",n=1,m="Candy Pirate",cq=CFrame.new(-1435.24,20.08,-12360.7),cm=CFrame.new(-1435.24,20.08,-12360.7)},
{lv=2425,hx=2449,ms="Snow Demon [Lv. 2425]",q="CandyQuest2",n=2,m="Snow Demon",cq=CFrame.new(-1435.24,20.08,-12360.7),cm=CFrame.new(-1435.24,20.08,-12360.7)},
{lv=2450,hx=2474,ms="Isle Outlaw [Lv. 2450]",q="TikiQuest1",n=1,m="Isle Outlaw",cq=CFrame.new(-13880.5,60.19,-10885.3),cm=CFrame.new(-13880.5,60.19,-10885.3)},
{lv=2475,hx=2499,ms="Island Boy [Lv. 2475]",q="TikiQuest2",n=2,m="Island Boy",cq=CFrame.new(-13880.5,60.19,-10885.3),cm=CFrame.new(-13880.5,60.19,-10885.3)},
{lv=2500,hx=2524,ms="Sun-kissed Warrior [Lv. 2500]",q="TikiQuest3",n=1,m="Sun-kissed Warrior",cq=CFrame.new(-13880.5,60.19,-10885.3),cm=CFrame.new(-13880.5,60.19,-10885.3)},
{lv=2525,hx=2549,ms="Isle Champion [Lv. 2525]",q="TikiQuest4",n=2,m="Isle Champion",cq=CFrame.new(-13880.5,60.19,-10885.3),cm=CFrame.new(-13880.5,60.19,-10885.3)},
{lv=2550,hx=2574,ms="Serpent Hunter [Lv. 2550]",q="TikiQuest5",n=1,m="Serpent Hunter",cq=CFrame.new(-13880.5,60.19,-10885.3),cm=CFrame.new(-13880.5,60.19,-10885.3)},
{lv=2575,hx=2599,ms="Skull Slayer [Lv. 2575]",q="TikiQuest6",n=2,m="Skull Slayer",cq=CFrame.new(-13880.5,60.19,-10885.3),cm=CFrame.new(-13880.5,60.19,-10885.3)},
{lv=2600,hx=2624,ms="Reef Bandit [Lv. 2600]",q="SubmergedQuest1",n=1,m="Reef Bandit",cq=CFrame.new(-13900,60,-12000),cm=CFrame.new(-13900,60,-12000)},
{lv=2625,hx=2649,ms="Coral Pirate [Lv. 2625]",q="SubmergedQuest2",n=2,m="Coral Pirate",cq=CFrame.new(-13900,60,-12000),cm=CFrame.new(-13900,60,-12000)},
{lv=2650,hx=2674,ms="Sea Chanter [Lv. 2650]",q="SubmergedQuest3",n=1,m="Sea Chanter",cq=CFrame.new(-13900,60,-12000),cm=CFrame.new(-13900,60,-12000)},
{lv=2675,hx=3000,ms="High Disciple [Lv. 2675]",q="SubmergedQuest4",n=2,m="High Disciple",cq=CFrame.new(-13900,60,-12000),cm=CFrame.new(-13900,60,-12000)},
}
for _,q in ipairs(Q) do q.b=q.ms:gsub(" %[Lv%. %d+%]","") if q.lv<700 then q.s=1 elseif q.lv<1500 then q.s=2 else q.s=3 end end
local function getQuest(lvl,sea)
    local best,first=nil,nil
    for _,q in ipairs(Q) do
        if q.s==sea then
            first=first or q
            if lvl>=q.lv then best=q else break end
        end
    end
    return best or first
end

-- ===== DATA MATERIAL (mob thật theo sea) =====
local MATS={
["Leather"]={{s=1,m="Pirate",p=CFrame.new(-1219.32,4.75,3915.63)},{s=3,m="Forest Pirate",p=CFrame.new(-13225.81,428.19,-7753.12)}},
["Scrap Metal"]={{s=1,m="Brute",p=CFrame.new(-1146.50,96.09,4312.13)},{s=3,m="Jungle Pirate",p=CFrame.new(-11982.22,376.33,-10451.42)}},
["Magma Ore"]={{s=1,m="Military Spy",p=CFrame.new(-5787.99,120.86,8762.25)},{s=2,m="Lava Pirate",p=CFrame.new(-5169.72,34.12,-4669.74)}},
["Bones"]={{s=1,m="Prisoner",p=CFrame.new(5311,146.4,-4940)}},
["Angel Wings"]={{s=1,m="Royal Soldier",p=CFrame.new(-7864.45,5661.94,-1708.22)}},
["Fish Tail"]={{s=1,m="Fishman Warrior",p=CFrame.new(61163.85,5.31,1819.78)},{s=3,m="Fishman Captain",p=CFrame.new(-11194.54,442.03,-8608.81)}},
["Vampire Fang"]={{s=2,m="Vampire",p=CFrame.new(-6030.32,6.44,-1313.56)}},
["Mystic Droplet"]={{s=2,m="Water Fighter",p=CFrame.new(-3436.77,290.52,-10503.44)}},
["Radioactive Material"]={{s=2,m="Factory Staff",p=CFrame.new(-507.7,72.9,-126.4)}},
["Dragon Scale"]={{s=3,m="Dragon Crew Warrior",p=CFrame.new(6242.00,51.52,-1243.98)}},
["Conjured Cocoa"]={{s=3,m="Chocolate Bar Battler",p=CFrame.new(1000.15,55.19,-12498.6)}},
["Demonic Wisp"]={{s=3,m="Demonic Soul",p=CFrame.new(-9712.03,204.70,6193.32)}},
["Gunpowder"]={{s=3,m="Pistol Billionaire",p=CFrame.new(81.16,43.76,5724.70)}},
["Mini Tusk"]={{s=3,m="Mythological Pirate",p=CFrame.new(-13869.17,564.95,-7084.41)}},
}
local function matFor(name)
    local list=MATS[name] if not list then return nil end
    for _,e in ipairs(list) do if e.s==SEA then return e end end
    return list[1],false
end

-- ===== DATA BOSS (tên thật trong workspace.Enemies) =====
local Bosses={
{n="The Saw",s=1},{n="Bobby",s=1},{n="Yeti",s=1},{n="Mob Leader",s=1},{n="Vice Admiral",s=1},
{n="Saber Expert",s=1},{n="Warden",s=1},{n="Chief Warden",s=1},{n="Swan",s=1},{n="Magma Admiral",s=1},
{n="Fishman Lord",s=1},{n="Wysper",s=1},{n="Thunder God",s=1},{n="Cyborg",s=1},{n="Greybeard",s=1},
{n="Diamond",s=2},{n="Jeremy",s=2},{n="Fajita",s=2},{n="Don Swan",s=2},{n="Smoke Admiral",s=2},
{n="Cursed Captain",s=2},{n="Awakened Ice Admiral",s=2},{n="Tide Keeper",s=2},{n="Darkbeard",s=2},{n="Order",s=2},
{n="Stone",s=3},{n="Island Empress",s=3},{n="Kilo Admiral",s=3},{n="Captain Elephant",s=3},{n="Beautiful Pirate",s=3},
{n="Longma",s=3},{n="rip_indra",s=3},{n="Soul Reaper",s=3},{n="Cake Prince",s=3},{n="Dough King",s=3},
{n="Terrorshark",s=3},{n="Leviathan",s=3},{n="Tyrant of the Skies",s=3},
}

-- ===== DATA ISLAND TP =====
local Islands={
{n="Starter Island",p=CFrame.new(1061,16,1544)},{n="Jungle",p=CFrame.new(-1604,36,154)},
{n="Pirate Village",p=CFrame.new(-1139,4,3825)},{n="Desert",p=CFrame.new(897,6,4388)},
{n="Frozen Village",p=CFrame.new(1384,87,-1297)},{n="Marine Fortress",p=CFrame.new(-5035,28,4325)},
{n="Skylands",p=CFrame.new(-4841,717,-2623)},{n="Colosseum",p=CFrame.new(-1576,7,-2983)},
{n="Prison",p=CFrame.new(5311,146,-4940)},{n="Magma Village",p=CFrame.new(-5316,12,8517)},
{n="Underwater City",p=CFrame.new(61122,18,1568)},{n="Upper Skylands",p=CFrame.new(-7902,5635,-1411)},
{n="Fountain City",p=CFrame.new(5254,38,4049)},{n="Kingdom of Rose",p=CFrame.new(-424,73,1836)},
{n="Green Zone",p=CFrame.new(-2442,73,-3219)},{n="Graveyard",p=CFrame.new(-5492,48,-793)},
{n="Snow Mountain",p=CFrame.new(604,401,-5371)},{n="Hot and Cold",p=CFrame.new(-5431,15,-5296)},
{n="Cursed Ship",p=CFrame.new(923,125,-12200)},{n="Ice Castle",p=CFrame.new(5669,28,-6482)},
{n="Forgotten Island",p=CFrame.new(-3052,236,-10148)},{n="Port Town",p=CFrame.new(-290,42,5581)},
{n="Hydra Valley",p=CFrame.new(5832,51,-1101)},{n="Great Tree",p=CFrame.new(2180,27,-6741)},
{n="Floating Turtle",p=CFrame.new(-10581,330,-8761)},{n="Haunted Castle",p=CFrame.new(-9480,142,5566)},
{n="Peanut Land",p=CFrame.new(-2202,15,-12354)},{n="Ice Cream Land",p=CFrame.new(-730,38,-12629)},
{n="Cake Land",p=CFrame.new(-383,79,-12611)},{n="Chocolate Land",p=CFrame.new(1000,55,-12498)},
{n="Candy Cane Land",p=CFrame.new(-1435,20,-12360)},{n="Tiki Outpost",p=CFrame.new(-13880,60,-10885)},
}
local SeaEvents={"Sea Beast","Terrorshark","Leviathan","Mirage Island","Kitsune Island","Frozen Dimension","Ship Raid","Pirate Raid","Rumbling Waters"}

-- ===== CORE =====
local function getLevel() local d=LP:FindFirstChild("Data") if d then local l=d:FindFirstChild("Level") if l then return l.Value end end return 0 end

-- ===== THEME =====
local C={Bg=Color3.fromRGB(15,10,25),Bg2=Color3.fromRGB(22,16,38),Bg3=Color3.fromRGB(30,22,50),
Primary=Color3.fromRGB(150,80,255),Primary2=Color3.fromRGB(170,100,255),Accent=Color3.fromRGB(180,120,255),
Text=Color3.fromRGB(245,240,255),Sub=Color3.fromRGB(180,165,220),Green=Color3.fromRGB(0,230,120),
Red=Color3.fromRGB(240,60,50),Yellow=Color3.fromRGB(255,200,50),Blue=Color3.fromRGB(80,150,255)}

-- ===== STATE =====
local S={FarmLv=false,FarmMs=false,FarmMat=false,SelMat="Leather",FarmBone=false,FarmChest=false,FarmElite=false,
AutoBoss=false,SelBoss="Bobby",AutoRaid=false,AutoAwaken=false,Chip="Flame",FarmFruit=false,Sniper=false,TrackEv=false,
PESP=false,BESP=false,MESP=false,CESP=false,FESP=false,AimA=false,PTrack=false,BTrack=false,TeamC=true,
UIToggle=Enum.KeyCode.RightShift,SelIsland="Starter Island",KillAura=false,AutoHaki=false,Magnet=true,
FarmH=20,Weapon="Combat",AutoStat=false,Stat="Melee",AntiDeath=true,Light=IS_MOB}
-- MOB CACHE: 1 vòng quét duy nhất, chỉ đọc workspace.Enemies (rẻ, không lag)
local MobCache={}
local function baseName(n) return (n:gsub(" %[Lv%. %d+%]",""):gsub(" %[Boss%]",""):gsub(" %[Raid Boss%]",""):gsub(" %[Elite Hunter%]","")) end
task.spawn(function()
    while true do
        local t={}
        local EN=WS:FindFirstChild("Enemies")
        if EN then
            for _,v in ipairs(EN:GetChildren()) do
                local h=v:FindFirstChildOfClass("Humanoid")
                local p=v:FindFirstChild("HumanoidRootPart") or v:FindFirstChild("Torso")
                if h and p and h.Health>0 then
                    t[#t+1]={M=v,HRP=p,H=h,Full=v.Name,N=baseName(v.Name),Boss=v.Name:find("%[Boss%]")~=nil or v.Name:find("%[Raid Boss%]")~=nil}
                end
            end
        end
        MobCache=t
        task.wait(S.Light and 0.4 or 0.2)
    end
end)

local function findMob(name)
    local h=hrp() if not h then return nil end
    local best,bd=nil,math.huge
    for _,m in ipairs(MobCache) do
        if m.N==name or m.Full==name then
            local d=(m.HRP.Position-h.Position).Magnitude
            if d<bd then bd=d best=m end
        end
    end
    return best
end
local function findAnyBoss()
    local h=hrp() if not h then return nil end
    local best,bd=nil,math.huge
    for _,m in ipairs(MobCache) do
        if m.Boss then
            local d=(m.HRP.Position-h.Position).Magnitude
            if d<bd then bd=d best=m end
        end
    end
    return best
end
local function findNPCModel(pat) -- tìm NPC shop trong workspace (Gacha/Scientist...)
    local low=pat:lower()
    for _,v in ipairs(WS:GetChildren()) do
        if v:IsA("Model") and v.Name:lower():find(low,1,true) then return v end
    end
    local M=WS:FindFirstChild("Map")
    if M then for _,v in ipairs(M:GetChildren()) do if v:IsA("Model") and v.Name:lower():find(low,1,true) then return v end end end
    return nil
end

-- QUEST GUI check (chuẩn Blox Fruits)
local function questGui()
    local pg=LP:FindFirstChild("PlayerGui") if not pg then return nil end
    local m=pg:FindFirstChild("Main") if not m then return nil end
    return m:FindFirstChild("Quest")
end
local function questVisible()
    local q=questGui() if not q then return false end
    return q.Visible==true
end
local function questTitle()
    local q=questGui() if not q then return "" end
    local ok,r=pcall(function()
        local c=q:FindFirstChild("Container") if not c then return "" end
        local t=c:FindFirstChild("QuestTitle") if not t then return "" end
        local tt=t:FindFirstChild("Title") if not tt then return "" end
        return tt.Text
    end)
    return ok and r or ""
end
-- Parse "X/Y" từ quest title (vd: "Defeat 5/6 Bandits" → 5, 6)
-- Trả về cur, max (hoặc nil,nil nếu không parse được)
local function questProgress()
    local ttl=questTitle()
    if ttl=="" then return nil,nil end
    -- Pattern: "X/Y" - cho phép space quanh dấu /
    local cur,max=ttl:match("(%d+)%s*/%s*(%d+)")
    if cur and max then
        return tonumber(cur),tonumber(max)
    end
    return nil,nil
end
-- Kiểm tra quest đã hoàn thành (cur >= max)
local function questCompleted()
    local cur,max=questProgress()
    if not cur or not max then return false end
    return cur>=max
end

-- EQUIP vũ khí
local function equip(name)
    if not name or name=="" then return end
    local c=chr() if not c then return end
    if c:FindFirstChild(name) then return end
    local bp=LP:FindFirstChild("Backpack") if not bp then return end
    local t=bp:FindFirstChild(name)
    if t then pcall(function() local hm=c:FindFirstChildOfClass("Humanoid") if hm then hm:EquipTool(t) end end) end
end
local function autoEquip()
    equip(S.Weapon)
    local c=chr()
    if c and not c:FindFirstChildOfClass("Tool") then
        local bp=LP:FindFirstChild("Backpack")
        if bp then local t=bp:FindFirstChild("Combat") or bp:FindFirstChildOfClass("Tool") if t then equip(t.Name) end end
    end
end

-- ATTACK v10: AutoClickController lo phần click, BringMob lo kéo quái
-- attackMob chỉ cần: bring mob về gần player + đảm bảo equipped
-- KHÔNG toTarget tới mob (tránh player bay lên trời theo mob)
local function attackMob(mob,maxCount)
    if not mob or not mob.HRP or not mob.H or mob.H.Health<=0 then return end
    -- Bring mob về gần player (MaxForce chỉ X/Z → mob không bay lên)
    if S.Magnet then
        BringMob:Bring(mob,maxCount)
    else
        -- Không bật magnet: chỉ teleport player tới gần mob (cách 5 studs)
        local h=hrp() if h then
            local tgt=mob.HRP.CFrame*CFrame.new(0,S.FarmH,5)
            -- Giữ Y của player ổn định (không bay lên theo mob)
            tgt=CFrame.new(tgt.X,math.max(tgt.Y,h.Position.Y-5),tgt.Z)
            toTarget(tgt,400)
        end
    end
    autoEquip()
    -- AutoClickController lo phần click (đã subscribe khi AF on)
end
local function floatState() local h=hum() if h then pcall(function() h:ChangeState(11) end) end end

-- ===== ESP (billboard + highlight, quét folder riêng — nhẹ) =====
local ESP={Obj={}}
function ESP:Add(inst,col,txt)
    if not inst or inst.Parent==nil or self.Obj[inst] then return end
    local o={H=make("Highlight",{FillColor=col or C.Red,OutlineColor=Color3.new(1,1,1),FillTransparency=.6,OutlineTransparency=0,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,Parent=inst})}
    local p=inst:IsA("Model") and (inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart) or inst
    if p then
        o.B=make("BillboardGui",{Size=UDim2.new(0,200,0,22),StudsOffset=Vector3.new(0,4,0),AlwaysOnTop=true,Parent=p})
        make("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=txt or inst.Name,Font=Enum.Font.GothamBold,TextSize=12,TextColor3=col or C.Red,TextStrokeTransparency=.3,Parent=o.B})
    end
    self.Obj[inst]={o=o,txt=txt or inst.Name}
end
function ESP:Rem(inst)
    local e=self.Obj[inst] if not e then return end
    pcall(function() if e.o.H then e.o.H:Destroy() end if e.o.B then e.o.B:Destroy() end end)
    self.Obj[inst]=nil
end
function ESP:Clear() for i in pairs(self.Obj) do self:Rem(i) end end
local espLoop=nil
local function espStart()
    if espLoop then return end
    espLoop=task.spawn(function()
        while true do
            pcall(function()
                if S.PESP or S.PTrack then
                    for _,p in ipairs(Players:GetPlayers()) do
                        if p~=LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                            local ls=p:FindFirstChild("leaderstats")
                            local bn=ls and ls:FindFirstChild("Bounty")
                            local h=hrp()
                            local d=h and math.floor((p.Character.HumanoidRootPart.Position-h.Position).Magnitude) or 0
                            local txt=p.Name..(bn and bn.Value>0 and (" | "..bn.Value.." Beli") or "").." | "..d.."m"
                            ESP:Add(p.Character,C.Blue,txt)
                            local e=ESP.Obj[p.Character]
                            if e and e.o.B and e.o.B:FindFirstChildOfClass("TextLabel") then e.o.B:FindFirstChildOfClass("TextLabel").Text=txt end
                        end
                    end
                end
                if S.BESP then
                    for _,m in ipairs(MobCache) do
                        if m.Boss then ESP:Add(m.M,C.Red,m.Full) end
                    end
                end
                if S.MESP then
                    local n=0 local cap=S.Light and 12 or 25
                    for _,m in ipairs(MobCache) do
                        if n<cap then ESP:Add(m.M,C.Green,m.N) n=n+1 end
                    end
                end
                if S.CESP then
                    local CM=WS:FindFirstChild("ChestModels")
                    if CM then for _,c in ipairs(CM:GetChildren()) do ESP:Add(c,C.Yellow,"Chest: "..c.Name) end end
                end
                if S.FESP then
                    local h=hrp()
                    for _,t in ipairs(WS:GetChildren()) do
                        if t:IsA("Tool") and t.Name:find("Fruit") then
                            local short,emoji=parseFruit(t.Name)
                            local dist=h and t:FindFirstChild("Handle") and math.floor((t.Handle.Position-h.Position).Magnitude) or 0
                            local txt=emoji.." "..short.." | "..dist.."m"
                            ESP:Add(t,C.Green,txt)
                            -- Cập nhật label liên tục để khoảng cách luôn đúng
                            local e=ESP.Obj[t]
                            if e and e.o.B then
                                local lbl=e.o.B:FindFirstChildOfClass("TextLabel")
                                if lbl then lbl.Text=txt end
                            end
                        end
                    end
                end
                for i,e in pairs(ESP.Obj) do
                    if i.Parent==nil then ESP:Rem(i) end
                end
            end)
            task.wait(S.Light and 2 or 1)
        end
    end)
end
local function espStopIfIdle()
    if not (S.PESP or S.PTrack or S.BESP or S.MESP or S.CESP or S.FESP) then ESP:Clear() end
end

-- ===== BRING MOB CONTROLLER =====
-- Giữ quái ổn định: KHÔNG bay lên trời, chỉ kéo N mob gần nhất (N = quest còn lại)
-- Dùng BodyVelocity với MaxForce chỉ trục X/Z → mob không bị kéo lên Y
local BringMob={Active={}}
-- Bring 1 mob tới gần player (chỉ kéo ngang, không kéo lên)
function BringMob:Bring(mob,maxCount)
    if not mob or not mob.HRP or not mob.H or mob.H.Health<=0 then return false end
    if maxCount and maxCount<=0 then return false end  -- đã đủ số lượng
    local h=hrp() if not h then return false end
    -- Set sim radius (load mob từ xa)
    if sethiddenproperty then
        pcall(function() sethiddenproperty(LP,"SimulationRadius",math.huge) end)
    end
    -- Lấy network ownership (client control mob physics)
    pcall(function() mob.HRP:SetNetworkOwner(LP) end)
    -- Hitbox to hơn nhưng KHÔNG quá to (25 thay vì 50 - tránh physics weird)
    if mob.HRP.Size.X<25 then
        pcall(function() mob.HRP.Size=Vector3.new(25,25,25) end)
    end
    pcall(function() mob.HRP.CanCollide=false end)
    -- Tính khoảng cách mob → player
    local mobPos=mob.HRP.Position
    local playerPos=h.Position
    local dist=(mobPos-playerPos).Magnitude
    if dist>15 then
        -- Teleport mob tới trước mặt player, ở Y = player.Y (KHÔNG bay lên trời)
        local lookVec=h.CFrame.LookVector
        -- chỉ dùng X,Z của lookVec (bỏ thành phần Y để mob không bị kéo lên/xuống)
        local flatLook=Vector3.new(lookVec.X,0,lookVec.Z)
        if flatLook.Magnitude<0.01 then flatLook=Vector3.new(0,0,-1) end
        flatLook=flatLook.Unit
        local targetPos=playerPos+flatLook*5
        -- Y của mob = Y của player (giữ mob ở tầm đánh, không cao hơn)
        targetPos=Vector3.new(targetPos.X,playerPos.Y,targetPos.Z)
        pcall(function() mob.HRP.CFrame=CFrame.new(targetPos) end)
    elseif dist>6 then
        -- Kéo mob về phía player bằng BodyVelocity (chỉ trục X/Z, KHÔNG kéo Y)
        local dir=playerPos-mobPos
        dir=Vector3.new(dir.X,0,dir.Z)  -- bỏ Y → mob không bị kéo lên trời
        if dir.Magnitude>0.5 then
            local bv=mob.HRP:FindFirstChild("TNTBringBV")
            if not bv then
                bv=Instance.new("BodyVelocity")
                bv.Name="TNTBringBV"
                bv.MaxForce=Vector3.new(math.huge,0,math.huge)  -- chỉ force X,Z
                bv.Parent=mob.HRP
            end
            bv.Velocity=dir.Unit*80
        end
    else
        -- Đã gần - xóa BV nếu có, mob đứng yên
        local bv=mob.HRP:FindFirstChild("TNTBringBV")
        if bv then bv:Destroy() end
    end
    self.Active[mob.M]=true
    return true
end
-- Cleanup: xóa BV của mob đã rời đi/chết
function BringMob:Cleanup(activeSet)
    for k,_ in pairs(self.Active) do
        if not activeSet[k] then
            pcall(function()
                if k and k.Parent then
                    local hrp2=k:FindFirstChild("HumanoidRootPart")
                    if hrp2 then
                        local bv=hrp2:FindFirstChild("TNTBringBV")
                        if bv then bv:Destroy() end
                    end
                end
            end)
            self.Active[k]=nil
        end
    end
end
-- Release all (khi tắt farm)
function BringMob:ReleaseAll()
    for k,_ in pairs(self.Active) do
        pcall(function()
            if k and k.Parent then
                local hrp2=k:FindFirstChild("HumanoidRootPart")
                if hrp2 then
                    local bv=hrp2:FindFirstChild("TNTBringBV")
                    if bv then bv:Destroy() end
                end
            end
        end)
    end
    self.Active={}
end

-- ===== AUTO FARM =====
local AF={Loop=nil,Fail=0,TravelHint=0,MatHint=0}
function AF:Stop()
    if self.Loop then task.cancel(self.Loop) self.Loop=nil end
    stopMove()
    BringMob:ReleaseAll()
    AutoClick:Unsubscribe()
end
-- Auto Farm State Machine:
-- IDLE → GO_TO_QUEST_GIVER → ACCEPT_QUEST → VERIFY_QUEST →
--   FIND_TARGET → FARMING → CHECK_PROGRESS → QUEST_DONE → IDLE (lặp lại)
function AF:StartLv()
    self:Stop()
    AutoClick:Subscribe()  -- Auto Click tự chạy khi AF on
    self.Loop=task.spawn(function()
        while S.FarmLv do
            pcall(function()
                floatState()
                local lvl=getLevel()
                if tick()-self.TravelHint>30 then
                    if SEA==1 and lvl>=700 then notify("Auto Farm","Bạn đã Lv "..lvl.." — nên sang Sea 2 (tab Misc)",6) self.TravelHint=tick() end
                    if SEA==2 and lvl>=1500 then notify("Auto Farm","Bạn đã Lv "..lvl.." — nên sang Sea 3 (tab Misc)",6) self.TravelHint=tick() end
                end
                local qd=getQuest(lvl,SEA) or getQuest(0,SEA)

                -- STATE: QUEST_DONE — kiểm tra trước
                if questVisible() and questCompleted() then
                    -- Quest hoàn thành: abandon + chờ quest mới
                    INV("AbandonQuest")
                    task.wait(0.4)
                    return
                end

                -- STATE: NO QUEST → đi nhận
                if not questVisible() then
                    if self.Fail>=3 then
                        -- Fallback: farm thường không cần quest
                        local mob=findMob(qd.b)
                        if mob then attackMob(mob) else toTarget(qd.cm,300) end
                        return
                    end
                    local h=hrp() if not h then return end
                    -- STATE: GO_TO_QUEST_GIVER
                    if (h.Position-qd.cq.Position).Magnitude>14 then
                        toTarget(qd.cq*CFrame.new(0,0,4),320)
                        return
                    end
                    -- STATE: ACCEPT_QUEST
                    stopMove()
                    INV("SetSpawnPoint")
                    INV("StartQuest",qd.q,qd.n)
                    task.wait(0.6)
                    -- STATE: VERIFY_QUEST
                    if not questVisible() then
                        self.Fail=self.Fail+1
                        if self.Fail==3 then notify("Auto Farm","Quest lỗi -> chuyển sang farm thường",5) end
                    else
                        self.Fail=0
                    end
                else
                    -- STATE: FARMING
                    self.Fail=0
                    local ttl=questTitle()
                    -- STATE: VERIFY_QUEST — kiểm tra quest đúng loại quái
                    if ttl~="" and not ttl:find(qd.m,1,true) then
                        INV("AbandonQuest")
                        task.wait(0.3)
                        return
                    end
                    -- STATE: CHECK_PROGRESS — tính số quái còn cần
                    local cur,max=questProgress()
                    local need = max and math.max(0, max - (cur or 0)) or 1
                    -- STATE: FIND_TARGET
                    local mob=findMob(qd.b)
                    if mob then
                        -- STATE: FARMING — bring mob với count limit
                        attackMob(mob, need)
                    else
                        -- Mob không có: bay tới spawn point
                        toTarget(qd.cm,320)
                    end
                end
            end)
            task.wait(S.Light and 0.2 or 0.13)
        end
        stopMove()
        BringMob:ReleaseAll()
        AutoClick:Unsubscribe()
    end)
end
-- Farm generic: fn() trả {m=mob} để đánh hoặc {p=cf} để bay tới
function AF:Run(fn)
    self:Stop()
    AutoClick:Subscribe()
    self.Loop=task.spawn(function()
        while true do
            pcall(function()
                floatState()
                local t=fn()
                if t then
                    if t.m then attackMob(t.m)
                    elseif t.p then toTarget(t.p,320) end
                end
            end)
            task.wait(S.Light and 0.22 or 0.14)
        end
    end)
end
function AF:StartMs()
    self:Run(function()
        local qd=getQuest(getLevel(),SEA) or getQuest(0,SEA)
        local mob=findMob(qd.b)
        if mob then return {m=mob} end
        return {p=qd.cm}
    end)
end
function AF:StartMat()
    self:Run(function()
        local e,okSea=matFor(S.SelMat)
        if e then
            local mob=findMob(e.m)
            if mob then return {m=mob} end
            if okSea==false and tick()-self.MatHint>10 then
                self.MatHint=tick()
                notify("Material","Nguyên liệu này farm tốt ở Sea "..e.s..", đang ở Sea "..SEA,4)
            end
            return {p=e.p}
        end
        return nil
    end)
end
function AF:StartBone()
    self:Run(function()
        local mob=findMob("Reborn Skeleton") or findMob("Living Zombie") or findMob("Demonic Soul") or findMob("Posessed Mummy")
        if mob then return {m=mob} end
        local qd=getQuest(2025,3) or getQuest(0,3)
        return {p=qd.cm}
    end)
end
function AF:StartChest()
    self:Run(function()
        local h=hrp() if not h then return nil end
        local best,bd=nil,math.huge
        local CM=WS:FindFirstChild("ChestModels")
        if CM then
            for _,c in ipairs(CM:GetChildren()) do
                local p=c:IsA("BasePart") and c or c:FindFirstChildWhichIsA("BasePart")
                if p then local d=(p.Position-h.Position).Magnitude if d<bd then bd=d best=p end end
            end
        end
        if best then return {p=best.CFrame*CFrame.new(0,2,0)} end
        return nil
    end)
end
-- Elite Hunter: nhận quest ở NPC Floating Turtle rồi đánh Diablo/Deandre/Urban
local ELI_NPC=CFrame.new(-5418.89,313.74,-2826.23)
function AF:StartElite()
    self:Stop()
    if SEA~=3 then notify("Elite","Elite Hunter chỉ có ở Sea 3 (Floating Turtle)",6) end
    self.Loop=task.spawn(function()
        while S.FarmElite do
            pcall(function()
                floatState()
                local h=hrp() if not h then return end
                local mob=findMob("Diablo") or findMob("Deandre") or findMob("Urban")
                if not mob then
                    for _,m in ipairs(MobCache) do if m.Full:find("Elite") or m.N:find("Elite") then mob=m break end end
                end
                if mob then attackMob(mob)
                elseif not questVisible() then
                    if (h.Position-ELI_NPC.Position).Magnitude>14 then toTarget(ELI_NPC*CFrame.new(0,0,4),320)
                    else INV("EliteHunter") task.wait(0.5) end
                else
                    toTarget(ELI_NPC*CFrame.new(0,40,0),320)
                end
            end)
            task.wait(0.2)
        end
        stopMove()
    end)
end

-- Khi tắt 1 chế độ farm, khởi động lại chế độ khác nếu còn bật (tránh bị đứng)
-- Nếu không còn chế độ nào → AF:Stop sẽ unsubscribe AutoClick
local function afRestart()
    if S.FarmLv then AF:StartLv()
    elseif S.FarmMs then AF:StartMs()
    elseif S.FarmMat then AF:StartMat()
    elseif S.FarmBone then AF:StartBone()
    elseif S.FarmChest then AF:StartChest()
    elseif S.FarmElite then AF:StartElite()
    else AF:Stop() end
end

-- ===== BOSS FARM =====
local BF={Loop=nil,Hint=0}
function BF:Stop()
    if BF.Loop then task.cancel(BF.Loop) BF.Loop=nil end
    stopMove()
    BringMob:ReleaseAll()
    AutoClick:Unsubscribe()
end
function BF:Start(name,all)
    self:Stop()
    AutoClick:Subscribe()
    BF.Loop=task.spawn(function()
        while true do
            pcall(function()
                floatState()
                local mob
                if all then mob=findAnyBoss()
                else
                    mob=findMob(name)
                    if not mob then
                        local bb=nil
                        for _,b in ipairs(Bosses) do if b.n==name then bb=b break end end
                        if bb and bb.s~=SEA then
                            if tick()-self.Hint>30 then self.Hint=tick() notify("Boss",name.." ở Sea "..bb.s.." — dùng Misc để chuyển biển",5) end
                        end
                        stopMove() return
                    end
                end
                if mob then attackMob(mob,1) else stopMove() end
            end)
            task.wait(0.12)
        end
    end)
end

-- ===== RAID (flow thật: Scientist chip -> RaidsNpc -> Summon -> càn quét) =====
local RD={Loop=nil,BuyT=0,SelT=0,FireT=0}
function RD:Stop()
    if RD.Loop then task.cancel(RD.Loop) RD.Loop=nil end
    stopMove()
    AutoClick:Unsubscribe()
end
local function inRaid()
    local pg=LP:FindFirstChild("PlayerGui") if not pg then return false end
    local m=pg:FindFirstChild("Main") if not m then return false end
    local t=m:FindFirstChild("Timer")
    if t and t.Visible==true then return true end
    local WO=WS:FindFirstChild("_WorldOrigin")
    return WO and WO:FindFirstChild("Locations") and WO.Locations:FindFirstChild("Island 1")~=nil
end
local function hasChip()
    local bp=LP:FindFirstChild("Backpack") local c=chr()
    local n="Special Microchip"
    return (bp and bp:FindFirstChild(n)) or (c and c:FindFirstChild(n))
end
local function summonBtn() -- nút triệu hồi: CircleIsland (Sea2) / Boat Castle (Sea3)
    local M=WS:FindFirstChild("Map") if not M then return nil end
    local isl=M:FindFirstChild("CircleIsland") or M:FindFirstChild("Boat Castle")
    if not isl then return nil end
    local rs=isl:FindFirstChild("RaidSummon2") if not rs then return nil end
    local bb=rs:FindFirstChild("Button") if not bb then return nil end
    local main=bb:FindFirstChild("Main")
    if main then return main:FindFirstChild("ClickDetector") end
    return bb:FindFirstChildOfClass("ClickDetector")
end
function RD:Start()
    RD:Stop()
    AutoClick:Subscribe()
    if SEA==1 then notify("Raid","Raid chỉ có ở Sea 2/3 — dùng Misc để chuyển biển!",7) end
    RD.Loop=task.spawn(function()
        while S.AutoRaid do
            pcall(function()
                floatState()
                if inRaid() then
                    -- trong raid: bay tới đảo mới nhất + đánh mob gần nhất
                    local h=hrp() if not h then return end
                    local RM=WS:FindFirstChild("Map") and WS.Map:FindFirstChild("RaidMap")
                    if RM then
                        for i=5,1,-1 do
                            local isl=RM:FindFirstChild("RaidIsland"..i)
                            if isl then
                                local pp=isl:FindFirstChildWhichIsA("BasePart")
                                if pp and (pp.Position-h.Position).Magnitude>30 then toTarget(pp.CFrame*CFrame.new(0,20,0),400) end
                                break
                            end
                        end
                    end
                    local best,bd=nil,math.huge
                    for _,m in ipairs(MobCache) do
                        local d=(m.HRP.Position-h.Position).Magnitude
                        if d<bd then bd=d best=m end
                    end
                    if best then attackMob(best) end
                else
                    -- ngoài raid: mua chip (đứng cạnh Scientist) -> chọn chip -> triệu hồi
                    if not hasChip() then
                        local h=hrp()
                        local sci=findNPCModel("Scientist")
                        local pp=sci and (sci.PrimaryPart or sci:FindFirstChildWhichIsA("BasePart"))
                        if pp and h then
                            if (pp.Position-h.Position).Magnitude>12 then toTarget(pp.CFrame*CFrame.new(0,2,4),350)
                            elseif tick()-self.BuyT>2 then self.BuyT=tick() INV("Cousin","Buy") end
                        elseif tick()-self.BuyT>2 then self.BuyT=tick() INV("Cousin","Buy") end
                    else
                        if tick()-self.SelT>5 then self.SelT=tick() INV("RaidsNpc","Select",S.Chip) end
                        if tick()-self.FireT>2.5 then
                            self.FireT=tick()
                            pcall(function()
                                local cd=summonBtn()
                                if cd and fireclickdetector then fireclickdetector(cd) end
                            end)
                        end
                    end
                end
            end)
            task.wait(0.25)
        end
        stopMove()
    end)
end

-- ===== AUTO AWAKEN (remote Awakener thật — chạy sau khi raid xong) =====
local AW={Loop=nil}
function AW:Stop() if AW.Loop then task.cancel(AW.Loop) AW.Loop=nil end stopMove() end
function AW:Start()
    AW:Stop()
    AW.Loop=task.spawn(function()
        while S.AutoAwaken do
            pcall(function()
                if not inRaid() then
                    -- vào phòng awaken (RaidMap còn) rồi gọi Awakener
                    local M=WS:FindFirstChild("Map")
                    if M and M:FindFirstChild("RaidMap") then
                        local RM=M.RaidMap
                        for i=5,1,-1 do
                            local isl=RM:FindFirstChild("RaidIsland"..i)
                            if isl then
                                local pp=isl:FindFirstChildWhichIsA("BasePart")
                                if pp then toTarget(pp.CFrame*CFrame.new(0,5,0),400) end
                                break
                            end
                        end
                    end
                    INV("Awakener","Check")
                    INV("Awakener","Awaken")
                end
            end)
            task.wait(1.5)
        end
        stopMove()
    end)
end

-- ===== FRUIT (fruit spawn là Tool trong workspace) =====
local FT={Loop=nil}
function FT:Stop() if FT.Loop then task.cancel(FT.Loop) FT.Loop=nil end stopMove() end
local function findFruit()
    for _,t in ipairs(WS:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("Handle") and t.Name:find("Fruit") then return t end
    end
    return nil
end
function FT:Start()
    FT:Stop()
    FT.Loop=task.spawn(function()
        while S.FarmFruit or S.Sniper do
            pcall(function()
                local f=findFruit()
                if f then
                    if S.Sniper and f.Name~=FT.Last then
                        FT.Last=f.Name
                        notify("FRUIT SNIPER","Xuất hiện: "..f.Name.."! Đang bay tới",6)
                    end
                    if S.FarmFruit then toTarget(f.Handle.CFrame,450) end
                else
                    FT.Last=nil
                end
            end)
            task.wait(0.5)
        end
        stopMove()
    end)
end

-- ===== KILL AURA =====
local KA={Loop=nil}
function KA:Stop()
    if KA.Loop then task.cancel(KA.Loop) KA.Loop=nil end
    AutoClick:Unsubscribe()
end
function KA:Start()
    KA:Stop()
    AutoClick:Subscribe()
    KA.Loop=task.spawn(function()
        while S.KillAura do
            pcall(function()
                local h=hrp() if not h then return end
                local n=0
                for _,m in ipairs(MobCache) do
                    if (m.HRP.Position-h.Position).Magnitude<25 then
                        if S.Magnet then
                            pcall(function()
                                if m.HRP.Size.X<25 then m.HRP.Size=Vector3.new(25,25,25) end
                                m.HRP.CanCollide=false
                            end)
                        end
                        n=n+1
                        if n>4 then break end
                    end
                end
                autoEquip()
                -- AutoClickController lo phần click
            end)
            task.wait(0.15)
        end
    end)
end

-- ===== AUTO HAKI (remote Buso thật) =====
local AH={Loop=nil}
function AH:Stop() if AH.Loop then task.cancel(AH.Loop) AH.Loop=nil end end
function AH:Start()
    AH:Stop()
    AH.Loop=task.spawn(function()
        while S.AutoHaki do
            pcall(function() INV("Buso") end)
            task.wait(8)
        end
    end)
end

-- ===== AUTO STAT (AddPoint thật) =====
local AS={Loop=nil}
function AS:Stop() if AS.Loop then task.cancel(AS.Loop) AS.Loop=nil end end
function AS:Start()
    AS:Stop()
    AS.Loop=task.spawn(function()
        while S.AutoStat do
            pcall(function()
                local d=LP:FindFirstChild("Data")
                if d then
                    local p=d:FindFirstChild("Points")
                    if p and p.Value>0 then INV("AddPoint",S.Stat,p.Value) end
                end
            end)
            task.wait(1)
        end
    end)
end

-- ===== PVP: AIM ASSIST (ghim camera vào người gần nhất, cache target) =====
local AA={Conn=nil,Tgt=nil,Next=0}
function AA:Stop() if AA.Conn then AA.Conn:Disconnect() AA.Conn=nil end AA.Tgt=nil end
function AA:Start()
    AA:Stop()
    AA.Conn=RS.RenderStepped:Connect(function()
        if not S.AimA then return end
        if tick()>AA.Next then -- quét target định kỳ (không quét mỗi frame -> mượt)
            AA.Next=tick()+(S.Light and 0.35 or 0.2)
            local h=hrp() if not h then return end
            local best,bd=nil,math.huge
            for _,p in ipairs(Players:GetPlayers()) do
                if p~=LP and p.Character then
                    local hh=p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
                    local hm2=p.Character:FindFirstChildOfClass("Humanoid")
                    if hh and hm2 and hm2.Health>0 then
                        local skip=false
                        if S.TeamC and LP.Team and p.Team and LP.Team==p.Team then skip=true end
                        if not skip then
                            local d=(hh.Position-h.Position).Magnitude
                            if d<bd and d<500 then bd=d best=hh end
                        end
                    end
                end
            end
            AA.Tgt=best
        end
        if AA.Tgt and AA.Tgt.Parent then
            Cam.CFrame=CFrame.lookAt(Cam.CFrame.Position,AA.Tgt.Position)
        end
    end)
end

-- ===== BOUNTY TRACKER (leaderstats thật) =====
local BT={Loop=nil}
function BT:Stop() if BT.Loop then task.cancel(BT.Loop) BT.Loop=nil end end
function BT:Start()
    BT:Stop()
    BT.Loop=task.spawn(function()
        local seen={}
        while S.BTrack do
            pcall(function()
                local h=hrp() if not h then return end
                for _,p in ipairs(Players:GetPlayers()) do
                    if p~=LP then
                        local ls=p:FindFirstChild("leaderstats")
                        local b=ls and ls:FindFirstChild("Bounty")
                        if b and b.Value>=250000 then
                            local d=p.Character and p.Character:FindFirstChild("HumanoidRootPart") and math.floor((p.Character.HumanoidRootPart.Position-h.Position).Magnitude) or 99999
                            if d<600 and not seen[p.Name] then
                                seen[p.Name]=true
                                notify("BOUNTY!"," "..p.Name.." ("..b.Value.." Beli) đang ở gần!",6)
                            elseif d>800 then
                                seen[p.Name]=nil
                            end
                        end
                    end
                end
            end)
            task.wait(S.Light and 3 or 2)
        end
    end)
end

-- ===== SEA EVENT TRACKER =====
local EVT={Loop=nil}
function EVT:Stop() if EVT.Loop then task.cancel(EVT.Loop) EVT.Loop=nil end end
local function findEvent(pat)
    local low=pat:lower()
    local function scan(container)
        for _,o in ipairs(container:GetChildren()) do
            if o:IsA("Model") and o.Name:lower():find(low,1,true) then return o end
        end
    end
    local m=scan(WS)
    if m then return m end
    local MP=WS:FindFirstChild("Map")
    if MP then m=scan(MP) end
    return m
end
function EVT:Start()
    EVT:Stop()
    EVT.Loop=task.spawn(function()
        local seen={}
        while S.TrackEv do
            pcall(function()
                for _,e in ipairs(SeaEvents) do
                    local m=findEvent(e)
                    if m then
                        if not seen[e] then
                            seen[e]=true
                            notify("SEA EVENT"," "..e.." đang xuất hiện!",7)
                        end
                        ESP:Add(m,C.Yellow,e)
                    else
                        seen[e]=nil
                    end
                end
            end)
            task.wait(S.Light and 8 or 5)
        end
    end)
end

-- ===== MISC =====
local Misc={}
Misc.AntiAFK=LP.Idled:Connect(function() pcall(function() VU:CaptureController() VU:ClickButton2(Vector2.new()) end) end)
local function hopServer()
    local req
    pcall(function() req=syn and syn.request or request or http_request end)
    if not req then notify("Hop","Executor không hỗ trợ HTTP",3) if getgenv() then getgenv().TNT_HOP=nil end return end
    pcall(function()
        local url="https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
        local data=HS:JSONDecode(req({Url=url,Method="GET"}).Body)
        for _,sv in ipairs(data.data) do
            if sv.playing<sv.maxPlayers and sv.id~=game.JobId then
                notify("Hop","Đang chuyển server...",3)
                TPS:TeleportToPlaceInstance(game.PlaceId,sv.id,LP) return
            end
        end
        notify("Hop","Không tìm thấy server khác",3)
        if getgenv() then getgenv().TNT_HOP=nil end
    end)
end
-- Hop tìm Fruit/Boss: cần bật Auto Execute trong executor để script tự chạy lại
function Misc:HopFind(mode)
    if not getgenv() then notify("Hop","Executor không hỗ trợ getgenv",3) return end
    getgenv().TNT_HOP=mode
    getgenv().TNT_HOPN=(getgenv().TNT_HOPN or 0)+1
    if getgenv().TNT_HOPN>15 then
        getgenv().TNT_HOP=nil getgenv().TNT_HOPN=0
        notify("Hop Find","Đã thử 15 server, không tìm thấy — dừng lại",6) return
    end
    notify("Hop Find","Đang tìm "..(mode=="fruit" and "Fruit" or "Boss").." (lần "..getgenv().TNT_HOPN.."/15)",4)
    hopServer()
end
function Misc:Rejoin() notify("Rejoin","Đang vào lại server...",3) TPS:Teleport(game.PlaceId,LP) end
function Misc:FPS()
    pcall(function()
        local t=WS.Terrain
        t.WaterWaveSize=0 t.WaterWaveSpeed=0 t.WaterReflectance=0 t.WaterTransparency=0
        Light.GlobalShadows=false Light.FogEnd=9e9 Light.Brightness=0
        settings().Rendering.QualityLevel=Enum.QualityLevel.Level01
        for _,o in ipairs(WS:GetDescendants()) do
            if o:IsA("BasePart") then o.Material=Enum.Material.Plastic o.Reflectance=0
            elseif o:IsA("Decal") or o:IsA("Texture") then o.Transparency=1
            elseif o:IsA("ParticleEmitter") or o:IsA("Trail") then o.Lifetime=NumberRange.new(0)
            elseif o:IsA("Fire") or o:IsA("SpotLight") or o:IsA("Smoke") or o:IsA("Sparkles") or o:IsA("Explosion") then o.Enabled=false
            elseif o:IsA("MeshPart") then o.Material=Enum.Material.Plastic o.Reflectance=0
            end
        end
        for _,e in ipairs(Light:GetChildren()) do
            if e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") or e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") then e.Enabled=false end
        end
    end)
    notify("FPS Boost","Đã áp dụng! Giảm đồ họa tối đa",4)
end
-- Anti Death Screen (hook effect Death/Respawn)
pcall(function()
    if hookfunction then
        local EC=ReSto:FindFirstChild("Effect")
        if EC then
            local ct=EC:FindFirstChild("Container")
            if ct then
                local d=ct:FindFirstChild("Death")
                if d then hookfunction(require(d),function() end) end
                local r2=ct:FindFirstChild("Respawn")
                if r2 then hookfunction(require(r2),function() end) end
            end
        end
    end
end)
-- Resume Hop Find khi script chạy lại sau khi teleport (cần Auto Execute)
task.spawn(function()
    if getgenv() and getgenv().TNT_HOP then
        task.wait(4)
        local mode=getgenv().TNT_HOP
        local found=mode=="fruit" and findFruit() or findAnyBoss()
        if found then
            getgenv().TNT_HOP=nil getgenv().TNT_HOPN=0
            notify("Hop Find","TÌM THẤY "..(mode=="fruit" and found.Name or found.Full).."! Dừng hop",8)
        else
            Misc:HopFind(mode)
        end
    end
end)

-- ============== UI ==============
local gui=make("ScreenGui",{Name="TNThud",ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,IgnoreGuiInset=true,Parent=getGui()})
-- ScreenGui riêng cho Status Bar — luôn hiện kể cả khi main UI bị ẩn
local sgui=make("ScreenGui",{Name="TNThudStatus",ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,IgnoreGuiInset=true,Parent=getGui()})
local VP=Cam.ViewportSize

-- ===== SERVER STATUS BAR (luôn hiện ở top) =====
local SBW=IS_MOB and math.min(560,VP.X-16) or 580
local SB=make("Frame",{Size=UDim2.new(0,SBW,0,28),Position=UDim2.new(0.5,-SBW/2,0,4),
    BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=sgui})
corner(SB,8) stroke(SB,C.Primary)
make("UIPadding",{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,28),Parent=SB})
local sbText=make("TextLabel",{Size=UDim2.new(1,-12,1,0),Position=UDim2.new(0,6,0,0),
    BackgroundTransparency=1,Text="Đang tải...",Font=Enum.Font.GothamMedium,TextSize=10,
    TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=false,Parent=SB})
-- Nút đóng/mở status bar (X) — nhỏ ở góc phải
local sbX=make("TextButton",{Size=UDim2.new(0,18,0,18),Position=UDim2.new(1,-22,0.5,-9),
    BackgroundColor3=C.Bg3,Text="✕",Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.Sub,
    AutoButtonColor=false,BorderSizePixel=0,Parent=SB}) corner(sbX,4)
local sbReopen=make("TextButton",{Size=UDim2.new(0,72,0,22),Position=UDim2.new(1,-78,0.5,-11),
    BackgroundColor3=C.Bg2,Text="📊 Status",Font=Enum.Font.GothamBold,TextSize=9,TextColor3=C.Accent,
    AutoButtonColor=false,BorderSizePixel=0,Visible=false,Parent=sgui}) corner(sbReopen,6) stroke(sbReopen,C.Primary)
sbX.MouseButton1Click:Connect(function() SB.Visible=false sbReopen.Visible=true end)
sbReopen.MouseButton1Click:Connect(function() SB.Visible=true sbReopen.Visible=false end)
-- Update loop status bar
task.spawn(function()
    while true do
        pcall(function()
            local h=hrp()
            local lvl=getLevel()
            local t=os.date("%H:%M:%S")
            local ply=#Players:GetPlayers()
            -- Quest
            local qd=getQuest(lvl,SEA) or getQuest(0,SEA)
            local qTxt=(qd and qd.b) or "Không"
            -- Fruit
            local f=findFruit()
            local fTxt,fCol="❌ Không có trái ác quỷ",C.Sub
            if f and f:FindFirstChild("Handle") then
                local short,emoji=parseFruit(f.Name)
                local dist=h and math.floor((f.Handle.Position-h.Position).Magnitude) or 0
                fTxt=emoji.." "..short.." | "..dist.."m"
                fCol=C.Green
            end
            -- Boss
            local boss=findAnyBoss()
            local bTxt="Không có boss"
            if boss and boss.HRP and h then
                local dist=math.floor((boss.HRP.Position-h.Position).Magnitude)
                bTxt=boss.N.." | "..dist.."m"
            end
            -- FPS
            local fps=math.floor(workspace:GetRealPhysicsFPS())
            sbText.Text=string.format("🌊 S%d | ⚡Lv %d | ⏰ %s | 👥 %d | 🎯 %s | 🍎 %s | 👹 %s | 📊 %d FPS",
                SEA,lvl,t,ply,qTxt,fTxt,bTxt,fps)
        end)
        task.wait(1)
    end
end)
local W=IS_MOB and math.min(560,VP.X-20) or 700 local H=IS_MOB and math.min(480,VP.Y-20) or 500
local main=make("Frame",{Size=UDim2.new(0,W,0,H),Position=UDim2.new(0.5,-W/2,0.5,-H/2),BackgroundColor3=C.Bg,BorderSizePixel=0,Parent=gui})
corner(main,12) stroke(main,C.Primary)
local top=make("Frame",{Size=UDim2.new(1,0,0,38),BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=main})
corner(top,12) make("Frame",{Size=UDim2.new(1,0,0,12),Position=UDim2.new(0,0,1,-12),BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=top})
make("TextLabel",{Size=UDim2.new(0,20,0,20),Position=UDim2.new(0,12,0.5,-10),BackgroundTransparency=1,Text="👑",Font=Enum.Font.GothamBold,TextSize=14,Parent=top})
make("TextLabel",{Size=UDim2.new(0,250,0,20),Position=UDim2.new(0,32,0.5,-10),BackgroundTransparency=1,Text="TNThud v10.0 | Sea "..SEA,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left,Parent=top})
local closeB=make("TextButton",{Size=UDim2.new(0,28,0,28),Position=UDim2.new(1,-34,0.5,-14),BackgroundColor3=C.Bg3,Text="✕",Font=Enum.Font.GothamBold,TextSize=14,TextColor3=C.Sub,AutoButtonColor=false,BorderSizePixel=0,Parent=top})
corner(closeB,6)
-- Reopen button — ở góc trên phải màn hình, parent vào sgui để luôn available kể cả khi main UI ẩn
-- Đặt dưới status bar (Y=36) để không bị chồng lên status bar trên mobile
local reopenB=make("TextButton",{Size=UDim2.new(0,84,0,26),Position=UDim2.new(1,-92,0,38),
    BackgroundColor3=C.Primary,Text="👑 Mở UI",Font=Enum.Font.GothamBold,TextSize=10,
    TextColor3=C.Text,AutoButtonColor=false,BorderSizePixel=0,Visible=false,Parent=sgui})
corner(reopenB,6) stroke(reopenB,C.Primary)
reopenB.MouseButton1Click:Connect(function() main.Visible=true reopenB.Visible=false end)
closeB.MouseButton1Click:Connect(function() main.Visible=false reopenB.Visible=true end)
local minB=make("TextButton",{Size=UDim2.new(0,28,0,28),Position=UDim2.new(1,-68,0.5,-14),BackgroundColor3=C.Bg3,Text="−",Font=Enum.Font.GothamBold,TextSize=16,TextColor3=C.Sub,AutoButtonColor=false,BorderSizePixel=0,Parent=top})
corner(minB,6)
local body=make("Frame",{Size=UDim2.new(1,0,1,-46),Position=UDim2.new(0,0,0,42),BackgroundTransparency=1,Parent=main})
local side=make("Frame",{Size=UDim2.new(0,128,1,-8),Position=UDim2.new(0,4,0,4),BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=body})
corner(side,8) stroke(side) make("TextLabel",{Size=UDim2.new(1,0,0,26),BackgroundTransparency=1,Text="👑 TNThud",Font=Enum.Font.GothamBlack,TextSize=13,TextColor3=C.Text,Parent=side})
local mSc=make("ScrollingFrame",{Size=UDim2.new(1,-8,1,-34),Position=UDim2.new(0,4,0,30),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,Parent=side})
make("UIListLayout",{Padding=UDim.new(0,3),Parent=mSc})
local items={{"🏠","Main"},{"👹","Boss"},{"⚡","Raid"},{"🍎","Fruit"},{"🌊","Sea"},{"👁","ESP"},{"📍","TP"},{"⚔️","PvP"},{"🛠️","Misc"}}
local mBtns={} local pages={}
local content=make("Frame",{Size=UDim2.new(1,-138,1,-8),Position=UDim2.new(0,136,0,4),BackgroundTransparency=1,Parent=body})
for i,it in ipairs(items) do
    local b=make("TextButton",{Size=UDim2.new(1,0,0,30),BackgroundColor3=C.Bg3,BackgroundTransparency=i==1 and 0 or 1,Text="",AutoButtonColor=false,BorderSizePixel=0,Parent=mSc})
    corner(b,6)
    local ic=make("TextLabel",{Size=UDim2.new(0,20,1,0),Position=UDim2.new(0,5,0,0),BackgroundTransparency=1,Text=it[1],Font=Enum.Font.Gotham,TextSize=12,TextColor3=i==1 and C.Text or C.Sub,Parent=b})
    local lb=make("TextLabel",{Size=UDim2.new(1,-28,1,0),Position=UDim2.new(0,26,0,0),BackgroundTransparency=1,Text=it[2],Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=i==1 and C.Text or C.Sub,TextXAlignment=Enum.TextXAlignment.Left,Parent=b})
    if i==1 then grad(b,C.Primary,C.Primary2,90) end
    local pg=make("ScrollingFrame",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=2,CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,Visible=i==1,Parent=content})
    make("UIListLayout",{Padding=UDim.new(0,4),Parent=pg}) make("UIPadding",{PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4),PaddingTop=UDim.new(0,4),Parent=pg})
    b.MouseButton1Click:Connect(function()
        for _,mb in ipairs(mBtns) do mb.b.BackgroundTransparency=1 mb.ic.TextColor3=C.Sub mb.lb.TextColor3=C.Sub end
        b.BackgroundTransparency=0 grad(b,C.Primary,C.Primary2,90) ic.TextColor3=C.Text lb.TextColor3=C.Text
        for j,p in ipairs(pages) do p.Visible=(j==i) end
    end)
    table.insert(mBtns,{b=b,ic=ic,lb=lb}) table.insert(pages,pg)
end
local function sec(p,t) make("TextLabel",{Size=UDim2.new(1,0,0,22),BackgroundTransparency=1,Text=t,Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.Accent,TextXAlignment=Enum.TextXAlignment.Left,Parent=p}) end
local function lbl(p,t) make("TextLabel",{Size=UDim2.new(1,0,0,16),BackgroundTransparency=1,Text=t,Font=Enum.Font.Gotham,TextSize=10,TextColor3=C.Sub,TextXAlignment=Enum.TextXAlignment.Left,Parent=p}) end
local function btn(p,t,cb)
    local c=make("Frame",{Size=UDim2.new(1,0,0,34),BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=p}) corner(c,6) stroke(c)
    local b=make("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=t,Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=C.Text,AutoButtonColor=false,Parent=c})
    b.MouseButton1Click:Connect(function() tw(c,{BackgroundColor3=C.Primary},0.1) task.delay(0.1,function() tw(c,{BackgroundColor3=C.Bg2},0.1) end) if cb then task.spawn(cb) end end)
    return b
end
local function tog(p,t,def,cb)
    local st=def or false
    local c=make("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=p}) corner(c,6) stroke(c)
    make("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),Parent=c})
    make("TextLabel",{Size=UDim2.new(1,-50,1,0),BackgroundTransparency=1,Text=t,Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true,Parent=c})
    local sw=make("Frame",{Size=UDim2.new(0,38,0,18),Position=UDim2.new(1,-38,0.5,-9),BackgroundColor3=C.Bg3,BorderSizePixel=0,Parent=c}) corner(sw,9)
    local kn=make("Frame",{Size=UDim2.new(0,14,0,14),Position=UDim2.new(0,2,0.5,-7),BackgroundColor3=C.Sub,BorderSizePixel=0,Parent=sw}) corner(kn,7)
    local b=make("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",AutoButtonColor=false,Parent=c})
    local function set(v) st=v
        if st then tw(sw,{BackgroundColor3=C.Primary},0.15) tw(kn,{Position=UDim2.new(1,-16,0.5,-7),BackgroundColor3=C.Text},0.15)
        else tw(sw,{BackgroundColor3=C.Bg3},0.15) tw(kn,{Position=UDim2.new(0,2,0.5,-7),BackgroundColor3=C.Sub},0.15) end
        if cb then task.spawn(cb,st) end end
    b.MouseButton1Click:Connect(function() set(not st) end) if def then set(true) end
    return {Set=set}
end
local function drop(p,t,opts,def,cb)
    local cur=def or opts[1]
    local o=opts
    local c=make("Frame",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=p}) corner(c,6) stroke(c)
    make("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),Parent=c})
    make("TextLabel",{Size=UDim2.new(1,-90,1,0),BackgroundTransparency=1,Text=t,Font=Enum.Font.GothamMedium,TextSize=10,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left,Parent=c})
    local lb=make("TextLabel",{Size=UDim2.new(0,80,1,0),Position=UDim2.new(1,-80,0,0),BackgroundTransparency=1,Text=cur,Font=Enum.Font.GothamBold,TextSize=9,TextColor3=C.Accent,TextXAlignment=Enum.TextXAlignment.Right,TextWrapped=true,Parent=c})
    local b=make("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",AutoButtonColor=false,Parent=c})
    b.MouseButton1Click:Connect(function() local i=table.find(o,cur) or 0 i=i%#o+1 cur=o[i] lb.Text=cur if cb then task.spawn(cb,cur) end end)
    return {Get=function() return cur end,Set=function(v) cur=v lb.Text=v end,SetOpts=function(list) o=list end}
end
local function sld(p,t,min,max,def,cb)
    local v=def or min
    local c=make("Frame",{Size=UDim2.new(1,0,0,48),BackgroundColor3=C.Bg2,BorderSizePixel=0,Parent=p}) corner(c,6) stroke(c)
    make("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10),Parent=c})
    local lb=make("TextLabel",{Size=UDim2.new(1,0,0,14),BackgroundTransparency=1,Text=t.."  ["..v.."]",Font=Enum.Font.GothamMedium,TextSize=10,TextColor3=C.Text,TextXAlignment=Enum.TextXAlignment.Left,Parent=c})
    local tr=make("Frame",{Size=UDim2.new(1,0,0,6),Position=UDim2.new(0,0,1,-12),BackgroundColor3=C.Bg3,BorderSizePixel=0,Parent=c}) corner(tr,3)
    local fl=make("Frame",{Size=UDim2.new((v-min)/(max-min),0,1,0),BackgroundColor3=C.Primary,BorderSizePixel=0,Parent=tr}) corner(fl,3)
    local dg=false
    local function upd(x) local r=math.clamp((x-tr.AbsolutePosition.X)/math.max(1,tr.AbsoluteSize.X),0,1) v=math.floor(min+(max-min)*r+0.5) fl.Size=UDim2.new(r,0,1,0) lb.Text=t.."  ["..v.."]" if cb then task.spawn(cb,v) end end
    local hb=make("TextButton",{Size=UDim2.new(1,0,0,25),Position=UDim2.new(0,0,0,-10),BackgroundTransparency=1,Text="",AutoButtonColor=false,Parent=tr})
    hb.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dg=true upd(i.Position.X) end end)
    UIS.InputChanged:Connect(function(i) if dg and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then upd(i.Position.X) end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dg=false end end)
end

-- ===== TAB 1: MAIN =====
local p1=pages[1]
sec(p1,"⚡ AUTO FARM LEVEL (1 → 3000)")
tog(p1,"Auto Farm Level (nhận quest + đánh quái)",false,function(v) S.FarmLv=v if v then AF:StartLv() else afRestart() end end)
tog(p1,"Magnet Quái (hitbox to - farm nhanh)",true,function(v) S.Magnet=v end)
sld(p1,"Độ cao khi farm",5,60,S.FarmH,function(v) S.FarmH=v end)
sec(p1,"⚔️ MASTERY & VŨ KHÍ")
local wd=drop(p1,"Vũ khí: ",{"Combat"},"Combat",function(v) S.Weapon=v end)
btn(p1,"🔄 Nạp danh sách vũ khí",function()
    local names={"Combat"}
    local bp=LP:FindFirstChild("Backpack") local c=chr()
    if bp then for _,t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then table.insert(names,t.Name) end end end
    if c then for _,t in ipairs(c:GetChildren()) do if t:IsA("Tool") and not table.find(names,t.Name) then table.insert(names,t.Name) end end end
    wd.SetOpts(names) wd.Set(names[1] or "Combat")
    notify("Vũ khí","Đã nạp "..#names.." vũ khí - chạm để đổi",3)
end)
tog(p1,"Auto Farm Mastery (farm quái quest hiện tại)",false,function(v) S.FarmMs=v if v then AF:StartMs() else afRestart() end end)
tog(p1,"Kill Aura (đánh quái quanh mình)",false,function(v) S.KillAura=v if v then KA:Start() else KA:Stop() end end)
tog(p1,"Auto Haki Buso (tự bật buff)",false,function(v) S.AutoHaki=v if v then AH:Start() else AH:Stop() end end)
sec(p1,"🔧 AUTO STAT (điểm năng lực)")
local sd=drop(p1,"Chỉ số: ",{"Melee","Defense","Sword","Gun","Demon Fruit"},"Melee",function(v) S.Stat=v end)
tog(p1,"Auto cộng điểm",false,function(v) S.AutoStat=v if v then AS:Start() else AS:Stop() end end)
sec(p1,"🔩 FARM MATERIAL (theo Sea)")
local matList={} for k in pairs(MATS) do table.insert(matList,k) end table.sort(matList)
drop(p1,"Nguyên liệu: ",matList,"Leather",function(v) S.SelMat=v end)
tog(p1,"Auto Farm Material",false,function(v) S.FarmMat=v if v then AF:StartMat() else afRestart() end end)
sec(p1,"💀 BONE / CHEST / ELITE")
tog(p1,"Auto Farm Bone (Sea 3 - Haunted)",false,function(v) S.FarmBone=v if v then AF:StartBone() else afRestart() end end)
tog(p1,"Auto Farm Chest (tự bay mở rương)",false,function(v) S.FarmChest=v if v then AF:StartChest() else afRestart() end end)
tog(p1,"Auto Elite Hunter (nhận quest + đánh)",false,function(v) S.FarmElite=v if v then AF:StartElite() else afRestart() end end)
sec(p1,"✈️ BAY MƯỢT (WASD + Space/Shift)")
sld(p1,"Fly Speed",30,400,100,function(v) Fly.Speed=v end)
tog(p1,"Bật Bay",false,function(v) Fly:Toggle(v) end)

-- ===== TAB 2: BOSS =====
local p2=pages[2]
sec(p2,"👹 AUTO BOSS")
tog(p2,"Auto Hunt Boss (boss nào sống đánh nấy)",false,function(v) S.AutoBoss=v if v then BF:Start("",true) else BF:Stop() end end)
sec(p2,"🎯 BOSS RIÊNG (theo Sea hiện tại)")
local bossList={} for _,b in ipairs(Bosses) do if b.s==SEA then table.insert(bossList,b.n) end end
if #bossList==0 then bossList={"Bobby"} end
local bd=drop(p2,"Boss: ",bossList,bossList[1],function(v) S.SelBoss=v end)
lbl(p2,"Boss chưa spawn: đứng chờ. Boss khác sea sẽ được nhắc chuyển biển.")
tog(p2,"Auto Farm Boss đã chọn",false,function(v)
    if v then BF:Start(S.SelBoss,false) else BF:Stop() end
end)

-- ===== TAB 3: RAID =====
local p3=pages[3]
sec(p3,"⚡ RAID (Sea 2 - CircleIsland / Sea 3 - Boat Castle)")
drop(p3,"Chip: ",{"Flame","Ice","Quake","Light","Dark","String","Rumble","Magma","Human: Buddha"},"Flame",function(v) S.Chip=v end)
tog(p3,"Auto Raid (mua chip + vào + đánh)",false,function(v) S.AutoRaid=v if v then RD:Start() else RD:Stop() end end)
tog(p3,"Auto Awaken (tỉnh thức skill sau raid)",false,function(v) S.AutoAwaken=v if v then AW:Start() else AW:Stop() end end)
lbl(p3,"Auto Raid: tự bay tới Scientist mua chip, chọn chip, triệu hồi, càn quét 5 đảo.")
lbl(p3,"Auto Awaken: bật cùng Auto Raid — khi raid xong tự vào phòng tỉnh thức.")

-- ===== TAB 4: FRUIT =====
local p4=pages[4]
sec(p4,"🍎 FRUIT")
tog(p4,"Auto Collect Fruit (tự bay lụm)",false,function(v) S.FarmFruit=v if S.FarmFruit or S.Sniper then FT:Start() else FT:Stop() end end)
tog(p4,"Fruit Sniper (báo + bay khi có fruit)",false,function(v) S.Sniper=v if S.FarmFruit or S.Sniper then FT:Start() else FT:Stop() end end)
tog(p4,"Fruit ESP",false,function(v) S.FESP=v if v then espStart() else espStopIfIdle() end end)
btn(p4,"🍎 Bay tới Ác Quỷ",function()
    local f=findFruit()
    if not f or not f:FindFirstChild("Handle") then
        notify("Bay tới Ác Quỷ","❌ Không có trái ác quỷ nào trong map!",4)
        return
    end
    local short,emoji=parseFruit(f.Name)
    local h=hrp()
    local dist=h and math.floor((f.Handle.Position-h.Position).Magnitude) or 0
    notify("Bay tới Ác Quỷ","Đang bay tới "..emoji.." "..short.." ("..dist.."m) — bật Bay để dừng",5)
    Fly:GotoTarget(f.Handle.Position)
end)
btn(p4,"🎲 Mua Random Fruit (Gacha)",function()
    task.spawn(function()
        local npc=findNPCModel("Gacha") or findNPCModel("Zioles")
        if npc then
            local p=npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart")
            if p then
                stopMove() toTarget(p.CFrame*CFrame.new(0,2,4),450)
                local t0=tick()
                while tick()-t0<8 do
                    local h=hrp()
                    if not h or (h.Position-p.Position).Magnitude<12 then break end
                    task.wait(0.1)
                end
            end
        end
        INV("Cousin","Buy")
        notify("Gacha","Đã mua! Giá ~"..(25000+150*math.max(getLevel()-1,0)).." Beli",5)
    end)
end)

-- ===== TAB 5: SEA EVENTS =====
local p5=pages[5]
sec(p5,"🌊 TRACKER")
tog(p5,"Track Sea Events (báo khi có event)",false,function(v) S.TrackEv=v if v then EVT:Start() else EVT:Stop() end end)
sec(p5,"🎯 HUNT (TP đến event đang có)")
for _,e in ipairs(SeaEvents) do
    btn(p5,"🔍 "..e,function()
        local m=findEvent(e)
        if m then
            local p=m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
            if p then stopMove() toTarget(p.CFrame*CFrame.new(0,20,0),450) notify("TP","Đã tới "..e,2) return end
        end
        notify("TP",e.." hiện không có",3)
    end)
end

-- ===== TAB 6: ESP =====
local p6=pages[6]
sec(p6,"👁 ESP (nhẹ - quét folder riêng)")
tog(p6,"Player ESP (tên + khoảng cách)",false,function(v) S.PESP=v if v then espStart() else espStopIfIdle() end end)
tog(p6,"Boss ESP",false,function(v) S.BESP=v if v then espStart() else espStopIfIdle() end end)
tog(p6,"Mob ESP (giới hạn số con để nhẹ)",false,function(v) S.MESP=v if v then espStart() else espStopIfIdle() end end)
tog(p6,"Chest ESP",false,function(v) S.CESP=v if v then espStart() else espStopIfIdle() end end)
tog(p6,"Fruit ESP",false,function(v) S.FESP=v if v then espStart() else espStopIfIdle() end end)

-- ===== TAB 7: TP =====
local p7=pages[7]
sec(p7,"📍 TP ISLAND")
local iNames={} for _,i in ipairs(Islands) do table.insert(iNames,i.n) end
drop(p7,"Đảo: ",iNames,"Starter Island",function(v) S.SelIsland=v end)
btn(p7,"📍 TP đến đảo",function()
    for _,i in ipairs(Islands) do if i.n==S.SelIsland then stopMove() toTarget(i.p*CFrame.new(0,25,0),450) notify("TP",i.n,2) return end end
end)
sec(p7,"👤 TP PLAYER GẦN NHẤT")
btn(p7,"📍 TP tới người chơi",function()
    local h=hrp() if not h then return end
    local best,bdp=nil,math.huge
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP and p.Character then
            local ph=p.Character:FindFirstChild("HumanoidRootPart")
            if ph then local d=(ph.Position-h.Position).Magnitude if d<bdp then bdp=d best=p end end
        end
    end
    if best then toTarget(best.Character.HumanoidRootPart.CFrame*CFrame.new(0,5,0),400) notify("TP",best.Name,2) else notify("TP","Không có ai",3) end
end)
sec(p7,"👹 TP BOSS / QUÁI")
btn(p7,"📍 TP tới boss sống",function()
    local m=findAnyBoss()
    if m then toTarget(m.HRP.CFrame*CFrame.new(0,20,0),450) notify("TP",m.Full,2) else notify("TP","Không có boss sống",3) end
end)
btn(p7,"📍 TP tới quái quest",function()
    local qd=getQuest(getLevel(),SEA) or getQuest(0,SEA)
    stopMove() toTarget(qd.cm*CFrame.new(0,20,0),450) notify("TP",qd.b,2)
end)

-- ===== TAB 8: PVP =====
local p8=pages[8]
sec(p8,"⚔️ PVP")
tog(p8,"Aim Assist (ghim camera người gần nhất)",false,function(v) S.AimA=v if v then AA:Start() else AA:Stop() end end)
tog(p8,"Team Check (bỏ qua đồng đội)",true,function(v) S.TeamC=v end)
tog(p8,"Player Tracker (ESP + khoảng cách)",false,function(v) S.PTrack=v if v then espStart() else espStopIfIdle() end end)
tog(p8,"Bounty Tracker (báo bounty cao)",false,function(v) S.BTrack=v if v then BT:Start() else BT:Stop() end end)

-- ===== TAB 9: MISC =====
local p9=pages[9]
sec(p9,"🔄 SERVER")
btn(p9,"Auto Rejoin (vào lại server)",function() Misc:Rejoin() end)
btn(p9,"Server Hop (đổi server)",function() hopServer() end)
btn(p9,"Hop tìm Fruit (cần Auto Exec)",function() Misc:HopFind("fruit") end)
btn(p9,"Hop tìm Boss (cần Auto Exec)",function() Misc:HopFind("boss") end)
sec(p9,"💰 MUA (remote thật)")
btn(p9,"Mua Buso Haki (25,000 Beli)",function() INV("BuyHaki","Buso") notify("Mua","Đã gửi lệnh mua Buso Haki",3) end)
btn(p9,"Mua Geppo (10,000 Beli)",function() INV("BuyHaki","Geppo") notify("Mua","Đã gửi lệnh mua Geppo",3) end)
btn(p9,"Mua Soru (200,000 Beli)",function() INV("BuyHaki","Soru") notify("Mua","Đã gửi lệnh mua Soru",3) end)
btn(p9,"Mua Ken Haki (250,000 Beli)",function() INV("KenTalk","Buy") notify("Mua","Đã gửi lệnh mua Ken Haki",3) end)
btn(p9,"Học Superhuman (3 triệu)",function() INV("BuySuperhuman") notify("Học","Đã gửi lệnh học Superhuman",3) end)
btn(p9,"Học Death Step (5 triệu + 5.000 Fragments)",function() INV("BuyDeathStep") notify("Học","Đã gửi lệnh học Death Step",3) end)
btn(p9,"Học Sharkman Karate (7.5 triệu)",function() INV("BuySharkmanKarate") notify("Học","Đã gửi lệnh học Sharkman Karate",3) end)
btn(p9,"Học Electric Claw (3 triệu + 5.000 Fragments)",function() INV("BuyElectricClaw","Start") task.wait(0.3) INV("BuyElectricClaw") notify("Học","Đã gửi lệnh học Electric Claw",3) end)
btn(p9,"Học Dragon Talon (3 triệu + 5.000 Fragments)",function() INV("BuyDragonTalon") notify("Học","Đã gửi lệnh học Dragon Talon",3) end)
btn(p9,"Học Godhuman (5 triệu + 5.000 Fragments)",function() INV("BuyGodhuman") notify("Học","Đã gửi lệnh học Godhuman",3) end)
sec(p9,"⚓ CHUYỂN BIỂN")
btn(p9,"Sang Sea 2 (cần Lv 700)",function() if SEA==1 then INV("TravelDressrosa") notify("Travel","Đang sang Sea 2...",3) else notify("Travel","Chỉ dùng ở Sea 1",3) end end)
btn(p9,"Sang Sea 3 (cần Lv 1500)",function() if SEA==2 then INV("TravelZou") notify("Travel","Đang sang Sea 3...",3) else notify("Travel","Chỉ dùng ở Sea 2",3) end end)
btn(p9,"Về Sea trước",function() if SEA==2 then INV("TravelMain") elseif SEA==3 then INV("TravelDressrosa") else notify("Travel","Đang ở Sea 1",3) end end)
sec(p9,"⚙️ TIỆN ÍCH")
tog(p9,"Chế độ Nhẹ cho máy yếu (đề xuất mobile)",IS_MOB,function(v) S.Light=v notify("Chế độ Nhẹ",v and "BẬT: giảm tần suất quét để hết lag" or "TẮT: tốc độ tối đa",4) end)
btn(p9,"FPS Boost (giảm đồ họa)",function() Misc:FPS() end)
btn(p9,"Đổi Team (Pirates/Marines)",function()
    if LP.Team and LP.Team.Name=="Pirates" then INV("SetTeam","Marines") notify("Team","Chuyển sang Marines",3)
    else INV("SetTeam","Pirates") notify("Team","Chuyển sang Pirates",3) end
end)
btn(p9,"Đổi phím ẩn/hiện UI",function()
    notify("Đổi phím","Nhấn phím bất kỳ trong 3 giây...",3)
    local c
    c=UIS.InputBegan:Connect(function(i,g) if g then return end if i.KeyCode~=Enum.KeyCode.Unknown then S.UIToggle=i.KeyCode notify("OK","Phím toggle: "..tostring(i.KeyCode):gsub("Enum.KeyCode.",""),3) c:Disconnect() end end)
    task.delay(3,function() if c then c:Disconnect() end end)
end)
sec(p9,"📱 THÔNG TIN")
lbl(p9,"Thiết bị: "..(IS_MOB and "Mobile" or "PC"))
lbl(p9,"Executor: "..(getexecutorname and getexecutorname() or "Unknown"))
lbl(p9,"Sea: "..SEA.." | Level: "..getLevel().."/3000")

-- ===== DRAG + TOGGLE + MINIMIZE =====
local dg,ds,sp
top.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dg=true ds=i.Position sp=main.Position end end)
UIS.InputChanged:Connect(function(i) if dg and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then local d=i.Position-ds main.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end end)
UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dg=false end end)
UIS.InputBegan:Connect(function(i,g) if not g and i.KeyCode==S.UIToggle then gui.Enabled=not gui.Enabled end end)
local mn=false
minB.MouseButton1Click:Connect(function() mn=not mn body.Visible=not mn
    if mn then tw(main,{Size=UDim2.new(0,280,0,38),Position=UDim2.new(0.5,-140,0,10)},0.2) minB.Text="▢"
    else tw(main,{Size=UDim2.new(0,W,0,H),Position=UDim2.new(0.5,-W/2,0.5,-H/2)},0.2) minB.Text="−" end end)

-- ===== SHOW =====
main.Visible=true main.Size=UDim2.new(0,W,0,H) main.BackgroundTransparency=0
notify("TNThud v10.0","Đã load! Sea "..SEA.." - Level "..getLevel().."\nAuto Farm: Auto Click + State Machine\nBay hết snap back!",6)
print("✅ TNThud v10.0 | Sea:",SEA,"| Level:",getLevel(),"| PlaceId:",game.PlaceId,"| Light:",S.Light)
