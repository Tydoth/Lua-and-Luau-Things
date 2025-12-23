
-- BindService edited to be pure Lua.

-- Variables

-- Modify as needed
local CONSTANTS = {
	LINK_LIMIT = 8, -- useful for preventing memory leaks 
	DEFAULT_ONCE = false,
	BUILT_IN_BIND_NAMES = {
		ADDED = "ADDED",
		REMOVED = "REMOVED",
		TRIGGERING = "TRIGGERING"
	},
	BUILT_IN_BIND_LINK_LIMIT = 16
}

local REASONS = {
	NAME_NOT_PROVIDED = `[{script}] - Name not provided to find bind.`,
	BIND_NOT_FOUND = `[{script}] - Bind of name not found!`,
	FUNC_NOT_FOUND = `[{script}] - Function of name not found!`,
	NO_FUNCS_LINKED = `[{script}] - Bind doesn't have links!`,
	NOT_DISBANDABLE = `[{script}] - Bind can't be disbanded!`,
	BIND_EXISTS = `[{script}] - Bind with name already exists!`,
	LINK_LIMIT_REACHED = `[{script}] - Bind's link limit reached!`,
	IS_BUILTIN_BIND = `[{script}] - Tried to override built in bind.`
}

local binds = {}

-- Private Functions

local function findBindByName(bind_name)	
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

local function linkExists(bind,	func_name)
	local found = bind.connections[func_name]
	if (not found) then
		warn(REASONS.FUNC_NOT_FOUND)
		return false
	end

	return true
end

local function continueHaltedThreads(bind_name, args)
	if (#binds[bind_name].threads == 0) then
		return
	end

	for _, thread in binds[bind_name].threads do
		coroutine.resume(thread, args)
	end
	binds[bind_name].threads = {}
end

local function createBuiltInBinds(): ()
	for _, bind in CONSTANTS.BUILT_IN_BIND_NAMES do
		local created = {
			name = bind,
			link_limit = CONSTANTS.BUILT_IN_BIND_LINK_LIMIT,
			threads = {},
			link_amount = 0,
			can_disband = false,
			connections = {}
		}
		binds[bind] = created
	end

end

local function triggerBuiltInBind(name, args)
	for _, link in binds[name].connections do
		coroutine.resume(link, args)
	end
end

-- Public Utility Functions

local function getConstants()
	return CONSTANTS
end

local function getAllBindNames()
	if (not next(binds)) then
		return {}
	end

	local names = {}
	for name in binds do
		names[name] = name
	end
	return names
end

local function getBind(bind_name)
	local found_bind = findBindByName(bind_name)
	if (found_bind) then
		return found_bind
	end
	return nil
end

local function getAllBinds()
	return binds
end

-- Public Functions

local function unlinkFunction(bind_name, func_name)

	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end

	local func_exists = linkExists(bind, func_name)
	if (not func_exists) then
		warn(REASONS.FUNC_NOT_FOUND)
		return
	end
	bind.link_amount -= 1
	bind.connections[func_name] = nil
end

local function linkFunction(bind_name, func_name, func, props)
	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (bind.link_amount >= bind.link_limit) then
		warn(REASONS.LINK_LIMIT_REACHED)
		return
	end
	local newProps = (props or {})

	bind.link_amount += 1
	bind.connections[func_name] = {
		name = func_name,
		func = func,
		once = (newProps.happen_once or CONSTANTS.DEFAULT_ONCE)
	}
end

local function awaitTrigger(bind_name)
	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	table.insert(binds[bind_name].threads, coroutine.running())

	return coroutine.yield()
end

local function triggerReturned(bind_name, args)
	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return nil
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return nil
	end
	continueHaltedThreads(bind_name, args)
	
	if (bind.link_amount == 0) then
		warn(REASONS.NO_FUNCS_LINKED)
		return nil
	end

	local links = bind.connections
	local returns = {}
	for _, link in links do
		returns[link.name] = link.func(args)
	end
	return returns
end

local function trigger(bind_name, args)
	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return
	end
	continueHaltedThreads(bind_name, args)

	if (bind.link_amount == 0) then
		warn(REASONS.NO_FUNCS_LINKED)
		return
	end

	triggerBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.TRIGGERING, bind_name)
	local links = bind.connections
	for _, link in links do
		link.func(args)
	end
end

local function resumeBind(bind_name)
	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	continueHaltedThreads(bind_name)
end

local function cleanBind(bind_name)
	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end

	bind.connections = {}
end

local function overrideBind(bind_name, bind_props)
	local bind = findBindByName(bind_name)
	if (not bind) then
		warn(REASONS.BIND_NOT_FOUND)
		return
	end
	if (table.find(CONSTANTS.BUILT_IN_BIND_NAMES, bind_name)) then
		warn(REASONS.IS_BUILTIN_BIND)
		return
	end
	
	local link_limit = (bind_props.link_limit and (type(bind_props.link_limit) == "number") and bind_props.link_limit) or bind.link_limit
	local can_disband = (bind_props.can_disband and (type(bind_props.can_disband) == "boolean") and bind_props.can_disband) or true
	
	bind.link_limit  = link_limit
	bind.can_disband = (bind_props.can_disband or bind.can_disband)
end

local function disbandBind(bind_name)

	local bind = findBindByName(bind_name)
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

local function newBind(bind_name, bind_props)
	local bind_exists = findBindByName(bind_name)
	if (bind_exists) then
		warn(REASONS.BIND_EXISTS)
		return
	end

	local new_props = (bind_props or {})
	local can_disband = (new_props.can_disband or true)
	local link_limit = math.max(
		CONSTANTS.LINK_LIMIT,
		(new_props.link_limit or CONSTANTS.LINK_LIMIT)
	)

	local bind = {
		name 				= bind_name,
		can_disband = (can_disband or true),
		link_limit  = link_limit,
		link_amount = 0, 
		connections = {},
		threads = {}
	}
	binds[bind_name] = bind

	triggerBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.ADDED, bind_name)
end

-- private again but too

local function initBuiltInBind(name)
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
		await = function(): (... any)
			return awaitTrigger(name)
		end,
	}
end

--------------------------------------------------------------

return table.freeze(
	{
		newBind		   	    = newBind,
		overrideBind      = overrideBind,
		trigger 	  		  = trigger,
		triggerReturned   = triggerReturned,
		awaitTrigger      = awaitTrigger,
		disbandBind 	    = disbandBind,
		cleanBind   	    = cleanBind,
		linkFunction	    = linkFunction,
		unlinkFunction    = unlinkFunction,
		getBind           = getBind,
		getAllBinds       = getAllBinds,
		getAllBindNames   = getAllBindNames,
		getConstants      = getConstants,
		OnBindAdded				= initBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.ADDED),
		OnBindDisbanding  = initBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.REMOVED),
		OnTriggerCall     = initBuiltInBind(CONSTANTS.BUILT_IN_BIND_NAMES.TRIGGERING)
	}
)