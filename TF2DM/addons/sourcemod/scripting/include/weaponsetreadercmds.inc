#if defined _TF2DM_WEAPONSETREADERCMDS_INC
 #endinput
#endif
#define _TF2DM_WEAPONSETREADERCMDS_INC

#pragma semicolon 1
#pragma newdecls required

#include <tf2>
#include "tf2extra/tf2extra.inc"

#include "include/weaponsetreadercore.inc"

public void WepSetRxCmds_Initialise()
{
    RegAdminCmd("tf2dm_wepsetrx_dump", WepSetRxCmds_CommandDumpRequested, view_as<int>(Admin_Config), "Dumps info about weapon sets. Invoke with no arguments to see usage details.");
}

public void WepSetRxCmds_Shutdown()
{
}

public Action WepSetRxCmds_CommandDumpRequested(int nClient, int nArgs)
{
    if ( nArgs < 1 )
    {
        PrintToConsole(nClient,
                       "Usage: tf2dm_wepsetrx_dump <weaponset> [slot] [class]\n" ...
                       "Weapon set ID is required, but other arguments are optional.\n" ...
                       "If no slot is specified, data for all slots will be output\n" ...
                       "(same for classes).");
                       
        return Plugin_Handled;
    }
    
    char strArgWeaponSet[16];
    GetCmdArg(1, strArgWeaponSet, sizeof(strArgWeaponSet));
    
    int nWeaponSet = StringToInt(strArgWeaponSet);
    if ( nWeaponSet < 0 || nWeaponSet >= MAX_WEAPONSETS )
    {
        PrintToConsole(nClient, "Weaponset index of '%i' out of range [0-%i].", nWeaponSet, MAX_WEAPONSETS-1);
        return Plugin_Handled;
    }
    
    int nSlot = -1;
    if ( nArgs >= 2 )
    {
        char strArgSlot[16] = "";
        GetCmdArg(2, strArgSlot, sizeof(strArgSlot));
        nSlot = StringToInt(strArgSlot);
        
        if ( nSlot < 0 || nSlot >= MAX_WEAPONSET_SLOTS )
        {
            PrintToConsole(nClient, "Slot value of '%i' out of range [0-%i].", nSlot, MAX_WEAPONSET_SLOTS-1);
            return Plugin_Handled;
        }
    }
    
    TFClassType nClass = TFClass_Unknown;
    if ( nArgs >= 3 )
    {
        char strArgClass[16] = "";
        GetCmdArg(3, strArgClass, sizeof(strArgClass));
        nClass = TF2_GetClass(strArgClass);
        
        if ( nClass == TFClass_Unknown )
        {
            PrintToConsole(nClient, "Class '%s' unrecognised.", strArgClass);
            return Plugin_Handled;
        }
    }
    
    char strWeaponSetName[MAX_WEAPONSET_NAME_LENGTH] = "";
    WepSetRxCore_GetWeaponSetDescriptiveName(nWeaponSet, strWeaponSetName, sizeof(strWeaponSetName));
    if ( strlen(strWeaponSetName) < 1 )
    {
        PrintToConsole(nClient, "Unnamed weapon set");
    }
    else
    {
        PrintToConsole(nClient, "'%s'", strWeaponSetName);
    }
    
    switch ( nArgs )
    {
        // Only weapon set ID was specified.
        case 1:
        {
            PrintAllSlotIndexes(nClient, nWeaponSet);
        }
        
        // Weapon set and slot were specified.
        case 2:
        {
            PrintAllClassIndexes(nClient, nWeaponSet, nSlot);
        }
        
        // All attributes were specified.
        default:
        {
            PrintHeader(nClient);
            PrintWeaponSetRecordToConsole(nClient, nWeaponSet, nSlot, nClass);
        }
    }
    
    return Plugin_Handled;
}

stock void PrintHeader(int nClient)
{
    PrintToConsole(nClient, "Set\tSlot\tClass\t\tItem Index");
}

stock void PrintAllSlotIndexes(int nClient, int nWeaponSet)
{
    for ( int nSlot = 0; nSlot < MAX_WEAPONSET_SLOTS; ++nSlot )
    {
        PrintAllClassIndexes(nClient, nWeaponSet, nSlot);
        PrintToConsole(nClient, "");
    }
}

stock void PrintAllClassIndexes(int nClient, int nWeaponSet, int nSlot)
{
    PrintHeader(nClient);
    
    for ( TFClassType nClass = TFCLASS_LOWER_BOUND; nClass <= TFCLASS_UPPER_BOUND; ++nClass )
    {
        PrintWeaponSetRecordToConsole(nClient, nWeaponSet, nSlot, nClass);
    }
}

stock void PrintWeaponSetRecordToConsole(int nClient, int nWeaponSet, int nSlot, TFClassType nClass)
{
    int nWeaponDefIndex = WepSetRxCore_GetItemIndex(nWeaponSet, nSlot, nClass);
    bool bShouldTabExtra = nClass != TFClass_Heavy && nClass != TFClass_Engineer;
    
    PrintToConsole(nClient, "%i\t%i\t%s%s\t%i", nWeaponSet, nSlot, TF2Ex_ClassName[nClass], bShouldTabExtra ? "\t" : "", nWeaponDefIndex);
}