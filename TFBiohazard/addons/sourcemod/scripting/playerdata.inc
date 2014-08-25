/**
 * userdata.inc - Defines player data arrays used by the plugin.
 * This is where things like player zombie status, rage level etc. are stored.
 * Players joining the game should be registered into these data arrays and should be removed when they leave.
 */

#include <sourcemod>

// To add a new property:
// 1. Add a new entry to the PlayerData enum.
// 2. Add a default in the appropriate place in ValueDefaults.
// 3. Add an accessor using IMPLEMENT_PROPERTY_ACCESSOR.
// 4. Add a mutator using IMPLEMENT_PROPERTY_MUTATOR.

// To add a new state flag:
// 1. Add a new entry to the UserStateFlags enum.

// Define this for checking pre-/post-conditions of functions.
// What did we learn? DON'T USE ASSERT STATEMENTS IN SP. They crash the server if they fail. :c Not ideal.
#define PD_DEBUG

#define TOTAL_SLOTS     MAXPLAYERS  // Total number of slots available for player data.
#define INVALID_USERID  0           // Invalid user ID.

enum PlayerData             // Properties held for each player.
{
    UserId,                 // User ID of the player whose info is stored at this index.
    StateFlags,             // Used to collect together flags such as zombie status and ubercharge readiness - see below.
    CurrentHealth,          // Current health a zombie has.
    MaxHealth,              // Max health a zombie can have.
    Float:RageLevel,        // Current rage level.
    JarateRef,              // Entity references for thrown Jarate jars.
    Float:TeleportLevel     // Current teleport charge for zombie Engineers.
}
#define TOTAL_PROPERTIES PlayerData     // Total number of slots required for stored player properties.

enum UserStateFlags                // Flags used with the StateFlags property.
{
    UsrZombie =        (1 << 0),   // Whether the given user is a zombie.
    UsrStartBoost =    (1 << 1),   // Whether the user gets a critboost for being a Patient Zero.
    UsrRaging =        (1 << 2),   // Whether the user is currently in rage.
    UsrSuperJump =     (1 << 3),   // Whether the user is in the air after having super jumped.
    UsrJumpPrevFrame = (1 << 4),   // The state of the user's jump buttons on the previous frame.
    UsrUberReady =     (1 << 5)    // The user has an Ubercharge ready.
}
#define TOTAL_FLAGS         UserStateFlags          // Total number of flags.

static ValueDefaults[PlayerData] =    // Holds the default values for each property.
{
    INVALID_USERID,         // No userid
    _:UsrZombie,            // Client starts as a zombie
    0,                      // 0 health
    0,                      // 0 max health
    0.0,                    // 0 rage level
    INVALID_ENT_REFERENCE,  // No jarate reference
    0.0                     // 0 teleport level
}

static PlayerDataArray[TOTAL_SLOTS][TOTAL_PROPERTIES];  // Main array that holds property data for players.
static NumOccupiedSlots = 0;                            // Number of slots that are occupied. They aren't contiguous (ie. the highest occupied slot number is probably higher than this).
                                                        // Note that this is only accurate if only the functions below are used for modifying the data.

// Note: I'm not exactly sure on what the SourceMod conventions are for this kind of thing, but
// the functions below that are prefixed with an underscore (_PD) are accessor functions which do not modify the array data.
// If the function is not prefixed with an underscore (PD) it does modify data.

// Accessors for properties.
#define IMPLEMENT_PROPERTY_ACCESSOR(%0,%1) stock %0:_PD_Get%1(slot) { return PlayerDataArray[slot][%1]; }
IMPLEMENT_PROPERTY_ACCESSOR(_,UserId)               // _PD_GetUserId(slot)
IMPLEMENT_PROPERTY_ACCESSOR(_,StateFlags)           // _PD_GetStateFlags(slot)
IMPLEMENT_PROPERTY_ACCESSOR(_,CurrentHealth)        // _PD_GetCurrentHealth(slot)
IMPLEMENT_PROPERTY_ACCESSOR(_,MaxHealth)            // _PD_GetMaxHealth(slot)
IMPLEMENT_PROPERTY_ACCESSOR(Float,RageLevel)        // Float:_PD_GetRageLevel(slot)
IMPLEMENT_PROPERTY_ACCESSOR(_,JarateRef)            // _PD_GetJarateRef(slot)
IMPLEMENT_PROPERTY_ACCESSOR(Float,TeleportLevel)    // Float:_PD_GetTeleportLevel(slot)

