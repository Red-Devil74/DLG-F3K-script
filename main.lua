--[[
  ============================
  ===  D L G    T R A C E  ===
  ============================

rev 2.1   06/15/2015
	J.W.G.  (filago on RCGroups)

rev 3.0.2 14/12/2016
	A.A. Costerus

  Rewrite of openTX code of a 2.1 script to a OpenTX 2.2 widget!

  The idea is that the DLG is prepared and that the screen is initialised 
  by holding (spring loaded) Switch F to up. In my DLG programming the is the launch mode. 
  Launch the DLG. When the climbrate is sufficient, release the switch. 
  Climb rate should be constant. At the top of the launch, do the push over and level off the  DLG. 
  This launch hight should be shown on screen. Gliding mode is activated. 
  When the DLG climbs (thermal/soaring) the maximum altitude should be logged.
  
  Furthermore the RX bat.volgate should be displayed.
  
  LUA Script for OpenTX to graph altitude vs time with DLG launch.
  X-axis will automatically re-scale by +33% seconds if the max is reached.
  Y-axis will automatically re-scale by +5 m if the max is reached.

  The graph code is leveraged from an openTX script.
  There are no other files required (such as BMP images) to run this script.
  Put file in SD-Card/WIDGETS/F3K-DLG/ and rename main.lua.

--]]

-- ==============
-- options that can be configured in the interface
-- ==============
local options = {
	{ "Color", COLOR, WHITE },
	{ "Shadow", COLOR, GREY },
	{ "Altitude", SOURCE, 1 },
	{ "RxBat", SOURCE,1},
	{ "Timer", SOURCE,1}

}

--  ================================
--	  variables for user to adjust
--  ================================
yMaxInit = 30				-- initial max altitude on graph (m)
xMaxInit = 40				-- initial max time on graph (seconds)
floorAlt = 2				-- altitude threshold for starting and stopping the flight (m)

--  -----------------------------
--	  the rest of the variables
--  -----------------------------
SF_id  = getFieldInfo ("sf").id		-- get field index # for switch F (Tx launch mode)
--thr_id = getFieldInfo ("thr").id	-- get field index # for throttle stick
gLeft     = 55						-- starting column of graph
gWidth    = 275						-- width of graph data area, and array size
gRight    = gLeft+gWidth			-- ending column of 
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
xScale	=10							-- X-axis marker interval (m)
xSpeed	=0							-- X-axis speed (pixels/second)
y		=0							-- temp use for calculating Y coordinate
yMax	=0							-- Y-axis max value (m)
yScale	=10							-- Y-axis marker interval (sec)
menuBar	= 50						-- set height of the menuBar
gHeight	= 180						-- set initial graph Height
flghtTime = 0						-- FlightTimer display 
nMins=0								-- used for displaying time propperly
nSecs=0								-- used for displaying time propperly
history = {}						-- tabel for historical data
recordValues = {}					-- tabel for the best values
	recordValues["maxAlt"]=0	-- set record values to 0
	recordValues["lnchAlt"]=0
	recordValues["fltTime"]=0
--nxtRow=0							--variable for displaying text propperly
rowHeight=16						--standard row height

	for i = 1, gWidth do
		alts[i] = -10			-- set altitude array values to be below the visible graph range
	end

--  ==============
--	create initialiseert een nieuwe instantie van de widget 
--	en maakt de context aan waarop alle instellingen / data 
--	van die widget instantie worden opgeslagen
--  ==============
function create (zone, options)
	local context = { zone=zone, options=options, index=0 }	--points={}, lastTime=0,
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
--	init (context)
	maincode (context)
	draw (context)
end


-- ==============
--	background functie wordt aangeroepen als de widget niet actief op het scherm if (andere scherm in beeld)
-- ==============
function background (context)
	maincode (context)
end
-- ==============
-- end of main blocks. Below blocks will be called above
-- ==============

function init (context)
	for i = 1, gWidth do
		alts[i] = -10			-- set altitude array values to be below the visible graph range
	end
	state =0
	xMax = xMaxInit				-- set X-axis max value (sec)
	xSpeed = gWidth/xMax		-- set X-axis speed (pixels/second)
	xScale = 10					-- set X-axis marker interval (s)
	yMax = yMaxInit				-- set Y-axis max value (m)
	yScale = 10					-- set Y-axis marker interval (sec)
	lnchAlt = 0					-- reset flight launch altitude
	maxAlt = 0					-- reset flight max altitude
	fltTime = 0					-- reset flight duration
	index = 1					-- set initial array position

