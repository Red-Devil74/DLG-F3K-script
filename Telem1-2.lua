--[[

  ============================
  ===  D L G    T R A C E  ===
  ============================

rev 2.1   06/15/2015
	J.W.G.  (filago on RCGroups)

rev 2.2 10/09/2016
	A.A. Costerus


  LUA Script for OpenTX to graph altitude vs time with DLG launch.
  X-axis will automatically re-scale by +33% seconds if the max is reached.
  Y-axis will automatically re-scale by +5 m if the max is reached.


  The graph code is leveraged from an openTX script.
  There are no other files required (such as BMP images) to run this script.
  Put file in SCRIPTS/TELEMETRY and rename telem1.lua, telem2.lua, etc, up to 7.

--]]



--  ================================
--	  variables for user to adjust
--  ================================

local yMaxInit = 40				-- initial max altitude on graph (m)
local xMaxInit = 30				-- initial max time on graph (seconds)
local floorAlt = 2				-- altitude threshold for starting and stopping the flight (m)


--  -----------------------------
--	  the rest of the variables
--  -----------------------------

local alt_id = getFieldInfo("Alt").id	-- get field index # for telemetry Altitude
local SF_id  = getFieldInfo("sf").id		-- get field index # for switch F (Tx launch mode)
local thr_id = getFieldInfo("thr").id		-- get field index # for throttle stick
local a1_id  = getFieldInfo("RxBt").id		-- get field index # for voltage
local t1_id  = getFieldInfo("timer1").id	-- get field index # for timer 1 (seconds)
local gLeft     = 15			-- starting column of graph
local gWidth    = 138			-- width of graph data area, and array size
local gRight    = gLeft+gWidth		-- ending column of graph
local state     = 0			-- program state : 0=init/stop, 1=ready, 2=launch climb, 3=gliding
local alts      = {}			-- array definition for graphed altitude values
local startTime = 0				-- time at start of flight
local fltTime					-- duration of each flight
local nowTime					-- current time
local lnchAlt					-- top of launch
local maxAlt					-- maximum altitude during flight
local nowAlt					-- current altitude
local swF						-- switch F value from Tx (<0 is UP for launch mode)
local lnchnr = 0 				-- launch counter
local a1						-- voltage from Tx
local timer1					-- timer 1 from Tx (sec > min)
local index						-- array index position
local xMax						-- X-axis max value (sec)
local xScale					-- X-axis marker interval (m)
local xSpeed					-- X-axis speed (pixels/second)
local y							-- temp use for calculating Y coordinate
local yMax						-- Y-axis max value (m)
local yScale					-- Y-axis marker interval (sec)


--  ==============
--	  initialize
--  ==============

local function init()			-- intialize values
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


--  =======
--	  run
--  =======

local function run(event)				-- this function will run until it is stopped
	lcd.clear ()					-- clear the display

	swF = getValue(SF_id)				-- (disabled) get value of switch F (Tx launch mode)
	nowAlt = getValue(alt_id)			-- get current altitude from vario (m)


--  ----------------------------------
--	  change program if needed
--  ----------------------------------

	if state == 0 and swF > 0 then					-- if SF was moved to launch mode from "init/stop" state
		init()							-- reset graph data & scale
		state = 1						-- change state to "ready"
	elseif state == 1 and swF < 0 then				-- if launch mode is ended without a flight
		state = 0						-- change state to "stop"
	elseif state == 1 and nowAlt > floorAlt then			-- if launch detected in "ready" state
		startTime = getTime()/100				-- set flight start time (seconds)
		alts[1] = nowAlt					-- set first altitude point
		index = 2						-- set index for 2nd alt point
		state = 2						-- change state to "launch climb"
		lnchnr = lnchnr + 1					-- increment the launch number
	elseif state == 2 and nowAlt < maxAlt then			-- if in "launch climb" and altitude decreases
		lnchAlt = maxAlt					-- set launch altitude
		state = 3						-- set state = "gliding"
	elseif state > 1 and nowAlt < floorAlt then			-- if "in flight" and altitude drops below X
		state = 0						-- change state to "stop"

	end


--  ----------------------------------------------------
--	  if the graph maximum Y is reached, re-scale in Y
--  ----------------------------------------------------

	if state > 1 and nowAlt > yMax then	--  if "in flight" and altitude reaches top of graph
		yMax = yMax+10							-- add 5 m to top of graph

		-- check the scale marker count, and adjust if needed
		yScale = 10								-- start with marker interval = 10 m
		while yMax/yScale > 6 do				-- as long as there would be more than 6 of them
			yScale = yScale*2						-- double the marker interval
		end
	end


