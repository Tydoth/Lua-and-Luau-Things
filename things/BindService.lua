--!strict
--!optimize 2
--[[
	A module that doesn't use metatable magic or bindable events, pure table magic.
	You need to unlink manually.
	
	made by Tydoth in like 30 minutes
	it's literally impossible to make server to client communication without remotes
	
	TODO:
	* Implement GC'd binds after a long pass (DONE)
	* Implement a way to get all binds
]]

-- private

local CONSTANTS = {
	LINK_LIMIT      = 8, -- useful for preventing memory leaks 
  DEFAULT_ONCE    = false,
  DEFAULT_GC_MODE = false, -- garbage collected,
  DEFAULT_GC_CLEAN_TIME = 300, -- time when gc'd binds are cleaned
  DEFAULT_GC_CLEAN_INTERVAL = 1, -- clean gc'd binds after some time,
  SERVICE_INIT_TAG = "ServitAlreadyRunningOrSomething"
}

local REASONS = {
	NAME_NOT_PROVIDED  = `[{script}] - Name not provided to find bind.`,
	BIND_NOT_FOUND     = `[{script}] - Bind of name not found!`,
	FUNC_NOT_FOUND     = `[{script}] - Function of name not found!`,
	NO_FUNCS_LINKED    = `[{script}] - Bind doesn't have links!`,
	NOT_DISBANDABLE    = `[{script}] - Bind can't be disbanded!`,
	BIND_EXISTS        = `[{script}] - Bind with name already exists!`,
  LINK_LIMIT_REACHED = `[{script}] - Bind's link limit reached!`,
  GC_BIND_NOT_FOUND  = `[{script} Internal] - Garbage Collected Bind not found.`
}

type LinkProps = {
	happen_once : boolean?
}

type Link = {
	name : string,
	func : (... any) -> (... any),
	once : boolean
}

type BindObjectProps = {
	can_disband : boolean?,
  link_limit  : number?,
  decay_time  : number? -- automatically gives it to gc list if this arg is provided
}

type BindObject = {
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

local binds : {[string]: BindObject} = {}
local garbage_collected_binds : {
  [string]: {
    name    : string,
    gc_time : number
  }
} = {}

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
  garbage_collected_binds[name] = nil
end

local function updateGarbageCollectedBinds(): ()
  local binds = garbage_collected_binds
  for _, bind in binds do
    bind.gc_time -= 1
    if (bind.gc_time <= 0)  then
     destroyGarbageCollectedBind(bind.name)
    end
  end
end

local function serviceLoop(): ()
  while (true) do
    task.wait(CONSTANTS.DEFAULT_GC_CLEAN_INTERVAL)
    if (not next(garbage_collected_binds)) then
      continue
    end
    updateGarbageCollectedBinds()
  end
end

local function serviceInit(): ()
  if (script:HasTag(CONSTANTS.SERVICE_INIT_TAG)) then
    return
  end
  script:AddTag(CONSTANTS.SERVICE_INIT_TAG)
  task.spawn(serviceLoop)
end

-- public

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

	local new_props : BindObjectProps = (bind_props or {})

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
    decay_time  = (new_props.decay_time or nil),    
		connections = {},
		threads = {}
	}
  binds[bind_name] = bind
  
  if (bind.decay_time) then
    garbage_collected_binds[bind_name] = {
      name = bind_name,
      gc_time = bind.decay_time
    }
  end
end

local function getAllBinds(): ({
  [string] : BindObject
  })
  
  return binds
end

serviceInit()

return table.freeze(
	{
		newBind		   	  = newBind,
		overrideBind    = overrideBind,
		trigger 	  		= triggerBind,
		triggerDeferred = triggerDeferred,
		disbandBind 	  = disbandBind,
		cleanBind   	  = cleanBind,
		bindFunction	  = bindFunction,
		unbindFunction  = unbindFunction,
 	    awaitTrigger    = awaitTrigger,
    	getAllBinds     = getAllBinds
	}
)
