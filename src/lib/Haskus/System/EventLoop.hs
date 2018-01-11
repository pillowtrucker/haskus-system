{-# LANGUAGE LambdaCase #-}

-- | Event loop
module Haskus.System.EventLoop
   ( L
   , JobResponse (..)
   , mainLoop
   )
where

import Control.Concurrent.STM
import Haskus.Utils.Flow

-- Note [Event loop]
-- ~~~~~~~~~~~~~~~~~
--
-- The event loop is loosely based on the EFL's main loop (Enlightenment
-- Foundation Libraries).
--
--      /------->-------\
--      |               |
--      |               |
--      |         PreIdle jobs
--      |               |
--      |               |<-----------<-----------\  Execute idle jobs or sleep
--      |         Idle jobs (optional) or sleep  |  until an event occurs
--      ^               |------------>-----------/  
--      |               |
--      |         PostIdle jobs
--      |               |
--      |               |<-----------<-----------\
--      |         Event handlers                 |  Handle all queued events
--      |               |------------>-----------/
--      |               |
--      \-------<-------/
--
-- Events happen asynchronously but their handlers are executed sequentially
-- (i.e., without concurrency) in the event arrival order. We can use these
-- handlers to modify a state without having to deal with race conditions or
-- scheduling (fairness, etc.).
--
-- As a consequence, jobs executed in the event loop must be as short as
-- possible. They mustn't block or wait for events themselves. These jobs are
-- executed by a single thread (no concurrence): longer jobs must be explicitly
-- threaded.
--
-- 
--
-- Note [Rendering loop]
-- ~~~~~~~~~~~~~~~~~~~~~
--
-- The rendering loop manages the GUI. It is an event loop where events can be
-- generated by input devices, timers, animators, etc.
--
-- The GUI state is altered in event handlers (and maybe in some idle jobs).
--
-- The rendering itself is performed by a PredIdle job.


type L a = IO a

data JobResponse
   = JobRenew
   | JobRemove
   deriving (Show,Eq)

mainLoop :: TVar [L JobResponse] -> TQueue (L JobResponse) -> TVar [L JobResponse] -> TQueue (L ()) -> L ()
mainLoop enterers idlers exiters handlers = go

   where
      go = do
            execJobs enterers
            execIdle
            execJobs exiters
            execHandlers
            go

      execJobs jobList = do
         jobs <- atomically <| swapTVar jobList []
         res  <- sequence jobs
         -- filter jobs that shouldn't be executed anymore
         let jobs' = (jobs `zip` res)
                        |> filter ((== JobRenew) . snd)
                        |> fmap fst
         -- append the renewed jobs to the jobs that may have been added since
         -- we started executing jobs
         atomically <| modifyTVar' jobList (jobs'++)

      -- execute idle jobs or sleep
      execIdle = do
         r <- atomically <| do
            emptyHandler <- isEmptyTQueue handlers
            emptyIdler   <- isEmptyTQueue idlers
            case (emptyHandler, emptyIdler) of
               (True,True)  -> retry                -- sleep
               (True,False) -> tryReadTQueue idlers -- return idle job
               (False,_)    -> return Nothing
         case r of
            Nothing -> return ()
            Just j  -> do
               -- execute idle job
               j >>= \case
                  -- queue it again if necessary
                  JobRenew  -> atomically (writeTQueue idlers j)
                  JobRemove -> return ()
               -- loop
               execIdle
   
      -- execute handlers
      execHandlers = do
         mj <- atomically <| tryReadTQueue handlers
         case mj of
            Nothing -> return ()
            Just j  -> do
               j
               execHandlers
