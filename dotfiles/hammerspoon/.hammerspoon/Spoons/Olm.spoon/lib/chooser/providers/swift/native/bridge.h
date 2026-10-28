// The one seam between Swift and Lua. Swift imports Lua's functions but not its function like
// macros, so every macro the module needs is wrapped here once as a static inline function, and
// the Swift side calls only these and plain lua_ functions. A new macro goes here, never into a
// hand written constant on the Swift side, since LUA_REGISTRYINDEX in particular depends on how
// this Lua was configured.
#import <Cocoa/Cocoa.h>
#import <LuaSkin/LuaSkin.h>

static inline int olm_registryIndex(void) { return LUA_REGISTRYINDEX; }
static inline int olm_noRef(void) { return LUA_NOREF; }
static inline void olm_pop(lua_State *L, int n) { lua_pop(L, n); }
static inline void olm_newTable(lua_State *L) { lua_newtable(L); }
static inline int olm_isFunction(lua_State *L, int idx) { return lua_isfunction(L, idx); }
static inline lua_Number olm_toNumber(lua_State *L, int idx) { return lua_tonumber(L, idx); }
static inline lua_Integer olm_toInteger(lua_State *L, int idx) { return lua_tointeger(L, idx); }

// Bytes pushed as one Lua string, embedded zeros kept, which is how an event's data travels.
static inline void olm_pushBytes(lua_State *L, const void *bytes, size_t n) {
  lua_pushlstring(L, (const char *)bytes, n);
}

static inline void olm_setFunction(lua_State *L, const char *name, lua_CFunction fn) {
  lua_pushcfunction(L, fn);
  lua_setfield(L, -2, name);
}
