/* =================================================
    ClientRecords - X6Herbius, 06/05/2018
   ================================================= */

#if defined _CLIENTRECORDS_INC
 #endinput
#endif
#define _CLIENTRECORDS_INC

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dynamic>

typedef ClientRecord_InitFunc = function void(Dynamic &item);

static Dynamic _records[MAXPLAYERS] = { INVALID_DYNAMIC_OBJECT, ... };
static Handle _fwdConstructor = INVALID_HANDLE;
static bool _bInitialised = false;

/**
 * Initialises client records.
 *
 * @param constructor   Function to call to initialise each dynamic item to its default value when a client connects.
 *
 * @noreturn
 */
void ClientRecords_Initialise(ClientRecord_InitFunc constructor)
{
    if ( _bInitialised )
    {
        ThrowError("ClientRecords: Already initialised.");
    }

    _fwdConstructor = CreateForward(ET_Ignore, Param_CellByRef);
    AddToForward(_fwdConstructor, INVALID_HANDLE, constructor);

    // Just in case this was called during a game, make sure we initialise
    // for all currently connected clients.
    for ( int i = 1; i <= MaxClients; ++i )
    {
        if ( !IsClientConnected(i) )
        {
            continue;
        }

        ClientRecords_NotifyClientConnected(i);
    }

    _bInitialised = true;
}

/**
 * Destroys any existing client records.
 *
 * @noreturn
 */
void ClientRecords_Destroy()
{
    if ( _bInitialised )
    {
        return;
    }

    for ( int i = 0; i < MAXPLAYERS; ++i )
    {
        if ( _records[i].IsValid )
        {
            _records[i].Dispose();
            _records[i] = INVALID_DYNAMIC_OBJECT;
        }
    }

    CloseHandle(_fwdConstructor);
    _bInitialised = false;
}

void ClientRecords_NotifyClientConnected(int index)
{
    if ( !_bInitialised )
    {
        ThrowError("ClientRecords: Not initialised.");
    }

    if ( index < 1 || index >= MAXPLAYERS )
    {
        ThrowError("ClientRecords: Client index %d is out of range.", index);
    }

    if ( _records[index].IsValid )
    {
        _records[index].Dispose();
    }

    _records[index] = INVALID_DYNAMIC_OBJECT;

    Call_StartForward(_fwdConstructor);
    Call_PushCellRef(_records[index]);
    Call_Finish();

    if (_records[index] == INVALID_DYNAMIC_OBJECT )
    {
        ThrowError("ClientRecords: Record %d was not correctly initialised.", index);
    }
}

void ClientRecords_NotifyClientDisconnected(int index)
{
    if ( !_bInitialised )
    {
        ThrowError("ClientRecords: Not initialised.");
    }

    if ( index < 1 || index >= MAXPLAYERS )
    {
        ThrowError("ClientRecords: Client index %d is out of range.", index);
    }

    if ( _records[index].IsValid )
    {
        _records[index].Dispose();
        _records[index] = INVALID_DYNAMIC_OBJECT;
    }
}

stock Dynamic ClientRecords_GetRecord(int index)
{
    if ( !_bInitialised )
    {
        ThrowError("ClientRecords: Not initialised.");
    }

    if ( index < 1 || index >= MAXPLAYERS )
    {
        ThrowError("ClientRecords: Client index %d out of range.", index);
    }

    return _records[index];
}
