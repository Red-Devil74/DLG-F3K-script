--[[
  ============================
  ===  D L G    T R A C E  ===
  ============================

rev 2.1   06/15/2015
	J.W.G.  (filago on RCGroups)

rev 3.0.1 20/11/2016
	A.A. Costerus

  Rewrite of openTX code of a 2.1 script to a OpenTX 2.2 widget!
  
  LUA Script for OpenTX to graph altitude vs time with DLG launch.
  X-axis will automatically re-scale by +33% seconds if the max is reached.
  Y-axis will automatically re-scale by +5 m if the max is reached.

  The graph code is leveraged from an openTX script.
  There are no other files required (such as BMP images) to run this script.
  Put file in SCRIPTS/MODELNAME and rename telem1.lua, telem2.lua, etc, up to 7.

--]]

-- ==============
-- options that can be configured in the interface
-- ==============
local options = {
  { "Color", COLOR, WHITE },
  { "Shadow", COLOR, BLACK }
}

--  ================================
--	  variables for user to adjust
--  ================================
yMaxInit = 40				-- initial max altitude on graph (m)
xMaxInit = 30				-- initial max time on graph (seconds)
floorAlt = 2				-- altitude threshold for starting and stopping the flight (m)

--  -----------------------------
--	  the rest of the variables
--  -----------------------------
value = getFieldInfo("Alt")			-- Get field info value
	if value ~= nil then
	vario = value.id 				-- Get .id from field index only if value is not equal to nil
	else
	vario=258
--alt_id = 258					--Unable to get this to work. temp hardcode current ID in.... fix later
	end 
SF_id  = getFieldInfo("sf").id		-- get field index # for switch F (Tx launch mode)
thr_id = getFieldInfo("thr").id		-- get field index # for throttle stick
--value = getFieldInfo("RxBt")
--	if value ~= nil then
--	a1_id  = value.id				-- get field index # for voltage
--	else
--	a1_id = 252						--Unable to get this to work. temp hardcode current ID in.... fix later
--	end
t1_id  = getFieldInfo("timer1").id	-- get field index # for timer 1 (seconds)
gLeft     = 55						-- starting column of graph
gWidth    = 300						-- width of graph data area, and array size
gRight    = gLeft+gWidth			-- ending column of 
gHeight = 0 						-- Height of graph
state     = 0						-- program state : 0=init/stop, 1=ready, 2=launch climb, 3=gliding
alts      = {}						-- array definition for graphed altitude values
startTime = 0						-- time at start of flight
fltTime=0							-- duration of each flight
nowTime=0							-- current time
lnchAlt=0							-- top of launch
maxAlt=0							-- maximum altitude during flight
nowAlt=0							-- current altitude
swF	=0								-- switch F value from Tx (<0 is UP for launch mode)
lnchnr = 0 							-- launch counter
a1		=0							-- voltage from Tx
timer1	=0							-- timer 1 from Tx (sec > min)
index	=0							-- array index position
xMax	=0							-- X-axis max value (sec)
xScale	=0							-- X-axis marker interval (m)
xSpeed	=0							-- X-axis speed (pixels/second)
y		=0							-- temp use for calculating Y coordinate
yMax	=0							-- Y-axis max value (m)
yScale	=0							-- Y-axis marker interval (sec)
menuBar	= 50						-- set height of the menuBar
gHeight	= 180				-- set initial graph Height

--  ==============
--	create initialiseert een nieuwe instantie van de widget 
--	en maakt de context aan waarop alle instellingen / data 
--	van die widget instantie worden opgeslagen
--  ==============
function create(zone, options)
	context = { zone=zone, options=options, points={}, lastTime=0, index=0 }
	return context
end

--  ==============
--	  update wordt aangeroepen als je de opties van de widget aanpast
--  ==============
function update(context, options)
	context.options = options
	context.index = 0
end

-- ===============
--	refresh functie wordt aangeroepen wanneer de widget het scherm moet vullen. 
--	Dit is voornamelijk het tekenen en dergelijke, maar hier kan je ook berekeningen uitvoeren
-- ===============

function refresh(context)
	init(context)
	mainCode(context)
end


-- ==============
--	background functie wordt aangeroepen als de widget niet actief op het scherm if (andere scherm in beeld)
-- ==============
function background(context)
	
end
-- ==============
-- end of main blocks. below blocks will be called above
-- ==============

