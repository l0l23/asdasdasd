/*
 * ============================================================================
 *
 *  Rotoblin
 *
 *  File:			rotoblin.itemcontrol.sp
 *  Type:			Module
 *  Description:	Tinkers with general items like throwables and cannisters
 *
 *  Copyright (C) 2010  Defrag <mjsimpson@gmail.com>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ============================================================================
 */

// --------------------
//       Private
// --------------------

static	const	Float:	REMOVE_DELAY					= 0.1; 

static	bool:	g_bEnableThrowables				= true;
static	Handle:	g_hEnableThrowables_Cvar			= INVALID_HANDLE;

static	bool:	g_bEnableCannisters				= true;
static	Handle:	g_hEnableCannisters_Cvar			= INVALID_HANDLE;

static			g_iDebugChannel						= 0;
static	const	String:	DEBUG_CHANNEL_NAME[]	= "ItemControl";

static const String: MOLOTOV_NAME[]					= "weapon_molotov_spawn"; // Trivia: Molotov basically means "hammer man".  His nickname was "iron arse".
static const String: PIPEBOMB_NAME[]				= "weapon_pipe_bomb_spawn";
static const String: PROP_PHYSICS_NAME[]			= "prop_physics";

static const String: GASCAN_MODEL_NAME[]			= "models/props_junk/gascan001a.mdl";
static const String: PROPANE_MODEL_NAME[]			= "models/props_junk/propanecanister001a.mdl";
static const String: OXYGEN_MODEL_NAME[]			= "models/props_equipment/oxygentank01.mdl";

// **********************************************
//                   Forwards
// **********************************************

/**
 * Plugin is starting.
 *
 * @noreturn
 */
public _ItemControl_OnPluginStart()
{
	HookPublicEvent(EVENT_ONPLUGINENABLE, _IC_OnPluginEnabled);
	HookPublicEvent(EVENT_ONPLUGINDISABLE, _IC_OnPluginDisabled);

	// Create convar
	CreateBoolConVar(g_hEnableThrowables_Cvar, "enable_throwables", "Enables or disables throwables (pipes and molotovs)", g_bEnableThrowables);
	UpdateEnableThrowables();
	
	// Create convar
	CreateBoolConVar(g_hEnableCannisters_Cvar, "enable_cannisters", "Enables or disables cannisters (petrol, propane and oxygen", g_bEnableCannisters);
	UpdateEnableCannisters();
	
	g_iDebugChannel = DebugAddChannel(DEBUG_CHANNEL_NAME);
	DebugPrintToAllEx("Module is now setup.", g_iDebugChannel);
}

static CreateBoolConVar(&Handle:conVar, const String:cvarName[], const String:cvarDescription[], bool:initialValue)
{	
	decl String:buffer[10];
	IntToString(int:initialValue, buffer, sizeof(buffer)); // Get default value for replacement style
	
	conVar = CreateConVarEx(cvarName, buffer, 
		cvarDescription, 
		FCVAR_NOTIFY | FCVAR_PLUGIN);
	
	if (conVar == INVALID_HANDLE) 
	{
		ThrowError("Unable to create enable cvar named %s!", cvarName);
	}
	
	AddConVarToReport(conVar); // Add to report status module
}

/**
 * Plugin is now enabled.
 *
 * @noreturn
 */
public _IC_OnPluginEnabled()
{
	HookEvent("round_start", _IC_RoundStart_Event, EventHookMode_PostNoCopy);
	HookEvent("round_end", _IC_RoundEnd_Event, EventHookMode_PostNoCopy);
	HookPublicEvent(EVENT_ONMAPEND, _IC_OnMapEnd);

	UpdateEnableThrowables();
	UpdateEnableCannisters();
	
	HookConVarChange(g_hEnableThrowables_Cvar, _IC_EnableThrowables_CvarChange);
	HookConVarChange(g_hEnableCannisters_Cvar, _IC_EnableCannisters_CvarChange);
	DebugPrintToAllEx("Module is now loaded");
}

/**
 * Plugin is now disabled.
 *
 * @noreturn
 */