// Mutators for properties.
#define IMPLEMENT_PROPERTY_MUTATOR(%0,%1) stock PD_Set%1(slot, %0:value) { PlayerDataArray[slot][%1] = value; }
IMPLEMENT_PROPERTY_MUTATOR(_,UserId)                // PD_SetUserId(slot, value)
IMPLEMENT_PROPERTY_MUTATOR(_,StateFlags)            // PD_SetStateFlags(slot, value)
IMPLEMENT_PROPERTY_MUTATOR(_,CurrentHealth)         // PD_SetCurrentHealth(slot, value)
IMPLEMENT_PROPERTY_MUTATOR(_,MaxHealth)             // PD_SetMaxHealth(slot, value)
IMPLEMENT_PROPERTY_MUTATOR(Float,RageLevel)         // PD_SetRageLevel(slot, Float:value)
IMPLEMENT_PROPERTY_MUTATOR(_,JarateRef)             // PD_SetJarateRef(slot, value)
IMPLEMENT_PROPERTY_MUTATOR(Float,TeleportLevel)     // PD_SetTeleportLevel(slot, Float:value)

// Convenience functions.
#define IMPLEMENT_PROPERTY_INCREMENTER(%0,%1) stock PD_Increment%1(slot, %0:value) { PD_Set%1(slot, _PD_Get%1(slot) + value); }
#define IMPLEMENT_PROPERTY_DECREMENTER(%0,%1) stock PD_Decrement%1(slot, %0:value) { PD_Set%1(slot, _PD_Get%1(slot) - value); }
IMPLEMENT_PROPERTY_INCREMENTER(Float,RageLevel)     // PD_IncrementRageLevel(slot, Float:value)
IMPLEMENT_PROPERTY_DECREMENTER(Float,RageLevel)     // PD_DecrementRageLevel(slot, Float:value)
IMPLEMENT_PROPERTY_INCREMENTER(Float,TeleportLevel) // PD_IncrementTeleportLevel(slot, Float:value)
IMPLEMENT_PROPERTY_DECREMENTER(Float,TeleportLevel) // PD_DecrementTeleportLevel(slot, Float:value)

// Flag functions.

/// Returns whether the given state flag for the given slot is set.
/// True if the flag is set, false otherwise.
stock bool:_PD_IsFlagSet(slot, UserStateFlags:flag)
{
    return (_PD_GetStateFlags(slot) & _:flag) == _:flag;
}

/// Sets the value of the given flag in the given slot.
stock PD_SetFlag(slot, UserStateFlags:flag, bool:value)
{
    // Setting the flag:
    if ( value )
    {
        PlayerDataArray[slot][StateFlags] |= _:flag;
    }
    
    // Clearing the flag:
    else
    {
        PlayerDataArray[slot][StateFlags] &= ~(_:flag);
    }
}

/// Toggles the value of the given flag in the given slot.
stock PD_ToggleFlag(slot, UserStateFlags:flag)
{
    PlayerDataArray[slot][StateFlags] ^= _:flag;
}

// Convenience functions for adding clients by their indices rather than user IDs.

