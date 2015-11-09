module ViperVM.Arch.X86_64.Assembler.ModRM
   ( ModRM(..)
   , SIB(..)
   , Scale(..)
   , RMMode(..)
   , newModRM
   , rmField
   , regField
   , modField
   , modRMFields
   , rmMode
   , useDisplacement
   , useSIB
   , scaleField
   , indexField
   , baseField
   , rmRegMode
   )
where

import Data.Word
import Data.Bits

import ViperVM.Arch.X86_64.Assembler.Size

-- | ModRM byte
newtype ModRM = ModRM Word8 deriving (Show,Eq)

-- | SIB byte
newtype SIB = SIB Word8 deriving (Show,Eq)

-- | SIB scale factor
data Scale
   = Scale1 
   | Scale2 
   | Scale4 
   | Scale8 
   deriving (Show,Eq)

-- | Mode for the R/M field
data RMMode
   = RMRegister   -- ^ Direct register addressing
   | RMBaseIndex  -- ^ Memory addressing with only base/index register
   | RMSIB        -- ^ Memory addressing with SIB byte
   deriving (Show, Eq)

-- | Create a ModRM byte (check inputs)
newModRM :: Word8 -> Word8 -> Word8 -> ModRM
newModRM md rm reg
   | md  .&. 0xFC /= 0 = error "Invalid value for mod field (> 3)"
   | rm  .&. 0xF8 /= 0 = error "Invalid value for rm field (> 8)"
   | reg .&. 0xF8 /= 0 = error "Invalid value for reg field (> 8)"
   | otherwise = ModRM $ (md `shiftL` 6) .|. (reg `shiftL` 3) .|. rm


-- | Get r/m field in ModRM
rmField :: ModRM -> Word8
rmField (ModRM x) = x .&. 0x07

-- | Get reg field in ModRM
regField :: ModRM -> Word8
regField (ModRM x) = (x `shiftR` 3) .&. 0x07

-- | Get mod field in ModRM
modField :: ModRM -> Word8
modField (ModRM x) = (x `shiftR` 6) .&. 0x03

-- | Get the tree fields (mod,reg,rm)
modRMFields :: ModRM -> (Word8,Word8,Word8)
modRMFields m = (modField m, regField m, rmField m)

-- | Indicate R/M field mode
rmMode :: AddressSize -> ModRM -> RMMode
rmMode sz rm = case (sz, modField rm, rmField rm) of
   (_,3,_)          -> RMRegister
   (AddrSize16,_,_) -> RMBaseIndex
   (_,_,4)          -> RMSIB
   _                -> RMBaseIndex

-- | Indicate if the r/m field contains a register
rmRegMode :: ModRM -> Bool
rmRegMode rm = modField rm == 3

-- | Indicate if displacement bytes follow
useDisplacement :: AddressSize -> ModRM -> Maybe Size
useDisplacement sz modrm = case (sz,modField modrm,rmField modrm) of
   (AddrSize16, 0, 6) -> Just Size16
   (AddrSize16, 1, _) -> Just Size8
   (AddrSize16, 2, _) -> Just Size16
   (AddrSize16, _, _) -> Nothing

   -- 64 bit uses 32 bit addressing
   (_, 0, 5)          -> Just Size32
   (_, 1, _)          -> Just Size8
   (_, 2, _)          -> Just Size32
   _                  -> Nothing

-- | Indicate if a SIB byte follows
useSIB :: AddressSize -> ModRM -> Bool
useSIB sz modrm = case (sz,modField modrm,rmField modrm) of
   (AddrSize16, _, _) -> False -- no SIB in 16 bit addressing
   (_, 3, _)          -> False -- direct register addressing
   (_, _, 4)          -> True
   _                  -> False


-- | Get SIB scale field
scaleField :: SIB -> Scale
scaleField (SIB x) = case x `shiftR` 6 of
   0 -> Scale1
   1 -> Scale2
   2 -> Scale4
   3 -> Scale8
   _ -> error "Invalid scaling factor"

-- | Get SIB index field
indexField :: SIB -> Word8
indexField (SIB x) = (x `shiftR` 3) .&. 0x07

-- | Get SIB base field
baseField :: SIB -> Word8
baseField (SIB x) = x .&. 0x07

