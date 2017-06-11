/* =================================================
    PluginCtl - X6Herbius, 11/02/2017
   ================================================= */

#if defined _PLUGINCTL_INC
 #endinput
#endif
#define _PLUGINCTL_INC

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#include "stringextra/stringextra.inc"

#define PCTL_PLUGIN_IDENT_MAX_LENGTH 16
#define PCTL_PLUGIN_LIBRARIES_MAX_LENGTH 256

static char _strPluginIdent[PCTL_PLUGIN_IDENT_MAX_LENGTH] = "";
static ConVar _cvPluginVersion = null;
static ConVar _cvPluginEnabled = null;

/**
 * Initialises the global data for this plugin.
 *
 * @param strPluginIdent    Unique identifier for this plugin. Cannot be longer than PCTL_PLUGIN_IDENT_MAX_LENGTH.
 * @param strPluginVersion  Version string for this plugin. Recommended format is "maj.min.rev.build".
 * @param cbEnabledChanged  Callback to call when the plugin's enabled state convar is changed.
 *
 * @noreturn
 */
public void PCtl_Initialise(const char[] strPluginIdent, const char[] strPluginVersion, ConVarChanged cbEnabledChanged)
{
    if ( isValid() )
    {
        ThrowError("PluginCtl: Already initialised for plugin '%s'.", _strPluginIdent);
    }
    
    strcopy(_strPluginIdent, sizeof(_strPluginIdent), strPluginIdent);
    
    char strPluginIdentLower[PCTL_PLUGIN_IDENT_MAX_LENGTH];
    StrEx_ToCase(strPluginIdentLower, sizeof(strPluginIdentLower), _strPluginIdent, StrEx_Lowercase);
    
    char strBuffer[64];
    
    Format(strBuffer, sizeof(strBuffer), "%s_enabled", strPluginIdentLower);
    _cvPluginEnabled = CreateConVar(strBuffer, "1", "Enables or disables the plugin.",
        FCVAR_ARCHIVE | FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0);
    
    Format(strBuffer, sizeof(strBuffer), "%s_version", strPluginIdentLower);
    _cvPluginVersion = CreateConVar(strBuffer, strPluginVersion, "Plugin version.",
        FCVAR_CHEAT);
    
    _cvPluginEnabled.AddChangeHook(cbEnabledChanged);
}

/**
 * Cleans up the global data for this plugin.
 *
 * @param cbEnabledChangedUnhook    Callback to unhook from the plugin enabled state convar, as passed to PCtl_Initialise.
 *
 * @noreturn
 */
public void PCtl_Shutdown(ConVarChanged cbEnabledChangedUnhook)
{
    if ( !isValid() )
    {
        return;
    }
    
    _cvPluginEnabled.RemoveChangeHook(cbEnabledChangedUnhook);
    
    delete _cvPluginEnabled;
    delete _cvPluginVersion;
}

/**
 * Returns the plugin version convar.
 *
 * @return Version convar.
 */
public ConVar PCtl_PluginVersion()
{
    return _cvPluginVersion;
}

/**
 * Returns the plugin enabled state convar.
 *
 * @return Enabled state convar.
 */
public ConVar PCtl_PluginEnabled()
{
    return _cvPluginEnabled;
}

/**
 * Returns the plugin identifier string.
 *
 * @param strBuffer   Output buffer.
 * @param nMaxLength  Length of the output buffer.
 *
 * @noreturn
 */
public void PCtl_PluginIdent(char[] strBuffer, int nMaxLength)
{
    if ( !isValid() )
    {
        return;
    }
    
    strcopy(strBuffer, nMaxLength, _strPluginIdent);
}

/**
 * Loads translations for the plugin.
 * This process assumes that for a plugin with a given IDENT:
 * - Translated phrases are contained within translations/IDENT/IDENT_phrases.txt
 * - Plugin config is located at cfg/sourcemod/IDENT/IDENT.cfg
 *
 * @noreturn
 */
public void PCtl_PerformPluginLoadTasks()
{
    if ( !isValid() )
    {
        return;
    }
    
    LoadTranslations("common.phrases");
    
    char buffer[64];
    
    Format(buffer, sizeof(buffer), "%s/%s_phrases", _strPluginIdent, _strPluginIdent);
    LoadTranslations(buffer);
    
    Format(buffer, sizeof(buffer), "sourcemod/%s", _strPluginIdent);
    AutoExecConfig(true, _strPluginIdent, buffer);
}

/**
 * Checks all the required libraries exist, and sets a failure state if any do not.
 * This should be called from OnAllPluginsLoaded().
 *
 * @param libraries Array of library name strings to check for.
 * @param count The total number of strings in the array.
 *
 * @noreturn
 */
public void PCtl_EnsureDependenciesExist(const char[][] libraries, int count)
{
    for ( int library = 0; library < count; ++library )
    {
        if ( !LibraryExists(libraries[library]) )
        {
            SetFailState("PluginCtl: Required library '%s' not found.");
        }
    }
}

stock bool isValid()
{
    return _cvPluginVersion != null;
}