public _IC_OnPluginDisabled()
{
	UnhookEvent("round_start", _IC_RoundStart_Event, EventHookMode_PostNoCopy);
	UnhookEvent("round_end", _IC_RoundEnd_Event, EventHookMode_PostNoCopy);
	UnhookPublicEvent(EVENT_ONMAPEND, _IC_OnMapEnd);
	UnhookPublicEvent(EVENT_ONENTITYCREATED, _IC_OnEntityCreated);

	UnhookConVarChange(g_hEnableThrowables_Cvar, _IC_EnableThrowables_CvarChange);
	UnhookConVarChange(g_hEnableCannisters_Cvar, _IC_EnableCannisters_CvarChange);
	
	DebugPrintToAllEx("Module is now unloaded");
}

/**
 * Map is ending.
 *
 * @noreturn
 */
public _IC_OnMapEnd()
{
	UnhookPublicEvent(EVENT_ONENTITYCREATED, _IC_OnEntityCreated); // To prevent mass processing while changing map
	DebugPrintToAllEx("Map end");
}

/**
 * Throwables style cvar changed.
 *
 * @param convar		Handle to the convar that was changed.
 * @param oldValue		String containing the value of the convar before it was changed.
 * @param newValue		String containing the new value of the convar.
 * @noreturn
 */
public _IC_EnableThrowables_CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAllEx("enable throwables cvar was changed. Old value %s, new value %s", oldValue, newValue);
	UpdateEnableThrowables();
}

/**
 * Cannisters style cvar changed.
 *
 * @param convar		Handle to the convar that was changed.
 * @param oldValue		String containing the value of the convar before it was changed.
 * @param newValue		String containing the new value of the convar.
 * @noreturn
 */
public _IC_EnableCannisters_CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAllEx("enable cannisters cvar was changed. Old value %s, new value %s", oldValue, newValue);
	UpdateEnableCannisters();
}

/**
 * Called when round start event is fired.
 *
 * @param event			INVALID_HANDLE (post no copy data hook).
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 * @noreturn
 */
public _IC_RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{		
	DebugPrintToAllEx("Round start");
	if (g_bEnableThrowables == false)
	{
		DebugPrintToAllEx("Will remove throwables");	
		RemoveThrowables();	
	}
	
	if (g_bEnableCannisters == false)
	{
		DebugPrintToAllEx("Will remove cannisters");	
		RemoveCarryableCannisters();	
	}
	
	HookPublicEvent(EVENT_ONENTITYCREATED, _IC_OnEntityCreated);
}

/**
 * Removes all throwables (pipes, molotovs) from the map
 *
 * @noreturn
 */
static RemoveThrowables()
{
	new pipeEnt = -1;
	while ((pipeEnt = FindEntityByClassnameEx(pipeEnt, PIPEBOMB_NAME)) != -1)
	{
		DebugPrintToAllEx("Removing pipebomb (ent %i)", pipeEnt);
		SafelyRemoveEdict(pipeEnt);
	}
	
	new moloEnt = -1;
	while ((moloEnt = FindEntityByClassnameEx(moloEnt, MOLOTOV_NAME)) != -1)
	{
		DebugPrintToAllEx("Removing molotov (ent %i)", moloEnt);
		SafelyRemoveEdict(moloEnt);
	}
}

/**
 * Removes all carryable cannisters (oxygen, propane, gas) from the map
 *
 * @noreturn
 */
static RemoveCarryableCannisters()
{
	new entity = -1;
	while ((entity = FindEntityByClassnameEx(entity, PROP_PHYSICS_NAME)) != -1)
	{
		if(PropPhysicsIsCarryableCannister(entity))
		{			
			SafelyRemoveEdict(entity);			
		}		
	}
}

/**
 * Called when round end event is fired.
 *
 * @param event			INVALID_HANDLE (post no copy data hook).
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 * @noreturn
 */
public _IC_RoundEnd_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	DebugPrintToAllEx("Round end");
	UnhookPublicEvent(EVENT_ONENTITYCREATED, _IC_OnEntityCreated); 
}