end

-- ---------------------------
-- custom function to propperly disply timers
-- ---------------------------
	local function SecondsToClock (seconds)
		local seconds = tonumber(seconds)
		if seconds <= 0 then
			return "00:00"
		else
			mins = string.format ("%02.f", math.floor (seconds/60))
			secs = string.format ("%02.f", math.floor (seconds -  mins *60))
		return mins..":"..secs
		end
	end


function maincode (context)				-- this function will run until it is stopped
	swF = getValue (SF_id)				-- get value of switch F (Tx launch mode)
	alt_id = getValue (context.options.Altitude)
		if(alt_id == nil) then
			return 0
		end	
	nowAlt = alt_id						-- get current altitude from Altitude sensor (m)

--  ----------------------------------
--	State 0 = Init
--	State 1 = Ready
--	State 2 = launch climb
--	State 3 = gliding
--	State -1 = Stopped
--  ----------------------------------
	if state == 0 and swF > 0 then					-- if SF was moved to launch mode from "init/stop" state
		init (context)								-- reset graph data & scale
		state = 1									-- change state to "ready"
	elseif state == 1 and swF < 0 then				-- if launch mode is ended without a flight
		state = 0									-- change state to "stop"
	elseif state == 1 and nowAlt > floorAlt then	-- if launch detected in "ready" state
		startTime = getTime () /100					-- set flight start time (seconds)
		alts[1] = nowAlt							-- set first altitude point
		index = 2									-- set index for 2nd alt point
		state = 2									-- change state to "launch climb"
		lnchnr = lnchnr + 1							-- increment the launch number
	elseif state == 2 and nowAlt < maxAlt then		-- if in "launch climb" and altitude decreases
		lnchAlt = maxAlt							-- set launch altitude
		state = 3									-- set state = "gliding"
	elseif state > 1 and nowAlt < floorAlt then		-- if "in flight" and altitude drops below X
	-- =======
	-- Displaying history
	-- =======
		history[lnchnr]={}							-- declare history table as a "struct"(?)
		history[lnchnr]["maxAlt"] = maxAlt			-- fill the current maxAlt in the row corresponding with the flight number
		history[lnchnr]["lnchAlt"] = lnchAlt		-- fill the current Launch alt. in the row corresponding with the flight number
		history[lnchnr]["fltTime"] = fltTime		-- fill the current flight time in the row corresponding with the flight number
	
	-- =============================
	-- put record values in table
	-- =============================
		if maxAlt>recordValues["maxAlt"] then
			recordValues["maxAlt"]=maxAlt
		end
		if lnchAlt>recordValues["lnchAlt"] then
			recordValues["lnchAlt"]=lnchAlt
		end
		if fltTime>recordValues["fltTime"] then
			recordValues["fltTime"]=fltTime
		end


		state = -1									-- change state to "stop" but keep graph on screen
	elseif state == -1 and swF > 0	then							-- motivate script to initialise, clear graph and go to state 0
			state = 0	
	end

--  ----------------------------------------------------
--	  if the graph maximum Y is reached, re-scale in Y
--  ----------------------------------------------------
	if state > 1 and nowAlt > yMax then		--  if "in flight" and altitude reaches top of graph
		yMax = yMax+5						-- add 5 m to top of graph

-- check the scale marker count, and adjust if needed
		yScale = 10							-- start with marker interval = 10 m
		while yMax/yScale > 6 do			-- as long as there would be more than 6 of them
			yScale = yScale*2				-- double the marker interval
		end
	end

--  ----------------------------------------------------
--	  if the graph maximum X is reached, re-scale in X
--  ----------------------------------------------------
	if state > 1 and index > gWidth  then								-- if graph is full,
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
		xScale = 12														-- start with marker interval = 12 seconds
		while xMax/xScale > 7 do										-- as long as there would be more than 7 of them
			xScale = xScale+10											-- increase the marker interval by 10 seconds
		end
	end
