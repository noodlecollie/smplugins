#include <sourcemod>
#include "pluginctl.inc"

#pragma semicolon 1
#pragma newdecls required

bool _bPluginEnabledState = false;

public Plugin myinfo = 
{
    name = "[TEST] PluginCtl",
    author = "X6Herbius",
    description = "Test suite for PluginCtl",
    version = "1.0.0.0",
    url = "http://x6herbius.com"
}

public void OnPluginStart()
{
    _bPluginEnabledState = true;
    LogMessage("[TEST] PluginCTL test suite running...");
    
    Test(PCtl_PluginVersion() == null, "Plugin version convar was not initially null.");
    Test(PCtl_PluginEnabled() == null, "Plugin enabled convar was not initially null.");
    
    PCtl_Initialise("tst", "1.2.3.4", OnPluginEnabledStateChanged);
    Test(PCtl_PluginVersion() != null, "Plugin version convar was null after initialisation.");
    Test(PCtl_PluginEnabled() != null, "Plugin enabled convar was null after initialisation.");
    Test(PCtl_PluginEnabled().BoolValue, "Plugin enabled convar was not set to enabled after initialisation.");
    
    char buffer[64];
    PCtl_PluginVersion().GetString(buffer, sizeof(buffer));
    Test(StrEqual(buffer, "1.2.3.4"), "Plugin version was not stored in convar successfully.");
    
    PCtl_PluginEnabled().BoolValue = false;
    Test(!_bPluginEnabledState, "Callback was not called correctly when plugin was disabled via convar.");
    
    PCtl_PluginEnabled().BoolValue = true;
    Test(_bPluginEnabledState, "Callback was not called correctly when plugin was enabled via convar.");
    
    PCtl_Shutdown(OnPluginEnabledStateChanged);
    LogMessage("[TEST] PluginCTL test suite passed.");
}

public void OnPluginEnd()
{
}

public void OnPluginEnabledStateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    _bPluginEnabledState = convar.BoolValue;
}

void Test(bool bResult, const char[] strError)
{
    if ( !bResult )
    {
        ThrowError(strError);
    }
}
