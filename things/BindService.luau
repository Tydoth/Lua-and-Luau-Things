
--!strict
--!optimize 2

-- Info
--------------------------------------------------------------

--[[
	@module BindService
	@file [
		BindService is a module for event handling.
		Unlike other modules, it uses pure table magic, so no
		metatables or wrapping is happening.
	]
	@summary A event wrapper using tables.
	
	-- does it even need this or am i showing off
	@author Tydoth
]]

--[[
	@TODO:
		* Implement GC'd binds after a long pass (DONE)
		* Implement a way to get binds (DONE)
		* Trigger function that returns every function's return value
		* Developer mode
		* make error/warn messages show where error happened
			instead of throwing vaguely
]]

-- External imports

-- Types
--------------------------------------------------------------

type GarbageCollectorSettings = {
	enabled  : boolean,
	interval : number
}

type GarbageCollectorProps = {
	enabled    : boolean?,
	interval   : number?
}

type LinkProps = {
	happen_once : boolean?
}

type BindObjectProps = {
	can_disband : boolean?,
	link_limit  : number?,
	decay_time  : number? -- automatically gives it to gc list if this arg is provided
}

export type BindSignal = {
	link : (
		func_name : string,
		func      : (
			bind_name : string	
		) -> ()
	) -> (
		{
			unlink : () -> ()
		}
	)
}

export type Link = {
	name : string,
	func : (... any) -> (... any),
	once : boolean
}

export type BindObject = {
	connections : {
		[string] : Link
	},
	threads			: {thread},
	name 				: string,
	can_disband : boolean,
	link_limit  : number,
	link_amount : number,
	decay_time  : number?
}

-- Variables
--------------------------------------------------------------

-- Modify as needed
local CONSTANTS = {
	LINK_LIMIT      = 8, -- useful for preventing memory leaks 
	DEFAULT_ONCE    = false,
	DEFAULT_GC_MODE = false, -- garbage collected,
	DEFAULT_GC_CLEAN_INTERVAL = 2, -- clean gc'd binds after some time,
	DEFAULT_CLEAN_GC_BINDS = true, -- clean gc'd binds if gc gets disabled,
	BUILT_IN_BIND_NAMES = {
		ADDED = "ADDED",
		REMOVED = "REMOVED",
		TRIGGERING = "TRIGGERING"
	}
}

local REASONS = {
	NAME_NOT_PROVIDED  = `[{script}] - Name not provided to find bind.`,
	BIND_NOT_FOUND     = `[{script}] - Bind of name not found!`,
	FUNC_NOT_FOUND     = `[{script}] - Function of name not found!`,
	NO_FUNCS_LINKED    = `[{script}] - Bind doesn't have links!`,
	NOT_DISBANDABLE    = `[{script}] - Bind can't be disbanded!`,
	BIND_EXISTS        = `[{script}] - Bind with name already exists!`,
	LINK_LIMIT_REACHED = `[{script}] - Bind's link limit reached!`,
	GC_BIND_NOT_FOUND  = `[{script} Internal] - Garbage Collected Bind not found.`,
	GC_INFO_NOT_GIVEN  = `[{script}] - Garbage Collector settings not provided.` ,
	GC_TOGGLE_IS_NIL   = `[{script}] - Garbage Collector toggle not provided.`,
	GC_IS_DISABLED     = `[{script}] - Tried to add garbage collected Bind when Garbage Collector is disabled.`,
	IS_BUILTIN_BIND    = `[{script}] - Tried to override built in bind.`
}

local garbage_collector_settings : GarbageCollectorSettings = {
	enabled 			 = CONSTANTS.DEFAULT_GC_MODE,
	interval			 = CONSTANTS.DEFAULT_GC_CLEAN_INTERVAL
}

local service_running : boolean = false
local binds : {[string]: BindObject} = {}
local garbage_collected_binds : {
	[string]: {
		name    : string,
		gc_time : number
	}
} = {}

-- Private Functions
--------------------------------------------------------------