--  ---------------------------
--	  graph the Altitude data
--  ---------------------------
	nowTime = getTime ()/100								-- get current time (seconds since radio started)

	if state > 1 and nowTime > (startTime+index/xSpeed) then 		-- if "in flight" AND enough time has elapsed,
		alts[index] = nowAlt										-- add current altitude to array
		index = index+1												-- increment the index
	end
end


function draw (context)
--  -----------------------------------
--	  draw the static graph elements
--  -----------------------------------
	lcd.setColor (CUSTOM_COLOR, context.options.Shadow)
	lcd.drawFilledRectangle (gLeft+1,menuBar+1,gWidth-1,gHeight-1, CUSTOM_COLOR)
	lcd.drawRectangle (gLeft,menuBar,gWidth,gHeight,SOLID)						-- graph perimeter

	for i = yScale, yMax, yScale do												-- create Y-axis scale (For i goes from 10 to 40 with steps of 10)
		y = menuBar+(gHeight*(i-yMax)/(0-yMax))									-- calculate y coordinates
		if y-3 > 2 then															-- if number will fit on screen
			lcd.drawNumber (gLeft-18,y-8,i,SMLSIZE)								-- draw graph scale number
		end		
		if y > 2 then															-- if horizonal line is below top of graph
			lcd.drawLine (gLeft+1,y,gRight,y,DOTTED,GREY)						-- draw horizontal line
		end
	end

	for i = xScale*xSpeed, gWidth, xScale*xSpeed do								-- create X-axis scale lines
		lcd.drawLine (gLeft+i,menuBar,gLeft+i,(gHeight+menuBar),DOTTED,GREY)	-- vert lines
	end
--  ---------------------------
--	draw graph data
--  ---------------------------
	
	lcd.setColor (CUSTOM_COLOR,RED)
	
--	previous_xPos = gLeft
	previous_yPos = menuBar+gHeight
	
	for i = 1, gWidth,1 do
--		xPos = gLeft+i
--		yPos = menuBar+(gHeight*(alts[i]-yMax)/(0-yMax))						-- calculate Y coordinate for graph point
		
		y = menuBar+(gHeight*(alts[i]-yMax)/(0-yMax))					-- calculate Y coordinate for graph point
				
		if y < (gHeight+menuBar-1) then										-- don't draw if below graph, because grey point overwrites bottom line.
			lcd.drawLine (gLeft+i-1,previous_yPos,gLeft+i,y,SOLID,CUSTOM_COLOR)		-- draw 3 pixel point for altitude
--			lcd.drawLine (previous_xPos,previous_yPos,xPos,yPos,SOLID,CUSTOM_COLOR)		-- draw point for altitude			
			previous_yPos = y
		end
--		previous_xPos = xPos
--		previous_yPos = yPos
	end
--  --------------------------------
--	  calculate and display values
--  --------------------------------
	a1 = getValue (context.options.RxBat)
		if(a1 == nil) then
			return 0
		end																	-- get voltage from the Tx

	timer1 = getValue (context.options.Timer)								-- get timer1 value from the Tx (sec)
	if state > 1 then														-- if in a flight state
		fltTime = nowTime-startTime						-- calculate the flight duration (min:sec)
		maxAlt = math.max (nowAlt,maxAlt)									-- update maximum altitude
	end

	if state == 2 then														-- if state is "launch climb"
		lnchAlt = nowAlt													-- update launch altitude with current alt
	end

	lcd.drawNumber (gRight-70, menuBar, nowAlt*10, SMLSIZE+INVERS+PREC1)	--show curent altitude in graphed area
	lcd.drawText  (gRight-30, menuBar, " m" , SMLSIZE+INVERS)

	lcd.drawText  (gRight+5,  menuBar,"Launch#: ", SMLSIZE+INVERS)			--show launch nr
	lcd.drawNumber (gRight+75,  menuBar, lnchnr, SMLSIZE+INVERS)
--
	lcd.drawText (gRight+5, menuBar+rowHeight, "Launch\194", SMLSIZE)				-- Launch height. diagonal up-right arrow
	lcd.drawNumber (gRight+75, menuBar+rowHeight, lnchAlt, SMLSIZE)	
	lcd.drawText (gRight+95, menuBar+rowHeight, "m", SMLSIZE)
