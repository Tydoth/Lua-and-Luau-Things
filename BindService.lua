--!strict
--[[
	A module that doesn't use metatable magic or bindable events, pure table magic.
	You need to unlink manually.
	
	made by Tydoth in like 30 minutes
	it's literally impossible to make server to client communication without remotes
]]

-- private

local CONSTANTS = {
	LINK_LIMIT = 4,
	DEFAULT_ONCE = false
}

local REASONS = {
	NAME_NOT_PROVIDED  = `[{script}] - Name not provided to find bind.`,
	BIND_NOT_FOUND     = `[{script}] - Bind of name not found!`,
	FUNC_NOT_FOUND     = `[{script}] - Function of name not found!`,
	NO_FUNCS_LINKED    = `[{script}] - Bind doesn't have links!`,
	NOT_DISBANDABLE    = `[{script}] - Bind can't be disbanded!`,
	BIND_EXISTS        = `[{script}] - Bind with name already exists!`,
	LINK_LIMIT_REACHED = `[{script}] - Bind's link limit reached!`
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
	link_limit  : number?
}

type BindObject = {
	connections : {
		[string] : Link
	},	
	threads			: {thread},
	name 				: string,
	can_disband : boolean,
	link_limit  : number,
	link_amount : number
}

local binds : {[string]: BindObject} = {}

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
		local func = link.func
		if (not func) then
			continue
		end
		local success, message = pcall(func, ...)
		if (link.once) then
			bind.connections[link.name] = nil
			bind.link_amount -= 1
		end
		if (success) then
			continue
		end
		warn(`Error {message} encountered while triggering bind.`)
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
		connections = {},
		threads = {}
	}
	binds[bind_name] = bind
end

return {
	newBind		   	  = newBind,
	overrideBind    = overrideBind,
	triggerBind 	  = triggerBind,
	disbandBind 	  = disbandBind,
	cleanBind   	  = cleanBind,
	bindFunction	  = bindFunction,
	unbindFunction  = unbindFunction,
	awaitTrigger    = awaitTrigger,
}