function init(context)
	for i = 1, gWidth do
		alts[i] = -10			-- set altitude array values to be below the visible graph range
	end
	xMax = xMaxInit				-- set X-axis max value (sec)
	xSpeed = gWidth/xMax		-- set X-axis speed (pixels/second)
	xScale = 5					-- set X-axis marker interval (s)
	yMax = yMaxInit				-- set Y-axis max value (m)
	yScale = 10					-- set Y-axis marker interval (sec)
	lnchAlt = 0					-- reset flight launch altitude
	maxAlt = 0					-- reset flight max altitude
	fltTime = 0					-- reset flight duration
	index = 1					-- set initial array position

end

function mainCode(context)				-- this function will run until it is stopped
--	lcd.clear ()					-- clear the display
	swF = getValue(SF_id)				-- get value of switch F (Tx launch mode)
	nowAlt = getValue(vario)			-- get current altitude from vario (m)

--  ----------------------------------
--	  change program if needed
--  ----------------------------------
	if state == 0 and swF > 0 then					-- if SF was moved to launch mode from "init/stop" state
		init(context)								-- reset graph data & scale
		state = 1									-- change state to "ready"
	elseif state == 1 and swF < 0 then				-- if launch mode is ended without a flight
		state = 0									-- change state to "stop"
	elseif state == 1 and nowAlt > floorAlt then	-- if launch detected in "ready" state
		startTime = getTime()/100					-- set flight start time (seconds)
		alts[1] = nowAlt							-- set first altitude point
		index = 2									-- set index for 2nd alt point
		state = 2									-- change state to "launch climb"
		lnchnr = lnchnr + 1							-- increment the launch number
	elseif state == 2 and nowAlt < maxAlt then		-- if in "launch climb" and altitude decreases
		lnchAlt = maxAlt							-- set launch altitude
		state = 3									-- set state = "gliding"
	elseif state > 1 and nowAlt < floorAlt then		-- if "in flight" and altitude drops below X
		state = 0									-- change state to "stop"
	end

--  ----------------------------------------------------
--	  if the graph maximum Y is reached, re-scale in Y
--  ----------------------------------------------------
	if state > 1 and nowAlt > yMax then		--  if "in flight" and altitude reaches top of graph
		yMax = yMax+10						-- add 10 m to top of graph

-- check the scale marker count, and adjust if needed
		yScale = 10							-- start with marker interval = 10 m
		while yMax/yScale > 6 do			-- as long as there would be more than 6 of them
			yScale = yScale*2				-- double the marker interval
		end
	end

--  -----------------------------------
--	  draw the static graph elements
--  -----------------------------------
	lcd.drawRectangle(gLeft,menuBar,gWidth+2,gHeight,SOLID)					-- graph perimeter
	for i = yScale, yMax, yScale do									-- create Y-axis scale (For i goes from 10 to 40 with steps of 10)
		y = menuBar+(gHeight*(i-yMax)/(0-yMax))						-- calculate y coordinates
		if y-3 > 2 then												-- if number will fit on screen
			lcd.drawNumber(gLeft-18,y-8,i,SMLSIZE)					-- draw graph scale number
		end		
		if y > 2 then												-- if horizonal line is below top of graph
			lcd.drawLine(gLeft+1,y,gRight,y,DOTTED,GREY)			-- draw horizontal line
		end
	end

	for i = xScale*xSpeed, gWidth, xScale*xSpeed do					-- create X-axis scale lines
		lcd.drawLine(gLeft+i,menuBar,gLeft+i,(gHeight+menuBar),DOTTED,GREY)	-- vert lines
	end

--  ---------------------------
--	  graph the Altitude data
--  ---------------------------
	nowTime = getTime()/100											-- get current time (seconds since radio started)

	if state>1 and nowTime>(startTime+index/xSpeed) then 			-- if "in flight" AND enough time has elapsed,
		alts[index] = nowAlt										-- add current altitude to array
		index = index+1												-- increment the index
	end

--  ---------------------------
--	draw graph data
--  ---------------------------
	lcd.setColor (CUSTOM_COLOR,RED)
	for i = 1, gWidth do
		y = menuBar+(gHeight*(alts[i]-yMax)/(0-yMax))					-- calculate Y coordinate for graph point
		if y < (gHeight+menuBar) then									-- don't draw if below graph, because grey point overwrites bottom line.
