
--!strict

-- Info
--------------------------------------------------------------

--[[
	@module TickService
	@file [
		A service for ticking. Similar to RunService, but offers
		more contorl.
	]
	@author Tydoth
]]

--[[
	@TODO:
	a lot
]]

-- Tyoes
--------------------------------------------------------------

type TickerProps = {
	interval : number
}

type TickerInstance = {
	identifier : string,
	interval  : number,
	current_tick : number,
	threads_awaiting : {thread},
	functions_linked : {[string]: (current_tick : number) -> (... any)}
}

-- Variables
--------------------------------------------------------------

local ticker_instances: {[string]: TickerInstance} = {}

-- Private
--------------------------------------------------------------

--[[
	Internal function to help determine if a Ticker exits or not.
	
	@private
	@param {string} identifier - The identifier of the Ticker to check.
	@reutnrs {boolean}
]]
local function tickerExists
(
	identifier : string
): (boolean)
	
	return (ticker_instances[identifier] ~= nil and true or false)
end

--[[
	Resumes halted threads.
	
	@private
	@param {string} identifier - The identifier of the Ticker to resume threads for.
	@param {number} current_tick - The current tick.
	@return {void}
]]
local function continueHaltedThreads
(
	identifier : string,
	current_tick : number
): ()
	
	if (#ticker_instances[identifier].threads_awaiting == 0) then
		return
	end
	
	local threads_to_resume = ticker_instances[identifier].threads_awaiting
	ticker_instances[identifier].threads_awaiting = {}
	for _, thread in threads_to_resume do
		coroutine.resume(thread, current_tick)
	end
end

--[[
	Waits for a single tick to pass.
	
	@private
	@param {string} identifier - The identifier of the Ticker to wait for.
	@return {number} - The current tick.
]]
local function awaitTick
(
	identifier : string
): (number)
	
	table.insert(ticker_instances[identifier].threads_awaiting, coroutine.running())
	return coroutine.yield()
end

--[[
	Begins tick cycle for a Ticker.
	
	@private
	@param {string} identifier - The identifier of the Ticker to begin.
	@return {void}
]]
local function tickerInit
(
	identifier : string	
): ()
		
	while (tickerExists(identifier)) do --TODO: optimize this?
		task.wait(ticker_instances[identifier].interval)
		ticker_instances[identifier].current_tick += 1
		continueHaltedThreads(identifier, ticker_instances[identifier].current_tick)
	end
end

-- Public
--------------------------------------------------------------

--[[
	Utility function used to convert seconds to ticks.
	
	@public
	@param {string} ticker_name - The name of the Ticker to convert to ticks.
	@param {number} seconds - The amount of seconds to convert to ticks.
	@return {number} - The amount of ticks.
]]
local function convertSecondsToTicks
(
	ticker_name : string,
	seconds     : number
): (number)
	
	if (not tickerExists(ticker_name)) then
		return 1
	end
	
	local interval = ticker_instances[ticker_name].interval
	local ticks = math.floor(seconds / interval)
	
	return ticks
end

--

--[[
	Yields current thread until a certain amount of ticks pass.
	
	@public
	@param {string} ticker_name - The name of the Ticker to wait for.
	@param {number} amount_to_wait - The amount of ticks to wait for.
	@return {void}
]]
local function awaitTicks
(
	ticker_name : string,
	amount_to_wait : number?
): ()
	
	if (not tickerExists(ticker_name)) then
		return
	end
	
	for _ = 1, (amount_to_wait or 1) do
		awaitTick(ticker_name)
	end
end

--[[
	A more convenient method that combines both `convertSecondsToTicks` and `awaitTicks`.
	
	@public
	@param {string} ticker_name - The name of the Ticker to wait for.
	@param {number} seconds - The amount of seconds to wait for.
	@return {void}
]]
local function awaitInSeconds
(
	ticker_name : string,
	seconds : number	
): ()
	
	local converted = convertSecondsToTicks(ticker_name, seconds or 1)
	awaitTicks(ticker_name, converted)
end

--[[
	Creates a new Ticker instance.
	
	@public
	@param {string} identifier - The name of the Ticker instance.
	@param {TickerProps} properties - The properties of the Ticker instance.
	@return {void}
]]
local function newTicker
(
	identifier : string,
	properties: TickerProps
): ()
		
	ticker_instances[identifier] = {
		identifier = identifier,
		interval = properties.interval or 0.1,
		current_tick = 1, -- to follow with Lua's conventions
		threads_awaiting = {},
		functions_linked = {}
	}
	task.spawn(tickerInit, identifier)
end

return table.freeze(
	{
		newTicker = newTicker,
		awaitTicks = awaitTicks,
		awaitInSeconds = awaitInSeconds,
		convertSecondsToTicks = convertSecondsToTicks
	}
)
