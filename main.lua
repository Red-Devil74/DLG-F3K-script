local options = {
--  { "Altitude", SOURCE, 1 },
  { "Background", COLOR, GREY },
  { "Text", COLOR, WHITE }
--  { "Interval", VALUE, 8, 1, 35 }
}
--
stateTxt = {"Stopped","Initialised","Ready","Launch!","Gliding"}
maxPoints = 250
state = 0
yMaxInit = 30				-- initial max altitude on graph (m)
xMaxInit = 30				-- initial max time on graph (seconds)
xMax = xMaxInit
yMax = yMaxInit
yScale = 10
xScale = 10
lnchAlt = 0
maxAlt = 0  
alts = {}
for i = 1, maxPoints,1 do
  alts[i] = -10			-- set altitude array values to be below the visible graph range
end
startTime = 0


--  ==============
--	create initialiseert een nieuwe instantie van de widget 
--	en maakt de context aan waarop alle instellingen / data 
--	van die widget instantie worden opgeslagen
--  ==============
function create (zone, options)
  local context = { zone=zone, options=options,index=0 }	--points={}, lastTime=0,
  return context
end

--  ==============
--	  update wordt aangeroepen als je de opties van de widget aanpast
--  ==============
function update (context, options)
  context.options = options
  context.index = 0
end

-- ===============
--	refresh functie wordt aangeroepen wanneer de widget het scherm moet vullen. 
--	Dit is voornamelijk het tekenen en dergelijke, maar hier kan je ook berekeningen uitvoeren
-- ===============
function refresh (context)
--  getdata (context)
  if getdata (context) == 0 then
    drawgraph (context)
  end
end
-- ==============
--	background functie wordt aangeroepen als de widget niet actief op het scherm is (andere scherm in beeld)
-- ==============
function background (context)
  getdata (context)
end
-- ==============
-- end of main blocks. Below blocks will be called above
-- ==============
function initiate (context)
  yMax = yMaxInit
  xMax = xMaxInit
  state = 0
  lnchAlt = 0
  maxAlt = 0
  xSpeed = 0
  for i = 1, maxPoints do
    alts[i] = -10			-- set altitude array values to be below the visible graph range
  end
  startTime = 0

end
--
function getdata (context)  
  --print("tst-debug:","getdata loaded")
  returnVal = 0
  x = context.zone.x
  y = context.zone.y
  width = context.zone.w
  height = context.zone.h
  if width > maxPoints then
    graphWidth = maxPoints else
    graphWidth = width
  end

  swF = getValue ('sf')				-- get value of switch F (Tx launch mode)
  --print("tst-debug:","swF status = ",swF)
  nowAlt = getValue ('Alt')
  --print("tst-debug:","Altitude = ",nowAlt)
--  ================================
--	  variables for user to adjust
--  ================================
  floorAlt = 2				-- altitude threshold for starting and stopping the flight (m)
  --  ======================
  --	State 0 = Init
  --	State 1 = Ready
  --	State 2 = launch climb
  --	State 3 = gliding
  --	State -1 = Stopped
  --  ======================
  --print("tst-debug: State = ", stateTxt [state+2], "Launch/Max Alt = ",lnchAlt,maxAlt)
  if state == 0 and swF > 0 then					-- if SF was moved to launch mode from "init/stop" state
    initiate (context)								-- reset graph data & scale
    state = 1									-- change state to "ready"
    --print("tst-debug: State = ", stateTxt [state+2], "Launch/Max Alt = ",lnchAlt,maxAlt)
  elseif state == 1 and swF < 0 then				-- if launch mode is ended without a flight
    state = 0									-- change state to "stop"
    --print("tst-debug: State = ", stateTxt [state+2], "Launch/Max Alt = ",lnchAlt,maxAlt)
  elseif state == 1 and nowAlt > floorAlt then	-- if launch detected in "ready" state
    -- model.resetTimer(0)
    startTime = getTime () /100					-- set flight start time (seconds)
    alts[context.index] = nowAlt							-- set first altitude point
    context.index = 2									-- set index for 2nd alt point
    state = 2									-- change state to "launch climb"
    --lnchNr = lnchNr + 1							-- increment the launch number
    --maxAlt = math.max (nowAlt,maxAlt)
    lnchAlt = maxAlt							-- set launch altitude
    --print("tst-debug: State = ", stateTxt [state+2], "Launch/Max Alt = ",lnchAlt,maxAlt)
  elseif state == 2 and nowAlt < maxAlt then		-- if in "launch climb" and altitude decreases
    lnchAlt = nowAlt							-- set launch altitude
    playNumber (lnchAlt*10,9,PREC1)
    state = 3									-- set state = "gliding"
    --print("tst-debug: State = ", stateTxt [state+2], "Launch/Max Alt = ",lnchAlt,maxAlt)
  elseif state > 1 and nowAlt < floorAlt then		-- if "in flight" and altitude drops below X
    --fltTime = model.getTimer(0).value           -- log the duration of this flight
    state = -1									-- change state to "stop" but keep graph on screen
    --print("tst-debug: State = ", stateTxt [state+2], "Launch/Max Alt = ",lnchAlt,maxAlt)
  elseif state == -1 and swF > 0	then							-- motivate script to initialise, and go to state 0
    state = 0
    --print("tst-debug: State = ", stateTxt [state+2], "Launch/Max Alt = ",lnchAlt,maxAlt)
  end
