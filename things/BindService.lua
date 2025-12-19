
-- Info
--------------------------------------------------------------

--!strict
--!optimize 2
--[[
	A module that doesn't use metatable magic or bindable events, pure table magic.
	You need to unlink manually.
	
	made by Tydoth in like 30 minutes
	it's literally impossible to make server to client communication without remotes
	
	TODO:
	* Implement GC'd binds after a long pass (DONE)
	* Implement a way to get binds (DONE)
	* 
]]

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

local CONSTANTS = {
	LINK_LIMIT      = 8, -- useful for preventing memory leaks 
	DEFAULT_ONCE    = false,
	DEFAULT_GC_MODE = false, -- garbage collected,
	DEFAULT_GC_CLEAN_INTERVAL = 1, -- clean gc'd binds after some time,
	DEFAULT_CLEAN_GC_BINDS = true -- clean gc'd binds if gc gets disabled
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
	GC_IS_DISABLED     = `[{script}] - Tried to add garbage collected Bind when Garbage Collector is disabled.`
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
  warn(`Error {message} encountered while triggering bind.`)
end

local function cleanGarbageCollectedBinds(): ()
	if (not CONSTANTS.DEFAULT_CLEAN_GC_BINDS) then
		return
	end
	garbage_collected_binds = {}
end

local function destroyGarbageCollectedBind
(
  name: string
): ()
  local found_correlating_bind = findBindByName(name)
  if (not found_correlating_bind) then
    warn(REASONS.GC_BIND_NOT_FOUND)
    return
  end
  binds[name] = nil
end

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
    updateGarbageCollectedBinds()
  end
end

local function serviceInit(): ()
  if (service_running) then
    return
  end
	service_running = true
  task.spawn(serviceLoop)
end

-- Public Garbage Collector Functions
--------------------------------------------------------------

local function getGarbageCollectorSettings(): (GarbageCollectorSettings)
	return garbage_collector_settings
end

-- Decides whether the garbage collector will run or not.
local function toggleGarbageCollector
(
	enabled : boolean
): ()

	assert(
		(enabled ~= nil),
		REASONS.GC_TOGGLE_IS_NIL
	)
	garbage_collector_settings.enabled = enabled

	if (enabled) then
		if (service_running) then
			return
		end
		task.spawn(serviceInit)
	end
end

local function modifyGarbageCollectorSettings
(
	props : {interval : number?}
): ()

	assert(
		props,
		REASONS.GC_INFO_NOT_GIVEN
	)

	local interval   : number  = (props.interval or garbage_collector_settings.interval or 1)
	garbage_collector_settings.interval = interval
end

-- Public Functions
--------------------------------------------------------------

-- Unlinks a function from a bind.
local function unbindFunction
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

-- Links a function to a bind.
local function bindFunction
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

-- Waits until a given bind is triggered.
local function awaitTrigger
(
	bind_name : string
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
  table.insert(bind.threads, coroutine.running())

	return coroutine.yield()
end

-- Destroys a given bind if it exists.
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

	binds[bind_name] = nil
end

-- Similar to triggering, but waits until the next cycle.
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

	if (#bind.threads ~= 0) then
		for _, thread in bind.threads do
			coroutine.resume(thread, ...)
		end
		bind.threads = {}
	end

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

-- Like triggering normally, but doesn't catch errors.
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
  
  if (#bind.threads ~= 0) then
    for _, thread in bind.threads do
      coroutine.resume(thread, ...)
    end
    bind.threads = {}
  end
  
  if (bind.link_amount == 0) then
    warn(REASONS.NO_FUNCS_LINKED)
    return
  end

  local links = bind.connections
  for _, link in links do
    task.spawn(link.func, ...)
  end
end

-- Triggers a bind, firing all functions and resuming threads.
local function triggerBind
(
	bind_name : string,
	...			  : any
): ()

	local bind : BindObject? = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end

	if (#bind.threads ~= 0) then
		for _, thread in bind.threads do
			coroutine.resume(thread, ...)
		end
		bind.threads = {}
	end

	if (bind.link_amount == 0) then
		warn(REASONS.NO_FUNCS_LINKED)
		return
	end

	local links = bind.connections
	for _, link in links do
    triggerFunc(
      bind.name, link, ...
    )
	end
end

-- Cleans a given bind's connections.
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

-- Overrides bind settings.
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

	bind.link_limit  = (bind_props.link_limit or bind.link_limit)
	bind.can_disband = (bind_props.can_disband or bind.can_disband)
end

-- Creates a new bind.
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
  
	if (bind.decay_time) then
		if (not garbage_collector_settings.enabled) then
			warn(REASONS.GC_IS_DISABLED)
			return
		end
		binds[bind_name].decay_time = bind.decay_time
    garbage_collected_binds[bind_name] = {
      name = bind_name,
      gc_time = bind.decay_time
    }
	end
end

-- Gets bind by name.
local function getBind
(
  name : string  
): (BindObject?)
  
  local found_bind = findBindByName(name)
  if (found_bind) then
    return found_bind
  end
  return nil
end

-- Gets all binds present.
local function getAllBinds(): ({
  [string] : BindObject
  })
  
  return binds
end

-- On require
--------------------------------------------------------------

serviceInit()

return table.freeze(
	{
		newBind		   	  = newBind,
		overrideBind      = overrideBind, -- override functions
		trigger 	      = triggerBind,
    	triggerDeferred   = triggerDeferred,
    	triggerUnreliable = triggerUnreliable,
		disbandBind 	  = disbandBind,
		cleanBind   	  = cleanBind,
		bindFunction	  = bindFunction,
		unbindFunction    = unbindFunction,
    	awaitTrigger      = awaitTrigger,
    	getBind           = getBind,
		getAllBinds       = getAllBinds,
		garbageCollector = {
			modifySettings = modifyGarbageCollectorSettings,
			getSettings    = getGarbageCollectorSettings,
			toggle 				 = toggleGarbageCollector,
		}
	}
)