--[[
	Internal function that finds bind via name and returns bind info.
	
	@private
	@param {string} bind_name - Name of bind to find.
	@returns {BindObject?} - Bind if found, else nil.
]]
local function findBindByName
(
	bind_name : string	
): (BindObject)?

	if (not bind_name) then
		warn(REASONS.NAME_NOT_PROVIDED)
		return nil
	end
	local found_bind = binds[bind_name]
	if (not found_bind) then
		return nil
	end

	return found_bind
end

--[[
	Internal function that returns if a link exists or not.
	
	@private
	@param {BindObject} bind - Bind to check.
	@param {string} func_name - Name of function to check.
	@returns {boolean} If it exists or not.
]]
local function linkExists
(
	bind      : BindObject,
	func_name : string
): (boolean)

	local found = bind.connections[func_name]
	if (not found) then
		warn(REASONS.FUNC_NOT_FOUND)
		return false
	end

	return true
end

--[[
	Internal function that fires a function.
	
	@private
	@param {string} bind_name - Name of bind to trigger.
	@param {string} func_name - Name of function to trigger.
	@param {...} Arguments to pass to the triggered function.
	@returns {void}
]]
local function triggerFunc
(
	bind_name : string,
	link      : Link,
	...       : any
): ()

	local func = link.func
	if (not func) then
		return
	end	
	local success, message = pcall(func, ...)
	if (link.once) then
		binds[bind_name].connections[link.name] = nil
		binds[bind_name].link_amount -= 1
	end
	if (success) then
		return
	end
	warn(`Error of "{message}" encountered while triggering bind.`)
end