/// Adds the given client to the arrays and returns their slot. Properties are set to their default values.
/// Throws an error if no array slots are left, or if the client is invalid.
stock PD_RegisterClient(client)
{
#if defined PD_DEBUG
    //LogMessage("RegisterClient Pre: NOS = %d", NumOccupiedSlots);
    if ( NumOccupiedSlots < 0 ) ThrowError("PD_RegisterClient precondition failed!");
    new prevOccupied = NumOccupiedSlots;
#endif

    new userid = GetClientUserId(client);
    if ( userid < 1 ) ThrowError("Client %d is not valid.", client);
    
#if !defined PD_DEBUG
    return PD_AddUserId(userid);
#else
    new ret = PD_AddUserId(userid);
    //LogMessage("RegisterClient Post: NOS = %d", NumOccupiedSlots);
    if ( NumOccupiedSlots != prevOccupied + 1 ) ThrowError("PD_RegisterClient postcondition failed!");
    return ret;
#endif
}

/// Removes the given client from the arrays.
/// Throws an error if the client is invalid.
stock PD_UnregisterClient(client)
{
#if defined PD_DEBUG
    //LogMessage("UnregisterClient Pre: NOS = %d", NumOccupiedSlots);
    if ( NumOccupiedSlots < 0 ) ThrowError("PD_UnregisterClient precondition failed!");
    new prevOccupied = NumOccupiedSlots;
    new bool:clientExists = _PD_IsUserIdPresent(GetClientUserId(client));
#endif

    new userid = GetClientUserId(client);
    if ( userid < 1 ) ThrowError("Client %d is not valid.", client);
    
    PD_RemoveUserId(userid);
    
#if defined PD_DEBUG
    if ( clientExists )
    {
        //LogMessage("UnregisterClient Post (exists): NOS = %d", NumOccupiedSlots);
        if ( NumOccupiedSlots != prevOccupied - 1 ) ThrowError("PD_UnregisterClient postcondition 1 failed!");
    }
    else
    {
        //LogMessage("UnregisterClient Post (!exists): NOS = %d", NumOccupiedSlots);
        if ( NumOccupiedSlots != prevOccupied ) ThrowError("PD_UnregisterClient postcondition 2 failed!");
    }
#endif
}

/// Returns the slot index for the given client, or -1 if the client is not registered.
/// Throws an error if the client is invalid. If the throwError parameter is true,
/// also throws an error if the client is not present in the arrays (instead of the
/// function returning -1).
stock _PD_GetClientSlot(client, bool:throwError = true)
{
#if defined PD_DEBUG
    //LogMessage("GetClientSlot Pre: NOS = %d", NumOccupiedSlots);
    if ( NumOccupiedSlots < 0 ) ThrowError("_PD_GetClientSlot precondition failed!");
    new prevOccupied = NumOccupiedSlots;
#endif

    new userid = GetClientUserId(client);
    if ( userid < 1 ) ThrowError("Client %d is not valid.", client);
    
    new ret =  _PD_SlotForUserId(userid);
    if ( ret < 0 && throwError ) ThrowError("Client %d is not present in the data arrays.", client);    // Fail first!
    
#if defined PD_DEBUG
    //LogMessage("GetClientSlot Post: NOS = %d", NumOccupiedSlots);
    if ( NumOccupiedSlots != prevOccupied ) ThrowError("_PD_GetClientSlot postcondition failed!");
#endif

    return ret;
}

// If lots of flag setting is going on, it's recommended to cache the value from _PD_GetClientSlot()
// and then use _PD_SetFlag() etc. in order to avoid re-calculating the client slot each time.

/// Returns whether the state flag on the given client is true or false.
/// Throws an error if the client is invalid or if they do not exist in the arrays.
stock bool:_PD_IsClientFlagSet(client, UserStateFlags:flag)
{
    return _PD_IsFlagSet(_PD_GetClientSlot(client), flag);
}

/// Sets the value of the given client's flag.
/// Throws an error if the client is invalid or if they do not exist in the arrays.
stock PD_SetClientFlag(client, UserStateFlags:flag, bool:value)
{
    PD_SetFlag(_PD_GetClientSlot(client), flag, value);
}

/// Toggles the value of the given client's flag.
/// Throws an error if the client is invalid or if they do not exist in the arrays.
stock PD_ToggleClientFlag(client, UserStateFlag:flag)
{
    PD_ToggleFlag(_PD_GetClientSlot(client), flag);
}

