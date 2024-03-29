/*
 * ============================================================================
 *
 *  Teamclerks
 *
 *  File:            teamclerks.main.sp
 *  Type:            Main
 *  Description:    Contains defines, enums, etc available to anywhere in the 
 *                    plugin.
 *    Credits:        kain
 *                    (http://www.teamclerks.net)
 *                  and the Rotoblin team for getting me started.
 *
 *  Copyright (C) 2012  kain <kain@teamclerks.net>
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

// **********************************************
//                 Preprocessor
// **********************************************

#pragma semicolon 1

// **********************************************
//                   Reference
// **********************************************

#define TC_DEBUG                1 // Whether debugging is enabled
#define TC_DEBUG_SERVER         0 // Whether debugging goes to the server console (1) or the file log (0)

#define SERVER_INDEX            0 // The client index of the server

#define MAX_ENTITIES            2048 // Max number of entities l4d supports

// Plugin info
#define PLUGIN_FULLNAME         "TeamClerks"                                    // Used when printing the plugin name anywhere
#define PLUGIN_SHORTNAME        "teamclerks"                                    // Shorter version of the full name, used in file paths, and other things
#define PLUGIN_AUTHOR           "kain"                                          // Author of the plugin
#define PLUGIN_DESCRIPTION      "A handful of utility plugins for L4D"          // Description of the plugin
#define PLUGIN_VERSION          "0.1.4"                                         // http://wiki.eclipse.org/Version_Numbering
#define PLUGIN_URL              "http://teamclerks-l4d-utils.googlecode.com/"   // URL associated with the project
#define PLUGIN_CVAR_PREFIX      PLUGIN_SHORTNAME                                // Prefix for cvars
#define PLUGIN_CMD_PREFIX       PLUGIN_SHORTNAME                                // Prefix for cmds
#define PLUGIN_TAG              "TeamClerks"                                    // Tag for prints and commands
#define PLUGIN_GAMECONFIG_FILE  PLUGIN_SHORTNAME                                // Name of gameconfig file

// **********************************************
//                    Includes
// **********************************************

// Globals
#include <sourcemod>
#include <sdktools>

#include "rotoblin/helpers/debug.inc"
#include "rotoblin/helpers/cmdmanager.inc"
#include "rotoblin/helpers/eventmanager.inc"
#include "rotoblin/helpers/clientindexes.inc"
#include "rotoblin/helpers/wrappers.inc"
#include "rotoblin/helpers/tankmanager.inc"

#include "teamclerks/helpers/clients.inc"
#include "teamclerks/helpers/restartmap.inc"

#include "teamclerks/cvarsilencer.sp"
#include "teamclerks/load.sp"
#include "teamclerks/skeetpractice.sp"
#include "teamclerks/1v1.sp"
#include "teamclerks/teamselect.sp"
#include "teamclerks/lerps.sp"

// --------------------
//       Private
// --------------------

static            bool: g_bIsZACKLoaded      = false;

// **********************************************
//                      Forwards
// **********************************************

public Plugin:myinfo = 
{
    name = PLUGIN_FULLNAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
}

/**
 * Called on pre plugin start.
 *
 * @param myself        Handle to the plugin.
 * @param late            Whether or not the plugin was loaded "late" (after map load).
 * @param error            Error message buffer in case load failed.
 * @param err_max        Maximum number of characters for error message buffer.
 * @return                APLRes_Success for load success, APLRes_Failure or APLRes_SilentFailure otherwise.
 */
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    /* Check plugin dependencies */
    if (!IsDedicatedServer())
    {
        strcopy(error, err_max, "Plugin only support dedicated servers");
        return APLRes_Failure; // Plugin does not support client listen servers, return
    }

    decl String:buffer[128];
    GetGameFolderName(buffer, 128);

    if (!StrEqual(buffer, "left4dead", false))
    {
        strcopy(error, err_max, "Plugin only support Left 4 Dead");
        return APLRes_Failure; // Plugin does not support this game, return
    }

    return APLRes_Success; // Allow load
}

/**
 * On plugin start extended. Called by the event manager once its done setting up.
 *
 * @noreturn
 */