--			lcd.drawLine(gLeft+i,y,gLeft+i,(menuBar+gHeight),SOLID,GREY)				-- draw grey line down from altitude
			lcd.drawLine(gLeft+i,y+1,gLeft+i,y,SOLID,CUSTOM_COLOR)					-- draw 2 pixel point for altitude
		end
	end

--  ----------------------------------------------------
--	  if the graph maximum X is reached, re-scale in X
--  ----------------------------------------------------
	if index > gWidth  then												-- if graph is full,

		j = 1															-- temporary index number for compacted array
		for i = 1, gWidth do											-- compact the array, skipping every 4th point
			if i % 4 ~= 0 then											-- if not every 4th point
				alts[j] = alts[i]										-- copy to compacted array
				j = j+1													-- increment j
			end
		end

		for i= j, gWidth do												-- reset the "empty" data at the end so it doesn't plot
			alts[i] = -10
		end

		index = j														-- set index to first "empty" location
		xMax = xMax * 4/3												-- new graph max time (sec)
		xSpeed = gWidth/xMax											-- new graph speed (pixels/sec)

		-- check the scale marker count, and adjust if needed
		xScale = 10														-- start with marker interval = 10 seconds
		while xMax/xScale > 7 do										-- as long as there would be more than 7 of them
			xScale = xScale+10											-- increase the marker interval by 10 seconds
		end
	end

--  --------------------------------
--	  calculate and display values
--  --------------------------------
--	a1 = getValue(a1_id)												-- get voltage from the Tx
	timer1 = getValue(t1_id/60)											-- get timer1 value from the Tx (sec > min)
	if state > 1 then													-- if in a flight state
		fltTime = nowTime-startTime										-- calculate the flight duration (sec)
		maxAlt = math.max (nowAlt,maxAlt)								-- update maximum altitude
	end

	if state == 2 then													-- if state is "launch climb"
		lnchAlt = nowAlt												-- update launch altitude with current alt
	end

	lcd.drawText  (gRight+5,  menuBar,"Launch#: ", SMLSIZE+INVERS)		--show launch nr
	lcd.drawNumber(gRight+75,  menuBar, lnchnr, SMLSIZE+INVERS)
--
	lcd.drawText(gRight+5, menuBar+20, "Launch\194", SMLSIZE)			-- Launch height. diagonal up-right arrow
	lcd.drawNumber(gRight+65, menuBar+20, lnchAlt, SMLSIZE)	
	lcd.drawText(gRight+77, menuBar+20, "m", SMLSIZE)
--
	lcd.drawText(gRight+5, menuBar+40, "Time:", SMLSIZE)
	lcd.drawNumber(gRight+65, menuBar+40, fltTime, SMLSIZE)
	lcd.drawText  (gRight+83, menuBar+40,"s", SMLSIZE)

	if maxAlt>lnchAlt then											-- show max alt if > launch alt
		lcd.drawNumber(gRight+30, menuBar+30, maxAlt, SMLSIZE)
		lcd.drawText  (gRight+40, menuBar+30,"m\192", SMLSIZE)		-- up arrow, or use char "^" for max alt
	end
	lcd.drawLine  (gRight+5,menuBar+60,440,menuBar+60 ,SOLID,1)			-- line below current flight values
--	lcd.drawText(gRight+5,menuBar+80, a1*100.."V", SMLSIZE+PREC2)					-- battery voltage
--	lcd.drawText  (gRight+55,menuBar+80,"V"    , SMLSIZE)
	lcd.drawNumber(gRight+5,     menuBar+80, timer1, SMLSIZE)
	lcd.drawText  (gRight+55,     menuBar+80,"min"  , SMLSIZE)
--
	lcd.drawNumber(gRight-60, menuBar, nowAlt*10, SMLSIZE+INVERS+PREC1)
	lcd.drawText  (gRight-30, menuBar, " m" , SMLSIZE+INVERS)
	lcd.drawText (gRight+5,menuBar+100, state ,SMLSIZE+INVERS)
	if nowAlt > floorAlt then
		lcd.drawText (gLeft,menuBar+120, "nowalt("..nowAlt..") > ".."flooralt ("..floorAlt..")" ,SMLSIZE)
		else
		lcd.drawText (gLeft,menuBar+120, "nowalt("..nowAlt..") < ".."flooralt ("..floorAlt..")" ,SMLSIZE)
	end


end






return { name="Test", options=options, create=create, update=update, refresh=refresh, background=background }
