{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

-- | System
module Haskus.System.System
   ( System(..)
   , defaultSystemInit
   , systemInit
   -- * Memory map
   , getProcessMemoryMap
   , memoryMapToBufferList
   , memoryMapToBuffer
   , MemoryMapEntry (..)
   , MappingType (..)
   , Perm (..)
   , Sharing (..)
   )
where

import qualified Haskus.Format.Binary.BitSet as BitSet
import Haskus.System.Linux.ErrorCode
import Haskus.System.Linux.Handle
import Haskus.System.Linux.FileSystem
import Haskus.System.Linux.FileSystem.Directory
import Haskus.System.Linux.FileSystem.ReadWrite
import Haskus.System.Linux.FileSystem.Mount
import Haskus.System.Linux.Process.MemoryMap

import Haskus.System.Sys
import Haskus.System.FileSystem
import Haskus.System.Devices
import Haskus.Utils.Flow
import Haskus.Utils.Types.List

import System.FilePath

import Prelude hiding (init,tail)

data System = System
   { systemProcFS        :: Handle            -- ^ procfs
   , systemDeviceManager :: DeviceManager     -- ^ Device manager
   }

-- | Initialize the system
defaultSystemInit :: Sys System
defaultSystemInit = systemInit "/system"

-- | Create a system object
--
-- Create the given @path@ if it doesn't exist and mount the system in it
systemInit :: FilePath -> Sys System
systemInit path = sysLogSequence "Initialize the system" $ do

   let 
      createDir p = sysCreateDirectory Nothing p (BitSet.fromList [PermUserRead,PermUserWrite,PermUserExecute]) False
      sysfsPath  = path </> "sys"
      procfsPath = path </> "proc"
      devicePath = path </> "dev"

   -- create root path (allowed to fail if it already exists)
   flowAssert "Create root directory" <| do
      createDir path `catchLiftLeft` \case
         EEXIST -> return ()
         e      -> failure e

   -- mount a tmpfs in root path
   flowAssert "Mount tmpfs" <| mountTmpFS sysMount path

   -- mount sysfs
   flowAssert "Create sysfs directory" <| createDir sysfsPath
   flowAssert "Mount sysfs" <| mountSysFS sysMount sysfsPath
   sysfd <- open Nothing sysfsPath BitSet.empty BitSet.empty
            |> flowAssert "open sysfs directory"

   -- mount procfs
   flowAssert "Create procfs directory" <| createDir procfsPath
   flowAssert "Mount procfs" <| mountProcFS sysMount procfsPath
   procfd <- open Nothing procfsPath BitSet.empty BitSet.empty
             |> flowAssert "open procfs directory"

   -- create device directory
   flowAssert "Create device directory" <| createDir devicePath
   flowAssert "Mount tmpfs" <| mountTmpFS sysMount devicePath
   devfd <- open Nothing devicePath BitSet.empty BitSet.empty
            |> flowAssert "open device directory"

   -- init device manager
   dm <- initDeviceManager sysfd devfd

   return $ System
      { systemProcFS        = procfd
      , systemDeviceManager = dm
      }

-- | Get process memory mappings
getProcessMemoryMap :: System -> FlowT (Union ReadErrors' OpenErrors) Sys [MemoryMapEntry]
getProcessMemoryMap sys =
   atomicReadBuffer (systemProcFS sys) "self/maps"
      ||> parseMemoryMap
