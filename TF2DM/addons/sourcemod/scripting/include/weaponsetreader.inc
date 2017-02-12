#if defined _TF2DM_WEAPONSETREADER_INC
 #endinput
#endif
#define _TF2DM_WEAPONSETREADER_INC

#pragma semicolon 1
#pragma newdecls required

#include "include/weaponsetreadercore.inc"
#include "include/weaponsetreadercmds.inc"

public void WepSetRx_Initialise()
{
    WepSetRxCore_Initialise();
    WepSetRxCmds_Initialise();
}

public void WepSetRx_Shutdown()
{
    WepSetRxCmds_Shutdown();
    WepSetRxCore_Shutdown();
}