--  -----------------------------------
--	  draw the static graph elements
--  -----------------------------------

	lcd.drawRectangle(gLeft,0,gWidth+2,64)			-- graph perimeter

	for i = yScale, yMax, yScale do					-- create Y-axis scale
		y = 64*(i-yMax)/(0-yMax)						-- calculate y coordinates
		if y-3 > 2 then								-- if number will fit on screen
			lcd.drawNumber(15,y-3,i,SMLSIZE)				-- draw graph scale number
		end
		if y > 2 then								-- if horizonal line is below top of graph
			lcd.drawLine(gLeft+1,y,gRight,y,SOLID,GREY_DEFAULT)		-- draw horizontal line
		end
	end

	for i = xScale*xSpeed, gWidth, xScale*xSpeed do		-- create X-axis scale lines
		lcd.drawLine(gLeft+i+1,1,gLeft+i+1,62,SOLID,GREY_DEFAULT)	-- vert lines
	end


--  ---------------------------
--	  graph the Altitude data
--  ---------------------------

	nowTime = getTime()/100							-- get current time (seconds since radio started)

	if state>1 and nowTime>(startTime+index/xSpeed) then 			-- if "in flight" AND enough time has elapsed,
		alts[index] = nowAlt						-- add current altitude to array
		index = index+1							-- increment the index
	end

--	draw graph data
	for i = 1, gWidth do
		y = 64*(alts[i]-yMax)/(0-yMax)				-- calculate Y coordinate for graph point
		if y < 63 then								-- don't draw if below graph, because grey point overwrites bottom line.
			lcd.drawLine(gLeft+i,y  ,gLeft+i,62 ,SOLID,GREY_DEFAULT)	--  draw grey line down from altitude
			lcd.drawLine(gLeft+i,y+1,gLeft+i,y,SOLID,0)				-- draw 2 pixel point for altitude
		end
	end


--  ----------------------------------------------------
--	  if the graph maximum X is reached, re-scale in X
--  ----------------------------------------------------

	if index > gWidth  then		-- if graph is full,

		local j = 1						-- temporary index number for compacted array
		for i = 1, gWidth do			-- compact the array, skipping every 4th point
			if i % 4 ~= 0 then				-- if not every 4th point
				alts[j] = alts[i]				-- copy to compacted array
				j = j+1							-- increment j
			end
		end

		for i= j, gWidth do				-- reset the "empty" data at the end so it doesn't plot
			alts[i] = -10
		end

		index = j						-- set index to first "empty" location
		xMax = xMax * 4/3				-- new graph max time (sec)
		xSpeed = gWidth/xMax			-- new graph speed (pixels/sec)

		-- check the scale marker count, and adjust if needed
		xScale = 10						-- start with marker interval = 10 seconds
		while xMax/xScale > 7 do		-- as long as there would be more than 7 of them
			xScale = xScale+10				-- increase the marker interval by 10 seconds
		end
	end


--  --------------------------------
--	  calculate and display values
--  --------------------------------

	a1 = getValue(a1_id)				-- get voltage from the Tx
	timer1 = getValue(t1_id)/60			-- get timer1 value from the Tx (sec > min)

	if state > 1 then					-- if in a flight state
		fltTime = nowTime-startTime			-- calculate the flight duration (sec)
		maxAlt = math.max (nowAlt,maxAlt)	-- update maximum altitude
	end

	if state == 2 then					-- if state is "launch climb"
		lnchAlt = nowAlt					-- update launch altitude with current alt
	end

	lcd.drawText  (162,  5,"LAUNCH   ", SMLSIZE+INVERS)
	lcd.drawNumber(205,  5, lnchnr       , SMLSIZE+INVERS)
	lcd.drawNumber(175, 16, lnchAlt   , SMLSIZE)
	lcd.drawText  (177, 16,"m\194"    , SMLSIZE)		-- diagonal up-right arrow
	lcd.drawNumber(200, 16, fltTime   , SMLSIZE)
	lcd.drawText  (201, 16,"s"        , SMLSIZE)

	if maxAlt>lnchAlt then								-- show max alt if > launch alt
		lcd.drawNumber(187, 26, maxAlt, SMLSIZE)
		lcd.drawText  (188, 26,"m\192", SMLSIZE)		-- up arrow, or use char "^" for max alt
	end

	lcd.drawLine  (gRight+6,37,207,37 , SOLID,0)		-- line below current flight values
	lcd.drawNumber(188,     42, a1*100, SMLSIZE+PREC2)	-- battery voltage
	lcd.drawText  (191,     42,"V"    , SMLSIZE)
	lcd.drawNumber(179,     53, timer1, SMLSIZE)
	lcd.drawText  (182,     53,"min"  , SMLSIZE)

	lcd.drawNumber(gRight-12, 2, nowAlt*10, SMLSIZE+INVERS+PREC1	)
	lcd.drawText  (gRight-12, 2, " m" , SMLSIZE+INVERS)

--	if demo == 1 then										-- if in demo mode
--		lcd.drawText(gRight-20,10,"DEMO",SMLSIZE+INVERS+BLINK)	-- display this
--	end

end


return { init=init, run=run }
