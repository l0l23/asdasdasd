/*
 * ============================================================================
 *
 *  Rotoblin
 *
 *  File:			rotoblin.2vs2mod.sp
 *  Type:			Module
 *  Description:	Provides a few modifications to rotoblin to support 2vs2.
 *
 *  Copyright (C) 2010  Mr. Zero <mrzerodk@gmail.com>
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

static					g_iDebugChannel			= 0;
static	const	String:	DEBUG_CHANNEL_NAME[]	= "2vs2mod";

static			Handle:	g_bIsModEnabled_Cvar	= INVALID_HANDLE;
static			bool:	g_bIsModEnabled			= false;

static	const	String:	INFECTED_BOT_NAMES[][]	= {"Hunter", "Boomer", "Smoker"};

// **********************************************
//                   Forwards
// **********************************************

/**
 * Plugin is starting.
 *
 * @noreturn
 */
public _2vs2Mod_OnPluginStart()
{
	HookPublicEvent(EVENT_ONPLUGINENABLE, _2V2_OnPluginEnabled);
	HookPublicEvent(EVENT_ONPLUGINDISABLE, _2V2_OnPluginDisabled);

	decl String:buffer[2];
	IntToString(int:g_bIsModEnabled, buffer, sizeof(buffer));
	g_bIsModEnabled_Cvar = CreateConVarEx("enable_2v2", buffer, "Sets whether 2vs2 mod is enabled", FCVAR_NOTIFY | FCVAR_PLUGIN);
	if (g_bIsModEnabled_Cvar == INVALID_HANDLE) ThrowError("Unable to create 2vs2mod cvar!");
	g_bIsModEnabled = GetConVarBool(g_bIsModEnabled_Cvar);
	AddConVarToReport(g_bIsModEnabled_Cvar); // Add to report status module

	g_iDebugChannel = DebugAddChannel(DEBUG_CHANNEL_NAME);
	DebugPrintToAllEx("Module is now setup");
}

/**
 * Plugin is now enabled.
 *
 * @noreturn
 */
public _2V2_OnPluginEnabled()
{
	g_bIsModEnabled = GetConVarBool(g_bIsModEnabled_Cvar);
	HookConVarChange(g_bIsModEnabled_Cvar, _2V2_Enable_CvarChange);
	HookPublicEvent(EVENT_ONCLIENTPUTINSERVER, _2V2_OnClientPutInServer);

	HookTankEvent(TANK_PASSED, _2V2_TankPassed_Event);

	DebugPrintToAllEx("Module is now loaded");
}

/**
 * Plugin is now disabled.
 *
 * @noreturn
 */
public _2V2_OnPluginDisabled()
{
	UnhookConVarChange(g_bIsModEnabled_Cvar, _2V2_Enable_CvarChange);

	UnhookPublicEvent(EVENT_ONCLIENTPUTINSERVER, _2V2_OnClientPutInServer);

	DebugPrintToAllEx("Module is now unloaded");
}

/**
 * Tank was passed.
 *
 * @noreturn
 */
public _2V2_TankPassed_Event()
{
	if (!g_bIsModEnabled) return;
	new client = GetTankClient();
	if (!client || !IsClientInGame(client) || !IsFakeClient(client)) return;

	DebugPrintToAllEx("Forced client %i: \"%N\" to suicide", client, client);
	ForcePlayerSuicide(client);

	CreateTimer(5.0, _2V2_KickInfectedBot, client);
}

/**
 * A client is put in the server
 *
 * @param client		Client index.
 * @noreturn
 */
public _2V2_OnClientPutInServer(client)
{
	if (!g_bIsModEnabled || !client || !IsFakeClient(client)) return; // Only deal with bots

	DebugPrintToAllEx("Client %i was put in server", client);
	CreateTimer(0.1, _2V2_SlayInfectedBot, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Called when the slay bot timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param client		Client index to slay.
 * @noreturn
 */
public Action:_2V2_SlayInfectedBot(Handle:timer, any:client)
{
	if (!client || !IsClientInGame(client) || !IsFakeClient(client)) return Plugin_Stop;

	decl String:name[32];
	GetClientName(client, name, sizeof(name));

	if (strlen(name) == 0) return Plugin_Continue; // Client still don't have a name

	new bool:foundBot = false;
	for (new i = 0; i < sizeof(INFECTED_BOT_NAMES); i++)
	{
		if (StrContains(name, INFECTED_BOT_NAMES[i], false) == -1) continue;
		foundBot = true;
		break;
	}

	if (!foundBot) return Plugin_Stop;

	if (IsPlayerAlive(client))
	{
		DebugPrintToAllEx("Forced client %i: \"%N\" to suicide", client, client);
		ForcePlayerSuicide(client);
	}

	CreateTimer(1.0, _2V2_KickInfectedBot, client);
	return Plugin_Stop;
}

/**
 * Called when the kick bot timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param client		Client index to kick.
 * @noreturn
 */
public Action:_2V2_KickInfectedBot(Handle:timer, any:client)
{
	if (!client || !IsClientInGame(client) || !IsFakeClient(client)) return;
	DebugPrintToAllEx("Kicked client %i: \"%N\"", client, client);
	KickClient(client, "[%s] Kicked infected bot", PLUGIN_TAG);
}

/**
 * Enable cvar changed.
 *
 * @param convar		Handle to the convar that was changed.
 * @param oldValue		String containing the value of the convar before it was changed.
 * @param newValue		String containing the new value of the convar.
 * @noreturn
 */
public _2V2_Enable_CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAllEx("Enable cvar was changed. Old value %s, new value %s", oldValue, newValue);
	g_bIsModEnabled = GetConVarBool(g_bIsModEnabled_Cvar);
}

// **********************************************
//                 Private API
// **********************************************

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