/// Returns the number of slots currently in use.
stock _PD_SlotCount()
{
    return NumOccupiedSlots;
}

/// Returns the maximum number of players supported.
stock _PD_TotalSlots()
{
    return TOTAL_SLOTS;
}

/// Returns the total number of properties.
stock _PD_TotalProperties()
{
    return _:TOTAL_PROPERTIES;
}

/// Returns the total number of flags.
stock _PD_TotalFlags()
{
    return TOTAL_FLAGS;
}

/// Returns whether the arrays are currently empty.
stock _PD_IsEmpty()
{
    return (_PD_SlotCount() < 1);
}

/// Returns whether the arrays are currently full.
stock _PD_IsFull()
{
    return (_PD_SlotCount() >= _PD_TotalSlots());
}

/// Resets all the array indices to their default values.
/// If userids is true, also resets user IDs.
/// Updates NumOccupiedSlots if userids is true.
stock PD_Reset(bool:userids = false)
{
#if defined PD_DEBUG
    //LogMessage("Reset Pre: NOS = %d", NumOccupiedSlots);
    if ( NumOccupiedSlots < 0 ) ThrowError("PD_Reset precondition failed!");
    new prevOccupied = NumOccupiedSlots;
#endif

    for ( new i = 0; i < _PD_TotalSlots(); i++ )
    {
        PD_ResetToDefault(i, userids);
    }
    
    if ( userids ) NumOccupiedSlots = 0;
    
#if defined PD_DEBUG
    if ( userids )
    {
        //LogMessage("Reset Post (userids): NOS = %d", NumOccupiedSlots);
        if ( NumOccupiedSlots != 0 ) ThrowError("PD_Reset postcondition 1 failed!");
    }
    else
    {
        //LogMessage("Reset Post (!userids): NOS = %d", NumOccupiedSlots);
        if ( NumOccupiedSlots != prevOccupied ) ThrowError("PD_Reset postcondition 1 failed!");
    }
#endif
}

/// Resets the given player data slot to default values.
/// If userids is true, also resets the user ID.
/// Throws an error if the slot is invalid.
/// Modifies NumOccupiedSlots if userids is true.
stock PD_ResetToDefault(slot, bool:userids = false)
{
#if defined PD_DEBUG
    //LogMessage("ResetToDefault Pre: NOS = %d", NumOccupiedSlots);
    if ( NumOccupiedSlots < 0 ) ThrowError("PD_ResetToDefault precondition failed!");
    new prevOccupied = NumOccupiedSlots;
#endif

    new start = userids ? 0 : 1;
    new bool:useridWasOccupied = (_PD_GetUserId(slot) > 0);
    for ( new i = start; i < _PD_TotalProperties(); i++ )
    {
        PD_ResetPropertyToDefault(slot, PlayerData:i);
    }
    
    if ( userids && useridWasOccupied ) NumOccupiedSlots--;
    
#if defined PD_DEBUG
    if ( userids && useridWasOccupied )
    {
        //LogMessage("ResetToDefault Post (userids): NOS = %d", NumOccupiedSlots);
        if ( NumOccupiedSlots != prevOccupied - 1 ) ThrowError("PD_ResetToDefault postcondition 1 failed!");
    }
    else
    {
        //LogMessage("ResetToDefault Post (!userids): NOS = %d", NumOccupiedSlots);
        if ( NumOccupiedSlots != prevOccupied ) ThrowError("PD_ResetToDefault postcondition 2 failed!");
    }
#endif
}

/// Resets the given property to its default value.
/// Throws an error if the slot or property is invalid.
stock PD_ResetPropertyToDefault(slot, PlayerData:property)
{
    PlayerDataArray[slot][property] = _PD_DefaultPropertyValue(property);
}

/// Resets the given property on all slots to its default value.
/// Throws an errir if the property is invalid.
stock PD_ResetPropertyOnAll(PlayerData:property)
{
    for ( int i = 0; i < _PD_TotalSlots(); i++ )
    {
        PD_ResetPropertyToDefault(i, property);
    }
}