--
  if state > 1 then
    maxAlt = math.max (nowAlt,maxAlt)
  end

  --  ----------------------------------------------------
  --	  if the graph maximum X is reached, re-scale in X
  --  ----------------------------------------------------
  if state > 1 and context.index > graphWidth  then								-- if graph is full
    returnVal = 1
    j = 1															-- temporary index number for compacted array
    for i = 1, graphWidth do											-- compact the array, skipping every 4th point
      if i % 4 ~= 0 then											-- if not every 4th point
        alts[j] = alts[i]									-- copy to compacted array
        j = j+1							  						-- increment j
      end
    end
    --
    for i= j, graphWidth do												-- reset the "empty" data at the end so it doesn't plot
      alts[i] = -10
    end
    context.index = j														-- set index to first "empty" location
    xMax = xMax * 4/3												-- new graph max time (sec)
    xSpeed = graphWidth/xMax											-- new graph speed (pixels/sec)
    -- check the scale marker count, and adjust if needed
    xScale = 12														-- start with marker interval = 12 seconds
    while xMax/xScale > 7 do										-- as long as there would be more than 7 of them
      xScale = xScale+10											-- increase the marker interval by 10 seconds
    end
  end
  --  ----------------------------------------------------
  --	  if the graph maximum Y is reached, re-scale in Y
  --  ----------------------------------------------------
  if state > 1 and nowAlt > yMax then		--  if "in flight" and altitude reaches top of graph
    returnVal = 1
    yMax = yMax+10						-- add 10 m to top of graph

    -- check the scale marker count, and adjust if needed
    yScale = 10							-- start with marker interval = 10 m
    while yMax/yScale > 4 do			-- as long as there would be more than 4 of them
      yScale = yScale*2				-- double the marker interval
    end
  end

--  =======================
--	graph the Altitude data
--  =======================
  xSpeed = graphWidth/xMax	
  nowTime = getTime ()/100								-- get current time (seconds since radio started)
  --nowTime = model.getTimer(0).value    -- get current time (seconds since radio started)
  enoughTime = startTime + context.index/xSpeed
  if state > 1 and nowTime > enoughTime then 		-- if "in flight" AND enough time has elapsed,
    alts[context.index] = nowAlt										-- add current altitude to array
    context.index = context.index + 1												-- increment the index
    --   print("Index = ",context.index)
  end
  return returnVal
end
-- 
--
function drawgraph (context)
  -- returnVal = 0
-- =====================
-- MAKE Y-AXIS GRIDLINES
-- =====================
  lcd.setColor (CUSTOM_COLOR, context.options.Text)
--  lcd.setColor (CUSTOM_COLOR2, context.options.Background)
  lcd.drawRectangle (x,y,graphWidth,height,SOLID+CUSTOM_COLOR)
--  lcd.drawFilledRectangle (x+1,y+1,width-2,height-2,CUSTOM_COLOR)
  for i = yScale, yMax, yScale do									             	-- create Y-axis scale (For i goes from 10 to 40 with steps of 10)
    yCor = height*(yMax-i)/(yMax)							                -- calculate y coordinates
    lcd.drawNumber (x , y+yCor , i , SMLSIZE+CUSTOM_COLOR)					            	-- draw graph scale number
    if yCor > 0 then-- Check if horizontal graphline is below "frame"
      lcd.drawLine (x+1, y+yCor , x+graphWidth - 2 , y+yCor , DOTTED, CUSTOM_COLOR)						-- draw horizontal line
    end
  end
  --

  -- =====================
  -- MAKE X-AXIS GRIDLINES
  -- =====================
  xSpeed = graphWidth/xMax
  for i = xScale*xSpeed, graphWidth, xScale*xSpeed do								-- create X-axis scale lines
    if x+i < graphWidth then
      lcd.drawLine (x+i, y , x+i , y+height , DOTTED , CUSTOM_COLOR)	-- vert lines
    end
  end

--
  --
  if state >1 or state ==-1 then
    if previous_xPos == nil then
      previous_xPos = x
    end
    if previous_yPos == nil then
      previous_yPos = y+height
    end
    -- maxAlt = math.max (nowAlt,maxAlt)									-- update maximum altitude
    for i = 1, graphWidth, 1 do
      xPos = x+i
      yPos = y + (height * (yMax-alts[i]) / yMax ) 					-- calculate Y coordinate for graph point
      lcd.setColor (CUSTOM_COLOR,RED)
      --lcd.drawPoint (xPos,yPos)
      lcd.drawLine (previous_xPos , previous_yPos , xPos , yPos , SOLID , CUSTOM_COLOR)		-- draw point for altitude
      previous_xPos = xPos
      previous_yPos = yPos
    end
  end
  if state >= -1 and state < 2 then
    lcd.drawText (x+graphWidth - 60, y + 5, "L\194:",SMLSIZE+INVERS)
    lcd.drawNumber (x+graphWidth - 32, y + 5, lnchAlt*10,SMLSIZE+INVERS+PREC1)
    lcd.drawText (x+graphWidth - 60, y + 20,"M\192:", SMLSIZE+INVERS)
    lcd.drawNumber (x+graphWidth - 32, y + 20, maxAlt*10, SMLSIZE+INVERS+PREC1)
    lcd.drawText (x+3,y+height-16, stateTxt[state+2] ,SMLSIZE+INVERS)
  end

--  return returnVal
--print("tst-debug:","Drawgraph loaded")
end 
--
--
return { name="DLG-Graph", options=options, create=create, update=update, refresh=refresh, background=background }
