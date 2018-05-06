#if defined _TF2UCC_CLIENTRECORD_INC
 #endinput
#endif
#define _TF2UCC_CLIENTRECORD_INC

#pragma semicolon 1
#pragma newdecls required

// For convenience: caches a member offset for efficiency.
// See dynamic-example.inc.
// %1: Function to call (eg. GetIntByOffset)
// %2: Name of member, as a string.
#define RETURN_VIA_OFFSET(%1, %2) \
    static int offset = INVALID_DYNAMIC_OFFSET; \
    if ( offset == INVALID_DYNAMIC_OFFSET ) \
    { \
        offset = this.GetMemberOffset(%2); \
        if ( offset == INVALID_DYNAMIC_OFFSET ) \
        { \
            ThrowError("Unable to get Dynamic offset for member '%s'.", (%2)); \
        } \
    } \
    return this.%1(offset);

methodmap UCC_ClientRecord < Dynamic
{
    public UCC_ClientRecord()
    {
        Dynamic obj = Dynamic(64, 0);

        obj.SetString("SampleString", "Dook", 32);

        return view_as<UCC_ClientRecord>(obj);
    }
}
