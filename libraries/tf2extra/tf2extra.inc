/* =================================================
    TF2Extra - X6Herbius, 11/02/2017
   ================================================= */

#if defined _TF2EXTRA_INC
 #endinput
#endif
#define _TF2EXTRA_INC

#pragma semicolon 1
#pragma newdecls required

#include <tf2>

static const char _strClassNames[][] =
{
    "unknown",
    "scout",
    "sniper",
    "soldier",
    "demoman",
    "medic",
    "heavyweapons",
    "pyro",
    "spy",
    "engineer"
};

public void TF2Ex_GetClassName(TFClassType nClass, char[] strBuffer, int nLength)
{
    if ( nClass < TFClass_Unknown || nClass > TFClass_Engineer )
    {
        ThrowError("TF2Ex: Unrecognised class '%n'.", nClass);
    }
    
    strcopy(strBuffer, nLength, _strClassNames[nClass]);
}