--

	lcd.drawText  (gRight+5, menuBar+2*rowHeight,"Max Alt\192:", SMLSIZE)			-- placeholder for MaxAlt. up arrow, or use char "^" for max alt
	lcd.drawText  (gRight+95, menuBar+2*rowHeight,"m", SMLSIZE)	

	if maxAlt>lnchAlt then													-- show max alt if > launch alt
		lcd.drawNumber (gRight+75, menuBar+2*rowHeight, maxAlt, SMLSIZE)
	end
						--
	lcd.drawText (gRight+5, menuBar+3*rowHeight, "Time:", SMLSIZE)					-- Flighttime of this launch
	lcd.drawText (gRight+70, menuBar+3*rowHeight,SecondsToClock (fltTime), SMLSIZE)

	lcd.drawLine  (gRight+3,menuBar+4*rowHeight,440,menuBar+4*rowHeight ,SOLID,1)				-- line below current flight values

--
	if lnchnr > 1 then
		lcd.drawText (gRight+5,menuBar+4*rowHeight, "last flight #"..lnchnr-1 ,SMLSIZE+INVERS)		-- Show flight history

		lcd.drawText ( gRight+5,menuBar+5*rowHeight, "Launch\194:",SMLSIZE)	
		lcd.drawNumber ( gRight+80,menuBar+5*rowHeight, history[lnchnr-1]["lnchAlt"], SMLSIZE)
		lcd.drawText (gRight+100, menuBar+5*rowHeight, "m", SMLSIZE)
				
		lcd.drawText ( gRight+5,menuBar+6*rowHeight, "Max\192:",SMLSIZE)
		lcd.drawNumber ( gRight+80,menuBar+6*rowHeight, history[lnchnr-1]["maxAlt"], SMLSIZE)
		lcd.drawText (gRight+100, menuBar+6*rowHeight, "m", SMLSIZE)
	
		lcd.drawText ( gRight+5,menuBar+7*rowHeight, "Time:",SMLSIZE)
		lcd.drawText ( gRight+75,menuBar+7*rowHeight, SecondsToClock (history[lnchnr-1]["fltTime"]), SMLSIZE)
	end
	lcd.drawLine  (gRight+3,menuBar+8*rowHeight-2,440,menuBar+8*rowHeight-2,SOLID,1)				-- line below last flight values

	lcd.drawText ( gRight+5,menuBar+8*rowHeight, "Max Values",SMLSIZE+INVERS)							-- Show max values
	lcd.drawText ( gRight+5,menuBar+9*rowHeight, "\194",SMLSIZE+INVERS)									-- Show max values
	lcd.drawText ( gRight+40,menuBar+9*rowHeight, "\192",SMLSIZE+INVERS)								-- Show max values
	lcd.drawText ( gRight+75,menuBar+9*rowHeight, "Time",SMLSIZE+INVERS)								-- Show max values

	lcd.drawNumber ( gRight+3,menuBar+10*rowHeight, tonumber (recordValues["lnchAlt"]),SMLSIZE)			-- Show max values
	lcd.drawText ( gRight+21,menuBar+10*rowHeight, "m",SMLSIZE)											-- Show max values
	lcd.drawNumber ( gRight+40,menuBar+10*rowHeight, tonumber (recordValues["maxAlt"]),SMLSIZE)			-- Show max values
	lcd.drawText ( gRight+58,menuBar+10*rowHeight, "m",SMLSIZE)											-- Show max values
	lcd.drawText ( gRight+75,menuBar+10*rowHeight, SecondsToClock (recordValues["fltTime"]),SMLSIZE)	-- Show max values


	lcd.drawText (gLeft+5,menuBar+10*rowHeight, "Phase: " ,SMLSIZE+INVERS)		--Show the various "states" of flight to aid in debugging 
	stateTxt = {"Stopped","Initialised","Ready","Launch!","Gliding"}
	lcd.drawText (gLeft+55,menuBar+10*rowHeight, stateTxt[state+2] ,SMLSIZE+INVERS)
end

return { name="F3K", options=options, create=create, update=update, refresh=refresh, background=background }