public OnPluginStartEx()
{
    TC_Debug("Setting up...");

    decl String:buffer[128];
    Format(buffer, sizeof(buffer), "%s version", PLUGIN_FULLNAME);
    new Handle:convar = CreateConVarEx("version", PLUGIN_VERSION, buffer, FCVAR_PLUGIN | FCVAR_NOTIFY);
    SetConVarString(convar, PLUGIN_VERSION);

    if (GetMaxEntities() > MAX_ENTITIES) // Ensure that our MAX_ENTITIES const is updated
    {
        ThrowError("Max entities exceeded, %d. Plugin needs a recompile with a updated max entity const, current value %d.", GetMaxEntities(), MAX_ENTITIES);
    }

    /* Initial setup of modules after event manager is done setting up.
     * To disable certain module, simply comment out the line. */

    // Load the rotoblin helpers
    _H_TankManager_OnPluginStart();
    _H_ClientIndexes_OnPluginStart();
    _H_CommandManager_OnPluginStart();
    
    _CvarSilencer_OnPluginStart();
    _Load_OnPluginStart();
    _SkeetPractice_OnPluginStart();
    _1v1_OnPluginStart();
    _TeamSelect_OnPluginStart();
    _Lerps_OnPluginStart();
    
    // Create cvar for control plugin state
    Format(buffer, sizeof(buffer), "Sets whether %s is enabled", PLUGIN_FULLNAME);
    convar = CreateConVarEx("enable", "0", buffer, FCVAR_PLUGIN | FCVAR_SPONLY);

    if (convar == INVALID_HANDLE) ThrowError("Unable to create main enable cvar!");
    if (GetConVarBool(convar) && !IsDedicatedServer())
    {
        SetConVarBool(convar, false);
        TC_Debug("Unable to enable teamclerks, running on a listen server!");
    }
    else
    {
        SetPluginState(GetConVarBool(convar));
    }

    HookConVarChange(convar, _Main_Enable_CvarChange);
    TC_Debug("Done setting up!");
}

public OnAllPluginsLoaded()
{
    if (LibraryExists("zack")) // If ZACK is loaded on the server
    {
        g_bIsZACKLoaded = true;
    }
    else
    {
        g_bIsZACKLoaded = false;
    }
}

public OnLibraryRemoved(const String:name[])
{
    if (StrEqual(name, "zack"))
    {
        g_bIsZACKLoaded = false;
    }
}

public OnLibraryAdded(const String:name[])
{
    if (StrEqual(name, "zack"))
    {
        g_bIsZACKLoaded = true;
    }
}

/**
 * Enable cvar changed.
 *
 * @param convar        Handle to the convar that was changed.
 * @param oldValue        String containing the value of the convar before it was changed.
 * @param newValue        String containing the new value of the convar.
 * @noreturn
 */
public _Main_Enable_CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
    TC_Debug("Enable cvar was changed. Old value %s, new value %s", oldValue, newValue);

    if (GetConVarBool(convar) && !IsDedicatedServer())
    {
        SetConVarBool(convar, false);
        TC_Debug("Unable to enable teamclerks, running on a listen server!");
        PrintToChatAll("[%s] Unable to enable %s! %s only support dedicated servers", PLUGIN_TAG, PLUGIN_FULLNAME, PLUGIN_FULLNAME);
        return;
    }

    SetPluginState(bool:StringToInt(newValue));
}

/**
 * Returns whether ZACK is loaded.
 *
 * @return              True if ZACK is loaded, false otherwise.
 */
stock bool:IsZACKLoaded() return g_bIsZACKLoaded;

/**
 * Helper method for rendering debug statements.
 */
TC_Debug(const String:format[], any:...)
{
    #if TC_DEBUG
    decl String:buffer[192];
    
    VFormat(buffer, sizeof(buffer), format, 2);
    
    #if TC_DEBUG_SERVER
    PrintToServer("%s", buffer);
    #else
    LogMessage("%s", buffer);
    #endif
    
    #else
    //suppress "format" never used warning
    if(format[0])
        return;
    else
        return;
    #endif
}