--[[
	Continues waiting threads.
	
	@private
	@param {string} bind_name - Name of bind to continue threads of.
	@param {...} Arguments to pass to the triggered functions.
	@returns {void}
]]
local function continueHaltedThreads
(
	bind_name : string ,
	...       : any
): ()

	if (#binds[bind_name].threads == 0) then
		return
	end

	for _, thread in binds[bind_name].threads do
		coroutine.resume(thread, ...)
	end
	binds[bind_name].threads = {}
end

--[[
	Creates and initializes built in binds.
	
	@private
	@returns {void}
]]
local function createBuiltInBinds(): ()
	for _, bind in CONSTANTS.BUILT_IN_BIND_NAMES do -- there's nothing wrong with this??
		local created : BindObject = {
			name = bind,
			link_limit = 64, -- i highly doubt it'll reach thtis
			threads = {},
			link_amount = 0,
			can_disband = false,
			connections = {}
		}
		binds[bind] = created
	end

end

--[[
	Similar to Trigger method, but reserved for built in Binds.
	
	@private
	@param {string} bind_name = The bind's name.
	@returns {void}
]]
local function triggerBuiltInBind
(
	name : string	,
	... : any
): ()

	for _, link in binds[name].connections do
		triggerFunc(name, link, ...)
	end
end

--[[
	Cleans every garbage collected bind
	
	@private
	@returns {void}
]]
local function cleanGarbageCollectedBinds(): ()
	if (not CONSTANTS.DEFAULT_CLEAN_GC_BINDS) then
		return
	end
	garbage_collected_binds = {}
end

--[[
	Cleans up garbage collected bind when it is time for it to go
	
	@private
	@returns {void}
]]
local function destroyGarbageCollectedBind
(
	bind_name: string
): ()
	local found_correlating_bind = findBindByName(bind_name)
	if (not found_correlating_bind) then
		warn(REASONS.GC_BIND_NOT_FOUND)
		return
	end
	binds[bind_name] = nil
end

--[[
	Updates garbage collected binds' decay time
	
	@private
	@returns {void}
]]
local function updateGarbageCollectedBinds(): ()
	local binds = garbage_collected_binds
	for _, bind in binds do
		bind.gc_time -= garbage_collector_settings.interval
		if (bind.gc_time <= 0) then
			garbage_collected_binds[bind.name] = nil
			destroyGarbageCollectedBind(bind.name)
		end
	end
end

--[[
	Garbage collection loop
	
	@private
	@returns {void}
]]
local function serviceLoop(): ()
	while (true) do
		task.wait(CONSTANTS.DEFAULT_GC_CLEAN_INTERVAL)
		if (not garbage_collector_settings.enabled) then
			cleanGarbageCollectedBinds()
			service_running = false
			return
		end
		if (not next(garbage_collected_binds)) then
			continue
		end
		task.defer(updateGarbageCollectedBinds)
	end
end

--[[
	Begins service, nothing else.
	
	@private
	@returns {void}
]]
local function serviceInit(): ()
	if (service_running) then
		return
	end
	createBuiltInBinds()
	service_running = true
	task.spawn(serviceLoop)
end

-- Public Utility Functions
--------------------------------------------------------------

--[[
	Returns constants.
	
	@public
	@returns {*} The constants.
]]
local function getConstants()
	return CONSTANTS
end

--[[
	Returns every bind's name.
	
	@public
	@returns {[string]: string} An array of bind names.
]]
local function getAllBindNames(): ({[string]: string})
	if (not next(binds)) then
		return {}
	end

	local names = {}
	for name in binds do
		names[name] = name
	end
	return names
end

--[[
	Gets bind by name.
	
	@public
	@param {string} bind_name - The name of the bind.
	@returns {BindObject?} The bind object if found, else nil.
]]
local function getBind
(
	bind_name : string  
): (BindObject?)

	local found_bind = findBindByName(bind_name)
	if (found_bind) then
		return found_bind
	end
	return nil
end

--[[
	Returns all active binds.
	
	@public
	@returns {[string]: BindObject} A dictionary of binds.
]]
local function getAllBinds(): ({
	[string] : BindObject
	})

	return binds
end

-- Public Garbage Collector Functions
--------------------------------------------------------------

--[[
	Determines if a bind is garbage collected.
	
	@public
	@param {string} bind_name - The name of the bind.
	@returns {boolean}
]]
local function isBindGCed
(
	bind_name : string	
): (boolean)

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return false
	end

	local in_garbage_collector = garbage_collected_binds[bind_name]
	if (in_garbage_collector) then
		return true
	end
	return false
end

--[[
	Returns all binds that are to be garbage collected.
	
	@public
	@returns {[string]: string} - A list of bind names.
]]
local function getGarbageCollectedBindNames(): ({[string]: string})
	if (not next(garbage_collected_binds)) then
		return {}
	end

	local names = {}
	for name in garbage_collected_binds do
		names[name] = name
	end
	return names
end

--[[
	Get the Garbage Collector's settings.
	
	@public
	@returns {GarbageCollectorSettings} The current settings.
]]
local function getGarbageCollectorSettings(): (GarbageCollectorSettings)
	return garbage_collector_settings
end

--[[
	Decides whether the Garbage Collector will run or not.
	
	@public
	@param {boolean} enabled - Whether or not the Garbage Collector runs.
	@returns {void}
]]
local function toggleGarbageCollector
(
	enabled : boolean
): ()

	assert(
		(enabled ~= nil),
		REASONS.GC_TOGGLE_IS_NIL
	)
	garbage_collector_settings.enabled = enabled

	if (enabled) then -- what is this bro
		if (service_running) then
			return
		end
		task.spawn(serviceInit)
	end
end

--[[
	Adjust the Garbage Collector's settings.
	
	@public
	@param {GarbageCollectorSettings} props - the new settings.
	@returns {void}
]]
local function modifyGarbageCollectorSettings
(
	props : {interval : number?}
): ()

	assert(
		props,
		REASONS.GC_INFO_NOT_GIVEN
	)

	local interval : number  = (props.interval or garbage_collector_settings.interval or 1)
	garbage_collector_settings.interval = interval
end

-- Public Functions
--------------------------------------------------------------

--[[
	Unlinks a function to a bind.
	Note: Prone to memory leak if function isn't cleaned on script using it.
	
	@public
	@param {string} bind_name - the bind's name.
	@param {string} func_name - the function's identifier.
	@returns {void}
]]
local function unlinkFunction
(
	bind_name : string,
	func_name : string
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end

	local func_exists = linkExists(bind, func_name)
	if (not func_exists) then
		return
	end
	bind.link_amount -= 1
	bind.connections[func_name] = nil
end

--[[
	Links a function to a bind.
	
	@public
	@param {string} bind_name - the bind's name.
	@param {string} func_name - the function's identifier.
	@param {function} func - the function.
	@param {LinkProps} props - the link's properties.
	@returns {void}
]]
local function linkFunction
(
	bind_name : string,
	func_name : string,
	func		  : (... any) -> (... any),
	props     : LinkProps?
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (bind.link_amount >= bind.link_limit) then
		warn(REASONS.LINK_LIMIT_REACHED)
		return
	end
	local newProps : LinkProps = (props or {})

	bind.link_amount += 1
	bind.connections[func_name] = {
		name = func_name,
		func = func,
		once = (newProps.happen_once or CONSTANTS.DEFAULT_ONCE)
	}
end

--[[
	Halts thread execution until a given bind is triggered.
	
	@public
	@param {string} bind_name - the bind's name.
	@returns {...} the arguments passed by the bind.
]]
local function awaitTrigger
(
	bind_name : string
): (... any)

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	table.insert(binds[bind_name].threads, coroutine.running())

	return coroutine.yield()
end

--[[
	Similar to `trigger` method, but waits until the end of current cycle.
	Useful for triggering binds with lots of links.

	@public
	@param {string} bind_name - the bind's name.
	@param {...} The arguments to pass to the functions.
	@returns {void}
]]
local function triggerDeferred
(
	bind_name : string,
	... 			: any
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return
	end
	continueHaltedThreads(bind_name, ...)

	if (bind.link_amount == 0) then
		warn(REASONS.NO_FUNCS_LINKED)
		return
	end

	local links = bind.connections
	for _, link in links do
		task.defer(
			triggerFunc,
			bind.name,
			link,
			...
		)
	end
end

--[[
	Similar to `trigger` method, but runs without error handling.
	Useful if you want maximum performance.
	
	@public
	@param {string} bind_name - the bind's name.
	@param {...} The arguments to pass to the functions.
	@returns {void}
]]
local function triggerUnreliable
(
	bind_name : string,
	...       : any  
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return
	end
	continueHaltedThreads(bind_name, ...)

	if (bind.link_amount == 0) then
		warn(REASONS.NO_FUNCS_LINKED)
		return
	end

	local links = bind.connections
	for _, link in links do
		task.spawn(link.func, ...)
	end
end

--[[
	Triggers a bind, executing every function connected and resuming threads.
	
	@public
	@param {string} bind_name - The bind's name.
	@param {...} The arguments to pass to the functions.
	@returns {void}
]]
local function trigger
(
	bind_name : string,
	...			  : any
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return
	end
	continueHaltedThreads(bind_name, ...)

	if (bind.link_amount == 0) then
		warn(REASONS.NO_FUNCS_LINKED)
		return
	end
	
	triggerBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.TRIGGERING, bind_name)
	local links = bind.connections
	for _, link in links do
		triggerFunc(
			bind.name, link, ...
		)
	end
end

--[[
	Resumes threads waiting for the bind.
	
	@public
	@param {string} bind_name - The bind's name.
	@returns {void}
]]
local function resumeBind
(
	bind_name : string	
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	continueHaltedThreads(bind_name)
end

--[[
	Cleans up a bind's connections. 
	Doesn't resume threads, use resumeBind method instead.
	
	@public
	@param {string} bind_name - The bind's name.
	@returns {void}
]]
local function cleanBind
(
	bind_name   : string
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end

	bind.connections = {}
end

--[[
	Modifies Bind properties.
	
	@public
	@param {string} bind_name - The bind's name.
	@param {BindObjectProps} bind_props - The properties to modify.
	@returns {void}
]]
local function overrideBind
(
	bind_name   : string,
	bind_props  : BindObjectProps
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return
	end

	bind.link_limit  = (bind_props.link_limit or bind.link_limit)
	bind.can_disband = (bind_props.can_disband or bind.can_disband)
end

--[[
	Completely destroys a bind, as well as cleaning up everything it had.
	
	@public
	@param {string} bind_name - the bind's name.
	@returns {void}
]]
local function disbandBind
(
	bind_name : string
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (not bind.can_disband) then
		warn(REASONS.NOT_DISBANDABLE)
		return
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return
	end
	continueHaltedThreads(bind_name, nil)

	binds[bind_name] = nil
	triggerBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.REMOVED, bind_name)
end

--[[
	Creates a new bind.
	Does not return the bind, you must specify name when using other methods.
	
	@public
	@param {string} bind_name - The bind's name.
	@param {BindObjectProps} bind_props - The properties to modify.
	@returns {void}
]]
local function newBind
(
	bind_name   : string,
	bind_props  : BindObjectProps?
): ()

	local bind_exists : BindObject? = findBindByName(bind_name)
	if (bind_exists) then
		warn(REASONS.BIND_EXISTS)
		return
	end

	local new_props   : BindObjectProps = (bind_props or {})
	local can_disband : boolean = new_props.can_disband or true
	local link_limit  : number  = math.max(
		CONSTANTS.LINK_LIMIT,
		(new_props.link_limit or CONSTANTS.LINK_LIMIT)
	)

	local bind : BindObject = {
		name 				= bind_name,
		can_disband = (can_disband or true),
		link_limit  = link_limit,
		link_amount = 0, 
		connections = {},
		threads = {}
	}
	binds[bind_name] = bind

	if (new_props.decay_time) then
		if (not garbage_collector_settings.enabled) then
			warn(REASONS.GC_IS_DISABLED)
			return
		end
		binds[bind_name].decay_time = new_props.decay_time
		garbage_collected_binds[bind_name] = {
			name = bind_name,
			gc_time = new_props.decay_time
		}
	end

	triggerBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.ADDED, bind_name)
end

-- private again but too

--[[
	Creates built in binds that act similarly to RBXScriptSignals.
	
	@private
	@param {string} name - The name of the bind.
	@returns {void}
]]
local function createBuiltInBindThing
(
	name : string	
): (BindSignal)
	
	return {
		link = function
		(
			func_name : string,
			func : (bind_name : string) -> ()
		): ({unlink : () -> ()})

			linkFunction(name, func_name, func)
			return {
				unlink = function()
					unlinkFunction(name, func_name)
				end
			}
		end,
	}
end

--------------------------------------------------------------

serviceInit()

return table.freeze(
	{
		newBind		   	    = newBind,
		overrideBind      = overrideBind,
		trigger 	  	    = trigger,
		triggerDeferred   = triggerDeferred,
		triggerUnreliable = triggerUnreliable,
		awaitTrigger      = awaitTrigger,
		disbandBind 	    = disbandBind,
		cleanBind   	    = cleanBind,
		linkFunction	    = linkFunction,
		unlinkFunction    = unlinkFunction,
		getBind           = getBind,
		getAllBinds       = getAllBinds,
		getAllBindNames   = getAllBindNames,
		getConstants      = getConstants,
		garbageCollector  = {
			isBindGCed      = isBindGCed,
			modifySettings  = modifyGarbageCollectorSettings,
			getSettings     = getGarbageCollectorSettings,
			getGCedBinds 	  = getGarbageCollectedBindNames,
			toggle 		      = toggleGarbageCollector,
		},
		OnBindAdded		    = createBuiltInBindThing(CONSTANTS.BUILT_IN_BIND_NAMES.ADDED),
		OnBindDisbanding  = createBuiltInBindThing(CONSTANTS.BUILT_IN_BIND_NAMES.REMOVED),
		OnTriggerCall     = createBuiltInBindThing(CONSTANTS.BUILT_IN_BIND_NAMES.TRIGGERING)
	}
)
