; *=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-*
; MonoDrome v1.0 (Release)
; Developed in 2009 by Chrono Syndrome.
; *=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-*

EnableExplicit
InitSprite()
InitKeyboard()
UsePNGImageDecoder()

;{ Definitions
; --Enumerations--
Enumeration ; Sprites
#SBackGround
#SPauseBuffer
#SConnectionLost
#SGameOver
#SPaused
#SWarmUp
#SLogo
#SExplosion
#SAvatar
#SBullet
#SEnemy
EndEnumeration

Enumeration ; Colors
#CWhite
#CCyan
#CYellow
#CRed
EndEnumeration

; --Constants--
#ScreenWidth = 400
#ScreenHeight = 400
#WindowParams = #PB_Window_ScreenCentered | #PB_Window_MinimizeGadget
#Caption = "Developed in 2009 by Chrono Syndrome."
#TSHint = "Press any key to begin..."
#Title = ".[MonoDrome]."
#MainWindow = 0
#TrayIcon = 0
#MaxFPS = 40
#GridSize = 20
#BGWidth = #ScreenWidth + #GridSize 
#GridOffset = #GridSize / 2
#TextOffset = 5
#ShootDelay = 15
#WUCounterWidth = 300
#ExplosionSize = 64
#SSize = 32
#Threadz = 4
#Phazes = 4
#ObjectBlink = 64
#TInterval = #ScreenHeight / #Threadz
#TitleStart = #MaxFPS + 1
#SpawningStart = 55
#WarmUp = #MaxFPS * 3
#FocusLost = 2
CompilerIf #PB_Compiler_Version < 440
#PixelSize = 0
CompilerElse
#PixelSize = 1
CompilerEndIf

; --Structures--
Structure SystemData
; -One-piece data-
*GUIFont
*FPSTimer
*AppIcon
; -GUI Data-
Input.i
Event.i
EventType.i
FPS.i
Paused.i
TitleScreen.I
CLMsg.Point  ; Сообщение "Connection lost..."
GOMsg.Point  ; Сообщение "Game Over"
PMsg.Point   ; Сообщение "Paused"
CStr.Point   ; Сообщение об авторстве.
WarmUp.Point ; Счетчик разогрева.
TSLogo.Point ; Логотип игры.
TSHint.Point ; Подсказки на титульном экране.
; -Data tables-
Colors.l[#Phazes]
Threadz.Point[#Threadz]
*Avatarz.Object[#Threadz]
; -Progress data-
AvatarzCount.i
Spawn.i
SpawnDelay.f
StructureUnion
VolatilityMark.i ; Начальная позиция для обнуления при перезагрузке.
Score.Q
EndStructureUnion
ScorePool.l
; -Effects data-
SinFeeder.i
BGOffset.i
EndStructure

Structure Object
X.i         ; Положение на оси.
Thread.i    ; Порядковый номер оси.
Color.l     ; Цветовая фаза.
Sprite.i    ; Используемое изображение.
HitRadius.i ; Реальный радиус.
Reserved.f  ; Резервное поле. Скорости, например.
EndStructure

; --Varibales--
Global System.SystemData
Global NewList Objectz.Object()
;} EndDefinitions

;{ Procedures
; --Math&Logic--
Procedure Rnd(Min, Max)
ProcedureReturn Random(Max - Min) + Min
EndProcedure

Macro GSin(Angle) ; Pseudo-procedure
Sin(Angle * #PI / 180)
EndMacro

Procedure GrayScale(Level.b)
!XOR EAX, EAX
!MOV byte AH, [p.v_Level]
!MOV byte AL, AH
!SHL EAX, 8
!MOV AL, AH
ProcedureReturn
EndProcedure

; --Input/Ouput--
Procedure GetInput()
ExamineKeyboard()
If KeyboardReleased(#PB_Key_Escape) : ProcedureReturn 'Exit' : EndIf
ProcedureReturn Asc(UCase(KeyboardInkey()))
EndProcedure

Procedure CountFPS()
Static Fps, FpsCounter, FpsTime, FpsTimeOld
FpsCounter + 1
FpsTime = ElapsedMilliseconds()
If FpsTime - FpsTimeOld >1000
FpsTimeOld = FpsTime
Fps = FpsCounter
FpsCounter = 0
EndIf
ProcedureReturn Fps
EndProcedure

Procedure CreateTimer(Period)
Define Junk.FILETIME, *Timer
*Timer = CreateWaitableTimer_(#Null, #False, #Null)
SetWaitableTimer_(*Timer, @Junk, Period, #Null, #Null, #False)
ProcedureReturn *Timer
EndProcedure

Macro PrepareString(Text, CoordsCache, BottomOffset) ; Pseudo-procedure
CoordsCache\X = (#ScreenWidth - TextWidth(Text)) / 2
CoordsCache\Y = #ScreenHeight - TextHeight(Text) - BottomOffset
EndMacro

Macro PrepareMessage(SpriteIdx, SourcePtr, CoordsCache, SetX = #True, CenterY = #True) ; Pseudo-procedure
CatchSprite(SpriteIdx, SourcePtr)
CompilerIf SetX : CoordsCache\X = (#ScreenWidth - SpriteWidth(SpriteIdx)) / 2
CompilerEndIf
CompilerIf CenterY = #False : CoordsCache\Y = SpriteHeight(SpriteIdx) / 2
CompilerElse : CoordsCache\Y = (#ScreenHeight - SpriteHeight(SpriteIdx)) / 2
CompilerEndIf
EndMacro

Macro PreparePauseMode() ; Pseudo-procedure
GrabSprite(#SPauseBuffer, 0, 0, #ScreenWidth, #ScreenHeight)
EndMacro

Macro Hide2Tray() ; Pseudo-procedure
#ToolTip = #Title + #CR$ + "-Left click to continue" + #CR$ + "-Right click to terminate"
If AddSysTrayIcon(#TrayIcon, WindowID(#MainWindow), System\AppIcon)
SysTrayIconToolTip(#TrayIcon, #ToolTip)
HideWindow(#MainWindow, #True)
EndIf
EndMacro

Macro OutputSprite(Sprite, x, y , Intensity = $FF, Color = $FFFFFF) ; Partializer.
DisableDebugger : DisplayTransparentSprite(Sprite, x, y , Intensity, Color) : EnableDebugger
EndMacro

; -Objects management-
Procedure AddObject(Type, X, Thread, ColorIdx)
Define *Obj.Object
AddElement(Objectz()) : *Obj = Objectz()
With *Obj
\Sprite = Type : \X = X
\Thread = Thread
\Color = System\Colors[ColorIdx]
Select Type
Case #SAvatar : \HitRadius = #SSize / 2 - 2
Case #SBullet : \HitRadius = #SSize / 2 - 9 : \Reserved = 3
Case #SEnemy  : \HitRadius = #SSize / 2 - 3 : \Reserved = -2
EndSelect
EndWith
ProcedureReturn *Obj
EndProcedure

Procedure TryShoot(*Shooter.Object, BulletPhaze)
With *Shooter
If \Sprite > #SExplosion
If \Reserved = 0 : AddObject(#SBullet, \X, \Thread, BulletPhaze) : \Reserved = #ShootDelay : EndIf
EndIf
EndWith
EndProcedure

Macro CheckHit(Obj1, Obj2) ; Pseudo-procedure
Abs(Obj1\X - Obj2\X) <= (Obj1\HitRadius + Obj2\HitRadius) And (Obj1\Thread = Obj2\Thread)
EndMacro

Procedure ExplodeObject(*Obj.OBject)
With *Obj
If \Sprite = #SAvatar : \Reserved = 0 : EndIf
\Sprite = #SExplosion
\X - (#ExplosionSize - #SSize) / 2
\HitRadius = 250
EndWith
EndProcedure

Procedure MoveObject(*OBj.Object)
Define *LPos, *Target.OBject
With *Obj
If \X < #ScreenWidth Or \Sprite <> #SBullet : \X + \Reserved
If \Sprite <> #SExplosion
If ListIndex(Objectz()) : *LPos = @Objectz() : EndIf
ForEach Objectz() : *Target = Objectz()
If *Target <> *Obj
If CheckHit(*Obj, *Target) ; Если произошло столкновение...
Select \Sprite
Case #SBullet : If *Target\Sprite = #SEnemy : \Sprite = #PB_Ignore
If \Color = *Target\Color : ExplodeObject(*Target) : System\ScorePool + System\AvatarzCount : EndIf
Break : EndIf
Case #SEnemy : If *Target\Sprite = #SAvatar : ExplodeObject(*Obj) : ExplodeObject(*Target) : Break 
EndIf
EndSelect
EndIf
EndIf
Next
If *LPos : ChangeCurrentElement(Objectz(), *LPos) : EndIf
EndIf
Else : \Sprite = #PB_Ignore : EndIf
EndWith
EndProcedure

; --World render--
Macro GetThreadY(ThreadIdx)
System\Threadz[ThreadIdx]\Y + System\Threadz[ThreadIdx]\X
EndMacro

Procedure DrawThreads()
With System
Define I, Color.l = RGB(0, 127 + GSin(\SinFeeder) * 128, 0)
Define Noise, Base
For I = 0 To #Threadz - 1
If \Avatarz[I]\Sprite = #PB_Ignore 
Base = I * #TInterval
For Noise = 1 To 5000
Plot(Random(#ScreenWidth - 1), Base + Random(#TInterval - 1), GrayScale(Random(127) + 128))
Next Noise
If \AvatarzCount > 0 ; "Connection lost..." message.
OutputSprite(#SConnectionLost, \CLMsg\X, GetThreadY(I) - \CLMsg\Y)
EndIf
Else : Line(0, GetThreadY(I), #ScreenWidth, #PixelSize, Color)
EndIf
Next I 
If \AvatarzCount = 0 : OutputSprite(#SGameOver, \GOMsg\X, \GOMsg\Y) : EndIf
EndWith
EndProcedure

Procedure RenderObjects()
Define X, Y, Alpha.f
Define *Obj.Object
ForEach Objectz() : *Obj = Objectz()
With *Obj
If \Sprite <> #PB_Ignore
If \Sprite = #SExplosion : Alpha = \HitRadius
Y = GetThreadY(\Thread) - #ExplosionSize / 2
Else : If System\TitleScreen ; Если идет угасание заставки...
Alpha = (1 - System\TitleScreen / #TitleStart) * (255 - #ObjectBlink)
Else : Alpha = 255 - GSin(System\SinFeeder) * #ObjectBlink
EndIf
Y = GetThreadY(\Thread) - #SSize / 2
EndIf : OutputSprite(\Sprite, \X, Y, Alpha, \Color)
EndIf
EndWith
Next
EndProcedure

Procedure DrawGUI()
Define I, Y, Txt.S, Val.f, *Obj.Object
With System
; -WarmUp counter render-
Val = (\Spawn - #SpawningStart) / #MaxFPS
If Val > 0 : I = Int(Val)
ClipSprite(#SWarmUp, I * #WUCounterWidth, 0, #WUCounterWidth, #ScreenHeight)
OutputSprite(#SWarmUp, \WarmUp\X, \WarmUp\Y, 220 * (Val - I))
EndIf
; -Score & Copyleft render-
If Val <= 0 : I = #White
Else : Val = (1 - (System\Spawn - #SpawningStart) / #WarmUp) * 255
I = GrayScale(Val)
EndIf
If I > $222222 ; Если текст уже достаточно светлый...
Txt = "SCORE: " + RSet(Str(\Score), 19, "0")
DrawText((#ScreenWidth - TextWidth(Txt)) / 2, #TextOffset, Txt, I) 
EndIf
DrawText(\CStr\X, \CStr\Y, #Caption, #White)
; -Recharge bars render-
For I = 0 To #Threadz - 1 : *Obj = \Avatarz[I]
Y = GetThreadY(I) - #SSize / 2 - 3
Val = *Obj\HitRadius * 2 * (*Obj\Reserved / #ShootDelay)
Box(*Obj\X + (#SSize - Val) / 2, Y, Val, 2, #White)
Next I
EndWith
EndProcedure

Procedure DisplayTitleScreen()
Define Color, Val.F
With System
Val = (\TitleScreen / #TitleStart) * 255
OutputSprite(#SLogo, \TSlogo\X, \TSlogo\Y, Val)
Color = GrayScale(Val) : Val = 255 - Val
DrawText(\TSHint\X + Val, #TextOffset, #TSHint, Color)
DrawText(\TSHint\X - Val, \TSHint\Y, #TSHint, Color)
EndWith
EndProcedure
;} EndProcedures

;{ Macros
Macro Initialization()
; -Window preparation-
OpenWindow(#MainWindow, 0, 0, #ScreenWidth, #ScreenHeight, #Title, #WindowParams)
OpenWindowedScreen(WindowID(#MainWindow), 0, 0, #ScreenWidth, #ScreenHeight, 0, 0, 0)
; -Font preparation-
System\GUIFont = FontID(LoadFont(#PB_Any, "Verdana", 8))
; -Timer preaparation-
System\FPSTimer = CreateTimer(1000 / #MaxFPS)
; -Tray icon preaparation-
System\AppIcon = ExtractIcon_(#Null, ProgramFilename(), 0)
; -Background preparation-
Define I
CreateSprite(#SBackGround, #BGWidth, #ScreenHeight)
StartDrawing(SpriteOutput(#SBackGround))
For I = #GridOffset To #ScreenHeight Step #GridSize : Line(0, I, #BGWidth, #PixelSize, $404040) : Next I
For I = #GridOffset To #BGWidth Step #GridSize : Line(I, 0, #PixelSize, #ScreenHeight, $404040) : Next I
For I = 0 To #Threadz - 1 : System\Threadz[I]\Y = #TInterval / 2 + I * #TInterval : Next I
; -Strings preparation-
DrawingFont(System\GUIFont)
PrepareString(#Caption, System\CStr, #TextOffset)
PrepareString(#TSHint, System\TSHint, #TextOffset)
StopDrawing()
; -Colors preparation-
System\Colors[0] = #White : System\Colors[1] = #Cyan
System\Colors[2] = #Yellow : System\Colors[3] = #Red
; -Binary data encapsulation-
DataSection : IncludePath "Resources\"
SConnectionLost: :IncludeBinary "ConnectionLost.PNG"
SGameOver:       :IncludeBinary "GameOver.PNG"
SPaused:         :IncludeBinary "Paused.PNG"
SWarmUp:         :IncludeBinary "WarmUp.PNG"
SLogo:           :IncludeBinary "Logo.PNG"
SExplosion:      :IncludeBinary "Explosion.PNG"
SAvatar:         :IncludeBinary "Avatar.PNG"
SBullet:         :IncludeBinary "Bullet.PNG"
SEnemy:          :IncludeBinary "Enemy.PNG"
EndDataSection
; -Sprites preparation-
SpriteQuality(#PB_Sprite_BilinearFiltering)
CatchSprite(#SExplosion, ?SEXplosion)
CatchSprite(#SAvatar, ?SAvatar)
CatchSprite(#SBullet, ?SBullet)
CatchSprite(#SEnemy, ?SEnemy)
; -Messages preparation-
PrepareMessage(#SConnectionLost, ?SConnectionLost, System\CLMsg, #True, #False)
PrepareMessage(#SGameOver, ?SGameOver, System\GOMsg)
PrepareMessage(#SPaused, ?SPaused, System\PMsg)
PrepareMessage(#SLogo, ?SLogo, System\TSLogo)
PrepareMessage(#SWarmUp, ?SWarmUp, System\WarmUp, #False)
System\WarmUp\X = (#ScreenHeight - #WUCounterWidth) / 2
System\TitleScreen = #TitleStart
; -Avatarz preparation-
Restart: ; Начальная позиция при горячей перезагрузке.
For I = 0 To #Threadz - 1
System\Avatarz[I] = AddObject(#SAvatar, 10, I, #CWhite)
Next I
; -System preparations-
System\AvatarzCount = #Phazes
System\SpawnDelay = #SpawningStart
System\Spawn = #SpawningStart + #WarmUp ; Задержка в 3 секунды.
EndMacro

Macro UpdateWorld()
If System\Paused = #False
; -Enemy respawn-
Define Thread
If System\Spawn = 0 
Repeat : Thread = Random(#Threadz - 1)
Until System\Avatarz[Thread]\Sprite <> #PB_Ignore 
AddObject(#SEnemy, #ScreenWidth, Thread, Rnd(1, #Phazes - 1))
System\Spawn = System\SpawnDelay - System\AvatarzCount
Else : System\Spawn - 1
EndIf
If System\SpawnDelay > #ShootDelay + #Threadz
System\SpawnDelay - 0.003 * (#Threadz + 1 - System\AvatarzCount) ; Декремент задержки respawn'а.
EndIf
; -Objects update-
Define Idx, *Obj.Object
ForEach Objectz() : *Obj = Objectz()
Idx = ListIndex(Objectz())
Select *Obj\Sprite
Case #SAvatar : If *Obj\Reserved : *Obj\Reserved - 0.2 * (System\AvatarzCount + 1)
If *Obj\Reserved < 0 : *Obj\Reserved = 0 : EndIf ; Все же float'ы.
EndIf
Case #SBullet, #SEnemy : MoveObject(*Obj)
Case #SExplosion : If *Obj\HitRadius > 0
*Obj\HitRadius - 10 : MoveObject(*Obj)
If Idx < #Threadz : System\Threadz[Idx]\X = Rnd(-#SSize, #SSize) : EndIf
Else : *Obj\Sprite = #PB_Ignore
If Idx < #Threadz : System\Threadz[Idx]\X = 0 : System\AvatarzCount - 1 : EndIf 
EndIf
EndSelect
Next
; -Clean up-
ForEach Objectz() : *Obj = Objectz()
If *Obj\Sprite = #PB_Ignore Or System\Avatarz[*Obj\Thread]\Sprite = #PB_Ignore
If ListIndex(Objectz()) > #Threadz - 1 : DeleteElement(Objectz()) : EndIf
EndIf
Next
EndIf
EndMacro

Macro Controls()
#ErasureStart = OffsetOf(SystemData\VolatilityMark)
#MR_YesNo = #PB_MessageRequester_YesNo
#MR_Yes = #PB_MessageRequester_Yes
; -Register input-
System\Input = GetInput()
System\FPS = CountFPS()
System\Event = WindowEvent()
System\EventType = EventType()
; -Windows events check-
Select System\Event
Case #PB_Event_SysTray
If System\EventType = #PB_EventType_LeftClick 
RemoveSysTrayIcon(#TrayIcon)
HideWindow(#MainWindow, #False)
ElseIf System\EventType = #PB_EventType_RightClick : End
EndIf
Case #PB_Event_CloseWindow : End ; Немедленный выход.
EndSelect
; -Focus check-
If GetActiveWindow() <> #MainWindow
If System\Paused = #False And System\AvatarzCount > 0 And System\TitleScreen < #TitleStart
PreparePauseMode() : System\Paused = #FocusLost : EndIf
ElseIf System\Paused = #FocusLost : System\Paused = #False
EndIf
; -Input check-
If System\TitleScreen = #False ; Если не демонстрируется заставка...
Define Thread, BColor = 0
Select System\Input
Case '1'      : BColor = 1 : Thread = 0
Case '2'      : BColor = 2 : Thread = 0
Case '3'      : BColor = 3 : Thread = 0
Case 'Q', 'Й' : BColor = 1 : Thread = 1
Case 'W', 'Ц' : BColor = 2 : Thread = 1
Case 'E', 'У' : BColor = 3 : Thread = 1
Case 'A', 'Ф' : BColor = 1 : Thread = 2
Case 'S', 'Ы' : BColor = 2 : Thread = 2
Case 'D', 'В' : BColor = 3 : Thread = 2
Case 'Z', 'Я' : BColor = 1 : Thread = 3
Case 'X', 'Ч' : BColor = 2 : Thread = 3
Case 'C', 'С' : BColor = 3 : Thread = 3
Case 'R', 'К' ; Горячая перезагрузка игры.
If System\Paused = #False ; Если игра не на паузе...
If System\AvatarzCount > 0 ; Если игра еще окончена...
Thread = MessageRequester(#Title, "Are you sure want to restart game ?", #MR_YesNo)
Else : Thread = #MR_Yes : EndIf
If Thread = #MR_Yes ; Если было получено подтверждение...
ZeroMemory_(System + #ErasureStart, SizeOf(SystemData) - #ErasureStart)
For BColor = 0 To #Threadz - 1 : System\Threadz[BColor]\X = 0 : Next BColor
ClearList(Objectz())
Goto Restart
EndIf
EndIf
Case ' ', 'P', 'З' ; Режим паузы.
If System\AvatarzCount > 0 ; Если игра продолжается...
If System\Paused = #False : PreparePauseMode() : EndIf
System\Paused = ~System\Paused
EndIf
Case 'Exit' ; Выход из игры.
If System\Paused = #False ; Если игра не на паузе...
If System\AvatarzCount = 0 : End ; Если игра закончена...
ElseIf MessageRequester(#Title, "Are you sure want to exit ?", #MR_YesNo) = #MR_Yes : End
EndIf
EndIf
Case #TAB : Hide2Tray() ; Экстренное сворачивание окна игры в tray.
EndSelect
If BColor And System\Paused = #False : TryShoot(System\Avatarz[Thread], BColor) : EndIf
ElseIf KeyboardReleased(#PB_Key_All) ; Если нажата какая-либо клавиша...
If System\Input = 'Exit' : End : EndIf ; Выход по Escape'у.
If System\Input = #TAB : Hide2Tray() ; Сворачивание игры в tray.
ElseIf System\TitleScreen = #TitleStart : System\TitleScreen - 1 : EndIf ; Выход с экрана заставки.
EndIf 
EndMacro

Macro UpdateEffects()
If System\Paused = #False
If System\BGOffset = -#GridSize : System\BGOffset = 0 : Else : System\BGOffset - 1 : EndIf
If System\SinFeeder = 180 : System\SinFeeder = 0 : Else : System\SinFeeder + 2 : EndIf
If System\ScorePool : System\Score + 1 : System\ScorePool - 1 : EndIf
If System\TitleScreen And System\TitleScreen < #TitleStart : System\TitleScreen - 1 : EndIf
RotateSprite(#SAvatar, 2, 1)
EndIf
EndMacro

Macro Vizualization()
Define I
If System\Paused = #False
DisplaySprite(#SBackGround, System\BGOffset, 0)
StartDrawing(ScreenOutput())
DrawingMode(#PB_2DDrawing_Transparent)
DrawingFont(System\GUIFont)
DrawThreads()
SpriteBlendingMode(3, 5)
If System\TitleScreen < #TitleStart : RenderObjects() : EndIf
If System\TitleScreen = #False : DrawGUI()
Else : DisplayTitleScreen()
EndIf
StopDrawing()
Else ; Экран паузы.
ClearScreen(#Black)
DisplayTransparentSprite(#SPauseBuffer, 0, 0, 100)
DisplayTransparentSprite(#SPaused, System\PMsg\X, System\PMsg\Y)
EndIf
FlipBuffers()
EndMacro
;} EndMacros

; -Main Code-
Initialization()
Repeat
If System\AvatarzCount > 0 And System\TitleScreen = #False : UpdateWorld() : EndIf
Controls()
UpdateEffects()
Vizualization()
WaitForSingleObject_(System\FPSTimer, #INFINITE)
ForEver
; IDE Options = PureBasic 5.21 LTS (Windows - x86)
; Folding = ---
; UseIcon = Resources\ExeIcon.ico
; Executable = MonoDrome.exe