//========================================================================
// fir_filter-misc
//========================================================================

// yummy macros 

`ifndef FIR_FILTER_MISC_V
`define FIR_FILTER_MISC_V

//------------------------------------------------------------------------
// FIR_FILTER_UNUSED
//------------------------------------------------------------------------

`define FIR_FILTER_UNUSED( signal_ )                                       \
  logic [$bits(signal_)-1:0] \signal_``_unused ;                        \
  assign \signal_``_unused = signal_;                                   \
  if (1)

//------------------------------------------------------------------------
// FIR_FILTER_UNDRIVEN
//------------------------------------------------------------------------

`define FIR_FILTER_UNDRIVEN( signal_ )                                     \
  assign signal_ = 'z;                                                  \
  if (1)

`endif /* FIR_FILTER_MISC_V */