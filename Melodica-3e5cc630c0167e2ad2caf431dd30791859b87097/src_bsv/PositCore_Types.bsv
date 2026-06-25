package PositCore_Types;

import Posit_Numeric_Types :: *;
import Posit_User_Types :: *;
import FloatingPoint :: *;
import FShow :: *;

// Type definitions
typedef FloatingPoint#(11,52) FDouble;
typedef FloatingPoint#(8,23)  FSingle;

typedef union tagged {
   FDouble D;
   FSingle S;
   Bit #(PositWidth) P;
   } FloatU deriving(Bits,Eq, FShow);

endpackage : PositCore_Types