/**
 * When an entity is created.
 *
 * @param entity		Entity index.
 * @param classname		Classname.
 * @noreturn
 */
public _IC_OnEntityCreated(entity, const String:classname[])
{
	if(ShouldRemove(entity, classname))
	{
		new entRef = EntIndexToEntRef(entity);
		CreateTimer(REMOVE_DELAY, _IC_RemoveEntity_Delayed, entRef);
	}	
}

/**
 * Determines whether, according to current settings, an entity should be removed or not
 *
 * @param entity the entity being considered for removal
 * @param classname the entity's classname
 * @return boolean telling us whether to remove or not
 */
static bool:ShouldRemove(entity, const String:classname[])
{	
	if(!g_bEnableThrowables)
	{
		if (IsThrowable(classname))
		{
			DebugPrintToAllEx("Found a late spawned throwable.");		
			return true;
		}
	}
	
	if(!g_bEnableCannisters)
	{
		if (StrEqual(classname, PROP_PHYSICS_NAME) && PropPhysicsIsCarryableCannister(entity))
		{
			DebugPrintToAllEx("Found a late spawned cannister");
			return true;
		}
	}

	return false;
}

/**
 * Determines whether a class is a throwable item (pipebomb or molotov)
 *
 * @param classname the entity's classname
 * @return boolean whether it's throwable or not
 */
static bool:IsThrowable(const String:classname[])
{
	return StrEqual(classname, PIPEBOMB_NAME) || StrEqual(classname, MOLOTOV_NAME);
}

/**
 * Determines whether a prop_physics is a throwable cannister
 *
 * @param prop_physicsEntity an entity that is already known to be of type prop_physics
 * @return boolean telling us whether the supplied entity is a throwable cannister or not
 */
static bool:PropPhysicsIsCarryableCannister(prop_physicsEntity)
{	
	decl String:modelName[128];
	GetEntPropString(prop_physicsEntity, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
	
	DebugPrintToAllEx("prop_physics found.  Model name is: %s", modelName);			
	
	if(	StrEqual(modelName, GASCAN_MODEL_NAME, false) || 
		StrEqual(modelName, PROPANE_MODEL_NAME, false) || 
		StrEqual(modelName, OXYGEN_MODEL_NAME, false))
	{
		if(bool:GetEntProp(prop_physicsEntity, Prop_Send, "m_isCarryable", 1))
		{
			DebugPrintToAllEx("Found carryable cannister with model type %s", modelName);
			return true;
		}		
	}
	
	return false;
}

/**
 * Delayed function for removing an entity
 *
 * @param timer the timer
 * @param entRef the entity reference to the entity that we're trying to remove
 * @return god knows
 */
public Action:_IC_RemoveEntity_Delayed(Handle:timer, any:entRef)
{
	new entity = EntRefToEntIndex(entRef);		
	SafelyRemoveEdict(entity);
	DebugPrintToAllEx("Removed item");
}


// **********************************************
//                 Private API
// **********************************************

/**
 * Updates the global enable throwables var with the cvar.
 *
 * @noreturn
 */
static UpdateEnableThrowables()
{
	g_bEnableThrowables = GetConVarBool(g_hEnableThrowables_Cvar);
	DebugPrintToAllEx("Updated enable throwables global var; %b", bool:g_bEnableThrowables);
}

/**
 * Updates the global enable throwables var with the cvar.
 *
 * @noreturn
 */
static UpdateEnableCannisters()
{
	g_bEnableCannisters = GetConVarBool(g_hEnableCannisters_Cvar);
	DebugPrintToAllEx("Updated enable cannisters global var; %b", bool:g_bEnableCannisters);
}


/**
 * Wrapper for printing a debug message without having to define channel index
 * everytime.
 *
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 * @noreturn
 */
static DebugPrintToAllEx(const String:format[], any:...)
{
	decl String:buffer[DEBUG_MESSAGE_LENGTH];
	VFormat(buffer, sizeof(buffer), format, 2);
	DebugPrintToAll(g_iDebugChannel, buffer);
}