/// Returns the default value for a given property.
/// Throws an error if the property is invalid.
stock _PD_DefaultPropertyValue(PlayerData:property)
{
    return ValueDefaults[property];
}

/// Sets the given flag on all slots.
stock PD_SetFlagOnAll(UserStateFlags:flag, bool:value)
{
    for ( int i = 0; i < _PD_TotalSlots(); i++ )
    {
        PD_SetFlag(i, flag, value);
    }
}

// Raw functions.

/// Finds the first free slot in the array.
/// Returns the slot index, or -1 if there are no free slots.
static stock _PD_FindFreeSlot()
{
    for ( new i = 0; i < _PD_TotalSlots(); i++ )
    {
        if ( !_PD_IsSlotOccupied(i) ) return i;
    }
    
    return -1;
}

/// Adds a user ID to the list and sets all properties to their default value.
/// Returns the index at which the user ID was added, or throws an error if there were not enough slots left.
/// Updates NumOccupiedSlots.
static stock PD_AddUserId(userid)
{
    new slot = _PD_FindFreeSlot();
    if ( slot < 0 ) ThrowError("No free player data slots available to store user ID %d.", userid);
    
    // Clear previous properties.
    PD_ResetToDefault(slot, true);
    
    // Add the user ID and return the slot.
    PlayerDataArray[slot][UserId] = userid;
    NumOccupiedSlots++;
    return slot;
}

/// Returns the first slot number for the given user ID, or -1 if the ID is not found.
static stock _PD_SlotForUserId(userid)
{
    for ( new i = 0; i < _PD_TotalSlots(); i++ )
    {
        if ( PlayerDataArray[i][UserId] == userid ) return i;
    }
    
    return -1;
}

/// Removes the first instance of the given user ID.
/// Any properties that were associated with the user ID are left as they are.
/// Updates NumOccupiedSlots.
static stock PD_RemoveUserId(userid)
{
    new slot = _PD_SlotForUserId(userid);
    if ( slot < 0 ) return;
    
    PlayerDataArray[slot][UserId] = INVALID_USERID;
    NumOccupiedSlots--;
}

/// Returns whether a given user ID is present in the array.
/// Returns true if so, false otherwise.
static stock bool:_PD_IsUserIdPresent(userid)
{
    return (_PD_SlotForUserId(userid) >= 0);
}

/// Returns whether a valid user ID is present in the given slot.
/// Returns true if so, false otherwise.
static stock bool:_PD_IsSlotOccupied(slot)
{
    return (PlayerDataArray[slot][UserId] != INVALID_USERID);
}

/// Prints all occupied player data to the console if PD_DEBUG is defined.
/// Does nothing otherwise.
stock _PD_PrintAllData()
{
#if defined PD_DEBUG
    LogMessage("Recorded number of player entries: %d", NumOccupiedSlots);
    
    new actualCount = 0;
    for ( new i = 0; i < _PD_TotalSlots(); i++ )
    {
        // Only print if there is a valid userid.
        if ( _PD_GetUserId(i) < 1 ) continue;
        
        actualCount++;
        
        decl String:str[512];
        str[0] = '\0';
        
        for ( new j = 0; j < _PD_TotalProperties(); j++ )
        {
            decl String:buffer[64];
            Format(buffer, sizeof(buffer), (j == 0 ? "%f" : ", %f"), float(_:PlayerDataArray[i][j]));
            StrCat(str, sizeof(str), buffer)
        }
        
        LogMessage("Slot %d: %s", i, str);
    }
    
    LogMessage("Actual count of player entries: %d (accurate: %s)", actualCount, (actualCount == NumOccupiedSlots ? "yes" : "no"));
#endif
}

// Undef the defines - it's safer to provide accessor functions.
#undef TOTAL_PROPERTIES
#undef TOTAL_SLOTS
#undef TOTAL_FLAGS