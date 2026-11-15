// Local compatibility shim for the Micron SDRAM behavioral model.
// The upstream test-defines.v is not reachable at the model path.
// The model only needs this file to exist; its own `ifdefs use
// MT48LC*, INIT_CLEAR_MEM_BANKS and PRELOAD_RAM, all defined (or not)
// inside the model itself. No macros are injected here.
